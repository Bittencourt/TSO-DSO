---
phase: 37-test-infrastructure-repo-hygiene
plan: 01
subsystem: repo-hygiene
tags: [gitignore, manifests, docs, formatter]
requires: []
provides:
  - ignored scratch dir .planning/tmp/ (incl. 37/)
  - per-minor manifests as the only root manifests
affects: [all later phase-37 plans]
key-files:
  modified:
    - .gitignore
    - src/pricing/fit.jl
    - src/planning/master.jl
    - src/planning/master_integer.jl
    - test/test_benchmark_ieee8500.jl
  deleted:
    - Manifest.toml
    - .planning/tmp/docs-work-manifest.json (untracked, working copy kept)
decisions:
  - Root Manifest.toml dropped (byte-identical to Manifest-v1.12.toml); Pkg selects Manifest-v1.X.toml by Julia minor.
requirements-completed: [HYG-08]
duration: ~25min
completed: 2026-10-06
---

# Phase 37 Plan 01: Repo hygiene foundation Summary

`.planning/tmp/` is now fully ignored and untracked, the redundant root `Manifest.toml` is gone with per-minor resolution verified on 1.10.11, 1.11.9 and 1.12.7, and the docs build emits zero unresolved `@ref` warnings.

## Tasks

| Task | Commit | Result |
|------|--------|--------|
| 1 ignore tmp, drop root Manifest | 08081f8 | `git ls-files .planning/tmp` empty; `.gitignore` header rewritten; each Julia minor selects its own `Manifest-v1.X.toml` |
| 2 docstring `@ref` + ieee8500 docstring | 7230e92 | 4 `@ref` links turned into code spans; `ast_equiv` EQUAL on all 4 files; formatter 2.10.2 clean |
| 3 docs build check | (measurement) | `check_suite_log --mode docs` OK, `Cannot resolve @ref` count 0 |

## Deviations from Plan

- Formatter 2.10.2 additionally turned a pre-existing one-line docstring (`run_harness`) in `test/test_benchmark_ieee8500.jl` into a triple-quoted block. This is docstring-only (AST EQUAL).
- `check_content_loss.py HEAD` exits 1 by design on these intentional docstring edits (+26/-8/-16/-8 chars, only `[..](@ref)` markup and docstring text); AST equivalence modulo docstrings was used as the proof instead.
- Recorded for a later plan: `.github/workflows/CI.yml` still has the comment "against the committed Manifest"; `docs/src/generated/experiments.md` mentions `Manifest.toml` generically (generated file, not edited).
- The throwaway JuliaFormatter 2.10 env was created by the repo's `format210.jl` (temp env outside the repo).

## Verification

- `check_planning_ids.py` OK, `check_script_api.jl` OK, `test_exports.jl` 14/14 pass.

## Self-Check: PASSED
