---
phase: 38-close-v4-0-audit-gaps
plan: 07
subsystem: experiments
tags: [scenario, admm, allow_export, provenance, jld2, reactive-mode, stochastic, oos]
requires:
  - "38-04: oos.inexact_h / oos.infeasible_h masks and _stochastic_status(infeasible_h, inexact_h)"
  - "38-06: count-sets tally 515/478/37/99"
provides:
  - "Scenario inner constructor rejects strategy ADMM with allow_export = false (all construction paths)"
  - "result_to_dict stores the reactive mode as a Symbol (:OFF/:CERTIFIED/:LIVE, missing for non-ADMM)"
  - "Stochastic artifacts store oos_inexact_draws, oos_infeasible_draws (Int) and oos_status (Symbol); collate_summary keeps them"
  - "status_policy.md section 7 'Stored simulation provenance' rewritten"
affects: [38-10]
tech-stack:
  added: []
  patterns: ["invalid strategy x scenario combinations fail in the Scenario inner constructor, before any solve"]
key-files:
  created:
    - .planning/phases/38-close-v4-0-audit-gaps/38-07-SUMMARY.md
  modified:
    - src/experiments/Scenario.jl
    - src/experiments/store.jl
    - src/experiments/sweep.jl
    - test/test_strategies.jl
    - docs/src/status_policy.md
    - .planning/phases/38-close-v4-0-audit-gaps/38-MEASUREMENTS.md
decisions:
  - "The ADMM import-only check sits in the inner constructor beside supports_pf, so with_strategy and run_sweep inherit it; solve_admm keeps its own guard for direct callers"
  - "collate_summary keeps the three Stochastic oos_* columns (missing for other strategies) so an excluded held-out draw is visible in the collated CSV"
metrics:
  duration: ~35min
  completed: 2026-10-07
  tasks: 2
  files: 6
requirements: [ARCH-02, ARCH-08, HYG-02]
---

# Phase 38 Plan 07: ADMM import-only rejected at construction; primitives-only stored provenance Summary

A Scenario that pairs ADMM with `allow_export = false` now fails when it is built. Before, it
failed only inside `solve_admm`. The stored provenance now holds only primitives: the reactive
mode is saved as a Symbol, and Stochastic artifacts record how many held-out draws were excluded
and the run status.

## Tasks

| Task | Name | Commits | Files |
|------|------|---------|-------|
| 1 | ADMM requires allow_export at Scenario construction | d8535e2 (RED), bb2a831 (GREEN) | src/experiments/Scenario.jl, test/test_strategies.jl, 38-MEASUREMENTS.md |
| 2 | Symbol reactive mode, stored OOS counts/status, docstrings, status_policy section 7 | 6429363 (RED), 63c2240 (GREEN), 6365a86 (style), 46b1f2e (ledger) | src/experiments/store.jl, src/experiments/sweep.jl, test/test_strategies.jl, docs/src/status_policy.md, 38-MEASUREMENTS.md |

## Results

- Task 1: the keyword form, the legacy `strategy = :admm` form and `TSODSO.run(ADMM(), ...)` (the
  `with_strategy` path) all throw `ArgumentError` with "requires allow_export = true". No solve
  runs first. Centralized, MPC and Stochastic still construct with `allow_export = false`. No
  existing test or script built an ADMM import-only Scenario. Filtered run over
  `test_strategies.jl,test_scenario_pf.jl,test_experiments.jl`: 54 items, 607/607 Pass.
- Task 2: `result_to_dict` stores `:LIVE` (and `missing` for non-ADMM runs). A JLD2 round trip
  returns a `Symbol`. On the CI golden Stochastic fixture the round-trip item asserts
  `oos_inexact_draws === 0`, `oos_infeasible_draws === 0` and `oos_status === :solved`, and every
  value still passes `is_prim`. Filtered run over `test_strategies.jl,test_experiments.jl`:
  45 items, 552/552 Pass.
- `--count-sets --strict`: before `all=515 fast=478 slow=37 files=99`, after
  `all=517 fast=480 slow=37 files=99 canary=1 outside=0`. That is the planned +2 fast items.
- The formatter produced whitespace-only changes, committed separately. `check_content_loss.py
  HEAD` is OK and `check_planning_ids.py` is OK.
- The stale `collate_summary` docstring ("persists `struct2dict(s)`") now describes the
  `_scenario_identity(s; style = :record)` flattening. Its column list now matches the code.

## Deviations from Plan

None that change behaviour. Two small details:
- The two new items' RED runs used scratch scripts in the session scratchpad. These checked only
  the no-solve assertions, so the `run(ADMM(), ...)` path was not run against the old code, where
  it would have started a solve.
- `collate_summary` keeps the three `oos_*` columns. The plan made this conditional ("if that list
  enumerates per-strategy scalars"). The must-have names collated summaries explicitly, so the
  columns were added.

## Known Stubs

None.

## Threat Flags

None. T-38-15 and T-38-16 are mitigated as planned: the constructor rejects the combination, and
the stored mode is a Symbol, checked by a round-trip test.

## Self-Check: PASSED

- FOUND: src/experiments/Scenario.jl, src/experiments/store.jl, src/experiments/sweep.jl,
  test/test_strategies.jl, docs/src/status_policy.md, 38-MEASUREMENTS.md
- FOUND commits: d8535e2, bb2a831, 6429363, 63c2240, 6365a86, 46b1f2e
