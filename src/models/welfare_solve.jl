# src/models/welfare_solve.jl
#
# SEAM: GLB-CVX centralized social-welfare solve.
#
# Generalizes `linear_solve.jl` to a multi-aggregator centralized welfare
# maximization over the LinDistFlow model at horizon T=24 (thesis eq.
# 3.38). Assembles each aggregator's :Rp/:Rq injections and utility, adds a
# non-negative priced frontier import p_import[t] and -- only when the formulation
# provides a reactive channel -- a FREE-SIGN reactive frontier q_import[t] at
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
                  allow_export::Bool = false, allow_almost::Bool = false)
        -> (ctx::ModelContext, objective::Float64, dadp::Vector{Float64})

Build and solve the GLB-CVX centralized social-welfare problem (thesis eq. 3.38) over
`feeder`, a swappable `AbstractPowerFlow`, and a vector of [`Aggregator`](@ref)s. This
GENERALIZES [`solve_linear`](@ref) from a single device list to multiple aggregators at
horizon `T` (the rung-1 `solve_linear` stays untouched as a regression). It:

 1. builds `Model(optimizer)` — `optimizer` defaults to `select_optimizer(problem_class(pf))`,
    so the solver factory is chosen BY FORMULATION TRAIT: DC/LinDistFlow
    route to the `QP()` backend, while `ConvexBranchFlow` routes to the tight-gap `SOCP()`
    backend (`tol_gap_abs/rel = 1e-8`, which the DADP accuracy and exactness check depend on).
    Both are Clarabel, and this file NEVER names a concrete solver (no
    `if formulation ==` branch). Cross-solver checks pass a different factory (e.g.
    `select_optimizer(NLP())`) plus `allow_local = true`;
 2. wraps it in a [`ModelContext`](@ref); stashes `feeder`/`T`;
 3. lets the power-flow formulation `contribute!` its branch/voltage terms into
    `ctx.residuals[:Rp]` (and `:Rq` for `LinDistFlow`) and each aggregator `contribute!`
    its net active/reactive injections into `:Rp`/`:Rq` plus its summed utility into
    `ctx.objective`;
 4. injects a priced active frontier exchange `p_import[t]` at `feeder.root` (stashed
    under `ctx.meta[:p_import]`). By default it is IMPORT-ONLY (`p_import ≥ 0`, buy from the
    MEM). With `allow_export = true` it is FREE-SIGN (`>0` buy, `<0` sell surplus to the MEM
    at the same λ₀) — the physically-complete transmission frontier that lets a high-PV feeder
    export its reverse-flow surplus. Priced export is the SOC-EXACTNESS enabler: it
    makes the welfare objective strictly decreasing in the loss current `l` (every unit of `l`
    costs export revenue), so the SOC cone `l·v ≥ P²+Q²` stays TIGHT in the over-voltage /
    reverse-flow regime instead of going slack (inexact). Import-only leaves losses-vs-
    curtailment welfare-equivalent, breaking that condition. It also adds — ONLY when the
    formulation provides a reactive channel
    — a FREE-SIGN reactive frontier import `q_import[t]` (no lower bound, stashed
    under `ctx.meta[:q_import]`), BOTH BEFORE closing the residuals. Without the free-sign
    `q_import`, pinning `:Rq` at every bus with a reactive load present is INFEASIBLE (or
    silently zeroes the reactive draw) — the MEM/substation supplies reactive power at the
    frontier;
 5. closes `:Rp` always and `:Rq` only when the POWER-FLOW FORMULATION provides a reactive
    channel — captured as `reactive = haskey(ctx.residuals, :Rq)` RIGHT AFTER the
    formulation contributes and BEFORE any aggregator writes. This keys off the
    formulation's capability, not a formulation flag: LinDistFlow closes `:Rq`; a DC
    (active-only) run leaves any aggregator reactive terms unclosed. Both closures are
    registered (`:balance_p` / `:balance_q`) so their duals are recoverable;
 6. maximizes welfare `Σ aggregator utility − λ₀ᵀ·p_import` (thesis eq. 3.38);
 7. solves through [`assert_solved!`](@ref)`(...; dual = true, allow_local, allow_almost)` —
    the OPTIMAL (or, for a nonconvex cross-check, LOCALLY_SOLVED) gate before any dual is
    trusted. `allow_almost` defaults `false` (STRICT gate,
    bit-for-bit identical to every pre-existing call site) and is forwarded VERBATIM to
    `assert_solved!`'s own `allow_almost` — see that function's docstring for the precondition
    it sanctions ("an intermediate re-solve whose DUALS are NOT read"). Passing `true` here
    does NOT bypass step 8/9 below (they still run on whatever primal was accepted); it is the
    caller's responsibility to independently verify precision before trusting `objective_value`
    when `allow_almost = true` accepted a near-feasible point (`fit_baseline`'s cross-check
    cross-check is the ONE intended caller, gated behind its own measured gap bound);
 8. runs the EXACTNESS GATE [`assert_socp_exact!`](@ref)`(ctx; rtol = rtol_exact)` — but
    ONLY when the formulation stashed a squared-current `:l` in `ctx.pf_vars` (i.e. a SOCP
    cone is present). It sits strictly AFTER `assert_solved!` and BEFORE any `dual()` read, so
    physically-meaningless duals from a STRICT (inexact) relaxation are REFUSED (thrown) rather
    than returned. `maxgap` is stashed under `ctx.meta[:socp_maxgap]`.
    DC/LinDistFlow stash no `:l` and skip this untouched. `rtol_exact` (default 1e-4) is a
    RELATIVE, base-free cone-slack tolerance and is a DISTINCT quantity from the
    battery-check `τ` — never conflated;
 9. runs the MANDATORY App. C post-solve battery complementarity check via
    [`assert_battery_complementarity!`](@ref): for every battery stashed under
    `ctx.agg_device_vars`, asserts the SCALE-FREE relative test
    `value(p_ch[t])·value(p_dch[t]) < τ·Pmax²` for all `t`, throwing loudly on violation
    Normalizing by the battery's rated power²
    makes the gate's protective strength INVARIANT to the per-unit base — an absolute product
    threshold weakens quadratically as the base grows and can silently admit a genuine
    simultaneous charge/discharge. The RELATIVE tolerance `τ` is PROBLEM-CLASS-AWARE by
    default: `1e-6` (fraction of `Pmax²`) on the QP path (DC/LinDistFlow, whose Clarabel-QP
    primal is tight) but a looser `1e-3` on the SOCP path (`ConvexBranchFlow`), where the
    interior-point conic solve co-activates the optimal face more. This keys off
    `problem_class(pf)` (a trait, not an `if formulation ==`) and never loosens the QP path
    (the `Pmax²`-scaled threshold is ≤ the old absolute `1e-6` for every `Pmax ≤ 1`).

Returns `(ctx, objective_value, dadp)` where `dadp = dual.(balance_p[bus, :])` at the
FIRST aggregator's bus (the distribution price / DADP over the horizon).

Throws `ArgumentError` on empty `aggregators`, `length(λ₀) != T`, or an aggregator bus
outside `1:length(feeder.buses)` — the boundary guards that keep a shape mismatch from
becoming a cryptic deep crash or a silently-wrong optimum.
"""
function solve_welfare(
    feeder::AbstractFeeder,
    pf::AbstractPowerFlow,
    aggregators::AbstractVector{<:Aggregator};
    T::Int = 24,
    λ₀,
    optimizer = select_optimizer(problem_class(pf)),
    allow_local::Bool = false,
    τ::Real = (problem_class(pf) isa SOCP ? 1e-3 : 1e-6),
    rtol_exact::Real = 1e-4,
    allow_export::Bool = false,
    # a NEW, narrowly-scoped kwarg forwarded VERBATIM to
    # assert_solved!'s own allow_almost (src/core/status.jl). Defaults false everywhere, so
    # EVERY existing call site (the planning subproblem/AgrOpt, stochastic_welfare, every
    # test) is bit-for-bit identical. See assert_solved!'s own docstring for the precondition this
    # sanctions ("an intermediate re-solve whose DUALS are NOT read") — the ONLY intended
    # caller is fit_baseline's cross-check, which discards this function's `dadp`
    # return value and gates acceptance behind its OWN measured, named primal-dual gap bound
    # (FIT_SITE3_ALMOST_GAP_TOL) BEFORE trusting `objective_value` (see src/pricing/fit.jl).
    allow_almost::Bool = false,
)
    # Boundary guards: empty aggregators ⇒ no priced load / no
    # objective; a λ₀ shape mismatch ⇒ BoundsError deep in objective assembly. Fail here.
    isempty(aggregators) &&
        throw(ArgumentError("solve_welfare needs at least one aggregator"))
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))

    model = Model(optimizer)                 # QP() factory by default; never names a solver

    # Cross-solver enablement: register the OPT-IN
    # RotatedSecondOrderCone / SecondOrderCone → nonconvex-quadratic bridges so a smooth-NLP
    # backend (Ipopt, via `select_optimizer(NLP())` + `allow_local = true`) can INDEPENDENTLY
    # re-solve the SOCP ConvexBranchFlow model as a cross-check. These bridges are DORMANT for
    # the primary Clarabel path (Clarabel supports both cone sets natively, so the
    # LazyBridgeOptimizer never reformulates) — they only activate when the chosen backend
    # cannot take the cone directly, reformulating `l·v ≥ P²+Q²` into the smooth quadratic
    # constraint Ipopt handles. They are no-ops for the cone-free DC/LinDistFlow (QP) paths.
    # Registered here (not in the factory) because bridges attach to the JuMP `Model`, not the
    # optimizer attributes, and this file is the sole model builder (still
    # no concrete solver named).
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)

    ctx = ModelContext(model)
    ctx.feeder = feeder
    ctx.T = T

    Np = length(feeder.buses)

    # Every aggregator must sit on a real feeder bus, else its injection grows :Rp beyond
    # the balance-closure range and vanishes from the network balance (welfare from
    # nowhere) — fail loudly, mirroring solve_linear's device guard.
    for (k, agg) in enumerate(aggregators)
        1 <= agg.bus <= Np || throw(
            ArgumentError("aggregator[$k] bus=$(agg.bus) is outside feeder buses 1:$Np"),
        )
    end

    # Formulation: branch/voltage terms into :Rp (and :Rq for LinDistFlow).
    contribute!(pf, ctx, feeder; T = T)

    # whether a REACTIVE channel exists is decided by the POWER-FLOW FORMULATION,
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
    reactive = has_reactive(pf)

    # Aggregators: net active/reactive injections into :Rp/:Rq + summed utility into
    # ctx.objective. Each aggregator is the sole :Rp/:Rq writer at its bus. (On a DC
    # run the aggregators still write :Rq, but it is left unclosed below — active-only.)
    #
    # PURELY ADDITIVE surplus stash. Capture each `contribute!` return
    # (previously discarded) and record, per aggregator, its NET active injection
    # `net[t] = p_inject[t] − Pdc[t]` (EXACTLY the expression written to :Rp at agg.bus, thesis
    # 3.22) plus the returned `utility` QuadExpr. Under a solved ctx the welfare accounting
    # The pricing layer splits social = prosumer + DSO surplus: the prosumer surplus is
    # `Σ_j U_agⱼ − Σ_j Σ_t λ_j[t]·net_j[t]` (thesis eqs. 3.46/3.47), where the price-transfer
    # term needs the per-aggregator net injection `p_agⱼ[t]` (= net[t] here) and `Σ_j U_agⱼ`
    # remains sourced from `value(ctx.objective)`. Recording it does NOT alter the
    # residual writes, the objective, the balance registration, the exactness gate, the battery
    # check, or the returned tuple.
    agg_net = Vector{NamedTuple}(undef, length(aggregators))
    for (k, agg) in enumerate(aggregators)
        res = contribute!(agg, ctx; T = T)
        net = [res.p_inject[t] - agg.Pdc[t] for t in 1:T]   # net active injection p_agⱼ[t] (3.22)
        agg_net[k] = (; bus = agg.bus, net = net, utility = res.utility)
    end
    ctx.meta[:agg_net] = agg_net

    # Frontier imports at the root, injected BEFORE closing the residuals. p_import is
    # priced and non-negative (active draw from the MEM). q_import is FREE-SIGN so the
    # reactive load closes feasibly instead of forcing Q ≡ 0 — added ONLY when the
    # formulation provides a reactive channel (a DC run has no reactive balance).
    # Active frontier exchange at the root, priced at λ₀. By default it is IMPORT-ONLY
    # (`p_import[t] ≥ 0`, buy from the MEM) — the rung-0…rung-2 behavior. With
    # `allow_export = true` it becomes a FREE-SIGN net exchange (`>0` buy, `<0` sell surplus
    # to the MEM at the same λ₀) — a physically-complete transmission frontier that lets a
    # high-PV feeder EXPORT its reverse-flow surplus instead of dissipating it. That export
    # sink is the SOC-exactness enabler: with import-only, shedding surplus via line
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
    balance_p, balance_q = close_balance!(ctx, Np, T; reactive = reactive)

    # GLB-CVX welfare (thesis eq. 3.38): Σ aggregator utility − λ₀ᵀ·p_import.
    welfare = ctx.objective - sum(λ₀[t] * p_import[t] for t in 1:T)
    @objective(model, Max, welfare)

    # OPTIMAL gate: never read a dual (price) before a trusted solve.
    # `allow_almost` is forwarded VERBATIM and defaults false — bit-for-bit identical to
    # before this kwarg existed on every call site that omits it.
    assert_solved!(
        model;
        dual = true,
        allow_local = allow_local,
        allow_almost = allow_almost,
    )

    # EXACTNESS GATE: the headline
    # correctness gate. It MUST run AFTER assert_solved! (a trusted primal) and BEFORE any
    # dual (price) is read, so a physically-meaningless dual from a STRICT (inexact) SOC
    # relaxation is refused rather than returned (Anti-Pattern "reading the DADP
    # before the exactness gate"). It is DATA-DRIVEN on the presence of the squared-current
    # variable `:l` in the formulation's `pf_vars` stash: only ConvexBranchFlow stashes `:l`,
    # so DC/LinDistFlow (no cone, no `:l`) skip this untouched — no `if formulation ==`
    # branching. `rtol_exact` (default 1e-4) is a RELATIVE, base-free cone-slack tolerance
    # normalizing the residual by the cone magnitude keeps the gate's protective
    # strength invariant to the per-unit base, unlike the old absolute threshold. It is
    # DELIBERATELY DISTINCT from the battery-check `τ` — a different physical quantity, do not
    # conflate them. `maxgap` (the absolute residual) is stashed under `ctx.meta[:socp_maxgap]`
    # as a first-class output reported alongside the prices.
    if has_branch_current(ctx)
        ctx.meta[:socp_maxgap] = assert_socp_exact!(ctx; rtol = rtol_exact)
    end

    # App. C MANDATORY post-solve battery complementarity: with λ_min < λ_med < λ_max there is no binary/complementarity constraint,
    # so p_ch·p_dch = 0 must be VERIFIED numerically at the welfare optimum. The check is a
    # SCALE-FREE relative test — see `assert_battery_complementarity!`.
    #
    # App. C's "no simultaneous charge/discharge" argument implicitly
    # assumes η=1. For η<1, whenever DLMP < λ_med and both legs are small, an SOC-neutral
    # round trip earns (λ_med−DLMP)(1−η²) > 0, so a GENUINE, KKT-consistent simultaneous
    # charge/discharge CAN be the true optimum on the AC (NLP/Ipopt) oracle path — this is a
    # latent gap in App. C's own parametrization, not a bug (see the audit notes).
    # The AC/NLP oracle therefore REPORTS (never throws on) a violation via `:warn`; every
    # other (SOCP) call site is COMPLETELY unaffected and keeps the default `:error` (still
    # throws, byte-for-byte the same message).
    on_violation = problem_class(pf) isa SOCP ? :error : :warn
    assert_battery_complementarity!(ctx; τ = τ, T = T, on_violation = on_violation)

    # DADP = dual of the ACTIVE balance at the first aggregator's bus over the horizon.
    priced = aggregators[1].bus
    dadp = dual.(balance_p[priced, :])
    return ctx, objective_value(model), dadp
end

"""
    assert_battery_complementarity!(ctx::ModelContext; τ::Real, T::Int = _require_T(ctx),
                                     on_violation::Symbol = :error)

Verify the App. C no-binary battery complementarity `p_ch[t]·p_dch[t] = 0` numerically at a
solved point. There is NO `p_ch·p_dch == 0` constraint in
the model — the strict `λ_min < λ_med < λ_max` parametrization alone makes simultaneous
charge/discharge dominated — so this post-solve certificate is the only thing that catches a
degenerate co-activation.

`on_violation` selects what happens on a violation:

  - `:error` (default) — throw, bit-for-bit the same message as before. Used by
    EVERY call site except the AC/NLP path in `solve_welfare` (`src/planning/subproblem.jl`,
    `src/admm/AgrOpt.jl`, `src/models/stochastic_welfare.jl` all pass only `τ`/`T` and so get
    this default, unchanged).
  - `:warn` — log the SAME message via `@warn` and CONTINUE (every violating `(bus, t)` pair
    is reported, not just the first). `solve_welfare` passes this ONLY on the AC/NLP
    (non-SOCP) path. It was found that App. C's "no simultaneous
    charge/discharge" argument implicitly assumes η=1: for η<1, whenever DLMP < λ_med and
    both legs are small, an SOC-neutral round trip earns `(λ_med−DLMP)(1−η²) > 0`, so a
    GENUINE, KKT-consistent simultaneous charge/discharge CAN be the true optimum — verified
    to 4 digits against the App. C KKT identity on the high-PV AC fixture (bus 2,
    t=7). This is a LATENT model-parametrization gap in App. C itself, not a solver bug, so
    the AC oracle must not hard-fail on an optimum it correctly found; see `docs/literate/prosumer_welfare.jl` for the backlog item (a
    proper complementarity treatment — binary/MPEC or an η-aware round-trip penalty — is
    deferred, NOT done here). The SOCP path's own call site is UNCHANGED and still
    throws (its looser `τ=1e-3` masks the identical effect, so no equivalent finding fires
    there).
  - any other value — throws an `ArgumentError` (fail loud on programmer error).

The test is RELATIVE (scale-free), not an absolute product threshold. For each
battery it normalizes the product by the square of the device's rated charge/discharge power
`Pmax` (recovered from the JuMP variable's upper bound) and flags

    value(p_ch[t]) · value(p_dch[t]) ≥ τ · Pmax²

i.e. it triggers when BOTH legs are simultaneously non-negligible relative to the battery's
own power rating (`√τ` of `Pmax` on each leg). Because `p_ch`, `p_dch`, and `Pmax` all scale
identically with the per-unit base, the ratio `p_ch·p_dch / Pmax²` is INVARIANT to the base.
An absolute product threshold, by contrast, weakens quadratically as the base grows (a real
simultaneous charge/discharge of a fixed MW is a tiny pu² product on a 100 MVA base and slips
under a fixed τ), so the same physical violation could pass on one base and be caught on
another. Genuine solver-noise co-activation (a tiny product on a truly-zero leg) still passes.

`τ` is a RELATIVE tolerance (fraction of `Pmax²`). `solve_welfare` defaults it PROBLEM-CLASS-
AWARE via the `problem_class` trait — looser on the interior-point SOCP path, tighter on the
QP path — and this function never loosens the QP path (its `Pmax²`-scaled threshold is ≤ the
old absolute one for every `Pmax ≤ 1`). Iterates `ctx.agg_device_vars` (skips
non-battery device stashes) and is a no-op when no batteries were registered.

BATTERY-ACTIVE-POWER-ONLY: this check's loop condition excludes any
device that ALSO carries a reactive decision variable (`:q`) — such a device (currently
only `FourQuadBESS`) has its OWN peer certificate,
[`assert_4q_complementarity!`](@ref) (`complementarity_4q.jl`), with its OWN
independently-measured tolerance. Excluding `:q`-carrying devices here keeps the two
checks structurally mutually exclusive over the same `ctx.agg_device_vars` stash —
this one never silently runs against a `FourQuadBESS`'s vars.
"""
function assert_battery_complementarity!(
    ctx::ModelContext;
    τ::Real,
    T::Int = _require_T(ctx),
    on_violation::Symbol = :error,
)
    on_violation in (:error, :warn) || throw(
        ArgumentError(
            "assert_battery_complementarity!: invalid on_violation=$(repr(on_violation)), expected :error or :warn",
        ),
    )
    !isempty(ctx.agg_device_vars) || return nothing
    for (bus, varlist) in ctx.agg_device_vars
        for v in varlist
            (haskey(v, :p_ch) && haskey(v, :p_dch) && !haskey(v, :q)) || continue   # a battery, not a 4Q device
            # Rated charge/discharge power (eq. 3.8 bound) = the base-scaling reference. The
            # atol floor guards a (degenerate) zero/absent upper bound against a div-by-zero.
            pmax = has_upper_bound(v.p_ch[1]) ? upper_bound(v.p_ch[1]) : 1.0
            scale² = max(abs(pmax), 1e-8)^2
            for t in 1:T
                prod = value(v.p_ch[t]) * value(v.p_dch[t])
                if prod >= τ * scale²
                    msg =
                        "Battery complementarity violated at bus $bus, t=$t: " *
                        "p_ch·p_dch = $prod ≥ τ·Pmax² = $(τ * scale²) " *
                        "(relative τ=$τ, Pmax≈$pmax; App. C)"
                    if on_violation === :error
                        throw(CertificateError(msg; kind = :battery))
                    else
                        @warn msg
                    end
                end
            end
        end
    end
    return nothing
end

export solve_welfare, assert_battery_complementarity!
