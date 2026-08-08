# Spike 004 — ac_dual_fallback_price multi-start agreement (D-11 fuller evidence).
#
# Replicates the EXACT-04 fixture (Phase4Fixtures.high_pv_feeder() /
# build_high_pv_aggregators(feeder; pv_scale = 1.2)) INLINE (per CONVENTIONS.md:
# "Replicate @testmodule fixtures locally, and verify the copy" — Phase4Fixtures is a
# TestItems @testmodule, unreachable from a plain script), calls
# `ac_dual_fallback_price(...; n_seeds = 5)` — the FULL 5-variant sweep, one seed per
# `_FALLBACK_IPOPT_VARIANTS` entry in src/models/ac_dual_fallback.jl — and answers: does the
# nonconvex-AC-dual fallback's price genuinely agree across 5 distinct Ipopt
# convergence-strategy starts on this fixture, or does a local-optimum artifact hide a
# genuinely unstable fallback price?
#
# POSITIVE CONTROL (non-negotiable, CONVENTIONS.md): `max_cost_spread < 1e-2` — a sanity
# bound proving the 5 variants are NOT wildly divergent. A genuine local-optimum artifact
# failing this bound would be a NEGATIVE finding worth surfacing honestly, not silently
# discarding (see README.md's verdict for the actual observed number).
#
# Run:  julia --project=. .planning/spikes/004-ovr-fallback-multistart/sweep.jl

using TSODSO
using JuMP
using CSV, DataFrames

const T = 24

# --- Inline fixture replication (verified against test/fixtures_phase4.jl at review time) ---
const TEMPERATURE = Float64[
    19, 18, 17, 16, 16, 17, 19, 21, 23, 26, 28, 30,
    31, 32, 32, 31, 29, 27, 25, 23, 22, 21, 20, 19,
]
const MEM_PRICE = Float64[
    3.8, 3.7, 3.6, 3.6, 3.7, 4.0, 4.8, 5.8, 6.5, 6.2, 5.9, 5.7,
    5.6, 5.8, 6.0, 6.8, 8.2, 9.0, 8.6, 7.4, 6.2, 5.2, 4.4, 4.0,
]
const BATT_λ_MIN = 3.8
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9

function high_pv_feeder()
    buses = [
        Bus(1, 0.95, 1.05, true),
        Bus(2, 0.95, 1.05, false),
        Bus(3, 0.95, 1.05, false),
    ]
    branches = [
        Branch(1, 2, 0.05, 0.05, 99.0),
        Branch(2, 3, 0.05, 0.05, 99.0),
    ]
    return Feeder(buses, branches, 1)
end

function build_high_pv_aggregators(feeder; seed::Integer = 20260406, pv_scale::Real = 0.5)
    N = length(feeder.buses)
    return [
        begin
            prof = generate_profiles(seed = seed + bus, T = T)
            Ppv = Float64[pv_scale * p for p in prof.pv]
            Pdc = Float64[0.2 * d for d in prof.demand]
            therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, TEMPERATURE)
            defer = Deferrable(bus, 8, 16, 1.0, 0.5, 0.5)
            batt = PVBattery(
                bus, 0.95, 1.0, 0.1, 0.0, 0.2, 0.1, BATT_λ_MIN, BATT_λ_MED, BATT_λ_MAX, Ppv,
            )
            Aggregator(bus, 0.95, [therm, defer, batt], Pdc)
        end for bus in 2:N
    ]
end

# --- Verify the copy against the original before trusting it (CONVENTIONS.md) ---
feeder = high_pv_feeder()
aggs = build_high_pv_aggregators(feeder; pv_scale = 1.2)
@assert length(feeder.buses) == 3 "fixture copy drift: expected 3 buses"
@assert length(feeder.branches) == 2 "fixture copy drift: expected 2 branches"
@assert length(aggs) == 2 "fixture copy drift: expected 2 aggregators (buses 2:3)"
println("Fixture copy verified: 3 buses, 2 branches, 2 aggregators.")

# --- The FULL 5-seed sweep ---
result = ac_dual_fallback_price(
    feeder,
    aggs;
    T = T,
    λ₀ = MEM_PRICE,
    allow_export = true,
    n_seeds = 5,
)

report = result.agreement_report
println()
println("seed_variant | cost            | max |dadp - dadp[1]|")
println("-------------|-----------------|--------------------")
rows = NamedTuple[]
for i in 1:report.n_seeds
    dadp_dev = maximum(abs.(report.dadps[i] .- report.dadps[1]))
    println(rpad(string(i), 13), "| ", rpad(string(report.costs[i]), 17), "| ", dadp_dev)
    push!(rows, (; seed_variant = i, cost = report.costs[i], max_abs_dadp_dev = dadp_dev))
end
println()
println("max_cost_spread = ", report.max_cost_spread)
println("max_dadp_spread = ", report.max_dadp_spread)
println("price_status = ", result.price_status)

df = DataFrame(rows)
csv_path = joinpath(@__DIR__, "sweep.csv")
CSV.write(csv_path, df)
println("Wrote ", csv_path)

# --- Positive control (CONVENTIONS.md: every sweep must contain a known control) ---
if report.max_cost_spread < 1e-2
    println("POSITIVE CONTROL PASSED: max_cost_spread = $(report.max_cost_spread) < 1e-2 — the 5 Ipopt variants agree; no local-optimum artifact masking instability.")
else
    println("POSITIVE CONTROL FAILED: max_cost_spread = $(report.max_cost_spread) >= 1e-2 — a genuine finding, document honestly in README.md, do not discard.")
end
