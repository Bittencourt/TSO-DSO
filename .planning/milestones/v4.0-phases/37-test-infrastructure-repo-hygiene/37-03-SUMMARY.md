---
phase: 37-test-infrastructure-repo-hygiene
plan: 03
subsystem: test-infrastructure
tags: [flake, retry, harness, archive]
requires: [37-02]
provides:
  - FlakeRetry @testmodule (with_solve_retry + atexit RETRY SUMMARY)
  - scripts/flake_rate.jl fresh-process flake harness
  - scripts/archive/ convention skipped by check_script_api.jl
affects: [later phase-37 plans that run the harness / apply the helper]
key-files:
  created:
    - test/fixtures_retry.jl
    - test/test_flake_retry.jl
    - scripts/flake_rate.jl
  modified:
    - .github/scripts/check_script_api.jl
    - scripts/repro_stability_check.jl
    - scripts/archive/reactive_flake_rate.jl (moved from scripts/)
requirements-completed: []
completed: 2026-10-06
---

# Phase 37 Plan 03: Flake tooling Summary

Retry-and-report helper, fresh-process flake harness, and archival of the Bool-API harness. HYG-06/HYG-08 are intentionally not marked complete (the helper is not applied to any item and the harness has only had a smoke run).

## Tasks

| Task | Commit | Result |
|------|--------|--------|
| 1 FlakeRetry + unit test | a176d3b | 4 items, 16 passes; retries only SolveFailedError (status in RETRYABLE_STATUSES) / ConvergenceError, rethrows last error after `tries`, logs each retry via @info, atexit `RETRY SUMMARY` |
| 2 flake_rate.jl | 4f44b41 | selftest OK; smoke (fit_baseline, 1 repeat): outcome `broken`, 5 pass / 1 broken, solve_label `solved`, Julia 1.12.5, 47.8 s |
| 3 archive + API skip | a14cbfd | `check_script_api.jl` selftest OK (55 cases + 3 archive path cases), real run OK (39 files); `check_planning_ids.py` OK |

## Deviations from Plan

- **[Rule 1] TestCounts shape:** `Test.get_test_counts` returns a struct in Julia 1.12 (not a tuple); the harness sums direct and `cumulative_*` fields.
- **[Rule 3] World age:** TestItemRunner is loaded lazily (so `--selftest` stays light), so the run goes through `Base.invokelatest`.
- The `ieee13_admm` target also covers the test_admm.jl ieee13 cross-validation item (named in the plan's interface notes), in addition to the 4q-bess item.
- The git mv of `reactive_flake_rate.jl` was staged earlier and landed in the harness commit 4f44b41 rather than the archive commit a14cbfd.

## Known Stubs

None.

## Self-Check: PASSED
