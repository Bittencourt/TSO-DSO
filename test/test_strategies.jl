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
        @test TSODSO.supports_pf(ADMM(), pf, tl) == expected
        @test TSODSO.supports_pf(MPC(), pf, tl) == expected
        @test TSODSO.supports_pf(Stochastic(), pf, tl) == expected
    end
    @test length(TSODSO.supported_pfs(Centralized())) == 4
    @test TSODSO.supported_pfs(ADMM()) == (:convex_branch_flow,)
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
