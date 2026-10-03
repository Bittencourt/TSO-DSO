---
phase: 32-declarative-power-flow-strategy-dispatch
plan: 06
subsystem: docs
tags: [julia, docs, literate, readme, arch-01, arch-02]

requires:
  - phase: 32-04
    provides: persistence layer for strategy Scenario
  - phase: 32-05
    provides: MPC/Stochastic run dispatch
provides:
  - Literate docs, scripts and README migrated to the declarative strategy/pf form
  - Documented pf selector table and the single TSODSO.run entry point
  - run_and_store end-to-end test for MPC and Stochastic
key-files:
  modified:
    - docs/literate/experiments.jl
    - docs/literate/mpc_rolling_horizon.jl
    - docs/literate/stochastic_pv_demand.jl
    - scripts/demo_mpc_plots.jl
    - scripts/compare_default_stochastic.jl
    - README.md
    - test/test_strategies.jl
key-decisions:
  - "Docs show the declarative form as primary; legacy flat kwargs mentioned once as compatibility"
requirements-completed: []
duration: 25min
completed: 2026-10-03
---

# Phase 32 Plan 06: Docs, scripts and README migration Summary

**All in-repo callers now use `strategy = ADMM()/MPC(...)/Stochastic(...)`, `pf = ...` and `TSODSO.run`; the experiments page documents the pf x strategy support matrix and demonstrates the construction-time rejection.**

## Task Commits
1. Literate docs: f85dab7
2. Scripts and README: 4ab8626
3. run_and_store tests (MPC/Stochastic, four filenames): 3a216ef

## Verification
- All three literate files exit 0 under `JULIA_LOAD_PATH="docs:.:@stdlib"`.
- Scripts parse; grep gates for removed fields (`mpc_H =`, `s.stoch_*`, ...) clean.
- test_strategies.jl: 398/398 pass (foreground).
- Rejected `ADMM() + pf = :lindistflow` verified to throw `ArgumentError` at construction.

## Deviations from Plan
None - plan executed as written.

## Known Stubs
None.

## Self-Check: PASSED
