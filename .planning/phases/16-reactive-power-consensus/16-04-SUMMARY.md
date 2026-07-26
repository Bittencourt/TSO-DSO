---
phase: 16-reactive-power-consensus
plan: 04
subsystem: infra
tags: [julia, jump, admm, socp, clarabel, reactive-power, measurement, drwatson]

# Dependency graph
requires:
  - phase: 16-reactive-power-consensus (plan 02)
    provides: "reactive_consensus::Bool kwarg on build_dso_opt/solve_admm (qag_dso pinned coupling variable + assert_no_slack certificate on :balance_q)"
provides:
  - "A re-runnable, DrWatson-convention script (scripts/reactive_flake_rate.jl) measuring the Clarabel NUMERICAL_ERROR-class flake rate of solve_admm under reactive_consensus in {false, true} on IEEE-13 AND IEEE-123 (N=20 repeats each, 80 solves total)"
  - "The committed measurement artifact (results/reactive_flake_rate/flake_rate_findings.txt) recording all four rates plus the rho/rho_q (Open Question 1) finding as a citable phase deliverable"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Inline reimplementation of TestItems.@testmodule fixture builders in a plain script: TestItems.jl's standalone @testmodule macro expands to a no-op outside the TestItemRunner introspection path, so a plain `include(\"test/fixtures_*.jl\")` does NOT actually define the fixture module. This script copies the builder logic (Aggregator/Thermostatic/Deferrable/PVBattery/generate_profiles calls, seeds, scales) verbatim from test/fixtures_phase4.jl and test/fixtures_phase7.jl instead."
    - "Repeated-run flake measurement via a tiny (1e-9-scale) lambda0 jitter per repeat, since the seeded fixtures are otherwise fully deterministic — perturbs the interior-point solver's exact iterate path without changing the economically-meaningful problem data."

key-files:
  created:
    - scripts/reactive_flake_rate.jl
    - results/reactive_flake_rate/flake_rate_findings.txt
  modified: []

key-decisions:
  - "The measured Clarabel flake rate is reported as-is, with no attempt to fix or explain away an unexpectedly HIGH IEEE-13 baseline (55%, reactive_consensus=false) — this phase's task is to measure and record, not to diagnose or patch solver conditioning (out of scope per REACT-01/03 and the plan's own 'no over-building' constraint)."
  - "reactive_consensus=true does NOT measurably worsen the flake rate on either fixture: IEEE-13 true (15%) is LOWER than its own false baseline (55%), and IEEE-123 true (5%) exactly matches its false baseline (5%). Both deltas are <= 0, so no rho_q escalation is warranted by this measurement."
  - "The rho vs rho_q question (Open Question 1) is answered directly from Plan 16-02's actual shipped mechanism (qag_dso pinned via a hard equality, zero rho-penalty term) rather than re-derived: 'shared rho vs distinct rho_q' does not apply to a mechanism with no rho-penalty weight on the reactive coupling constraint at all."

patterns-established: []

requirements-completed: [REACT-01, REACT-03]

# Metrics
duration: ~45min
completed: 2026-07-26
---

# Phase 16 Plan 04: Reactive Flake-Rate Measurement + Rho/Rho_q Finding Summary

**Measured the Clarabel NUMERICAL_ERROR-class flake rate of `solve_admm` under `reactive_consensus ∈ {false, true}` on IEEE-13 (N=20: 55% false / 15% true) and IEEE-123 (N=20: 5% false / 5% true), and recorded the rho vs rho_q (Open Question 1) finding grounded in Plan 16-02's hard-equality-pinned `qag_dso` mechanism.**

## Performance

- **Duration:** ~45 min (dominated by the actual 80-solve measurement run, ~40 min wall-clock under concurrent CPU load from other parallel-agent worktrees)
- **Tasks:** 1
- **Files modified:** 2 created (`scripts/reactive_flake_rate.jl`, `results/reactive_flake_rate/flake_rate_findings.txt`)

## Accomplishments

- **The measured flake rates (the phase's key deliverable):**

  | Fixture  | reactive_consensus | N  | fails | rate  |
  |----------|---------------------|----|-------|-------|
  | IEEE-13  | false               | 20 | 11    | 0.550 |
  | IEEE-13  | true                | 20 | 3     | 0.150 |
  | IEEE-123 | false               | 20 | 1     | 0.050 |
  | IEEE-123 | true                | 20 | 1     | 0.050 |

  **Notable finding:** the IEEE-13 baseline (`reactive_consensus=false`) rate measured here (55%) is substantially higher than STATE.md's characterization of the pre-existing Clarabel flake as "rare." This is reported as-is per this plan's explicit "never silently accept or silently fix" instruction (16-RESEARCH.md Pitfall 5) — it is NOT attributable to `reactive_consensus`, since it appears on the `false` (unchanged) path using the SAME `assert_solved!` gate the rest of the codebase already relies on; it may reflect this specific ground-truth-calibrated IEEE-13 fixture sitting closer to a congestion-driven feasibility boundary than the fixtures previously sampled, and/or the 1e-9 lambda0 jitter methodology this script uses to vary an otherwise-deterministic seeded fixture across repeats (documented in the script's own header). **Critically, `reactive_consensus=true` did NOT increase this rate — it measured LOWER (15%) on the same fixture**, so the phase's central empirical question (does adding `qag_dso` to the SOCP worsen conditioning?) is answered: no evidence of that at this scale, on either fixture.
- **The rho/rho_q finding (Open Question 1):** recorded directly from Plan 16-02's shipped mechanism — `qag_dso[j,t]` is pinned via a hard equality (`:qag_pin`, `qag_dso[j,t] == q_draw[j][t]`) with NO quadratic rho-penalty term of its own. "Shared rho vs. distinct rho_q" does not apply to this mechanism; there is no rho-penalty weight on the reactive coupling constraint to tune, shared or distinct.
- Created `scripts/reactive_flake_rate.jl` (`457` lines) following the `benders_toy.jl`-style DrWatson header convention (`using DrWatson; @quickactivate "TSODSO"; using TSODSO; using Printf`), writing to `projectdir("results", "reactive_flake_rate")`.
- Committed the output artifact `results/reactive_flake_rate/flake_rate_findings.txt` containing all four rates, the delta computation, and both written findings (flake rate + rho/rho_q).

## Task Commits

Each task was committed atomically:

1. **Task 1: Author the N>=20 repeated-run flake-rate measurement script** - `f44e5ed` (feat)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified

- `scripts/reactive_flake_rate.jl` - New DrWatson-convention script. Reimplements the IEEE-13 (`build_ieee13_ground_aggregators`-equivalent, seed 20260718, `GROUND_LOAD_SCALE=0.005`/`GROUND_PV_SCALE=0.03`) and IEEE-123 (`build_ieee123_aggregators`-equivalent, seed 20260719, `LOAD_SCALE=0.03`/`PV_SCALE=0.06`/`DEV_SCALE=0.05`) populations INLINE (copied verbatim from `test/fixtures_phase4.jl`/`test/fixtures_phase7.jl`'s underlying builders — see Deviations/Decisions for why `include`-ing the test fixture files directly does not work), reusing the shared adaptive-rho config constants (`RHO0=5.0`, `EPS_ABS=1e-5`, `EPS_REL=1e-4`, `TAU=2.0`, `MU=10.0`, `RHO_MIN=1e-2`, `RHO_MAX=1e4`) verbatim. Defines `count_failures(feeder, aggs, λ₀; reactive_consensus, n_repeats, seed_offset)`, calling `solve_admm` in a `try/catch` N times with a `1e-9`-scale λ₀ jitter per repeat, incrementing a failure counter and `@warn`-logging each caught exception. Runs all 4 (fixture × mode) combinations at N=20, prints a summary table, and writes rates + prose findings to `results/reactive_flake_rate/flake_rate_findings.txt`.
- `results/reactive_flake_rate/flake_rate_findings.txt` - The committed, citable output artifact: all four measured rates, the delta computation and its interpretation, and the rho/rho_q (Open Question 1) finding text.

## Decisions Made

- **Reimplemented fixture populations inline rather than `include`-ing the test fixture files.** `TestItems.jl`'s standalone `@testmodule` macro expands to a no-op (`return nothing`) outside the `TestItemRunner`/VS-Code-extension AST-introspection path (confirmed by reading `TestItems.jl`'s own source: `macro testmodule(ex...); return nothing; end`). This means `include("test/fixtures_phase7.jl")` from a plain script does NOT define `Phase7Fixtures` — the plan's own `<action>` anticipated this exact ambiguity ("verify at execution time and fall back to inline reconstruction if not"). Verified the no-op behavior directly against the installed `TestItems` package before choosing the inline path, per the plan's explicit guidance.
- **Reported the measured IEEE-13 baseline flake rate (55%) as-is, without investigation or fix.** This is a pure measurement task; explaining or improving the pre-existing (non-reactive-related) baseline flake sensitivity is out of this plan's scope (and out of this phase's scope per REACT-01/03). The task's acceptance criterion is explicitly "the rates are RECORDED, not that any particular rate threshold is met."
- **No rho_q follow-up recommended.** Since `reactive_consensus=true`'s rate did not exceed its own fixture's `false` baseline on either IEEE-13 or IEEE-123 (delta <= 0 on both), the script's own conditional logic (mirroring 16-RESEARCH.md Pattern 3's "only escalate if the empirical experiment shows the degenerate-target assumption doesn't hold") correctly emitted the "no follow-up warranted" branch rather than the "materially worse — a soft rho_q alternative would be the natural follow-up" branch.

## Deviations from Plan

None - plan executed exactly as written. The `include`-vs-inline-reconstruction fork the plan itself flagged as an open implementation choice was resolved (inline reconstruction, per the plan's own fallback instruction) after verifying at execution time that `@testmodule` does not expand outside the test-runner context — this was an anticipated decision point in the plan's own `<action>` text, not an unplanned deviation.

## Issues Encountered

- The Julia process (80 solves across 2-bus/13-bus/123-bus-scale SOCPs) ran for approximately 33-40 minutes wall-clock under concurrent CPU contention from other parallel-agent worktrees in the same sandbox (a full `Pkg.test()` run for a sibling worktree was observed running concurrently). No functional issue — just longer wall-clock time than the plan's own "several minutes" estimate for IEEE-123 alone; resolved by running in the background and waiting for completion.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Both of the phase's REQUIRED empirical measurements (Clarabel flake rate under Q-consensus; rho vs rho_q resolution) are now complete and committed as citable artifacts.
- The measured flake rates are available for the phase's own completion notes/ROADMAP entry to cite directly (IEEE-13: 55%→15%, IEEE-123: 5%→5%, reactive_consensus false→true).
- No `src/**` file was modified by this plan (only `scripts/reactive_flake_rate.jl` and `results/reactive_flake_rate/` were created), preserving the plan's stated scope boundary.
- No blockers for phase completion.

---
*Phase: 16-reactive-power-consensus*
*Completed: 2026-07-26*

## Self-Check: PASSED

- FOUND: scripts/reactive_flake_rate.jl
- FOUND: results/reactive_flake_rate/flake_rate_findings.txt
- FOUND: .planning/phases/16-reactive-power-consensus/16-04-SUMMARY.md
- FOUND: commit f44e5ed (feat(16-04): measure Clarabel flake rate + rho/rho_q finding under reactive_consensus)
- FOUND: commit 05c2d8f (docs(16-04): complete reactive flake-rate measurement plan)
