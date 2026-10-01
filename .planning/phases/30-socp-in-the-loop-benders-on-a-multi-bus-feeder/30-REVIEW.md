---
phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder
reviewed: 2026-10-01T15:17:45Z
depth: standard
iteration: 3
files_reviewed: 17
files_reviewed_list:
  - src/planning/benders.jl
  - src/planning/nash.jl
  - src/planning/master.jl
  - src/planning/trace.jl
  - src/planning/ac_recheck.jl
  - src/planning/feasibility_oracle.jl
  - src/planning/subproblem.jl
  - test/test_planning_nash.jl
  - test/test_planning_inexact_policy.jl
  - test/test_planning_ac_recheck.jl
  - test/test_planning_alpha_bounds_stackelberg.jl
  - test/test_planning_master.jl
  - test/test_planning_benders_ieee13.jl
  - test/test_planning_feasibility_oracle.jl
  - docs/literate/integer_investment.jl
  - src/planning/master_integer.jl (call-chain only: add_ll_cut!/build_master_integer, needed to verify CR-02)
findings:
  critical: 0
  warning: 3
  info: 3
  total: 6
status: issues_found
---

# Phase 30: Code Review Report (iteration 3, final)

**Reviewed:** 2026-10-01T15:17:45Z
**Depth:** standard, plus call-chain tracing into `master_integer.jl` (`add_ll_cut!`, `build_master_integer`) to check the CR-02 validity argument
**Files Reviewed:** 17 (16 in scope, plus 1 traced call-chain file)
**Status:** issues_found

## Summary

This pass re-reviews the code after fix commits 12bfef2..22b7eb5. No blockers remain. The
items marked "requires human verification" were checked one by one:

1. **CR-02 (`_oracle_or_infeasible`).**
   - The classification is correct. Non-`ErrorException`s rethrow, and so do trusted-solve
     gate throws (exactness under `:throw`, complementarity) and non-infeasibility statuses.
   - The `:report` argument holds. Inexact and exact points both return the relaxation's
     value, so the corner search minimizes the convex function `Q_R` exactly, and
     `min Q_R ≤ min Q_true`.
   - A lower `Q_nu` gives a weaker Laporte-Louveaux (LL) cut **only while `Q_nu ≥ L`**. Two
     gaps remain, below:
     - that precondition is not enforced (WR-02);
     - the corner search maps `ALMOST_INFEASIBLE` to `+Inf` without the confirmation step
       the outer loop applies (WR-01).
2. **CR-01 (Nash).** Resolved.
   - `run_nash!` and `run_nash_probe` default to `:strict` and validate the policy before any
     solve. The policy is forwarded to every best response.
   - `certificates` and `any_relaxation_only` are populated from each returned result, after
     `_select_incumbent`, so the certificate matches the committed `z`.
3. **WR-01 (`_select_incumbent`).** Well-defined and honest.
   - `exact.UB ≥ relax.UB`. Near convergence the gap test is monotone in UB, so a converged
     certified point implies the loop's own test fires. Rule 2 cannot be starved.
   - `exact_incumbent.gap` pairs a true upper bound with a valid LB.
   - One cosmetic gap (IN-02): the trace's last row is not updated when the point is swapped.
4. **WR-02 (`:reject`).** Sound.
   - Relaxation cuts under-estimate `Q_R ≤ Q_true`, so appending them keeps LB valid. "Reject"
     still means the trial never reaches UB or the incumbent.
   - The stall backstop is correct for both master types. If the master re-proposes `z`
     after cuts that are tight at `z`, then `LB = c_y·y + Q_R(z)` is the cost of a feasible
     relaxed point, so that point *is* the relaxation optimum. This also holds for
     `BendersMasterInteger` with a different `b`.
   - Termination is guaranteed by `max_iter` (fail-loud). The backstop only shortens the
     period-1 repeat.
5. **WR-05 (`lb_slack`).** The proof in the `ALPHA_LB_REJECTION_TOL` docstring is correct:
   `cost_k ≥ optimum − gap − gap_k ≥ α − (S+gap) − tol_k`.
   - Yes, an over-high bound can now escape both layers. Any bound in
     `(true_min, optimum + S]` is accepted at build time, and by construction never fires at
     runtime.
   - Nothing accounts for its effect on LB (WR-03).
6. **WR-06 (`_feas_cut_class`).** A weak cut is still valid (convexity of `V`, `V = 0` on the
   feasible set).
   - The loop cannot cycle unboundedly: period-1 repeats are caught, and anything else ends at
     `max_iter`.
   - For `v` below the master's own ~1e-7 feasibility tolerance, though, a "weak" cut cannot
     exclude `z_k`. That sub-band is effectively a fatal error deferred by one iteration
     (IN-03).

Also verified:
- **WR-03 (`_incumbent_ac_report`).** The success and failure NamedTuples have identical
  field sets.
- **WR-04.** A docstring-only change, now accurate.
- **IN-02.** `solve_feasibility_oracle!` forwards `attempts_out` correctly.
- **IN-03.** The guards now reject unknown Symbols.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: The corner search maps `ALMOST_INFEASIBLE` to `+Inf` without the confirmation the outer loop requires, so a false infeasibility over-estimates `Q_nu` and makes the LL cut invalid

**File:** `src/planning/benders.jl:123-124`, `src/planning/benders.jl:280-289`, `src/planning/benders.jl:324-325`, `src/planning/benders.jl:475-476` (compare `src/planning/benders.jl:1346-1353`)

**Issue:**
- **Two different rules.**
  - The outer loop treats an oracle status in `ORACLE_INFEASIBLE_STATUSES` (which includes
    `ALMOST_INFEASIBLE`, a reduced-accuracy near-certificate) only as a *claim*. It confirms
    the claim with the slack-min oracle and raises a named "oracles disagree" error when
    `v ≤ FEAS_CUT_V_NOISE`. The comment at lines 120-122 calls that check "what actually
    confirms (or refutes, loudly)".
  - `_oracle_or_infeasible` has no confirmation step: any status in that tuple becomes
    `nothing`, which means `Q = +Inf`.
- **Its docstring is wrong.** It says it applies "the same classification
  `solve_stackelberg!`'s own outer oracle catch applies". It does not.
- **Over-estimating `Q_nu` is the dangerous direction.** A false `+Inf` is a feasible `z` that
  Clarabel flags `ALMOST_INFEASIBLE` after the retry ladder; it is most likely near the
  network boundary, where the welfare-maximizing import usually sits.
  - In the ternary branch it shrinks `hi = m2` and discards a region that may contain the
    minimizer.
  - In the joint branch it removes points from the minimization.
  - Either way the returned `Q_nu` is above the true corner minimum. `add_ll_cut!` then
    over-constrains θ at that corner permanently, because cut rows are never retracted.
  - This is the same failure class that iteration-2 CR-02 fixed for the bare `catch`, now
    narrowed to one status.

**Fix:** Treat only certified infeasibility as `+Inf` in the corner search. Either confirm
the claim with the slack-min oracle (thread `feas_oracle` through `ll_cut_recourse`), or
exclude the reduced-accuracy status:
```julia
const CORNER_INFEASIBLE_STATUSES =
    (MOI.INFEASIBLE, MOI.INFEASIBLE_OR_UNBOUNDED, MOI.LOCALLY_INFEASIBLE)

function _oracle_or_infeasible(oracle, z; on_inexact::Symbol, feas_oracle = nothing)
    return try
        solve_planning_oracle!(oracle, z; on_inexact = on_inexact)
    catch e
        e isa ErrorException || rethrow()
        is_solved_and_feasible(oracle.model; dual = true) && rethrow()
        ts = termination_status(oracle.model)
        ts in ORACLE_INFEASIBLE_STATUSES || rethrow()
        if ts == MOI.ALMOST_INFEASIBLE
            feas_oracle === nothing && rethrow()   # unconfirmed near-certificate: fail loud
            _feas_cut_class(solve_feasibility_oracle!(feas_oracle, z).v) === :disagree && rethrow()
        end
        nothing
    end
end
```
Then correct the docstring's "same classification" claim.

### WR-02: The CR-02 validity argument ("a weaker cut, never an invalid one") holds only when `Q_nu ≥ L`, and nothing enforces that; `add_ll_cut!`'s docstring math is also wrong

**File:** `src/planning/benders.jl:223-236` (the claim), `src/planning/master_integer.jl:208` (`L = α_op_lb + α_x_lb`, never validated), `src/planning/master_integer.jl:433-438` and `:473` (the cut)

**Issue:**
- **The cut and its precondition.** The cut is `θ ≥ (Q_nu − L)·D(b) + L`. At Hamming distance
  `k` from `b^ν`, `D = 1 − k`.
  - It is implied by `θ ≥ L` at every other corner **iff `Q_nu ≥ L`**.
  - If `Q_nu < L`, the cut raises θ's floor at every corner with `k ≥ 2` to
    `L + (k−1)(L − Q_nu) > L`. That is an invalid cut, not a weaker one.
- **The fix makes this easier to reach.** CR-02 deliberately makes `Q_nu` smaller under
  `:report` (the relaxation's per-corner minimum).
- **Nothing checks `L`.** For `BendersMasterInteger`, `L` is the sum of two explicit,
  never-validated bounds (`_accepted_lb_slack` returns 0 and `build_master_integer` has no
  `bounds_ctx`).
- **The runtime floor guard does not cover it.** It checks only the *iterate's*
  `−W_R(z_k)` against `α_op_lb` and `follower(z_k)` against `α_x_lb`. It never checks the
  corner *minimum* `Q_nu`, which sits at a different `z` and can be lower than every
  visited iterate.
- **So the claim is conditional.** "The integer cut stays valid" is true only under an
  unchecked precondition.
- **Docstring errors.** `add_ll_cut!`'s docstring says other corners have "`D <= -1`,
  reduces to `θ >= L - 2k(Q_nu - L)`". Both parts are wrong: `D = 0` at `k = 1`, and the
  reduction is `L − (k−1)(Q_nu − L)`.

**Fix:** Enforce the precondition where the cut is built, and fail loudly rather than add an
invalid row:
```julia
function add_ll_cut!(master::BendersMasterInteger, b_trial, Q_nu::Real, L::Real; atol = 1e-6)
    ...
    Q_nu >= L - atol * max(1, abs(L)) || error(
        "add_ll_cut!: Q_nu=$Q_nu < L=$L — the declared epigraph lower bound " *
        "α_op_lb + α_x_lb is not a valid lower bound on the per-corner recourse; " *
        "the LL cut would be INVALID at every corner with Hamming distance >= 2.")
    ...
end
```
Then correct the docstring reduction and state the `Q_nu ≥ L` precondition in
`corner_recourse`'s CR-02 paragraph.

### WR-03: WR-05 makes bounds in `(true_min, optimum + S]` invisible to BOTH layers, but the convergence certificate is not widened, so LB can exceed the true optimum by up to `S + gap` while `gap ≤ tol` is reported

**File:** `src/planning/master.jl:584-595`, `src/planning/master.jl:617-624`, `src/planning/master.jl:141-155` (the docstring proof), `src/planning/benders.jl:720`, `src/planning/benders.jl:1606-1609`

**Issue:**
- **The proof is right, and it is the problem.** The docstring itself says build time accepts
  bounds "that may sit up to `S + gap` above the TRUE minimum". The new runtime tolerance,
  `tol_k + lb_slack`, then guarantees such a bound never fires.
- **How LB is inflated.** At the true argmin `z*`, the master's `α_op` is floored at
  `α > −W_R(z*)`. So `LB = c_y·y + α + α_x` can exceed the true optimum by up to
  `(S_op + gap_op) + S_x`.
- **The certificate does not cover it.** The convergence test
  `(UB − LB)/max(1,|UB|) ≤ tol` does not account for this, so the reported gap can
  understate the true gap by `(lb_slack.op + lb_slack.x)/max(1,|UB|)`.
- **It can be as large as `tol`.** `S ≥ ALPHA_LB_REJECTION_TOL = 1e-6`, which equals the
  default `tol`. On any instance with `|UB| ≲ 1`, or with a caller-tightened `tol`, an
  accepted bound can therefore hide a true gap up to about 2×tol. This is reached silently,
  with no runtime signal.
- **Measured case.** On IEEE-13 T=4 the effect is about 2.5e-8 relative, which is harmless.
  That depends on the instance; the design does not guarantee it.

**Fix:** Make the build-time acceptance sound, not just consistent. Clamp an accepted explicit
bound to the derivation's certified lower bound, so it is never above the true minimum:
```julia
# master.jl, explicit-bound branch after the rejection check
α_eff = min(Float64(α_op_lb), d.optimum - alpha_lb_margin(d.optimum, d.gap))
α_eff < α_op_lb && @warn "build_master: α_op_lb=$α_op_lb lies within the acceptance slack " *
    "above the derived minimum; using the certified bound $α_eff" maxlog = 1
slack_op = 0.0   # the clamped bound is sound, so the runtime floor needs no slack
```
Alternatively, keep the bound as given and widen the certificate:
`converged_at(UBx) = (UBx − (LB_k − lb_slack.op − lb_slack.x)) / max(1, abs(UBx)) <= tol`.

## Info

### IN-01: Stale comments still describe `v > FEAS_CUT_V_TOL` as the only acceptance rule

**File:** `src/planning/benders.jl:117-122`, `src/planning/benders.jl:916-920`
**Issue:**
- The `ORACLE_INFEASIBLE_STATUSES` comment says the "`v > FEAS_CUT_V_TOL` check ... confirms
  (or refutes, loudly)".
- The `solve_stackelberg!` docstring says the cut "is appended only if `v > FEAS_CUT_V_TOL`"
  and then contradicts itself a few lines later with the WR-06 weak band.
- Since WR-06 the deciding threshold is `FEAS_CUT_V_NOISE`.

**Fix:** Reword both to the three-way `_feas_cut_class` rule.

### IN-02: When `_select_incumbent` swaps in the certified point, the trace's last row disagrees with the returned `UB`/`gap`

**File:** `src/planning/benders.jl:1570-1576`, `src/planning/benders.jl:1615-1630`
**Issue:** The optimality row is pushed with the relaxation `UB`/`gap` before
`_select_incumbent` runs. After a swap, `result.UB`/`result.gap` are the certified values, but
`last(result.trace.UB_trace)` is the relaxation-only one. `trace_summary`/`is_converged`
consumers then see a different certificate than the result.
**Fix:** Add an `incumbent_swapped::Bool` to the result, or document on the result that the
trace records the running-minimum UB, not the returned one.

### IN-03: The WR-06 "weak" band below the master's own feasibility tolerance is a deferred fatal error, not "the loop continues"

**File:** `src/planning/benders.jl:142-149`, `src/planning/benders.jl:157-164`, `src/planning/benders.jl:1354-1364`
**Issue:**
- For `FEAS_CUT_V_NOISE < v ≲ 1e-7` (HiGHS's primal feasibility tolerance), the appended cut
  `v + u'(z − z_k) ≤ 0` is satisfied at `z_k` within the master's tolerance. The master may
  return the same `z_k`, and the next iteration then raises the named stall error.
- Only `(~1e-7, 1e-6]` really degrades gracefully.
- The docstring presents the whole band as "the normal regime ... appended and the loop
  continues".

**Fix:** State the two sub-bands in `_feas_cut_class`'s docstring. Optionally classify
`v ≤ 10·(master primal tol)` as `:weak_nonseparating`, so the trace shows it.

---

_Reviewed: 2026-10-01T15:17:45Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
