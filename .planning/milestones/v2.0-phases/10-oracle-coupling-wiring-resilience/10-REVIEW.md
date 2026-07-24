---
phase: 10-oracle-coupling-wiring-resilience
reviewed: 2026-07-22T19:03:17Z
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
  warning: 0
  info: 7
  total: 7
status: clean
---

# Phase 10: Code Review Report (iteration 3 — final fix verification)

**Reviewed:** 2026-07-22T19:03:17Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** clean

## Summary

Final re-review after fix commit `4919817` addressing iteration 2's sole Warning (WR-01:
the CR-03 SOCP exactness-gate wiring in `solve_planning_oracle!` had zero test coverage).
Git history confirms `4919817` is the ONLY change to the reviewed files since iteration 2
(51 lines added to `test/test_planning_oracle.jl`; all four `src/` files byte-identical),
so this review focused on the soundness of the new testitem and any issues it could
introduce.

**WR-01 fix verdict — SOUND, verified by independent execution:**

The new testitem (`test/test_planning_oracle.jl:267-316`, "ConvexBranchFlow solve runs the
PF-04 exactness gate and stashes socp_maxgap (CR-03)") implements exactly the mandatory
half of the iteration-2 fix suggestion. Every cross-referenced dependency was traced:

- `operational_oracle(...; z = nothing, allow_export = true)` on `ConvexBranchFlow` routes
  through `solve_welfare`, which stashes `ctx.meta[:p_import]` (welfare_solve.jl:210) —
  the `zstar = value.(free.ctx.meta[:p_import])` read is valid, and the free solve itself
  passes the same exactness gate (welfare_solve.jl:256-258), so `zstar` is a
  certified-exact pin point by construction.
- `ConvexBranchFlow`'s `contribute!` stashes `ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)`
  (ConvexBranchFlow.jl:232), so the pre-solve assertions
  `haskey(o.ctx.meta[:pf_vars], :l)` (NamedTuple `haskey` — valid) and
  `!haskey(o.ctx.meta, :socp_maxgap)` (nothing writes that key at build time) arm the gate.
- `assert_socp_exact!` returns `maxgap::Float64` (exactness.jl:78-107), matching the
  post-solve `isa Float64` assertion; on the PlanningOracle's own `ctx`, subproblem.jl:288
  is the sole `:socp_maxgap` writer (the free oracle's ctx is a distinct object), so
  `haskey(res.ctx.meta, :socp_maxgap)` genuinely proves the gate branch executed — the
  exact `haskey` chain of subproblem.jl:287, the meta key, and the throw-through path are
  all now covered.
- **Empirical verification:** I replicated the testitem's body (with the Phase6Fixtures
  logic inlined verbatim) in an isolated scratch environment against the current source —
  10/10 assertions pass, `socp_maxgap = 1.64e-7`, roughly two orders of magnitude inside
  the test's `1e-5` bound (not a fragile margin). The `problem_class(::ConvexBranchFlow)
  = SOCP()` override (ConvexBranchFlow.jl:241) also makes this the first test to exercise
  the SOCP-side τ default (`get(o.ctx.meta, :problem_class, nothing) isa SOCP ? 1e-3 :
  1e-6`, subproblem.jl:269) with a `SOCP()` stash, closing that branch too.

**No new issues introduced.** The testitem is self-contained (imports `value`, reuses the
established fixture/feasibility pattern from the file header note, reuses `aggs` across
builds exactly as the pre-existing items at lines 90-124 do) and modifies no source file.
One narrow residual of the fix is recorded as new Info IN-07 (the refuse side of the gate
on the *oracle path* and the `rtol_exact` forwarding remain indirectly covered only) — it
was the explicitly "optional" half of the iteration-2 fix suggestion, and the refuse
behavior of `assert_socp_exact!` itself is directly covered by
`test/test_exactness.jl:48,134`.

The 6 Info findings from iteration 2 (IN-01..IN-06) were out of fix scope; their code
anchors are unchanged and all remain valid, carried forward below. No Critical or Warning
findings remain — status is **clean** (info-only findings do not block).

## Info

### IN-01: `catch` block in `solve_with_retry!` swallows the original exception and can misattribute non-status `ErrorException`s

**File:** `src/planning/retry.jl:141-161`
**Issue:** (Carried forward from iterations 1-2, unchanged.) Any `ErrorException` — not
just `assert_solved!`'s status failure — enters the status-inspection path; the original
message/backtrace is discarded and replaced by the re-queried status diagnostic. A future
`ErrorException` source inside `assert_solved!`'s call tree with healthy model statuses
would be reported under an "exhausted attempts" banner.
**Fix:** Log the original via `@error exception = (e, catch_backtrace())` before raising,
or introduce a typed `SolveFailedError` in `assert_solved!` so the catch is precise.

### IN-02: "exhausted N attempt(s)" message is misleading for a non-retryable immediate raise

**File:** `src/planning/retry.jl:152-160` (test: `test/test_planning_retry.jl:108`)
**Issue:** (Carried forward, unchanged.) A genuinely `INFEASIBLE` model raises
"exhausted 1 attempt(s)" — no retry budget was exhausted; the status was refused as
non-retryable. The test's `occursin("exhausted 1 attempt", ...)` cements the wording.
**Fix:** Branch the message: "non-retryable status after attempt N" vs "retry budget
exhausted after N attempt(s)"; update the test's `occursin` accordingly.

### IN-03: `π_s` docstring claims non-uniform-Δt readiness, but `Δt::Real` is a scalar

**File:** `src/planning/subproblem.jl:251-254, 267, 298`
**Issue:** (Carried forward, unchanged.) "correct-by-construction for a future
non-uniform `Δt`" — a scalar `Δt::Real` cannot express a duration vector;
`sum(Δt * π[t] for t in 1:o.T)` would need `Δt[t]`.
**Fix:** Accept `Δt::Union{Real, AbstractVector{<:Real}}` with a length guard, or soften
the docstring to "uniform Δt today."

### IN-04: ~80 lines of `solve_welfare` assembly duplicated verbatim — drift risk between the twin builders

**File:** `src/planning/subproblem.jl:130-198` (vs `src/models/welfare_solve.jl:117-238`)
**Issue:** (Carried forward, unchanged — documented deliberate D-03/D-11 decision.) The
bridge/guard/contribute!/frontier/closure sequence is a near-verbatim copy; a future fix
to `solve_welfare`'s assembly will not propagate. Known divergence: welfare_solve stashes
`ctx.meta[:agg_net]` (PRICE-03); the oracle does not.
**Fix:** No action now. When Phase 11+ touches either file, extract a shared
`_assemble_welfare_core!` both call.

### IN-05: Cross-call retry escalation can partially DE-escalate a previously-needed rung-4 conditioning

**File:** `src/planning/retry.jl:94-108` (docstring 55-64)
**Issue:** (Carried forward from iteration 2, unchanged.) The "complete attribute set"
property holds within one call, but stickiness is cross-call: after a prior call ended at
rung 4 (`static_regularization_constant => 1e-5`, `dynamic_regularization_eps => 1e-11`,
refine 200), a later call that fails retryably on attempt 1 runs rung 2, which *lowers*
`static_regularization_constant` back to 1e-6 while retaining rung-4's
`dynamic_regularization_eps`/`iterative_refinement_max_iter` leftovers — a mixed regime
no rung defines. Consequence is bounded (rungs 2-3 waste two solves + warnings before
rung 4 restores the full set; termination is still trusted-or-loud).
**Fix:** Either start later calls' escalation at the highest previously-applied rung
(track it in a model attribute or a small wrapper struct), or note the cross-call
rung-2/3 de-escalation explicitly in the stickiness paragraph.

### IN-06: WR-02 fix covers set-time attribute rejection only; lazily-validating backends still bypass the diagnostic

**File:** `src/planning/retry.jl:125-139`
**Issue:** (Carried forward from iteration 2, unchanged.) The `try`/`catch` converts a
rejection thrown *by `set_optimizer_attribute`* into the loud diagnostic — correct for
backends that validate raw options at set time (e.g. HiGHS). A backend that stores raw
options and validates them at `optimize!` time (Ipopt-style) would instead throw inside
`assert_solved!` on the next attempt: if that exception is not an `ErrorException` it
propagates raw (undiagnosed); if it is, it is misattributed to a solve-status failure
with possibly stale statuses. Latent — the production path is Clarabel-only.
**Fix:** No action required for v1; if a non-Clarabel retryable path ever becomes live,
detect the backend up front (`solver_name(model)`) and refuse rungs ≥ 2 with the loud
diagnostic before attempting escalation.

### IN-07: Oracle-path refuse side of the exactness gate and `rtol_exact` forwarding covered only indirectly

**File:** `src/planning/subproblem.jl:287-289` (test: `test/test_planning_oracle.jl:267-316`)
**Issue:** New residual of the WR-01 fix (its explicitly optional half). The new testitem
proves the gate branch *executes and passes* on the ConvexBranchFlow oracle path; the
refuse side (the `error(...)` from `assert_socp_exact!` propagating out of
`solve_planning_oracle!` before any `dual.()` read) is covered only transitively via
`test/test_exactness.jl:48,134`, which exercises `assert_socp_exact!` directly on a
welfare ctx, not through the oracle. Likewise, a *loosening* typo in the `rtol =
rtol_exact` forwarding (e.g. `1e4` for `1e-4`) would not fail the pass-side test — only a
tightening typo would. Low risk: the forwarding is a one-line literal kwarg pass-through
and the gate function itself is well-tested.
**Fix:** Optional. Pair the new testitem with an inexact fixture (the high-PV/no-export
regime `test_exactness.jl:98-134` already constructs) asserting
`@test_throws ErrorException solve_planning_oracle!(...)`, or assert the gate throws at a
deliberately tiny `rtol_exact` at the exact point to prove the kwarg reaches the gate.

---

_Reviewed: 2026-07-22T19:03:17Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
