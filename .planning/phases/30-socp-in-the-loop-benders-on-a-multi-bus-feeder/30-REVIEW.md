---
phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder
reviewed: 2026-10-01T14:05:47Z
depth: standard
iteration: 2
files_reviewed: 14
files_reviewed_list:
  - src/planning/feasibility_oracle.jl
  - src/planning/ac_recheck.jl
  - src/planning/benders.jl
  - src/planning/master.jl
  - src/planning/trace.jl
  - src/planning/subproblem.jl
  - test/fixtures_planning_ieee13_short.jl
  - test/test_planning_ac_recheck.jl
  - test/test_planning_alpha_bounds_stackelberg.jl
  - test/test_planning_benders_ieee13.jl
  - test/test_planning_feasibility_oracle.jl
  - test/test_planning_inexact_policy.jl
  - test/test_planning_master.jl
  - test/test_planning_oracle.jl
findings:
  critical: 2
  warning: 6
  info: 4
  total: 12
status: issues_found
---

# Phase 30: Code Review Report (iteration 2)

**Reviewed:** 2026-10-01T14:05:47Z
**Depth:** standard (plus targeted cross-file call-site tracing of `solve_planning_oracle!` / `solve_stackelberg!`)
**Files Reviewed:** 14
**Status:** issues_found

## Summary

This pass re-reviews the code after fix commits 2bdefc2..083f7c3. Most iteration-1 fixes
hold up when checked independently:

- **CR-01/CR-03.** `solve_planning_oracle!` now returns an explicit `exactness` verdict. The
  battery-complementarity gate runs on every result it returns, including `:report` results.
  `socp_relaxation_gap` is only read when an `:l` stash exists.
- **Return shape.** The change is additive (two new trailing NamedTuple fields). No caller in
  `src/`, `docs/` or `test/` destructures the result by position, so nothing breaks.
- **WR-01 catch block.** Only an untrusted solve with a status in
  `ORACLE_INFEASIBLE_STATUSES` reaches the feasibility branch. Everything else is rethrown.
- **WR-06.** The stall guard is correct.
- **WR-10.** Removing the second solve is correct: the incumbent's verdict comes from the
  solve that set UB.
- **WR-07.** The bracket is no longer circular. The lower side `LB − ε ≤ J*` really tests
  cut validity against an independent model.

Two problems remain at blocker level. Both concern the main question for this pass: can an
untrusted result still become a cut, UB or incumbent?

1. **Nash ignores the new certificate.** The default policy changed from "inexact means
   throw" (before Phase 30) to `:certify_incumbent`. The only production multi-distributor
   caller, `run_nash!`, never reads `ub_relaxation_only` or `incumbent_exactness`. A Nash
   sweep therefore silently commits relaxation-only best responses that used to fail loudly.
2. **The integer-master corner search bypasses the policy.** Its recourse search
   (`corner_recourse`) still calls the oracle in `:throw` mode. At T=1 it crashes under the
   default policy. At T>1 its bare `catch` turns any inexact or complementarity throw into
   `+Inf`. The minimum it returns is then too high, which can make the Laporte-Louveaux (LL)
   cut invalid.

The warnings cover:

- the incumbent comparison, which mixes exact and relaxation-only costs;
- `:reject`, which can never make progress;
- a post-convergence AC tooling failure, which discards a converged result;
- the meaning of `ac_report.ok`;
- a gap between the build-time rejection slack and the runtime floor tolerance;
- `FEAS_CUT_V_TOL`, which can wrongly stop the run near a curved feasibility boundary.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: `run_nash!` silently accepts relaxation-only best responses — the new default policy turned a loud failure into a silent one, and no production caller reads the certificate

**File:** `src/planning/benders.jl:826` (default `inexact_policy = :certify_incumbent`), `src/planning/benders.jl:1317-1358` (certificate only on the return value), `src/planning/nash.jl:475-489`

**Issue:**
- **Before Phase 30.** Every `solve_stackelberg!` call threw at the first SOCP-inexact
  oracle solve, because `solve_planning_oracle!` threw unconditionally.
- **Now.** The default `:certify_incumbent` accepts inexact iterates as cuts, as UB, and as
  the incumbent. It only flags this on the result: `ub_relaxation_only`,
  `incumbent_exactness`, `ac_report`.
- **Nash never sees the flags.** `run_nash!` (nash.jl:475) calls `solve_stackelberg!`
  without `inexact_policy`, so it gets the new default. It then reads only `result_i.z` and
  `result_i.follower`. A grep of `src/planning/nash.jl` and `coupling.jl` finds no reference
  to `ub_relaxation_only`, `incumbent_exactness` or `ac_report`.
- **Consequence.** A best response whose UB certifies only the SOC relaxation, and whose
  incumbent is physically unverified, is written into the shared model by `write_back!`. It
  feeds the Nash residual, and the returned equilibrium carries no marker that any part of
  it is relaxation-only.
- **This is the same bypass CR-02 was meant to close.** The certificate is honest on the
  `solve_stackelberg!` result, but the one production consumer drops it. The pre-Phase-30
  fail-loud guarantee for Nash is gone without notice.
- **Other callers.** `docs/literate/integer_investment.jl` (lines 289, 413) also inherits
  the new default and does not check the flags.

**Fix:** Do not change Nash's behaviour silently. Either pin the old behaviour, or carry the
certificate through:
```julia
# nash.jl, inside the sweep
result_i = solve_stackelberg!(spec.feeder, spec.pf, spec.aggregators;
    ...,
    follower = DistributorView(shared, i),
    inexact_policy = get(spec, :inexact_policy, :strict),   # preserve pre-Phase-30 semantics by default
)
result_i.ub_relaxation_only && error(
    "run_nash!: distributor $i best response (sweep $k) is SOCP-inexact " *
    "(incumbent maxgap=$(result_i.incumbent_socp_maxgap)); its UB certifies the " *
    "relaxation only. Pass inexact_policy=:certify_incumbent explicitly and record it.")
```
If certified-relaxation equilibria are meant to be allowed, add an `ub_relaxation_only`
column to `NashTrace` and a run-level flag on `run_nash!`'s return value.

### CR-02: The integer-master recourse path ignores `inexact_policy` — T=1 crashes under the default policy, T>1 silently computes an over-estimated `Q_nu` (invalid LL cut)

**File:** `src/planning/benders.jl:216` (`_corner_recourse_ternary`), `src/planning/benders.jl:349-356` (`_corner_recourse_joint`), `src/planning/benders.jl:1237`

**Issue:** `ll_cut_recourse(::BendersMasterInteger, ...)` runs on every optimality iteration,
after the outer loop has already accepted the iterate under the active `inexact_policy`. It
calls `corner_recourse`, which calls `solve_planning_oracle!(oracle, z)` with the default
`on_inexact = :throw`.

- **T == 1.** Any corner-search trial in the SOC-inexact region throws `"SOCP relaxation
  INEXACT"`. The whole run aborts under `:certify_incumbent`, the documented default. The
  policy is honoured for the outer trial and then ignored one call later.
- **T > 1.** The bare `catch` at line 351 turns the throw into `Qz = Inf, feas_cut =
  nothing`, i.e. "oracle-infeasible, no certificate". That covers inexact solves, real
  complementarity violations, and even `InterruptException`. The Kelley/bisection loop then
  minimizes `Q` only over the exact points. That minimum is at least the true
  `min_{z∈[0,y_inv]^T} Q(z)`, and strictly larger whenever the minimizer is in the inexact
  region. `add_ll_cut!` requires `Q_nu` to be the exact per-corner minimum; an over-estimate
  over-constrains θ at that corner permanently, because cut rows are never retracted. The
  run can then converge to a wrong integer solution with no error.

Before Phase 30, the outer loop crashed at the first inexact iterate, so this mismatch was
rarely reached. The new default makes it reachable.

**Fix:** Pass the policy into the recourse evaluator, and stop treating every exception as
"infeasible":
```julia
function _corner_recourse_joint(oracle, follower, y_inv, T; iters = 100, on_inexact = :throw)
    ...
    orr = try
        solve_planning_oracle!(oracle, z; on_inexact = on_inexact)
    catch e
        e isa ErrorException || rethrow()                      # never swallow InterruptException etc.
        is_solved_and_feasible(oracle.model; dual = true) && rethrow()   # gate failure, not infeasibility
        termination_status(oracle.model) in ORACLE_INFEASIBLE_STATUSES || rethrow()
        return (; Qz = Inf, gradQ = nothing, feas_cut = nothing)
    end
```
Apply the same change to `_corner_recourse_ternary`. Then call
`ll_cut_recourse(master, oracle, follower, lb_res, Q_nu_iterate; on_inexact = inexact_policy === :strict ? :throw : :report)`
from `solve_stackelberg!`.

## Warnings

### WR-01: Incumbent selection compares relaxation-only costs against certified costs, so an inexact iterate can displace an exact incumbent and downgrade the whole result to `ub_relaxation_only`

**File:** `src/planning/benders.jl:1245-1257`

**Issue:** `cost_k < UB` is evaluated the same way for exact and inexact iterates. For an
inexact iterate, `cost_k` uses `W_R(z_k) ≥ W_true(z_k)`, so it is a lower estimate of that
point's physical cost. An inexact iterate can therefore replace an exact incumbent whose
physical cost is lower than the inexact point's true cost.

The run then returns `ub_relaxation_only = true` and a relaxation-only `UB`. A physically
certified incumbent was found and is thrown away. The convergence test `gap <= tol` is also
measured against this relaxation UB, not the best certified one.

**Fix:** Track a separate exact incumbent (`UB_exact`, `y_best_exact`, `z_best_exact`)
updated only when `oracle_res.exactness !== :inexact`. Report both. When an exact incumbent
exists, prefer it for the returned `(y, z)` and for the certificate, or at least return it
alongside, so callers can choose a certified point.

### WR-02: `:reject` can never get past an inexact trial — it is `:strict` delayed by one iteration, under a misleading name

**File:** `src/planning/benders.jl:1128-1170`

**Issue:** A rejection adds no row to the master. The deterministic master LP re-proposes the
same `z` next iteration, and the WR-06 guard then raises `":reject stalled"`. So any run that
meets an inexact trial under `:reject` ends with an error after one wasted iteration. The
test confirms this (stall at iteration 8, 7 checkpoints). The docstring still describes it
as a policy that "skips the inexact trial".

A useful and sound version exists. The relaxation's cuts are valid lower bounds whatever the
exactness verdict, so they can be appended. Only the iterate's ability to become UB or the
incumbent needs to be blocked.

**Fix:** Under `:reject`, append the `:op`/`:x` optimality cuts (so the master moves on) but
skip the incumbent update and record `policy_action = :rejected`:
```julia
if oracle_res.exactness === :inexact && inexact_policy === :reject
    add_optimality_cut!(master, :op, -oracle_res.cost, oracle_res.π, lb_res.z)
    add_optimality_cut!(master, :x, follower_res.cost, follower_res.π_s, lb_res.z)
    # no UB / incumbent update; trace row cut_type = :rejected
    continue
end
```
Keep the stall guard as a backstop. If the current fail-fast behaviour is intended, rename
or document `:reject` as "`:strict` with one diagnostic iteration".

### WR-03: A post-convergence AC tooling failure throws away a converged Benders result

**File:** `src/planning/benders.jl:1318-1324`, `src/planning/ac_recheck.jl:105-117`

**Issue:** When the incumbent is inexact, `ac_recheck_incumbent` runs after convergence. If
Ipopt does not reach `LOCALLY_SOLVED`, it rethrows an `ErrorException`. `solve_stackelberg!`
does not catch it, so the converged result, trace and certificate are all lost, and the
diagnostic's tooling failure is reported as the run's failure. This contradicts the
solve_stackelberg! docstring (line 788: "NEVER thrown, never silently passed"). The AC
re-check is the slowest and least robust solve in the pipeline (Ipopt on a nonconvex model).

**Fix:** Catch at the call site and report the failure in `ac_report`:
```julia
ac_report = if ub_relaxation_only
    try
        ac = ac_recheck_incumbent(feeder, aggregators, λ₀, T, z_best)
        (; ac..., socp_welfare = incumbent_welfare, welfare_gap = incumbent_welfare - ac.ac_welfare)
    catch e
        e isa ErrorException || rethrow()
        (; ok = false, violations = nothing, p_import = nothing, ac_welfare = NaN,
           raw_status = "AC_RECHECK_FAILED", error = sprint(showerror, e),
           socp_welfare = incumbent_welfare, welfare_gap = NaN)
    end
else
    nothing
end
```

### WR-04: `ac_report.ok` and its docstring overclaim — a violation of a limits-DROPPED re-optimized dispatch does not show the incumbent is physically unrealizable

**File:** `src/planning/ac_recheck.jl:44-47`, `src/planning/ac_recheck.jl:131-171`

**Issue:** The AC model re-optimizes welfare with all thermal and voltage limits removed.
Since the optimizer is never told about the limits, it will cross any binding limit whenever
welfare improves by doing so. `ok = false` therefore only says that the limits-free AC
optimum violates a limit. It does not say that no AC-feasible dispatch exists at `z`.

The docstring says "A violation means the SOCP relaxation's answer at `z` is not physically
realizable as-is", which does not follow. It will raise false alarms at exactly the
incumbents that matter: those where a limit binds. The 10δ tolerance is fine as a noise
floor. The problem is what the check means, not how tight it is.

**Fix:**
- Make the check a real feasibility test. First solve `ACPowerFlow(; limits = true)` at the
  pinned `z`. `LOCALLY_SOLVED` there shows a limit-respecting AC dispatch exists, so set
  `ok = true`.
- Fall back to the limits-dropped model only for the diagnostic magnitudes.
- Reword the docstring to state that `ok = false` from the fallback is "not certified", not
  "not realizable".

### WR-05: The build-time rejection slack and the runtime floor tolerance differ, so an explicitly accepted bound can later fire the runtime "modeling bug" error

**File:** `src/planning/master.jl:556-557`, `src/planning/master.jl:587-588`, `src/planning/benders.jl:575-583`, `src/planning/benders.jl:1193-1198`

**Issue:**
- **Build time.** An explicit bound is accepted up to
  `optimum + max(1e-6, 10·gap_derive, 1e-8·|optimum|)`.
- **Runtime.** The floor fires when `cost_k < lb − max(1e-6, 10·gap_k, 1e-8·|cost_k|)`.
  Here `gap_k` is the pinned oracle's own gap, which is usually much smaller than the
  derivation solve's gap.
- **Worked example (IEEE-13 T=4, measured numbers from the fix report).**
  - Derivation: `gap_derive = 4.5e-6`, so the accepted slack is about `4.5e-5`.
  - Pinned solve: `gap_k ≈ 2.8e-7`, so the runtime tolerance is about `6.1e-6`.
  - An explicit bound at `optimum + 3e-5` passes the build-time check. If the master later
    visits the welfare argmax, where `cost_k ≈ optimum`, the runtime floor fires as a
    "genuine modeling bug (invalid declared lower bound)".
- **Root cause.** The true minimum is only known to lie in about `[optimum − gap,
  optimum + gap]`. Accepting bounds up to `optimum + 10·gap` accepts bounds that may be up to
  about 11·gap above the true minimum, i.e. genuinely invalid ones. The two checks disagree
  about what counts as valid.

The rejection can still catch a clearly over-high bound: the T=8 `-5.0` case is about 11
above the optimum. The `:auto` path, `optimum − margin`, is sound and cannot false-fire
unless solver error exceeds `10·gap_derive + 10·gap_k`.

**Fix:** Use one validity rule in both places. For example, accept an explicit bound only if
`α ≤ optimum + gap_derive` (the largest value that can still be the true minimum), and treat
anything between that and `optimum + slack` as "accepted with warning: may be invalid by up
to Δ". Alternatively, pass `gap_derive` into `_assert_epigraph_floor` and use
`max(tol_k, slack_derive)` so an accepted bound can never trip the runtime check.

### WR-06: `FEAS_CUT_V_TOL` turns a genuinely infeasible near-boundary trial into a fatal "oracles disagree" error

**File:** `src/planning/benders.jl:140`, `src/planning/benders.jl:1087-1094`

**Issue:**
- **Why small `v` happens.** Benders feasibility cuts are Kelley cuts on the convex
  slack-min value `V(z)`. After a cut, the master usually proposes a point on that cut's
  plane. Where `V` is curved (voltage-driven boundaries, coupled multi-hour boundaries),
  that point can still be infeasible, with `V` shrinking towards 0 on each successive cut.
- **What the code does.** Once a genuinely infeasible trial has `V ≤ 1e-6` while Clarabel
  still reports `INFEASIBLE`/`ALMOST_INFEASIBLE`, the loop raises a hard error instead of
  continuing.
- **Why the threshold is weakly grounded.** It is absolute, and `v` is a sum over `T` hours.
  It was checked against only three natural cuts (smallest 3.86e-5). The T=1 thermal case
  never reaches this regime only because `V` is linear there, so one cut is exact.

The guard correctly refuses to append a cut that does not separate `z_k`. Treating that
situation as fatal is the wrong response to a normal convergence regime.

**Fix:** Handle the boundary case instead of erroring. The slack-min solve returns a
`p_import` that is feasible to within `v`. Re-evaluate the oracle and follower at that
repaired point, `z_rep = value.(fo.p_import)`, and take the optimality branch there; cuts
from any feasible point are globally valid. Raise the "disagree" error only if the repaired
point also fails. At minimum, scale the threshold by `T` and record `v` on the trace row so
the regime can be measured.

## Info

### IN-01: Stale trace docstrings after CR-01/WR-01

**File:** `src/planning/trace.jl:61-62`, `src/planning/trace.jl:102-106`
**Issue:**
- `cut_type_trace` is documented as `:optimality` or `:feasibility`, but `:rejected` is also
  pushed.
- `:certified_incumbent` is still described as "the SOCP-inexact oracle throw was caught and
  the incumbent reconstructed from the already-solved model". After CR-01 there is no throw
  and no reconstruction.
- `:oracle_feasibility_cut` is described as "a genuine `MOI.INFEASIBLE`", but it is now any
  of the four `ORACLE_INFEASIBLE_STATUSES`.

**Fix:** Update all three descriptions.

### IN-02: `retry_count` and `solve_time` under-report on the new branches

**File:** `src/planning/benders.jl:1065-1112`, `src/planning/benders.jl:1165`
**Issue:**
- The `:oracle_feasibility_cut` row records `t_solve` from before `solve_feasibility_oracle!`
  runs, so that solve is never timed.
- That row's `retry_count` counts only the master's retries.
- The `:rejected` row ignores the oracle's retries (`oracle_attempts[] - 1`), even though the
  oracle solved successfully.

These rows break the trace docstring's claim of "GENUINE per-iteration retry count".
**Fix:** Bracket the feasibility-oracle solve with `time_ns()`, and add
`oracle_attempts[] - 1` on the `:rejected` row.

### IN-03: Dead type guards in `build_master`; an unknown Symbol raises `MethodError`, not `ArgumentError`

**File:** `src/planning/master.jl:521-530`
**Issue:** `α_op_lb isa Union{Symbol, Real}` is always true, because the keyword is already
typed that way. `α_op_lb = :atuo` (a typo) therefore skips every guard. It then reaches
`α_op_lb > d.optimum + slack` (a `MethodError` on `isless`) or `Float64(:atuo)`.
**Fix:** `(α_op_lb isa Real || α_op_lb === :auto) || throw(ArgumentError(...))`. Do the same
for `α_x_lb`.

### IN-04: Weak or tautological test assertions

**File:** `test/test_planning_inexact_policy.jl:358`, `test/test_planning_master.jl:316-323`, `test/test_planning_benders_ieee13.jl:149`
**Issue:**
- `rep.welfare_gap == rep.socp_welfare - rep.ac_welfare` restates the definition.
- The "beyond the slack" `@test_throws ArgumentError` checks never confirm which bound was
  rejected (no message match), so an unrelated `ArgumentError` would pass.
- `Jstar <= result.UB + ε` holds for any feasible UB against a global optimum. Only the
  `LB − ε ≤ J*` side tests the decomposition. This is acceptable, but the header should say
  so.

**Fix:** Match the error message (for example `occursin("α_op_lb", msg)`). Drop or replace
the tautological equality.

---

_Reviewed: 2026-10-01T14:05:47Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
