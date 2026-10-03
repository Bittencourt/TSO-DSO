---
phase: 32-declarative-power-flow-strategy-dispatch
plan: 01
subsystem: experiments
tags: [julia, strategy-types, dispatch, validation, arch-02]

requires:
  - phase: 08-experiment-harness
    provides: Scenario validation text moved into strategy constructors
provides:
  - AbstractStrategy with Centralized/ADMM/MPC/Stochastic self-validating structs
  - Unexported generic TSODSO.run
  - supports_pf / supported_pfs strategy x power-flow matrix
  - ADMMDetails / MPCDetails / StochasticDetails result structs
affects: [32-02 Scenario restructure, 32-03 run dispatch, store, MPC, Stochastic]

tech-stack:
  added: []
  patterns: ["struct with validating positional inner ctor + hand-written kwarg ctor (no @kwdef)", "trait-based valid-combination matrix"]

key-files:
  created: [src/experiments/strategies.jl, test/test_strategies.jl]
  modified: [src/TSODSO.jl, docs/src/api.md]

key-decisions:
  - "run is not exported and Base.run is not imported; always called as TSODSO.run"
  - "step > H and H > T remain run-time guards in run_mpc, not constructor checks"

patterns-established:
  - "supports_pf is the single place to relax the strategy x pf matrix (ADMM in Phase 34)"

requirements-completed: [ARCH-02]

duration: 10min
completed: 2026-10-03
---

# Phase 32 Plan 01: Strategy Type Layer Summary

**Four self-validating strategy structs (Centralized, ADMM, MPC, Stochastic) with an unexported `TSODSO.run` generic, a `supports_pf` matrix trait, and typed details structs, with Scenario untouched.**

## Accomplishments
- `src/experiments/strategies.jl` created with moved validation (messages prefixed ADMM:/MPC:/Stochastic:), defaults identical to the old flat fields, Stochastic uniform sentinel plus defensive copy, and value `==`/`hash`.
- Included before `Scenario.jl` in `src/TSODSO.jl`; added to the Experiment Harness page list in `docs/src/api.md`.
- `test/test_strategies.jl`: 6 solver-free testitems, 77 assertions passing.

## Task Commits
1. Task 1: b02a264 (feat)
2. Task 2: 3d22302 (test)

## Deviations from Plan
None. Plan executed as written. Tests were committed after the implementation rather than as a separate RED commit.

## Known Stubs
None.

## Self-Check: PASSED
