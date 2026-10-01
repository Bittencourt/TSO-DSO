---
phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder
plan: 01
subsystem: optimization
tags: [jump, clarabel, ipopt, socp, benders, feasibility-cut, planning]

# Dependency graph
requires:
  - phase: 10-02/11-01
    provides: "PlanningOracle/build_planning_oracle (src/planning/subproblem.jl), BendersMaster/add_feasibility_cut! (src/planning/master.jl), solve_with_retry! (src/planning/retry.jl), assert_solved! (src/core/status.jl)"
  - phase: 27-09
    provides: "_mpc_truth_import_acpf's direct assert_solved!(...; allow_local=true) bypass pattern (src/experiments/mpc_loop.jl), mirrored here for the planning-layer AC re-check"
provides:
  - "FeasibilityOracle / build_feasibility_oracle / solve_feasibility_oracle! (src/planning/feasibility_oracle.jl) — a second, built-ONCE slack-minimization oracle producing a genuine (v, u) Benders feasibility-cut pair for a voltage- or thermally-infeasible pinned z, no Farkas-ray extraction"
  - "ac_recheck_incumbent (src/planning/ac_recheck.jl) — the incumbent-only AC physics re-check (ACPowerFlow(; limits=false)) that bypasses solve_planning_oracle!/solve_with_retry! entirely and reports (never throws) a physical violation"
  - "build_feasibility_oracle registered in test_planning_noninteger.jl's PVAL-04 no-binaries registry"
affects: [30-02, 30-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Slack-relaxed pin (p_import = z + s+ - s-) with an L1 slack-min objective, reusing contribute!/aggregator-writer/balance-closure verbatim from build_planning_oracle — a second independent JuMP model, not a variant/mutation of PlanningOracle"
    - "Incumbent-only AC re-check: build_planning_oracle(feeder, ACPowerFlow(; limits=false), ...) + direct assert_solved!(...; dual=false, allow_local=true), bypassing solve_planning_oracle!/solve_with_retry! (neither accepts Ipopt's LOCALLY_SOLVED)"
    - "Violation computed directly from solved P/Q/l/v vs. feeder.branches[b].smax / feeder.buses[j].vmin/vmax — never a constraint dual (ACPowerFlow(limits=false) has no limit constraint to read one from)"

key-files:
  created:
    - src/planning/feasibility_oracle.jl
    - src/planning/ac_recheck.jl
    - test/test_planning_feasibility_oracle.jl
    - test/test_planning_ac_recheck.jl
  modified:
    - src/TSODSO.jl
    - test/test_planning_noninteger.jl

key-decisions:
  - "The feasibility-cut gradient sign is u = dual.(pin) UN-NEGATED (not -dual.(pin) as the docstring originally assumed before empirical verification) — determined by solving at a known-thermally-infeasible anchor z_k=0.08 and checking both candidate signs against the full measured feasible/infeasible map on ieee13_modified(); u=+pi reproduces the real 0.0686 pu thermal threshold exactly, u=-pi wrongly excludes every feasible point tried."
  - "The voltage-infeasible fixture required a dedicated, thermally-widened (smax=90) IEEE-13 variant with a 10-aggregator ample-battery population (not the real unmodified feeder) — confirmed by direct probe that thermal always binds first on the real feeder as z grows (per 30-RESEARCH.md's own prediction), isolated per CONTEXT.md's Assumption A1 ('separate fixtures')."

requirements-completed: ["BILEV-04"]

# Metrics
duration: 55min
completed: 2026-10-01
---

# Phase 30 Plan 01: SOCP-in-the-loop Benders feasibility-cut and AC re-check infra Summary

**Slack-minimization feasibility oracle (verified-sign Benders cut) and an incumbent-only `ACPowerFlow(limits=false)` physics re-check, both built once and independently tested on `ieee13_modified()`.**

## Performance

- **Duration:** 55 min
- **Started:** 2026-10-01T00:00:00Z (approx, session start)
- **Completed:** 2026-10-01
- **Tasks:** 3
- **Files modified:** 6 (4 created, 2 modified)

## Accomplishments
- `build_feasibility_oracle`/`solve_feasibility_oracle!` produce a genuine, nonzero-cost `(v, u)` feasibility-cut pair — consumed as-is by the existing `add_feasibility_cut!` — on both a thermally-infeasible and a voltage-infeasible pinned `z`.
- Empirically re-derived (not assumed) the correct sign of the cut gradient: `u = dual.(pin)`, un-negated — the opposite convention from `solve_planning_oracle!`'s own `π`, because this is a structurally different `Min`-sense slack objective.
- `ac_recheck_incumbent` bypasses `solve_planning_oracle!`/`solve_with_retry!` entirely (neither accepts Ipopt's `LOCALLY_SOLVED`) and reports — never throws — a populated violation report on a head-branch-overloading pin, while cleanly reporting zero violations on a feasible pin.
- Both new builders/functions verified passing via direct-script probes and the project's `@testitem` emulator (TestItemRunner does not resolve under `--project=.` in this repo); `build_feasibility_oracle` registered in the PVAL-04 no-binaries registry, confirmed not to break that tripwire.

## Task Commits

Each task was committed atomically:

1. **Task 1: build_feasibility_oracle / solve_feasibility_oracle! (BILEV-04a)** - `05e6573` (feat)
2. **Task 2: Incumbent-only AC physics re-check (BILEV-04b infra)** - `bdb3a94` (feat)
3. **Task 3: Thermal + voltage feasibility-cut fixtures, AC re-check fixtures, test files** - `dc397e3` (test)

**Plan metadata:** (this commit)

## Files Created/Modified
- `src/planning/feasibility_oracle.jl` - `FeasibilityOracle`/`build_feasibility_oracle`/`solve_feasibility_oracle!`, the slack-minimization second oracle
- `src/planning/ac_recheck.jl` - `ac_recheck_incumbent`, the incumbent-only AC physics re-check
- `src/TSODSO.jl` - two new `include(...)` lines (feasibility_oracle.jl, ac_recheck.jl) directly after `subproblem.jl`'s
- `test/test_planning_noninteger.jl` - `build_feasibility_oracle` registered in the PVAL-04 registry (not EXEMPT)
- `test/test_planning_feasibility_oracle.jl` - thermal + voltage feasibility-cut `@testitem`s, each preceded by a relax-one-constraint ablation confirming causation
- `test/test_planning_ac_recheck.jl` - feasible-pin and overload-pin `@testitem`s for `ac_recheck_incumbent`

## Decisions Made
- **Cut-gradient sign re-derivation:** the plan's own docstring template assumed `u = -π` by analogy with `solve_planning_oracle!`'s D-06 sign-flip precedent; direct empirical testing (solving the feasibility oracle at `z_k=0.08` and plugging both signs into the cut inequality against the full measured feasible/infeasible map) showed this analogy does NOT transfer — `u = +π` (un-negated) is the correct sign for this `Min`-sense slack-objective oracle. Documented explicitly in the function's docstring per the task's own acceptance criterion ("no TODO/assumed formula language").
- **Voltage fixture substitution:** per CONTEXT.md's Assumption A1 ("separate fixtures" permits purpose-built feeders), the voltage-infeasible fixture uses a thermally-widened (`smax=90`) IEEE-13 variant with a 10-aggregator ample-battery population rather than the unmodified feeder — confirmed by direct probe that thermal always binds first on the real feeder as `z` grows (30-RESEARCH.md's own prediction, reproduced this session).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected the feasibility-cut gradient sign from the plan's assumed `u=-π` to the empirically-verified `u=+π`**
- **Found during:** Task 1 (building/testing `solve_feasibility_oracle!`)
- **Issue:** The initial implementation (following the plan's own suggested-but-unverified analogy to `solve_planning_oracle!`'s D-06 sign inversion) set `u = -dual.(fo.pin)`. Plugging this into the cut inequality `v + u'(z-z_k) <= 0` against the measured feasible/infeasible map showed it VIOLATES the cut at every known-feasible `z` tried — an invalid cut that would wrongly exclude the entire feasible region from the master.
- **Fix:** Re-ran the empirical 3+-point sign check (the task's own acceptance criterion) and found `u = +dual.(fo.pin)` (un-negated) is correct — it excludes exactly `z >= 0.0686` (the real thermal limit) and holds at every tested feasible point. Updated `solve_feasibility_oracle!`'s implementation and docstring accordingly.
- **Files modified:** src/planning/feasibility_oracle.jl
- **Verification:** Direct probe script re-run confirming cut inequality at both signs across `z ∈ {0.0, 0.01, 0.02, 0.05, 0.0686, 0.08, 0.09}`; both new `@testitem`s pass with the corrected sign.
- **Committed in:** 05e6573 (Task 1 commit — caught and fixed before commit, not a follow-up patch)

**2. [Rule 1 - Bug] Fixed a docstring/function ordering bug in the test fixture module that silently broke one docstring attachment**
- **Found during:** Task 3 (writing `test_planning_feasibility_oracle.jl`)
- **Issue:** Inserting a new `try_solve_planning_oracle` helper function between `big_battery_agg`'s docstring and its function definition caused `@doc` to attach the docstring to the wrong (intervening) function, raising `LoadError: cannot document the following expression` when two docstrings ended up adjacent.
- **Fix:** Reordered so `try_solve_planning_oracle` (with its own docstring) is fully defined BEFORE `big_battery_agg`'s docstring+function pair.
- **Files modified:** test/test_planning_feasibility_oracle.jl
- **Verification:** Re-ran the file through the project's `@testitem` emulator — all 24 assertions across both new test files pass.
- **Committed in:** dc397e3 (Task 3 commit — caught and fixed before commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 — bugs caught via the plan's own mandated empirical verification steps, fixed before the task commit landed, no follow-up patch needed).
**Impact on plan:** Both deviations were caught during the plan's own required verification steps (the sign check, running the tests) before committing — no incorrect code was ever committed. No scope creep.

## Issues Encountered
None beyond the two deviations above (both resolved within the same task's verification cycle).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 30-04 (wave 2) can now wire `solve_stackelberg!`'s oracle-feasibility-cut branch directly to `build_feasibility_oracle`/`solve_feasibility_oracle!` and the AT-CONVERGENCE AC re-check hook directly to `ac_recheck_incumbent` — both building blocks are independently built, tested, and registered.
- No blockers. The cut-gradient sign finding (u=+π, un-negated) is the one fact plan 30-04 must carry forward verbatim when wiring `add_feasibility_cut!(master, r.v, r.u, r.z_k)` from `solve_feasibility_oracle!`'s return.

---
*Phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder*
*Completed: 2026-10-01*

## Self-Check: PASSED

All claimed files found on disk; all three task commit hashes (05e6573, bdb3a94, dc397e3)
found in `git log --oneline --all`.
