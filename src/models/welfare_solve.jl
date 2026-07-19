# src/models/welfare_solve.jl
#
# SEAM: GLB-CVX centralized social-welfare solve (OPT-01).
# OWNER: plan 03-05.
#
# Generalizes `linear_solve.jl` to a multi-aggregator centralized welfare
# maximization over the Phase-2 LinDistFlow model at horizon T=24 (thesis eq.
# 3.38). Assembles each aggregator's :Rp/:Rq injections and utility, adds a
# non-negative priced frontier import p_import[t] and -- only when the formulation
# provides a reactive channel (WR-03) -- a FREE-SIGN reactive frontier q_import[t] at
# feeder.root (without it, pinning :Rq at every bus with reactive load present is
# infeasible; a DC active-only run has no reactive channel, so aggregator reactive
# terms are left unclosed), closes the nodal-balance residuals to zero, and
# maximizes welfare = sum(aggregator utility) - sum_t lambda0[t]*p_import[t]
# as a convex QP via `select_optimizer(QP())` (no model names a concrete solver).
# Gated on OPTIMAL via `assert_solved!`, then runs the mandatory post-solve battery
# complementarity check (p_ch*p_dch < tau, App. C). Because every device utility is
# concave and the LinDistFlow constraints are affine, the local optimum is global.

using JuMP

"""
    solve_welfare(feeder, pf::AbstractPowerFlow, aggregators::AbstractVector{<:Aggregator};
                  T::Int = 24, λ₀, optimizer = select_optimizer(problem_class(pf)),
                  allow_local::Bool = false, τ::Real = 1e-3, rtol_exact::Real = 1e-4,
                  allow_export::Bool = false)
        -> (ctx::ModelContext, objective::Float64, dadp::Vector{Float64})

Build and solve the GLB-CVX centralized social-welfare problem (thesis eq. 3.38) over
`feeder`, a swappable `AbstractPowerFlow`, and a vector of [`Aggregator`](@ref)s. This
GENERALIZES [`solve_linear`](@ref) from a single device list to multiple aggregators at
horizon `T` (the rung-1 `solve_linear` stays untouched as a regression). It:

1. builds `Model(optimizer)` — `optimizer` defaults to `select_optimizer(problem_class(pf))`,
   so the solver factory is chosen BY FORMULATION TRAIT (RESEARCH Pattern 5): DC/LinDistFlow
   route to the `QP()` backend, while `ConvexBranchFlow` routes to the tight-gap `SOCP()`
   backend (`tol_gap_abs/rel = 1e-8`, which the DADP accuracy and exactness check depend on).
   Both are Clarabel, and this file NEVER names a concrete solver (INFRA-02, no
   `if formulation ==` branch). Cross-solver checks pass a different factory (e.g.
   `select_optimizer(NLP())`) plus `allow_local = true`;
2. wraps it in a [`ModelContext`](@ref); stashes `feeder`/`T`;
3. lets the power-flow formulation `contribute!` its branch/voltage terms into
   `ctx.residuals[:Rp]` (and `:Rq` for `LinDistFlow`) and each aggregator `contribute!`
   its net active/reactive injections into `:Rp`/`:Rq` plus its summed utility into
   `ctx.meta[:objective]`;
4. injects a priced active frontier exchange `p_import[t]` at `feeder.root` (stashed
   under `ctx.meta[:p_import]`). By default it is IMPORT-ONLY (`p_import ≥ 0`, buy from the
   MEM). With `allow_export = true` it is FREE-SIGN (`>0` buy, `<0` sell surplus to the MEM
   at the same λ₀) — the physically-complete transmission frontier that lets a high-PV feeder
   export its reverse-flow surplus. Priced export is the SOC-EXACTNESS enabler (PF-04): it
   makes the welfare objective strictly decreasing in the loss current `l` (every unit of `l`
   costs export revenue), so the SOC cone `l·v ≥ P²+Q²` stays TIGHT in the over-voltage /
   reverse-flow regime instead of going slack (inexact). Import-only leaves losses-vs-
   curtailment welfare-equivalent, breaking that condition. It also adds — ONLY when the
   formulation provides a reactive channel
   (WR-03) — a FREE-SIGN reactive frontier import `q_import[t]` (no lower bound, stashed
   under `ctx.meta[:q_import]`), BOTH BEFORE closing the residuals. Without the free-sign
   `q_import`, pinning `:Rq` at every bus with a reactive load present is INFEASIBLE (or
   silently zeroes the reactive draw) — the MEM/substation supplies reactive power at the
   frontier (RESEARCH Pitfall 2);
5. closes `:Rp` always and `:Rq` only when the POWER-FLOW FORMULATION provides a reactive
   channel — captured as `reactive = haskey(ctx.residuals, :Rq)` RIGHT AFTER the
   formulation contributes and BEFORE any aggregator writes (WR-03). This keys off the
   formulation's capability, not a formulation flag: LinDistFlow closes `:Rq`; a DC
   (active-only) run leaves any aggregator reactive terms unclosed. Both closures are
   registered (`:balance_p` / `:balance_q`) so their duals are recoverable;
6. maximizes welfare `Σ aggregator utility − λ₀ᵀ·p_import` (thesis eq. 3.38);
7. solves through [`assert_solved!`](@ref)`(...; dual = true, allow_local)` — the OPTIMAL
   (or, for a nonconvex cross-check, LOCALLY_SOLVED) gate before any dual is trusted;
8. runs the PF-04 EXACTNESS GATE [`assert_socp_exact!`](@ref)`(ctx; rtol = rtol_exact)` — but
   ONLY when the formulation stashed a squared-current `:l` in `ctx.meta[:pf_vars]` (i.e. a SOCP
   cone is present). It sits strictly AFTER `assert_solved!` and BEFORE any `dual()` read, so
   physically-meaningless duals from a STRICT (inexact) relaxation are REFUSED (thrown) rather
   than returned (threats T-04-01/T-04-03). `maxgap` is stashed under `ctx.meta[:socp_maxgap]`.
   DC/LinDistFlow stash no `:l` and skip this untouched. `rtol_exact` (default 1e-4) is a
   RELATIVE, base-free cone-slack tolerance (WR-01) and is a DISTINCT quantity from the
   battery-check `τ` — never conflated (Pitfall 2);
9. runs the MANDATORY App. C post-solve battery complementarity check: for every battery
   stashed under `ctx.meta[:agg_device_vars]`, asserts `value(p_ch[t])·value(p_dch[t]) < τ`
   for all `t`, throwing loudly on violation (RESEARCH Pitfall 1, threat T-03-13). The
   tolerance `τ` is PROBLEM-CLASS-AWARE by default: `1e-6` on the QP path (DC/LinDistFlow,
   whose Clarabel-QP primal is tight) but `1e-4` on the SOCP path (`ConvexBranchFlow`), where
   the interior-point conic solve reports each variable only to ~`1e-6`…`1e-8`, so a product
   of two ~`1e-2` quantities carries a looser residual. This keys off `problem_class(pf)` (a
   trait, not an `if formulation ==`) and never loosens the QP path.

Returns `(ctx, objective_value, dadp)` where `dadp = dual.(balance_p[bus, :])` at the
FIRST aggregator's bus (the distribution price / DADP over the horizon).

Throws `ArgumentError` on empty `aggregators`, `length(λ₀) != T`, or an aggregator bus
outside `1:length(feeder.buses)` — the boundary guards that keep a shape mismatch from
becoming a cryptic deep crash or a silently-wrong optimum (RESEARCH Pitfall 4).
"""
function solve_welfare(
    feeder,
    pf::AbstractPowerFlow,
    aggregators::AbstractVector{<:Aggregator};
    T::Int = 24,
    λ₀,
    optimizer = select_optimizer(problem_class(pf)),
    allow_local::Bool = false,
    τ::Real = (problem_class(pf) isa SOCP ? 1e-3 : 1e-6),
    rtol_exact::Real = 1e-4,
    allow_export::Bool = false,
)
    # Boundary guards (RESEARCH Pitfall 4): empty aggregators ⇒ no priced load / no
    # objective; a λ₀ shape mismatch ⇒ BoundsError deep in objective assembly. Fail here.
    isempty(aggregators) &&
        throw(ArgumentError("solve_welfare needs at least one aggregator"))
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))

    model = Model(optimizer)                 # QP() factory by default; never names a solver

    # Cross-solver enablement (RESEARCH Pitfall 4): register the OPT-IN
    # RotatedSecondOrderCone / SecondOrderCone → nonconvex-quadratic bridges so a smooth-NLP
    # backend (Ipopt, via `select_optimizer(NLP())` + `allow_local = true`) can INDEPENDENTLY
    # re-solve the SOCP ConvexBranchFlow model as a cross-check. These bridges are DORMANT for
    # the primary Clarabel path (Clarabel supports both cone sets natively, so the
    # LazyBridgeOptimizer never reformulates) — they only activate when the chosen backend
    # cannot take the cone directly, reformulating `l·v ≥ P²+Q²` into the smooth quadratic
    # constraint Ipopt handles. They are no-ops for the cone-free DC/LinDistFlow (QP) paths.
    # Registered here (not in the factory) because bridges attach to the JuMP `Model`, not the
    # optimizer attributes, and this file is the sole model builder (INFRA-02 preserved: still
    # no concrete solver named).
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)

    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder
    ctx.meta[:T] = T

    Np = length(feeder.buses)

    # Every aggregator must sit on a real feeder bus, else its injection grows :Rp beyond
    # the balance-closure range and vanishes from the network balance (welfare from
    # nowhere) — fail loudly, mirroring solve_linear's CR-01 device guard.
    for (k, agg) in enumerate(aggregators)
        1 <= agg.bus <= Np || throw(
            ArgumentError(
                "aggregator[$k] bus=$(agg.bus) is outside feeder buses 1:$Np",
            ),
        )
    end

    # Formulation: branch/voltage terms into :Rp (and :Rq for LinDistFlow).
    contribute!(pf, ctx, feeder; T = T)

    # WR-03: whether a REACTIVE channel exists is decided by the POWER-FLOW FORMULATION,
    # not by the aggregators. Capture it HERE — right after the formulation contributes but
    # BEFORE any aggregator writes — so it reflects the formulation's capability alone:
    # LinDistFlow allocates :Rq (reactive modeled); DCPowerFlow is active-only and never
    # does. Keying off this (rather than off `haskey(ctx.residuals, :Rq)` after the
    # aggregators have run) is what makes the DC↔LinDistFlow interchange sound: an
    # aggregator ALWAYS emits its reactive term, but on a DC network there is no reactive
    # channel to balance it, so those terms are simply not assembled (a DC study models
    # active power only). Without this, a DCPowerFlow + reactive-aggregator run pinned :Rq
    # to zero at every non-root load bus and was INFEASIBLE. This is a data-driven seam —
    # no `if formulation ==` branching.
    reactive = haskey(ctx.residuals, :Rq)

    # Aggregators: net active/reactive injections into :Rp/:Rq + summed utility into
    # ctx.meta[:objective]. Each aggregator is the sole :Rp/:Rq writer at its bus. (On a DC
    # run the aggregators still write :Rq, but it is left unclosed below — active-only.)
    for agg in aggregators
        contribute!(agg, ctx; T = T)
    end

    # Frontier imports at the root, injected BEFORE closing the residuals. p_import is
    # priced and non-negative (active draw from the MEM). q_import is FREE-SIGN so the
    # reactive load closes feasibly instead of forcing Q ≡ 0 — added ONLY when the
    # formulation provides a reactive channel (WR-03; a DC run has no reactive balance).
    # Active frontier exchange at the root, priced at λ₀. By default it is IMPORT-ONLY
    # (`p_import[t] ≥ 0`, buy from the MEM) — the rung-0…rung-2 behavior. With
    # `allow_export = true` it becomes a FREE-SIGN net exchange (`>0` buy, `<0` sell surplus
    # to the MEM at the same λ₀) — a physically-complete transmission frontier that lets a
    # high-PV feeder EXPORT its reverse-flow surplus instead of dissipating it. That export
    # sink is the SOC-exactness enabler (PF-04): with import-only, shedding surplus via line
    # losses (`−r·l`) versus PV curtailment is welfare-equivalent, so the objective is NOT
    # strictly decreasing in the loss current `l` and the SOC cone can go slack (inexact) in
    # the over-voltage / reverse-flow regime. Priced export makes every unit of `l` cost real
    # export revenue, restoring the strict loss-penalization the exactness certificate needs
    # (the `l·v = P²+Q²` cone becomes tight — thesis over-voltage result is exact). The `−λ₀ᵀ
    # p_import` welfare term below is sign-correct for BOTH cases (buy costs, sell earns).
    if allow_export
        @variable(model, p_import[t = 1:T])          # free-sign net frontier exchange
    else
        @variable(model, p_import[t = 1:T] >= 0)     # import-only priced frontier
    end
    for t in 1:T
        add_to_residual!(ctx, :Rp, feeder.root, t, p_import[t])
    end
    ctx.meta[:p_import] = p_import
    if reactive
        @variable(model, q_import[t = 1:T])          # free-sign reactive frontier import
        for t in 1:T
            add_to_residual!(ctx, :Rq, feeder.root, t, q_import[t])
        end
        ctx.meta[:q_import] = q_import
    end

    # Close the residuals. :Rp is always populated and always closed. :Rq is closed ONLY
    # when the FORMULATION provides a reactive channel (`reactive`) — DATA-DRIVEN on the
    # formulation's capability, never a formulation flag. On a DC run any aggregator :Rq
    # terms remain unclosed (reactive is out of scope for an active-only model).
    size(ctx.residuals[:Rp]) == (Np, T) || error(
        "residual :Rp is $(size(ctx.residuals[:Rp])), expected ($Np, $T) — an index escaped the feeder",
    )
    @constraint(model, balance_p[j = 1:Np, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
    register_constraint!(ctx, :balance_p, balance_p)          # dual = λ_j (DADP)
    if reactive
        size(ctx.residuals[:Rq]) == (Np, T) || error(
            "residual :Rq is $(size(ctx.residuals[:Rq])), expected ($Np, $T) — an index escaped the feeder",
        )
        @constraint(model, balance_q[j = 1:Np, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
        register_constraint!(ctx, :balance_q, balance_q)
    end

    # GLB-CVX welfare (thesis eq. 3.38): Σ aggregator utility − λ₀ᵀ·p_import.
    welfare = ctx.meta[:objective] - sum(λ₀[t] * p_import[t] for t in 1:T)
    @objective(model, Max, welfare)

    # OPTIMAL gate: never read a dual (price) before a trusted solve (threat T-03-14).
    assert_solved!(model; dual = true, allow_local = allow_local)

    # PF-04 EXACTNESS GATE (RESEARCH Pattern 4; threats T-04-01 / T-04-03): the headline
    # correctness gate. It MUST run AFTER assert_solved! (a trusted primal) and BEFORE any
    # dual (price) is read, so a physically-meaningless dual from a STRICT (inexact) SOC
    # relaxation is refused rather than returned (RESEARCH Anti-Pattern "reading the DADP
    # before the exactness gate"). It is DATA-DRIVEN on the presence of the squared-current
    # variable `:l` in the formulation's `pf_vars` stash: only ConvexBranchFlow stashes `:l`,
    # so DC/LinDistFlow (no cone, no `:l`) skip this untouched — no `if formulation ==`
    # branching. `rtol_exact` (default 1e-4) is a RELATIVE, base-free cone-slack tolerance
    # (WR-01): normalizing the residual by the cone magnitude keeps the gate's protective
    # strength invariant to the per-unit base, unlike the old absolute threshold. It is
    # DELIBERATELY DISTINCT from the battery-check `τ` — a different physical quantity, do not
    # conflate them. `maxgap` (the absolute residual) is stashed under `ctx.meta[:socp_maxgap]`
    # as a first-class output reported alongside the prices.
    if haskey(ctx.meta, :pf_vars) && haskey(ctx.meta[:pf_vars], :l)
        ctx.meta[:socp_maxgap] = assert_socp_exact!(ctx; rtol = rtol_exact)
    end

    # App. C MANDATORY post-solve battery complementarity (RESEARCH Pitfall 1, threat
    # T-03-13): with λ_min ≤ λ_med ≤ λ_max there is no binary/complementarity constraint,
    # so p_ch·p_dch = 0 must be VERIFIED numerically at the welfare optimum.
    if haskey(ctx.meta, :agg_device_vars)
        for (bus, varlist) in ctx.meta[:agg_device_vars]
            for v in varlist
                (haskey(v, :p_ch) && haskey(v, :p_dch)) || continue   # a battery
                for t in 1:T
                    prod = value(v.p_ch[t]) * value(v.p_dch[t])
                    prod < τ || error(
                        "Battery complementarity violated at bus $bus, t=$t: " *
                        "p_ch·p_dch = $prod ≥ τ=$τ (App. C, threat T-03-13)",
                    )
                end
            end
        end
    end

    # DADP = dual of the ACTIVE balance at the first aggregator's bus over the horizon.
    priced = aggregators[1].bus
    dadp = dual.(balance_p[priced, :])
    return ctx, objective_value(model), dadp
end

export solve_welfare
