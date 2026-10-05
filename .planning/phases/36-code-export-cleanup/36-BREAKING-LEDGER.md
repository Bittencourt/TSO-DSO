# Phase 36 breaking-changes ledger

Running list of breaking removals; consumed by the docs "Breaking changes" note.

- `operational_oracle`: keywords `objective_hook`, `horizon_state` and `z` removed (passing any raises `MethodError`).
- `_coupling_dual(ctx, z)` is now `_coupling_dual(ctx)`; the `z !== nothing` throw path is gone.
- `DlmpDecomposition`: deprecated `.loss` / `.voltage` aliases (and their `propertynames` entries) removed; use `.cone` / `.drop`. `NamedTuple(d)` still returns the old field names.
- Reactive mode: `Bool` and `Symbol` forms removed (`normalize_reactive_mode` accepts only `ReactiveMode.T`, anything else raises `ArgumentError` naming OFF, CERTIFIED, LIVE). `ReactiveMode` is now a module (type `ReactiveMode.T`); bare `OFF`/`CERTIFIED`/`LIVE` and `normalize_reactive_mode` are no longer exported. `repr` and the JLD2 type path of stored modes changed (gitignored data/sims files written earlier load with a reconstructed type).
- Export surface trimmed from 192 exported names to 90 (plus the module): 102 names are no longer exported (list in `.github/scripts/unexported_names.txt`). Call them as `TSODSO.name`. 85 of them are declared `public` (advanced API, via `Compat.@compat public`): problem-class singletons `LP/QP/SOCP/NLP/MILP`, optimizer-choice helpers, planning building blocks, MPC/stochastic building blocks, exactness helpers, fixture node helpers, experiment builders, `set_rho!`/`set_rho_q!`, `extract_reactive_dlmp`. The remaining 17 are internal (`record!`, `converged`, `admm_supported`, per-unit helpers `I_base Z_base PerUnitBase to_pu_*  assert_magnitudes*`, `IEEE8500_*` constants, `FIT_λ_*`). On Julia 1.11+ `names(TSODSO)` also lists public names; use `Base.isexported` to inspect the exported set.
