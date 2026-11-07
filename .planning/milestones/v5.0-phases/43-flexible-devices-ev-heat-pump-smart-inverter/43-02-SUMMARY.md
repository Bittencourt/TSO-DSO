---
phase: 43-flexible-devices-ev-heat-pump-smart-inverter
plan: 02
subsystem: flexible-devices-ev
tags: [electric-vehicle, v1g, v2g, complementarity-certificate, crossval, binary-free]
requires:
  - "43-01 capability traits (storage_kind, agg_device_types type-paired stash, _stash_entry_has_kind)"
provides:
  - "ElectricVehicle{T} <: AbstractDevice: V1G with window zero-upper-bounds, soft quadratic departure target, T+1 SOC closure; opt-in V2G with strictly positive c_deg"
  - "storage_kind(::Type{<:ElectricVehicle}) = :ev"
  - "assert_ev_complementarity! + TAU_EV (measured provenance) in src/models/complementarity_ev.jl"
  - "solve_welfare and AgrOpt (check_ev, final-only) EV certificate wiring"
  - "test/test_electricvehicle.jl: guards, contract, zero-binary, negative-price certificate report, measured-then-pinned crossval"
affects:
  - "43-03 HeatPump, 43-04 SmartInverterPV (same wiring pattern)"
  - "43-05 seeded EV session sampling (device now exists)"
tech-stack:
  added: []
  patterns:
    - "anonymous JuMP objects only; window as zero upper bound (wrap-capable union)"
    - "trait-routed certificate selection with NO legacy shape fallback for a new device"
key-files:
  created:
    - src/devices/ElectricVehicle.jl
    - src/models/complementarity_ev.jl
    - test/test_electricvehicle.jl
  modified:
    - src/devices/CapabilityTraits.jl
    - src/models/welfare_solve.jl
    - src/admm/AgrOpt.jl
    - src/admm/admm_state.jl
    - src/TSODSO.jl
    - test/test_exports.jl
decisions:
  - "V1G has no p_dch variable; V2G vars are (p_ch, p_dch, soc, soc0); the shortfall s is a model variable not exposed in vars"
  - "App. C lambda triple kept on the EV (strict ordering guard) so charge/discharge utilities are strictly concave/convex; V2G adds linear c_deg on top"
  - "TAU_EV = 2e-7, ~11x above measured floor 1.75e-8 (relative to Pmax^2) on genuine-dispatch V2G two-bus fixtures"
  - "check_ev defaults false in solve_agr!; admm_state final solves pass true (mid-loop off) so every pre-existing caller is byte-identical"
metrics:
  duration: "~75 min"
  completed: "2026-11-02"
  tasks: 3
  files: 10
requirements-completed: [DEV-06, DEV-07, DEV-10]
---

# Phase 43 Plan 02: ElectricVehicle (V1G/V2G) Summary

**One-liner:** Binary-free ElectricVehicle device (session windows as zero upper bounds, quadratic soft departure target, opt-in V2G with c_deg > 0) with its own measured-tolerance EV complementarity certificate and a 5-seed centralized-vs-ADMM crossval pinned at observed maxima.

## What Was Built

- `src/devices/ElectricVehicle.jl`: throw-guarded inner constructor (eta, Pmax, band, soc0, target, kappa, lambda strict ordering, session indices, t_arr != t_dep, V2G requires c_deg > 0), promotion outer constructor with `v2g`/`c_deg` keywords, `contribute!` returning `(; vars, p_inject, utility)` only (active-only, nothing written to residuals/objective), anonymous `soc0` Parameter, `soc_terminal` parity with PVBattery, session re-guard against the actual `T`. Wrap (overnight) windows supported as the union of two intervals.
- `src/models/complementarity_ev.jl`: scale-free `p_ch·p_dch < TAU_EV·Pmax²` certificate, `on_violation` `:error`/`:warn`, `report = true` neutralizer returning the worst ratio, `CertificateError(; kind = :ev)`; Pmax recovered as the max upper bound over the horizon (index 1 is zero outside the window). Provenance table in the file header.
- Wiring: `storage_kind(::Type{<:ElectricVehicle}) = :ev`; `solve_welfare` calls the EV certificate after the battery certificate with the same problem-class-aware `on_violation`; `solve_agr!` gains `check_ev`/`τ_ev`/`ev_on_violation`; `admm_state.jl` final solves enable it.

## Measurements (pinned, not invented)

- tau_ev floor (compliant V2G, genuine dispatch, 5 seeds): max ratio 1.75e-8 of Pmax^2 (flat price: <= 1.3e-13). `TAU_EV = 2e-7`.
- Crossval (V1G/V2G, 5 seeds, iters = 2): max |dW| 3.886e-5 / 1.807e-5; max |d lambda|_2 4.129e-6 / 9.654e-6. Bands pinned at those maxima rounded up to 4 significant digits. Table is in the test file header.
- Negative-price V2G fixture: certificate ratio >> 1 (co-charge ~0.8 of Pmax^2); EV certificate fires; battery certificate does not throw (trait routing). Without type provenance the legacy shape fallback WOULD throw -- asserted as the regression guard.

## Verification

- `test_electricvehicle.jl`: 260/260 (fast set), RED proven first (45 UndefVarError, exit 1).
- Directly affected files green: test_exports, test_device_traits, test_agr, test_pvbattery, test_aggregator, test_admm, test_admm_reactive, test_fourquadbess, test_admm_exactness_default.
- Full suite NOT run (orchestrator runs it at phase end). Golden device files untouched; `:default` path unchanged (EV opt-in, `check_ev` default false).

## TDD Gate Compliance

RED `382e287` (test) -> GREEN `90ea1cd` (feat) -> crossval test commit (see below).

## Deviations from Plan

**1. [Rule 3 - Blocking] Curated export list**
- **Found during:** Task 2 verification
- **Issue:** `test/test_exports.jl` pins the exact exported set; the new `ElectricVehicle` and `assert_ev_complementarity!` exports failed it.
- **Fix:** Added both symbols to the curated list (same treatment as FourQuadBESS / assert_4q_complementarity!).
- **Files:** test/test_exports.jl (in commit 90ea1cd)

**2. [Plan-detail] `check_ev` default**
- Plan said "mirror check_battery"; implemented default `false` (battery defaults true) so every existing caller is byte-identical; admm_state final solves pass `true`.

**3. [Plan-detail] Crossval centralized optimizer**
- The swing-price fixture returned ALMOST_OPTIMAL under the tol_gap 1e-10 override used by flat-price fixtures, so the centralized solve uses the default SOCP optimizer; bands were measured with exactly that configuration.

## Known Stubs

None.

## Threat Flags

None. T-43-02-1/2/3 mitigated (strict c_deg guard, measured provenance table, battery-cert silence test).

## Self-Check: PASSED

- src/devices/ElectricVehicle.jl, src/models/complementarity_ev.jl, test/test_electricvehicle.jl exist.
- Commits 382e287, 90ea1cd and the crossval commit present in git log.
