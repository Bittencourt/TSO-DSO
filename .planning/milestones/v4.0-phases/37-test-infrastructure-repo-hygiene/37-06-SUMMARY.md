---
phase: 37-test-infrastructure-repo-hygiene
plan: 06
subsystem: test-infrastructure
tags: [flake-rate, measurement, quarantine-decision]
requires: [37-03, 37-05]
provides:
  - "20x fresh-process flake measurements on Julia 1.12.5 and 1.12.7 (results/flake_rate)"
  - "evidence-based decision: nothing quarantined"
key-files:
  created:
    - results/flake_rate/20261006T105826_1.12.5.csv
    - results/flake_rate/20261006T114935_1.12.7.csv
  modified:
    - results/flake_rate/findings.txt
requirements-completed: []
completed: 2026-10-06
---

# Phase 37 Plan 06: Flake-rate measurement Summary

Measured, did not quarantine: no reproducible flake at current defaults. HYG-06 is intentionally NOT marked complete (final gate remains).

## Results (20 fresh-process repeats each, `--jobs 2`)

| target | 1.12.5 | 1.12.7 |
|---|---|---|
| ieee13_admm | 20/20 pass | 20/20 pass |
| stochastic_welfare | 20/20 pass | 20/20 pass |
| fit_baseline | 20/20 broken, solve_label=solved | 20/20 broken, solve_label=solve_failed:ALMOST_OPTIMAL |

No NUMERICAL_ERROR, SLOW_PROGRESS or ConvergenceError labels anywhere. With 0/20 failures the Wilson 95% upper bound on the failure rate is 16.1%, so a rarer flake is not excluded. The historical Phase-16 IEEE-13 NUMERICAL_ERROR rates (11/20, 3/20) were measured on old Bool-API code and do not reproduce.

## Decision (branch a)
- ieee13_admm, stochastic_welfare: nothing quarantined, no `with_solve_retry` applied (helper remains available and unit-tested).
- fit_baseline: deterministic per patch, already gated by 37-05; regimes distinguished by `solve_label` only.
- No test or src edits; canary/goldens untouched; `check_planning_ids.py` green.

## Commits
- 78a9f0c: results/flake_rate CSVs and findings.txt

## Deviations
None. Duplicate wait-watchers were started and one was stopped by its time limit; harmless.

## Self-Check: PASSED
