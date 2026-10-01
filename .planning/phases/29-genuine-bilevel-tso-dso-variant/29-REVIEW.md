---
phase: 29-genuine-bilevel-tso-dso-variant
reviewed: 2026-09-30T00:00:00Z
depth: standard
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
  warning: 8
  info: 5
  total: 14
status: issues_found
---

# Phase 29: Code Review Report

**Reviewed:** 2026-09-30
**Depth:** standard (with targeted live probes; no `Pkg.test` launched)
**Files Reviewed:** 7
**Status:** issues_found

## Summary

I checked the KKT/SOS1 single-level reformulation in `bilevel_kkt.jl` by hand against the
follower's Lagrangian. On both fixtures, the stationarity rows (`statio_x` sums `mu_cap` over `t`,
and `statio_z` carries the linear `q_op*z` gradient) and the four complementarity pairs are
correct. The MOI `SOS1ToMILPBridge` takes interval-arithmetic bounds for the affine slack
elements. That makes the primal side of every pair rigorously bounded. Both fixtures' hand
derivations (corner `0 / -3.9`; interior `y*=0.148, total=-1.4726`; joint `-3.0628125`;
`rho_y(0.05)=9.8`) re-derive correctly.

The defects sit around the reformulation, not inside its algebra:

- **Dual bound (`m_ub`):** the only thing that makes the answer exact is the measured dual bound,
  and the code that measures it can fail silently.
- **Lower-level KKT:** the KKT system leaves out one lower-level bound (`x_inv <= x_inv_max`).
- **Boundary guard:** the guard lets non-LinDistFlow formulations through.
- **Tests:** several assertions that claim to certify something actually pass for an unrelated
  reason, or check the oracle instead of the production model.

Live probes (scratch scripts that only `using TSODSO`) confirmed:
- `m_ub = 9544.44` on the interior fixture. It comes from Clarabel's arbitrary point on an
  unbounded dual face at `y=0`. The tight value is 14.8.
- Fixing `y_inv = 1.0` with `x_inv_max = 0.1` makes the production MILP `INFEASIBLE`, even though
  `y = 1.0` is bilevel-feasible.
- `ACPowerFlow()` gets past the guard and fails deep inside JuMP with an `ErrorException`, not an
  `ArgumentError`.

## Structural Findings (fallow)

No structural pre-pass was provided.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: The dual bound `m_ub` can be silently under-measured, and the post-solve check cannot detect a cut-off optimum

**File:** `src/planning/bilevel_kkt.jl:179-217` (probe loop, silent skip at line 200) and `src/planning/bilevel_kkt.jl:461-494` (validity check)

**Issue:** `m_ub` is the big-M for every complementarity dual. It is the only thing that makes the
single-level MILP equivalent to the bilevel problem. Two compounding defects:

1. **A failed probe is skipped silently.** `if is_solved_and_feasible(m; dual = true) ... end` just
   drops a probe that failed, and the code errors only when *both* probes fail. The `y_probe = 0.0`
   probe is the one that carries the large duals: `rho_y` is non-increasing in `y`, so its maximum
   is at `y = 0`. That probe is also the degenerate one (`0 <= x_inv <= 0`, so Slater's condition
   fails and the dual optimal face is unbounded). With `q_op > 0` it goes through Clarabel's
   interior-point method, the solver most likely to return `ALMOST_OPTIMAL` or `SLOW_PROGRESS` on a
   problem with no strictly feasible interior.
   - If only that probe fails, `m_ub` comes from the `y_max` probe alone.
   - On the interior fixture that gives `10 * 0.02 = 0.2`, while the true `rho_y` reaches 14.8.
   - Every leader decision with `rho_y > 0.2` (here `y < 0.146`) is then excluded from the MILP's
     feasible set, with no error.
   - The CONTEXT decision says "derive valid primal/dual bounds; fail loudly otherwise". A
     half-measured bound is not "loud".

2. **The post-solve check is necessary, not sufficient.** `solve_bilevel!` rejects a solution only
   when a dual sits within `1e-6` of `m_ub`. When `m_ub` is too small, the true optimum is cut off.
   The MILP then returns the best remaining leader decision, and its duals can lie strictly inside
   `[0, m_ub]`. This is the documented failure mode of big-M bilevel reformulations (Pineda &
   Morales 2019, "Solving linear bilevel problems using big-Ms: not all that glitters is gold").
   - Concrete mechanism: with `T >= 2` and a non-monotone leader cost in `y`, the true optimum can
     be at `y = 0` (needs large `rho_y`, excluded) while the restricted optimum is a later kink
     where `rho_y < m_ub`.
   - The check passes and a wrong "bilevel optimum" is returned.
   - The docstring of `solve_bilevel!` presents this check as the validity gate.

Together these give a credible way to return a wrong answer with no error, in the one component
whose correctness the phase's "exact" claim depends on.

**Fix:** Fail if *either* probe fails, and stop depending on an IPM's choice on a degenerate face.
For this follower structure the dual bounds are available in closed form:
```julia
# inside _measure_follower_kkt_bounds, replacing the silent skip
is_solved_and_feasible(m; dual = true) || error(
    "_measure_follower_kkt_bounds: probe y_probe=$y_probe failed — refusing to " *
    "derive m_ub from a partial measurement:\n" * last(probe_statuses))

# and/or an analytic bound valid for every y (follower: z ≥ 0, z ≤ cap*x, 0 ≤ x ≤ y):
mu_cap_max = maximum(max.(pi_tariff .- c_op, 0.0))            # statio_z with z ≥ 0
rho_y_max  = corridor_cap * sum(max.(pi_tariff .- c_op, 0.0)) # statio_x with rho_lo = 0
mu_lo_max  = maximum(max.(c_op .- pi_tariff, 0.0)) + mu_cap_max
rho_lo_max = c_inv + corridor_cap * T * mu_cap_max
m_ub = safety * max(1e-6, mu_cap_max, rho_y_max, mu_lo_max, rho_lo_max)
```
Also reword the `solve_bilevel!` docstring so it says the at-bound check is a necessary (not
sufficient) sanity check, and that the validity guarantee rests on `m_ub`.

## Warnings

### WR-01: The KKT system has no multiplier for the follower's `x_inv <= x_inv_max`, so bilevel-feasible leader decisions become MILP-infeasible

**File:** `src/planning/bilevel_kkt.jl:375`, `src/planning/bilevel_kkt.jl:386-390`

**Issue:** `x_inv_max` is a bound in the follower's own problem (the probe at line 181 and both
oracles model it that way). In the single-level model it is only a variable bound, with no dual in
`statio_x`. When the follower's response would hit `x_inv_max` and `y_inv > x_inv_max`, the
equation `c_inv - cap*Σmu_cap + rho_y - rho_lo = 0` has no feasible completion.

Live probe: `x_inv_max = 0.1, y_max = 5`, with `y_inv` fixed to `1.0`, gives `INFEASIBLE`. The true
follower response (`x_inv = 0.1, z = 1.0`) exists. The optimal value survives today only because
`c_y >= 0` makes `y = x_inv_max` weakly dominant. Any change to the leader objective (a subsidy on
`y`, or coupling `y` to other upper-level terms) turns this into a wrong answer. The interior test
file's header (lines 37-41) admits this as a "known modeling gap" that is "sidestepped by
construction". The src file says nothing about it and does not guard it, which breaks the "throw a
clear ArgumentError, never a silent fallback" API decision.

**Fix:** Add the missing complementarity pair:
```julia
@variable(model, 0 <= rho_max <= m_ub)
@expression(model, slack_max, x_inv_max - x_inv)
# statio_x: c_inv - corridor_cap*sum(mu_cap) + rho_y + rho_max - rho_lo == 0
@constraint(model, [slack_max, rho_max] in MOI.SOS1([1.0, 2.0]))
```
Include `rho_max` in the `solve_bilevel!` bound check. At minimum, throw an `ArgumentError` when
`y_max > x_inv_max`.

### WR-02: The formulation guard is a SOCP denylist, so `ACPowerFlow` gets through and fails deep in JuMP (and `DCPowerFlow` is accepted untested)

**File:** `src/planning/bilevel_kkt.jl:295-301`

**Issue:** `problem_class(pf) isa SOCP` rejects only SOCP formulations. `ACPowerFlow`
(`problem_class == NLP()`) passes the guard, then fails at solve with
`ScalarQuadraticFunction-in-EqualTo are not supported by the solver` (an `ErrorException`, confirmed
live). The locked decisions say "DSO network LinDistFlow (LP)" and "Unsupported inputs ... throw a
clear ArgumentError". `DCPowerFlow` builds and solves without any test or documentation. Any
future QP-class formulation that adds a quadratic term would also make this an MIQP that HiGHS
cannot solve (the file's own Pitfall 5).

**Fix:** Use an allowlist:
```julia
pf isa LinDistFlow || throw(ArgumentError(
    "build_bilevel_kkt supports only LinDistFlow (strictly affine network) — got $(typeof(pf))"))
```
Add an `ACPowerFlow()` case to the boundary-guard testitem.

### WR-03: `m_ub` is an artefact of Clarabel's dual choice, not a measured quantity (9544 vs the tight 14.8), and it weakens complementarity enforcement

**File:** `src/planning/bilevel_kkt.jl:180, 200-206`

**Issue:** At `y_probe = 0` the dual optimal set is unbounded: `rho_y` and `rho_lo` can both move
along a ray, and so can `mu_cap` and `mu_lo`. HiGHS (LP) returns the vertex `14.8 / 1.5`. Clarabel
(QP) returns an interior point of the face: `dual(inv_bound) = -954.4`, `reduced_cost(x) = 350.6`,
giving `m_ub = 9544.4` (live probe on the interior fixture; `3318.5` on a T=2 variant). So the
"MEASURED, never guessed" bound depends on the solver and its version, and is about 650x larger
than needed. The bridge enforces `mu <= m_ub * b`. With HiGHS `mip_feasibility_tolerance = 1e-9`
also acting as the integrality tolerance, a fractional `b` of 1e-9 leaves up to ~1e-5 of
complementarity violation. The CONTEXT asked for the MILP tolerance to be re-measured for this
consumer, and that was not done for this M.

**Fix:** Use the closed-form bounds from CR-01, or probe at a small `y = ε > 0` (non-degenerate).
Record `m_ub` in a test so that drift is visible.

### WR-04: The interior test's "fine grid resolves the optimum independently of the salted point" assertion uses the salted result

**File:** `test/test_planning_certification_bilevel_interior.jl:406-409`

**Issue:** The comment says the check confirms "the fine grid itself resolves the true optimum,
independent of the salted point". The code tests `bf.y`, which comes from `salted_grid`, a grid
that contains `0.148` exactly. So `abs(bf.y - 0.148) < grid_spacing + atol_hand` is true by
construction. The fine-only run `bf_fine_only` is computed but only used in the loose `atol = 1e-2`
total check (line 414).

**Fix:**
```julia
@test abs(bf_fine_only.y - F.INTERIOR_Y_HAND) <= grid_spacing
@test isapprox(bf.total, bf_fine_only.total; atol = 10 * grid_spacing)  # analytic slope ≈ 9.95
```
The real difference is about 1e-4 (`f(0.15) = -1.4725` vs `-1.4726`), so `1e-2` is about 100x
looser than the claimed spacing argument.

### WR-05: The "SOS1 branch-switch" and "z≡0 mutation guard" assertions run on the oracle QP, not on the production MILP

**File:** `test/test_planning_certification_bilevel_interior.jl:424-442`

**Issue:** `r_below`, `r_above` and `r_at_one` all come from `solve_follower_at`, a standalone
Clarabel QP. None of them touches `kkt.model`. The production optimum sits exactly at the kink
`y = 0.148`, where `slack_y = 0` and `rho_y = 0` hold at the same time (degenerate
complementarity). So the production solve never shows `[slack_y, rho_y]` in either strict branch.
The checker's requirement ("[slack_y, rho_y] SOS1 pair genuinely switching") is met only for the
oracle. A production reformulation with a broken `rho_y` pair would still pass lines 433-442.

**Fix:** Fix the leader decision in the production model and read the production duals:
```julia
for (y, expect_rho) in ((0.05, F.RHO_Y_BELOW_HAND), (1.0, 0.0))
    k = build_bilevel_kkt(feeder, LinDistFlow(); ...same kwargs...)
    fix(k.y_inv, y; force = true)
    r = solve_bilevel!(k)
    @test isapprox(r.rho_y, expect_rho; atol = 1e-6)
end
```

### WR-06: The "too-tight bound" test passes through MILP infeasibility and never reaches the validity check it claims to test

**File:** `test/test_planning_bilevel.jl:128-156`

**Issue:** With `safety = 1e-9`, `m_ub` is about 1e-9. On the corner fixture, `statio_x`
(`1 - 2*mu_cap + rho_y - rho_lo = 0`, all multipliers in `[0, 1e-9]`) has no solution, so
`assert_solved!` throws "Solve failed" first. `@test_throws Exception` accepts any exception. The
`isapprox(v, kkt.m_ub)` error branches in `solve_bilevel!` (lines 465-494) are therefore never
exercised by any test. The comment ("the solved complementarity variables land at/near the bound")
is false.

**Fix:** Choose a `safety` that keeps the model feasible but makes a dual bind. On the interior
fixture with the leader fixed at a small `y` (so `rho_y` is forced to `14.8 - 100y`), set `m_ub`
equal to that value. Match on the message, for example
`@test_throws r"sits at \(or within" solve_bilevel!(kkt)` on Julia 1.11, or catch the error and
check `occursin`.

### WR-07: The oracles do not share production's semantics for the network coupling or the follower's tie-breaking

**File:** `test/test_planning_certification_bilevel.jl:146-149`, `test/test_planning_certification_bilevel_interior.jl:170-171`, `test/test_planning_certification_bilevel.jl:104-105`

**Issue:**
- **Network coupling:** brute force sets `d_star = min(z_star, d_max)` and still charges
  `pi_tariff * z_star`, so a `z > d_max` response counts as feasible-but-curtailed. In production,
  `balance_p` forces `d = z`, so the same `y` is infeasible.
- **Voltage bounds:** brute force ignores them; production enforces them.
- **BilevelJuMP:** the oracle hand-codes `d == z`.
- **Follower ties:** brute force takes whatever optimum HiGHS or Clarabel reports when the follower
  has ties. The KKT-MILP is *optimistic*: the leader picks among the follower's optimal set.

The fixtures never activate these differences (`d_max` and the voltage limits are slack, and there
are no follower ties). So the oracles agreeing with production says nothing about the embedded
LinDistFlow coupling, which is the CONTEXT "Option B" decision. The optimistic assumption is also
not stated in the `bilevel_kkt.jl` docstrings.

**Fix:** In brute force, mark `z_star > d_max` (or `v2` outside its bounds) as infeasible
(`continue`) instead of capping it. State "optimistic bilevel; leader-level constraints on
follower variables are coupling constraints" in the `build_bilevel_kkt` docstring. Add one fixture
where `d_max` binds the follower's response, to exercise the network coupling.

### WR-08: The multi-period path (`T > 1`, the shared-`x_inv` stationarity sum) has no test

**File:** `src/planning/bilevel_kkt.jl:386-390`; all three test files

**Issue:** Every production call in the tests uses `T = 1`. The CONTEXT scope is `T <= 2`. The
`sum(mu_cap[t] for t in 1:T)` in `statio_x` and the per-`t` SOS1 loops are the most error-prone
lines, and nothing exercises them. A wrong index (for example `mu_cap[1]` repeated) would pass
every test. A live T=2 probe gave a plausible answer (`y = 0.148, z = [1.48, 0]`), but that is not
a pinned test.

**Fix:** Add a T=2 interior fixture with distinct tariffs where both periods deliver
(`pi_tariff[t] - c_op[t] > c_inv/corridor_cap` for both `t`). Hand-derive it and cross-check
against BilevelJuMP and brute force.

## Info

### IN-01: The "differs" floors are below the "equals" tolerances

**File:** `test/test_planning_certification_bilevel_interior.jl:292-293, 375`; `test/fixtures_planning.jl:166`

**Issue:** `GAP_FLOOR_INTERIOR = 1e-6` while `atol_hand = 1e-4`, and `BILEV_GAP_FLOOR = 1e-8`. A
result could be "equal to joint within atol_hand" and "different from joint" at the same time. The
floors are justified by `mip_feasibility_tolerance`, which is a constraint-violation tolerance and
not an objective-comparison error bar. The divergence asserts are carried by the golden-value
asserts, not by the floors.

**Fix:** Set each floor to at least 10x the largest equality tolerance used in the same test
(`>= 1e-3`), or drop the floors and say that the golden asserts carry the divergence claim.

### IN-02: Tolerance comments point to "this plan's SUMMARY" instead of stating the measured value

**File:** `test/test_planning_certification_bilevel_interior.jl:373-375, 388-392, 397-401`; `test/test_planning_bilevel.jl:36-40`

**Issue:** The header says production matched within 1e-7, but `atol_hand = 1e-4` (1000x looser).
`atol_bilevel` and `atol_bruteforce` (both 1e-3) cite measurements that are not recorded in the
file. That goes against the "measure comparison epsilons" convention (memory:
`highs-exactness-defaults`).

**Fix:** Write the measured residuals inline next to each `atol`, and set each `atol` to about 10x
the measured value.

### IN-03: The absolute tolerance in the at-bound check does not scale with `m_ub`

**File:** `src/planning/bilevel_kkt.jl:464-494`

**Issue:** `isapprox(v, m_ub; atol = 1e-6)` uses a fixed absolute window, while `m_ub` ranges from
1e-5 to about 1e4. The four blocks are also copy-pasted.

**Fix:** Loop over `(name, var)` pairs and test `v >= m_ub * (1 - 1e-6) - 1e-9`.

### IN-04: The boundary-guard test covers only part of the guard list

**File:** `test/test_planning_bilevel.jl:47-126`

**Issue:** There are no cases for:
- the `pi_tariff`, `q_op` and `v_d` length mismatches
- non-positive `corridor_cap`, `x_inv_max`, `y_max`, `d_max` and `safety`
- negative `c_inv` and `c_y`
- `ACPowerFlow` (see WR-02)

**Fix:** Add one `@test_throws ArgumentError` per guard.

### IN-05: The `TSODSO.jl` include comment is garbled about dependencies

**File:** `src/TSODSO.jl` (bilevel_kkt include block)

**Issue:** "needs only follower.jl's/master.jl's ALREADY-LOADED sibling files transitively" is
confusing. The file actually depends on `ModelContext`, `contribute!`, `add_to_residual!`,
`register_constraint!`, `problem_class`/`SOCP` and `select_optimizer`/`assert_solved!`, all from
core, powerflow and solver, not from planning.

**Fix:** List the real dependencies.

---

_Reviewed: 2026-09-30_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
