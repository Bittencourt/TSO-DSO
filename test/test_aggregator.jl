# Seam: devices/Aggregator.jl (DEV-05). Aggregator roll-up, the network-facing writer.
#
# RED in Wave 0: the `Aggregator` type does not exist yet — plan 03-05 turns this green.
# The name contains "aggregator" so `occursin("aggregator", ti.name)` selects it.

@testitem "aggregator: roll-up type exists (DEV-05)" tags = [:aggregator] begin
    using TSODSO

    # Plan 03-05 will add the aggregator that sums devices into nodal net P/Q + utility (3.21-3.23).
    @test isdefined(TSODSO, :Aggregator)
end
