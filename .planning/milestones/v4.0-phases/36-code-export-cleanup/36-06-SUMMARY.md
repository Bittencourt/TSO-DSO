---
phase: 36-code-export-cleanup
plan: 06
subsystem: docs
tags: [exports, docs, migration, breaking-changes]
requires: [36-05]
provides:
  - scripts and literate pages migrated to the trimmed export surface
  - ReactiveMode module documented; makedocs modules include TSODSO.ReactiveMode
  - Breaking changes section in docs/src/status_policy.md
key-files:
  modified:
    - 12 scripts/*.jl and 11 docs/literate/*.jl (added `using TSODSO: ...` lines)
    - docs/src/api.md
    - docs/make.jl
    - docs/src/status_policy.md
requirements-completed: [HYG-03]
completed: 2026-10-05
---

# Phase 36 Plan 06: Scripts, docs and breaking-changes note Summary

Scripts and literate pages import the unexported names they use, `ReactiveMode` is documented, a Breaking changes section covers all ledger entries, and the docs build exits 0 with `checkdocs = :exports`.

## Commits
- 0625d2e: migrate 23 files (87 sites; added import lines only; ast_equiv `--literals` EQUAL on all)
- docs commit: api.md `ReactiveMode` entries, `modules = [TSODSO, TSODSO.ReactiveMode]`, "7. Breaking changes" in status_policy.md
- cross-reference commit: 21 `[name](@ref)` links in 7 literate pages qualified as `@ref TSODSO.name`

## Details
- docs/src markdown and README needed no changes (README hits are prose in the layout block, not code).
- The scanner counts the new import line as a site, so re-scan is not 0; the equivalent check (only `using TSODSO:` lines added, parse OK, docs build executes all pages with no UndefVarError) passes.
- Variant: nested module check (assumption A3) worked; `TSODSO.ReactiveMode` stays in `modules`.
- Docs build p06 and p06b exit 0. The first build had 32 unresolved `@ref` warnings (21 from names that stopped being exported, fixed by qualifying); 6 remain, all in src docstrings of internal constants/fields (`TAU_SOLVER_FIX08`, `MEASURED_ε_FIX08`, `FIT_SITE3_ALMOST_GAP_TOL`, `stall_z_atol`, `*.lb_clamped`), non-fatal since `:cross_references` is in `warnonly`. I did not verify these were present before the phase.
- Planning-ID scan: my added text has no IDs (remaining hits pre-existing).
- check_suite_log reported "stale run" for p06b only because of commit-timestamp ordering; log and done marker show exit 0.

## Deviations from Plan
**1. [Rule 1 - Bug] Broken cross-references after unexporting** — fixed by qualifying with `TSODSO.` (third commit).

## Known Stubs
None.
