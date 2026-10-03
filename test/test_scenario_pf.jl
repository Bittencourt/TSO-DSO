# ARCH-01 test file: Scenario `pf` selector construction + `build_powerflow` materialization.
# All items are solver-free. Plan 03 appends run-time per-pf items.

@testitem "ARCH-01 build_powerflow default is ConvexBranchFlow()" begin
    using TSODSO
    pf = TSODSO.build_powerflow(Scenario(name = "x"))
    @test pf === ConvexBranchFlow()
    @test Scenario(name = "x").pf === :convex_branch_flow
end

@testitem "ARCH-01 build_powerflow per selector" begin
    using TSODSO
    lit = TSODSO.build_powerflow(
        Scenario(name = "x", pf = :convex_branch_flow, pf_thesis_literal = true),
    )
    @test lit === ConvexBranchFlow(thesis_literal = true)
    r = TSODSO.build_powerflow(
        Scenario(name = "x", pf = :restricted_branch_flow, pf_ε = 0.01),
    )
    @test r isa RestrictedBranchFlow
    @test r.ε == 0.01
    @test TSODSO.build_powerflow(Scenario(name = "x", pf = :lindistflow)) isa LinDistFlow
    ac = TSODSO.build_powerflow(Scenario(name = "x", pf = :ac))
    @test ac isa ACPowerFlow
    @test ac == ACPowerFlow()
end

@testitem "ARCH-01 pf construction guards" begin
    using TSODSO
    function throws_arg(f)
        return try
            f()
            false
        catch e
            e isa ArgumentError ? true : rethrow()
        end
    end
    @test throws_arg(() -> Scenario(name = "x", pf = :bogus))
    @test throws_arg(() -> Scenario(name = "x", pf = :restricted_branch_flow, pf_ε = -1.0))
    @test throws_arg(() -> Scenario(name = "x", pf = :restricted_branch_flow, pf_ε = NaN))
    @test throws_arg(() -> Scenario(name = "x", pf = :convex_branch_flow, pf_ε = 0.1))
    @test throws_arg(
        () -> Scenario(name = "x", pf = :restricted_branch_flow, pf_thesis_literal = true),
    )
    for pf in (:restricted_branch_flow, :lindistflow, :ac)
        for st in (:admm, :mpc, :stochastic)
            @test throws_arg(() -> Scenario(name = "x", strategy = st, pf = pf))
        end
    end
    for st in (:admm, :mpc, :stochastic)
        @test throws_arg(
            () -> Scenario(name = "x", strategy = st, pf_thesis_literal = true),
        )
    end
    for pf in (:convex_branch_flow, :restricted_branch_flow, :lindistflow, :ac)
        @test Scenario(name = "x", pf = pf).pf === pf
    end
end

@testitem "ARCH-01 strategy x pf matrix agrees with supports_pf" begin
    using TSODSO
    function constructs(st, pf, lit)
        return try
            Scenario(name = "x", strategy = st, pf = pf, pf_thesis_literal = lit)
            true
        catch e
            e isa ArgumentError ? false : rethrow()
        end
    end
    combos = [
        (:convex_branch_flow, false),
        (:convex_branch_flow, true),
        (:restricted_branch_flow, false),
        (:lindistflow, false),
        (:ac, false),
    ]
    for st in (Centralized(), ADMM(), MPC(), Stochastic())
        for (pf, lit) in combos
            @test constructs(st, pf, lit) == TSODSO.supports_pf(st, pf, lit)
        end
    end
end

@testitem "ARCH-01 _powerflow_from_selector terminal branch throws" begin
    using TSODSO
    @test_throws ArgumentError TSODSO._powerflow_from_selector(:bogus, false, 0.0)
end
