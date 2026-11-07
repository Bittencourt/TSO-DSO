---
title: v5.0 integration-check backlog (W1, W4-W9, docs @ref warnings)
created: 2026-11-06
source: v5.0 milestone audit, tech debt not closed by Phase 47
area: ci / experiments / api / docs
---

The v5.0 milestone audit (`.planning/v5.0-MILESTONE-AUDIT.md`) found two blockers (B1, B2) and nine
integration warnings (W1-W9). Phase 47 closed B1, B2, W2 and W3. The items below are what is left. None of
them makes a committed result wrong. Each comes with a suggested fix.

- **W1: threaded ADMM tests never run in CI.** The `julia-runtest` lane is single-threaded, so the
  serial == threaded equality has only been checked by hand. Fix: add a CI lane (or a job step) with
  `JULIA_NUM_THREADS=4` that runs the threaded ADMM test files only.
- **W4: `:case_a_784` on `:ieee123` fails at materialize, not at construction.** The IEEE-8500 combinations are
  refused when the `Scenario` is constructed. Fix: add the same refusal to the `Scenario` constructor so that
  the unsupported combination fails early with an `ArgumentError`.
- **W5: `Scenario` / `run_scenario` cannot reach the v5.0 features** (parallel, `agr_optimizer`, actors,
  `BehaviourSpec`, `flex_devices`, `FlexMarket`). These features are only reachable through direct calls.
  Fix: add optional `Scenario` fields with defaults that leave the current digests unchanged, threaded
  through `run_scenario`; or document the direct-call path as the supported route.
- **W6: `actor_wedge_rows` is neither exported nor public,** although it is the only producer of ledger actor
  lines. Fix: mark it `public` (Julia 1.11+ syntax behind a version check), or export it, and update
  `test/test_exports.jl`.
- **W7: the default-path digest fences only assert on Julia 1.12.5.** The CI `1.12` lane skips them. Fix:
  pin one CI lane to 1.12.5, or record per-version digests for the lanes CI runs.
- **W8: `PriceBased` / `AbstractCoordination` are exported, but nothing dispatches on them.** Fix: either
  dispatch the coordination entry points on them, or stop exporting them in the next breaking release
  and note this in the changelog.
- **W9: `scripts/ieee8500_scenario_point.jl` rebuilds `solve_admm` from positional internals.** Parity
  is tested on IEEE-13 only. Fix: route the script through a public keyword entry point, or add a
  parity test on a second feeder. Pair this with the 8500 re-run hardening todo of the same date.
- **Docs build: two unresolved `@ref` warnings in `docs/src/api.md`** (`_analytic_distflow_start!`,
  `_any_flexible_reactive`). Both are internal helpers. Fix: drop the `@ref` links, or list the helpers in an
  internals `@docs` block.
- **`SettlementInput` provenance flag.** A `SettlementInput` built from an actor-objective run cannot be told
  apart from a normal one, so `clear_flex_market` cannot refuse it. Fix: add a provenance field, for example
  `objective_kind`, with a default that keeps existing constructors and digests unchanged, and refuse
  actor-run inputs. This is part of the future requirement SETL-F2 (actor-aware flexibility market and tariff
  comparison) in `.planning/REQUIREMENTS.md`.
- **`TAU_EV_ADMM` docstring.** The docstring in `src/models/complementarity_ev.jl` still says the ADMM
  final-consolidation call site is its only user. The price-taker and flex stage-2 solves now reuse it,
  because they pair it with `τ_batt = 1e-3`. Fix: update the docstring only, with the value unchanged, the next
  time `src/models` is opened.

## Info items from the phase-47 code review (iteration 2, accepted, not fixed)

Details are in `.planning/phases/47-v5-audit-gap-closure/47-REVIEW.md`.

- **IN-01:** FourQuadBESS has no co-charge certificate on the price-taker paths. This gap predates the review.
- **IN-02:** no test covers the rethrow branch of `_certificate_status`.
- **IN-03:** the stage-2 reactive-decision refusal assumes no flexible load has its own reactive output. No test pins that assumption.
- **IN-04:** `τ_ev` is not threaded alongside `τ_batt`. This was a decision, but `clear_flex_market` does not document it.
- **IN-05:** the flex-market docs page does not say that `compare_tariffs` refuses EV, HeatPump, SmartInverterPV and wrapped populations up front.
- **IN-06:** `test_flex_market.jl` repeats a status assert.
- **IN-07:** the `compare_tariffs` refusal message names only SmartInverterPV among the devices `clear_flex_market` refuses. It also refuses FourQuadBESS and FixedCapacitor. No test runs a full flex clear on a heat-pump population.
- **IN-08:** the SmartInverterPV fence case uses a counted optimizer that only stage 2 uses. Pinning the `"_flex_physics:"` message prefix would prove directly that the refusal happens before any solve.
- **IN-09:** the shared `fit_baseline` refusal message (`src/pricing/fit.jl`) still says "phase-43 / phase-44" and suggests dropping `flex_devices`, which is the wrong fix for behaviour wrappers.

## Residual items from the v5.0 re-audit (2026-11-07)

- **N1 (warning):** in `compare_tariffs`, the `houses` input skips the up-front device check (`src/settlement/comparison.jl:404` covers `aggs` only). The house legs also keep only `battery_certificate` (around lines 662 and 758), so a V2G EV in `houses` gets an honest battery `:not_checked`, but an EV `:refused` result is never shown. Fix: extend the up-front check to `houses`, or carry `ev_certificate` into the house legs.
- **N2 (warning, predates v5.0):** `src/planning/subproblem.jl:365` runs only the battery certificate, and nothing refuses EV populations. Fix: refuse EVs there, or run `assert_ev_complementarity!`.
- **N3 (info):** `build_settlement_ledger` accepts `actor_wedges` and `flex_payments` together with no guard (`run_inputs.jl:536-555`). It is a building block for hand-assembled ledgers. This ties in with the SETL-F2 provenance flag.
- **N4 (info):** `TAU_EV_ADMM` is the default in the exported `price_taker_dispatch` signature, but it is neither exported nor `public`.
