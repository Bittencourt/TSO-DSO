# Seam: devices/Behavioural.jl (+ experiments/materialize.jl BehaviourSpec / apply_behaviour).
#
# Phase 44 plan 04 (ACTOR-04, model side): exogenous, seeded behavioural scenarios as WRAPPER
# devices (PartialCompliance, OptOut, Rebound) and an opt-in population transform. Nothing inside
# the solves changes (zero binaries, no new solver paths). Every item name contains "behaviour".
#
# MEASUREMENT-BEFORE-GOLDEN: every tolerance below was MEASURED (2026-11-02, julia 1.12.5, scratch
# script outside the repo) on three device classes (an EV that must charge, a Thermostatic load, a
# HeatPump; two-bus-scale parameters, T = 24) at the SWING price (12 on hours 5..8, 1 on 18..24 and
# 1..4, 4 else) against a per-device FIT-flat-price baseline (price 6.6), and pinned at 3 x the
# observed maximum:
#
#   quantity                                       observed max          pinned band
#   xi = 1 identity |p'-p|, |U'-U|                 0.0 (bitwise equal)   1e-12 (numerical-zero floor)
#   blend |p' - (b + xi(p-b))|  xi in .25/.5/.75   2.20e-11 (EV)         6.6e-11
#   blend |U' - ((1-xi)Ub + xi U)|                 5.26e-11 (EV)         1.58e-10
#   Rebound recovery violation (u = max(0,p-b))    4.85e-11 (HeatPump)   1.46e-10
#   baseline permutation agreement (tie-break)     1.85e-10 (EV)         see `_BASELINE_TIEBREAK`
#   Ub (regularised solve) vs unregularised U      7.37e-11 (EV)         2.2e-10
#   wrapped two-bus crossval, 5 seeds x {hand-built [PartialCompliance(EV, .5), OptOut(HP),
#     Rebound(PartialCompliance(Thermostatic, .5), W=6)], apply_behaviour(compliance=.5,
#     opt_out=.4, rebound=(W=6, r=1), seed)}, swing price, solve_welfare (SOCP) vs solve_admm:
#       |dWelfare|   hand max 6.25e-5, spec max 6.91e-5     pinned 2.08e-4 (3 x 6.91e-5)
#       |dlambda|_2  hand max 6.30e-6, spec max 7.58e-6     pinned 2.28e-5 (3 x 7.58e-6)
#     (|lambda|_2 ~ 27.04; every run converges in iters = 2; EV certificate ratio 0.0)

@testmodule BehaviourFixtures begin
    using TSODSO, JuMP

    const T = 24
    const SWING = Float64[
        (t in 5:8) ? 12.0 : ((t >= 18 || t <= 4) ? 1.0 : 4.0) for t in 1:T
    ]
    const FLAT = fill(6.6, T)
    const SPIKE = Float64[(t in 10:12) ? 60.0 : 6.6 for t in 1:T]

    # An EV that MUST charge (soc0 < target): flat-price optimum is non-unique in time.
    ev() = TSODSO.ElectricVehicle(
        2, 0.95, 1.0, 0.02, 0.0, 0.08, 0.02, 0.06, 1e3, 3.8, 6.2, 8.9, 18, 8,
    )
    therm(; φ = nothing) = Thermostatic(
        2, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5,
        Float64[19 + 5 * sin(2π * (t - 9) / 24) for t in 1:T], φ,
    )
    hp() = TSODSO._flex_heatpump(1_234_567, 2, 1, T; scale = 0.02)

    """Standalone maximisation of `utility + price' p_inject` for a freshly built device."""
    function solve_standalone(mk, price)
        model = Model(TSODSO.select_optimizer(TSODSO.QP()))
        set_silent(model)
        ctx = TSODSO.ModelContext(model)
        res = TSODSO.contribute!(mk(), ctx; T = T)
        @objective(model, Max, res.utility + sum(price[t] * res.p_inject[t] for t in 1:T))
        TSODSO.assert_solved!(model; dual = false)
        return (; p = value.(res.p_inject), U = value(res.utility), res, model, ctx)
    end

    """Per-device flat-price baseline (the same shape `apply_behaviour` uses)."""
    function baseline(d)
        return TSODSO._device_baseline(d, T)
    end
end

@testitem "behaviour: wrappers satisfy the contribute! contract, anonymity, zero binaries" setup =
    [BehaviourFixtures] tags = [:behaviour] begin
    using TSODSO, JuMP
    F = BehaviourFixtures
    T = F.T

    function build(wrapper::Symbol, d)
        bs = F.baseline(d)
        wrapper === :pc && return PartialCompliance(d, 0.5, bs.b, bs.Ub)
        wrapper === :oo && return OptOut(d, bs.b, bs.Ub)
        return Rebound(PartialCompliance(d, 0.5, bs.b, bs.Ub), bs.b, 3, 1.0)
    end

    for w in (:pc, :oo, :rb)
        model = Model(TSODSO.select_optimizer(TSODSO.QP()))
        ctx = TSODSO.ModelContext(model)
        # two wrapped devices coexist in ONE model (anonymous JuMP objects)
        r1 = TSODSO.contribute!(build(w, F.ev()), ctx; T = T)
        r2 = TSODSO.contribute!(build(w, F.hp()), ctx; T = T)
        for r in (r1, r2)
            @test all(in(propertynames(r)), (:vars, :p_inject, :utility))
            @test !hasproperty(r, :q_inject)
            @test length(r.p_inject) == T
            @test all(x -> x isa AffExpr, r.p_inject)
            @test r.utility isa QuadExpr
        end
        @test isempty(ctx.residuals)
        @test isempty(ctx.objective.terms) && iszero(ctx.objective.aff)
        vs = all_variables(model)
        @test count(is_binary, vs) == 0
        @test count(is_integer, vs) == 0
    end
    # OptOut owns no decision variable at all
    model = Model()
    ctx = TSODSO.ModelContext(model)
    r = TSODSO.contribute!(build(:oo, F.therm()), ctx; T = T)
    @test r.vars == (;)
    @test isempty(all_variables(model))
end

@testitem "behaviour: xi = 1 identity and the blend math p' = b + xi(p-b), U' = (1-xi)Ub + xi U" setup =
    [BehaviourFixtures] tags = [:behaviour] begin
    using TSODSO, JuMP
    F = BehaviourFixtures

    # bands: see the header table (3 x observed max)
    ATOL_ID = 1e-12
    ATOL_P = 6.6e-11
    ATOL_U = 1.58e-10

    function check(mk)
        d = mk()
        bs = F.baseline(d)
        inner = F.solve_standalone(mk, F.SWING)
        id = F.solve_standalone(() -> PartialCompliance(mk(), 1.0, bs.b, bs.Ub), F.SWING)
        ok = maximum(abs.(id.p .- inner.p)) <= ATOL_ID && abs(id.U - inner.U) <= ATOL_ID
        for xi in (0.25, 0.5, 0.75)
            w = F.solve_standalone(
                () -> PartialCompliance(mk(), xi, bs.b, bs.Ub),
                F.SWING,
            )
            dp = maximum(abs.(w.p .- (bs.b .+ xi .* (inner.p .- bs.b))))
            dU = abs(w.U - ((1 - xi) * bs.Ub + xi * inner.U))
            ok &= dp <= ATOL_P && dU <= ATOL_U
        end
        return ok
    end
    @test check(F.ev)
    @test check(F.therm)
    @test check(F.hp)
end

@testitem "behaviour: OptOut fixes p_inject = b, utility = Ub; all-OptOut aggregator solves" setup =
    [BehaviourFixtures, TwoBusFixtures] tags = [:behaviour] begin
    using TSODSO, JuMP
    F = BehaviourFixtures
    T = F.T

    d = F.hp()
    bs = F.baseline(d)
    # (no standalone solve: an OptOut owns no variable and a variable-free model has nothing
    # to hand Clarabel; the constants are read off the returned expressions)
    r = TSODSO.contribute!(
        OptOut(d, bs.b, bs.Ub),
        TSODSO.ModelContext(Model());
        T = T,
    )
    @test [JuMP.constant(x) for x in r.p_inject] == bs.b
    @test all(x -> isempty(x.terms), r.p_inject)
    @test r.utility.aff.constant == bs.Ub
    @test isempty(r.utility.terms) && isempty(r.utility.aff.terms)
    @test r.vars == (;)

    # Pitfall 9: an aggregator whose devices are ALL OptOut still builds and solves.
    prof = generate_profiles(seed = TwoBusFixtures.SEED_2BUS + 2, T = T)
    Pdc = Float64[TwoBusFixtures.LOAD_SCALE_2BUS * p for p in prof.demand]
    e = F.ev()
    be = F.baseline(e)
    h = F.hp()
    bh = F.baseline(h)
    aggs = [
        TSODSO.Aggregator(2, 0.90, [OptOut(e, be.b, be.Ub), OptOut(h, bh.b, bh.Ub)], Pdc),
    ]
    ctx, obj, _ = solve_welfare(
        TwoBusFixtures.two_bus_feeder(),
        ConvexBranchFlow(),
        aggs;
        T = T,
        λ₀ = fill(4.0, T),
        allow_export = true,
    )
    @test isfinite(obj)
    @test all(isfinite, extract_dlmp(ctx; bus = 2, T = T))
    @test all(k -> k === :none, TSODSO.storage_kind.(ctx.agg_device_types[2]))
end

@testitem "behaviour: Rebound is a convex linear recovery constraint, always feasible" setup =
    [BehaviourFixtures] tags = [:behaviour] begin
    using TSODSO, JuMP
    F = BehaviourFixtures
    T = F.T
    ATOL_VIOL = 1.46e-10   # 3 x observed max (header table)

    d = F.hp()
    bs = F.baseline(d)
    inner = F.solve_standalone(F.hp, F.SPIKE)
    # the unwrapped device curtails at the spike
    @test maximum(max.(0.0, inner.p .- bs.b)) > 1e-3

    function violation(w, W, r)
        umin = max.(0.0, w.p .- bs.b)
        return maximum(
            r * umin[t] - sum(bs.b[τ] - w.p[τ] for τ in (t + 1):min(t + W, T); init = 0.0)
            for t in 1:T
        )
    end
    # W = 6, r = 1: curtails and the recovery inequality holds at the solution
    w6 = F.solve_standalone(() -> Rebound(F.hp(), bs.b, 6, 1.0), F.SPIKE)
    @test maximum(max.(0.0, w6.p .- bs.b)) > 1e-3
    @test violation(w6, 6, 1.0) <= ATOL_VIOL
    # W = 2, r = 2 (a hard recovery requirement): still feasible; recovery holds
    w2 = F.solve_standalone(() -> Rebound(F.hp(), bs.b, 2, 2.0), F.SPIKE)
    @test violation(w2, 2, 2.0) <= ATOL_VIOL
    # baseline feasibility: the baseline itself satisfies the constraints (u = 0)
    # (solve succeeded with all curtailment forbidden by W = 3: p == b to the noise floor)
    w3 = F.solve_standalone(() -> Rebound(F.hp(), bs.b, 3, 1.0), F.SPIKE)
    @test maximum(max.(0.0, w3.p .- bs.b)) <= 1e-9
    # horizon clip, no wrap: a spike in the last hours cannot be curtailed unrecoverably
    spikeT = Float64[(t in 22:24) ? 60.0 : 6.6 for t in 1:T]
    free = F.solve_standalone(F.hp, spikeT)
    clipped = F.solve_standalone(() -> Rebound(F.hp(), bs.b, 3, 1.0), spikeT)
    @test maximum(max.(0.0, free.p .- bs.b)[22:24]) > 1e-4
    @test maximum(max.(0.0, clipped.p .- bs.b)[22:24]) <= 1e-9
    @test max(0.0, clipped.p[T] - bs.b[T]) <= 1e-9
    # stacked over PartialCompliance and exposing the curtailment variable
    st = F.solve_standalone(
        () -> Rebound(PartialCompliance(F.hp(), 0.5, bs.b, bs.Ub), bs.b, 6, 1.0),
        F.SPIKE,
    )
    @test haskey(st.res.vars, :rebound_u)
    @test violation(st, 6, 1.0) <= ATOL_VIOL
end

@testitem "behaviour: wrapper traits forward; phi exposed; storage kind routed" setup =
    [BehaviourFixtures] tags = [:behaviour] begin
    using TSODSO, JuMP
    F = BehaviourFixtures
    T = F.T

    th = F.therm(φ = 0.8)
    ev = F.ev()
    bt = F.baseline(th)
    be = F.baseline(ev)
    pct = PartialCompliance(th, 0.5, bt.b, bt.Ub)
    ooth = OptOut(th, bt.b, bt.Ub)
    rbt = Rebound(pct, bt.b, 3, 1.0)
    pce = PartialCompliance(ev, 0.5, be.b, be.Ub)
    ooev = OptOut(ev, be.b, be.Ub)

    for w in (pct, ooth, rbt)
        @test TSODSO.is_flexible_load(w) === TSODSO.is_flexible_load(th)
        @test TSODSO.has_reactive_decision(w) === TSODSO.has_reactive_decision(th)
        @test w.φ == 0.8
    end
    for w in (pce, ooev)
        @test TSODSO.is_flexible_load(w) === TSODSO.is_flexible_load(ev)
        @test TSODSO.has_reactive_decision(w) === TSODSO.has_reactive_decision(ev)
        @test w.φ === nothing
    end
    # storage_kind: type-level, forwarded for PartialCompliance / Rebound, :none for OptOut
    @test TSODSO.storage_kind(typeof(pce)) === TSODSO.storage_kind(typeof(ev)) === :ev
    @test TSODSO.storage_kind(pce) === :ev
    @test TSODSO.storage_kind(typeof(Rebound(pce, be.b, 3, 1.0))) === :ev
    @test TSODSO.storage_kind(typeof(ooev)) === :none
    @test TSODSO.storage_kind(typeof(pct)) === :none

    # An Aggregator derives the same reactive draw from the wrapper as from the inner device
    function qcoeffs(dev)
        model = Model(TSODSO.select_optimizer(TSODSO.QP()))
        ctx = TSODSO.ModelContext(model)
        agg = TSODSO.Aggregator(2, 0.9, [dev], fill(0.01, T))
        r = TSODSO.contribute!(agg, ctx; T = T)
        vs = all_variables(model)
        return [coefficient(r.q_inject[3], v) for v in vs if !is_parameter(v)]
    end
    inner_q = qcoeffs(th)
    wrapped_q = qcoeffs(PartialCompliance(th, 1.0, bt.b, bt.Ub))
    @test inner_q ≈ wrapped_q
    @test any(!iszero, wrapped_q)
end

@testitem "behaviour: constructor and wrap-time guards throw ArgumentError" setup =
    [BehaviourFixtures] tags = [:behaviour] begin
    using TSODSO, JuMP
    F = BehaviourFixtures
    T = F.T

    d = F.therm()
    b = zeros(T)
    # xi outside (0, 1]; xi = 0 must be OptOut
    @test_throws ArgumentError PartialCompliance(d, 0.0, b, 0.0)
    @test_throws ArgumentError PartialCompliance(d, -0.1, b, 0.0)
    @test_throws ArgumentError PartialCompliance(d, 1.01, b, 0.0)
    @test_throws ArgumentError PartialCompliance(d, NaN, b, 0.0)
    # non-finite baseline / utility
    @test_throws ArgumentError PartialCompliance(d, 0.5, [NaN; b[2:end]], 0.0)
    @test_throws ArgumentError PartialCompliance(d, 0.5, b, Inf)
    @test_throws ArgumentError OptOut(d, [Inf; b[2:end]], 0.0)
    # wrong b length at contribute!
    model = Model()
    ctx = TSODSO.ModelContext(model)
    @test_throws ArgumentError TSODSO.contribute!(
        PartialCompliance(d, 0.5, zeros(T - 1), 0.0), ctx; T = T,
    )
    @test_throws ArgumentError TSODSO.contribute!(OptOut(d, zeros(T + 1), 0.0), ctx; T = T)
    # Rebound: r < 1, W < 1
    @test_throws ArgumentError Rebound(d, b, 3, 0.9)
    @test_throws ArgumentError Rebound(d, b, 0, 1.0)
    @test_throws ArgumentError Rebound(d, b, 3, NaN)
    # out-of-scope devices
    bess = FourQuadBESS(2, 0.95, 1.0, 0.1, 0.1, 0.15, 0.0, 0.2, 0.1, 3.8, 6.2, 8.9)
    sipv = SmartInverterPV(2, 0.1, fill(0.05, T))
    cap = FixedCapacitor(2, 0.1)
    for x in (bess, sipv, cap)
        @test_throws ArgumentError PartialCompliance(x, 0.5, b, 0.0)
        @test_throws ArgumentError OptOut(x, b, 0.0)
        @test_throws ArgumentError Rebound(x, b, 3, 1.0)
    end
    # no double wrapping except Rebound(PartialCompliance(.))
    pc = PartialCompliance(d, 0.5, b, 0.0)
    @test_throws ArgumentError PartialCompliance(pc, 0.5, b, 0.0)
    @test_throws ArgumentError OptOut(pc, b, 0.0)
    @test Rebound(pc, b, 3, 1.0) isa Rebound
    @test_throws ArgumentError Rebound(Rebound(pc, b, 3, 1.0), b, 3, 1.0)
end

@testitem "behaviour: FIT, MPC and stochastic entries reject wrapped devices" setup =
    [BehaviourFixtures, TwoBusFixtures] tags = [:behaviour] begin
    using TSODSO, JuMP
    F = BehaviourFixtures
    T = F.T

    d = F.hp()
    bs = F.baseline(d)
    wrapped = [
        PartialCompliance(d, 0.5, bs.b, bs.Ub),
        OptOut(d, bs.b, bs.Ub),
        Rebound(d, bs.b, 3, 1.0),
    ]
    for w in wrapped
        # the guard fit_baseline and run_mpc both call
        @test_throws ArgumentError TSODSO._reject_unsupported_flex_devices([w], "run_mpc")
        @test_throws "run_mpc" TSODSO._reject_unsupported_flex_devices([w], "run_mpc")
        agg = TSODSO.Aggregator(2, 0.9, [w], fill(0.01, T))
        ctx = TSODSO.ModelContext(Model())
        @test_throws ArgumentError TSODSO._fit_pv_and_flex(agg, ctx; T = T)
    end
    @test_throws "PartialCompliance" TSODSO._reject_unsupported_flex_devices(
        [wrapped[1]], "fit_baseline",
    )
    @test_throws "OptOut" TSODSO._reject_unsupported_flex_devices(
        [wrapped[2]], "fit_baseline",
    )
    @test_throws "Rebound" TSODSO._reject_unsupported_flex_devices(
        [wrapped[3]], "fit_baseline",
    )
    # stochastic aggregator-taking entry
    agg = TSODSO.Aggregator(2, 0.9, [wrapped[1]], fill(0.01, T))
    @test_throws ArgumentError TSODSO.build_stochastic_welfare(
        TwoBusFixtures.two_bus_feeder(),
        ConvexBranchFlow(),
        [[agg], [agg]];
        T = T,
        λ₀ = fill(4.0, T),
    )
    @test_throws "PartialCompliance" TSODSO.build_stochastic_welfare(
        TwoBusFixtures.two_bus_feeder(),
        ConvexBranchFlow(),
        [[agg], [agg]];
        T = T,
        λ₀ = fill(4.0, T),
    )
end

@testitem "behaviour: default BehaviourSpec returns its input ===; default population untouched" tags =
    [:behaviour] begin
    using TSODSO
    using TSODSO: build_feeder, build_population, generate_profiles, sub_seed

    feeder = build_feeder(:ieee13)
    profiles = generate_profiles(; seed = sub_seed(42, :profiles), T = 24)
    s_pop = sub_seed(42, :population)
    aggs = build_population(:default, feeder, :ieee13, profiles, s_pop)
    @test apply_behaviour(aggs, BehaviourSpec(); T = 24) === aggs
    # seed / include_storage alone do not wrap anything either
    @test apply_behaviour(aggs, BehaviourSpec(seed = 7, include_storage = true); T = 24) ===
          aggs
    # the golden digests of the default population are pinned by test_flex_population.jl,
    # which this plan leaves byte-identical (`git diff -- test/test_flex_population.jl` empty).
    @test all(a -> !any(d -> d isa Union{PartialCompliance, OptOut, Rebound}, a.devices), aggs)
end

@testitem "behaviour: seeded opt-out draws (SplitMix64 mix, same seed same draws)" tags =
    [:behaviour] begin
    using TSODSO
    using TSODSO: build_feeder, build_population, generate_profiles, sub_seed

    @test TSODSO._BEH_TAG_OPTOUT == 21
    feeder = build_feeder(:ieee13)
    profiles = generate_profiles(; seed = sub_seed(42, :profiles), T = 24)
    aggs = build_population(:default, feeder, :ieee13, profiles, sub_seed(42, :population))
    function drawn(seed; p = 0.5)
        out = apply_behaviour(aggs, BehaviourSpec(opt_out = p, seed = seed); T = 24)
        return [(a.bus, i) for a in out for (i, d) in enumerate(a.devices) if d isa OptOut]
    end
    a1 = drawn(1)
    @test a1 == drawn(1)                      # reproducible
    @test a1 != drawn(2)                      # a different seed changes the draws
    @test !isempty(a1)
    # the draw is exactly rand(LehmerRNG(_flex_mix(seed, 21, bus, i))) < opt_out
    wrapset(d) = TSODSO.is_flexible_load(d)
    expected = [
        (a.bus, i) for a in aggs for (i, d) in enumerate(a.devices) if wrapset(d) &&
        rand(TSODSO.StableRNGs.LehmerRNG(TSODSO._flex_mix(1, 21, a.bus, i))) < 0.5
    ]
    @test a1 == expected
    # opt_out = 1.0 => every wrapped-set device is an OptOut; opt_out = 0 => no wrapper at all
    full = apply_behaviour(aggs, BehaviourSpec(opt_out = 1.0, seed = 3); T = 24)
    @test all(
        d -> (d isa OptOut) == wrapset(d),
        (d for a in full for d in a.devices),
    )
    @test apply_behaviour(aggs, BehaviourSpec(opt_out = 0.0, compliance = 1.0); T = 24) ===
          aggs
end

@testitem "behaviour: per-device baseline is deterministic, covers every class, unregularised Ub" setup =
    [BehaviourFixtures, TwoBusFixtures] tags = [:behaviour] begin
    using TSODSO, JuMP
    F = BehaviourFixtures
    T = F.T

    for mk in (F.ev, F.therm, F.hp)
        a = TSODSO._device_baseline(mk(), T)
        b = TSODSO._device_baseline(mk(), T)
        @test a.b == b.b && a.Ub == b.Ub
        @test length(a.b) == T && all(isfinite, a.b) && isfinite(a.Ub)
        # Ub is the UNREGULARISED utility at the baseline: compare with a tie-break-free solve
        model = Model(TSODSO.select_optimizer(TSODSO.QP()))
        set_silent(model)
        ctx = TSODSO.ModelContext(model)
        r = TSODSO.contribute!(mk(), ctx; T = T)
        @objective(model, Max, r.utility + sum(6.6 * r.p_inject[t] for t in 1:T))
        TSODSO.assert_solved!(model; dual = false)
        @test abs(a.Ub - value(r.utility)) <= 2.2e-10   # header table
    end
    @test TSODSO._BASELINE_TIEBREAK == 1e-6
    # an EV that must charge is non-unique in time: the tie-break returns a spread schedule
    ev = TSODSO._device_baseline(F.ev(), T)
    @test count(<(-1e-6), ev.b) > 1
    # a FixedCapacitor has no variable: constants returned without a solve
    cap = TSODSO._device_baseline(FixedCapacitor(2, 0.1), T)
    @test cap.b == zeros(T) && cap.Ub == 0.0

    # PVBattery only with include_storage = true
    aggs = TwoBusFixtures.build_two_bus_aggregators(TwoBusFixtures.two_bus_feeder())
    kinds(out) = [nameof(typeof(d)) for d in out[1].devices]
    off = apply_behaviour(aggs, BehaviourSpec(compliance = 0.5); T = T)
    @test :PVBattery in kinds(off)
    on = apply_behaviour(aggs, BehaviourSpec(compliance = 0.5, include_storage = true); T = T)
    @test !(:PVBattery in kinds(on))
    @test TSODSO.storage_kind.(typeof.(on[1].devices))[3] === :battery

    # baseline cost is paid at transform time: a wrapper contributes with NO optimizer attached
    model = Model()
    ctx = TSODSO.ModelContext(model)
    for d in on[1].devices
        TSODSO.contribute!(d, ctx; T = T)
    end
    @test !isempty(all_variables(model))
end

@testitem "behaviour: compliance 0 routes to OptOut; spec validation is fail-loud" setup =
    [TwoBusFixtures] tags = [:behaviour] begin
    using TSODSO
    T = TwoBusFixtures.T
    aggs = TwoBusFixtures.build_two_bus_aggregators(TwoBusFixtures.two_bus_feeder())
    types(out) = [typeof(d) for d in out[1].devices]
    z = apply_behaviour(aggs, BehaviourSpec(compliance = 0.0); T = T)
    @test types(z)[1] <: OptOut
    h = apply_behaviour(aggs, BehaviourSpec(compliance = 0.5); T = T)
    @test types(h)[1] <: PartialCompliance && h[1].devices[1].xi == 0.5
    r = apply_behaviour(
        aggs,
        BehaviourSpec(compliance = 0.5, rebound = (W = 3, r = 1.2)); T = T,
    )
    @test types(r)[1] <: Rebound && r[1].devices[1].inner isa PartialCompliance
    @test r[1].devices[1].W == 3 && r[1].devices[1].r == 1.2
    # rebound alone (compliance 1): bare device wrapped by Rebound
    ro = apply_behaviour(aggs, BehaviourSpec(rebound = (W = 2, r = 1.0)); T = T)
    @test types(ro)[1] <: Rebound && !(ro[1].devices[1].inner isa PartialCompliance)
    # bus, Pdc and phi are carried over
    @test h[1].bus == aggs[1].bus && h[1].Pdc == aggs[1].Pdc && h[1].φ == aggs[1].φ

    @test_throws ArgumentError BehaviourSpec(compliance = -0.1)
    @test_throws ArgumentError BehaviourSpec(compliance = 1.1)
    @test_throws ArgumentError BehaviourSpec(compliance = NaN)
    @test_throws ArgumentError BehaviourSpec(opt_out = -0.1)
    @test_throws ArgumentError BehaviourSpec(opt_out = 1.5)
    @test_throws ArgumentError BehaviourSpec(rebound = (W = 3, r = 0.5))
    @test_throws ArgumentError BehaviourSpec(rebound = (W = 0, r = 1.0))
    @test_throws ArgumentError BehaviourSpec(rebound = (W = 3, r = Inf))
    @test_throws ArgumentError BehaviourSpec(rebound = 3)
    @test_throws ArgumentError BehaviourSpec(nonsense = 1)
end

@testitem "behaviour: baseline_net_load is Pdc minus the baselines, deterministic" setup =
    [BehaviourFixtures, TwoBusFixtures] tags = [:behaviour] begin
    using TSODSO
    using TSODSO: baseline_net_load
    F = BehaviourFixtures
    T = F.T

    prof = generate_profiles(seed = TwoBusFixtures.SEED_2BUS + 2, T = T)
    Pdc = Float64[TwoBusFixtures.LOAD_SCALE_2BUS * p for p in prof.demand]
    e, h = F.ev(), F.hp()
    be, bh = F.baseline(e), F.baseline(h)
    wrapped = [
        TSODSO.Aggregator(
            2, 0.9, [PartialCompliance(e, 0.5, be.b, be.Ub), OptOut(h, bh.b, bh.Ub)], Pdc,
        ),
    ]
    nl = baseline_net_load(wrapped, T)
    @test length(nl) == 1 && length(nl[1]) == T
    # all devices wrapped: exactly Pdc minus the stored b vectors
    @test nl[1] == (Pdc[1:T] .- be.b) .- bh.b
    @test baseline_net_load(wrapped, T) == nl

    # plain aggregators (incl. storage and unwrapped flexible devices) are handled too
    plain = TwoBusFixtures.build_two_bus_aggregators(TwoBusFixtures.two_bus_feeder())
    @test apply_behaviour(plain, BehaviourSpec(); T = T) === plain
    n1 = baseline_net_load(plain, T)
    @test n1 == baseline_net_load(plain, T)
    @test length(n1) == 1 && length(n1[1]) == T && all(isfinite, n1[1])
    # sum over aggregators
    @test length(reduce(+, baseline_net_load([plain[1], plain[1]], T))) == T
end

@testitem "behaviour: wrapped two-bus population, centralized vs ADMM crossval, certificates pass (crossval)" setup =
    [BehaviourFixtures, TwoBusFixtures] tags = [:behaviour, :admm] begin
    using TSODSO, JuMP, LinearAlgebra
    F = BehaviourFixtures
    T = F.T

    # bands: 3 x observed max over 5 seeds x 2 constructions (header table)
    BAND_W = 2.08e-4
    BAND_L = 2.28e-5

    pdc(seed) = Float64[
        TwoBusFixtures.LOAD_SCALE_2BUS * p for p in generate_profiles(seed = seed + 2, T = T).demand
    ]
    function hand(seed)
        e, h, t = F.ev(), F.hp(), F.therm()
        be, bh, bt = F.baseline(e), F.baseline(h), F.baseline(t)
        devs = AbstractDevice[
            PartialCompliance(e, 0.5, be.b, be.Ub),
            OptOut(h, bh.b, bh.Ub),
            Rebound(PartialCompliance(t, 0.5, bt.b, bt.Ub), bt.b, 6, 1.0),
        ]
        return [TSODSO.Aggregator(2, 0.9, devs, pdc(seed))]
    end
    function spec(seed)
        base = [TSODSO.Aggregator(2, 0.9, AbstractDevice[F.ev(), F.hp(), F.therm()], pdc(seed))]
        return apply_behaviour(
            base,
            BehaviourSpec(compliance = 0.5, opt_out = 0.4, rebound = (W = 6, r = 1.0), seed = seed);
            T = T,
        )
    end
    function crossval(aggs)
        ctx, obj, _ = solve_welfare(
            TwoBusFixtures.two_bus_feeder(), ConvexBranchFlow(), aggs;
            T = T, λ₀ = F.SWING, allow_export = true,
        )
        dl = extract_dlmp(ctx; bus = 2, T = T)
        res = solve_admm(
            TwoBusFixtures.two_bus_feeder(), ConvexBranchFlow(), aggs;
            T = T, λ₀ = F.SWING, ρ = TwoBusFixtures.RHO_2BUS, allow_export = true,
        )
        ok = abs(res.welfare - obj) <= BAND_W && norm(vec(res.λ) - vec(dl)) <= BAND_L
        # certificates still pass on the wrapped population (storage_kind routing)
        ok &= isfinite(TSODSO.assert_ev_complementarity!(ctx; T = T))
        ok &= all(isfinite, extract_dlmp(ctx; bus = 2, T = T))
        return ok, ctx
    end
    for k in 0:4, mk in (hand, spec)
        ok, ctx = crossval(mk(TwoBusFixtures.SEED_2BUS + k))
        @test ok
        # the type-paired stash records the WRAPPER types in lockstep
        kinds = TSODSO.storage_kind.(ctx.agg_device_types[2])
        @test all(in((:ev, :none)), kinds)
    end
    @test TSODSO.storage_kind(typeof(hand(1)[1].devices[1])) === :ev
end
