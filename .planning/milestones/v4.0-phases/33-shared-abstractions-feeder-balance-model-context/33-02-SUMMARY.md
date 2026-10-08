---
phase: 33-shared-abstractions-feeder-balance-model-context
plan: 02
subsystem: models / admm / planning / pricing
tags: [AbstractFeeder, dispatch, ARCH-03]
requires: [33-01]
provides:
  - shared entry points typed feeder::AbstractFeeder
  - solve_admm / build_dso_opt typed ::Feeder with named ArgumentError on MeshedFeeder
  - struct feeder parameters constrained F <: AbstractFeeder
affects: [33-03, 33-04]
key-files:
  modified:
    - src/models/{welfare_solve,linear_solve,mpc_window,stochastic_welfare,oracle,toy_dc}.jl
    - src/admm/{solve_admm,DsoOpt}.jl
    - src/planning/{subproblem,feasibility_oracle,master,bilevel_kkt}.jl
    - src/pricing/fit.jl
    - test/test_abstract_feeder.jl
decisions:
  - Signature-only edits, no body changes; goldens untouched
metrics:
  tasks: 3
  files: 14
completed: 2026-10-03
---

# Phase 33 Plan 02: Typed feeder entry points Summary

Shared model, planning and pricing entry points now take `feeder::AbstractFeeder`. ADMM paths are `::Feeder`, and a `MeshedFeeder` handed to `solve_admm` or `build_dso_opt` throws an `ArgumentError` naming the function and "MeshedFeeder".

## Tasks

1. `e43a909` - typed `solve_welfare`, `solve_linear`, `build_mpc_window`, `build_stochastic_welfare`, `build_stochastic_oos_harness`, `operational_oracle`. `solve_toy_dc` is loosened to `AbstractFeeder`. `MpcWindow` and `StochasticOosHarness` are constrained `F <: AbstractFeeder`.
2. `8cdd721` - typed `build_planning_oracle`, `build_feasibility_oracle`, `make_relaxed_oracle_model`, `alpha_op_lb_derivation`, `derive_alpha_op_lb`, `build_bilevel_kkt` and `fit_baseline`. `PlanningOracle` and `FeasibilityOracle` are constrained `F <: AbstractFeeder`.
3. `b7f9020` - `solve_admm` and `build_dso_opt` are `::Feeder`, with `::MeshedFeeder` throwing methods. `DsoOpt` is constrained `F <: AbstractFeeder`. A new testitem in `test/test_abstract_feeder.jl` asserts the errors.

The ADMM `::Feeder` typing sits in the task 3 commit, not task 2, because those files also carry the throwing methods.

## Verification

Twelve TestItemRunner files ran: `test_abstract_feeder`, `test_toy_dc`, `test_dso`, `test_welfare_solve`, `test_linear_solve`, `test_mpc_window`, `test_admm`, `test_admm_knifeedge_canary`, `test_planning_oracle`, `test_pricing_fit`, `test_stochastic_welfare`, `test_stochastic_oos_harness`. Two runs gave 265 and 192 passes with 0 failures. The knife-edge canary still reports iters = 56. I did not run the full suite.

## Deviations from Plan

None - plan executed as written. No non-feeder callers were found, so no type was widened to `Any`.

## Known Stubs

None.

## Self-Check: PASSED
