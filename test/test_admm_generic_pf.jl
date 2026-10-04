# test/test_admm_generic_pf.jl
#
# Phase 34 Plan 09 (ARCH-05/06 prerequisite): formulation-generic solve_admm/build_dso_opt via the
# `admm_supported` trait, the (topology, formulation) pair check, the LinDistFlow NaN exactness gap
# and the additive `battery_on_violation` kwarg of `solve_agr!`.

@testitem "admm generic pf: admm_supported trait matrix" tags = [:admm, :genericpf] begin
    using TSODSO
    @test TSODSO.admm_supported(ConvexBranchFlow())
    @test TSODSO.admm_supported(ConvexBranchFlow(thesis_literal = true))
    @test TSODSO.admm_supported(RestrictedBranchFlow())
    @test TSODSO.admm_supported(MeshedFlow())
    @test TSODSO.admm_supported(LinDistFlow())
    @test !TSODSO.admm_supported(ACPowerFlow())
    @test !TSODSO.admm_supported(DCPowerFlow())
end

@testitem "admm generic pf: AC/DC and mis-pairs rejected with named ArgumentErrors" setup =
    [Phase6Fixtures] tags = [:admm, :genericpf] begin
    using TSODSO

    function errof(f)
        return try
            f()
            nothing
        catch e
            e
        end
    end

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    λ₀ = Phase6Fixtures.two_bus_lambda0()
    Th = Phase6Fixtures.T
    for pf in (ACPowerFlow(), DCPowerFlow())
        e = errof(() -> solve_admm(feeder, pf, aggs; T = Th, λ₀ = λ₀, ρ = 5.0))
        @test e isa ArgumentError
        @test occursin("solve_admm", e.msg) && occursin(string(typeof(pf)), e.msg)
        e = errof(() -> TSODSO.build_dso_opt(feeder, aggs, Th; ρ = 5.0, λ₀ = λ₀, pf = pf))
        @test e isa ArgumentError
        @test occursin("build_dso_opt", e.msg) && occursin(string(typeof(pf)), e.msg)
    end

    bus3 = [
        TSODSO.Bus(1, 0.95, 1.05, true),
        TSODSO.Bus(2, 0.95, 1.05, false),
        TSODSO.Bus(3, 0.95, 1.05, false),
    ]
    loop = [
        TSODSO.Branch(1, 2, 0.01, 0.02, 10.0),
        TSODSO.Branch(2, 3, 0.01, 0.02, 10.0),
        TSODSO.Branch(3, 1, 0.01, 0.02, 10.0),
    ]
    mesh = TSODSO.MeshedFeeder(bus3, loop, 1)
    # pair check runs BEFORE the empty-aggregators guard
    e = errof(() -> solve_admm(mesh, ConvexBranchFlow(), Aggregator[]; T = 1, λ₀ = [4.0], ρ = 10.0))
    @test e isa ArgumentError
    @test occursin("solve_admm", e.msg) && occursin("MeshedFeeder", e.msg)
    # (MeshedFeeder, MeshedFlow) passes the pair check and reaches the next guard
    e = errof(() -> solve_admm(mesh, MeshedFlow(), Aggregator[]; T = 1, λ₀ = [4.0], ρ = 10.0))
    @test e isa ArgumentError
    @test occursin("at least one aggregator", e.msg)
end

@testitem "admm generic pf: Restricted/LinDist ADMM match centralized welfare; NaN maxgap for LinDist" setup =
    [Phase6Fixtures] tags = [:admm, :genericpf] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    Th = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()

    function run_pair(pf)
        # near-lossless fixture: tighten the centralized SOCP gap exactly as test_admm.jl does
        opt = if TSODSO.problem_class(pf) isa SOCP
            select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)
        else
            select_optimizer(TSODSO.problem_class(pf))
        end
        _, obj_c, _ = solve_welfare(
            feeder, pf, aggs; T = Th, λ₀ = λ₀, allow_export = true, optimizer = opt,
        )
        res = solve_admm(
            feeder, pf, aggs; T = Th, λ₀ = λ₀, ρ = Phase6Fixtures.RHO_2BUS, allow_export = true,
        )
        return obj_c, res
    end

    for pf in (RestrictedBranchFlow(), LinDistFlow())
        obj_c, res = run_pair(pf)
        @test isapprox(res.welfare, obj_c; rtol = 1e-4)
        if pf isa LinDistFlow
            @test isnan(res.exact_maxgap)
        else
            @test isfinite(res.exact_maxgap) && res.exact_maxgap < 1e-6
        end
    end
    # Convex stays finite
    _, res = run_pair(ConvexBranchFlow())
    @test isfinite(res.exact_maxgap) && res.exact_maxgap < 1e-6
end

@testitem "admm generic pf: solve_agr! battery_on_violation kwarg is forwarded (default :error)" setup =
    [Phase6Fixtures] tags = [:admm, :genericpf] begin
    using TSODSO

    function errof(f)
        return try
            f()
            nothing
        catch e
            e
        end
    end

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    Th = Phase6Fixtures.T
    agr = TSODSO.build_agr_opt(aggs[1], Th; ρ = 5.0)
    λj = fill(4.0, Th)
    cj = zeros(Th)
    # default behaviour unchanged (no throw on a non-co-activated population)
    @test errof(() -> TSODSO.solve_agr!(agr, λj, cj, 5.0)) === nothing
    @test errof(() -> TSODSO.solve_agr!(agr, λj, cj, 5.0; battery_on_violation = :warn)) === nothing
    # the kwarg reaches assert_battery_complementarity! (invalid value is rejected there)
    e = errof(() -> TSODSO.solve_agr!(agr, λj, cj, 5.0; battery_on_violation = :bogus))
    @test e isa ArgumentError
    @test occursin("on_violation", e.msg)
end

@testitem "admm generic pf: Scenario runs ADMM on lindistflow and restricted_branch_flow" tags =
    [:admm, :genericpf] begin
    using TSODSO

    function go(pf)
        base = Scenario(name = "g-$pf", feeder = :ieee13, seed = 7, T = 24, pf = pf)
        r_admm = TSODSO.run(TSODSO.with_strategy(base, ADMM(ρ = 100.0)))
        return base, r_admm
    end

    _, r_lin = go(:lindistflow)
    @test r_lin isa TSODSO.ScenarioResult
    @test isfinite(r_lin.welfare)

    base, r_res = go(:restricted_branch_flow)
    r_cen = TSODSO.run(TSODSO.with_strategy(base, Centralized()))
    @test isapprox(r_res.welfare, r_cen.welfare; rtol = 1e-4)
end
