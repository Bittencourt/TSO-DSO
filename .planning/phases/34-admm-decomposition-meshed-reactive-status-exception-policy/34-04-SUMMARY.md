---
phase: 34-admm-decomposition-meshed-reactive-status-exception-policy
plan: 04
subsystem: admm-planning
tags: [exceptions, julia, convergence]
requires: ["34-03"]
provides:
  - "solve_admm maxiter, solve_stackelberg! exhaustion + :reject stalled, run_nash! exhaustion + integer CYCLED throw ConvergenceError"
affects: [34-11]
key-files:
  modified: [src/admm/solve_admm.jl, src/planning/benders.jl, src/planning/nash.jl, test/test_tsodso_errors.jl, test/test_admm.jl, test/test_planning_benders.jl, test/test_planning_nash.jl, test/test_planning_inexact_policy.jl, test/test_planning_benders_integer.jl, test/test_planning_certification_integer.jl, test/test_planning_benders_ieee13.jl]
key-decisions:
  - "Only the exception type changed (with iterations = maxiter / max_iter / k / max_sweeps); message text byte-identical; :budget_exceeded early return untouched"
requirements-completed: []
duration: ~75min
completed: 2026-10-04
---

# Phase 34 Plan 04: Convergence family typed throws Summary

The five iterative non-convergence throws now raise `ConvergenceError` with byte-identical messages and an `iterations` field. Docstrings in solve_admm.jl, benders.jl and nash.jl updated. Single atomic commit 3de8457 (source + tests).

## Tests migrated
- test_planning_benders.jl:224,253; test_planning_nash.jl:519,871,873; test_planning_inexact_policy.jl:198; test_planning_benders_integer.jl:104,132; test_planning_certification_integer.jl:561; test_admm.jl:222 (`@test_throws Exception` tightened to `ConvergenceError`); comment in test_planning_benders_ieee13.jl:109.
- New in test_tsodso_errors.jl: solve_admm maxiter=1 -> `ConvergenceError`, `iterations == 1`, msg prefix.

## Remaining `ErrorException` inventory in test (all NOT-converted or comments)
- (a) other sources: test_fit.jl (fit AC-PF), test_planning_alpha_bounds_stackelberg.jl (`_assert_epigraph_floor`), test_planning_benders_integer.jl:178-235 (`_oracle_or_infeasible`), test_planning_master_integer.jl (`add_ll_cut!`), test_planning_bilevel.jl:203 (rho_y guard), test_mpc_loop.jl (`_mpc_assert_true_state_inband`), test_close_balance.jl, test_context.jl, test_feeder.jl, test_pricing_welfare.jl, test_planning_ac_recheck.jl:93, test_planning_certification_integer.jl:176 (enumerate_lattice WR-01 guard, constructed in-test).
- (b) comments/hierarchy checks: test_tsodso_errors.jl, test_stochastic_welfare.jl, test_planning_retry.jl:195, test_planning_nash_integer.jl:42, test_planning_ac_recheck.jl:87, test_planning_master_integer.jl:277, test_planning_bilevel.jl:110.

## Verification (foreground)
Batches: canary/errors/admm*/abstract_feeder/ieee123/acceptance 206 pass, 1 broken (pre-existing); benders/nash/inexact/benders_integer 297 pass, 1 broken; nash_integer/certification*/ieee13/noninteger 114 pass; ac_recheck/alpha_bounds/feasibility_oracle/goldens/hardening/trace/experiments 254 pass; test_admm_timeout.jl plain script 17 pass. Canary unchanged (iters = 56, welfare -4823.66604824162). Caller-closure files all covered (fixtures_* are not test files).

## Deviations from Plan
None.

## Known Stubs
None.

## Self-Check: PASSED
