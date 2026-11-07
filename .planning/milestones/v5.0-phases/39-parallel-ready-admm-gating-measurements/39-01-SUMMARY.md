---
phase: 39-parallel-ready-admm-gating-measurements
plan: 01
subsystem: admm
tags: [clarabel, threading, determinism, bitwise, spike, par-02, gate, juMP]

# Dependency graph
requires:
  - phase: 34-admm-decomposition-meshed-reactive-status-exception-policy
    provides: the `_admm_build`/`_react_agr_solve!` per-aggregator solve grain the spike measures
provides:
  - "Spike 005 PAR-02 gate artifact: documented PASS verdict — Clarabel solves inside Threads.@spawn tasks are bitwise-equal to serial on the real multi-aggregator fixture under the production configuration (julia -t 4, BLAS=1, MOI.NumberOfThreads()=1)"
  - "Settled direct_model question: constructs on JuMP 1.30.1 but fails at first @variable with MathOptInterface.AddVariableNotAllowed — the ADMM build-once/set_objective_coefficient loop cannot run on a direct model (Clarabel stays copy_to-only)"
  - "Re-runnable spike harness with live-proof controls: positive (fresh-state serial reproduces itself bitwise), cross-state, negative (perturbation MUST fail the byte-compare; ulp-escalation recorded as data)"
affects: [39-02-threaded-executor, 39-04-equality-tests, 40-pop-05-scaling]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Bitwise comparator idiom: reinterpret(UInt8,·) byte equality + isequal (never isapprox) + FNV-1a digest per (leg, unit) for attributability"
    - "Solver-thread pinning in-process: BLAS.set_num_threads(1) once + MOI.NumberOfThreads()=>1 per model (factory defaults untouched)"

key-files:
  created:
    - .planning/spikes/005-clarabel-concurrency/sweep.jl
    - .planning/spikes/005-clarabel-concurrency/sweep.csv
    - .planning/spikes/005-clarabel-concurrency/README.md
  modified:
    - .planning/spikes/MANIFEST.md

key-decisions:
  - "Spike verdict recorded PASS from three consecutive real runs: threaded == serial BITWISE-EQUAL on all 10 IEEE-13 aggregators — the PAR-02 gate opens for the Phase-39 threaded executor (39-02/39-04 equality tests remain the end-to-end arbiter)"
  - "Negative control implements a ulp-escalation ladder starting at the plan's flat +eps() because the solver absorbed 1 ulp (bit-identical output); perturbation became visible at eps()*2^1 — recorded as a data row, not a loosened gate"
  - "direct_model outcome recorded as classified data (AddVariableNotAllowed at first variable addition), refining but not editing the factory.jl 2026-07-18 note (spikes observe without mutating src/)"

patterns-established:
  - "Spike-005 control triple: positive (reproduce known bitwise result), cross-state (third fresh state), negative (deliberately perturbed copy MUST fail the byte-compare) — checked on every run, script errors loudly otherwise"
  - "Fixture replication through the production factory seams (build_feeder/generate_profiles/build_price/build_population/sub_seed) matching Scenario._materialize verbatim"

requirements-completed: [PAR-02]

# Metrics
duration: 9min
completed: 2026-10-24
---

# Phase 39 Plan 01: Parallel-Ready ADMM & Gating Measurements — Spike 005 Summary

**Clarabel concurrency spike (spike 005) recorded a PASS verdict: threaded @spawn solves are bitwise-equal to serial on the 10-aggregator IEEE-13 ADMM fixture under the production configuration, and direct_model is settled as AddVariableNotAllowed at first variable addition**

## Performance

- **Duration:** 9 min
- **Started:** 2026-10-24T03:45:57Z
- **Completed:** 2026-10-24T03:54:40Z
- **Tasks:** 2
- **Files modified:** 4 (3 created, 1 modified)

## Accomplishments
- Spike 005 ran green under `julia -t 4` on the production `_admm_build` fixture (IEEE-13, seed 7, T=24, ConvexBranchFlow, LIVE reactive consensus, 10 aggregators): the threaded leg is **BITWISE-EQUAL** to serial on every aggregator (pag bytes, objective value, utility, BarrierIterations) across 3 consecutive fresh-process runs
- The PAR-02 gate artifact is complete: `README.md` records `verdict: PASS` citing `sweep.csv` rows; MANIFEST row registered — per the locked decision, the threaded executor may now be enabled by plan 39-02
- The `direct_model` question is settled in writing: `JuMP.direct_model(Clarabel.Optimizer())` constructs but fails at the first `@variable` with `MathOptInterface.AddVariableNotAllowed` — recorded as a classified outcome row, so the ADMM build-once/`set_objective_coefficient` loop stays on indirect construction (Clarabel copy_to-only)
- All three research source facts confirmed on the real fixture (not just toy QPs): bitwise concurrency equality, `AddVariableNotAllowed` failure mode, and acceptance of `MOI.NumberOfThreads() => 1` by Clarabel 0.11.1

## Task Commits

Each task was committed atomically:

1. **Task 1: Write and run the spike sweep (serial vs threaded vs direct_model, with controls)** - `898894a` (feat)
2. **Task 2: Record the verdict (README) and register the spike** - `9893a59` (docs)

**Plan metadata:** (this commit)

## Files Created/Modified
- `.planning/spikes/005-clarabel-concurrency/sweep.jl` - Re-runnable spike: serial_ref / serial_recheck / threaded @spawn / direct_model legs on the production factory fixture; bitwise comparator; control triple; include-safe; stdout table + sweep.csv
- `.planning/spikes/005-clarabel-concurrency/sweep.csv` - 166 keyed rows (leg, bus, metric, value, note): per-(leg, j) FNV-1a digests, per-metric equality, controls, direct_model outcome, verdict
- `.planning/spikes/005-clarabel-concurrency/README.md` - Spike-001-shape frontmatter with `verdict: PASS`, method, production configuration, results citing sweep.csv, documented direct_model answer, consequence line
- `.planning/spikes/MANIFEST.md` - Spike 005 registered in the manifest matching the existing row format

## Decisions Made
- Verdict filled from the ACTUAL run per the honesty policy: PASS (threaded bitwise-equal, controls green, 3 consecutive runs) — never re-run-until-pass (the runs were identical anyway)
- Negative control uses a ulp-escalation ladder seeded at the plan's `+eps()`: the solver absorbed a 1-ulp coupling-price perturbation (bit-identical output), and the perturbation became visible at `eps()*2^1`. The control's PURPOSE (comparator proven live) is intact and strengthened; the ulp count is recorded as data in sweep.csv
- `solve_agr!` (the production mid-loop grain) used as the per-task unit exactly as `_react_agr_solve!` calls it (LIVE kwargs, `check_battery=false, strict=false`), minus the `st` writes — no hand-rolled coefficient mutation, tasks touch only their own AgrOpt.model

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Negative control: flat 1-ulp perturbation was solver-absorbed**
- **Found during:** Task 1 (design-time robustness, confirmed live on first run)
- **Issue:** The plan's negative control perturbed one coupling coefficient by exactly `+eps()`; a 1-ulp input perturbation produces bit-identical solver output on this QP, which would have tripped the plan's own "if either control misbehaves, error loudly" clause on every run
- **Fix:** Escalate ulp-by-ulp (`eps()*2^k`, k = 0..20) until the byte-compare fails; the k that first became visible (k=1) is recorded as a `negative_control` data row. A comparator that cannot detect ANY perturbation still errors the script
- **Files modified:** .planning/spikes/005-clarabel-concurrency/sweep.jl, documented in README.md
- **Verification:** Negative control FAILED_AS_DESIGNED on all 3 runs; positive/cross-state controls PASS on all 3 runs
- **Committed in:** 898894a (Task 1 commit)

**2. [Rule 1 - Bug] Multi-line exception text broke sweep.csv line-addressability**
- **Found during:** Task 1 (post-run inspection)
- **Issue:** The direct_model leg's `showerror` note embeds newlines, producing quoted multi-line CSV rows that break line-based inspection (grep/cut) of sweep.csv
- **Fix:** `row!` sanitizes `\n`→`" | "` (and strips `\r`) so the CSV stays one physical line per row; 167 lines = header + 166 rows
- **Files modified:** .planning/spikes/005-clarabel-concurrency/sweep.jl (regenerated sweep.csv)
- **Verification:** `wc -l sweep.csv` = 167; `cut -d, -f1` lists exactly the 10 leg kinds
- **Committed in:** 898894a (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 × Rule 1, both in spike harness mechanics — the agent's-discretion zone named by 39-CONTEXT.md)
**Impact on plan:** Both fixes are confined to the spike harness and strengthen the measurement's honesty (a live comparator, a line-addressable evidence file). No src/ changes; no gate loosened; canary untouched.

## Issues Encountered
- None beyond the two auto-fixed items above. Three consecutive fresh-process runs produced identical digests and the same verdict, so no flakiness was observed at this grain.

## Known Stubs
None — the spike is fully wired to the production factory (`TSODSO._admm_build`), all legs execute, and all outcomes are recorded.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 39-02 (threaded executor) is unblocked: the PAR-02 gate is PASSED and documented; the executor split in `admm_phases.jl` can consume the exact patterns verified here (fetch-in-load_nodes-order + TaskFailedException unwrap, BLAS pinned once, MOI.NumberOfThreads()=>1 per model)
- Plan 39-04's serial-vs-threaded equality tests remain the end-to-end arbiter (this spike measured the solve-only per-aggregator grain at iteration 1; the full-loop float-order contract still gets its own regression tests)
- The `direct_model` finding means Clarabel-backed hot loops must keep indirect construction — relevant context for any future perf work (the factory.jl 2026-07-18 note's failure mode is now refined in the spike README, left unedited in src/ per observe-only discipline)

---
*Phase: 39-parallel-ready-admm-gating-measurements*
*Completed: 2026-10-24*

## Self-Check: PASSED

- Files: sweep.jl, sweep.csv, README.md all FOUND in .planning/spikes/005-clarabel-concurrency/; MANIFEST.md contains the 005 row
- Commits: 898894a (Task 1, feat) and 9893a59 (Task 2, docs) both FOUND in git log
- src/ untouched: `git status --porcelain src/` empty after all runs
- Verdict line verified: `verdict: PASS` (no PENDING); threaded_vs_serial = BITWISE-EQUAL in sweep.csv
