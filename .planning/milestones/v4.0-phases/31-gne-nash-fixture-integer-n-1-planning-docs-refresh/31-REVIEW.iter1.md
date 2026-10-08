---
phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh
reviewed: 2026-10-02T12:10:00Z
depth: standard
files_reviewed: 15
files_reviewed_list:
  - src/planning/benders.jl
  - src/planning/coupling.jl
  - src/planning/master.jl
  - src/planning/master_integer.jl
  - src/planning/nash.jl
  - src/planning/bilevel_kkt.jl
  - test/test_planning_alpha_bounds_stackelberg.jl
  - test/test_planning_benders_integer.jl
  - test/test_planning_master.jl
  - test/test_planning_master_integer.jl
  - test/test_planning_nash.jl
  - test/test_planning_nash_integer.jl
  - docs/writeups/stackelberg_vs_psr_n1n2.typ
  - docs/writeups/modelo_stackelberg_dso_unico.typ
  - docs/src/api.md
findings:
  critical: 2
  warning: 6
  info: 7
  total: 15
status: issues_found
fix_status: not_started — autonomous mode stopped by user after this review; findings left open
---

# Phase 31: Code Review Report

**Reviewed:** 2026-10-02 · **Depth:** standard (scoped to `git diff 36e3c1e`) · **Status:** issues_found

> Orchestrator note: the reviewer returned this report inline; it was saved verbatim by the
> orchestrator. No fix iteration was run — the user stopped autonomous mode after this review.
> Reproduction script for CR-01: `/tmp/claude-1000/-home-pedro-programming-TSO-DSO/981f784b-8b89-4fdd-b64d-2c7c39f9b271/scratchpad/review_cycle_damped.jl`
> (scratch, not committed; BILEV-07 test fixture + `ω=0.5`, ~107 s via `julia --project=.`).

## Summary

Verified sound: the WR-03 Option A clamp (`min(requested, d.bound)` gives installed ≤ optimum − margin with
margin ≥ 10·|gap|, so cost_k ≥ α − tol_k with lb_slack = 0 — the WR-05 runtime-floor proof holds, and
production reads `lower_bound(master.α_op)` = the clamped value, benders.jl:1513); WR-01
ALMOST_INFEASIBLE is now confirmed via feas_oracle or rethrown; the LL-cut D(b) docstring is now correct
(D = 1−k); the analytic GNE set {(x1, 0.7−x1)} is correct (each player sits at z = 0.7 since
6 − p = λ₀ + c_y + c_inv/cap + c_op gives p = 0.7) and the probe's `x_inv_spread > 0.5` would fail if the
continuum collapsed; the λ₀·z term is consistent across the VE objective, `cost_per_distributor` and the
Benders UB. Two blockers: integer cycle detection raises false "CYCLED" errors (reproduced), and on the
shipped fixture "VE selection" is mathematically empty — every GNE on the continuum is a VE.

## Critical Issues

### CR-01: Integer cycle detection fires on runs that are still converging (reproduced)

**File:** `src/planning/nash.jl:736-754` (key built at 633-641)

**Issue:** The cycle key is only the joint binary vector `b` (from `result_i.y`), but the game state also
includes the continuous `z` and `x_inv`. Binaries routinely settle before those do, so any run that needs
three or more sweeps with stable `b` is reported as a cycle. Phase 24's own inner stall guard
(`apply_integer_cuts!`, master_integer.jl:833-838) already learned this: "a revisit with a materially
different z is expected cutting-plane refinement progress, never a stall".

**Reproduced:** the BILEV-07 test fixture with `integer=(;K=4), ω=0.5` throws
`integer diagonalization CYCLED — the joint binary state [1,0,0,0,1,0,0,0] recurred at sweep 2 (first seen at sweep 1)`
after 107 s. Damping halves the residual each sweep while `b` stays fixed. Undamped runs that need ≥3
sweeps fail the same way. The only cycle test ("standalone replication") checks Julia `Dict` key equality
and never calls `run_nash!`, so it cannot catch this.

**Fix:** Key on the full committed state, and only flag a cycle when the whole state recurs, e.g.
`state_k = (joint_b, round.(z_prev ./ tol_outer), round.(x_inv_prev ./ tol_outer))` checked only when the
sweep has not converged; or require `b` to recur with a non-decreasing residual (the Phase-24
`isapprox(z)` pattern). Add a live `run_nash!(...; integer, ω=0.5)` test that must converge.

### CR-02: The VE is not unique on the interior-cap fixture, but docs and tests claim it is selected and certified

**Files:** `src/planning/nash.jl:285-292, 1037-1049, 1079-1083`; `docs/writeups/stackelberg_vs_psr_n1n2.typ:229-231`; `test/test_planning_nash.jl` (VE testitem, Tests 1-3)

**Issue:** With c_inv = [1, 1], the joint objective and every constraint depend on `x_inv` only through
x1 + x2, so the joint problem's optimal face is the entire split segment. The KKT conditions hold at every
GNE point: interior x_i gives c_inv = cap·π_i, so π_i = 0.5; at the endpoint x1 = 0, z-stationarity gives
π_1 = W′(0.7) − λ₀ − c_y − c_op = 1.0 − 0.5 = 0.5. So every point of the continuum has identical
multipliers and the VE set equals the GNE set. The writeup's "Dentro do continuum de GNEs acima, o VE é o
GNE cujo multiplicador … é IDÊNTICO" is false here; the returned point is solver-dependent (31-FINDINGS:
Clarabel IPM lands on the analytic center (0.35, 0.35)). The tests cannot tell a VE from any other GNE:
`sum(x_inv) ≈ 0.7` holds at every GNE, `isfinite(π)` is trivially true, and the no-profitable-deviation
check is a GNE property. Rosen's uniqueness argument needs diagonal strict concavity, which this fixture
(linear in x) lacks.

**Fix:** Docs — state that the VE is non-unique on this fixture and that `solve_variational_equilibrium`
returns a solver-dependent point of the VE face. Selection test — use asymmetric c_inv or a strictly convex
investment cost so the VE is unique; assert the hand-derived split and compare `π_capacity` against each
player's shared-row dual from a `run_nash!` best response.

## Warnings

### WR-01: The new no-Farkas-ray infeasible branch is a dead end for every caller that needs a cut

**Files:** `src/planning/coupling.jl:434-444`; `src/planning/benders.jl:493-497, 584-585, 1298-1301`

`(; feasible=false, v=NaN, u=NaN)` is handled correctly only by the T==1 ternary `Qfun`. At T>1,
`_corner_recourse_joint.evaluate` returns `feas_cut = (; v=NaN, u=NaN…)`, which is `!== nothing`, so the
NaN cut is pushed into the small LP and JuMP throws an opaque `Invalid coefficient NaN on variable …`
(verified in scratch `nan.jl`). In the outer loop, `add_feasibility_cut!` throws `ArgumentError` and
aborts the whole Nash run although the trial is merely infeasible. The coupling docstring frames this as
"fails loudly there", but nothing can recover.
**Fix:** in `evaluate`, `feas_cut = isfinite(fr.v) ? (; …) : nothing` (route to bisection); in
`coupling.jl`, on INFEASIBLE with no ray, re-solve once with presolve off (then restore) to get a genuine
Farkas ray before falling back to NaN.

### WR-02: Writeup claims `inexact_policy` applies to the bilevel KKT variant

**File:** `docs/writeups/modelo_stackelberg_dso_unico.typ:195` — "aplica-se às três linhas, pois todas
chamam `solve_stackelberg!` internamente (linha 2 via sua própria resolução KKT-MILP…)". `bilevel_kkt.jl`
never calls `solve_stackelberg!`, has no `inexact_policy`, and rejects QP/SOCP formulations (~line 305).
**Fix:** restrict the claim to rows 1 and 3; say row 2 is LP-only.

### WR-03: The integer "brute-force certification" is not independent, and the measured equilibrium is not pinned

**File:** `test/test_planning_nash_integer.jl:116-148` — the enumeration reuses production
`corner_recourse` with the same oracle/follower and the same `c_y·y + Q` accounting as the UB under test,
so a bug there is reproduced on both sides; the measured `z=[0.5,0.5]`, `x_inv=[0.25,0.25]`, `UB=-0.225`
are never asserted. **Fix:** assert the hand-derived lattice equilibrium; for each lattice y, check with a
separately built LP/QP (fix y, pin j in a fresh shared model, minimize player i's full cost in one solve),
without `corner_recourse`.

### WR-04: `add_ll_cut!` tolerance band still appends an invalid cut

**File:** `src/planning/master_integer.jl:664-679` — for L − atol·max(1,|L|) ≤ Q_nu < L the guard passes
and the cut is appended with negative slope (Q_nu − L): at Hamming distance k, θ ≥ L + (k−1)(L − Q_nu),
over-constraining by up to (K−1)·atol·|L| (order of Benders `tol`). The public `atol` kwarg allows
arbitrarily invalid cuts; the test does this with `atol=10`, Q = L − 0.5, and asserts success.
**Fix:** after the guard, cut with `Q_eff = max(Q_nu, L)` and log the clamp.

### WR-05: Weak or unconfirmed infeasibility verdicts become +Inf in the corner search

**File:** `src/planning/benders.jl:126-133, 304-320` — for ALMOST_INFEASIBLE any non-`:disagree` verdict
counts as confirmed, including `:weak` (2.4e-9 < v ≤ 1e-6, within the master's feasibility tolerance of
the boundary); mapping it to +Inf can drop a near-boundary minimizer, overestimate Q_nu and make the LL
cut slightly invalid. `LOCALLY_INFEASIBLE` and `INFEASIBLE_OR_UNBOUNDED` are labelled "CERTIFIED" and skip
confirmation. **Fix:** confirm only on `:separating`; rethrow (or bisect) on `:weak`; route
`LOCALLY_INFEASIBLE` through feas_oracle confirmation.

### WR-06: The `integer` path silently ignores user bounds and assumes nonnegative costs

**File:** `src/planning/nash.jl:601-615` — `spec.master_kwargs.α_op_lb`/`α_x_lb` are silently discarded;
the default `α_x_lb = 0.0` is unvalidated while `build_shared_transmission` never checks
`c_inv`/`c_op ≥ 0`; with negative `c_op`, L is not a valid bound and the run aborts deep in `add_ll_cut!`
or the floor guard. **Fix:** throw if `master_kwargs` contains α_* keys with `integer !== nothing` (or
honour them); validate `c_inv, c_op ≥ 0` or derive α_x_lb = Σ min(0, c)·bounds.

## Info

- **IN-01:** `CORNER_INFEASIBLE_STATUSES` (benders.jl:132) is dead code, as its own comment admits.
- **IN-02:** benders.jl:1511-1512 comment ("tolerance includes the build-time acceptance slack") is stale; `lb_slack` is always zero, and the field plus `_accepted_lb_slack` (master_integer.jl:400) are dead weight.
- **IN-03:** `run_nash!` docstring Algorithm step 4 is garbled (nash.jl:343).
- **IN-04:** stackelberg_vs_psr_n1n2.typ:193 says `b[1:K]` are the "ÚNICAS variáveis binárias" in `src/planning/` — misleading: `bilevel_kkt.jl`'s SOS1 pairs are bridged to binaries by `SOS1ToMILPBridge`.
- **IN-05:** nash.jl:638-640 never checks `result_i.y` lies on the lattice or `idx_i < 2^K`; `digits(...; pad=K)` silently returns more than K digits. Assert `abs(y − idx·step) ≤ 1e-9·y_max && idx < 2^K`.
- **IN-06:** interior-cap probe z_spread measured 5.8e-4 (~6× `tol_outer`) vs an assertion bound of 0.01 (17× the measurement); converged flows differing by more than the outer tolerance is unexplained.
- **IN-07:** `@warn … maxlog=1` (master.jl:623, 666; master_integer.jl:291, ~330) hides every clamp after the first in multi-build contexts such as Nash; `run_nash_probe` cannot forward `integer`, so integer N>1 multiplicity cannot be probed.

---
_Reviewed: 2026-10-02 · Reviewer: Claude (gsd-code-reviewer) · Depth: standard_
