# Phase 36 breaking-changes ledger

Running list of breaking removals; consumed by the docs "Breaking changes" note.

- `operational_oracle`: keywords `objective_hook`, `horizon_state` and `z` removed (passing any raises `MethodError`).
- `_coupling_dual(ctx, z)` is now `_coupling_dual(ctx)`; the `z !== nothing` throw path is gone.
- `DlmpDecomposition`: deprecated `.loss` / `.voltage` aliases (and their `propertynames` entries) removed; use `.cone` / `.drop`. `NamedTuple(d)` still returns the old field names.
