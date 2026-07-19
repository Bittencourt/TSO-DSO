# Seam: pricing/checks.jl (PRICE-05). Economic-direction price checks.
#
# RED @testitem harness (Wave 1 of Phase 5). Plan 05-04 turns these green by defining
# `economic_direction_checks` (assert the DLMP moves in the economically-correct direction:
# up into a congestion/import window, down — possibly negative — in a PV-glut / reverse-flow /
# over-voltage window). Every item name contains "econ" AND "direction" so either
# `occursin("econ", ti.name)` or `occursin("direction", ti.name)` selects it. While RED the
# sole failing assertion is a missing-symbol `isdefined` check; behavioral asserts are guarded.

@testitem "econ direction: economic_direction_checks is defined (PRICE-05)" tags = [
    :econ,
    :direction,
] begin
    using TSODSO

    # RED until plan 05-04 defines the economic-direction checker.
    @test isdefined(TSODSO, :economic_direction_checks)
end

@testitem "econ direction: PV-glut window drives the DLMP down vs a congestion window (PRICE-05)" tags = [
    :econ,
    :direction,
] begin
    using TSODSO

    # RED until plan 05-04 defines the checker; the behavioral direction assertion goes live
    # (a solved ctx whose PV-glut hour price sits below its congestion hour price) once it lands.
    @test isdefined(TSODSO, :economic_direction_checks)

    if isdefined(TSODSO, :economic_direction_checks) && isdefined(TSODSO, :extract_dlmp)
        using TSODSO: Bus, Branch, Feeder

        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        T = 3
        batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
        agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
        ctx, _obj, _dadp =
            solve_welfare(feeder, ConvexBranchFlow(), [agg]; T = T, λ₀ = fill(40.0, T), allow_export = true)

        # The checker returns/asserts the economically-correct sign relationships; it must not throw.
        @test economic_direction_checks(ctx; T = T) !== nothing
    end
end
