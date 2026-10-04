---
phase: 35-ieee-8500-scale-after-refactor
plan: 01
subsystem: admm-exactness
tags: [admm, exactness, hybrid-floor, diagnostics]
requires: []
provides:
  - "solve_admm/solve_dso! atol_exact default nothing (hybrid floor)"
  - "hybrid_ratios(ctx) diagnostic"
  - "scripts/run_tests_filtered.jl runner"
affects: [src/admm/solve_admm.jl, src/admm/DsoOpt.jl, src/models/exactness.jl]
key-files:
  created: [scripts/run_tests_filtered.jl, test/test_admm_exactness_default.jl]
  modified: [src/admm/solve_admm.jl, src/admm/DsoOpt.jl, src/models/exactness.jl]
decisions:
  - "ADMM consolidation gate uses the hybrid floor by default; explicit Real stays a flat bypass; gate logic/tau/epsilon untouched"
metrics:
  completed: 2026-10-04
---

# Phase 35 Plan 01: ADMM hybrid-floor exactness default Summary

`solve_admm` and `solve_dso!` now default `atol_exact` to `nothing`, so the ADMM consolidation gate uses the same hybrid floor as the centralized path. A new `hybrid_ratios(ctx)` diagnostic reports per-branch ratios, and the knife-edge canary and ADMM suite did not move.

## Commits
- af9cb8e: signatures, docstrings, `scripts/run_tests_filtered.jl`
- c7a324a: `hybrid_ratios` and `test/test_admm_exactness_default.jl`

## Verification
- New test file: 17 assertions pass (tests A, B, N, hybrid_ratios).
- `tag:exact`: 37 pass.
- Canary file: 2 pass, iters = 56, welfare = -4823.66604824162 (unchanged, not re-pinned).
- `tag:admm`: 270 pass, 0 failures. The plan estimated 953+ assertions; the tag selects 270 here, and all of them pass.
- `assert_socp_exact!` is unchanged; the `exactness.jl` diff is additive only.

## Deviations from Plan
Test fixture bus voltage bounds changed from 0.5/1.5 to 0.95/1.1 because Feeder rejects bounds outside the 0.8-1.2 per-unit band. This is a test-only change. Tasks 1 and 2 share a test file, so their commits split by source file rather than strictly by task.

## Known Stubs
None.

## Self-Check: PASSED
