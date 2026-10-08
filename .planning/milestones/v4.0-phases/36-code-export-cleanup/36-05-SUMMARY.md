---
phase: 36-code-export-cleanup
plan: 05
subsystem: tests
tags: [exports, migration, tests]
requires: [36-04]
provides:
  - test/ migrated to the trimmed export surface (explicit `using TSODSO: names`)
  - unexport_migrate.py selfcheck mode
key-files:
  modified:
    - 54 test/*.jl files (fixtures and test files)
    - .github/scripts/unexport_migrate.py
requirements-completed: []
completed: 2026-10-05
---

# Phase 36 Plan 05: Test migration to trimmed exports Summary

All test files and `@testmodule` fixtures now import the unexported names they use; the full suite is green with goldens and canary untouched. HYG-03 is NOT marked complete (plan 06 migrates scripts/docs).

## Commits
- 2d85d02: migrate test files (424 sites in 55 files; 54 changed, 163 inserted `using TSODSO:` lines, nothing else)

## Details
- Scanner: it already skipped `:NAME` symbol contexts, single-line strings, comments and docstrings; added a `selfcheck` mode (`:SOCP`, `"SOCP in text"`, `Symbol("SOCP")` and one real `SOCP()` yields exactly 1 site) which passes. `test/test_exports.jl` was excluded from the apply run. Note: `scan`/`apply` ignore directory arguments (pass file lists) and `apply` takes ~15 minutes over test/.
- A post-apply check (per testitem/testmodule: used names minus imported names) reports 0 missing. `ast_equiv.jl --literals` prints EQUAL for all 54 changed files. The diff contains only added `using TSODSO: ...` lines.
- Scanner misses (UndefVarError): none.
- Hot-spot files (coupling, close_balance, master, master_integer) plus `tag:exports`: 565/565 pass.
- Full suite `p05b`: Pass=32202 Fail=0 Error=0 Broken=5 Total=32207; canary welfare -4823.66604824162 present; Aqua items inside the suite pass.

## Suite delta vs plan 03 (32201)
Nominal +12 (test_exports.jl) would give 32213, observed 32202 (+1). Explanation: the p03 run also executed a stale gitignored scratch copy of test_admm_dualresid.jl (`.planning/tmp/36/t.jl`, 11 assertions) that TestItemRunner discovers under the project root. Removing it gives 32201 - 11 + 12 = 32202, which matches exactly. This is inferred from counts (dualresid + exports = 23 in a targeted run), not from the old log.

## Deviations from Plan

**1. [Rule 3 - Blocking] Stale scratch testitem file in `.planning/tmp/36/`**
- First full run `p05` reported 1 error from `.planning/tmp/36/t.jl` (un-migrated scratch copy; `record!` undefined). Moved it out of the project tree to the session scratchpad and re-ran the full suite as `p05b` (green). Not a repo change (the directory is gitignored). Later plans should keep scratch `.jl` files containing `@testitem` out of the project root.

## Known Stubs
None.
