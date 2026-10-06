---
phase: 37-test-infrastructure-repo-hygiene
plan: 04
subsystem: test-infrastructure
tags: [timing, slow-tagging, julia-1.12.7]
requires: [37-02, 37-03]
provides:
  - 37-TIMINGS.md (per-file and per-item times, Broken accounting lines)
  - 37-slow-items.txt (35 items to tag :slow)
affects: [37-05, 37-12, 37-13]
key-files:
  created:
    - .planning/phases/37-test-infrastructure-repo-hygiene/37-TIMINGS.md
    - .planning/phases/37-test-infrastructure-repo-hygiene/37-slow-items.txt
requirements-completed: []
completed: 2026-10-06
---

# Phase 37 Plan 04: Instrumented timing run Summary

One detached verbose full run on Julia 1.12.7 (37m03s) was parsed into a per-item timing table and a rule-based list of 35 `:slow` items (1213.8 s of item time). HYG-05 is intentionally not marked complete (the tags are applied in a later plan).

## Result

- Totals 1.12.7: Pass 32218 / Error 1 / Broken 4 / Total 32223, against the 1.12.5 baseline 32205 / 0 / 5. Canary: iters = 56, welfare = -4823.666048218671 (golden -4823.66604824162 agrees to about 5e-12 relative).
- Selected 510 items in 98 files (506 from plan 02 plus the 4 flake_retry items).
- Pass delta +13: +16 (flake_retry items), +1 (`guards` testset), -4 (inferred, passes lost in the erroring FIT item).
- Only failure: `welfare surplus accounting: +25% FIT ratio golden + non-failing thesis cross-check` (test/test_pricing_welfare.jl:301). `fit_baseline` returns ALMOST_OPTIMAL / NEARLY_FEASIBLE_POINT, `assert_solved!` throws `SolveFailedError` (test line 325). No other failure or error; nothing was fixed here.
- Machine-readable lines (in 37-TIMINGS.md):
  - BROKEN_1.12.5=5
  - BROKEN_1.12.7_RAW=4 (acceptance IEEE-13 SC3, ieee13 ground v9[16], nash plot skip, diagnostics plot skip)
  - BROKEN_1.12.7_EXPECTED_POSTGATE=5

## Findings for the tagging plan

- The Aqua item costs 582 s, of which "Persistent tasks" is 552.3 s. By rule it stays fast, but it is about 58% of the estimated fast-set item time (about 1007 s). The fast wall time is bounded below by roughly 10 min. Consider `persistent_tasks=false` in the fast set.
- The 1.12.5 baseline logs are non-verbose, so the compile-bias re-assessment (rule c) could not use per-item 1.12.5 figures; no item was removed under it.

## Tasks

| Task | Commit | Result |
|------|--------|--------|
| 1 Instrumented run | (measurement, no commit) | `.planning/tmp/36/p37-timing.{log,done}`, DONE=1 as expected |
| 2 Timings and slow list | eb6006b | 35 slow names verified present in test/; `check_planning_ids.py` OK |

## Deviations from Plan

None. A follow-up wording fix (relative canary difference 5e-12) was made in 37-TIMINGS.md after the commit and is included in the docs commit.

## Self-Check: PASSED
