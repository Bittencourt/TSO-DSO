---
status: complete
phase: 41-settlement-ledger-equity
source: [41-VERIFICATION.md]
started: 2026-10-26
updated: 2026-10-27
---

## Current Test

[testing complete]

## Tests

### 1. BL-01 sign-convention eyeball
expected: The fit-leg `wholesale_total` in `src/settlement/comparison.jl` reads the same economic quantity with the same sign as the dadp/flat/tou legs (`+Σ λ₀·p_import`; merchandising surplus coupled as `collections − wholesale`). Eyeball the code and the hermetic fixture receipt (~12.0 on a pure-consumer fixture) to confirm the convention matches the module header spec.
result: pass
evidence: "Code: comparison.jl:719 `wholesale_total = +sum(λ₀vec[t]*imp_total[t])` (matches ledger-sign legs at :534/:633); :733 `merchandising_surplus = dso_total - wholesale_total`; header spec :39-41 names the same convention. Live: BL-01 pin testitem green in 346/346 settlement suite (3m00.5s, exit 0) — pure-consumer fixture receipt `> 0` and `≈ 12.0 rtol=1e-6` (pre-fix code: −12), identities bitwise. User confirmed 2026-10-27."

### 2. Rendered docs page
expected: `docs/literate/settlement_equity.jl` builds via both `docs/make.jl` sites and honestly presents the solve_failed/refusal statuses and the explicit no-income-data statement.
result: pass
evidence: "Rendered docs/build/generated/settlement_equity.html (39 KB, built Oct 26 19:08 in the green full docs build; fresh vs source 558b27c 02:16). No-income statement rendered: 'the metrics operate on BILLS only — no income data exists to use.' Honest statuses: fit leg `error:SolveFailedError not_run - -`; flat/tou `solve_failed` WITH measured values (−5956.92/−5304.40, 36.22/41.25, −1305.58/−554.80); INFEASIBLE attribution prose; '(run) row: refused or stalled — its own honest record, certified values missing.' User confirmed 2026-10-27."

## Summary

total: 2
passed: 2
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none]
