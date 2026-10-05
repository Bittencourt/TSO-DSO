# Test file: Scenario `pf` selector construction + `build_powerflow` materialization.
# All items are solver-free. Plan 03 appends run-time per-pf items.

@testitem "scenario_pf: build_powerflow default is ConvexBranchFlow()" begin
    using TSODSO
    pf = TSODSO.build_powerflow(Scenario(name = "x"))
    @test pf === ConvexBranchFlow()
    @test Scenario(name = "x").pf === :convex_branch_flow
end

@testitem "scenario_pf: build_powerflow per selector" begin
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

@testitem "scenario_pf: pf construction guards" begin
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
        for st in (:mpc, :stochastic)
            @test throws_arg(() -> Scenario(name = "x", strategy = st, pf = pf))
        end
    end
    # ADMM is formulation-generic: convex (also thesis-literal), restricted, LinDist
    @test throws_arg(() -> Scenario(name = "x", strategy = :admm, pf = :ac))
    for pf in (:restricted_branch_flow, :lindistflow)
        @test Scenario(name = "x", strategy = :admm, pf = pf).pf === pf
    end
    @test Scenario(name = "x", strategy = :admm, pf_thesis_literal = true).pf_thesis_literal
    for st in (:mpc, :stochastic)
        @test throws_arg(
            () -> Scenario(name = "x", strategy = st, pf_thesis_literal = true),
        )
    end
    for pf in (:convex_branch_flow, :restricted_branch_flow, :lindistflow, :ac)
        @test Scenario(name = "x", pf = pf).pf === pf
    end
end

@testitem "scenario_pf: strategy x pf matrix agrees with supports_pf" begin
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

@testitem "scenario_pf: _powerflow_from_selector terminal branch throws" begin
    using TSODSO
    @test_throws ArgumentError TSODSO._powerflow_from_selector(:bogus, false, 0.0)
end

# ---- Run-time items: ieee13, T = 24, seed = 1 ----

@testitem "scenario_pf: default pf bit-identical to direct solve" begin
    using TSODSO, Test
    s = Scenario(name = "pf-default", feeder = :ieee13, seed = 1, T = 24)
    feeder = TSODSO.build_feeder(s.feeder)
    profiles =
        TSODSO.generate_profiles(; seed = TSODSO.sub_seed(s.seed, :profiles), T = s.T)
    λ₀ = TSODSO.build_price(s.price, s.T, profiles)
    aggs = TSODSO.build_population(
        s.population,
        feeder,
        s.feeder,
        profiles,
        TSODSO.sub_seed(s.seed, :population),
    )
    ctx, welfare, _ = TSODSO.solve_welfare(
        feeder,
        TSODSO.ConvexBranchFlow(),
        aggs;
        T = s.T,
        λ₀ = λ₀,
        allow_export = s.allow_export,
    )
    load_buses = sort!([a.bus for a in aggs])
    dadp = Matrix{Float64}(TSODSO.extract_dlmp(ctx)[load_buses, :])
    r = TSODSO.run(Centralized(), s)
    @test r.welfare == Float64(welfare)
    @test r.dadp == dadp
    @test r.exact_maxgap == Float64(ctx.meta[:socp_maxgap])
end

@testitem "scenario_pf: restricted and thesis_literal honoured" begin
    using TSODSO, Test
    base =
        TSODSO.run(Centralized(), Scenario(name = "b", feeder = :ieee13, seed = 1, T = 24))
    s_r = Scenario(
        name = "r",
        feeder = :ieee13,
        seed = 1,
        T = 24,
        pf = :restricted_branch_flow,
    )
    s_t = Scenario(name = "t", feeder = :ieee13, seed = 1, T = 24, pf_thesis_literal = true)
    @test TSODSO.build_powerflow(s_r) isa TSODSO.RestrictedBranchFlow
    @test TSODSO.build_powerflow(s_t) isa TSODSO.ConvexBranchFlow
    for s in (s_r, s_t)
        r = TSODSO.run(Centralized(), s)
        @test isfinite(r.welfare)
        @test isfinite(r.exact_maxgap)
        @test r.exact_maxgap < 1e-4
        @test isapprox(r.welfare, base.welfare; rtol = 1e-6)
    end
end

@testitem "scenario_pf: lindistflow: NaN maxgap, no KeyError" begin
    using TSODSO, Test
    s = Scenario(name = "ldf", feeder = :ieee13, seed = 1, T = 24, pf = :lindistflow)
    r = TSODSO.run(Centralized(), s)
    @test isfinite(r.welfare)
    @test isnan(r.exact_maxgap)
    @test size(r.dadp, 2) == 24
    @test size(r.dadp, 1) > 0
end

@testitem "scenario_pf: ac: NaN maxgap, allow_local honoured" begin
    using TSODSO, Test
    base =
        TSODSO.run(Centralized(), Scenario(name = "b", feeder = :ieee13, seed = 1, T = 24))
    r = TSODSO.run(
        Centralized(),
        Scenario(name = "ac", feeder = :ieee13, seed = 1, T = 24, pf = :ac),
    )
    @test isfinite(r.welfare)
    @test isnan(r.exact_maxgap)
    @test isapprox(r.welfare, base.welfare; rtol = 1e-3)
end

@testitem "scenario_pf: wrapper equivalence" begin
    using TSODSO, Test
    s = Scenario(name = "w", feeder = :ieee13, seed = 1, T = 24)
    a = run_scenario(s)
    b = TSODSO.run(s)
    c = TSODSO.run(s.strategy, s)
    for x in (b, c)
        @test x.welfare == a.welfare
        @test x.dadp == a.dadp
        @test x.exact_maxgap == a.exact_maxgap
    end
end
