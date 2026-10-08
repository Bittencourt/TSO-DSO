---
phase: 32-declarative-power-flow-strategy-dispatch
verified: 2026-10-03T00:00:00Z
status: passed
score: 3/3 roadmap success criteria verified
overrides_applied: 0
---

# Phase 32: Declarative Power-Flow & Strategy Dispatch Verification Report

**Phase Goal:** Researcher can select the power-flow formulation and solve strategy declaratively through `Scenario`, dispatched via one common entry point.
**Status:** passed
**Re-verification:** No (initial)

## Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | pf selectable via `Scenario`; `run_scenario` honours it; nothing hard-coded to `ConvexBranchFlow()` | VERIFIED | `Scenario` has `pf::Symbol`, `pf_thesis_literal`, `pf_ε` (Scenario.jl:115-117). `run(::Centralized)` and `run(::ADMM)` call `build_powerflow(s_eff)` (run.jl:93,123) and pass `pf` to `solve_welfare`/`solve_admm`; AC uses `allow_local`; `exact_maxgap` NaN for non-SOC pf. `mpc_loop.jl:298` also uses `build_powerflow`. A grep of `src/experiments` finds no `ConvexBranchFlow()` constructor call outside docs/comments. Remaining `ConvexBranchFlow()` uses are in the powerflow/admm layers (internal delegation), not the scenario path. |
| 2 | Strategies are types dispatched through one `run(strategy, scenario)` returning a common shape | VERIFIED | `AbstractStrategy`, `Centralized`, `ADMM`, `MPC`, `Stochastic` (strategies.jl:15-126); package-owned `function run end` (not exported, avoids `Base.run`). Methods exist for all four: run.jl:88,118; mpc_loop.jl:1678; run_stochastic.jl:330. All return `ScenarioResult(scenario, welfare, dadp, exact_maxgap, elapsed, details)`, with typed `ADMMDetails`/`MPCDetails`/`StochasticDetails`. `run_scenario(s) = run(s.strategy, s)` is a thin wrapper. |
| 3 | `Scenario` no longer carries strategy-specific fields in a flat bag | VERIFIED | The struct fields are name, feeder, seed, T, population, price, allow_export, pf, pf_thesis_literal, pf_ε, strategy. There are no ρ/mpc_*/stoch_* fields. Legacy flat kwargs are mapped by an outer constructor. The `supports_pf` matrix rejects invalid strategy x pf combos with `ArgumentError`. |

**Score:** 3/3

## Requirements Coverage

| Requirement | Source Plans | Status | Evidence |
|-------------|--------------|--------|----------|
| ARCH-01 (declarative pf selection in `Scenario`) | 32-02, 32-03 | SATISFIED | Truth 1 |
| ARCH-02 (strategies as types, common entry point) | 32-01..32-04 | SATISFIED | Truths 2 and 3 |

Both IDs appear in the plan frontmatter and in REQUIREMENTS.md (lines 102/104 and the traceability table, lines 190-191). No orphaned requirements.
Bookkeeping: REQUIREMENTS.md still shows both as `[ ]` / `Pending`. Mark them complete at phase close.

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Strategy, pf and dispatch tests on HEAD 0e1b30a | TestItemRunner filtered to `test_strategies.jl` | 407 passed / 407 | PASS |

## Anti-Patterns

No `TBD`/`FIXME`/`XXX` markers in strategies.jl, run.jl, Scenario.jl, materialize.jl or store.jl. The code review (5 warnings: WR-01..05) was fully fixed per 32-REVIEW-FIX.md. WR-04 is an acknowledged residual: `Stochastic.probabilities` stays a mutable `Vector`, mitigated by re-validation at each run. This is informational, not blocking.

## Human Verification Required

None.

## Pending

Final full-suite confirmation on HEAD 0e1b30a is pending the orchestrator's detached run. The previous certified run at 03b91a5 was 31762 passed / 0 failed / 0 errored / 5 broken, with docs build exit 0. The review fixes were validation-only.

## Gaps Summary

No gaps. The phase goal is achieved in the codebase.

_Verified: 2026-10-03_
_Verifier: Claude (gsd-verifier)_

## Final Full-Suite Confirmation (orchestrator)

Full suite at HEAD 0e1b30a (post review fixes; log start 16:55:34 > commit 16:55:26):
**31782 passed / 0 failed / 0 errored / 5 broken** (31787 total, 28m35s). ADMM knife-edge canary
unchanged (`iters = 56`, `welfare = -4823.66604824162`). Docs build exit 0 at 03b91a5 (no docs
inputs changed since except a store.jl docstring line).
