---
phase: 41-settlement-ledger-equity
plan: 04
subsystem: settlement
tags: [tariff-comparison, compare_tariffs, measurement-artifact, committed-csv, case-a-784, literate-writeup, no-income-data, julia]

# Dependency graph
requires:
  - phase: 41-settlement-ledger-equity (plans 01–03)
    provides: "the complete computational core the runner assembles: SettlementInput adapters + double-entry ledger (01), equity metrics + rebound (02), tariff construction + price-taker + feasibility status (03)"
  - phase: 40-784-house-thesis-population
    provides: "build_population(:case_a_784), case_a_household_map, _case_a_house primitives, the Phase-40 measured battery-certificate refusal precedent"
  - phase: 35/39/40 measurement pattern
    provides: "committed-CSV artifact contract (upsert, provenance columns, honest status rows) and the literate precomputed-results page precedent"
provides:
  - "src/settlement/comparison.jl — compare_tariffs: one DADP run → four tariff legs (dadp/flat/tou/fit) settled and re-dispatched on the same feeder+population → summary/household_bills/equity_breakouts/rebound DataFrames, statuses recorded never dropped"
  - "scripts/tariff_comparison.jl — the measurement-artifact producer (ieee13-ground + case-a-784 modes, upsert CSV contract, provenance on every row, run-level honest status rows)"
  - "results/settlement_comparison/{tariff_comparison,household_bills,equity_breakouts}.csv — the committed comparison artifact incl. the 784-house ADMM refusal status row (iters=80)"
  - "docs/literate/settlement_equity.jl — the writeup page with the locked no-income-data statement, registered at both docs/make.jl sites, live slice executed end-to-end"
affects: [thesis settlement/equity analysis (researcher-facing artifacts), /gsd-verify-work phase gate, SETL-07/08 flexibility-market follow-ons]

# Tech tracking
tech-stack:
  added: []   # zero new packages (RESEARCH audit table empty by construction)
  patterns:
    - "Runner-as-assembly: compare_tariffs introduces no new solve/formulation — every leg consumes a tested seam; statuses recorded as rows, legs never dropped"
    - "Run-level honest status rows: a DADP-run refusal (CertificateError at executor defaults) is itself the committed artifact, keyed (mode, tariff='(run)', seed, t_horizon)"
    - "Line-oriented artifact CSVs: script flattens embedded newlines in status notes (flatten_note) so docs-page minimal readers stay per-line"
    - "Fairness echo column: fairness_total evaluates every derived tariff's prices on the DADP run's OWN quantities — the 41-03 revenue-neutrality condition carried into the artifact"

key-files:
  created:
    - src/settlement/comparison.jl
    - scripts/tariff_comparison.jl
    - results/settlement_comparison/tariff_comparison.csv
    - results/settlement_comparison/household_bills.csv
    - results/settlement_comparison/equity_breakouts.csv
    - docs/literate/settlement_equity.jl
  modified:
    - src/TSODSO.jl
    - test/test_settlement.jl
    - test/test_exports.jl
    - scripts/README.md
    - docs/make.jl

key-decisions:
  - "FIT-leg thermal infeasibility measured and attributed: on the congestion-calibrated IEEE-13 fixtures the batteryless (A4) FIT dispatch is genuinely PRIMAL_INFEASIBLE against the head-branch thermal rating (probe 2026-10-26: lifting ONLY the head smax to SMAX_NO_LIMIT makes fit_baseline converge, welfare -4822.1488652716525, SITE-2 ac_status LOCALLY_SOLVED) — recorded as honest error rows, never dropped, never re-tuned"
  - "ieee13-ground smoke mode pins seed 20260718 (the ground-fixture regression seed): the seed-42 default population's centralized run is refused at the battery-complementarity certificate (bus 5, t=16; product 5.78648310574336e-8 vs tau·Pmax² 6.25e-9) — that refusal was recorded as its own (run) status row; the thesis seed 42 stays LOCKED on case-a-784"
  - "784-house ADMM at executor defaults (ρ = ADMM().ρ, no tol changes) converged at iters=80 and was refused at the final battery-complementarity consolidation — the Phase-40 measured precedent reproduced; the status row IS the committed artifact and per-tariff 784 rows are honestly absent (no certified run to settle)"
  - "Ground-mode gate seed-42 refusal row is data: the first regeneration recorded it (seed-keyed upsert); the final committed CSV keeps the working ground comparison + both run-level refusal records documented in the script header and this summary"
  - "Battery-certificate counts cover the price-taker dispatches at each row's bills_granularity (per-house re-solves when houses are attributed, aggregator-level otherwise); dadp bus-level counts are :not_checked (the run IS the dispatch); fit is always :not_checked (batteryless A4)"

patterns-established:
  - "compare_tariffs return shape (summary/household_bills/equity_breakouts/rebound DataFrames, no file IO in src/) — the script owns persistence (the Phase-35/39/40 contract)"
  - "Gate-then-golden runner pins (measured 2026-10-26, Julia 1.12.5, 2-bus fixture): dadp fairness echo bitwise (floor 1e-15), flat echo rel 2.8658034134118547e-16 → 10×, tou echo bitwise (floor 1e-15)"

requirements-completed: [SETL-02, SETL-05]

# Metrics
duration: ~2h05m execution + 68m full-suite gate
completed: 2026-10-26
---

# Phase 41 Plan 04: Tariff Comparison Deliverable Summary

**The comparison deliverable assembled: `compare_tariffs` settles one DADP run and rebuilds all four tariff legs (DADP / flat / TOU / FIT) on the same feeder+population with per-leg welfare, ledger totals, AC-feasibility statuses, equity on bills AND surplus, rebound and breakouts; the measurement script commits the CSVs (ground comparison certified, 784-house ADMM refusal at iters=80 recorded as the honest status-row artifact); the literate writeup carries the no-income-data statement and reads the committed CSVs.**

## Performance

- **Duration:** ~2h05m execution (3 tasks) + 68m17s full-suite phase gate
- **Tasks:** 3/3 complete (Task 1 TDD: RED → GREEN; Tasks 2–3 auto)
- **Files:** 12 (6 created, 6 modified)

## Accomplishments

- **SETL-02 runner:** `compare_tariffs(feeder, pf, aggs; T, λ₀, engine, …)` — engines `:centralized` (solve_welfare) / `:admm` (solve_admm, loud non-`:converged` refusal); per-leg ledger settlement (dadp = the run's own numbers; flat/tou = 41-03's revenue-neutral derivations at penalty-free price-taker dispatches with the documented lossless frontier; fit = `fit_baseline` consumed via its documented `optimizer`/`on_inexact` kwargs only, solver-outcome failures → status rows); uniform `ac_feasibility_status` per leg; equity (gini/theil/atkinson/palma) on bills AND surplus with exclusion counts; `fairness_total` echo of the locked revenue-neutrality condition; rebound vs the dadp baseline; pv/bus/tercile breakouts with the A1 fit-leg exclusion. Guards (T-41-19): unknown engine, houses↔map_rows mismatch, missing map, duplicate buses — all pre-solve ArgumentErrors.
- **SETL-02/05 measurement artifact:** `scripts/tariff_comparison.jl` (case_a_scaling skeleton: DrWatson provenance, upsert contract, honest `run_compare_outcome`, BLAS pin, `--mode` entry) committed with `results/settlement_comparison/*.csv`. Ground mode certified three legs on the real feeder (see numbers below); BOTH run-level refusals (seed-42 ground battery certificate; case-a-784 ADMM at iters=80) recorded as status rows. Script indexed in `scripts/README.md` (CI guard green).
- **SETL-05 writeup:** `docs/literate/settlement_equity.jl` — no-income-data statement as its own emphasized block, a seconds-scale live slice (executed end-to-end during verification: exact residual 0.0, named MS line, revenue-neutrality totals equal, battery certificate `:ok`, AC `:feasible`, four metrics on household rows), heavy sections reading the committed CSVs via a quote-aware minimal reader, metric-conventions table, A1 asymmetry section, regeneration commands. Registered at BOTH `docs/make.jl` sites.
- **The committed comparison table (ieee13-ground, seed 20260718, T=24):**
  | tariff | welfare | total payments | merch. surplus | AC status |
  |---|---|---|---|---|
  | dadp | -4823.014448023751 | -0.06554196555750413 | +2.9896376546634444 | feasible |
  | flat | -5956.918644128607 | 36.22391728208873 | -1305.5821196861452 | solve_failed |
  | tou | -5304.404272993124 | 41.24981820478568 | -554.80212831957 | solve_failed |
  | fit | error:SolveFailedError (attributed thermal infeasibility) | — | — | not_run |
  The `fairness_total` column equals the dadp settlement on every derived leg (−0.065541965557504 vs −0.0655419655575041 — dust), confirming the revenue-neutrality condition on the real run. TOU rebound: amount 101.40766977440782, ratio 1557.3946045650391 (large load shift into later hours after peak reductions); flat rebound 0.0/NaN (no reduction hours); dadp 0.0/NaN (baseline == itself).
- **Golden policy held:** `git diff --exit-code src/pricing/ src/admm/ src/models/` clean at every commit; `fit_baseline` touched only through its documented kwargs.

## Task Commits

1. **Task 1: comparison.jl runner + hermetic and :slow suite tests** — `cd2819c` (test, RED) → `ab583b7` (feat, GREEN)
2. **Task 2: scripts/tariff_comparison.jl + committed CSVs + scripts/README.md index** — `cb3b9aa` (includes the note-flattening CSV hygiene fix; commit amended once from `c400773` before any dependent commit — atomicity preserved)
3. **Task 3: docs/literate/settlement_equity.jl + both make.jl registrations** — `558b27c`

**Plan metadata:** (this commit) docs(41-04)

## Files Created/Modified

- `src/settlement/comparison.jl` (created, 765 lines) — `compare_tariffs` + internal row/frame helpers; zero new formulations
- `src/TSODSO.jl` (modified) — settlement include block + `compare_tariffs` (declares its own export)
- `test/test_settlement.jl` (modified) — 5 new `@testitem`s (four-leg hermetic + guards, fairness echo, equity/rebound conventions, pv/bus/tercile breakouts, :slow IEEE-13 four-leg run with the honest fit-leg contract); gate-then-golden echo pins
- `test/test_exports.jl` (modified) — `compare_tariffs` in the keep set (17/17 green)
- `scripts/tariff_comparison.jl` (created) + `scripts/README.md` (index row, same commit)
- `results/settlement_comparison/*.csv` (created, committed) — 5 summary rows, 30 bus-granularity bill rows, header-only breakouts (honest empty)
- `docs/literate/settlement_equity.jl` (created) + `docs/make.jl` (two registrations only)

## Decisions Made

See key-decisions: the FIT thermal-infeasibility attribution, the ground-mode seed choice (with the seed-42 refusal recorded as data), the 784 refusal-as-artifact handling, and the certificate-count granularity rule. Additionally: `fairness_total` is defined as the leg's prices over the DADP quantities (negated, payment-signed) so the echo is directly comparable with `total_payments`; `total_payments` is the leg's settlement at its OWN dispatch.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test 5's fit-leg assumption falsified by measurement — the fit leg is genuinely infeasible on the ground fixture**
- **Found during:** Task 1 GREEN (the :slow item's `isfinite(welfare)` failed on the fit row)
- **Issue:** the plan asserted finite welfare on ALL four legs, assuming `fit_baseline` converges on the IEEE-13 ground fixture. Measured: the batteryless (A4) FIT dispatch terminates PRIMAL_INFEASIBLE at the seed SOC solve (genuine certificate, not a flake).
- **Fix:** attributed by probe (head-branch `smax` is the binding constraint — lifting only it makes `fit_baseline` converge); Test 5 rewritten to assert the honest status-row contract (the runner's `error:SolveFailedError` row with missing certified values, legs never dropped).
- **Files modified:** test/test_settlement.jl
- **Committed in:** ab583b7

**2. [Rule 3 - Blocking] Ground smoke mode's seed pinned to the ground-fixture regression seed (20260718)**
- **Found during:** Task 2 (first ieee13-ground run)
- **Issue:** at seed 42 the default population's centralized DADP run is refused at the battery-complementarity certificate — the whole smoke artifact would be a single error row.
- **Fix:** smoke-mode seed = 20260718 (the seed the ground fixture was calibrated and validated with; three alternative seeds probed clean). The plan pins no seed for the ground mode (thesis constants belong to case-a-784). The seed-42 refusal is itself recorded as a (run) status row — data, not failure.
- **Files modified:** scripts/tariff_comparison.jl
- **Committed in:** cb3b9aa

**3. [Rule 1 - Bug] Status notes carried embedded newlines into the committed CSVs**
- **Found during:** Task 3 verification (the docs page's line-oriented CSV reader crashed on multi-line quoted fields)
- **Issue:** solver messages in `notes` are multi-line; the repo's artifact CSVs are line-oriented by convention (the established docs readers split per line).
- **Fix:** `flatten_note` in the script's writers (`\n` → "; ", `"` → `'`); both modes re-run and the CSVs regenerated (784 outcome identical: iters=80, error:CertificateError). Task 2 commit amended before any dependent commit.
- **Files modified:** scripts/tariff_comparison.jl, results/settlement_comparison/*.csv
- **Committed in:** cb3b9aa

**4. [Rule 1 - Bug] Three implementation defects caught by the GREEN run**
- **Found during:** Task 1 GREEN
- **Issue:** (a) `push_bill_rows!` consumed the ledger's INPUT house rows instead of the ledger's OUTPUT rows (no `bill` field); (b) the breakouts closure shadowed `Base.keys` with the grouping vector (MethodError); (c) the test's flat/tou certificate-count expectation contradicted the documented granularity rule (counts cover the dispatches at the row's `bills_granularity`).
- **Fix:** pass `led.households`; rename the shadow; align the test assertions with the (docstring-documented) granularity rule.
- **Files modified:** src/settlement/comparison.jl, test/test_settlement.jl
- **Committed in:** ab583b7

---

**Total deviations:** 4 auto-fixed (3 × Rule 1, 1 × Rule 3). **Impact on plan:** all fixes forced by measured codebase/artifact behavior; no scope creep; golden untouched; all must_haves truths hold (the heavy :case_a_784 artifact is the committed status row the plan pre-authorized — "kill = measured outcome", "do not re-tune anything").

## Issues Encountered

- Whole-tree formatter passes (CI scope `src/test/docs`) reflow two pre-existing, out-of-plan files (`src/experiments/materialize.jl`, `test/test_population_case_a_scaling.jl`); reverted untouched and logged to `deferred-items.md` (scope boundary).
- 41-02's note about `roadmap.update-plan-progress` not writing was respected: ROADMAP.md deliberately untouched (orchestrator-owned).

## Deferred Items

- **Pre-existing JuliaFormatter drift** in `src/experiments/materialize.jl` + `test/test_population_case_a_scaling.jl` (docstring reflow class; details in `.planning/phases/41-settlement-ledger-equity/deferred-items.md`) — a standalone `format(...)` commit by the phase owner before the next CI run, or a re-check at the CI-pinned 2.10.2.

## Verification (plan-level, all run)

- `TSODSO_TEST_FILES=test_settlement.jl julia --project=. -e 'import Pkg; Pkg.test()'` — **320/320 pass, exit 0** (fast + :slow)
- `TSODSO_TEST_FILES=test_exports.jl …` — **17/17 pass** (`compare_tariffs` in the keep set)
- `julia --project=. scripts/tariff_comparison.jl --mode ieee13-ground` — exit 0, CSVs written; `--mode case-a-784` — exit 0 with the honest status row (iters=80)
- `python3 .github/scripts/check_scripts_index.py` — green (43 tracked files)
- `git diff --exit-code src/pricing/ src/admm/ src/models/` — clean
- Literate: `Literate.markdown` parse render OK; the page's code EXECUTED end-to-end (`include`) against the real settlement layer — live slice + both CSV sections render
- **Full suite (phase gate): 32949 pass / 0 fail / 0 error / 7 broken (all `expected_broken.txt`-covered), exit 0, 68m17s**

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- SETL-01..06 all delivered; the researcher-facing artifacts are in place: `src/settlement/comparison.jl` (programmatic), `results/settlement_comparison/*.csv` (committed), the docs page (renders the committed numbers).
- The 784-house per-tariff comparison awaits the same bounded solver-precision resolution Phase-40 used for the agreement point (agr_optimizer ladder) — explicitly OUT of this plan's scope ("no tol changes"); recorded as the honest refusal in the artifact.
- SETL-07/08 (flexibility market) can consume `compare_tariffs`' return shapes directly.

## Self-Check: PASSED

- Files exist (all six created key-files non-empty on disk — verified pre-write).
- Commits exist: cd2819c, ab583b7, cb3b9aa, 558b27c — verified in `git log`.
- Test evidence re-verified: settlement 320/320, exports 17/17, scripts-index guard 0, golden diff clean, full suite 32949/0/0/7-listed exit 0.

## TDD Gate Compliance

- `test(41-04)` commit `cd2819c` precedes `feat(41-04)` commit `ab583b7` in git history — VERIFIED (RED run observed: 144 passed / 5 errored before implementation).
- Tasks 2–3 are non-test-source tasks (script/docs/artifact); no RED/GREEN gates apply.

---
*Phase: 41-settlement-ledger-equity*
*Completed: 2026-10-26*
