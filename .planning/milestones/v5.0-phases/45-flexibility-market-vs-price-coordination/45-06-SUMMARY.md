---
phase: 45-flexibility-market-vs-price-coordination
plan: 06
subsystem: settlement / coordination / measurement
tags: [julia, scripts, csv, flex-market, ieee13, ieee123, provenance, testitems]

requires:
  - phase: 45-05
    provides: compare_tariffs(...; flex_market, welfare_optimizer), FLEX_EXTRA_COLUMNS, flex bill/rebound delivery_shortfall
provides:
  - "scripts/tariff_comparison.jl: --flex-market, --record-timeout, modes ieee123 and ieee123-default, flex_markets_for, assert_dadp_reproduces"
  - "Committed flex-market measurement rows on IEEE-13 and IEEE-123 in results/settlement_comparison/ (plus a new rebound_hourly.csv)"
  - "test/test_flex_market_ieee.jl (slow IEEE-13 compare item + fast committed-CSV invariant item), test/test_flex_market_ieee123.jl (slow smoke)"
affects: [45-07]

tech-stack:
  added: []
  patterns:
    - "Provenance guard: the in-run dadp row is compared with the committed one after a CSV round trip (isequal, no tolerance) before any upsert"
    - "Opt-in script paths write only their own rows (tariff prefix filter); the default ieee13-ground and case-a-784 paths are unchanged"

key-files:
  created:
    - test/test_flex_market_ieee.jl
    - test/test_flex_market_ieee123.jl
    - results/settlement_comparison/rebound_hourly.csv
  modified:
    - scripts/tariff_comparison.jl
    - results/settlement_comparison/tariff_comparison.csv
    - results/settlement_comparison/household_bills.csv

key-decisions:
  - "run_wall_s is stamped only on the new paths (ieee13-ground --flex-market rows, both IEEE-123 modes, --record-timeout rows); the default ieee13-ground and case-a-784 paths stay exactly as before and the committed base rows keep run_wall_s missing"
  - "--flex-market on case-a-784 is refused with ArgumentError in comparison_main (compare_tariffs refuses houses with flex_market)"
  - "ieee123 modes require --t-horizon 24 (the copied temperature and price profiles are 24-hour days)"
  - "ieee123-default uses build_feeder(:ieee123) == ieee123_modified(), the :mem prices and the default optimizer, the research probe's exact configuration"
  - "The TOU-baseline flex redispatch on ieee13-ground is ALMOST_OPTIMAL at the default optimizer and is recorded as error:SolveFailedError status rows; no conditioning was added (never re-tuned)"
  - "SUMMARY_COLS was not extended (optional in the plan): header-only creation on a fresh checkout stays the base schema"

requirements-completed: []  # SETL-07/08 are marked by the final plan of the phase (45-07)

duration: 36min
completed: 2026-11-05
---

# Phase 45 Plan 06: Flex-market script modes and committed measurement Summary

**`scripts/tariff_comparison.jl` can now clear flexibility-market legs (`--flex-market`) and run two IEEE-123 configurations. The committed CSVs gain:**
- 8 ieee13-ground flex rows, written after a bitwise check that the in-run dadp row reproduces the committed one;
- the certified ieee123 run: 4 base rows plus 6 flex rows, all flex rows ok and AC feasible;
- an honest `ieee123-default` `(run) error:CertificateError` row.

Every pre-existing row is unchanged.

## Performance

- **Duration:** about 36 min
- **Started:** 2026-11-05T03:23:00Z
- **Completed:** 2026-11-05T03:59Z
- **Tasks:** 2/2, plus one FMT style commit
- **Files modified:** 6 (3 created)

## Accomplishments

- **Script flags and modes:**
  - `--flex-market` is a boolean flag, parsed as `"--flex-market" in args`.
  - `--record-timeout S` writes a `(run)` row with status `timeout`, `run_wall_s = S` and notes `stopped after S s wall`, without solving.
  - The modes are now `ieee13-ground`, `case-a-784`, `ieee123` and `ieee123-default`.
  - The default seeds are `SEED_IEEE123 = 20260719` and `SEED_IEEE123_DEFAULT = 20260718`.
  - The header documents every new mode and flag, and lists `rebound_hourly.csv` under Outputs.
- **Flex sets (`flex_markets_for`):**
  - ieee13-ground: flat × {uniform, pab} × β {0, 0.05, 0.1}, plus TOU × {uniform, pab}. That is 8 legs and 2 clears.
  - ieee123 (and ieee123-default): the 6 flat legs, 1 clear.
- **Provenance guard (`assert_dadp_reproduces`):**
  - It runs before any write and compares `welfare`, `aggregators_total` and `status` after a CSV round trip, using `isequal`.
  - It errors and writes nothing on any difference, on a missing committed row or on a refused in-run DADP.
  - On this run it **passed bitwise**: welfare `-4823.014448023751`, aggregators_total `0.06554196555750413`, status `ok`.
- **ieee13-ground flex path:**
  - It upserts only the `flex_*` rows: summary (with `run_wall_s`), bills (with `delivery_shortfall`) and rebound (to `rebound_hourly.csv`).
  - The base rows are never back-filled.
- **IEEE-123 population:** copied verbatim from `scripts/actor_behaviour_sweep.jl`, which copies `test/fixtures_ieee123.jl`. The only change is that seed and T are arguments. The source is cited in a comment, and the fixture file is not included.
- **Conditioning:** `ieee123` uses `welfare_optimizer = select_optimizer(SOCP(); tol_gap_abs = 3e-9, tol_gap_rel = 3e-9)` with engine `:centralized`. τ, ε and the hybrid floor are untouched.

## Measured outcomes (quoted from the committed CSV)

### Wall times

| Mode | run_wall_s (compare call) | flex_wall_s per clear | Process wall |
|---|---|---|---|
| ieee13-ground --flex-market | 64.43 s | flat clear 16.26 s; TOU clear 12.23 s | ~1.5 min |
| ieee123 --flex-market | 215.62 s | flat clear 126.13 s (20,485 probe solves, 0 failed) | ~5 min |
| ieee123-default | 26.90 s (refused) | — | ~1.5 min |

### ieee13-ground --flex-market (seed 20260718, T = 24, centralized, default optimizer)

| Row | status | feasibility | welfare | aggregators_total | flex_payments_total | baseline_overpayment |
|---|---|---|---|---|---|---|
| flex_uniform | ok | feasible | -4822.902972574327 | 872.0088541893346 | 871.9456813087315 | 0.0 |
| flex_uniform_beta0.05 | ok | feasible | (same) | 877.8061963792213 | (same) | 5.79734218988689 |
| flex_uniform_beta0.1 | ok | feasible | (same) | 883.6035385691082 | (same) | 11.59468437977378 |
| flex_pab | ok | feasible | (same) | 208.408351569444 | 208.3451786888405 | 0.0 |
| flex_pab_beta0.05 | ok | feasible | (same) | 214.18483948125615 | (same) | 5.776487911812152 |
| flex_pab_beta0.1 | ok | feasible | (same) | 219.96132739306825 | (same) | 11.552975823624305 |
| flex_uniform_tou | error:SolveFailedError | not_run | missing | missing | missing | missing |
| flex_pab_tou | error:SolveFailedError | not_run | missing | missing | missing | missing |

- **Welfare gaps (flat clear):**
  - raw gap (flex − dadp) = **+0.11147544942468812**;
  - `welfare_gap_vs_dadp_lossless` = **−0.021660989005795273**, with `welfare_dadp_lossless` = −4822.881311585321 and `welfare_socp_import` = −4821.440555669784.
- **AC and congestion:**
  - The flex dispatch is AC **feasible**, with max_overload_ratio 0.96736. The flat and TOU base legs are `solve_failed`.
  - `n_congested_hours` = **9**, with κ = 0.01 inside the measured interval [6.09e-4, 0.7197).
  - `redispatch_socp_maxgap` = 2.07e-9.
- **Shortfall:**
  - `delivery_shortfall_total` = **0.296140167664805**, max 2.29e-3, ratio 1.25e-3.
  - At 10w, the total is 0.2961401530535588.
- **Money:**
  - **Uniform vs PAB:** flex payments 871.95 vs 208.35. PAB pays 663.60 less for the same physics.
  - `tariff_on_activation` = 36.33251277624433. `energy_merchandising_surplus` is 2.89973 on every row.
- **β overpayments:**
  - uniform: 5.797 at β 0.05 and 11.595 at β 0.1;
  - PAB: 5.776 and 11.553.
  - The welfare and the AC verdict are `==` across β.
- **TOU baseline:** the stage-2 redispatch solve ended ALMOST_OPTIMAL / NEARLY_FEASIBLE_POINT, so both legs are `error:SolveFailedError` status rows. The probes themselves ran fine: 1,842 solves, 0 failed, bid repair 1.5e-3. This is a measured outcome; no conditioning was added.

### ieee123 --flex-market (certified fixture population, seed 20260719, tol_gap 3e-9)

- **Base rows:**
  - dadp: ok, feasible, welfare −41035.404363490736, max overload 0.99999999597.
  - flat: ok, **infeasible**, 1 thermal violation at ratio 1.117207.
  - tou: ok, **infeasible**, 3 thermal violations at ratio 1.259551.
  - fit: `error:CertificateError`, SOCP inexact at ratio 2.497.
- **All 6 flex rows:** ok, AC **feasible**, welfare −41031.45804507148, max overload 0.99999998235.
- **Welfare gaps:**
  - raw gap (flex − dadp) = **+3.9463184192572953**;
  - `welfare_gap_vs_dadp_lossless` = **−1.809171709464863**, with welfare_dadp_lossless −41029.64887336201.
- **Congestion:** `n_congested_hours` = **1**, with κ = 0.01 inside [7.88e-4, 0.7199). `redispatch_socp_maxgap` = 7.44e-9.
- **Shortfall:** `delivery_shortfall_total` = **0.70933441617307**, max 7.05e-3, ratio 0.0745.
- **Uniform vs PAB:** flex payments 72.78343873359775 vs 62.74457621675646. aggregators_total is 62.759126756044736 vs 52.72026423920354.
- **Activation:** `tariff_on_activation` = 12.392942858589123. flex_up_total 9.036, flex_down_total 0.486.
- **β overpayment = 0.0 at every β.** The single congested hour is the reverse-flow PV-peak hour. By construction the phantom inflates only positive consumption baselines, and net exporters are not inflated. So β has no lever on this feeder, and the totals are `==` across β.
- **Battery certificates:** 29 of 85 baseline battery certificates are refused at flat, the same class the research measured.

### ieee123-default (build_population(:default, :ieee123), seed 20260718, default optimizer)

- **Result:** a `(run)` row with `error:CertificateError`, engine centralized, feasibility not_run, run_wall_s 26.90 s.
- **Message:** "SOCP relaxation INEXACT: worst gap/(atol_b+rtol·|cone|)=1.062285309572047 > 1 … max abs |l·v−(P²+Q²)|=3.137388504548255e-7". This matches the research measurement exactly (ratio 1.0623, gap 3.14e-7).

## Task Commits

1. **Task 1: script flag and modes, slow test files:** `1134c80` (feat)
2. **Task 2: committed measurement rows and the fast CSV invariant item:** `4e1dbf1` (feat)
3. **FMT style pass (script + both test files):** `af500f0` (style). `check_content_loss.py HEAD` reported OK, whitespace only.

## Test results

| Run | Result |
|---|---|
| Task 1 parse check (`include` + parse_args!/flex_markets_for asserts) | ok (re-run after FMT: ok) |
| `TSODSO_TEST_SET=all TSODSO_TEST_FILES=test_flex_market_ieee.jl` (IEEE-13 slow item) | 18/18 pass, 1m55s |
| `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_flex_market_ieee.jl` (CSV item) | 22/22 pass |
| IEEE-123 smoke, background, log at the scratchpad `flex_ieee123_smoke.log` | 6/6 pass, 7m14.7s, `exit=0`, "tests passed"; flex_uniform ok / feasible |
| After FMT: fast `test_flex_market_ieee.jl` + `test_flex_market_fence.jl` (45-01 fence) | 90/90 pass, 0 soft-scope warnings |

- **Repo gates:**
  - planning-ID guard: 355 (not above 355);
  - `check_setup_names.py`: 28 testmodules, 0 unresolved;
  - `check_scripts_index.py`: complete;
  - `check_script_api.jl scripts/tariff_comparison.jl`: OK;
  - JuliaFormatter 2.10.2: second pass true.
- **Test environment:** restored with `git checkout -- test/Project.toml test/Manifest.toml` after every run.

## CSV diff review

The check compared every committed CSV against a scratchpad copy taken before the first run:
- Every pre-existing row is identical in all of its original columns. The new trailing columns are empty on those rows, so nothing was back-filled, and the FIT `error:SolveFailedError` row is unchanged.
- **tariff_comparison.csv:** 5 old rows, plus 19 new ones (8 ieee13-ground flex, 10 ieee123, 1 ieee123-default). 35 new columns: the 34 flex extras plus `run_wall_s`.
- **household_bills.csv:** 30 old rows, plus 825 new ones, all `flex_*` or `ieee123`. 1 new column, `delivery_shortfall`.
- **rebound_hourly.csv** (new): 336 rows, all `flex_*` or `ieee123`.
- **equity_breakouts.csv:** unchanged. The bus-granularity legs emit no breakout rows.

## Deviations from Plan

### Auto-fixed Issues

**1. [Measured tolerance] The rebound shortfall sum is not `==` to the summary total**
- **Found during:** Task 2, the CSV item.
- **Issue:** the plan said "within the 45-05 measured tolerance". 45-05 measured an exact 0.0 on its 2-bus fixture. On these feeders:
  - the per-bus bill sums are still exact (0.0);
  - the per-hour rebound sums differ by up to 1.87e-16 relative (IEEE-13 5.55e-17 absolute, IEEE-123 −1.11e-16), because the summation order differs.
- **Fix:** bills are asserted with `==`. Rebound uses `rtol = 6e-16`, which is 3x the observed maximum. The measurement is recorded in the test file header.
- **Commit:** `4e1dbf1`

**2. [Scope] run_wall_s only on the new paths**
- **Issue:** the plan's 5b says "every summary row a mode writes", but the plan also says the default ieee13-ground and case-a-784 runs execute exactly as before.
- **Fix:** `run_wall_s` is stamped on the flex rows of ieee13-ground, on every ieee123 and ieee123-default row, and on `--record-timeout` rows. The default paths do not stamp it. The CSV item asserts that the ieee13-ground base rows have `run_wall_s` missing, which guards against back-fill.

**3. [Rule 2 - Input validation] `--flex-market` with `case-a-784` is refused** with ArgumentError in `comparison_main`. compare_tariffs would refuse it anyway, but only after the long population build. The ieee123 modes also refuse `--t-horizon` other than 24.

**4. [Formatter] The verbatim profile arrays were expanded one value per line** by JuliaFormatter. The repo uses no `#! format: off` pragma, so the formatter's output was kept. The values are unchanged: content-loss is OK and the post-FMT parse check asserts them.

No other deviations. No gate, τ, ε or population was changed to obtain a row.

## Issues Encountered

None blocking. The TOU-baseline flex redispatch refusal on IEEE-13 (ALMOST_OPTIMAL at the default optimizer) is a measured outcome, recorded as status rows. 45-07 should quote it on the literate page as such.

## Known Stubs

None.

## Next Phase Readiness

- 45-07 (literate page) can read every number above from `results/settlement_comparison/tariff_comparison.csv`, including `run_wall_s` for the IEEE-123 wall time, from `household_bills.csv` and from `rebound_hourly.csv`.
- Reproduce:
  - `julia --project=. scripts/tariff_comparison.jl --mode ieee13-ground --flex-market`
  - `--mode ieee123 --flex-market` (about 5 min)
  - `--mode ieee123-default`

## Self-Check: PASSED

- FOUND: scripts/tariff_comparison.jl, test/test_flex_market_ieee.jl, test/test_flex_market_ieee123.jl, results/settlement_comparison/rebound_hourly.csv
- FOUND commits: 1134c80, 4e1dbf1, af500f0
