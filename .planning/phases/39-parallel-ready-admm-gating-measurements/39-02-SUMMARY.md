---
phase: 39-parallel-ready-admm-gating-measurements
plan: 02
subsystem: admm
tags: [threads, parallelism, admm, clarabel, blas, par-01, par-03, task-parallelism]

# Dependency graph
requires:
  - phase: 39-01 (Clarabel concurrency spike)
    provides: spike 005 PASS verdict — threaded @spawn Clarabel solves bitwise-equal to serial on the 10-aggregator IEEE-13 fixture under the production configuration; the documented gate for enabling this executor
provides:
  - "opt-in threaded executor on solve_admm: `parallel::Bool = false` kwarg (last) with fail-loud 1-thread ArgumentError guard; serial default byte-identical (canary never re-pinned)"
  - "split AGR-solve execute step in admm_phases.jl (_agr_solve_step!): serial = exact pre-existing loop; threaded = one Threads.@spawn task per aggregator, fetch in load_nodes order, original-exception rethrow (PAR-03), apply writes serial in the join"
  - "task-safe solve grain in admm_state.jl: _react_agr_solve_only (zero st/ls writes) + _react_agr_apply! (original writes, original order), composed by _react_agr_solve! for the serial path"
  - "BLAS thread-count save/finally-restore on every solve_admm exit path (threaded only); MOI.NumberOfThreads()=1 per AGR model at threaded entry only — factory defaults untouched"
affects: [39-04 (serial-vs-threaded equality + error-parity tests), phase 40 POP-05 scaling, any threaded solve_admm caller]

# Tech tracking
tech-stack:
  added: []
  patterns: ["split execute step: serial/threaded branches share build + consensus, only the AGR grain is executor-dispatched", "fetch-in-order join with TaskFailedException unwrap (throw e.task.exception) for serial error attribution", "task-safe solve grain / serial-join apply split keeping the float-order contract", "process-global BLAS pin at executor entry + finally restore in the orchestrator"]

key-files:
  created: []
  modified:
    - src/admm/solve_admm.jl
    - src/admm/admm_phases.jl
    - src/admm/admm_state.jl

key-decisions:
  - "Executor split lives as planned in admm_phases.jl (_agr_solve_step! helper serves BOTH the mid-loop step and the certify AGR re-solves) — no new module; steps 2-5 stay shared and serial so the float-order contract is untouched"
  - "BLAS pin ownership split: solve_admm.jl snapshots get_num_threads() and restores in finally (every exit path: ConvergenceError throw, budget return, certificate re-wrap); admm_phases.jl sets BLAS=1 + MOI pins ONCE per helper call, never per task"
  - "has_4q indexing gated on final in the spawn comprehension (Rule-1 fix found by the -t 2 smoke: the mid-loop passes has_4q_by_bus = nothing)"
  - "Certify re-solves run the same executor-dispatched grain as the mid-loop step (research RESOLVED Q2), keeping 'all AGR solves are executor-dispatched' semantics uniform"

patterns-established:
  - "Task-safe grain split: _react_agr_solve_only (per-j/loop-invariant reads only, zero shared writes) + _react_agr_apply! (all shared writes in the serial join region) — the reusable shape for any future parallelized stage in this loop"
  - "Original-exception rethrow idiom in joins: e isa TaskFailedException ? throw(e.task.exception) : rethrow() — mirrors solve_admm.jl's type-check-then-rethrow seam"
  - "Additive-kwarg discipline #4: parallel::Bool = false keeps the default path byte-for-byte; canary re-run per task as the golden-policy proof"

requirements-completed: [PAR-01, PAR-03]

# Metrics
duration: 35min
completed: 2026-10-24
---

# Phase 39 Plan 02: Parallel-Ready ADMM Executor Summary

**Opt-in threaded AGR executor on solve_admm (`parallel` kwarg + fail-loud 1-thread guard) with a fetch-in-load_nodes-order join that rethrows original exceptions — serial default proven byte-identical by the unchanged knife-edge canary, and a `-t 2` smoke showing bitwise serial-vs-threaded equality on IEEE-13**

## Performance

- **Duration:** 35 min
- **Started:** 2026-10-24T05:55:46Z
- **Completed:** 2026-10-24T06:31:00Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- `parallel::Bool = false` kwarg (last) on `solve_admm` with the fail-loud guard in the boundary-guard block (`parallel=true requires Threads.nthreads() > 1`, no silent serial fallback), threaded down as a trailing argument to `_admm_iterate!`/`_admm_certify`, docstring Returns/Throws documented, and a try/finally that snapshots/restores the process-global BLAS thread count on EVERY exit path when threaded
- Solve/apply split of `_react_agr_solve!` (both reactive variants): `_react_agr_solve_only` touches only per-j/loop-invariant state and its own AgrOpt model (grep-verified zero `st`/`ls` writes) while `_react_agr_apply!` performs the original writes in the original order; composition keeps the serial statement sequence identical
- `_agr_solve_step!` dispatches the AGR grain for both the mid-loop step and the certify re-solves: serial branch is the exact pre-existing loop; threaded branch pins BLAS=1 + MOI NumberOfThreads=1 at entry (once per call, threaded path only), spawns one task per aggregator, fetches in `load_nodes` order, unwraps `TaskFailedException` → `throw(e.task.exception)` (PAR-03 original-exception parity), and applies writes serially
- Measured evidence: threaded run under `-t 2` is bitwise-EQUAL to serial on the IEEE-13 fixture (iters 56, welfare -4823.66604824162, dadp/primal/dual/rho traces and mu_q all `==`); BLAS count restored after return; 1-thread `parallel=true` call throws the exact ArgumentError

## Task Commits

Each task was committed atomically:

1. **Task 1: parallel kwarg, fail-loud guard, flag threaded down + callee signature extension** - `57f60ba` (feat)
2. **Task 2: Solve/apply split of _react_agr_solve! (admm_state.jl)** - `40f930a` (refactor)
3. **Task 3: Split execute step + fetch-in-order join (admm_phases.jl)** - `1af3dda` (feat)

## Files Created/Modified
- `src/admm/solve_admm.jl` — `parallel::Bool = false` last kwarg, 1-thread ArgumentError guard, flag-down to both internal calls, BLAS save/finally-restore wrapping iterate+certify, docstring threaded-executor section + Throws entry
- `src/admm/admm_phases.jl` — trailing `parallel::Bool = false` on both callee signatures (Task 1, signature-only), `_agr_solve_step!` serial/threaded dispatcher, SEAM header executor-split contract, `using LinearAlgebra: BLAS`
- `src/admm/admm_state.jl` — `_react_agr_solve_only`/`_react_agr_apply!` split per reactive variant with `_react_agr_solve!` as back-to-back composition

## Decisions Made
- Followed the plan's structure exactly; the two verification greps written for single-line call sites (`ρ_max, time_limit_s, parallel)` / `rtol_exact, parallel)`) cannot survive the pinned JuliaFormatter 2.10 layout (92-col margin reformats both calls multi-line), so the semantic criterion was verified instead: both call sites pass `parallel` as the trailing argument (visible in the committed diff), and the anti-pattern greps (zero `@sync`/`threadid()` occurrences) pass literally — comment prose was phrased to keep those greps meaningful
- BLAS pin ownership split across the two files (snapshot/restore in solve_admm.jl's finally; set-once at helper entry in admm_phases.jl) exactly per the plan's Task 1/Task 3 division

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] has_4q_by_bus indexed when nothing (threaded mid-loop call)**
- **Found during:** Task 3 (post-edit `-t 2` smoke of the threaded branch)
- **Issue:** the spawn comprehension unconditionally indexed `has_4q_by_bus[jj]`, but the mid-loop call passes `has_4q_by_bus = nothing` (has_4q is only meaningful on final re-solves) — every threaded mid-loop step died with `MethodError: no method matching getindex(::Nothing, ::Int64)`
- **Fix:** gated the index on `final`: `has_4q = final ? has_4q_by_bus[jj] : false` (evaluated at spawn time, outside the task body)
- **Files modified:** src/admm/admm_phases.jl
- **Verification:** `-t 2` threaded solve completes and is bitwise-equal to serial; targeted tests 130/130 after the fix
- **Committed in:** 1af3dda (part of the Task 3 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** The fix was required for the threaded branch to function at all; no scope creep.

## Issues Encountered
- The plan's Task 1 automated verify chain includes two literal single-line greps that the pinned formatter (margin = 92) cannot produce for the extended `_admm_iterate!` call; resolved by verifying the semantic criterion (trailing `parallel` present at both call sites) — documented under Decisions Made
- Smoke scripts were kept in /tmp/opencode (never in the repo) so no generated files needed tracking

## Known Stubs

None — no placeholder/stub patterns in the modified files; the threaded executor is fully wired end-to-end (behavioral formal tests are plan 39-04's deliverable by design, per the plan's own gate note).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Plan 39-04 can land its behavioral tests against a working executor: guard ArgumentError (1-thread-safe), threaded-vs-serial bitwise equality (fixture proven bitwise-equal in this plan's smoke), error-parity via the TaskFailedException unwrap, and the canary-after-parallel BLAS-restore check
- Phase 40's POP-05 scaling consumes this executor; `parallel` is kwarg-only (Scenario identity untouched), so Scenario-level wiring remains Phase 40's concern per the locked decision

---
*Phase: 39-parallel-ready-admm-gating-measurements*
*Completed: 2026-10-24*

## Self-Check: PASSED

- All 3 modified files exist on disk (solve_admm.jl, admm_phases.jl, admm_state.jl)
- SUMMARY.md exists in the phase directory
- All 3 task commits found in git log: 57f60ba, 40f930a, 1af3dda
- Verification evidence: targeted tests 130/130; canary pins UNCHANGED (iters = 56, welfare = -4823.66604824162, escalations = 0); -t 2 threaded smoke bitwise-equal to serial; zero @sync/threadid() occurrences; guard ArgumentError verified at 1 thread

