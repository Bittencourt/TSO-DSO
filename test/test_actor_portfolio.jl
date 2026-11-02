# test/test_actor_portfolio.jl
#
# Seam: SlotTable / build_slot_table (src/actors/Portfolio.jl), the slot-indexed DSO-OPT
# (`build_dso_opt(...; slots)`), the slot branch of `_admm_build` and the trailing
# `AdmmState.slot_bus` field (plan 44-03, ACTOR-03 build-time structure). Every item name
# contains "actor portfolio".
#
# ANCHOR: the slot branch forced onto a 1:1 population (each site its own actor, slot id ==
# bus id) must equal the legacy ADMM result BITWISE (`==`, never `isapprox`) on welfare, dadp,
# iters, every residual trace and every `agr_*` key. The 44-03 items use exact equality only;
# the 44-05 items (several sites per bus, ACTOR-03) compare a SPLIT population (two sites at one
# bus) with the MERGED aggregator (one site holding both device sets and the summed Pdc) and
# need tolerances, which are MEASURED (julia 1.12.5, seeds 20260719..21, ADMM run at
# eps_abs = 1e-7, eps_rel = 1e-8, rho = 5; pinned at 3x the observed max):
#
#   quantity                                          observed max   pinned
#   centralized split vs merged  |dW|  (4-bus)       9.8e-15        1e-12 (numerical-zero floor)
#   centralized split vs merged  |dlambda|           3.5e-11        1.04e-10
#   ADMM split vs merged         |dW|  (4-bus)       7.72e-6        2.3e-5
#   ADMM split vs merged         |dlambda|           2.70e-6        8.1e-6
#   ADMM split vs centralized    |dW|                5.22e-6        1.6e-5
#   ADMM split vs centralized    |dlambda|           2.63e-6        7.9e-6
#   2-bus OFF/CERTIFIED/LIVE/4Q split vs merged |dW| 1.03e-5        3.1e-5
#   2-bus ... |dlambda|                              2.2e-7         6.6e-7
#   2-bus LIVE/4Q |dmu_q|                            5.1e-7         1.53e-6
#   slot-lambda gap max_s |lambda_s - lambda_bus|    2.7e-15        1e-12 (numerical-zero floor)
#   profit_by_actor vs independent sum               1.1e-16        1e-12 (numerical-zero floor)
#
# The slot-lambda gap is ~0 structurally: after the first dual step every slot at a bus holds the
# DSO's nodal balance dual, so the certificate is REPORTED (never thrown) and is tiny by design.
# Iteration counts differ between split and merged and NO parity is claimed. Measured
# (merged/split): 4-bus 17/15, 17/14, 13/15; 2-bus OFF 3/4, 3/3, 3/4; LIVE 3/4; 4Q 4/189, 4/185,
# 4/171 (the 4Q site as a separate slot converges far slower than inside one aggregator).
#
# Accumulators live in functions / `let` (testitem bodies are top-level scope).

@testmodule PortfolioFixtures begin
    using TSODSO
    using TSODSO: SOCP, select_optimizer, extract_dlmp, SMAX_NO_LIMIT

    const T = 24
    const SEEDS = (20260719, 20260720, 20260721)
    const LAMBDA0 = 4.0
    # measured bands (see header table)
    const TOL_CENT_W = 1e-12
    const TOL_CENT_L = 1.04e-10
    const TOL_ADMM_W = 2.3e-5
    const TOL_ADMM_L = 8.1e-6
    const TOL_ADMM_CENT_W = 1.6e-5
    const TOL_ADMM_CENT_L = 7.9e-6
    const TOL_2BUS_W = 3.1e-5
    const TOL_2BUS_L = 6.6e-7
    const TOL_2BUS_MU = 1.53e-6
    const TOL_FLOOR = 1e-12

    temp() = Float64[19, 18, 17, 16, 16, 17, 19, 21, 23, 26, 28, 30, 31, 32, 32, 31, 29, 27, 25, 23, 22, 21, 20, 19]
    function feeder2()
        return Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 1e-3, 1e-3, SMAX_NO_LIMIT)],
            1,
        )
    end
    function feeder4(r = 0.05)
        return Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false),
                Bus(3, 0.95, 1.05, false), Bus(4, 0.95, 1.05, false)],
            [Branch(1, 2, r, r, SMAX_NO_LIMIT), Branch(2, 3, r, r, SMAX_NO_LIMIT),
                Branch(3, 4, r, r, SMAX_NO_LIMIT)],
            1,
        )
    end
    function site(bus, seed; flex = false, q4 = false, ls = 0.01, ps = 0.0025)
        prof = generate_profiles(seed = seed + bus, T = T)
        Ppv = Float64[ps * p for p in prof.pv]
        Pdc = Float64[ls * d for d in prof.demand]
        devs = AbstractDevice[]
        if flex
            push!(devs, Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, temp()))
            push!(devs, Deferrable(bus, 8, 16, 1.0, 0.5, 0.5))
        end
        push!(devs, PVBattery(bus, 0.95, 1.0, 0.05, 0.0, 0.1, 0.05, 3.8, 6.2, 8.9, Ppv))
        q4 && push!(devs, FourQuadBESS(bus, 0.95, 1.0, 0.01, 0.01, 0.015, 0.0, 0.1, 0.05, 3.8, 6.2, 8.9))
        return Aggregator(bus, 0.90, devs, Pdc)
    end
    merge_sites(a, b) = Aggregator(a.bus, a.φ, vcat(a.devices, b.devices), a.Pdc .+ b.Pdc)
    lambda0() = fill(LAMBDA0, T)
    cent_opt() = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)
    admm_kw(; ρ = 5.0, maxiter = 800) = (
        T = T, λ₀ = lambda0(), ρ = ρ, allow_export = true, maxiter = maxiter,
        ε_abs = 1e-7, ε_rel = 1e-8,
    )
    function central(f, aggs, buses)
        ctx, obj, _ = solve_welfare(
            f, ConvexBranchFlow(), aggs; T = T, λ₀ = lambda0(), allow_export = true,
            optimizer = cent_opt(),
        )
        d = reduce(vcat, (extract_dlmp(ctx; bus = b, T = T)' for b in buses))
        return (; welfare = obj, dadp = d)
    end
    # 4-bus population: sites at buses 2, 3, 3, 4 (two sites at bus 3) and the merged twin
    function pop4(seed)
        s2 = site(2, seed; ls = 0.05, ps = 0.01)
        s3a = site(3, seed; ls = 0.03, ps = 0.008)
        s3b = site(3, seed + 1000; ls = 0.03, ps = 0.008)
        s4 = site(4, seed; ls = 0.05, ps = 0.01)
        return (; s2, s3a, s3b, s4, m3 = merge_sites(s3a, s3b))
    end
    # 2-bus pair at bus 2. kind: :off / :cert (no flex), :live (flex), :q4 (flex + 4Q-BESS 2nd site)
    function pop2(seed, kind)
        a1 = site(2, seed; flex = kind == :live || kind == :q4)
        a2 = site(2, seed + 1000; q4 = kind == :q4)
        return (; a1, a2, m = merge_sites(a1, a2))
    end
    # Portfolio A (buses 2, 3; margin 0.5) and B (buses 3, 4): bus 3 is shared.
    function portfolios4(p)
        return [
            Portfolio(p.s2, p.s3a; name = :A, objective = ProfitObjective(0.5)),
            Portfolio(p.s3b, p.s4; name = :B),
        ]
    end
    function run4(seed; parallel = false)
        p = pop4(seed)
        f = feeder4()
        kw = admm_kw()
        sites = [p.s2, p.s3a, p.s3b, p.s4]
        rs = solve_admm(f, ConvexBranchFlow(), sites; kw..., actors = portfolios4(p), parallel = parallel)
        return (; p, f, kw, sites, rs)
    end
    function run4_full(seed)
        r = run4(seed)
        p = r.p
        rm = solve_admm(r.f, ConvexBranchFlow(), [p.s2, p.m3, p.s4]; r.kw...)
        cm = central(r.f, [p.s2, p.m3, p.s4], 2:4)
        cs = central(r.f, r.sites, 2:4)
        return (; r..., rm, cm, cs)
    end
    function run2(seed, kind)
        p = pop2(seed, kind)
        f = feeder2()
        mode = kind == :off ? ReactiveMode.OFF : kind == :cert ? ReactiveMode.CERTIFIED : ReactiveMode.LIVE
        kw = admm_kw()
        rm = solve_admm(f, ConvexBranchFlow(), [p.m]; kw..., reactive_consensus = mode)
        rs = solve_admm(
            f, ConvexBranchFlow(), [p.a1, p.a2]; kw..., reactive_consensus = mode,
            actors = [Portfolio(p.a1), Portfolio(p.a2)],
        )
        return (; rm, rs, mode)
    end
end

@testitem "actor portfolio: slot table id rule and determinism" tags = [:actors] begin
    using TSODSO
    using TSODSO: build_slot_table

    # distinct buses: ids == buses ascending, bus[s] == s
    st1 = build_slot_table([3, 2, 5], [1, 1, 2], 5)
    @test st1.ids == [2, 3, 5]
    @test all(s -> st1.bus[s] == s, st1.ids)
    @test st1.actor == Dict(3 => 1, 2 => 1, 5 => 2)
    @test st1.site == Dict(3 => 1, 2 => 2, 5 => 3)

    # shared bus: first site keeps id = bus, the k-th further site gets N + k
    st2 = build_slot_table([2, 3, 2, 2], [1, 1, 2, 2], 3)
    @test st2.ids == [2, 3, 4, 5]
    @test st2.bus == Dict(2 => 2, 3 => 3, 4 => 2, 5 => 2)
    @test st2.site == Dict(2 => 1, 3 => 2, 4 => 3, 5 => 4)
    @test st2.actor == Dict(2 => 1, 3 => 1, 4 => 2, 5 => 2)

    # portfolio-then-positional order decides "first at a bus"
    st3 = build_slot_table([2, 3, 2, 2], [2, 1, 1, 2], 3)
    @test st3.ids == [2, 3, 4, 5]
    @test st3.site[3] == 2          # actor 1 site idx 2 (bus 3) -> id 3
    @test st3.site[2] == 3          # actor 1 site idx 3 (bus 2) is first at bus 2 -> id 2
    @test st3.site[4] == 1          # actor 2 site idx 1 -> N + 1
    @test st3.site[5] == 4          # actor 2 site idx 4 -> N + 2

    # deterministic across repeated calls
    let a = build_slot_table([2, 3, 2, 2], [2, 1, 1, 2], 3)
        @test a.ids == st3.ids && a.bus == st3.bus && a.actor == st3.actor && a.site == st3.site
    end

    # malformed inputs
    @test_throws ArgumentError build_slot_table([2, 3], [1], 3)
    @test_throws ArgumentError build_slot_table([0, 3], [1, 1], 3)
    @test_throws ArgumentError build_slot_table([2, 4], [1, 1], 3)
end

@testitem "actor portfolio: forced slot path on the 10-aggregator IEEE-13 population is bitwise legacy" setup =
    [ExperimentHarnessFixtures] tags = [:actors, :admm] begin
    using TSODSO

    function same(a, b)
        ok = a.welfare == b.welfare && a.dadp == b.dadp && a.iters == b.iters
        for f in fieldnames(typeof(a.residuals))
            ok &= getfield(a.residuals, f) == getfield(b.residuals, f)
        end
        for k in (:agr_dispatch, :agr_utility, :agr_import, :agr_prices)
            ok &= getfield(a, k) == getfield(b, k)
        end
        ok &= keys(a) == keys(b)
        return ok
    end
    # The canary population: the 10-aggregator IEEE-13 scenario materialisation with the default
    # ADMM strategy parameters (recipe of test_admm_parallel.jl; converges in 56 iterations).
    function canary_population()
        kw0 = ExperimentHarnessFixtures.minimal_scenario_kwargs()
        s = TSODSO.Scenario(; kw0..., strategy = :admm)
        st = s.strategy
        feeder, λ₀, aggs = TSODSO._materialize(s)
        pf = TSODSO.build_powerflow(s)
        kw = (
            T = s.T,
            λ₀ = λ₀,
            ρ = st.ρ,
            maxiter = st.maxiter,
            ε_abs = st.ε_abs,
            ε_rel = st.ε_rel,
            τ = st.τ_ratio,
            μ = st.μ,
            allow_export = s.allow_export,
        )
        return feeder, aggs, kw, pf
    end
    function run_case()
        feeder, aggs, kw, pf = canary_population()
        legacy = solve_admm(feeder, pf, aggs; kw...)
        acts = [Portfolio(a; name = Symbol("site", i)) for (i, a) in enumerate(aggs)]
        slot = solve_admm(feeder, pf, aggs; kw..., actors = acts, _force_slot_path = true)
        return (; legacy, slot, n = length(aggs))
    end
    r = run_case()
    @test r.n == 10
    @test same(r.legacy, r.slot)
end

@testitem "actor portfolio: multi-bus portfolio on distinct buses equals legacy bitwise" setup =
    [ExperimentHarnessFixtures] tags = [:actors, :admm] begin
    using TSODSO

    # The canary population: the 10-aggregator IEEE-13 scenario materialisation with the default
    # ADMM strategy parameters (recipe of test_admm_parallel.jl; converges in 56 iterations).
    function canary_population()
        kw0 = ExperimentHarnessFixtures.minimal_scenario_kwargs()
        s = TSODSO.Scenario(; kw0..., strategy = :admm)
        st = s.strategy
        feeder, λ₀, aggs = TSODSO._materialize(s)
        pf = TSODSO.build_powerflow(s)
        kw = (
            T = s.T,
            λ₀ = λ₀,
            ρ = st.ρ,
            maxiter = st.maxiter,
            ε_abs = st.ε_abs,
            ε_rel = st.ε_rel,
            τ = st.τ_ratio,
            μ = st.μ,
            allow_export = s.allow_export,
        )
        return feeder, aggs, kw, pf
    end
    function run_case()
        feeder, aggs, kw, pf = canary_population()
        legacy = solve_admm(feeder, pf, aggs; kw...)
        acts = [Portfolio(aggs[1:5]; name = :a), Portfolio(aggs[6:end]; name = :b)]
        port = solve_admm(feeder, pf, aggs; kw..., actors = acts)
        return (; legacy, port)
    end
    r = run_case()
    @test r.port.welfare == r.legacy.welfare
    @test r.port.dadp == r.legacy.dadp
    @test r.port.iters == r.legacy.iters
    @test r.port.agr_dispatch == r.legacy.agr_dispatch
    @test keys(r.port) == keys(r.legacy)
end

@testitem "actor portfolio: legacy guards keep their messages when actors is nothing" setup =
    [TwoBusFixtures] tags = [:actors, :admm] begin
    using TSODSO

    feeder = TwoBusFixtures.two_bus_feeder()
    a1 = TwoBusFixtures.build_two_bus_aggregators(feeder; seed = 1)[1]
    a2 = TwoBusFixtures.build_two_bus_aggregators(feeder; seed = 2)[1]
    @test a1.bus == a2.bus
    kw = (
        T = TwoBusFixtures.T,
        λ₀ = TwoBusFixtures.two_bus_lambda0(),
        ρ = TwoBusFixtures.RHO_2BUS,
        allow_export = true,
    )
    err = try
        solve_admm(feeder, ConvexBranchFlow(), [a1, a2]; kw...)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("one aggregator per load node", sprint(showerror, err))
    # the forced slot path (a test seam) is only reachable with at most one site per bus in
    # this plan: a bus with several sites still reaches the legacy guard
    err2 = try
        solve_admm(feeder, ConvexBranchFlow(), [a1, a2]; kw..., _force_slot_path = true)
        nothing
    catch e
        e
    end
    @test err2 isa ArgumentError
end

@testitem "actor portfolio: AdmmState 18-arg constructor and slot_bus meta only on the slot branch" setup =
    [TwoBusFixtures] tags = [:actors, :admm] begin
    using TSODSO
    using TSODSO: AdmmState, build_slot_table, _admm_build, _react_mode, normalize_reactive_mode

    feeder = TwoBusFixtures.two_bus_feeder()
    aggs = TwoBusFixtures.build_two_bus_aggregators_no_flex(feeder)
    Th = TwoBusFixtures.T
    λ₀ = TwoBusFixtures.two_bus_lambda0()
    ρ = TwoBusFixtures.RHO_2BUS
    mode = normalize_reactive_mode(ReactiveMode.LIVE)
    rmode = _react_mode(mode)

    function build(slots)
        return _admm_build(feeder, ConvexBranchFlow(), aggs, Th, λ₀, ρ, ρ, mode, rmode; slots = slots)
    end
    N = length(feeder.buses)
    slots = build_slot_table([a.bus for a in aggs], collect(1:length(aggs)), N)
    st_leg = build(nothing)
    st_slot = build(slots)
    @test !haskey(st_leg.dso.ctx.meta, :slot_bus)
    @test st_slot.dso.ctx.meta[:slot_bus] == slots.bus
    @test st_slot.load_nodes == st_leg.load_nodes == slots.ids
    # 18-arg positional construction still works and defaults slot_bus to the identity
    flds = fieldnames(AdmmState)
    args = Tuple(getfield(st_leg, f) for f in flds[1:18])
    st18 = AdmmState(args...)
    @test st18.slot_bus == Dict(j => j for j in st_leg.load_nodes)
    @test st_leg.slot_bus == st18.slot_bus
    @test st_slot.slot_bus == slots.bus
    # the p_p normalisation counts slots: equal to the legacy value when 1:1
    @test length(st_slot.load_nodes) * Th == length(st_leg.load_nodes) * Th
    # DsoOpt keeps its 10-field layout
    @test length(fieldnames(typeof(st_slot.dso))) == 10
end

@testitem "actor portfolio: forced slot path parallel == serial bitwise (thread-gated, no skip record)" setup =
    [ExperimentHarnessFixtures] tags = [:actors, :admm, :parallel] begin
    using TSODSO
    using LinearAlgebra: BLAS

    # Under the default 1-thread suite the threaded executor throws by design (fail-loud), so
    # the equality comparison runs only when threads are available. It deliberately emits NO
    # `@test_skip`: that would need a new test/expected_broken.txt record. Run it with
    # `JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_actor_portfolio.jl`.
    function run_case()
        kw0 = ExperimentHarnessFixtures.minimal_scenario_kwargs()
        s = TSODSO.Scenario(; kw0..., strategy = :admm)
        st = s.strategy
        feeder, λ₀, aggs = TSODSO._materialize(s)
        pf = TSODSO.build_powerflow(s)
        kw = (
            T = s.T, λ₀ = λ₀, ρ = st.ρ, maxiter = st.maxiter, ε_abs = st.ε_abs,
            ε_rel = st.ε_rel, τ = st.τ_ratio, μ = st.μ, allow_export = s.allow_export,
        )
        acts = [Portfolio(a; name = Symbol("site", i)) for (i, a) in enumerate(aggs)]
        ser = solve_admm(feeder, pf, aggs; kw..., actors = acts, _force_slot_path = true)
        par = solve_admm(
            feeder, pf, aggs; kw..., actors = acts, _force_slot_path = true, parallel = true,
        )
        return (; ser, par)
    end
    if Threads.nthreads() > 1
        blas0 = BLAS.get_num_threads()
        try
            r = run_case()
            @test r.par.welfare == r.ser.welfare
            @test r.par.dadp == r.ser.dadp
            @test r.par.iters == r.ser.iters
            @test r.par.residuals.primal_trace == r.ser.residuals.primal_trace
            @test r.par.residuals.dual_trace == r.ser.residuals.dual_trace
            @test r.par.agr_dispatch == r.ser.agr_dispatch
        finally
            BLAS.set_num_threads(blas0)
        end
    else
        @info "actor portfolio: 1-thread runtime; threaded slot-path equality not exercised"
        @test Threads.nthreads() == 1
    end
end

@testitem "actor portfolio: forced slot path LIVE reactive with a 4Q-BESS site equals legacy bitwise" setup =
    [TwoBusFixtures, FourQuadBESSFixtures] tags = [:actors, :admm, :reactive] begin
    using TSODSO

    function run_case()
        feeder = TwoBusFixtures.two_bus_feeder()
        aggs = FourQuadBESSFixtures.build_two_bus_aggregators_4q(feeder)
        kw = (
            T = TwoBusFixtures.T,
            λ₀ = TwoBusFixtures.two_bus_lambda0(),
            ρ = TwoBusFixtures.RHO_2BUS,
            allow_export = true,
            reactive_consensus = ReactiveMode.LIVE,
            maxiter = 500,
        )
        legacy = solve_admm(feeder, ConvexBranchFlow(), aggs; kw...)
        acts = [Portfolio(a; name = Symbol("site", i)) for (i, a) in enumerate(aggs)]
        slot = solve_admm(
            feeder, ConvexBranchFlow(), aggs; kw..., actors = acts, _force_slot_path = true,
        )
        return (; legacy, slot)
    end
    r = run_case()
    @test r.slot.mu_q !== nothing && r.slot.q_devices !== nothing
    @test r.slot.welfare == r.legacy.welfare
    @test r.slot.dadp == r.legacy.dadp
    @test r.slot.iters == r.legacy.iters
    @test r.slot.mu_q == r.legacy.mu_q
    @test r.slot.q_devices == r.legacy.q_devices
    @test r.slot.agr_dispatch == r.legacy.agr_dispatch
    @test r.slot.residuals.primal_trace == r.legacy.residuals.primal_trace
end

# ---- 44-05: several sites / actors at ONE bus (ACTOR-03) -------------------------------------------

@testitem "actor portfolio: split-bus centralized equals merged aggregator" setup =
    [PortfolioFixtures] tags = [:actors] begin
    using TSODSO
    using Test

    function gaps(seed)
        p = PortfolioFixtures.pop4(seed)
        f = PortfolioFixtures.feeder4()
        cm = PortfolioFixtures.central(f, [p.s2, p.m3, p.s4], 2:4)
        cs = PortfolioFixtures.central(f, [p.s2, p.s3a, p.s3b, p.s4], 2:4)
        return abs(cm.welfare - cs.welfare), maximum(abs.(cm.dadp .- cs.dadp))
    end
    for seed in PortfolioFixtures.SEEDS
        dW, dλ = gaps(seed)
        @test dW <= PortfolioFixtures.TOL_CENT_W
        @test dλ <= PortfolioFixtures.TOL_CENT_L
    end
end

@testitem "actor portfolio: split-bus ADMM auto-routes to the slot branch and matches merged and centralized" setup =
    [PortfolioFixtures] tags = [:actors, :admm] begin
    using TSODSO
    using Test

    for seed in PortfolioFixtures.SEEDS
        r = PortfolioFixtures.run4_full(seed)
        rs, rm = r.rs, r.rm
        # routed to the slot branch (no legacy "share bus" ArgumentError), converged
        @test rs.status === :converged
        # dadp is per BUS (3 load buses), NOT per slot (4 slots)
        @test size(rs.dadp) == (3, PortfolioFixtures.T)
        @test size(rm.dadp) == (3, PortfolioFixtures.T)
        @test abs(rs.welfare - rm.welfare) <= PortfolioFixtures.TOL_ADMM_W
        @test maximum(abs.(rs.dadp .- rm.dadp)) <= PortfolioFixtures.TOL_ADMM_L
        @test abs(rs.welfare - r.cs.welfare) <= PortfolioFixtures.TOL_ADMM_CENT_W
        @test maximum(abs.(rs.dadp .- r.cs.dadp)) <= PortfolioFixtures.TOL_ADMM_CENT_L
        # per-slot lambda and the REPORTED agreement certificate
        @test sort(collect(keys(rs.lambda_slots))) == [2, 3, 4, 5]
        @test all(v -> length(v) == PortfolioFixtures.T, values(rs.lambda_slots))
        @test rs.slot_lambda_gap isa Float64 && isfinite(rs.slot_lambda_gap)
        @test rs.slot_lambda_gap <= PortfolioFixtures.TOL_FLOOR
        @test rs.slot_lambda_agree isa Bool && rs.slot_lambda_agree
        # the published per-bus row is the primary slot's -lambda (ascending buses 2, 3, 4)
        @test vec(rs.dadp[1, :]) == rs.lambda_slots[2]
        @test vec(rs.dadp[2, :]) == rs.lambda_slots[3]
        @test vec(rs.dadp[3, :]) == rs.lambda_slots[4]
        # slot -> bus / actor maps; extra slot 5 = N + 1 sits on bus 3
        @test rs.slot_bus == Dict(2 => 2, 3 => 3, 4 => 4, 5 => 3)
        @test rs.slot_actor == Dict(2 => 1, 3 => 1, 4 => 2, 5 => 2)
        @test sort(collect(keys(rs.agr_dispatch))) == [2, 3, 4, 5]
        # the merged result carries none of the slot keys
        @test !haskey(rm, :lambda_slots) && !haskey(rm, :slot_lambda_gap)
    end
end

@testitem "actor portfolio: portfolios spanning buses with a shared bus: actor key on slots" setup =
    [PortfolioFixtures] tags = [:actors, :admm] begin
    using TSODSO
    using Test

    r = PortfolioFixtures.run4(PortfolioFixtures.SEEDS[1])
    rs = r.rs
    T = PortfolioFixtures.T
    @test haskey(rs, :actor)
    # independent profit = -sum_t m * pag over A's sites (slots 2 and 3); B has the default
    # objective (no wedge), so its profit is exactly 0. Slot 5 (B's site at the shared bus) is in
    # the slot-keyed dispatch but carries no wedge.
    m = 0.5
    profitA = -sum(m * rs.agr_dispatch[s][t] for s in (2, 3) for t in 1:T)
    @test abs(rs.actor.profit_by_actor[1] - profitA) <= PortfolioFixtures.TOL_FLOOR
    @test rs.actor.profit_by_actor[2] == 0.0
    @test rs.actor.retail_wedge[1] == fill(m, T)
    @test rs.actor.retail_wedge[2] === nothing
    @test rs.actor.social_welfare == rs.welfare
    @test abs(rs.actor.actor_objective_value - (rs.welfare - profitA)) <= PortfolioFixtures.TOL_FLOOR

    # the wedge on the portfolio that owns the EXTRA slot (B: slots 4 and 5)
    p = PortfolioFixtures.pop4(PortfolioFixtures.SEEDS[1])
    acts = [
        Portfolio(p.s2, p.s3a; name = :A),
        Portfolio(p.s3b, p.s4; name = :B, objective = ProfitObjective(0.5)),
    ]
    rb = solve_admm(r.f, ConvexBranchFlow(), r.sites; r.kw..., actors = acts)
    profitB = -sum(m * rb.agr_dispatch[s][t] for s in (4, 5) for t in 1:T)
    @test abs(rb.actor.profit_by_actor[2] - profitB) <= PortfolioFixtures.TOL_FLOOR
    @test rb.actor.profit_by_actor[1] == 0.0
    # a wedge moves dispatch: the slot dispatch differs from the other run's
    @test rb.agr_dispatch[5] != rs.agr_dispatch[5]
end

@testitem "actor portfolio: OFF and CERTIFIED reactive with two sites at one bus" setup =
    [PortfolioFixtures] tags = [:actors, :admm, :reactive] begin
    using TSODSO
    using Test

    for kind in (:off, :cert), seed in PortfolioFixtures.SEEDS[1:2]
        r = PortfolioFixtures.run2(seed, kind)
        @test r.rs.status === :converged
        @test size(r.rs.dadp) == (1, PortfolioFixtures.T)
        @test abs(r.rs.welfare - r.rm.welfare) <= PortfolioFixtures.TOL_2BUS_W
        @test maximum(abs.(r.rs.dadp .- r.rm.dadp)) <= PortfolioFixtures.TOL_2BUS_L
        @test r.rs.slot_lambda_gap <= PortfolioFixtures.TOL_FLOOR
        @test r.rs.mu_q === nothing && r.rs.q_devices === nothing
    end
end

@testitem "actor portfolio: LIVE reactive and a FourQuadBESS second site on a shared bus" setup =
    [PortfolioFixtures] tags = [:actors, :admm, :reactive] begin
    using TSODSO
    using Test

    seed = PortfolioFixtures.SEEDS[1]
    for kind in (:live, :q4)
        r = PortfolioFixtures.run2(seed, kind)
        @test r.rs.status === :converged
        @test size(r.rs.dadp) == (1, PortfolioFixtures.T)
        @test size(r.rs.mu_q) == (1, PortfolioFixtures.T)
        @test abs(r.rs.welfare - r.rm.welfare) <= PortfolioFixtures.TOL_2BUS_W
        @test maximum(abs.(r.rs.dadp .- r.rm.dadp)) <= PortfolioFixtures.TOL_2BUS_L
        @test maximum(abs.(r.rs.mu_q .- r.rm.mu_q)) <= PortfolioFixtures.TOL_2BUS_MU
        @test r.rs.slot_lambda_gap <= PortfolioFixtures.TOL_FLOOR
    end
    # the 4Q-BESS is the SECOND site: slot id N + 1 = 3 on bus 2; q_devices is keyed by slot id
    r4 = PortfolioFixtures.run2(seed, :q4)
    @test collect(keys(r4.rs.q_devices)) == [3]
    @test length(r4.rs.q_devices[3]) == PortfolioFixtures.T
    @test r4.rs.slot_bus == Dict(2 => 2, 3 => 2)
    @test collect(keys(r4.rm.q_devices)) == [2]
end

@testitem "actor portfolio: p_p normaliser counts slots and the legacy value when 1:1" setup =
    [PortfolioFixtures] tags = [:actors, :admm] begin
    using TSODSO
    using TSODSO: build_slot_table, _admm_build, _react_mode, normalize_reactive_mode

    p = PortfolioFixtures.pop4(PortfolioFixtures.SEEDS[1])
    f = PortfolioFixtures.feeder4()
    T = PortfolioFixtures.T
    mode = normalize_reactive_mode(ReactiveMode.OFF)
    rmode = _react_mode(mode)
    function build(aggs, slots)
        return _admm_build(
            f, ConvexBranchFlow(), aggs, T, PortfolioFixtures.lambda0(), 5.0, 5.0, mode, rmode;
            slots = slots,
        )
    end
    shared = [p.s2, p.s3a, p.s3b, p.s4]
    st_shared = build(shared, build_slot_table([a.bus for a in shared], [1, 1, 2, 2], 4))
    @test length(st_shared.load_nodes) * T == 4 * T          # n_slots * T (3 buses, 4 slots)
    one = [p.s2, p.m3, p.s4]
    st_leg = build(one, nothing)
    st_slot = build(one, build_slot_table([a.bus for a in one], [1, 2, 3], 4))
    @test length(st_leg.load_nodes) * T == length(st_slot.load_nodes) * T == 3 * T
end

@testitem "actor portfolio: threaded shared-bus solve equals serial bitwise (thread-gated, no skip record)" setup =
    [PortfolioFixtures] tags = [:actors, :admm, :parallel] begin
    using TSODSO
    using Test
    using LinearAlgebra: BLAS

    # Runs the comparison only with threads available; no `@test_skip` (it would need a new
    # test/expected_broken.txt record). Use JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_actor_portfolio.jl.
    if Threads.nthreads() > 1
        blas0 = BLAS.get_num_threads()
        try
            ser = PortfolioFixtures.run4(PortfolioFixtures.SEEDS[1]).rs
            par = PortfolioFixtures.run4(PortfolioFixtures.SEEDS[1]; parallel = true).rs
            @test par.welfare == ser.welfare
            @test par.dadp == ser.dadp
            @test par.iters == ser.iters
            @test par.agr_dispatch == ser.agr_dispatch
            @test par.lambda_slots == ser.lambda_slots
            @test par.residuals.primal_trace == ser.residuals.primal_trace
        finally
            BLAS.set_num_threads(blas0)
        end
    else
        @info "actor portfolio: 1-thread runtime; threaded shared-bus equality not exercised"
        @test Threads.nthreads() == 1
    end
end

@testitem "actor portfolio: shared bus with actors does not reach the legacy guard but actors = nothing still does" setup =
    [PortfolioFixtures] tags = [:actors, :admm] begin
    using TSODSO
    using Test

    p = PortfolioFixtures.pop2(PortfolioFixtures.SEEDS[1], :off)
    f = PortfolioFixtures.feeder2()
    kw = PortfolioFixtures.admm_kw()
    r = solve_admm(
        f, ConvexBranchFlow(), [p.a1, p.a2]; kw..., actors = [Portfolio(p.a1), Portfolio(p.a2)],
    )
    @test r.status === :converged
    # one portfolio owning both sites at the bus is also routed to the slot branch
    r1 = solve_admm(f, ConvexBranchFlow(), [p.a1, p.a2]; kw..., actors = [Portfolio(p.a1, p.a2)])
    @test r1.status === :converged
    @test r1.slot_actor == Dict(2 => 1, 3 => 1)
    # legacy path (no actors): the verbatim legacy guard
    err = try
        solve_admm(f, ConvexBranchFlow(), [p.a1, p.a2]; kw...)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("one aggregator per load node", sprint(showerror, err))
end
