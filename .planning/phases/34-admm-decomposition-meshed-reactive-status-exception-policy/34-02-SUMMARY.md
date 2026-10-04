---
phase: 34-admm-decomposition-meshed-reactive-status-exception-policy
plan: 02
subsystem: core
tags: [exceptions, julia, status, retry-ladder]
requires: ["34-01"]
provides:
  - "assert_solved!, solve_with_retry! (2 sites), run_nash! final re-solve throw SolveFailedError"
  - "assert_no_slack throws CertificateError(kind = :no_slack)"
affects: [34-03, 34-04, 34-06]
key-files:
  modified: [src/core/status.jl, src/planning/retry.jl, src/planning/nash.jl, test/test_tsodso_errors.jl, test/test_planning_retry.jl, test/test_stochastic_welfare.jl]
key-decisions:
  - "Message text byte-identical (heredoc kept in place, only the wrapper changed)"
requirements-completed: []
duration: ~50min
completed: 2026-10-04
---

# Phase 34 Plan 02: SolveFailed family typed throws Summary

Solver-failure throw sites now raise typed `SolveFailedError` (and `CertificateError` for the no-slack guard) with byte-identical message text; the retry ladder still escalates on them via `_is_solver_failure`.

## Tasks (single atomic commit, source + test migration)
- Commit with both tasks (see git log, `refactor(34-02)`).
- Converted: status.jl (assert_solved!, assert_no_slack + docstrings), retry.jl (attribute rejection, exhausted ladder, header comment), nash.jl final consistency re-solve.
- Tests: test_tsodso_errors.jl gained a byte-identical-text item (expected literal built from the old layout) and a `CertificateError` item; test_planning_retry.jl `ErrorException` -> `SolveFailedError` (4 asserts + `@test_throws` at the INFEASIBLE item) and a new retry-on-typed-error item (escalation + non-solver TypeError rethrown); test_stochastic_welfare.jl:160 `e isa ErrorException` -> `TSODSO._is_solver_failure(e)`.

## Test lines left as ErrorException (thrower not converted)
test_planning_nash.jl:519/873/1152 (run_nash! exhaustion and SOCP INEXACT gate stay ErrorException until later plans), test_planning_benders_integer.jl (injected fakes / `_oracle_or_infeasible`), test_fit, test_close_balance, test_mpc_loop, test_planning_bilevel, test_planning_inexact_policy, etc. Passing runs confirmed no further migration was needed. test_status.jl had no ErrorException matches.

## Verification
Four foreground batches, all 0 failures: errors/retry/status/stochastic_welfare (89), operational + canary (635 pass, 1 broken pre-existing), planning nash/benders/bilevel/mpc/fit (720, 1 broken), planning certification/oracle/master/goldens/ieee123 (342). Canary unchanged (iters = 56, welfare -4823.66604824162). Closure of `grep -rlE "solve_with_retry!|assert_solved!|assert_no_slack|run_nash!" test` covered by the batches (fixtures files excluded; test_planning_benders_integer/run_stochastic/oos in batch 3).

## Deviations from Plan
None of substance. Test writing adjustments: assert_no_slack test uses `atol = -1.0` to force the trip; retry-on-typed-error test reuses the ill-conditioned fixture and uses `dual = nothing` to provoke a non-solver TypeError.

## Known Stubs
None.

## Self-Check: PASSED
