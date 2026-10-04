---
phase: 33-shared-abstractions-feeder-balance-model-context
plan: 08
subsystem: core
tags: [ARCH-07, ModelContext, typed-reads, has_branch_current]
requires: [33-06]
provides:
  - src/pricing, src/planning, src/experiments, RestrictedBranchFlow read typed ctx fields
  - last three haskey(pf_vars, :l) gates replaced by has_branch_current(ctx.pf)
affects: [33-10]
key-files:
  modified: [src/pricing/dlmp.jl, fit.jl, welfare.jl, checks.jl, src/planning/subproblem.jl, ac_recheck.jl, master.jl, nash.jl, src/experiments/mpc_loop.jl, run_stochastic.jl, src/powerflow/RestrictedBranchFlow.jl, test/test_pricing_dlmp.jl, test/fixtures_phase19.jl]
decisions:
  - pf_vars/feeder/T reads use _require_*; objective/agg_device_vars read typed fields directly; checks.jl tolerant feeder read became ctx.feeder
metrics:
  tasks: 3
completed: 2026-10-03
---

# Phase 33 Plan 08: Typed reads in pricing/planning/experiments Summary

All reads (code, kwarg defaults, docstrings, comments) of `meta[:pf_vars|:feeder|:T|:objective|:agg_device_vars]` in the target files now use typed fields; only TRANSIENT-MIRROR lines remain (grep verified).

- Gates: `_assert_priceable` (dlmp.jl), `has_cone` (fit.jl), subproblem oracle gate, and the fixtures_phase19 test copy now use `has_branch_current(ctx.pf)`. `extract_dlmp` still refuses a SOCP-shaped ctx lacking `:socp_maxgap`.
- test_pricing_dlmp: hand-built contexts set `ctx.pf = ConvexBranchFlow()` and `ctx2.pf = LinDistFlow()`; assertions unchanged.
- Kwarg defaults `T = _require_T(ctx)` in welfare.jl/checks.jl.
- Planning balance-closing copies and mpc_loop copies untouched (deferred).

## Commits
- d1f913b pricing
- 475d426 planning
- 390c98c experiments and RestrictedBranchFlow

## Verification
Foreground TestItemRunner batches: pricing (dlmp, welfare, fit, checks) 625 pass/1 broken; planning oracle/noninteger/thesis_repro/ac_recheck/feasibility/inexact/bilevel/master 344/344; planning nash/hardening/follower/certification/benders/coupling/retry/trace/checkpoint 383 pass/1 broken; mpc_loop/restricted/experiments/run_stochastic/mpc_terminal/mpc_trace/planning_goldens 566/566. Broken counts are pre-existing @test_broken. Full suite not run. No golden touched.

## Deviations from Plan
None.

## Known Stubs
None.

## Self-Check: PASSED
