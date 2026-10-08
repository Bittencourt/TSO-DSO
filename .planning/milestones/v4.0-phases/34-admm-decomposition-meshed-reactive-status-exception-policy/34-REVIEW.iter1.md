---
phase: 34-admm-decomposition-meshed-reactive-status-exception-policy
reviewed: 2026-10-04T00:00:00Z
depth: standard
files_reviewed: 29
files_reviewed_list:
  - src/TSODSO.jl
  - src/core/errors.jl
  - src/core/status.jl
  - src/admm/admm_state.jl
  - src/admm/admm_phases.jl
  - src/admm/solve_admm.jl
  - src/admm/AgrOpt.jl
  - src/admm/DsoOpt.jl
  - src/experiments/mpc_loop.jl
  - src/experiments/run_stochastic.jl
  - src/experiments/strategies.jl
  - src/models/ac_oracle.jl
  - src/models/complementarity_4q.jl
  - src/models/exactness.jl
  - src/models/mesh_angle_certificate.jl
  - src/models/restriction_exactness.jl
  - src/models/welfare_solve.jl
  - src/planning/ac_recheck.jl
  - src/planning/benders.jl
  - src/planning/coupling.jl
  - src/planning/nash.jl
  - src/planning/retry.jl
  - src/planning/subproblem.jl
  - src/pricing/fit.jl
  - test/test_admm_generic_pf.jl
  - test/test_admm_meshed.jl
  - test/test_admm_phases.jl
  - test/test_status_policy.jl
  - test/test_tsodso_errors.jl
findings:
  critical: 0
  warning: 4
  info: 5
  total: 9
status: issues_found
---

# Phase 34: Code Review Report

**Reviewed:** 2026-10-04
**Depth:** standard (phase-34 diff `b955aa4..HEAD`, with the old monolithic `solve_admm` compared statement by statement)
**Files Reviewed:** 29
**Status:** issues_found

## Summary

The ADMM decomposition is faithful to the former monolith. I diffed the old loop against `_admm_iterate!`, `_adapt_rho!`, `_admm_certify` and the `_react_*` hooks and found these identical:

- statement order and `set_rho!` order;
- the LIVE stacked norms (`p_total = 2·p_p`);
- the independent ρ_q freeze and adaptation;
- the dual step, which now splits into two loops over independent variables;
- the certification pass.

State is carried across iterations correctly through `AdmmState` and `_LiveState`. `ρf` is read from `st.ρf` after mutation. The `μq`, `d`, `b` and `qag_dso_prev` snapshots are updated in the same order as before.

The typed exceptions have correct fields and `showerror` prints `msg`. The MPC and stochastic catch narrowing is sound. `InterruptException` is rethrown before the type filter, and `ConvergenceError` is deliberately excluded.

I found no correctness bug that changes behaviour on a tested path. The remaining issues concern the `_is_solver_failure` predicate being wider than the verdict it guards, a few typed-error migrations that were left inconsistent with the policy, and a few small robustness and type gaps.

## Warnings

### WR-01: `:report` swallow in `solve_planning_oracle!` catches far more than the inexactness verdict

**File:** `src/planning/subproblem.jl:355-360`
**Issue:** The only intended verdict is the cone-inexactness throw from `assert_socp_exact!`, which is now `CertificateError(kind = :socp_exact)`.

- The handler is `(_is_solver_failure(e) && on_inexact === :report) || rethrow()`, which accepts every `ErrorException`, `SolveFailedError`, `CertificateError` and `ConvergenceError`.
- Any legacy `error(...)` raised inside `assert_socp_exact!` or `socp_relaxation_gap` is therefore silently reclassified as `exactness = :inexact`. Examples are a shape guard or an internal invariant violation.
- Before the migration the verdict was the only `ErrorException` source, so the broad catch was tolerable. It is no longer needed now that the verdict has its own type.
- The comment above it (lines 282-284 and 358-359) was mechanically rewritten and reads "`assert_socp_exact!`'s ONLY a solver-failure exception ... is its inexactness verdict". It is garbled and no longer says what is intended.

**Fix:**
```julia
catch e
    (e isa CertificateError && e.kind === :socp_exact && on_inexact === :report) || rethrow()
```
Also repair the comment to: "its ONLY exactness verdict is `CertificateError(kind = :socp_exact)`".

### WR-02: `fit_baseline` retry keys on the exception message string instead of the typed status

**File:** `src/pricing/fit.jl:692`
**Issue:** The condition is `_is_solver_failure(e) && occursin("ALMOST_OPTIMAL", e.msg)`.

- `SolveFailedError` now carries `termination_status`, so string-matching `.msg` defeats the point of the typed exception.
- The predicate also admits `CertificateError` and `ConvergenceError`, whose messages could contain that substring (for example a SOCP-inexact message echoing a status).
- Such an error would then trigger the relaxed re-solve and mask the real failure.

**Fix:**
```julia
(e isa SolveFailedError && e.termination_status == MOI.ALMOST_OPTIMAL) ||
    (e isa ErrorException && occursin("ALMOST_OPTIMAL", e.msg)) || rethrow(e)
```
The legacy branch can be dropped once no source throws a plain `ErrorException` for this case.

### WR-03: `ac_recheck_incumbent` still downgrades a typed `SolveFailedError` to a plain `ErrorException`

**File:** `src/planning/ac_recheck.jl:119-130`
**Issue:** The catch is widened to `_is_solver_failure`, but the handler then discards the typed exception. It throws `ErrorException("ac_recheck_incumbent: AC power-flow re-check FAILED ...")`.

- This loses `termination_status`, `primal_status`, `dual_status` and `raw_status`.
- It also leaves a solver failure on the legacy type, against the stated policy (SolveFailedError means the solver result is untrustworthy).
- The same pattern appears in `mpc_loop.jl:1660` (AC truth-settlement non-convergence), which throws a plain `ErrorException` even though `model_t` statuses are at hand.
- `docs/src/status_policy.md` inventories the `mpc_loop` case but not the `ac_recheck` re-wrap.

**Fix:** Throw `SolveFailedError(msg, oracle_ac.model)` here. In `mpc_loop.jl:1660`, throw `SolveFailedError(msg, model_t)`. `_is_solver_failure` call sites keep working because the typed error is in the union. Update the policy page inventory.

### WR-04: `STATUS_VOCABULARY` and the ADMM battery warn-gate leave the sibling 4Q gate hard-failing on LinDistFlow

**File:** `src/admm/admm_state.jl:78`, `src/admm/AgrOpt.jl:321-323`
**Issue:** `_batt_on_violation` relaxes `assert_battery_complementarity!` to `:warn` for non-SOCP formulations (LinDistFlow), mirroring `welfare_solve.jl`. The 4Q peer certificate in the same final pass (`assert_4q_complementarity!`, called with `check_4q = has_4q`) has no equivalent switch and always throws `CertificateError(:four_quadrant)`.

- The rationale for warning on a lossless formulation is that there is no loss penalty discouraging simultaneous charge and discharge. It applies equally to a `FourQuadBESS`.
- The centralized `solve_welfare` path never calls the 4Q gate at all.
- A LinDistFlow ADMM run with a 4Q device can therefore fail hard where the centralized solve passes.
- The test `test_admm_generic_pf.jl` covers only the battery kwarg and does not exercise a 4Q device under LinDistFlow.

**Fix:** Either thread the same policy into `assert_4q_complementarity!` (it already has `report = true`, so pass `report = !(problem_class(pf) isa SOCP)`), or document and test that 4Q stays strict under non-SOCP formulations.

## Info

### IN-01: `AdmmState.exact_maxgap::Any` and a `Union{Nothing,_LiveState}` field weaken type stability

**File:** `src/admm/admm_state.jl:97,103`
**Issue:** `exact_maxgap::Any` holds `nothing`, `Float64` or `NaN`. The struct would be fully concrete with `Union{Nothing, Float64}`.

`react::Union{Nothing,_LiveState}` is accessed as `st.react.μq` and so on inside the LIVE hooks. JET may flag these as possible `getproperty(::Nothing)` calls, because the type is a union at inference time. The dispatch tag already proves it is non-`nothing`.

**Fix:** Use `exact_maxgap::Union{Nothing,Float64}`. In the LIVE hooks use `ls = st.react::_LiveState`, or write a small `_live(st)` accessor that asserts the type once.

### IN-02: `_mpc_status` returns `:certified` for an empty trace

**File:** `src/experiments/mpc_loop.jl:231-235`
**Issue:** `all(==(:certified_convex_dual), [])` is `true`, so an empty `cert_status_trace` yields `:certified` even though no step was certified. This is unreachable for `steps >= 1` today.

**Fix:** Add `isempty(cert_status_trace) && return :cert_failed`, or document and assert the precondition.

### IN-03: Remaining solver-failure and non-convergence throws in `benders.jl` are still plain `ErrorException`

**File:** `src/planning/benders.jl:590,680`
**Issue:** The `_corner_recourse_joint` cutting-plane master LP failure (line 590) is an untrustworthy solver result and should be `SolveFailedError`. The "exhausted iterations without meeting the gap" error (line 680) is non-convergence and should be `ConvergenceError`. The policy page lists the "corner-recourse bug checks" generically as modeling-bug asserts, which does not cover either of these.

**Fix:** Migrate both, or list them explicitly in the deferral inventory.

### IN-04: Test assertions that cannot fail

**File:** `test/test_tsodso_errors.jl:5`
**Issue:** `@test isconcretetype(ErrorException)` and `!(T <: ErrorException)` are compile-time facts about the type system. They verify nothing about the code under test. A test that matters here is that a `SolveFailedError` raised from a real `solve_with_retry!` exhaustion is caught by `_oracle_or_infeasible`. Another is that an `ArgumentError` at an MPC tier is not swallowed. I did not see either asserted at the call-site level.

**Fix:** Add behavioural tests at the widened and narrowed catch sites.

### IN-05: `Base.showerror` prints only `msg`, so the exception type is invisible in logs

**File:** `src/core/errors.jl:120`
**Issue:** This is deliberate (message text identical), but `tier_reasons` in `mpc_loop.jl` uses `sprint(showerror, err)`. The recorded reason for a `CertificateError` is then indistinguishable from a `SolveFailedError`. Consider prefixing the type name in `tier_reasons` only, which leaves the exception text untouched.

---

_Reviewed: 2026-10-04_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
