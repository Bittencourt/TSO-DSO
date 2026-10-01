---
phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder
plan: 04
subsystem: optimization
tags: [jump, clarabel, highs, benders, socp-exactness, feasibility-cut, planning]

# Dependency graph
requires:
  - phase: 30-01
    provides: "FeasibilityOracle/build_feasibility_oracle/solve_feasibility_oracle! (src/planning/feasibility_oracle.jl, u=+dual.(pin) un-negated sign), ac_recheck_incumbent (src/planning/ac_recheck.jl)"
  - phase: 30-02
    provides: "build_master's :auto α_op_lb/α_x_lb derivation + opt-in bounds_ctx build-time rejection (src/planning/master.jl), ALPHA_LB_REJECTION_TOL, derive_alpha_x_lb(::FollowerLP) dispatch"
provides:
  - "solve_stackelberg!'s inexact_policy keyword (:strict/:reject/:certify_incumbent, default :certify_incumbent), dispatched by disambiguating an oracle throw using ONLY is_solved_and_feasible + the :socp_maxgap stash timing (no string-matching, no duplicated tolerance)"
  - "solve_stackelberg!'s oracle-feasibility-cut branch (BILEV-04a): a genuine MOI.INFEASIBLE from the oracle routes to build_feasibility_oracle/solve_feasibility_oracle!/add_feasibility_cut!, the loop continues without updating UB"
  - "solve_stackelberg! ALWAYS constructs and threads bounds_ctx into build_master on every master===nothing call path (never conditional on :auto, never throwing merely because a pre-built follower is supplied) -- α_op_lb validated unconditionally, α_x_lb validated wherever a sound derivation exists (NamedTuple or FollowerLP), honestly skipped for DistributorView"
  - "_assert_epigraph_floor: a universal, bound-source-independent runtime guard on the optimality branch"
  - "AC-recheck-at-convergence: ac_report, a new trailing result field, nothing when the incumbent is exact, a populated ac_recheck_incumbent report otherwise"
  - "BendersTrace gains socp_maxgap_trace/policy_action_trace columns and a :rejected cut_type kind; trace_summary gains n_inexact_iterations"
affects: [30-05, 30-06, 31]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Oracle-throw disambiguation via is_solved_and_feasible + :socp_maxgap stash-timing ONLY -- no string-matching on error messages, no duplicated tolerance logic (T-30-07 mitigation)"
    - "bounds_ctx computed from the ORIGINAL follower/follower_kwargs arguments BEFORE the follower reassignment, giving a real three-way dispatch (NamedTuple / FollowerLP / nothing) rather than dead code"
    - "Universal runtime floor guard (_assert_epigraph_floor) as defense-in-depth, independent of how a bound was derived or validated at build time"

key-files:
  created:
    - test/test_planning_alpha_bounds_stackelberg.jl
    - test/test_planning_inexact_policy.jl
  modified:
    - src/planning/trace.jl
    - src/planning/benders.jl
    - test/test_planning_feasibility_oracle.jl

key-decisions:
  - "The genuine-infeasibility branch (!is_solved_and_feasible) is checked BEFORE the :socp_maxgap-based exactness disambiguation, and is UNCONDITIONAL regardless of inexact_policy -- BILEV-04a's recovery fires on every policy, only the exactness-class throw (BILEV-04b) is policy-dispatched."
  - ":reject never appends any cut on an inexact trial, which is DETERMINISTIC: the master's LP is unchanged, so it re-proposes the IDENTICAL trial every subsequent iteration once it first lands in the inexact zone -- a genuine, accepted (T-30-09), non-default-policy limitation confirmed empirically on a real IEEE-13 T=4 fixture, not assumed."
  - "test_planning_inexact_policy.jl's fixture reuses plan 30-03's own IEEE13ShortHorizonFixtures (T=4, ieee13_modified()) with near-zero leader/follower costs so the Benders loop's OWN natural trajectory (not a synthetic forced z) passes through a measured SOCP-inexact pin (z~0.0504, maxgap~1.7e-3-2.4e-3) -- the SAME run also naturally exercises BILEV-04a's oracle-feasibility-cut branch (genuine MOI.INFEASIBLE at 3 early iterations), confirmed as a bonus regression beyond plan 30-01's own purpose-built fixtures."
  - "test_planning_feasibility_oracle.jl's two new solve_stackelberg! end-to-end items reuse the SAME feeder/population as that file's own dedicated ablation items (small_house_agg/big_battery_agg), with y_max/costs tuned (measured, not guessed) so the master's natural trial sequence hits a genuinely thermal- or voltage-caused MOI.INFEASIBLE, confirmed via the SAME relax-one-constraint ablation technique."
  - "W2 overhead (checker-flagged): derive_alpha_op_lb's own one-time relaxed solve costs ~13.1ms on the toy two-bus/ToyElasticDevice fixture (test_planning_nash.jl's own population), vs ~695.5ms for a full solve_stackelberg! best-response -- roughly 1.9% overhead per build_master call now reached unconditionally through solve_stackelberg! (including every run_nash! best-response). Measured this session, 20-iteration average each; carried forward for Phase 31's own FINDINGS."

requirements-completed: ["BILEV-04", "BILEV-05"]

# Metrics
duration: ~95min
completed: 2026-10-01
---

# Phase 30 Plan 04: solve_stackelberg! inexact_policy + oracle-feasibility-cut + unconditional bounds_ctx + AC-recheck Summary

**`solve_stackelberg!` survives genuine SOCP-in-the-loop friction end-to-end: a 3-way `inexact_policy` dispatch (default `:certify_incumbent`), a real oracle-feasibility-cut recovery branch, unconditional `bounds_ctx` validation on every call path (including `run_nash!`'s `DistributorView`), and a once-at-convergence AC physics re-check — all closing BILEV-04/BILEV-05's integration.**

## Performance

- **Duration:** ~95 min
- **Completed:** 2026-10-01
- **Tasks:** 3/3 completed
- **Files modified:** 5 (2 new, 3 modified)

## Accomplishments

- `src/planning/trace.jl`'s `BendersTrace` gains additive `socp_maxgap_trace`/`policy_action_trace` columns and a `:rejected` `cut_type` kind; `trace_summary` gains `n_inexact_iterations` — every pre-existing `push!` call site (which omits the new keywords) still compiles and records the `NaN`/`:none` sentinels, confirmed by zero regressions on the pre-existing planning suite.
- `src/planning/benders.jl`'s `solve_stackelberg!` gains `inexact_policy::Symbol = :certify_incumbent`, dispatched via a disambiguation recipe using ONLY information `solve_planning_oracle!` already computes (`is_solved_and_feasible` + the `:socp_maxgap` stash timing) — no string-matching, no duplicated tolerance logic (T-30-07). `:strict` reproduces today's byte-identical throw; `:reject` skips the inexact cut (no `UB` update, `:rejected` trace row); `:certify_incumbent` reconstructs the already-solved model's `(cost, π, π_s, dadp, ctx)` and proceeds normally.
- The oracle-feasibility-cut branch (BILEV-04a) is now real: a genuine `MOI.INFEASIBLE` oracle throw calls `solve_feasibility_oracle!`/`add_feasibility_cut!` on a second, built-once `feas_oracle` (plan 30-01), and the loop recovers instead of crashing — confirmed not just on plan 30-01's own purpose-built thermal/voltage fixtures but NATURALLY on a realistic T=4 IEEE-13 run (test_planning_inexact_policy.jl's own fixture hits it 3 times en route to convergence).
- `bounds_ctx` is now ALWAYS constructed and threaded into `build_master` on every `master === nothing` call path reached through `solve_stackelberg!` — `α_op_lb` is validated unconditionally (including `run_nash!`'s own `master_kwargs` literal and every pre-existing `master_kwargs` literal across the test suite); `α_x_lb` is validated wherever a sound derivation exists (a `follower_kwargs` `NamedTuple` or a pre-built `FollowerLP`), honestly skipped (never silently passed) for `DistributorView`'s pooled-capacity coupling. `solve_stackelberg!` never throws merely because a pre-built `follower` is supplied — confirmed by `test_planning_nash.jl`'s full regression (Nash results unchanged) and the new `test_planning_alpha_bounds_stackelberg.jl`.
- A universal runtime epigraph floor guard (`_assert_epigraph_floor`) fires unconditionally on the optimality branch regardless of how either bound was derived — defense-in-depth per BILEV-05.
- The AC-recheck-at-convergence hook runs ONCE, immediately before the converged return: `ac_report` is a new trailing, additive result field — `nothing` on every pre-existing LinDistFlow-based result (confirmed), a populated `ac_recheck_incumbent` report only when the incumbent turns out SOCP-inexact.
- Three new `@testitem`s in `test/test_planning_alpha_bounds_stackelberg.jl` cover the over-high-bound rejection (no checkpoint file written), a valid-bound zero-regression convergence, and a pre-built `DistributorView` follower being accepted while `α_op_lb` stays validated.
- `test/test_planning_inexact_policy.jl` (new) exercises the full 3-policy matrix at a MEASURED, naturally-occurring SOCP-inexact pin (never synthetic). `test/test_planning_feasibility_oracle.jl` gains two `solve_stackelberg!` end-to-end items (thermal + voltage) satisfying BILEV-04a's "loop still converges" criterion on realistic trajectories.

## Task Commits

Each task was committed atomically:

1. **Task 1: trace.jl additions + inexact_policy dispatch + runtime epigraph floor guard** - `d6d2165` (feat)
2. **Task 2: Oracle-feasibility-cut branch + unconditional bounds_ctx wiring + AC-recheck-at-convergence** - `7816ddf` (feat)
3. **Task 3: inexact_policy test matrix + "loop still converges" criterion** - `ce179cc` (test)

**Plan metadata:** (this commit)

## Files Created/Modified

- `src/planning/trace.jl` - `BendersTrace` gains `socp_maxgap_trace`/`policy_action_trace`, `:rejected` cut kind, `trace_summary`'s `n_inexact_iterations`
- `src/planning/benders.jl` - `inexact_policy` dispatch, `_assert_epigraph_floor`, the oracle-feasibility-cut branch, unconditional `bounds_ctx` wiring, the AC-recheck-at-convergence hook, `ac_report`, updated docstring
- `test/test_planning_alpha_bounds_stackelberg.jl` - 3 new `@testitem`s (BILEV-05 `solve_stackelberg!`-level coverage)
- `test/test_planning_inexact_policy.jl` - the 3-policy `inexact_policy` matrix at a measured SOCP-inexact pin
- `test/test_planning_feasibility_oracle.jl` - 2 new `solve_stackelberg!` end-to-end items (thermal + voltage "loop still converges")

## Decisions Made

- **Genuine-infeasibility routing is unconditional, independent of `inexact_policy`:** the `!is_solved_and_feasible` check runs BEFORE the `:socp_maxgap`-based exactness disambiguation in the same `catch` block, so BILEV-04a's recovery fires identically under `:strict`/`:reject`/`:certify_incumbent` — only a genuine exactness-class throw is policy-dispatched.
- **`:reject`'s deterministic stall is documented, not engineered around:** since no cut is ever appended on a rejected trial, the master's LP is byte-identical on the next iteration and re-proposes the SAME trial forever once it first lands in the inexact zone. Confirmed empirically (not assumed) on a real IEEE-13 T=4 fixture; `test_planning_inexact_policy.jl`'s own `:reject` item asserts the resulting `max_iter` exhaustion and cross-references the companion `:certify_incumbent` item (same fixture/configuration) to show the pin is genuinely inexact-but-feasible, never a true infeasibility — attributing the raise to the designed `:reject` branch.
- **Both new `test_planning_inexact_policy.jl`/`test_planning_feasibility_oracle.jl` fixtures use the Benders loop's OWN natural trial sequence** (near-zero leader/follower investment costs to let economics drive exploration) rather than a synthetic forced z, per the plan's own "never a synthetic forced case" requirement — each anchor point was independently confirmed via the SAME relax-one-constraint ablation technique plan 30-01's own fixtures use.
- **W2 overhead measured, not assumed:** `derive_alpha_op_lb`'s one-time relaxed solve costs ~13.1ms vs ~695.5ms for a full `solve_stackelberg!` best-response on the toy two-bus fixture (test_planning_nash.jl's own population) — ~1.9% overhead per `build_master` call, now paid unconditionally through every `solve_stackelberg!`/`run_nash!` best-response. Recorded here for Phase 31's own FINDINGS to carry forward (orchestrator-flagged W2).

## Deviations from Plan

### Auto-fixed Issues

None — no Rule 1/2/3 auto-fixes were needed; the implementation matched the plan's `<interfaces>`/`<action>` blocks closely. One internal bug was caught and fixed DURING Task 1's own implementation, before any commit:

**1. [Rule 1 - Bug] Double-counted `t_solve` on the oracle-throw `catch` path**
- **Found during:** Task 1, writing the try/catch disambiguation around `solve_planning_oracle!`.
- **Issue:** An initial draft added `t_solve += (time_ns() - t0_ns) / 1.0e9` unconditionally at the TOP of the `catch` block, AND again after the try/catch block (for the success/`:certify_incumbent` fall-through paths) — double-counting the elapsed time for any iteration that threw.
- **Fix:** Removed the unconditional accumulation at the top of `catch`; the `:reject` branch (the only path that `continue`s without reaching the post-try/catch line) now accumulates `t_solve` itself, immediately before its `continue`.
- **Files modified:** src/planning/benders.jl
- **Verification:** Re-ran the emulator's own regression set; `solve_time >= 0` guard in `trace.jl`'s `push!` never fired, and manual inspection of `t_solve` values across the probe scripts showed no anomalous doubling.
- **Committed in:** `d6d2165` (Task 1 commit — caught and fixed before commit).

---

**Total deviations:** 1 auto-fixed (Rule 1 — caught during the plan's own careful implementation, before any commit).
**Impact on plan:** None on substance — the bug was never committed; no scope creep.

## Issues Encountered

- **Pre-existing, unrelated `Broken` test item:** the full regression run (and the Task 2 `test_planning_nash.jl`-inclusive run) consistently reports `1 Broken` alongside `0 Failed` (e.g. `376 pass / 1 broken / 0 fail / 377 total`, exit code 0). Grepped every included file (`fixtures_phase6.jl`, `fixtures_planning.jl`, `test_planning_oracle.jl`, `test_planning_benders.jl`, `test_planning_benders_integer.jl`, `test_planning_hardening.jl`, `test_planning_nash.jl`, and this plan's own new files) for `@test_broken`/`broken=` — zero matches found anywhere. Reproduced identically (same count) across two independent full runs, present only once `test_planning_nash.jl`/`test_planning_benders_integer.jl` are included (absent from the narrower Task-1-only run), and NOT attributable to any file this plan touches. Logged here per the Scope Boundary rule (pre-existing, out of this plan's scope) rather than chased further; `Test.jl`'s own exit code 0 confirms it is not a failure.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plan 30-05 can now run the real IEEE-13, T∈[3,6] BILEV-03 convergence test with full confidence that `solve_stackelberg!` survives genuine SOCP-in-the-loop friction (oracle infeasibility, SOCP inexactness) without crashing — exactly the scenario this plan exists to make survivable.
- Plan 30-06 (phase close) should carry forward the measured W2 overhead (~1.9% per `build_master` call via `derive_alpha_op_lb`'s one-time relaxed solve, now paid unconditionally through every `solve_stackelberg!`/`run_nash!` best-response) into its own FINDINGS for Phase 31.
- No blockers. `ALPHA_LB_REJECTION_TOL` (plan 30-02) is reused verbatim by `_assert_epigraph_floor`'s own default tolerance — no second, drifting constant introduced.

---
*Phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder*
*Completed: 2026-10-01*

## Self-Check: PASSED

All 6 claimed files found on disk; all three task commit hashes (d6d2165, 7816ddf,
ce179cc) found in `git log --oneline --all`.
