---
phase: 10-oracle-coupling-wiring-resilience
reviewed: 2026-07-22T18:03:56Z
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
  critical: 3
  warning: 4
  info: 4
  total: 11
status: issues_found
---

# Phase 10: Code Review Report

**Reviewed:** 2026-07-22T18:03:56Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Reviewed the Phase-10 planning-layer resilience seams (`solve_with_retry!`, `checkpoint_iteration!`/`resume_from_checkpoint`) and the build-once `PlanningOracle` subproblem, plus their three test files and the `TSODSO.jl` wiring. Cross-referenced against the dependencies each file claims to reuse verbatim: `assert_solved!` (src/core/status.jl), `ModelContext`, `solve_welfare` (src/models/welfare_solve.jl), `operational_oracle`/`_coupling_dual` (src/models/oracle.jl), `Aggregator.contribute!`, the DrWatson `safesave` implementation (`~/.julia/packages/DrWatson/2QF5p/src/saving_files.jl`), and the Phase-6/8 test fixtures.

The wiring (`TSODSO.jl`), include ordering, boundary guards, Parameter-based re-solve discipline, and the dual-sign toy-case regression are sound. However, three Critical defects exist, and each one is precisely in the failure-handling territory this phase exists to harden:

1. `solve_with_retry!` has a silent fall-off-the-end path that returns `nothing` after a failed solve when `max_attempts > 4` (or `< 1`) — the exact "silent-corrupt" outcome D-10 forbids, and `solve_planning_oracle!` would then read duals from the untrusted model.
2. `resume_from_checkpoint` returns the **stale** pre-crash state after the documented crash-redo workflow, because DrWatson `safesave` backup files (`iter_NNNNN_#1.jld2`) lexicographically sort **after** the fresh canonical file.
3. `solve_planning_oracle!` returns `π`/`dadp` duals with **neither** the PF-04 SOCP exactness gate nor the mandatory App. C battery-complementarity check that `solve_welfare` (the model it mirrors) treats as preconditions for trusting any dual.

## Critical Issues

### CR-01: `solve_with_retry!` silently returns `nothing` after a failed solve when `max_attempts` exceeds the ladder length (or is < 1)

**File:** `src/planning/retry.jl:76-100`
**Issue:** The loop iterates over `ladder[1:min(max_attempts, length(ladder))]` — at most 4 rungs — but the retry decision uses `attempt < max_attempts`. With `max_attempts = 5` (or any value > 4), a retryable failure on rung 4 satisfies `4 < 5`, executes `continue`, the loop then ends, and the function falls off the end returning `nothing` — no error, no warning of exhaustion. The caller `solve_planning_oracle!` (src/planning/subproblem.jl:254-258) discards the return value and immediately reads `dual.(o.pin)`, `dual.(...)`, and `objective_value(o.model)` from a model whose last solve **failed** — exactly the "silent-corrupt" outcome the file's own D-10 contract ("raise loudly, never silent-skip") forbids. Depending on what Clarabel left in the result cache, this either throws an unrelated result-access error or, worse, returns numerically garbage prices as if trusted. Symmetrically, `max_attempts <= 0` makes `ladder[1:min(0,4)]` empty: the loop never runs, `optimize!` is never called, and the function again silently returns `nothing`. `max_attempts` is a public keyword forwarded verbatim by `solve_planning_oracle!`, so both paths are reachable by any caller tuning the budget upward for a stubborn instance.
**Fix:** Clamp/validate the budget and make budget exhaustion at the ladder end raise. Minimal version:

```julia
function solve_with_retry!(model::Model; max_attempts::Int = 4, dual::Bool = true)
    1 <= max_attempts || throw(ArgumentError("max_attempts must be ≥ 1, got $max_attempts"))
    ladder = [...]
    n_attempts = min(max_attempts, length(ladder))
    for (attempt, settings) in enumerate(ladder[1:n_attempts])
        ...
            if ts in RETRYABLE_STATUSES && attempt < n_attempts   # ladder-aware, not budget-aware
                @warn ...
                continue
            end
            error(...)
        ...
    end
end
```

The key change is `attempt < n_attempts` (the number of rungs actually available), so the final available rung always terminates in either `return assert_solved!(...)` or the loud `error(...)`.

### CR-02: `resume_from_checkpoint` returns the stale DrWatson backup, not the freshest checkpoint, after re-checkpointing the highest iteration

**File:** `src/planning/checkpoint.jl:70-73` (interacting with `checkpoint_iteration!`'s `safe = true`, line 46)
**Issue:** `checkpoint_iteration!` uses `@tagsave(...; safe = true)`, which routes through DrWatson's `safesave`: when `iter_00002.jld2` already exists, the **existing** file is renamed to `iter_00002_#1.jld2` and the **new** data is written to the canonical `iter_00002.jld2` (verified in DrWatson 2QF5p `saving_files.jl:275-300`). But `resume_from_checkpoint` selects `files[end]` from a plain lexicographic sort of *all* `.jld2` files — and `'_'` (0x5F) sorts after `'.'` (0x2E), so `sort(["iter_00002.jld2", "iter_00002_#1.jld2"])` puts the **backup last** (verified: `['iter_00002.jld2', 'iter_00002_#1.jld2']`). The result: in the exact workflow this primitive exists for — crash during iteration k, resume, redo iteration k, checkpoint k again, crash again, resume — the second resume loads `iter_k_#1.jld2`, the **pre-redo stale state**, silently, while reporting the correct iteration number. With multiple redos it gets worse: `_#2` (the oldest save) sorts after `_#1`, so `files[end]` is the *oldest* state. This directly contradicts the file's own T-10-02 rationale ("`safe = true` ... never silently overwrites a prior checkpoint") — the overwrite is prevented, but the resume path then silently *reads the overwritten data*. Additionally, any foreign `.jld2` file in the directory that sorts last raises `KeyError("iteration")` instead of a diagnosable error.
**Fix:** Restrict the resume scan to canonical checkpoint names (excluding `safesave` backups and foreign files), e.g.:

```julia
function resume_from_checkpoint(dir::AbstractString = datadir("planning_checkpoints"))
    isdir(dir) || return nothing
    files = sort(filter(f -> occursin(r"^iter_\d{5}\.jld2$", basename(f)),
                        readdir(dir; join = true)))
    isempty(files) && return nothing
    dict = wload(files[end])
    return (; iteration = dict["iteration"], state = dict["state"])
end
```

Also add a test that checkpoints the same iteration twice with different states and asserts resume returns the **second** state — the current test suite (test_planning_checkpoint.jl) never exercises a re-save, so this bug is invisible to it.

### CR-03: `solve_planning_oracle!` returns duals without the PF-04 SOCP exactness gate or the mandatory App. C battery check

**File:** `src/planning/subproblem.jl:254-261`
**Issue:** `build_planning_oracle` explicitly advertises formulation-generic routing including `ConvexBranchFlow → SOCP` (docstring, lines 84-88), and its ctx carries the same `:pf_vars`/`:agg_device_vars` stashes the shared builders write. Yet `solve_planning_oracle!` reads `π = dual.(o.pin)` and `dadp = dual.(o.ctx.constraints[:balance_p][...])` with **no** `assert_socp_exact!` and **no** `assert_battery_complementarity!`. `solve_welfare` — the model this module claims to mirror — documents both as *mandatory* preconditions before any dual is read (welfare_solve.jl:243-264, threats T-04-01/T-04-03: "physically-meaningless duals from a STRICT (inexact) relaxation are REFUSED (thrown) rather than returned"), and CLAUDE.md pins "SOCP relaxation must be validated exact" as a hard project constraint. The risk is aggravated here, not reduced: the `pin[t]: p_import[t] == z[t]` constraint fixes the frontier exchange, removing the priced-export degree of freedom that welfare_solve identifies as the SOC-exactness *enabler* — so a `ConvexBranchFlow`-backed oracle at an off-optimal `z_trial` is exactly the regime where the cone can go slack, and `π` (the Benders-cut gradient feeding the entire Phase-11 planning loop) would be physically meaningless with zero signal. Similarly, a `PVBattery` device under the aggregator gets no complementarity certificate at the pinned point, where degenerate co-activation is *more* likely than at the free optimum.
**Fix:** Mirror welfare_solve's post-solve gate block between the retry-gated solve and the dual reads:

```julia
solve_with_retry!(o.model; max_attempts = max_attempts, dual = true)

if haskey(o.ctx.meta, :pf_vars) && haskey(o.ctx.meta[:pf_vars], :l)
    o.ctx.meta[:socp_maxgap] = assert_socp_exact!(o.ctx; rtol = rtol_exact)  # add rtol_exact kwarg
end
assert_battery_complementarity!(o.ctx; τ = τ, T = o.T)                       # add τ kwarg

π = dual.(o.pin)
...
```

Both gates are data-driven no-ops on the current LinDistFlow/QP test path, so this adds zero cost today while closing the SOCP hole the docstring's own formulation-genericity claim opens.

## Warnings

### WR-01: Retry-ladder attributes are never reset — escalated conditioning silently persists across all future re-solves of the build-once model

**File:** `src/planning/retry.jl:76-79`
**Issue:** `set_optimizer_attribute` mutates the model permanently. After one transient failure escalates to rung 2+, every subsequent call to `solve_with_retry!` on the same model starts with the escalated attributes still set — so "attempt 1: as-built (no attribute changes)" (docstring line 47 and inline comment line 63) is false from the second call onward. For the `PlanningOracle` (built once, re-solved hundreds of times inside a Benders loop), a single early numerical hiccup permanently changes the conditioning regime — and dual accuracy — of *all* later cuts, invisibly. Relatedly, rung 4 does not restate `equilibrate_max_iter`, so it runs with rung 3's leftover `equilibrate_max_iter => 50` — the docstring's rung-4 list (lines 50-51) does not mention this inherited setting.
**Fix:** Either (a) capture the pre-call attribute values and restore them on successful return, or (b) make the sticky escalation an explicit, documented contract (update the docstring, drop the "as-built" claim, and make each rung a *complete* attribute set so leftovers cannot combine unpredictably). Option (b) is likely the intent; it just must be stated.

### WR-02: The escalation rungs hardcode Clarabel raw-attribute names on a solver-generic `Model`

**File:** `src/planning/retry.jl:62-79`
**Issue:** `solve_with_retry!` is exported as a general API and accepts any `Model` (the infeasibility test itself passes a HiGHS-backed `LP()` model), but rungs 2-4 set Clarabel-specific raw attributes (`static_regularization_constant`, `iterative_refinement_max_iter`, `equilibrate_max_iter`, `dynamic_regularization_eps`). On a HiGHS- or Ipopt-backed model, a retryable status on attempt 1 (e.g. `SLOW_PROGRESS`, which both solvers can report) leads to `set_optimizer_attribute` throwing an unknown-option error on rung 2 — outside the `try`, so it propagates as a raw, undiagnosed exception instead of the D-10 four-line diagnostic. Today's only production caller routes to Clarabel (QP/SOCP classes), so this is latent, not live — but it violates the project's "no model names a concrete solver" symmetry: the *retry wrapper* now assumes one.
**Fix:** Guard the escalation by backend, e.g. skip (with a `@warn`) or wrap the `set_optimizer_attribute` loop in a `try`/`catch` that converts an unsupported-attribute failure into the loud exhaustion error; or document loudly in the docstring that rungs ≥ 2 REQUIRE a Clarabel backend and raise an `ArgumentError` up front when `solver_name(model) != "Clarabel"` is detectable.

### WR-03: `checkpoint_iteration!` accepts iteration numbers that silently break the lexicographic-order contract

**File:** `src/planning/checkpoint.jl:34-49`
**Issue:** No validation of `iter`. A negative value produces `iter_000-3.jld2` (`lpad(-3, 5, '0')` pads the string `"-3"`), which both pollutes the directory and sorts nonsensically. A value > 99999 produces `iter_100000.jld2`, which sorts lexicographically *before* `iter_99999.jld2` — so `resume_from_checkpoint` silently resumes from the wrong (lower) iteration, violating the "lexicographic sort is numerically correct" invariant the whole resume scheme rests on (docstring lines 27-29). Neither bound is guarded or documented as a hard limit.
**Fix:** `0 <= iter <= 99999 || throw(ArgumentError("iter must be in 0:99999 (5-digit zero-padded filename contract), got $iter"))` — or parse the iteration number back out of the filename in `resume_from_checkpoint` and sort numerically, removing the width limit entirely.

### WR-04: Retry test's ill-conditioned fixture pins solver-version-specific numerical behavior

**File:** `test/test_planning_retry.jl:36-38`
**Issue:** `@test termination_status(raw_model) in TSODSO.RETRYABLE_STATUSES` hard-asserts that a specific ill-conditioned SOCP with `max_iter = 5` fails with a *retryable* status on the current Clarabel version. Any Clarabel upgrade that changes iteration behavior (or reports `ITERATION_LIMIT`, which is NOT in `RETRYABLE_STATUSES`) turns this into a red test with no product bug — a flaky-on-upgrade pattern. The comment acknowledges it was "empirically verified this session," which is exactly the property that erodes. Note that `MOI.ITERATION_LIMIT` is the natural status for a `max_iter = 5` stop, so this test is one solver-version away from asserting on a status the ladder deliberately refuses to retry.
**Fix:** Make the precondition assertion tolerant: `@test termination_status(raw_model) != MOI.OPTIMAL` plus `if termination_status(raw_model) in TSODSO.RETRYABLE_STATUSES ... else @info "fixture no longer produces a retryable status; skipping escalation branch" end` — or gate the second half of the test on the observed status so a solver upgrade degrades to a skip, not a failure. (Separately worth deciding: should `ITERATION_LIMIT` be in `RETRYABLE_STATUSES`? The ladder increases refinement iterations, which is precisely the remedy for it.)

## Info

### IN-01: `catch` block in `solve_with_retry!` swallows the original exception and can misattribute non-status `ErrorException`s

**File:** `src/planning/retry.jl:82-97`
**Issue:** Any `ErrorException` — not just `assert_solved!`'s status failure — enters the status-inspection path; the original exception (message, backtrace) is discarded and replaced by the re-queried status diagnostic. If a future `ErrorException` source appears inside `assert_solved!`'s call tree while the model status is fine, the raised message would report healthy statuses under an "exhausted attempts" banner.
**Fix:** Chain the original: `error("solve_with_retry!: ... ")` → `throw(ErrorException(...))` preceded by `@error exception = (e, catch_backtrace())`, or match on the message/introduce a typed `SolveFailedError` in `assert_solved!` so the catch is precise.

### IN-02: "exhausted N attempt(s)" message is misleading for a non-retryable immediate raise

**File:** `src/planning/retry.jl:91-97`
**Issue:** A genuinely `INFEASIBLE` model raises "exhausted 1 attempt(s)" — but no retry budget was exhausted; the status was refused as non-retryable. The test even asserts on this wording (`test_planning_retry.jl:65`), cementing it. A future reader debugging an infeasibility will be told a retry budget ran out.
**Fix:** Branch the message: "non-retryable status after attempt N" vs "retry budget exhausted after N attempt(s)"; update the test's `occursin` accordingly.

### IN-03: `π_s` docstring claims non-uniform-Δt readiness, but `Δt::Real` is a scalar

**File:** `src/planning/subproblem.jl:242, 257` (docstring line 227-229)
**Issue:** "correct-by-construction for a future non-uniform `Δt`" — a scalar `Δt::Real` cannot express a non-uniform duration vector; `sum(Δt * π[t] for t in 1:o.T)` with a `Vector` Δt would need `Δt[t]`. The claim is aspirational, not structural.
**Fix:** Either accept `Δt::Union{Real, AbstractVector{<:Real}}` and index it (`Δt isa Real ? Δt : Δt[t]`, with a length guard), or soften the docstring to "uniform Δt today; vectorize when non-uniform steps land."

### IN-04: ~80 lines of `solve_welfare` assembly duplicated verbatim — drift risk between the twin builders

**File:** `src/planning/subproblem.jl:130-193` (vs `src/models/welfare_solve.jl:117-238`)
**Issue:** The bridge registration, guard block, contribute!/frontier/reactive-capture/closure sequence is a near-verbatim copy of `solve_welfare`'s. This is a *documented, deliberate* D-03/D-11 decision (do not modify Phase-3/4 files), but it creates a maintenance seam: a future WR-class fix to welfare_solve's assembly (as has already happened once — WR-03 ordering) will not propagate here, and nothing enforces the "identical shape" claim. Note one already-diverged detail: welfare_solve stashes `ctx.meta[:agg_net]` (PRICE-03); the oracle intentionally does not — fine today, but the divergence list will only grow.
**Fix:** No action required now. When Phase 11+ touches either file, consider extracting the shared assembly into one internal `_assemble_welfare_core!(ctx, feeder, pf, aggregators; T, frontier)` both call, so the pin becomes a post-assembly addition rather than a fork.

---

_Reviewed: 2026-07-22T18:03:56Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
