---
phase: 41-settlement-ledger-equity
verified: 2026-10-26T09:23:10Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Eyeball the BL-01 sign-convention flip: :fit leg wholesale_total = sum(λ₀·p_import) and merchandising_surplus = dso_total − wholesale_total, matching the ledger convention"
    expected: "The fit leg's per-actor totals read with the same payment-sign semantics as the other legs; conservation still exact (confirmed numerically in the committed CSV: fit row dso+aggs+wholesale = 0)"
    why_human: "REVIEW-FIX explicitly marks this fixed item 'requires human verification' — the semantic choice of sign convention deserves an eyeball beyond the numeric pin"
  - test: "Build docs (julia --project=docs docs/make.jl) and view the rendered 'Settlement, Tariffs & Equity' page"
    expected: "Page renders with the live tiny slice, the CSV-sourced heavy sections, the locked no-income-data statement, and honest presentation of the flat/tou :solve_failed statuses and the fit-leg A1 batteryless asymmetry"
    why_human: "Rendered output quality and honest narrative presentation cannot be verified by grep; Literate page registration at both make.jl sites is code-verified but rendering is not"
---

# Phase 41: Settlement, Ledger & Equity Verification Report

**Phase Goal:** A researcher can settle any run into a money-conserving per-actor ledger, compare tariff schemes on the same network and population, and read equity and rebound outcomes.
**Verified:** 2026-10-26T09:23:10Z
**Status:** human_needed (all automated truths VERIFIED; 2 human items remain)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A run settles into a ledger over DSO, each aggregator, each household and wholesale, and a test shows actors sum to zero with an explicit merchandising-surplus line | ✓ VERIFIED | `SettlementLedger.jl` (478 ln): double-entry `_push_transfer_pair!`, explicit `merchandising_surplus` named line (struct field, L94), construction-time guard throws on any non-zero residual (L392–397). `test/test_settlement.jl` L45/L49: `ledger_residual(led) == 0.0`, `sum(values(led.balances)) == 0.0`; MS ↔ `welfare_accounting(ctx).dso` oracle at L74/L355 (rtol 1.479974182716057e-15, measured-pin). Committed CSV independently conserves: `dso_total + aggregators_total + wholesale_total = 0` exactly on every data row (verified by awk over `tariff_comparison.csv`) |
| 2 | FIT, TOU, flat and nodal DADP tariffs can be compared on the same network and population, with flat and TOU derived revenue-neutral from the DADP run | ✓ VERIFIED | `comparison.jl` `compare_tariffs(feeder, pf, aggs; ...)`: ONE solved DADP run → four legs `["dadp","flat","tou","fit"]` on the SAME feeder+population, fixed leg order, legs never dropped (honest status rows). Revenue neutrality: `tariffs.jl` `revenue_neutral_flat`/`revenue_neutral_tou` derive from the run's own `bus_nets`; hand-computed anchors `flat == [30.0, 30.0]`, `tou == [15.0, 37.5]` asserted `==` on totals in tests (L440–448) AND reproduced in a fresh Julia process during this verification. Fairness echo visible in committed artifact: dadp `total_payments` = flat `fairness_total` = −0.065541965557504 (agreement ~1e-16). Committed ieee13-ground comparison has all 4 tariff rows; the 784-house ADMM refusal-at-iters-80 is a committed `error:CertificateError` status row — a MEASURED RESULT per plan pre-authorization (judged on mechanism + ieee13-ground comparison per verification context) |
| 3 | Each tariff's resulting dispatch has an AC-physics network-feasibility status that is reported, never thrown | ✓ VERIFIED | `feasibility.jl` (415 ln): `FeasibilityStatus` docstring "REPORTED status — never thrown"; `ACPowerFlow(; limits = false)` + `SMAX_NO_LIMIT` thermal/voltage per-hour diagnostics. Tests cover ALL three outcomes: `:feasible` (L826), `:infeasible` with branch-hour detail (L857–862), `:solve_failed` recorded-never-thrown (L900–922). End-to-end proof in committed artifact: dadp=feasible, flat/tou=solve_failed (recorded with fit-leg `notes` carrying termination status `INFEASIBLE`), fit=not_run — report semantics working, no throw anywhere |
| 4 | Gini, Theil, Atkinson and Palma on per-household bills/surplus pass known-value tests, including negative values, and results are broken out by PV owner/non-owner, electrical location and load level, with the writeup stating no income data is used | ✓ VERIFIED | `test_equity.jl` (351 ln): uniform anchor `(0,0,0,0.25)` exact (L12–23); negative-value anchors `gini([-2,1,3,6]) == 0.8125`, negative-mean mirror `gini([-3,-1]) == -0.25`, `palma([-2,1,3,6]) == -3.0`, Theil/Atkinson exclusion counts REPORTED (`n_excluded == 1`, never silently dropped), Gini never computed after zeroing negatives. Breakouts: `equity_breakdown` + `load_terciles` tests (L150–283) and `test_settlement.jl` L1332 "equity breakouts by pv_group / bus / load tercile (synthetic two-house)"; `comparison.jl` L343–353 builds `("pv_group","bus","load_tercile")` groupings from map_rows + Σ Pdc. No-income statement locked in `docs/literate/settlement_equity.jl` L17–22 ("NO income data exists in this framework and none is used anywhere"), reinforced L95/L336. Anchors independently reproduced in a fresh Julia process during this verification |
| 5 | A rebound metric reports load shifted into later hours after price-driven reductions | ✓ VERIFIED | `equity.jl` L339 `rebound(...)` returns single number + per-hour detail; known-value tests L286–311: `rebound_amount == 2.0`, `rebound_ratio == 0.4` exact, NaN on identical profiles. Reproduced in fresh Julia process. Wired into comparison: `rebound_amount`/`rebound_ratio` columns on flat/tou rows vs the dadp baseline (dadp row is baseline: 0.0/NaN by construction, committed CSV confirms); per-hour rebound detail DataFrame returned by `compare_tariffs` |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `src/settlement/SettlementLedger.jl` | Ledger types, double-entry, MS named line, exact residual, household refinement | ✓ VERIFIED | 478 ln (min 100); exact-by-construction guard + `ledger_residual` |
| `src/settlement/run_inputs.jl` | SettlementInput + centralized/ADMM adapters with status guard | ✓ VERIFIED | 367 ln (min 70); `ctx.meta[:agg_net]`/`:p_import` stash reads (L100), loud `ArgumentError` guards, `:converged`-path key requirement (L9/L56); hardened post-review to typed `UnconvergedAdmmError` (commit 0e6c7ca) |
| `src/settlement/equity.jl` | 4 metrics + breakouts + terciles + rebound | ✓ VERIFIED | 360 ln (min 150); convention docstrings; exported |
| `src/settlement/tariffs.jl` | Revenue-neutral flat/TOU + pinned bins | ✓ VERIFIED | 294 ln (min 80); `bus_nets` weights (L262); `default_tou_bins(24)` pinned 6/12/6 (test L452–453) |
| `src/settlement/price_taker.jl` | Penalty-free counterfactual QP + certificate report semantics | ✓ VERIFIED | 186 ln (min 80); `contribute!` verbatim (L9/L54); `CertificateError` → recorded `:refused` (L137) |
| `src/settlement/feasibility.jl` | FeasibilityStatus, report-never-throw | ✓ VERIFIED | 415 ln (min 100); all three status outcomes tested |
| `src/settlement/comparison.jl` | compare_tariffs runner → 4 DataFrames | ✓ VERIFIED | 765 ln (min 120); fixed leg order, no file IO in src/, `fit_baseline` consumed as-is with A1 asymmetry documented (L42–47) |
| `test/test_settlement.jl` | Conservation/MS/sign/guard/tariff/feasibility items | ✓ VERIFIED | 1470 ln (min 150); `@test_throws ArgumentError` guards throughout |
| `test/test_equity.jl` | Known-value certificates incl. negatives | ✓ VERIFIED | 351 ln (min 120) |
| `scripts/tariff_comparison.jl` | Artifact producer, upsert + provenance | ✓ VERIFIED | 586 ln (min 150); `upsert_row` (L206), `provenance_row` (L222), run-level honest status rows |
| `results/settlement_comparison/tariff_comparison.csv` | Committed comparison artifact | ✓ VERIFIED | 5 data rows (4 tariff legs + 784 run-refusal status row) + header; provenance columns; conservation = 0 on every row |
| `results/settlement_comparison/household_bills.csv` | Committed bill/surplus rows | ✓ VERIFIED | 30 bus-granularity rows (ieee13-ground, fit-leg bus granularity marked per A1) |
| `results/settlement_comparison/equity_breakouts.csv` | Per-group equity rows | ⚠️ HONEST-EMPTY | Header-only, disclosed in 41-04-SUMMARY ("header-only breakouts (honest empty)"). Consequence of two measured facts: (a) the 784-house ADMM run was refused at iters=80 (pre-authorized measured result), and (b) ieee13-ground ran bus-granularity (no houses/map_rows ⇒ no group rows by construction, comparison.jl L249). The breakout MECHANISM is fully verified by tests (test_equity L178–283, test_settlement L1332). Docs page handles the empty CSV (filter → empty loop, L251–257) |
| `docs/literate/settlement_equity.jl` | Writeup with no-income statement | ✓ VERIFIED | 337 ln (min 80); locked statement L17–22; reads committed CSVs (L186, L332) |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `run_inputs.jl` | `pricing/welfare.jl` | `ctx.meta[:agg_net]` / `:p_import` stash reads | WIRED | L7/L81/L100 |
| `run_inputs.jl` | `admm/solve_admm.jl` | `:converged` guard + additive keys | WIRED | `:converged`-only keys (L9), `ArgumentError` (L56); upgraded to typed `UnconvergedAdmmError` (WR-05 fix) |
| `test_settlement.jl` | `welfare_accounting` | MS cross-check oracle | WIRED | L65–74, L355 measured-pin rtol 1.48e-15 |
| `tariffs.jl` | `run_inputs.jl` | `bus_nets` weights | WIRED | L19/L262/L273 |
| `price_taker.jl` | `devices/Aggregator.jl` | `contribute!` | WIRED | L9/L54/L77 |
| `feasibility.jl` | `pricing/fit.jl` idiom | `SMAX_NO_LIMIT` / `limits = false` | WIRED | L14/L40/L107–110 |
| `price_taker.jl` | `assert_battery_complementarity!` | `CertificateError` → recorded status | WIRED | L30/L66/L137 `err isa CertificateError` |
| `comparison.jl` | `pricing/fit.jl` | `fit_baseline` consumed as-is | WIRED | L7/L21/L36, leg 4 at L644+ |
| `tariff_comparison.jl` | `case_a_scaling.jl` idiom | upsert/provenance/CertificateError | WIRED | L31–34/L149/L198–222 |
| `settlement_equity.jl` | `results/settlement_comparison/*.csv` | heavy sections read committed CSVs | WIRED | L14/L186/L332 |
| `docs/make.jl` | `settlement_equity.jl` | BOTH sites | WIRED | Literate source list L57 + pages list L107 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `tariff_comparison.csv` | per-leg rows | `compare_tariffs` ← solved-run stashes (`ctx.meta`) | Yes — 5 measured rows incl. welfare −4823.0144 (matches the pinned canary magnitude for this fixture class) | ✓ FLOWING |
| `household_bills.csv` | bill/surplus | ledger settlement of the run's own quantities | Yes — 30 rows, signed values both signs present | ✓ FLOWING |
| `equity_breakouts.csv` | per-group metrics | groupings from map_rows (house granularity only) | No rows on committed runs — measured-empty (784 refusal + bus-granularity ieee13 mode) | ⚠️ EMPTY-BY-MEASUREMENT (mechanism verified by tests; not a wiring defect) |
| `settlement_equity.jl` (docs) | tables | committed CSVs (precomputed-results precedent) | Yes for bills/summary; breakouts section reads the header-only CSV and no-ops | ✓ FLOWING (empty-safe) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Equity known values incl. negatives reproduce | fresh `julia` process: gini/theil/atkinson/palma anchors | All `OK` (uniform (0,0,0,0.25); gini-neg 0.8125; gini-negmean −0.25; palma-neg −3.0; exclusion counts) | ✓ PASS |
| Revenue-neutral anchors | fresh `julia` process: `revenue_neutral_flat`/`_tou` on hand anchor | `flat == [30.0, 30.0]`, `tou == [15.0, 37.5]`, totals identity `==` | ✓ PASS |
| Rebound known value | fresh `julia` process | amount 2.0, ratio 0.4 exact | ✓ PASS |
| load_terciles labeling | fresh `julia` process | `[:low ×3, :mid ×4, :high ×3]` (floor/floor/remainder-to-middle) | ✓ PASS |
| Committed artifact conserves | awk over tariff_comparison.csv | `dso+aggs+wholesale = 0` on every data row | ✓ PASS |
| Full test suite | plan-execution gate | 32,949 pass / 0 fail (orchestrator-reported); REVIEW-FIX re-ran fast affected suite 492/492 | ✓ PASS (gate-recorded) |

Note: fresh-process checks ran ~15 s each (Julia startup + package load), above the 10 s spot-check guideline — recorded honestly; they are pure-function re-computations, no servers started, no state modified.

### Probe Execution

No `probe-*.sh` scripts declared by the phase plans and none exist under conventional locations — Phase 41's runnable verification contract is the Julia test suite (run at the plan-execution gate) plus the artifact producer `scripts/tariff_comparison.jl`, whose output artifact was committed and re-verified arithmetically above. Step 7c: N/A (no declared probes).

| Probe | Command | Result | Status |
| ----- | ------- | ------ | ------ |
| (none declared) | — | — | N/A |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| SETL-01 | 41-01 | Per-actor ledger (DSO/aggregators/households/wholesale), conserved, explicit MS line | ✓ SATISFIED | Truth 1 |
| SETL-02 | 41-03, 41-04 | Compare FIT/TOU/flat/DADP on same network+population; flat & TOU revenue-neutral from DADP | ✓ SATISFIED | Truth 2 |
| SETL-03 | 41-03 | AC-physics feasibility as reported status, never thrown | ✓ SATISFIED | Truth 3 |
| SETL-04 | 41-02 | Gini/Theil/Atkinson/Palma, sign-safe, known-value tests | ✓ SATISFIED | Truth 4 |
| SETL-05 | 41-02, 41-04 | Breakouts by PV ownership / electrical location / load level; writeup states no income data | ✓ SATISFIED | Truth 4 |
| SETL-06 | 41-02 | Rebound metric: load shifted into later hours after reductions | ✓ SATISFIED | Truth 5 |

**Orphaned requirements:** none. REQUIREMENTS.md maps exactly SETL-01..06 to Phase 41; all six are claimed by plans (41-01: SETL-01; 41-02: SETL-04/05/06; 41-03: SETL-02/03; 41-04: SETL-02/05). SETL-07/08 are correctly mapped to Phase 45 (Pending) and not claimed here.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| (none) | — | No TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER markers in any phase-owned file; no console-only handlers, no empty implementations, no static stub returns found | — | — |

Informational (not a gap): `deferred-items.md` records pre-existing JuliaFormatter drift in two files this phase does NOT own (`src/experiments/materialize.jl`, `test/test_population_case_a_scaling.jl`) — pre-dates Phase 41, explicitly reverted untouched per scope boundary, left for the phase owner before the next CI format job.

Code review: 41-REVIEW.md — all 6 critical+warning findings fixed (41-REVIEW-FIX.md, 6/6, fast suite 492/492); 6 INFO findings intentionally out of fix scope.

### Human Verification Required

### 1. BL-01 sign-convention eyeball (from code-review fix report)

**Test:** Review the `:fit` leg's `wholesale_total = sum(λ₀[t]·p_import[t])` and `merchandising_surplus = dso_total − wholesale_total` flip in `src/settlement/comparison.jl` against the ledger's `balances[:wholesale] = +Σ λ₀·p_import` convention.
**Expected:** All legs read with one consistent payment-sign semantics; conservation exact (already numerically confirmed: fit row sums to 0 in the committed CSV).
**Why human:** 41-REVIEW-FIX.md explicitly marks this fixed item "requires human verification" — the semantic choice deserves an eyeball beyond the numeric pin.

### 2. Rendered docs page

**Test:** `julia --project=docs docs/make.jl`, open the generated "Settlement, Tariffs & Equity" page.
**Expected:** Live tiny slice renders; CSV-sourced heavy sections render; the locked no-income-data statement is prominent; the flat/tou `:solve_failed` statuses, the fit-leg `error:SolveFailedError` row, the A1 batteryless asymmetry and the 784-house refusal row are presented honestly rather than hidden.
**Why human:** Rendering quality and narrative honesty cannot be verified by grep; registration at both make.jl sites (L57, L107) is code-verified but output is not.

## Gaps Summary

No gaps. All five roadmap success criteria are met at the mechanism level with committed-artifact corroboration and fresh-process behavioral reproduction. The two honesty-policy artifacts — the 784-house ADMM refusal row and the header-only equity_breakouts.csv — are measured outcomes of pre-authorized plan semantics (statuses recorded as rows, legs never dropped), not failures of the phase goal; the comparison MECHANISM (four legs on one feeder+population) and the committed ieee13-ground comparison satisfy criterion 2 as directed by the verification context. Status is `human_needed` solely because two items require human judgment (a sign-convention semantic and rendered-docs presentation) — not because any automated truth failed.

---

_Verified: 2026-10-26T09:23:10Z_
_Verifier: the agent (gsd-verifier)_

---

## Human Verification Resolution (2026-10-27)

Both human_verification items RESOLVED via conversational UAT (41-HUMAN-UAT.md, status: complete, commit 13d537d):

1. **BL-01 sign-convention eyeball — PASS.** comparison.jl:719 `+Σ λ₀·imp_total` matches ledger-sign legs (:534/:633) and header spec (:39-41); :733 surplus = collections − wholesale; BL-01 pin green in 346/346 settlement suite (pure-consumer receipt ≈ +12.0, pre-fix −12). User confirmed.
2. **Rendered docs page — PASS.** docs/build/generated/settlement_equity.html (fresh vs source 558b27c) renders the no-income statement ("operate on BILLS only — no income data exists to use"), the fit leg as honest error:SolveFailedError, flat/tou solve_failed rows with measured values, and the refusal-attribution prose. User confirmed.
