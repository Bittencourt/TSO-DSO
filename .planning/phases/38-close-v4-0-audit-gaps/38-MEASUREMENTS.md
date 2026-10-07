# Phase 38 — Measurements Ledger

Evidence ledger for the phase gate: per-plan measurements and test deltas. Each plan appends its
rows (test-file item/Pass deltas from filtered runs on Julia 1.12.5, plus any measured numbers it
relied on) so the gate plan can reconcile the full-suite totals against the per-plan claims.

## Test deltas

| plan | file | @testitems before -> after | Pass before -> after (1.12.5 filtered run) | note |
|------|------|----------------------------|--------------------------------------------|------|
| 38-01 | test/test_exactness.jl | 6 -> 6 | 20 -> 28 | +8 kernel parity assertions inside 2 existing items; combined filtered run with test_admm_exactness_default.jl: 62/62 |
