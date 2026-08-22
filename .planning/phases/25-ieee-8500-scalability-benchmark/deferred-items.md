# Deferred Items — Phase 25 (IEEE-8500 Scalability Benchmark)

Discoveries made during plan execution that are out of the discovering plan's `<files>` scope,
logged here per the executor's SCOPE BOUNDARY rule rather than fixed inline.

## Plan 25-05: near-zero-impedance MV connector breaks the naive SOC-exactness noise-floor calibration

**Found during:** Task 1's real 5-rung noise-floor calibration deliverable (`--calibrate-noise-floor`)
on both IEEE-8500 fixtures.

**What was found:** On BOTH `ieee8500_mv_modified()` and `ieee8500_modified()`, the worst-offending
branch in the SOCP cone-residual scan is, at every tolerance rung, the SAME real vendored MV
segment `HVMV_Sub_48332 -> _HVMV_Sub_LSB` — `IEEE8500_MV_BRANCH_RX_OHMS[("HVMV_Sub_48332",
"_HVMV_Sub_LSB")] = (1e-6 Ω, 1e-5 Ω)`. At `S_base = 0.5 MVA`, `V = 12.47 kV` this converts to a
genuinely near-zero per-unit impedance (`r ≈ 3.2e-9 pu`, `x ≈ 3.2e-8 pu`) — roughly SIX orders of
magnitude smaller than the D-13 near-ideal regulator/switch convention already used elsewhere in
this same fixture (`IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` = 3e-4/1.5e-4 pu).

**Why this matters:** the LinDistFlow SOC-exactness argument relies on a strictly-positive
loss-cost gradient (`r·l` in the objective) to drive the squared-current variable `l` to its tight
minimal value at the optimum. On a near-zero-`r` branch that gradient is essentially absent, so the
cone residual on THIS branch does not shrink as the solver's `tol_gap` tightens — it is a
STRUCTURAL/ill-conditioning property of the branch, not shrinking numerical noise. Confirmed via a
real-entrypoint diagnostic (not a ratio-only conclusion): the SAME branch tops the worst-gap list on
both fixtures, at every density/seed tried.

**Consequence for this plan (historical — SUPERSEDED by Item 1's 2026-08-21 resolution below):**
at the time plan 25-05 measured it, the calibrated `IEEE8500_MV_EXACT_ATOL`/`IEEE8500_EXACT_ATOL`
constants in `scripts/benchmark_ieee8500.jl` were measured HONESTLY (never inherited from
IEEE-13/123) but were consequently LARGE (0.1796 / 0.5653) — large enough that the harness's own
`exact_verdict` classification against them was a much weaker check than IEEE-13/123's `1e-6`-scale
gate. This was documented in-code and here, not silently absorbed. Item 1 below (RESOLVED) fixed
the root cause and both constants are now re-measured, ~150x smaller, and genuinely noise-like.

**Deferred (out of plan 25-05's `<files>` scope — only `src/models/exactness.jl`,
`scripts/benchmark_ieee8500.jl`, `test/test_benchmark_ieee8500.jl` are authorized):**

### Item 1 — RESOLVED 2026-08-21 (phase-25 gap-closure task, authorized directly by the user)

`scripts/reduce_ieee8500_impedances.jl`'s `reshape_near_zero_mv_edges!` now detects this ONE
degenerate MV segment (`("HVMV_Sub_48332", "_HVMV_Sub_LSB")`, the substation Low Side Bus busbar
tie) via an explicit, documented threshold (`r_ohm < MV_NEAR_ZERO_R_THRESHOLD_OHM = 1e-5 Ω`, with
a loud assert-exactly-1 check so a future data refresh that changes this set fails fast) and
reassigns its `r_ohm`/`x_ohm` VALUES in place — same bus pair, same `IEEE8500_MV_BRANCH_RX_OHMS`
table, same connectivity — to the D-13 near-ideal Ω-equivalent of `IEEE123_SWITCH_R`/
`IEEE123_SWITCH_X` at this fixture's own MV per-unit base: `(r=0.09330 Ω, x=0.04665 Ω)` (was
`(1e-6 Ω, 1e-5 Ω)`). `IEEE8500_REGULATOR_EDGES` is untouched (still 43 entries); MV edge count
(2477), and both fixtures' bus/branch counts (4875/4874, 2521/2520) are unchanged. Full
data-shaping rationale in `25-DATA-PROVENANCE.md`'s new "Deviation from verbatim transcription"
section.

**Measured before/after** (both measured via `scripts/benchmark_ieee8500.jl
--calibrate-noise-floor`, machine confirmed quiet both times — the AFTER column is this
gap-closure task's own fresh Task 3 measurement, not inherited from any prior estimate):

| Fixture | Rung | Before (measured_gap) | After (measured_gap) |
|---|---|---|---|
| `ieee8500-mv` | tol=1e-6 | 0.4960365893 | 0.0312771897 |
| `ieee8500-mv` | tol=1e-7 | 0.3802856023 | 0.0059259602 |
| `ieee8500-mv` | tol=1e-8 (FLOOR) | 0.1795915651 (plateaued; tol=1e-9/1e-10 failed `ALMOST_OPTIMAL`) | 0.0011460286 (shrinking 27x tighter than tol=1e-6 — genuine noise-like behavior; tol=1e-9/1e-10 still fail `ALMOST_OPTIMAL`) |
| `ieee8500` | tol=1e-6 | 0.5653322911 (FLOOR before — every tighter rung failed) | 0.0273083027 |
| `ieee8500` | tol=1e-7 (FLOOR after) | NaN (`ALMOST_OPTIMAL`) | 0.0049691451 |

`ieee8500-mv`'s floor improved 157x at tol=1e-8 (`0.1796 -> 0.001146`). `ieee8500`'s floor
improved from a tol=1e-6 plateau (`0.5653`) to a genuinely tighter tol=1e-7 floor (`0.004969`),
a 114x improvement, AND (unlike before) it now successfully reaches a SECOND ladder rung at all.
More important than either raw ratio: BOTH fixtures' residuals now SHRINK as tolerance tightens
rung-over-rung instead of plateauing/immediately failing — they now behave like real numerical
noise rather than a structural relaxation floor. `test/test_benchmark_ieee8500.jl`'s D-16 goldens
(model dimensions, termination status, ADMM iteration count) were re-run and ALL 10/10 still
pass unchanged — only the (never-golden) wall-time and exactness-gap columns moved. See this
gap-closure task's `25-07-SUMMARY.md` for the full 5-rung ladder and the re-calibrated
`IEEE8500_MV_EXACT_ATOL`/`IEEE8500_EXACT_ATOL` constants.

**IMPORTANT HONEST CAVEAT — this fix does NOT make a converged ADMM consolidation work.** Even
after this fix the floor is still `~1e-3` scale, which STILL exceeds `solve_admm`'s hardcoded
final-consolidation `assert_socp_exact!` default of `atol=1e-6` (no override parameter exists —
see Item 3 below, which remains OPEN). A genuinely CONVERGED, CONSOLIDATED ADMM point on either
IEEE-8500 fixture can still throw at that gate. This fix closes the STRUCTURAL relaxation failure
(the residual now behaves like noise and shrinks with tolerance) but does NOT close the numerical
gap between that noise floor and the project's existing `1e-6` default gate — that gap is Item 3's
concern, still open.

### Items 2 and 3 — still OPEN (NOT in scope for this gap-closure task)

**Item 2 (open):** Whether `assert_socp_exact!`/`socp_relaxation_gap` should special-case or
exclude near-zero-impedance branches from the max-gap scan, so a single degenerate connector
cannot dominate (and effectively disable) the exactness gate for an otherwise well-conditioned
network — `src/models/exactness.jl` is NOT in this gap-closure task's authorized file list.

**Item 3 (open):** `solve_admm`'s own hardcoded final-consolidation `assert_socp_exact!` call
  (`src/admm/solve_admm.jl`, `check_exact = true`) uses the PROJECT DEFAULT `atol = 1e-6`/
  `rtol = 1e-4` with no override parameter — meaning ADMM on either IEEE-8500 fixture will hit
  this SAME near-zero-impedance branch's residual and throw at the final consolidation gate
  REGARDLESS of density, population, or convergence quality. This is a real, reproducible finding
  (confirmed live during Task 2's `--quick` and `--time-limit 1` exercises: the ADMM point on
  `ieee8500-mv` never reaches a clean converged consolidation — it is intentionally exercised
  under a SHORT wall-clock budget in this plan specifically so `solve_admm`'s D-18 early exit
  (`:budget_exceeded`) fires before the final consolidation gate is ever reached). A future plan
  that wants a genuinely CONVERGED, CONSOLIDATED ADMM point on either IEEE-8500 fixture will hit
  this throw and needs an override seam on `solve_admm`'s `atol`/`rtol` (currently none exists) —
  Item 1's data-shaping fix (now resolved) closed the STRUCTURAL failure but did NOT close the
  remaining numerical gap between the re-measured `~1e-3` noise floor and this `1e-6` default.

**Not a plan-25-05 blocker:** Task 1/2/3's own acceptance criteria do not require a converged
ADMM consolidation — they require an honestly-reported point (including `budget_exceeded`), which
this plan delivers. This item is flagged for plan 25-06 (headline results) and beyond.
