---
phase: 33-shared-abstractions-feeder-balance-model-context
reviewed: 2026-10-04T00:00:00Z
depth: standard
files_reviewed: 44
files_reviewed_list:
  - src/TSODSO.jl
  - src/core/ModelContext.jl
  - src/core/balance.jl
  - src/data/Feeder.jl
  - src/data/MeshedFeeder.jl
  - src/powerflow/AbstractPowerFlow.jl
  - src/powerflow/ConvexBranchFlow.jl
  - src/powerflow/RestrictedBranchFlow.jl
  - src/powerflow/MeshedFlow.jl
  - src/powerflow/LinDistFlow.jl
  - src/powerflow/DCPowerFlow.jl
  - src/powerflow/ACPowerFlow.jl
  - src/devices/Aggregator.jl
  - src/devices/AbstractDevice.jl
  - src/devices/FixedCapacitor.jl
  - src/admm/AgrOpt.jl
  - src/admm/DsoOpt.jl
  - src/admm/solve_admm.jl
  - src/models/welfare_solve.jl
  - src/models/linear_solve.jl
  - src/models/mpc_window.jl
  - src/models/stochastic_welfare.jl
  - src/models/exactness.jl
  - src/models/restriction_exactness.jl
  - src/models/complementarity_4q.jl
  - src/models/ac_oracle.jl
  - src/models/oracle.jl
  - src/models/mesh_angle_certificate.jl
  - src/models/toy_dc.jl
  - src/pricing/dlmp.jl
  - src/pricing/fit.jl
  - src/pricing/welfare.jl
  - src/pricing/checks.jl
  - src/planning/subproblem.jl
  - src/planning/feasibility_oracle.jl
  - src/planning/master.jl
  - src/planning/bilevel_kkt.jl
  - src/planning/nash.jl
  - src/planning/ac_recheck.jl
  - src/experiments/mpc_loop.jl
  - src/experiments/run_stochastic.jl
  - test/test_abstract_feeder.jl
  - test/test_close_balance.jl
  - test/test_model_context_traits.jl
  - test/test_model_context_migration_gate.jl
findings:
  critical: 0
  warning: 1
  info: 4
  total: 5
status: issues_found
---

# Phase 33: Code Review Report (iteration 2)

**Reviewed:** 2026-10-04
**Depth:** standard
**Files Reviewed:** 44
**Status:** issues_found

## Summary

I re-read the six fix commits (2e69e8c, 63b2665, c0172ce, 481ad28, 2ad5329, b955aa4) against the iteration-1 findings.

- **Numeric results:** None of the fixes changes a numeric result.
  - The edits are gate or guard logic, `has_reactive(pf)` substitutions, a stash clear on DC, and validation that runs before constraints are built.
  - `close_balance!` still builds the same constraints in the same order.
  - `_check_residual` only adds validation in front of the unchanged shape check.
- **Gate sites:** All five gate sites now call `has_branch_current(ctx)`. No `has_branch_current(x.pf)` call remains in `src/`.
- **Trait methods:** `has_branch_current` is `true` for Convex, Restricted, Meshed and AC. The default is `false`, and `Nothing` is `false`.
- **Guard consistency with each `contribute!`:**
  - Convex, Restricted and Meshed set `pf_vars` including `:l` and `ctx.pf`.
  - LinDist and DC give `false` with no `:l`.
  - AC stashes `(; v, P, Q, l)`.
- **Failure mode:** A failed mid-way `contribute!` (the iteration-1 IN-04 partial-state case) now throws loudly through the guard instead of failing open.
- **Fixer's WR-02 claim:** I checked it and it holds. Every `has_reactive(pf)` substitution reads the same `pf` object that was passed to `contribute!` immediately before. This includes `fit.jl:547`, which uses `ac`, and `nash.jl`, which uses `specs[i].pf`. For every concrete formulation, `has_reactive(pf)` equals `haskey(:Rq)` at that point.

## Verification of iteration-1 fixes

| ID | Verdict | Notes |
|----|---------|-------|
| WR-01 | Fixed | The `ctx` guard works, DC clears the stale `pf_vars`, and the tests cover the disagreement, consistent and DC-reset cases. The trait is still opt-in for third-party formulations, but a mismatch is now loud. |
| WR-02 | Accepted | There is no behaviour divergence, as the fixer verified. See WR-01 below for the residual asymmetry. |
| WR-03 | Partially fixed | `welfare_accounting` is guarded. The builder `@objective` sites are unguarded; this was a deliberate choice. See IN-01. |
| WR-04 | Fixed | `_require_feeder(ctx).root` is used only when `dadp === nothing`, which is the case where it matters. There is no dedicated test. |
| WR-05 | Fixed | `_check_residual` raises `ArgumentError` for a missing or non-`Matrix{AffExpr}` residual and for non-positive N/T. The existing shape-mismatch message is preserved. |
| WR-06 | Partially fixed | The regex now accepts `meta[ :key` and the non-vacuity count is asserted. See IN-02. |
| IN-02, IN-03 | Fixed | The DC signature is typed and `_require_T` rejects `T <= 0`. |
| IN-04 | Partly retracted | `RestrictedBranchFlow` does set `ctx.meta[:formulation]` (line 322), so the `:unknown` claim in iteration 1 was wrong. The partial-state concern is now mitigated by the guard. |

## Warnings

### WR-01: `has_reactive` has no consistency guard, unlike `has_branch_current`
**File:** `src/powerflow/AbstractPowerFlow.jl:43` (consumers `src/models/linear_solve.jl:137`, `welfare_solve.jl:179`, `mpc_window.jl:189`, `stochastic_welfare.jl:313,636`)
**Issue:**
- The default `has_reactive(::AbstractPowerFlow) = true` is trusted everywhere, and the data-driven `haskey(:Rq)` fallback is gone.
- A formulation that does not write `:Rq` fails loudly through `close_balance!` (WR-05), so that case is safe.
- The opposite case is silent. `DCPowerFlow` reports `false`, but `Aggregator.contribute!` still writes `:Rq`, including under DC. Under DC with a reactive device (`q_inject`, `FourQuadBESS`, `FixedCapacitor`) those injections therefore go into an unclosed residual and are dropped with no diagnostic. This is the same behaviour as before the migration, so it is not a regression. It remains a silent-ignore path with no test pinning it.

**Fix:** Add a test, or an explicit `@warn` or `ArgumentError` in the builders, for `!has_reactive(pf)` combined with `haskey(ctx.residuals, :Rq)` and a reactive device present. The fixer's concern about changing existing solves is valid, so a pinning test documenting the current "active-only, reactive ignored" behaviour is the minimum.

## Info

### IN-01: Builder `@objective(... ctx.objective ...)` sites still accept the default zero objective
**File:** `src/planning/master.jl:293`, `src/planning/subproblem.jl:212`, `src/models/mpc_window.jl:262`
**Issue:** These sites previously raised `KeyError` for a missing `:objective`. They now silently take `zero(QuadExpr)`. The fixer left them on purpose because zero-aggregator builds may be legitimate. Zero aggregators gives a feasibility-only model, so the risk is small.
**Fix:** Optionally add a one-line comment at each site stating that a zero objective is intentional.

### IN-02: Migration gate still has known blind spots
**File:** `test/test_model_context_migration_gate.jl:3`
**Issue:** The gate does not catch the dynamic-key access `for k in (:feeder, :T); ctx.meta[k]`, `meta.key`, or `docs/writeups`. The fixer's rationale is acceptable, since the writeups are generated HTML. The first two are the pattern that hid a reader in Plan 33-10.
**Fix:** Optionally add a narrow second pass that flags `meta\[[a-z_]+\]` inside the same file as one of the five key names.

### IN-03: No regression test for the WR-04 path
**File:** `src/pricing/checks.jl:123`
**Issue:** `economic_direction_checks` with `dadp === nothing` and an unset feeder is untested. The change is trivial.
**Fix:** Add a short `@test_throws ArgumentError` using a hand-built ctx that has `:balance_p` registered but no feeder.

### IN-04: Stale documentation and abstract field types
**File:** `src/pricing/fit.jl:300`, `src/core/ModelContext.jl:68-71`
**Issue:**
- The `fit.jl` doc comment still cites `has_branch_current(ctx.pf)`. The gate is now `has_branch_current(ctx)`.
- The abstract field types from the old IN-01 are unchanged. That is acceptable for build-time code.

**Fix:** Update the comment.

---

_Reviewed: 2026-10-04_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
