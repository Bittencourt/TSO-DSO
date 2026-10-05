---
phase: 36-code-export-cleanup
plan: 07
subsystem: testing
tags: [fixtures, tags, rename, hygiene]
requires: [36-06]
provides:
  - nine test fixture files and @testmodules named after content
  - content tags :ieee123, :ieee8500, :adaptive replace :phase7/:phase25
key-files:
  modified:
    - test/fixtures_*.jl (9 git mv renames)
    - 87 files with module/path references (test, src, scripts, docs/literate)
    - 8 test files with tag changes
requirements-completed: [HYG-07]
duration: ~1h (mostly suite wait)
completed: 2026-10-05
---

# Phase 36 Plan 07: Fixture and Tag Renames Summary

Nine phase-numbered fixtures renamed by content (SmallRadial, IEEE13, TwoBus, IEEE123, ExperimentHarness, FourQuadBESS, MPC, Stochastic, Mesh) with history kept, and phase tags replaced by content tags; the suite count is unchanged.

## Commits
- Rename-only commit (9 `git mv`, 100% similarity).
- Module identifier and path-prose rename across 87 files (test, src, scripts, docs/literate).
- Tag rename commit (:phase25 to :ieee8500; :phase7 to :ieee123 or :adaptive; [:admm, :ieee123] for test_ieee123_admm.jl) plus the hardening comment reword.

Hashes are in `git log` for the 36-07 scope.

## Verification
- `check_setup_names.py`: 20 testmodules, 222 setup uses, 0 unresolved.
- Grep for `Phase<N>Fixtures`, `fixtures_phase<N>`, `:phase<N>` over src, ext, test, scripts, docs/literate, docs/make.jl, .github: empty. The TwoBusFixtures-before-FourQuadBESSFixtures sibling order is kept.
- AST equivalence: src, scripts and docs/literate files EQUAL (prose-only edits). Test files differ only by tag symbols, as intended.
- Tag selection: ieee123 7 items, ieee8500 10, adaptive 8 (all non-empty); the combined multi-spec run passed 27594/27594.
- Full suite p07: 32202 pass / 0 fail / 0 error / 5 broken, identical to p05b. Canary welfare = -4823.66604824162 present in log. Goldens and canary not re-pinned.

## Deviations from Plan
None. Tag-listing via `check_setup_names.py --tags` was replaced by counting tagged items by grep. `.github/workflows/CI.yml` and `scripts/run_tests_filtered.jl` do not filter on removed tags.

## Self-Check: PASSED
