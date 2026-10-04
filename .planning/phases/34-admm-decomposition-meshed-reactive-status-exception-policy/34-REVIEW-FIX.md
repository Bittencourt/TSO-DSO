---
phase: 34
fixed_at: 2026-10-04T00:00:00Z
review_path: .planning/phases/34-admm-decomposition-meshed-reactive-status-exception-policy/34-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 34: Code Review Fix Report

**Source review:** 34-REVIEW.md (scope: critical_warning). Info findings IN-01..IN-05 not in scope.

## Fixed Issues

### WR-01: `:report` swallow narrowed
**Files modified:** `src/planning/subproblem.jl`
**Commit:** 4a77eb7
**Applied fix:** handler now accepts only `CertificateError` with `kind === :socp_exact` under `:report`; garbled comment and docstring repaired. Verified `assert_socp_exact!` has a single verdict throw (other guards are ArgumentError/KeyError). Fixed: requires human verification (catch-condition logic).

### WR-02: `fit_baseline` retry keyed on typed status
**Files modified:** `src/pricing/fit.jl`
**Commit:** 5381651
**Applied fix:** `SolveFailedError` with `termination_status == ALMOST_OPTIMAL`, with the legacy `ErrorException` message-match kept as fallback only. Fixed: requires human verification.

### WR-03: typed `SolveFailedError` kept in ac_recheck and MPC AC settlement
**Files modified:** `src/planning/ac_recheck.jl`, `src/experiments/mpc_loop.jl`, `test/test_planning_ac_recheck.jl`, `docs/src/status_policy.md`
**Commit:** 0e0cd91
**Applied fix:** both sites throw `SolveFailedError(msg, model)` (message text byte-identical); the existing test now expects `SolveFailedError`; policy inventory updated.

### WR-04: 4Q gate mirrors battery warn-gate
**Files modified:** `src/admm/AgrOpt.jl`, `src/admm/admm_state.jl`, `test/test_admm_generic_pf.jl`
**Commit:** b8556b6
**Applied fix:** new `report_4q` kwarg on `solve_agr!` (default `false`), set by `_report_4q(st)` = non-SOCP. ConvexBranchFlow, RestrictedBranchFlow and MeshedFlow are all SOCP, so no currently-passing SOCP run changes. New `@testitem` covers the trait and the kwarg. Fixed: requires human verification (policy logic).

## Verification
Foreground runs, all green: admm_generic_pf, admm_knifeedge_canary, admm_meshed, admm_phases, tsodso_errors, status_policy, planning_ac_recheck, planning_inexact_policy (311/311); fit, pricing_fit, alpha_bounds_stackelberg, feasibility_oracle, benders_integer, nash_integer (221/221); mpc_loop (369/369). Knife-edge canary not re-pinned; no golden changed.

---
_Fixer: Claude (gsd-code-fixer)_


## Orchestrator disposition (after iteration-2 re-review)

Iteration 2: 0 critical, 0 warning, 3 info — all four warnings verified fixed. Loop stopped.
IN-06 (stale ErrorException docstrings), IN-07 (non-failing 4Q test), IN-08 (remaining untyped
solver failures in fit.jl:612 / benders.jl:590,680) DEFERRED to Phase 36 (Code & Export Cleanup),
recorded in 34-CONTEXT.md <deferred>.
