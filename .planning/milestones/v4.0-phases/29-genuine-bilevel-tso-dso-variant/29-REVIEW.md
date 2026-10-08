---
phase: 29-genuine-bilevel-tso-dso-variant
reviewed: 2026-10-01T01:31:44Z
depth: standard
iteration: 3
files_reviewed: 7
files_reviewed_list:
  - src/planning/bilevel_kkt.jl
  - src/TSODSO.jl
  - src/planning/benders.jl
  - test/test_planning_bilevel.jl
  - test/fixtures_planning.jl
  - test/test_planning_certification_bilevel.jl
  - test/test_planning_certification_bilevel_interior.jl
findings:
  critical: 0
  warning: 1
  info: 4
  total: 5
status: issues_found
---

# Phase 29: Code Review Report (iteration 3)

**Reviewed:** 2026-10-01T01:31:44Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

This pass re-reviews the code after 81cc227 (CR-01: post-solve certificate LP), a8f4411 (WR-01: `safety >= 1`) and 23a72b1 (WR-02: three-stage lexicographic multipliers). The iteration-2 report is backed up as `29-REVIEW.iter2.md`. Resolved items are not raised again.

**Iteration-2 CR-01, WR-01 and WR-02 are fixed.** No critical issue remains. The results of the priority checks follow.

1. **The certificate LP characterizes valid KKT multipliers correctly.** `_recover_kkt_certificate` (`bilevel_kkt.jl:598-609`) uses exactly the MILP's `statio_x`/`statio_z` at the fixed primal. It zeroes every multiplier whose primal slack is above `act_tol`, and it puts no other restriction on the multipliers. So the LP is feasible exactly when the primal is an (act_tol-)KKT point of the follower, and its min-max objective tests "some certificate fits the limits", not "HiGHS's vertex fits".
   - **The 1e-6 threshold can err in two directions.**
     - *False reject:* an active slack is reported above 1e-6. The multiplier is then fixed to 0, the LP becomes infeasible, and the code raises a hard error. HiGHS's integrality tolerance of 1e-9 times the SOS1 big-M would have to exceed 1e-6 for this to happen.
     - *False accept:* a slack in (0, 1e-6] leaves its multiplier free. The worst effect is a complementarity product of about `m_ub·1e-6`, which is within tolerance.
   - **Neither direction showed up in testing.** Three scratch sweeps found no misclassification:
     - `hard.jl`: 459 optimal solves, T in 1..4. About 40% had `q_op = 0` (bang-bang), about 20% had `a[t] = 0` exactly, `c_inv = 0` and `c_y = 0` were included, and `y` was fixed at `0`, at `x_inv_max` or at random. 0 errors.
     - `scale.jl`: magnitudes scaled up to the per-unit band ceiling. 0 errors.
     - `bigM.jl`: `x_inv_max` up to 1e5, which inflates the bridge big-M on `slack_cap`. 0 errors, and no slack fell in (1e-7, 1e-3).
   - The per-unit guard in `Feeder` (`smax < 100`) bounds the network magnitudes, so the absolute threshold is adequate in practice.
2. **The bound-exception rule is sound.** `_lim` (`:579`) only admits certificates `<= m_ub_proven + atol` when the box is at least `m_ub_proven`. The closed-form proof (re-verified in iteration 2) guarantees such a certificate at every follower optimum for every `y_inv`. So a box `>= m_ub_proven` cannot cut off the optimum, and the exception masks nothing.
   - The consequence is that with untouched bounds and any `safety >= 1`, the check is mathematically unreachable. It can only fire when a caller tightens a bound below `m_ub_proven`. The docstrings say this honestly ("necessary, not sufficient", "catches a bound ... tightened by a caller").
3. **The lexicographic minimization is well defined and unique.** I checked the docstring's case analysis by hand. Stage 1 reduces to `min Σ mu_cap` subject to `mu_cap >= a⁺`, which gives `mu_cap = a⁺` componentwise. Stage 2 fixes `rho_y - rho_lo` or `rho_y + rho_max` at its positive or negative part. Stage 3 resolves the only remaining split.
   - **Empirical check:** `hard.jl` min/max-probes every multiplier on the lexicographic optimal face. The worst spread was 5.1e-8 over 459 solves, including 87 `y = x_inv = x_inv_max` corners and 204 `x_inv = 0` cases.
   - **The `rho_y = 0` / `rho_max = total` convention at the corner is defensible.** It reports the right-derivative of the follower's value in `y`. That is the same one-sided convention the `x = y = 0` case uses (`rho_y = K⁺` is the right-derivative there too), so the two degenerate cases are consistent with each other.
4. **The new tests are falsifiable.**
   - **CR-01 regression testitem:** its 6 cases threw under the pre-fix code.
   - **WR-02 testitem:** it pins hand-derived canonical values. Against the raw-vertex code the corner fixture returns `mu_cap = 0.5`/`mu_lo = 0.8`, and the corner case tells stage 3 apart from a plain `min Σ`.
   - **WR-01 stress test:** it reaches the at-bound branch through `set_upper_bound` with a unique `rho_y = 9.8`. The new `safety = 0.5` guard assertion is genuine.

**One new defect** (WR-01 below): moving the returned multipliers onto the certificate LP introduced a silent-wrong-value regression. The LP reads cached copies of the follower data instead of the model.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: The certificate LP uses cached follower data, so modifying the built model in place silently returns wrong multipliers (regression from 23a72b1)

**File:** `src/planning/bilevel_kkt.jl:476-481` (cached fields), `:598-609` (certificate LP), `:769-773` (returned values)

**Issue:** `_recover_kkt_certificate` rebuilds the follower's stationarity from the `c_inv`, `corridor_cap`, `margin`, `q_op` and `x_inv_max` copies stored on `BilevelKKT` at build time. It does not read the coefficients of `kkt.model[:statio_x]`/`kkt.model[:statio_z]`.

The project's stated idiom is "build once; mutate via `set_normalized_rhs` / `set_objective_coefficient`; re-solve" (CLAUDE.md §6). A researcher who sweeps the follower's data in place on the registered constraints therefore gets a MILP solved for the new data and multipliers certified against the old data. Before 23a72b1 the returned multipliers were the MILP's own values, which were consistent with the mutated model. They are now silently wrong.

Reproduced with `scratchpad/stale.jl` on the interior fixture:

```
set_normalized_rhs(k.model[:statio_x], -1.0)   # c_inv 0.2 -> 1.0
solve_bilevel!(k)  ->  y = 0.14 (correct for c_inv = 1.0), rho_y = 0.8 (WRONG; true rho_y = 10*0.1 - 1.0 = 0)
```

The code raises no error. Stationarity under the cached `c_inv = 0.2` happens to be satisfiable. Other mutations, such as changing a `statio_z` coefficient while every multiplier of that t is fixed, would instead make the certificate LP infeasible. That raises the misleading "MILP returned a primal with no valid follower KKT certificate" error on a correct solve.

**Fix:** Read the data from the model at solve time so the certificate always matches what HiGHS solved:

```julia
sx = kkt.model[:statio_x]; sz = kkt.model[:statio_z]
c_inv_now = -normalized_rhs(sx)                                  # c_inv + ... == 0
cap_now   = -normalized_coefficient(sx, kkt.mu_cap[1])           # coefficient of mu_cap[t]
q_now     = [normalized_coefficient(sz[t], kkt.z[t]) for t in 1:T]
margin_now = [normalized_rhs(sz[t]) for t in 1:T]                # (c_op - pi) + ... == 0  =>  rhs = pi - c_op
```

Use these values in place of the cached fields. At minimum, assert at the top of `_recover_kkt_certificate` that the cached fields still equal the model's coefficients, and error loudly if they do not. Also document on `BilevelKKT` that the model must not be mutated except through `fix(y_inv, ·)`.

## Info

### IN-01: Fixing a multiplier variable bypasses the at-bound check that is meant to catch hand-tightened bounds

**File:** `src/planning/bilevel_kkt.jl:565`

**Issue:** `_ub(v) = has_upper_bound(v) ? upper_bound(v) : Inf`. `fix(v, c; force = true)` deletes the variable's bounds, so a fixed multiplier is reported with `ub = Inf`. The certificate LP then leaves it unrestricted.

On the WR-01 stress setup, `set_upper_bound(rho_y, 9.8)` raises the at-bound error, but `fix(rho_y, 9.8; force = true)` passes silently (`scratchpad/stale.jl`). The docstring (`:712-714`) presents the check as the guard against caller-tightened bounds.

**Fix:** `_ub(v) = is_fixed(v) ? fix_value(v) : has_upper_bound(v) ? upper_bound(v) : Inf`. A fixed multiplier is the tightest possible bound, so it should be checked like one.

### IN-02 (carried from iteration-2 IN-01): `GAP_FLOOR_INTERIOR` derivation comment contradicts its value

**File:** `test/test_planning_certification_bilevel_interior.jl:297-304`

**Issue:** The comment derives the floor as "10x ... `mip_feasibility_tolerance=1e-9`", which is 1e-8, but the constants are `1e-6`. This is still unresolved; it was out of the fixer's scope.

**Fix:** Set the constants to `1e-8`, or state the real basis of 1e-6.

### IN-03 (carried from iteration-2 IN-02): The T=2 brute force omits the voltage-band filter

**File:** `test/test_planning_certification_bilevel_interior.jl:687-698`

**Issue:** `brute_force_T2` filters only `z <= d_max`. The other oracles also filter the bus-2 voltage band. The result is unaffected on this fixture, but the oracle is not equivalent to production semantics.

**Fix:** Add `all(0.95^2 .<= 1 .- 2e-3 .* zs .<= 1.05^2) || continue`.

### IN-04 (carried from iteration-2 IN-03): Stale plan-time language in the `build_bilevel_kkt` docstring

**File:** `src/planning/bilevel_kkt.jl:275-279`

**Issue:** "MEASURES, does not assume ... extended ... ONLY if measurement (Task 2's fixture) shows it is insufficient" describes a plan task, not behaviour.

**Fix:** Replace it with the measured outcome: the shared `select_optimizer(MILP())` defaults are used unchanged and solve every fixture to `OPTIMAL`.

_Iteration-1 info items IN-01..IN-05 (see `29-REVIEW.iter1.md`) were not re-checked and are not repeated._

---

_Reviewed: 2026-10-01T01:31:44Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
