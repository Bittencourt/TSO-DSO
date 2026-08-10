---
phase: 22-stochastic-pv-demand-uncertainty
plan: 01
subsystem: testing
tags: [julia, jump, scenario-schema, testitems, ci-fixture]

# Dependency graph
requires:
  - phase: 21-mpc-rolling-horizon-rtp
    provides: "mpc_* additive @kwdef field precedent on Scenario.jl (D-12 boundary-guard
      pattern this plan mirrors) and fixtures_phase21.jl's @testmodule structural shape"
provides:
  - "Scenario.jl stoch_S/stoch_probabilities/stoch_H_oos additive @kwdef fields with
    construction-time ArgumentError validation (D-01/D-04/D-10)"
  - "Phase22Fixtures @testmodule: a small, Deferrable-free, solvable/exact 2-bus radial CI
    fixture producing disjoint-seeded scenario aggregator populations (D-12)"
affects: ["22-02", "22-03", "22-04", "22-05"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Empty-vector sentinel resolved to a materialized default inside the inner constructor
      before it reaches new(...) — never left ambiguous on a constructed struct"

key-files:
  created: [test/fixtures_phase22.jl]
  modified: [src/experiments/Scenario.jl]

key-decisions:
  - "stoch_probabilities uses an empty-Vector{Float64} sentinel (not Union{Nothing,...} or a
    default-uniform literal) because @kwdef field defaults cannot self-reference the sibling
    stoch_S default; the sentinel is resolved inside the inner constructor so no constructed
    Scenario ever stores the ambiguous empty vector (D-04)."
  - "stoch_S locked to [3,5] and stoch_H_oos locked to [5,10] via construction-time
    ArgumentError, mirroring the project's threat T-08-05 'checked LOUDLY, never @assert'
    convention already used for the mpc_* D-12 block."
  - "Phase22Fixtures excludes the Deferrable device entirely (not just at short-T like Phase
    21's fixture) because the extensive-form builder (plan 22-02) will duplicate each
    aggregator once per in-sample scenario under nonanticipativity ties; an S-way duplication
    of a Deferrable energy budget would add cost with no fixture-scale benefit."

patterns-established:
  - "Additive stochastic-only Scenario fields are no-ops for :centralized/:admm/run_mpc — read
    only by the future run_stochastic(scenario) entry point (plan 22-04), same isolation
    discipline as the Phase-21 mpc_* fields."

requirements-completed: [STOCH-01]

# Metrics
duration: ~15min
completed: 2026-08-10
---

# Phase 22 Plan 1: Scenario schema + CI fixture Summary

**Additive `stoch_S`/`stoch_probabilities`/`stoch_H_oos` fields on `Scenario` (empty-vector
sentinel resolved to default-uniform at construction) plus a small Deferrable-free 2-bus
`Phase22Fixtures` TestItems module, laying the two contract files every later Phase-22 plan
depends on.**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-08-10T02:13:20Z
- **Tasks:** 2/2 completed
- **Files modified:** 2 (1 modified, 1 created)

## Accomplishments
- `Scenario.jl` gains three validated, additive `stoch_*` fields (in-sample scenario count,
  explicit/default-uniform probability vector, held-out scenario budget) with zero behavioral
  change to any existing `:centralized`/`:admm`/`mpc_*` construction path.
- `test/fixtures_phase22.jl` provides `Phase22Fixtures`, a self-contained, Deferrable-free,
  solvable/exact 2-bus radial fixture ready for `setup=[Phase22Fixtures]` in every downstream
  Phase-22 `@testitem`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Scenario.jl additive stoch_* fields (D-01/D-04/D-10)** - `cce5201` (feat)
2. **Task 2: Phase22Fixtures small Deferrable-free CI fixture (D-12)** - `e22fb58` (test)

**Plan metadata:** (pending — final metadata commit follows this SUMMARY)

## Files Created/Modified
- `src/experiments/Scenario.jl` - Added `stoch_S`, `stoch_probabilities`, `stoch_H_oos` fields,
  their construction-time `ArgumentError` validation block, and docstring updates.
- `test/fixtures_phase22.jl` - New `Phase22Fixtures` `@testmodule`: `stoch_feeder`,
  `stoch_scenario_aggregators`, `stoch_lambda0`, `temperature_profile`, and pinned constants.

## Decisions Made
- Empty-vector sentinel for `stoch_probabilities`, resolved inside the inner constructor
  (see key-decisions above) — the only way to make a `@kwdef` field default depend on a
  sibling field's value.
- Locked `stoch_S ∈ [3,5]` and `stoch_H_oos ∈ [5,10]` per D-01/D-10, enforced identically to
  the existing `mpc_H`/`mpc_step` guard pattern.

## Deviations from Plan

None - plan executed exactly as written. Both tasks' acceptance criteria and `<verify>`
scripts passed on the first attempt with no auto-fixes required.

## Issues Encountered

None. The worktree's base commit (`d5419a96c788bd96d1757f41be4b33c70da43e6e`) was ahead of the
spawned worktree's initial `HEAD` (a stale `main`-derived commit from an unrelated milestone);
per the `<worktree_branch_check>` protocol this was corrected with a single `git reset --hard`
to the specified base before any task work began — not a plan deviation, a setup-time
housekeeping step.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `src/experiments/Scenario.jl` and `test/fixtures_phase22.jl` are stable, validated contract
  files ready for plan 22-02 (extensive-form builder), 22-03 (out-of-sample harness), and
  22-04 (orchestrator).
- No blockers. The v3.0 Phase-22 flag (no empirical measurement yet of Clarabel's
  scenario-count ceiling on the stochastic extensive form) remains open for a later plan to
  establish — out of scope for this plan.

---
*Phase: 22-stochastic-pv-demand-uncertainty*
*Completed: 2026-08-10*

## Self-Check: PASSED

- FOUND: src/experiments/Scenario.jl
- FOUND: test/fixtures_phase22.jl
- FOUND: .planning/phases/22-stochastic-pv-demand-uncertainty/22-01-SUMMARY.md
- FOUND commit: cce5201 (Task 1)
- FOUND commit: e22fb58 (Task 2)
