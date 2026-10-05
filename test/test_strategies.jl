# ARCH-02 strategy-layer test file. Later plans append dispatch / legacy-kwarg / flat-field items.
# All items here are solver-free.

@testitem "ARCH-02 strategy defaults" begin
    using TSODSO
    a = ADMM()
    @test a.ρ == 100.0
    @test a.ε_abs == 1e-4
    @test a.ε_rel == 1e-3
    @test a.maxiter == 200
    @test a.τ_ratio == 2.0
    @test a.μ == 10.0
    @test ADMM(ρ = 50).ρ === 50.0
    m = MPC()
    @test m.H == 6
    @test m.step == 1
    @test m.terminal_soc == true
    @test m.forecast_error == 0.05
    st = Stochastic()
    @test st.S == 3
    @test st.H_oos == 5
    @test st.probabilities == fill(1 / 3, 3)
end

@testitem "ARCH-02 strategy validation" begin
    using TSODSO
    @test_throws ArgumentError ADMM(ρ = 0.0)
    @test_throws ArgumentError ADMM(ρ = -1.0)
    @test_throws ArgumentError ADMM(ε_abs = 0.0)
    @test_throws ArgumentError ADMM(ε_rel = 0.0)
    @test_throws ArgumentError ADMM(τ_ratio = 0.0)
    @test_throws ArgumentError ADMM(μ = 0.0)
    @test_throws ArgumentError ADMM(maxiter = 0)
    @test_throws ArgumentError MPC(H = 0)
    @test_throws ArgumentError MPC(step = 0)
    @test_throws ArgumentError MPC(forecast_error = -0.1)
    @test_throws ArgumentError MPC(forecast_error = 1.0)
    @test_throws ArgumentError Stochastic(S = 2)
    @test_throws ArgumentError Stochastic(S = 6)
    @test_throws ArgumentError Stochastic(H_oos = 4)
    @test_throws ArgumentError Stochastic(H_oos = 11)
    @test_throws ArgumentError Stochastic(probabilities = [0.5, 0.5])
    @test_throws ArgumentError Stochastic(probabilities = [0.5, 0.5, 0.0])
    @test_throws ArgumentError Stochastic(probabilities = [0.5, 0.3, 0.3])
end

@testitem "ARCH-02 stochastic probabilities copy" begin
    using TSODSO
    p = [0.5, 0.3, 0.2]
    st = Stochastic(probabilities = p)
    @test st.probabilities == p
    @test st.probabilities !== p
    p[1] = 99.0
    @test st.probabilities[1] == 0.5
end

@testitem "ARCH-02 strategy value equality" begin
    using TSODSO
    @test ADMM(ρ = 50.0) == ADMM(ρ = 50.0)
    @test hash(ADMM(ρ = 50.0)) == hash(ADMM(ρ = 50.0))
    @test ADMM(ρ = 50.0) != ADMM(ρ = 60.0)
    @test Stochastic(probabilities = [0.5, 0.3, 0.2]) == Stochastic(probabilities = [0.5, 0.3, 0.2])
    @test hash(Stochastic(probabilities = [0.5, 0.3, 0.2])) == hash(Stochastic(probabilities = [0.5, 0.3, 0.2]))
    @test MPC(H = 3) != MPC(H = 4)
    @test MPC(H = 3) == MPC(H = 3)
    @test hash(MPC(H = 3)) == hash(MPC(H = 3))
    @test Centralized() == Centralized()
    @test hash(Centralized()) == hash(Centralized())
    @test Stochastic() == Stochastic(probabilities = [1 / 3, 1 / 3, 1 / 3])
end

@testitem "ARCH-02 supports_pf matrix" begin
    using TSODSO
    cases = [(:convex_branch_flow, false), (:convex_branch_flow, true),
        (:restricted_branch_flow, false), (:lindistflow, false), (:ac, false)]
    for (pf, tl) in cases
        @test TSODSO.supports_pf(Centralized(), pf, tl)
        expected = pf === :convex_branch_flow && !tl
        @test TSODSO.supports_pf(ADMM(), pf, tl) == (pf !== :ac)
        @test TSODSO.supports_pf(MPC(), pf, tl) == expected
        @test TSODSO.supports_pf(Stochastic(), pf, tl) == expected
    end
    @test length(TSODSO.supported_pfs(Centralized())) == 4
    @test TSODSO.supported_pfs(ADMM()) ==
          (:convex_branch_flow, :restricted_branch_flow, :lindistflow)
    @test TSODSO.supported_pfs(MPC()) == (:convex_branch_flow,)
    @test TSODSO.supported_pfs(Stochastic()) == (:convex_branch_flow,)
end

@testitem "ARCH-02 run is package-owned" begin
    using TSODSO
    @test TSODSO.run !== Base.run
    @test !(:run in names(TSODSO))
    for n in (:AbstractStrategy, :Centralized, :ADMM, :MPC, :Stochastic)
        @test n in names(TSODSO)
    end
end

@testitem "ARCH-02 Scenario has no flat strategy fields" begin
    using TSODSO
    @test fieldnames(Scenario) == (
        :name, :feeder, :seed, :T, :population, :price, :allow_export,
        :pf, :pf_thesis_literal, :pf_ε, :strategy,
    )
    s = Scenario(name = "x")
    @test !hasproperty(s, :ρ)
    @test !hasproperty(s, :mpc_H)
    @test !hasproperty(s, :stoch_S)
    @test !hasproperty(s, :maxiter)
end

@testitem "ARCH-02 legacy kwargs map identically" begin
    using TSODSO
    @test Scenario(name = "x", strategy = :admm, ρ = 50.0, maxiter = 10) ==
          Scenario(name = "x", strategy = ADMM(ρ = 50.0, maxiter = 10))
    @test Scenario(name = "x", strategy = :mpc, mpc_H = 3) ==
          Scenario(name = "x", strategy = MPC(H = 3))
    @test Scenario(name = "x", strategy = :stochastic, stoch_S = 4, stoch_H_oos = 6) ==
          Scenario(name = "x", strategy = Stochastic(S = 4, H_oos = 6))
    p = [0.5, 0.3, 0.2]
    s = Scenario(name = "x", strategy = :stochastic, stoch_probabilities = p)
    @test s == Scenario(name = "x", strategy = Stochastic(probabilities = p))
    @test s.strategy.probabilities == p
    @test s.strategy.probabilities !== p
    @test Scenario(name = "x", strategy = :centralized).strategy == Centralized()
    @test Scenario(name = "x").strategy == Centralized()
end

@testitem "ARCH-02 foreign and contradictory knobs throw ArgumentError" begin
    using TSODSO
    @test_throws ArgumentError Scenario(name = "x", mpc_H = 3)
    @test_throws ArgumentError Scenario(name = "x", strategy = :admm, mpc_H = 3)
    @test_throws ArgumentError Scenario(name = "x", strategy = ADMM(), ρ = 10.0)
    @test_throws ArgumentError Scenario(name = "x", strategy = :mpc, ρ = 10.0)
    @test_throws ArgumentError Scenario(name = "x", strategy = :stochastic, mpc_H = 2)
end

@testitem "ARCH-02 unknown strategy symbol, kwarg and feeder throw ArgumentError" begin
    using TSODSO
    @test_throws ArgumentError Scenario(name = "x", strategy = :bogus)
    @test_throws ArgumentError Scenario(name = "x", bogus = 1)
    @test_throws ArgumentError Scenario(name = "x", feeder = :ieee14)
end

@testitem "ARCH-02 Scenario value equality" begin
    using TSODSO
    a = Scenario(name = "x", strategy = :admm, ρ = 50.0)
    b = Scenario(name = "x", strategy = ADMM(ρ = 50.0))
    @test a == b
    @test hash(a) == hash(b)
    @test Scenario(name = "x", pf = :restricted_branch_flow, pf_ε = 0.1) !=
          Scenario(name = "x", pf = :restricted_branch_flow, pf_ε = 0.2)
    @test a != Scenario(name = "x", strategy = ADMM(ρ = 51.0))
end

@testitem "ARCH-02 with_strategy re-validates" begin
    using TSODSO
    s = TSODSO.with_strategy(Scenario(name = "x"), ADMM())
    @test s.strategy == ADMM()
    @test_throws ArgumentError TSODSO.with_strategy(Scenario(name = "x", pf = :ac), ADMM())
end

# ---- Run-time ARCH-02 result-shape items (Plan 32-03) ----

@testitem "ARCH-02 ScenarioResult shape Centralized" begin
    using TSODSO, Test
    r = TSODSO.run(Centralized(), Scenario(name = "cen", feeder = :ieee13, seed = 1, T = 24))
    @test ismissing(r.iters)
    @test ismissing(r.final_r)
    @test ismissing(r.final_s)
    @test ismissing(r.reactive_consensus_mode)
    @test r.details === nothing
    @test :iters in propertynames(r)
    @test r.welfare isa Float64
    @test r.dadp isa Matrix{Float64}
end

@testitem "ARCH-02 ScenarioResult shape ADMM" begin
    using TSODSO, Test
    r = TSODSO.run(Scenario(name = "adm", feeder = :ieee13, seed = 1, T = 24, strategy = ADMM()))
    @test r.details isa TSODSO.ADMMDetails
    @test r.iters isa Int
    @test r.iters >= 1
    @test r.final_r isa Float64
    @test r.reactive_consensus_mode isa TSODSO.ReactiveMode.T
    @test r.iters == r.details.iters
    @test r.final_r == r.details.final_r
    @test r.final_s == r.details.final_s
    @test r.reactive_consensus_mode == r.details.reactive_consensus_mode
end

@testitem "ARCH-02 run(st, s) explicit strategy wins" begin
    using TSODSO, Test
    r = TSODSO.run(ADMM(maxiter = 300), Scenario(name = "x", feeder = :ieee13, seed = 1, T = 24))
    @test r.scenario.strategy == ADMM(maxiter = 300)
end

@testitem "ARCH-02 run(MPC) common shape" tags = [:mpc_loop] setup = [MPCFixtures] begin
    using TSODSO, Test
    s = Scenario(name = "m", feeder = :ieee13, T = 9, strategy = MPC(H = 3, forecast_error = 0.0))
    r = run_mpc(s)
    res = TSODSO.run(s.strategy, s)
    @test res isa TSODSO.ScenarioResult
    @test res.welfare == r.realized_welfare
    @test res.dadp == reshape(r.trace.dadp_trace, 1, :)
    @test isnan(res.exact_maxgap)
    @test res.details isa TSODSO.MPCDetails
    @test res.details.regret == r.regret
    @test res.details.steps == r.steps
end

@testitem "ARCH-02 run(Stochastic) common shape" begin
    using TSODSO, Test
    s = Scenario(name = "t", feeder = :ieee13, T = 9, strategy = Stochastic(S = 3, H_oos = 5))
    r = run_stochastic(s)
    res = TSODSO.run(s.strategy, s)
    @test res isa TSODSO.ScenarioResult
    @test res.welfare == r.in_sample.welfare
    @test size(res.dadp) == (1, 9)
    @test res.dadp == reshape(r.in_sample.expected_dadp, 1, :)
    @test res.exact_maxgap == maximum(r.in_sample.socp_maxgap)
    @test res.details isa TSODSO.StochasticDetails
end

@testitem "ARCH-02 run_mpc/run_stochastic fallback to defaults" begin
    using TSODSO, Test
    r_def = run_stochastic(Scenario(name = "t", feeder = :ieee13, T = 9))
    r_exp = run_stochastic(Scenario(name = "t", feeder = :ieee13, T = 9, strategy = Stochastic()))
    @test r_def.in_sample.welfare == r_exp.in_sample.welfare
    @test run_mpc(Scenario(name = "m", feeder = :ieee13, T = 9)).steps == 9 - 6 + 1
end

@testitem "ARCH-02 MPC/Stochastic reject non-convex pf at construction" begin
    using TSODSO, Test
    for st in (MPC(), Stochastic())
        @test_throws ArgumentError Scenario(name = "x", feeder = :ieee13, pf = :lindistflow, strategy = st)
        @test_throws ArgumentError Scenario(name = "x", feeder = :ieee13, pf = :ac, strategy = st)
        @test_throws ArgumentError Scenario(
            name = "x", feeder = :ieee13, pf = :restricted_branch_flow, strategy = st,
        )
        @test_throws ArgumentError Scenario(
            name = "x", feeder = :ieee13, pf_thesis_literal = true, strategy = st,
        )
    end
end

@testitem "ARCH-02 run(st, s) dispatch uniformity" setup = [MPCFixtures] begin
    using TSODSO, Test
    for st in (Centralized(), MPC(H = 3, forecast_error = 0.0), Stochastic(S = 3, H_oos = 5))
        s = Scenario(name = "u", feeder = :ieee13, T = 9, strategy = st)
        res = TSODSO.run(s.strategy, s)
        @test res isa TSODSO.ScenarioResult
        @test res.welfare isa Float64
        @test res.dadp isa Matrix{Float64}
        @test res.exact_maxgap isa Float64
        @test res.elapsed >= 0
    end
end

@testitem "ARCH-02 run_and_store round-trip for MPC and Stochastic" setup = [ExperimentHarnessFixtures] begin
    using TSODSO, Test
    using DrWatson: wload

    is_prim(v) = v isa Union{Number,Symbol,String,Bool,Missing,Nothing} ||
                 (v isa AbstractArray && eltype(v) <: Union{Number,Symbol,String,Bool})
    ExperimentHarnessFixtures.with_tempdir() do dir
        s_mpc = Scenario(
            name = "st-mpc", feeder = :ieee13, T = 9,
            strategy = MPC(H = 3, forecast_error = 0.0),
        )
        s_sto = Scenario(
            name = "st-sto", feeder = :ieee13, T = 9,
            strategy = Stochastic(S = 3, H_oos = 5),
        )
        run_and_store(s_mpc; dir = dir)
        run_and_store(s_sto; dir = dir)
        f_mpc = joinpath(dir, TSODSO.scenario_filename(s_mpc))
        f_sto = joinpath(dir, TSODSO.scenario_filename(s_sto))
        @test isfile(f_mpc)
        @test isfile(f_sto)
        @test f_mpc != f_sto
        d_mpc = wload(f_mpc)
        d_sto = wload(f_sto)

        @test Symbol(d_mpc["strategy"]) == :mpc
        @test Symbol(d_sto["strategy"]) == :stochastic
        @test Symbol(d_mpc["pf"]) == :convex_branch_flow
        @test Symbol(d_sto["pf"]) == :convex_branch_flow
        @test haskey(d_mpc, "regret")
        @test haskey(d_mpc, "steps")
        @test haskey(d_sto, "welfare_gap")
        @test isfinite(d_mpc["welfare"])
        @test isfinite(d_sto["welfare"])
        for d in (d_mpc, d_sto)
            @test haskey(d, "gitcommit")
            @test haskey(d, "julia_version")
            for (k, v) in d
                @test !(v isa TSODSO.AbstractStrategy)
                @test !(v isa NamedTuple)
                @test !(v isa TSODSO.MpcTrace)
                @test is_prim(v)
            end
        end
        @test haskey(d_mpc, "mpc_H")
        @test !haskey(d_mpc, "stoch_S")
        @test haskey(d_sto, "stoch_S")
        @test !haskey(d_sto, "mpc_H")
    end
end

@testitem "ARCH-02 four strategies four filenames" begin
    using TSODSO, Test
    strategies = (Centralized(), ADMM(), MPC(), Stochastic())
    names = [
        TSODSO.scenario_filename(Scenario(name = "n", feeder = :ieee13, strategy = st))
        for st in strategies
    ]
    @test length(unique(names)) == 4
    @test all(endswith(".jld2"), names)
end

@testitem "REVIEW WR-01 run_mpc/run_stochastic re-validate strategy x pf" begin
    using TSODSO, Test
    s = Scenario(name = "w1", feeder = :ieee13, T = 9, pf = :lindistflow)
    @test_throws ArgumentError run_mpc(s)
    @test_throws ArgumentError run_stochastic(s)
end

@testitem "REVIEW WR-02 ADMM rejects non-finite knobs" begin
    using TSODSO, Test
    for k in (:ρ, :ε_abs, :ε_rel, :τ_ratio, :μ), v in (NaN, Inf)
        @test_throws ArgumentError ADMM(; (k => v,)...)
    end
end

@testitem "REVIEW WR-03 negative zero is normalized (== implies same hash)" begin
    using TSODSO, Test
    a = Scenario(name = "z", feeder = :ieee13, pf = :restricted_branch_flow, pf_ε = -0.0)
    b = Scenario(name = "z", feeder = :ieee13, pf = :restricted_branch_flow, pf_ε = 0.0)
    @test a == b
    @test hash(a) == hash(b)
    @test !signbit(a.pf_ε)
    @test hash(MPC(forecast_error = -0.0)) == hash(MPC(forecast_error = 0.0))
end

@testitem "REVIEW WR-04 post-construction probability mutation is caught at run time" begin
    using TSODSO, Test
    st = Stochastic(probabilities = [0.5, 0.3, 0.2])
    st.probabilities[1] = 0.9    # bypasses constructor validation (sum != 1)
    s = Scenario(name = "w4", feeder = :ieee13, T = 9, strategy = st)
    @test_throws ArgumentError run_stochastic(s)
end
