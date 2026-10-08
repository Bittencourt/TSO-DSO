---
phase: 34-admm-decomposition-meshed-reactive-status-exception-policy
plan: 05
subsystem: status-policy
tags: [status, vocabulary, julia]
requires: ["34-04"]
provides:
  - "TSODSO.STATUS_VOCABULARY and additive trailing `status` on solve_stackelberg!, run_nash!, run_mpc, run_stochastic"
affects: [34-11]
key-files:
  modified: [src/core/errors.jl, src/planning/benders.jl, src/planning/nash.jl, src/experiments/mpc_loop.jl, src/experiments/run_stochastic.jl, test/test_admm_timeout.jl]
  created: [test/test_status_policy.jl]
key-decisions:
  - "DC + reactive aggregators: pinned by test (objective -4819.9377763808125, no :balance_q, :Rq present), no throw/warning added"
requirements-completed: []
duration: ~60min
completed: 2026-10-04
---

# Phase 34 Plan 05: Status vocabulary Summary

`STATUS_VOCABULARY` (not exported, in errors.jl) is the single table; `status` is appended as the last field of the four entry-point results (solve_admm already had it). Helpers `_mpc_status` and `_stochastic_status` derive it from existing ledger fields. Docstrings updated. Commit: see git log (feat(34-05)).

## Verification (foreground)
- canary + test_status_policy.jl: 28 pass, canary unchanged (iters = 56, welfare -4823.66604824162).
- test_admm_timeout.jl plain script: 19 pass (solve_admm vocabulary membership added there for both `:converged` and `:budget_exceeded`).
- benders/nash/mpc_loop/run_stochastic/oos_harness/experiments/tsodso_errors: 730 pass, 1 broken (pre-existing).
- DC pin reproduced to rtol 1e-12 with no re-measure needed.

## Deviations from Plan
Task 2's solve_admm membership checks were put in the existing test_admm_timeout.jl plain script (reusing its fixture) instead of a new @testitem, to avoid duplicating a ~1 min ADMM fixture. The two tasks were committed together in one commit.

## Known Stubs
None.

## Self-Check: PASSED
