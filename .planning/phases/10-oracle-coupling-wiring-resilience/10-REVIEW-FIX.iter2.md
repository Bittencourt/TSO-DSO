---
phase: 10-oracle-coupling-wiring-resilience
fixed_at: 2026-07-22T18:38:00-03:00
review_path: .planning/phases/10-oracle-coupling-wiring-resilience/10-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 10: Code Review Fix Report

**Fixed at:** 2026-07-22T18:38:00-03:00
**Source review:** .planning/phases/10-oracle-coupling-wiring-resilience/10-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (3 Critical + 4 Warning; fix_scope = critical_warning, the 4 Info findings were not in scope)
- Fixed: 7
- Skipped: 0

**Verification:** every fix parse-checked (`Meta.parseall`), then the full `:planning`-tagged
test-item suite was run (48/48 pass), and finally the FULL package suite via
`Pkg.test()`: **1994 pass, 2 broken (pre-existing, documented `@test_broken`), 0
failures** in 8m13s, exit 0. Modified files were run through JuliaFormatter v2 (the
CI-enforced config) in a follow-up style commit.

## Fixed Issues

### CR-01: `solve_with_retry!` silently returns `nothing` after a failed solve when `max_attempts` exceeds the ladder length (or is < 1)

**Files modified:** `src/planning/retry.jl`, `test/test_planning_retry.jl`
**Commit:** 4d59130
**Applied fix:** Added an up-front `max_attempts >= 1 || throw(ArgumentError(...))` guard
(previously `max_attempts <= 0` skipped the loop entirely and silently returned `nothing`
without ever calling `optimize!`). Made the retry decision LADDER-aware: introduced
`n_attempts = min(max_attempts, length(ladder))` and changed the retry condition from
`attempt < max_attempts` to `attempt < n_attempts`, so the final available rung always
terminates in either `return assert_solved!(...)` or the loud D-10 `error(...)` — the
function can no longer fall off the end returning `nothing`. Docstring updated with the
clamp/validation semantics. Regression tests added (the review noted the existing suite
could not catch this): a new testitem asserting `ArgumentError` for `max_attempts = 0`
and `-3` (with `OPTIMIZE_NOT_CALLED` confirming the model was untouched), and an
`max_attempts = 10` overshoot exercise on the ill-conditioned fixture asserting the
wrapper either recovers or raises "exhausted" — never returns `nothing`. Semantics
verified by these passing regression tests, not just syntax check.

### CR-02: `resume_from_checkpoint` returns the stale DrWatson backup after re-checkpointing the highest iteration

**Files modified:** `src/planning/checkpoint.jl`, `test/test_planning_checkpoint.jl`
**Commit:** 034d66f
**Applied fix:** Restricted the resume scan to canonical checkpoint names via
`filter(f -> occursin(r"^iter_\d{5}\.jld2$", basename(f)), readdir(dir; join = true))`,
excluding DrWatson `safesave` backups (`iter_NNNNN_#k.jld2`, which hold STALE pre-redo
state yet sort lexicographically after the fresh canonical file because `'_'` > `'.'`)
and foreign `.jld2` files (which previously raised an undiagnosable
`KeyError("iteration")`). Docstring updated to document the canonical-only contract.
Regression tests added (explicitly requested by the review — the prior suite never
exercised a re-save): double-save of the same iteration asserting resume returns the
SECOND state while the `_#1` backup exists on disk; triple-save asserting the canonical
file still wins over `_#1`/`_#2`; and a foreign `.jld2` file that sorts last being
ignored. Semantics verified by these passing regression tests.

### CR-03: `solve_planning_oracle!` returns duals without the PF-04 SOCP exactness gate or the mandatory App. C battery check

**Files modified:** `src/planning/subproblem.jl`
**Commit:** 75993e2
**Applied fix:** Mirrored `solve_welfare`'s post-solve trust-gate block between the
retry-gated solve and the dual reads: (1) the PF-04 exactness gate
`assert_socp_exact!(o.ctx; rtol = rtol_exact)`, data-driven on the `:l` stash in
`ctx.meta[:pf_vars]` (only `ConvexBranchFlow` stashes `:l`; DC/LinDistFlow skip),
stashing `maxgap` under `ctx.meta[:socp_maxgap]`; (2) the mandatory App. C
`assert_battery_complementarity!(o.ctx; τ = τ, T = o.T)`. Added the `rtol_exact::Real =
1e-4` and problem-class-aware `τ` keywords mirroring `solve_welfare`'s defaults; since
`PlanningOracle` does not carry `pf`, `build_planning_oracle` now stashes
`ctx.meta[:problem_class] = problem_class(pf)` at build time and the `τ` default reads it
(`SOCP` path → `1e-3`, QP path → `1e-6`). Note: the battery gate is NOT a no-op on the
current test path (the review's claim was slightly off — `Aggregator.contribute!` does
stash `:agg_device_vars`, and Phase6Fixtures includes a `PVBattery`), so the gate was
exercised LIVE by the existing oracle tests at pinned `z_trial` points and passes
(48/48 planning tests green).

### WR-01: Retry-ladder attributes are never reset — escalated conditioning silently persists across re-solves

**Files modified:** `src/planning/retry.jl`
**Commit:** 529db8e
**Applied fix:** Took the review's option (b): made sticky escalation an explicit,
documented contract. The docstring now states that `set_optimizer_attribute` mutations
persist permanently, that later calls start their rung 1 from the last-escalated
conditioning (the "as-built" claim now applies only to the first-ever call), and WHY
this is intentional for a build-once model inside a Benders loop (a conditioning regime
needed once is assumed needed again rather than re-failing every iteration). Made every
rung ≥ 2 a COMPLETE attribute set: rung 4 now explicitly restates
`equilibrate_max_iter => 50` (previously inherited invisibly from rung 3's leftovers),
and the docstring's rung-4 list was corrected to match.

### WR-02: Escalation rungs hardcode Clarabel raw-attribute names on a solver-generic `Model`

**Files modified:** `src/planning/retry.jl`
**Commit:** c99d399
**Applied fix:** Wrapped the `set_optimizer_attribute` escalation loop in a `try`/`catch`
that converts a backend attribute rejection (e.g. HiGHS/Ipopt hitting rungs ≥ 2 after a
retryable attempt-1 status) into the D-10 loud 4-line diagnostic `error(...)` — naming
the backend (`solver_name(model)`), the offending attribute, the original rejection
(`sprint(showerror, attr_err)`), and the full status quadruple — instead of an
undiagnosed raw unknown-option exception. Statuses are safely queryable there because
escalation only runs after attempt 1 has solved and failed retryably. Docstring updated:
rungs ≥ 2 require a Clarabel backend; attempt 1 applies no attributes so any backend can
use the single-attempt path.

### WR-03: `checkpoint_iteration!` accepts iteration numbers that silently break the lexicographic-order contract

**Files modified:** `src/planning/checkpoint.jl`, `test/test_planning_checkpoint.jl`
**Commit:** b2f65ad
**Applied fix:** Added the review's suggested guard
`0 <= iter <= 99999 || throw(ArgumentError("iter must be in 0:99999 (5-digit zero-padded
filename contract), got $iter"))` and documented the hard bound in the docstring (negative
→ malformed `iter_000-3.jld2` name; > 99999 → `iter_100000.jld2` sorts BEFORE
`iter_99999.jld2`, silently resuming the wrong iteration). Added a testitem asserting
`ArgumentError` for `-3` and `100000`, and that the boundary values `0` and `99999` are
valid with resume picking `99999`.

### WR-04: Retry test's ill-conditioned fixture pins solver-version-specific numerical behavior

**Files modified:** `test/test_planning_retry.jl`
**Commit:** 0a587ff
**Applied fix:** Softened the hard precondition to the stable property
`@test termination_status(raw_model) != MOI.OPTIMAL`, and gated the entire escalation
branch (including the CR-01 overshoot regression) on
`raw_ts in TSODSO.RETRYABLE_STATUSES`. On a future Clarabel upgrade that reports e.g.
`MOI.ITERATION_LIMIT` (not in `RETRYABLE_STATUSES`), the test now degrades to an
informative `@info` skip naming the observed status instead of a spurious red. The
review's parenthetical question (should `ITERATION_LIMIT` join `RETRYABLE_STATUSES`?) was
deliberately NOT acted on — that is a semantic policy change beyond this finding's scope,
left for the phase owner.

## Additional Commit

- **e8f9911** `style(10): apply JuliaFormatter to review-fix files` — JuliaFormatter v2
  (project `.JuliaFormatter.toml`, CI-enforced) pass over the four files the fixes
  touched that needed reflow. No semantic changes; planning suite re-run green after.

---

_Fixed: 2026-07-22T19:55:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
