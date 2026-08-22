---
quick_id: 260822-hld
description: Phase-25 round-2 follow-up — thread ADMM exactness-gate atol, calibration-density/t-horizon flags, measure the ieee8500 density-0.1/T=10 point
date: 2026-08-22
status: complete
commits:
  - c15eb4a (Task A — thread EXACTNESS_ATOL into run_admm_point's solve_admm atol_exact)
  - a42046e (Task B — --calibration-density and --t-horizon on calibrate mode)
  - 262c983 (Task C — cols=:union vcat bug fix; measure the ieee8500 density-0.1/T=10 point)
  - 91a5b83 (docs — mark phase-25 deferred item 3 resolved)
---

# Quick Task 260822-hld — Summary

Threaded quick task 260822-f0b's `atol_exact`/`rtol_exact` override seam into `solve_admm`'s
ADMM path using the SAME freshly-measured, per-fixture `EXACTNESS_ATOL[fixture_sym]` noise floor
already used for the centralized point's own `exact_verdict` — never a literal chosen to pass a
specific point (T-25-12 anti-certificate-laundering). Extended the noise-floor calibration mode
with `--calibration-density`/`--t-horizon` overrides so a point-appropriate floor can be measured
at ANY (density, T_horizon), not just the hardcoded 0.05/24. Then actually ran the density-0.1/
T=10 `ieee8500` point end-to-end: the ADMM consolidation gate, which previously threw
`SOCP relaxation INEXACT`, now converges. This closes phase-25's deferred Item 3
(`solve_admm`'s hardcoded, unthreaded final-consolidation `atol`).

## Note on the missing PLAN.md

`.planning/quick/260822-hld-phase-25-round2-thread-admm-exactness-at/260822-hld-PLAN.md` — listed
as "THE PLAN — authoritative" in this executor's own launch instructions — did **not exist**
anywhere in this worktree, the main checkout, or git history (`git log --all` for any
`260822-hld` path addition returns nothing). Rather than treat this as a hard blocker, I executed
directly from the extremely detailed `<hard_constraints>`, `<success_criteria>`,
`<measured_context>`, and `<verification_notes>` embedded in my own launch prompt, which together
fully specified Tasks A/B/C, the exact CLI invocations, the exact numeric floor comparisons
expected, and the verification commands. This SUMMARY documents what was actually built and
measured against those embedded specifications. Flagging this discrepancy for the orchestrator —
a PLAN.md should exist for this quick task and does not.

## What changed

### Task A — thread `EXACTNESS_ATOL[fixture_sym]` into `solve_admm`'s `atol_exact` (`scripts/benchmark_ieee8500.jl`)

- `run_admm_point` gains a new `atol_exact::Real` parameter, threaded straight through to
  `solve_admm(...; atol_exact = atol_exact)` — the additive gate-override seam quick task
  260822-f0b built onto the FINAL consolidation `assert_socp_exact!` call only (the mid-loop
  `check_exact = false` call is untouched, as before).
- `run_sweep_mode`'s call site passes `atol` — the SAME `EXACTNESS_ATOL[fixture_sym]` variable
  already computed and used for the centralized point's `exact_atol_used`/`exact_verdict` columns
  a few lines above. No new constant, no new lookup — literally the same value, reused.
- New `admm_atol_used` CSV column on `density_sweep.csv` records the value actually passed.
- **Anti-certificate-laundering (T-25-12):** the threaded value is always a value ALREADY measured
  and committed via `--calibrate-noise-floor` for that fixture — never a number chosen to make a
  specific point pass. Verified live in Task C: a point whose cone gap (`1.3968e-4`) sits well
  BELOW its fixture's measured floor (`4.9691e-3`) now correctly passes; the SAME point, under the
  OLD unthreaded default (`atol=1e-6`, tighter than the fixture's own genuine noise floor), threw
  — demonstrating the gate still discriminates rather than rubber-stamping.

### Task B — `--calibration-density`/`--t-horizon` on calibrate mode (`scripts/benchmark_ieee8500.jl`)

- `run_calibration` and `run_calibrate_mode` now accept/parse explicit `density`/`T_horizon`
  overrides (`--calibration-density <float>`, `--t-horizon <int>`), the latter honouring the SAME
  `>= T_HORIZON_FLOOR` validation `run_sweep_mode` already enforces (refuses, never silently
  clamps). Absent either flag, behaviour is BYTE-IDENTICAL to before (`CALIBRATION_DENSITY=0.05`,
  `T=24`) — verified live by re-running `ieee13`'s default calibration and confirming the
  `measured_gap` values matched the pre-existing committed rows exactly
  (`2.579145160095453e-9` at both `tol=1e-6` and `tol=1e-8`).
- New `density`/`t_horizon` columns on `noise_floor_calibration.csv`; the upsert key changed from
  bare `fixture` to `(fixture, density, t_horizon)` so a fixture calibrated at more than one point
  coexists rather than one measurement silently overwriting another (T-25-11 spirit).
- **Provenance honesty:** backfilled the 12 pre-existing legacy rows with their GENUINE recorded
  provenance (`density=0.05`, `t_horizon=24` — `CALIBRATION_DENSITY`'s and the module-level `T`'s
  actual values at the time those rows were measured), never an assumption of convenience.

### Task C — vcat schema-evolution bug fix + the actual density-0.1/T=10 measurement

**Rule 1 bug, discovered live:** the first real invocation of the density-0.1/T=10 point crashed
`run_sweep_mode`'s own CSV upsert with `ArgumentError: column(s) admm_atol_used are missing from
argument(s) 1` — DataFrames' default `vcat(...; cols = :setequal)` refuses to combine a
freshly-measured row (new `admm_atol_used` column) with the OLDER-schema committed CSV. This SAME
latent bug existed for Task B's `density`/`t_horizon` columns too (masked only because I had
already pre-backfilled `noise_floor_calibration.csv` before first exercising it). Fixed BOTH
upserts (`run_sweep_mode`'s `density_sweep.csv`, `run_calibrate_mode`'s
`noise_floor_calibration.csv`) with `cols = :union`, which fills missing cells with `missing`
instead of throwing — never silently dropping a previously-committed row just because it predates
a later column addition (T-25-11).

**Measured, per this task's hard constraints:**

1. **Point-appropriate calibration ladder** (`--calibrate-noise-floor --fixture ieee8500
   --calibration-density 0.1 --t-horizon 10`, default 5-rung tolerance ladder): only `tol=1e-6`
   resolved (`measured_gap = 0.032501551229094705`); every tighter rung failed `ALMOST_OPTIMAL`.
   Floor = `0.0325016` (the only successful rung). **This is ~6.5x LARGER than the committed
   density-0.05/T=24 floor (`0.0049691451`)** — stated explicitly per this task's hard constraint,
   not glossed over. (Because `CALIBRATION_SEED == _SWEEP_SEED == 20260821` and both use the same
   `density_filtered_population` call, this calibration ladder's network/population is IDENTICAL
   to the actual target sweep point below — a genuinely point-matched measurement, not an
   approximation.)

2. **Target point re-run** (`--fixture ieee8500 --density 0.1 --solver clarabel --t-horizon 10`,
   default `--clarabel-tol` and `--time-limit`, i.e. the SAME invocation the orchestrator's own
   diagnostic used): with Task A's fix live,

   | Field | Before (orchestrator diagnostic, unthreaded `atol=1e-6`) | After (this task, `atol_exact` threaded) |
   |---|---|---|
   | `centralized termination_status` | `ALMOST_OPTIMAL` | `ALMOST_OPTIMAL` — **unchanged, NOT claimed fixed** |
   | `admm_status` | `ERROR:ErrorException` (SOCP relaxation INEXACT, cone gap `1.3968e-4`) | `converged` |
   | `admm_iters` | n/a (threw before returning) | `8` |
   | `admm_atol_used` | n/a (no column existed) | `0.004969145122458496` |
   | `admm_time_s` | n/a | `227.4s` |
   | `admm_peak_rss_delta_mb` | `3280.6` (measured baseline, no OOM) | `3200.4` (consistent, no OOM) |

   The point's measured cone gap (`1.3968e-4`) sits comfortably below EITHER floor — the reused
   density-0.05/T=24 value (`4.9691e-3`, ratio ≈ 0.028) or the freshly-measured, point-appropriate
   density-0.1/T=10 value (`0.0325016`, ratio ≈ 0.0043) — so the converged verdict is robust to
   which floor is used, not a knife-edge pass. **Stated plainly per this task's hard constraint:
   the ADMM gate no longer throws on this point.** The centralized solve's `ALMOST_OPTIMAL` status
   is a SEPARATE, still-open conditioning question (phase-25's deferred Item 4) — explicitly not
   addressed here, and `allow_almost` was never reached for, consistent with `src/core/status.jl`'s
   "the final solve stays strict" policy.

3. **D-16 goldens:** `julia --project=. test/test_benchmark_ieee8500.jl` — 10/10 pass. Running the
   goldens incidentally re-measured the (unrelated) `ieee8500-mv,0.1,clarabel` `--quick` row; only
   its wall-clock columns moved (structural values byte-identical to the golden literals), so those
   5 columns were restored to their git-committed values, keeping this task's own new
   `admm_atol_used` column and the `ieee8500` target-point row intact (a plain `git checkout --`
   would have discarded this task's own legitimate, not-yet-committed measurement — done via a
   targeted column-level restore instead).

4. **`test/test_admm_timeout.jl`:** 17/17 pass — unrelated code path (`solve_admm`'s
   `time_limit_s` D-18 exit), unaffected by this task's changes, run as an extra regression check
   per the plan's verification notes.

## Verification

| Check | Result |
|---|---|
| Script still parses after each task's edits (`Meta.parseall`) | OK, 3x |
| `--calibrate-noise-floor --fixture ieee13` (default density/T) reproduces committed `measured_gap` | Byte-identical (`2.579145160095453e-9`) |
| `--calibrate-noise-floor --fixture ieee13 --calibration-density 0.25 --t-horizon 10` | Produces a distinct, additional row; legacy rows untouched |
| `--t-horizon 5` (below `T_HORIZON_FLOOR=10`) in calibrate mode | Rejected with `ArgumentError`, not silently clamped |
| Density-0.1/T=10 `ieee8500` calibration ladder | `tol=1e-6 -> 0.0325016`; tighter rungs `ALMOST_OPTIMAL` |
| Density-0.1/T=10 `ieee8500` target point, Task A live | `admm_status: ERROR -> converged` (8 iters), `admm_atol_used=0.0049691451` |
| `julia --project=. test/test_benchmark_ieee8500.jl` | 10/10 D-16 goldens pass |
| `julia --project=. test/test_admm_timeout.jl` | 17/17 pass |
| `results/ieee8500_benchmark/density_sweep.csv` after goldens run | Wall-clock-only drift on the unrelated `ieee8500-mv,0.1,clarabel` row restored; this task's own `ieee8500` row and new `admm_atol_used` column intact |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `cols = :union` fix on both CSV-upsert `vcat` calls**
- **Found during:** Task C, first real invocation of the density-0.1/T=10 point
- **Issue:** `run_sweep_mode`'s CSV upsert threw `ArgumentError: column(s) admm_atol_used are
  missing from argument(s) 1` — DataFrames' default `vcat(cols=:setequal)` cannot combine a
  freshly-measured row (Task A's new `admm_atol_used` column) against the older-schema committed
  CSV. The SAME latent bug exists in `run_calibrate_mode`'s upsert (Task B's `density`/
  `t_horizon` columns), masked only because that CSV had already been manually pre-backfilled
  before I first exercised it.
- **Fix:** `vcat(...; cols = :union)` on both upserts — missing cells fill with `missing` instead
  of throwing.
- **Files modified:** `scripts/benchmark_ieee8500.jl`
- **Verification:** re-ran the target point after the fix; CSV write succeeded; `git diff` shows
  only the intended rows changed.
- **Committed in:** `262c983` (Task C commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 bug fix)
**Impact on plan:** Necessary for Task C's own deliverable (the CSV write) to succeed at all; no
scope creep — the fix is confined to the two upsert call sites this task's own schema changes
affected.

## Issues Encountered

- The PLAN.md this task was launched to execute did not exist (see "Note on the missing PLAN.md"
  above). Worked from the embedded task specification instead; flagging for the orchestrator.
- A stray, untracked duplicate `julia` process from an earlier `setsid nohup ... &` launch attempt
  survived past its spawning Bash call and was running CONCURRENTLY with a second, properly
  `run_in_background`-tracked launch of the SAME calibration command — a genuine violation of the
  "one compute process at a time" memory discipline this task's `<memory_note>` requires. Caught
  via `ps -ef` (two PIDs running the identical command line) before it caused OOM; killed the
  untracked stray (`kill -TERM`) and kept the tracked one. No data was corrupted (the stray's own
  log/exit file were captured for the record — `SIGTERM`, exit 143 — and discarded). Lesson
  recorded here rather than silently omitted.

## Next Phase Readiness

- Phase-25 deferred Item 3 (`solve_admm`'s unthreaded final-consolidation `atol`) is now RESOLVED
  — see `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md`'s updated Item 3
  section for the full before/after.
- Item 2 (whether `assert_socp_exact!`/`socp_relaxation_gap` should special-case near-zero-
  impedance branches) remains open and untouched.
- Item 4's centralized-solve `ALMOST_OPTIMAL` conditioning gap at IEEE-8500 headline scale remains
  open and untouched — explicitly NOT addressed by this task (hard constraint 2).
- A future plan wanting a genuinely converged, CERTIFIED-EXACT headline (T=24) IEEE-8500 ADMM
  point still needs Item 4's conditioning gap resolved first (the centralized solve must reach a
  real `OPTIMAL` before `exact_verdict` can even be computed) — this task only closes the ADMM-side
  consolidation-gate gap (Item 3), not the centralized-solve conditioning gap (Item 4).

## Known Stubs

None — no UI/data-rendering stubs; this is a measurement/harness quick task.

## Threat Flags

None — no new network endpoints, auth paths, or trust-boundary surface introduced. The
`atol_exact` threading is a value substitution on an EXISTING internal gate (`solve_admm`'s own
final consolidation check), not a new surface, and remains bound by the same T-25-12
anti-certificate-laundering constraint the seam was built under.

## Self-Check: PASSED

- FOUND: commit `c15eb4a`
- FOUND: commit `a42046e`
- FOUND: commit `262c983`
- FOUND: commit `91a5b83`
- FOUND: `scripts/benchmark_ieee8500.jl`
- FOUND: `results/ieee8500_benchmark/density_sweep.csv`
- FOUND: `results/ieee8500_benchmark/noise_floor_calibration.csv`
- FOUND: `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md`
- FOUND: `.planning/quick/260822-hld-phase-25-round2-thread-admm-exactness-at/260822-hld-SUMMARY.md`
