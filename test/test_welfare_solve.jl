# Seam: models/welfare_solve.jl (OPT-01). GLB-CVX centralized social-welfare solve.
#
# RED in Wave 0: `solve_welfare` does not exist yet — plan 03-05 turns this green
# (end-to-end multi-device GLB-CVX to a global optimum, plus the battery
# complementarity p_ch·p_dch < τ numeric check, App. C). The name contains "welfare"
# so `occursin("welfare", ti.name)` selects it. Uses the shared T=24 fixture to prove
# the harness wiring is healthy.

@testitem "welfare: GLB-CVX solve_welfare + battery complementarity over the T=24 fixture (OPT-01)" tags = [:welfare] setup = [Phase3Fixtures] begin
    using TSODSO

    # The shared fixture is healthy (exercises setup wiring): valid feeder + T=24 price/demand.
    feeder = Phase3Fixtures.small_radial_feeder()
    @test feeder.root == 1
    @test length(Phase3Fixtures.λ₀) == length(Phase3Fixtures.Pdc) == Phase3Fixtures.T == 24

    # Plan 03-05 will add solve_welfare (eq. 3.38) with the WR-03 q_import frontier fix,
    # OPTIMAL gating, and the post-solve p_ch·p_dch < τ battery-complementarity assertion.
    @test isdefined(TSODSO, :solve_welfare)
end
