---
phase: 11-single-distributor-stackelberg-benders-certified
reviewed: 2026-07-22T23:03:52Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - src/TSODSO.jl
  - src/planning/benders.jl
  - src/planning/follower.jl
  - src/planning/master.jl
  - test/Project.toml
  - test/test_planning_benders.jl
  - test/test_planning_certification.jl
  - test/test_planning_follower.jl
  - test/test_planning_master.jl
findings:
  critical: 0
  warning: 0
  info: 7
  total: 7
status: clean
---

# Phase 11: Code Review Report (iteration 3 — fix verification)

**Reviewed:** 2026-07-22T23:03:52Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** clean

## Summary

Re-review of the Phase-11 Stackelberg–Benders implementation after the iteration-2 fix
pass (commits `873b838..59c3cbc`, addressing CR-01 and WR-01..WR-05 from
`11-REVIEW.iter2.md`). All six fixes were verified sound by tracing the code, the cut
algebra, and the fix-commit diffs; no new Critical or Warning defects were introduced.
Five prior Info findings remain valid and are carried forward unchanged; two new Info
observations were added. **No Critical or Warning findings remain.**

### Fix verification detail

**CR-01 (incumbent tracking) — VERIFIED SOUND**, including the feasibility-cut
interaction specifically flagged for scrutiny:

- `benders.jl:135-141` initializes `UB = Inf`, `y_best = NaN`, `z_best = fill(NaN, T)`;
  `benders.jl:178-183` updates the incumbent only on strict improvement
  (`cost_k < UB`), storing `y_best = lb_res.y` and a defensive `copy(lb_res.z)` (no
  aliasing of the master's re-solved value vector).
- *Feasibility-cut interaction is correct*: the infeasible branch
  (`benders.jl:157-165`) appends the Farkas cut, checkpoints, and `continue`s **before**
  any of `UB`/`y_best`/`z_best`/`gap` is touched — a feasibility iteration can neither
  corrupt the incumbent nor trigger convergence. The `(; ... gap = NaN ...)` in the
  feasibility checkpoint payload is a NamedTuple field, not a rebinding of the local
  `gap`, so the loop's gap state is also untouched.
- *A NaN incumbent can never be returned*: convergence requires `gap <= tol`, and while
  `UB == Inf` the gap is `(Inf - LB)/Inf = NaN`, for which `NaN <= tol` is `false` — the
  return path is reachable only after at least one optimality iteration has set the
  incumbent.
- *The gap certificate is valid with a stale-`UB`/fresh-`LB` pairing*: `LB` is
  monotonically nondecreasing (cuts are only ever appended), so
  `LB_k <= optimum <= UB_incumbent` holds at every iteration and
  `gap <= tol` certifies the incumbent within `tol·max(1,|UB|)` of the optimum —
  exactly the docstring's claim, now true of the returned point.
- Regression coverage: `test_planning_benders.jl:74-83` re-solves both subproblems at
  the returned `z` and asserts the true-cost-equals-`UB` identity with `atol = 1e-6`,
  which the pre-fix last-iterate return would violate by an amount not bounded by `tol`.

**WR-01 (follower-first ordering) — VERIFIED**: `solve_follower!` now runs at
`benders.jl:155`, and `solve_planning_oracle!` (`benders.jl:168`) is reached only on
the feasible branch; the infeasible branch `continue`s at line 164 without ever
touching the oracle. No wasted oracle solve, and the oracle's exactness/complementarity
gates can no longer crash the loop at an undeliverable trial `z_k`.

**WR-02 (exact compat pins) — VERIFIED**: `test/Project.toml:29-32` now uses equality
specifiers (`BilevelJuMP = "= 0.6.3"`, `HiGHS = "= 1.24.1"`, `Ipopt = "= 1.15.0"`), and
the comment (lines 16-28) correctly explains why the `= X.Y.Z` form is required. See
IN-07 for the (informational) scope limit of these pins.

**WR-03 (finiteness guards) — VERIFIED**: both `add_optimality_cut!`
(`master.jl:163-169`) and `add_feasibility_cut!` (`master.jl:221-226`) reject
non-finite `cost_k`/`grad_k`/`v_k`/`u_k`/`z_k` with `ArgumentError` **before** either
`@constraint` or the `push!` to `master.cuts`, so a rejected cut leaves the persistent
master fully untouched (asserted by the new unit test at
`test_planning_master.jl:109-127`). `solve_follower!` additionally enforces the
documented `isfinite` certificate guarantee in production (`follower.jl:201-204`)
before the certificate ever reaches the Benders loop.

**WR-04 (feasibility-branch end-to-end test) — VERIFIED**: the new test
(`test_planning_benders.jl:93-141`) shrinks `x_inv_max` to 0.25 (deliverable cap 0.5).
Traced through the fixture: the zero-cut master's first trial is `z = 0` (feasible),
and the post-first-cuts master proposes `z = 2.5 > 0.5`, so the production Farkas
branch is genuinely reached — the test asserts a `:feasibility` entry in
`result.master.cuts`, convergence to the correct boundary optimum
`y* = z* = 0.5` (total cost `0.5z² - 0.7z` is decreasing on `[0, 0.7]`, so the
deliverable cap binds), and the `checkpoint_files == result.iters` invariant across
mixed feasibility/optimality iterations (the exact T-11-06 interplay flagged in the
prior review).

**WR-05 (presolve/Farkas fragility) — RESOLVED via the documented-comment option** the
prior review offered: `follower.jl:182-194` now records that the certificate behavior
is verified against the exact-pinned HiGHS 1.24.1 and names the concrete fallback
(`set_optimizer_attribute(model, "presolve", "off")` in `build_follower`) to apply if a
future HiGHS lands in the loud `else` branch. Residual risk is fail-loud with a
documented recovery; see IN-07.

Cross-module contracts re-checked and consistent: `solve_planning_oracle!` returns
`(; cost, π, π_s, dadp, ctx)` matching benders.jl's `:op`-cut consumption
(`cost_k = -oracle_res.cost`, `grad_k = oracle_res.π`); `solve_with_retry!` accepts the
`dual = true` keyword `solve_master!` passes, and its non-Clarabel-backend attribute
rejection is converted to a loud diagnostic (relevant since the master is a HiGHS LP);
`checkpoint_iteration!`'s `(state, iter; dir)` signature matches both call sites;
include order in `TSODSO.jl` (`follower.jl` → `master.jl` → `benders.jl`) satisfies
benders.jl's call-time dependencies; all symbols the tests consume are exported by
their seam files.

## Info

### IN-01: Exhaustion error reports a stale `gap` when the final iterations took the feasibility branch (carried forward)

**File:** `src/planning/benders.jl:210-213`
**Issue:** The feasibility branch `continue`s before the local `gap` is recomputed, so
"last gap=$gap" in the max-iter `error(...)` can name a gap from an arbitrarily older
optimality iteration (or `NaN` if no optimality iteration ever ran).
**Fix:** Track the iteration index at which `gap` was last computed and include it in
the message, or report `UB`/`LB` alongside.

### IN-02: `tol` is the one unchecked numeric input in the boundary guards (carried forward)

**File:** `src/planning/benders.jl:121-126`
**Issue:** `T`, `max_iter`, and `length(λ₀)` are guarded, but a `NaN` or negative `tol`
silently guarantees exhaustion (every `gap <= tol` comparison is false for NaN) —
fail-loud is preserved but the diagnosis ("exhausted N iterations") is misleading.
**Fix:** `isfinite(tol) && tol > 0 || throw(ArgumentError(...))` alongside the other guards.

### IN-03: `max_iter` above 99999 throws deep in the loop instead of at the boundary guards (carried forward)

**File:** `src/planning/benders.jl:121-126`; `src/planning/checkpoint.jl:49-53`
**Issue:** `checkpoint_iteration!` enforces `iter ∈ 0:99999` (5-digit filename
contract), so `max_iter = 200_000` would run 99,999 iterations before dying inside
`checkpoint_iteration!` — violating this file's own "fail here, not deep in the loop"
guard discipline.
**Fix:** Add `max_iter <= 99_999 || throw(ArgumentError(...))` to the guard block,
citing the checkpoint filename contract.

### IN-04: `solve_master!` requires duals it never reads (carried forward)

**File:** `src/planning/master.jl:261`
**Issue:** `solve_with_retry!(master.model; ..., dual = true)` gates the master solve
on dual availability, but `solve_master!` reads only primal values and the objective.
**Fix:** Pass `dual = false` (or document why dual-status strictness is wanted on the
master too).

### IN-05: Certification test pins a HiGHS-version-specific failure status (`MOI.OTHER_ERROR`) (carried forward)

**File:** `test/test_planning_certification.jl:166-167`
**Issue:** The BigMMode negative regression asserts the exact status the current HiGHS
build uses to report "Cannot solve MIQP". A HiGHS upgrade that adds MIQP support or
changes the status code fails this test. Per the file's DEVIATION note this is an
intentional tripwire; with WR-02's exact pin the trigger is now gated behind a
deliberate pin bump, further reducing surprise.
**Fix:** None required; optionally widen to
`termination_status(r_bigm.model) != MOI.OPTIMAL` if the tripwire intent is "never
silently certifies" rather than "pins this exact status".

### IN-06: Farkas certificate is checked for finiteness but not positivity — a degenerate `v <= 0` certificate would cycle silently until max-iter exhaustion (new)

**File:** `src/planning/follower.jl:195-205`; `src/planning/master.jl:228-231`
**Issue:** The feasibility cut `v_k + Σ u_k(z - z_k) <= 0` only excludes the trial
point `z_k` when `v_k > 0` (at `z = z_k` it reduces to `v_k <= 0`). A genuine
certificate has `v > 0` by definition, but neither `solve_follower!`'s new WR-03
enforcement nor `add_feasibility_cut!`'s guards check the sign: a numerically
degenerate `v <= 0` certificate would append a vacuous cut, let the master re-propose
the same `z_k` forever, and surface only as the max-iter exhaustion error with a
stale/NaN gap (compounding IN-01). Fail-loud is preserved but the diagnosis would be
poor. Low likelihood under the pinned HiGHS 1.24.1 (both infeasible regimes were
verified in the prior review to return `v > 0`).
**Fix:** Extend the `follower.jl:201` guard to
`isfinite(v) && v > 0 && all(isfinite, u) || error(...)` (with a comment that a
non-positive `v` yields a cut that fails to exclude `z_k`).

### IN-07: Exact compat pins govern only the test environment — the package environment can still float HiGHS within 1.x (new)

**File:** `test/Project.toml:29-32`; `Project.toml:34-35`; `src/planning/follower.jl:186-189`
**Issue:** The WR-02/WR-05 fixes pin HiGHS/Ipopt exactly in `test/Project.toml`, and
`follower.jl`'s comment says the Farkas behavior is verified "against the EXACT-pinned
HiGHS 1.24.1". But the root `Project.toml` compat entries remain caret specifiers
(`HiGHS = "1.24.1"` → any `1.x >= 1.24.1`), so any non-test consumer of
`solve_follower!` (e.g. a DrWatson experiment script instantiating the package
environment after a `Pkg.update()`) can run on a floated HiGHS where the Farkas-ray
availability is unverified. The failure mode is the loud `else`-branch error with the
documented presolve-off fallback recipe, so this is informational, not a defect — and
the root `Manifest.toml` pins the currently resolved build for reproducible runs. Note
also the test/Project.toml comment's phrase "pinned to match the root Project.toml's
own compat entries" is imprecise (root uses caret, test uses equality; the version
numbers match, the specifier semantics do not).
**Fix:** None required; optionally tighten the root compat to `HiGHS = "= 1.24.1"` for
symmetry, or soften the follower.jl/test-Project.toml comments to "exact-pinned in the
test environment; Manifest-pinned elsewhere".

---

_Reviewed: 2026-07-22T23:03:52Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
