---
phase: 37-test-infrastructure-repo-hygiene
plan: 09
subsystem: ci
tags: [ci, github-actions, fast-slow-split, jet]
requires: [37-05, 37-08]
provides:
  - CI test job runs the fast set (TSODSO_TEST_SET=fast) on Julia 1.10/1.11/1.12
  - CI jet job (Julia 1.12) running scripts/jet_check.jl against the baseline
  - .github/workflows/slow.yml nightly + workflow_dispatch full suite on 1.10 and 1.12
key-files:
  created: [.github/workflows/slow.yml]
  modified: [.github/workflows/CI.yml, .github/scripts/check_suite_log.py]
decisions:
  - slow.yml has permissions contents: read and no secrets; action versions identical to CI.yml
metrics:
  tasks: 3
  completed: 2026-10-06
---

# Phase 37 Plan 09: CI fast/slow wiring Summary

Per-push CI now runs the fast set and a separate JET job; a new nightly/dispatch workflow runs the full suite. The fast set was run locally once, detached, on Julia 1.12.7.

## Commits
- 72f199c: CI.yml fast env, jet job, per-minor Manifest comment
- 76b280a: slow.yml (cron `17 3 * * *`, workflow_dispatch input test_set all|slow, matrix 1.10/1.12, timeout 120)
- cfaf7a7: check_suite_log.py tolerant canary welfare match (see Deviations)

## Local validation (CI cannot run locally)
- PyYAML parses both files. CI jobs: test, jet, format, docs. slow.yml: schedule + workflow_dispatch, one job `test`.
- Expressions: only `inputs.*`, `matrix.*`, `github.workspace`, `github.workflow`/`ref`, `secrets.*` (pre-existing in CI.yml only). `grep -c secrets slow.yml` = 0. `actionlint` not installed, so not run.
- Permissions: the new jet job and slow.yml set `contents: read`.
- `check_planning_ids.py` (248 files) and `check_script_api.jl` (40 files) green.

## Fast-set local run (p37-fast, `julia +1.12`, -t2, TSODSO_TEST_SET=fast)
- Exit 0. Pass 31895, Fail 0, Error 0, Broken 4, Total 31899. Wall time 524 s (about 8.7 min), inside the ~12-15 min budget (estimate in 37-TIMINGS.md: about 8.4 min plus load).
- Full suite for comparison (37-TIMINGS.md): Total 32223; the fast set excludes the 35 slow items, so the passthrough is observable (31899 < 32223).
- Canary present: `iters = 56`, `welfare = -4823.666048218671` (golden -4823.66604824162, about 5e-12 relative).
- Broken check, not tautological: the runtests guard enforces observed Broken records subset of `test/expected_broken.txt`; the log has 0 `UNEXPECTED` lines and the "guards" testset passed. The file lists 4 `broken` entries (plus 2 `skipped` for CairoMakie that do not count as Broken); the fast run observed exactly 4, so all four allowed items are in the fast set. This is a first measurement of the fast-set count on 1.12.7; `check_suite_log.py p37-fast --broken 4` exits 0 ("suite OK").

## Deviations from Plan

**[Rule 3 - Blocking] check_suite_log.py canary welfare regex too strict.** The log prints `-4823.666048218671` on 1.12.7 while the regex demanded the literal `-4823.66604824162`, so the check failed although the canary item passed. Replaced with a float comparison at rel 1e-9 (the same discrepancy was already noted in 37-TIMINGS.md). Commit cfaf7a7.

## MANUAL verification (GitHub side, after push)
1. The fast job log shows fewer items than the full suite (env passthrough via julia-runtest; expect about 475 items vs 510).
2. The `jet` job passes on GitHub.
3. `gh workflow run slow.yml` starts; inspect with `gh run view`. Scheduled runs only fire from the default branch.

HYG-04 and HYG-05 intentionally NOT marked complete (final gate remains).

## Self-Check: PASSED
Commits 72f199c, 76b280a, cfaf7a7 exist; slow.yml present; p37-fast.done = 0.
