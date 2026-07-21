---
phase: 07-admm-convergence-scale
plan: 03
subsystem: optimization
tags: [admm, jump, set_objective_coefficient, socp, transit-node, adaptive-rho, build-once]

# Dependency graph
requires:
  - phase: 07-01
    provides: Phase-7 ADMM residual/stopping scaffolding and fixtures the set_rho! seam plugs into
  - phase: 06-admm-decomposition
    provides: build_agr_opt / build_dso_opt / solve_agr! / solve_dso! (the build-once subproblems mutated here)
provides:
  - "set_rho!(agr::AgrOpt, ρ) — in-place −0.5ρ diagonal quadratic-penalty updater (build-once preserved)"
  - "set_rho!(dso::DsoOpt, ρ) — in-place +0.5ρ diagonal quadratic-penalty updater (build-once preserved)"
  - "build_dso_opt transit-node relaxation: zero-injection non-load buses admitted (IEEE-123 scale-up enabler)"
affects: [07-04, 07-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "In-place adaptive-ρ via the 4-arg batch set_objective_coefficient(model, x, x, ±0.5ρ) — no rebuild"
    - "Coupling axis (load_nodes = aggregator buses) DECOUPLED from balance-closure axis (all non-root buses)"

key-files:
  created: []
  modified:
    - src/admm/AgrOpt.jl
    - src/admm/DsoOpt.jl
    - test/test_agr.jl
    - test/test_dso.jl

key-decisions:
  - "Pass ±0.5ρ (NOT bare ρ) to set_objective_coefficient(model,x,x,coeff): the JuMP-natural x² coefficient of a 0.5ρx² term is 0.5ρ; bare ρ would double the penalty."
  - "DsoOpt.pag DenseAxisArray flattened by indexing its known axes (collect unsupported on a Vector-axis DenseAxisArray)."
  - "Transit relaxation is a documentary no-op on 2-bus/IEEE-13 (transit_nodes == Int[]) — byte-for-byte same model; only IEEE-123-style junction buses exercise it."

patterns-established:
  - "Pattern 1 (RESEARCH): mutate the diagonal quadratic penalty coeff in place on a ρ change; equivalence proven by mutate-then-solve == fresh-build-at-ρ."
  - "Pitfall 5 (RESEARCH): zero-injection transit closure pins :Rp/:Rq at non-load non-root buses; balance registered at all N; invalid buses still fail loud."

requirements-completed: [ADMM-02]

# Metrics
duration: ~35min
completed: 2026-07-19
---

# Phase 7 Plan 03: set_rho! + Transit-Node Relaxation Summary

**Adaptive ρ now mutates the ADMM subproblem penalty geometry in place via the verified 4-arg `set_objective_coefficient` (±0.5ρ, no rebuild), and DSO-OPT admits zero-injection transit buses — the two seams the 07-04 adaptive loop and the 07-05 IEEE-123 scale case require.**

## Performance

- **Duration:** ~35 min
- **Tasks:** 2 (both TDD, RED baseline confirmed before implementation)
- **Files modified:** 4

## Accomplishments
- `set_rho!(agr, ρ)` / `set_rho!(dso, ρ)` mutate the diagonal quadratic penalty coefficient of `pag[t]²` (`−0.5ρ`, Max) and `pag_dso[j,t]²` (`+0.5ρ`, Min) in one batch `set_objective_coefficient(model, x, x, ±0.5ρ)` call — NO rebuild; `num_variables`/`num_constraints` invariant across a ρ change, and a mutate-then-solve is proven EQUIVALENT to a fresh build at the new ρ.
- `build_dso_opt` transit-node relaxation: `load_nodes` (the ADMM coupling axis) is decoupled from all-non-root buses (the balance-closure axis); a non-root, non-load bus is admitted as a physically-valid zero-injection transit node with `:Rp`/`:Rq` pinned to 0 and `balance_p`/`balance_q` closed at all N buses. The SOCP stays well-determined (proven by an OPTIMAL solve on a synthetic root→transit→load feeder).
- 2-bus and IEEE-13 cases are byte-for-byte unaffected (`transit_nodes == Int[]`); genuinely-invalid buses (aggregator on root / out of range) still fail loud.

## Task Commits

Each task was committed atomically:

1. **Task 1: set_rho! quadratic-coefficient updaters (build-once preserved)** — `2e4b1aa` (feat)
2. **Task 2: Relax the DSO-OPT transit-node guard (zero-injection buses)** — `fd95f20` (feat)

_TDD note: the RED @testitems (set_rho!/build-once/transit) already existed from the Wave-0 harness; RED was confirmed before implementing, then driven GREEN. Additional equivalence + transit-solve @testitems were added to test_agr.jl / test_dso.jl (my owned files, since test_admm_adaptive.jl belongs to another executor this wave)._

## Files Created/Modified
- `src/admm/AgrOpt.jl` — added `set_rho!(agr::AgrOpt, ρ)` (batch `−0.5ρ` diagonal update); exported.
- `src/admm/DsoOpt.jl` — added `set_rho!(dso::DsoOpt, ρ)` (batch `+0.5ρ`, axis-indexed flatten); relaxed the transit-node guard to admit zero-injection buses + pinned-zero `:Rp`/`:Rq` closure; updated docstring; exported.
- `test/test_agr.jl` — added the AGR set_rho! mutate-then-solve == fresh-build-at-ρ + build-once equivalence @testitem.
- `test/test_dso.jl` — added the DSO set_rho! equivalence @testitem and a transit zero-injection solve @testitem (synthetic feeder); updated the guard @testitem to reflect transit admission + genuinely-invalid fail-loud cases.

## Verification

Targeted TestItemRunner runs (test env on `JULIA_LOAD_PATH`):

- `set_rho!` + `build-once` filter: **24/24 GREEN** (AGR + DSO equivalence, num_variables/num_constraints invariance, plus the harness `admm adaptive rho: set_rho! in-place quad-coeff` item).
- `transit` + `dso` filter: **55/55 GREEN** (transit admission, load_nodes decoupling, balance at all N, OPTIMAL solve; guard fail-loud; all existing DSO items incl. IEEE-13 reactive closure + PF-04 exactness).
- `agr` + `adaptive` filter: **34 GREEN**, 1 downstream ERROR (see below).

## Deviations from Plan

None affecting the plan's scope. Implementation notes:

- The RESEARCH sketch used `v = vec(dso.pag)`; on this codebase `dso.pag` is a Vector-axis `DenseAxisArray` where `collect`/`vec` is unsupported, so the flatten was implemented as `VariableRef[dso.pag[j,t] for j in dso.load_nodes for t in 1:dso.T]`. Behaviorally identical (batch quadratic-coeff update); Rule 3 (blocking API detail) inline fix, no scope change.

## Known Downstream Reds (NOT this plan; NOT regressions)

These fail ONLY because they call the not-yet-extended `solve_admm` (owned by other Phase-7 plans / files I must not touch) or a parallel-wave stub. All were RED before this plan and are unrelated to the additive `set_rho!` / no-op-for-existing-feeders transit change:

- `admm adaptive rho: scale-invariant convergence 2-bus AND ieee13` — needs `solve_admm(...; ε_abs, ε_rel, τ, μ, ρ_min, ρ_max)` (plan **07-04** adaptive-ρ policy). The test file header itself states 07-04 turns it green.
- `admm dualresid: z-block dual residual + two-residual stop` — needs `solve_admm(...; ε_abs, ε_rel)` (07-01/07-04 extended stopping).
- `ieee123 admm: end-to-end converge + DADP cross-validation` — guarded on `isdefined(TSODSO, :ieee123_modified)`, a plan **07-02** stub.

## Threat Flags

None — the changes touch only the ADMM penalty geometry and the transit-node balance closure, both inside the plan's declared trust boundaries (T-07-06 / T-07-07 / T-07-08 mitigated by the build-once equivalence, the all-N balance closure, and the preserved 2-bus/IEEE-13 coupling).

## Self-Check: PASSED

- Files present: src/admm/AgrOpt.jl, src/admm/DsoOpt.jl, test/test_agr.jl, test/test_dso.jl, 07-03-SUMMARY.md — all FOUND.
- Commits present: 2e4b1aa (Task 1), fd95f20 (Task 2) — all FOUND.
- `set_rho!` exported from both AgrOpt.jl and DsoOpt.jl; transit relaxation (`transit_nodes`) present in DsoOpt.jl.
