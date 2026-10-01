---
phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder
plan: 03
subsystem: testing
tags: [jump, clarabel, socp, benders, ieee13, testitems]

# Dependency graph
requires:
  - phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder (plans 30-01/30-02/30-04)
    provides: the oracle-feasibility-cut (BILEV-04a), AC-recheck (BILEV-04b), and
      inexact_policy/:auto-bound (BILEV-04b/BILEV-05) wiring that plan 30-05's BILEV-03
      convergence @testitem will need alongside this plan's fixture
provides:
  - "@testmodule IEEE13ShortHorizonFixtures (test/fixtures_planning_ieee13_short.jl):
    a tuned, T=4 IEEE-13 aggregator population where z=zeros(T) is confirmed
    oracle-feasible and SOCP-exact"
  - "A measured feasible/exact/inexact/infeasible sweep map over z in [-0.1, 0.07] pu/hr
    for this exact population, documented in the fixture's own header comment"
  - "solve_joint_reference: an independently-built (from scratch, never reusing
    PlanningOracle/FollowerLP/BendersMaster) monolithic single-shot SOCP model for the
    BILEV-03 convergence cross-check, with its UB <-> -welfare_total sign convention
    documented"
affects: [30-05-benders-ieee13-convergence]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Build-once JuMP model reusing contribute!(pf, ctx, feeder; T) + aggregator
      contribute! loop verbatim, mirroring build_planning_oracle's own shape but with
      z[t] as a genuine bounded @variable (not a Parameter pin) for the non-decomposed
      joint reference"
    - "Fixture tuning evidence documented in the module's own header comment (measured
      z=0 probe output + sweep table), never asserted without a fresh re-run"

key-files:
  created:
    - test/fixtures_planning_ieee13_short.jl
    - test/test_planning_ieee13_short_fixture.jl
  modified: []

key-decisions:
  - "Chose T=4 (within the CONTEXT.md-mandated T in [3,6] range)."
  - "Re-probed RESEARCH.md's own exploratory T=4 recipe verbatim (load_scale=0.01,
    pv_scale=0.03, batt_pmax=0.02, batt_emax=0.1, batt_soc0=0.05) against the CURRENT
    codebase state rather than assuming RESEARCH.md's older infeasibility finding still
    holds: z=zeros(4) is NOW oracle-feasible and SOCP-exact on this population (measured
    cost=-609.0471557105552, maxgap=2.24e-10) -- no magnitude retuning was actually
    needed. This is a found discrepancy with RESEARCH.md (likely due to Phase 26-29
    exactness/complementarity-gate fixes landing between RESEARCH.md's probe and this
    plan's execution), reported rather than silently reconciled."
  - "solve_joint_reference reuses z[t] as BOTH the frontier import and the follower's
    delivered flow (no separate p_import/x_op), per the plan's own interface recipe,
    folding the follower's capacity limit into the invest_op constraint directly."

requirements-completed: [BILEV-03]

# Metrics
duration: ~25min
completed: 2026-10-01
---

# Phase 30 Plan 03: Tuned IEEE-13 Fixture + Independent Joint Reference Summary

**Built a tuned, T=4 IEEE-13 aggregator population fixture (z=0 oracle-feasible and
SOCP-exact, confirmed by direct probe) plus an independently-built monolithic
joint-reference SOCP solver for BILEV-03's convergence cross-check, both smoke-tested.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-10-01
- **Tasks:** 2/2 completed
- **Files modified:** 2 (both new)

## Accomplishments

- `test/fixtures_planning_ieee13_short.jl` (`@testmodule IEEE13ShortHorizonFixtures`): a
  T=4-parametrized IEEE-13 aggregator population (PVBattery + Thermostatic only, never
  `Deferrable`), confirmed by a direct `solve_planning_oracle!` probe to have
  `z=zeros(4)` oracle-feasible and SOCP-exact
  (`cost=-609.0471557105552`, `maxgap=2.2407826061415185e-10`).
- A measured feasible/exact/inexact/infeasible sweep map across `z in {-0.1, -0.08,
  -0.05, ..., 0.05, 0.06, 0.0686, 0.07}` pu/hr, documented in the fixture module's own
  header comment as the authoritative reference for plan 30-05's convergence test.
- `solve_joint_reference`: an independently-built (from scratch, reusing ONLY
  `contribute!`/`add_to_residual!`/`register_constraint!` — never
  `PlanningOracle`/`FollowerLP`/`BendersMaster`) single-shot monolithic SOCP model
  representing the SAME integrated problem `solve_stackelberg!` Benders-decomposes, with
  its `UB ≈ -welfare_total` sign relationship documented in its own docstring.
- `test/test_planning_ieee13_short_fixture.jl`: one `@testitem` smoke-testing
  `solve_joint_reference` on the fixture's own population; verified via the TestItemRunner
  emulator (3/3 assertions pass in ~39s, well inside the ≤2 min in-suite budget).

## Task Commits

Each task was committed atomically:

1. **Task 1: Tuned T-parametrized IEEE-13 population (z=0 feasible)** - `e152796` (test)
2. **Task 2: Independent monolithic joint-reference solver + smoke test** - `2979978` (test)

_Note: Task 1's commit (`e152796`) includes `solve_joint_reference` in the same file
write as the population builder — see Deviations below._

## Files Created/Modified

- `test/fixtures_planning_ieee13_short.jl` - `@testmodule IEEE13ShortHorizonFixtures`:
  `T`, `LAMBDA0`, `house_agg`, `population`, `solve_joint_reference`, plus the
  tuning-evidence header comment (z=0 probe output + sweep map table).
- `test/test_planning_ieee13_short_fixture.jl` - one `@testitem` smoke-testing
  `solve_joint_reference` against the fixture's own population.

## Decisions Made

- **T=4** chosen (Claude's discretion, within CONTEXT.md's `T ∈ [3,6]` range).
- **No population retuning was actually needed.** RESEARCH.md's own exploratory T=4
  recipe (`load_scale=0.01, pv_scale=0.03, batt_pmax=0.02, batt_emax=0.1,
  batt_soc0=0.05`), re-probed fresh this session against the current codebase state,
  already has `z=zeros(T)` oracle-feasible and SOCP-exact — unlike RESEARCH.md's own
  earlier (pre Phase 26-29 fix) measurement of the identical recipe as `MOI.INFEASIBLE`
  at `z=0`. This discrepancy is documented in the fixture's own header comment rather
  than silently assumed away; the measured sweep map also matches RESEARCH.md's reported
  `z=0.06` inexactness ratio (≈4852×) almost exactly, confirming the recipe itself is
  unchanged — only the project's own exactness/complementarity gates evolved.
- **`solve_joint_reference`** follows the plan's own `<interfaces>` recipe verbatim
  (reusing `z[t]` as both frontier import and follower-delivered flow), with the
  `balance_p`/`balance_q` closure pattern copied from `build_planning_oracle`.
- Smoke-test tuple (`c_y=0.01, y_max=0.05, corridor_cap=1.0, x_inv_max=0.05, c_inv=0.01,
  c_op=fill(0.01,T)`) chosen to stay inside the fixture's own measured feasible-and-exact
  `z ∈ [-0.05, 0.05]` window; the joint solve converges with `y=x_inv≈0.05` (the box
  binds) and all `z[t] ≥ 0`.

## Deviations from Plan

### Auto-fixed Issues

None — no Rule 1/2/3 auto-fixes were needed.

### Other Deviations

**1. Task-boundary file overlap (not a Rule violation, documentation-only)**
- **Found during:** writing Task 1's deliverable.
- **Issue:** The plan's Task 1 lists only `test/fixtures_planning_ieee13_short.jl` as its
  file, with `solve_joint_reference` scoped to Task 2 (which also touches the same
  file). The fixture module was authored as a single `Write` covering both the
  population builder (Task 1) and `solve_joint_reference` (Task 2) before the first
  commit, since both were designed together for internal consistency (shared `T`,
  `LAMBDA0`, and population builder reused by `solve_joint_reference`'s own smoke test).
- **Resolution:** Task 1's commit (`e152796`) therefore already contains
  `solve_joint_reference`; Task 2's commit (`2979978`) adds only the new test file. Both
  tasks' acceptance criteria and `<verify>` scripts were independently run and passed
  (Task 1's direct-script probe; Task 2's `@testitem` emulator run) before their
  respective commits, so no verification step was skipped — only the commit boundary
  shifted slightly from the plan's literal per-task file split.
- **Files affected:** `test/fixtures_planning_ieee13_short.jl`.
- **Committed in:** `e152796` (Task 1 commit).

---

**Total deviations:** 1 (documentation-only, no behavior/scope impact)
**Impact on plan:** None on substance — both tasks' acceptance criteria were verified
independently and in the plan's own specified order before each commit.

## Issues Encountered

- `@testmodule`/`@testitem` do not resolve when a fixture file is `include`d directly
  outside the TestItemRunner harness (`UndefVarError: @testmodule not defined`,
  `TestItems` package import alone is insufficient either — its real `@testmodule`
  macro only registers with the runner, it does not define a plain top-level module when
  `include`d standalone). Resolved per this repo's known TestItemRunner trap: used the
  provided top-level `@testmodule`/`@testitem` emulator (copied to this agent's own
  scratch location, `ROOT` repointed at this worktree's `test/` directory) to run Task
  2's `@testitem`, and a minimal inline `@testmodule` macro definition for Task 1's
  plain verify script.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 30-05 (wave 3) can now consume `IEEE13ShortHorizonFixtures` via
  `setup=[IEEE13ShortHorizonFixtures]` for the BILEV-03 convergence `@testitem`: the
  population, `T`, `LAMBDA0`, and `solve_joint_reference` (with its documented
  `UB ≈ -welfare_total` sign convention) are all available and independently verified.
- No blockers. The measured feasible-and-exact `z ∈ [-0.05, 0.05]` window (wider than
  RESEARCH.md's older `[0.01, 0.05]` estimate) gives plan 30-05 more room to choose a
  `y_max`/`corridor_cap` that keeps the Benders loop's natural trial range inside the
  exact region for a "clean" convergence demonstration, per 30-RESEARCH.md's Open
  Question 2 resolution.

---
*Phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder*
*Completed: 2026-10-01*

## Self-Check: PASSED

- FOUND: test/fixtures_planning_ieee13_short.jl
- FOUND: test/test_planning_ieee13_short_fixture.jl
- FOUND: .planning/phases/30-socp-in-the-loop-benders-on-a-multi-bus-feeder/30-03-SUMMARY.md
- FOUND: commit e152796 (Task 1)
- FOUND: commit 2979978 (Task 2)
