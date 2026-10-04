---
phase: 33-shared-abstractions-feeder-balance-model-context
plan: 07
subsystem: core
tags: [ARCH-07, ModelContext, typed-reads]
requires: [33-06]
provides:
  - src/models, src/admm, src/devices read typed ctx fields; no legacy-key reads remain
affects: [33-08]
key-files:
  modified: [src/models/exactness.jl, ac_oracle.jl, restriction_exactness.jl, mesh_angle_certificate.jl, oracle.jl, welfare_solve.jl, linear_solve.jl, mpc_window.jl, stochastic_welfare.jl, complementarity_4q.jl, src/admm/AgrOpt.jl, DsoOpt.jl, solve_admm.jl, src/devices/AbstractDevice.jl, FixedCapacitor.jl]
decisions:
  - reads of T/feeder/pf_vars use _require_* (ArgumentError when unset); objective/agg_device_vars read typed fields directly
metrics:
  tasks: 3
completed: 2026-10-03
---

# Phase 33 Plan 07: Typed reads in models/admm/devices Summary

All reads (code, kwarg defaults, docstrings, comments) of `meta[:pf_vars|:feeder|:T|:objective|:agg_device_vars]` in src/models, src/admm, src/devices now use the typed fields. The grep for remaining legacy-key mentions (excluding TRANSIENT-MIRROR lines and the writer file Aggregator.jl, owned by 33-10) returns only one docstring line in devices/Aggregator.jl (writer file, left for 33-10).

- `haskey(pf_vars, :l)` gates in `welfare_solve.jl` and `stochastic_welfare.jl` (per scenario `ctxs[s].pf`) became `has_branch_current(ctx.pf)`.
- `haskey(ctx.meta, :agg_device_vars)` became `!isempty(ctx.agg_device_vars)` (4 sites).
- The stale exactness.jl comment claiming MeshedFlow never runs the gate was corrected (MeshedFlow delegates to the shared SOCP body, which stashes `l`); the WR-02 conclusion wording was adjusted accordingly (no longer claims it is never exercised). Gate logic and thresholds untouched.

## Objective upstream-guard audit (T-33-22)
- linear_solve: empty-devices `ArgumentError` (WR-01); comment updated.
- welfare_solve: `isempty(aggregators)` ArgumentError (line ~130).
- mpc_window and stochastic build_*: `isempty(aggregators)` ArgumentError; stochastic also `isempty(scenario_aggs)`.
- AgrOpt: `contribute!` of its aggregator always adds to the objective.
No site needed a new guard.

## Commits
- b12e1e4 certificates and oracles
- 3e62a16 builders and gates
- 6e3971c ADMM and device sources

## Verification
Foreground TestItemRunner, three batches: certificates/oracles 182/182; builders (close_balance, welfare, linear, mpc, stochastic, oos harness, fourquadbess, pvbattery, toy_dc) 374/374; admm/dso/aggregator/devices/agr/thesis_repro including knife-edge canary 464/464. Full suite not run. No golden touched.

## Deviations from Plan
None. (toy_dc.jl was in the test list only; its source had no legacy reads.)

## Known Stubs
None.

## Self-Check: PASSED
