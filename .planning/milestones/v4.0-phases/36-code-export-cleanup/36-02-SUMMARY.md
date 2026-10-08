---
phase: 36-code-export-cleanup
plan: 02
subsystem: oracle-and-pricing-api
tags: [dead-code-removal, breaking-change]
requires: [36-01]
provides:
  - operational_oracle(ctx; role, allow_export) without stub kwargs
  - DlmpDecomposition without .loss/.voltage aliases
  - 36-BREAKING-LEDGER.md
key-files:
  modified:
    - src/models/oracle.jl
    - src/pricing/dlmp.jl
    - src/models/stochastic_welfare.jl
    - src/devices/PVBattery.jl
    - src/planning/subproblem.jl
    - src/TSODSO.jl
    - test/test_oracle.jl
    - test/test_planning_oracle.jl
    - test/test_pricing_dlmp.jl
    - scripts/pv_boom_report.jl
    - scripts/pv_boom_report_v2.jl
    - scripts/demo_flexibility_plots.jl
    - scripts/thesis_caseA.jl
    - docs/literate/pricing_dlmp.jl
  created:
    - .planning/phases/36-code-export-cleanup/36-BREAKING-LEDGER.md
requirements-completed: [HYG-02]
duration: ~30 min
completed: 2026-10-05
---

# Phase 36 Plan 02: Oracle stub and DLMP alias removal Summary

Removed the inert `objective_hook`, `horizon_state` and `z` keywords from `operational_oracle` (now `MethodError`, tested), the `z` throw path in `_coupling_dual`, and the deprecated `.loss`/`.voltage` aliases of `DlmpDecomposition`.

## Commits
- 06760b1: oracle stub kwargs and z path removed, tests updated
- e3e5ae2: DlmpDecomposition aliases removed, callers migrated

## Verification
- Filtered oracle/planning/stochastic run: 100 pass, 0 fail. DLMP/pricing run: 562 pass, 1 pre-existing broken.
- Canary/ADMM/strategies/experiments/mpc run: 569 pass; canary iters = 56, welfare = -4823.66604824162.
- Golden-bearing files: numeric literals EQUAL vs 801fb0c.
- Full detached suite deferred to the end of 36-03 (both plans change only dead code and the shim).

## Deviations from Plan
- [Rule 3 - Blocking] `scripts/demo_flexibility_plots.jl` and `scripts/thesis_caseA.jl` also used `decomp.loss`/`decomp.voltage`; migrated to `.cone`/`.drop` (not listed in the plan).
- The `propertynames` assertion at the end of the NamedTuple test item was inverted to assert the aliases are absent.

## Known Stubs
None.

## Self-Check: PASSED
