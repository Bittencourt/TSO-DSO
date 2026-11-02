# Seam: devices/SmartInverterPV.jl
#
# Phase 43 plan 04 (DEV-09, DEV-10b). SmartInverterPV is PV with a smart-inverter reactive
# capability, as a SEPARATE device (the FourQuadBESS precedent; PVBattery is NOT widened):
# curtailable `pv_used[t] <= Ppv[t]` plus a sign-free `q[t]`, tied by ONE ANONYMOUS per-t
# apparent-power cone `[S_inv, pv_used[t], q[t]] in SecondOrderCone()`. Neither pv_used nor q
# carries a device utility term: both are priced ONLY through the network balances.
#
# Every item name contains "smartinverterpv" so `occursin("smartinverterpv", ti.name)` selects it.
#
# Signature under test:  SmartInverterPV(bus, S_inv, Ppv)

# MEASUREMENT-BEFORE-GOLDEN (DEV-10b): the centralized-vs-ADMM crossval bands below were MEASURED
# (2026-11-02) on the SmartInverterPV-only two-bus fixture (`TwoBusFixtures.two_bus_feeder`, T = 24,
# rho = RHO_2BUS, SWING price lambda0 = 1 (hours 18..24, 1..4) | 12 (hours 5..8) | 4 (else), load
# Pdc = 0.02*demand, Ppv = 0.06*pv profile, S_inv = 0.03 pu, aggregator phi = 0.90) across 5 seeds,
# `solve_welfare` (SOCP, reactive balance live) vs `solve_admm` (DEFAULT reactive mode = LIVE because
# the device carries `has_reactive_decision`; every run converges in iters = 2; dispatch is genuine:
# pv_used reaches S_inv = 0.03, 1-5 hours are curtailed below availability, and the centralized q
# reaches ~0.0087 (it covers the aggregator's reactive load) with |mu_c|_2 ~ 5e-5..1.2e-4):
#
#   seed        |dWelfare|    |dLambda|_2 (T=24)   |dMu_q|_2 (T=24)
#   20260719    1.208e-5      2.129e-6             2.665e-6
#   20260720    3.167e-5      3.910e-6             2.003e-6
#   20260721    7.272e-7      1.439e-6             3.788e-6
#   20260722    1.061e-5      2.974e-6             2.195e-6
#   20260723    6.229e-6      1.788e-6             4.621e-6
#   max         3.167e-5      3.910e-6             4.621e-6
#
# The bands are PINNED AT those observed maxima (rounded UP to 4 significant digits, never padded
# to a round number): welfare atol 3.168e-5; lambda ||.||_2 atol 3.911e-6; mu_q ||.||_2 atol 4.622e-6.
#
# ROUTING NOTE (T-43-04-1): an explicit OFF/CERTIFIED reactive mode on a population containing a
# has_reactive_decision device FAILS LOUD (DsoOpt.jl guard) -- the device's q would otherwise be silently
# dropped from the network model. So the "routing proof" below is: (a) CERTIFIED throws, never
# silently bypasses; (b) LIVE publishes a no-slack :balance_q certificate that prices the device's q;
# (c) the centralized :Rq carries the q_inject variable through the Aggregator (no direct :Rq write).

@testitem "smartinverterpv: constructor guards reject degenerate cone / negative profile" tags =
    [:smartinverterpv] begin
    using TSODSO, JuMP

    @test TSODSO.SmartInverterPV(2, 1.0, [0.0, 0.5, 1.0]) isa TSODSO.AbstractDevice
    @test TSODSO.SmartInverterPV(2, 1.0, [0.0, 0.5, 1.0]) isa
          TSODSO.SmartInverterPV{Float64}
    @test_throws ArgumentError TSODSO.SmartInverterPV(2, 0.0, [0.5])
    @test_throws ArgumentError TSODSO.SmartInverterPV(2, -1.0, [0.5])
    @test_throws ArgumentError TSODSO.SmartInverterPV(2, 1.0, [0.5, -0.1])

    # Mixed-type call (Int S_inv, Int profile) promotes to one common type.
    mixed = TSODSO.SmartInverterPV(2, 1, [0, 1])
    @test mixed isa TSODSO.SmartInverterPV{Float64} || mixed isa TSODSO.SmartInverterPV{Int}
    mixed2 = TSODSO.SmartInverterPV(2, 1, [0.0, 1.0])
    @test mixed2 isa TSODSO.SmartInverterPV{Float64}
    @test mixed2.S_inv === 1.0
end

@testitem "smartinverterpv: contribute! widened 4-tuple contract, zero utility, no residual writes" tags =
    [:smartinverterpv] begin
    using TSODSO, JuMP

    T = 4
    d = TSODSO.SmartInverterPV(2, 1.0, fill(0.5, T))
    model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
    ctx = TSODSO.ModelContext(model)
    res = TSODSO.contribute!(d, ctx; T = T)

    @test propertynames(res) == (:vars, :p_inject, :q_inject, :utility)
    @test res.q_inject === res.vars.q
    @test res.q_inject isa Vector{VariableRef}
    @test length(res.vars.pv_used) == T && length(res.vars.q) == T
    @test res.p_inject isa Vector{AffExpr}
    for t in 1:T
        @test res.p_inject[t] == 1.0 * res.vars.pv_used[t]
    end
    # Active/reactive side writes NOTHING to residuals or the objective.
    @test isempty(ctx.residuals)
    @test isempty(ctx.objective.terms)

    # Zero-utility-on-q invariant: the utility is identically zero (no term mentions q or pv_used).
    @test res.utility isa QuadExpr
    @test isempty(res.utility.terms)
    @test isempty(res.utility.aff.terms)
    @test iszero(res.utility.aff.constant)
    # q is sign-free (no bounds), pv_used only lower-bounded at 0.
    for t in 1:T
        @test !has_lower_bound(res.vars.q[t]) && !has_upper_bound(res.vars.q[t])
        @test lower_bound(res.vars.pv_used[t]) == 0.0
    end
end

@testitem "smartinverterpv: anonymity -- no named JuMP objects, two instances on one model" tags =
    [:smartinverterpv] begin
    using TSODSO, JuMP

    T = 3
    mk() = TSODSO.SmartInverterPV(2, 1.0, fill(0.5, T))
    model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
    ctx = TSODSO.ModelContext(model)
    TSODSO.contribute!(mk(), ctx; T = T)
    @test isempty(object_dictionary(model))
    # A second instance would throw on any named-container collision.
    TSODSO.contribute!(mk(), ctx; T = T)
    @test isempty(object_dictionary(model))
    @test length(all_variables(model)) == 2 * 2T
end

@testitem "smartinverterpv: apparent-power cone binds (tight S_inv forces q support and curtailment)" tags =
    [:smartinverterpv] begin
    using TSODSO, JuMP

    T = 4
    Ppv = fill(1.0, T)
    function solve_sipv(S_inv; qprice)
        d = TSODSO.SmartInverterPV(2, S_inv, Ppv)
        model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
        ctx = TSODSO.ModelContext(model)
        res = TSODSO.contribute!(d, ctx; T = T)
        @objective(
            model,
            Max,
            sum(1.0 * res.p_inject[t] + qprice * res.q_inject[t] for t in 1:T)
        )
        TSODSO.assert_solved!(model; dual = false, allow_local = false)
        return res
    end

    # Tight cone with a reactive value: p and q share the S_inv budget (p = q = S/sqrt(2)).
    tight = solve_sipv(0.8; qprice = 1.0)
    for t in 1:T
        p = value(tight.vars.pv_used[t])
        q = value(tight.vars.q[t])
        @test abs(q) > 1e-3
        @test p < 1.0 - 1e-3                      # curtailed below availability
        @test p^2 + q^2 ≈ 0.8^2 atol = 1e-5       # cone binds
    end
    # No reactive value: q relaxes to the price-neutral optimum, full PV is used.
    neutral = solve_sipv(10.0; qprice = 0.0)
    for t in 1:T
        @test value(neutral.vars.pv_used[t]) ≈ 1.0 atol = 1e-6
    end
    # Sign-free: a negative reactive price drives q negative.
    neg = solve_sipv(0.8; qprice = -1.0)
    @test all(value(neg.vars.q[t]) < -1e-3 for t in 1:T)
end

@testitem "smartinverterpv: zero binary / zero integer variables, exact variable count" tags =
    [:smartinverterpv] begin
    using TSODSO, JuMP

    T = 5
    d = TSODSO.SmartInverterPV(2, 1.0, fill(0.5, T))
    model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
    ctx = TSODSO.ModelContext(model)
    TSODSO.contribute!(d, ctx; T = T)
    vars = all_variables(model)
    @test length(vars) == 2T                   # pv_used (T) + q (T)
    @test count(is_binary, vars) == 0
    @test count(is_integer, vars) == 0
end

@testitem "smartinverterpv: profile shorter than horizon throws at contribute!" tags =
    [:smartinverterpv] begin
    using TSODSO, JuMP

    T = 6
    ctx() = TSODSO.ModelContext(Model())
    @test_throws ArgumentError TSODSO.contribute!(
        TSODSO.SmartInverterPV(2, 1.0, fill(0.5, T - 1)),
        ctx();
        T = T,
    )
    @test TSODSO.contribute!(TSODSO.SmartInverterPV(2, 1.0, fill(0.5, T)), ctx(); T = T) isa
          NamedTuple
end

@testitem "smartinverterpv: classification -- reactive decision yes, flexible load no" tags =
    [:smartinverterpv] begin
    using TSODSO, JuMP

    d = TSODSO.SmartInverterPV(2, 1.0, fill(0.5, 3))
    @test TSODSO.has_reactive_decision(d) === true
    @test TSODSO.is_flexible_load(d) === false
    @test TSODSO.storage_kind(d) === :none

    # Aggregator roll-up: q_inject enters :Rq (+1 coefficient) via the existing hasproperty branch,
    # with NO power-factor term on the PV's own active injection (not a flexible load).
    T = 3
    agg = TSODSO.Aggregator(2, 0.9, [d], zeros(T))
    ctx = TSODSO.ModelContext(Model())
    TSODSO.contribute!(agg, ctx; T = T)
    Rq = ctx.residuals[:Rq]
    q = ctx.agg_device_vars[2][1].q
    p = ctx.agg_device_vars[2][1].pv_used
    for t in 1:T
        @test get(Rq[2, t].terms, q[t], 0.0) ≈ 1.0 atol = 1e-12
        @test get(Rq[2, t].terms, p[t], 0.0) == 0.0
    end
end

# --- centralized-vs-ADMM crossval (gate-then-golden), bands pinned from the header table ---

@testitem "smartinverterpv: centralized vs ADMM crossval, LIVE reactive default, measured bands pinned (crossval)" setup =
    [TwoBusFixtures] tags = [:smartinverterpv, :admm] begin
    using TSODSO, JuMP, LinearAlgebra

    T = TwoBusFixtures.T
    S_inv = 0.03
    λswing = [(t in 5:8) ? 12.0 : ((t >= 18 || t <= 4) ? 1.0 : 4.0) for t in 1:T]

    function sipv_aggs(seed::Integer)
        prof = generate_profiles(seed = seed + 2, T = T)
        Pdc = Float64[TwoBusFixtures.LOAD_SCALE_2BUS * p for p in prof.demand]
        Ppv = Float64[0.06 * p for p in prof.pv]
        return [Aggregator(2, 0.90, [TSODSO.SmartInverterPV(2, S_inv, Ppv)], Pdc)], Ppv
    end

    band_W, band_λ, band_μ = 3.168e-5, 3.911e-6, 4.622e-6

    for k in 0:4
        seed = TwoBusFixtures.SEED_2BUS + k
        aggs, Ppv = sipv_aggs(seed)
        ctx, obj, _ = solve_welfare(
            TwoBusFixtures.two_bus_feeder(),
            ConvexBranchFlow(),
            aggs;
            T = T,
            λ₀ = λswing,
            allow_export = true,
        )
        dl = extract_dlmp(ctx; bus = 2, T = T)
        mc = TSODSO.extract_reactive_dlmp(ctx; bus = 2, T = T)
        aggs2, _ = sipv_aggs(seed)
        res = solve_admm(
            TwoBusFixtures.two_bus_feeder(),
            ConvexBranchFlow(),
            aggs2;
            T = T,
            λ₀ = λswing,
            ρ = TwoBusFixtures.RHO_2BUS,
            allow_export = true,
        )
        @test abs(res.welfare - obj) <= band_W
        @test norm(vec(res.λ) - vec(dl)) <= band_λ
        @test norm(vec(res.mu_q) - vec(mc)) <= band_μ
        # Trait exercised end-to-end: the device resolves the default reactive mode LIVE.
        @test res.reactive_consensus_mode === ReactiveMode.LIVE
        @test res.mu_q !== nothing
        # Dispatch is genuine (non-degenerate): PV runs, reactive support is used, cone respected.
        v = ctx.agg_device_vars[2][1]
        pv = value.(v.pv_used)
        q = value.(v.q)
        @test maximum(pv) > 0.5 * S_inv
        @test maximum(abs.(q)) > 1e-3
        for t in 1:T
            @test pv[t] <= Ppv[t] + 1e-7
            @test pv[t]^2 + q[t]^2 <= S_inv^2 + 1e-7   # apparent-power cone holds (exact identity)
        end
        @test ctx.agg_device_types[2] == DataType[TSODSO.SmartInverterPV{Float64}]
    end
end

@testitem "smartinverterpv: reactive routing proof -- CERTIFIED fails loud, LIVE certifies :balance_q, q enters :Rq via the Aggregator (routing)" setup =
    [TwoBusFixtures] tags = [:smartinverterpv, :admm] begin
    using TSODSO, JuMP

    T = TwoBusFixtures.T
    prof = generate_profiles(seed = TwoBusFixtures.SEED_2BUS + 2, T = T)
    Pdc = Float64[TwoBusFixtures.LOAD_SCALE_2BUS * p for p in prof.demand]
    Ppv = Float64[0.06 * p for p in prof.pv]
    mk() = [Aggregator(2, 0.90, [TSODSO.SmartInverterPV(2, 0.03, Ppv)], Pdc)]
    λ₀ = TwoBusFixtures.two_bus_lambda0()

    # (a) An explicit non-LIVE mode must NOT silently drop the device's q: it throws.
    for mode in (ReactiveMode.OFF, ReactiveMode.CERTIFIED)
        @test_throws ArgumentError solve_admm(
            TwoBusFixtures.two_bus_feeder(),
            ConvexBranchFlow(),
            mk();
            T = T,
            λ₀ = λ₀,
            ρ = TwoBusFixtures.RHO_2BUS,
            allow_export = true,
            reactive_consensus = mode,
        )
    end

    # (b) LIVE: the published :balance_q carries no hidden slack (the no-slack certificate).
    res = solve_admm(
        TwoBusFixtures.two_bus_feeder(),
        ConvexBranchFlow(),
        mk();
        T = T,
        λ₀ = λ₀,
        ρ = TwoBusFixtures.RHO_2BUS,
        allow_export = true,
        reactive_consensus = ReactiveMode.LIVE,
    )
    @test res.reactive_consensus_mode === ReactiveMode.LIVE
    balance_q = res.dso_ctx.constraints[:balance_q]
    max_slack = maximum(
        abs(assert_no_slack(res.dso_ctx.model, balance_q[j, t]; atol = 1e-6)) for
        j in 1:size(balance_q, 1), t in 1:size(balance_q, 2)
    )
    @test max_slack <= 1e-6

    # (c) Centralized: the device's q variable reaches the network ONLY as the Aggregator's +1 :Rq
    # coefficient (never a direct :Rq write by the device) and its reactive dual is the published mu.
    ctx, _, _ = solve_welfare(
        TwoBusFixtures.two_bus_feeder(),
        ConvexBranchFlow(),
        mk();
        T = T,
        λ₀ = λ₀,
        allow_export = true,
    )
    v = ctx.agg_device_vars[2][1]
    Rq = ctx.residuals[:Rq]
    for t in 1:T
        @test get(Rq[2, t].terms, v.q[t], 0.0) ≈ 1.0 atol = 1e-12
    end
end
