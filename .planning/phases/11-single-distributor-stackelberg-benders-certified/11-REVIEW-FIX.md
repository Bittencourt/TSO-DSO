---
phase: 11-single-distributor-stackelberg-benders-certified
fixed_at: 2026-07-22T00:00:00Z
review_path: .planning/phases/11-single-distributor-stackelberg-benders-certified/11-REVIEW.md
iteration: 1
findings_in_scope: 6
fixed: 6
skipped: 0
status: all_fixed
---

# Phase 11: Code Review Fix Report

**Fixed at:** 2026-07-22
**Source review:** .planning/phases/11-single-distributor-stackelberg-benders-certified/11-REVIEW.md
**Iteration:** 1

**Summary:**

- Findings in scope: 6 (fix_scope = critical_warning: 1 Critical + 5 Warnings; 5 Info findings out of scope)
- Fixed: 6
- Skipped: 0

**Verification:** the fast `:planning`-tagged TestItemRunner filter was run green after each
fix (140 passing items after the last code fix, up from 127 pre-fix — 8 new WR-03
assertions + 5 new WR-04 assertions). The full suite (`Pkg.test()`) was run once at the
end: **4039 pass, 4 broken (pre-existing `@test_broken` markers), 0 failures, exit 0**
(~14 min). All touched `.jl` files were formatted with the project's JuliaFormatter v2
config before each commit.

## Fixed Issues

### CR-01: `solve_stackelberg!` returns the last master iterate, not the incumbent that achieved `UB`

**Files modified:** `src/planning/benders.jl`, `test/test_planning_benders.jl`
**Commit:** 2ab7907
**Applied fix:** Added incumbent tracking (`y_best`/`z_best`, initialized `NaN`/`fill(NaN, T)`).
The `UB = min(UB, ...)` running minimum was replaced with an explicit
`cost_k = master.c_y * lb_res.y + follower_res.cost - oracle_res.cost` and a
`cost_k < UB` incumbent update that stores `y_best = lb_res.y`, `z_best = copy(lb_res.z)`.
The converged return now yields `y = y_best, z = z_best` — the point actually certified by
`UB` and the `gap ≤ tol` guarantee. Docstring (Algorithm step 3 and Returns section)
updated to match. Regression test added per the fix guidance ("assert returned cost == UB
within tol"): the end-to-end convergence test now re-solves the follower and oracle at the
returned `z` and asserts `c_y*y + φ_x(z) - W(z) ≈ result.UB` (atol 1e-6) — returning an
uncertified last iterate breaks this identity by an amount not bounded by `tol`.

### WR-01: Oracle solved before the follower feasibility check

**Files modified:** `src/planning/benders.jl`
**Commit:** 873b838
**Applied fix:** Reordered the loop body — `solve_follower!` now runs first; the
feasibility-cut/`continue` branch executes before any oracle call, and
`solve_planning_oracle!` is only reached for follower-deliverable `z_k`. This routes
infeasible extreme trials (master box allows `z` up to `y_max = 8.0` vs. deliverable
`corridor_cap·x_inv_max = 4.0` on the fixture) to the feasibility cut instead of crashing
in the oracle's exactness/complementarity gates, and eliminates the wasted oracle solve
per infeasible iteration. Docstring Algorithm step 3 updated. The WR-04 test (commit
86668ef) exercises exactly this ordering end-to-end: its undeliverable trials reach the
feasibility branch without ever touching the oracle.

### WR-02: `test/Project.toml` caret compat ranges contradict the file's own "EXACT version" comment

**Files modified:** `test/Project.toml`, `test/Manifest.toml`
**Commit:** 56b1497
**Applied fix:** Switched all three compat entries to equality specifiers
(`BilevelJuMP = "= 0.6.3"`, `HiGHS = "= 1.24.1"`, `Ipopt = "= 1.15.0"`) — exact pinning
per the file's stated supply-chain-integrity intent — and extended the comment to explain
why the `= X.Y.Z` syntax is required (bare `X.Y.Z` is a caret specifier). Re-resolved the
test environment: `Pkg.resolve()` reported no package changes (the committed Manifest was
already at exactly those versions); only `test/Manifest.toml`'s `project_hash` updated,
committed alongside.

### WR-03: Cut appenders validate length but not finiteness

**Files modified:** `src/planning/master.jl`, `src/planning/follower.jl`, `test/test_planning_master.jl`
**Commit:** a71b266
**Applied fix:** Both halves of the review's suggested fix applied. In
`add_optimality_cut!`: `isfinite(cost_k)`, `all(isfinite, grad_k)`, and
`all(isfinite, z_k)` guards, each a loud `ArgumentError`, placed after the length guards
and before `@constraint` (a NaN/Inf row on the build-once master is unremovable). In
`add_feasibility_cut!`: analogous `v_k`/`u_k`/`z_k` guards. In `solve_follower!`'s
infeasible branch: the docstring's "both `isfinite`" certificate promise is now enforced
in production — a non-finite `(v, u)` raises loudly before it can reach the master.
Docstrings updated. New `@testitem` in `test_planning_master.jl` covers all six
non-finite rejection paths and asserts the master's constraint count and cut log are
untouched after the rejected calls.

### WR-04: Production feasibility-cut branch never exercised end-to-end

**Files modified:** `test/test_planning_benders.jl`
**Commit:** 86668ef
**Applied fix:** Added a `@testitem` running `solve_stackelberg!` on a fixture variant
with the follower's deliverable capacity shrunk (`x_inv_max = 0.25`, so
`corridor_cap·x_inv_max = 0.5`) below both the unconstrained optimum `z* = 0.7` and the
master's early cut-driven trials — forcing at least one follower-infeasible trial. Asserts:
(1) at least one `result.master.cuts` entry has `kind == :feasibility` (the production
branch actually ran), (2) the run still converges (`gap ≤ 1e-6`) to the boundary optimum
`y* = z* = 0.5` (analytic: `total(z) = 0.5z² − 0.7z` is decreasing on `[0, 0.7]`, so the
cap binds), and (3) the checkpoint-count-equals-`result.iters` invariant holds across
feasibility iterations (T-11-06 interplay). Verified empirically green before commit.

### WR-05: Farkas-ray availability under `presolve => "on"` is a solver-version-dependent behavior

**Files modified:** `src/planning/follower.jl`
**Commit:** 59c3cbc
**Applied fix:** Documentation-only change, per the review's "no behavioral change
needed" note. Added a `WR-05 SOLVER-VERSION NOTE` comment on `solve_follower!`'s
certificate branch stating: the behavior is verified against the exact-pinned HiGHS
1.24.1 (cross-referencing WR-02's `= 1.24.1` pin), the failure mode on an upgrade is the
loud `else`-branch error, and the documented fallback (11-RESEARCH.md Pitfall F1) is the
follower-model-local `set_optimizer_attribute(model, "presolve", "off")` in
`build_follower`.

## Skipped Issues

None — all in-scope findings were fixed. (IN-01 through IN-05 were out of scope under
`fix_scope = critical_warning`.)

---

_Fixed: 2026-07-22_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
