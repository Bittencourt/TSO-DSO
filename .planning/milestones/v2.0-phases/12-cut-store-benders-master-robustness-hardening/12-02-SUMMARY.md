---
phase: 12-cut-store-benders-master-robustness-hardening
plan: 02
subsystem: testing
tags: [julia, jump, benders, stackelberg, highs, testitems, load-test, retry, checkpoint]

# Dependency graph
requires:
  - phase: 12-cut-store-benders-master-robustness-hardening
    plan: 01
    provides: BendersTrace convergence ledger, solve_with_retry!'s attempts_out keyword,
      the genuine per-iteration retry_count_trace/n_cuts_trace/oracle_status_trace fields
provides:
  - A single load-test @testitem proving the Phase-10 retry/checkpoint machinery and the
    Phase-11 persistent Benders cut store hold up at realistic (>=50) iteration counts
  - The empirical solve_with_retry! escalation rate measured on a planning-layer fixture
    (sourced from BendersTrace.retry_count_trace, cross-checked against captured @warn logs)
  - Checkpoint round-trip integrity proof at a mid/high iteration count (k_check=50 of 66)
  - STATE.md's carried Phase-10 "measure, don't assume" blocker closed with real numbers
affects: [13-nash-diagonalization-multi-distributor]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Load-test fixture-shape lever (Claude's Discretion per 12-CONTEXT.md): when a toy
       fixture's cutting-plane gap floors at a hard numerical precision limit regardless of
       tol (verified empirically, not assumed), raise the horizon T instead of tightening
       tol further — a higher-dimensional epigraph genuinely needs more supporting
       hyperplanes, whereas a scalar (T=1) quadratic converges superlinearly to a fixed
       point in ~16 iterations no matter how tight tol is asked to be."
    - "Test.collect_test_logs + BendersTrace.retry_count_trace dual-witness cross-check:
       an aggregate log-scrape count and a genuine per-iteration mechanism count are
       asserted EQUAL for the same run, never treated as redundant or as substitutes for
       one another."

key-files:
  created: []
  modified:
    - test/test_planning_hardening.jl
    - .planning/STATE.md

key-decisions:
  - "T raised from 1 to 8 for the load-test fixture ONLY (test_planning_benders.jl's own
     T=1 fixture is untouched) — every other literal (dev a/b/Pmax, λ₀=4.0, corridor_cap,
     x_inv_max, c_inv, c_op, c_y, y_max, α_x_lb) reused verbatim, just broadcast to length
     T=8, never a new numeric constant, EXCEPT α_op_lb (see next decision)."
  - "α_op_lb loosened from -5.0 to -50.0 at T=8 — a CORRECTNESS requirement, not merely a
     convergence-speed tweak: -5.0 silently clips the epigraph and converges to a WRONG
     answer (y=0.34, cost=-3.36); -50.0 (and looser) all agree on the hand-derivable true
     optimum (y=z=1.4, cost=-7.84 for every period)."
  - "tol left at the project's STANDARD 1e-6 (never tightened) — T=8 alone is sufficient
     to land result.iters at 66, comfortably inside the 50:100 target band."
  - "Item tagged [:planning, :slow] (measured ~33-55s wall-clock for this one item,
     mirroring test_ieee123_admm.jl's [:admm, :phase7] two-tag precedent) since it pushes
     the file's total :planning quick-run noticeably, alongside the three existing
     edge-case items."

patterns-established:
  - "When a plan's own <interfaces> block instructs 'reuse fixture literals verbatim,
     force iteration count via tol alone' and empirical measurement shows that is
     impossible (a hard convergence floor independent of tol), CONTEXT.md's own
     'Claude's Discretion' escape hatch over fixture SHAPE is the correct lever — change
     the minimum necessary structural parameter (here: T), verify the new answer against
     an independently hand-derived closed form, and document the full empirical trail as
     a deviation (mirrors plan 12-01's own precedent for the near-boundary offset)."

requirements-completed: [PLAN-05, PLAN-06]

# Metrics
duration: 65min
completed: 2026-07-23
---

# Phase 12 Plan 02: Cut-Store & Benders Master Robustness Hardening (Load Test) Summary

**Load-test `@testitem` forcing a genuinely-converging 66-iteration Benders run (T=8 toy fixture) with retry/checkpoint machinery fully active; empirical `solve_with_retry!` escalation rate (0% on this fixture) measured from `BendersTrace.retry_count_trace` and cross-checked against captured `@warn` logs, closing the STATE.md "measure, don't assume" blocker.**

## Performance

- **Duration:** ~65 min (including empirical probing to determine a fixture that forces
  >=50 genuinely-converging Benders iterations)
- **Started:** 2026-07-22T22:00:00-03:00 (approx)
- **Completed:** 2026-07-22T23:00:33-03:00
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- New load-test `@testitem` in `test/test_planning_hardening.jl` (tags `[:planning, :slow]`):
  forces `result.iters == 66` on a cheap toy fixture (still `two_bus_feeder()` +
  `LinDistFlow()`, never the full SOCP oracle), with the Phase-10 retry ladder and
  per-iteration checkpointing fully active throughout.
- Empirical retry-rate measurement: `total_retries_from_trace` (from
  `BendersTrace.retry_count_trace`, plan 12-01's `attempts_out` mechanism) asserted equal
  to `n_retry_warnings` (an independently captured `@warn` count via
  `Test.collect_test_logs`) for the SAME run — both `0` on this fixture, a genuine,
  cross-checked measurement, not an assumption.
- Checkpoint round-trip cross-check at scale: a direct `wload` of `iter_00050.jld2` matches
  the in-memory `BendersTrace` row at iteration 50 field-for-field (`LB`, `UB`, `isequal`
  on `gap` to tolerate the `NaN` sentinel); `resume_from_checkpoint` reports iteration 66
  (the final, highest-numbered checkpoint); checkpoint file count (66) matches
  `result.iters` exactly.
- Cut-store growth instrumentation validated at scale: `n_cuts_trace` monotone
  non-decreasing across all 66 iterations, ending at 124 — exactly `length(master.cuts)`.
- STATE.md's carried Phase-10 blocker ("measure, don't assume the v1.0 Clarabel rate
  holds") closed with the actual measured numbers, appended (not overwritten).
- Full `Pkg.test()` suite green: 4095 passed / 0 failed / 0 errored / 4 documented-broken
  (pre-existing thesis-figure cross-checks, unaffected); the full `:planning`-tagged suite
  (196 items, including all of plan 12-01's edge cases and this plan's load test) green.

## Task Commits

1. **Task 1: Load test — >=50-iteration Benders run, empirical retry-rate measurement, checkpoint round-trip at scale** - `2b5a594` (test)
2. **Task 2: Record the empirical retry-rate measurement in STATE.md, closing the carried Phase-10 blocker** - `375af92` (docs)

## Files Created/Modified

- `test/test_planning_hardening.jl` - New load-test `@testitem` (66-iteration T=8 toy fixture, retry/checkpoint at scale, cut-store growth, empirical retry-rate cross-check)
- `.planning/STATE.md` - Phase-12 empirical retry-rate measurement appended to the carried Phase-10 blocker

## Decisions Made

- Raised the load-test fixture's horizon from `T=1` to `T=8` (see key-decisions above and
  the Deviations section below for the full empirical justification).
- Loosened `α_op_lb` from `-5.0` to `-50.0` at `T=8` scale — required for correctness, not
  just convergence speed.
- Left `tol` at the project's standard `1e-6` (no tightening needed).
- Tagged the item `[:planning, :slow]` given its measured ~33-55s runtime.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug in plan's own empirical assumption] The literal T=1 toy fixture cannot produce a >=50-iteration genuinely-converging run at ANY `tol`**
- **Found during:** Task 1, while empirically probing `tol` values per the plan's own
  instruction ("empirically RUN the test and adjust tol tighter/looser until
  `result.iters` lands at >= 50... the run still CONVERGES, never exhausts").
- **Issue:** On `test_planning_benders.jl`'s literal `T=1` fixture (reused verbatim, per
  the plan's `<interfaces>` block), the Benders gap trajectory hits a bit-exact numerical
  floor of `~4.8995e-8` after exactly 16 iterations and NEVER moves again — verified out to
  300 iterations. Every `tol` above that floor converges in exactly 16 iterations; every
  `tol` below it exhausts the 200-iteration cap with the IDENTICAL stuck gap (also verified
  out to 300 iterations with a hand-rolled copy of the loop). This is a genuine, provable
  property of a scalar (`T=1`) quadratic welfare curve under Kelley cutting-plane Benders
  (superlinear convergence to a machine-precision-limited fixed point) — there is
  structurally no `tol` value satisfying both `result.iters >= 50` and "converges, never
  exhausts" on this exact fixture.
- **Fix:** Per 12-CONTEXT.md's own explicit "Claude's Discretion" over "Load-test fixture
  parameterization (how to force slow convergence: tolerance, fixture shape)", raised the
  horizon to `T=8` — a genuinely higher-dimensional cutting-plane problem needs more
  supporting hyperplanes to pin down all 8 dimensions of the epigraph, empirically measured
  to land `result.iters` at 66. Every other literal reused verbatim (broadcast to length 8,
  never a new numeric constant) except `α_op_lb`, which required loosening from `-5.0` to
  `-50.0` for CORRECTNESS at this scale — `-5.0` silently clips the epigraph, converging to
  a wrong answer (`y=0.34`, cost=`-3.36`); `-50.0` (confirmed stable against `-100.0` and
  `-200.0`, all three agreeing) converges to the true optimum, independently verified by
  hand-deriving the T=8 closed form (`total(z) = 4.0z² - 11.2z`, `z* = 11.2/8 = 1.4`,
  `total(1.4) = -7.84`) — matching the production Benders loop's converged `y=z=1.4`,
  `UB=-7.84` exactly.
- **Files modified:** `test/test_planning_hardening.jl` (the deviation and its full
  empirical trail are documented in-file, immediately above the `@testitem`).
- **Verification:** The load-test item passes (`result.iters=66`, `result.gap <= 1e-6`,
  cut-store growth monotone and matching `master.cuts`, checkpoint round-trip exact,
  retry-rate cross-check exact). Full `:planning`-tagged suite (196 items) green. Full
  `Pkg.test()` suite green (4095 passed / 0 failed / 0 errored / 4 documented-broken).
- **Committed in:** `2b5a594` (Task 1 commit — the fixture was corrected before the file
  was ever committed, so no separate fix commit was needed).

---

**Total deviations:** 1 auto-fixed (a bug in the plan's own empirical assumption about the
T=1 fixture's convergence behavior — corrected via CONTEXT.md's own explicitly-granted
fixture-shape discretion, not a departure from any locked decision).
**Impact on plan:** No scope creep. The plan's own escape-hatch language ("empirically RUN
the test and adjust... until result.iters lands at >= 50... do not switch to the IEEE-13
SOCP oracle or any larger fixture to force iteration count") is honored in spirit and
letter: the fixture remains the cheap toy `two_bus_feeder()` + `LinDistFlow()` oracle
throughout; only the horizon `T` (and the one epigraph bound that scale requires for
correctness) changed, and the change is exhaustively documented with an independent
hand-derivation proving the new fixture converges to its TRUE optimum, not an artifact.

## Issues Encountered

None beyond the deviation documented above — resolved during Task 1 execution, before any
commit was made, via direct empirical probing (a standalone Julia script reproducing the
fixture and hand-rolling the Benders loop to inspect the gap trajectory iteration-by-
iteration) rather than guessing at `tol` values inside the test suite itself.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The Phase-10 retry/checkpoint machinery and the Phase-11 persistent Benders cut store are
  now proven at realistic (>=50) iteration counts — Phase 13's Gauss-Seidel diagonalization
  loop nests a SECOND outer loop on top of mechanics whose scale behavior is measured, not
  assumed.
- The empirical retry rate on THIS toy fixture is 0% — a genuine, honest measurement, but
  it does NOT directly bound the IEEE-13 ADMM oracle's own documented cone-slack
  `NUMERICAL_ERROR` rate (the specific concern the Phase-10 blocker names), since
  CONTEXT.md explicitly prohibits exercising that oracle in this load test. STATE.md's
  updated blocker bullet flags this scope boundary explicitly — re-measure if/when a
  feeder-scale planning fixture is introduced.
- Phase 12 owns no new requirement IDs (deepens PLAN-05/PLAN-06 from Phase 11, as scoped in
  12-CONTEXT.md); both plans (12-01, 12-02) are now complete.

---
*Phase: 12-cut-store-benders-master-robustness-hardening*
*Completed: 2026-07-23*

## Self-Check: PASSED

All claimed modified files verified present on disk with the expected content; both task
commit hashes (`2b5a594`, `375af92`) verified present in git history.
