# src/models/oracle.jl
#
# operational_oracle: a thin wrapper over `solve_welfare` exposing the centralized
# operational solve as `operational_oracle(feeder, pf, aggregators; λ₀, T, role,
# allow_export) -> (; cost, π, dadp, ctx)` where `cost` is the GLB-CVX optimum and `π` is
# the FRONTIER coupling dual (the dual of the nodal active balance at `feeder.root`).
# From the planning note the coupling variable is the interconnection flow (the aggregator
# net-import profile / frontier import) and `π_s` is the dual of the coupling constraint.
#
# This file adds no new solve path and does not modify `solve_welfare`: it re-uses the
# already-registered `:balance_p` dual (which `solve_welfare` gates behind
# `assert_solved!(...; dual = true)`), so `π` has the same provenance as the trusted price
# the operational layer already computes.

using JuMP

"""
    operational_oracle(feeder, pf::AbstractPowerFlow,
                       aggregators::AbstractVector{<:Aggregator};
                       λ₀, T::Int = 24,
                       role::Symbol = :follower, allow_export::Bool = false)
        -> (; cost, π, dadp, ctx)

Run the centralized GLB-CVX operational solve as an **oracle** the deferred planning
layer can query, returning a `NamedTuple`:

  - `cost`  — the welfare optimum (`objective_value`, thesis eq. 3.38);
  - `π`     — the **frontier coupling dual**: the dual of the active nodal balance
    `:balance_p` at `feeder.root` over the horizon (`_coupling_dual(ctx)`). This is the
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

# Extension slots

  - `role` (`:leader` | `:follower`) is the explicit Stackelberg role (the distributor is
    the `:leader`); it is validated but does not alter the solve.
  - The coupling dual `π` is always the dual of the free frontier import; there is no
    pinned-import variant here (see the planning oracle for the pinned form).
  - Meshed formulations plug in through the `pf::AbstractPowerFlow` argument: a future
    `MeshedFlow <: AbstractPowerFlow` would bypass the `assert_radial` invariant that
    `Feeder` construction enforces for radial networks.

Throws `ArgumentError` on an unknown `role` (project convention: fail loudly, never
`@assert`). All other guards (empty aggregators, `λ₀`/`T` shape, aggregator bus range)
are inherited unchanged from [`solve_welfare`](@ref).
"""
function operational_oracle(
    feeder::AbstractFeeder,
    pf::AbstractPowerFlow,
    aggregators::AbstractVector{<:Aggregator};
    λ₀,
    T::Int = 24,
    role::Symbol = :follower,
    allow_export::Bool = false,
)
    # Coupling role guard: the planning layer only knows :leader / :follower
    # (PSR: distributor = leader). Reject anything else up front so a typo can never
    # silently masquerade as a valid Stackelberg role once the planning layer lands.
    role in (:leader, :follower) || throw(
        ArgumentError(
            "operational_oracle role=$(repr(role)) is not a Stackelberg role; " *
            "expected :leader or :follower",
        ),
    )

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

    π = _coupling_dual(ctx)
    return (; cost, π, dadp, ctx)
end

"""
    _coupling_dual(ctx::ModelContext) -> Vector{Float64}

Recover the FRONTIER coupling dual `π` from a solved [`ModelContext`](@ref): the dual of
the active nodal balance `:balance_p` at the feeder root (`ctx.feeder.root`) over
the horizon. This is the interconnection price the deferred planning game equates across
the TSO↔DSO boundary (`λ_j ↔ π_s`, PSR note).

The frontier import is free, so `π` is the frontier-node DADP (the dual of the root
balance).

Reads the constraint handle registered by `solve_welfare` as `:balance_p` (a
`bus × time` array); requires a solve that passed `assert_solved!(...; dual = true)`.
"""
function _coupling_dual(ctx::ModelContext)
    feeder = _require_feeder(ctx)
    balance_p = ctx.constraints[:balance_p]        # bus × time ConstraintRef array (DADP)
    root = feeder.root

    # π = dual of the ACTIVE balance at the FRONTIER (root) over the horizon — the
    # interconnection coupling dual (distinct from the first-aggregator DADP).
    return dual.(balance_p[root, :])
end

export operational_oracle
