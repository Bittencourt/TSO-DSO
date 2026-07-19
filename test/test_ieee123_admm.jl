# test/test_ieee123_admm.jl
#
# Seam: the IEEE-123 ADMM scale target — the failing END-TO-END test (the MVP first
# deliverable). Plan 07-05 greens it once the fixture (07-02), the adaptive-ρ / transit
# relaxation (07-03), and the two-residual stop (07-04) are all in place.
#
# RED @testitem harness (Wave 0 of Phase 7). NEVER edited to go green. Item names contain
# "ieee123" and "crossval" so the VALIDATION filters select them.
#
# RED SIGNAL (never a runner crash): the gate is `isdefined(TSODSO, :ieee123_modified) &&
# isdefined(TSODSO, :set_rho!)` (the fixture + the adaptive-ρ seam). Every behavioral assert
# sits BEHIND the guard.
#
# CONTRACT pinned here (the phase success criterion):
#   - ADMM converges in ~tens of iterations (well under the fail-loud cap) on the voltage-
#     constrained 123-node case with the SAME per-unit adaptive-ρ config as the smaller feeders.
#   - the recovered price `λ_j → DADP` matches `extract_dlmp` on the centralized SOCP (ADMM-03),
#     and the converged DSO-OPT is PF-04 exact (`exact_maxgap` small) at the binding-voltage point.

@testitem "ieee123 admm: end-to-end converge + DADP cross-validation (ieee123, crossval)" setup = [
    Phase7Fixtures,
] tags = [:admm, :phase7] begin
    using TSODSO

    # RED until Waves 2–4 (fixture 07-02, adaptive-ρ/transit 07-03, two-residual stop 07-04,
    # end-to-end green 07-05).
    @test isdefined(TSODSO, :ieee123_modified)
    @test isdefined(TSODSO, :set_rho!)

    if isdefined(TSODSO, :ieee123_modified) && isdefined(TSODSO, :set_rho!)
        feeder = ieee123_modified()
        Th = Phase7Fixtures.T
        λ₀ = Phase7Fixtures.ieee123_lambda0()

        # one seeded aggregator per LOAD node; the transit (junction) buses carry zero injection.
        aggs = Phase7Fixtures.build_ieee123_aggregators(feeder)
        load_buses = [a.bus for a in aggs]

        # Centralized ground truth: the monolithic SOCP welfare + its DADP duals (ADMM-03 oracle).
        ctx_c, obj_c, _ = solve_welfare(
            feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀, allow_export = true,
        )
        dlmp_c = reduce(
            vcat, (extract_dlmp(ctx_c; bus = b, T = Th)' for b in load_buses),
        )

        # ADMM with the SAME per-unit adaptive-ρ config (scale-invariant, ADMM-02).
        res = solve_admm(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, ρ = Phase7Fixtures.RHO0,
            ε_abs = Phase7Fixtures.EPS_ABS, ε_rel = Phase7Fixtures.EPS_REL,
            τ = Phase7Fixtures.TAU, μ = Phase7Fixtures.MU,
            ρ_min = Phase7Fixtures.RHO_MIN, ρ_max = Phase7Fixtures.RHO_MAX,
            maxiter = 300, allow_export = true,
        )

        @test res.iters < 300                                   # converged before the fail-loud cap
        @test isapprox(res.welfare, obj_c; rtol = 1e-4)         # welfare match (ADMM-04)
        @test res.exact_maxgap < 1e-3                           # PF-04 exact on the converged DSO-OPT
        @test isapprox(res.λ, dlmp_c; atol = 1e-2, rtol = 1e-3) # DADP → centralized price (λ_j → DADP)
    end
end
