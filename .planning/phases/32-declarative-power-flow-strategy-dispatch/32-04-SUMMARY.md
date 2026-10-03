---
phase: 32-declarative-power-flow-strategy-dispatch
plan: 04
subsystem: experiments
tags: [julia, persistence, drwatson, savename, collate, arch-02]

requires:
  - phase: 32-03
    provides: reshaped ScenarioResult with typed details
provides:
  - _scenario_identity flatten helper (:filename / :record styles)
  - scenario_filename with prefixed active-strategy-only names
  - result_to_dict with legacy flat keys, pf fields, MPC/Stochastic extras
  - collate_summary with pf and MPC/Stochastic knob columns
affects: [32-05]

key-files:
  modified: [src/experiments/store.jl, src/experiments/sweep.jl, test/test_experiments.jl]

key-decisions:
  - "Filename built from an explicit flattened Dict because savename drops struct-valued fields"
  - "stoch_probabilities not a collate column; its FNV-1a digest lives in the filename only"

requirements-completed: []

duration: 30min
completed: 2026-10-03
---

# Phase 32 Plan 04: Persistence layer for strategy Scenario Summary

**One shared `_scenario_identity` helper now feeds both `scenario_filename` (prefixed, active-knobs-only names such as `strategy=ADMM`, `admm_ρ=`) and `result_to_dict` (legacy flat primitive keys plus `pf` fields), with `collate_summary` extended for mixed-strategy sweeps.**

## Accomplishments
- store.jl: per-strategy `_strategy_label`/`_strategy_knobs` methods; `digits = 10`, `safe = true`, FNV-1a non-uniform probability digest and NAME_MAX fallback retained; `struct2dict` removed.
- sweep.jl: `:pf, :pf_thesis_literal, :pf_ε` and `:mpc_*`/`:stoch_S`/`:stoch_H_oos` added to `keep` and `selector_cols`; `run_sweep` still calls `Scenario(; nt...)`.
- Tests: `test_experiments.jl` 106 passing (was 70), including filename identity (vary-each-knob uniqueness), result_to_dict primitives, run_and_store round-trip, and mixed-strategy collate (byte-identical, `missing` ADMM cells on centralized row; RESEARCH A3 confirmed, no collate padding needed).

## Task Commits
1. store.jl: bb5e4ad
2. sweep.jl: 34ae51e
3. test_experiments.jl: 3c47f23

## Deviations from Plan
None - plan executed as written. Numeric goldens untouched; only filename strings changed (older `data/sims` artifacts orphaned, gitignored).

## Known Stubs
None.

## Self-Check: PASSED
