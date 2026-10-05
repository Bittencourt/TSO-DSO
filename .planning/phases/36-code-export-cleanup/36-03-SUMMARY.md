---
phase: 36-code-export-cleanup
plan: 03
subsystem: admm-reactive-mode
tags: [breaking-change, namespacing]
requires: [36-02]
provides:
  - ReactiveMode module (ReactiveMode.T, OFF/CERTIFIED/LIVE), enum-only normalize_reactive_mode
key-files:
  modified:
    - src/admm/ReactiveMode.jl
    - src/admm/admm_state.jl
    - src/admm/admm_phases.jl
    - src/admm/DsoOpt.jl
    - src/admm/AgrOpt.jl
    - src/admm/solve_admm.jl
    - src/experiments/strategies.jl
    - test/test_reactive_mode.jl
    - test/test_admm_phases.jl
    - test/test_strategies.jl
    - test/test_experiments.jl
    - test/test_admm_reactive.jl
    - test/test_dso.jl
    - test/test_ieee123_admm.jl
    - test/test_admm_meshed.jl
    - test/fixtures_phase6.jl
    - test/fixtures_phase19.jl
    - scripts/reactive_flake_rate.jl
    - docs/literate/meshed_reactive_price.jl
    - .planning/phases/36-code-export-cleanup/36-BREAKING-LEDGER.md
requirements-completed: [HYG-02, HYG-03]
completed: 2026-10-05
---

# Phase 36 Plan 03: ReactiveMode module and enum-only API Summary

`ReactiveMode` is now a module holding `@enum T OFF CERTIFIED LIVE`; `normalize_reactive_mode` accepts only `ReactiveMode.T` and raises `ArgumentError` (naming OFF, CERTIFIED, LIVE) for Bool, Symbol and anything else. Only `ReactiveMode` is exported.

## Commits
- 394eb03: src consumers, tests, script, literate page and ledger migrated in one commit (tasks 1 and 2 touch the same call sites and the tree is only consistent when both land together).

## Verification
- Targeted set (reactive_mode, admm_phases, strategies, experiments, dso, admm_meshed, canary): green after fixing `TSODSO.OFF` style qualified uses in test_admm_phases (67 pass on re-run of the two files).
- Full detached suite p03: 32201 pass / 0 fail / 0 error / 5 broken (suite OK via check_suite_log.py). Canary line present (iters = 56, welfare = -4823.66604824162). Aqua direct script all checks pass.
- Pass delta vs 32177: +24. test_reactive_mode.jl went from 10 assertions (Bool 2, Symbol 3, identity 3, invalid 2) to 21 (identity 4, 8 throws, 3 message, 4 export checks plus type checks, so +11); the remaining +13 comes from plan 02 (added MethodError and alias-absence assertions net of removed ones). No test was deleted outright. Broken stays 5; the single broken in the DLMP/pricing set is pre-existing (it is part of the 5 baseline).
- Structural bare-word audit in test_admm_phases (solve_admm.jl, admm_phases.jl) passes.

## Deviations from Plan
- Tasks 1 and 2 committed together (single commit) because the intermediate state would not compile against the tests.
- Task 3's separate heavy-file run was folded into the full suite, which includes test_admm_reactive.jl and test_ieee123_admm.jl.
- The `scripts` and tests also used `TSODSO.OFF`-style qualified names, migrated to `TSODSO.ReactiveMode.X`.

## Known Stubs
None.

## Self-Check: PASSED
