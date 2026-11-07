---
phase: 43-flexible-devices-ev-heat-pump-smart-inverter
plan: 03
subsystem: flexible-devices-heatpump
tags: [heat-pump, 2R2C, thermal-model, flexible-load, crossval, binary-free]
requires:
  - "43-01 capability traits (has_reactive_decision default follows is_flexible_load)"
  - "43-02 EV wiring pattern"
provides:
  - "HeatPump{T} <: AbstractDevice: 2R2C (Tin + Tem) Forward-Euler recursion, exogenous COP vector, comfort band through T+1, joint two-state terminal kwarg"
  - "is_flexible_load(::HeatPump) = true (Aggregator eq. 3.23 power-factor roll-up with per-device phi override)"
  - "test/test_heatpump.jl: guards, closed-form step, T+1 band, terminal variants, roll-up, zero-binary, measured-then-pinned crossval"
affects:
  - "43-04 SmartInverterPV (same wiring pattern)"
tech-stack:
  added: []
  patterns:
    - "whole-horizon (T+1) state coverage, recursion t = 1:T (deliberate deviation from Thermostatic 1:(T-1))"
    - "constructor Euler-stability guard (alpha_ie+alpha_ia <= 1, alpha_me+alpha_ma <= 1)"
key-files:
  created:
    - src/devices/HeatPump.jl
    - test/test_heatpump.jl
  modified:
    - src/TSODSO.jl
    - test/test_exports.jl
decisions:
  - "Forward-Euler discretization with a load-bearing stability guard; Thermostatic.jl untouched (byte-identical)"
  - "COP and Tout are plain exogenous vectors validated length >= T at contribute! (no Parameter seam)"
  - "terminal applies jointly to both states; a pinned Real must lie inside BOTH the comfort and envelope bands"
  - "Crossval bands pinned at observed maxima: welfare 4.926e-5, lambda 5.130e-6, mu_q 2.485e-6"
metrics:
  duration: "~60 min"
  completed: "2026-11-02"
  tasks: 3
  files: 4
requirements-completed: [DEV-08]
---

# Phase 43 Plan 03: HeatPump (2R2C) Summary

**One-liner:** Binary-free HeatPump device with a coupled two-state 2R2C building model (exogenous COP keeps heat linear), a hard comfort band through T+1, a joint two-state terminal rule, flexible-load reactive roll-up, and a 5-seed centralized-vs-ADMM crossval pinned at measured maxima.

## What Was Built

- `src/devices/HeatPump.jl`: throw-guarded inner constructor (band orders, b > 0, Pmax > 0, each alpha >= 0, beta > 0, Euler stability for both states, ICs inside their bands, phi in (0,1], terminal in nothing/:cyclic/value-in-both-bands), promotion outer constructor with `phi`/`terminal` keywords, `is_flexible_load(::HeatPump) = true`, `contribute!` returning `(; vars = (; p, Tin, Tem, Tin0, Tem0), p_inject, utility)` with anonymous JuMP objects only and length guards on both `Tout` and `COP`.
- Include wiring after ElectricVehicle.jl; `HeatPump` added to the curated export list in `test/test_exports.jl`.
- No CapabilityTraits edit: `has_reactive_decision(::HeatPump) === true` follows from the 43-01 default.

## Measurements (pinned, not invented)

Two-bus fixture, T = 24, swing price, 5 seeds, `solve_welfare` vs `solve_admm` (default reactive mode, resolves LIVE, iters = 2 on every seed, dispatch genuine: p reaches Pmax, Tin touches 19):

- max |dWelfare| = 4.925e-5 (band 4.926e-5)
- max |dLambda|_2 = 5.129e-6 (band 5.130e-6)
- max |dMu_q|_2 = 2.484e-6 (band 2.485e-6)

Per-seed table is in the test file header.

## Verification

- `test_heatpump.jl`: 101 passed (8 items, fast set) before crossval; combined run with test_exports, test_device_traits, test_aggregator, test_electricvehicle, test_admm_reactive: 661/661.
- Thermostatic.jl untouched (no diff). Full suite NOT run (orchestrator runs it at phase end).

## TDD Gate Compliance

RED `0ba87e6` (test) -> GREEN `14bbc19` (feat) -> crossval `8e493bb` (test). Caveat: the first RED attempt used a scratch TestItemRunner script whose workers could not load TSODSO, so it errored for the wrong reason; the file was proven failing only in the sense that `HeatPump` did not exist. All verification afterwards used `Pkg.test()` with `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=...`, which works.

## Deviations from Plan

**1. [Rule 3 - Blocking] Curated export list**
- `test/test_exports.jl` pins the exact exported set; `HeatPump` added (commit 14bbc19).

**2. [Plan-detail] Terminal-variant test fixtures**
- Pinning both states to one value, and cyclic closure, are physically infeasible on some ambient/IC choices because p >= 0 (heating only) cannot cool Tin quickly. Test fixtures were chosen per variant (cyclic: Tem0 = 20, Tout = 15; pinned 20.5: Tem0 = 21, Tout = 17) after scanning feasibility; no device logic or tolerance was loosened.

**3. [Plan-detail] Crossval also pins mu_q**
- Plan listed |dMu|_2 among measured quantities; it is measured and pinned (LIVE mode populates `mu_q`).

## Known Stubs

None.

## Threat Flags

None. T-43-03-1/2 mitigated (sign + Euler stability guards, IC-in-band guards); T-43-03-3 mitigated (Thermostatic.jl no diff); no packages added.

## Self-Check: PASSED

- src/devices/HeatPump.jl, test/test_heatpump.jl exist; commits 0ba87e6, 14bbc19, 8e493bb in git log.
