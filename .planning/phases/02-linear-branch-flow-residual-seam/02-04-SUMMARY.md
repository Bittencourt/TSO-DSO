---
phase: 02-linear-branch-flow-residual-seam
plan: 04
subsystem: optimization-model
tags: [jump, clarabel, socp-precursor, lindistflow, dc-powerflow, duals, dadp, tdd]

# Dependency graph
requires:
  - phase: 02-01
    provides: ModelContext indexed :Rp/:Rq residual accumulator + add_to_objective! (QuadExpr welfare)
  - phase: 02-02
    provides: DCPowerFlow / LinDistFlow contribute! into the shared per-bus residual
  - phase: 02-03
    provides: Interruptible device (concave-quadratic utility, signed :Rp injection, network-agnostic)
provides:
  - "solve_linear(feeder, pf, devices; T, λ₀) -> (ctx, objective, dadp): the rung-1 centralized linear assembly that produces the FIRST distribution price"
  - "Data-driven residual closure (haskey(:Rq)) that closes whatever residuals a formulation populated — zero formulation branching"
  - "Interface-conformance guarantee: DC↔LinDistFlow swap changes only the pf argument (identical objective + DADP)"
  - "Analytic first-price fixture: DADP=λ₀, p*=(a−λ₀)/b derived from fixture coefficients"
affects: [phase-03-aggregator, phase-04-socp-exactness, phase-05-price-decomposition, phase-06-admm]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Centralized single-solve assembly generalizing toy_dc to a real feeder + swappable formulation + device vector"
    - "Close-every-present-residual via haskey (registry contents), never `if formulation ==`"
    - "Priced frontier import injected at root like a device (+p_import), objective Σ utility − λ₀ᵀ·p_import (thesis 3.38 shape)"
    - "Dual read only after assert_solved!(dual=true); DADP = dual(:balance_p[load_bus,:])"

key-files:
  created:
    - .planning/phases/02-linear-branch-flow-residual-seam/02-04-SUMMARY.md
  modified:
    - src/models/linear_solve.jl
    - test/test_linear_solve.jl
    - test/test_conformance.jl

key-decisions:
  - "Stash device variables under ctx.meta[:device_vars] (and p_import under ctx.meta[:p_import]) so the analytic test can assert value(p) == (a−λ₀)/b without re-deriving the served power"
  - "Reworded docstrings/comments to avoid the literal tokens `Clarabel`/`HiGHS` and `if formulation ==` so the threat-mitigation grep gates (T-02-10, T-02-04) pass on the source text, not just the code"

patterns-established:
  - "solve_linear is the rung-1 price seam: every later rung (aggregator, SOCP, decomposition) swaps pieces behind this same assembly contract"
  - "The nodal-balance dual at the priced bus is the DADP; sign anchored positive to the toy_dc convention"

requirements-completed: [PF-02, DEV-03]

# Metrics
duration: 12min
completed: 2026-07-18
---

# Phase 2 Plan 04: Linear Central Assembly & First Price Summary

**`solve_linear` assembles any AbstractPowerFlow + devices into one QP, closes the nodal balance data-driven (no formulation branching), and returns the first distribution price (DADP = dual of the active balance) — validated analytically (DADP=λ₀, p*=(a−λ₀)/b) and proven formulation-swappable (DC≡LinDistFlow).**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-07-18T18:51Z
- **Completed:** 2026-07-18T19:03Z
- **Tasks:** 2 (both TDD)
- **Files modified:** 3 (1 source, 2 tests)

## Accomplishments
- Implemented `solve_linear(feeder, pf, devices; T, λ₀) -> (ctx, objective, dadp)` — the earliest point a real feeder-based linear model produces a distribution price.
- Assembly closes every residual present via `haskey(ctx.residuals, :Rq)` (active always, reactive only when the formulation populated it) — data-driven on registry contents, no `if formulation ==` branch, no concrete solver named (`select_optimizer(QP())`).
- Priced frontier import injected at the root; welfare `Σ utility − λ₀ᵀ·p_import`; OPTIMAL gate via `assert_solved!(dual=true)` before any dual read; DADP recovered as `dual(:balance_p[load_bus,:])`.
- Analytic 2-bus loss-less first-price test: `DADP ≈ λ₀`, positive sign, `p* ≈ (a−λ₀)/b` — expectations DERIVED from fixture coefficients, not hard-coded.
- Interface-conformance test: identical objective and DADP for DCPowerFlow vs LinDistFlow, only the `pf` argument changing (criterion 4 as an automated test).

## Task Commits

Each task was committed atomically (TDD RED → GREEN):

1. **Task 1 (RED): analytic first-price test** - `232616e` (test)
2. **Task 1 (GREEN): implement solve_linear** - `77ba3a2` (feat)
3. **Task 2: DC↔LinDistFlow conformance test** - `1e2f578` (test)

**Plan metadata:** (this SUMMARY) — `docs(02-04)`

## Files Created/Modified
- `src/models/linear_solve.jl` - `solve_linear` centralized assembly: contribute! fan-in, frontier import, data-driven balance closure, welfare objective, OPTIMAL gate, DADP extraction.
- `test/test_linear_solve.jl` - `:linear` @testitem: analytic 2-bus first price (DADP=λ₀, p*=(a−λ₀)/b, positive sign, OPTIMAL, :balance_p registered).
- `test/test_conformance.jl` - `:conformance` @testitem: DC≡LinDistFlow equal objective + DADP, both matching the derived closed form.

## Decisions Made
- **Stash device/import variables in `ctx.meta`.** `solve_linear` records `ctx.meta[:device_vars]` (the vector of served-power variables returned by each device's `contribute!`) and `ctx.meta[:p_import]`. This lets the analytic test assert `value(p) ≈ (a−λ₀)/b` directly instead of re-deriving it from the frontier flow, and gives later rungs a handle on the primal solution.
- **Docstring wording vs. threat-mitigation grep gates.** The acceptance criteria are literal grep gates (T-02-10 forbids solver names in the model file; T-02-04 forbids `if formulation ==`). Explanatory comments originally named `Clarabel`/`HiGHS` and quoted the `if formulation ==` anti-pattern; these were reworded (e.g. "the QP factory backend", "branching on the formulation type") so the source text passes the gates while retaining the pedagogical intent.

## Deviations from Plan

None - plan executed exactly as written. (The comment rewording above is a wording choice to satisfy the plan's own literal grep gates, not a behavioral deviation.)

## Issues Encountered
- The quick-run command in the plan/RESEARCH (`julia --project=. -e 'using TestItemRunner; ...'`) fails because `TestItemRunner` is a test-env dependency, not a main-project dep. Used the authoritative `julia --project=. -e 'using Pkg; Pkg.test()'` for RED/GREEN verification instead. Not a code issue.

## Verification
- RED baseline: 116 pass, new analytic test errored (solve_linear undefined) — confirmed before implementing.
- After Task 1 GREEN: 121 pass, 0 fail, 0 error.
- After Task 2 (phase gate): **127 pass, 0 fail, 0 error** (full suite incl. rung-0 toy_dc regression and Aqua) on Julia 1.12.5.
- Grep gates: no concrete solver name in `linear_solve.jl`; no `if formulation ==` / `== :dc` / `== :lindist`; `haskey(ctx.residuals, :Rq)` present; `select_optimizer(QP())` present; `assert_solved!` precedes `dual.(`.

## Next Phase Readiness
- The rung-1 price seam is live: Phase 3 (aggregator roll-up) and Phase 4 (SOCP exactness) swap pieces behind the same `solve_linear` assembly contract without touching device or closure code.
- STATE.md / ROADMAP.md intentionally NOT updated by this executor (parallel-wave policy); orchestrator will reconcile.

## Self-Check: PASSED

---
*Phase: 02-linear-branch-flow-residual-seam*
*Completed: 2026-07-18*
