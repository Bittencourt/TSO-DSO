# test/test_admm_generic_pf.jl
#
# Formulation-generic solve_admm/build_dso_opt via the
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
    [TwoBusFixtures] tags = [:admm, :genericpf] begin
    using TSODSO

    function errof(f)
        return try
            f()
            nothing
        catch e
            e
        end
    end

    feeder = TwoBusFixtures.two_bus_feeder()
    aggs = TwoBusFixtures.build_two_bus_aggregators(feeder)
    λ₀ = TwoBusFixtures.two_bus_lambda0()
    Th = TwoBusFixtures.T
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
    [TwoBusFixtures] tags = [:admm, :genericpf] begin
    using TSODSO
    using TSODSO: SOCP

    feeder = TwoBusFixtures.two_bus_feeder()
    aggs = TwoBusFixtures.build_two_bus_aggregators(feeder)
    Th = TwoBusFixtures.T
    λ₀ = TwoBusFixtures.two_bus_lambda0()

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
            feeder, pf, aggs; T = Th, λ₀ = λ₀, ρ = TwoBusFixtures.RHO_2BUS, allow_export = true,
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
    [TwoBusFixtures] tags = [:admm, :genericpf] begin
    using TSODSO

    function errof(f)
        return try
            f()
            nothing
        catch e
            e
        end
    end

    feeder = TwoBusFixtures.two_bus_feeder()
    aggs = TwoBusFixtures.build_two_bus_aggregators(feeder)
    Th = TwoBusFixtures.T
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

@testitem "admm generic pf: 4Q certificate policy mirrors the battery gate (SOCP strict, others report)" setup =
    [TwoBusFixtures] tags = [:admm, :genericpf] begin
    using TSODSO

    stub(pf) = (; dso = (; ctx = (; pf = pf)))
    @test TSODSO._report_4q(stub(LinDistFlow()))
    @test !TSODSO._report_4q(stub(ConvexBranchFlow()))
    @test !TSODSO._report_4q(stub(MeshedFlow()))
    @test !TSODSO._report_4q(stub(RestrictedBranchFlow()))
    @test TSODSO._batt_on_violation(stub(LinDistFlow())) === :warn
    @test TSODSO._batt_on_violation(stub(ConvexBranchFlow())) === :error

    # the kwarg reaches solve_agr!'s 4Q gate (no 4Q device here -> no-op either way)
    feeder = TwoBusFixtures.two_bus_feeder()
    aggs = TwoBusFixtures.build_two_bus_aggregators(feeder)
    Th = TwoBusFixtures.T
    agr = TSODSO.build_agr_opt(aggs[1], Th; ρ = 5.0)
    λj = fill(4.0, Th)
    cj = zeros(Th)
    for rep in (false, true)
        r = TSODSO.solve_agr!(agr, λj, cj, 5.0; check_4q = true, report_4q = rep)
        @test length(r.pag) == Th
    end
end

@testitem "admm generic pf: solve_agr! 4Q gate on a real co-activating FourQuadBESS (report_4q warns vs throws)" tags =
    [:admm, :genericpf] begin
    using TSODSO, JuMP, Logging

    # Boundary fixture (same device as test_fourquadbess.jl's honest-boundary item): a
    # large positive frontier price λ plus a tight upper SOC band makes the AGR-OPT optimum
    # co-activate p_ch AND p_dch (measured p_ch·p_dch ≈ 15.6 >> tol 6.4e-3), i.e. a REAL
    # violation reached through solve_agr!'s own call path, not a hand-set solution.
    d = TSODSO.FourQuadBESS(2, 0.5, 1.0, 8.0, 8.0, 12.0, 0.0, 1.5, 1.3, 1.0, 4.0, 9.0)
    agg = TSODSO.Aggregator(2, 0.9, [d], [0.0, 0.0])
    ρ = 0.01
    λj = [9.0, 9.0]
    cj = zeros(2)

    agr_err = TSODSO.build_agr_opt(agg, 2; ρ = ρ)
    @test_throws CertificateError TSODSO.solve_agr!(
        agr_err, λj, cj, ρ; check_4q = true, report_4q = false,
    )

    agr_rep = TSODSO.build_agr_opt(agg, 2; ρ = ρ)
    logger = Test.TestLogger()
    r = Logging.with_logger(logger) do
        TSODSO.solve_agr!(agr_rep, λj, cj, ρ; check_4q = true, report_4q = true)
    end
    @test length(r.pag) == 2
    warns = filter(l -> l.level == Logging.Warn, logger.logs)
    @test !isempty(warns)
    @test any(l -> occursin("4Q-BESS complementarity violated", string(l.message)), warns)
end
