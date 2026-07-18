# Seam: devices/PVBattery.jl (DEV-04). PV + battery (BESS), no binaries.
#
# RED in Wave 0: the `PVBattery` device does not exist yet — plan 03-04 turns this
# green (incl. the mandatory post-solve p_ch·p_dch < τ complementarity check, App. C).
# The name contains "battery" so `occursin("battery", ti.name)` selects it. Uses the
# shared T=24 fixture to prove the harness wiring is healthy.

@testitem "battery: PVBattery device type exists over the T=24 fixture (DEV-04)" tags = [:battery] setup = [Phase3Fixtures] begin
    using TSODSO

    # The shared fixture is healthy (exercises setup wiring): a valid 3-bus feeder + T=24 PV profile.
    feeder = Phase3Fixtures.small_radial_feeder()
    @test length(feeder.buses) == 3
    @test length(Phase3Fixtures.Ppv) == Phase3Fixtures.T == 24

    # Plan 03-04 will add the no-binary PV+battery device (SOC 3.6-3.9, utility 3.15-3.20).
    @test isdefined(TSODSO, :PVBattery)
end
