---
phase: 45-flexibility-market-vs-price-coordination
plan: 03
subsystem: coordination
tags: [julia, jump, clarabel, socp, flex-market, redispatch, dlmp, delivery, testitems]

requires:
  - phase: 45-02
    provides: FlexBids, flex_bids, FLEX_RANGE_FLOOR, FlexMarketFixtures (feeder2, coupled_agg)
  - phase: 41-settlement
    provides: settlement_input, price_taker_dispatches, price_taker_dispatch battery-certificate block
provides:
  - "src/coordination/flex_clear.jl: FLEX_CONGESTION_KAPPA, FlexBidDevice, _stage2_aggregators, _redispatch, _congested_hours, _deliver, _flex_physics"
  - "One physics record per (baseline price, n_blocks) clear, with 27 fixed fields; uncomputed fields are nothing on a non-ok status"
  - "FlexMarketFixtures: tight_agg (one binding hour), stage2, zero_bids, tight_physics, allfinite"
affects: [45-04, 45-05, 45-06, 45-07]

tech-stack:
  added: []
  patterns:
    - "Stage 2 = solve_welfare over one FlexBidDevice pseudo-aggregator per real aggregator; no new network formulation"
    - "Absent bid blocks get no JuMP variable (constant 0 AffExpr), so zero-width bids give Δ == 0 exactly"
    - "Solver-outcome errors map to (status, notes) through a helper that returns nothing for anything else; the caller rethrow()s inside its catch"

key-files:
  created:
    - src/coordination/flex_clear.jl
  modified:
    - src/TSODSO.jl
    - docs/src/api.md
    - test/test_flex_market.jl

key-decisions:
  - "FlexBidDevice creates a variable only for offered blocks (width > 0); absent blocks are the constant 0, which avoids degenerate [0,0] bounds in the IPM and makes zero-width Δ exactly 0"
  - "Congested hour: s_t = max_j(|congestion| + |drop|)/λ₀[t] > κ = 1e-2; the reported interval [kappa_lo, kappa_hi) is measured ~[1e-9, 0.09) on the tight fixture"
  - "Delivery weight w = 10·max(max|π|, max λ₀, max|price|), fixed and documented; the 10w re-delivery only feeds shortfall_10w_total"
  - "_stage2_aggregators also refuses a non-ascending bus order up front (settlement_input would refuse it after the solve)"
  - "The physics record holds per-aggregator vectors (u, w :: Vector{Matrix}, Δ, π, targets, shortfall :: Vector{Vector}) and does not keep ctx2"

requirements-completed: []  # SETL-07 spans plans 01-07; the final plan of the phase marks it

duration: 35min
completed: 2026-11-04
---

# Phase 45 Plan 03: Stage-2 redispatch, congestion and delivery physics Summary

**Stage 2 clears each aggregator's bids as a `FlexBidDevice` pseudo-aggregator on the existing `solve_welfare` SOCP and exactness gate. Clearing prices are read only through `settlement_input`, and congested hours come from `decompose_dlmp` with a reported κ interval. Each aggregator then re-solves against an L1 exact-penalty tracking term to follow its activated target, with the shortfall reported. `_flex_physics` folds the pipeline into one record, and every solver outcome comes back as a status value.**

## Performance

- **Duration:** about 35 min
- **Started:** about 2026-11-05T01:50Z (22:50 -0300)
- **Completed:** 2026-11-05T02:25Z
- **Tasks:** 2/2. Each has a RED commit and a GREEN commit, followed by one docstring commit and one FMT style commit.
- **Files modified:** 4 (1 created)

## Accomplishments

- **`FlexBidDevice`:**
  - The inner constructor throws `ArgumentError` on mismatched sizes, a wrong `gross` length, non-finite entries or negative widths.
  - `contribute!` uses anonymous bounded variables, returns no `q_inject` and keeps the default traits (not a flexible load, storage `:none`). As a result, the roll-up writes only the inelastic reactive draw `−Pdc·tanφ`.
- **`_redispatch`:**
  - Calls `solve_welfare(...; allow_export = true)` in an if/else shape, so `optimizer = nothing` makes exactly the default call. A test confirms that an explicit optimizer gives identical `Δ` and prices (`==`).
  - Error mapping: `INFEASIBLE` and `INFEASIBLE_OR_UNBOUNDED` → `infeasible_redispatch`; `:socp_exact` → `inexact_redispatch`; any other solver outcome → `error:<Type>`; anything else is rethrown.
  - `grep "dual("` on the file returns nothing.
- **`_congested_hours`:** the score is defined from `decompose_dlmp` and documented in the docstring. The function returns `scores`, `kappa_lo` and `kappa_hi`.
- **`_deliver`:**
  - It is a fresh price-taker QP plus the tracking penalty, gated by `assert_solved!(dual = false)`.
  - The battery-certificate block is copied verbatim and reports without throwing.
  - The docstring states that the penalty is not money. `build_settlement_ledger` appears 0 times in the file.
- **`_flex_physics`:** runs stage 1, bids, stage 2, congestion, delivery at w and the 10w diagnostic. Stage-1 and delivery errors become `error:<Type>` with a `baseline: ` or `delivery: ` prefix on the notes.
- **Include and docs:** the include follows `flex_bids.jl`, and the api.md Coordination `Pages` list names the new file.

## Measured tolerances

The rule is 3x the observed maximum over seeds 20260719, 20260720 and 20260721, or `==` when the observed maximum is 0.0. Values were measured with scratch scripts outside the repo on Julia 1.12.5 and are recorded in the header of `test/test_flex_market.jl`.

| Quantity | 20260719 | 20260720 | 20260721 | Observed max | Pinned |
|---|---|---|---|---|---|
| Stage 2: \|bus_nets − (b + Δ)\| (tight, K = 4) | 2.22e-16 | 1.11e-16 | 2.22e-16 | 2.22e-16 | 6.67e-16 |
| Stage 2: max_wash, tight | 7.02e-9 | 5.70e-9 | 3.72e-9 | 7.02e-9 | 2.11e-8 |
| Stage 2: max_wash, no limit (same pin) | 2.29e-9 | 4.25e-11 | 2.40e-9 | (covered) | 2.11e-8 |
| Stage 2: Δ with all-zero widths | 0.0 | (one seed) | | 0.0 | `==` (exact) |
| Delivery: Σ shortfall, separable (tight) | 2.82e-12 | 3.01e-12 | 3.06e-12 | 3.06e-12 | 9.17e-12 |
| Delivery: over-reach \|shortfall[2] − R↑[2]\| | 6.94e-10 | 6.10e-10 | 6.97e-10 | 6.97e-10 | 2.09e-9 |
| Delivery: over-reach, other hours' shortfall | 3.13e-9 | 3.18e-9 | 3.11e-9 | 3.18e-9 | 9.53e-9 |
| Delivery: \|net(w) − net(10w)\|, over-reach | 8.87e-11 | 1.26e-10 | 9.17e-11 | 1.26e-10 | 3.79e-10 |
| Delivery: \|net(w) − net(10w)\|, coupled T = 24 (same pin) | 5.25e-12 | 1.51e-11 | 2.66e-12 | (covered) | 3.79e-10 |

Other measured values (asserted only by sign, set membership or equality):
- **SOCP maxgap, tight stage 2:** 1.45e-7, 3.14e-7 and 1.06e-7. **Coupled:** 5.4e-10, 4.2e-10 and 9.4e-10.
- **Δ in the binding hour (tight):** 0.653, 0.665 and 0.653 pu. The test asserts > 0.1.
- **Congestion score interval:**
  - tight: [7.2e-10, 0.090), [1.1e-9, 0.141) and [2.8e-10, 0.090). κ = 1e-2 sits about 7 decades above `kappa_lo` and about 9x below `kappa_hi`;
  - coupled: `kappa_hi` is 0.348, 0.357 and 0.338, with 12, 8 and 2 congested hours;
  - with no limit (`SMAX_NO_LIMIT`), `kappa_lo` ≤ 5.9e-13 and `kappa_hi` = Inf.
- **Delivery weight w (tight):** 62.6, 61.3 and 62.6. **shortfall_10w_total (tight):** 2.84e-12, 2.92e-12 and 3.08e-12, so it matches the w-shortfall to about 1e-13.
- **Coupled aggregator:**
  - shortfall_total is 6.9e-11, 1.7e-10 and 3.0e-11, against Σ|Δ| of 0.026, 0.017 and 0.004 pu. The hour-separable targets were reachable on this fixture.
  - The delivery battery certificate is `:ok` for all three seeds.
- **Infeasible offer** (Pdc + 2.0 against smax = 1.0): Clarabel reports `INFEASIBLE` / `PRIMAL_INFEASIBLE`, which maps to `infeasible_redispatch` on all seeds. The bids are kept, and `n_probe_solves` = 31.

## Stage-2 timing on the fixtures

Warm timings, Julia 1.12.5, Clarabel, single aggregator on the 2-bus feeder:

| Fixture | `_redispatch` (ms) | `_flex_physics` wall (s) |
|---|---|---|
| tight Interruptible, T = 3, K = 4 | 8.7, 8.5, 10.2 | 0.045, 0.044, 0.046 |
| coupled (Thermostatic + Deferrable + PVBattery), T = 24, K = 4 | 27.3, 22.8, 24.8 | 1.36, 1.38, 1.34 |

On the coupled fixture the wall time is dominated by the 241 probe solves. The first call in a fresh process pays about 18 to 30 s of compilation.

## Task Commits

1. **Task 1 RED, stage-2 tests and fixtures:** `1c3fdc8` (test). It failed with `UndefVarError: FlexBidDevice` / `_stage2_aggregators`.
2. **Task 1 GREEN, FlexBidDevice, stage 2, congestion, include and api.md:** `49e0448` (feat)
3. **Task 2 RED, delivery and pipeline tests:** `d13917f` (test). It failed with `UndefVarError: _flex_physics`; the Task 2 source was set aside by a file copy, not a stash.
4. **Task 2 GREEN, `_deliver` and `_flex_physics`:** `e3744a7` (feat)
5. **Docstring reword so no code span wraps:** `19a96e4` (docs). Kept separate so the style commit is whitespace-only.
6. **FMT style pass:** `cd7c600` (style). `check_content_loss.py HEAD` reported OK.

## Test results

- **Task 1 verify** (`test_flex_market.jl`, `test_flex_market_fence.jl`, `test_welfare_solve.jl`): 450/450 pass, 0 fail, 0 error.
- **Task 2 verify** (`test_flex_market.jl`, `test_flex_market_fence.jl`, `test_settlement.jl`): 755/755 pass, 0 fail, 0 error.
- **After FMT, all four files** (`test_flex_market`, the fence, `test_welfare_solve`, `test_settlement`): 892/892 pass, 0 fail, 0 error. 0 soft-scope warnings.
- **Fence:** the digest goldens are unchanged, `(0x51a1ed4c3c66413e, ...)`.
- **Repo gates:** planning-ID guard 355 (not above 355); `check_setup_names.py` 28 testmodules, 0 unresolved; JuliaFormatter 2.10.2 second pass returned true.

## Files Created/Modified

- `src/coordination/flex_clear.jl` (new, about 680 lines):
  - `FLEX_CONGESTION_KAPPA`, `FlexBidDevice` plus its `contribute!`;
  - `_refuse_fixed_capacitor`, `_stage2_aggregators`, `_redispatch_status`, `_redispatch`, `_congested_hours`;
  - `_deliver`, `_physics_error_status`, `_dispatch_record`, `_physics_record`, `_flex_physics`.
- `src/TSODSO.jl`: the include line after `flex_bids.jl`.
- `docs/src/api.md`: the Coordination `Pages` list, which now names `coordination/flex_clear.jl`.
- `test/test_flex_market.jl`: the stage-2 and delivery fixtures, 6 new items and the extended tolerance table.

## Physics record (for 45-04)

The fields, in order:
- `status`, `notes`, `price`;
- `baseline`, with `net`, `utility`, `battery_certificate`, `battery_message` and the `n_battery_*` counts;
- `bids`, a `Vector{FlexBids}`;
- `u`, `w` (`Vector{Matrix}`, T × K per aggregator), `Δ`, `π` (`Vector{Vector}`, per aggregator);
- `congested`, `congestion_scores`, `kappa_lo`, `kappa_hi`;
- `targets`;
- `delivered`, with the same shape as `baseline`;
- `shortfall` (per aggregator), `shortfall_total`, `shortfall_10w_total`;
- `weight`, `maxgap`, `p_import_stage2`, `max_wash`;
- `n_probe_solves`, `n_probe_failed`, `bid_repair_max`, `min_bid_ask_gap`;
- `wall_s`.

On a non-ok status, the fields that were not computed are `nothing`.

## Decisions Made

- **Only offered blocks get variables.** A zero width would otherwise give a `[0, 0]`-bounded variable. Clarabel would return about 1e-12 for it, not 0, and the bounds are degenerate for an interior-point method. With constants instead, all-zero bids give `Δ == 0` exactly, which the test asserts with `==`.
- **`_redispatch_status` returns `nothing`** for errors that are not solver outcomes, and the caller calls `rethrow()` inside its catch block. `rethrow(err)` outside a catch context would itself fail, and this shape lets the mapping be tested directly.
- **The record does not keep `ctx2`,** which would retain the JuMP model in memory. Everything 45-04 needs (π, Δ, the accepted blocks, `p_import_stage2`, delivered nets) is copied out as plain `Float64`. `congestion_scores` and `targets` are extra fields beyond the plan's list, added for reporting.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Input validation] Early refusal of a non-ascending bus order**
- **Found during:** Task 1
- **Issue:** `settlement_input` refuses a non-ascending stash, but only after the stage-2 solve.
- **Fix:** `_stage2_aggregators` throws `ArgumentError` before any solve. It is tested.
- **Commit:** 49e0448

**2. [Rule 2 - Input validation] Guards on `_congested_hours` and `_flex_physics`**
- **Found during:** Task 1 and Task 2
- **Issue:** `_congested_hours` divides by λ₀[t], so a short or non-positive λ₀ needed a guard. `_flex_physics` also needed guards on λ₀ length and finiteness and on an empty population.
- **Fix:** each case is an `ArgumentError`, and each is tested.

**3. [Measurement] Separate tolerance for the other hours in the over-reach case**
- **Found during:** Task 2
- **Issue:** the plan expected the non-over-reach hours to stay within the separable tolerance. Measured, they are at 3.18e-9: interior-point noise once hour 2 is pushed to its `Pmin` bound. The separable pipeline value is only 3.06e-12.
- **Fix:** the other hours are pinned at their own measured 3x (9.53e-9), and the separable tolerance stays 9.17e-12. The tolerance was measured, not loosened.

**4. Docstring commit before FMT:** the formatter joins a code span that wraps across lines into one 140-character line. The docstring was reworded in its own `docs` commit, so the style commit stays whitespace-only (content-loss OK).

**5. `test/test_exports.jl` unchanged:** every new name is internal (`TSODSO._name` / `TSODSO.FlexBidDevice`), so the export keep list needed no change, as with 45-02.

Otherwise the plan executed as written.

## Issues Encountered

None.

## Known Stubs

None.

## Next Phase Readiness

- 45-04 can build:
  - the uniform rows from `phys.π[k][t]·phys.Δ[k][t]`;
  - the PAB rows from `phys.u[k]` / `phys.w[k]` with `phys.bids[k].up_m` / `dn_g`;
  - the β phantom rows from `phys.congested`;
  - the ledger from `phys.delivered.net`.
- The κ interval and the congestion scores are available for the β documentation.

## Self-Check: PASSED

- FOUND: src/coordination/flex_clear.jl, test/test_flex_market.jl
- FOUND commits: 1c3fdc8, 49e0448, d13917f, e3744a7, 19a96e4, cd7c600
