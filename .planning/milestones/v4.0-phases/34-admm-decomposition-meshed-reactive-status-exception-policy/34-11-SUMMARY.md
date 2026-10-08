---
phase: 34-admm-decomposition-meshed-reactive-status-exception-policy
plan: 11
subsystem: docs
tags: [docs, status-policy, exceptions, meshed, admm, julia]
requires: ["34-10"]
provides:
  - "docs/src/status_policy.md (@id status-policy), linked from the five entry-point docstrings"
  - "Rung 10 page: live meshed ADMM vs centralized duals, self-checking; MESH-06 advisory closed in docs"
affects: []
key-files:
  created: [docs/src/status_policy.md]
  modified: [docs/make.jl, docs/literate/meshed_reactive_price.jl, docs/literate/admm.jl, src/admm/solve_admm.jl, src/planning/benders.jl, src/planning/nash.jl, src/experiments/mpc_loop.jl, src/experiments/run_stochastic.jl, src/core/errors.jl]
key-decisions:
  - "Status table rendered from TSODSO.STATUS_VOCABULARY via an @example block (cannot drift)"
requirements-completed: []
duration: ~25min
completed: 2026-10-04
---

# Phase 34 Plan 11: Status & exception policy docs Summary

One policy page (THROW vs RETURN, exception-type table, STATUS_VOCABULARY-rendered status table, ARCH-09 handler rule, deferred ErrorException/catch inventory, `has_reactive` rule), linked from `solve_admm`, `solve_stackelberg!`, `run_nash!`, `run_mpc`, `run_stochastic`; Rung 10 now runs meshed live-reactive ADMM beside the centralized `:balance_q` dual.

## Commits
- 0245e7d docs(34-11): status & exception policy page and entry-point docstring links
- 4e279d2 docs(34-11): meshed page runs live ADMM vs centralized, closes MESH-06

## Verification (foreground)
- Docstring-link smoke: `links OK`.
- Canary + test_status_policy + test_tsodso_errors: 83/83 pass (canary untouched).
- `meshed_reactive_price.jl` under docs env: executes; live gaps gap_p 3.4e-6, gap_q 2.3e-5, rel welfare gap 2.4e-7, status `:converged`. `admm.jl` executes (`admm page OK`).
- `git diff b955aa4.. -- src | grep "export.*build_"`: empty. src diff reviewed: only docstring/comment lines (one comment line reworded in errors.jl).
- New exports (TSODSOError, SolveFailedError, CertificateError, ConvergenceError, admm_supported) have docstrings and are surfaced by existing api.md `@autodocs` Pages (core/errors.jl, admm/admm_state.jl); api.md unchanged.
- Full docs build NOT run here (can exceed the foreground budget); left to the orchestrator's Plan 12 gate. The `@example` block in status_policy.md (uses Markdown) was therefore not executed standalone.

## Deviations from Plan
**1. [Rule 1 - Bug] Phase-23 page triangle check broke after typed-exception migration**
- **Found during:** Task 2 page execution
- **Issue:** `triangle_infeasible` tested `e isa ErrorException`, but `solve_welfare` now throws `SolveFailedError`, so the existing WR-02 self-check fired.
- **Fix:** test `e isa SolveFailedError` (message check unchanged); comment updated.
- **Files:** docs/literate/meshed_reactive_price.jl; **Commit:** 4e279d2

## Known Stubs
None.

## Self-Check: PASSED
REQUIREMENTS.md intentionally untouched.
