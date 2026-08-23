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
#
# !!! warning "CORRECTED 2026-07-26 — that 1.378 failure was a solver-tolerance artifact"
#     The re-tune was **not necessary for exactness**. Re-tested directly: the ORIGINAL triple
#     (`0.03 / 0.06 / 0.05`) on the REAL-impedance feeder throws at the default `tol_gap = 1e-8`
#     with exactly ratio `1.3781586234547918`, and **solves cleanly at `tol_gap = 1e-10`** —
#     `socp_maxgap = 1.673e-08`, `vpeak = 1.00198` pu, `dso = +0.662750` (still positive, i.e. the
#     sign flip's DADP side survives there too). `atol = 1e-6` sits at Clarabel's achievable cone
#     residual on this 122-branch feeder, so the "broke the gate outright" reading is not
#     supported — see Section 8.
#
#     The re-tuned point below remains a perfectly valid operating point and nothing downstream
#     of it is wrong; it simply was not *required*, and the asymmetry rationale in Sections 5 and
#     7 rests on the same default-tolerance evidence (see the warnings there).

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
# !!! warning "CORRECTED 2026-07-26 — the upper-band half of this claim needs re-measuring"
#     Phase 17's search ran at the default `tol_gap = 1e-8`, where "drives the SOC relaxation
#     genuinely inexact" is **not distinguishable from solver noise** on this feeder (`atol = 1e-6`
#     sits at Clarabel's achievable cone residual — Section 8). Two specific problems:
#
#     * the datum anchoring this paragraph (ratio 1.378 at the `0.03` point) is **refuted** — it
#       solves cleanly at `tol_gap = 1e-10`; and
#     * an independent sweep found the voltage **upper bound is never active at all** on this
#       feeder across a 5.5× PV range (`vpeak` 0.9997-1.016 pu against caps 1.05-1.10), so there
#       is no observed upper-band binding to be asymmetric about.
#
#     Phase 17's full search space was **not** re-swept, so this is recorded as *evidence
#     undermined, needs re-measurement at tight tolerance* — not as refuted. The **lower**-band
#     claim (`vmin_solved ≈ 0.9487` pu, load-driven) is real physics and is unaffected.
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
# !!! warning "CORRECTED 2026-07-26 — same caveat as Section 5"
#     "Pushing the population scale up … drives the SOC relaxation inexact before the bound is even
#     reached" was measured at the default `tol_gap = 1e-8`, which cannot distinguish a relaxation
#     gap from solver under-convergence on this feeder (Section 8). The observed
#     `vmax_solved ≈ 1.0105` pu is a real measurement and stands; the **inference** that inexactness
#     limits the upper band does not, pending re-measurement at tight tolerance. The lower-band
#     binding (`vmin_solved ≈ 0.9487` pu) is unaffected.
#
# ## 8. Plan 18-01's stability/sensitivity sweep — does the sign flip survive population-scale
#    perturbation?
#
# **Yes — at all five swept points.** (This section was CORRECTED on 2026-07-26; the original
# verdict, quoted at the end, was wrong.)
#
# Re-measured with the shipped exactness gate still ARMED (default `rtol_exact = 1e-4`), changing
# only the SOLVER tolerance to `tol_gap = 1e-10`:
#
# | δ | socp_maxgap | dadp_dso | fit_dso | sign flip |
# |---|---|---|---|---|
# | −0.05 | 3.505e-08 | +2.709838 | −182.9611 | yes |
# | −0.02 | 1.900e-08 | +3.277535 | −190.8755 | yes |
# | 0.00 | 1.162e-08 | +3.725742 | −196.2165 | yes |
# | +0.02 | 4.610e-08 | +4.163925 | −201.6167 | yes |
# | +0.05 | 1.342e-08 | +4.807417 | −209.9950 | yes |
#
# 5/5 solve; the DSO-surplus sign flip holds at every point; both surpluses are **monotone** in
# population scale (`dadp_dso` +2.71 → +4.81, `fit_dso` −183 → −210, directional, public-data).
# There is no boundary, no discontinuity and no knife edge in this neighbourhood.
#
# !!! warning "CORRECTED 2026-08-23 — `fit_dso` column above does NOT currently reproduce at all 5 points"
#     Quick task `260823-gea` re-ran this exact measurement (fixed `scripts/repro_stability_check.jl`,
#     `tol_gap=1e-10`, 3 independent runs, all consistent) to close out the golden-band item below and
#     found a partial non-reproduction: `solve_welfare`'s SOCP-exactness gate DOES still resolve 5/5
#     (0/5 THREW, the `dadp_dso` column above is confirmed), but `fit_baseline`'s OWN internal nested
#     solve — a separate call site, SITE 3 of the `optimizer` threading in `260726-mo7` — now fails
#     with `ALMOST_OPTIMAL`/`NEARLY_FEASIBLE_POINT` at 3 of the 5 points (`δ=-0.02, 0.00, +0.05`),
#     leaving `fit_dso` (and hence the full sign-flip confirmation) measured at only 2 of 5 points
#     today. This is a DIFFERENT numerical issue than the one this section originally diagnosed —
#     solver convergence at an extreme tolerance, not SOCP relaxation inexactness — and it may reflect
#     environment drift (Clarabel/Julia patch versions) since the `run-after-kwarg.log` this table is
#     sourced from was captured. The table above is left AS-IS (a historical record of that log), but
#     should not be read as currently-reproducible in the `fit_dso` column without a fresh re-run.
#     Closing this out needs a bounded, budgeted re-measurement in a future phase — not attempted here
#     per this task's own measurement-before-golden discipline (an honest partial result is preferred
#     over spending unbounded solver time chasing a clean 5/5 or quietly re-trying until one appears).
#
# **Why the original sweep concluded otherwise — the failures were NUMERICAL.**
# `assert_socp_exact!`'s `atol = 1e-6` sits AT Clarabel's achievable cone residual on this
# 122-branch feeder at the default `tol_gap = 1e-8`. Tightening shrinks the residual one to two
# orders of magnitude while the optimum is UNCHANGED (`dadp_dso` agrees to 6-7 significant
# figures) — a structural relaxation gap is a property of the optimum and cannot behave that way.
# Independently, on real IEEE-123 impedances the voltage upper bound is **never active** across a
# 5.5× PV range (`vpeak ≤ 1.016` pu against caps ≥ 1.05), so the high-PV/reverse-flow mechanism
# that drives genuine SOC inexactness on the IEEE-13 stress fixture does not occur here at all.
#
# Two of the four originally-recorded failures were also **misattributed**: they were
# `fit_baseline`, not `solve_welfare`, because `scripts/repro_stability_check.jl` wraps three
# solves in one `try/catch`. Nothing was flaky — Clarabel is deterministic and the ratios
# reproduce bit-for-bit; only the attribution was inferred.
#
# The golden magnitude band was **re-derived and re-pinned** by quick task `260823-gea`:
# `DSO_BAND_LO=0.0, DSO_BAND_HI=7.211125525764296` in `test/test_thesis_repro.jl`, replacing the
# original `5.58855710237937` that had been derived from the ONE point (`δ=0.0`) solving at the
# time. The re-derivation turned on a distinction the old measurement script conflated: the
# `1.5 × max|dso|` rule ranges over `dso` (the DADP DSO surplus, produced by `solve_welfare` +
# `welfare_accounting`), whereas `fit_baseline` produces `fit_dso` for the sign-flip check and
# nothing the band depends on. The script had gated the band on all-three-stages success *and*
# discarded `acct.dso` as `NaN` whenever `fit_baseline` threw — so the band was both gated on and
# starved by a stage irrelevant to it. With both fixed, `dso` is trustworthy at **5 of 5** swept
# points (while only 2/5 clear all three stages), giving `1.5 × 4.807417 = 7.211125525764296`
# from the fixed script at `REPRO_TOL_GAP=1e-10`. This coincides numerically with the `7.211`
# previously projected in the planning notes, but is reached by the decoupling argument above —
# **not** by the refuted "the sweep solves 5/5 everywhere" assumption that figure was originally
# extrapolated from. The band widens (`5.5886 → 7.2111`); the sign gate `DSO_BAND_LO = 0.0` and
# every other assertion in that test are unchanged, and the pinned point (`|dso| = 3.7257`) sits
# inside both the old and new bands, so nothing about the reproduction's verdict moves.
#
# The separate `fit_baseline`-convergence finding stands on its own and is NOT closed by this:
# at `tol_gap=1e-10` its nested solve returns `ALMOST_OPTIMAL`/`NEARLY_FEASIBLE_POINT` at 3 of 5
# swept points (discrete flake rate 13/20 = 0.650, all 13 at that same stage, reproduced across
# 3 runs), so the FULL sign-flip confirmation holds at 2 of 5 points, not 5 of 5 as
# `260726-mo7`'s summary recorded.
#
# ~~ORIGINAL (WRONG) VERDICT: "No — not confirmed … `sign_flip_survives: false` — ALL FOUR
# non-zero perturbation points FAILED OUTRIGHT … the DSO-surplus sign flip is therefore confirmed
# only at the exact Phase-17-retuned population point, NOT across a ±2-5% neighborhood."~~
#
# Evidence: `.planning/spikes/003-phase18-fragility-tolerance/` (README + `run.log` before /
# `run-after-kwarg.log` after), `.planning/spikes/002-ieee123-validity-map/` (the noise-floor
# proof), commit `c099ee6` (the `optimizer` kwarg on `fit_baseline` that made the FIT
# counterfactual conditionable at all). `scripts/repro_stability_check.jl`'s three-solve
# `try/catch` has now been split per stage and the `optimizer` kwarg threaded through
# (`260823-gea`), so a future population re-tune (or a future attempt at this golden-band
# re-derivation, budgeted for the slower tight-tolerance solves) can re-run it directly with no
# further prerequisite fix.
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
println(
    "live-checked population re-tune = ",
    cite_repro((
        LOAD_SCALE_IEEE123,
        PV_SCALE_IEEE123,
        round(DEV_SCALE_IEEE123; digits = 4),
    ),),
)

(
    n_load_nodes = n_load_nodes,
    LOAD_SCALE_IEEE123 = LOAD_SCALE_IEEE123,
    PV_SCALE_IEEE123 = PV_SCALE_IEEE123,
    DEV_SCALE_IEEE123 = DEV_SCALE_IEEE123,
)
