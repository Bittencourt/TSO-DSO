# Seam: powerflow/MeshedFlow.jl (MESH-02). Driven green by plan 23-02.
@testitem "MeshedFlow solves the loop fixture via solve_welfare on both impedance profiles (MESH-02)" setup =
    [Phase23Fixtures] begin
    using TSODSO, Test

    for profile in (:uniform, :heterogeneous)
        feeder = Phase23Fixtures.mesh_feeder(profile)
        aggs = Phase23Fixtures.mesh_aggregators()
        λ₀ = Phase23Fixtures.mesh_lambda0()

        # solve_welfare returns without throwing (assert_solved! + assert_socp_exact! both
        # pass on BOTH impedance profiles -- the existing cone-tightness gate cannot tell
        # them apart, per RESEARCH.md's Pitfall 14; that is exactly what plan 23-03's NEW
        # angle-recoverability certificate is for).
        ctx, w, dadp =
            solve_welfare(feeder, MeshedFlow(), aggs; T = Phase23Fixtures.T_MESH, λ₀ = λ₀)

        @test ctx.meta[:formulation] == :MeshedFlow
        @test length(dadp) == Phase23Fixtures.T_MESH
        @test isfinite(w)
    end

    # D-09-adjacent defense-in-depth check, at the FLOW level (mirrors plan 23-01's D-09
    # regression at the DATA level): the SAME 4-branch diamond edge list that MeshedFeeder
    # accepts (nB=4 > N-1=3, a genuine loop) still makes `Feeder` throw `ArgumentError` --
    # the radial gate is untouched, even after MeshedFlow has been exercised through
    # solve_welfare above.
    diamond_buses = [
        TSODSO.Bus(1, 0.95, 1.05, true),
        TSODSO.Bus(2, 0.90, 1.10, false),
        TSODSO.Bus(3, 0.90, 1.10, false),
        TSODSO.Bus(4, 0.90, 1.10, false),
    ]
    diamond_branches = [
        TSODSO.Branch(1, 2, 0.01, 0.02, TSODSO.SMAX_NO_LIMIT),
        TSODSO.Branch(1, 3, 0.01, 0.02, TSODSO.SMAX_NO_LIMIT),
        TSODSO.Branch(2, 4, 0.01, 0.02, TSODSO.SMAX_NO_LIMIT),
        TSODSO.Branch(3, 4, 0.01, 0.02, TSODSO.SMAX_NO_LIMIT),
    ]
    @test_throws ArgumentError TSODSO.Feeder(diamond_buses, diamond_branches, 1)
end
