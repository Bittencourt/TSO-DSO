# Seam: devices/HeatPump.jl
#
# Phase 43 plan 03 (DEV-08, DEV-10b). The HeatPump is the 2R2C ("TiTe") building thermal model:
# indoor-air Tin + envelope-mass Tem coupled by a Forward-Euler linear recursion with the ambient
# profile, an EXOGENOUS per-step COP vector (heat = COP[t]*p stays linear), a hard comfort band on
# Tin through T+1, a concave-quadratic comfort utility, and a joint two-state `terminal` kwarg.
# It is a FLEXIBLE LOAD (is_flexible_load = true), so its power-factor reactive draw rolls up
# through the Aggregator (eq. 3.23) and the ADMM default reactive mode resolves LIVE.
#
# Every item name contains "heatpump" so `occursin("heatpump", ti.name)` selects it.
#
# Signature under test:
#   HeatPump(bus, α_ie, α_ia, α_me, α_ma, β, Tmin, Tmax, Tem_min, Tem_max, Tin0, Tem0, Pmax, b,
#            Tout, COP; φ = nothing, terminal = nothing)
#
# (2R2C lineage: Kircher / Bacher-Madsen RC models -- cited at MEDIUM bibliographic confidence.)

# MEASUREMENT-BEFORE-GOLDEN (DEV-10b): the centralized-vs-ADMM crossval bands below were MEASURED
# (2026-11-02) on the HeatPump-only two-bus fixture (`TwoBusFixtures.two_bus_feeder`, T = 24,
# rho = RHO_2BUS, SWING price lambda0 = 1 (hours 18..24, 1..4) | 12 (hours 5..8) | 4 (else), pu power
# Pmax = 0.02, 2R2C (a_ie, a_ia, a_me, a_ma) = (0.1, 0.05, 0.05, 0.02), beta = 30, comfort band
# 19..23, envelope band 5..35, Tin0 = 21, Tem0 = 20, b = 0.05, Tout = 5 + 4 sin(2 pi (t-9)/24),
# COP[t] = 3 + 0.05 (Tout[t] - 5), aggregator phi = 0.90) across 5 seeds, `solve_welfare` (SOCP, default
# optimizer, reactive balance live) vs `solve_admm` (DEFAULT reactive mode = LIVE because the
# HeatPump is a flexible load; every run converges in iters = 2, dispatch is genuine: p hits Pmax,
# Tin touches the 19 lower band):
#
#   seed        |dWelfare|    |dLambda|_2 (T=24)   |dMu_q|_2 (T=24)    (|lambda_c|_2 ~ 27.04, |mu_c|_2 ~ 4e-4..6e-4)
#   20260719    3.993e-5      5.129e-6             2.484e-6
#   20260720    4.925e-5      5.082e-6             2.462e-6
#   20260721    2.734e-5      2.928e-6             1.418e-6
#   20260722    4.625e-5      4.652e-6             2.253e-6
#   20260723    2.832e-5      3.001e-6             1.453e-6
#   max         4.925e-5      5.129e-6             2.484e-6
#
# The bands are PINNED AT those observed maxima (rounded UP to 4 significant digits, never padded
# to a round number): welfare atol 4.926e-5; lambda ||.||_2 atol 5.130e-6; mu_q ||.||_2 atol 2.485e-6.

@testitem "heatpump: HeatPump constructor guards reject physics / stability violations" tags =
    [:heatpump] begin
    using TSODSO, JuMP

    T = 6
    # Valid parameterization: Euler-stable (α_ie+α_ia = 0.15 <= 1, α_me+α_ma = 0.07 <= 1).
    good(;
        aie = 0.1,
        aia = 0.05,
        ame = 0.05,
        ama = 0.02,
        β = 1.0,
        Tmin = 19.0,
        Tmax = 23.0,
        Emin = 10.0,
        Emax = 35.0,
        Tin0 = 21.0,
        Tem0 = 20.0,
        Pmax = 1.0,
        b = 1.0,
        φ = nothing,
        terminal = nothing,
    ) = TSODSO.HeatPump(
        2,
        aie,
        aia,
        ame,
        ama,
        β,
        Tmin,
        Tmax,
        Emin,
        Emax,
        Tin0,
        Tem0,
        Pmax,
        b,
        fill(5.0, T),
        fill(3.0, T);
        φ = φ,
        terminal = terminal,
    )

    @test good() isa TSODSO.AbstractDevice
    @test good() isa TSODSO.HeatPump{Float64}

    @test_throws ArgumentError good(Tmin = 23.0, Tmax = 19.0)      # comfort band order
    @test_throws ArgumentError good(Tmin = 21.0, Tmax = 21.0)
    @test_throws ArgumentError good(Emin = 35.0, Emax = 10.0)      # envelope band order
    @test_throws ArgumentError good(b = 0.0)                       # concavity
    @test_throws ArgumentError good(b = -1.0)
    @test_throws ArgumentError good(aie = -0.1)                    # sign guards
    @test_throws ArgumentError good(aia = -0.1)
    @test_throws ArgumentError good(ame = -0.1)
    @test_throws ArgumentError good(ama = -0.1)
    @test_throws ArgumentError good(β = 0.0)                       # heating must RAISE Tin
    @test_throws ArgumentError good(β = -1.0)
    @test_throws ArgumentError good(Pmax = 0.0)
    @test_throws ArgumentError good(Pmax = -1.0)
    @test_throws ArgumentError good(φ = 0.0)                       # φ ∈ (0, 1]
    @test_throws ArgumentError good(φ = 1.1)
    @test_throws ArgumentError good(Tin0 = 18.0)                   # IC outside comfort band
    @test_throws ArgumentError good(Tin0 = 24.0)
    @test_throws ArgumentError good(Tem0 = 5.0)                    # IC outside envelope band
    @test_throws ArgumentError good(Tem0 = 40.0)
    @test_throws ArgumentError good(aie = 0.6, aia = 0.5)          # Euler stability (air)
    @test_throws ArgumentError good(ame = 0.7, ama = 0.4)          # Euler stability (mass)
    @test_throws ArgumentError good(terminal = 30.0)               # pinned terminal outside band
    @test_throws ArgumentError good(terminal = :bogus)

    @test good(φ = 0.95).φ === 0.95
    @test good().φ === nothing

    # Mixed-type call (Int among Float64s) promotes to one common type.
    mixed = TSODSO.HeatPump(
        2,
        0.1,
        0.05,
        0.05,
        0.02,
        1,
        19,
        23,
        10,
        35,
        21,
        20,
        1,
        1,
        fill(5, T),
        fill(3.0, T),
    )
    @test mixed isa TSODSO.HeatPump{Float64}
    @test mixed.Pmax === 1.0
end

@testitem "heatpump: contribute! honors the aggregatable contract and closed-form 2R2C step" tags =
    [:heatpump] begin
    using TSODSO, JuMP

    T = 3
    aie, aia, ame, ama, β = 0.1, 0.05, 0.05, 0.02, 1.0
    Tin0, Tem0 = 21.0, 20.0
    Tout = fill(10.0, T)
    COP = [3.0, 3.5, 4.0]
    hp = TSODSO.HeatPump(
        2,
        aie,
        aia,
        ame,
        ama,
        β,
        19.0,
        23.0,
        10.0,
        35.0,
        Tin0,
        Tem0,
        1.0,
        1.0,
        Tout,
        COP,
    )

    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx = TSODSO.ModelContext(model)
    res = TSODSO.contribute!(hp, ctx; T = T)

    @test haskey(res, :vars) && haskey(res, :p_inject) && haskey(res, :utility)
    @test res.p_inject isa Vector{AffExpr}
    @test length(res.p_inject) == T
    @test res.utility isa QuadExpr
    # Active-only: the device writes NOTHING to residuals / objective.
    @test isempty(ctx.residuals)
    @test length(res.vars.Tin) == T + 1 && length(res.vars.Tem) == T + 1
    # Sign convention: a heating load is a NEGATIVE injection −p.
    for t in 1:T
        @test res.p_inject[t] == -res.vars.p[t]
    end

    # Fix p (solve only to read the determined states) and compare with the hand Euler update.
    pfix = [0.4, 0.0, 0.0]
    for t in 1:T
        fix(res.vars.p[t], pfix[t]; force = true)
    end
    @objective(model, Max, res.utility)
    TSODSO.assert_solved!(model; dual = false, allow_local = false)
    Tin = Float64[value(x) for x in res.vars.Tin]
    Tem = Float64[value(x) for x in res.vars.Tem]
    @test Tin[1] ≈ Tin0 atol = 1e-9
    @test Tem[1] ≈ Tem0 atol = 1e-9
    for t in 1:T
        exp_in =
            Tin[t] +
            aie * (Tem[t] - Tin[t]) +
            aia * (Tout[t] - Tin[t]) +
            β * COP[t] * pfix[t]
        exp_em = Tem[t] + ame * (Tin[t] - Tem[t]) + ama * (Tout[t] - Tem[t])
        @test Tin[t + 1] ≈ exp_in atol = 1e-8
        @test Tem[t + 1] ≈ exp_em atol = 1e-8
    end
    # Absolute hand-computed first step: 21 + 0.1(−1) + 0.05(−11) + 1·3·0.4 = 21.55
    @test Tin[2] ≈ 21.55 atol = 1e-8
    # 20 + 0.05(1) + 0.02(−10) = 19.85
    @test Tem[2] ≈ 19.85 atol = 1e-8
end

@testitem "heatpump: comfort band holds through T+1, draw within [0, Pmax], terminal variants" tags =
    [:heatpump] begin
    using TSODSO, JuMP

    T = 6
    Tin0, Tem0 = 21.0, 20.0
    function solve_hp(; terminal = nothing, price = 1.0, Tem0 = 20.0, tout = 15.0)
        hp = TSODSO.HeatPump(
            2,
            0.1,
            0.05,
            0.05,
            0.02,
            1.0,
            19.0,
            23.0,
            10.0,
            35.0,
            Tin0,
            Tem0,
            1.0,
            1.0,
            fill(tout, T),
            fill(3.0, T);
            terminal = terminal,
        )
        model = Model(TSODSO.select_optimizer(TSODSO.QP()))
        ctx = TSODSO.ModelContext(model)
        res = TSODSO.contribute!(hp, ctx; T = T)
        @objective(model, Max, res.utility + sum(price * res.p_inject[t] for t in 1:T))
        TSODSO.assert_solved!(model; dual = true, allow_local = false)
        return res
    end

    res = solve_hp()
    for t in 1:(T + 1)
        @test 19.0 - 1e-7 <= value(res.vars.Tin[t]) <= 23.0 + 1e-7
        @test 10.0 - 1e-7 <= value(res.vars.Tem[t]) <= 35.0 + 1e-7
    end
    # Variable bounds themselves reach T+1 (whole-horizon closure rule).
    @test lower_bound(res.vars.Tin[T + 1]) == 19.0
    @test upper_bound(res.vars.Tin[T + 1]) == 23.0
    @test lower_bound(res.vars.Tem[T + 1]) == 10.0
    @test upper_bound(res.vars.Tem[T + 1]) == 35.0
    for t in 1:T
        @test -1e-8 <= value(res.vars.p[t]) <= 1.0 + 1e-8
    end

    # :cyclic ⇒ both states return to their own IC Parameters.
    rc = solve_hp(terminal = :cyclic)
    @test value(rc.vars.Tin[T + 1]) ≈ Tin0 atol = 1e-6
    @test value(rc.vars.Tem[T + 1]) ≈ Tem0 atol = 1e-6

    # Real ⇒ BOTH states pinned to the value (joint terminal, A3).
    rr = solve_hp(terminal = 20.5, Tem0 = 21.0, tout = 17.0)
    @test value(rr.vars.Tin[T + 1]) ≈ 20.5 atol = 1e-6
    @test value(rr.vars.Tem[T + 1]) ≈ 20.5 atol = 1e-6

    # nothing ⇒ both free: with cheap-comfort pricing they are NOT forced to the IC.
    rn = solve_hp(price = 5.0)
    @test !(value(rn.vars.Tin[T + 1]) ≈ Tin0 && value(rn.vars.Tem[T + 1]) ≈ Tem0)
end

@testitem "heatpump: Tout / COP shorter than the horizon throw at contribute!" tags =
    [:heatpump] begin
    using TSODSO, JuMP

    T = 6
    mk(Tout, COP) = TSODSO.HeatPump(
        2,
        0.1,
        0.05,
        0.05,
        0.02,
        1.0,
        19.0,
        23.0,
        10.0,
        35.0,
        21.0,
        20.0,
        1.0,
        1.0,
        Tout,
        COP,
    )
    ctx() = TSODSO.ModelContext(Model())
    @test_throws ArgumentError TSODSO.contribute!(
        mk(fill(5.0, T), fill(3.0, T - 1)),
        ctx();
        T = T,
    )
    @test_throws ArgumentError TSODSO.contribute!(
        mk(fill(5.0, T - 1), fill(3.0, T)),
        ctx();
        T = T,
    )
    # Exactly length T is accepted.
    @test TSODSO.contribute!(mk(fill(5.0, T), fill(3.0, T)), ctx(); T = T) isa NamedTuple
end

@testitem "heatpump: flexible-load classification, LIVE reactive default via traits, :Rq roll-up" tags =
    [:heatpump] begin
    using TSODSO, JuMP

    T = 4
    bus = 2
    mk(; φ = nothing) = TSODSO.HeatPump(
        bus,
        0.1,
        0.05,
        0.05,
        0.02,
        1.0,
        19.0,
        23.0,
        10.0,
        35.0,
        21.0,
        20.0,
        1.0,
        1.0,
        fill(5.0, T),
        fill(3.0, T);
        φ = φ,
    )
    @test TSODSO.is_flexible_load(mk()) === true
    @test TSODSO.has_reactive_decision(mk()) === true

    # Roll-up: the heat pump's p carries the power-factor reactive term (eq. 3.23).
    for (φ_dev, φ_agg) in ((nothing, 0.9), (0.8, 0.9))
        hp = mk(φ = φ_dev)
        agg = TSODSO.Aggregator(bus, φ_agg, [hp], zeros(T))
        ctx = TSODSO.ModelContext(Model())
        TSODSO.contribute!(agg, ctx; T = T)
        Rq = ctx.residuals[:Rq]
        p = ctx.agg_device_vars[bus][1].p
        φ_used = φ_dev === nothing ? φ_agg : φ_dev
        tanφ = sqrt(1 - φ_used^2) / φ_used
        nonzero = 0
        for t in 1:T
            c = get(Rq[bus, t].terms, p[t], 0.0)
            @test c ≈ -tanφ atol = 1e-12     # p_inject = −p ⇒ coefficient −tanφ
            nonzero += !iszero(c)
        end
        @test nonzero == T
    end
end

@testitem "heatpump: zero binary / zero integer variables, exact variable count" tags =
    [:heatpump] begin
    using TSODSO, JuMP

    T = 5
    hp = TSODSO.HeatPump(
        2,
        0.1,
        0.05,
        0.05,
        0.02,
        1.0,
        19.0,
        23.0,
        10.0,
        35.0,
        21.0,
        20.0,
        1.0,
        1.0,
        fill(5.0, T),
        fill(3.0, T),
    )
    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx = TSODSO.ModelContext(model)
    TSODSO.contribute!(hp, ctx; T = T)
    vars = all_variables(model)
    # p (T) + Tin (T+1) + Tem (T+1) + Tin0, Tem0 Parameters (2) = 3T + 4.
    @test length(vars) == 3T + 4
    @test count(is_binary, vars) == 0
    @test count(is_integer, vars) == 0
end

@testitem "heatpump: two instances contribute to ONE model (anonymous JuMP objects)" tags =
    [:heatpump] begin
    using TSODSO, JuMP

    T = 6
    mk() = TSODSO.HeatPump(
        2,
        0.1,
        0.05,
        0.05,
        0.02,
        1.0,
        19.0,
        23.0,
        10.0,
        35.0,
        21.0,
        20.0,
        1.0,
        1.0,
        fill(5.0, T),
        fill(3.0, T);
        terminal = :cyclic,
    )
    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx = TSODSO.ModelContext(model)
    r1 = TSODSO.contribute!(mk(), ctx; T = T)   # would throw on a named-container collision
    r2 = TSODSO.contribute!(mk(), ctx; T = T)
    @test length(all_variables(model)) == 2 * (3T + 4)
    @test r1.vars.Tin0 != r2.vars.Tin0
    @test isempty(object_dictionary(model))
end

# --- centralized-vs-ADMM crossval (gate-then-golden), bands pinned from the header table ---

@testitem "heatpump: centralized vs ADMM crossval, LIVE reactive default, measured bands pinned (crossval)" setup =
    [TwoBusFixtures] tags = [:heatpump, :admm] begin
    using TSODSO, JuMP, LinearAlgebra

    T = TwoBusFixtures.T
    λswing = [(t in 5:8) ? 12.0 : ((t >= 18 || t <= 4) ? 1.0 : 4.0) for t in 1:T]
    Tout = [5.0 + 4.0 * sin(2π * (t - 9) / 24) for t in 1:T]
    COP = [3.0 + 0.05 * (Tout[t] - 5.0) for t in 1:T]

    function hp_aggs(seed::Integer)
        prof = generate_profiles(seed = seed + 2, T = T)
        Pdc = Float64[TwoBusFixtures.LOAD_SCALE_2BUS * p for p in prof.demand]
        hp = TSODSO.HeatPump(
            2,
            0.1,
            0.05,
            0.05,
            0.02,
            30.0,
            19.0,
            23.0,
            5.0,
            35.0,
            21.0,
            20.0,
            0.02,
            0.05,
            Tout,
            COP,
        )
        return [TSODSO.Aggregator(2, 0.90, [hp], Pdc)]
    end

    band_W, band_λ, band_μ = 4.926e-5, 5.130e-6, 2.485e-6

    for k in 0:4
        seed = TwoBusFixtures.SEED_2BUS + k
        ctx, obj, _ = solve_welfare(
            TwoBusFixtures.two_bus_feeder(),
            ConvexBranchFlow(),
            hp_aggs(seed);
            T = T,
            λ₀ = λswing,
            allow_export = true,
        )
        dl = extract_dlmp(ctx; bus = 2, T = T)
        mc = TSODSO.extract_reactive_dlmp(ctx; bus = 2, T = T)
        res = solve_admm(
            TwoBusFixtures.two_bus_feeder(),
            ConvexBranchFlow(),
            hp_aggs(seed);
            T = T,
            λ₀ = λswing,
            ρ = TwoBusFixtures.RHO_2BUS,
            allow_export = true,
        )
        @test abs(res.welfare - obj) <= band_W
        @test norm(vec(res.λ) - vec(dl)) <= band_λ
        @test norm(vec(res.mu_q) - vec(mc)) <= band_μ
        # Trait exercised end-to-end: a flexible-load member resolves the default reactive mode LIVE.
        @test res.reactive_consensus_mode === ReactiveMode.LIVE
        @test res.mu_q !== nothing
        # Dispatch is genuine (non-degenerate certificate): the heat pump actually runs.
        hpv = ctx.agg_device_vars[2][1]
        @test maximum(value.(hpv.p)) > 0.5 * 0.02
        # Structural identity, exact: the comfort band holds through T+1 in the centralized solve.
        @test all(19.0 - 1e-7 <= value(x) <= 23.0 + 1e-7 for x in hpv.Tin)
        @test ctx.agg_device_types[2] == DataType[TSODSO.HeatPump{Float64}]
    end
end
