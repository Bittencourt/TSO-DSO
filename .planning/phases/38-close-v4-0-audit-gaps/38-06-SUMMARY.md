---
phase: 38-close-v4-0-audit-gaps
plan: 06
subsystem: test-hygiene-ci
tags: [admm, time-limit, budget-exceeded, testitems, ci, setup-names]
requires:
  - "38-05: ledger running tally (count-sets 513/476/98 before this plan)"
provides:
  - "test/test_admm_timeout.jl as two discovered fast :admm @testitems (:budget_exceeded + typed ConvergenceError cap; :converged)"
  - "CI format job step 'Check @testitem setup names resolve' (selftest, then full check)"
affects: [38-10]
tech-stack:
  added: []
  patterns: ["every test file is @testitem-only so the runner discovers it; count-sets proves membership"]
key-files:
  created:
    - .planning/phases/38-close-v4-0-audit-gaps/38-06-SUMMARY.md
  modified:
    - test/test_admm_timeout.jl
    - .github/workflows/CI.yml
    - .planning/phases/38-close-v4-0-audit-gaps/38-MEASUREMENTS.md
decisions:
  - "The cap assertion is tightened from Exception to ConvergenceError, the type measured to be thrown"
  - "No :slow tag: warm in-suite time is about 13 s, under the 30 s rule; the gate plan re-measures in the full verbose run"
metrics:
  duration: ~15min
  completed: 2026-10-07
  tasks: 2
  files: 3
requirements: [HYG-05, ARCH-08]
---

# Phase 38 Plan 06: ADMM timeout test discovered by the suite, setup-name guard in CI Summary

The only test of `solve_admm`'s `:budget_exceeded` path now runs in the suite. It used to be a
plain script that the runner never discovered. It is now two fast `:admm` @testitems built from
inline fixtures. The CI `format` job now also runs the @testitem setup-name guard.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Convert the timeout script into two fast @testitems | adf08ec | test/test_admm_timeout.jl, 38-MEASUREMENTS.md |
| 2 | Run check_setup_names in the CI format job | b74ec9d | .github/workflows/CI.yml |

## Results

- `file:test_admm_timeout.jl` filtered run on 1.12.5: 19/19 pass (1 + 11 + 7), 2 items selected,
  55.4 s cold including compile.
- `--count-sets --strict`: before `all=513 fast=476 slow=37 files=98 canary=1 outside=0`, after
  `all=515 fast=478 slow=37 files=99 canary=1 outside=0`. This matches the expected tally.
- `test/expected_broken.txt` is unchanged because the file has no Broken tests.
- The formatter (`format210.jl`) made no changes. `check_content_loss.py HEAD` is OK, and
  `check_planning_ids.py` is OK.
- `check_setup_names.py --selftest`: 4 cases OK. The full check reports 21 testmodules,
  222 setup uses, 0 unresolved. The CI YAML parses, and the new step sits between "Check for
  planning identifiers" and "Scripts index selftest".

## Deviations from Plan

None. The plan was executed as written.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: test/test_admm_timeout.jl (2 `^@testitem`, 0 "NOT a TestItemRunner"/"Run directly")
- FOUND: adf08ec, b74ec9d
