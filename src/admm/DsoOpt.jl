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
- `p_import` — the FREE-SIGN active frontier exchange `p_import[t]` at `feeder.root` (>0 buy,
  <0 sell surplus to the MEM at λ₀); priced export is the SOC-exactness enabler (PF-04).
- `load_nodes::Vector{Int}` — the non-root buses carrying an aggregator (== every non-root bus,
  guarded at build time); the `j` axis of `pag`.
- `T::Int` — the day-ahead horizon (thesis A1).
- `feeder` — the network the SOCP is built on.
- `ρ::Float64` — the FIXED ADMM penalty weight (the `0.5·ρ·pag²` quadratic term, built once).
- `λ₀::Vector{Float64}` — the MEM / wholesale price profile pricing `p_import`.
"""
struct DsoOpt{P,PI,F}
    model::Model
    ctx::ModelContext
    pag::P
    p_import::PI
    load_nodes::Vector{Int}
    T::Int
    feeder::F
    ρ::Float64
    λ₀::Vector{Float64}
end

"""
    build_dso_opt(feeder, aggregators, T::Int; ρ::Real, λ₀) -> DsoOpt

Build the whole-network `DSO-OPT` SOCP (thesis eq. 3.47) ONCE, reusing the validated
[`ConvexBranchFlow`](@ref) branch-flow builder verbatim and mirroring the centralized
[`solve_welfare`](@ref) frontier + balance-closure path, but closing each LOAD node with an
explicit coupling variable `pag_dso_j[t]` instead of an aggregator injection. Steps
(RESEARCH Pattern 4):

1. `model = Model(select_optimizer(SOCP()))` (INFRA-02 — never names a concrete solver);
   register the `RSOCtoNonConvexQuad` / `SOCtoNonConvexQuad` cross-solver bridges exactly as
   `solve_welfare`; wrap in a [`ModelContext`](@ref); stash `ctx.meta[:feeder]` / `[:T]` for
   the PF-04 gate.
2. `contribute!(ConvexBranchFlow(), ctx, feeder; T)` — VERBATIM reuse: builds `P, Q, v, v̂,
   l ≥ 0`, the rotated SOC cone (3.39), the true voltage drop (3.33), the exactness copy
   (3.43), the apparent-power limit (3.36, only where a real limit binds), accumulates
   `:Rp` (3.31) / `:Rq` (3.32), and stashes `ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)`.
3. Add the FREE-SIGN priced frontier `p_import[t]` (active, 3.31) and `q_import[t]` (reactive,
   3.32) at `feeder.root`, injected into `:Rp[root]` / `:Rq[root]` (mirrors
   `solve_welfare(...; allow_export = true)`). Priced export makes the objective strictly
   decreasing in the loss current `l`, keeping the SOC cone TIGHT (exact) under reverse flow
   (PF-04, RESEARCH Pitfall 3).
4. Close BOTH balances (mirroring the centralized SOCP so ADMM welfare + duals match on
   IEEE-13):
   - ACTIVE: for each load node `j` introduce `pag_dso[j,t]` and inject it into `:Rp[j]`;
     `p_import` already closes the root. Pin `:Rp[j,t] == 0` at all buses, register
     `:balance_p` (its dual is the DADP λ_j).
   - REACTIVE: inject each load node's CONSTANT reactive draw `−Pdc·tan(acos φ)` (thesis 3.23,
     inelastic per A3) into `:Rq[j]`, `q_import` supplies the root; pin `:Rq[j,t] == 0` at all
     buses, register `:balance_q`. This is a FIXED constant (no μ dual-ascent — reactive is
     not a consensus quantity).
5. `@objective(model, Min, Σ_t λ₀[t]·p_import[t] + 0.5·ρ·Σ_{j,t} pag_dso[j,t]²)` — the FIXED
   ρ-penalty built ONCE. Each ADMM iteration mutates only the LINEAR coefficient of each
   `pag_dso[j,t]` via `set_objective_coefficient` (see [`solve_dso!`](@ref)) — no rebuild
   (ADMM-03). λ_j is a plain `Float64` coefficient, NEVER a JuMP `Parameter` (an indefinite
   bilinear `λ·pag` the conic backend rejects; RESEARCH Pitfall 1).

Load nodes are the aggregator buses (the root carries no aggregator). Throws `ArgumentError`
on empty `aggregators`, a `λ₀` shape mismatch, an aggregator bus outside `1:length(feeder.buses)`,
an aggregator ON the root, or a non-root TRANSIT bus with no aggregator (its `:Rp`/`:Rq` would
be unclosed and the SOCP under-determined — the guard that keeps Phase-7 scale-up sound).
"""
function build_dso_opt(feeder, aggregators, T::Int; ρ::Real, λ₀)
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

    # TRANSIT-NODE GUARD (plan-checker WARNING-2): DSO-OPT currently requires EVERY non-root
    # bus to carry an aggregator, else that bus's :Rp/:Rq is closed with no coupling/draw term
    # (its net injection pinned to zero) — an under-determined transit node that silently
    # distorts the network state. Fail loudly; guards Phase-7 scale-up to true transit feeders.
    agg_buses = Set(agg.bus for agg in aggregators)
    for j in 1:N
        j == root && continue
        j in agg_buses || throw(
            ArgumentError(
                "non-root bus $j carries no aggregator; DSO-OPT requires every non-root bus " *
                "to be a load node (its :Rp/:Rq would be unclosed — plan-checker WARNING-2)",
            ),
        )
    end
    load_nodes = sort!(collect(agg_buses))

    # Per-load-node CONSTANT reactive draw q_ag_j[t] = Σ_{agg@j} −Pdc[t]·tan(acos φ) (thesis
    # 3.23). Summed over any aggregators sharing a bus; the temporal guard mirrors Aggregator.
    q_draw = Dict{Int,Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)
    for agg in aggregators
        length(agg.Pdc) >= T || throw(
            ArgumentError(
                "aggregator at bus $(agg.bus) has Pdc length $(length(agg.Pdc)) < T=$T " *
                "(thesis 3.22/3.23)",
            ),
        )
        tanφ = sqrt(1 - agg.φ^2) / agg.φ            # tan(arccos φ) (thesis 3.23)
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

    # (4b) REACTIVE load-node CONSTANT draw (thesis 3.23), injected into :Rq[j]. A fixed
    # parameter (no μ dual-ascent — reactive is not a consensus quantity).
    for j in load_nodes, t in 1:T
        add_to_residual!(ctx, :Rq, j, t, q_draw[j][t])
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
    @objective(
        model,
        Min,
        sum(λ₀[t] * p_import[t] for t in 1:T) +
        0.5 * ρ * sum(pag_dso[j, t]^2 for j in load_nodes, t in 1:T)
    )

    return DsoOpt(
        model,
        ctx,
        pag_dso,
        p_import,
        load_nodes,
        T,
        feeder,
        Float64(ρ),
        Vector{Float64}(λ₀),
    )
end

export DsoOpt, build_dso_opt
