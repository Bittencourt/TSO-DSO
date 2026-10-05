# Phase 36 breaking-changes ledger

Running list of breaking removals; consumed by the docs "Breaking changes" note.

- `operational_oracle`: keywords `objective_hook`, `horizon_state` and `z` removed (passing any raises `MethodError`).
- `_coupling_dual(ctx, z)` is now `_coupling_dual(ctx)`; the `z !== nothing` throw path is gone.
- `DlmpDecomposition`: deprecated `.loss` / `.voltage` aliases (and their `propertynames` entries) removed; use `.cone` / `.drop`. `NamedTuple(d)` still returns the old field names.
- Reactive mode: `Bool` and `Symbol` forms removed (`normalize_reactive_mode` accepts only `ReactiveMode.T`, anything else raises `ArgumentError` naming OFF, CERTIFIED, LIVE). `ReactiveMode` is now a module (type `ReactiveMode.T`); bare `OFF`/`CERTIFIED`/`LIVE` and `normalize_reactive_mode` are no longer exported. `repr` and the JLD2 type path of stored modes changed (gitignored data/sims files written earlier load with a reconstructed type).
