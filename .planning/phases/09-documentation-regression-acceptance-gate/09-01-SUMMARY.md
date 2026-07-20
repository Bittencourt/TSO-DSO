---
phase: 09-documentation-regression-acceptance-gate
plan: 01
subsystem: docs
tags: [documenter, literate, jump, socp, lindistflow, exactness]

# Dependency graph
requires:
  - phase: 02-linear-branch-flow-residual-seam
    provides: LinDistFlow contribute!, solve_linear (rung 1-2 assembly)
  - phase: 03-prosumer-device-library-social-welfare-solve
    provides: Deferrable/Aggregator aggregatable-device contract, solve_welfare
  - phase: 04-convex-branch-flow-correctness-milestone
    provides: ConvexBranchFlow contribute! (SOCP + exactness copy), assert_socp_exact!
provides:
  - docs/literate/lindistflow.jl (Rung 1-2 literate page)
  - docs/literate/convex_branch_flow.jl (Rung 3 literate page)
affects: [09-02, 09-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Literate page = title -> math (fenced ```math``` citing thesis eq numbers) -> real construction/solve -> bare-expression validation display, replicated from docs/literate/toy_dc.jl"
    - "Every literate page calls ONLY a real src/ entrypoint (solve_linear, solve_welfare) — never a parallel/reimplemented JuMP model"

key-files:
  created:
    - docs/literate/lindistflow.jl
    - docs/literate/convex_branch_flow.jl
  modified: []

key-decisions:
  - "Substituted Deferrable for the plan-specified Interruptible device inside the Rung-3 Aggregator, because Interruptible is the self-injecting (Phase-2) device contract and Aggregator requires the aggregatable (Phase-3) contract — this is a real code-contract mismatch, not a stylistic choice"

patterns-established:
  - "Aggregatable-device contract check before wiring any device into an Aggregator page: only Deferrable/Thermostatic/PVBattery satisfy the (; vars, p_inject, utility) return contract; Interruptible is self-injecting and network-writing"

requirements-completed: [EXP-03]

# Metrics
duration: 25min
completed: 2026-07-20
---

# Phase 9 Plan 1: LinDistFlow + SOCP Convex Branch-Flow Literate Pages Summary

**Two new Documenter/Literate pages (Rung 1-2 LinDistFlow, Rung 3 SOCP + exactness copy) that call the real `solve_linear`/`solve_welfare` entrypoints and render genuine solved numbers — including the PF-04 `socp_maxgap` exactness certificate — beside the thesis equations they implement (3.31-3.33, 3.39, 3.43, 3.45).**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-07-20T11:30:55Z
- **Tasks:** 2 completed
- **Files modified:** 2 created

## Accomplishments
- `docs/literate/lindistflow.jl` proves the residual-seam contract (PF-01/PF-02) generalizes from `toy_dc.jl`'s single-node DC balance to a real 2-bus radial branch-flow network with a flexible `Interruptible` load, via the real `solve_linear` rung-1 assembly, and shows the new `:Rq` reactive residual LinDistFlow allocates.
- `docs/literate/convex_branch_flow.jl` proves the SOCP relaxation + LinDistFlow exactness copy (thesis 3.39/3.43/3.45) closes EXACT on a real feeder by calling `solve_welfare(..., ConvexBranchFlow(), ...)` and displaying `ctx.meta[:socp_maxgap]` — a genuinely solved number, not a hardcoded placeholder.
- Both pages verified via plain `julia --project=. -e 'include(...)'`, matching the acceptance criterion that they will also execute cleanly as `@example` blocks once wired into `docs/make.jl` (plan 09-04).

## Task Commits

Each task was committed atomically:

1. **Task 1: LinDistFlow literate page (rung 1-2, thesis 3.31-3.33/3.43)** - `d9bbb72` (docs)
2. **Task 2: Convex Branch-Flow + exactness literate page (rung 3, thesis 3.39/3.43-3.45, PF-04)** - `a40b255` (docs)

_Note: no TDD tasks in this plan; no test → feat → refactor split._

## Files Created/Modified
- `docs/literate/lindistflow.jl` - Rung 1-2 literate page: math (3.31/3.32/3.33/3.43) -> 2-bus radial Feeder + Interruptible device -> `solve_linear(feeder, LinDistFlow(), [device]; T=1, λ₀=[1.0])` -> displays `objective`, `dadp`, `haskey(ctx.residuals, :Rq)`
- `docs/literate/convex_branch_flow.jl` - Rung 3 literate page: math (3.39/3.43/3.45) -> 2-bus radial Feeder + Aggregator(Deferrable) -> `solve_welfare(feeder, ConvexBranchFlow(), [agg]; T=1, λ₀=[1.0], allow_export=true)` -> displays `objective`, `dadp`, `ctx.meta[:socp_maxgap]`

## Decisions Made
- Used `Deferrable` (not the plan-specified `Interruptible`) as the aggregatable member device on the Rung-3 page — see Deviations below for the reasoning.
- Kept both pages at `T = 1` (single period) to keep the literate source minimal while still exercising the real multi-bus network, matching the "math -> assumptions -> validation" structure without pulling in a 24-hour price profile that would obscure the page's point.
- Feeder fixtures mirror the shape already used by `test/test_pricing_fit.jl`'s `FitFixtures.feeder()` (Rung 1-2) and `test/test_exactness.jl`'s inline fixture (Rung 3), per the plan's explicit instruction to reuse existing fixture shapes rather than inventing new ones.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Substituted Deferrable for Interruptible inside the Rung-3 Aggregator**
- **Found during:** Task 2 (Convex Branch-Flow + exactness literate page)
- **Issue:** The plan's task text specified `Aggregator(2, φ, [Interruptible(2, Pmin, Pmax, a, b)], Pdc)`. Running this raised `FieldError: type Array has no field p_inject` from inside `Aggregator.contribute!`. Per `src/devices/AbstractDevice.jl`'s documented "TWO variants" contract, `Interruptible` is the Variant-1 SELF-INJECTING device (Phase-2 pattern: writes directly to `ctx.residuals`/objective and returns its raw variable array), while `Aggregator` (the sole network-facing writer, DEV-05) requires a Variant-2 AGGREGATABLE device that returns `(; vars, p_inject, utility)` and writes nothing itself. `Interruptible` cannot be a member of any `Aggregator` — this is a real contract mismatch in the plan's example, not a transient bug.
- **Fix:** Replaced `Interruptible(2, Pmin, Pmax, a, b)` with `Deferrable(2, 1, 1, 0.5, 1.0, 1.0)` (bus, t_start, t_end, E, Pmax, b) — `Deferrable` conforms to the aggregatable-device contract used by `Thermostatic`/`Deferrable`/`PVBattery`. Updated the page's prose to explain the two device-contract variants and why the previous page's `Interruptible` cannot be reused here.
- **Files modified:** `docs/literate/convex_branch_flow.jl`
- **Verification:** `julia --project=. -e 'include("docs/literate/convex_branch_flow.jl")'` runs to completion with no error (confirmed twice: once failing pre-fix with the `FieldError`, once passing post-fix).
- **Committed in:** `a40b255` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — device-contract mismatch)
**Impact on plan:** Necessary to make the Rung-3 page call a real, contract-compliant `src/` entrypoint at all. No scope creep — same feeder shape, same solve call, same displayed validation numbers the plan specified; only the flexible-device choice changed.

## Issues Encountered
None beyond the deviation documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Both new literate pages are standalone-includable and execute cleanly, ready to be wired into `docs/make.jl`'s `Literate.markdown`/`pages` tree by plan 09-04.
- Plan 09-02 (the remaining three literate pages: prosumer_welfare, pricing_dlmp, admm) can proceed independently — no shared state or file conflicts with this plan's two pages.
- Flag for 09-02/09-04: any future literate page that wraps a flexible device inside an `Aggregator` must use an aggregatable-contract device (`Deferrable`, `Thermostatic`, `PVBattery`) — `Interruptible` is Phase-2-only and self-injecting.

---
*Phase: 09-documentation-regression-acceptance-gate*
*Completed: 2026-07-20*

## Self-Check: PASSED

- FOUND: docs/literate/lindistflow.jl
- FOUND: docs/literate/convex_branch_flow.jl
- FOUND: .planning/phases/09-documentation-regression-acceptance-gate/09-01-SUMMARY.md
- FOUND commit: d9bbb72
- FOUND commit: a40b255
