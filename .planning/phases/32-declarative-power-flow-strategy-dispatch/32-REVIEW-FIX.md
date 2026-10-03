---
phase: 32-declarative-power-flow-strategy-dispatch
fixed_at: 2026-10-03T00:00:00Z
review_path: .planning/phases/32-declarative-power-flow-strategy-dispatch/32-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 32: Code Review Fix Report

**Fixed at:** 2026-10-03
**Source review:** .planning/phases/32-declarative-power-flow-strategy-dispatch/32-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5
- Fixed: 5
- Skipped: 0

Verified with TestItemRunner per touched test file: test_strategies.jl (407 pass), test_experiments.jl (109 pass), test_mpc_loop.jl (356 pass), test_run_stochastic.jl (14 pass). Fixes are validation-only; no solver paths changed.

## Fixed Issues

### WR-01: `run_mpc` / `run_stochastic` bypass the strategy x pf support matrix

**Files modified:** `src/experiments/mpc_loop.jl`, `src/experiments/run_stochastic.jl`, `test/test_strategies.jl`
**Commit:** b89f8d5
**Applied fix:** wrappers rebuild the scenario via `with_strategy` when the substituted default strategy differs, re-running `supports_pf` (ArgumentError). Regression testitem added.

### WR-02: ADMM constructor accepts NaN and Inf knobs

**Files modified:** `src/experiments/strategies.jl`, `test/test_strategies.jl`
**Commit:** b1ad445
**Applied fix:** `isfinite` check on all five float knobs (ArgumentError) before sign checks.

### WR-03: `Scenario` `==` and `hash` disagree for `pf_ε = -0.0`

**Files modified:** `src/experiments/Scenario.jl`, `src/experiments/strategies.jl`, `test/test_strategies.jl`
**Commit:** 99853f2
**Applied fix:** normalize `-0.0` to `+0.0` (`x + 0.0`) for `Scenario.pf_ε` and `MPC.forecast_error` (the only zero-admitting float knobs; ADMM knobs require > 0).

### WR-04: `Stochastic.probabilities` mutable inside a value-hashed immutable

**Files modified:** `src/experiments/strategies.jl`, `src/experiments/run_stochastic.jl`, `test/test_strategies.jl`
**Commit:** 2f9aed3
**Applied fix:** took the review's "at minimum" option. Factored validation into `_check_probabilities`, used by the constructor and re-run at the start of `_run_stochastic`. The field stays a `Vector` (existing tests and docs compare it with `==`/`!==` against vectors). Flagged for human review: a fully immutable container was not adopted.

### WR-05: Filename-truncation fallback uses `Base.hash`

**Files modified:** `src/experiments/store.jl`, `test/test_experiments.jl`
**Commit:** a47e758
**Applied fix:** fallback now appends `_stable_hex64(codeunits(full))` (zero-padded 16 hex digits). Only names that hit the NAME_MAX fallback change.

---

_Fixed: 2026-10-03_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
