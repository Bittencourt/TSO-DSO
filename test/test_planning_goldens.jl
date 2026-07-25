# test/test_planning_goldens.jl
#
# Seam: PVAL-02 — permanent regression infrastructure for the two one-off validation
# results that, until this plan, existed only as inline consts scattered across
# test/test_planning_certification.jl (the N=1 Phase 11 BilevelJuMP certification) and
# test/test_planning_nash.jl (the N=2 Phase 13 hand-checked Nash equilibrium). This file
# does NOT duplicate or re-execute test/test_planning_certification.jl's BilevelJuMP
# certification (PVAL-01 stays in-suite, untouched, in the same `Pkg.test` gate) — it
# adds the DEDICATED PVAL-02 goldens module (test/fixtures_planning.jl) and re-asserts
# each production entrypoint's own convergence/gap gate BEFORE comparing the result
# against the pinned golden value, mirroring test/test_acceptance.jl's own
# consolidates-without-duplicating, gate-before-golden convention.
#
# Consolidates (without duplicating):
#   - test/test_planning_certification.jl — the N=1 `solve_stackelberg!` gap gate +
#     hand-enumerated y*/z*/total golden (now sourced from PlanningFixtures, not a
#     private local const).
#   - test/test_planning_nash.jl — the N=2 `run_nash!` convergence gate + hand-checked
#     z/x_inv golden, and the `run_nash_probe` gating checks + a NEWLY BOUNDED spread
#     regression (previously only asserted `>= 0 && isfinite`, never bounded).

@testitem "planning goldens: N=1 certified Stackelberg equilibrium — gap gate then pinned golden regression (PVAL-02)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture, PlanningFixtures] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]
    follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])
    master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)

    result = mktempdir() do dir
        solve_stackelberg!(
            feeder,
            LinDistFlow(),
            [agg];
            λ₀ = λ₀,
            T = 1,
            follower_kwargs = follower_kwargs,
            master_kwargs = master_kwargs,
            tol = 1e-6,
            max_iter = 100,
            checkpoint_dir = dir,
        )
    end

    # GATE first (PVAL-02 assertion ordering, T-14-01): the production Benders loop's
    # OWN convergence gate must hold before the pinned golden is even consulted.
    @test result.gap <= 1e-6

    # VALUE second: the pinned N=1 hand-enumerated/BilevelJuMP-certified golden.
    @test isapprox(result.y, PlanningFixtures.N1_Y_HAND; atol = 1e-3)
    @test isapprox(result.z[1], PlanningFixtures.N1_Z_HAND; atol = 1e-3)
    @test isapprox(result.UB, PlanningFixtures.N1_OBJ_HAND; atol = 1e-3)
end

@testitem "planning goldens: N=2 Nash equilibrium — convergence gate then pinned golden regression (PVAL-02)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture, PlanningFixtures] begin
    using TSODSO

    shared = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.3],
        c_inv = [1.0, 1.0],
        c_op = [[0.5], [0.5]],
    )
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    specs = [spec, spec]

    result = run_nash!(
        specs,
        shared;
        z0 = zeros(2, 1),
        tol_outer = 1e-4,
        max_sweeps = 50,
        checkpoint_dir = mktempdir(),
    )

    # GATE first (PVAL-02 assertion ordering, T-14-01): `run_nash!`'s own convergence
    # flag must hold before the pinned golden is even consulted.
    @test result.converged

    # VALUE second: the pinned N=2 hand-checked congested equilibrium golden.
    @test isapprox(result.z, PlanningFixtures.N2_Z_HAND; atol = 1e-3)
    @test isapprox(result.x_inv, PlanningFixtures.N2_XINV_HAND; atol = 1e-3)
end

@testitem "planning goldens: N=2 multi-seed/multi-order probe — gating checks then spread-bound regression (PVAL-02)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture, PlanningFixtures] begin
    using TSODSO

    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    specs = [spec, spec]

    build_shared =
        () -> build_shared_transmission(;
            N = 2,
            T = 1,
            corridor_cap = 2.0,
            x_inv_max = [0.3, 0.3],
            c_inv = [1.0, 1.0],
            c_op = [[0.5], [0.5]],
        )

    # Hand-picked per 13-RESEARCH.md Pattern 4 (identical to test_planning_nash.jl's own
    # probe fixture): a cold start, a symmetric-capacity-split guess, and an asymmetric
    # start favoring distributor 1.
    seeds = (;
        zero = zeros(2, 1),
        saturating = fill(2.0 * (0.3 + 0.3) / 2, 2, 1),
        skewed = [0.5; 0.1;;],
    )
    orders = (:forward, :reverse)

    result = run_nash_probe(
        specs,
        build_shared;
        seeds = seeds,
        orders = orders,
        tol_outer = 1e-4,
        max_sweeps = 50,
        checkpoint_dir = mktempdir(),
    )

    # GATE first (PVAL-02 assertion ordering, T-14-01): every probe run must have
    # actually converged, and the structural "a converged equilibrium" honesty language
    # (NASH-04) must hold, before the pinned spread bounds are even consulted.
    @test result.n_runs == 6
    @test all(r -> r.result.converged, result.runs)
    @test occursin("a converged equilibrium", result.summary)
    @test !occursin("the equilibrium", result.summary)

    # VALUE second: the pinned, LOOSE UPPER BOUND on each reported spread — a bounded
    # regression where only `>= 0 && isfinite` was checked before (see
    # PlanningFixtures's own rationale comment for the derivation of these bounds).
    @test result.spread.z_spread <= PlanningFixtures.N2_PROBE_Z_SPREAD_MAX
    @test result.spread.x_inv_spread <= PlanningFixtures.N2_PROBE_XINV_SPREAD_MAX
    @test result.spread.cost_spread <= PlanningFixtures.N2_PROBE_COST_SPREAD_MAX
end
