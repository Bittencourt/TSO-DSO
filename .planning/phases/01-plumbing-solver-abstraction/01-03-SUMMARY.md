---
phase: 01-plumbing-solver-abstraction
plan: 03
subsystem: infra
tags: [julia, jump, solver-factory, clarabel, highs, ipopt, weakdeps, package-extensions, status-discipline, residual-registry]

# Dependency graph
requires:
  - phase: 01-plumbing-solver-abstraction (plan 01-01)
    provides: TSODSO package scaffold, empty seam stubs, Wave 0 RED @testitems (test_factory/test_status/test_context)
provides:
  - "select_optimizer(::ProblemClass) singleton-dispatch solver factory (HiGHS/Clarabel/Ipopt)"
  - "GurobiChoice/MosekChoice markers + commercial_optimizer hook wired to weakdep package extensions"
  - "assert_solved! solve-status choke point (is_solved_and_feasible, allow_local=false) + assert_no_slack guard"
  - "ModelContext + register_constraint! + add_to_residual! shared nodal-balance residual registry"
  - "AbstractPowerFlow abstract type + contribute! contract (PF-01 seam stub)"
affects: [02-power-flow-formulations, 04-socp-branch-flow, 05-pricing-duals, 06-admm-decomposition, planning-benders]

# Tech tracking
tech-stack:
  added: []  # all deps present from plan 01-01; this plan fills stubs only
  patterns:
    - "ProblemClass singleton types + multiple-dispatch solver selection (no if-branching)"
    - "Commercial solvers as [weakdeps] + [extensions], reachable only via commercial_optimizer marker dispatch"
    - "Single solve-status choke point delegating to is_solved_and_feasible (supersedes termination_status == OPTIMAL)"
    - "Accumulating residual registry seam so power-flow formulations share one nodal balance with no formulation branching"

key-files:
  created: []
  modified:
    - src/solver/ProblemClass.jl
    - src/solver/factory.jl
    - ext/TSODSOGurobiExt.jl
    - ext/TSODSOMosekExt.jl
    - src/core/ModelContext.jl
    - src/core/status.jl
    - src/powerflow/AbstractPowerFlow.jl

key-decisions:
  - "select_optimizer dispatches on ProblemClass singleton types; models never name a solver (INFRA-02)"
  - "Gurobi/MosekTools stay [weakdeps]; ext/* add commercial_optimizer methods only when the solver is loaded (never a hard dep)"
  - "assert_solved! uses is_solved_and_feasible(allow_local=false) so LOCALLY_SOLVED is rejected for the convex core (Pitfall 2)"
  - "add_to_residual! accumulates (never overwrites) — the PF-01 no-branching seam"
  - "Recorded RESEARCH Pitfall-1 correction in factory.jl: Clarabel is copy_to-only; never direct_model(Clarabel...); reserve direct_model for HiGHS"

patterns-established:
  - "Pattern 1: singleton ProblemClass + select_optimizer dispatch (INFRA-02)"
  - "Pattern 2: commercial solvers as opt-in package extensions via marker-type dispatch"
  - "Pattern 3: assert_solved!/assert_no_slack single INFRA-03 choke point"
  - "Pattern 6: ModelContext residual/constraint registries (PF-01)"

requirements-completed: [INFRA-02, INFRA-03, PF-01]

# Metrics
duration: 18min
completed: 2026-07-18
---

# Phase 01 Plan 03: Solver Abstraction, Status Discipline & Residual-Registry Keystone Summary

**Filled the compute keystone: `select_optimizer(::ProblemClass)` singleton-dispatch factory with Gurobi/Mosek weakdep extensions, the `assert_solved!` fail-loud status choke point, and the `ModelContext` residual registry + `AbstractPowerFlow` contract — driving the factory, status, and context Wave 0 @testitems GREEN.**

## Performance

- **Duration:** ~18 min
- **Tasks:** 2 completed
- **Files modified:** 7 (src/solver/*, ext/*, src/core/*, src/powerflow/*)

## Accomplishments
- INFRA-02: every model requests its solver via `select_optimizer(::ProblemClass)` dispatch — HiGHS (LP/MILP), Clarabel (QP/SOCP, tight duality-gap tolerances), Ipopt (NLP); grep confirms no non-factory `src/` file names a solver.
- INFRA-02 (commercial): `GurobiChoice`/`MosekChoice` markers + `commercial_optimizer` fallback that errors with load instructions; `ext/TSODSOGurobiExt.jl` and `ext/TSODSOMosekExt.jl` add the concrete methods only when the weakdep is present — Gurobi/MosekTools remain out of `[deps]`.
- INFRA-03: `assert_solved!` wraps `optimize!` + `is_solved_and_feasible(model; dual, allow_local=false)`, erroring with full termination/primal/dual/raw diagnostics; `assert_no_slack` recomputes a constraint LHS to catch hidden slack.
- PF-01: `ModelContext` owns the JuMP model plus `constraints`/`residuals`/`meta` registries; `add_to_residual!` accumulates into a shared nodal balance (no `if formulation ==`), and `AbstractPowerFlow` + `contribute!` define the swappable-formulation contract.
- Recorded the RESEARCH Pitfall-1 correction as a doc comment in `factory.jl` (Clarabel is `copy_to`-only; never `direct_model(Clarabel...)`).

## Task Commits

Each task was committed atomically:

1. **Task 1: ProblemClass singletons + select_optimizer factory + commercial weakdep extensions (INFRA-02)** - `e1cd3fe` (feat)
2. **Task 2: ModelContext residual registry + AbstractPowerFlow contract + solve-status discipline (PF-01, INFRA-03)** - `8c4a457` (feat)

## Files Created/Modified
- `src/solver/ProblemClass.jl` - abstract `ProblemClass` + `LP`/`MILP`/`QP`/`SOCP`/`NLP` singletons + `GurobiChoice`/`MosekChoice` markers.
- `src/solver/factory.jl` - `select_optimizer(::ProblemClass)` dispatch (only core file that imports HiGHS/Clarabel/Ipopt) + `commercial_optimizer` fallback + Clarabel/`direct_model` correction note.
- `ext/TSODSOGurobiExt.jl` - adds `commercial_optimizer(::GurobiChoice, ::ProblemClass)`; loads only with Gurobi present.
- `ext/TSODSOMosekExt.jl` - adds `commercial_optimizer(::MosekChoice, ::ProblemClass)`; loads only with MosekTools present.
- `src/core/ModelContext.jl` - `mutable struct ModelContext` + `ModelContext(model)` + `register_constraint!` + accumulating `add_to_residual!`.
- `src/core/status.jl` - `assert_solved!` (INFRA-03 choke point) + `assert_no_slack` hidden-slack guard.
- `src/powerflow/AbstractPowerFlow.jl` - `abstract type AbstractPowerFlow` + `function contribute! end` contract.

## Verification

- factory @testitem GREEN: `Model(select_optimizer(LP()))` builds + solves to OPTIMAL.
- context @testitem GREEN: `add_to_residual!` twice into `:nodal_balance` accumulates; `register_constraint!` handle round-trips.
- status @testitem GREEN: optimal solve passes `assert_solved!`; infeasible model throws (fail-loud `@test_throws`).
- Grep gate CLEAN: no `using|import` of HiGHS/Clarabel/Ipopt/Gurobi/Mosek in `src/{models,core,data,units,powerflow}`.
- `Project.toml` `[deps]` contains no Gurobi/MosekTools (both `[weakdeps]` only).

Tests were run via a scratch environment that `dev`s the package alongside `TestItemRunner`+`JuMP` (the default project env lacks `TestItemRunner`, which is a test-only dep) and filtered to this worktree's `test/test_factory.jl`, `test/test_context.jl`, `test/test_status.jl`.

## Deviations from Plan

None - plan executed exactly as written. Test files (`test/test_factory.jl`, `test/test_context.jl`, `test/test_status.jl`) were already authored as Wave 0 RED @testitems in plan 01-01 and turned GREEN by the src fills; no test edits were required.

## Known Stubs

- `src/powerflow/AbstractPowerFlow.jl` — `contribute!` is an intentional contract stub with no methods (by design). Concrete DC/LinDistFlow/SOCP formulations that implement it land in Phase 2+, as specified by PF-01. Not a blocker: Phase 1 only requires the seam contract to exist.

## Self-Check: PASSED

- FOUND: src/solver/ProblemClass.jl, src/solver/factory.jl, ext/TSODSOGurobiExt.jl, ext/TSODSOMosekExt.jl, src/core/ModelContext.jl, src/core/status.jl, src/powerflow/AbstractPowerFlow.jl
- FOUND commits: e1cd3fe (Task 1), 8c4a457 (Task 2)
