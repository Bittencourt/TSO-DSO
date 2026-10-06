---
phase: 37-test-infrastructure-repo-hygiene
plan: 02
subsystem: test-infrastructure
tags: [testitemrunner, selection, broken-guard]
requires: [37-01]
provides:
  - TSODSO_TEST_SET fast|slow|all selection (fail-closed) in test/runtests.jl
  - allowed-broken guard (test/expected_broken.txt)
  - run_tests_filtered.jl --count-sets [--strict]
  - check_suite_log.py --broken N / --skip-canary
affects: [later phase-37 plans applying :slow tags]
key-files:
  created:
    - test/runner_support.jl
    - test/expected_broken.txt
  modified:
    - test/runtests.jl
    - scripts/run_tests_filtered.jl
    - .github/scripts/check_suite_log.py
requirements-completed: []
completed: 2026-10-06
---

# Phase 37 Plan 02: Test entrypoint selection and broken guard Summary

`test/runtests.jl` now selects items by `TSODSO_TEST_SET` (fast|slow|all, invalid value throws), only from `test/`, fails on zero selection, and fails on any Broken/skipped record not in `test/expected_broken.txt`. HYG-05/HYG-06 are intentionally not marked complete (later plans remain).

## Tasks

| Task | Commit | Result |
|------|--------|--------|
| 1 runner_support, expected_broken, runtests rewrite | e787aa1 (+16c18f1 header fix) | bogus set errors with `fast\|slow\|all`; slow+zero items exits 1; short run exits 0 with `TSODSO` outer set (Pass 75, Broken 2) |
| 2 `--count-sets` | e8e9dbd | selftest OK; counts all=506 fast=505 slow=1 files=97 canary=1 |
| 3 check_suite_log options | 3f554a6 | p37-short log: totals Pass 75 / Broken 2 / Total 77 match the summary; wrong `--broken` exits 1 |

## Deviations from Plan

- **[Rule 1 - plan assumption] A `:slow` tag already exists** (test/test_planning_hardening.jl, one item). So `--count-sets --strict` exits 0 now (slow=1) instead of failing, and `TSODSO_TEST_SET=slow` with `TSODSO_TEST_FILES=test_ieee13.jl` still fails (zero selection), as required. Strict-mode bite is proven in `--selftest` through the pure `check_tally` (slow == 0 rejected).
- Walker uses a captured outer testset (`Test.DefaultTestSet` has no `parent` field).
- check_suite_log parser needed no change for the outer-testset shape (first row after the last `Test Summary:` header is the top-level row).
- Removed requirement ids from the runtests header comment to keep `check_planning_ids.py` green.
- First p37-short run was rejected as stale (started in the same second as HEAD); relaunched after 2s.

## Verification

`check_planning_ids.py` OK, `check_script_api.jl` OK. Full suite not run in this plan.

## Self-Check: PASSED
