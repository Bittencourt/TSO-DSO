---
phase: 33
fixed_at: 2026-10-04T00:00:00Z
review_path: .planning/phases/33-shared-abstractions-feeder-balance-model-context/33-REVIEW.md
iteration: 1
findings_in_scope: 6
fixed: 6
skipped: 0
status: all_fixed
---

# Phase 33: Code Review Fix Report

**Fixed at:** 2026-10-04
**Source review:** .planning/phases/33-shared-abstractions-feeder-balance-model-context/33-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 6
- Fixed: 6 (WR-02 as "verified no divergence", safe parts only)
- Skipped: 0

Verification: test batches (close_balance, traits, migration gate, toy_dc, linear/welfare solve, dlmp, welfare pricing, exactness, fit, AC, planning master/feasibility/bilevel/nash/inexact, stochastic, mpc_window, run_stochastic, knife-edge canary) all green, 0 failures.

## Fixed Issues

### WR-01: has_branch_current fails open
**Files modified:** `src/core/ModelContext.jl`, `src/powerflow/DCPowerFlow.jl`, `src/models/welfare_solve.jl`, `src/pricing/dlmp.jl`, `src/planning/subproblem.jl`, `src/pricing/fit.jl`, `src/models/stochastic_welfare.jl`, `test/test_model_context_traits.jl`
**Commit:** 63b2665
**Applied fix:** New `has_branch_current(ctx::ModelContext)` compares the `ctx.pf` trait against `pf_vars` carrying `:l` and throws `ArgumentError` on disagreement; the five gate sites use it. `DCPowerFlow.contribute!` now clears `ctx.pf_vars` (the other formulations overwrite it). A resetting call in every `contribute!` was not added since only DC leaves a stale stash. Regression `@testitem`s added. Also covers IN-02 (typed `feeder::AbstractFeeder`) and IN-03 (`_require_T` rejects `T <= 0`). Requires human verification (logic gate).

### WR-02: has_reactive vs haskey(:Rq)
**Files modified:** `src/planning/master.jl`, `src/planning/feasibility_oracle.jl`, `src/planning/bilevel_kkt.jl`, `src/planning/nash.jl`, `src/pricing/fit.jl`
**Commits:** 2e69e8c, 63b2665 (fit.jl)
**Applied fix:** Verified against `0e1b30a`: the old `linear_solve` devices wrote only `:Rp`, and `welfare_solve`/`mpc_window`/`stochastic_welfare` captured `haskey(:Rq)` right after the formulation, before aggregators ran. So there was NO behaviour divergence. All concrete formulations (LinDist, Convex, Restricted, Meshed via `_contribute_convex!`, AC) write `:Rq` iff `has_reactive`, DC neither; so the remaining planning/fit `haskey` sites (all captured right after `contribute!`, with typed `pf::AbstractPowerFlow`) were migrated to `has_reactive(pf)` as provably equivalent. The existing trait-agreement test already asserts `has_reactive(pf) == haskey(:Rq)` for all six. The proposed loud guard for DC + reactive device was NOT added: DC + aggregator legitimately writes an unclosed `:Rq` in today's solving models (documented active-only behaviour), so a guard would change existing solves.

### WR-03: welfare_accounting misses an absent objective
**Files modified:** `src/pricing/welfare.jl`
**Commit:** c0172ce
**Applied fix:** `ArgumentError` when `ctx.agg_device_vars` is empty. Regression test lives in `test/test_model_context_traits.jl`. The builders' `@objective(... ctx.objective ...)` sites (master, subproblem, mpc_window) were left unchanged since zero-aggregator builds may be legitimate and a guard there could change solving models.

### WR-04: economic_direction_checks silent feeder default
**Files modified:** `src/pricing/checks.jl`
**Commit:** 481ad28
**Applied fix:** `root = dadp === nothing ? _require_feeder(ctx).root : 0`. No dedicated regression test (the path requires a solved ctx before reaching the line).

### WR-05: close_balance! opaque failures
**Files modified:** `src/core/balance.jl`, `test/test_close_balance.jl`
**Commit:** 2ad5329
**Applied fix:** `_check_residual` helper throws `ArgumentError` for a missing / non-`Matrix{AffExpr}` residual; `N`/`T` must be positive. Shape-mismatch message unchanged (existing test passes). Regression tests added.

### WR-06: weak migration gate
**Files modified:** `test/test_model_context_migration_gate.jl`
**Commit:** b955aa4
**Applied fix:** Regex accepts `meta[ :key`; asserts more than 50 files scanned; non-vacuity test extended. The dynamic-key second pass and `docs/writeups` scanning were not added (the writeups HTML is generated/historical and a variable-key scan would produce false positives on legitimate keys).

## Not in scope

Info findings IN-01 and IN-04 were not attempted (fix_scope critical_warning); IN-02/IN-03 were fixed incidentally in the WR-01 commit.

---

_Fixed: 2026-10-04_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_

## Orchestrator disposition (after iteration-2 re-review)

Iteration-2 re-review: 0 critical, 1 warning, 4 info; all six iteration-1 warnings verified fixed with
no numeric change. The --auto loop was STOPPED at iteration 2 (not run to 3):

- **WR-01 (iter 2): no `has_reactive` consistency guard; DC + reactive device leaves `:Rq` unclosed silently.**
  Pre-existing behaviour (identical before Phase 33, not a regression). A hard guard would alter
  currently-solving DC+aggregator models, which this pure-refactor phase must not do. DEFERRED to
  Phase 34 (ARCH-08 status/exception policy), with a pinning test to be added there.
- IN-01..IN-04 accepted as info (zero-objective builder sites, dynamic-key gate scan, WR-04 path
  test, stale fit.jl:300 comment / abstract field types).
