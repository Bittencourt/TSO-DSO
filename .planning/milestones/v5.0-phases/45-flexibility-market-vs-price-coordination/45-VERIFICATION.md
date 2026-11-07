---
phase: 45-flexibility-market-vs-price-coordination
verified: 2026-11-05T08:03:17Z
status: passed
score: 12/12 must-haves verified
overrides_applied: 0
human_verification:
  - test: "TOU-baseline flexibility legs on IEEE-13 (flex_uniform_tou, flex_pab_tou) are recorded as error:SolveFailedError"
    expected: "The researcher accepts the ALMOST_OPTIMAL / NEARLY_FEASIBLE_POINT stage-2 outcome at the default optimizer as a measured refusal row (flex_wall_s 12.23 s), not re-tuned, or opens a follow-up to measure it under a documented conditioning seam"
    why_human: "Research judgment: whether a near-optimal Clarabel stop counts as a refusal or should be examined under conditioning"
  - test: "Uniform vs pay-as-bid payment gap on IEEE-13"
    expected: "Sign-off on flex_payments_total 871.9457 (uniform) vs 208.3452 (pay-as-bid), a difference of 663.60, against a DADP merchandising surplus of 2.99. The docs attribute this to energy mispricing: the flat level is 0.1534 vs mean λ₀ 5.6042 (ratio 0.027), activated up 236.88 and down 0. On IEEE-123 the figures are 72.78 vs 62.74"
    why_human: "Interpretation of the money split and of the energy-mispricing framing"
  - test: "tariff_on_activation overlap"
    expected: "Accept 36.3325 on IEEE-13 (12.3929 on IEEE-123) as the documented tariff-plus-clearing-price overlap of the locked settlement design"
    why_human: "Market-design judgment (user-approved 2026-11-04; confirm that the measured magnitude is acceptable)"
  - test: "β has no effect on IEEE-123"
    expected: "Accept that baseline_overpayment is 0 at β = 0.05 and β = 0.10 because the only congested hour (n_congested_hours = 1, hour 12) is a reverse-flow export hour (flat-baseline net load −4.086). On IEEE-13 (9 congested hours) the overpayment is 5.797/11.595 (uniform) and 5.776/11.553 (pay-as-bid), exactly linear"
    why_human: "Whether the IEEE-123 β sweep is an informative measurement or needs a different congestion fixture"
  - test: "10× delivery-penalty heuristic and the upper-bound claim"
    expected: "Accept w = 90 (ten times the largest price) as a heuristic. Shortfall totals are 0.2961 on IEEE-13 (ratio 1.25e-3) and 0.7093 on IEEE-123 (ratio 7.45e-2, about 7.4 % of the activated volume); the changes at 10w are −1.46e-8 and −2.38e-7. The upper-bound statement covers totals only (not the worst bus-hour), relative to the relaxed battery model"
    why_human: "Theoretical claim about the penalty's exactness that cannot be verified by grep or tests"
  - test: "Baseline battery-certificate refusals"
    expected: "baseline_batt_refused = 10 on IEEE-13 and 29 on IEEE-123 (the stage-1 flat baseline); the delivered flex rows have batt_refused = 0. The docs page prints the count only for IEEE-123 (section 10); the IEEE-13 count of 10 is not mentioned. Decide whether to add it"
    why_human: "Documentation completeness and research disclosure judgment"
  - test: "IEEE-123 default-population refusal"
    expected: "Accept ieee123-default (run) = error:CertificateError, gap ratio 1.062285 > 1 (run_wall_s 26.9 s), recorded and never re-tuned; the certified fixtures population at tol_gap 3e-9 is the IEEE-123 measurement"
    why_human: "Honesty-policy acceptance of which IEEE-123 configuration is the headline"
  - test: "Lossless vs lossy welfare convention"
    expected: "Accept that flex welfare uses the lossless import while DADP uses the loss-inclusive SOCP import. Raw gap +0.1115 / +3.9463 (flex appears better); like-for-like lossless gap −0.0217 (relative −4.49e-6) / −1.8092 (relative −4.41e-5); DADP loss cost 0.1331 / 5.7555 (IEEE-13 / IEEE-123)"
    why_human: "Choice of comparison convention for thesis reporting"
  - test: "Uniform clearing price vs DADP price on the IEEE feeders"
    expected: "price_gap_vs_dadp_max is 4.636 (IEEE-13) and 3.820 (IEEE-123), against the 9.18e-2 band measured on the 2-bus test fixture. Confirm that the docs' first-welfare-theorem framing (equality only with exact separable bids) is stated strongly enough given this distance"
    why_human: "Interpretation of the first-welfare-theorem analogue"
  - test: "FIT has no numeric row in any flexibility-bearing scenario"
    expected: "Accept that SETL-08 'across FIT' is met by status rows. IEEE-13 FIT is error:SolveFailedError (pre-existing, unchanged); IEEE-123 FIT is error:CertificateError (ratio 2.497). The five-scheme table with all-numeric rows exists only on the 2-bus test fixture"
    why_human: "Requirement-interpretation judgment under the honesty policy"
  - test: "Out-of-phase touches"
    expected: "Accept the src/pricing/dlmp.jl change: only a `_DLMP_RECON_FAIL` constant is extracted, the thrown message is byte-identical and the error type is unchanged after the iteration-3 WR-01 fix. Also accept the docs/src/api.md @autodocs fill for 8 pre-existing files: devices/ElectricVehicle, HeatPump, SmartInverterPV and Behavioural; models/complementarity_ev; actors/actor_objective, Portfolio and efficiency"
    why_human: "src/pricing/ is a golden directory by policy; scope acceptance is the researcher's call"
  - test: "Full docs build and prose fidelity of docs/literate/flex_market.jl"
    expected: "Run julia --project=docs docs/make.jl (not run by the orchestrator or by 45-07, which proved checkdocs only with a reduced build) and review the page prose. The verifier ran the page standalone: exit 0, and every number printed matches the CSV"
    why_human: "Prose correctness is listed as manual-only in 45-VALIDATION.md; the full docs build is heavy"
---

# Phase 45: Flexibility Market vs Price Coordination Verification Report

**Phase Goal:** A researcher can run a DSO flexibility market as an alternative to price-based coordination and compare all schemes in one table.
**Verified:** 2026-11-05T08:03:17Z
**Status:** human_needed
**Re-verification:** No, this is the initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | **SC1:** A researcher runs a flexibility market with an explicit baseline and payment rule (uniform or pay-as-bid) and gets the same settlement record as price-based coordination | ✓ VERIFIED | `FlexMarket(; baseline_tariff, payment_rule, n_blocks, baseline_inflation)` validates its inputs (`src/coordination/coordination.jl`). The exported `clear_flex_market` (`flex_settle.jl`) calls the same primitive `build_settlement_ledger` (`source = :flex_market`, `flex_payments` mirror pairs, flow (e) in `SettlementLedger.jl:493-507`), so the conservation fold `residual == 0.0` throws otherwise. Flex rows carry the 37 base summary columns plus 34 additive columns. The test "settlement record conserves for both rules and every β" asserts `ledger_residual == 0.0` for {uniform, pay-as-bid} × β ∈ {0, 0.05, 0.10} × 3 seeds |
| 2 | **SC2:** A comparison table reports welfare, per-actor surplus, network feasibility and equity across FIT, TOU, flat, DADP and the flexibility market on the same scenario | ✓ VERIFIED (see human item on FIT) | `compare_tariffs(...; flex_market)` appends the flex rows after dadp/flat/tou/fit through `vcat(...; cols = :union)` (`comparison.jl`). The committed `tariff_comparison.csv` has ieee13-ground dadp/flat/tou/fit + 8 flex rows and ieee123 dadp/flat/tou/fit + 6 flex rows. Each row has welfare, dso/aggregators/wholesale totals, `feasibility_status` and `max_overload_ratio`, and gini/theil/atkinson/palma on bills and surplus. FIT appears as a status row in both IEEE modes |
| 3 | Default path byte-identical: the fence was captured before any src edit and is still green | ✓ VERIFIED | Commit 295b928 (the first phase commit) touches only `test/test_flex_market_fence.jl` and `expected_broken.txt`; the first src commit is 31da05d. The digest tuple is unchanged since capture (formatting only). The verifier's run on Julia 1.12.5 (the default channel) logged the same digests `(0x51a1…, 0xf4e1…, 0x082f…, 0x5515…, 0xe386…)`, and the assertion is active, not skipped |
| 4 | Defaults `flex_market = nothing` / `welfare_optimizer = nothing` reproduce the default call exactly; the early return is unchanged | ✓ VERIFIED | Code: the flex branch is entered only when `flex_markets !== nothing`, and the welfare_optimizer `if/else` makes the exact default call. Fence items "comparison keywords default unchanged" and "welfare_optimizer contract and guards" pass |
| 5 | Truthful, convex, hour-separable bids from probing each aggregator's own model, with PAV repair, range floor and counts reported | ✓ VERIFIED | `flex_bids.jl` (381 lines). The tests for the interruptible anchor, V(b) reproduction, zero range and guards/monotone repair pass with measured tolerances (header table, 3× the observed max) |
| 6 | Stage 2 reuses `solve_welfare` (same feeder, pf, exactness gate); failures become statuses, never throws | ✓ VERIFIED | `_redispatch` → `solve_welfare(...)` over `FlexBidDevice` pseudo-aggregators. `_redispatch_status` maps INFEASIBLE to `infeasible_redispatch`, `:socp_exact` to `inexact_redispatch` and other solver errors to `error:<Type>`, and anything else is rethrown. Committed evidence: `flex_*_tou` rows are `error:SolveFailedError` |
| 7 | Uniform price is the dual of the stage-2 nodal balance read through the gated `settlement_input` | ✓ VERIFIED | `flex_clear.jl:307,713`: `π` comes from `rd.input2.prices` |
| 8 | Uniform and pay-as-bid give identical dispatch, welfare and AC status, and differ only in money | ✓ VERIFIED | One physics record per (baseline, n_blocks) key. CSV: identical welfare and max_overload across the 6 flat rows of each mode. Test "payment rules differ only in money" passes |
| 9 | β changes money only; overpayment reported and linear | ✓ VERIFIED | CSV: physics identical across β. IEEE-13 overpayment ratio at β 0.10/0.05 is 2.000000 for both rules. Test "baseline inflation changes money only" passes |
| 10 | Liveness: the welfare gap to the centralized optimum shrinks as n_blocks goes 1→16 | ✓ VERIFIED | Test "liveness against the centralized optimum" asserts a strictly decreasing gap, the upper bound, and a final gap ≤ 7.92e-4 (3× 2.64e-4 measured). It passes |
| 11 | Committed artifacts: CSV rows upserted with provenance, base rows never back-filled, refusals as status rows, run wall time recorded | ✓ VERIFIED | The 5 pre-existing rows are byte-identical to `295b928~1` (a column-by-column check, with all new columns empty). `run_wall_s` is present on every new-path row. ieee123-default `(run)` = `error:CertificateError` (ratio 1.062). The script has `--flex-market`, `ieee123`, `ieee123-default` and `assert_dadp_reproduces` |
| 12 | Literate page computes every number from the CSV and is registered in make.jl and scripts/README.md; api.md surfaces the coordination files | ✓ VERIFIED | `docs/literate/flex_market.jl` reads the CSVs through `find_row` and `num`, with no typed results; λ₀ comes from the script's own generators. Verifier ran it standalone: exit 0, and the output matches the CSV. Registration was verified in `docs/make.jl` (the literate list and the Experiments nav) and in `scripts/README.md` (`check_scripts_index.py` passes). The api.md Coordination block lists all 4 files |

**Score:** 12/12 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/coordination/coordination.jl` | types, row naming | ✓ VERIFIED | 174 lines; exports AbstractCoordination, PriceBased and FlexMarket |
| `src/coordination/flex_bids.jl` | bid probing | ✓ VERIFIED | 381 lines |
| `src/coordination/flex_clear.jl` | stage 2, congestion, delivery | ✓ VERIFIED | 782 lines |
| `src/coordination/flex_settle.jl` | payment rules, `clear_flex_market` | ✓ VERIFIED | 384 lines; exported |
| `src/settlement/SettlementLedger.jl` | `flex_payments` flow | ✓ VERIFIED | V5 validation and flow (e) mirror pairs |
| `src/settlement/comparison.jl` | `flex_market` / `welfare_optimizer` keywords, `FLEX_EXTRA_COLUMNS` | ✓ VERIFIED | +563 lines; guards run before any solve |
| `src/TSODSO.jl` | include chain | ✓ VERIFIED | The coordination files load after equity.jl and before comparison.jl; `test_exports.jl` lists all 4 symbols |
| `scripts/tariff_comparison.jl` | flag and modes | ✓ VERIFIED | |
| `results/settlement_comparison/*.csv` | committed measurements | ✓ VERIFIED | 24 summary rows; `rebound_hourly.csv` is new |
| `docs/literate/flex_market.jl` | literate page | ✓ VERIFIED | 678 lines; runs standalone |
| `test/test_flex_market*.jl` | tests | ✓ VERIFIED | 4 files, 26 test items |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| `clear_flex_market` | `build_settlement_ledger(...; flex_payments)` | `_flex_settle` | ✓ WIRED |
| `_redispatch` | `solve_welfare` + `settlement_input` | optimizer passthrough | ✓ WIRED |
| `_congested_hours` | `decompose_dlmp(ctx2)` | κ = 1e-2 with a reported interval | ✓ WIRED |
| `compare_tariffs` | `_flex_tables` → `vcat(...; cols = :union)` | opt-in branch | ✓ WIRED |
| `ieee123_main` | `compare_tariffs(...; welfare_optimizer = tol_gap 3e-9, flex_market)` | script | ✓ WIRED |
| literate page | `tariff_comparison.csv`, `rebound_hourly.csv` | quote-aware reader | ✓ WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| docs page tables | every printed number | committed CSV cells + the script's λ₀ generators | yes | ✓ FLOWING |
| flex summary rows | welfare / money | delivered dispatch utilities + ledger balances | yes | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Targeted fast flex tests | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_flex_market.jl,test_flex_market_fence.jl,test_flex_market_ieee.jl julia --project=. -e 'import Pkg; Pkg.test()'` | 1454/1454 pass, 3m41s, exit 0 (test env restored afterwards) | ✓ PASS |
| Literate page runs from the CSV | `julia --project=docs docs/literate/flex_market.jl` | exit 0; the numbers match the CSV | ✓ PASS |
| Scripts index | `python3 .github/scripts/check_scripts_index.py` | complete (47 files) | ✓ PASS |
| Setup names | `check_setup_names.py` | 0 unresolved | ✓ PASS |
| Planning-ID guard | `check_planning_ids.py` | 355 hits (ceiling 355) | ✓ PASS |
| Full suite | orchestrator, at HEAD c74f874 | 36668 / 0 / 0 / 7 broken (allowlisted) | ✓ PASS (not re-run) |

### Probe Execution

Not applicable: the phase declares no probe scripts.

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|--------------|-------------|--------|----------|
| SETL-07 | 45-01..04, 06, 07 | Flexibility market with explicit baseline and payment rule, same settlement record | ✓ SATISFIED | Truths 1, 5–10 |
| SETL-08 | 45-01, 05, 06, 07 | Comparison table across FIT, TOU, flat, DADP and the flexibility market | ✓ SATISFIED (FIT shown as status rows on IEEE, see the human item) | Truths 2, 4, 11, 12 |

No orphaned requirements: REQUIREMENTS.md maps only SETL-07 and SETL-08 to Phase 45.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| phase-modified files | — | TBD/FIXME/XXX/TODO/HACK | none found | — |
| `src/pricing/dlmp.jl` | 276-281, 419 | out-of-phase edit to a golden directory (constant extraction only) | ℹ️ Info | The message and error type are unchanged; listed for sign-off |

Project policies checked:
- **Default path byte-identical:** verified (fence digests active on 1.12.5).
- **Goldens not re-pinned:** verified (no golden or canary files in the phase diff; the fence digest tuple is unchanged since capture).
- **Tolerances measured, not picked:** verified (header table in `test_flex_market.jl`, 3× the observed max or exact `==`).
- **Certificates report and never throw:** verified (`ac_feasibility_status` is recorded; stage-2 certificate errors become statuses).
- **Refusals become status rows:** verified (TOU flex rows, IEEE-123 FIT, ieee123-default `(run)`).
- **Null results stated honestly:** verified. The page prints "NULL (exactly zero)" when the gap is 0; the measured gaps are non-null and negative.

### Human Verification Required

1. **TOU-baseline flex rows:** `flex_uniform_tou` and `flex_pab_tou` on IEEE-13 end in `error:SolveFailedError` (ALMOST_OPTIMAL / NEARLY_FEASIBLE_POINT, flex_wall_s 12.23 s). Decide whether to accept this as a refusal or measure it under conditioning.
2. **Uniform vs pay-as-bid payments on IEEE-13:** 871.9457 vs 208.3452 (Δ 663.60), against a DADP merchandising surplus of 2.99. The flat level is 0.1534 vs mean λ₀ 5.6042 (0.027×), so the market mostly buys energy-value correction. On IEEE-123 the figures are 72.78 vs 62.74.
3. **tariff_on_activation:** 36.3325 on IEEE-13, 12.3929 on IEEE-123.
4. **β has no effect on IEEE-123:** the only congested hour is hour 12, a reverse-flow export (net −4.086), so the overpayment is 0 at every β. On IEEE-13 it is exactly linear (ratio 2.000000).
5. **10× delivery penalty (w = 90) is a heuristic:** the upper-bound claim covers totals only. The IEEE-123 shortfall ratio is 7.45 % of the activated volume.
6. **Baseline battery-certificate refusals:** 10 on IEEE-13 and 29 on IEEE-123. The docs mention only the IEEE-123 count.
7. **IEEE-123 default-population refusal:** gap ratio 1.062285, recorded and not re-tuned.
8. **Lossless vs lossy welfare convention:** raw gaps are +0.1115 / +3.9463, lossless gaps −0.0217 / −1.8092.
9. **Clearing-price distance from DADP on the IEEE feeders:** 4.636 / 3.820, against the 9.18e-2 band on the 2-bus fixture.
10. **FIT is a status row in every flexibility-bearing scenario:** the five-scheme table has all-numeric rows only on the 2-bus fixture.
11. **Out-of-phase touches:** `src/pricing/dlmp.jl` (constant extraction only) and the `docs/src/api.md` fill for 8 pre-existing files.
12. **Full `docs/make.jl` build and prose review of the page:** neither has been run. The page itself runs standalone.

### Gaps Summary

There are no gaps. Both roadmap success criteria and all 12 must-have truths are backed by code, committed artifacts, passing targeted tests (1454/1454) and a standalone run of the literate page. The status is `human_needed` only because the listed research-judgment points need the researcher's sign-off.

---

_Verified: 2026-11-05T08:03:17Z_
_Verifier: Claude (gsd-verifier)_

## Human Verification Outcome (2026-11-05)

The researcher reviewed all 12 human-verification items and chose **"Accept + doc touch-up"**.
Every item is accepted as a measured, documented limitation. None is a gap.

The doc touch-up in `docs/literate/flex_market.jl` changed three things:

- **Section 2:** the `price_gap_vs_dadp_max` print is now read against the two-bus band (9.18e-2).
  The IEEE gaps of 4.6357 and 3.8205 are more than 40× that band. The page now says plainly that the
  uniform clearing price is not a DADP-price estimate on these feeders, and that the
  first-welfare-theorem framing holds for welfare totals only.
- **Section 8:** a new computed print shows refused baseline battery certificates per feeder:
  10 on IEEE-13 and 29 on IEEE-123, with 0 delivered refusals on both. This fills the missing
  IEEE-13 count.
- **Section 12:** two new limitation bullets, one on the refused baseline battery certificates and one
  saying clearing prices are not DLMP estimates.

The page was re-run standalone (`julia --project=. docs/literate/flex_market.jl`): exit 0, and the
printed numbers match the CSVs. The full `docs/make.jl` build is still pending (item 12).

Out-of-scope changes: the researcher chose **"Keep both"**, the `src/pricing/dlmp.jl` message
constant and the `docs/src/api.md` fill for 8 pre-existing files.
