# src/admm/DsoOpt.jl
#
# SEAM: DSO-OPT — the whole-network SOCP ADMM subproblem (ADMM-01).
# OWNER: plan 06-03 (Wave 2).
#
# WHAT IT IS (RESEARCH Pattern 4 / thesis eq. 3.47):
#   The network subproblem that REUSES `ConvexBranchFlow.contribute!` verbatim (P, Q, v, v̂,
#   l, cone, vdrop, cpydrop, smax, :Rp/:Rq) plus the priced FREE-SIGN frontier import — the
#   SOC-exactness enabler (PF-04). Block 2 of the 2-block split derived from the single
#   augmented Lagrangian (RESEARCH Pattern 1):
#
#       min_{P,Q,v,v̂,l,p_import,q_import,pag_dso}
#             Σ_t λ₀[t]·p_import[t]                            (frontier active cost)
#           − Σ_j Σ_t λ_j[t]·pag_dso_j[t]                     (coupling linear price)
#           + (ρ/2) Σ_j Σ_t ( pag_dso_j[t] − a_j[t] )²        (ρ-penalty)
#         s.t.  ConvexBranchFlow constraints (thesis 3.31–3.45)
#               :Rp[root] + p_import[t]  == 0                 (root, hard — no aggregator)
#               :Rp[j]    + pag_dso_j[t] == 0                 (load-node ACTIVE coupling var)
#               :Rq[root] + q_import[t]  == 0                 (free-sign reactive frontier)
#               :Rq[j]    + q_ag_j[t]    == 0                 (load-node CONSTANT reactive draw)
#
#   `pag_dso_j := −netflow_j` is an explicit coupling variable so the objective touches a
#   SINGLE variable per (j,t) — the key that makes `set_objective_coefficient` a one-call
#   update (ADMM-03). Solver via `select_optimizer(SOCP())` (INFRA-02); gated on
#   `assert_solved!(...; dual=true)` (INFRA-03). `assert_socp_exact!(dso.ctx)` runs on the
#   CONVERGED solve only (PF-04, RESEARCH Pitfall 3) — never mid-loop (early iterates are
#   legitimately inexact). Never model λ_j as a `Parameter` (Pitfall 1).
#
# REACTIVE CLOSURE (mirrors the centralized `solve_welfare` SOCP path): `ConvexBranchFlow`
# sets `reactive = true` (allocates :Rq at every bus), so the whole-network Q balance MUST be
# closed or the reactive flow is unconstrained/free and the ADMM welfare + duals cannot match
# the centralized SOCP on IEEE-13 (φ = 0.90). Each load node injects its CONSTANT reactive
# draw `−Pdc·tan(acos φ)` (thesis 3.23, inelastic per A3 — NOT a consensus quantity, so no μ
# dual-ascent) into :Rq; a free-sign `q_import` at the root supplies it; then :Rq is pinned to
# zero at ALL nodes and registered as :balance_q.
#
# REACT-01 (Phase 16, `reactive_consensus::Bool = false` kwarg, default OFF): when `true`, the
# per-load-node CONSTANT `q_draw[j][t]` injected above is instead promoted to a genuine JuMP
# coupling variable `qag_dso[j,t]` (stashed at `ctx.meta[:qag_dso]`), PINNED to the same fixed
# target via an explicit equality `qag_dso[j,t] == q_draw[j][t]` (registered `:qag_pin`) — this
# is a ONE-SHOT certified dual read, NOT a live μ dual-ascent loop (thesis A3: `AgrOpt.qag`/
# `q_draw` never moves, so no ρ-penalty is needed). The DEFAULT (`false`) path is
# BYTE-IDENTICAL to today (REACT-03); `:balance_q`'s own registration is UNCHANGED either way.

using JuMP

"""
    DsoOpt

The built-ONCE whole-network `DSO-OPT` SOCP subproblem (thesis eq. 3.47), block 2 of the
2-block ADMM. Holds the JuMP `model`, its [`ModelContext`](@ref) `ctx` (carrying the
`ConvexBranchFlow` `pf_vars`, the stashed `feeder`/`T`, and the registered `:balance_p` /
`:balance_q` duals), and the handles the ADMM loop mutates or reads between iterations:

# Fields

  - `model::Model` — the SOCP model, built once (`select_optimizer(SOCP())`); re-solved via
    `set_objective_coefficient` only (ADMM-03, never rebuilt).
  - `ctx::ModelContext` — the shared context; `ctx.meta[:pf_vars]` carries `:l` (the SOC cone is
    present), `ctx.meta[:feeder]`/`[:T]` feed the PF-04 exactness gate, and `:socp_maxgap` is
    stashed after a `check_exact` solve.
  - `pag` — the ACTIVE coupling container `pag[j,t]` (`j` over the load nodes, `t` over `1:T`),
    each pinned by `:Rp[j] + pag[j,t] == 0`. The SOLE variable per `(j,t)` whose linear
    objective coefficient the ADMM loop updates.
  - `qag` — the REACTIVE coupling container, mirroring `pag`'s shape `(load_nodes, T)`.
    `nothing` under `OFF`/`CERTIFIED` (no live reactive coupling block exists); under `LIVE`,
    the SAME `qag_dso` container stashed at `ctx.meta[:qag_dso]`, carrying its own
    `0.5·ρ_q·qag[j,t]²` quadratic objective penalty, mutated in place by [`set_rho_q!`](@ref).
  - `p_import` — the FREE-SIGN active frontier exchange `p_import[t]` at `feeder.root` (>0 buy,
    <0 sell surplus to the MEM at λ₀); priced export is the SOC-exactness enabler (PF-04).
  - `load_nodes::Vector{Int}` — the non-root buses carrying an aggregator (== every non-root bus,
    guarded at build time); the `j` axis of `pag`.
  - `T::Int` — the day-ahead horizon (thesis A1).
  - `feeder` — the network the SOCP is built on.
  - `ρ::Float64` — the INITIAL penalty ρ₀ captured at build time. NOTE (IN-01): under adaptive ρ the
    LIVE penalty lives ONLY in the model's quadratic objective coefficients (mutated by
    [`set_rho!`](@ref)); this immutable field is NEVER updated, so after the first ρ adaptation it
    holds ρ₀, not the current penalty. Do not read it as "the current ρ". Currently unused elsewhere.
  - `λ₀::Vector{Float64}` — the MEM / wholesale price profile pricing `p_import`.
"""
struct DsoOpt{P, Q, PI, F}
    model::Model
    ctx::ModelContext
    pag::P
    qag::Q
    p_import::PI
    load_nodes::Vector{Int}
    T::Int
    feeder::F
    ρ::Float64
    λ₀::Vector{Float64}
end

"""
    build_dso_opt(feeder, aggregators, T::Int; ρ::Real, λ₀, reactive_consensus = false, ρ_q::Real = ρ)
        -> DsoOpt

Build the whole-network `DSO-OPT` SOCP (thesis eq. 3.47) ONCE, reusing the validated
[`ConvexBranchFlow`](@ref) branch-flow builder verbatim and mirroring the centralized
[`solve_welfare`](@ref) frontier + balance-closure path, but closing each LOAD node with an
explicit coupling variable `pag_dso_j[t]` instead of an aggregator injection. Steps
(RESEARCH Pattern 4):

 1. `model = Model(select_optimizer(SOCP()))` (INFRA-02 — never names a concrete solver);
    register the `RSOCtoNonConvexQuad` / `SOCtoNonConvexQuad` cross-solver bridges exactly as
    `solve_welfare`; wrap in a [`ModelContext`](@ref); stash `ctx.meta[:feeder]` / `[:T]` for
    the PF-04 gate.
 2. `contribute!(ConvexBranchFlow(), ctx, feeder; T)` — VERBATIM reuse: builds `P, Q, v, v̂, l ≥ 0`, the rotated SOC cone (3.39), the true voltage drop (3.33), the exactness copy
    (3.43), the apparent-power limit (3.36, only where a real limit binds), accumulates
    `:Rp` (3.31) / `:Rq` (3.32), and stashes `ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)`.
 3. Add the FREE-SIGN priced frontier `p_import[t]` (active, 3.31) and `q_import[t]` (reactive,
    3.32) at `feeder.root`, injected into `:Rp[root]` / `:Rq[root]` (mirrors
    `solve_welfare(...; allow_export = true)`). Priced export makes the objective strictly
    decreasing in the loss current `l`, keeping the SOC cone TIGHT (exact) under reverse flow
    (PF-04, RESEARCH Pitfall 3).
 4. Close BOTH balances (mirroring the centralized SOCP so ADMM welfare + duals match on
    IEEE-13):
      + ACTIVE: for each load node `j` introduce `pag_dso[j,t]` and inject it into `:Rp[j]`;
        `p_import` already closes the root. Pin `:Rp[j,t] == 0` at all buses, register
        `:balance_p` (its dual is the DADP λ_j).
      + REACTIVE: inject each load node's CONSTANT reactive draw `−Pdc·tan(acos φ)` (thesis 3.23,
        inelastic per A3) into `:Rq[j]`, `q_import` supplies the root; pin `:Rq[j,t] == 0` at all
        buses, register `:balance_q`. This is a FIXED constant (no μ dual-ascent — reactive is
        not a consensus quantity). REACT-01 (`reactive_consensus = true`): promote this constant
        to a genuine JuMP coupling variable `qag_dso[j,t]`, PINNED to the same fixed target via
        the registered equality `:qag_pin` (`qag_dso[j,t] == q_draw[j][t]`) — still a one-shot
        certified dual read, NOT a live consensus ascent (Assumption A1/A3).
 5. `@objective(model, Min, Σ_t λ₀[t]·p_import[t] + 0.5·ρ·Σ_{j,t} pag_dso[j,t]²)` — the FIXED
    ρ-penalty built ONCE. Each ADMM iteration mutates only the LINEAR coefficient of each
    `pag_dso[j,t]` via `set_objective_coefficient` (see [`solve_dso!`](@ref)) — no rebuild
    (ADMM-03). λ_j is a plain `Float64` coefficient, NEVER a JuMP `Parameter` (an indefinite
    bilinear `λ·pag` the conic backend rejects; RESEARCH Pitfall 1).

Load nodes are the aggregator buses (the root carries no aggregator). A non-root bus WITHOUT an
aggregator is admitted as a physically-valid ZERO-INJECTION TRANSIT node (plan 07-03, RESEARCH
Pitfall 5): it carries no coupling variable and no reactive draw, and its `:Rp`/`:Rq` is pinned to
zero via `balance_p`/`balance_q` (closed at all `N` buses) — the correct zero-injection closure
that lets IEEE-123 (~37 junction buses) build. `load_nodes` (the ADMM coupling axis) is thereby
DECOUPLED from "all non-root buses" (the balance-closure axis); on the 2-bus / IEEE-13 fixtures
every non-root bus is a load node, so both axes coincide and the model is unchanged. Throws
`ArgumentError` on empty `aggregators`, a `λ₀` shape mismatch, an aggregator bus outside
`1:length(feeder.buses)`, an aggregator ON the root, or — WR-04, phase-19 review — a
`q_inject`-carrying device (`FourQuadBESS`) combined with `reactive_consensus != :live` (under
`OFF`/`CERTIFIED` the reactive closure is the inelastic `−Pdc·tanφ` draw alone, so the device's
reactive decision would be silently dropped from the network model — genuinely invalid inputs
still fail loud).

`reactive_consensus` (D-12, MESH-05): a 3-state mode normalized via
[`normalize_reactive_mode`](@ref), accepting a `Bool` (back-compat: `false → OFF`,
`true → CERTIFIED`), a `Symbol` (`:off`/`:certified`/`:live`), or a [`ReactiveMode`](@ref)
directly.

  - `OFF` (default, `false`): step 4's reactive injection is the byte-identical constant
    `q_draw[j][t]` (no `ctx.meta[:qag_dso]` key exists).
  - `CERTIFIED` (`true`): the constant is promoted to a genuine JuMP coupling variable
    `qag_dso[j,t]` (stashed at `ctx.meta[:qag_dso]`), pinned to the SAME fixed target via a
    registered equality `:qag_pin` (`qag_dso[j,t] == q_draw[j][t]`) — a one-shot certified dual
    read, NOT a live consensus ascent (thesis A3: `q_draw` never moves, so no new
    ρ-penalty/residual is needed).
  - `LIVE` (`:live`, NEW — MESH-05): `qag_dso[j,t]` is declared the SAME way as `CERTIFIED`
    (stashed at `ctx.meta[:qag_dso]`), but NO `:qag_pin` equality is registered — it is left as
    a genuinely open coupling variable, carrying its own `0.5·ρ_q·Σ qag_dso[j,t]²` quadratic
    penalty in the objective (see `ρ_q` below), for plan 19-07's outer μ-dual-ascent loop to
    drive.

`ρ_q::Real = ρ` (MESH-05): the FIXED quadratic penalty weight for the `LIVE` reactive coupling
block, mirroring `ρ`'s role for the active `pag_dso` block. Defaults to tracking `ρ` unless the
caller overrides it (plan 19-07 adapts it independently via [`set_rho_q!`](@ref)). Unused
(never referenced) under `OFF`/`CERTIFIED`.
"""
function build_dso_opt(
    feeder,
    aggregators,
    T::Int;
    ρ::Real,
    λ₀,
    reactive_consensus = false,
    ρ_q::Real = ρ,
)
    mode = normalize_reactive_mode(reactive_consensus)

    # Boundary guards (mirror solve_welfare): fail here, not deep in objective assembly.
    isempty(aggregators) &&
        throw(ArgumentError("build_dso_opt needs at least one aggregator"))
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))

    N = length(feeder.buses)
    root = feeder.root

    # Every aggregator must sit on a real, NON-root feeder bus.
    for (k, agg) in enumerate(aggregators)
        1 <= agg.bus <= N || throw(
            ArgumentError("aggregator[$k] bus=$(agg.bus) is outside feeder buses 1:$N"),
        )
        agg.bus == root && throw(
            ArgumentError(
                "aggregator[$k] sits on the root bus $root; the frontier root carries " *
                "no aggregator in DSO-OPT (thesis 3.47)",
            ),
        )
    end

    # WR-04 (phase-19 code review): under OFF/CERTIFIED this model's reactive closure target
    # `q_draw[j][t]` is composed from the INELASTIC `−Pdc·tanφ` term ALONE (thesis 3.23, below),
    # so a DEVICE-carried reactive decision (the widened D-09 `q_inject` contract — today only
    # `FourQuadBESS`) would be silently DROPPED from the network model, while the centralized
    # model's `Aggregator.contribute!` DOES write `−Pdc·tanφ + q_inject` into `:Rq` — a silent
    # semantic divergence. Under CERTIFIED that divergence would additionally be laundered
    # through the `:balance_q` no-slack certificate into a PUBLISHED reactive dual priced
    # against the wrong closure. The combination is new and undefined (pre-Phase-19 no device
    # carried `q_inject`), so it fails LOUD (project convention), directing the caller to
    # `:live` — the only mode whose coupling target (`qag_live == qag + q_inject`, AgrOpt.jl)
    # includes the device's reactive decision. The `dv isa FourQuadBESS` probe matches the sole
    # `q_inject`-implementing device today; a future `q_inject`-carrying device must extend
    # this guard (or the probe should move to a contract-level trait).
    if mode != LIVE
        for (k, agg) in enumerate(aggregators)
            if hasproperty(agg, :devices) && any(dv -> dv isa FourQuadBESS, agg.devices)
                throw(
                    ArgumentError(
                        "build_dso_opt: aggregator[$k] (bus $(agg.bus)) carries a " *
                        "FourQuadBESS — a device-level reactive decision (q_inject, D-09) — " *
                        "but reactive_consensus normalizes to $(mode), not LIVE. Under " *
                        "OFF/CERTIFIED the DSO reactive closure is the inelastic −Pdc·tanφ " *
                        "draw alone, so the device's q_inject would be silently dropped " *
                        "from the network model (and under CERTIFIED the published " *
                        "dual(:balance_q) would be priced against a closure that no longer " *
                        "matches the centralized model's). Pass reactive_consensus = :live " *
                        "(WR-04, phase-19 review).",
                    ),
                )
            end
        end
    end

    # TRANSIT-NODE RELAXATION (plan 07-03, RESEARCH Pitfall 5): DECOUPLE the ADMM coupling axis
    # (`load_nodes` = aggregator buses) from the balance-closure axis (all non-root buses). A
    # non-root bus WITHOUT an aggregator is a physically-valid ZERO-INJECTION TRANSIT node (a
    # junction / lateral tap): it carries NO coupling variable and NO reactive draw, so its
    # :Rp/:Rq residual is exactly the branch-flow residual, which `balance_p`/`balance_q` (closed
    # at ALL N buses below) pins to zero — the correct zero-injection closure, NOT an
    # under-determined node. Only genuinely invalid buses fail loud: an aggregator out of range or
    # ON the root (both guarded above). IEEE-123 has ~37 transit buses; the 2-bus / IEEE-13
    # fixtures have NONE (every non-root bus is a load node ⇒ transit_nodes == Int[]), so those
    # cases are byte-for-byte unaffected — same load_nodes, same model shape.
    agg_buses = Set(agg.bus for agg in aggregators)
    load_nodes = sort!(collect(agg_buses))
    transit_nodes = Int[j for j in 1:N if j != root && !(j in agg_buses)]

    # Per-load-node CONSTANT reactive draw q_ag_j[t] = Σ_{agg@j} −Pdc[t]·tan(acos φ) (thesis
    # 3.23). Summed over any aggregators sharing a bus; the temporal guard mirrors Aggregator.
    q_draw = Dict{Int, Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)
    for agg in aggregators
        length(agg.Pdc) >= T || throw(
            ArgumentError(
                "aggregator at bus $(agg.bus) has Pdc length $(length(agg.Pdc)) < T=$T " *
                "(thesis 3.22/3.23)",
            ),
        )
        tanφ = reactive_factor(agg.φ)               # tan(arccos φ) (thesis 3.23), single-sourced (IN-01)
        q = q_draw[agg.bus]
        for t in 1:T
            q[t] += -agg.Pdc[t] * tanφ
        end
    end

    model = Model(select_optimizer(SOCP()))          # SOCP factory; never names a solver

    # Cross-solver enablement (mirror solve_welfare): the SOC→nonconvex-quad bridges are
    # DORMANT for the primary conic path (the SOCP backend takes the cones natively) and only
    # activate when a smooth-NLP backend re-solves the SOCP as a cross-check. INFRA-02 intact.
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)

    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder
    ctx.meta[:T] = T

    # (2) VERBATIM ConvexBranchFlow reuse: P, Q, v, v̂, l, cone, vdrop, cpydrop, smax,
    # :Rp/:Rq, and the pf_vars stash (with :l) — the SOCP is NOT re-implemented here.
    contribute!(ConvexBranchFlow(), ctx, feeder; T = T)

    # (3) FREE-SIGN priced frontier at the root, injected BEFORE closing the residuals.
    @variable(model, p_import[t = 1:T])              # free-sign active frontier exchange
    @variable(model, q_import[t = 1:T])              # free-sign reactive frontier import
    for t in 1:T
        add_to_residual!(ctx, :Rp, root, t, p_import[t])
        add_to_residual!(ctx, :Rq, root, t, q_import[t])
    end
    ctx.meta[:p_import] = p_import
    ctx.meta[:q_import] = q_import

    # (4a) ACTIVE load-node coupling: one variable per (load node, t), injected into :Rp[j].
    @variable(model, pag_dso[j = load_nodes, t = 1:T])
    for j in load_nodes, t in 1:T
        add_to_residual!(ctx, :Rp, j, t, pag_dso[j, t])
    end

    # (4b) REACTIVE load-node closure (thesis 3.23), 3 EXPLICIT branches keyed on `mode`
    # (MESH-05, D-12) — never a shared branch with a conditional skip (T-19-06). A fixed
    # parameter under OFF/CERTIFIED (no μ dual-ascent — reactive is not a consensus quantity
    # there); a genuinely live coupling variable under LIVE.
    if mode == OFF
        # BYTE-IDENTICAL to pre-Phase-19 `reactive_consensus = false`: inject the CONSTANT
        # draw directly, no qag_dso variable, no ctx.meta[:qag_dso] key.
        for j in load_nodes, t in 1:T
            add_to_residual!(ctx, :Rq, j, t, q_draw[j][t])
        end
    elseif mode == CERTIFIED
        # BYTE-IDENTICAL to pre-Phase-19 `reactive_consensus = true` (REACT-01/REACT-03):
        # promote the constant to a genuine JuMP coupling variable `qag_dso[j,t]`, PINNED to
        # the SAME fixed target via the registered equality `:qag_pin` — a one-shot certified
        # dual read, NOT a live consensus ascent (Assumption A1/A3: q_draw never moves). The
        # `:qag_pin` registration is UNCONDITIONAL in this branch (T-19-07 — never skip it).
        @variable(model, qag_dso[j = load_nodes, t = 1:T])
        for j in load_nodes, t in 1:T
            add_to_residual!(ctx, :Rq, j, t, qag_dso[j, t])
        end
        @constraint(model, qag_pin[j = load_nodes, t = 1:T], qag_dso[j, t] == q_draw[j][t])
        register_constraint!(ctx, :qag_pin, qag_pin)
        ctx.meta[:qag_dso] = qag_dso
    elseif mode == LIVE
        # NEW (MESH-05): declare qag_dso the SAME way as CERTIFIED (same @variable call, same
        # :Rq injection, same ctx.meta[:qag_dso] stash), but register NO :qag_pin equality —
        # qag_dso stays a genuinely OPEN coupling variable, driven by plan 19-07's outer μ
        # dual-ascent loop and carrying its own ρ_q-scaled quadratic penalty (see (5) below).
        @variable(model, qag_dso[j = load_nodes, t = 1:T])
        for j in load_nodes, t in 1:T
            add_to_residual!(ctx, :Rq, j, t, qag_dso[j, t])
        end
        ctx.meta[:qag_dso] = qag_dso
    else
        error("unreachable: normalize_reactive_mode returned an unhandled ReactiveMode")
    end

    # (4b') TRANSIT-NODE ZERO INJECTION (RESEARCH Pitfall 5): each non-root, non-load bus is a
    # physical zero-injection junction — inject a pinned 0 into its :Rp/:Rq so `balance_p`/
    # `balance_q` (below, at all N buses) close it as a zero-injection node rather than leaving
    # it out of the coupling. A documentary no-op on feeders with no transit bus (2-bus/IEEE-13:
    # transit_nodes == Int[]), so their model is unchanged. NO coupling variable / reactive draw
    # is added here — transit buses have no aggregator, so they are absent from `load_nodes`,
    # `pag_dso`, and `q_draw`, keeping the ADMM coupling axis untouched.
    for j in transit_nodes, t in 1:T
        add_to_residual!(ctx, :Rp, j, t, 0.0)
        add_to_residual!(ctx, :Rq, j, t, 0.0)
    end

    # (4c) Close BOTH balances at ALL buses (root + every load node). Registered so the DADP
    # duals are recoverable (mirrors the centralized SOCP; ADMM welfare + duals then match).
    size(ctx.residuals[:Rp]) == (N, T) || error(
        "residual :Rp is $(size(ctx.residuals[:Rp])), expected ($N, $T) — an index escaped the feeder",
    )
    @constraint(model, balance_p[j = 1:N, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
    register_constraint!(ctx, :balance_p, balance_p)          # dual = λ_j (DADP)

    size(ctx.residuals[:Rq]) == (N, T) || error(
        "residual :Rq is $(size(ctx.residuals[:Rq])), expected ($N, $T) — an index escaped the feeder",
    )
    @constraint(model, balance_q[j = 1:N, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
    register_constraint!(ctx, :balance_q, balance_q)

    # (5) FIXED-penalty objective built ONCE (thesis 3.47). The pag_dso variables carry NO
    # linear term yet (default zero coupling price); solve_dso! sets each linear coefficient
    # per iteration via set_objective_coefficient — the ρ/2 quadratic below is never touched.
    # Under LIVE ONLY, an ADDITIONAL 0.5·ρ_q·Σ qag_dso[j,t]² term is folded into the SAME
    # accumulator BEFORE the single @objective call, so OFF/CERTIFIED literally never construct
    # or touch the ρ_q term (byte-identical built objective under those two modes).
    obj_expr =
        sum(λ₀[t] * p_import[t] for t in 1:T) +
        0.5 * ρ * sum(pag_dso[j, t]^2 for j in load_nodes, t in 1:T)
    if mode == LIVE
        obj_expr += 0.5 * ρ_q * sum(qag_dso[j, t]^2 for j in load_nodes, t in 1:T)
    end
    @objective(model, Min, obj_expr)

    return DsoOpt(
        model,
        ctx,
        pag_dso,
        mode == LIVE ? qag_dso : nothing,
        p_import,
        load_nodes,
        T,
        feeder,
        Float64(ρ),
        Vector{Float64}(λ₀),
    )
end

"""
    solve_dso!(dso::DsoOpt, λ, a, ρ::Real; check_exact::Bool = false, strict::Bool = true)
        -> (; pag_dso, p_import, exact_maxgap)

Re-solve the built-ONCE `DSO-OPT` (thesis eq. 3.47) for one ADMM iteration by mutating ONLY
the LINEAR objective coefficient of each coupling variable `pag_dso[j,t]` — no JuMP rebuild
(ADMM-03, RESEARCH Pattern 3 / Pitfall 6). For each load node `j` and time `t` it calls

    set_objective_coefficient(dso.model, dso.pag[j,t], −λ[j][t] − ρ·a[j][t])

(the FIXED `0.5·ρ·pag²` quadratic penalty from `build_dso_opt` is left UNTOUCHED), then gates
the solve on [`assert_solved!`](@ref)`(...; dual = true)` (INFRA-03) before any dual is read.

`λ` and `a` are indexable by the load-node bus id, each yielding a length-`T` price / target
profile (`λ[j][t]`, `a[j][t]`): `λ` is the current DADP estimate, `a` the AGR-OPT consensus
target. λ_j is a plain scalar coefficient, NEVER a JuMP `Parameter` (an indefinite bilinear
`λ·pag` the conic backend rejects; RESEARCH Pitfall 1).

`check_exact` is the CONVERGENCE flag. When `true` (only the final, converged solve — mid-loop
iterates are legitimately inexact and would throw, RESEARCH Pitfall 3) it runs the PF-04
exactness gate [`assert_socp_exact!`](@ref)`(dso.ctx; rtol = rtol_exact, atol = atol_exact)`,
stashing the returned `maxgap` under `dso.ctx.meta[:socp_maxgap]`; a STRICT (inexact) cone means
`l` is a fictitious over-current and the recovered prices are physically meaningless, so the
gate THROWS and prices are refused. When `false` the gate is NOT run (and `atol_exact`/
`rtol_exact` are inert — never consulted).

`atol_exact`/`rtol_exact` (2026-08-22 follow-up, quick task 260822-f0b) are an ADDITIVE override
seam onto [`assert_socp_exact!`](@ref)'s own `atol`/`rtol` kwargs. Their defaults (`1e-6`/`1e-4`)
are copied VERBATIM from `assert_socp_exact!`'s own current defaults
(`src/models/exactness.jl:78`), so every existing call site — including this function's own
mid-loop `check_exact = false` calls, which never reach the branch that consults them — is
byte-identical. This is a SEAM, not a default weakening (T-25-12, certificate-laundering): never
use it to make a point classify as exact that would otherwise be inexact under the project's own
default gate. A caller overriding it is asserting they have their OWN independently measured
noise floor for the tolerance they pass (mirrors how `scripts/benchmark_ieee8500.jl`'s
`IEEE8500_MV_EXACT_ATOL`/`IEEE8500_EXACT_ATOL` were derived).

Returns `(; pag_dso, p_import, exact_maxgap)` — the solved coupling values `value.(dso.pag)`,
the frontier exchange `value.(dso.p_import)`, and the certified cone residual (`nothing` until
a `check_exact = true` solve stashes it).
"""
function solve_dso!(
    dso::DsoOpt,
    λ,
    a,
    ρ::Real;
    check_exact::Bool = false,
    strict::Bool = true,
    atol_exact::Real = 1e-6,
    rtol_exact::Real = 1e-4,
)
    # ADMM-03 build-once re-solve: mutate ONLY the linear coefficient of each pag_dso[j,t]
    # (one scalar call per (j,t)); the ρ/2 quadratic penalty built in build_dso_opt is fixed.
    for j in dso.load_nodes, t in 1:dso.T
        set_objective_coefficient(dso.model, dso.pag[j, t], -λ[j][t] - ρ * a[j][t])
    end

    # INFRA-03: never trust a dual (price) before a trusted primal solve. `strict = true` (the
    # default, and ALWAYS used on the final/converged solve) requires a fully OPTIMAL, dual-
    # feasible point. `strict = false` is the MID-LOOP mode: the DSO subproblem's DUALS are never
    # read in ADMM (the transactive price is the outer multiplier λ, not `dual(balance_p)`), so an
    # ALMOST_OPTIMAL / NEARLY_FEASIBLE primal — the interior-point backend stopping just shy of its
    # centralized-grade gap under the ρ-penalty — is acceptable at an intermediate iterate (the
    # residual loop self-corrects; RESEARCH Pitfall 2/4). The converged solve is still STRICT.
    if strict
        assert_solved!(dso.model; dual = true)
    else
        assert_solved!(dso.model; dual = false, allow_almost = true)
    end

    # PF-04 EXACTNESS GATE — CONVERGENCE ONLY (RESEARCH Pitfall 3). Runs strictly AFTER
    # assert_solved! and refuses prices (throws) if the SOC cone is inexact; stashes maxgap.
    # Mid-loop iterates skip this — they are legitimately inexact and would throw spuriously.
    if check_exact
        dso.ctx.meta[:socp_maxgap] =
            assert_socp_exact!(dso.ctx; rtol = rtol_exact, atol = atol_exact)
    end

    return (;
        pag_dso = value.(dso.pag),
        p_import = value.(dso.p_import),
        exact_maxgap = get(dso.ctx.meta, :socp_maxgap, nothing),
    )
end

"""
    set_rho!(dso::DsoOpt, ρ::Real) -> DsoOpt

Mutate the FIXED quadratic penalty weight of the built-ONCE DSO-OPT in place when the adaptive-ρ
loop (07-04) changes ρ — WITHOUT rebuilding the JuMP model (ADMM-04 build-once preserved,
RESEARCH Pattern 1). DSO-OPT is `Min λ₀ᵀp_import + (ρ/2)·Σ_{j,t} pag_dso[j,t]²`, so the diagonal
quadratic coefficient of every `pag_dso[j,t]²` is `+0.5ρ` (Min objective — MIRROR of the AGR-OPT
`−0.5ρ`). Flatten the `pag` coupling container to a `Vector{VariableRef}` and set them all in one
BATCH call:

    set_objective_coefficient(dso.model, v, v, fill(0.5ρ, length(v)))

The 4-arg (quadratic) `set_objective_coefficient(model, x, x, c)` sets the coefficient of `x²`
to `c` directly (JuMP 1.30.1 absorbs the MOI `0.5·xᵀQx` canonicalization — VERIFIED, RESEARCH
Pattern 1 / objective.jl:629,712). The mutation is stored in the `CachingOptimizer` and re-applied
on the next `optimize!`, identical mechanism to the LINEAR `set_objective_coefficient` update
[`solve_dso!`](@ref) already runs each iteration — so `num_variables`/`num_constraints` are
INVARIANT (no rebuild) and a mutate-then-solve is EQUIVALENT to a fresh build at the new ρ.

CONTRACT for the caller (07-04): call `set_rho!` ONLY when ρ actually changed and in LOCKSTEP
with the linear coefficient update `−λ[j][t] − ρ·a[j][t]` (same ρ — Pitfall 1: penalty ρ and
ascent ρ must not diverge). Never model ρ (or λ) as a JuMP `Parameter`. Keep ρ strictly POSITIVE
(convexity guard, Pitfall 6: ρ > 0 ⇒ DSO stays convex-Min); the adaptive policy clamps
ρ ∈ `[ρ_min, ρ_max]`. Returns `dso`.
"""
function set_rho!(dso::DsoOpt, ρ::Real)
    # Flatten the pag_dso DenseAxisArray (j over load_nodes × t) to a flat Vector{VariableRef}
    # by indexing over its KNOWN axes — `collect` on a Vector-axis DenseAxisArray is unsupported.
    v = VariableRef[dso.pag[j, t] for j in dso.load_nodes for t in 1:dso.T]
    # Diagonal quadratic coeff of every pag_dso[j,t]² set to +0.5ρ (Min objective, penalty added).
    # BATCH form — one MOI modification list; no rebuild (RESEARCH Pattern 1).
    set_objective_coefficient(dso.model, v, v, fill(0.5 * ρ, length(v)))
    return dso
end

"""
    set_rho_q!(dso::DsoOpt, ρ_q::Real) -> DsoOpt

Mutate the FIXED quadratic penalty weight of the built-ONCE `LIVE` reactive coupling block in
place — the exact `set_rho!` PEER for the reactive `qag` block (MESH-05, plan 19-07's outer
μ-dual-ascent loop adapts `ρ_q` independently of `ρ`). DSO-OPT under `LIVE` carries an
ADDITIONAL `Min ... + (ρ_q/2)·Σ_{j,t} qag[j,t]²` term (see `build_dso_opt`'s objective
assembly), so the diagonal quadratic coefficient of every `qag[j,t]²` is `+0.5ρ_q`. Flatten the
`qag` coupling container to a `Vector{VariableRef}` and set them all in one BATCH call, mirroring
`set_rho!`'s exact shape:

    set_objective_coefficient(dso.model, v, v, fill(0.5ρ_q, length(v)))

`num_variables`/`num_constraints` are INVARIANT (no rebuild) — a mutate-then-solve is EQUIVALENT
to a fresh build at the new `ρ_q` (identical mechanism to `set_rho!`).

Throws `ArgumentError` if `dso.qag === nothing` — calling this on an `OFF`/`CERTIFIED`-built
`DsoOpt` (no live reactive coupling block exists) is a caller error, fail loud rather than
silently no-op. Returns `dso`.
"""
function set_rho_q!(dso::DsoOpt, ρ_q::Real)
    dso.qag !== nothing || throw(
        ArgumentError(
            "set_rho_q!: this DsoOpt was built without a live reactive coupling block " *
            "(reactive_consensus != :live); nothing to update",
        ),
    )
    # Flatten the qag_dso DenseAxisArray (j over load_nodes × t) to a flat Vector{VariableRef},
    # mirroring set_rho!'s exact flatten-then-one-call shape.
    v = VariableRef[dso.qag[j, t] for j in dso.load_nodes for t in 1:dso.T]
    # Diagonal quadratic coeff of every qag[j,t]² set to +0.5ρ_q (Min objective, penalty added).
    # BATCH form — one MOI modification list; no rebuild (RESEARCH Pattern 1).
    set_objective_coefficient(dso.model, v, v, fill(0.5 * ρ_q, length(v)))
    return dso
end

export DsoOpt, build_dso_opt, solve_dso!, set_rho!, set_rho_q!
