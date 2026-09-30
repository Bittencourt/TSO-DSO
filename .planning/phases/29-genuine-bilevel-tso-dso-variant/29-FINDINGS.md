# Phase 29 Findings: Genuine Bilevel TSO-DSO Variant

**Phase:** 29-genuine-bilevel-tso-dso-variant
**Closed:** 2026-09-30
**Requirements:** BILEV-01, BILEV-02

This document consolidates the fixture design, measured numbers, and audit/suite results
across plans 29-01 (production `build_bilevel_kkt!`/`solve_bilevel!`), 29-02 (BILEV-02
corner-fixture certification), and 29-04 (BILEV-02 BLOCKER-1 non-degenerate interior
fixture), per the plan's eight required points.

## 1. Fixture designs and why each produces a genuine bilevel-vs-joint gap

### CORNER fixture (`bilevel_toy_fixture()`, plan 29-01/29-02, `test/fixtures_planning.jl`)

2-bus/T=1 embedded LinDistFlow network (root bus 1, load bus 2, `r=x=1e-3`,
`smax=99.0`), with an exogenous tariff `pi_tariff=[0.2]` strictly BELOW the follower's
own operating cost `c_op=[0.5]` and `q_op=0` (plain LP follower, no quadratic term). The
follower minimizes `c_inv*x_inv + (c_op-pi_tariff)*z` subject to `z <= corridor_cap*x_inv`
(`mu_cap`), `x_inv <= y_inv` (`rho_y`), `x_inv,z >= 0`. Because `c_op - pi_tariff = 0.3 > 0`
for every `y_inv >= 0`, the follower's dominant strategy is to under-supply to the
degenerate corner `x_inv=z=0` regardless of what the leader invests — this is the
"follower's own cost makes it under-supply" case CONTEXT.md's BILEV-02 decision requires.
The DSO leader's true valuation of `z` (embedded LinDistFlow network + linear elastic
demand `v_d=[3.0]`/`d_max`) values `z` positively, so the JOINT (single-planner,
tariff-free) optimum invests and dispatches (`y*=x_inv*=1.0`, `z*=2.0`), producing a
genuine wedge between the bilevel answer (`0.0`) and the joint answer (`-3.9`). This
fixture is cheap (LP, degenerate corner) but — as plan 29-02's own "Next Phase Readiness"
flagged — alone it cannot exercise genuine leader-follower INTERACTION (the follower's
response is constant in `y_inv`) or the SOS1 pair's "inactive" branch.

### Non-degenerate INTERIOR fixture (`BilevelInteriorCertFixture`, plan 29-04,
`test/test_planning_certification_bilevel_interior.jl`, self-contained)

Same 2-bus/T=1 lossless feeder shape, but with `q_op=[1.0] > 0` (a convex quadratic
follower term) and `pi_tariff=[2.0]` set ABOVE `c_op=[0.5]` this time, so the follower's
reduced single-variable QP in `z` has a genuinely INTERIOR unconstrained optimum
(`z_F = (pi_tariff - c_op - c_inv/corridor_cap)/q_op = 1.48`, reached once the follower's
own investment cap loosens past `y_inv=0.148`). This produces a TWO-BRANCH piecewise-linear
follower response in `y_inv`: for `y_inv < 0.148` the coupling constraint `x_inv <= y_inv`
BINDS (follower supply-constrained, `rho_y > 0`); for `y_inv >= 0.148` it goes SLACK
(follower at its own free interior optimum, `rho_y ≈ 0`). This is the piece the corner
fixture structurally cannot provide: a fixture where the production single-level KKT-MILP's
SOS1 `[slack_y, rho_y]` pair is observed BOTH active and inactive across the leader's
feasible range, proving genuine complementarity switching (not a wrong reformulation or a
`z≡0` stub that would pass the corner fixture's three oracles vacuously). The joint
reference here (`y*=x_inv*=0.2475`, `z*=2.475`, `total*=-3.0628125`) again diverges
genuinely from the bilevel production answer (`y*=x_inv*=0.148`, `z*=1.48`,
`total*=-1.4726`).

## 2. Measured bilevel/joint/gap numbers for both fixtures

| Quantity | Corner fixture (29-02) | Interior fixture (29-04) |
|----------|------------------------|---------------------------|
| Bilevel `y*`/`x_inv*` | `0.0` (`BILEV_Y_HAND`) | `0.148` (`INTERIOR_Y_HAND`/`INTERIOR_XINV_HAND`) |
| Bilevel `z*` | `0.0` (`BILEV_Z_HAND`) | `1.48` (`INTERIOR_Z_HAND`) |
| Bilevel `total*` | `0.0` (`BILEV_TOTAL_HAND`) | `-1.4726` (`INTERIOR_TOTAL_HAND`) |
| Joint `y*`/`x_inv*` | `1.0` (`JOINT_Y_HAND`/`JOINT_XINV_HAND`) | `0.2475` (`JOINT_Y_HAND_INTERIOR`/`JOINT_XINV_HAND_INTERIOR`) |
| Joint `z*` | `2.0` (`JOINT_Z_HAND`) | `2.475` (`JOINT_Z_HAND_INTERIOR`) |
| Joint `total*` | `-3.9` (`JOINT_TOTAL_HAND`) | `-3.0628125` (`JOINT_TOTAL_HAND_INTERIOR`) |
| Measured gap (cost / power) | `3.9` / `2.0` | `~1.59` / `~0.995` |
| Gap floor | `BILEV_GAP_FLOOR = 1e-8` | `GAP_FLOOR_INTERIOR`/`Z_GAP_FLOOR_INTERIOR = 1e-6` |

Both fixtures' live production solves matched their hand-derivations exactly (corner:
`0.0` to double precision, no atol slack needed; interior: within `1e-7` per plan 29-04's
SUMMARY) — no hand-derivation correction was needed on either fixture. The measured gaps
sit 8 (corner) and 5-6 (interior) orders of magnitude above their respective floors.

## 3. Measured SOS1 `m_ub` bounds and Pitfall-3 validity-check confirmation

- **Corner fixture:** `m_ub = 10.0` (plan 29-01 SUMMARY) — the measured minimal feasible
  complementarity-dual assignment at this fixture's corner is `≈0.534` (from the widened
  probe collecting both named-constraint duals AND variable-bound reduced costs,
  `reduced_cost(x_inv)=1.0`, `reduced_cost(z[1])=0.3`), comfortably inside `[0, 10.0]`.
- **Interior fixture:** derived via the same `_measure_follower_kkt_bounds` helper
  (`safety * max(1e-6, maximum(magnitudes))`, `src/planning/bilevel_kkt.jl`), with the
  explicit branch-switch demonstration `RHO_Y_BELOW_HAND = 9.8` (`y_inv=0.05`, below the
  kink, coupling binding) and `RHO_Y_ABOVE_HAND ≈ 0.0` (`y_inv=1.0`, above the kink,
  `rho_y≈5.2e-11≈0`) — both comfortably inside the derived bound, with the "above" value
  confirming the SOS1 pair's inactive branch is genuinely reached.
- **Validity check:** `solve_bilevel!`'s post-solve Pitfall-3 check (`src/planning/
  bilevel_kkt.jl` lines ~452-493, asserting no complementarity variable sits within
  `atol_bound` of `kkt.m_ub`) never fired on either accepted production result — both
  plan 29-01's (12/12 assertions) and plan 29-04's (28/28 assertions) direct-script
  verification runs completed with `solve_bilevel!` returning normally (no `error(...)`
  raised), which is only possible if the check's internal `isapprox(v, kkt.m_ub; ...)`
  assertions all evaluated `false`.

## 4. `select_optimizer(::MILP)` shared-tolerance extension status

**Not extended.** `git diff 3d4beb0..HEAD --stat -- src/` shows only three files changed
in `src/` across the whole phase: `src/TSODSO.jl` (+6, one new `include` line),
`src/planning/benders.jl` (+17, comment/docstring-only, see point 5), and the new
`src/planning/bilevel_kkt.jl` (+510). **`src/solver/factory.jl` was not touched** — the
existing `select_optimizer(::MILP)` (`output_flag=>false`, `mip_rel_gap=>0.0`,
`mip_feasibility_tolerance=>1e-9`) was reused unmodified by both fixtures. Both plan
29-01's and plan 29-04's SUMMARYs independently confirm the shared default solved cleanly
(`MOI.OPTIMAL`/production reproduces both hand-derived optima to within measured atols) —
no keyword-passthrough seam was added (Pitfall 4's "measure first, don't touch
speculatively" instruction honored on both fixtures).

## 5. `solve_stackelberg!` byte-identical confirmation

`git diff 3d4beb0..HEAD -- src/planning/benders.jl` shows exactly 17 inserted lines, all
either `#`-prefixed module-header comments or markdown-formatted docstring prose (a new
"Honest relabelling" paragraph above the function and inside its docstring). Zero
executable lines were added, removed, or modified. `solve_stackelberg!`'s code is
byte-identical to its Phase-28-close state.

## 6. WARNING-1 (checker feedback): why `solve_stackelberg!` cannot serve as the joint reference

`solve_stackelberg!` solves THE INTEGRATED PROBLEM via Benders decomposition — its
subproblem (`FollowerLP`/`solve_follower!`) feeds the follower's own true reported
cost/recourse directly, unmodified, into the leader's optimality-cut epigraph
(`add_optimality_cut!(master, :x, follower_res.cost, follower_res.π_s, ...)`). That cost
is itself built around `pi_tariff`-driven follower behavior baked into `FollowerLP`'s own
coupling (`x_op[t] == z[t]`, dual-pinned) — there is no parameter or mode inside
`solve_stackelberg!`/`FollowerLP`/`BendersMaster` that "drops" or zeroes out the tariff to
recover a tariff-free single-planner social optimum. The joint reference this phase
requires is structurally a DIFFERENT optimization problem (a single planner directly
choosing `y`, `x_inv`, `z` against its OWN valuation `v(z)`, with no tariff term and no
follower-cost epigraph at all), not a parameterization of the existing Benders loop. This
is why both plans 29-02 (`build_joint_reference`) and 29-04
(`build_joint_reference_interior`) each hand-roll a genuinely separate, self-contained
single-planner JuMP model (reusing `contribute!(LinDistFlow(), ...)` verbatim for the
network welfare term) rather than attempting to reuse or reconfigure
`solve_stackelberg!`/`FollowerLP`/`BendersMaster` for this purpose.

## 7. Golden-audit result

`python3 .planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/scripts/audit_goldens.py --base 3d4beb0 --head HEAD` exits **0**:

```
# Golden-move audit: 3d4beb0..HEAD -- test/

Total flagged numeric-literal moves: 0
Attributed: 0  Allowlisted (investigated false negatives): 0  Unattributed: 0

No unattributed golden-value moves found (allowlisted false negatives shown above, if any).
AUDIT_EXIT:0
```

Zero flagged moves at all (not zero-unattributed-among-many-flagged) — confirming Phase 29
only ADDS new named constants (`BILEV_*_HAND`/`JOINT_*_HAND`/`BILEV_GAP_FLOOR` in
`test/fixtures_planning.jl`; `INTERIOR_*_HAND`/`JOINT_*_HAND_INTERIOR`/
`GAP_FLOOR_INTERIOR`/`Z_GAP_FLOOR_INTERIOR`/`RHO_Y_*_HAND` self-contained in plan 29-04's
own file) and never touches, moves, or re-pins any pre-existing golden value.

## 8. `x_inv_max`/`d_max` never binding on the interior fixture (T-29-09)

Confirmed by direct inspection of `test/test_planning_certification_bilevel_interior.jl`'s
own header comment (section (c)): `x_inv_max=10.0`/`d_max=10.0` are "deliberately LARGE
relative to every quantity actually reached (never bind on this fixture, verified below)
— this sidesteps a known modeling gap (the production KKT's `statio_x` has no dual term
for `x_inv <= x_inv_max`, only for `x_inv <= y_inv`), by construction, not by fixing the
model." The fixture's own measured optima (`x_inv* ∈ {0.148 (bilevel), 0.2475 (joint)}`,
`z*/d* ∈ {1.48, 2.475}`) sit far below both `10.0` bounds, confirming the bound genuinely
never binds in either the production or joint reference solve. This is the deliberately
sidestepped KKT-completeness gap the plan's threat model (T-29-09) flagged as accepted,
not resolved, scope for this phase — a future phase extending `build_bilevel_kkt` to give
`statio_x` a dual term for the `x_inv <= x_inv_max` bound (currently only `x_inv <= y_inv`
is modeled) would need a fixture where that bound genuinely binds to exercise it.

## Full-suite certification

See the "Full-Suite Certification" section appended below once Task 2 completes.
