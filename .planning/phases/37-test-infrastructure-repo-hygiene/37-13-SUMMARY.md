---
phase: 37-test-infrastructure-repo-hygiene
plan: 13
subsystem: testing
tags: [phase-gate, full-suite, jet, formatter, docs]
requires: [37-12]
provides:
  - 37-FINAL-GATES.md evidence table for every phase gate
affects: []
key-files:
  created:
    - .planning/phases/37-test-infrastructure-repo-hygiene/37-FINAL-GATES.md
  modified:
    - test/fixtures_retry.jl
    - test/runner_support.jl
    - test/runtests.jl
    - test/test_flake_retry.jl
decisions:
  - "Pass delta on 1.12.5 is exactly 32205+16+1+1; 1.12.7 is 5 lower, solely the gated FIT item"
metrics:
  completed: 2026-10-06
requirements-completed: [HYG-04, HYG-05, HYG-06, HYG-08]
---

# Phase 37 Plan 13: Final Gates Summary

Both detached full runs and all static guards are green and recorded in 37-FINAL-GATES.md.

- 1.12.5: 32223 pass / 0 / 0 / 5 broken, which equals 32205 + 16 (flake_retry) + 1 (guards) + 1 (Aqua persistent-tasks item). Canary iters 56, welfare -4823.66604824162.
- 1.12.7: 32218 pass / 0 / 0 / 5 broken. The 5 fewer passes are the assertions skipped by the gated FIT item. Broken stays 5, which matches `BROKEN_1.12.7_EXPECTED_POSTGATE`.
- JET is 0 new / 0 fixed on both patches. The planning-ID, script-API, scripts-index and count-sets guards pass, with selftests. Docs build is clean, Aqua passes, and tmp/Manifest hygiene holds.

## Deviations from Plan

**[Rule 1] Formatter drift** in 4 test runner files from earlier plans. The 2.10.2 formatter reformatted them (content-loss check OK) and I committed that as 6dabf6e (`style(37-13)`). The suites had run on the pre-format text, which is AST-equivalent.

GitHub-side checks (env passthrough, JET job, nightly slow workflow) are listed as MANUAL in 37-FINAL-GATES.md.

## Self-Check: PASSED
