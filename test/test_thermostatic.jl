# Seam: devices/Thermostatic.jl (DEV-01). Thermostatic (A/C) flexible load.
#
# RED in Wave 0: the `Thermostatic` device does not exist yet — plan 03-03 turns this
# green. The name contains "thermostatic" so `occursin("thermostatic", ti.name)` selects it.

@testitem "thermostatic: device type exists (DEV-01)" tags = [:thermostatic] begin
    using TSODSO

    # Plan 03-03 will add the thermostatic device (recursion 3.2-3.3, comfort band, utility 3.11).
    @test isdefined(TSODSO, :Thermostatic)
end
