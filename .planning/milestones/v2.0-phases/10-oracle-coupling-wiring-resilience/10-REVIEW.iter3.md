---
phase: 10-oracle-coupling-wiring-resilience
reviewed: 2026-07-22T18:44:10Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - src/TSODSO.jl
  - src/planning/checkpoint.jl
  - src/planning/retry.jl
  - src/planning/subproblem.jl
  - test/test_planning_checkpoint.jl
  - test/test_planning_oracle.jl
  - test/test_planning_retry.jl
findings:
  critical: 0
  warning: 1
  info: 6
  total: 7
status: issues_found
---

# Phase 10: Code Review Report (iteration 2 — fix verification)

**Reviewed:** 2026-07-22T18:44:10Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Re-reviewed the Phase-10 files after the fix commits `4d59130..e8f9911` addressing the iteration-1 findings (3 Critical + 4 Warning, backed up at `10-REVIEW.iter2.md`). Each fix was traced against its cross-referenced dependencies: `assert_solved!` (src/core/status.jl), `assert_socp_exact!` (src/models/exactness.jl), `assert_battery_complementarity!` + the `solve_welfare` gate block and τ default (src/models/welfare_solve.jl:107, 241-264), the `pf_vars`/`agg_device_vars` meta stashes (ConvexBranchFlow.jl:232, LinDistFlow.jl:97, Aggregator.jl:174), and the `ProblemClass` trait structs.

**Fix verification verdict — all 7 prior findings are soundly fixed:**

- **CR-01 (retry fall-through):** FIXED. `max_attempts >= 1` guard (retry.jl:89) throws `ArgumentError` before touching the model; `n_attempts = min(max_attempts, length(ladder))` (line 116) and the ladder-aware retry decision `attempt < n_attempts` (line 146) guarantee the final available rung terminates in `return assert_solved!(...)` or the loud `error(...)`. Regression tests cover the overshoot budget (`max_attempts = 10`, test_planning_retry.jl:58-73) and the `<= 0` path including a `MOI.OPTIMIZE_NOT_CALLED` untouched-model assertion (lines 80-95).
- **CR-02 (stale safesave-backup resume):** FIXED. `resume_from_checkpoint` now filters `basename` against `r"^iter_\d{5}\.jld2$"` (checkpoint.jl:98-103), excluding `iter_NNNNN_#k.jld2` backups and foreign `.jld2` files. Sorting joined paths within one directory is equivalent to sorting basenames, so the highest-iteration invariant holds. Regression tests cover double-save, triple-save (oldest backup sorting last), and a foreign trailing file (test_planning_checkpoint.jl:70-118).
- **CR-03 (missing dual trust gates):** FIXED. `solve_planning_oracle!` now runs the PF-04 exactness gate (data-driven on the `:l` stash — the exact `haskey` chain welfare_solve.jl:256 uses) and the mandatory App. C battery check strictly between the retry-gated solve and any `dual.()` read (subproblem.jl:287-295). The `τ` default mirrors `solve_welfare`'s problem-class-aware default (welfare_solve.jl:107) via the `:problem_class` stashed at build time (subproblem.jl:146, 269); a missing stash defaults to the *tighter* 1e-6 (fails loud, never loose). `ctx.meta[:feeder]`/`[:T]`/`[:pf_vars]` — everything `assert_socp_exact!` reads — are all populated by `build_planning_oracle`. One coverage gap remains (WR-01 below).
- **WR-01 (sticky attributes):** FIXED as documented contract — the docstring now states the stickiness explicitly (retry.jl:55-64) and rung 4 restates `equilibrate_max_iter => 50`, making each rung ≥ 2 a complete set for the within-one-call case. A cross-call residual quirk remains (IN-05 below).
- **WR-02 (Clarabel attrs on a generic model):** FIXED for set-time rejection — the `set_optimizer_attribute` call is wrapped and converted into the D-10 four-line diagnostic naming the backend and attribute (retry.jl:125-139); statuses are queryable there because escalation only runs after attempt 1's solve. A lazy-validation residual remains (IN-06 below).
- **WR-03 (iteration bounds):** FIXED. `0 <= iter <= 99999` guard (checkpoint.jl:49-53) with boundary-value tests (0 and 99999 accepted; -3 and 100000 rejected).
- **WR-04 (solver-version-pinned fixture):** FIXED. The test measures the raw status first, hard-asserts only the stable property (`!= MOI.OPTIMAL`), and gates the escalation branch on the observed status, degrading to an `@info` skip on solver drift (test_planning_retry.jl:40-77).

No new Critical issues were introduced by the fixes. One new Warning (untested SOCP branch of the CR-03 fix) and two new Info items (residual edges of the WR-01/WR-02 fixes); four Info items carry forward from iteration 1 unchanged, as they were out of fix scope and remain valid.

## Warnings

### WR-01: The CR-03 SOCP exactness-gate wiring in `solve_planning_oracle!` has zero test coverage

**File:** `src/planning/subproblem.jl:287-289` (tests: `test/test_planning_oracle.jl`)
**Issue:** The CR-03 fix commit (`75993e2`) touched only `src/planning/subproblem.jl` — unlike CR-01 and CR-02, no regression test was added. Every `PlanningOracle` test builds on `LinDistFlow()`, whose `pf_vars` stash is `(; v, P, Q)` (no `:l`), so the `haskey(o.ctx.meta, :pf_vars) && haskey(o.ctx.meta[:pf_vars], :l)` branch is a no-op in the entire suite (`grep ConvexBranchFlow test/test_planning_*.jl` → no matches). The battery gate at least executes as a pass-through via Phase6Fixtures' PVBattery aggregator, but the exactness gate — the load-bearing half of the fix, per its own comment ("MORE load-bearing at an off-optimal z_trial than in the free welfare solve") — would silently ship broken if the `haskey` chain, the meta key, or the `rtol_exact` forwarding had a typo. The 1994-pass suite is not evidence this branch works; it is evidence it never runs.
**Fix:** Add one `ConvexBranchFlow`-backed oracle testitem mirroring `test_exactness.jl`'s exact-point pattern (radial fixture with the LinDistFlow exactness copy): build the oracle, solve at a feasible `z_trial`, and assert `haskey(res.ctx.meta, :socp_maxgap)` and `res.ctx.meta[:socp_maxgap] < tol` — proving the gate ran and passed. Optionally pair it with a deliberately inexact fixture (the high-PV/no-export regime `test_exactness.jl:98-134` already constructs) asserting `@test_throws` — proving the gate refuses.

## Info

### IN-01: `catch` block in `solve_with_retry!` swallows the original exception and can misattribute non-status `ErrorException`s

**File:** `src/planning/retry.jl:141-161`
**Issue:** (Carried forward from iteration 1, unchanged.) Any `ErrorException` — not just `assert_solved!`'s status failure — enters the status-inspection path; the original message/backtrace is discarded and replaced by the re-queried status diagnostic. A future `ErrorException` source inside `assert_solved!`'s call tree with healthy model statuses would be reported under an "exhausted attempts" banner.
**Fix:** Log the original via `@error exception = (e, catch_backtrace())` before raising, or introduce a typed `SolveFailedError` in `assert_solved!` so the catch is precise.

### IN-02: "exhausted N attempt(s)" message is misleading for a non-retryable immediate raise

**File:** `src/planning/retry.jl:152-160` (test: `test/test_planning_retry.jl:108`)
**Issue:** (Carried forward, unchanged.) A genuinely `INFEASIBLE` model raises "exhausted 1 attempt(s)" — no retry budget was exhausted; the status was refused as non-retryable. The test's `occursin("exhausted 1 attempt", ...)` cements the wording.
**Fix:** Branch the message: "non-retryable status after attempt N" vs "retry budget exhausted after N attempt(s)"; update the test's `occursin` accordingly.

### IN-03: `π_s` docstring claims non-uniform-Δt readiness, but `Δt::Real` is a scalar

**File:** `src/planning/subproblem.jl:251-254, 267, 298`
**Issue:** (Carried forward, unchanged.) "correct-by-construction for a future non-uniform `Δt`" — a scalar `Δt::Real` cannot express a duration vector; `sum(Δt * π[t] for t in 1:o.T)` would need `Δt[t]`.
**Fix:** Accept `Δt::Union{Real, AbstractVector{<:Real}}` with a length guard, or soften the docstring to "uniform Δt today."

### IN-04: ~80 lines of `solve_welfare` assembly duplicated verbatim — drift risk between the twin builders

**File:** `src/planning/subproblem.jl:130-198` (vs `src/models/welfare_solve.jl:117-238`)
**Issue:** (Carried forward, unchanged — documented deliberate D-03/D-11 decision.) The bridge/guard/contribute!/frontier/closure sequence is a near-verbatim copy; a future fix to `solve_welfare`'s assembly will not propagate. Known divergence: welfare_solve stashes `ctx.meta[:agg_net]` (PRICE-03); the oracle does not.
**Fix:** No action now. When Phase 11+ touches either file, extract a shared `_assemble_welfare_core!` both call.

### IN-05: Cross-call retry escalation can partially DE-escalate a previously-needed rung-4 conditioning

**File:** `src/planning/retry.jl:94-108` (docstring 55-64)
**Issue:** New residual edge of the WR-01 fix. The "complete attribute set" property holds within one call, but stickiness is cross-call: after a prior call ended at rung 4 (`static_regularization_constant => 1e-5`, `dynamic_regularization_eps => 1e-11`, refine 200), a later call that fails retryably on attempt 1 runs rung 2, which *lowers* `static_regularization_constant` back to 1e-6 while retaining rung-4's `dynamic_regularization_eps`/`iterative_refinement_max_iter` leftovers — a mixed regime no rung defines, and a strictly weaker static regularization than the one the model already demonstrated it needs. Consequence is bounded (rungs 2-3 waste two solves + warnings before rung 4 restores the full set; termination is still trusted-or-loud), but the docstring's "predictable combinations" claim does not hold across calls.
**Fix:** Either start later calls' escalation at the highest previously-applied rung (track it in a model attribute or a small wrapper struct), or note the cross-call rung-2/3 de-escalation explicitly in the stickiness paragraph.

### IN-06: WR-02 fix covers set-time attribute rejection only; lazily-validating backends still bypass the diagnostic

**File:** `src/planning/retry.jl:125-139`
**Issue:** New residual edge of the WR-02 fix. The `try`/`catch` converts a rejection thrown *by `set_optimizer_attribute`* into the loud diagnostic — correct for backends that validate raw options at set time (e.g. HiGHS). A backend that stores raw options and validates them at `optimize!` time (Ipopt-style) would instead throw inside `assert_solved!` on the next attempt: if that exception is not an `ErrorException` it propagates raw (undiagnosed); if it is, it is misattributed to a solve-status failure with possibly stale statuses. Latent — the production path is Clarabel-only — same class as the original WR-02.
**Fix:** No action required for v1; if a non-Clarabel retryable path ever becomes live, detect the backend up front (`solver_name(model)`) and refuse rungs ≥ 2 with the loud diagnostic before attempting escalation.

---

_Reviewed: 2026-07-22T18:44:10Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
