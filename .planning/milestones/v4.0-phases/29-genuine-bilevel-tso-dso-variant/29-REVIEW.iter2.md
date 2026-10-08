---
phase: 29-genuine-bilevel-tso-dso-variant
reviewed: 2026-10-01T00:52:20Z
depth: standard
iteration: 2
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
  critical: 1
  warning: 2
  info: 3
  total: 6
status: issues_found
---

# Phase 29: Code Review Report (iteration 2)

**Reviewed:** 2026-10-01T00:52:20Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

This pass re-reviews the code after commits 5da5232..07b3822, which fixed CR-01 and WR-01..WR-08 from iteration 1 (backed up as `29-REVIEW.iter1.md`). Iteration-1 items are not raised again.

**Closed-form bound `_follower_kkt_dual_bound`: verified valid.** I checked the four-case proof by hand against the follower KKT system, including the new `rho_max` term:

- **`x_inv > 0`:** `rho_lo = 0`. Each `mu_cap[t]` is uniquely determined and `<= a⁺[t]`. So `rho_y + rho_max = cap*Σmu_cap - c_inv <= cap*Σa⁺ - c_inv`.
- **`x_inv = 0`, `y > 0`:** `rho_y = 0` and `rho_max = 0`. Optimality of `x = 0` requires `c_inv >= cap*Σa⁺`. With `mu_cap = a⁺` this gives `rho_lo = c_inv - cap*Σa⁺`, which lies in `[0, c_inv]`.
- **`x_inv = 0`, `y = 0`:** choose `rho_y = (cap*Σa⁺ - c_inv)⁺` and `rho_lo = (c_inv - cap*Σa⁺)⁺`.

At least one KKT multiplier vector therefore fits in `[0, m_ub]` for every `y_inv` and every follower optimum, as long as `safety >= 1`. The bound cannot cut off the true optimum.

Empirical check: a scratch script ran 60 random instances (T in 1..3, random data, `x_inv_max`/`d_max` often binding) at the tightest `safety = 1`. It compared the production MILP objective with a 301-point brute-force grid using the follower QP. Worst `prod - bf` was 1.0e-7, and no instance was cut off. The `rho_max` stationarity term, its SOS1 pair and the T>1 `Σmu_cap` sum are correct.

**New defect: the post-solve at-bound check rejects correct results.** The bound proof only shows that *some* in-box multiplier exists. HiGHS returns an arbitrary vertex of the multiplier face, and when `x_inv* = 0` that face is degenerate and its vertices sit at `m_ub`. `solve_bilevel!` then throws a hard error on a correct optimum. Raising `safety`, as the error message advises, cannot help: the vertex moves with `m_ub`. This is reproduced below (CR-01).

**Fixed tests:** all are genuinely falsifiable.

- **WR-01 test:** without `rho_max` the fixed-y model is INFEASIBLE.
- **WR-05/WR-08 fixed-y checks:** they pin uniquely determined multipliers.
- **WR-06 test:** it reaches the at-bound branch with a unique `rho_y = 9.8`.
- **WR-04 test:** it now checks the fine-only grid.
- **WR-07 d_max test:** it has a hand-derived binding optimum.

## Critical Issues

### CR-01: `solve_bilevel!` throws a "true optimum may have been cut off" error on correct optima whenever the follower does not invest (`x_inv* = 0`)

**File:** `src/planning/bilevel_kkt.jl:469-509` (check). Root cause is the degenerate multiplier face described at `:129-131` and `:155-167`.

**Issue:** When `x_inv = 0` with `y_inv = 0`, the slack pairs `[slack_y, rho_y]`, `[x_inv, rho_lo]`, `[slack_cap, mu_cap]` and `[z, mu_lo]` all have zero primal slack. The multipliers then form an unbounded ray, which the `[0, m_ub]` box truncates:

- `rho_y - rho_lo = cap*Σmu_cap - c_inv`
- `mu_cap - mu_lo = a`

The MILP objective does not involve the multipliers, so HiGHS returns whichever vertex its pivoting reaches. Those vertices lie on the box face `= m_ub`, so the check fires on a mathematically valid KKT point.

This is the generic outcome whenever the leader prefers no delivery:

- `pi_tariff >= v_d`, or
- a large `c_y`, or
- a caller that fixes `y_inv = 0` for a sensitivity sweep.

Reproduced with a scratch script on the interior fixture data:

```
interior, v_d=[1.0] (true optimum y*=0, obj 0):  rho_y=148.0 = m_ub, mu_cap=14.82  -> ERROR "rho_y sits at ... m_ub=148.0"
same, safety=1:                                  rho_y=14.8  = m_ub               -> ERROR
interior, c_y=20 (true optimum y*=0):            rho_y=148.0 = m_ub               -> ERROR
interior, fix(y_inv, 0.0):                       rho_y=148.0, rho_lo=133.2        -> ERROR
```

In the 60-instance random sweep, the default `safety = 10` gave 6/60 false errors, all on optima the brute force confirmed. `safety = 1` gave 26/60.

The corner fixture passes only because HiGHS happens to pick the vertex `mu_cap = 0.5`, `mu_lo = 0.8`, `rho_y = rho_lo = 0`. That is solver-path luck, not a property of the code.

The error text ("re-derive a looser bound (increase `safety`) and re-build") sends users into a loop that can never succeed, because the offending vertex scales with `m_ub`. No testitem covers a `y* = 0` optimum with a profitable follower (`a⁺ > 0`), so the suite stays green.

**Fix:** Validity already rests on the closed-form bound, as the docstring concedes. Make the post-check test whether an in-box certificate exists, not where HiGHS's vertex happens to land:

```julia
# after assert_solved!: fix the primal, then find the SMALLEST KKT certificate
cert = Model(select_optimizer(LP()))
@variable(cert, 0 <= mc[1:T]); @variable(cert, 0 <= ml[1:T])
@variable(cert, 0 <= ry); @variable(cert, 0 <= rl); @variable(cert, 0 <= rm); @variable(cert, s)
@constraint(cert, c_inv - cap*sum(mc) + ry + rm - rl == 0)
@constraint(cert, [t=1:T], -a[t] + q_op[t]*zv[t] + mc[t] - ml[t] == 0)
# complementarity on the solved active set: zero every multiplier whose primal slack > tol
slack_cap_v[t] > tol && fix(mc[t], 0.0)  # likewise ml/ry/rl/rm
@constraint(cert, [mc; ml; ry; rl; rm] .<= s); @objective(cert, Min, s)
optimize!(cert)
objective_value(cert) < kkt.m_ub - atol || error("... no KKT certificate inside m_ub ...")
```

Keep the extra data needed for this (`a`, `q_op`, `c_inv`, `corridor_cap`) on `BilevelKKT`. Report the minimal certificate as the multipliers (see WR-02). Then add a regression testitem: interior data with `v_d = [1.0]`, expecting `y* = x_inv* = z* = 0`, `total = 0`, and `solve_bilevel!` not throwing.

A minimal alternative is to drop the hard error when `x_inv ≈ 0`, since all the degenerate faces arise there. The `y = x = x_max` split of `rho_y`/`rho_max` is bounded by its sum and did not trigger in testing.

## Warnings

### WR-01: `safety` in `(0, 1)` is accepted, but the validity proof needs `safety >= 1`, and the check cannot detect the resulting cut-off

**File:** `src/planning/bilevel_kkt.jl:316`

**Issue:** The guard is `safety > 0`. The `_follower_kkt_dual_bound` proof shows the tight multiplier can equal the unscaled bound exactly; for example, `rho_y(y=0) = 14.8` on the interior fixture. So any `safety < 1` can remove the true optimum from the MILP.

The `solve_bilevel!` docstring (`:455-462`) itself says the at-bound check cannot detect a cut-off optimum. A caller who passes `safety = 0.5` to "tighten the big-M" therefore gets a silently wrong leader decision, with no error.

**Fix:** Change the guard to `safety >= 1 || throw(ArgumentError("safety must be >= 1 (the closed-form bound is tight); got $safety"))`. The WR-06 stress test needs some other way to build an under-sized `m_ub`, for example:

- an internal `_m_ub_override` keyword, or
- building with `safety = 1` and then `set_upper_bound(tight.rho_y, 9.8)`.

The second option is simpler and keeps the public API safe.

### WR-02: Returned multipliers (`mu_cap`, `mu_lo`, `rho_*`) are arbitrary points on a non-unique multiplier face, but are returned as if meaningful

**File:** `src/planning/bilevel_kkt.jl:511-523`

**Issue:** Whenever `x_inv = 0`, or `y = x = x_max`, the multipliers are not unique, and the returned values are just HiGHS's vertex:

- Corner fixture: returns `mu_cap = 0.5` and `mu_lo = 0.8`, while the minimal certificate is `mu_cap = 0`, `mu_lo = 0.3`.
- `v_d = [1.0]` case: returns `mu_cap = 14.82` and `rho_y = 148` against `a⁺ = 1.5`.

The project treats duals as prices, so a consumer will reasonably read `rho_y` as the shadow value of the leader's investment cap. These values can change with the HiGHS version or presolve path, which hurts reproducibility.

**Fix:** Return the minimal (canonical) certificate computed in the CR-01 fix. At the least, state in the docstring that the multipliers are unique only on non-degenerate active sets and must not be read as prices otherwise.

## Info

### IN-01: `GAP_FLOOR_INTERIOR` derivation comment contradicts its value

**File:** `test/test_planning_certification_bilevel_interior.jl:297-304`

**Issue:** The comment says the floor is "10x the production MILP's own `mip_feasibility_tolerance=1e-9`", which is 1e-8, but the value is `1e-6`. `fixtures_planning.jl:166` uses 1e-8 for the same stated derivation.

**Fix:** Either set `1e-8`, or state the real basis (for example, the 1e-6 production-vs-hand tolerance).

### IN-02: T=2 brute force omits the voltage-bound filter that the other oracles apply "to match production semantics"

**File:** `test/test_planning_certification_bilevel_interior.jl:687-698`

**Issue:** `brute_force_T2` filters only `z <= d_max`. The other two brute-force oracles also filter the bus-2 voltage band, per WR-07. The band is slack on this fixture, so results are unaffected, but the oracle is not semantically equivalent to production if it is copied or reused.

**Fix:** Add `all(0.95^2 .<= 1 .- 2e-3 .* zs .<= 1.05^2) || continue`.

### IN-03: Stale plan-time language in the `build_bilevel_kkt` docstring

**File:** `src/planning/bilevel_kkt.jl:260-264`

**Issue:** The paragraph "MEASURES, does not assume ... extended with a keyword-passthrough seam ONLY if measurement (Task 2's fixture) shows it is insufficient" describes a plan task, not behaviour. It should be resolved or removed.

**Fix:** Replace it with the measured outcome. The shared `select_optimizer(MILP())` defaults are used unchanged and solve all fixtures to `OPTIMAL`.

_Iteration-1 info items IN-01..IN-05 were out of the fixer's scope and remain as described in `29-REVIEW.iter1.md`. They are not repeated here._

---

_Reviewed: 2026-10-01T00:52:20Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
