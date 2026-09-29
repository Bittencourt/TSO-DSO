# Direct Test.jl reproduction of test_pricing_fit.jl's "fit: FIT-vs-DADP ratio regression
# golden (EXP-04)" testitem, per the project memory that TestItemRunner does not resolve
# under `julia --project=.` (gsd-plan-verify-testitemrunner-trap). Re-inlines the FitFixtures
# @testmodule body (feeder + aggregators) as plain functions since @testmodule is a
# TestItems-only macro not available in the package environment.
#
# Phase 26 gap-closure (26-17, Task 2): re-measures and re-pins FIT_RATIO_GOLDEN after
# FIX-04 (battery soc[T+1] horizon linking) closed PVBattery's free hour-T discharge on
# this T=4 fixture. OLD 0.6428101637491034 -> NEW 0.772018581825438 (PM-06).
using Test
using TSODSO
using TSODSO: Bus, Branch, Feeder

const T = 4

function fitfixtures_feeder()
    buses = [
        Bus(1, 0.95, 1.05, true),     # root / MEM frontier
        Bus(2, 0.95, 1.05, false),
        Bus(3, 0.95, 1.05, false),
    ]
    branches = [Branch(1, 2, 0.02, 0.03, 10.0), Branch(2, 3, 0.02, 0.03, 10.0)]
    return Feeder(buses, branches, 1)
end

function fitfixtures_aggregators(; seed::Integer)
    aggs = TSODSO.Aggregator[]
    for bus in 2:3
        prof = generate_profiles(seed = seed + bus, T = T)
        defer = Deferrable(bus, 1, T, 0.4, 0.3, 1.0)
        batt = PVBattery(bus, 0.95, 1.0, 0.3, 0.0, 1.0, 0.5, 1.0, 2.0, 3.0, prof.pv)
        push!(aggs, Aggregator(bus, 0.9, [defer, batt], prof.demand))
    end
    return aggs
end

feeder = fitfixtures_feeder()
aggs = fitfixtures_aggregators(seed = 20260718)

res = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = T)

# Phase 26 gap-closure re-pin (PM-06) — FIX-04 closed PVBattery's free hour-T discharge on
# this T=4 fixture. OLD 0.6428101637491034 -> NEW 0.772018581825438.
FIT_RATIO_GOLDEN = 0.772018581825438

@testset "26-17 repro: fit ratio golden" begin
    @test isapprox(res.ratio, FIT_RATIO_GOLDEN; rtol = 1e-4)
end
