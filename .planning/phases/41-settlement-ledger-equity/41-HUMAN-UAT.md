---
status: partial
phase: 41-settlement-ledger-equity
source: [41-VERIFICATION.md]
started: 2026-10-26
updated: 2026-10-26
---

## Current Test

[awaiting human testing — deferred during autonomous milestone run]

## Tests

### 1. BL-01 sign-convention eyeball
expected: The fit-leg `wholesale_total` in `src/settlement/comparison.jl` reads the same economic quantity with the same sign as the dadp/flat/tou legs (`+Σ λ₀·p_import`; merchandising surplus coupled as `collections − wholesale`). Eyeball the code and the hermetic fixture receipt (~12.0 on a pure-consumer fixture) to confirm the convention matches the module header spec.
result: [pending]

### 2. Rendered docs page
expected: `docs/literate/settlement_equity.jl` builds via both `docs/make.jl` sites and honestly presents the solve_failed/refusal statuses and the explicit no-income-data statement.
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
