---
phase: 05-distribution-pricing-dadp-dlmp-decomposition
plan: 01
subsystem: distribution-pricing
tags: [pricing, dlmp, socp, duals, welfare, surplus, seam, red-harness]
requires:
  - ConvexBranchFlow.contribute! (PF-03, plan 04-02) with named :cone/:vdrop/:cpydrop containers
  - solve_welfare (OPT-01, plan 03-05) + Aggregator.contribute! return (DEV-05, plan 03-05)
  - register_constraint! / ctx.constraints / ctx.meta (PF-01, plan 01-03)
provides:
  - "ctx.constraints[:cone|:vdrop|:cpydrop|:smax] — branch-flow SOCP constraint duals recoverable by name for the four-way DLMP decomposition (PRICE-02)"
  - "ctx.meta[:agg_net] — per-aggregator (bus, net=p_inject−Pdc, utility) stash for the social=prosumer+DSO surplus split (PRICE-03)"
  - "src/pricing/{dlmp,fit,checks,welfare}.jl on the include graph + four RED @testitem harness files"
affects:
  - plan 05-02 (decompose_dlmp reads the registered duals)
  - plan 05-03 (fit_baseline)
  - plan 05-04 (economic_direction_checks)
  - plan 05-05 (welfare_accounting reads ctx.meta[:agg_net])
tech-stack:
  added: []
  patterns:
    - "register_constraint! as a PURE wrap of an already-built named @constraint container (byte-identical feasible set)"
    - "anonymous filtered @constraint loop → named sparse branch-indexed container with an IDENTICAL predicate"
    - "isdefined-guarded RED @testitem harness (test_convex_branch_flow.jl convention)"
key-files:
  created:
    - src/pricing/dlmp.jl
    - src/pricing/fit.jl
    - src/pricing/checks.jl
    - src/pricing/welfare.jl
    - test/test_dlmp.jl
    - test/test_fit.jl
    - test/test_economic_direction.jl
    - test/test_pricing_welfare.jl
  modified:
    - src/powerflow/ConvexBranchFlow.jl
    - src/models/welfare_solve.jl
    - src/TSODSO.jl
    - test/test_convex_branch_flow.jl
    - test/test_welfare_solve.jl
decisions:
  - ":smax registered as a named sparse container keyed by BRANCH INDEX b (and t), NOT an (b,br) tuple, so decompose_dlmp (05-02) can index the congestion dual by branch on the root→j tree path (WARNING-2)"
  - "The :smax container predicate reproduces the prior anonymous loop's `B[b].smax < _SMAX_NO_LIMIT` guard EXACTLY, keeping the feasible set byte-identical (IEEE-13 golden + socp_maxgap unchanged)"
  - "The Task-2 agg_net GREEN behavioral test lives in test_welfare_solve.jl (co-located with the solve_welfare seam); the RED accounting harness lives in the DISTINCT test_pricing_welfare.jl"
metrics:
  tasks_completed: 3
  files_created: 8
  files_modified: 5
  tests_baseline_green: 598
  tests_red_harness: 8
  completed: 2026-07-18
---

# Phase 5 Plan 01: Additive Phase-4 Pricing Seam + RED Harness Summary

Registered the four SOCP branch-flow constraint duals (`:cone` 3.39, `:vdrop` 3.33, `:cpydrop` 3.43, `:smax` 3.36) and stashed each aggregator's net active injection + utility under `ctx.meta[:agg_net]`, making the Phase-4 welfare solve price-decomposable and surplus-splittable — additively, with the IEEE-13 golden and PF-04 exactness gate byte-identical — then wired the `src/pricing/` include graph and a four-file RED `@testitem` harness.

## What Was Built

- **Task 1 — branch-flow dual registration (`ConvexBranchFlow.contribute!`).** Added `register_constraint!(ctx, :cone, cone)`, `:vdrop`, `:cpydrop` as PURE wraps of the already-named `@constraint` containers. Converted the anonymous apparent-power `@constraint` loop into a named, branch-indexed sparse container `smax[b=1:nB, t=1:T; B[b].smax < _SMAX_NO_LIMIT]` (same `SecondOrderCone`, same filter predicate) and registered it as `:smax`. The four handles are now recoverable via `ctx.constraints`.
- **Task 2 — per-aggregator surplus stash (`solve_welfare`).** Captured each previously-discarded `contribute!(agg, ctx; T)` return and recorded `ctx.meta[:agg_net]` as a `Vector{NamedTuple}` of `(; bus, net = p_inject − Pdc, utility)` in aggregator order — the price-transfer term `p_agⱼ[t]` and utility the surplus split (05-05) needs. Purely additive: no change to residual writes, objective, balance registration, exactness gate, battery check, or the returned tuple.
- **Task 3 — include graph + RED harness.** Created four comment-only `src/pricing/{dlmp,fit,checks,welfare}.jl` seam stubs (SEAM/OWNER headers naming the downstream plan + planned exports), included them after `models/oracle.jl` in dependency order, and added four `isdefined`-guarded RED `@testitem` files whose names carry the `dlmp` / `fit` / `econ`+`direction` / `welfare`+`surplus` filter substrings.

## Correctness Nets Verified

- **IEEE-13 golden byte-identical.** The `ieee13`/`ground` items (`GOLDEN_V9_16`, `GOLDEN_WELFARE`, `GOLDEN_DADP16`, `GOLDEN_SUM_DADP`) and `ctx.meta[:socp_maxgap]` stay green after the `:smax` loop→container conversion — no feasible-set / objective / exactness drift.
- **Zero regressions.** 598 pre-existing + Task-1/2 additive tests pass; the only 8 failures are the intentional pricing REDs, each failing cleanly on the missing-symbol `isdefined` assertion (0 errored — no runner crashes).
- **`:smax` keyed by branch index.** Verified the sparse container holds `(1,1),(1,2)` and excludes the sentinel branch `(2,1)` — the branch-index convention decompose_dlmp (05-02) requires (WARNING-2).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] SparseAxisArray key access in the `:smax` @testitem**
- **Found during:** Task 1 (first full-suite run — 3 errored).
- **Issue:** The named filtered `:smax` container is a `JuMP.Containers.SparseAxisArray`; `keys(smax)` / `(1,1) in keys(smax)` throws because `size`/`axes` are unsupported for sparse containers.
- **Fix:** Assert membership via the underlying dict (`length(smax) == 2`, `haskey(smax.data, (1,1))`) instead of `keys`.
- **Files modified:** test/test_convex_branch_flow.jl
- **Commit:** 196fa19

## Known Stubs

The four `src/pricing/*.jl` files are INTENTIONAL comment-only seam stubs (this plan's deliverable) and the eight new pricing `@testitem`s are the INTENTIONAL RED harness. They are resolved by their owning Wave-2 plans (05-02 `extract_dlmp`/`decompose_dlmp`, 05-03 `fit_baseline`, 05-04 `economic_direction_checks`, 05-05 `welfare_accounting`). No stub blocks this plan's goal (the additive seam is live and green).

## Commits

- `196fa19` feat(05-01): register branch-flow constraint duals for DLMP decomposition
- `3b95f57` feat(05-01): stash per-aggregator net injection + utility for surplus split
- `0c4b51d` test(05-01): wire src/pricing include graph + RED @testitem harness

## Self-Check: PASSED

All 8 created source/test files and the SUMMARY exist on disk; all three task commits (196fa19, 3b95f57, 0c4b51d) are present in the git history.
