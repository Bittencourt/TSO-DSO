---
phase: 29-genuine-bilevel-tso-dso-variant
fixed_at: 2026-09-30T00:00:00Z
review_path: .planning/phases/29-genuine-bilevel-tso-dso-variant/29-REVIEW.md
iteration: 1
findings_in_scope: 9
fixed: 9
skipped: 0
status: all_fixed
---

# Phase 29: Code Review Fix Report

**Fixed at:** 2026-09-30
**Source review:** .planning/phases/29-genuine-bilevel-tso-dso-variant/29-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 9 (CR-01, WR-01..WR-08; Info findings out of scope)
- Fixed: 9
- Skipped: 0

**Production goldens unchanged:** corner fixture `y = x_inv = z = 0`, `total = 0`;
interior fixture `y* = x_inv* = 0.148`, `z* = 1.48`, `total* = -1.4726`. Measured
after every src change.

**Verification:** direct Julia scripts, `JULIA_LOAD_PATH="test:.:@stdlib"`, using a
scratch `@testmodule`/`@testitem` emulator. The emulator runs each body as top-level
code, the way TestItemRunner's `include_string` does, and it reproduced the soft-scope
trap described below. All testitems in `test/test_planning_bilevel.jl`,
`test/test_planning_certification_bilevel.jl` and
`test/test_planning_certification_bilevel_interior.jl` pass. `Pkg.test()` was NOT run;
the orchestrator certifies the full suite.

## Fixed Issues

### CR-01: The dual bound `m_ub` can be silently under-measured, and the post-solve check cannot detect a cut-off optimum

**Files modified:** `src/planning/bilevel_kkt.jl`
**Commit:** 5da5232
**Status:** fixed: requires human verification (logic/derivation change)
**Applied fix:**
- Replaced the solver-probe `_measure_follower_kkt_bounds` (with its silent skip of a
  failed probe) by a closed-form `_follower_kkt_dual_bound`. No solver is involved, so
  there is no probe left to fail silently. A non-finite bound raises an error.
- With `a = pi_tariff - c_op`, the bound is
  `safety * max(1e-6, max a⁺, max a⁻, corridor_cap*Σa⁺ - c_inv, c_inv)`.
  The docstring proves that for every `y_inv` and every follower-optimal primal, at
  least one KKT multiplier vector fits inside `[0, m_ub]`. That is the condition for
  the single-level MILP to be equivalent to the bilevel problem.
- This bound is tighter than the review's suggested formula (`mu_lo <= a⁻`,
  `rho_lo <= c_inv`, `rho_y <= (capΣa⁺ - c_inv)⁺`).
- Values: corner `m_ub = 10` (old probe: 10); interior `m_ub = 148` (old probe:
  9544.4; tight `rho_y(0) = 14.8`).
- Reworded the `solve_bilevel!` docstring: the at-bound check is NECESSARY, NOT
  SUFFICIENT (Pineda & Morales 2019), and the validity guarantee rests on `m_ub`.
- **Human check requested:** please review the four-case derivation in the
  `_follower_kkt_dual_bound` docstring.

### WR-01: The KKT system has no multiplier for the follower's `x_inv <= x_inv_max`

**Files modified:** `src/planning/bilevel_kkt.jl`, `test/test_planning_bilevel.jl`, `test/test_planning_certification_bilevel_interior.jl`
**Commit:** 78e5066
**Status:** fixed: requires human verification (KKT system change)
**Applied fix:**
- Added `rho_max ∈ [0, m_ub]`, `slack_max = x_inv_max - x_inv`, the SOS1 pair
  `[slack_max, rho_max]`, and `+ rho_max` in `statio_x`.
- Added a new `rho_max` field to `BilevelKKT`, included `rho_max` in the
  `solve_bilevel!` at-bound check and its return tuple, and extended the CR-01 bound
  derivation to cover it.
- New testitem: `x_inv_max = 0.1` with `y_inv` fixed at 1.0. This was `INFEASIBLE`
  before the fix. It now gives `x_inv = 0.1`, `z = 1.0`, `mu_cap = 0.5`, `rho_y = 0`
  and `rho_max = 4.8`, all hand-derived.
- Removed the "known modeling gap" note from the interior test header.

### WR-02: The formulation guard is a SOCP denylist

**Files modified:** `src/planning/bilevel_kkt.jl`, `test/test_planning_bilevel.jl`
**Commit:** 65b7310
**Applied fix:**
- The guard is now an allowlist: `pf isa LinDistFlow || throw(ArgumentError(...))`.
- The docstring is updated.
- The boundary-guard testitem gains `ACPowerFlow()` and `DCPowerFlow()` cases. Both
  now throw `ArgumentError`.

### WR-03: `m_ub` is an artefact of Clarabel's dual choice

**Files modified:** `test/test_planning_bilevel.jl`
**Commit:** f6b40bd (the code fix itself landed in CR-01, 5da5232)
**Applied fix:**
- New testitem pins the closed-form `m_ub` exactly (corner 10.0, interior 148.0), so
  any drift is visible.
- It also asserts all five complementarity products on the interior optimum are
  below 1e-6. With `m_ub = 148` the bridge leaves at most about 1.5e-7 of
  complementarity slack, down from about 1e-5.

### WR-04: The "fine grid resolves the optimum" assertion uses the salted result

**Files modified:** `test/test_planning_certification_bilevel_interior.jl`
**Commit:** 310f59b
**Applied fix:**
- Now asserts `abs(bf_fine_only.y - 0.148) <= grid_spacing`.
- The salted-vs-fine total check uses an analytic tolerance,
  `c_y*grid_spacing + 5e-5` (1.75e-4), instead of `1e-2`. Some fine-grid point lies
  on the slope-0.05 right branch within one spacing of the kink.
- Measured values: Clarabel's kink-point `z` is 1.47996, which is 3.7e-5 short of
  1.48, and the salted-vs-fine total difference is 6.3e-5.
- I did not use the review's suggested `10*grid_spacing`: it is 0.025, looser than the
  old 1e-2.

### WR-05: The "SOS1 branch-switch" and "z≡0 guard" assertions run on the oracle QP

**Files modified:** `test/test_planning_certification_bilevel_interior.jl`
**Commit:** 817734b
**Applied fix:**
- Added production-model checks: build the KKT-MILP, `fix(k.y_inv, y)`, then
  `solve_bilevel!`.
- At `y = 0.05`: `rho_y = 9.8`, `slack_y = 0`, `x_inv = 0.05`, `z = 0.5`.
- At `y = 1.0`: `rho_y = 0`, `slack_y > 0.5`, `x_inv = 0.148`, `z = 1.48`. This is
  also the production-level z≡0 guard.
- The existing oracle checks are kept.

### WR-06: The "too-tight bound" test passes through MILP infeasibility

**Files modified:** `test/test_planning_bilevel.jl`
**Commit:** 0f82794
**Applied fix:**
- Rewrote the testitem on the interior data, with `y_inv` fixed at 0.05 (which forces
  `rho_y = 9.8`) and `safety = 9.8/14.8` (so `m_ub = 9.8`).
- The model stays feasible, `rho_y` binds, and the test asserts an `ErrorException`
  whose message contains `"rho_y sits at (or within"`.
- Positive control: the same solve with `safety = 1` passes and reports
  `rho_y = 9.8`.
- Uses the `err = try ... catch e; e end` form (the `@testitem` try-scoping trap).

### WR-07: The oracles do not share production's semantics

**Files modified:** `src/planning/bilevel_kkt.jl`, `test/test_planning_certification_bilevel.jl`, `test/test_planning_certification_bilevel_interior.jl`
**Commit:** ec36025
**Applied fix:**
- Both brute-force oracles now treat `z > d_max`, or a bus-2 squared voltage
  `1 - 2r*z` outside `[0.95², 1.05²]`, as leader-infeasible (`continue`), with
  `d = z`. Previously such a response counted as feasible-but-curtailed.
- Their docstrings state the follower-tie caveat and why each fixture's follower
  response is unique.
- The `build_bilevel_kkt` docstring now states the optimistic bilevel semantics and
  the coupling-constraint interpretation.
- The interior BilevelJuMP oracle and brute force take a `dmax` keyword.
- New testitem where `d_max = 1.0` binds the follower's response. Hand-derived:
  `y* = x_inv* = 0.1`, `z* = d* = 1.0`, `total* = -0.995`, `rho_y = 4.8`.
  Production matches to 1e-6, BilevelJuMP to ~1e-8, and brute force within one grid
  spacing.

### WR-08: The multi-period path (`T > 1`) has no test

**Files modified:** `test/test_planning_certification_bilevel_interior.jl`
**Commit:** 07b3822
**Applied fix:**
- New T=2 testitem with distinct tariffs `pi_tariff = [2.0, 1.5]`; both periods
  deliver. The three follower branches are hand-derived.
- Production optimum: `y* = 0.148`, `z* = [1.48, 1.0]`, `total* = -2.9726`,
  `mu_cap = [0.02, 0]`, `m_ub = 248`.
- Fixed-y production checks pin `rho_y` on each branch: 14.8 at `y = 0.05`, 2.8 at
  `y = 0.12`, 0 at `y = 1.0`.
- Cross-checked against a T=2 BilevelJuMP oracle (atol 1e-5) and a brute-force grid.
- Mutation check: replacing `sum(mu_cap[t] ...)` with `mu_cap[1]` made 8 assertions
  fail. The mutation was reverted.
- The brute-force loop is wrapped in a function. `@testitem` bodies run as top-level
  code, where a for-loop that updates an outer binding hits Julia's soft-scope rule
  and raises `UndefVarError`. A first draft hit exactly this error under the faithful
  emulator.

---

_Fixed: 2026-09-30_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
