# Seam: pricing/fit.jl (PRICE-04). Flat feed-in-tariff (FIT) baseline counterfactual.
#
# RED @testitem harness (Wave 1 of Phase 5). Plan 05-03 turns these green by defining
# `fit_baseline` (re-solve the operational welfare under a flat feed-in tariff and return the
# baseline welfare / prices + the DLMP-vs-FIT efficiency ratio). Every item name contains
# "fit" so `occursin("fit", ti.name)` selects it. While RED the sole failing assertion is a
# missing-symbol `isdefined` check; the behavioral asserts sit behind the `isdefined` guard.

@testitem "fit: fit_baseline is defined and returns a finite baseline welfare (PRICE-04)" tags = [
    :fit,
] begin
    using TSODSO

    # RED until plan 05-03 defines the FIT baseline.
    @test isdefined(TSODSO, :fit_baseline)

    if isdefined(TSODSO, :fit_baseline)
        using TSODSO: Bus, Branch, Feeder

        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        T = 3
        batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
        agg = Aggregator(2, 0.9, [batt], fill(0.1, T))

        res = fit_baseline(feeder, ConvexBranchFlow(), [agg]; λ_fit = 40.0, T = T)
        @test isfinite(res.welfare)
    end
end

@testitem "fit: the DLMP-vs-FIT efficiency ratio is a finite positive scalar (PRICE-04)" tags = [
    :fit,
] begin
    using TSODSO

    # RED until plan 05-03 exposes the efficiency ratio.
    @test isdefined(TSODSO, :fit_baseline)

    if isdefined(TSODSO, :fit_baseline)
        using TSODSO: Bus, Branch, Feeder

        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        T = 3
        batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
        agg = Aggregator(2, 0.9, [batt], fill(0.1, T))

        res = fit_baseline(feeder, ConvexBranchFlow(), [agg]; λ_fit = 40.0, T = T)
        @test res.ratio > 0
        @test isfinite(res.ratio)
    end
end
