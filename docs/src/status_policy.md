# [Status & exception policy](@id status-policy)

Every entry point of the framework (`solve_admm`, `solve_stackelberg!`, `run_nash!`,
`run_mpc`, `run_stochastic`) follows one rule for the question "does this outcome throw, or
does it return a status?". This page is the single home of that rule.

## 1. The policy

**THROW** for:

- invalid inputs (`ArgumentError`);
- solver failures that make results untrustworthy (`SolveFailedError`);
- certificate refusals (`CertificateError`);
- genuine non-convergence (`ConvergenceError`).

**RETURN a status** for valid-answer outcomes: converged, a caller-set budget, the documented
MPC certificate tiers, and the documented stochastic skip-and-report.

## 2. Exception types

| Type | Role | Raised by |
|------|------|-----------|
| `TSODSOError` | abstract root of the hierarchy | (never raised directly) |
| `SolveFailedError` | solver result is untrustworthy (non-optimal termination, missing primal/dual point); carries `termination_status`, `primal_status`, `dual_status`, `raw_status` | `assert_solved!` and the retry/solve wrappers used by every entry point |
| `CertificateError` | an exactness / no-slack / complementarity certificate was refused; carries `kind::Symbol` | `assert_socp_exact!`, `assert_no_slack`, the planning certificates |
| `ConvergenceError` | an iterative method exhausted its budget without consensus; carries `iterations` | `solve_admm` (`maxiter`), `solve_stackelberg!` (`max_iter`, `:reject` stall), `run_nash!` |

Migration note: these replace the former `ErrorException` throws at the same sites. The
message text is byte-identical (`showerror` prints exactly `e.msg`); only the exception
**type** changed. `ErrorException` is a concrete struct, so a `SolveFailedError` is not an
`ErrorException`; internal catch sites that must treat both generations as solver failures use
the predicate `_is_solver_failure`.

## 3. Status vocabulary per entry point

The vocabulary below is rendered from `TSODSO.STATUS_VOCABULARY`, the same constant
`test/test_status_policy.jl` checks, so this table cannot drift from the code.

```@example status_policy
using TSODSO, Markdown
throws = Dict(
    :solve_admm => "ArgumentError, SolveFailedError, ConvergenceError",
    :solve_stackelberg => "ArgumentError, SolveFailedError, CertificateError, ConvergenceError",
    :run_nash => "ArgumentError, SolveFailedError, CertificateError, ConvergenceError",
    :run_mpc => "ArgumentError (inputs); tier failures are returned as :cert_failed",
    :run_stochastic => "ArgumentError, SolveFailedError (except INFEASIBLE held-out, skipped)",
)
rows = ["| entry point | `status` values | throws |", "|---|---|---|"]
for k in keys(TSODSO.STATUS_VOCABULARY)
    vals = join(("`:$(s)`" for s in TSODSO.STATUS_VOCABULARY[k]), ", ")
    push!(rows, "| `$(k)` | $(vals) | $(throws[k]) |")
end
Markdown.parse(join(rows, "\n"))
```

Meaning of the less obvious values: `:budget_exceeded` is the caller-set `time_limit_s` of
`solve_admm`; `:converged_relaxation_only` means the upper bound certifies only the SOC
relaxation; `:degraded` means a restricted/local-AC MPC step with none failed;
`:oos_infeasible_skipped` means a held-out stochastic scenario was skipped and reported.

## 4. Handler rule (ARCH-09)

Catch blocks are narrowed to the documented failure modes:

- the MPC tier handlers admit only `SolveFailedError` and `CertificateError`;
  `MethodError`, `BoundsError`, `ArgumentError`, `KeyError` and `InterruptException`
  propagate;
- the `run_stochastic` skip-and-report admits only a `SolveFailedError` on an INFEASIBLE
  status; anything else throws.

## 5. Inventory of what is not yet migrated (deferred)

**Remaining `ErrorException` modeling-bug asserts** (a failure here is a bug in the model or a
violated internal invariant, not a researcher-facing outcome; they stay `error(...)`):

- `_assert_epigraph_floor` and the corner-recourse bug checks in `src/planning/benders.jl`;
  `add_ll_cut!` `Q_nu` in `src/planning/master_integer.jl`;
- the feasibility-oracle failure, `:disagree` and weak-stall errors in `benders.jl`;
- `add_to_residual!` / `close_balance!` shape checks (`src/core/balance.jl`, the
  `ctx.residuals` size checks in `master.jl`, `subproblem.jl`, `feasibility_oracle.jl`,
  `bilevel_kkt.jl`, `mpc_loop.jl`, `nash.jl`);
- `welfare_accounting` (`src/pricing/welfare.jl`), the `fit_baseline` SITE-2 failure
  (`src/pricing/fit.jl`), the DLMP closure checks (`src/pricing/dlmp.jl`);
- `_mpc_assert_true_state_inband` and the AC truth-settlement non-convergence in
  `src/experiments/mpc_loop.jl`;
- the `run_nash!` lattice / parity / damped guards in `src/planning/nash.jl`;
- the `ModelContext` construction checks and the solver-factory configuration errors
  (`src/core/ModelContext.jl`, `src/solver/factory.jl`).

**Non-narrowed catch blocks** (inventoried only; narrowing is deferred): the planning
handlers widened to `_is_solver_failure` (`src/planning/retry.jl`, `benders.jl` four sites,
`coupling.jl`, `ac_recheck.jl`, `master.jl`, the `:report` swallow in `subproblem.jl`, the
`ALMOST_OPTIMAL` handler in `pricing/fit.jl`) and the attribute snapshot/restore in
`src/admm/DsoOpt.jl`.

## 6. The `has_reactive` rule

Reactive terms of aggregators on an active-only formulation (DC) are intentionally unclosed:
this is a documented degradation with no throw and no status, pinned by
`test/test_status_policy.jl`.
