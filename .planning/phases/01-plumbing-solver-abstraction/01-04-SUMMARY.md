---
phase: 01-plumbing-solver-abstraction
plan: 04
subsystem: infra
tags: [jump, highs, clarabel, documenter, literate, testitems, dual, socp-lp]

# Dependency graph
requires:
  - phase: 01-plumbing-solver-abstraction (plan 01-02)
    provides: Feeder/Bus/Branch immutable data model, PerUnitBase, assert_magnitudes
  - phase: 01-plumbing-solver-abstraction (plan 01-03)
    provides: select_optimizer(::ProblemClass) factory, ModelContext + residual registry, register_constraint!/add_to_residual!, assert_solved! status choke point
provides:
  - solve_toy_dc(feeder) walking-skeleton build+solve returning (ctx, objective, nodal-balance dual)
  - end-to-end integration across every Phase-1 seam (data → factory → residual registry → status → price)
  - executable Documenter+Literate reproducibility pipeline (docs/make.jl + docs/literate/toy_dc.jl)
affects: [phase-02-powerflow, phase-05-pricing, phase-06-admm, phase-09-docs]

# Tech tracking
tech-stack:
  added: [Documenter 1.17, Literate 2.21 (docs env only)]
  patterns:
    - "Model built via Model(select_optimizer(LP())) — model files never name a concrete solver (INFRA-02)"
    - "Nodal balance routed through ctx.residuals[:nodal_balance] even at single-node rung 0 (PF-01 accumulation seam)"
    - "Solve returns only after assert_solved!(...; dual=true, allow_local=false) (INFRA-03 choke point)"
    - "Literate @example blocks execute the real solve during makedocs — docs cannot drift from code"

key-files:
  created:
    - docs/make.jl
    - docs/literate/toy_dc.jl
    - docs/src/index.md
    - docs/Project.toml
    - docs/Manifest.toml
    - test/Manifest.toml
  modified:
    - src/models/toy_dc.jl
    - test/test_toy_dc.jl
    - test/Project.toml
    - .gitignore

key-decisions:
  - "Route the single-node nodal balance through the shared residual registry so Phase 2 branch-flow contributes with no if-formulation branching"
  - "Return dual(balance) now — the price/DADP seam consumed from Phase 5 onward"
  - "Documenter build uses remotes=nothing so it succeeds in a bare/worktree checkout"
  - "Wire JuMP Parameter pattern as a commented example for Phase 6 ADMM (wired-but-unused)"

patterns-established:
  - "Pattern: solver-agnostic model build via ProblemClass dispatch"
  - "Pattern: shared nodal-balance residual accumulation (PF-01) exercised from rung 0"
  - "Pattern: reproducible executable docs via Literate → Documenter @example"

requirements-completed: [INFRA-02, INFRA-03, PF-01]

# Metrics
duration: ~35min
completed: 2026-07-18
---

# Phase 1 Plan 04: Toy DC Walking Skeleton Summary

**solve_toy_dc closes the walking skeleton — a single-node DC solve built via select_optimizer(LP()), routed through the ctx.residuals[:nodal_balance] seam, gated by assert_solved!, returning objective + nodal-balance dual; plus an executable Literate/Documenter reproducibility page.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-07-18
- **Tasks:** 2
- **Files modified/created:** 10

## Accomplishments
- Filled `src/models/toy_dc.jl`: `solve_toy_dc(feeder)` builds `Model(select_optimizer(LP()))` (no concrete solver named), stashes the feeder in `ctx.meta`, adds `p_import`/`p_load`, routes the nodal balance through `add_to_residual!(ctx, :nodal_balance, …)` + `register_constraint!(ctx, :balance, …)`, maximises toy welfare, solves through `assert_solved!(model; dual=true, allow_local=false)`, and returns `(ctx, objective_value(model), dual(balance))`.
- Drove the `toy: rung0` @testitem GREEN — full `Pkg.test()` now reports 44 pass, 0 failed, 0 errored (Aqua/JET included).
- Created the executable docs pipeline: `docs/literate/toy_dc.jl` documents the per-unit base (S_base=1 MVA, V_base=4.16 kV placeholder) and toy DC math, then runs the real `solve_toy_dc`; `docs/make.jl` renders it via Literate and executes it during `makedocs` (built HTML shows objective=2.0, dual=1.0).
- Wired the commented JuMP `Parameter` pattern for Phase 6 ADMM (wired-but-unused).

## Task Commits

1. **Task 1: End-to-end toy DC single-node solve through all seams (rung 0)** — `dfa96b8` (feat, tdd)
2. **Task 2: Literate rung-0 doc page + Documenter wiring** — `f2a8cba` (docs)

_TDD note: the RED `toy: rung0` @testitem was already committed in Wave 0 (`30c7e24`); this plan drove it GREEN (feat gate) — no separate test commit needed._

## Files Created/Modified
- `src/models/toy_dc.jl` — filled the rung-0 walking-skeleton `solve_toy_dc`; no concrete solver named; PF-01 residual seam exercised; returns objective + dual.
- `test/test_toy_dc.jl` — added `using JuMP` for `is_solved_and_feasible` (matches `test_factory.jl`/`test_status.jl`).
- `test/Project.toml` / `test/Manifest.toml` — added JuMP to test deps (+ committed lock).
- `docs/make.jl` — Documenter build running Literate over the toy page; `@example` blocks execute the solve.
- `docs/literate/toy_dc.jl` — executable Literate source documenting per-unit base + toy math.
- `docs/src/index.md`, `docs/Project.toml`, `docs/Manifest.toml` — docs environment + homepage.
- `.gitignore` — ignore Literate-generated `/docs/src/generated/`.

## Decisions Made
- Kept rung 0 strictly single-node (RESEARCH Open-Question 2, RESOLVED) but still routed the balance through the shared residual registry so the PF-01 seam is genuinely exercised.
- Returned `dual(balance)` immediately — the price/DADP seam future phases trust.
- `remotes=nothing` in `makedocs` so the docs build succeeds without a configured git remote (worktree/bare checkout).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added JuMP to the test environment deps**
- **Found during:** Task 1 (running the full suite)
- **Issue:** `test_toy_dc.jl` (and the pre-existing `test_factory.jl`, `test_status.jl`, `test_context.jl` owned by plan 01-03) all `using JuMP`, but JuMP was absent from `test/Project.toml` deps. Under `Pkg.test()` on Julia 1.12.5 with a freshly resolved test environment, all four @testitems errored with "Package JuMP not found in current path". This blocked the plan's success criterion (full suite 0 errored).
- **Fix:** Added `JuMP = "4076af6c-…"` to `test/Project.toml [deps]` (JuMP is already the project's core, pinned dependency — not a new/untrusted package) and committed the resolved `test/Manifest.toml` per the repo's INFRA-01 Manifest-commit policy.
- **Verification:** `julia --project=. -e 'import Pkg; Pkg.test()'` → 44 pass, 0 failed, 0 errored.
- **Committed in:** `dfa96b8` (Task 1 commit)

**2. [Rule 3 - Blocking] `remotes=nothing` in Documenter makedocs**
- **Found during:** Task 2 (first docs build)
- **Issue:** `makedocs` errored because Documenter could not infer the git repository remote in the worktree/bare checkout ("Configure `repo` and/or `remotes` appropriately…").
- **Fix:** Passed `remotes = nothing` to `makedocs` (disables per-line source links; a pipeline proof does not need them; re-enable on CI deploy).
- **Verification:** `include("docs/make.jl")` exits 0; built HTML shows the executed toy-solve results.
- **Committed in:** `f2a8cba` (Task 2 commit)

**3. [Rule 3 - Housekeeping] Ignore Literate-generated markdown**
- **Found during:** Task 2
- **Issue:** `docs/src/generated/toy_dc.md` is regenerated on every build; leaving it untracked would clutter the tree.
- **Fix:** Added `/docs/src/generated/` to `.gitignore` (alongside the existing `/docs/build/`).
- **Committed in:** `f2a8cba` (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (3 blocking/housekeeping, all Rule 3)
**Impact on plan:** All fixes were configuration/environment corrections required to meet the plan's own success criteria. No source behavior changed beyond the planned `solve_toy_dc`. The JuMP-test-dep fix also un-broke three sibling testitems from plan 01-03 that shared the same missing-dependency root cause. No scope creep.

## Issues Encountered
- The orchestrator baseline described only `toy: rung0` as RED; in the fresh Julia 1.12.5 test resolve, three additional JuMP-importing testitems (`factory`, `status`, `context`) also errored on the missing JuMP test dep. Resolving the shared root cause (deviation 1) turned all of them green together.

## Threat Coverage
- **T-01-06 (Tampering):** `solve_toy_dc` returns only after `assert_solved!(…; allow_local=false)` — mitigated.
- **T-01-07 (Tampering):** model built via `select_optimizer(LP())`; grep confirms no HiGHS/Clarabel/Ipopt/Gurobi/Mosek name in `src/models/toy_dc.jl` — mitigated.
- **T-01-09 (Repudiation):** the Literate page executes the real `solve_toy_dc` during the Documenter build (`@example` blocks), so the doc cannot pass while diverging from the code — mitigated.

No new threat surface introduced.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The full Phase-1 spine is proven end-to-end: data → factory → residual registry → status → objective + dual.
- Phase 2 can add an `AbstractPowerFlow` (DC/LinDistFlow) `contribute!` method writing into `ctx.residuals[:nodal_balance]` with no changes to the `solve_toy_dc` call site.
- Phase 5 has the nodal-balance dual seam available; Phase 6 has the commented `Parameter` pattern ready for ADMM re-solves.
- Phase gate note (INFRA-01): CI matrix on Julia 1.10 LTS + 1.11 (+1.12) should be confirmed green before `/gsd:verify-work`; verified locally on 1.12.5.

---
*Phase: 01-plumbing-solver-abstraction*
*Completed: 2026-07-18*

## Self-Check: PASSED

All created files exist on disk and both task commits (`dfa96b8`, `f2a8cba`) are present in git history.
