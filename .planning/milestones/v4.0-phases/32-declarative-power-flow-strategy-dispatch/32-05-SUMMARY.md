---
phase: 32-declarative-power-flow-strategy-dispatch
plan: 05
subsystem: experiments
tags: [julia, mpc, stochastic, run-dispatch, arch-01, arch-02]

requires:
  - phase: 32-03
    provides: run dispatch, ScenarioResult, MPCDetails/StochasticDetails
provides:
  - TSODSO.run(::MPC, s) and run(::Stochastic, s) returning the common ScenarioResult shape
  - _run_mpc/_run_stochastic internal bodies reading strategy knobs and build_powerflow(s)
  - run_mpc/run_stochastic thin wrappers with NamedTuple contracts unchanged
affects: [phase-32 verification]

key-files:
  modified:
    - src/experiments/mpc_loop.jl
    - src/experiments/run_stochastic.jl
    - test/test_mpc_loop.jl
    - test/test_run_stochastic.jl
    - test/test_strategies.jl

key-decisions:
  - "Mechanical substitution only (s.mpc_*/s.stoch_* -> st.*; ConvexBranchFlow() -> build_powerflow(s)); seeds and returned NamedTuples untouched"
  - "run(::MPC): welfare = realized_welfare, dadp = 1 x n row, exact_maxgap = NaN"
  - "run(::Stochastic): welfare = in_sample.welfare, dadp = expected_dadp row, exact_maxgap = max socp_maxgap (NaN if empty)"

requirements-completed: [ARCH-01, ARCH-02]

completed: 2026-10-03
---

# Phase 32 Plan 05: MPC and Stochastic dispatch Summary

**MPC and Stochastic now read their knobs from `Scenario.strategy` and the formulation from `build_powerflow(s)`, and are reachable through `TSODSO.run` returning a common `ScenarioResult`; numeric goldens are untouched.**

## Task Commits
1. mpc_loop.jl: 3c823c8
2. run_stochastic.jl: 675610f
3. Test migration and new ARCH-02 items: committed with this summary

## Verification
- test_strategies.jl 160/160, test_mpc_loop.jl 356/356, test_run_stochastic.jl 14/14 (foreground, stacked load path).
- Numeric assertions unchanged; only Scenario constructions migrated.
- No `s.mpc_*`/`s.stoch_*` and no executable `ConvexBranchFlow()` remain in the two source files.

## Deviations from Plan
None - plan executed as written.

## Known Stubs
None.

## Self-Check: PASSED
