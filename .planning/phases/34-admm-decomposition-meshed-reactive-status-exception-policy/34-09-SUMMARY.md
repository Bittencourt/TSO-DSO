---
phase: 34-admm-decomposition-meshed-reactive-status-exception-policy
plan: 09
subsystem: admm
tags: [admm, julia, power-flow, dispatch]
requires: ["34-08"]
provides:
  - "admm_supported trait + _check_admm_pair!; formulation-generic solve_admm/build_dso_opt (pf kwarg); solve_agr! battery_on_violation; NaN exact_maxgap without branch current; widened supports_pf(::ADMM)"
affects: [34-10]
key-files:
  created: [test/test_admm_generic_pf.jl]
  modified: [src/admm/admm_state.jl, src/admm/admm_phases.jl, src/admm/solve_admm.jl, src/admm/DsoOpt.jl, src/admm/AgrOpt.jl, src/experiments/strategies.jl, test/test_abstract_feeder.jl, test/test_strategies.jl, test/test_scenario_pf.jl]
key-decisions:
  - "Battery gate policy read from st.dso.ctx.pf via problem_class (no AdmmState field added); :error for SOCP class keeps default path bit-identical"
  - "supports_pf(::ADMM) allows thesis-literal convex (mirrors admm_supported); only :ac rejected"
requirements-completed: []
duration: ~60min
completed: 2026-10-04
---

# Phase 34 Plan 09: Formulation-generic ADMM Summary

`solve_admm` / `build_dso_opt` now accept any `admm_supported` formulation (Convex both variants, Restricted, Meshed, LinDist); AC/DC and radial-formulation x MeshedFeeder pairs throw `ArgumentError` naming the function and type, with the pair check ahead of the empty-aggregators guard. The always-throw `::MeshedFeeder` methods are deleted.

## Changes
- `admm_state.jl`: exported `admm_supported`, `_check_admm_pair!`, `_batt_on_violation(st)`; the final AGR solves pass `battery_on_violation` (`:warn` iff non-SOCP).
- `DsoOpt.jl`: `feeder::AbstractFeeder`, kwarg `pf = ConvexBranchFlow()`, `contribute!(pf, ...)`; `solve_dso!` gates `assert_socp_exact!` on `has_branch_current(dso.ctx)`.
- `AgrOpt.jl`: additive `battery_on_violation::Symbol = :error`.
- `admm_phases.jl`: `pf = pf` passed to `build_dso_opt`; `exact_maxgap = NaN` when no branch current.
- `strategies.jl`: `supported_pfs(::ADMM)` = (convex, restricted, lindistflow); `supports_pf(::ADMM, ...)` split out; MPC/Stochastic unchanged.

## Verification (foreground)
- canary (iters = 56, welfare -4823.66604824162) unchanged, never re-pinned; passes in every batch.
- batch A: canary + generic_pf + abstract_feeder + strategies: green after test fixes.
- batch B: test_admm*, test_experiments, test_scenario_pf: green after fixing test_scenario_pf guard expectations.
- batch C: test_scenario_pf, test_admm_timeout, test_dso, test_agr, test_ieee123_admm, test_status_policy, test_tsodso_errors: 255 pass.

## Commits
- a512115 feat(34-09): formulation-generic solve_admm/build_dso_opt via admm_supported trait
- ae679d4 feat(34-09): widen supports_pf(::ADMM) to convex/restricted/lindistflow

## Deviations from Plan
- [Rule 1 - Test] test_abstract_feeder's meshed-rejection test called `solve_admm` / `build_dso_opt` without required `λ₀`/`ρ` (old always-throw methods swallowed any kwargs) and with the old `build_dso_opt` argument order; updated to supply them and added the (MeshedFeeder, MeshedFlow) passes-pair-check assertion.
- [Rule 1 - Test] test_scenario_pf "pf construction guards" pinned ADMM rejecting restricted/lindistflow/thesis-literal; updated to the widened matrix (ADMM still rejects `:ac`).
- Centralized reference in the generic-pf welfare test uses tightened Clarabel gaps for SOCP-class formulations (near-lossless 2-bus fixture trips PF-04 at default gaps, as in test_admm.jl); gate not touched.
- Battery co-activation is hard to provoke on fixtures; Test 5 verifies default unchanged, `:warn` accepted, and that the kwarg is forwarded (invalid value rejected by `assert_battery_complementarity!`).
- Scenario-level ADMM run assertions (LinDist finite welfare; Restricted vs Centralized rtol 1e-4) pass on ieee13 seed 7.

## Known Stubs
None.

## Self-Check: PASSED
REQUIREMENTS.md intentionally untouched (ARCH-05/06 not marked complete).
