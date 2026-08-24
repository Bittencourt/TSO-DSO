---
phase: 22-stochastic-pv-demand-uncertainty
plan: 04
subsystem: experiments
tags: [julia, jump, clarabel, socp, stochastic-programming, orchestrator, out-of-sample]

# Dependency graph
requires:
  - phase: 22-stochastic-pv-demand-uncertainty
    provides: "Scenario.jl stoch_* fields + Phase22Fixtures from plan 22-01"
  - phase: 22-stochastic-pv-demand-uncertainty
    provides: "build_stochastic_welfare(feeder, pf, scenario_aggs; probabilities, T, λ₀) —
      the S-scenario extensive-form welfare builder (STOCH-01/STOCH-02) from plan 22-02"
  - phase: 22-stochastic-pv-demand-uncertainty
    provides: "StochasticOosHarness/build_stochastic_oos_harness/solve_stochastic_oos_step! —
      the Parameter-pinned single-scenario out-of-sample re-solve harness (STOCH-03) from
      plan 22-03"
provides:
  - "run_stochastic(s::Scenario) -> NamedTuple — the phase's ONE entry point (STOCH-03):
    materializes S disjoint-seeded in-sample scenarios, solves the extensive form, drives
    the out-of-sample harness across H disjoint-seeded held-out scenarios, and reports the
    realized-vs-in-sample welfare gap"
affects: ["22-05"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "run_stochastic is an INDEPENDENT entry point (mirrors run_mpc's own D-01/D-02
      positioning) — never wired through run_scenario's :centralized/:admm strategy dispatch"
    - "Two disjoint sub_seed tag-prefix families (:stoch_insample_*/:stoch_oos_*) drive two
      independent materialize.jl population builds from the SAME Scenario"
    - "Bus-keyed device lookup (_stoch_device_with_field) to slide a held-out scenario's own
      PV/demand/ambient data onto a build-once harness whose handles are keyed only by bus"

key-files:
  created: [src/experiments/run_stochastic.jl, test/test_run_stochastic.jl]
  modified: [src/TSODSO.jl, docs/src/api.md]

key-decisions:
  - "realized_welfare uses a uniform-weight average over the held-out budget
    (sum(welfare_h) / s.stoch_H_oos) — Claude's-discretion default per the plan's own text,
    documented in run_stochastic's docstring rather than left implicit."
  - "λ₀ is computed ONCE from in-sample scenario 1's own profile draw and reused verbatim
    for every in-sample AND held-out scenario, per the plan's own action text (:mem's shape
    is deterministic and profile-independent, so this is not a hidden per-scenario price
    divergence)."
  - "The out-of-sample harness is built against held-out scenario 1's aggregator LIST as
    the device structure template, and the battery pins are set ONCE before the held-out
    loop (D-09's build-once contract) — never re-pinned per held-out scenario, since the
    first-stage schedule is fixed across all held-out draws by construction."

patterns-established:
  - "A phase's closing orchestrator (run_stochastic here, run_mpc in Phase 21) is wired as
    the LAST include in TSODSO.jl, reads the phase's own additive Scenario fields directly,
    and is never routed through run_scenario's strategy dispatch."

requirements-completed: [STOCH-03]

# Metrics
duration: ~35min
completed: 2026-08-10
---

# Phase 22 Plan 4: run_stochastic orchestrator Summary

**`run_stochastic(s::Scenario)` — the phase's one entry point: materializes S
disjoint-seeded in-sample scenarios, solves the extensive form via
`build_stochastic_welfare`, drives the build-once `StochasticOosHarness` across H
disjoint-seeded held-out scenarios pinned to the in-sample optimum, and reports the
realized-vs-in-sample welfare gap (measured, stable, and pinned only after a D-11
stability check).**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-08-10T03:07:00Z (approx.)
- **Completed:** 2026-08-10T03:44:51Z
- **Tasks:** 2/2 completed
- **Files modified:** 4 (2 modified, 2 created)

## Accomplishments

- `run_stochastic(s::Scenario)` implements the full pipeline end-to-end: materializes
  `s.stoch_S` in-sample scenario aggregator populations from the `:stoch_insample_profiles_k`/
  `:stoch_insample_population_k` disjoint `sub_seed` tag family, solves
  `build_stochastic_welfare`, reads the SOLVED shared first-stage battery schedule off
  scenario 1's own device vars, materializes `s.stoch_H_oos` held-out populations from the
  disjoint `:stoch_oos_profiles_h`/`:stoch_oos_population_h` family, builds the
  `StochasticOosHarness` exactly once against held-out scenario 1's device structure, pins
  the harness's battery controls to the in-sample optimum once (before the held-out loop),
  then re-slides every held-out scenario's own PV/demand/ambient data and re-solves via
  `solve_stochastic_oos_step!`.
- Returns `(; in_sample = (; welfare, dadp, expected_dadp, probabilities, socp_maxgap), oos =
  (; welfare_h, realized_welfare, welfare_gap))`, with `welfare_gap = realized_welfare -
  in_sample.welfare` (uniform-weight average of `welfare_h` across the held-out budget).
- Wired into `src/TSODSO.jl` as the last include (after `experiments/mpc_loop.jl`) and into
  `docs/src/api.md`'s "Stochastic PV/Demand Uncertainty" section.
- `test/test_run_stochastic.jl` covers seed disjointness (T-22-06), same-seed reproducibility
  (INFRA-04), and D-11's measurement-before-golden discipline: a repeated-run stability
  assertion (3 fresh calls, all pairwise `==`) textually precedes the one pinned golden
  `welfare_gap` literal (`-0.025156091170856598`, measured and confirmed stable in the same
  run before being written into the test).

## Task Commits

Each task was committed atomically:

1. **Task 1: run_stochastic(s::Scenario) orchestrator — in-sample + out-of-sample welfare
   gap (D-09/D-10)** - `630b5d6` (feat)
2. **Task 2: test_run_stochastic.jl — seed disjointness, reproducibility, D-11
   measurement-before-golden** - `c8e544c` (test)

**Plan metadata:** (pending — final metadata commit follows this SUMMARY, owned by the
orchestrator)

## Files Created/Modified

- `src/experiments/run_stochastic.jl` - New `run_stochastic(s::Scenario)` orchestrator +
  the internal `_stoch_device_with_field` helper.
- `src/TSODSO.jl` - Wired `include("experiments/run_stochastic.jl")` as the final include,
  after `experiments/mpc_loop.jl`.
- `docs/src/api.md` - Extended the "Stochastic PV/Demand Uncertainty" `@autodocs` `Pages`
  list to `["models/stochastic_welfare.jl", "experiments/run_stochastic.jl"]`.
- `test/test_run_stochastic.jl` - New `@testitem`s (seed disjointness, reproducibility,
  D-11 measurement-before-golden).

## Decisions Made

- `realized_welfare` is a uniform-weight average across the held-out budget — the plan
  explicitly leaves this weighting to Claude's discretion; documented inline and in the
  docstring rather than left implicit.
- `λ₀` is materialized once (from in-sample scenario 1's profile draw) and reused for every
  scenario, in-sample and held-out alike — matches the plan's own action text and
  `build_price(:mem, ...)`'s documented profile-independence.
- The out-of-sample harness's `ppv_handles`/`tout_handles` are keyed only by bus, so a small
  internal helper (`_stoch_device_with_field`) resolves, per held-out scenario, which member
  device at that bus carries the field being re-slid (`:Ppv` for the PVBattery member, `:Tout`
  for the Thermostatic member) — necessary because an aggregator's `devices` list is not
  itself keyed by field name.

## Deviations from Plan

None - plan executed exactly as written. Both tasks' acceptance criteria and `<verify>`
scripts passed on the first attempt with no auto-fixes required. The only structural
adjustment (moving the single `feeder = build_feeder(s.feeder)` call to before the in-sample
loop rather than rebuilding it per-scenario) is a straightforward reading of the plan's own
"Materialize: feeder = build_feeder(s.feeder)" text — not a deviation from the plan's stated
intent, just an implementation-order clarification versus an early literal reading of the
action text's own paragraph ordering.

## Issues Encountered

None. The worktree's base commit was ahead of the spawned worktree's initial `HEAD` (a stale
commit predating waves 1-3); per the `<worktree_branch_check>` protocol this was corrected
with a single `git reset --hard` to the specified base before any task work began — not a
plan deviation, a setup-time housekeeping step (same pattern documented in plan 22-01's own
SUMMARY).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `run_stochastic(s::Scenario)` is a stable, exported, documented contract ready for plan
  22-05 (the literate experiment page / phase-closing plan).
- `select_optimizer(::SOCP; attrs...)`'s convergence-precision fix (plan 22-02) and the
  `StochasticOosHarness` build-once/pin idiom (plan 22-03) are both exercised end-to-end
  through this orchestrator, with no regression observed.
- No blockers carried forward specific to this plan. The pre-existing v3.0 Phase-22 flag
  ("no empirical measurement yet of Clarabel's scenario-count ceiling on the stochastic
  extensive form") remains open for a later plan if needed — this plan's own verify script
  ran comfortably at `stoch_S=3`/`stoch_H_oos=5` on the small `:ieee13` fixture.

---
*Phase: 22-stochastic-pv-demand-uncertainty*
*Completed: 2026-08-10*

## Self-Check: PASSED

- FOUND: src/experiments/run_stochastic.jl
- FOUND: test/test_run_stochastic.jl
- FOUND: src/TSODSO.jl
- FOUND: docs/src/api.md
- FOUND commit: 630b5d6 (Task 1)
- FOUND commit: c8e544c (Task 2)
