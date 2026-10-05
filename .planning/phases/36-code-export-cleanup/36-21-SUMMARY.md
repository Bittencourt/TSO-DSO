---
phase: 36-code-export-cleanup
plan: 21
subsystem: ci-hygiene
tags: [ci, guard, hygiene, python]
requires: ["36-20"]
provides:
  - "Fail-closed CI guard against planning identifiers (check_planning_ids.py)"
affects: [".github/workflows/CI.yml"]
tech-stack:
  added: []
  patterns: ["stdlib-only Python guard with --selftest, allowlist with stale-entry failure"]
key-files:
  created:
    - .github/scripts/check_planning_ids.py
    - .github/scripts/planning_id_allowlist.txt
  modified:
    - .github/scripts/planning_id_rules.py
    - .github/workflows/CI.yml
    - src/powerflow/RestrictedBranchFlow.jl
    - test/test_restricted_branch_flow.jl
    - test/test_planning_coupling.jl
    - test/test_planning_inexact_policy.jl
key-decisions:
  - "Scope is exactly the CONTEXT scope: src, ext, test, scripts, docs/literate, docs/make.jl, docs/src/*.md, README.md, .github/workflows/CI.yml; .planning/ excluded"
  - "Allowlist is empty (header comment only): no hit needed exemption"
requirements-completed: [HYG-01]
duration: ~25min
completed: 2026-10-05
---

# Phase 36 Plan 21: Planning-identifier CI guard Summary

Fail-closed guard (exit 0 clean, 1 hit or stale allowlist entry, 2 unreadable file or bad allowlist) over 243 tracked files, wired into the CI `format` job after the content-loss step.

## Tasks

1. Residual cleanup (commit 94b448c): renamed `_EXACT04_MEASURED_ε` to `_MEASURED_EXACTNESS_ε` (value `0.010189528427785532 * 1.25` unchanged, all uses in src and test updated; no hits in scripts/docs/ext). Trimmed trailing spaces from three `@testitem` names (test_planning_coupling.jl, test_planning_inexact_policy.jl x2). Formatted with format210.jl (2.10.2). AST diff: EQUAL for the two testitem files, DIFF only at the renamed identifier sites in the other two (expected); content-loss reports only the +8/+4 char identifier-length change.
2. Guard (ea05fe5): `check_planning_ids.py` with `--root`, `--allowlist`, path args and `--selftest` (14 positive rules, 9 negatives incl. 3-phase, T-24, IEEE-8500, 2026-10-04, 0.10-0.12, eq. 3.43, Gan-Low 2015, and 6 fail-closed cases: clean, hit, allowlisted, stale, malformed allowlist, undecodable file). `planning_id_rules.py` scope narrowed to `.github/workflows/CI.yml` and `docs/src` to `.md` only. Rules include the artifact path/name patterns, byte-identical and Pitfall N.
3. CI wiring (98a918b): step "Check for planning identifiers" in the format job; YAML parses.

## Verification

- `--selftest` OK; guard exits 0 over full scope; a temporary offending README line gave exit 1 with file:line (reverted).
- Targeted run of restricted_branch_flow, exactness, exactness_verdict, admm_exactness_default, knifeedge canary, planning_coupling, planning_inexact_policy: 228/228 pass. Canary and goldens not re-pinned.
- Full suite not rerun (only an identifier rename and test-name whitespace changed); last full suite p20 = 32202/0/0/5.

## Deviations from Plan

- Rule 3: the plan's guard file did not yet exist and scope per orchestrator differed from plan (CI.yml only rather than whole workflows dir); scope constants adjusted in the rules module.
- Allowlist file named `planning_id_allowlist.txt` per plan frontmatter (research doc says planning_ids_allowlist.txt).

## Known Stubs

None.

## Self-Check: PASSED

Files exist, commits 94b448c, ea05fe5, 98a918b present.
