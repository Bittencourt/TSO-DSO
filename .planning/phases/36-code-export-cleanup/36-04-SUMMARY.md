---
phase: 36-code-export-cleanup
plan: 04
subsystem: exports
tags: [breaking-change, exports, compat, public]
requires: [36-03]
provides:
  - Compat 4.10 direct dependency
  - curated export surface (91 names incl. module) plus Compat @compat public blocks
  - test/test_exports.jl snapshot testitem (tag :exports)
key-files:
  created:
    - test/test_exports.jl
    - .github/scripts/unexported_names.txt
  modified:
    - Project.toml
    - Manifest.toml
    - Manifest-v1.10.toml
    - Manifest-v1.11.toml
    - Manifest-v1.12.toml
    - docs/Manifest.toml
    - bench/Manifest.toml
    - src/TSODSO.jl
    - 36 src files (per-file export statements)
    - .planning/phases/36-code-export-cleanup/36-BREAKING-LEDGER.md
requirements-completed: []
completed: 2026-10-05
---

# Phase 36 Plan 04: Export trim, Compat public block, docstring Summary

Exports cut from 192 to 90 names (plus the module, 91 total), 85 advanced names declared `@compat public`, Compat promoted to a direct dependency, top-module docstring rewritten, and an export-surface snapshot test added. HYG-03 is NOT complete: plans 05-06 migrate tests, scripts and docs (the suite is intentionally red until plan 05).

## Commits
- d7b1e42: Compat direct dependency, manifests re-resolved
- deee68e: export trim, `@compat public` blocks, new module docstring, unexported name list, ledger entry
- 21ef5b0: `test/test_exports.jl`

## Details
- Manifests: only the project_hash, TSODSO `deps` list (+Compat) and, in the root `Manifest.toml`, `Manifest-v1.12.toml`, `docs/Manifest.toml` entries, the previously missing TSODSO extension lines changed. No package version moved. Resolved on 1.10.11, 1.11.9 and 1.12.5 (juliaup `release`; the `1.12` channel is 1.12.7 and bumped two stdlib JLLs, so it was not used). `Manifest.toml` was re-resolved in a scratch copy because `Manifest-v1.12.toml` takes precedence. `test/Manifest.toml` does not embed TSODSO and needed no change.
- Classification: all names not in the keep list were unexported (102). Tier I (no `public`, 17 names): record!, converged, admm_supported, per-unit helpers (I_base, Z_base, PerUnitBase, to_pu_impedance, to_pu_power, assert_magnitudes, assert_magnitudes_voltage), IEEE8500_* constants (4), FIT_lambda constants (3). Names not explicitly listed in the plan and classified as `public` (building blocks): assert_connected, markov_path, build_ieee123, sub_seed, hybrid_ratios, socp_gap_report, ac_dual_fallback_price, LADDER_ATTR_NAMES, RETRYABLE_STATUSES. The final count 91 matches the expected ~91 exactly.
- Duplicates (record!, set_rho!, set_rho_q!, solve_follower!) disappeared because both halves were unexported; the AST walk finds each exported name in exactly one file.
- Public declarations are in one block region at the end of `src/TSODSO.jl`, grouped by subsystem.

## Deviations from Plan

**1. [Rule 1 - Bug in plan verify] `names(TSODSO)` includes public names on Julia >= 1.11**
- The plan's verify command (`n ∉ Set(names(TSODSO))`) fails on 1.11+/1.12 because `names` lists public symbols too. The snapshot test and my verification filter with `Base.isexported`. Noted in the breaking ledger.

**2. Docstring check**: the new module docstring is ID-free; the remaining `plan 01-02` style comments in the include graph below it are untouched (out of the plan's scope).

## Verification
- `tag:exports` test: pass (12/12).
- `Aqua.test_all(TSODSO)`: all pass (undefined exports, stale deps, compat bounds incl. Compat, persistent tasks).
- TSODSO loads on 1.10.11 (91 names), 1.11.9, 1.12.5.
- Full suite not run (expected red until plan 05).

## Known Stubs
None.

## Self-Check: PASSED
