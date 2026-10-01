---
phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder
reviewed: 2026-10-01T12:56:55Z
depth: standard
diff_base: 97a3f36
files_reviewed: 16
files_reviewed_list:
  - src/planning/feasibility_oracle.jl
  - src/planning/ac_recheck.jl
  - src/planning/benders.jl
  - src/planning/master.jl
  - src/planning/trace.jl
  - src/TSODSO.jl
  - test/fixtures_planning_ieee13_short.jl
  - test/test_planning_ac_recheck.jl
  - test/test_planning_alpha_bounds_stackelberg.jl
  - test/test_planning_benders_ieee13.jl
  - test/test_planning_feasibility_oracle.jl
  - test/test_planning_ieee13_short_fixture.jl
  - test/test_planning_inexact_policy.jl
  - test/test_planning_master.jl
  - test/test_planning_noninteger.jl
  - docs/literate/stackelberg_benders.jl
findings:
  critical: 3
  warning: 10
  info: 7
  total: 20
status: issues_found
---

# Phase 30: Code Review Report

**Reviewed:** 2026-10-01T12:56:55Z
**Depth:** standard (scoped to `git diff 97a3f36`)
**Files Reviewed:** 16
**Status:** issues_found

## Narrative Findings (AI reviewer)

## Summary

The core math holds up in three places:

- **Feasibility cut (BILEV-04a).** `V(z) = min ‖s‖₁` is convex in `z`, because `z` only
  enters the right-hand side of a linear equality in a convex program. JuMP's constraint
  `p_import − s⁺ + s⁻ − z == 0` has the parameter `z` on the right-hand side, so under JuMP's
  dual convention (for a Min problem, the dual equals ∂obj/∂rhs) `π = ∂V/∂z`. That makes
  `u = +π` the correct sign. The cut `v + u'(z − z_k) ≤ 0` is therefore a valid supporting
  hyperplane and cannot remove a z that is feasible for the relaxation. True-AC-feasible z
  form a subset of relaxation-feasible z, so it cannot remove those either. When the
  slack-min oracle's own relaxation is inexact, V_relaxed ≤ V_true, so the cut is weaker but
  still valid.
- **Optimality cuts from an inexact relaxation.** These are valid under-estimators of both
  `−W_R` and `−W_true`, because `W_R ≥ W_true`. The LB stays valid.
- **`derive_alpha_op_lb`.** Freeing the pin over `p_import ∈ [0, y_max]^T` gives
  `−W*_box ≤ −W(z)` for every z in the master's box (`z ≤ y_inv ≤ y_max`), and the bound
  stays valid when the box SOCP is itself inexact.

The defects are in the policy plumbing, in reporting and certification, and in
tolerance/test hygiene:

- The default `:certify_incumbent` path skips the battery-complementarity gate entirely.
- An inexact incumbent produces a "converged" UB/gap that only holds for the relaxation. The
  AC report always says `ok = true`.
- The exactness disambiguation (based on whether `:socp_maxgap` is present) is wrong for
  every formulation that does not stash `:l`.
- The cross-check tolerance in the IEEE-13 test is a frozen literal, 10× the run's own
  UB−LB. The test checks the Benders certificate against itself, inflated, instead of
  bracketing the joint optimum.

30-FINDINGS.md §3 says the populated `ac_report` path "IS exercised end-to-end through
`solve_stackelberg!` by `test_planning_inexact_policy.jl`'s `:certify_incumbent` item". That
is false: that item asserts `result.ac_report === nothing` (line 198). No test drives the
populated-report path through `solve_stackelberg!`.

## Critical Issues

### CR-01: `:certify_incumbent` (the DEFAULT) silently bypasses the battery-complementarity gate

**File:** `src/planning/benders.jl:1068-1079` (with `src/planning/subproblem.jl` `solve_planning_oracle!`)
**Issue:** `solve_planning_oracle!` runs `assert_socp_exact!` and then
`assert_battery_complementarity!`. When the exactness gate throws, the complementarity gate
never runs. The `:certify_incumbent` branch rebuilds `(cost, π, π_s, dadp)` straight from the
model and continues with "as if it had returned normally". As a result:

- an optimality cut is appended from that model;
- the UB can be updated from it;
- it can become the incumbent;

and none of this has passed the App. C complementarity check. The project treats that check
as mandatory: a degenerate `p_ch·p_dch` co-activation makes `π` physically meaningless
(threat T-03-13). Two facts make this worse:

- Pinned off-optimal z is exactly where co-activation is most likely, and the inexact pins
  sit at the edge of the feasible region.
- The Literate T=24 section documents that a real complementarity violation happens on this
  same population at larger `y_max`.

The comment "the underlying solve IS trustworthy" is therefore false.
**Fix:** In the reconstruction branch, run the complementarity gate before accepting the
result, and propagate its error unchanged:
```julia
else   # :certify_incumbent
    assert_battery_complementarity!(oracle.ctx;
        τ = (get(oracle.ctx.meta, :problem_class, nothing) isa SOCP ? 1e-3 : 1e-6),
        T = oracle.T)                      # never skipped
    π = dual.(oracle.pin)
    ...
```
A better fix is to factor `solve_planning_oracle!`'s post-solve gates and its return-tuple
assembly into one helper, `_oracle_result(o; Δt)`, that both paths call. Then the
reconstruction cannot drift away from the real path.

### CR-02: An inexact incumbent returns a "converged" UB/gap that is only a relaxation value, and `ac_report.ok` is always `true`

**File:** `src/planning/benders.jl:1144-1150, 1209-1254`; `src/planning/ac_recheck.jl:141-146`
**Issue:** On a `:certify_incumbent` iterate,
`cost_k = c_y·y + F(z) − W_R(z)`, which is **≤** the true cost because `W_R ≥ W_true`. It can
become `UB`/`z_best`. When it does:

1. `UB` is not an upper bound on the true problem. `gap ≤ tol` certifies only the relaxation,
   yet the result is returned exactly like a certified convergence. `converged_via` still
   reads `:clean`, and there is no `incumbent_exact` or `UB_trusted` field.
2. `ac_recheck_incumbent` hard-codes `ok = true` (line 142), even when `n_thermal_violations
   > 0`. `test_planning_ac_recheck.jl:56` locks that in by asserting `r.ok` next to
   `n_thermal_violations > 0`. Any caller that writes
   `res.ac_report === nothing || res.ac_report.ok` passes a physically violating incumbent.
   That is the "silently passed" outcome CONTEXT.md forbids.
3. The report never compares AC welfare at `z_best` with the SOCP `W_R(z_best)`, so how far
   UB is off is never measured.

No test covers this end-to-end. Every `solve_stackelberg!` test asserts
`ac_report === nothing`, which contradicts 30-FINDINGS.md §3.
**Fix:** Return an explicit certificate, and have `ok` reflect the violations:
```julia
ok = n_thermal == 0 && n_voltage == 0
return (; ok, violations, p_import = [value(oracle_ac.p_import[t]) for t in 1:T],
        ac_welfare = objective_value(oracle_ac.model), raw_status = raw_status(oracle_ac.model))
```
In `solve_stackelberg!`, add `incumbent_exact::Bool` and `incumbent_socp_maxgap` to the
result. Document that `UB`/`gap` are relaxation-certified only when
`incumbent_exact == false`. Alternatively, never let a `:certified_incumbent` iterate update
`UB`: keep its cut but leave the incumbent alone. That restores `UB` validity at no cost to
LB soundness. Add an end-to-end test whose incumbent really is inexact, and correct
30-FINDINGS.md §3.

### CR-03: The exactness-vs-other-throw disambiguation is wrong for formulations without an `:l` stash, so the original error is replaced by a FieldError

**File:** `src/planning/benders.jl:1021-1079`
**Issue:** The rule "`:socp_maxgap` absent ⇒ the exactness gate threw" holds only when
`solve_planning_oracle!` actually runs the exactness gate, i.e. when `pf_vars` has `:l`. For
LinDistFlow (`pf_vars = (; v, P, Q)`, `src/powerflow/LinDistFlow.jl:97`) and DC, the key is
**never** set. Any post-solve `ErrorException`, for example from
`assert_battery_complementarity!` (τ=1e-6 on the QP path), is then classified as an
exactness failure:

- Under `:certify_incumbent` (the default) and under `:reject`, the branch calls
  `socp_relaxation_gap(oracle.ctx)`. That reads `pv.l` and raises `FieldError: type
  NamedTuple has no field l` (confirmed on Julia 1.12.5). The real complementarity diagnosis
  is lost.
- Before this phase, the original error propagated with its own message. The docstring
  promises that non-exactness throws are "propagated unchanged". That promise is broken.
- If a future formulation stashes `:l` but its exactness path differs, the same structural
  flaw would let a non-exactness throw be policy-accepted silently.

**Fix:** Do not infer the cause from a side-effect key. Either have `assert_socp_exact!`
throw a dedicated `SocpInexactError <: Exception` and catch only that, or have
`solve_planning_oracle!` record `ctx.meta[:gate_failed] = :exactness` right before
rethrowing. At minimum, guard the branch:
```julia
elseif haskey(oracle.ctx.meta, :socp_maxgap) ||
       !(haskey(oracle.ctx.meta, :pf_vars) && haskey(oracle.ctx.meta[:pf_vars], :l))
    rethrow()   # exactness gate cannot have been the thrower
```

## Warnings

### WR-01: Any failed oracle solve is routed to an oracle feasibility cut and labelled `:genuinely_infeasible`, with no check that the cut separates z_k

**File:** `src/planning/benders.jl:982-1020`
**Issue:** `!is_solved_and_feasible(...)` is also true after the retry ladder is exhausted on
`SLOW_PROGRESS`, `ITERATION_LIMIT`, `NUMERICAL_ERROR` or `ALMOST_*`, and on the
foreign-backend attribute error path. In all of these cases:

- The trace hard-codes `oracle_status = :genuinely_infeasible` (line 1015), which can be
  wrong.
- At a z_k that is actually feasible, `fo_res.v ≈ 1e-9` and `u ≈ 0`. The appended
  "cut" `1e-9 ≤ 0` is either accepted within HiGHS tolerance, in which case the master
  re-proposes the same z_k until `max_iter` is exhausted, or it makes the master infeasible.
  Either way the diagnosis is wrong.
- The same stall happens at a genuinely infeasible z_k sitting within ~1e-7 of the
  threshold, because `v/‖u‖` falls below the master's feasibility tolerance.

**Fix:** Branch only on `termination_status(oracle.model) in (MOI.INFEASIBLE,
MOI.INFEASIBLE_OR_UNBOUNDED, MOI.LOCALLY_INFEASIBLE)` and rethrow on anything else. Record
the real status, `Symbol(termination_status(oracle.model))`. After
`solve_feasibility_oracle!`, require `fo_res.v > FEAS_CUT_V_TOL` (a measured value);
otherwise raise a named error saying the oracle and feasibility oracle disagree.

### WR-02: "Always feasible by construction" is an overclaim, and a feasibility-oracle failure masks the original error

**File:** `src/planning/feasibility_oracle.jl:8-11, 172-176, 221-223`; `src/planning/benders.jl:992`
**Issue:** The slack only frees `p_import`. If no `p_import` value makes the network and
device constraints feasible, the slack-min model is infeasible too. Examples: an
import-independent voltage violation, or device minimums that cannot be met.
`solve_with_retry!` then throws from inside the oracle's `catch` block, and the user sees a
feasibility-oracle solve failure instead of the original infeasibility.
**Fix:** Correct the docstrings: the model is feasible iff some `p_import` admits the network.
Wrap line 992 in a `try` that rethrows with both errors and names `z_k`.

### WR-03: The build-time rejection threshold has zero tolerance, because margin and tolerance cancel exactly

**File:** `src/planning/master.jl:98, 110, 234, 308, 455, 483`
**Issue:** `derived = obj − ALPHA_LB_MARGIN`, and rejection fires when
`α > derived + ALPHA_LB_REJECTION_TOL`. Both constants are `1e-6`, so the threshold equals
the raw solver optimum `obj`. A user bound equal to the true minimum is rejected whenever the
solver reports `obj` slightly low. The FINDINGS audit shows `α_x_lb = 0.0` is accepted only
because `-1e-6 + 1e-6 == 0.0` in floating point and HiGHS returns exactly `0`. The
"rejection tolerance" therefore provides no tolerance at all.
**Fix:** Validate against the un-margined optimum:
`α > (derived + margin) + rejection_tol`. Better, have the derive functions return
`(; optimum, bound = optimum − margin)` and compare against `optimum + rejection_tol`.

### WR-04: The α-bound margin and runtime-floor tolerance are absolute, toy-measured and not scale-aware, yet are applied to IEEE-13 SOCP

**File:** `src/planning/master.jl:82-110`; `src/planning/benders.jl:545-558, 1098-1099`
**Issue:** `1e-6` was measured on a T=1 two-bus LinDistFlow toy with a duality gap of
`2.85e-9`. It is now applied unconditionally to `ConvexBranchFlow` IEEE-13 runs. At T=4,
|W|≈609 and the measured Clarabel duality gap is 2.79e-7, which leaves about 3.6× headroom.
At T=24, or for larger |W|, Clarabel's relative gap tolerance produces absolute errors above
the combined 2e-6 slack.

With `:auto` and near-zero investment costs, the iterates approach the box argmax. There the
true `−W(z_k) − (−W*_box) → 0`, so `_assert_epigraph_floor` can fire as a "genuine modeling
bug" on pure solver noise. This contradicts the project rule "measure comparison epsilons,
don't pick them" for the instances these constants actually run on.
**Fix:** Make the margin relative to the derive solve's own measured gap, for example
`margin = max(1e-6, 10·|obj − dual_objective_value|, 1e-8·|obj|)`, computed at derivation
time. Use the same scale-aware tolerance in `_assert_epigraph_floor`. Re-measure on the
IEEE-13 T=4 and T=24 fixtures.

### WR-05: `socp_maxgap` is discarded on every exact iteration, contradicting CONTEXT and the trace docstring

**File:** `src/planning/benders.jl:973, 1186-1187`; `src/planning/trace.jl` (field docstring); `docs/literate/stackelberg_benders.jl` (cone-gap panel)
**Issue:** `solve_planning_oracle!` stores the measured gap in `oracle.ctx.meta[:socp_maxgap]`
on every successful SOCP solve, but the loop records `socp_maxgap_k = NaN` unless the policy
branch fired. As a result:

- CONTEXT.md asks for a per-iteration `socp_maxgap` and for "report the cone gap at the
  incumbent". The incumbent's gap is not returned at all.
- The trace docstring says the value is recorded when the gate "passed with a nonzero
  residual". The code does not do that.
- The Literate "incumbent cone-gap" panel is empty by construction, yet the prose presents
  this as "a genuine, positively-confirmed result".
- `test_planning_benders_ieee13.jl:157` (`all(isnan, ...)`) is vacuous for the same reason.
- `n_inexact_iterations` currently works only because of the NaN sentinel. Once gaps are
  recorded it must count `policy_action ∈ (:certified_incumbent, :rejected)` instead.

**Fix:** Record `get(oracle.ctx.meta, :socp_maxgap, NaN)` on success rows. Return the
incumbent's measured gap. Change `n_inexact_iterations` to count by `policy_action`, and
update the Literate prose and the IEEE-13 assertion to check measured gaps.

### WR-06: `:reject` deterministically burns the entire remaining iteration budget

**File:** `src/planning/benders.jl:1031-1067`
**Issue:** Rejecting adds no cut and changes no master state, so the next `solve_master!`
returns the identical trial. The test confirms this, and it is documented as T-30-09. Once
`:reject` fires, every remaining iteration is wasted: a full oracle SOCP solve plus a JLD2
checkpoint each. The run ends with a generic "exhausted" error that hides the cause.
**Fix:** Detect the repeat (same `lb_res.z` as the last rejected trial, within tolerance) and
throw immediately with a named "`:reject` stalled at inexact z=…" error. Alternatively,
document `:reject` as fail-fast.

### WR-07: The cross-check tolerance is a frozen, partly circular literal that is 10× looser than the certificate it checks, and its derivation is not reproducible

**File:** `test/test_planning_benders_ieee13.jl:44-71, 142-143`; `test/fixtures_planning_ieee13_short.jl:215-222`
**Issue:**
- `measured_crosscheck_atol = 10·(UB−LB)` comes from the Benders run's own output and is then
  frozen as a literal. It is a picked number dressed as a measurement. If a future run's
  UB−LB changes, the tolerance does not follow.
- Benders already certifies `J* ∈ [LB, UB]` when its cuts are valid. Allowing ±10·(UB−LB)
  around UB is strictly weaker than the claim being tested.
- The header's "`joint.gap`" (source 2) does not exist, because `solve_joint_reference`
  returns only `(y, x_inv, z, welfare_total)`.
- The joint reference uses `dual = false` and never checks its own cone exactness. It is a
  relaxation-to-relaxation comparison.
- The joint model is independent of the decomposition, which is good. It shares the
  `contribute!` builders, though, so it cannot catch formulation-level errors. That is
  acceptable, but it should be stated.

**Fix:** Assert the bracket with runtime-measured solver gaps:
```julia
ε = 10 * max(oracle_gap, joint_gap)   # both computed in-test from objective/dual_objective
@test result.LB - ε <= -joint.welfare_total <= result.UB + ε
```
Return `gap = abs(objective_value(model) - dual_objective_value(model))` from
`solve_joint_reference` (this needs `dual = true`), and run `socp_relaxation_gap` on the
joint model. With the documented numbers, J* ≈ 609.01120 lies inside [609.01116, 609.01135],
so the bracket test passes without the 10× slack.

### WR-08: No test pins the sign or validity of the feasibility cut

**File:** `test/test_planning_feasibility_oracle.jl:159-175, 220-233`
**Issue:** The unit items assert `cost > 1e-6`, `v == cost`, `length(u) == T`, and
"row count +1". All of these hold for `u = −π`, which is exactly the sign the docstring warns
about. Nothing checks that the cut excludes `z_k` or keeps a known-feasible z.
**Fix:** Add assertions such as
`r.v + r.u' * (z_feasible - r.z_k) <= 1e-8` (for example with `z_feasible = [0.02]`, which
the docstring map lists as feasible) and `r.v > 0` at `z_k`. Then solve the master after the
cut and assert `value.(master.z)` respects it.

### WR-09: The AC re-check re-optimizes dispatch instead of evaluating the incumbent, and reports `p_import` for hour 1 only

**File:** `src/planning/ac_recheck.jl:75-85, 144`
**Issue:**
- The AC model is a fresh welfare maximization at pinned z. Its violations describe "some
  AC-optimal dispatch at z_best", not the SOCP incumbent's dispatch or prices. The docstring
  presents it as the incumbent's physics check.
- `p_import = value(p_import[1])` drops hours 2…T for every T>1 run, including the phase's
  own T=4 and T=24 runs.
- `z_incumbent` has no length guard.

**Fix:** Document clearly what is being checked. Return the full `p_import` vector and the AC
objective (see CR-02). Add `length(z_incumbent) == T || throw(ArgumentError(...))`.

### WR-10: The incumbent re-check at convergence ignores `inexact_policy` and is affected by sticky retry attributes

**File:** `src/planning/benders.jl:1209-1224`
**Issue:** The convergence re-solve at `z_best` runs on a model whose Clarabel attributes may
have been escalated by earlier `solve_with_retry!` calls (escalation is sticky). Its verdict
can therefore differ from the original solve's. If the re-check comes back inexact under
`:strict`, the code produces an `ac_report` instead of throwing, which violates `:strict`'s
contract. Under `:reject`, an inexact re-check means the incumbent came from a run that
`:reject` should have excluded, and it is reported as a normal convergence.
**Fix:** Under `:strict`, rethrow on an inexact re-check. Under `:reject`, error out. Only
`:certify_incumbent` should produce an `ac_report`.

## Info

### IN-01: Dead type checks, and non-`:auto` symbols raise a MethodError instead of an ArgumentError

**File:** `src/planning/master.jl:423-432, 462-465, 489-495`
**Issue:** The keywords are already typed `Union{Symbol,Real}`, so the `isa` guards can never
fail. `α_op_lb = :Auto` (a typo) reaches `Float64(:Auto)` and throws a `MethodError`.
**Fix:** Replace the guards with
`α_op_lb isa Real || α_op_lb === :auto || throw(ArgumentError(...))`.

### IN-02: The reconstruction duplicates `solve_planning_oracle!`'s return logic and hard-codes Δt=1

**File:** `src/planning/benders.jl:1073-1078`
**Issue:** `π_s = sum(π)` silently ignores the `Δt` weighting the real path applies.
**Fix:** Use a shared helper (see CR-01).

### IN-03: The PVAL-04 tripwire is evaded by naming

**File:** `src/planning/master.jl` (`make_relaxed_*`); `test/test_planning_noninteger.jl:24-34`
**Issue:** Choosing names that avoid the `build_\w+` regex weakens the tripwire's coverage.
**Fix:** Register these builders in the no-binaries check instead. They are cheap.

### IN-04: `ac_report === nothing` mixes "not a SOCP" with "exact"

**File:** `src/planning/benders.jl:1246-1253`
**Issue:** For LinDistFlow and DC, `nothing` means "not checked", not "certified exact".
**Fix:** Add an `incumbent_exactness ∈ (:exact, :inexact, :not_applicable)` field.

### IN-05: The sweep map covers only uniform z, but the tests claim a non-uniform "exact window"

**File:** `test/fixtures_planning_ieee13_short.jl:46-58`; `test/test_planning_benders_ieee13.jl:145-155`
**Issue:** The incumbent `z = [0.001, 0, 0, 0.05]` is non-uniform. The window claim is not
established for such points. Exactness was actually enforced by the gate, so only the prose
is wrong.

### IN-06: Weak or vacuous test assertions and test hygiene

**File:** `test/test_planning_inexact_policy.jl:184`; `test/test_planning_benders_ieee13.jl:157-158`; `test/test_planning_alpha_bounds_stackelberg.jl:131-142`
**Issue:**
- `all(g -> g > 0, finite_gaps)` is trivially true.
- Line 158 allows `:certified_incumbent`, but line 157 already forbids it.
- The final `@test_throws` omits `checkpoint_dir`, so a regression would write into the
  repo's `datadir("planning_checkpoints")`.
- The `@test_throws ArgumentError` items do not check the message, so any unrelated
  `ArgumentError` would satisfy them.

### IN-07: The feasibility-cut sign is justified only empirically

**File:** `src/planning/feasibility_oracle.jl:187-207`
**Issue:** The sign follows directly from JuMP's dual convention: for a Min problem with
`rhs = z`, `π = ∂V/∂z`. Recording that derivation would make the sign independent of the
single T=1 probe.

---

_Reviewed: 2026-10-01T12:56:55Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
