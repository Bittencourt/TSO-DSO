---
phase: 25-ieee-8500-scalability-benchmark
plan: 07
subsystem: data
tags: [opendss, ieee8500, socp-exactness, lindistflow, data-provenance, julia]

# Dependency graph
requires:
  - phase: 25-01
    provides: "Dependency-free scripts/reduce_ieee8500_impedances.jl + generated src/data/ieee8500_impedances.jl"
  - phase: 25-05
    provides: "socp_relaxation_gap(ctx); scripts/benchmark_ieee8500.jl --calibrate-noise-floor; deferred-items.md item 1's original finding"
provides:
  - "scripts/reduce_ieee8500_impedances.jl's reshape_near_zero_mv_edges!: D-13 near-ideal reshape of the one degenerate MV busbar-tie connector, with an explicit documented threshold + loud assert-exactly-1 check"
  - "Regenerated src/data/ieee8500_impedances.jl with the corrected (HVMV_Sub_48332, _HVMV_Sub_LSB) r/x values"
  - "Re-calibrated IEEE8500_MV_EXACT_ATOL/IEEE8500_EXACT_ATOL (both ~150x smaller, genuinely noise-like) in scripts/benchmark_ieee8500.jl"
  - "deferred-items.md item 1 marked RESOLVED with full before/after measurement; items 2/3 left open"
affects: [25-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "In-place data-shaping reshape (never remove/relocate the edge) for a degenerate real-world connector, with an explicit numeric threshold + loud assert-exactly-N guard so a future upstream refresh cannot silently widen the treatment"

key-files:
  created:
    - .planning/phases/25-ieee-8500-scalability-benchmark/25-07-SUMMARY.md
  modified:
    - scripts/reduce_ieee8500_impedances.jl
    - src/data/ieee8500_impedances.jl
    - scripts/benchmark_ieee8500.jl
    - results/ieee8500_benchmark/noise_floor_calibration.csv
    - results/ieee8500_benchmark/density_sweep.csv
    - .planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md
    - .planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md

key-decisions:
  - "Fixed in the REDUCTION SCRIPT, not by hand-editing the generated table — preserves plan 25-01's must-have that the committed table is regenerable from vendored source by one dependency-free script"
  - "The reshaped edge KEEPS its native entry in IEEE8500_MV_BRANCH_RX_OHMS (same bus pair, same table, same connectivity) — only its r_ohm/x_ohm VALUES change to the D-13 near-ideal Ω-equivalent of IEEE123_SWITCH_R/X at this fixture's own MV base (r=0.09330 Ω, x=0.04665 Ω). IEEE8500_REGULATOR_EDGES (the Set-based 'no real Ω value' category) is deliberately left untouched at 43 entries — this is a narrower, table-local fix, not a move into the regulator/switch near-ideal mechanism"
  - "Detection uses an explicit, documented numeric threshold (r_ohm < 1e-5 Ω) plus a loud assert-exactly-1 check, never a hardcoded bus-pair-name match — a future vendored-data refresh that silently reshapes a different or additional set of branches fails fast instead of quietly expanding the treatment"
  - "Re-ran the calibration ladder myself (not reusing the orchestrator's earlier verification numbers) on a machine independently confirmed quiet, per this project's anti-certificate-laundering / measurement-before-golden conventions"

requirements-completed: []

# Metrics
duration: ~35min active execution (plus a CPU quiet-machine gate wait before Task 3)
completed: 2026-08-21
---

# Phase 25 Plan 07: IEEE-8500 D-13 Busbar-Tie Fix + Noise-Floor Re-Calibration Summary

**Applied the project's own D-13 near-ideal-branch treatment to the one degenerate vendored MV busbar-tie connector that structurally broke LinDistFlow SOC-exactness on both IEEE-8500 fixtures, cutting the calibrated noise floors ~150x and restoring genuine tolerance-shrinking (noise-like) behavior — while leaving `solve_admm`'s stricter `atol=1e-6` consolidation gate still unresolved.**

## Performance

- **Duration:** ~35 min of active execution work (code + calibration runs), plus additional
  wall-clock time spent honoring the CPU quiet-machine gate (waiting for the orchestrator's
  full-suite `Pkg.test()` — 29,760 passed — to finish before running any calibration, per this
  task's own `<cpu_gate>` instructions)
- **Tasks:** 4 (reduction-script fix, topology/fixture verification, noise-floor re-calibration, record update)
- **Files modified:** 7 (2 code, 2 generated/committed CSV, 1 doc, 1 provenance doc, 1 new summary)

## Accomplishments

- `scripts/reduce_ieee8500_impedances.jl`'s new `reshape_near_zero_mv_edges!`: detects the ONE
  degenerate MV segment (`("HVMV_Sub_48332", "_HVMV_Sub_LSB")`, the substation Low Side Bus
  busbar tie) via an explicit, documented threshold (`r_ohm < MV_NEAR_ZERO_R_THRESHOLD_OHM =
  1e-5 Ω`), reassigns its `r_ohm`/`x_ohm` in place to the D-13 near-ideal Ω-equivalent of
  `IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` at this fixture's own MV base (`r=0.09330 Ω`,
  `x=0.04665 Ω`, was `1e-6 Ω`/`1e-5 Ω`), and throws loudly unless EXACTLY 1 segment matches
- Regenerated `src/data/ieee8500_impedances.jl` via the script (never hand-edited); `--verify`
  passes; confirmed by diff that ONLY the header comment and this one edge's values changed
- Confirmed topology is fully unaffected: `ieee8500_modified()` still 4,875 buses/4,874 branches,
  `ieee8500_mv_modified()` still 2,521 buses/2,520 branches, both construct cleanly
  (`assert_radial`/`assert_magnitudes` run inside `Feeder(...)` without throwing),
  `IEEE8500_REGULATOR_EDGES` still exactly 43 entries, and the 25-03 `enabled=False` 38/5 split
  is still honored (both counts asserted inside `main()`, which ran without error)
- Re-measured both fixtures' SOCP-exactness noise floors on a machine independently confirmed
  quiet:

  | Fixture | Floor before | Floor after | Improvement |
  |---|---|---|---|
  | `ieee8500-mv` | 0.1795915651 (tol=1e-8, plateaued) | 0.0011460286 (tol=1e-8, shrinking 27x tighter than tol=1e-6) | 157x |
  | `ieee8500` | 0.5653322911 (tol=1e-6, every tighter rung failed) | 0.0049691451 (tol=1e-7) | 114x, AND now reaches a second rung at all |

  Both fixtures' residuals now genuinely SHRINK as `tol_gap` tightens instead of
  plateauing/immediately failing — behaving like real interior-point numerical noise rather than
  a structural relaxation floor.
- Updated `IEEE8500_MV_EXACT_ATOL`/`IEEE8500_EXACT_ATOL` in `scripts/benchmark_ieee8500.jl` and
  the committed `results/ieee8500_benchmark/noise_floor_calibration.csv` with the fresh numbers;
  re-ran `test/test_benchmark_ieee8500.jl` — **all 10/10 D-16 goldens pass unchanged**
  (`model_vars=137594`, `model_cons=275118`, `termination_status=OPTIMAL`,
  `admm_status=budget_exceeded`, `admm_iters=1`); only the never-golden wall-time and
  exactness-gap columns in `density_sweep.csv` moved (`exact_maxgap` dropped from `0.0683` to
  `0.000578`, now well inside the new, much tighter `exact_atol_used`)
- `deferred-items.md` item 1 marked RESOLVED with the full before/after table; items 2 and 3 left
  explicitly open; `25-DATA-PROVENANCE.md` updated with a "Deviation from verbatim transcription"
  section documenting that this ONE edge is not a byte-for-byte transcription of the vendored
  source, and why

## Task Commits

Each task was committed atomically:

1. **Task 1: D-13 reshape in the reduction script + regenerated table** — `a08eabf` (fix)
2. **Task 2: topology/fixture verification** — no separate commit (verification-only; ran
   `ieee8500_modified()`/`ieee8500_mv_modified()` and confirmed counts, no code change required)
3. **Task 3: noise-floor re-calibration** — `1b1da1f` (fix: constants + CSVs)
4. **Task 4: record update** — `670fe38` (docs: provenance + deferred-items, written before Task 3
   ran, since Tasks 1/2/4's doc work is cheap and Task 3 required the CPU quiet-machine gate) +
   `48e3f4c` (docs: finalized deferred-items.md with Task 3's actual fresh measured numbers,
   replacing the placeholder figures)

**Plan metadata:** this SUMMARY.md commit (below) — STATE.md/ROADMAP.md intentionally NOT touched,
per this task's explicit instruction that the orchestrator owns those writes.

**Note on task/commit granularity:** Task 4's doc work was split across two commits because the
task's own instructions front-loaded the doc updates (cheap, no CPU needed) before the CPU-gated
Task 3 calibration runs, then required going back to replace placeholder numbers with Task 3's
actual measurements — both commits are Task 4's work, sequenced around the CPU gate rather than
duplicated.

## Files Created/Modified

- `scripts/reduce_ieee8500_impedances.jl` — new `reshape_near_zero_mv_edges!` function + D-13
  near-ideal-treatment constants (`MV_NEAR_ZERO_R_THRESHOLD_OHM`,
  `D13_NEAR_IDEAL_R_OHM_AT_MV_BASE`/`X_OHM_AT_MV_BASE`), wired into `main()` before dedupe; file
  header and `emit_output`'s generated-file header comment both updated for provenance
- `src/data/ieee8500_impedances.jl` — regenerated; only the `("HVMV_Sub_48332",
  "_HVMV_Sub_LSB")` entry's values and the header comment changed
- `scripts/benchmark_ieee8500.jl` — `IEEE8500_MV_EXACT_ATOL`/`IEEE8500_EXACT_ATOL` re-measured;
  surrounding comment rewritten to document what changed and why, plus the retained
  `solve_admm` atol caveat
- `results/ieee8500_benchmark/noise_floor_calibration.csv` — upserted with the fresh 5-rung
  ladders for both `ieee8500-mv` and `ieee8500`
- `results/ieee8500_benchmark/density_sweep.csv` — `--quick` point's row refreshed (same model
  dimensions/status/iteration count, new timing and exactness-gap columns)
- `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` — item 1 marked
  RESOLVED with full before/after table; items 2/3 preserved as open, de-duplicated
- `.planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md` — new "Deviation
  from verbatim transcription" section

## Decisions Made

- **Fixed in the reduction script, not the generated table:** hand-editing
  `src/data/ieee8500_impedances.jl` would have broken plan 25-01's must-have that the table is
  regenerable end-to-end from vendored source by one dependency-free script (including
  `--verify`). All 4 authorized files were touched; `src/data/ieee8500.jl` was NOT touched (not
  needed — its existing generic loop over `IEEE8500_REGULATOR_EDGES` membership is untouched
  because this fix does not add to that set).
- **Table placement:** the reshaped edge stays in `IEEE8500_MV_BRANCH_RX_OHMS` with corrected
  values, rather than moving into the `IEEE8500_REGULATOR_EDGES` Set-based "no real Ω value"
  category. This matches the task's own success criterion that `IEEE8500_REGULATOR_EDGES` remain
  at 43 entries (topology/categorization unchanged; only this one edge's numeric values changed).
- **Threshold-based, not name-based, detection:** `r_ohm < 1e-5 Ω` with a loud assert-exactly-1
  check, so a future vendored-source refresh that changes which segments are degenerate is caught
  immediately rather than silently reshaping a different scope.
- **Numbers measured fresh, not copied from the orchestrator's earlier verification run:** the
  orchestrator's pre-verified evidence (quoted in this task's brief) closely matches what I
  independently re-measured (`0.0011460286` vs. their quoted `~0.001141`), consistent with running
  the identical code change — but the numbers actually committed to `deferred-items.md` and
  `scripts/benchmark_ieee8500.jl` are this task's own Task 3 measurement.

## Deviations from Plan

None — plan executed exactly as written. Task 2 required no code change (verification-only,
confirmed via direct construction of both fixtures), which is consistent with the task's own
framing ("Confirm topology and fixtures are unaffected").

## Issues Encountered

- **CPU quiet-machine gate:** the orchestrator's full-suite `Pkg.test()` was running when this
  task started; Tasks 1, 2, and the doc portions of Task 4 were completed first (as instructed),
  and Task 3's calibration runs were held until the orchestrator confirmed the machine was quiet
  (29,760 tests passed). The orchestrator also flagged that the originally-suggested poll pattern
  (`pgrep -f "import Pkg; Pkg.test"`) self-matches its own wrapper process and never exits; this
  was corrected by polling a LOG FILE marker instead (`until grep -q "^wrote " <logfile>; do sleep
  10; done`, launched via `run_in_background`), which completed correctly for both calibration
  runs.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plan 25-06 (headline results) can now use `scripts/benchmark_ieee8500.jl`'s density-sweep mode
  with the corrected, genuinely-noise-like `IEEE8500_MV_EXACT_ATOL`/`IEEE8500_EXACT_ATOL`
  constants — the `exact_verdict` classification against them is now a meaningful check rather
  than the much-weaker check the original inflated floors implied.
- **Honest caveat carried forward (deferred-items.md item 3, still OPEN):** even after this fix,
  both re-measured floors are still `~1e-3` scale, which STILL exceeds `solve_admm`'s hardcoded
  final-consolidation `assert_socp_exact!` default of `atol=1e-6` (no override parameter exists
  on `solve_admm`). A genuinely CONVERGED, CONSOLIDATED ADMM point on either IEEE-8500 fixture
  can still throw at that gate. This fix closes the STRUCTURAL relaxation failure (the residual
  now behaves like noise and shrinks with tolerance) but does NOT make ADMM consolidation work on
  these fixtures — plan 25-06 should still expect (and honestly report, per D-18/T-25-11)
  `ERROR:*` or `budget_exceeded` ADMM rows rather than a clean `:converged` status on either
  IEEE-8500 fixture, unless a follow-up `solve_admm` atol-override fix lands first.
- **Deferred-items.md item 2 (still OPEN, not touched):** whether `assert_socp_exact!`/
  `socp_relaxation_gap` should special-case or exclude near-zero-impedance branches from the
  max-gap scan in general — `src/models/exactness.jl` was not in this task's authorized file list.
- No blockers for plan 25-06 to start.

---
*Phase: 25-ieee-8500-scalability-benchmark*
*Completed: 2026-08-21*

## Self-Check: PASSED

- All 8 claimed files (`scripts/reduce_ieee8500_impedances.jl`, `src/data/ieee8500_impedances.jl`,
  `scripts/benchmark_ieee8500.jl`, `results/ieee8500_benchmark/noise_floor_calibration.csv`,
  `results/ieee8500_benchmark/density_sweep.csv`, `deferred-items.md`, `25-DATA-PROVENANCE.md`,
  this summary) verified present on disk.
- All 4 task commits (`a08eabf`, `670fe38`, `1b1da1f`, `48e3f4c`) verified present in `git log`.
