---
phase: 36-code-export-cleanup
plan: 14
subsystem: hygiene
tags: [planning-id-scrub, module-file, docs, readme, ci-comments]
requires: ["36-13"]
provides:
  - src/TSODSO.jl, docs/make.jl, docs/src/*.md, README.md and CI.yml free of planning identifiers (classifier TOTAL 0)
affects: [36-15]
key-files:
  modified:
    - src/TSODSO.jl
    - docs/make.jl
    - docs/src/status_policy.md
    - README.md
    - .github/workflows/CI.yml
requirements-completed: []
completed: 2026-10-05
---

# Phase 36 Plan 14: Scrub of src/TSODSO.jl, docs, README and CI comments Summary

The ~110 per-include comments in `src/TSODSO.jl` became short section headers naming what each included file provides, keeping every load-order rationale (world-age ordering, "must load after X", orchestration-over-validated-builders notes). `docs/make.jl`, `status_policy.md`, `README.md` and `CI.yml` lost their phase, requirement, threat, decision and pitfall tags. `docs/src/index.md` and `docs/src/api.md` had no hits. Classifier reports TOTAL 0 over the 7-file set. HYG-01 stays pending.

## Commits
- ef339e1: scrub src/TSODSO.jl
- e57b251: JuliaFormatter 2.10.2 pass on src/TSODSO.jl (only whitespace: the module docstring bullet list got the standard 2-space indent; check_content_loss printed OK)
- 68f3929: scrub docs/make.jl, status_policy.md, README.md, CI.yml comments. The formatter pass on `docs/make.jl` was a no-op, so there is no second commit for it.

## Verification
- Classifier TOTAL 0; `ast_equiv.jl` EQUAL for `src/TSODSO.jl` and `docs/make.jl` against the pre-plan commit; `thesis_tokens.py` OK; `check_content_loss.py HEAD` OK after the formatter.
- `ast_equiv.jl --strings` reports 0 changed string literals for both `.jl` files.
- `test_exports.jl`: 12/12 pass.
- CI.yml: YAML parses; job and step structure identical to the pre-plan file once `#` comment lines inside `run:` scripts are ignored (the Julia comments embedded in the format job's script were edited, so a raw parsed-value diff is non-empty). The only changed line not starting with `#` is `- '1.10'   # LTS floor ...` where only the trailing comment changed.
- The `docs/src/status_policy.md` "Breaking changes" section (section 7) is intact.
- No docs build was part of this plan, and the full suite is not re-run here (no code changed; AST EQUAL). The last full suite (plan 13) was 32202/0/0/5.

## Message changes
None. No runtime strings, error messages or `@testitem` names changed.

## Hand-edited MIXED lines
`include("admm/AgrOpt.jl")` and `include("admm/DsoOpt.jl")` trailing comments keep their `thesis 3.46` and `thesis 3.47` references verbatim, with only the plan and requirement tags removed.

## Deviations from Plan
- [Rule 1] Process wording the classifier cannot catch was reworded: `byte-identical` / `byte-unchanged` (to `bit-for-bit identical` / `UNCHANGED`, in `TSODSO.jl`, README, `status_policy.md`), `RESEARCH ...` citations, `Wave-2` / `Waves 2-4`, `this plan is the SOLE owner of this shared edit`, `Wired empty (comment-only) in plan ...`, `Phase-20's certificate/fallback ladder`, `SITE-2` in `status_policy.md`, and the README roadmap row's "(Phases 19-24)". The heading "Handler rule (ARCH-09)" became "Handler rule"; no anchors referenced it.
- [Rule 1] Pointers like "(commit dc0de79)" were kept in `docs/make.jl` because they cite a git commit, not a planning ID.
- The plan's CI.yml diff-check (no non-`#` changed lines) would print one line because of the trailing comment on a matrix entry; the change is comment-only and the parsed YAML is identical.

## Known Stubs
None.

## Self-Check: PASSED
