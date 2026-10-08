---
phase: 34-admm-decomposition-meshed-reactive-status-exception-policy
plan: 06
subsystem: status-policy
tags: [exceptions, julia, mpc, stochastic]
requires: ["34-05"]
provides:
  - "mpc_loop tier catches admit only SolveFailedError/CertificateError; run_stochastic skip-and-report catches SolveFailedError only; assert_ac_exact! T mismatch is ArgumentError"
affects: [34-11]
key-files:
  modified: [src/experiments/mpc_loop.jl, src/experiments/run_stochastic.jl, src/models/ac_oracle.jl, test/test_mpc_loop.jl, test/test_run_stochastic.jl, test/test_ac_oracle.jl]
key-decisions:
  - "ConvergenceError deliberately not admitted in mpc tiers (neither is iterative)"
requirements-completed: []
duration: ~30min
completed: 2026-10-04
---

# Phase 34 Plan 06: Narrow mpc_loop / run_stochastic handlers Summary

Both `_mpc_certify_and_price` catches now rethrow anything but `SolveFailedError`/`CertificateError` (InterruptException still explicit); `_stoch_solve_held_out!` catches `SolveFailedError` only (infeasibility-status check unchanged); `assert_ac_exact!` T mismatch throws `ArgumentError`; docstrings updated. Single atomic commit e136755 (source + tests).

## Tests
- test_mpc_loop.jl: `boom` seam now throws `SolveFailedError`; new assertions that `MethodError`/`BoundsError`/`ArgumentError`/`KeyError` propagate from both tier-2 and tier-3 seams, `InterruptException` propagates, and `SolveFailedError`/`CertificateError` still yield `:cert_failed` / `:local_ac_dual`.
- test_run_stochastic.jl: `_stoch_solve_held_out!(nothing, 3)` propagates `MethodError`; infeasible case still `(NaN, true)`.
- test_ac_oracle.jl: T mismatch `@test_throws ArgumentError`.

## Verification (foreground)
Batch 1 (canary, mpc_loop, ac_oracle, run_stochastic): 410 pass. Batch 2 (oos_harness, stochastic_welfare, status_policy, experiments, ac_recheck, mpc_window, acceptance, ieee13): 264 pass, 2 broken (pre-existing). Batch 3 (mpc_terminal, strategies, restricted_branch_flow, fit): 482 pass. Canary unchanged (never re-pinned). Caller closure covered: test_mpc_terminal, test_fit, test_strategies, test_status_policy, test_ac_oracle, test_restricted_branch_flow, test_mpc_loop, test_run_stochastic (fixtures_phase21 is not a test file).

No previously swallowed error surfaced; no source wrapping needed.

## Remaining catch inventory (not narrowed, CONTEXT deferred)
Files with `catch` outside mpc_loop.jl: admm/DsoOpt.jl (3), core/errors.jl, core/status.jl, experiments/run_stochastic.jl (the narrowed one), models/welfare_solve.jl, planning/ac_recheck.jl, planning/benders.jl (6), planning/bilevel_kkt.jl, planning/coupling.jl, planning/master.jl, planning/nash.jl, planning/retry.jl (2), planning/subproblem.jl, pricing/checks.jl, pricing/fit.jl, pricing/welfare.jl. Several use `_is_solver_failure` (legacy ErrorException or TSODSOError union).

## Deviations from Plan
None.

## Known Stubs
None.

## Self-Check: PASSED
