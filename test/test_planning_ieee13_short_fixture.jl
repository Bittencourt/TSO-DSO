# test/test_planning_ieee13_short_fixture.jl
#
# Seam: smoke test for the
# `IEEE13ShortHorizonFixtures` fixture module (`test/fixtures_planning_ieee13_short.jl`):
# confirms the independently-built monolithic joint-reference solver
# (`solve_joint_reference`, NEVER a reuse of `PlanningOracle`/`FollowerLP`/
# `BendersMaster`) solves on the fixture's own tuned T=4 IEEE-13 population and returns a
# finite optimum. The end-to-end Benders convergence `@testitem` consumes this SAME fixture module via
# `setup=[IEEE13ShortHorizonFixtures]`.

@testitem "planning ieee13 short fixture: solve_joint_reference solves and returns a finite optimum" tags =
    [:planning] setup = [IEEE13ShortHorizonFixtures] begin
    using TSODSO

    feeder = TSODSO.ieee13_modified()
    aggs = IEEE13ShortHorizonFixtures.population(feeder)
    T = IEEE13ShortHorizonFixtures.T

    # Small, documented investment/corridor tuple, consistent with the fixture's own
    # tuned λ₀/population scale (feasible-and-exact z window ≈ [-0.05, 0.05] pu/hr, per
    # fixtures_planning_ieee13_short.jl's own header comment): cheap enough investment
    # (`c_y`, `c_inv`, `c_op`) that the joint solve can freely explore up to `y_max`
    # without leaving that window.
    c_y = 0.01
    y_max = 0.05
    corridor_cap = 1.0
    x_inv_max = 0.05
    c_inv = 0.01
    c_op = fill(0.01, T)

    result = IEEE13ShortHorizonFixtures.solve_joint_reference(
        feeder,
        aggs;
        λ₀ = IEEE13ShortHorizonFixtures.LAMBDA0,
        T = T,
        c_y = c_y,
        y_max = y_max,
        corridor_cap = corridor_cap,
        x_inv_max = x_inv_max,
        c_inv = c_inv,
        c_op = c_op,
    )

    @test isfinite(result.welfare_total)
    @test 0 <= result.y <= y_max
    @test all(result.z .>= -1e-6)
end
