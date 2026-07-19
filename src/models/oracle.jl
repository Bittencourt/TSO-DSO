# src/models/oracle.jl
#
# SEAM: operational_oracle + SEAM-01 extension-interface stubs (OPT-03 / SEAM-01).
# OWNER: plan 04-04.
#
# A thin, ADDITIVE wrapper over `solve_welfare` exposing the centralized operational
# solve as `operational_oracle(feeder, pf, aggregators; λ₀, T, z, role,
# objective_hook, horizon_state) -> (; cost, π, dadp, ctx)` where `cost` is the GLB-CVX
# optimum and `π` is the FRONTIER coupling dual (the dual of the nodal active balance at
# `feeder.root`). From the PSR planning note the coupling variable is the interconnection
# flow `z` (≈ the aggregator net-import profile `p_ag` / frontier import `p₀`) and `π_s`
# is the dual of the coupling constraint `z_x = z_y` — the z↔p_ag, λ_j↔π_s bridge the
# deferred Stackelberg-Nash planning layer (Phase 8/9) will consume WITHOUT a rewrite.
#
# This file adds NO new solve path and does NOT modify `solve_welfare`: it re-uses the
# already-registered `:balance_p` dual (which `solve_welfare` gates behind
# `assert_solved!(...; dual = true)`), so `π`'s provenance is exactly the trusted price
# the operational layer already computes (threat T-04-12).

using JuMP

"""
    operational_oracle(feeder, pf::AbstractPowerFlow,
                       aggregators::AbstractVector{<:Aggregator};
                       λ₀, T::Int = 24,
                       z = nothing, role::Symbol = :follower,
                       objective_hook::Function = identity, horizon_state = nothing,
                       allow_export::Bool = false)
        -> (; cost, π, dadp, ctx)

Run the centralized GLB-CVX operational solve as an **oracle** the deferred planning
layer can query, returning a `NamedTuple`:

- `cost`  — the welfare optimum (`objective_value`, thesis eq. 3.38);
- `π`     — the **frontier coupling dual**: the dual of the active nodal balance
  `:balance_p` at `feeder.root` over the horizon (`_coupling_dual(ctx, z)`). This is the
  interconnection price the planning game equates across the TSO↔DSO boundary
  (`λ_j ↔ π_s` in the PSR note); it is DISTINCT from `dadp`, which `solve_welfare`
  reports at the FIRST aggregator's bus;
- `dadp`  — the distribution price at the first aggregator's bus (passed through from
  `solve_welfare`), a length-`T` vector;
- `ctx`   — the solved [`ModelContext`](@ref), so a caller can read any other dual.

The solve routes to the right open-source solver by
`select_optimizer(problem_class(pf))` — a `ConvexBranchFlow` oracle solves as SOCP, a
`LinDistFlow`/DC oracle as QP — so this wrapper NEVER names a concrete solver (INFRA-02).

`allow_export` (default `false`) is passed straight through to [`solve_welfare`](@ref): with
`false` the frontier import is IMPORT-ONLY (`p_import ≥ 0`), with `true` it becomes a
free-sign net exchange that lets a high-PV feeder EXPORT its reverse-flow surplus to the
MEM. Priced export is the SOC-exactness enabler in the over-voltage / reverse-flow regime
(PF-04), so a congestion-driven over-voltage ground-truth solve (thesis Fig 4.4) requires
`allow_export = true` to stay both feasible and exact.

# SEAM-01 extension interfaces (INERT stubs — accepted, typed, and documented, but with
# NO Phase-4 behavior; each names the v2 requirement that makes it concrete). These exist
# so the planning layer is purely additive later; passing them here does not change the
# Phase-4 result (threat T-04-13: no silent partial behavior).

1. **Coupling-flow interface** (`z`, `role`, returned `π`) → PLAN-01/02 (Phase 8/9).
   `z` is the coupling-flow setpoint (frontier import target; `z↔p_ag`). `nothing` ⇒ the
   frontier import is FREE and `π` is the frontier-node DADP. A non-`nothing` `z` would pin
   the frontier import, but that pin is **not** wired into `solve_welfare` in Phase 4, so
   passing a non-`nothing` `z` FAILS LOUDLY (`_coupling_dual` throws an `ArgumentError`)
   rather than silently returning an UNPINNED proxy dual (WR-03; threat T-04-13: NO silent
   partial pinning — a wrong coupling price must never reach the planning game unflagged).
   `role` (`:leader` | `:follower`) is the explicit Stackelberg role (PSR: the distributor is the
   `:leader`); it is validated but does not alter the solve.
2. **Multi-scenario objective hook** (`objective_hook::Function = identity`) →
   STOCH-01/02 (v2). Reserved to compose the per-scenario welfare into the extensive-form
   objective. In Phase 4 it is accepted but NOT applied (`identity` is the single-scenario
   composition); wiring it into assembly is the stochastic-extension point.
3. **Rolling-horizon parameter** (`horizon_state = nothing`) → MPC-01/02 (v2). Reserved
   for the receding-horizon initial state (battery `soc0` / forecast). The concrete form
   is a JuMP `Parameter` re-settable without a rebuild:
   `@variable(m, s0 in Parameter(v)); set_parameter_value(s0, x)` (RESEARCH Pattern 6,
   verified). In Phase 4 it is accepted but ignored (no state is threaded).
4. **Meshed-formulation slot** → MESH-01 (v2). The `pf::AbstractPowerFlow` argument IS the
   seam: a future `MeshedFlow <: AbstractPowerFlow` plugs in here and would bypass the
   `assert_radial` invariant that `Feeder` construction enforces for the radial v1. No
   meshed formulation exists in Phase 4; the slot is the abstract-type argument itself.

Throws `ArgumentError` on an unknown `role` (project convention: fail loudly, never
`@assert`). All other guards (empty aggregators, `λ₀`/`T` shape, aggregator bus range)
are inherited unchanged from [`solve_welfare`](@ref).
"""
function operational_oracle(
    feeder,
    pf::AbstractPowerFlow,
    aggregators::AbstractVector{<:Aggregator};
    λ₀,
    T::Int = 24,
    z = nothing,
    role::Symbol = :follower,
    objective_hook::Function = identity,
    horizon_state = nothing,
    allow_export::Bool = false,
)
    # SEAM-01 coupling role guard: the planning layer only knows :leader / :follower
    # (PSR: distributor = leader). Reject anything else up front so a typo can never
    # silently masquerade as a valid Stackelberg role once the planning layer lands.
    role in (:leader, :follower) || throw(
        ArgumentError(
            "operational_oracle role=$(repr(role)) is not a Stackelberg role; " *
            "expected :leader or :follower (SEAM-01 / PSR planning note)",
        ),
    )

    # INERT SEAM-01 stubs (threat T-04-13): `objective_hook` and `horizon_state` are
    # accepted and typed but carry NO Phase-4 behavior — they are the STOCH / MPC v2
    # extension points documented above. Referencing them here keeps the seam explicit
    # without pretending it is implemented (no composition, no state threading).
    objective_hook === identity ||
        @debug "operational_oracle: non-identity objective_hook is a STOCH-01/02 (v2) " *
               "extension point and is NOT applied in Phase 4"
    horizon_state === nothing ||
        @debug "operational_oracle: horizon_state is an MPC-01/02 (v2) rolling-horizon " *
               "extension point and is IGNORED in Phase 4"

    # Route to the formulation's problem class (QP for DC/LinDistFlow, SOCP for the
    # ConvexBranchFlow) — never naming a concrete solver (INFRA-02). This is the ONLY
    # solve; `solve_welfare` already gates the dual read behind `assert_solved!`.
    ctx, cost, dadp = solve_welfare(
        feeder,
        pf,
        aggregators;
        T = T,
        λ₀ = λ₀,
        optimizer = select_optimizer(problem_class(pf)),
        allow_export = allow_export,
    )

    π = _coupling_dual(ctx, z)
    return (; cost, π, dadp, ctx)
end

"""
    _coupling_dual(ctx::ModelContext, z) -> Vector{Float64}

Recover the FRONTIER coupling dual `π` from a solved [`ModelContext`](@ref): the dual of
the active nodal balance `:balance_p` at the feeder root (`ctx.meta[:feeder].root`) over
the horizon. This is the interconnection price the deferred planning game equates across
the TSO↔DSO boundary (`λ_j ↔ π_s`, PSR note).

`z` is the SEAM-01 coupling-flow setpoint (`z↔p_ag`):

- `z === nothing` — the frontier import is FREE; `π` is the frontier-node DADP (the dual
  of the root balance). This is the Phase-4 behavior.
- `z !== nothing` — would pin the frontier import to `z`, but that pin is **not** wired into
  `solve_welfare` in Phase 4 (it is the PLAN-01/02 extension: add a coupling constraint
  `p_import == z` and return ITS dual). Rather than silently returning the UNPINNED frontier
  DADP as a proxy — which a planning caller would mistake for a genuine pinned coupling price
  — this THROWS an `ArgumentError` naming the extension point (WR-03; threat T-04-13: NO
  silent partial pinning). This mirrors the loud `role` guard in `operational_oracle`.

Reads the constraint handle registered by `solve_welfare` as `:balance_p` (a
`bus × time` array); requires a solve that passed `assert_solved!(...; dual = true)`.
"""
function _coupling_dual(ctx::ModelContext, z)
    feeder = ctx.meta[:feeder]
    balance_p = ctx.constraints[:balance_p]        # bus × time ConstraintRef array (DADP)
    root = feeder.root

    if z !== nothing
        # SEAM-01 z-pin (PLAN-01/02 extension point): pinning `p_import == z` and reading
        # that pin's dual is NOT implemented in Phase 4. Returning the UNPINNED frontier DADP
        # as a proxy behind a `@debug` (disabled by default) would hand a planning caller a
        # WRONG coupling price with zero visible signal (WR-03). Fail LOUDLY instead — a wrong
        # π fed into the Phase 8/9 Stackelberg loop is exactly the silent-wrong hazard this
        # module forbids (threat T-04-13: NO silent partial pinning), and this matches the
        # loud `role` guard in `operational_oracle`.
        throw(
            ArgumentError(
                "operational_oracle: z-pin (frontier import p_import == z) is a PLAN-01/02 " *
                "(Phase 8/9) extension point and is NOT wired into solve_welfare in Phase 4; " *
                "pass z = nothing (the coupling dual would otherwise be an UNPINNED proxy, " *
                "not a genuine pinned coupling price — SEAM-01 / PSR planning note, WR-03)",
            ),
        )
    end

    # π = dual of the ACTIVE balance at the FRONTIER (root) over the horizon — the
    # interconnection coupling dual (distinct from the first-aggregator DADP).
    return dual.(balance_p[root, :])
end

export operational_oracle
