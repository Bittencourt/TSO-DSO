---
phase: 37-test-infrastructure-repo-hygiene
plan: 05
subsystem: test-infrastructure
tags: [slow-tags, aqua-split, fit-gate, ieee8500]
requires: [37-04]
provides:
  - ":slow tags on 35 measured items plus a new :slow Aqua persistent-tasks item"
  - "gated @test_broken for the FIT ALMOST_* solve failure (outcome-conditioned)"
  - "ieee8500 harness test decision: manual (measured)"
affects: [37-12, 37-13]
key-files:
  modified:
    - test/test_toy_dc.jl
    - test/test_pricing_welfare.jl
    - test/expected_broken.txt
    - .github/scripts/check_suite_log.py
    - .planning/phases/37-test-infrastructure-repo-hygiene/37-slow-items.txt
  created:
    - .planning/todos/pending/2026-10-06-fit-baseline-almost-optimal-julia-1-12-7.md
requirements-completed: []
completed: 2026-10-06
---

# Phase 37 Plan 05: Slow tags, FIT gate, ieee8500 decision Summary

The fast/slow split is real: `--count-sets --strict` gives all=511, fast=474, slow=37, canary=1 fast, none outside test/. HYG-05/06/08 are intentionally NOT marked complete.

## Commits
- e85457a: :slow tags (12 files, 35 items) + Aqua split.
- 241547f: FIT gate, expected_broken amendment, check_suite_log docstring, backlog todo.

## Task 1: tags and Aqua split
- 35 items from 37-slow-items.txt tagged `:slow` (header-only edits, JuliaFormatter 2.10.2 applied).
- Aqua split (orchestrator decision): fast item runs `Aqua.test_all(TSODSO; persistent_tasks = false)` (10 passes, 27.7 s measured); new `:slow` item "quality: Aqua persistent tasks (...)" runs `Aqua.test_persistent_tasks(TSODSO)`. Coverage unchanged. It was added to 37-slow-items.txt (36 lines).
- slow=37 = 36 listed + 1 item that already carried `:slow` before this phase ("planning hardening: load test", test_planning_hardening.jl). It was not in the 37-04 list (file total below threshold); left as is.
- Tag-only checker (scratch `.planning/tmp/37/check_tag_only_diff.jl`, AST-based): OK for 13 files; the only non-tag differences are the intentional Aqua body change and the new Aqua item (reported by the checker as exceptions).
- `check_content_loss.py HEAD` reports +chars on the tagged files: expected, it only tolerates whitespace/comma changes, and adding `:slow` is content. The AST checker is the real gate here.
- check_planning_ids.py and check_script_api.jl green.

## Task 2: FIT gate
- Item solves via a local helper that returns the caught error only for `SolveFailedError` whose termination status starts with `ALMOST_`; everything else propagates. No Julia-version condition, no src change.
- Gated path: `@info` (with VERSION and statuses) + `@test_broken false`; ratio golden and thesis cross-check are skipped (documented limitation: unavailable there).
- Wording: "observed on 1.12.7; not on 1.12.5; other patches unmeasured".
- Verified (`TSODSO_TEST_FILES=test_pricing_welfare.jl`): 1.12.7: rc 0, gate @info printed (ALMOST_SOLVED / NEARLY_FEASIBLE_POINT), Pass 35, Broken 1. 1.12.5: rc 0, no gate @info, Pass 40, Broken 1 (existing conditional cross-check, gap 0.25).
- expected_broken.txt: still 6 entries, the single FIT entry reason amended. check_suite_log.py docstring now says the `--broken` count is per Julia patch (BROKEN_* in 37-TIMINGS.md; default 5 kept).
- Backlog todo filed. Full-suite Broken on 1.12.7 is checked later against BROKEN_1.12.7_EXPECTED_POSTGATE=5.

## Task 3: ieee8500 decision: MANUAL (no wrapper)
Measured `julia +release --project=. test/test_benchmark_ieee8500.jl` (all 34 assertions pass, "ALL TESTS PASSED"): wall 14m49.5s (the harness testset alone 10m39.8s), user 910 s, peak RSS 2.74 GB. Wall time exceeds the plan's 10-minute bound, so no `test_benchmark_ieee8500_item.jl` was created. For the scripts-README plan: document as manual, run `julia --project=. test/test_benchmark_ieee8500.jl` (about 15 min, about 2.7 GB), pins model_vars 137258 / model_cons 274570 / admm_iters 1 per the plan (file header carries the current golden history). No `@testitem` exists outside test/.

## Deviations
- [Orchestrator additions] Aqua split as above. Task 2 verify run per version into logs with explicit assertions (exit code, gate @info presence, Broken count) instead of `| tail`.
- Note: the `rtk` hook rewrites `git`/grep inside `$(...)` and pipelines in this environment; used `/usr/bin/git` and `/usr/bin/grep` where needed. No effect on repo state.

## Self-Check: PASSED
Commits e85457a and 241547f exist; todo, expected_broken and test files present; src untouched.
