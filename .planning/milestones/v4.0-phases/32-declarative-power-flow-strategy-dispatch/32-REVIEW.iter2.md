---
phase: 32-declarative-power-flow-strategy-dispatch
reviewed: 2026-10-03T00:00:00Z
depth: standard
files_reviewed: 22
files_reviewed_list:
  - src/experiments/strategies.jl
  - src/experiments/Scenario.jl
  - src/experiments/materialize.jl
  - src/experiments/run.jl
  - src/experiments/store.jl
  - src/experiments/sweep.jl
  - src/experiments/mpc_loop.jl
  - src/experiments/run_stochastic.jl
  - src/TSODSO.jl
  - test/test_strategies.jl
  - test/test_scenario_pf.jl
  - test/test_experiments.jl
  - test/test_mpc_loop.jl
  - test/test_run_stochastic.jl
  - test/test_planning_noninteger.jl
  - docs/literate/experiments.jl
  - docs/literate/mpc_rolling_horizon.jl
  - docs/literate/stochastic_pv_demand.jl
  - scripts/compare_default_stochastic.jl
  - scripts/demo_mpc_plots.jl
  - README.md
  - docs/src/api.md
findings:
  critical: 0
  warning: 5
  info: 3
  total: 8
status: issues_found
---

# Phase 32: Code Review Report

**Reviewed:** 2026-10-03
**Depth:** standard
**Files Reviewed:** 22

## Summary

The source files were reviewed in full (strategies, Scenario, materialize, run, store, sweep, mpc_loop, run_stochastic, TSODSO.jl). The tests, docs, scripts and README were only grepped for stale use of the removed flat fields (`s.mpc_H`, `s.stoch_S`, and similar); none was found in executable code.

The core design holds up:
- The legacy-kwarg mapping is correct and detects knobs by supplied keys, not by comparing against defaults.
- Strategy `==` and `hash` are consistent for ordinary values.
- Filename flattening keeps the active strategy's knobs and uses `digits = 10` and `safe = true`.
- `TSODSO.run` does not shadow `Base.run` anywhere else in the module.

I found no blockers. The warnings are validation holes, one bypass of the strategy x pf matrix, and `==`/`hash` edge cases.

## Warnings

### WR-01: `run_mpc` / `run_stochastic` bypass the strategy x pf support matrix

**File:** `src/experiments/mpc_loop.jl:1660`, `src/experiments/run_stochastic.jl:315`
**Issue:**
- The wrappers do `st = s.strategy isa MPC ? s.strategy : MPC()`.
- A `Scenario` built with `strategy = Centralized()` and `pf = :lindistflow`, `:ac` or `:restricted_branch_flow` (or `pf_thesis_literal = true`) is valid at construction.
- Calling `run_mpc(s)` or `run_stochastic(s)` on it skips `supports_pf` entirely. `_run_mpc` and `_run_stochastic` then call `build_powerflow(s)` and hit exactly the combinations that `supports_pf` documents as failing (measured).
- The failure is a cryptic solver or model error deep in the loop instead of an `ArgumentError`.
- Silently substituting `MPC()` defaults for a non-MPC scenario is also surprising. This is a loss of the invariant that Phase 32 introduced.

**Fix:** Re-validate inside the wrappers, or require the right strategy type:
```julia
function run_mpc(s::Scenario; _truth_settlement::Symbol = :ac)
    st = s.strategy isa MPC ? s.strategy : MPC()
    s_eff = st == s.strategy ? s : with_strategy(s, st)   # re-runs supports_pf
    return _run_mpc(s_eff, st; _truth_settlement)
end
```
Do the same in `run_stochastic`. Alternatively, throw an `ArgumentError` when `s.strategy` is not an `MPC` / `Stochastic`.

### WR-02: ADMM constructor accepts NaN and Inf knobs

**File:** `src/experiments/strategies.jl:49-57`
**Issue:**
- `NaN <= 0` is `false`, so `ADMM(ρ = NaN)`, `ε_abs = NaN`, `ε_rel = NaN`, `τ_ratio = NaN` and `μ = NaN` all pass validation. `Inf` is also accepted.
- The run never converges and silently burns `maxiter` iterations.
- NaN also breaks `==` reflexivity (`ADMM(ρ=NaN) != ADMM(ρ=NaN)`), so `_effective_scenario` always rebuilds the scenario.
- `Scenario` validates `pf_ε` with `isfinite`, but the ADMM knobs do not.

**Fix:**
```julia
all(isfinite, (ρ, ε_abs, ε_rel, τ_ratio, μ)) ||
    throw(ArgumentError("ADMM: knobs must be finite"))
```
Add this before the sign checks.

### WR-03: `Scenario` `==` and `hash` disagree for `pf_ε = -0.0`

**File:** `src/experiments/Scenario.jl:175-185, 361-377`
**Issue:**
- `-0.0 >= 0` is true and `-0.0 != 0.0` is false, so `Scenario(...; pf_ε = -0.0)` is accepted for any `pf`.
- `-0.0 == 0.0` is true, so such a scenario is `==` to the `0.0` one. But `hash(-0.0) != hash(0.0)`, which violates the `==` => same-hash contract and breaks `Dict`/`Set`/`unique` use.
- The same applies to `ADMM`/`MPC` float knobs.
- `savename` would also render `pf_ε=-0.0` under restricted flow.

**Fix:** Normalize in the constructor with `pf_ε = pf_ε + 0.0`, which turns `-0.0` into `+0.0`, or hash with `isequal` semantics. The same normalization is cheap for the strategy floats.

### WR-04: `Stochastic.probabilities` is a mutable vector inside a value-hashed immutable

**File:** `src/experiments/strategies.jl:103-130, 147-149`
**Issue:**
- The constructor copies the vector defensively, but `st.probabilities[i] = x` afterwards mutates it silently.
- `Scenario` and `Stochastic` are used as value keys: `hash`, `==`, `scenario_filename`, `_effective_scenario`.
- A mutation after construction bypasses the sum-to-1 and positivity validation and changes the hash of an object already stored in a `Dict` or `Set`.

**Fix:** Store an immutable container (`NTuple`, or a `Vector` wrapped read-only), or document it as read-only. At minimum have `_strategy_knobs` and `_run_stochastic` re-validate before use.

### WR-05: Filename-truncation fallback uses `Base.hash`, contradicting the file's own reproducibility rationale

**File:** `src/experiments/store.jl:165`
**Issue:**
- `_stable_hex64` exists because `Base.hash` is not stable across Julia versions (1.10 vs 1.11+), per its docstring.
- The over-length fallback nevertheless appends `string(hash(full); base = 16)`, so the same Scenario can get different artifact names on different Julia versions.
- The hash is also not zero-padded, so its length varies.
- The path is rarely hit, but when it is, reproducibility and the collision claim are weaker than documented.

**Fix:**
```julia
return stem * "_h" * _stable_hex64(codeunits(full)) * ".jld2"
```

## Info

### IN-01: `strategy::AbstractStrategy` is an abstractly typed field

**File:** `src/experiments/Scenario.jl:118`
**Issue:**
- Every `s.strategy` access is type-unstable.
- This is acceptable for a per-run seam but will show up in JET reports.
- `ScenarioResult.details` is already a small `Union` and is fine.

**Fix:** Optionally parametrize `Scenario{S<:AbstractStrategy}`, or note the trade-off in the docs.

### IN-02: Docstring shape inconsistency for Stochastic `dadp`

**File:** `src/experiments/run_stochastic.jl:322` versus `src/experiments/run.jl:25-27`
**Issue:**
- The Stochastic `run` docstring says `1 x T` row.
- The `ScenarioResult` docstring says `1 x n`, and the MPC docstring says `1 x n` for the published hours.
- Make these consistent. `expected_dadp` is a per-hour vector at one bus, so `1 x T` is probably the correct shape for Stochastic.

### IN-03: `MPC` `H ≤ T` and `step ≤ H` are checked only at run time

**File:** `src/experiments/strategies.jl:66-72`
**Issue:**
- `Scenario(T = 12, strategy = MPC(H = 24))` constructs fine and only fails inside `_run_mpc`.
- The comment documents this. The cross-field check (`H ≤ T`) could cheaply live in the `Scenario` inner constructor, alongside the `supports_pf` check, so that sweeps fail before any solve.
- `step ≤ H` could be validated in the `MPC` constructor itself.
