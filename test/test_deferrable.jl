# Seam: devices/Deferrable.jl (DEV-02). Deferrable (shiftable) flexible load.
#
# RED in Wave 0: the `Deferrable` device does not exist yet — plan 03-03 turns this
# green. The name contains "deferrable" so `occursin("deferrable", ti.name)` selects it.

@testitem "deferrable: device type exists (DEV-02)" tags = [:deferrable] begin
    using TSODSO

    # Plan 03-03 will add the deferrable device (energy-window coupling 3.4-3.5, utility 3.12).
    @test isdefined(TSODSO, :Deferrable)
end
