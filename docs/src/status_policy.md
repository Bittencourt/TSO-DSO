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
MPC certificate tiers, and the documented stochastic skip-and-report (infeasible or inexact
held-out draws).

## 2. Exception types

| Type | Role | Raised by |
|------|------|-----------|
| `TSODSOError` | abstract root of the hierarchy | (never raised directly) |
| `SolveFailedError` | solver result is untrustworthy (non-optimal termination, missing primal/dual point); carries `termination_status`, `primal_status`, `dual_status`, `raw_status` | `assert_solved!` and the retry/solve wrappers used by every entry point |
| `CertificateError` | an exactness / no-slack / complementarity certificate was refused; carries `kind::Symbol` | `assert_socp_exact!`, `assert_no_slack`, the planning certificates |
| `ConvergenceError` | an iterative method exhausted its budget without consensus; carries `iterations` | `solve_admm` (`maxiter`), `solve_stackelberg!` (`max_iter`, `:reject` stall), `run_nash!` |

Migration note: these replace the former `ErrorException` throws at the same sites. The
message text is bit-for-bit identical (`showerror` prints exactly `e.msg`); only the exception
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
    :run_stochastic => "ArgumentError, SolveFailedError, CertificateError (in-sample); held-out INFEASIBLE or inexact draws are skipped and reported",
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
`:oos_infeasible_skipped` means a held-out stochastic scenario was skipped and reported;
`:oos_inexact_skipped` means at least one held-out re-solve failed the shared SOCP exactness
gate (`CertificateError` of kind `:socp_exact`); that draw keeps its welfare value in
`welfare_h` but is flagged in `inexact_h` and excluded from `realized_welfare`/`welfare_gap`;
it takes precedence over `:oos_infeasible_skipped`, and the masks carry the full detail.

## 4. Handler rule

Catch blocks are narrowed to the documented failure modes:

- the MPC tier handlers admit only `SolveFailedError` and `CertificateError`;
  `MethodError`, `BoundsError`, `ArgumentError`, `KeyError` and `InterruptException`
  propagate;
- the `run_stochastic` skip-and-report admits only a `SolveFailedError` on an INFEASIBLE
  status or a `CertificateError` of kind `:socp_exact` raised by the held-out step; anything
  else throws.

## 5. Inventory of what is not yet migrated (deferred)

**Remaining `ErrorException` modeling-bug asserts** (a failure here is a bug in the model or a
violated internal invariant, not a researcher-facing outcome; they stay `error(...)`):

- `_assert_epigraph_floor` and the corner-recourse non-finite bug checks in `src/planning/benders.jl`
  (the `_corner_recourse_joint` master-LP failure is a `SolveFailedError` and its iteration
  exhaustion a `ConvergenceError`);
  `add_ll_cut!` `Q_nu` in `src/planning/master_integer.jl`;
- the feasibility-oracle failure, `:disagree` and weak-stall errors in `benders.jl`;
- `add_to_residual!` / `close_balance!` shape checks (`src/core/balance.jl`, the
  `ctx.residuals` size checks in `master.jl`, `subproblem.jl`, `feasibility_oracle.jl`,
  `bilevel_kkt.jl`, `mpc_loop.jl`, `nash.jl`);
- `welfare_accounting` (`src/pricing/welfare.jl`), the DLMP closure checks
  (`src/pricing/dlmp.jl`); the `fit_baseline` AC-PF non-convergence
  (`src/pricing/fit.jl`) is a `SolveFailedError`;
- `_mpc_assert_true_state_inband` in `src/experiments/mpc_loop.jl` (the AC
  truth-settlement non-convergence and the `ac_recheck_incumbent` re-check failure are
  `SolveFailedError`, carrying the solver statuses);
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

## 7. Breaking changes

This release trims the API surface and removes several deprecated forms. Everything below
fails loudly instead of silently changing behavior.

- **Orchestration keywords.** `operational_oracle` no longer accepts the keywords
  `objective_hook`, `horizon_state` and `z`; passing any of them raises a `MethodError`.
- **Reactive mode.** `ReactiveMode` is now a module. The only accepted values are
  `ReactiveMode.OFF`, `ReactiveMode.CERTIFIED` and `ReactiveMode.LIVE` (type
  `ReactiveMode.T`). The earlier `Bool` and `Symbol` forms raise an `ArgumentError`, and the bare
  names `OFF`, `CERTIFIED`, `LIVE` and `normalize_reactive_mode` are no longer exported.
- **Unexported names.** The exported surface shrank from 192 names to 90. The removed names
  are reached as `TSODSO.name` or `using TSODSO: name`. They fall into these groups: the
  problem-class singletons (`LP`, `QP`, `SOCP`, `NLP`, `MILP`), optimizer-choice helpers,
  planning building blocks, MPC and stochastic building blocks, exactness helpers, fixture
  node helpers, experiment builders, the per-unit base helpers (`PerUnitBase`, `Z_base`,
  `I_base`, `to_pu_impedance`, `to_pu_power`) and internal constants. The advanced-API names,
  including the per-unit base helpers, are declared `public` and remain documented in the
  [API Reference](api.md); on Julia 1.11 and later use `Base.isexported` to inspect the
  exported set, since `names` also lists `public` names.
- **`DlmpDecomposition` aliases.** The deprecated `.loss` and `.voltage` properties are
  removed; use `.cone` and `.drop`. `NamedTuple(d)` keeps the historical positional order but
  now uses the same names: its keys are `(energy, cone, congestion, drop, reactive, total)`
  instead of `(energy, loss, congestion, voltage, reactive, total)`.
- **Stored simulation provenance.** The type path of the reactive mode changed, so locally
  stored simulation provenance files written before this change load the mode with a
  reconstructed type.
