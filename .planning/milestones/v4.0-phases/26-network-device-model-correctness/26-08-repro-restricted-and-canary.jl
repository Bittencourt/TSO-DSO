# Plan 26-08 Task 1 companion reproduction script.
#
# Purpose: a literal, self-contained, non-TestItemRunner re-derivation of the two goldens
# Plan 26-08's SC-6 golden-policy obligation must re-verify after Plans 26-02..07 land:
#   1. RestrictedBranchFlow._EXACT04_MEASURED_ε (the Gan-Low modification gap ε, measured on
#      the EXACT-04 high-PV fixture) — test/test_restricted_branch_flow.jl's own @testitem.
#   2. test/test_admm_knifeedge_canary.jl's pinned IEEE-13 ADMM trajectory (iters + welfare).
#
# Run via `julia --project=. .planning/phases/26-network-device-model-correctness/26-08-repro-restricted-and-canary.jl`.
# Exits nonzero (via @assert) if either live re-measurement no longer matches what is
# currently pinned in the source — per this plan's action, THAT is the signal to
# re-measure and update the pinned constant (or the two literals just below, kept in sync
# with whatever this task ends up pinning in the two real test files) with an
# old->new+cause comment, never to silently loosen this script's tolerances.
#
# The Phase4FixturesRepro module below is a plain-module copy of test/fixtures_phase4.jl's
# @testmodule body (the `@testmodule`/`@testitem` macros do not resolve under a bare
# `julia --project=.` invocation — see the gsd-plan-verify-testitemrunner-trap memory) — kept
# in sync with that file's `high_pv_feeder`/`build_high_pv_aggregators`/`_house_aggregator`
# by inspection if it is ever extended. Verified against the CURRENT (pre-Phase-26) code
# during the 26-08 plan revision session: ε_measured=0.005811069152331871 (pinned base
# 0.005811069127373614), ADMM iters=58, welfare=-4822.90361661042 (pinned
# -4822.903616694139) — all within tolerance, confirming this script reproduces both
# existing goldens exactly before any Phase-26 code change lands.

using TSODSO
using Logging: with_logger, SimpleLogger, Warn
using JuMP

module Phase4FixturesRepro
using TSODSO

const T = 24
const BATT_λ_MIN = 3.8
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9

function temperature_profile()
    return Float64[
        19, 18, 17, 16, 16, 17,
        19, 21, 23, 26, 28, 30,
        31, 32, 32, 31, 29, 27,
        25, 23, 22, 21, 20, 19,
    ]
end

function _house_aggregator(
    feeder,
    bus;
    seed::Integer,
    φ::Real,
    pv_scale::Real = 1.0,
    load_scale::Real = 1.0,
    batt_pmax::Real = 0.5,
    batt_emax::Real = 2.0,
    batt_soc0::Real = 1.0,
)
    prof = generate_profiles(seed = seed + bus, T = T)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, temperature_profile())
    defer = Deferrable(bus, 8, 16, 1.0, 0.5, 0.5)
    batt = PVBattery(
        bus, 0.95, 1.0, batt_pmax, 0.0, batt_emax, batt_soc0,
        BATT_λ_MIN, BATT_λ_MED, BATT_λ_MAX, Ppv,
    )
    return Aggregator(bus, φ, [therm, defer, batt], Pdc)
end

function high_pv_feeder()
    buses = [
        Bus(1, 0.95, 1.05, true),
        Bus(2, 0.95, 1.05, false),
        Bus(3, 0.95, 1.05, false),
    ]
    branches = [Branch(1, 2, 0.05, 0.05, 99.0), Branch(2, 3, 0.05, 0.05, 99.0)]
    return Feeder(buses, branches, 1)
end

function build_high_pv_aggregators(feeder; seed::Integer = 20260406, pv_scale::Real = 0.5)
    N = length(feeder.buses)
    return [
        _house_aggregator(
            feeder, bus;
            seed = seed, φ = 0.95, pv_scale = pv_scale, load_scale = 0.2,
            batt_pmax = 0.1, batt_emax = 0.2, batt_soc0 = 0.1,
        ) for bus in 2:N
    ]
end
end # module

# --- (1) Re-measure the Gan-Low modification gap ε on the EXACT-04 fixture, exactly as
# test_restricted_branch_flow.jl's "measured Gan-Low modification gap ε" @testitem does ---
feeder = Phase4FixturesRepro.high_pv_feeder()
aggs = Phase4FixturesRepro.build_high_pv_aggregators(feeder; pv_scale = 1.2)
mem_price = Float64[
    3.8, 3.7, 3.6, 3.6, 3.7, 4.0,
    4.8, 5.8, 6.5, 6.2, 5.9, 5.7,
    5.6, 5.8, 6.0, 6.8, 8.2, 9.0,
    8.6, 7.4, 6.2, 5.2, 4.4, 4.0,
]

ctx_ac, cost_ac, _ = TSODSO.solve_welfare(
    feeder, TSODSO.ACPowerFlow(), aggs;
    T = Phase4FixturesRepro.T, λ₀ = mem_price, allow_local = true, allow_export = true,
)
v̂_GL = TSODSO.recover_lossfree_shadow_voltage(ctx_ac)
pv_ac = ctx_ac.meta[:pf_vars]
N = length(feeder.buses)
ε_measured = maximum(
    v̂_GL[j, t] - value(pv_ac.v[j, t]) for j in 1:N, t in 1:Phase4FixturesRepro.T
)
pinned_ε_base = TSODSO._EXACT04_MEASURED_ε / 1.25   # the source stores ε_measured * 1.25
println(
    "live ε_measured=$ε_measured  pinned(base)=$pinned_ε_base  " *
    "pinned(with 1.25x)=$(TSODSO._EXACT04_MEASURED_ε)",
)
# Phase 26 gap-closure (Plan 26-08): re-measured 2026-09-29 after Plan 26-14's App. C
# throw-to-diagnostic conversion unblocked this AC-oracle-based measurement. OLD pinned
# base 0.005811069127373614 -> NEW pinned base 0.010189528427785532; see
# src/powerflow/RestrictedBranchFlow.jl's `_EXACT04_MEASURED_ε` comment for the full cause.
@assert isapprox(ε_measured, pinned_ε_base; rtol = 1e-6) "RestrictedBranchFlow._EXACT04_MEASURED_ε is STALE vs a live re-measurement (live=$ε_measured, pinned-base=$pinned_ε_base) -- re-measure and update the constant in src/powerflow/RestrictedBranchFlow.jl with an old->new+cause comment (Phase 26 FIX-01/02), then update this script's expectation to match"

# --- (2) Re-run the IEEE-13 ADMM knife-edge canary trajectory, exactly as
# test_admm_knifeedge_canary.jl does ---
kw = (name = "phase8-fixture", feeder = :ieee13, strategy = :admm, seed = 7, T = 24)
s = TSODSO.Scenario(; kw...)
buf = IOBuffer()
r = with_logger(SimpleLogger(buf, Warn)) do
    TSODSO.run_scenario(s)
end
println("live ADMM canary: iters=$(r.iters) welfare=$(r.welfare)")
# PINNED literals below MUST be kept in sync with test/test_admm_knifeedge_canary.jl's own
# pinned assertions -- if this task updates that file's r.iters/r.welfare goldens, update
# these two literals identically in the SAME commit.
#
# Phase 26 gap-closure (Plan 26-08, Task 1): this canary trajectory is Plan 26-20's own
# responsibility (re-pinned strictly after Plan 26-12's live-reactive-default fix), NOT
# re-derived by this task -- Task 1 only cross-referenced it for the NO-DISCREPANCY check
# its own action text requires. Re-running this script here (2026-09-29, after ALL of Plans
# 26-01..26-20 are merged) reproduces Plan 26-20's own pinned values EXACTLY (r.iters=56,
# r.welfare=-4823.66604824162, bit-identical) -- NO discrepancy found; these literals are
# updated to match 26-20-SUMMARY.md/test/test_admm_knifeedge_canary.jl's already-landed
# re-pin (OLD 58/-4822.903616694139 -> NEW 56/-4823.66604824162), not independently
# re-derived.
@assert r.iters == 56 "ADMM knife-edge canary iteration count moved (live=$(r.iters), pinned=56) -- update test/test_admm_knifeedge_canary.jl AND this script with an old->new+cause comment"
@assert isapprox(r.welfare, -4823.66604824162; rtol = 1e-6, atol = 1e-3) "ADMM knife-edge canary welfare moved (live=$(r.welfare), pinned=-4823.66604824162) -- update test/test_admm_knifeedge_canary.jl AND this script with an old->new+cause comment"

println("OK: RestrictedBranchFlow ε + ADMM knife-edge canary both re-verified against their currently pinned values")
