---
phase: 06-admm-decomposition-core
plan: 02
subsystem: admm
tags: [admm, agr-opt, subproblem, build-once, qp]
requires:
  - "src/devices/Aggregator.jl :: contribute! (device/aggregator roll-up, thesis 3.21-3.23)"
  - "src/core/ModelContext.jl :: ModelContext, add_to_objective!, register_constraint!"
  - "src/solver/factory.jl :: select_optimizer(QP())"
  - "src/core/status.jl :: assert_solved!"
  - "src/models/welfare_solve.jl :: assert_battery_complementarity! (App. C)"
provides:
  - "src/admm/AgrOpt.jl :: AgrOpt (build-once per-node QP subproblem struct)"
  - "src/admm/AgrOpt.jl :: build_agr_opt(agg, T; ρ) (thesis 3.46 block-1 builder)"
  - "src/admm/AgrOpt.jl :: solve_agr!(agr, λ_j, c_j, ρ) (coefficient-update re-solve + App. C gate)"
affects:
  - "src/admm/solve_admm.jl (plan 06-04 — the dual-ascent loop consumes AgrOpt/solve_agr!)"
tech-stack:
  added: []
  patterns:
    - "Build-once JuMP QP; per-iteration set_objective_coefficient re-solve (no rebuild, ADMM-03)"
    - "Reuse Aggregator.contribute! verbatim — ADMM as orchestration, not re-implementation"
    - "Price λ_j kept a plain Float64 coefficient, never a JuMP Parameter (avoids indefinite bilinear)"
key-files:
  created: []
  modified:
    - "src/admm/AgrOpt.jl (filled the Wave-1 comment-only stub)"
    - "test/test_agr.jl (new @testitem harness, name-substring \"agr\"/\"resolve\")"
decisions:
  - "AGR-OPT reuses Aggregator.contribute! (RESEARCH Pattern 4 option a); its stray :Rp/:Rq writes are harmless (never closed here)"
  - "Coupling var pag[t] pinned to Σ p_inject − Pdc (3.22); reactive qag[t] kept a constant Float64 vector (3.23, DERs active-only)"
  - "App. C battery gate uses τ=1e-6 (tight QP path) inside solve_agr!"
metrics:
  duration: ~12m
  completed: 2026-07-19
  tasks: 2
  files: 2
  commits: 5
---

# Phase 6 Plan 02: AGR-OPT Per-Node Subproblem Summary

Built the AGR-OPT block-1 ADMM subproblem (thesis eq. 3.46) as a build-once per-node QP that
reuses `Aggregator.contribute!` verbatim, introduces the coupling variable `pag_j[t]` pinned to
the net active injection (3.22), and re-solves each ADMM iteration via a single
`set_objective_coefficient` update on `pag_j[t]` — with the App. C battery-complementarity gate
running after every solve. The `agr`-filtered `@testitem`s are GREEN.

## What Was Built

- **`AgrOpt` struct** — holds the built-once JuMP `model`, its `ModelContext`, the coupling
  variable handle `pag::Vector{VariableRef}`, the constant reactive injection `qag::Vector{Float64}`
  (thesis 3.23, exposed for the μ update), plus `T`, `bus`, and `ρ`.
- **`build_agr_opt(agg, T; ρ)`** — (1) `Model(select_optimizer(QP()))` + `ModelContext`;
  (2) `res = contribute!(agg, ctx; T)` reuses the aggregator/device builders verbatim (populates
  `ctx.meta[:objective]` = `U_ag` and `ctx.meta[:agg_device_vars]` for the battery check);
  (3) `pag[t] == res.p_inject[t] − agg.Pdc[t]` (3.22); (4) constant `qag` (3.23);
  (5) `@objective(Max, U_ag − (ρ/2)Σ pag²)` — the FIXED quadratic ρ-penalty built once.
- **`solve_agr!(agr, λ_j, c_j, ρ)`** — updates only the linear coefficient of each `pag[t]` to
  `−λ_j[t] − ρ·c_j[t]` (RESEARCH Pattern 3), gates on `assert_solved!(...; dual=true)`, runs
  `assert_battery_complementarity!(agr.ctx; τ=1e-6, T=agr.T)` (App. C), and returns
  `(; pag = value.(agr.pag), utility = value(ctx.meta[:objective]))`.

## Verification

- `agr`-filtered `@testitem`s: **19 pass / 0 fail** (build + solve + build-once/resolve +
  price-shift, App. C gate runs inline without throwing).
- Build-once proof (`resolve` item): `num_variables`/`num_constraints` are identical across two
  `solve_agr!` calls with different `(λ_j, c_j)` — only `set_objective_coefficient` mutates the
  model (ADMM-03, threat T-06-04).
- Discipline greps hold: `select_optimizer(QP())` present (INFRA-02, threat T-06-11); no concrete
  solver named (`Clarabel`/`HiGHS`/`Ipopt` absent); no `Parameter(` for the price (T-06-09);
  `assert_battery_complementarity` invoked in `solve_agr!` (T-06-10).
- Full `Pkg.test()`: **1084 pass**, 1 broken (pre-existing). The only 3 failures are in
  `test/test_admm.jl` — the parallel executor's Wave-3 harness asserting
  `isdefined(TSODSO, :solve_admm)` (plan 06-04, not yet implemented); these were RED at the base
  commit and are out of this plan's scope. No Phase 1-5 regression, no `agr` regression.

## Deviations from Plan

None — plan executed exactly as written. (The plan's verify command
`julia --project=. -e 'using TestItemRunner; ...'` requires the test-env dep `TestItemRunner`,
so it was run with the test project stacked onto `JULIA_LOAD_PATH` — a runner-invocation detail,
not a code or behavior change.)

## Known Stubs

None. `AgrOpt`, `build_agr_opt`, and `solve_agr!` are fully wired to the reused builders and the
solved model; no placeholder/empty-value data paths were introduced.

## Self-Check: PASSED

- FOUND: src/admm/AgrOpt.jl (AgrOpt, build_agr_opt, solve_agr!, export line)
- FOUND: test/test_agr.jl (4 @testitems, names contain "agr"; one contains "resolve")
- FOUND commits: 045f173 (test RED), d3d1935 (build_agr_opt GREEN), 5e9153b (test RED),
  2ed3dd8 (solve_agr! GREEN)
