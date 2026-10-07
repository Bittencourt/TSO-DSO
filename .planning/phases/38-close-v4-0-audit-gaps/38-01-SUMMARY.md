---
phase: 38-close-v4-0-audit-gaps
plan: 01
subsystem: exactness-certificate
tags: [socp-exactness, refactor, shared-kernel, gap-closure]
requires: []
provides:
  - "_socp_cone_check(ctx; rtol, atol, ε, τ_solver) -> (; maxgap, maxratio): the one non-throwing cone-exactness kernel (for plans 02 MPC first tier and 04 OOS step)"
  - "assert_socp_exact! = own head-branch pre-check + kernel + unchanged throw"
  - "38-MEASUREMENTS.md phase evidence ledger"
affects: [38-02, 38-04]
tech-stack:
  added: []
  patterns: ["non-throwing kernel + throwing gate wrapper"]
key-files:
  created:
    - .planning/phases/38-close-v4-0-audit-gaps/38-MEASUREMENTS.md
  modified:
    - src/models/exactness.jl
    - test/test_exactness.jl
decisions:
  - "Kernel zero-match ArgumentError uses a caller-neutral 'SOCP exactness check:' prefix; assert_socp_exact! keeps its verbatim 'assert_socp_exact!:'-prefixed pre-check"
  - "Kernel is internal (underscore), not exported, not in the public list"
metrics:
  duration: ~10min
  completed: 2026-10-07
  tasks: 2
  files: 3
requirements: [FIX-08]
---

# Phase 38 Plan 01: Shared non-throwing SOCP cone-check kernel Summary

The `assert_socp_exact!` loop over `_cone_row` now lives in a single internal kernel. `_socp_cone_check` returns a concrete `(; maxgap, maxratio)` without throwing. `assert_socp_exact!` calls it and throws as before, so its verdict, return value and message are unchanged. The MPC first tier and the out-of-sample (OOS) step can now reuse the library's cone arithmetic instead of carrying their own copy.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 (RED) | Failing parity assertions | 28f5c71 | test/test_exactness.jl |
| 1 (GREEN) | Kernel + delegating gate + ledger | d88649d | src/models/exactness.jl, 38-MEASUREMENTS.md |
| 2 | Consumer sweep + format | (no commit: formatter produced no changes) | — |

## Verification

- RED: 2 errored (`UndefVarError: _socp_cone_check`), 20 passed.
- `file:test_exactness.jl,test_admm_exactness_default.jl`: 62/62 pass (11 items).
- `file:test_exactness.jl,test_admm_exactness_default.jl,test_welfare_solve.jl,test_mesh_flow.jl`: 206/206 pass (18 items).
- `check_planning_ids.py`: OK. `format210.jl` then `check_content_loss.py HEAD`: OK, no diff. `git diff --quiet`: clean.
- The `function _socp_cone_check` definition appears exactly once. `scripts/jet_baseline.txt` has 0 entries for exactness.jl. The kernel's accumulators start at `0.0` and are updated only with `max` of Float64 values, so the returned NamedTuple is concrete.

## Test delta (test_exactness.jl, Julia 1.12.5 filtered run)

@testitems 6 -> 6; Pass 20 -> 28. Eight parity assertions were added inside 2 existing items: on the exact point, the kernel's maxgap equals the gate's return value, its maxratio equals the `hybrid_ratios` maximum, and maxratio <= 1. On the small-smax slack point, the kernel returns maxratio > 1 without throwing, the gate still throws `CertificateError` with `kind === :socp_exact` and the same message prefix, and the kernel's flat-atol override matches `hybrid_ratios`.

## Deviations from Plan

- Added a `@test err.value.kind === :socp_exact` assertion beyond the four listed behaviours. It pins threat T-38-01 (certificate kind unchanged).
- The `_socp_head_branch` one-line comment now points to the rationale inside `_socp_cone_check`, because the long comment block moved there with the code.

Otherwise the plan was executed as written.

## Self-Check: PASSED

- FOUND: src/models/exactness.jl (`function _socp_cone_check`), test/test_exactness.jl, 38-MEASUREMENTS.md
- FOUND commits: 28f5c71, d88649d
