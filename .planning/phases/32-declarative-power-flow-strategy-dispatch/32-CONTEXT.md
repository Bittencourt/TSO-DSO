# Phase 32: Declarative Power-Flow & Strategy Dispatch - Context

**Gathered:** 2026-10-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Researcher can select the power-flow formulation and the solve strategy declaratively through
`Scenario`, dispatched via one common entry point (ARCH-01, ARCH-02):

1. `Scenario` selects the power-flow formulation and `run_scenario` honours it — nothing is
   hard-coded to `ConvexBranchFlow()` (today: `run.jl:112`, `mpc_loop.jl:298`,
   `run_stochastic.jl:151`).
2. Solve strategies are types (`Centralized`, `ADMM`, `MPC`, `Stochastic`) dispatched through one
   `run(strategy, scenario)` entry point returning results of a common shape.
3. `Scenario` no longer carries strategy-specific fields in one flat bag.

OUT of scope: making `solve_admm` formulation-generic (ARCH-05, Phase 34); feeder/ModelContext
type unification (Phase 33); meshed feeders as a `Scenario` selector.

</domain>

<decisions>
## Implementation Decisions

### Power-Flow Selection in Scenario
- Representation: primitive `pf::Symbol` selector (default `:convex_branch_flow`) plus primitive
  option fields (`pf_thesis_literal::Bool`, `pf_ε::Float64`), materialized by a new
  `build_powerflow(s)` in `materialize.jl`. Preserves the "Scenario holds only primitives →
  savename works" invariant (Phase 8).
- Selectable set: `:convex_branch_flow` (default; `thesis_literal` option),
  `:restricted_branch_flow` (`ε`), `:lindistflow`, `:ac`. `MeshedFlow` NOT exposed (needs a
  meshed feeder, not a Scenario selector yet). `DCPowerFlow` not exposed.
- Invalid strategy × pf combos (e.g. `ADMM` + `:lindistflow`/`:ac`) throw `ArgumentError` at
  `Scenario` construction (ADMM accepts only SOCP-family formulations until Phase 34 / ARCH-05).
- `exact_maxgap` for non-cone formulations (`:lindistflow`, `:ac`) is `NaN`, documented as
  "not applicable" — keeps the common `Float64` result shape.

### Strategy Types & Entry Point
- `abstract type AbstractStrategy`; concrete structs carry their own knobs and validate in their
  constructors (validation moves out of `Scenario`):
  `Centralized()`, `ADMM(; ρ, ε_abs, ε_rel, maxiter, τ_ratio, μ)`,
  `MPC(; H, step, terminal_soc, forecast_error)`, `Stochastic(; S, probabilities, H_oos)`.
  Defaults identical to today's flat-field defaults (incl. `ρ = 100.0`, probabilities
  empty-sentinel → uniform, defensive copy).
- Entry point: `run(strategy::AbstractStrategy, s::Scenario)` as package-owned `TSODSO.run`,
  NOT exported (avoid `Base.run` collision); documented as `TSODSO.run(...)`.
- `run_scenario`, `run_mpc`, `run_stochastic` kept as thin wrappers (no deprecation) so all
  existing tests/docs/goldens keep working. `run_scenario(s)` dispatches on `s.strategy`.
- `Scenario` holds `strategy::AbstractStrategy` (default `Centralized()`); `run(s) = run(s.strategy, s)`.

### Scenario Restructure & Compatibility
- Legacy flat kwargs (`Scenario(; strategy = :admm, ρ = 50.0, mpc_H = 6, …)`) keep working via an
  outer kwarg constructor that maps `strategy::Symbol` + flat knobs to the strategy struct.
  Passing a knob foreign to the chosen strategy (e.g. `mpc_H` with `:centralized`) throws
  `ArgumentError`. In-repo tests/docs migrate to the new form.
- Filename identity: `scenario_filename` flattens the strategy to prefixed primitive fields
  (`strategy=ADMM`, `admm_ρ=…`), keeping `digits = 10`, `safe = true`, and the non-uniform
  probability FNV-1a digest. Only the active strategy's knobs appear (shorter names — also
  relieves the NAME_MAX pressure noted in store.jl).
- Goldens: every NUMERIC golden must be bit-identical — this phase is pure orchestration/dispatch,
  no model change. Only savename/filename STRINGS change (documented, accepted).
- New file `src/experiments/strategies.jl`, included before `Scenario.jl`; `run` methods
  co-located with each existing entry point (`run.jl`, `mpc_loop.jl`, `run_stochastic.jl`).

### Common Result Shape
- Every strategy returns `ScenarioResult`: common fields `scenario`, `welfare`, `dadp`,
  `exact_maxgap`, `elapsed` + typed strategy-specific `details` (ADMM: iters/final_r/final_s/
  reactive_consensus_mode; MPC: regret/trace/…; Stochastic: in_sample/oos).
- Headline mapping: MPC → `welfare = realized_welfare` (truth-settled), `dadp` = published DADP;
  Stochastic → `welfare = in_sample.welfare` (expected), `dadp = expected_dadp`. Documented.
- Existing ADMM fields stay accessible: `getproperty` forwarding keeps `r.iters`, `r.final_r`,
  `r.final_s`, `r.reactive_consensus_mode` working; `result_to_dict` updated accordingly.
- `run_mpc`/`run_stochastic` keep returning their current NamedTuples (goldens untouched);
  `run(::MPC, s)` / `run(::Stochastic, s)` wrap them into `ScenarioResult`.

### Claude's Discretion
- Exact concrete type of `details` (per-strategy NamedTuple vs small structs), as long as it is
  type-stable enough for JET and serializable by `result_to_dict`.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/experiments/materialize.jl` — `build_feeder`/`build_price`/`build_population`/`sub_seed`;
  add `build_powerflow` here.
- `src/powerflow/*` — `ConvexBranchFlow(; thesis_literal)`, `RestrictedBranchFlow(; ε)` (validates
  ε ≥ 0), `LinDistFlow()`, `ACPowerFlow(; limits)`.
- `solve_welfare`, `build_mpc_window`, `build_stochastic_welfare` already accept
  `pf::AbstractPowerFlow`; `solve_admm` is typed `pf::ConvexBranchFlow` (src/admm/solve_admm.jl:241).
- `extract_dlmp` errors if no SOCP balance was registered (src/pricing/dlmp.jl:372) — check its
  behaviour on `:lindistflow`/`:ac` before wiring `:centralized` + those formulations.

### Established Patterns
- `Scenario` validation via inner constructor throwing `ArgumentError` (never `@assert`).
- Primitive-only Scenario fields for DrWatson `savename`; `scenario_filename` in store.jl is the
  sole on-disk identity key (digits=10, safe=true, FNV-1a digest for dropped vector field).
- Same-seed bit-for-bit reproducibility (INFRA-04) via `sub_seed` — must be preserved.

### Integration Points
- `src/experiments/run.jl` (`run_scenario`, `ScenarioResult`), `mpc_loop.jl` (`run_mpc`),
  `run_stochastic.jl`, `store.jl` (`scenario_filename`, `result_to_dict`, `run_and_store`),
  `sweep.jl` (`run_sweep` builds Scenarios from a param Dict — must accept the new form or the
  legacy flat keys).
- Callers: 37 `Scenario(` sites in test/ (fixtures_phase8.jl, test_experiments.jl,
  test_admm_knifeedge_canary.jl, test_mpc_loop.jl, test_run_stochastic.jl, test_mpc_window.jl) and
  docs/literate (experiments.jl, mpc_rolling_horizon.jl, stochastic_pv_demand.jl).

</code_context>

<specifics>
## Specific Ideas

- Use the exact ARCH-02 names: `Centralized`, `ADMM`, `MPC`, `Stochastic`, `run(strategy, scenario)`.
- Every numeric golden stays bit-identical — verify with the full suite (baseline 31260/0/0/5).

</specifics>

<deferred>
## Deferred Ideas

- `solve_admm` accepting any `AbstractPowerFlow` (ARCH-05 → Phase 34); lift the ADMM×pf
  construction-time restriction then.
- Meshed feeder / `MeshedFlow` as a `Scenario` selector (after Phase 33's `AbstractFeeder`).
- Removing the legacy flat-kwarg constructor (a later cleanup, e.g. Phase 36).

</deferred>
