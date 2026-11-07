---
phase: 45-flexibility-market-vs-price-coordination
plan: 04
subsystem: coordination / settlement
tags: [julia, jump, clarabel, settlement-ledger, flex-market, payment-rules, liveness, testitems]

requires:
  - phase: 45-03
    provides: _flex_physics physics record, FLEX_CONGESTION_KAPPA, FlexMarketFixtures (tight_agg, feeder2)
  - phase: 45-02
    provides: build_settlement_ledger(...; flex_payments), FLEX_RANGE_FLOOR, FlexBids
  - phase: 41-settlement
    provides: flat_prices, tou_prices, default_tou_bins, ac_feasibility_status, settlement_input
provides:
  - "src/coordination/flex_settle.jl: _baseline_price, _FlexRow, _marginal_up_price, _flex_payment_rows, _flex_settle, clear_flex_market (exported)"
  - "clear_flex_market record: 17 fixed keys; status rows carry ledger/feasibility/rows/bills/surplus = nothing and money/welfare = missing"
  - "FlexMarketFixtures: market_agg (peaked congested-up fixture), cent_opt, market_dadp, market_clear, row_total, activation_value, caught"
affects: [45-05, 45-06, 45-07]

tech-stack:
  added: []
  patterns:
    - "Physics computed once per clear; the payment rule and β only build rows, so physics columns are == across rules and β by construction"
    - "Every non-zero accepted quantity is booked (interior-point noise included), so row quantities sum to Δ and no threshold decides acceptance"
    - "Default TOU bins resolved only on the :tou path, before the physics, so a T = 3 flat clear never meets the 24-hour-only default"

key-files:
  created:
    - src/coordination/flex_settle.jl
  modified:
    - src/TSODSO.jl
    - test/test_flex_market.jl
    - test/test_exports.jl
    - docs/src/api.md

key-decisions:
  - "_flex_payment_rows and _flex_settle take the aggregator buses (physics order) as an extra positional argument: the physics record carries no bus list"
  - "clear_flex_market refuses input.T != T and aggregator buses != input.buses (one aggregator per bus) with ArgumentError before any solve"
  - "PAB books every block with a non-zero quantity; rejected blocks come back at about 1e-9 of either sign, so row direction is read from the bid matrix, not the sign"
  - "β phantom PAB price = the highest up block with u > FLEX_RANGE_FLOOR (fallback: highest non-zero block)"
  - "The β/money tests use a peaked market fixture (inelastic +0.5 pu in hour 2, head 0.15·p0[2]); the liveness and price-band items keep the tight fixture"

requirements-completed: []  # SETL-07 spans plans 01-07; the final plan of the phase marks it

duration: 27min
completed: 2026-11-05
---

# Phase 45 Plan 04: Flex-market settlement, payment rules and liveness Summary

**`clear_flex_market` is now exported and turns one physics record into a `SettlementLedger` with `ledger_residual == 0.0`:**
- delivered energy is settled at the baseline tariff, and the DSO pays λ₀ on the lossless delivered import;
- under the uniform rule each activated (bus, hour) is paid π·Δ; under pay-as-bid each block is paid at its own bid price;
- β phantom up-payments are booked as real ledger rows.

**The rules and β change money only; the physics is `==` across them.** On the hour-separable tight fixture, the uniform clear's welfare gap to the centralized optimum falls at every step of n_blocks 1 → 16, from about 0.05 to about 2e-4.

## Performance

- **Duration:** about 27 min
- **Started:** 2026-11-05T02:23Z (23:23 -0300)
- **Completed:** 2026-11-05T02:50Z
- **Tasks:** 2/2 (Task 1 RED + GREEN; Task 2 test-only), plus one docstring commit and one FMT style commit
- **Files modified:** 5 (1 created)

## Accomplishments

- **`_baseline_price`:** `flat_prices(input)` for `:flat`, with `bins` ignored. For `:tou` it calls `tou_prices(input; bins)`, using `default_tou_bins(input.T)` only when `bins === nothing`.
- **`_flex_payment_rows`:** builds concrete `Vector{_FlexRow}` rows:
  - uniform rows `(bus, t, π, Δ)` for each `Δ ≠ 0`;
  - PAB rows `(m_k, +u_k)` / `(g_k, −w_k)` for each non-zero block;
  - β phantom rows `β·max(−b, 0)` in congested hours with `Δ > FLEX_RANGE_FLOOR`.

  It also returns `flex_payments_total`, `baseline_overpayment`, `tariff_on_activation = Σ p_t·Δ` and `flex_payment_on_delivered` (uniform only; `missing` for PAB).
- **`_flex_settle`:**
  - It builds a local N×T uniform tariff matrix over `input.buses`, the delivered nets and utilities per bus, and `p_import_lossless = −Σ n`.
  - It calls the primitive `build_settlement_ledger(...; source = :flex_market, flex_payments = rows)`.
  - It derives bills and surplus per bus, `welfare_lossless` and `welfare_socp_import`.
- **`clear_flex_market` (exported):**
  - Order of work: input guards, then the baseline price, then `_flex_physics` once. On `ok` it then runs `ac_feasibility_status` (original aggs, delivered nets; report only) and `_flex_settle`.
  - A non-ok status returns the same 17 keys, with `nothing` and `missing` in place of uncomputed values. It never throws for a solver outcome.
  - The docstring carries the runnable usage sentence, the status values, the welfare convention, the reactive-power note and the "bid generation runs once per clear" note.
- **Wiring:**
  - the include comes after `flex_clear.jl`;
  - `clear_flex_market` is in the `test_exports.jl` keep list;
  - `coordination/flex_settle.jl` is appended to the api.md Coordination Pages list.

## Measured tolerances

The rule is 3x the observed maximum over seeds 20260719, 20260720 and 20260721, or `==` when the observed maximum is 0.0. An inequality that held with no violation on every seed is asserted strictly, with no slack. Values come from scratch scripts outside the repo, Julia 1.12.5, and are recorded in the `test/test_flex_market.jl` header.

| Quantity | 20260719 | 20260720 | 20260721 | Observed max | Pinned |
|---|---|---|---|---|---|
| \|Σ ledger balances\| (both rules × β ∈ {0, 0.05, 0.10}, market fixture, K = 4) | 4.55e-15 | 4.22e-15 | 3.11e-15 | 4.55e-15 | 1.37e-14 |
| Σ row price·qty − (payments + overpayment) | 0.0 | 0.0 | 0.0 | 0.0 | `==` |
| tariff_on_activation − independent Σ p·Δ | 0.0 | 0.0 | 0.0 | 0.0 | `==` |
| overpayment(0.10) − 2·overpayment(0.05) (both rules) | 0.0 | 0.0 | 0.0 | 0.0 | `==` |
| PAB − uniform aggregator balance | −8.21e-3 | −1.13e-2 | −7.05e-3 | −7.05e-3 (no violation) | `<` (strict) |
| Liveness Σ shortfall, max over K (tight, flat baseline) | 8.65e-11 | 7.98e-11 | 9.03e-11 | 9.03e-11 | 2.71e-10 |
| Liveness gap_16 = W* − welfare_socp_import | 1.55e-4 | 2.51e-4 | 2.64e-4 | 2.64e-4 | 7.92e-4 |
| Monotone noise: largest gap_{K'} − gap_K | −7.14e-4 | −3.74e-4 | −3.78e-4 | −3.74e-4 (no violation) | `<` (strict) |
| Upper-bound noise: largest welfare_socp_import − W* | −1.55e-4 | −2.51e-4 | −2.64e-4 | −1.55e-4 (no violation) | `<= W*` (no slack) |
| Price band \|π − λ\| at activated (bus, hour), K = 16 | 2.73e-2 | 3.06e-2 | 2.30e-2 | 3.06e-2 | 9.18e-2 |

In the liveness shortfall, K = 1 gives the largest value; for K ≥ 2 the shortfall stays below 4.8e-12.

### Liveness K-sweep (tight fixture, flat baseline from the centralized DADP run, `cent_opt()` at tol 1e-10)

W* is social welfare recomputed from utilities: `Σ inC.bus_utilities − λ₀ᵀ inC.p_import` from `settlement_input` on the centralized ctx. It is never an objective value.

| Seed | W* | gap_1 | gap_2 | gap_4 | gap_8 | gap_16 | gap_1/gap_16 |
|---|---|---|---|---|---|---|---|
| 20260719 | 0.197828 | 4.907e-2 | 1.096e-2 | 1.608e-3 | 8.688e-4 | 1.550e-4 | 317 |
| 20260720 | 0.550249 | 7.380e-2 | 1.679e-2 | 1.657e-3 | 1.283e-3 | 2.507e-4 | 294 |
| 20260721 | 0.538073 | 5.486e-2 | 1.154e-2 | 1.660e-3 | 6.420e-4 | 2.638e-4 | 208 |

All 15 clears are `ok`. The gap decreases at every refinement on every seed. The overall trend is roughly O(1/K²), though individual steps are uneven: a factor of 1.3 to 10 per doubling.

Interruptible is exactly hour-separable, so this is purely the bid-discretisation gap; this fixture has no hour-separability gap.

### Other measured values

- **Peaked market fixture, K = 4:**
  - only hour 2 is congested, with up-activation Δ₂ of 0.161, 0.158 and 0.132 pu;
  - κ interval: [7.9e-10, 0.206), [1.1e-11, 0.322) and [1.1e-11, 0.209);
  - shortfall: 1.06e-11, 1.09e-11 and 1.11e-11;
  - uniform flex payments: 1.032, 0.997 and 0.844; PAB: 1.024, 0.985 and 0.837;
  - β = 0.05 overpayment: 0.299, 0.305 and 0.290 (uniform);
  - tariff_on_activation: 1.013, 0.970 and 0.829;
  - flex_payment_on_delivered equals the uniform payment to about 7e-11.
- **AC status:** seed 1 is `:infeasible` at ratio 1 + 5.2e-9; seeds 2 and 3 are `:feasible`. This matches the research finding that the targets sit on the head-branch limit, so the test accepts any status in the AC set.
- **Peaked fixture K-sweep (not asserted):** the gap plateaus over K = 1, 2, 4 at 1.25e-2, 1.76e-2 and 9.56e-3, with noise steps up to +1.5e-11. It drops at K = 8, because hour 3's first down block only clears once it is narrow enough. That is why liveness keeps the tight fixture.

## Task Commits

1. **Task 1 RED, settlement-record / rule / β tests and market fixture:** `6ab2c2b` (test). It failed with `UndefVarError: clear_flex_market`.
2. **Task 1 GREEN, flex_settle.jl, include, export, api.md, pinned tolerances:** `d768e7a` (feat)
3. **Task 2, liveness and price-band items:** `a3ae3db` (test)
4. **Docstring reword so no code span wraps:** `a7d9916` (docs)
5. **FMT style pass:** `a9c592f` (style). `check_content_loss.py` reported OK.

## Test results

- **Task 1 verify** (`test_flex_market`, the fence, `test_exports`, `test_settlement`): 1380/1380 pass, 0 fail, 0 error.
- **Task 2 verify** (`test_flex_market.jl`): 1071/1071 pass.
- **After FMT, all four files:** 1413/1413 pass, 0 fail, 0 error, with no soft-scope warnings.
- **Fence:** the digests are unchanged, `(0x51a1ed4c3c66413e, 0xf4e1569ddabc1b5f, 0x082f2207b4e88cc4, 0x5515555ce78f74e5, 0xe386f1abc04d04c8)`.
- **Repo gates:**
  - planning-ID guard: 355 (not above 355);
  - `check_setup_names.py`: 28 testmodules, 0 unresolved;
  - JuliaFormatter 2.10.2: second pass true.

## TDD Gate Compliance

- **Task 1:** the RED commit `6ab2c2b` precedes the GREEN commit `d768e7a`.
- **Task 2 is test-only.** It cross-validates the behaviour Task 1 already shipped and touches no source file, so its tests passed on first run. There is no separate RED → GREEN pair, by the nature of the task.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Fixture] β tests use a peaked market fixture, not the plain tight fixture**
- **Found during:** Task 1, scratch measurement before writing the tests.
- **Issue:** with the flat baseline derived from the DADP run, the tight fixture's baseline sits below the hour-2 limit. Stage 2 therefore buys *down*-flex in the congested hour (Δ₂ ≈ −0.24), so the β phantom, which needs up-activation, is structurally 0 there. Sweeping smax (0.40 to 0.50 of the peak) did not change the sign.
- **Fix:** `market_agg` adds an inelastic +0.5 pu in hour 2 and sets the head branch at 0.15·p₀[2] above it. The flat baseline then overloads hour 2, and only hour 2 is congested, with up-activation of 0.13 to 0.16 pu. The design rationale is recorded in the fixture comment. The liveness and price-band items stay on the tight fixture, as planned.
- **Commit:** `6ab2c2b`

**2. [Rule 1 - Bug in the planned check] PAB row direction from the bid matrix, not the sign**
- **Found during:** Task 1 measurement.
- **Issue:** rejected blocks come back at about ±1e-9, some slightly outside [0, width]. A row's quantity sign therefore does not identify up or down.
- **Fix:** every non-zero block is still booked, so the quantities sum to Δ. The test now checks that each price belongs to `up_m[t, :]` or `dn_g[t, :]`, and the docstring states the convention.
- **Commit:** `d768e7a`

**3. [Rule 2 - Input validation] Guards in `clear_flex_market`**
- **Issue:** a mismatched `input.T`, or aggregator buses that differ from `input.buses`, would otherwise fail deep inside the ledger, after the solves.
- **Fix:** both cases raise `ArgumentError` before any solve, and both are tested.
- **Commit:** `d768e7a`

**4. Signature detail:** `_flex_payment_rows` and `_flex_settle` take `agg_buses` as an extra positional argument, because the physics record holds no bus list. `clear_flex_market` keeps exactly the planned signature.

**5. Liveness shortfall tolerance:** the plan said the shortfall should stay within "the separable tol" (9.17e-12, measured at K = 4 on 45-03's π₀ baseline). Under the flat baseline the K = 1 clear reaches 9.03e-11, so it has its own measured pin of 2.71e-10. The tolerance was measured, not loosened.

**6. Docstring commit before FMT:** the formatter joins wrapped code spans into overlong lines, the same damage case 45-03 hit. I set the formatted file aside in the scratchpad and restored the HEAD content per file with `git show`. I then reworded the docstrings in their own docs commit, so the style commit is whitespace-only.

Otherwise the plan executed as written.

## Issues Encountered

None.

## Known Stubs

None.

## Next Phase Readiness

- 45-05 can map `clear_flex_market`'s record onto `_summary_row` plus the appended columns, using:
  - `ledger.balances`, `bills` and `surplus`;
  - `welfare_lossless` and `welfare_socp_import`;
  - `feasibility`;
  - `baseline_overpayment`, `tariff_on_activation` and `flex_payment_on_delivered`;
  - the physics fields (shortfall, congested hours, maxgap, probe counts).
- Status rows already carry every key.

## Self-Check: PASSED

- FOUND: src/coordination/flex_settle.jl, test/test_flex_market.jl, test/test_exports.jl, docs/src/api.md
- FOUND commits: 6ab2c2b, d768e7a, a3ae3db, a7d9916, a9c592f
