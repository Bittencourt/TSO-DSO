# test/test_admm_adaptive.jl
#
# Seam: per-unit-normalized adaptive ρ + build-once quadratic-coeff mutation + the transit-node
# (zero-injection) DSO-OPT relaxation (ADMM-02, RESEARCH Patterns 1 & 4, Pitfall 5).
#
# RED @testitem harness (Wave 0 of Phase 7). Plans 07-03 (set_rho! + transit relaxation) and
# 07-04 (adaptive-ρ policy) turn these green by IMPLEMENTING the code — the tests are NEVER
# edited to go green. Item names contain "adaptive"/"rho" (adaptive-ρ items) and "transit"/"dso"
# (the transit-node item) so the VALIDATION filters select them.
#
# RED SIGNAL (never a runner crash): the gate is `isdefined(TSODSO, :set_rho!)` — the 07-03
# quadratic-coefficient updater. Every behavioral assert sits BEHIND the guard.
#
# CONTRACT pinned here:
#   - `set_rho!(subproblem, ρ)` mutates the diagonal quadratic penalty coeff IN PLACE (RESEARCH
#     Pattern 1, verified JuMP `set_objective_coefficient(m,x,x,·)`) — NO rebuild, so the model's
#     variable/constraint counts are INVARIANT across a ρ change (ADMM-04 build-once).
#   - the SAME (ε_abs, ε_rel, τ, μ, ρ_min, ρ_max) config converges on BOTH the 2-bus and IEEE-13
#     (scale-invariant per-unit ρ, RESEARCH Pattern 3).
#   - a genuine TRANSIT bus (non-root, no aggregator) is accepted by `build_dso_opt` (zero
#     injection pinned) rather than throwing the Phase-6 guard (RESEARCH Pitfall 5).

@testitem "admm adaptive rho: set_rho! in-place quad-coeff, build-once invariant (adaptive, rho)" setup =
    [Phase7Fixtures, Phase6Fixtures] tags = [:admm, :phase7] begin
    using TSODSO
    using JuMP: num_variables, num_constraints

    # RED until Wave 2/3 (plan 07-03 lands set_rho!).
    @test isdefined(TSODSO, :set_rho!)

    if isdefined(TSODSO, :set_rho!) && isdefined(TSODSO, :build_dso_opt)
        feeder = Phase6Fixtures.two_bus_feeder()
        aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
        Th = Phase6Fixtures.T
        λ₀ = Phase6Fixtures.two_bus_lambda0()

        dso = build_dso_opt(feeder, aggs, Th; ρ = Phase7Fixtures.RHO0, λ₀ = λ₀)
        nv = num_variables(dso.model)
        nc = num_constraints(dso.model; count_variable_in_set_constraints = true)

        # A ρ change mutates ONLY objective coefficients (Pattern 1) — no variable/constraint added.
        set_rho!(dso, Phase7Fixtures.TAU * Phase7Fixtures.RHO0)
        @test num_variables(dso.model) == nv
        @test num_constraints(dso.model; count_variable_in_set_constraints = true) == nc

        # The AGR-OPT side mirrors the mutation (build-once preserved on both blocks).
        agr = build_agr_opt(aggs[1], Th; ρ = Phase7Fixtures.RHO0)
        nva = num_variables(agr.model)
        set_rho!(agr, Phase7Fixtures.RHO0 / Phase7Fixtures.TAU)
        @test num_variables(agr.model) == nva
    end
end

@testitem "admm adaptive rho: scale-invariant convergence 2-bus AND ieee13 (adaptive, rho)" setup =
    [Phase7Fixtures, Phase6Fixtures, Phase4Fixtures] tags = [:admm, :phase7] begin
    using TSODSO

    # RED until Wave 3 (adaptive-ρ policy, plan 07-04, guarded by the 07-03 set_rho! seam).
    @test isdefined(TSODSO, :set_rho!)

    if isdefined(TSODSO, :set_rho!)
        # SAME per-unit config on both scales (no hard-coded scale-specific penalty, ADMM-02).
        cfg = (
            ρ = Phase7Fixtures.RHO0,
            ε_abs = Phase7Fixtures.EPS_ABS,
            ε_rel = Phase7Fixtures.EPS_REL,
            τ = Phase7Fixtures.TAU,
            μ = Phase7Fixtures.MU,
            ρ_min = Phase7Fixtures.RHO_MIN,
            ρ_max = Phase7Fixtures.RHO_MAX,
        )

        # 2-bus
        f2 = Phase6Fixtures.two_bus_feeder()
        a2 = Phase6Fixtures.build_two_bus_aggregators(f2)
        r2 = solve_admm(
            f2,
            ConvexBranchFlow(),
            a2;
            T = Phase6Fixtures.T,
            λ₀ = Phase6Fixtures.two_bus_lambda0(),
            maxiter = 500,
            allow_export = true,
            cfg...,
        )
        @test r2.iters < 500
        @test converged(
            r2.residuals,
            last(r2.residuals.eps_pri_trace),
            last(r2.residuals.eps_dual_trace),
        )

        # IEEE-13 (congestion-driven) — SAME cfg must also converge (scale invariance).
        f13 = ieee13_modified()
        a13 = Phase4Fixtures.build_ieee13_ground_aggregators(f13)
        r13 = solve_admm(
            f13,
            ConvexBranchFlow(),
            a13;
            T = Phase4Fixtures.T,
            λ₀ = Phase4Fixtures.mem_price_profile(),
            maxiter = 500,
            allow_export = true,
            cfg...,
        )
        @test r13.iters < 500
        @test r13.exact_maxgap < 1e-3
    end
end

@testitem "admm transit dso: zero-injection non-load bus accepted (transit, dso)" setup =
    [Phase7Fixtures] tags = [:admm, :phase7] begin
    using TSODSO

    # RED until Wave 2/3 (plan 07-03 relaxes the DSO-OPT transit-node guard). The observable
    # signal is a feeder with a genuine TRANSIT bus (non-root, no aggregator) no longer throwing.
    @test isdefined(TSODSO, :set_rho!)

    if isdefined(TSODSO, :set_rho!) && isdefined(TSODSO, :build_dso_opt)
        # 3-bus radial: root(1) → transit(2, NO aggregator) → load(3, aggregator). Bus 2 is a
        # genuine zero-injection junction — the Phase-6 guard rejected it; Phase 7 must accept it.
        buses = [Bus(1, 0.95, 1.05, true), Bus(2, 0.9, 1.1, false), Bus(3, 0.9, 1.1, false)]
        branches = [Branch(1, 2, 0.02, 0.02, 99.0), Branch(2, 3, 0.02, 0.02, 99.0)]
        feeder = Feeder(buses, branches, 1)

        aggs = Phase7Fixtures.build_ieee123_aggregators(feeder; load_buses = [3])   # ONLY bus 3
        Th = Phase7Fixtures.T
        λ₀ = Phase7Fixtures.ieee123_lambda0()

        # Building the DSO-OPT over a feeder with a transit bus must NOT throw (zero injection pinned).
        dso = build_dso_opt(feeder, aggs, Th; ρ = Phase7Fixtures.RHO0, λ₀ = λ₀)
        @test hasproperty(dso, :model)
    end
end
