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
  warning: 6
  info: 4
  total: 10
status: issues_found
---

# Phase 33: Code Review Report

**Depth:** standard. I read the full diff of the core, powerflow, devices and models files, and spot-checked the pricing, planning and admm callers.

## Summary

I found no outright blockers.

- **Dispatch:** The dispatch design is sound. The `MeshedFeeder` and `Feeder` methods for Convex, Restricted and LinDist are disjoint, so there are no ambiguities.
- **Internal delegation:** Restricted and MeshedFlow correctly go through `_contribute_convex!` rather than the radial-only public method.
- **`close_balance!`:** It matches the old inline blocks in operation order, anonymous naming and `label` handling. I found no consumer that looks up `model[:balance_*]` (the only `object_dictionary` hit is `nash.jl:1487`, which unregisters names that `contribute!` newly adds).
- **Typed fields:** `_require_*` are used on the reader side in most places.
- **Gaps:** The remaining problems are fail-open behaviour in the new trait gate, a behaviour change in `has_reactive` against the old `haskey(:Rq)`, silently defaulting reads that survived the migration, and a weak migration gate.

## Warnings

### WR-01: `has_branch_current` fails open, and the gate depends on `ctx.pf`, which is only set by `contribute!`
**File:** `src/powerflow/AbstractPowerFlow.jl:50-51` (used at `src/models/welfare_solve.jl:264`, `src/pricing/dlmp.jl:112`, `src/planning/subproblem.jl:352`, `src/pricing/fit.jl:522`, `src/models/stochastic_welfare.jl:433`)
**Issue:** The old gate was data-driven, `:l in keys(pf_vars)`, so it could not miss a cone. The new gate defaults to `false` for any `AbstractPowerFlow`. Two cases silently skip the SOCP exactness certificate and the `_assert_priceable` refusal:
1. A new or third-party formulation that stashes `l` but forgets the trait method.
2. A context whose `pf_vars` was populated without `ctx.pf` being set (hand-built contexts, tests).

`ctx.pf` is also last-writer-wins. `pf_vars` is never cleared when a second `contribute!` (for example DC) runs on the same ctx, so `pf` and `pf_vars` can disagree.
**Fix:** Keep the trait, but add a consistency guard: a helper that checks `has_branch_current(ctx.pf) == (ctx.pf_vars !== nothing && haskey(ctx.pf_vars, :l))` and errors loudly on disagreement ("implement has_branch_current for this formulation"), used at the five gate sites. Also reset `ctx.pf_vars = nothing` at the start of each `contribute!`.

### WR-02: `has_reactive(pf)` is not equivalent to the old `haskey(ctx.residuals, :Rq)`, and the two mechanisms now coexist
**File:** `src/models/linear_solve.jl:137`, `src/models/welfare_solve.jl:179`, `src/models/mpc_window.jl:189`, `src/models/stochastic_welfare.jl:313,636`; remaining `haskey` sites at `src/planning/master.jl:265`, `src/planning/feasibility_oracle.jl:130`, `src/planning/bilevel_kkt.jl:388`, `src/planning/nash.jl:1516`, `src/pricing/fit.jl:473,547`
**Issue:** `Aggregator.contribute!` always writes `:Rq` (`src/devices/Aggregator.jl:236`), including under DC.
- Old `solve_linear` evaluated `haskey` after the aggregators had written, so DC plus an aggregator closed `balance_q`. New code does not close it.
- For DC, the device reactive injections (`q_inject`, `FourQuadBESS`, `FixedCapacitor`) then stay in an unclosed `:Rq` residual and are silently ignored.
- In the sites that kept `haskey`, a nonstandard `pf` that does not write `:Rq` would disagree with `has_reactive`'s default `true`.

If DC plus a reactive device is a legitimate configuration, the old and new behaviour diverge without a test. If it is not, it should raise.
**Fix:** Migrate the remaining `haskey(ctx.residuals, :Rq)` sites to `has_reactive(pf)`, so there is one source of truth. Add a loud check (for example in `close_balance!` or in the builders) that errors when `!has_reactive(pf)` but `haskey(ctx.residuals, :Rq)` and any reactive device is present. Add a test for DC combined with `FixedCapacitor` or `FourQuadBESS`.

### WR-03: `welfare_accounting` no longer detects a missing objective
**File:** `src/pricing/welfare.jl:82`, `src/pricing/welfare.jl:126`
**Issue:** The required-key loop dropped `:objective` and `:feeder`. `ctx.objective` is now a non-optional field that defaults to `zero(QuadExpr)`. A ctx with no aggregators contributing therefore yields `util = value(zero) = 0` and a plausible-looking but wrong prosumer/DSO split. The same silent-zero risk applies to `@objective(model, Max, ctx.objective - ...)` in `master.jl:293`, `subproblem.jl:212` and `mpc_window.jl:262`, which previously raised `KeyError` when `:objective` was missing.
**Fix:** In `welfare_accounting`, require a nontrivial objective (`isempty(ctx.agg_device_vars)` or `iszero(ctx.objective)` → `ArgumentError`). Do the same in builders that expect at least one aggregator.

### WR-04: `economic_direction_checks` silently defaults an unset feeder
**File:** `src/pricing/checks.jl:123-124`
**Issue:** `feeder = ctx.feeder` followed by `feeder !== nothing ? feeder.root : 0` reads the raw field and falls back to `root = 0`. The root bus is then included in the scan, which skews the extremal deviations. This is the silent-default pattern the checked accessors were introduced to remove (migrated verbatim from `get(ctx.meta, :feeder, nothing)`).
**Fix:** Use `_require_feeder(ctx)` when `dadp === nothing`. Only skip the feeder lookup when a `dadp` override is supplied.

### WR-05: `close_balance!` gives opaque failures for a missing or wrongly shaped residual
**File:** `src/core/balance.jl:45`, `src/core/balance.jl:57`
**Issue:**
- `ctx.residuals[:Rp]` raises a bare `KeyError` when no formulation or aggregator has contributed; same for `:Rq` when `reactive=true` but the formulation did not write it (more likely given WR-02).
- A scalar `AffExpr` residual makes `size(...)` throw a `MethodError`, bypassing the "index escaped the feeder" message.
- `N` and `T` are not validated; `T = 0` silently builds empty containers.

**Fix:** `r = get(ctx.residuals, :Rp, nothing); r isa Matrix{AffExpr} || error("$(label)residual :Rp missing or not an indexed Matrix{AffExpr} (got $(typeof(r)))")`; same for `:Rq`; add `N > 0 && T > 0 || throw(ArgumentError(...))`.

### WR-06: Migration gate is weak and can pass vacuously
**File:** `test/test_model_context_migration_gate.jl:3,22-25`
**Issue:**
- The regex only matches `meta[:key` and `meta, :key`. It misses `meta[ :T]`, `meta[Symbol("T")]`, `getindex(ctx.meta, :T)`, iteration over a key tuple such as `for k in (:feeder, :T)` followed by `ctx.meta[k]` (exactly the `welfare.jl` hidden reader found in Plan 33-10), and `meta.key`.
- `isdir(dir) || continue` makes the scan pass if every directory is missing. No assertion confirms that files were actually scanned.
- `docs/writeups` is not scanned and still contains `ctx.meta[:agg_device_vars]` at `docs/writeups/FRAMEWORK_GUIDE.html:1420`.

**Fix:** Count files scanned and `@test nfiles > 50`. Broaden the regex to `meta\[\s*:(…)`. Add a second pass flagging any `ctx.meta[<variable>]` / `get(…meta, <variable>` whose key is not a literal symbol. Update or scan the writeups.

## Info

### IN-01: Abstract field types defeat type stability
**File:** `src/core/ModelContext.jl:68-71`
**Issue:** `feeder::Union{Nothing,AbstractFeeder}`, `pf::Union{Nothing,AbstractPowerFlow}`, `pf_vars::Union{Nothing,NamedTuple}` are abstract; accesses dynamically dispatch. Acceptable for build-time code per CLAUDE.md; worth a JET check in hot loops (`solve_admm`, `mpc_loop`).
**Fix:** Optional function barriers, or parametrize later.

### IN-02: `DCPowerFlow.contribute!` signature does not match its docstring
**File:** `src/powerflow/DCPowerFlow.jl:30,45`
**Issue:** Docstring says `feeder::AbstractFeeder`, method has untyped `feeder`. It also does not touch `pf_vars`, which can leave stale data from an earlier formulation (see WR-01).
**Fix:** Type it as `feeder::AbstractFeeder`.

### IN-03: `_require_T` only rejects zero
**File:** `src/core/ModelContext.jl:98`
**Issue:** A negative `ctx.T` passes.
**Fix:** Use `ctx.T <= 0`.

### IN-04: Partial state on a failed `contribute!`
**File:** `src/powerflow/RestrictedBranchFlow.jl:218-323`, `src/powerflow/MeshedFlow.jl:79-82`
**Issue:** `_contribute_convex!` sets `pf_vars` before Restricted's bound shrinking runs. If a later step throws, the ctx holds `pf_vars` but `pf === nothing`, so a reused ctx fails open. Also `ctx.meta[:formulation]` is never set by Restricted, so Restricted contexts report `:unknown` in `restriction_exactness.jl:119` / `mesh_angle_certificate.jl:118`.
**Fix:** Set `ctx.pf` before the formulation-specific steps, or wrap them in try/finally; consider deriving the formulation label from `ctx.pf`.
