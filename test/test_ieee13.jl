# Seam: data/ieee13.jl (DATA-03) + the IEEE-13 GLB-CVX SOCP solve (OPT-02/OPT-03).
#
# RED @testitem harness (Wave 1). The modified IEEE 13-node fixture `ieee13_modified()`
# is filled by plan 04-03; the SOCP solve on it depends on ConvexBranchFlow (04-02) and
# the ground-truth regression on the oracle/golden (04-04/04-06). Item names contain
# "ieee13" (fixture + solve) and "ground" (thesis-number regression) so the respective
# `occursin(...)` filters select them. Behavioral asserts sit behind `isdefined` guards so
# they go live as each owning wave lands; while RED the failing assertions are clean
# missing-symbol checks.

@testitem "ieee13: ieee13_modified constructs radial — 11 buses, 10 branches, root at index 1 (DATA-03)" tags = [
    :ieee13,
] begin
    using TSODSO

    # RED until plan 04-03 ships the fixture.
    @test isdefined(TSODSO, :ieee13_modified)

    if isdefined(TSODSO, :ieee13_modified)
        feeder = TSODSO.ieee13_modified()               # runs assert_radial + assert_magnitudes
        @test length(feeder.buses) == 11                 # thesis node 0 + nodes 1..10
        @test length(feeder.branches) == 10              # radial tree ⇒ buses − 1
        @test feeder.root == 1                            # index 1 = thesis MEM frontier (node 0)
    end
end

@testitem "ieee13: GLB-CVX SOCP solve is OPTIMAL with a finite nodal-balance dual (OPT-02)" tags = [
    :ieee13,
] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    # RED until BOTH the fixture (04-03) and the SOCP formulation (04-02) land.
    @test isdefined(TSODSO, :ieee13_modified)
    @test isdefined(TSODSO, :ConvexBranchFlow)

    if isdefined(TSODSO, :ieee13_modified) && isdefined(TSODSO, :ConvexBranchFlow)
        feeder = TSODSO.ieee13_modified()
        aggs = Phase4Fixtures.build_ieee13_aggregators(feeder; seed = 20260718)
        λ₀ = Phase4Fixtures.mem_price_profile()

        pf = TSODSO.ConvexBranchFlow()
        ctx, obj, dadp = solve_welfare(
            feeder, pf, aggs;
            T = Phase4Fixtures.T, λ₀ = λ₀,
            optimizer = select_optimizer(problem_class(pf)),
        )

        @test isfinite(obj)                              # OPTIMAL (else solve_welfare threw)
        @test length(dadp) == Phase4Fixtures.T
        @test all(isfinite, dadp)                        # nodal-balance dual available
    end
end

@testitem "ground: IEEE-13 SOCP reproduces thesis voltage/DADP within tolerance (OPT-02/OPT-03)" tags = [
    :ieee13,
    :ground,
] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    # RED until the fixture (04-03), the SOCP formulation (04-02), and the pinned golden
    # (04-04/04-06) land. The exact thesis-figure match (|V₉|[16] ≈ 1.0493, welfare ≈ $1819)
    # is a documented cross-check within tolerance (RESEARCH Open Q1); the tight pinned
    # golden is finalized by the oracle/ground-truth wave behind a human-verify checkpoint.
    @test isdefined(TSODSO, :ieee13_modified)
    @test isdefined(TSODSO, :ConvexBranchFlow)

    if isdefined(TSODSO, :ieee13_modified) && isdefined(TSODSO, :ConvexBranchFlow)
        feeder = TSODSO.ieee13_modified()
        aggs = Phase4Fixtures.build_ieee13_aggregators(feeder; seed = 20260718)
        λ₀ = Phase4Fixtures.mem_price_profile()

        pf = TSODSO.ConvexBranchFlow()
        ctx, obj, dadp = solve_welfare(
            feeder, pf, aggs;
            T = Phase4Fixtures.T, λ₀ = λ₀,
            optimizer = select_optimizer(problem_class(pf)),
        )

        # Voltage MAGNITUDE at thesis node 9 (struct index 10), hour 16 — |V| = √v (A1).
        pv = ctx.meta[:pf_vars]
        v9_16 = sqrt(value(pv.v[10, 16]))
        @test 0.95 <= v9_16 <= 1.05                      # in the per-unit voltage band
        @test isapprox(v9_16, 1.0493; atol = 5e-2)        # approximate thesis cross-check (Open Q1)
        @test all(isfinite, dadp)
    end
end
