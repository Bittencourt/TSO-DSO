---
phase: 45-flexibility-market-vs-price-coordination
plan: 05
subsystem: settlement / coordination
tags: [julia, dataframes, compare-tariffs, flex-market, jet, testitems, fence]

requires:
  - phase: 45-04
    provides: clear_flex_market, _baseline_price, _flex_settle (agg-bus list), market_agg peaked fixture
  - phase: 45-03
    provides: _flex_physics record, FLEX_CONGESTION_KAPPA, tight_agg fixture
  - phase: 45-01
    provides: default-path digest fence, FlexFenceFixtures (SUMMARY_COLUMNS), _flex_row_name, coordination_label
provides:
  - "compare_tariffs(...; flex_market, welfare_optimizer): opt-in flexibility-market rows appended to summary, household_bills and rebound"
  - "FLEX_EXTRA_COLUMNS (34 additive columns), _flex_extras, _flex_status_row, _flex_tables, _flex_market_list, _with_shortfall_column (all internal)"
  - "welfare_optimizer conditioning seam: centralized DADP solve plus every redispatch; ArgumentError under engine = :admm"
affects: [45-06, 45-07]

tech-stack:
  added: []
  patterns:
    - "Opt-in rows go through their own DataFrame and vcat(base, flex; cols = :union); the default return statement is unchanged"
    - "One keyword-only extras builder with every key defaulting to missing, so ok and status rows cannot diverge in schema"
    - "Physics plus AC once per (baseline_tariff, n_blocks) clear key, money per FlexMarket"
    - "A try expression as the bound value (nothing on a mapped failure) instead of local-then-assign, for JET"

key-files:
  created: []
  modified:
    - src/settlement/comparison.jl
    - src/coordination/flex_clear.jl
    - test/test_flex_market.jl
    - test/test_flex_market_fence.jl

key-decisions:
  - "welfare_optimizer with engine = :admm throws ArgumentError before any solve (solve_admm takes no optimizer); flex_market is still allowed under :admm, and its redispatch then runs at the default SOCP optimizer"
  - "With flex_market, houses, an empty vector, non-FlexMarket entries, duplicate row names and any FixedCapacitor in the population throw ArgumentError in the compare_tariffs guard block, before the DADP solve"
  - "energy_merchandising_surplus = dso_total + flex_payments_total + baseline_overpayment (tariff collections minus wholesale)"
  - "delivery_shortfall_ratio and price_gap_vs_dadp_max are NaN on an ok row with no activation; price_gap uses bus-hours with |Δ| > FLEX_RANGE_FLOOR"
  - "Flex bill and rebound tables always carry delivery_shortfall, even when every clear is a status row (no rows)"
  - "The JET reports from the stage-2 redispatch (flex_clear.jl) were fixed in code, not baselined"

requirements-completed: []  # SETL-08 is listed by this plan, but the phase marks requirements in its final plan (as 45-01..04 did for SETL-07)

duration: 28min
completed: 2026-11-05
---

# Phase 45 Plan 05: Flexibility market in the comparison table Summary

**`compare_tariffs` now reports DADP, flat, TOU, FIT and any number of flexibility-market rows on the same scenario.**
- The flex rows are opt-in (`flex_market = FlexMarket()` or a vector). They are appended through their own table and `vcat(...; cols = :union)`, with the 37 base columns plus 34 additive columns.
- A `welfare_optimizer` seam conditions the centralized DADP solve and every redispatch. With `engine = :admm` it is refused before any solve.
- The default call is unchanged: the 45-01 digests are identical, and the new keywords at `nothing` give `isequal` tables.

## Performance

- **Duration:** about 28 min
- **Started:** about 2026-11-05T02:53Z (23:53 -0300)
- **Completed:** 2026-11-05T03:21Z
- **Tasks:** 2/2, plus one JET fix commit and one FMT style commit
- **Files modified:** 4

## Accomplishments

- **Keywords:**
  - `flex_market = nothing` and `welfare_optimizer = nothing` come after `agr_optimizer`.
  - Both are documented in the docstring, including the `:admm` decision, the FixedCapacitor refusal and the bill and rebound shortfall column.
  - A neutral "FLEX-MARKET LEGS (opt-in)" paragraph is in the header comment.
- **Guards** (before λ₀vec, so before any solve):
  - `:admm` with a non-`nothing` `welfare_optimizer`, using the planned message;
  - `_flex_market_list` normalisation, which refuses a non-FlexMarket scalar, a vector with a non-FlexMarket entry, an empty vector and duplicate row names;
  - `houses` combined with `flex_market`;
  - any `FixedCapacitor` device when `flex_market !== nothing`.
- **DADP call:** an if/else shape. `nothing` runs the original call text unchanged; otherwise it passes `optimizer = welfare_optimizer`. The `:admm` branch is untouched.
- **`_flex_tables`:**
  - It groups markets by `(baseline_tariff, n_blocks)` in first-appearance order. Per key it runs `_baseline_price` (with the comparison's `bins`), then `_flex_physics(...; optimizer = welfare_optimizer)`, then one `ac_feasibility_status` on the delivered nets when the clear is ok.
  - Per FlexMarket, in input order, it runs `_flex_settle` and builds `merge(_summary_row(...), _flex_extras(...))` with the research mapping. Equity goes through `_equity_columns` at bus granularity, and rebound is measured against the DADP net load.
  - Bill rows (one per bus) and rebound rows (one per hour) use the base row shapes plus `delivery_shortfall`: summed over hours on bills, over buses on rebound.
  - Status rows come from `_flex_status_row`, with the same field set and no bill or rebound rows.
- **Return path:** only when `flex_market !== nothing`, the summary, household_bills and rebound tables are `vcat(base_df, flex_df; cols = :union)`. `equity_breakouts` is unchanged, and the default `return` executes exactly as before.

### Final FLEX_EXTRA_COLUMNS (34, in order, after the 37 base columns)

`coordination baseline_tariff payment_rule n_blocks baseline_inflation flex_payments_total energy_merchandising_surplus tariff_on_activation flex_payment_on_delivered flex_up_total flex_down_total delivery_shortfall_total delivery_shortfall_max delivery_shortfall_ratio delivery_shortfall_total_10w tracking_weight baseline_overpayment n_congested_hours congestion_kappa congestion_kappa_lo congestion_kappa_hi redispatch_socp_maxgap redispatch_p_import_total welfare_socp_import welfare_dadp_lossless welfare_gap_vs_dadp_lossless price_gap_vs_dadp_max bid_repair_max min_bid_ask_gap max_wash n_probe_solves n_probe_failed baseline_batt_refused flex_wall_s`

This matches the plan's list exactly. `keys(_flex_extras()) == FLEX_EXTRA_COLUMNS` is asserted, so the const and the row builder cannot drift apart.

## Measured values

These come from the peaked market fixture (`market_agg`), 2-bus, T = 3, `bins = [[1, 2], [3]]`, default solver everywhere, three markets: uniform, PAB and uniform with β = 0.05. They were measured on Julia 1.12.5 with a scratch script outside the repo.

| Quantity | 20260719 | 20260720 | 20260721 | Pinned |
|---|---|---|---|---|
| flex row status (all three markets) | ok | ok | ok | asserted ok |
| AC feasibility of the flex rows | infeasible | feasible | feasible | set membership |
| PAB − uniform aggregators_total | −8.21e-3 | −1.13e-2 | −7.05e-3 | `<` (strict, no slack) |
| Σ bill `delivery_shortfall` − summary total | 0.0 | 0.0 | 0.0 | `==` |
| Σ rebound `delivery_shortfall` − summary total | 0.0 | 0.0 | 0.0 | `==` |
| delivery_shortfall_total | 1.06e-11 | 1.09e-11 | 1.11e-11 | not asserted |
| welfare_gap_vs_dadp_lossless (uniform) | −1.38e-2 | −1.89e-2 | −1.07e-2 | finite, and `==` welfare − welfare_dadp_lossless |
| tariff_on_activation | 1.013 | 0.970 | 0.829 | finite |
| β = 0.05 baseline_overpayment | 0.299 | 0.305 | 0.290 | `> 0`; uniform row `== 0.0` |
| price_gap_vs_dadp_max | 7.5e-3 | 6.0e-3 | 7.3e-3 | not asserted |
| n_congested_hours | 1 | 1 | 1 | `==` across β |

- The PAB, overpayment and tariff-on-activation values match 45-04's numbers. Seed 1's AC verdict is again `infeasible`, at a ratio of 1 + 5e-9.
- **Counting factory on the tight fixture:** exactly 1 call without a flex market (the DADP solve) and exactly 2 with `FlexMarket()` (DADP plus one redispatch). Every guard case gives 0 calls.
- **Warm wall time:** the three-market `compare_tariffs` call takes about 0.15 s. The first call in a process takes about 11 s, mostly compilation.

## Task Commits

1. **Task 1: keywords, guards, DADP passthrough, fence items:** `2355f0e` (feat)
2. **Task 2: flex rows, FLEX_EXTRA_COLUMNS, integration item:** `27f5300` (feat)
3. **Task 2 JET fix in the stage-2 redispatch:** `042295f` (fix)
4. **FMT style pass:** `1351ebe` (style). `check_content_loss.py` reported OK, whitespace only.

## Test results

- **Task 1 verify** (fence plus `test_settlement`): 374/374 pass.
- **Task 2 verify** (`test_flex_market`, the fence, `test_settlement`, `test_actor_settlement`, `test_exports`): 1766/1766 pass, 0 fail, 0 error. This held before the JET fix, after it, and again after FMT.
- **Soft-scope warnings:** 0.
- **Fence:** the digests are unchanged, `(0x51a1ed4c3c66413e, 0xf4e1569ddabc1b5f, 0x082f2207b4e88cc4, 0x5515555ce78f74e5, 0xe386f1abc04d04c8)`.
- **JET** (Julia 1.12.7, `julia +1.12`, run alone): `jet_check: 20 current, 20 baseline, 0 NEW, 0 FIXED`, exit 0. `git diff -- scripts/jet_baseline.txt` is empty.
- **Repo gates:**
  - planning-ID guard: 355 (not above 355);
  - `check_setup_names.py`: 28 testmodules, 0 unresolved;
  - JuliaFormatter 2.10: second pass true;
  - `check_content_loss.py`: OK.

## TDD Gate Compliance

- **Task 1:** the fence items were written before the source edit, but they were not run and committed as a separate RED commit. Test and implementation landed together in `2355f0e`.
- **Task 2:** the integration item was written alongside the implementation, after a scratch measurement that fixed the tolerances, and landed together in `27f5300`.
- **No `test(...)` RED commit exists for this plan.** The default-path fence that guards the change predates it (45-01).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug, JET] Fixed 5 new JET reports in `src/coordination/flex_clear.jl` (45-03 code)**
- **Found during:** Task 2, the first full ratchet run: 25 current against 20 baseline, 5 NEW.
- **Issue:**
  - `local ctx2` was assigned inside `try`, which gave four "may be undefined" reports in `_redispatch`.
  - The Nothing branch of the union-split `rd.ctx2` reached `_congested_hours`, which gave a kwcall MethodError report.
  - Both came from phase-45 code that had not been JET-checked before this plan.
- **Fix:**
  - The solve is now the value of the try expression (`nothing` on a mapped outcome), and the early return checks `ctx2 === nothing`.
  - `_flex_physics` narrows with `rd.ctx2::ModelContext` after the ok check.
  - Behaviour is unchanged: 1766/1766 tests pass after the fix.
- **Files modified:** src/coordination/flex_clear.jl, which is not in the plan's files_modified list.
- **Commit:** `042295f`

**2. [Ordering] Counting-factory reach assertion split across the two tasks**
- **Issue:** the two-call reach check (DADP plus redispatch) needs the flex leg, which Task 2 builds.
- **Fix:** Task 1 asserts exactly 1 call (DADP only, with no flex market). Task 2 adds the exactly-2-calls assertion with `flex_market = FlexMarket()`. Both are in the fence item.
- **Commits:** `2355f0e`, `27f5300`

**3. [Fixture] The integration item uses the peaked `market_agg` fixture, not the plain tight fixture**
- **Issue:** the plan said "hermetic tight fixture", but on the tight fixture the β phantom is structurally 0 under the flat baseline (45-04 deviation 1). `baseline_overpayment > 0` would fail there.
- **Fix:** the integration item uses `market_agg`. The tight fixture is still used for the counting-factory reach check and the guards.

**4. [Rule 2 - Robustness] The `delivery_shortfall` column is always present on the flex bill and rebound tables**
- **Issue:** when every clear is a status row, the flex bill and rebound tables would have no rows and therefore no `delivery_shortfall` column.
- **Fix:** `_with_shortfall_column` adds an empty column, so the appended schema does not depend on the solver outcome. This is tested on the status path.

**5. [Rule 2 - Input validation] An empty `flex_market` vector is refused** with `ArgumentError` before any solve. The plan did not list it; the message says to pass `nothing`.

**6. `scripts/jet_baseline.txt` unchanged:** it is listed in files_modified, but zero growth was achieved, so the file needed no change.

## Issues Encountered

None.

## Known Stubs

None.

## Next Phase Readiness

- 45-06 and 45-07 can call `compare_tariffs(...; flex_market = [...], welfare_optimizer = ...)` to get all five schemes in one table.
- For IEEE-123, pass the documented `tol_gap = 3e-9` SOCP factory as `welfare_optimizer` with `engine = :centralized`.
- The flex columns are listed above. Status rows keep the schema stable.

## Self-Check: PASSED

- FOUND: src/settlement/comparison.jl, src/coordination/flex_clear.jl, test/test_flex_market.jl, test/test_flex_market_fence.jl
- FOUND commits: 2355f0e, 27f5300, 042295f, 1351ebe
