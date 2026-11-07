---
phase: 44-aggregator-as-actor
plan: 01
subsystem: actors
tags: [actor-objective, portfolio, admm, agr-opt, byte-identity-fence]
requires: []
provides:
  - "AbstractActorObjective / WelfareObjective / ProfitObjective (+ agr_objective, agr_linear_offset, wedge_term, is_default_objective)"
  - "Portfolio + _expand_actors"
  - "AgrOpt objective kwarg and linear_offset field; wedge reaches solve_agr! coefficient"
  - "Pre-change FNV digest fence of default solve_admm / solve_welfare"
affects: [44-02, 44-03, 44-04, 44-05, 44-06, 44-07]
tech-stack:
  added: []
  patterns: ["margin stored as AgrOpt.linear_offset, re-added inside set_objective_coefficient update"]
key-files:
  created:
    - src/actors/actor_objective.jl
    - src/actors/Portfolio.jl
    - test/test_actor_default_fence.jl
    - test/test_actor_objective.jl
  modified:
    - src/admm/AgrOpt.jl
    - src/TSODSO.jl
    - test/test_exports.jl
    - test/expected_broken.txt
key-decisions:
  - "Wedge is a linear retail margin on pag stored as linear_offset (never baked into the objective: solve_agr! overwrites that coefficient)"
  - "ProfitObjective(0) is not the default objective; zero wedge is never short-circuited"
  - "Digest fence is one @testitem with one version-gated @test_skip (single expected_broken entry)"
requirements-completed: []
duration: ~45min
completed: 2026-11-02
---

# Phase 44 Plan 01: Actor objective foundation Summary

Pre-change default digests pinned, then the objective hierarchy, `Portfolio`, and an AGR-OPT hook that carries a retail margin through the per-iteration ADMM coefficient update.

## Tasks

1. Pre-change fence (`ba1ad0e`): `git diff -- src` was empty (0 lines) at capture. Full-field FNV-1a digests of default `solve_admm` and `solve_welfare` (two-bus and IEEE-13), plus `ctx.meta` key set, canary 56 / -4823.66604824162. IEEE-13 digests were identical across two fresh processes. Digest assertions gated on Julia 1.12.5, with one skip record in `test/expected_broken.txt`.
2. Hierarchy + Portfolio + exports (`9b29659`): V5 guards throw `ArgumentError`; four new exports added to `test_exports.jl`.
3. AgrOpt hook (`0344afc`): `objective` kwarg, `linear_offset` field, margin added inside `solve_agr!`. Test reads the actual `pag` coefficient (`-lambda - rho*c + m`), checks it survives a re-solve, and shows the margin changes the optimum while `ProfitObjective(0.0)` gives bitwise the default `pag`.

## Verification

Targeted run of test_actor_objective, test_actor_default_fence, test_agr, test_admm_phases, test_admm_knifeedge_canary: 121 pass, 0 fail. Goldens not edited after capture; canary unchanged.

## Deviations from Plan

- Two-bus `solve_welfare` needed the tightened SOCP optimizer (tol_gap 1e-10, as in test_admm_generic_pf.jl) or the exactness gate refused at default tolerance; this is the fixture's known near-lossless behaviour, not a src issue.
- The fence is one combined @testitem rather than two, so a single version-gate skip entry covers it (plan asked for exactly one entry).
- Digest folder handles JuMP `SparseAxisArray` (via `.data`) since a result field is one.

## Issues Encountered

None outstanding. REQUIREMENTS.md not touched (ACTOR-01 is marked by plan 44-07).

## Self-Check: PASSED
