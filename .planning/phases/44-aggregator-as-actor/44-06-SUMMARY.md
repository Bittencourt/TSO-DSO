---
phase: 44-aggregator-as-actor
plan: 06
subsystem: settlement
tags: [settlement-ledger, actor-profit, shared-bus, adapters, rebound]
requires: ["44-02", "44-04", "44-05"]
provides:
  - "build_settlement_ledger(...; actor_wedges): per-site mirror pair (:actor,id) <-> (:aggregator,bus) of m_t*load, ledger_residual == 0.0 exactly"
  - "Both settlement_input adapters sum nets/utilities per bus on shared buses (slot-aware ADMM branch via slot_bus)"
  - "TSODSO.actor_wedge_rows(ctx, portfolios, aggregators; T) and (result, portfolios; T) (internal, unexported)"
affects: [44-07]
tech-stack:
  added: []
  patterns: ["first-seen bus assigned directly, later sites += (no 0.0 + x), so single-site ledgers stay bit-identical", "actor line appended after flow (c) as an adjacent mirror pair"]
key-files:
  created:
    - test/test_actor_settlement.jl
  modified:
    - src/settlement/SettlementLedger.jl
    - src/settlement/run_inputs.jl
key-decisions:
  - "WelfareObjective portfolios contribute NO wedge rows (omitted, not zero rows); their (:actor,id) balance is absent"
  - "Centralized actor_wedge_rows needs the aggregators vector (agg_net stash is positional, sites matched by ===); the ADMM form reads slot_actor/slot_bus, else each site's bus"
  - "build_settlement_ledger(::SettlementInput) overload forwards actor_wedges too"
  - "No new export: helper stays internal, test_exports unchanged"
requirements-completed: []
duration: ~1h
completed: 2026-11-02
---

# Phase 44 Plan 06: Actor settlement line and shared-bus adapters Summary

The actor profit is a separate, exactly conserving line in the Phase-41 ledger, and both settlement adapters now handle several sites at one bus by summing per bus instead of silently overwriting.

## Tasks

1. RED (`3f36a47`): `test/test_actor_settlement.jl` with seven items (default bit-identity, conservation and profit line, centralized shared-bus sum, ADMM slot-keyed sum, legacy 1:1 adapters, rebound on a wrapped population, V5 guards). Failed on the missing keyword and helper.
2. GREEN (`3999cef`): `actor_wedges` keyword with V5 validation (finite, length T, bus among ledger buses, row shape) and flow (d); per-bus `+=` accumulation in the centralized adapter; `_slot_bus_inputs` slot-aware branch in the ADMM adapter (legacy branch statements unchanged, only re-indented); `actor_wedge_rows` helper.

## Measured tolerances (julia 1.12.5, 3 seeds, 4-bus population with two sites at bus 3, ADMM eps_abs 1e-7)

| Quantity | Observed max | Pinned |
|---|---|---|
| balances[(:actor,k)] vs independent sum m*load | 0.0 | 1e-12 floor |
| balances[(:actor,k)] vs solve profit_by_actor (centralized) | 2.2e-16 | 1e-12 floor |
| balances[(:actor,k)] vs ADMM profit_by_actor | 2.2e-16 | 1e-12 floor |

Conservation, default-ledger equality and shared-bus sums are asserted with `==`.

## Verification (julia 1.12.5, fast set, foreground)

`test_actor_settlement, test_settlement, test_actor_default_fence, test_exports, test_welfare_solve, test_actor_objective`: 694 pass, 0 fail. `test/test_settlement.jl` unchanged (empty diff); no golden, tolerance or `expected_broken.txt` change.

## Deviations from Plan

- **[Decision]** The centralized helper takes the `aggregators` vector as a third argument (the plan sketched `(result_or_ctx, portfolios)`), because the stash is positional and shared buses make bus-only matching ambiguous.
- The rebound item passed before implementation (it composes existing pieces); it is kept as the ACTOR-04 measurement anchor, not as a RED driver.
- The IEEE-13 fixture was not used for the settlement items; a 2-bus and a purpose-built 4-bus feeder keep the items at seconds. IEEE-13 and the IEEE-123 sweep belong to 44-07.

## Known Stubs

None.

## Self-Check: PASSED

Commits `3f36a47`, `3999cef` exist; `actor_wedges` present in `src/settlement/SettlementLedger.jl`; REQUIREMENTS.md untouched.
