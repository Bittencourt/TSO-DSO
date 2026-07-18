---
phase: 02-linear-branch-flow-residual-seam
plan: 02
subsystem: powerflow
tags: [jump, lindistflow, dc-power-flow, dispatch, residual-seam, socp-precursor]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: AbstractPowerFlow contract, ModelContext residual registry, Feeder/Branch data model, select_optimizer factory
  - phase: 02-01
    provides: indexed add_to_residual!(ctx, name, i, t, expr) Matrix{AffExpr} accumulator + add_to_objective! QuadExpr accumulator
provides:
  - DCPowerFlow concrete AbstractPowerFlow subtype (active-only, :Rp only) with dispatched contribute!
  - LinDistFlow concrete AbstractPowerFlow subtype (:Rp + :Rq + squared-voltage v + 3.43 voltage drop) with dispatched contribute!
  - test/test_powerflow.jl residual-contribution unit tests against a bare ModelContext (no assembly)
affects: [02-03 devices, 02-04 linear_solve assembly, 04-socp exact branch flow]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Formulation-as-type: concrete AbstractPowerFlow subtypes selected purely by Julia dispatch (no if formulation ==)"
    - "Per-bus/time residual accumulation: inflow − outflow of P into :Rp, Q into :Rq via indexed add_to_residual!"
    - "Squared-voltage LinDistFlow: v = |V|², root fixed at 1.0, non-root bounds squared (vmin²/vmax²)"

key-files:
  created:
    - src/powerflow/DCPowerFlow.jl
    - src/powerflow/LinDistFlow.jl
    - test/test_powerflow.jl
  modified: []

key-decisions:
  - "DC writes only :Rp and never allocates :Rq or a voltage variable (active-only linearization; RESEARCH A3/Open-Q3)"
  - "LinDistFlow root squared voltage fixed via fix(...; force=true); non-root buses skip bound-setting on the root to avoid conflicting with the fix"
  - "Voltage-drop constraint named `vdrop` (registered in the model object dictionary) so tests can assert its presence/count"
  - "pf_vars = (; v, P, Q) stashed in ctx.meta for post-solve inspection and the Phase-4 exactness check"

patterns-established:
  - "Pattern 1: dispatched contribute!(::Formulation, ctx, feeder; T) writing the shared residual — zero formulation branching"
  - "Pattern (Pitfall 1 guard): square the magnitude pu bounds at the model boundary for squared-voltage variables"

requirements-completed: [PF-02]

# Metrics
duration: ~20min
completed: 2026-07-18
---

# Phase 2 Plan 02: Linear Branch-Flow Formulations (DC + LinDistFlow) Summary

**DCPowerFlow (active-only :Rp) and LinDistFlow (loss-less branch flow with squared-voltage v, the thesis-3.43 voltage drop, and :Rp+:Rq balances) as dispatch-selected AbstractPowerFlow subtypes writing only into the shared residual seam.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-07-18
- **Tasks:** 2
- **Files modified:** 3 (2 source, 1 test)

## Accomplishments
- `DCPowerFlow` contributes a per-bus active balance (inflow − outflow of branch active flow `P`) into `ctx.residuals[:Rp]` — thesis eq. 3.31 with losses dropped — and allocates no `:Rq` and no voltage variable.
- `LinDistFlow` contributes active (`:Rp`, 3.31) and reactive (`:Rq`, 3.32) balances, a squared-voltage variable `v = |V|²` (root fixed at 1.0, non-root bounds `vmin²`/`vmax²`), and the loss-less voltage-drop constraint `vdrop: v_to == v_from − 2(rP + xQ)` (thesis 3.43, l→0).
- Both formulations are selected purely by Julia multiple dispatch — no `if formulation ==` / string-compare branching (grep-gate clean in both files).
- New `test/test_powerflow.jl` exercises both formulations against a bare `ModelContext` (no assembly/device code): residual shape/type, per-bus inflow−outflow structure, `!haskey(:Rq)` for DC, squared bounds + root fix + `vdrop` presence for LinDistFlow, and a 2-bus loss-less identity `p_import == p_load` solved via HiGHS.

## Task Commits

Each task was committed atomically:

1. **Task 1: DCPowerFlow (active-only) with dispatched contribute!** - `5105899` (feat)
2. **Task 2: LinDistFlow (loss-less branch flow + squared voltage) with dispatched contribute!** - `006a9eb` (feat)

_TDD flow per task: RED-first @testitem written and verified failing, then GREEN implementation._

## Files Created/Modified
- `src/powerflow/DCPowerFlow.jl` - `struct DCPowerFlow <: AbstractPowerFlow` + dispatched `contribute!` writing active-only `:Rp` (thesis 3.31, loss-less); exports `DCPowerFlow`.
- `src/powerflow/LinDistFlow.jl` - `struct LinDistFlow <: AbstractPowerFlow` + dispatched `contribute!` creating `v`/`P`/`Q`, squared-voltage bounds + root fix, `vdrop` (3.43), and `:Rp`/`:Rq` balances; exports `LinDistFlow`.
- `test/test_powerflow.jl` - `powerflow` and `lindistflow` @testitems (residual structure + 2-bus loss-less identity).

## Decisions Made
- LinDistFlow skips bound-setting on the root bus (it is already `fix`ed at 1.0); setting bounds on a fixed variable is redundant/conflicting, so the loop `continue`s past `feeder.root`.
- The voltage-drop constraint is given the name `vdrop` so its presence and per-branch/time count are directly assertable via `object_dictionary`.
- Kept the T=1 fixtures for exact structural/analytic checks while coding all indices as `(bus, t)` so Phase-3 multi-period is additive (RESEARCH Alternatives / A2).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed a type mismatch in the DC test assertions**
- **Found during:** Task 1 (DCPowerFlow test, GREEN step)
- **Issue:** `isequal_canonical(::AffExpr, ::VariableRef)` has no method — a leaf-bus residual was compared against a bare `VariableRef` (`P[b,t]`) instead of an `AffExpr`.
- **Fix:** Promoted the RHS to an `AffExpr` (`1.0 * P[b,t]`) in the two affected assertions.
- **Files modified:** test/test_powerflow.jl
- **Verification:** powerflow filter 9/9 assertions pass.
- **Committed in:** `5105899` (Task 1 commit)

**2. [Rule 1 - Bug] Reworded a source comment that tripped the no-branching grep gate**
- **Found during:** Task 1 (grep-gate check)
- **Issue:** A descriptive comment literally contained `if formulation ==`, which the acceptance grep `grep -nE 'if .*formulation *=='` flags as a false positive.
- **Fix:** Reworded the comment to "no formulation-flag branching anywhere".
- **Files modified:** src/powerflow/DCPowerFlow.jl
- **Verification:** grep gate returns clean (no matches) for both files.
- **Committed in:** `5105899` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs, both in test/comment text — not in production logic).
**Impact on plan:** Both were mechanical corrections to make the acceptance checks pass; no scope creep, no model-logic change.

## Issues Encountered
- `TestItemRunner` lives only in `test/Project.toml`, so the plan's `@run_package_tests` filter command cannot run from the default project. Resolved by building a throwaway scratch environment (`dev` the worktree package + add `TestItemRunner`) and running the filtered items with the repo as the active project and the scratch env on `JULIA_LOAD_PATH`. The authoritative full run (`Pkg.test()`) uses the real test env and passed 87/87.

## Known Stubs
None — both formulations are fully implemented; no placeholder/empty-return paths.

## Verification
- `powerflow` + `lindistflow` filtered @testitems: **GREEN** (25 assertions across 4 items).
- Full suite `julia --project=. -e 'using Pkg; Pkg.test()'`: **87/87 pass**, including Aqua (new exports introduce no ambiguities/stale deps) and the rung-0 `toy_dc` regression — no regression.
- Grep gate `grep -nE 'if .*formulation *==|== *:dc|== *:lindist'`: clean in both source files.

## Next Phase Readiness
- The residual seam now carries two swappable multi-bus network formulations by dispatch; wave-3 assembly (`02-04 linear_solve`) can close `:Rp` (always) and `:Rq` (via `haskey`) with zero formulation branching.
- No edits made outside `src/powerflow/` + `test/test_powerflow.jl`; devices/core/assembly untouched (parallel-executor boundary respected).

## Self-Check: PASSED
- Files: DCPowerFlow.jl, LinDistFlow.jl, test_powerflow.jl, 02-02-SUMMARY.md all present.
- Commits: 5105899 (Task 1), 006a9eb (Task 2) present in git log.

---
*Phase: 02-linear-branch-flow-residual-seam*
*Completed: 2026-07-18*
