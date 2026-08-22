---
quick_id: 260822-rle
description: Widen the IEEE-8500 zero-length bus-merge threshold from "exactly 1.000 ft" to "sub-metre", merging the remaining line-split artifacts, then re-measure SOCP exactness
date: 2026-08-22
status: complete
commits:
  - 5b653e5 (Task 1 — widen threshold/guard to sub-metre, catch 6 more line-split pairs)
  - 7d99f4f (Task 2 — reconcile measured delta, re-pin D-16 goldens, correct header counts)
  - 876b1e0 (Task 3 — re-measure SOCP exactness at 3 points, update provenance docs)
---

# Quick Task 260822-rle — Summary

Widened the IEEE-8500 length-class bus-merge threshold (`scripts/reduce_ieee8500_impedances.jl`)
from an exact-1.000-ft match to a documented, float-safe sub-metre bound, catching **6 further**
real-conductor line-split segments beyond the 3 quick task 260822-pxb already merged (reconciling
the plan's own hand-recount of "6 new," not the task-framing's stated "5"). **Result: the headline
SOCP-exactness point genuinely FLIPS from INEXACT to EXACT — a real resolution, not another
dominance transfer without net improvement.** No tolerance, threshold, or survivor-selection rule
was tuned to manufacture this result; the new dominant offender (a genuinely longer, 4.745 m real
conductor) is named plainly as an honest "next tier" finding.

## What changed

### Task 1 — widen the threshold, widen the guard, add the CAP_ belt-and-braces assertion (`scripts/reduce_ieee8500_impedances.jl`)

Replaced `MV_ZERO_LENGTH_KM = 0.0003048` (exact 1.000 ft, `isapprox` match) with
`MV_SUBMETRE_LENGTH_KM_BOUND = 0.001` km (strict `< 1 metre`) plus a `MV_SUBMETRE_LENGTH_KM_EPS =
1.0e-6` km (1 mm) float-safety margin, applied as `r.length_km < bound - eps`. Added a `name`
field to `MVLinecodeRef` (threaded through both construction sites: `parse_mv_lines`'s
`Linecode=`-referencing branch via a new `match(r"New\s+Line\.(\S+)"i, raw)` capture, and
`apply_merge!`'s `kept_linecode` rebuild) solely to support a new belt-and-braces guard: every
matched record now asserts `!startswith(r.name, "CAP_")` before being collected, throwing loudly
if it ever fires (it never does today — CAP_ stubs parse into `inline_recs`, never
`linecode_recs` — the guard exists for a future data-refresh misclassification). The count
assertion moved from `length(pairs) == 2` to `length(pairs) == 8`. Reused
`compute_bus_degrees`/`resolve_merge_pairs`/`apply_merge!` completely unchanged — no second code
path.

Full regeneration printed exactly 8 pairs merged, and **all 8 survivors matched the plan's
hand-computed degree table exactly**, including the two non-obvious transformer-attachment cases:
`L3104796 -> M1125974` (xfmr `T5260569C`'s `mv_base` correctly renamed) and `M1047744 ->
L3178971` (xfmr `T5338896A` already sat on the survivor, confirmed a no-op rename, not a special
case). `resolve_merge_pairs`'s pairwise-disjointness assertion ran over all 8 pairs without
throwing, confirming the 16 distinct bus names are genuinely disjoint. Both fixtures constructed
without throwing, and all 6 new casualty bus names (`P829798`, `M1047612`, `M1069310`,
`L3104796`, `M1026708`, `M1047744`) are confirmed absent (0 matches each) from the regenerated
`src/data/ieee8500_impedances.jl`.

### Task 2 — reconcile the measured delta, re-run both test files, re-pin goldens with justification (`src/data/ieee8500.jl`, `test/test_benchmark_ieee8500.jl`)

Measured bus/branch counts: `ieee8500_modified()` (headline) `4872/4871 -> 4866/4865`;
`ieee8500_mv_modified()` (MV-only) `2518/2517 -> 2512/2511`. **This matches the plan's own
recounted "6 new merges" prediction exactly** (not the task-framing directory name's stated "5")
— no discrepancy investigation was needed since the measured delta matched the pre-stated correct
prediction on the first try. `src/data/ieee8500.jl`'s header doc-comment corrected accordingly,
with a dated note citing this task appended after the 260822-pxb note (not replacing it).

`julia --project=. test/test_ieee8500.jl` passed 26896/26896 assertions unmodified — the file's
own audit (no MV-bus-count literal exists there) held, confirmed live rather than assumed. D-08
head `smax` invariant explicitly re-verified on both fixtures (`55.0` pu, unique branch touching
`IEEE8500_ROOT_BUS`); total load re-verified conserved at `10773.170000000011` kW; 1177 load buses
on the headline fixture, unchanged.

`julia --project=. test/test_benchmark_ieee8500.jl` failed as expected on the two pinned D-16
goldens (`model_vars: 137144 != 137444`, `model_cons: 274218 != 274818`) — the file's OWN Test 1
(run `--quick` twice in the same session, compare directly) confirmed the new values were stable
BEFORE re-pinning them. `termination_status`/`admm_status`/`admm_iters` were unchanged, left
untouched. Re-ran after the update: 10/10 pass.

### Task 3 — re-measure the 3 SOCP-exactness points, build a 3-column before/after table, report honestly (`results/ieee8500_benchmark/socp_gap_report.csv`, `deferred-items.md`, `25-DATA-PROVENANCE.md`)

Preserved the pass-1 (post-260822-pxb) `socp_gap_report.csv` rows via `git show HEAD~2:...` before
re-running the 3 `--gap-report` points (the harness's own CSV upsert-by-`point`-key would
otherwise overwrite them in place) — all 3 confirmed to reproduce the plan's cited pass-1 values
exactly. Re-ran all 3 points sequentially, one Julia process at a time; all 3 reached `OPTIMAL`.

## 3-column before/after table

| Point | pre-merge gap | pass-1 gap (260822-pxb) | pass-2 gap (260822-rle) | pass-1 offender (`r_pu`) | pass-2 offender (`r_pu`) |
|---|---|---|---|---|---|
| `ieee8500,density=0.1,T=10,tol=1e-6` | 0.0325016 | 0.0061304 | **0.0018221** | `M1069310->M1069311` (9.373e-7) | `L2916620->N1136366` (2.401e-6) |
| `ieee8500-mv,density=0.1,T=24,tol=1e-8` | 0.0005781 | 0.0003853 | **0.0002056** | `M1069310->M1069311` (9.373e-7) | `L2916620->N1136366` (2.401e-6) |
| `ieee8500-mv,density=0.25,T=24,tol=1e-8` | 0.0037728 | 0.0008137 | **0.0005239** | `M1069310->M1069311` (9.373e-7) | `L2916620->N1136366` (2.401e-6) |

Verdict against each fixture's own (unchanged, never re-tuned) `EXACTNESS_ATOL`
(`IEEE8500_EXACT_ATOL=0.0049691451`, `IEEE8500_MV_EXACT_ATOL=0.0011460286`, read live from
`scripts/benchmark_ieee8500.jl` and confirmed byte-identical):

| Point | pass-1 verdict | pass-2 verdict |
|---|---|---|
| `ieee8500,density=0.1,T=10` | INEXACT (1.23x over) | **EXACT (0.367x of atol)** |
| `ieee8500-mv,density=0.1` | EXACT (0.336x) | EXACT (0.179x, more margin) |
| `ieee8500-mv,density=0.25` | EXACT (0.710x) | EXACT (0.457x, more margin) |

**Honest verdict: the headline point — the one that stayed INEXACT after the pass-1 merge — now
genuinely classifies EXACT, with real margin.** This is a real resolution, not another
dominance-transfer-without-net-improvement. No atol, tolerance, or threshold was adjusted; only
the merge scope widened via the same generic machinery.

**New dominant offender, all 3 points: `L2916620<->N1136366`** (`r_pu=2.401e-6`, ~2.6x the
just-merged-away `M1069310->M1069311`'s `9.373e-7`). Resolved to source line `LN5472390-3`
(`Lines.dss` line 1788, `length=0.004744927 km` = **4.745 metres**) — well above this task's
`< 1 metre` scope and nearly 6x the longest segment this task merged. This is a genuinely longer
real conductor, not another sub-metre split artifact — the honest "next tier" this item's own
rubric anticipated. `assert_socp_exact!`'s project-default `atol=1e-6` gate still does NOT pass at
any of the 3 points (all 3 pass-2 gaps remain `~1e-3`-`~1e-4` scale); this was never claimed.

`deferred-items.md` Item 5 gained a dated "quick task 260822-rle" outcome sub-entry (appended, not
replacing the 260822-pxb entry); `25-DATA-PROVENANCE.md` gained a further "FURTHER SUPERSEDING
deviation" section documenting the 6 new pairs/survivors, the CAP_/switch exclusion boundary, and
a further non-comparability note. Both files grew only (confirmed via `git diff --stat`, 0
deletions in either file).

## Verification

| Check | Result |
|---|---|
| `julia scripts/reduce_ieee8500_impedances.jl --verify` | PASS (CT5 sanity, unaffected) |
| `julia scripts/reduce_ieee8500_impedances.jl` regenerate | "Bus merge (length-class): 8 pairs merged" — all 8 survivors match the plan's table exactly |
| 6 new casualty names absent from generated table | confirmed, 0 matches each (`P829798`, `M1047612`, `M1069310`, `L3104796`, `M1026708`, `M1047744`) |
| CAP_-prefix guard present in `detect_length_class_merge_pairs` | confirmed via grep |
| Both fixtures construct | `4866 4865 2512 2511` — matches the plan's own recounted "6 new" prediction exactly |
| D-08 head `smax` invariant, both fixtures | `55.0` pu, unique branch touching root |
| Total load conservation | `10773.170000000011` kW, 1177 load buses headline |
| `julia --project=. test/test_ieee8500.jl` | 26896/26896 pass, unmodified |
| `julia --project=. test/test_benchmark_ieee8500.jl` | 10/10 pass after re-pinning 2 goldens (stability-confirmed first via the file's own Test 1) |
| 3 `--gap-report` re-measurements | all `OPTIMAL`, all wrote 20 offender rows, one process at a time |
| `git diff --stat` on `deferred-items.md`/`25-DATA-PROVENANCE.md` | both grew, 0 deletions |
| `git diff --diff-filter=D` after each commit | no unexpected deletions |

## Deviations from Plan

None — plan executed exactly as written, including the exact predicted survivor/degree values
for all 6 new merges and the exact predicted bus-count reconciliation (6-new, matching
4866/4865/2512/2511, not the task-framing's "5").

## Issues Encountered

None. All 3 gap-report solves reached `OPTIMAL` on the first attempt. Machine had 2.1-2.7 GiB
free / 6.4-6.9 GiB available throughout (shared machine, checked via `free -h` before each solve);
ran one Julia process at a time, using `run_in_background` + polling against exit-code files
rather than blocking foreground waits, per the shared-machine and turn-discipline constraints. No
OOM occurred at any point. The T=10 headline point completed without incident.

## Next Phase Readiness

- The generic bus-merge machinery remains reusable for any future investigation of the newly-named
  next-tier offender, `L2916620<->N1136366` (`LN5472390-3`, 4.745 m real conductor) — this is a
  DIFFERENT class (genuinely longer, not a sub-metre split artifact) and would require its own
  scoping/justification if a future task chooses to pursue it, not a simple threshold rewiden.
- `deferred-items.md` Item 5 now carries an honest, non-manufactured record across THREE passes
  (pre-merge -> pass-1 260822-pxb -> pass-2 260822-rle) — a future plan revisiting IEEE-8500 SOCP
  exactness should read the full chain before assuming the mechanism is fully resolved.
- `assert_socp_exact!`'s project-default `atol=1e-6` still does NOT pass on any of these 3 points
  — this task never claimed otherwise. Item 2 (whether `exactness.jl` should special-case
  near-zero-impedance branches) remains open and unaddressed.

## Known Stubs

None — this is a data-reduction/measurement quick task with no UI or data-rendering surface.

## Threat Flags

None — no new network endpoints, auth paths, or trust-boundary surface introduced. All changes
are offline data reduction (dependency-free Base+regex script) and test/measurement code.

## Self-Check: PASSED

- FOUND: commit `5b653e5`
- FOUND: commit `7d99f4f`
- FOUND: commit `876b1e0`
- FOUND: `scripts/reduce_ieee8500_impedances.jl` (`MV_SUBMETRE_LENGTH_KM_BOUND`/CAP_ guard/`name` field present)
- FOUND: `src/data/ieee8500_impedances.jl` (regenerated; 6 new casualty bus names absent)
- FOUND: `src/data/ieee8500.jl` (header counts corrected to 4866/2512)
- FOUND: `test/test_benchmark_ieee8500.jl` (goldens updated to 137144/274218, passing)
- FOUND: `results/ieee8500_benchmark/socp_gap_report.csv` (3 points re-measured, pass-2 rows present)
- FOUND: `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` (Item 5 outcome (continued) sub-entry appended)
- FOUND: `.planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md` (further superseding section appended)
- FOUND: `.planning/quick/260822-rle-widen-ieee-8500-bus-merge-threshold-to-s/260822-rle-SUMMARY.md`
