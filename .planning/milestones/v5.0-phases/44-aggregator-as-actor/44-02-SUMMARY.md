---
phase: 44-aggregator-as-actor
plan: 02
subsystem: actors
tags: [actor-objective, solve-welfare, solve-admm, efficiency-loss, measured-tolerances]
requires: ["44-01"]
provides:
  - "solve_welfare(...; actors) centralized retail wedge, social welfare returned, ctx.meta[:actor]"
  - "solve_admm(...; actors) on the legacy 1:1 path + trailing `actor` result key"
  - "actor_efficiency(W_opt, W_soc) -> (; delta_abs, delta_rel)"
affects: [44-03, 44-04, 44-05, 44-06, 44-07]
tech-stack:
  added: []
  patterns: ["wedge only in a LOCAL objective expression; ctx.objective untouched so social welfare is recomputable"]
key-files:
  created:
    - src/actors/efficiency.jl
  modified:
    - src/models/welfare_solve.jl
    - src/admm/solve_admm.jl
    - src/admm/admm_phases.jl
    - src/TSODSO.jl
    - test/test_actor_objective.jl
    - test/test_exports.jl
key-decisions:
  - "Implementation choice (orchestrator-accepted deviation from CONTEXT wording): the centralized wedge is added in solve_welfare from ctx.meta[:agg_net], not through a new Aggregator.contribute! keyword. Aggregator.jl is untouched; the default path is bit-identical."
  - "ProfitObjective(0) is routed through the wedge path (never short-circuited); the default fence and canary pass unchanged."
  - "Two-bus fixture wedge is dormant for |m| <~ 2 (dispatch kink); m = 5.0 is the measured live operating point."
requirements-completed: []
duration: ~75min
completed: 2026-11-02
---

# Phase 44 Plan 02: Actor objective on both solve paths Summary

`actors = [Portfolio(...)]` now works on `solve_welfare` and `solve_admm`: each portfolio's objective (welfare or profit-with-retail-wedge) applies to all its sites, `welfare` is always SOCIAL, and the actor objective value, per-portfolio profit and DeltaW are reported separately.

## Tasks

1. Centralized wedge + efficiency helper (`e40aeaf`): `actors` kwarg validated (`_expand_actors`, wedge length) before any model build; wedge terms accumulate onto a local `welfare` expression; on the actor path the returned 3rd element is `value(ctx.objective) - lambda0' p_import` and `ctx.meta[:actor] = (; social_welfare, actor_objective_value, profit_by_actor, retail_wedge)`. `actor_efficiency` in `src/actors/efficiency.jl`, exported, added to the exports test.
2. ADMM wiring (`1a2e972`): `actors` kwarg on `solve_admm`; per-bus objective Dict passed to `_admm_build` via a trailing `objectives` keyword; the default call to `build_agr_opt` is literally unchanged. A converged non-default result gains a trailing `actor` key (default key set/order unchanged).
3. Regression sweep + inheritance: `fit_baseline`, `run_mpc` and `run_stochastic` expose no `actors` keyword; test items assert `@test_throws MethodError` with valid positional arguments and that the message names `actors`. No new kwargs added to those entries (the Scenario carries no actors field, so no other route exists).

## Measured tolerances (3x observed max, julia 1.12.5)

Seeds {20260719..21} two-bus (m = 5.0) and {20260718..20} IEEE-13 ground (2 portfolios x 5 buses, m = 0.5 on portfolio 1):

| Quantity | Observed | Pinned band |
|---|---|---|
| central abs(W(Profit(0)) - W(default)) | max 3.09e-11 | 9.3e-11 |
| central dadp Profit(0) vs default | 0.0 | `==` |
| ADMM Profit(0) vs default (welfare, dadp, iters, trace) | bitwise equal | `==` |
| ADMM vs central welfare, relative | max 4.12e-8 | 1.24e-7 |
| ADMM vs central dadp, IEEE-13 | max 4.09e-3 | 1.23e-2 |
| ADMM vs central dadp, two-bus | max 1.35e-5 | 4.1e-5 |
| central DeltaW (live) | min 1.96e-3 IEEE, 0.248 two-bus | > min/3 |
| negative DeltaW excursion | none | slack = 9.3e-11 central; 1.24e-7 rel ADMM |
| ADMM net-injection shift (live) | min 1.42e-2 IEEE, 6.8e-3 two-bus | > min/3 |

Table is also in the test-file header. Efficiency loss at these points: DeltaW about 2.0e-3 (IEEE-13, relative 4e-7) and 0.25 (two-bus).

## Verification

- `test_actor_objective.jl` (fast set + fence + exports): 164 pass. Slow set for the same file (IEEE-13 ADMM portfolios, crossval, legacy equality): 153 pass in 9m48s.
- Wave regression (objective, fence, canary, test_admm, test_agr, test_dso, test_admm_reactive, test_welfare_solve, test_settlement, test_flex_population, test_exports, test_admm_phases): 834 pass, 0 fail. Goldens, fence digests and `expected_broken.txt` untouched.

## Deviations from Plan

- Test file `test/test_actor_objective.jl` was committed together with Task 1 (single shared file); Task 2's commit carries only `src/admm`.
- The IEEE-13 ADMM item is tagged `:slow` (about 10 min), matching the existing IEEE-13 crossval item; two-bus ADMM and IEEE-13 centralized items run in the fast set.
- Measured live point for two-bus is m = 5.0, not a small margin (see decisions).

## Known Stubs

None.

## Self-Check: PASSED

Files `src/actors/efficiency.jl` and this SUMMARY exist; commits `e40aeaf`, `1a2e972` exist in the log.
