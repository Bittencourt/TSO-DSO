---
phase: 33-shared-abstractions-feeder-balance-model-context
plan: 05
subsystem: models
tags: [ARCH-04, close_balance, refactor]
requires: [33-01, 33-02, 33-03, 33-04]
provides:
  - five balance-closing copies replaced by one close_balance! call each
affects: [33-06]
key-files:
  modified: [src/models/welfare_solve.jl, src/models/linear_solve.jl, src/models/mpc_window.jl, src/models/stochastic_welfare.jl, src/admm/DsoOpt.jl]
decisions:
  - reactive decided by has_reactive(pf) at every migrated site; DsoOpt passes true
metrics:
  tasks: 3
  files: 5
completed: 2026-10-03
---

# Phase 33 Plan 05: Migrate ARCH-04 sites to close_balance! Summary

`welfare_solve`, `linear_solve`, `mpc_window`, both `stochastic_welfare` sites (extensive builder with `label = "scenario $s "`, and the OOS harness) and `DsoOpt` now close balances through `close_balance!`. No `size(ctx.residuals[:Rp])` remains in those five files.

## Commits

1. `707780e` - welfare_solve, linear_solve (`balance_p, balance_q = close_balance!(...)`, DADP dual unchanged; WR-03 comment kept in linear_solve).
2. `fb3868d` - mpc_window, stochastic_welfare (both sites).
3. `471d38d` - DsoOpt (`reactive = true`; transit-node zero injections stay before the call).

## Verification (foreground TestItemRunner, full suite not run)

- test_close_balance (fingerprints), test_welfare_solve, test_linear_solve: 178 pass.
- test_close_balance, test_mpc_window, test_stochastic_welfare, test_stochastic_oos_harness: 89 pass.
- test_dso, test_admm, test_admm_knifeedge_canary (iters == 56), test_close_balance: pass. test_admm_reactive: 22 pass, 2 fail (see below).

Fingerprints were not touched. Remaining `an index escaped the feeder` copies are `core/balance.jl` plus the deferred `planning/{feasibility_oracle,master,bilevel_kkt,subproblem}.jl`. (Pricing/mpc_loop copies use different text.)

## Deviations from Plan

None in the migration itself.

## Deferred Issues

`test_admm_reactive.jl` lines 113 and 174 (`@test has_kwarg`) fail. The probe is `hasmethod(build_dso_opt, Tuple{Any, typeof(aggs), Int}, (:reactive_consensus,))`. Since Plan 33-02, `build_dso_opt` takes `feeder::Feeder` as first argument, so the `Any` probe no longer matches. This is unrelated to the DsoOpt balance edit (signature unchanged). The probe was not confirmed against a pre-edit baseline. Fix by probing with `typeof(feeder)` in a later plan (the test is outside this plan's files).

## Known Stubs

None.

## Self-Check: PASSED
