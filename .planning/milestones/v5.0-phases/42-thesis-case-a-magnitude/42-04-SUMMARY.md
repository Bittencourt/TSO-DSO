---
phase: 42-thesis-case-a-magnitude
plan: 04
subsystem: measurement-runner
tags: [ofat-ablation, pre-registration, device-variant-rebuild, source-contract, upsert-csv, certification, julia, tdd]

# Dependency graph
requires:
  - plan: 42-01
    provides: the pre-registered protocol (42-CASE-A-PROTOCOL.md §7 axis tables) + the guard/gain/provenance helpers in scripts/lib/case_a_common.jl
  - plan: 42-03
    provides: the case_a_magnitude.jl runner skeleton (modes, AGR ladder, run_fit_outcome, _measure_point, upsert machinery, honest status vocabulary)
  - phase: 40-case-a-population
    provides: _case_a_house/_case_a_rung_counts primitives, case_a_household_map, the nested-prefix ladder idiom, DEFAULT_LADDER_FRACTIONS
  - phase: 41-settlement-tariffs
    provides: the drift-tripwire fail-loud shape (tariff_comparison.jl:511-518) and the case_a_houses_flat rebuild precedent
provides:
  - scripts/lib/case_a_common.jl — case_a_houses_variant (protocol §7d rebuild from the SAME _case_a_house primitives, map-consistent, TSODSO-qualified at call time), assert_houses_map_aligned (drift tripwire), case_a_variant_rollup (1:1 bus roll-up guard)
  - scripts/case_a_magnitude.jl — the four OFAT ablation modes (--mode ablation-fit | ablation-price | ablation-population | ablation-devices) with ABLATION_AXES pinned verbatim from protocol §7, --axis/--variant validation, seed-42-only scoping, and the shared _solve_and_gain_rows code path
  - results/thesis_case_a_magnitude/ablation.csv — the committed small-scale certification artifact (rung_1/78 rows, honest statuses)
affects: [42-05 (runs the axes as pure machinery at all scales — the per-axis CLI surface is certified), 42-06 (reproducibility band reads the same CSVs)]

# Tech tracking
tech-stack:
  added: []   # zero new packages (threat register T-42-04-SC: empty by construction)
  patterns: [source-contract-axis-dicts, tsodso-qualified-call-time-lib, provenance-transparent-reuse-rows, declared-values-drift-guard, fit-price-kwarg-registered-default]

key-files:
  created:
    - results/thesis_case_a_magnitude/ablation.csv
  modified:
    - scripts/lib/case_a_common.jl
    - scripts/case_a_magnitude.jl
    - scripts/README.md
    - test/test_case_a_magnitude.jl

key-decisions:
  - "Rebuild helper placed in scripts/lib/case_a_common.jl (the plan frontmatter artifact path): TSODSO referenced ONLY via TSODSO.X-qualified names resolved at CALL time, so the lib include stays TSODSO-free (guard/gain items unchanged) while the runner/rebuild items load TSODSO before calling — device checks are by type NAME, never isa"
  - "Ablation upsert key extended to (axis, variant, seed, t_horizon, kind, rung): the plan's bare (axis, variant, seed, t_horizon) identity would make per-row upserts DELETE the sibling rows of the same variant (the 42-03 lesson, re-applied); every ladder attempt + the gain/reuse row survives kills"
  - "Population rung_1.0 and full_784 are REUSED headline rows (protocol §7c: 'the 1.0-rung IS the headline measurement' — reused, never re-run); the fraction<1.0 rungs solve fresh with no per-rung re-tuning"
  - "Reused rows carry status='reused' + a note naming the source CSV/row/seed; proxy-reuse rows keep the FIXTURE's measurement seed in their provenance (20260719/20260718), not the ablation anchor seed — the seed column always names the seed the numbers came from"
  - "Axis (a) FIT prices come from the model's own FIT_λ_* constants (λ_export ±×0.5/×2.0 = exactly the protocol's 4.8/19.2); run_fit_outcome gained an additive fit_prices kwarg whose default is the registered triple — byte-identical default path"
  - "Protocol §7c populations-axis reuse is wired to the LIVE artifacts: proxy rows come from proxy.csv and the headline from magnitude.csv, both failing LOUDLY when the source artifact or certified row is missing — reuse is never fabricated"

patterns-established:
  - "Pattern: axis-Dict source contract — each protocol §7 axis pinned as committed TEXT (one Dict entry per axis; the population list as a formatter-stable multi-line block), so a silent variant addition is a visible script edit + test edit + protocol amendment"
  - "Pattern: TSODSO-qualified call-time lib helpers — a shared lib stays include-composable without the package while its rebuild helpers construct real TSODSO objects (qualified names resolve in any module that did using TSODSO)"
  - "Pattern: provenance-transparent reuse row — status='reused', measured values copied verbatim, note names source CSV+row+source status; the honest source outcome travels in the note when the source itself refused"

requirements-completed: [REPRO-05]   # the ablation machinery: 4 pre-registered axes as test-pinned runner modes, device-variant rebuild + tripwires, certified end-to-end at the smallest rung; the heavy per-axis runs are 42-05's payload

# Metrics
duration: 42min
completed: 2026-10-26
---

# Phase 42 Plan 04: OFAT Ablation Axes + Device-Variant Rebuild Summary

**The runner's REPRO-05 half: four pre-registered OFAT ablation modes with axis Dicts pinned verbatim from protocol §7 (source-contract tested), a device-mix rebuild from the SAME `_case_a_house` primitives with map-consistency tripwire, and `ablation.csv` with honest-status kill-anytime rows — CERTIFIED end-to-end on the smallest population rung (1/78: 10 houses, ladder converged iters=2; the FIT leg's refusal recorded as an honest `error:SolveFailedError` row), with the rung welfare exactly reproducing the committed Phase-40 ladder precedent.**

## Performance

- **Duration:** 42 min
- **Started:** 2026-10-26T13:22:48Z
- **Completed:** 2026-10-26T14:04:30Z
- **Tasks:** 3/3 (TDD RED→GREEN pair + certification)
- **Files modified:** 5 (1 created, 4 modified)

## Accomplishments

- **RED→GREEN source contract (RED `2cc1451` → GREEN `8397003`)**: a fast-lane item pins each protocol §7 axis Dict as committed text (`fit_params` → registered/lam_export_half/lam_export_double; `price_range` → registered/scale_0.5/scale_2.0; `population` → the two proxies + the six DEFAULT_LADDER_FRACTIONS rungs + full_784; `device_mix` → registered/batteries_out/pv_half) plus the four `ablation-*` mode names — adding a variant now requires a script edit + test edit + protocol amendment, all visible (T-42-04-1).
- **Device-variant rebuild (lib)**: `case_a_houses_variant(feeder, feeder_sym, T, seed; variant, fraction)` rebuilds per-house Aggregators from the SAME `_case_a_house` primitives in `case_a_household_map` order (`pv_fraction` never used — the transform is post-construction), returns variant-correct map rows (`device_set`/`pv_group` recomputed from ACTUAL device sets), and tripwires before returning: `assert_houses_map_aligned` errors with the fail-loud drift message on length/bus/pv-group disagreement (T-42-04-2); `case_a_variant_rollup` keeps the 1:1 bus roll-up guard. Unit items pin batteries_out (exactly PVBattery dropped everywhere), pv_half (first-half/second-half split, map↔device consistency house-for-house, 10-aggregator roll-up) and the tripwire (reversed map rows error).
- **The four ablation modes (runner)**: `--mode ablation-fit|ablation-price|ablation-population|ablation-devices`, all sharing `_solve_and_gain_rows` (extracted verbatim from `_measure_point` — the §8 same-code-path claim stays structural) and writing `ablation.csv` keyed (axis, variant, seed, t_horizon, kind, rung) with honest statuses. Axis (a) re-solves ONLY fit_baseline (new additive `fit_prices` kwarg, registered default = the model's `FIT_λ_*` constants) reusing the seed-42 certified W_DADP from magnitude.csv — missing headline → loud error, never a silent re-solve. Axes (b)/(d) re-run the full AGR ladder per variant (λ₀ elementwise scalings; the device rebuild at fraction 1.0, with the registered variant tripwired structurally against `build_population(:case_a_784)`). Axis (c) solves fresh fraction<1.0 rungs (no per-rung re-tuning) and emits `status="reused"` rows for the proxies (proxy.csv) and full_784/rung_1.0 (magnitude.csv), each note naming its source CSV+row. `--axis`/`--variant` validate against the committed Dicts (unknown → ArgumentError listing permitted values; population fractions accept the decimal expansion, normalized to the Dict key); ablations are seed-42-only (protocol §3).
- **Small-scale certification (GREEN `28a2154`)**: `--mode ablation-population --variant 1/78` ran end-to-end in ~2.5 min — 10 houses rolled up to 10 bus aggregators, AGR ladder converged at the default rung (iters=2, 40.1 s, welfare −4823.502302305045 — exactly the Phase-40 `scaling_ladder.csv` rung1 value, an independent consistency cross-check recorded here but never asserted as a golden), and the FIT leg refused at the registered call AND the pinned retry → the gain row is an honest `error:SolveFailedError` (the same refusal class as the committed ieee13-ground precedent — recorded, never re-tuned). The decimal CLI token `0.01282051282051282` was also certified end-to-end: it normalizes to the `1/78` Dict key and replaces its own rows under the row-granularity key.

## Task Commits

1. **Task 1: RED — axis-Dict source contract + device-variant rebuild items** - `2cc1451` (test)
2. **Task 2: GREEN — rebuild helper + four ablation modes + ablation.csv schema** - `8397003` (feat)
3. **Task 3: small-scale certification — committed 1/78 population-rung rows** - `28a2154` (feat)

_Tasks 1→2 are the TDD pair (the RED commit precedes the GREEN in history); Task 3 is the certification run._

## Test Evidence

- **RED (`2cc1451`)**: `TSODSO_TEST_FILES=test_case_a_magnitude.jl … Pkg.test()` → exit 1: **75 passed, 8 failed, 3 errored** — the contract item failed on the absent axis-Dict lines/mode names; the three rebuild items errored on `UndefVarError: case_a_houses_variant` (the natural RED — helpers absent); all pre-existing items stayed green.
- **GREEN (`8397003`)**: same command → exit 0, **105/105 assertions**; JuliaFormatter clean on all three changed code files (idempotent re-format); CLI misuse paths verified exiting nonzero with permitted-value ArgErrors (`--variant not_a_variant`, `--variant bogus`, `--axis device_mix` mismatch, `--seed 43` on an ablation mode, `--variant all` on headline); `check_scripts_index.py` green; `git diff ba3a21b..HEAD -- src/` empty.
- **Sanity gate (`8397003`)**: `TSODSO_TEST_FILES=test_case_a_magnitude.jl,test_settlement.jl` → exit 0, **448/448** (settlement suite unbroken by the shared-lib change).
- **Certification (`28a2154`)**: `--mode ablation-population --variant 1/78` → exit 0 (~2.5 min), 2 honest rows committed; decimal-token re-run → exit 0, same-key rows replaced. Fast lane → exit 0, **123/123** (the committed-CSV structural item now validates the ablation rows: provenance, status vocabulary, Δ identity where both welfares certify).
- **No `src/` diff**: `git diff ba3a21b..HEAD -- src/` empty (re-verified post-commit — measurement-only phase).

## Files Created/Modified

- `scripts/lib/case_a_common.jl` — +the device-variant rebuild trio (`case_a_houses_variant`, `assert_houses_map_aligned`, `case_a_variant_rollup`) + `CASE_A_DEVICE_VARIANTS`; header documents the call-time TSODSO qualification.
- `scripts/case_a_magnitude.jl` — +the four ablation modes, `ABLATION_AXES`/`ABLATION_MODE_AXIS`/`POPULATION_RUNG_FRACTIONS` (with drift guards), `_solve_and_gain_rows` extraction, `_certified_headline_row`/`_proxy_reuse_rows`/`_headline_reuse_rows`, `_write_ablation_rows`, `ABLATION_COLS` + per-mode `ensure_all_schemas`, `--axis`/`--variant` validation, seed-42 ablation scoping; `run_fit_outcome` gained the additive `fit_prices` kwarg.
- `test/test_case_a_magnitude.jl` — +4 fast-lane items (axis source contract; batteries_out; pv_half + roll-up; drift tripwire); header records the helper-placement decision.
- `scripts/README.md` — the ablation modes + `ablation.csv` registered in the `case_a_magnitude.jl` row.
- `results/thesis_case_a_magnitude/ablation.csv` — the committed certification artifact (rung + gain rows for `rung_1/78`, honest statuses, full provenance).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The plan's ablation upsert key would make sibling rows self-destruct**
- **Found during:** Task 2 (writing the ablation write boundary)
- **Issue:** The plan specified upsert key `(:axis, :variant, :seed, :t_horizon)`, but each ablation variant emits MULTIPLE rows (one per ladder attempt + the gain/reuse row) and the runner upserts per row — under the bare identity key every write would DELETE the sibling rows of the same variant, exactly the 42-03 bug (a kill would not leave the rows already captured).
- **Fix:** Key extended with the row-granularity columns: `(:axis, :variant, :seed, :t_horizon, :kind, :rung)`. Re-runs replace exactly their own rows; siblings and other variants are never dropped. All stated upsert truths preserved.
- **Files modified:** `scripts/case_a_magnitude.jl`
- **Commit:** `8397003`

**2. [Rule 1 - Bug] `Symbol[:axis, :variant; MEASURE_COLS]` is a Julia syntax error**
- **Found during:** Task 2 (first CLI misuse check — `syntax: unexpected semicolon in array expression`)
- **Issue:** Mixing `,` and `;` element forms inside one array literal does not parse; the runner was dead on arrival.
- **Fix:** `vcat([:axis, :variant], MEASURE_COLS)`. (Also hardened the parse check to scan `Meta.parseall` output for error nodes — the initial parse-only check missed it.)
- **Files modified:** `scripts/case_a_magnitude.jl`
- **Commit:** `8397003`

### Deliberate Interpretations (within plan discretion)

- **Population rung 1.0 / full_784 are REUSED, not re-solved:** the plan text says "each rung = one ladder-governed solve + fit", but protocol §7c pins `full_784` as "the headline row itself — reused, never re-run" and clarifies "the 1.0-rung IS the headline measurement". The protocol wins where the plan is ambiguous: fraction<1.0 rungs solve fresh, `rung_1.0` and `full_784` emit `status="reused"` rows naming magnitude.csv. This also keeps every run in THIS plan strictly off the 784-house solve path (42-05's payload).
- **Helper placement = the lib** (the plan's frontmatter artifact path), with TSODSO qualified at call time — one of the two placements the plan explicitly offers; recorded in the test header.
- **The RED test's population-Dict pin was restated in the GREEN commit** as the formatter-stable multi-line Dict block (the one-line form exceeds the 92-char JuliaFormatter margin CI enforces); same semantic contract, assertion still occursin-based with no counts.
- **Reused proxy rows carry the FIXTURE's seed in provenance** (20260719/20260718), not the ablation anchor seed — the seed column must name the seed the numbers actually came from (the upsert key includes :seed, so the rows key exactly like their proxy.csv sources).

No architectural deviations (Rule 4): none triggered. No authentication gates. No blockers.

## Measured Results (recorded, never gated)

| axis | variant | kind | status | welfare_dadp | welfare_fit | Δ% | iters |
|------|---------|------|--------|--------------|-------------|----|-------|
| population | rung_1/78 | rung | converged | −4823.502302305045 | — | — | 2 |
| population | rung_1/78 | gain | error:SolveFailedError | −4823.502302305045 | — (FIT INFEASIBLE at attempt AND pinned retry) | — | — |

The FIT refusal at this rung is DATA (the committed ieee13-ground FIT INFEASIBLE is the same class), recorded per the honesty policy; 42-05's full-axis runs will show whether it persists at larger rungs. Cross-check (recorded, never asserted): the rung welfare equals the Phase-40 `scaling_ladder.csv` rung1 row exactly — the nested-prefix rebuild is consistent with the committed ladder machinery. No golden is pinned on any measured magnitude (protocol §10).

## Known Stubs

None. Every ablation axis is fully wired (Dict validation, population build, ladder, FIT, gain, reuse, upsert, provenance); `reused` rows are protocol §7c's provenance-transparent reuse mechanism (T-42-04-3), not placeholders — the solve path they shadow was certified by this plan's run.

## Threat Check

All register entries addressed: T-42-04-1 (free-form search smuggled in) — the four axis Dicts are pinned as committed text by the source-contract item; a new variant requires script + test + protocol edits, all visible. T-42-04-2 (rebuild diverging from the validated construction) — the rebuild uses ONLY the `_case_a_house`-family primitives in household-map order, the alignment tripwire errors before any solve, the roll-up guard keeps one aggregator per bus, unit items pin device sets per variant, and the registered full-fraction rebuild tripwires structurally against `build_population(:case_a_784)`. T-42-04-3 (reused rows looking like solves) — `status="reused"` + notes naming the source CSV/row, enforced by the committed-CSV structural item. T-42-04-4 (invalid flags) — all misuse paths verified exiting nonzero with permitted-value ArgErrors. T-42-04-SC — zero new packages. No security-relevant surface beyond the plan's threat model (CLI flags validated; CSVs under `results/`; no network/auth paths; `src/` untouched).

## TDD Gate Compliance

- Task 1/2 pair: `test(42-04)` RED `2cc1451` precedes `feat(42-04)` GREEN `8397003` in history — VERIFIED.
- Task 3 certification is the plan's committed-artifact step (its verify ran the full fast lane post-commit) — VERIFIED.

## Self-Check: PASSED

- `results/thesis_case_a_magnitude/ablation.csv` exists (2 data rows, contains `population` + `rung_1/78` + non-empty `protocol_sha`) — FOUND
- `scripts/lib/case_a_common.jl` contains `case_a_houses_variant`, `assert_houses_map_aligned`, `case_a_variant_rollup` — FOUND
- `scripts/case_a_magnitude.jl` contains all four `ablation-*` modes + the four pinned axis Dicts — FOUND
- `scripts/README.md` contains the ablation modes + `ablation.csv` (index guard green) — FOUND
- `test/test_case_a_magnitude.jl` contains the four new items — FOUND
- Commits `2cc1451`, `8397003`, `28a2154` all present in `git log`, RED preceding GREEN — FOUND
- Fast lane exit 0 (123/123 assertions) — VERIFIED
- `git diff ba3a21b..HEAD -- src/` empty — VERIFIED
