---
phase: 43-flexible-devices-ev-heat-pump-smart-inverter
plan: 04
subsystem: flexible-devices-smartinverterpv
tags: [smart-inverter, pv, reactive, socp, apparent-power-cone, crossval, binary-free]
requires:
  - "43-01 capability traits (has_reactive_decision)"
  - "43-03 wiring pattern"
provides:
  - "SmartInverterPV{T} <: AbstractDevice: curtailable pv_used + sign-free q in one anonymous per-t SecondOrderCone, zero device utility"
  - "has_reactive_decision(::SmartInverterPV) = true declared in the device file (ADMM reactive default resolves LIVE)"
  - "test/test_smartinverterpv.jl: guards, 4-tuple contract, zero-utility, anonymity, cone binding, zero-binary, trait roll-up, measured-then-pinned crossval incl. mu, routing proof"
affects:
  - "43-05 (high-PV SOCP exactness re-measurement and Volt-VAR comparator are NOT in this plan)"
tech-stack:
  added: []
  patterns:
    - "FourQuadBESS widened return (vars, p_inject, q_inject, utility) consumed via Aggregator hasproperty branch, zero Aggregator edits"
key-files:
  created:
    - src/devices/SmartInverterPV.jl
    - test/test_smartinverterpv.jl
  modified:
    - src/TSODSO.jl
    - test/test_exports.jl
decisions:
  - "Literal per-t PV bound (no Parameter seam); utility is the zero QuadExpr; q priced only via network balances"
  - "Crossval bands pinned at observed maxima: welfare 3.168e-5, lambda 3.911e-6, mu_q 4.622e-6"
  - "Routing proof uses LIVE no-slack :balance_q + OFF/CERTIFIED fail-loud, not a CERTIFIED qag_dso pin (see deviations)"
metrics:
  duration: "~45 min"
  completed: "2026-11-02"
  tasks: 3
  files: 4
requirements-completed: [DEV-09]
---

# Phase 43 Plan 04: SmartInverterPV Summary

**One-liner:** PV with a smart-inverter optimal-Q capability (curtailable pv_used plus sign-free q inside one anonymous apparent-power SOC per hour, zero device utility) that routes q through the existing LIVE reactive consensus, certified against the centralized solve with measured welfare/lambda/mu bands.

## What Was Built

- `src/devices/SmartInverterPV.jl`: throw-guarded constructor (S_inv > 0, Ppv >= 0), float-promoting outer constructor, `has_reactive_decision = true`, `contribute!` returning `(; vars = (; pv_used, q), p_inject, q_inject = q, utility)` with a zero `QuadExpr`, a profile-length guard, and only anonymous JuMP objects. PVBattery.jl and FourQuadBESS.jl are untouched.
- `include` wired after HeatPump.jl; `SmartInverterPV` added to the curated export list in `test/test_exports.jl`.

## Measurements (pinned)

Two-bus, T = 24, swing price, S_inv = 0.03, 5 seeds, `solve_welfare` vs `solve_admm` (default reactive mode resolves LIVE, iters = 2): max |dWelfare| 3.167e-5, max |dLambda|_2 3.910e-6, max |dMu_q|_2 4.621e-6; bands pinned at these maxima rounded up. Dispatch is genuine: pv_used reaches S_inv, 1-5 hours curtailed, centralized |q| reaches ~0.0087. Per-seed table is in the test file header.

## Verification

Combined run (smartinverterpv, fourquadbess, admm_reactive, device_traits, exports, aggregator, heatpump, electricvehicle): 1114/1114. Full suite not run (orchestrator runs it at phase end).

## Deviations from Plan

**1. [Rule 1 - Plan premise wrong] CERTIFIED routing item reframed**
- **Issue:** the plan's item asked for a `reactive_consensus = CERTIFIED` solve with a pinned qag_dso trajectory. `build_dso_opt` deliberately throws ArgumentError for any explicit OFF/CERTIFIED mode on a population containing a `has_reactive_decision` device (the q would be silently dropped). The device therefore cannot run under CERTIFIED by design.
- **Fix:** the routing item asserts (a) OFF and CERTIFIED fail loud, (b) the LIVE run's published `:balance_q` passes `assert_no_slack`, (c) in the centralized model q reaches the network only as the Aggregator's +1 `:Rq` coefficient. No guard was loosened.
- **Commit:** test(43-04) crossval commit.

**2. [Rule 3 - Blocking] Curated export list**
- `test/test_exports.jl` pins the exact exported set; `SmartInverterPV` added.

## Known Stubs

None.

## Threat Flags

None. T-43-04-1..4 mitigated (routing item, constructor guards, anonymity test, zero-utility test); no packages added.

## TDD Gate Compliance

RED `5f41387` (test) -> GREEN `cd5469d` (feat) -> crossval test commit (third task). RED failed on the missing `SmartInverterPV` type.

## Self-Check: PASSED

- src/devices/SmartInverterPV.jl and test/test_smartinverterpv.jl exist; commits 5f41387, cd5469d and the crossval commit are in git log.
