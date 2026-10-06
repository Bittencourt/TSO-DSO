---
phase: 37-test-infrastructure-repo-hygiene
plan: 08
subsystem: testing
tags: [jet, baseline, refactor, bit-identity]
requires: [37-07]
provides:
  - TSODSO._objective helper (JuMP.objective_value with a Float64 assertion)
  - scripts/jet_baseline.txt shrunk from 33 to 11 signatures
key-files:
  modified: [src/solver/factory.jl, src/core/ModelContext.jl, scripts/jet_baseline.txt]
decisions:
  - Cleanups ADOPTED (fingerprints byte-identical), not reverted
metrics:
  tasks: 2
  completed: 2026-10-06
---

# Phase 37 Plan 08: JET false-positive cleanups Summary

Cleanups applied: all 22 code call sites of `objective_value(` now go through one internal helper `_objective(model)::Float64` (in `src/solver/factory.jl`), and `has_branch_current(ctx)` copies `ctx.pf_vars` to a local before its Nothing guard. The JET baseline dropped from 33 to 11 signatures (23 fixed, 1 new: the helper's own convert check, justified in Group 1).

## Bit-identity proof (Julia 1.12.5, `+release`)

Driver (scratchpad, no `@testitem`) printed `repr` plus `reinterpret(UInt64, x)` for: the IEEE-13 ADMM knife-edge canary (iters = 56, welfare -4823.66604824162, dadp), centralized IEEE-13 run, `solve_welfare` (LinDistFlow multi-device and ConvexBranchFlow), `welfare_accounting`, `fit_baseline`, and a `solve_stackelberg!` Benders run. 302 lines before; `elapsed` excluded as nondeterministic. Two baseline runs identical; after-edit output `cmp`-identical to before, also after JuliaFormatter 2.10.2. No tolerance constants touched.

## Verification

- JET check: 11 current / 11 baseline, 0 NEW, 0 FIXED on 1.12.5 and 1.12.7 (version-header WARNING on 1.12.5 is expected).
- Filtered tests pass: canary, welfare_solve, pricing_welfare (1 pre-existing Broken), context, planning_benders, benders_integer, master, master_integer, fit, stochastic_welfare, run_stochastic, toy_dc, ac_oracle, linear_solve, ac_recheck, bilevel, oracle, feasibility_oracle, follower.
- `check_script_api.jl` and `check_planning_ids.py` green.
- `check_content_loss.py HEAD` flags the working tree before commit only because the name is 5 characters shorter per call site; it is clean against the new HEAD.

## Deviations from Plan

None. The three conditionally-defined-local reports and the Union{Nothing} reports were left baselined as instructed. HYG-04 intentionally not marked complete.

## Self-Check: PASSED
Commit 8a82acc present; fingerprints_before/after identical.
