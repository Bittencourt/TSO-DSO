---
phase: 12-cut-store-benders-master-robustness-hardening
reviewed: 2026-07-22T00:00:00Z
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
  critical: 1
  warning: 2
  info: 5
  total: 8
status: issues_found
---

# Phase 12: Code Review Report

**Reviewed:** 2026-07-22
**Depth:** standard
**Files Reviewed:** 10
**Status:** issues_found

## Summary

Phase 12 additions reviewed adversarially: the new `BendersTrace` ledger (`trace.jl`),
its wiring into both loop branches of `solve_stackelberg!` (`benders.jl`), the
`attempts_out::Ref{Int}` threading through `retry.jl`/`master.jl`/`subproblem.jl`, the
follower's `v > 0` Farkas guard (IN-06), and the new/extended tests including the
degenerate feasibility-cut edge cases and the 66-iteration load test.

The `attempts_out` threading is sound: `solve_with_retry!` sets the Ref only on its
single successful-return path (`retry.jl:155`), every failure path throws before the
caller can read a stale value, `benders.jl` allocates fresh Refs per iteration, and the
load test's trace-vs-log cross-check (`total_retries_from_trace == n_retry_warnings`)
is exact by construction (one escalation `@warn` per net retry). The trace's guard set,
sequential-`k` check, sentinel semantics (`UB = Inf`, `gap = NaN`, `:not_solved`), and
one-row-per-iteration-on-both-branches invariant (which the IN-01 exhaustion message
depends on) all hold under tracing.

However, one BLOCKER was found and verified against the pinned JuMP source: the
`master_status_trace` column records the dirty-model sentinel `:OPTIMIZE_NOT_CALLED`
on **every row of every run**, because the status is queried after cut rows are
appended to the master. The column's documented contract ("the genuine termination
status after this iteration's master solve") is never satisfied, and no test asserts
the column's contents, so the defect is invisible to the suite.

## Critical Issues

### CR-01: `master_status_trace` always records `:OPTIMIZE_NOT_CALLED` — status queried after cut appends dirty the master model

**File:** `src/planning/benders.jl:202` (feasibility branch) and `src/planning/benders.jl:245` (optimality branch)
**Issue:** Both trace pushes compute `master_status = Symbol(termination_status(master.model))` **after** a cut has been appended to `master.model`:

- Feasibility branch: `add_feasibility_cut!(master, ...)` runs at line 186, the trace push at lines 196–206.
- Optimality branch: `add_optimality_cut!(master, ...)` runs twice at lines 216/218, the trace push at lines 239–249.

`add_optimality_cut!`/`add_feasibility_cut!` call `@constraint` on `master.model`, and
JuMP's `add_constraint` sets `model.is_model_dirty = true` (verified: JuMP e83v9
`src/constraints.jl:569`). The master is built via `Model(select_optimizer(LP()))`
(`master.jl:98`) — a CACHING-mode model, not `direct_model` — and JuMP's
`MOI.get(model, MOI.TerminationStatus())` short-circuits to `MOI.OPTIMIZE_NOT_CALLED`
whenever `model.is_model_dirty && mode(model) != DIRECT` (verified: JuMP e83v9
`src/optimizer_interface.jl:756-758`). The HiGHS wrapper's own cached status is never
reached.

Consequence: `master_status_trace` is `[:OPTIMIZE_NOT_CALLED, :OPTIMIZE_NOT_CALLED, ...]`
on every iteration of every run — directly contradicting the field's documented
contract (`trace.jl:66-67`: "`Symbol(termination_status(master.model))` after this
iteration's master solve") and the file-header claim that both retry-gated
subproblems' **genuine** termination statuses are recorded. The ledger column that
Phase 12 exists to deliver is a constant sentinel. (`oracle_status_trace` is NOT
affected: nothing modifies `oracle.model` between its solve inside
`solve_planning_oracle!` and the query at line 246.)

**Fix:** Capture the master's status immediately after the master solve, before
`solve_follower!` and before any cut append, and use the captured symbol in both
pushes:

```julia
master_attempts = Ref(1)
lb_res = solve_master!(master; attempts_out = master_attempts)
master_status_k = Symbol(termination_status(master.model))   # capture BEFORE any cut append
...
push!(trace, k; ..., master_status = master_status_k, ...)   # both branches
```

Additionally add a regression assertion (see WR-02) so this cannot silently recur.

## Warnings

### WR-01: `solve_time_trace` measures checkpoint I/O and git provenance stamping, not subproblem solve time

**File:** `src/planning/benders.jl:167,205,248` (with `src/planning/trace.jl:77-78` documenting the contract)
**Issue:** `solve_time = time() - t_iter0` is computed **after** `checkpoint_iteration!`
on both branches. `checkpoint_iteration!` (`checkpoint.jl:56-62`) runs DrWatson's
`@tagsave` with `storepatch = true` and `gitpath = ...` — a JLD2 disk write **plus git
commit and patch-diff shell-outs, every iteration**. On the toy fixtures used
throughout (sub-millisecond LP/QP solves), the checkpoint overhead plausibly dominates
the recorded "solve time" by orders of magnitude. The field's documented contract
(`trace.jl:77-78`: "wall-clock seconds spent solving this iteration's subproblem(s)")
is therefore not what the column contains — it is per-iteration wall time including
cut appends, JLD2 I/O, and git subprocess latency. As a convergence-diagnostics ledger
intended for thesis-grade instrumentation ("measure, don't assume"), this is a
measurement-fidelity defect, not a style nit.
**Fix:** Either (a) bracket only the solves — accumulate
`t_solve = (time after solve_master!) - t_iter0` plus the follower/oracle solve spans,
and push that; or (b) if whole-iteration wall time is genuinely wanted, rename/redocument
the field as `iter_time_trace` ("wall-clock seconds for the full iteration including
checkpointing"). Option (a) matches the current docstring; option (b) is the smaller
diff.

### WR-02: No test asserts the contents of `master_status_trace` — the defective column passes the entire suite

**File:** `test/test_planning_benders.jl:94-104`, `test/test_planning_hardening.jl:244-266`
**Issue:** The trace assertions check `iters`, `gap_trace` length, `cut_type_trace`,
`is_converged`, `n_cuts_trace`, `retry_count_trace`, and
`oracle_status_trace[end] != :not_solved` — but never the value of any
`master_status_trace` entry (nor that `oracle_status_trace[end]` is specifically
`:OPTIMAL`, only that it differs from the sentinel). This is exactly the missing
assertion that lets CR-01's always-`:OPTIMIZE_NOT_CALLED` column ship green. A
documented ledger column whose value is never asserted anywhere is untested behavior.
**Fix:** In the end-to-end converging test add:

```julia
@test all(==(:OPTIMAL), result.trace.master_status_trace)
@test result.trace.oracle_status_trace[end] == :OPTIMAL
```

(after fixing CR-01; before the fix, the first assertion correctly fails).

## Info

### IN-01: `Ref(1)` sentinel for `master_attempts`/`oracle_attempts` defeats the trace's own fail-loud `retry_count >= 0` guard

**File:** `src/planning/benders.jl:168-171,211`
**Issue:** If a future refactor ever drops the `attempts_out` forwarding inside
`solve_master!`/`solve_planning_oracle!`, the Ref stays at its initial value and
`retry_count = Ref(1)[] - 1 = 0` is silently recorded forever — a plausible-looking
value that no guard can catch. Initializing with `Ref(0)` instead would make a
dropped-threading regression produce `retry_count = -1`, tripping `push!`'s existing
`retry_count >= 0` `ArgumentError` loudly (the project's own fail-loud idiom). The
accompanying comment's rationale is also inverted: if a call site *omitted* the
keyword, the initial value would be the only value ever read, so `Ref(1)` *hides*
staleness rather than making it safe.
**Fix:** Initialize `master_attempts = Ref(0)` / `oracle_attempts = Ref(0)` and update
the comment: the 0 sentinel converts a silent threading regression into a loud
`ArgumentError` via the `retry_count >= 0` guard.

### IN-02: `n_cuts_trace` docstring says "this iteration's cut" (singular); optimality iterations append two cuts

**File:** `src/planning/trace.jl:63-65`
**Issue:** On the optimality branch, `benders.jl` appends both the `:op` and `:x` cuts
before the push, so `n_cuts_trace` jumps by 2 per optimality iteration (by 1 on
feasibility iterations). The docstring's singular phrasing ("immediately after this
iteration's cut was appended") under-describes the semantics a reader will use when
interpreting `diff(n_cuts_trace)`.
**Fix:** Document: "+2 on an optimality iteration (`:op` and `:x` cuts), +1 on a
feasibility iteration."

### IN-03: Episode LB-monotonicity test — the feasibility cuts never bind, so half the claimed tightening mechanism is inert

**File:** `test/test_planning_hardening.jl:138-149`
**Issue:** The master's optimum in this episode sits at `y_inv = 0, z = 0` (only the
`cost_ks` optimality cuts bind `α_op`). The feasibility cuts `z <= z_caps[i]`
(z_caps 8.0→2.0) are all slack at `z = 0`, so — contrary to the comment "ONLY the
deliberately tightening scalar (cost_k / z_cap) drives the bound each round" — the
`z_cap` sequence contributes nothing to any LB value, and a mis-built feasibility row
(e.g. a sign-flipped `u`) would not be detected by the monotonicity assertion. The
genuine-Farkas near-boundary items do exercise real feasibility cuts, so coverage
exists elsewhere; this item's comment overstates what it verifies.
**Fix:** Either make at least one round's feasibility cut bind (e.g. a `z >= …`-shaped
cut combined with an optimality cut that rewards positive `z`), or trim the comment to
claim only what the assertion tests (cost_k-driven LB monotonicity under redundant
appended rows).

### IN-04: `time()` wall clock used for `solve_time`; a backward clock step crashes the run via the push! guard

**File:** `src/planning/benders.jl:167`
**Issue:** `solve_time = time() - t_iter0` uses the adjustable system clock. An NTP
step backwards mid-iteration yields a negative `solve_time`, and `push!`'s
`solve_time >= 0` guard (`trace.jl:178-179`) then aborts a potentially hours-long
research run with an `ArgumentError` unrelated to any model defect.
**Fix:** Use the monotonic clock: `t_iter0 = time_ns()` and
`solve_time = (time_ns() - t_iter0) / 1e9`.

### IN-05: Load-test iteration band (`iters in 50:199`) is pinned to exact solver versions

**File:** `test/test_planning_hardening.jl:261-262`
**Issue:** `@test result.iters >= 50` / `< 200` encodes an empirically measured
cutting-plane trajectory (66 iterations) that depends on HiGHS/Clarabel internals. The
file documents the measurement and the test env pins HiGHS exactly, so this is
acceptable today — but any solver bump can flip this to a red with no product bug
(the file's own WR-04 skip-degrade idiom in `test_planning_retry.jl` is the better
pattern). Flagged so a future upgrade triages it as fixture drift, not a Benders
regression.
**Fix:** Acceptable as-is given the exact-pin; alternatively assert the qualitative
properties only (`converged`, `iters < max_iter`, trace/checkpoint invariants) and
log `iters` via `@info`.

---

_Reviewed: 2026-07-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
