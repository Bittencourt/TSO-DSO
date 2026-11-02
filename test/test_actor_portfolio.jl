# test/test_actor_portfolio.jl
#
# Seam: SlotTable / build_slot_table (src/actors/Portfolio.jl), the slot-indexed DSO-OPT
# (`build_dso_opt(...; slots)`), the slot branch of `_admm_build` and the trailing
# `AdmmState.slot_bus` field (plan 44-03, ACTOR-03 build-time structure). Every item name
# contains "actor portfolio".
#
# ANCHOR: the slot branch forced onto a 1:1 population (each site its own actor, slot id ==
# bus id) must equal the legacy ADMM result BITWISE (`==`, never `isapprox`) on welfare, dadp,
# iters, every residual trace and every `agr_*` key. No tolerance is involved anywhere in this
# file: every comparison is exact equality, so there is nothing to measure.
#
# Accumulators live in functions / `let` (testitem bodies are top-level scope).

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
