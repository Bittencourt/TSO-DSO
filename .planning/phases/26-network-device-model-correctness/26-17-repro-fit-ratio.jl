# .planning/phases/26-network-device-model-correctness/26-17-repro-fit-ratio.jl
#
# Direct-script reproduction of test/test_pricing_fit.jl's EXP-04 "FIT-vs-DADP ratio regression
# golden" testitem (Plan 26-17, Task 2) — TestItemRunner traps under --project=. (see the
# gsd-plan-verify-testitemrunner-trap memory), so this script reconstructs the `FitFixtures`
# @testmodule inline (byte-identical to test/test_pricing_fit.jl's own definition) and asserts
# against the CURRENTLY-PINNED `FIT_RATIO_GOLDEN` constant, PARSED LIVE from the edited test
# file (never hardcoded here), so a wrong (or missing) re-pin fails this check.

using TSODSO
using TSODSO: Bus, Branch, Feeder

const FIT_T = 4

function fit_fixture_feeder()
    buses = [
        Bus(1, 0.95, 1.05, true),
        Bus(2, 0.95, 1.05, false),
        Bus(3, 0.95, 1.05, false),
    ]
    branches = [Branch(1, 2, 0.02, 0.03, 10.0), Branch(2, 3, 0.02, 0.03, 10.0)]
    return Feeder(buses, branches, 1)
end

function fit_fixture_aggregators(; seed::Integer)
    aggs = TSODSO.Aggregator[]
    for bus in 2:3
        prof = generate_profiles(seed = seed + bus, T = FIT_T)
        defer = Deferrable(bus, 1, FIT_T, 0.4, 0.3, 1.0)
        batt = PVBattery(bus, 0.95, 1.0, 0.3, 0.0, 1.0, 0.5, 1.0, 2.0, 3.0, prof.pv)
        push!(aggs, Aggregator(bus, 0.9, [defer, batt], prof.demand))
    end
    return aggs
end

feeder = fit_fixture_feeder()
aggs = fit_fixture_aggregators(seed = 20260718)
res = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = FIT_T)
println("MEASURED res.ratio = ", res.ratio)

src = read("test/test_pricing_fit.jl", String)
m = match(r"FIT_RATIO_GOLDEN\s*=\s*([0-9.eE+-]+)", src)
m === nothing && error(
    "Could not parse FIT_RATIO_GOLDEN from test/test_pricing_fit.jl — Plan 26-17 Task 2 must " *
    "re-pin this constant",
)
pinned = parse(Float64, m.captures[1])
println("PARSED pinned FIT_RATIO_GOLDEN = ", pinned)

isapprox(res.ratio, pinned; rtol = 1e-4) || error(
    "FIT_RATIO_GOLDEN re-pin FAILED: measured res.ratio=$(res.ratio) vs pinned=$(pinned)",
)
println("OK: measured ratio matches the pinned FIT_RATIO_GOLDEN within rtol=1e-4")
