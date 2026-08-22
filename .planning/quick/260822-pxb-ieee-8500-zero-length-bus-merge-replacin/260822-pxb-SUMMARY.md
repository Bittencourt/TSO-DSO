---
quick_id: 260822-pxb
description: Replace impedance fabrication with a principled topological bus-merge reduction for degenerate IEEE-8500 segments, then re-measure SOCP exactness before/after
date: 2026-08-22
status: complete
commits:
  - 2c5e582 (Task 1 — generic zero-length bus-merge machinery; merges the 2 real 1-ft bus-split segments)
  - f275f96 (Task 2 — merges the substation busbar-tie connector, superseding the D-13 value-reassignment)
  - db0cc8e (Task 3 — re-baseline goldens, re-measure SOCP exactness, deferred-items.md Item 5 outcome)
---

# Quick Task 260822-pxb — Summary

Replaced impedance fabrication with a physically-principled topological bus MERGE for 3 degenerate
IEEE-8500 MV segments: 2 genuine 1-ft real-conductor bus-splits (`LN5473436-1`, `LN6259981-1`,
each inserted historically to attach a service transformer) and the `HVMV_Sub_connector`
substation busbar tie (previously given a D-13 near-ideal value-reassignment, plan 25-05/25-07,
`deferred-items.md` item 1). All three are now removed from the topology entirely — collapsed
onto a degree-rule survivor — instead of being assigned any impedance value.

**Result: exactness improved substantially but did NOT fully resolve — an honest, non-null
finding.** The top-1 SOCP-exactness gap shrank 1.5x-5.3x at all 3 re-measured points, and one
point (`ieee8500-mv, density=0.25`) flips from INEXACT to EXACT against its fixture's own
(unchanged) calibrated `atol`. But the dominant-offender fingerprint pattern PERSISTS: a new
branch (`M1069310->M1069311`, a real, non-degenerate-length conductor — confirmed by direct
source inspection, NOT another artificial bus-split) inherits dominance from the merged-away
branch. No tolerance, threshold, or survivor-selection rule was tuned to manufacture this result.

## What changed

### Task 1 — generic bus-merge machinery + the 2 length-class merges (`scripts/reduce_ieee8500_impedances.jl`)

Built a reusable, four-function pipeline: `detect_length_class_merge_pairs` (exact-length
threshold `MV_ZERO_LENGTH_KM = 0.0003048` km = 1.000 ft, asserts exactly 2 matches),
`compute_bus_degrees` (bus-name -> degree over the fully-parsed-but-not-yet-merged topology, using
the phase-deduplicated regulator/switch edge Set so a 3-phase bank counts once, not 3x),
`resolve_merge_pairs` (asserts pairwise disjointness; survivor = strictly greater remaining
degree, lexicographic tie-break on an exact tie), and `apply_merge!` (drops the degenerate edge;
renames the survivor onto every remaining `linecode_recs`/`inline_recs`/`switch_pairs`/
`disabled_switch_pairs`/`xfmr_instances` (`mv_base` only)/`reg_edges` entry; asserts no self-loop
appears post-rename). `main()`'s parse order was reordered so xfmr/regulator parsing happens
before any merge resolution, per the plan's own requirement.

Applied to the 2 pairs: `M1142828` (remaining degree 0) merges into `L2674047` (remaining degree
1); `M1009834` (remaining degree 0) merges into `L3178969` (remaining degree 1) — both exactly the
predicted survivors. Both service transformers (`T5260514C`, `T5355596B`) confirmed reattached to
their survivors in the regenerated table (`("L2674047","X2674047C")`, `("L3178969","X3178969B")`).

### Task 2 — connector merge, superseding the D-13 reshape (`scripts/reduce_ieee8500_impedances.jl`)

`reshape_near_zero_mv_edges!` was renamed `merge_near_zero_mv_edges!` and converted from
value-reassignment to a merge, reusing the SAME generic machinery. `_HVMV_Sub_LSB` and
`HVMV_Sub_48332` are an EXACT degree tie (both remaining degree 1); the deterministic
lexicographic tie-break selects `HVMV_Sub_48332` (`'H'` < `'_'` in ASCII). Removed the now-dead
D-13 value-reassignment constants (`D13_NEAR_IDEAL_R_PU`, `D13_NEAR_IDEAL_X_PU`,
`D13_NEAR_IDEAL_R_OHM_AT_MV_BASE`, `D13_NEAR_IDEAL_X_OHM_AT_MV_BASE`, `IEEE8500_MV_ZBASE_OHM`,
`IEEE8500_MV_S_BASE_MVA`, `IEEE8500_MV_V_BASE_KV`) after grepping the whole file to confirm no
other reference. The D-08 head `smax` invariant (`55.0 pu`, unique branch touching
`IEEE8500_ROOT_BUS`) was explicitly re-verified intact on both fixtures. `deferred-items.md` item
1 gained an appended, dated superseding sub-entry (2026-08-21 history preserved);
`25-DATA-PROVENANCE.md` gained a new section documenting the merge mechanism for all 3 pairs, the
excluded "next tier" classes, and the non-comparability of pre-existing measurement CSVs.

### Task 3 — re-baseline, re-measure (`test/test_ieee8500.jl`, `test/test_benchmark_ieee8500.jl`, `src/data/ieee8500.jl`, `deferred-items.md`)

Preserved the pre-merge `socp_gap_report.csv` baseline via `git show` before re-running the same 3
points (the harness's own CSV upsert would otherwise overwrite those rows in place). Ran
`julia --project=. test/test_ieee8500.jl` — all 26,932 assertions pass unmodified (no MV-bus-count
literal in that file, confirming the plan's own audit). Ran
`julia --project=. test/test_benchmark_ieee8500.jl` — the 2 pinned D-16 goldens on the
`ieee8500-mv --quick` point failed as expected (`model_vars: 137594 != 137444`,
`model_cons: 275118 != 274818`); the test file's OWN Test 1 (run `--quick` twice, compare
directly) confirmed the new values are stable BEFORE re-pinning them.
`termination_status`/`admm_status`/`admm_iters` were unchanged, left untouched. `src/data/
ieee8500.jl`'s header doc-comment bus counts corrected (`4,875 -> 4,872` headline,
`2,521 -> 2,518` MV-only), citing this task.

## Measured bus/branch counts

| Fixture | Before | After Task 1 (2 length-class merges) | After Task 2 (+ connector merge) |
|---|---|---|---|
| `ieee8500_modified()` (headline) | 4875 buses / 4874 branches | 4873 / 4872 | 4872 / 4871 |
| `ieee8500_mv_modified()` (MV-only) | 2521 buses / 2520 branches | 2519 / 2518 | 2518 / 2517 |

All 4 predicted counts matched exactly (no discrepancy investigation needed). Radiality
(`branches == buses - 1`, `Feeder`'s own inner-constructor `assert_radial`) holds on every
regeneration — confirms no self-loop or parallel edge was silently introduced by any of the 3
merges. Total `IEEE8500_LOAD_KW` sum unchanged (no `SX*` load bus touched by any merge).

## BEFORE/AFTER SOCP-exactness table (the 3 re-measured points)

| Point | BEFORE dominant branch (`r_pu`) | BEFORE gap | AFTER dominant branch (`r_pu`) | AFTER gap | Improvement |
|---|---|---|---|---|---|
| `ieee8500,density=0.1,T=10,tol=1e-6` | `L2674047->M1142828` (1.542e-7) | 0.0325016 | `M1069310->M1069311` (9.373e-7) | 0.0061304 | 5.3x |
| `ieee8500-mv,density=0.1,T=24,tol=1e-8` | `L2674047->M1142828` (1.542e-7) | 0.0005781 | `M1069310->M1069311` (9.373e-7) | 0.0003853 | 1.5x |
| `ieee8500-mv,density=0.25,T=24,tol=1e-8` | `L2674047->M1142828` (1.542e-7) | 0.0037728 | `M1069310->M1069311` (9.373e-7) | 0.0008137 | 4.6x |

Verdict against each fixture's own (pre-merge-calibrated, NOT re-measured this task)
`EXACTNESS_ATOL` (`IEEE8500_EXACT_ATOL=0.0049691`, `IEEE8500_MV_EXACT_ATOL=0.0011460`):

| Point | BEFORE verdict | AFTER verdict |
|---|---|---|
| `ieee8500,density=0.1,T=10` | INEXACT (6.5x over) | still INEXACT (1.2x over — much closer) |
| `ieee8500-mv,density=0.1` | EXACT | still EXACT (more margin) |
| `ieee8500-mv,density=0.25` | INEXACT (3.3x over) | **now EXACT** (genuine flip) |

**Honest verdict: this is NOT a null result, but it is also NOT full resolution.** The
merged-away branch's dominance passes to the next-most-degenerate branch in the SAME cluster
`deferred-items.md` Item 5 already flagged as "still open." A quick source check confirms
`M1069310<->M1069311` (`LN5486729-1`, `length=0.000560638 km`, real `3PH_H-2/0_ACSR`) is one of
the 5 "other short-but-non-round real MV segments" this task's own scope deliberately excluded —
it does not round-trip to an exact imperial unit, so it is a real, non-degenerate-length
conductor that happens to carry a naturally small impedance, NOT the same "artificial bus-split
marker" class this task's merge targeted. Whether it warrants a different remedy is left open
(next tier, recorded in `deferred-items.md`).

## Non-comparability note

`results/ieee8500_benchmark/density_sweep_full.csv`, `density_sweep.csv` (all rows except the
freshly re-run `ieee8500-mv,0.1,clarabel,10` D-16 golden row), `noise_floor_calibration.csv`, and
every PRE-this-task row of `socp_gap_report.csv` (preserved in git history at commit
`329ed26364fd0e554a30a6b76d6917992a443705`, the pre-merge base) were measured on the
4875-bus-headline/2521-bus-MV-only topology and are NOT directly comparable to any measurement
taken after this task — a fixture-identity change (3 fewer buses), not a solver or tolerance
change. Documented explicitly in `25-DATA-PROVENANCE.md`'s new section.

## Verification

| Check | Result |
|---|---|
| `julia scripts/reduce_ieee8500_impedances.jl --verify` | PASS (CT5 sanity, unaffected) |
| `julia scripts/reduce_ieee8500_impedances.jl` regenerate | "Bus merge (length-class): 2 pairs merged" + "Bus merge (near-zero-r connector): 1 pair(s) merged" — exactly the predicted pairs/survivors |
| `grep -c "M1142828\|M1009834"` on generated table | 0 |
| `grep -c '"_HVMV_Sub_LSB"'` (exact-quoted) on generated table | 0 (note: the plan's literal unquoted `grep -c "_HVMV_Sub_LSB"` returns 2 — both are substring false-positives from the UNRELATED, legitimately-still-present bus `regxfmr_HVMV_Sub_LSB`, verified by inspection) |
| `grep -n "D13_NEAR_IDEAL"` | no matches |
| Both fixtures construct (`ieee8500_modified()`, `ieee8500_mv_modified()`) | yes, both regenerations, all 3 stages |
| Head branch `smax` invariant, both fixtures | `55.0` pu, unique branch touching root, confirmed both post-Task-1 and post-Task-2 |
| `julia --project=. test/test_ieee8500.jl` | 26932/26932 pass, unmodified |
| `julia --project=. test/test_benchmark_ieee8500.jl` | 10/10 pass after re-pinning 2 goldens (stability-confirmed first) |
| 3 `--gap-report` re-measurements | all `OPTIMAL`, all wrote 20 offender rows, one process at a time |
| `git diff --diff-filter=D` after each commit | no unexpected deletions |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan's literal `grep -c "_HVMV_Sub_LSB"` verify command has an unavoidable substring false-positive**
- **Found during:** Task 2's own verify step
- **Issue:** the plan's verify command `grep -c "_HVMV_Sub_LSB" src/data/ieee8500_impedances.jl returns 0` is a substring match — it also matches the UNRELATED, legitimately-still-present bus name `regxfmr_HVMV_Sub_LSB` (the substation transformer's own MV-side terminal, untouched by this merge), returning 2, not 0.
- **Fix:** verified the intended check via the exact-quoted string `grep -c '"_HVMV_Sub_LSB"'` (matching how the casualty name would appear as a Julia `repr()`'d Dict key), which correctly returns 0. Documented both results above so a future reader isn't confused by the discrepancy.
- **Files modified:** none (verification-only; no code change needed)
- **Commit:** N/A (documented in this SUMMARY only)

No other deviations — plan executed as written, including the exact predicted survivor/degree
values for all 3 merges and all 4 bus-count checkpoints.

## Issues Encountered

None. All 3 gap-report solves reached `OPTIMAL` on the first attempt (no `ALMOST_OPTIMAL`,
timeout, or OOM). Machine had ~3.1 GiB free / 7.2 GiB available at the start of Task 3's
measurements (shared machine, checked via `free -h`); ran one Julia process at a time throughout,
using `run_in_background` + polling rather than blocking foreground waits, per the shared-machine
and turn-discipline constraints. No OOM occurred at any point.

## Next Phase Readiness

- The generic bus-merge machinery (`compute_bus_degrees`/`resolve_merge_pairs`/`apply_merge!`) in
  `scripts/reduce_ieee8500_impedances.jl` is now reusable for any future degenerate-segment
  investigation on this fixture (e.g. the still-open `M1069310->M1069311`/`M1108489->P829798`
  next-tier candidates, IF a future investigation determines either is genuinely a bus-split
  rather than a naturally-short real conductor).
- `deferred-items.md` Item 5 now carries an honest, non-manufactured before/after record — a
  future plan revisiting IEEE-8500 SOCP exactness should read it before assuming the mechanism is
  resolved.
- `assert_socp_exact!`'s project-default `atol=1e-6` still does NOT pass on any of these 3 points
  — this task never claimed otherwise. Item 2 (whether `exactness.jl` should special-case
  near-zero-impedance branches) remains open and unaddressed.

## Known Stubs

None — this is a data-reduction/measurement quick task with no UI or data-rendering surface.

## Threat Flags

None — no new network endpoints, auth paths, or trust-boundary surface introduced. All changes
are offline data reduction (dependency-free Base+regex script) and test/measurement code.

## Self-Check: PASSED

- FOUND: commit `2c5e582`
- FOUND: commit `f275f96`
- FOUND: commit `db0cc8e`
- FOUND: `scripts/reduce_ieee8500_impedances.jl` (`compute_bus_degrees`/`resolve_merge_pairs`/`apply_merge!`/`merge_near_zero_mv_edges!` present)
- FOUND: `src/data/ieee8500_impedances.jl` (regenerated; casualty bus names absent)
- FOUND: `test/test_benchmark_ieee8500.jl` (goldens updated to 137444/274818, passing)
- FOUND: `results/ieee8500_benchmark/socp_gap_report.csv` (3 points re-measured, ieee13 control row untouched)
- FOUND: `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` (Item 1 addendum + Item 5 outcome appended)
- FOUND: `.planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md` (new merge section)
- FOUND: `.planning/quick/260822-pxb-ieee-8500-zero-length-bus-merge-replacin/260822-pxb-SUMMARY.md`
