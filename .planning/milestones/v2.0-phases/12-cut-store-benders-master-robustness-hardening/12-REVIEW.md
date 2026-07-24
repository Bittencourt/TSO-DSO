---
phase: 12-cut-store-benders-master-robustness-hardening
reviewed: 2026-07-23T00:00:00Z
depth: standard
files_reviewed: 10
files_reviewed_list:
  - src/TSODSO.jl
  - src/planning/benders.jl
  - src/planning/follower.jl
  - src/planning/master.jl
  - src/planning/retry.jl
  - src/planning/subproblem.jl
  - src/planning/trace.jl
  - test/test_planning_benders.jl
  - test/test_planning_hardening.jl
  - test/test_planning_retry.jl
findings:
  critical: 0
  warning: 0
  info: 4
  total: 4
status: clean
---

# Phase 12: Code Review Report (iteration 3 — fix verification)

**Reviewed:** 2026-07-23
**Depth:** standard
**Files Reviewed:** 10
**Status:** clean

## Summary

Re-review of the Phase 12 files after the fix commits `0cfa619` (CR-01), `e992d70`
(WR-01 + IN-04), and `af9c60b` (Logging test-dep, outside the reviewed file set but
inspected for scope). All three prior Critical/Warning findings are fixed correctly,
and no new Critical or Warning defects were found. Verification detail:

**CR-01 (master_status always `:OPTIMIZE_NOT_CALLED`) — FIXED.**
`benders.jl:189` now captures `master_status_k = Symbol(termination_status(master.model))`
immediately after `solve_master!` returns — before `solve_follower!` and before any
`add_*_cut!` call — and both trace pushes (`benders.jl:225` feasibility, `benders.jl:277`
optimality) consume the captured symbol. I traced the window between the solve and the
capture for hidden mutations of `master.model`: `solve_master!` (`master.jl:262-281`)
only reads `value`/`objective_value` after `solve_with_retry!` returns, and
`solve_with_retry!` (`retry.jl:153-155`) sets `attempts_out` and returns on the same
success path with no post-solve model mutation (attribute escalation happens only
*before* a re-solve). Nothing dirties the model in that window, so the recorded status
is the genuine post-solve status on every row. The trailing `oracle_status` query at
`benders.jl:278` remains correct as-is: between the oracle solve and the query, only
`master.model` receives cuts and `checkpoint_iteration!` touches no model; the
post-solve gates inside `solve_planning_oracle!` (`subproblem.jl:297-305`) are
read-only (`assert_socp_exact!`/`assert_battery_complementarity!` read values, add no
constraints).

**WR-01 (solve_time included checkpoint/git I/O) — FIXED.**
`benders.jl:175-238` now accumulates `t_solve` by bracketing exactly the three solve
calls (`solve_master!`, `solve_follower!`, and `solve_planning_oracle!` on the
optimality branch) with the monotonic `time_ns()` clock, excluding cut appends,
`checkpoint_iteration!`'s JLD2/git shell-outs, and trace bookkeeping. The
`solve_time_trace` docstring (`trace.jl:77-81`) was updated to match the new
semantics. This also resolves the prior IN-04 (adjustable `time()` clock could go
negative under an NTP step and trip the `solve_time >= 0` push! guard).

**WR-02 (no test asserted `master_status_trace` contents) — FIXED.**
`test/test_planning_benders.jl:111-112` now asserts
`all(==(:OPTIMAL), result.trace.master_status_trace)` and
`result.trace.oracle_status_trace[end] == :OPTIMAL` on the end-to-end converging run —
exactly the regression assertion that would have caught CR-01 (before the fix, the
first assertion fails on the constant `:OPTIMIZE_NOT_CALLED` column; verified against
the fix ordering above that it now passes for genuine reasons: `assert_solved!` is a
strict gate, so a returned master solve is always `MOI.OPTIMAL`).

**Adversarial re-check for new issues introduced by the fixes:** the capture point is
before `solve_follower!`, so a follower/oracle exception mid-iteration leaves no
partial trace row (the run aborts loudly — consistent with the file's fail-loud
contract); the incumbent is always set before `gap <= tol` can trigger (first
optimality iteration has `cost_k < Inf`, so `y_best`/`z_best` are never returned as
their NaN initializers); `push!`'s guards all run before any field mutation, so a
rejected row cannot leave the ledger torn; the load test's trace-vs-log retry
cross-check remains exact (one escalation `@warn` per net retry, `Logging` now
declared in the test env per `af9c60b`); and the checkpoint-vs-trace equality
assertions in the load test compare like-for-like values (both record `UB` after the
incumbent update, `gap`/`NaN` sentinels compared via `isequal`). No new defects.

The remaining findings below are the prior review's Info items carried forward
verbatim (confirmed still present and still valid); they were explicitly out of fix
scope and none rises to Warning severity.

## Info

### IN-01: `Ref(1)` sentinel for `master_attempts`/`oracle_attempts` defeats the trace's own fail-loud `retry_count >= 0` guard

**File:** `src/planning/benders.jl:179,234`
**Issue:** Carried forward (prior IN-01, still present). If a future refactor ever
drops the `attempts_out` forwarding inside `solve_master!`/`solve_planning_oracle!`,
the Ref stays at its initial value and `retry_count = Ref(1)[] - 1 = 0` is silently
recorded forever — a plausible-looking value no guard can catch. Initializing with
`Ref(0)` would make a dropped-threading regression produce `retry_count = -1`,
tripping `push!`'s existing `retry_count >= 0` `ArgumentError` loudly (the project's
own fail-loud idiom). The comment's rationale is inverted: if a call site omitted the
keyword, the initial value would be the only value ever read, so `Ref(1)` *hides*
staleness rather than making it safe.
**Fix:** Initialize `master_attempts = Ref(0)` / `oracle_attempts = Ref(0)` and update
the comment: the 0 sentinel converts a silent threading regression into a loud
`ArgumentError` via the `retry_count >= 0` guard.

### IN-02: `n_cuts_trace` docstring says "this iteration's cut" (singular); optimality iterations append two cuts

**File:** `src/planning/trace.jl:63-65`
**Issue:** Carried forward (prior IN-02, still present). On the optimality branch,
`benders.jl` appends both the `:op` and `:x` cuts before the push, so `n_cuts_trace`
jumps by 2 per optimality iteration (by 1 on feasibility iterations). The singular
phrasing under-describes the semantics a reader will use when interpreting
`diff(n_cuts_trace)`.
**Fix:** Document: "+2 on an optimality iteration (`:op` and `:x` cuts), +1 on a
feasibility iteration."

### IN-03: Episode LB-monotonicity test — the feasibility cuts never bind, so half the claimed tightening mechanism is inert

**File:** `test/test_planning_hardening.jl:128-149`
**Issue:** Carried forward (prior IN-03, still present). The master's optimum in this
episode sits at `y_inv = 0, z = 0` (only the `cost_ks` optimality cuts bind `α_op`).
The feasibility cuts `z <= z_caps[i]` (z_caps 8.0→2.0) are all slack at `z = 0`, so —
contrary to the comment "ONLY the deliberately tightening scalar (cost_k / z_cap)
drives the bound each round" — the `z_cap` sequence contributes nothing to any LB
value, and a mis-built feasibility row (e.g. a sign-flipped `u`) would not be detected
by the monotonicity assertion. The genuine-Farkas near-boundary items exercise real
feasibility cuts, so coverage exists elsewhere; this item's comment overstates what it
verifies.
**Fix:** Either make at least one round's feasibility cut bind, or trim the comment to
claim only what the assertion tests (cost_k-driven LB monotonicity under redundant
appended rows).

### IN-04: Load-test iteration band (`iters in 50:199`) is pinned to exact solver versions

**File:** `test/test_planning_hardening.jl:261-262`
**Issue:** Carried forward (prior IN-05, still present). `@test result.iters >= 50` /
`< 200` encodes an empirically measured cutting-plane trajectory (66 iterations) that
depends on HiGHS/Clarabel internals. The file documents the measurement and the test
env pins HiGHS exactly, so this is acceptable today — but any solver bump can flip
this to a red with no product bug (the WR-04 skip-degrade idiom in
`test_planning_retry.jl` is the better pattern). Flagged so a future upgrade triages
it as fixture drift, not a Benders regression.
**Fix:** Acceptable as-is given the exact-pin; alternatively assert the qualitative
properties only (`converged`, `iters < max_iter`, trace/checkpoint invariants) and log
`iters` via `@info`.

---

_Reviewed: 2026-07-23_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
