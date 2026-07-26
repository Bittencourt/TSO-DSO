# # Thesis Reproduction — Assumptions & Reduction Chain
#
# This page consolidates every assumption behind the numbers on the
# [Thesis Case A Reproduction — Real-Impedance IEEE-123](@ref) page, so a reader can trace the
# reported DSO-surplus sign flip all the way back to the raw public data, the reduction that
# turned it into a usable fixture, and the population re-tune that keeps the solve exact.
# Every cited number here carries the fixed "directional, public-data" qualifier —
# `[CITED: ...]` markers point to primary sources, `(directional, public-data)` markers flag a
# number measured on this repo's own fixture rather than lifted from the thesis.

const REPRO_QUALIFIER = "directional, public-data"
cite_repro(x) = "$x ($REPRO_QUALIFIER)"

# ## 1. Units resolution
#
# The IEEE-123 branch impedances are ingested from public OpenDSS `IEEE123Master.dss` /
# `IEEELineCodes.DSS` files with **no `Units=` directive anywhere in the chain** — per the
# OpenDSS `LineCode` documentation, unspecified `Units=` means no scale conversion is applied,
# so `z_Ω = R1 × Length` is computed directly with no `5280`/`1000`/`kft` scale factor. This is
# the classic feet-vs-miles/kft trap; it is fully resolved and worked-example-verified on the
# [IEEE-123 Real Impedances — Public-Data Reduction](@ref) page (`scripts/reduce_ieee123_impedances.jl`) —
# not re-derived here, only cross-referenced.
#
# ## 2. Fortescue reduction fidelity
#
# Each `n×n` symmetric line-code impedance matrix is reduced to a single positive-sequence
# `R1`/`X1` via the classic Fortescue-averaging identity (`R1 = mean(diag) − mean(offdiag)`,
# same for `X1`), assuming approximately transposed, balanced 3-phase construction — standard
# for this class of reduction, not a claim the physical conductors are perfectly transposed.
# Single/two-phase laterals (`n = 1`) short-circuit to `R1 = rmatrix[1,1]` directly (no
# off-diagonal to average). Full worked example and the pinned sanity values
# (`R1 ≈ 0.057967`, `X1 ≈ 0.118756` on `linecode.1`) live on the
# [IEEE-123 Real Impedances — Public-Data Reduction](@ref) page.
#
# ## 3. Omitted regulators / capacitors / switches
#
# Regulators, capacitors, and switches are **not** actively modeled as real devices — they are
# absorbed into the fixture's existing near-ideal switch-class impedance
# (`IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` in `src/data/ieee123.jl`), per the phase's REQUIREMENTS
# Out-of-Scope declaration. Only the 117 ordinary (non-switch) branches receive real per-segment
# Ω data from `IEEE123_BRANCH_RX_OHMS`; the 5 switch/regulator-collapsed edges intentionally
# keep their pre-existing synthetic near-ideal value.
#
# ## 4. The aggregator population re-tune
#
# `test/fixtures_phase7.jl` re-tunes the IEEE-123 aggregator population scale AFTER Phase 17
# swapped in real impedances, because the ORIGINAL synthetic-impedance triple broke
# `solve_welfare`'s SOCP-exactness gate outright on the real network (`assert_socp_exact!`
# threw — worst gap ratio 1.378 > 1). The re-tune:

const LOAD_SCALE_IEEE123 = 0.05    # was 0.03 (synthetic-impedance point)
const PV_SCALE_IEEE123 = 0.12      # was 0.06
const DEV_SCALE_IEEE123 = 0.05 * (0.05 / 0.03)   # ≈ 0.0833; ratio to LOAD_SCALE held fixed

# WHY: Phase 17's exhaustive population-scale search found the achievable regime on the real
# feeder is genuinely **asymmetric** — the lower voltage band (drop toward 0.9 pu) transfers
# reasonably well under load-scaling, but the upper band (rise toward 1.1 pu) does not; any
# population scale pushing the solved max meaningfully above ~1.02-1.03 pu drives the SOC
# relaxation genuinely inexact before reaching 1.08 pu (the same high-PV/reverse-flow
# exactness boundary Phase 15's EXACT-04 finding documents on the IEEE-13 fixture).
#
# ## 5. The PV scenario
#
# The population is one seeded aggregator per LOAD node (`ieee123_load_nodes()`, 85 spot-load
# buses out of the full topology — the remaining ~37 junction buses are zero-injection transit
# nodes), each with a Thermostatic + Deferrable + PVBattery device set. PV magnitude is scaled
# by `PV_SCALE_IEEE123` relative to a seeded `generate_profiles` draw — a residential-order PV
# penetration, not the thesis's original 5 MWp calibration (which this repo cannot access
# without thesis Appendix E). This is a modeling assumption, not a measured fact: the PV
# scenario is deliberately residential-scale so the SOC relaxation stays exact at this fixture's
# real impedances, not calibrated to reproduce any specific published PV penetration figure.
#
# ## 6. THE HONESTY-MANDATE PARAGRAPH — welfare-ratio-vs-surplus-sign metric caveat
#
# **State this plainly: the thesis's headline +25% AGGREGATE-WELFARE-RATIO MAGNITUDE does NOT
# cleanly transfer to real public IEEE-123 data.** On this fixture the aggregate welfare gap
# between DADP and FIT is only **≈+0.045% (directional, public-data)** — small and
# comparatively fragile, not the thesis's +25%. What DOES reproduce, robustly and
# correctly-signed, is the **DSO-surplus sign flip**: the FIT baseline's DSO surplus is negative
# (**fit_dso ≈ -196.216447, directional, public-data**), the DADP optimum's DSO surplus is
# positive (**acct.dso ≈ +3.725705, directional, public-data**), and the prosumer surplus
# decreases under DADP (**acct.prosumer ≈ -41039.129 < fit_prosumer ≈ -40857.497, directional,
# public-data**) — the SAME directional redistribution the thesis reports ("DSO surplus
# -\$2829 -> +\$439"). Dividing two welfare numbers that can each be negative
# (`welfare_dadp` by `welfare_fit`) silently inverts the intended "DADP is better" reading
# whenever the denominator's sign flips — this repo NEVER reports that ratio as a primary claim
# (Pitfall 1, enforced mechanically in `scripts/thesis_case123_repro.jl` and both literate
# pages). The sign flip, not the ratio magnitude, is this phase's actually-pinned,
# thesis-faithful signal.
#
# ## 7. The asymmetric voltage-binding caveat (Phase 17)
#
# The real-impedance IEEE-123 fixture's voltage constraint binds **asymmetrically**: the lower
# band (toward 0.9 pu, driven by residential load) is strongly binding and transfers well across
# population scales, while the upper band (toward 1.1 pu, driven by PV reverse-flow) is only
# weakly/boundary-limited — pushing the population scale up to chase a stronger upper-band bind
# drives the SOC relaxation inexact before the bound is even reached. Phase-17-retuned solves
# observe **vmin_solved ≈ 0.9487 pu, vmax_solved ≈ 1.0105 pu (directional, public-data)** — both
# inside the feasible band, with real headroom on the lower side and comparatively little on the
# upper side. Any future re-tune of this population must re-verify this asymmetry, not assume it
# holds at a different scale.
#
# ## 8. Plan 18-01's stability/sensitivity sweep — does the sign flip survive population-scale
#    perturbation?
#
# **No — not confirmed.** `scripts/repro_stability_check.jl` (Plan 18-01) swept
# `LOAD_SCALE_IEEE123`/`PV_SCALE_IEEE123`/`DEV_SCALE_IEEE123` by ±2%/±5% around the exact
# retuned point and found `sign_flip_survives: false` — ALL FOUR non-zero perturbation points
# FAILED OUTRIGHT (`assert_socp_exact!` threw, worst gap/tol ratios 1.10–3.23), exactly the
# near-boundary knife-edge risk this page's Section 7 documents. The DSO-surplus sign flip is
# therefore confirmed **only at the exact Phase-17-retuned population point (directional,
# public-data)**, NOT across a ±2-5% neighborhood — the golden magnitude band
# (`DSO_BAND_LO=0.0, DSO_BAND_HI=5.58855710237937`) pinned in `test/test_thesis_repro.jl` is
# derived from that single successfully-solved point only, per
# `results/repro_stability_check/findings.txt`'s own explicit flag. Any future population
# re-tune MUST re-run `scripts/repro_stability_check.jl` before trusting that band again.
#
# ## Live-checked constants
#
# A small amount of live code, so this page cannot silently drift from `src/` even though it is
# narrative-first: the load-node count and the re-tune constants restated above are checked
# live against the real feeder and the values this page cites.

using TSODSO

feeder = ieee123_modified()
n_load_nodes = length(ieee123_load_nodes())

@assert n_load_nodes == 85 "expected 85 IEEE-123 load nodes, got $n_load_nodes"
@assert LOAD_SCALE_IEEE123 ≈ 0.05
@assert PV_SCALE_IEEE123 ≈ 0.12
@assert DEV_SCALE_IEEE123 ≈ 0.05 * (0.05 / 0.03)

println("live-checked load-node count = ", cite_repro(n_load_nodes))
println("live-checked population re-tune = ", cite_repro(
    (LOAD_SCALE_IEEE123, PV_SCALE_IEEE123, round(DEV_SCALE_IEEE123; digits = 4)),
))

(n_load_nodes = n_load_nodes, LOAD_SCALE_IEEE123 = LOAD_SCALE_IEEE123,
    PV_SCALE_IEEE123 = PV_SCALE_IEEE123, DEV_SCALE_IEEE123 = DEV_SCALE_IEEE123)
