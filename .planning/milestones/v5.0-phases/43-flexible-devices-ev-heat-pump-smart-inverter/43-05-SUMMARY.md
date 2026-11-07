---
phase: 43-flexible-devices-ev-heat-pump-smart-inverter
plan: 05
subsystem: population-optin-and-highpv-exactness
tags: [population, seeding, ev, socp-exactness, volt-var, measurement]
requires:
  - "43-02..43-04 device constructors (ElectricVehicle, HeatPump, SmartInverterPV)"
provides:
  - "build_population(...; flex_devices = nothing | :ev | :heatpump | :smartinverterpv | Vector): per-house seeded opt-in, no-op default"
  - "scripts/socp_highpv_remeasure.jl + results/socp_highpv/highpv_exactness.csv (30 measured rows)"
  - "docs/literate/socp_highpv_exactness.jl page reading the committed CSV"
affects: []
tech-stack:
  added: []
  patterns:
    - "kwarg wrapper around the original body (_build_population_core) keeps every positional call site byte-identical"
key-files:
  created:
    - test/test_flex_population.jl
    - scripts/socp_highpv_remeasure.jl
    - results/socp_highpv/highpv_exactness.csv
    - docs/literate/socp_highpv_exactness.jl
  modified:
    - src/experiments/materialize.jl
    - scripts/README.md
    - docs/make.jl
decisions:
  - "Opt-in is a build_population kwarg (default nothing), not a Scenario selector: SCENARIO_VALID_POPULATIONS and Scenario.jl untouched"
  - "EV sessions: seed hash((s_pop,:ev,bus,house_index)), tag-split arr/dep/energy/soc0 streams; truncated-normal arrival 18.5+-2 [15,22], departure 7.5+-1.5 [5,10] (wraps), lognormal energy fraction; documented LOW-CONFIDENCE (ACN-Data Lee/Li/Low 2019, NHTS 2017)"
  - "Re-measurement verdicts classified by CertificateError.kind: refused_socp_exact vs later certificates (refused_battery) with socp_gate_passed recorded"
  - "Volt-VAR = IEEE 1547-2018 Cat-B curve, evaluated post hoc on the fixed-dispatch ACPowerFlow(limits=false) physics max voltage"
metrics:
  duration: "~70 min"
  completed: "2026-11-02"
  tasks: 3
  files: 7
requirements-completed: [DEV-06, DEV-09]
---

# Phase 43 Plan 05: Flex population opt-in and high-PV SOCP exactness re-measurement Summary

**One-liner:** A no-op-default `flex_devices` kwarg attaches per-house hash-seeded EV/HeatPump/SmartInverterPV devices to `build_population`, and the high-PV SOCP exactness is re-measured (30 rows, with/without optimal Q) with a post-hoc Volt-VAR droop comparator.

## What Was Built

- `src/experiments/materialize.jl`: `build_population` now takes `flex_devices` (validated; unknown selector throws `ArgumentError`). The original body became `_build_population_core`; the wrapper is a pass-through when the selector is empty. `:case_a_784` gets one flex set per house (rolled into the bus aggregator); `:default` gets one per aggregator (house_index 1), skipping pure-capacitor aggregators. Calibration constants carry a citation block marked LOW-CONFIDENCE.
- `test/test_flex_population.jl`: byte-identity fence, opt-in device types, seeding determinism / per-house distinctness / validity (wrap sessions occur), and an end-to-end `solve_welfare` + `solve_admm` agreement on a two-bus flex EV population. RED commit `78a8171` failed on the missing kwarg (MethodError).
- Measurement: `scripts/socp_highpv_remeasure.jl` (certified 3-bus high-PV substrate copied verbatim), seeds 20260719..23, pv scales 0.5 and 1.2, variants active_only / with_optimal_q / q_only_capability.

## Measured results (results/socp_highpv/highpv_exactness.csv)

- 30 rows: 26 `exact`, 4 `refused_battery` (all at pv 1.2: active_only seed 20260722; with_optimal_q seeds 20260721-23). The 4 refusals are BATTERY-complementarity refusals issued after the SOCP cone gate passed (the gate runs first); they are not SOCP inexactness, and their cone residual is unavailable (a refused solve returns no model).
- pv 0.5: all 15 exact; worst ratio 0.159 (q_only_capability), 0.058 (active_only), 0.056 (with_optimal_q). pv 1.2: all returned points exact, worst ratio 0.069.
- Conclusion as measured: optimal Q did not produce SOCP inexactness in this regime; the observed refusals come from the battery certificate, more often with the added inverter panel (3 of 5 seeds) than without (1 of 5). Small sample; no further claim.
- Droop comparator (physics max voltage up to 1.12 pu at pv 1.2): the droop's request sign agrees with the optimal-q dispatch in 12/120, 7/120, 17/48, 30/120 active hours across the four with-Q cells. Reported only; the droop is never a convex constraint.

## Deviations from Plan

**1. [Rule 1 - Plan premise] "refused_with_certificate" split by certificate kind.** The first run showed all refusals were battery complementarity, not the SOCP gate. Verdicts are now `refused_<CertificateError.kind>` with `socp_gate_passed`. The diagnostic re-solve at `rtol_exact = 1e12` is used only after a `refused_socp_exact` (none occurred); no tolerance or tau was raised.

**2. [Rule 3] Local upsert instead of `upsert_sweep_rows`.** That helper lives in another script with a different key; a small keyed upsert (fixture, variant, seed; `cols = :union`) is in the script itself.

**3. Added a third variant `q_only_capability`** (zero-panel inverter) because `with_optimal_q` also adds active PV and confounds the Q effect.

## Verification

- `test_flex_population.jl` green (30 tests). Directly affected files (population, case_a, experiments, admm, ieee8500, settlement, mpc, etc.; 28650 passed) pass; the runner's only failure was the `guards` item reporting a requested file with no fast-set testitem (slow-only file), not a test failure. Full suite not run (orchestrator).
- `python3 .github/scripts/check_scripts_index.py` passes. Literate page script portion executes against the committed CSV; a full Documenter build was not run (slow).
- `:default` / `:case_a_784` structurally identical with `flex_devices = nothing`; no golden touched.

## Known Stubs

None.

## Threat Flags

None. T-43-05-1..4 mitigated (fence tests, per-house hash seeding with distinctness test, verdicts only via standard gates, in-code low-confidence calibration notes).

## TDD Gate Compliance

RED `78a8171` (test) -> GREEN `ea5db00` (feat); measurement task `e5a9cc9`.

## Self-Check: PASSED

Files exist: test/test_flex_population.jl, scripts/socp_highpv_remeasure.jl, results/socp_highpv/highpv_exactness.csv, docs/literate/socp_highpv_exactness.jl; commits 78a8171, ea5db00, e5a9cc9 in git log.
