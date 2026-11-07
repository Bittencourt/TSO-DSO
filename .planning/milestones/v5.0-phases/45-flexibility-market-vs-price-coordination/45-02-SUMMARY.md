---
phase: 45-flexibility-market-vs-price-coordination
plan: 02
subsystem: settlement / coordination
tags: [julia, jump, clarabel, settlement-ledger, flex-market, bids, pav, testitems]

requires:
  - phase: 45-01
    provides: default-path fence (FlexFenceFixtures), coordination types, test_flex_market.jl header table
  - phase: 41-settlement
    provides: SettlementLedger, build_settlement_ledger, _push_transfer_pair!, price_taker_dispatch build shape
provides:
  - "build_settlement_ledger(...; flex_payments = nothing): flow (e), one (:aggregator, bus) <-> :dso mirror pair per row, V5-validated"
  - "SettlementInput overload forwards flex_payments (and documents actor_wedges)"
  - "src/coordination/flex_bids.jl: FLEX_RANGE_FLOOR, FlexBids, _fixed_net_model, _pav_nondecreasing, flex_bids"
  - "FlexMarketFixtures testmodule (seeded ledger rows, feeder2(smax), interruptible_agg, coupled_agg, curve/solve-count helpers)"
affects: [45-03, 45-04, 45-05, 45-06, 45-07]

tech-stack:
  added: []
  patterns:
    - "Build-once probe model: fix all hours at b, then per hour unfix -> range LPs -> fixed probes -> re-fix; every solve status-gated, never assert_solved!"
    - "Secant prices over equal widths R/K; a failed probe drops its block and the next secant spans from the last good point"
    - "One weighted PAV pass over [g_K..g_1, m_1..m_K] gives convexity and g1 <= m1 at once; the largest change is reported"

key-files:
  created:
    - src/coordination/flex_bids.jl
  modified:
    - src/settlement/SettlementLedger.jl
    - src/settlement/run_inputs.jl
    - src/TSODSO.jl
    - docs/src/api.md
    - test/test_flex_market.jl
    - test/test_flex_market_fence.jl

key-decisions:
  - "flex_payments rows must carry integer (non-Bool) bus and t and real price/quantity; a Float t or a String price is an ArgumentError, not an InexactError/MethodError"
  - "Absent blocks store width 0.0 and price 0.0 (never NaN), so a stage-2 pseudo-device can multiply them safely; V0 = NaN only when the baseline solve itself fails"
  - "A range of exactly 0 never emits a block even with range_floor = 0 (no division by a zero width)"
  - "flex_bids and FlexBids stay internal (not exported); their docstrings surface through the Coordination @autodocs Pages list"

patterns-established:
  - "The interruptible anchor uses the analytic baseline -p0 - Pdc (not a price-taker solve), so the anchor test isolates the bid generator's own noise"

requirements-completed: []  # SETL-07 spans plans 01-07; the final plan of the phase marks it

duration: 24min
completed: 2026-11-04
---

# Phase 45 Plan 02: Ledger flex payments and bid probing Summary

**The settlement ledger now books flexibility payments as exactly-conserving `(:aggregator, bus) <-> :dso` mirror pairs, and the default path is unchanged. A new probing routine (`flex_bids`) reads truthful, convex, divisible bids off each aggregator's own fixed-net value function. It uses one model per aggregator, built once, and computes secant blocks above a 1e-6 pu range floor followed by one weighted PAV repair. The repair size is reported.**

## Performance

- **Duration:** about 24 min
- **Started:** 2026-11-05T01:24:00Z (2026-11-04 22:24 -0300)
- **Completed:** 2026-11-05T01:48:00Z
- **Tasks:** 2/2, each a RED commit plus a GREEN commit, followed by one FMT style commit
- **Files modified:** 7 (1 created)

## Accomplishments

- **Flow (e):** `flex_payments = nothing` was added after `actor_wedges` in the primitive. It has a docstring bullet and an "(e)" entry in the flows list; the list now names (d) as well, to stay consistent. A V5 block runs before `transfers = Transfer[]`, and flow (e) runs after (d) and before the fold. `sizehint!` is untouched: `git diff | grep -c sizehint` returned 0.
- **SettlementInput overload:** it forwards `flex_payments = flex_payments` (1 line). Its docstring now lists all three keywords.
- **`flex_bids`:**
  - It builds one `Model(select_optimizer(QP()))` per aggregator, with anonymous `pag` and `Max ctx.objective`. There is no price term, no ρ term and no `solve_agr!`.
  - `price_taker.jl` is unchanged (`git diff` is empty) and `assert_solved!` appears 0 times.
  - The solve count is exactly `1 + 2T + K·(offered hour-directions)`.
- **Include and docs:** `include("coordination/flex_bids.jl")` comes after `coordination.jl`, and the api.md Coordination `Pages` list now names it.

## Measured tolerances

The rule is 3x the observed maximum over seeds 20260719, 20260720 and 20260721, or `==` when the observed maximum is 0.0. It was measured with scratch scripts outside the repo on Julia 1.12.5, and the values are recorded in the `test/test_flex_market.jl` header.

| Quantity | seed 20260719 | seed 20260720 | seed 20260721 | Observed max | Pinned |
|---|---|---|---|---|---|
| Ledger: aggregator balance change vs. the independent Σ price·quantity (seeded rows, 2-bus T = 3) | 3.11e-15 | 1.11e-15 | 5.55e-15 | 5.55e-15 | 1.67e-14 |
| Ledger: DSO balance change vs. the negated sum | 0.0 | 0.0 | 0.0 | 0.0 | `==` (exact) |
| Bids: \|V0 − price-taker utility\| (coupled aggregator, T = 24, K = 4) | 1.14e-8 | 1.23e-8 | 2.90e-9 | 1.23e-8 | 3.68e-8 |
| Bids: secant price vs. the analytic anchor (Interruptible, K = 1 / K = 4) | 9.0e-11 / 3.37e-10 | 9.7e-11 / 3.79e-10 | 7.5e-11 / 3.37e-10 | 3.79e-10 | 1.14e-9 |
| Bids: `repair_max` (coupled, T = 24, K = 4) | 7.74e-7 | 2.72e-6 | 1.96e-6 | 2.72e-6 | 8.18e-6 |
| Bids: `repair_max` (Interruptible anchor, K = 1 and 4) | 0.0 | 0.0 | 0.0 | 0.0 | `==` (exact) |

No wash tolerance was needed in this plan: stage 2 is not built yet.

Other measured values:
- **Hand-written rows** (3.0·0.5 and 3.0·(−0.25)): both balance changes are exactly 0.0 in this case.
- **Bid–ask gap** (`min_bid_ask_gap`): on the coupled fixture it is 5.06 to 5.14, and on the anchor fixture 0.20 to 1.10. It is strictly positive everywhere.
- **Interruptible ranges:** every hour-direction is interior and offered, with 13 solves at K = 1 and 31 at K = 4.
- **Coupled ranges:** R↑ is 0.0475 to 0.0525 pu and R↓ is 1.0 to 1.5 pu, so all 96 up blocks and 96 down blocks are offered. `n_failed` is 0, and the stage-1 battery certificate is `:ok` for all seeds.

## Probe timing

On the coupled fixture (Thermostatic + Deferrable + PVBattery, T = 24, K = 4, 241 solves per aggregator, after a warm-up call):

- **Per probe solve:** 6.24, 6.03 and 6.61 ms for the three seeds.
- **Total `flex_bids` time:** 1.50, 1.45 and 1.59 s per aggregator.

## Task Commits

1. **Task 1 RED, ledger flex-payment tests and fence item:** `7dc0aac` (test). It failed with `got unsupported keyword argument "flex_payments"`.
2. **Task 1 GREEN, flow (e), V5 block, forwarding and pinned tolerances:** `009f6c6` (feat)
3. **Task 2 RED, bid-probing tests and fixtures:** `8d2c203` (test). It failed with `flex_bids` and `_pav_nondecreasing` undefined.
4. **Task 2 GREEN, flex_bids.jl, include, api.md and pinned tolerances:** `9808669` (feat)
5. **FMT style pass:** `e4c8527` (style). It is whitespace and wrapping only, and `check_content_loss.py HEAD` reported OK.

## Test results

- **Task 1 verify** (`test_flex_market.jl`, `test_flex_market_fence.jl`, `test_settlement.jl`, `test_actor_settlement.jl`): 483/483 pass, 0 fail, 0 error.
- **Task 2 verify** (`test_flex_market.jl`, `test_flex_market_fence.jl`): 214/214 pass, 0 fail, 0 error.
- **After FMT, the Task 1 set again** (four files): 607/607 pass, 0 fail, 0 error. 0 soft-scope warnings and 0 UNEXPECTED broken records.
- **Fence:** the digest goldens are unchanged, and the new item "flex market: ledger default unchanged" passes.
- **Planning-ID guard:** 355 (not above 355). **JuliaFormatter 2.10.2:** the second `format` pass returned true.

## Files Created/Modified

- `src/coordination/flex_bids.jl` (new, 382 lines): `FLEX_RANGE_FLOOR`, `FlexBids`, `_fixed_net_model`, `_bid_solve_ok`, `_pav_nondecreasing`, `_probe_direction!`, `_repair_hour!`, `_first_block`, `flex_bids`
- `src/settlement/SettlementLedger.jl`: the `flex_payments` keyword, docstring, V5 block and flow (e)
- `src/settlement/run_inputs.jl`: keyword forwarding and the overload docstring, plus FMT rewrapping of existing lines
- `src/TSODSO.jl`: the include line
- `docs/src/api.md`: the Coordination `Pages` list
- `test/test_flex_market.jl`: `FlexMarketFixtures`, the ledger item and four bid items, and the tolerance table
- `test/test_flex_market_fence.jl`: the "flex market: ledger default unchanged" item

## Decisions Made

- **Probe failure handling:** a failed probe drops its block (width 0, counted in `n_failed`). The next successful probe's secant spans from the last good point, so the offered quantity is kept rather than truncated. A failed range LP offers nothing in that direction. A failed baseline solve returns an empty bid with `V0 = NaN`. Nothing throws.
- **Anchor baseline:** the anchor fixture uses the analytic baseline `−p₀ − Pdc`. The anchor test therefore measures the bid generator's noise only, not the price-taker's.
- **Exports:** `flex_bids` and `FlexBids` are internal; later plans call them as `TSODSO.flex_bids`. No export-list change was needed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Input validation] Type checks on flex_payments rows**
- **Found during:** Task 1
- **Issue:** The planned checks (`Int(f.bus) in buses`, `1 ≤ f.t ≤ T`, `isfinite`) would raise `InexactError` for `t = 1.5` and `MethodError` for a String price, not `ArgumentError`.
- **Fix:** bus and t must be non-Bool integers, and price and quantity must be reals, each checked with an `ArgumentError`. Tests were added for `t = 1.5` and `price = "3.0"`, plus an empty-row-list case (no rows added).
- **Files modified:** src/settlement/SettlementLedger.jl, test/test_flex_market.jl
- **Commit:** 009f6c6

**2. [Rule 2 - Input validation] Extra argument guards on flex_bids and PAV**
- **Found during:** Task 2
- **Issue:** The plan required guards on `length(b)`, finite `b` and `n_blocks`. Two inputs were still unguarded: a negative or non-finite `range_floor`, and non-positive PAV weights. Either one silently corrupts the curve.
- **Fix:** both now raise `ArgumentError`, and both are tested.
- **Commit:** 9808669

**3. FMT scope:** formatting `src/settlement/run_inputs.jl`, which the plan lists, also rewrapped five existing lines that were already off-format at HEAD. The change is whitespace only, and content-loss reported OK.

Otherwise the plan executed as written.

## Issues Encountered

None.

## Known Stubs

None.

## Next Phase Readiness

- Stage 2 (45-03) can build `FlexBidDevice` straight from the `FlexBids` matrices: absent blocks are width 0 and price 0, so they are safe in a linear objective.
- The `FlexMarketFixtures` testmodule already provides `feeder2(smax)`, `interruptible_agg` (φ = 1.0) and `coupled_agg` for the stage-2 and liveness items.

## Self-Check: PASSED

- FOUND: src/coordination/flex_bids.jl, test/test_flex_market.jl, test/test_flex_market_fence.jl
- FOUND commits: 7dc0aac, 009f6c6, 8d2c203, 9808669, e4c8527
