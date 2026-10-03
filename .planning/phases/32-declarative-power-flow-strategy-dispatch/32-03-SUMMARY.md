---
phase: 32-declarative-power-flow-strategy-dispatch
plan: 03
subsystem: experiments
tags: [julia, run-dispatch, scenario-result, power-flow-selector, arch-01, arch-02]

requires:
  - phase: 32-02
    provides: Scenario pf/strategy fields, build_powerflow, with_strategy
provides:
  - ScenarioResult(scenario, welfare, dadp, exact_maxgap, elapsed, details) with getproperty forwarding
  - TSODSO.run(::Centralized, s), run(::ADMM, s), run(s); run_scenario thin wrapper
  - pf selector honoured end-to-end for Centralized (convex, restricted, lindistflow, ac)
affects: [32-04 store, 32-05 MPC/Stochastic]

key-files:
  modified: [src/experiments/run.jl, test/test_scenario_pf.jl, test/test_strategies.jl]

key-decisions:
  - "exact_maxgap uses an explicit isa Union{ConvexBranchFlow,RestrictedBranchFlow} guard; NaN for LinDistFlow/AC"
  - "allow_local = pf isa ACPowerFlow only for AC"
  - "Shared _materialize helper keeps the seed/sub_seed sequence unchanged"
  - "Explicit-strategy test uses ADMM(maxiter = 300): maxiter = 5 correctly refuses to converge"

requirements-completed: []

duration: 25min
completed: 2026-10-03
---

# Phase 32 Plan 03: run dispatch and pf wiring Summary

**`run_scenario` now dispatches by strategy type via `TSODSO.run`, takes the power flow from `build_powerflow(s)`, and returns a reshaped `ScenarioResult` with typed `details` and `missing`-forwarding ADMM properties.**

## Accomplishments
- Reshaped `ScenarioResult`; `iters/final_r/final_s/reactive_consensus_mode` are forwarded properties (`missing` for non-ADMM).
- `run(::Centralized)` and `run(::ADMM)` implemented; `run(s)` and `run_scenario(s)` wrap them.
- Tests: `test_scenario_pf.jl` 76 passing, `test_strategies.jl` 122 passing (incl. default-pf equality with a direct `solve_welfare` call, LinDistFlow/AC NaN maxgap).

## Task Commits
1. run.jl rewrite: d01407e
2. Run-time tests: c0635ce

## Deviations from Plan
**[Rule 1 - Test bug]** The plan's `ADMM(maxiter = 5)` explicit-strategy example makes `solve_admm` refuse (non-convergence). Used `ADMM(maxiter = 300)`, which still tests that the explicit strategy wins. Both test items cover this in the same commit.

## Known Issues (expected)
`store.jl`, `mpc_loop.jl`, `run_stochastic.jl` still read removed fields / lack `run` methods until Plans 04/05. Requirements not marked complete.

## Known Stubs
None.

## Self-Check: PASSED
