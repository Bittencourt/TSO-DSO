---
phase: 33-shared-abstractions-feeder-balance-model-context
plan: 03
subsystem: core
tags: [close_balance, ARCH-04, fingerprint]
requires: [33-01]
provides:
  - close_balance! helper (src/core/balance.jl), exported and documented
  - literal pre-migration constraint-order fingerprints for Plan 33-05
affects: [33-05]
key-files:
  created: [src/core/balance.jl, test/test_close_balance.jl]
  modified: [src/TSODSO.jl, docs/src/api.md]
decisions:
  - Anonymous containers with base_name so scenario contexts on one model cannot collide
metrics:
  tasks: 2
  files: 4
completed: 2026-10-03
---

# Phase 33 Plan 03: close_balance! helper and fingerprints Summary

`close_balance!(ctx, N, T; reactive, label)` now exists. It uses the existing error text and operation order, builds anonymous `balance_p` / `balance_q` containers, and registers them in `ctx.constraints`. No call site is migrated yet; Plan 33-05 does that.

## Tasks

1. `021dc45` - `test/test_close_balance.jl`: fingerprints captured on the unmodified builders. Literal constraint positions for the `balance_p` / `balance_q` blocks on `solve_welfare` (LinDistFlow and DC), `solve_linear` and `build_mpc_window`. Constraint counts and type pairs for the stochastic extensive builder (S=2) and `build_dso_opt`, plus the DsoOpt balance blocks. The fingerprints were green on unmodified source.
2. `41cb5ba` - `src/core/balance.jl`, include after `core/ModelContext.jl`, `docs/src/api.md` Core Pages entry, and 3 helper-contract testitems. They cover the reactive and DC returns, registration identity, MOI names, `EqualTo(0)`, no object-dictionary entry, two contexts on one model, and the exact `:Rp` / `:Rq` error text with the `label` prefix.

## Verification

`test_close_balance.jl` and `test_context.jl` ran under TestItemRunner with 0 failures. I did not run the full suite. `grep close_balance! src/models src/admm` returns 0.

Audit: `constraint_by_name` has no consumer in `src` or `test`, so nothing looks balance constraints up by name on a stochastic model.

## Deviations from Plan

None. Task 1 also fingerprints the DsoOpt balance blocks by name. The plan asked for counts and types only there.

## Known Stubs

None.

## Self-Check: PASSED
