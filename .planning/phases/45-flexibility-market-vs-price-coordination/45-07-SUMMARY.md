---
phase: 45-flexibility-market-vs-price-coordination
plan: 07
subsystem: docs / repo gates
tags: [julia, literate, documenter, checkdocs, jet, formatter, flex-market]

requires:
  - phase: 45-06
    provides: committed flex-market rows in results/settlement_comparison/ (tariff_comparison.csv, rebound_hourly.csv)
  - phase: 45-05
    provides: FLEX_EXTRA_COLUMNS (the column meanings the page explains)
provides:
  - "docs/literate/flex_market.jl: the flexibility-market vs price-coordination page, every number recomputed live from the committed CSVs"
  - "docs/make.jl registration (literate list + Experiments nav) and the extended scripts/README.md tariff_comparison.jl row"
  - "docs/src/api.md: the pre-existing export gap closed (8 files), so a checkdocs = :exports build passes"
  - "SETL-07 and SETL-08 closed"
affects: []

tech-stack:
  added: []
  patterns:
    - "Flat level recovered from the CSV as tariff_on_activation / (flex_up_total - flex_down_total) (exact under a constant baseline price)"
    - "A script's literal price profile is read by parsing the script (Meta.parseall) and evaluating that one definition in a fresh Module, so the page never retypes it"
    - "Reduced checkdocs proof: makedocs over api.md plus a stub index.md in the scratchpad, with a negative control on the pre-edit api.md"

key-files:
  created:
    - docs/literate/flex_market.jl
  modified:
    - docs/make.jl
    - scripts/README.md
    - docs/src/api.md

key-decisions:
  - "The CSVs carry no run-date column; the page prints the provenance columns every row stamps (julia version, seed, T, threads, BLAS) and says the measurement date is the commit that recorded the rows, instead of inventing a date"
  - "Mean λ₀ comes from the script's own generators: TSODSO.build_price(:mem, 24, nothing) for IEEE-13 (ground_setup), and the script's ieee123_lambda0() literal parsed from scripts/tariff_comparison.jl for IEEE-123"
  - "The IEEE-123 reverse-flow hour is shown from data: the flat leg's per-hour net load in rebound_hourly.csv (min at hour 12, export) against the delivered flex net load in that hour"
  - "api.md gains a neutral 'Aggregator Actors' section; the four device files go into the Prosumer Devices block and complementarity_ev.jl into the Models block (docs-only, no @docs duplicates)"

requirements-completed: [SETL-07, SETL-08]

duration: 14min
completed: 2026-11-05
---

# Phase 45 Plan 07: Literate page, docs gates and requirement closure Summary

**`docs/literate/flex_market.jl` reads the committed comparison CSVs and recomputes every number live, with the framings below stated plainly. It is registered in docs and scripts. api.md now lists every documented export, so `checkdocs = :exports` passes (15 missing docstrings before the edit, 0 after). JET, the guard, the formatter and the targeted regression set are green, and SETL-07/08 are closed.**

## Performance

- **Duration:** about 14 min
- **Started:** 2026-11-05T04:03:34Z
- **Completed:** 2026-11-05T04:17Z
- **Tasks:** 2/2, plus one FMT style commit
- **Files modified:** 4 (1 created)

## Accomplishments

### The page (13 sections, 642 lines)

All numbers below are what the page prints from the CSV. None of them is typed in the source: a grep of the page for the measured values finds nothing.

| Section | Printed from the CSV |
|---|---|
| 2. First-welfare-theorem framing | lossless gap: IEEE-13 −0.0217 (rel −4.49e-6); IEEE-123 −1.8092 (rel −4.41e-5). Verdict "flex below DADP", not null. Cites the liveness and price-band items of `test/test_flex_market.jl`. Max \|π − λ\| 4.6357 / 3.8205 |
| 3. Lossless vs lossy | IEEE-13: flex −4822.9030, DADP −4823.0144, raw +0.1115, lossless −0.0217, DADP loss cost 0.1331. IEEE-123: raw +3.9463, lossless −1.8092 |
| 4. Payment rules | IEEE-13: uniform 871.9457 vs PAB 208.3452 (PAB pays 663.6005 less, welfare equal: true). IEEE-123: 72.7834 vs 62.7446 |
| 5. Tariff on activation | 36.3325 (IEEE-13), 12.3929 (IEEE-123). Described as standard LFM practice; money only |
| 6. Congestion vs mispricing | 9 of 24 congested hours, κ in [6.095e-4, 0.7197); 1 of 24, κ in [7.881e-4, 0.7199). Flat level 0.1534 / 1.4495 against mean λ₀ 5.6042 |
| 7. β gaming | uniform 0 / 5.7973 / 11.5947; PAB 0 / 5.7765 / 11.5530 (ratio exactly 2). IEEE-123: 0 at every β. Physics identical across β. Cites EcoGrid 2.0 (Applied Energy 261, 2020) and Ziras et al. (RSER 135, 2021) |
| 8. Hour-separability shortfall | 0.2961 (ratio 1.25e-3) and 0.7093 (ratio 7.45e-2). The 10w change is only −1.46e-8 / −2.38e-7, so the shortfall is structural. Polytope bids are future work |
| 9. AC per leg | all five schemes for both modes. IEEE-13 flex feasible at 0.9673580259; flat and TOU on IEEE-123 infeasible at 1.1172 and 1.2596 |
| 10. IEEE-123 | 215.6 s compare call; 20485 probe solves, 0 failed, 126.1 s clear physics; 29 battery refusals. Hour 12 flat net −4.0860 (export) vs flex −3.5998. Default-population row quoted: `error:CertificateError`, ratio 1.062285309572047 |
| 11. Status rows | the 6 non-ok rows, including the IEEE-13 FIT row and both TOU-baseline `ALMOST_OPTIMAL` rows |
| 12. Assumptions | truthful bidding, exogenous β only, no market power, hour-separable divisible bids, inelastic reactive power, the lossless convention |
| 13. Reproduce | the three commands |

Section 1 explains why stage-2 reactive power is held at `−Pdc·tanφ`: the AC check uses the same q, and holding the full baseline q makes stage 2 infeasible.

### Registrations

- `docs/make.jl`: `"flex_market.jl"` with a trailing comment, placed after `settlement_equity.jl`. The nav entry is `"Flexibility Market vs Price Coordination" => "generated/flex_market.md"` under Experiments.
- `scripts/README.md`: the tariff_comparison.jl row is extended (no new row) with:
  - in Purpose: the flex legs, `--flex-market`, the `ieee123` and `ieee123-default` modes, `--record-timeout` and the page name;
  - in How to run: the three commands with their runtimes (IEEE-123: 215.6 s compare call, 126.1 s of it the flex clear);
  - in Outputs: the `rebound_hourly.csv` path.

### api.md

The edit adds:
- `devices/ElectricVehicle.jl`, `HeatPump.jl`, `SmartInverterPV.jl` and `Behavioural.jl` to the Prosumer Devices block;
- `models/complementarity_ev.jl` to the Models block;
- a new "## Aggregator Actors" block for `actors/actor_objective.jl`, `Portfolio.jl` and `efficiency.jl`, with `Order = [:type, :constant, :function]`.

The Coordination Pages list is exactly the four coordination files, with `:constant` in `Order`. The audit loop (every `src` file with an export line, excluding `src/TSODSO.jl`) reports nothing missing.

## Gate evidence

### Reduced checkdocs build (scratchpad)

```
S=/tmp/claude-1000/-home-pedro-programming-TSO-DSO/fb4d3a0a-3e04-4903-ba56-4b034de53945/scratchpad
mkdir -p $S/docs_check/src; cp docs/src/api.md $S/docs_check/src/; (stub index.md)
julia --project=docs $S/checkdocs.jl $S/docs_check
#   makedocs(; root = ARGS[1], source = "src", build = "build", sitename = "check",
#     modules = [TSODSO, TSODSO.ReactiveMode], pages = ["index.md", "api.md"],
#     checkdocs = :exports, warnonly = [:cross_references], remotes = nothing,
#     doctest = false, format = HTML(size_threshold = 1 MiB, size_threshold_warn = 800 KiB))
```

- **Post-edit api.md:** exit 0, `CHECKDOCS_BUILD_OK`, no `missing_docs` error, about 39 s. The only warnings are unresolved `@ref`s, which are expected outside the full manual and are in warnonly.
- **Negative control** (the same build on `git show HEAD:docs/src/api.md` from before the edit): exit 1, "15 docstrings not included in the manual". These were WelfareObjective, ProfitObjective, AbstractActorObjective, Portfolio, actor_efficiency, Rebound, OptOut, PartialCompliance, SmartInverterPV (×2), HeatPump (×2), ElectricVehicle (×2) and assert_ev_complementarity!. So the gate is live, and the edit closes it.
- `modules` matches docs/make.jl (`[TSODSO, TSODSO.ReactiveMode]`) and is a superset of the plan's `[TSODSO]`.

### Other gates

- **JET** (Julia 1.12.7, `julia +1.12`, run alone and detached): `jet_check: 20 current, 20 baseline, 0 NEW, 0 FIXED`, exit 0. `git diff -- scripts/jet_baseline.txt` is empty.
- **Planning-ID guard:** 355 (not above 355). The new page alone scans clean.
- **Export audit:** the phase added exactly `AbstractCoordination`, `PriceBased`, `FlexMarket` (coordination.jl:174) and `clear_flex_market` (flex_settle.jl:380). test/test_exports.jl:36 matches, and test_exports.jl passes in the regression set.
- **expected_broken.txt:** `git diff 295b928.. -- test/expected_broken.txt` is empty (295b928 is the 45-01 fence commit).
- **FMT:** JuliaFormatter 2.10.2 over the 15 listed files plus `scripts/tariff_comparison.jl`, which was clean at HEAD (unchanged). First pass false, second pass true. Only `docs/literate/flex_market.jl` changed (3 line wraps).
- **Formatter follow-up checks:**
  - `check_content_loss.py HEAD` (before the commit) and `HEAD~1` (after it) both report OK, whitespace only. The diff was reviewed by eye.
  - `check_setup_names.py`: 28 testmodules, 244 setup uses, 0 unresolved.
  - `check_scripts_index.py`: complete (47 files).
- **Page standalone:** `julia --project=docs docs/literate/flex_market.jl` exits 0 in about 12 s. It was re-run after FMT, and the output matches the pre-FMT run.

### Targeted regression set

`TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_flex_market.jl,test_flex_market_fence.jl,test_flex_market_ieee.jl,test_settlement.jl,test_actor_settlement.jl,test_actor_default_fence.jl,test_exports.jl,test_welfare_solve.jl julia --project=. -e 'import Pkg; Pkg.test()'`

- **Result:** **1934 / 1934 pass**, 0 fail, 0 error, 5m16.1s, exit 0. Soft-scope warnings: 0.
- **45-01 fence digests:** unchanged, `(0x51a1ed4c3c66413e, 0xf4e1569ddabc1b5f, 0x082f2207b4e88cc4, 0x5515555ce78f74e5, 0xe386f1abc04d04c8)`.
- **Test environment:** restored afterwards with `git checkout -- test/Project.toml test/Manifest.toml`.

## Task Commits

1. **Task 1: literate page, make.jl registration, README row:** `7b66cab` (docs)
2. **Task 2: api.md surfacing (docs-only):** `7f2db35` (docs)
3. **FMT phase-wide style pass:** `71787a8` (style)
4. **REQUIREMENTS.md closure:** in the final metadata commit, after every gate above.

## Deviations from Plan

### Auto-fixed Issues

**1. [Data availability] No run-date column in the CSV**
- **Issue:** the plan's header asks for "the run date read from the CSV provenance", but the CSV stamps julia_version, threads, blas_threads, seed and t_horizon, and no date.
- **Fix:** the page prints the provenance that does exist and says that the measurement date is the commit that recorded the rows. Neither a typed date nor a git call was used: a shallow CI checkout would report the wrong date.

**2. [Data availability] Flat level and λ₀ are not CSV columns**
- **Fix:**
  - The flat level is derived exactly from the CSV as `tariff_on_activation / (flex_up_total − flex_down_total)`. The baseline price is constant under flat.
  - λ₀ comes from the script's own generators, as the plan allows ("say which"). The page states which generator each feeder uses.
- **Result:** both feeders give a mean of 5.6042. The IEEE-123 fixture profile and `:mem` agree, and the research measurement was 5.60.

**3. [Additive] Negative-control checkdocs run.** This was not in the plan. It was added to prove the reduced build detects the gap rather than passing vacuously.

**4. [Scope] Reduced build `modules`.** It uses `[TSODSO, TSODSO.ReactiveMode]`, matching docs/make.jl, instead of the plan's `[TSODSO]`, plus the same HTML size thresholds, so that the proof matches the real build.

No gate, tolerance or committed CSV was changed.

## Issues Encountered

None.

## Known Stubs

None. Every printed value is wired to a CSV cell or to a script generator.

## Note for the orchestrator

The full test suite and the full `docs/make.jl` build still have to be run. The full build executes every literate page, including the new one, which takes about 12 s standalone. The checkdocs property was proven only by the reduced build.

## Self-Check: PASSED

- FOUND: docs/literate/flex_market.jl, docs/make.jl (both registrations), scripts/README.md, docs/src/api.md
- FOUND commits: 7b66cab, 7f2db35, 71787a8
