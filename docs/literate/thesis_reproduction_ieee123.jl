# # Thesis Case A Reproduction — Real-Impedance IEEE-123
#
# This page live-executes the phase's headline finding: Palacios' PhD thesis (UNSJ/CONICET,
# 2022) Case A `[CITED: thesis p.98, Case A]` reports that day-ahead dynamic pricing (DADP)
# redistributes surplus from the DSO's transactive counterparty position toward the DSO itself —
# "DSO surplus -\$2829 -> +\$439" — compared to a German feed-in-tariff (FIT) baseline. This page
# reproduces that redistribution's **sign**, on real public OpenDSS-derived IEEE-123 impedances
# (Phase 17) with reactive pricing available (Phase 16), calling the REAL
# [`solve_welfare`](@ref), [`fit_baseline`](@ref), [`welfare_accounting`](@ref) and
# [`decompose_dlmp`](@ref) entrypoints end-to-end — never a re-derivation, so the numbers below
# cannot silently drift from the committed `src/` code (mirrors the
# [IEEE-123 Real Impedances — Public-Data Reduction](@ref) page's live-execution convention).
#
# ## Why NOT the aggregate welfare ratio
#
# The thesis's headline is often quoted as a **+25% aggregate social-welfare ratio**
# (`welfare_dadp / welfare_fit`). That ratio is NOT the claim on this page — dividing two
# welfare numbers that can each be negative silently inverts the intended "DADP is better"
# reading whenever the sign of the denominator flips (the promotion-source script's own Pitfall
# 1 guard). The full metric caveat — including the actual small, fragile aggregate welfare delta
# measured on this fixture — is enumerated in the companion
# [Thesis Reproduction — Assumptions & Reduction Chain](@ref) page; this page reports only the
# robust, correctly-signed **DSO-surplus sign flip** as its terminal finding.
#
# ## The "directional, public-data" qualifier
#
# Every cited reproduction number on this page carries the fixed qualifier below (the phase's
# one new convention) so a reader never mistakes a directional, public-data reproduction for an
# exact-figure claim:

const REPRO_QUALIFIER = "directional, public-data"
cite_repro(x) = "$x ($REPRO_QUALIFIER)"

# ## Live solve — real-impedance IEEE-123, Phase-17-retuned population
#
# The population constants below are the Phase-17-retuned point (`test/fixtures_phase7.jl`),
# reproduced here as plain `const`s so this page has no load-time dependency on a
# `TestItems.@testmodule` (which expands to a no-op outside `TestItemRunner`'s AST-introspection
# path). [`ieee123_modified`](@ref) is the real ingestion path documented on the
# [IEEE-123 Real Impedances — Public-Data Reduction](@ref) page.

using TSODSO
using Statistics

const T = 24
const BATT_λ_MIN = 3.8
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9
const SEED_IEEE123 = 20260719
const LOAD_SCALE_IEEE123 = 0.05
const PV_SCALE_IEEE123 = 0.12
const DEV_SCALE_IEEE123 = 0.05 * (0.05 / 0.03)

function _temperature_profile()
    return Float64[19, 18, 17, 16, 16, 17, 19, 21, 23, 26, 28, 30,
        31, 32, 32, 31, 29, 27, 25, 23, 22, 21, 20, 19]
end

function _ieee123_lambda0()
    return Float64[3.8, 3.7, 3.6, 3.6, 3.7, 4.0, 4.8, 5.8, 6.5, 6.2, 5.9, 5.7,
        5.6, 5.8, 6.0, 6.8, 8.2, 9.0, 8.6, 7.4, 6.2, 5.2, 4.4, 4.0]
end

function _house_aggregator(feeder, bus; seed, φ, pv_scale = 1.0, load_scale = 1.0, dev_scale = 1.0,
    batt_pmax = 0.5, batt_emax = 2.0, batt_soc0 = 1.0)
    prof = generate_profiles(seed = seed + bus, T = T)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0 * dev_scale, 0.5, _temperature_profile())
    defer = Deferrable(bus, 8, 16, 1.0 * dev_scale, 0.5 * dev_scale, 0.5)
    batt = PVBattery(bus, 0.95, 1.0, batt_pmax, 0.0, batt_emax, batt_soc0,
        BATT_λ_MIN, BATT_λ_MED, BATT_λ_MAX, Ppv)
    return Aggregator(bus, φ, [therm, defer, batt], Pdc)
end

feeder = ieee123_modified()
aggs = [
    _house_aggregator(feeder, bus; seed = SEED_IEEE123, φ = 0.90,
        load_scale = LOAD_SCALE_IEEE123, pv_scale = PV_SCALE_IEEE123, dev_scale = DEV_SCALE_IEEE123,
        batt_pmax = 0.5 * LOAD_SCALE_IEEE123, batt_emax = 2.0 * LOAD_SCALE_IEEE123,
        batt_soc0 = 1.0 * LOAD_SCALE_IEEE123)
    for bus in ieee123_load_nodes()
]
λ₀ = _ieee123_lambda0()

# The DADP welfare optimum (GLB-CVX SOCP, thesis eq. 3.38) — a live, gated solve:

ctx, welfare_dadp, _ = solve_welfare(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ₀, allow_export = true)
acct = welfare_accounting(ctx; T = T)

# The FIT counterfactual (German feed-in tariff, thesis eqs 3.24-3.28) — confirmed feasible on
# this voltage-driven (not congestion-driven) fixture, unlike the IEEE-13 congestion case:

fb = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ₀)
fit_dso = fb.social_fit - fb.prosumer_surplus

# The reactive DLMP (Phase 16) — a distinct, un-summed price signal, available on this same
# plain `solve_welfare` ctx with no ADMM-only reactive-consensus mechanism involved:

d = decompose_dlmp(ctx)
mean_reactive_dlmp = mean(d.reactive)

# ## Terminal findings — the DSO-surplus sign flip
#
# `ctx.meta[:socp_maxgap]` certifies the SOC relaxation is exact at this pinned population
# point (PF-04), so the duals recovered above (and hence the surplus split) are physically
# meaningful:

ctx.meta[:socp_maxgap]

# The DSO-surplus sign flip (FIT negative -> DADP positive, "directional, public-data") and the
# prosumer-surplus decrease under DADP, both mirroring the thesis's own Case A framing:

println("DADP DSO surplus  = ", cite_repro(round(acct.dso; digits = 6)))
println("FIT  DSO surplus  = ", cite_repro(round(fit_dso; digits = 6)))
println("DADP prosumer     = ", cite_repro(round(acct.prosumer; digits = 4)))
println("FIT  prosumer     = ", cite_repro(round(fb.prosumer_surplus; digits = 4)))
println("mean reactive DLMP = ", cite_repro(round(mean_reactive_dlmp; digits = 6)), " pu")

# The live DSO-surplus tuple — the terminal expression this page renders, so the sign flip
# (`dso > 0`, `fit_dso < 0`) and the prosumer decrease (`prosumer < fit_prosumer`) are directly
# checkable against the numbers printed above, all still carrying the
# "directional, public-data" qualifier:

(dso = acct.dso, fit_dso = fit_dso, prosumer = acct.prosumer, fit_prosumer = fb.prosumer_surplus)
