---
phase: 32-declarative-power-flow-strategy-dispatch
plan: 02
subsystem: experiments
tags: [julia, scenario, power-flow-selector, legacy-kwargs, arch-01, arch-02]

requires:
  - phase: 32-01
    provides: strategy structs, supports_pf, supported_pfs
provides:
  - Scenario with 11 fields (pf, pf_thesis_literal, pf_ε, strategy::AbstractStrategy)
  - Legacy flat-kwarg outer constructor with _resolve_strategy
  - build_powerflow(s) and with_strategy(s, st)
  - Scenario value ==/hash
affects: [32-03 run dispatch, 32-04 store, 32-05 MPC/Stochastic]

key-files:
  created: [test/test_scenario_pf.jl]
  modified: [src/experiments/Scenario.jl, src/experiments/materialize.jl, test/test_strategies.jl]

key-decisions:
  - "Scenario is a plain struct (no @kwdef) with a hand-written outer kwarg constructor; legacy knobs are detected by supplied keys, never by default comparison"
  - "Foreign pf_* options are judged against neutral defaults in the inner constructor"

requirements-completed: []

duration: 15min
completed: 2026-10-03
---

# Phase 32 Plan 02: Scenario pf selector and strategy field Summary

**Scenario now selects the power-flow formulation via `pf::Symbol` (+ `pf_thesis_literal`, `pf_ε`) and holds a `strategy::AbstractStrategy`, with the legacy flat-kwarg form mapped to strategy structs and `build_powerflow` materializing the four selectors.**

## Accomplishments
- `Scenario.jl` restructured (11 fields); invalid strategy x pf combos, foreign knobs, and unknown selectors throw `ArgumentError` at construction.
- `build_powerflow` (via `_powerflow_from_selector`) added; default is `===` `ConvexBranchFlow()`.
- `with_strategy`, value `==`/`hash` added.
- Tests: `test_scenario_pf.jl` (50 passing), `test_strategies.jl` (104 passing), all solver-free.

## Task Commits
1. Task 1: Scenario restructure (feat)
2. Task 2: build_powerflow + test_scenario_pf.jl (feat)
3. Task 3: test_strategies.jl items (test)

## Deviations from Plan
None. Tests were committed after implementation (no separate RED commits).

## Known Issues (expected, per plan)
`run.jl`, `mpc_loop.jl`, `run_stochastic.jl`, `store.jl` still read removed flat fields; run-time tests (test_experiments, test_mpc_loop, test_run_stochastic) fail until Plans 03-05. Requirements ARCH-01/ARCH-02 not marked complete (phase in progress).

## Known Stubs
None.

## Self-Check: PASSED
