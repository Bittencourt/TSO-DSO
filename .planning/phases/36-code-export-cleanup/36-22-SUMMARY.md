---
phase: 36-code-export-cleanup
plan: 22
subsystem: verification
tags: [gates, formatter, aqua, docs, suite]
requires: ["36-21"]
provides: ["36-FINAL-GATES.md"]
key-files:
  created: [.planning/phases/36-code-export-cleanup/36-FINAL-GATES.md]
  modified: [test/test_exports.jl]
decisions:
  - "Inlined the 102-name unexported list into test_exports.jl (the name file was a test dependency of the deleted tooling)."
  - "Left test/test_benchmark_ieee8500.jl unformatted: formatter change fails content-loss."
metrics:
  completed: 2026-10-05
---

# Phase 36 Plan 22: Final Gates Summary

All phase gates are green on the finished tree: suite 32202 pass / 0 / 0 / 5 broken (identical to p20, canary iters = 56, welfare -4823.66604824162), docs build OK, Aqua 8/8, guard and selftest exit 0, token grep empty, golden literals EQUAL.

## Commits
- 949b0c8 chore(36-22): remove one-shot unexport migration tooling; inline the name list in the export test
- Gates and summary in the docs commit.

## Deviations
- [Rule 3] `test/test_exports.jl` read `.github/scripts/unexported_names.txt`; deleting the file would have broken the test, so the list became an inline tuple (same single assertion, suite count unchanged).
- Formatter: `test/test_benchmark_ieee8500.jl` still wants a docstring rewrite (+4 chars, flagged by content-loss); left unformatted and documented.

## Docs
4 unresolved `@ref` warnings (plan 06: 6); all internal names in `docs/src/api.md`, non-fatal.

## Breaking removals (phase aggregate)
`operational_oracle` keywords `objective_hook`/`horizon_state`/`z`; Bool/Symbol reactive modes (`ReactiveMode` is a module, `normalize_reactive_mode` enum-only); 102 names unexported (192 to 90); `DlmpDecomposition` `.loss`/`.voltage` aliases; stored reactive-mode type path. Documented in `docs/src/status_policy.md` section 7.

## Message changes
Aggregated in the per-plan summaries (benders, DsoOpt, admm_phases, master/master_integer, mpc_loop, exactness, restriction_exactness, literate, scripts, testitem names); tags and process wording removed only, no test asserts any. This plan changed none.

## Pass-count delta
32177 to 32202 (+25), from assertions added in earlier plans; none in this plan. No golden re-pinned.

## Self-Check: PASSED
