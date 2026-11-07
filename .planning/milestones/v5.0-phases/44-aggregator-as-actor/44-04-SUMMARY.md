---
phase: 44-aggregator-as-actor
plan: 04
subsystem: devices
tags: [behavioural-wrappers, partial-compliance, opt-out, rebound, seeded-population, per-device-baseline]
requires: ["44-01"]
provides:
  - "PartialCompliance, OptOut, Rebound wrapper devices (exported)"
  - "BehaviourSpec + apply_behaviour (default returns input ===), exported"
  - "internal _device_baseline, _BASELINE_TIEBREAK, _BEH_TAG_OPTOUT = 21, baseline_net_load (for 44-06/44-07)"
affects: [44-05, 44-06, 44-07]
tech-stack:
  added: []
  patterns: ["wrapper traits forwarded in CapabilityTraits.jl", "baseline solved once at transform time, stored in the wrapper"]
key-files:
  created:
    - src/devices/Behavioural.jl
    - test/test_behaviour.jl
  modified:
    - src/devices/CapabilityTraits.jl
    - src/experiments/materialize.jl
    - src/pricing/fit.jl
    - src/models/stochastic_welfare.jl
    - src/TSODSO.jl
    - test/test_exports.jl
key-decisions:
  - "Baseline is the FIT flat-price (FIT_λ_IMPORT = 6.6) PER-DEVICE single-device QP, NOT fit_baseline's output (fit_baseline returns per-aggregator flows, drops batteries, rejects EV/HeatPump/SmartInverterPV, runs a nested AC power flow). fit_baseline untouched."
  - "Partial compliance p' = b + xi(p-b), U' = (1-xi)Ub + xi U(p) is the exact expectation over a population with a xi-share responding (assumption A2); xi = 0 is OptOut; opt-out draw is per device, not per house."
  - "_BASELINE_TIEBREAK = 1e-6 (measured, see below)"
  - "Storage wrapped only with include_storage = true (flat-price storage baseline is degenerate)"
requirements-completed: []
duration: ~110min
completed: 2026-11-02
---

# Phase 44 Plan 04: Behavioural wrappers and population transform Summary

Exogenous, seeded behavioural scenarios as wrapper devices (PartialCompliance, OptOut, Rebound, binary-free, standard `contribute!` contract) plus an opt-in `apply_behaviour(aggs, BehaviourSpec(...); T)` transform that computes each wrapped device's FIT flat-price baseline once, at transform time.

## Tasks

1. Wrappers, traits, guards (`c9bcd03`): `src/devices/Behavioural.jl`; traits forwarded in `CapabilityTraits.jl` (`is_flexible_load`, `has_reactive_decision`, type-level `storage_kind`; OptOut is `:none`); wrapper `φ` field exposed for the Aggregator; guard Union in `_reject_unsupported_flex_devices` extended (FIT, MPC) and the same guard added at `build_stochastic_welfare` (wrappers only, so existing EV behaviour there is unchanged). FourQuadBESS / SmartInverterPV / FixedCapacitor and double wrapping rejected at wrap time.
2. BehaviourSpec, baseline, apply_behaviour (`ed760c3`): validation fail-loud (incl. unknown keywords), SplitMix64 `_flex_mix(seed, 21, bus, device_index)` + `LehmerRNG` draw, default spec returns input `===`, `baseline_net_load` helper.

## Baseline deviation wording (for docs)

The baseline `b` is the FIT price signal applied per device (a single-device flat-price solve at `FIT_λ_IMPORT`), not `fit_baseline`'s output. Rationale (CONTEXT, revised 2026-11-02): `fit_baseline` returns per-aggregator flows, drops batteries, rejects EV/HeatPump/SmartInverterPV and runs a nested AC power flow.

## Tie-break measurement (`_BASELINE_TIEBREAK = 1e-6`)

Flat price 6.6, T = 24, EV that must charge (V1G and V2G), Thermostatic, HeatPump, flex EV. Two solves differing only by a dummy variable created first agree to 1.85e-10 max (EV V1G) for every tie-break in {0, 1e-8 .. 1e-2}: Clarabel returns the analytic centre of the optimal face, so the regulariser buys solver-independent uniqueness rather than rescuing this solver. Its bias on b is linear in the value: 3.84e-11 at 1e-6 (V2G worst), 3.84e-10 at 1e-5. 1e-6 is the largest power of ten whose bias stays under the 1.85e-10 floor. `Ub` is evaluated on the unregularised utility (differs from a tie-break-free solve by 7.37e-11 max; band 2.2e-10).

## Tolerance table (3x observed max, julia 1.12.5; also in the test header)

| Quantity | Observed max | Pinned |
|---|---|---|
| xi = 1 identity (p, U) | 0.0 (bitwise) | 1e-12 (numerical-zero floor, not 3x of 0) |
| blend p' vs b + xi(p-b), xi in .25/.5/.75 | 2.20e-11 (EV) | 6.6e-11 |
| blend U' vs (1-xi)Ub + xi U | 5.26e-11 (EV) | 1.58e-10 |
| Rebound recovery violation | 4.85e-11 (HeatPump) | 1.46e-10 |
| Ub vs unregularised U | 7.37e-11 (EV) | 2.2e-10 |
| wrapped crossval \|dW\| (5 seeds x 2 constructions) | 6.91e-5 | 2.08e-4 |
| wrapped crossval \|dlambda\|_2 | 7.58e-6 | 2.28e-5 |

Crossval: two-bus, swing price, `solve_welfare` vs `solve_admm`, wrapped population (PartialCompliance(EV, .5), OptOut(HP), Rebound(PartialCompliance(Thermostatic, .5), W=6)) both hand-built and via `apply_behaviour(compliance=.5, opt_out=.4, rebound=(W=6,r=1), seed)`; all converge in 2 iterations, EV certificate ratio 0.0, exactness gate passes.

## Verification

Targeted runs (fast set): test_behaviour (196 tests), test_exports, test_electricvehicle (265), test_flex_population (39, goldens untouched, `git diff -- test/test_flex_population.jl` empty), test_actor_default_fence (5, digests untouched): all pass.

## Deviations from Plan

- Task 1 tests used a test-local baseline helper (tie-break 1e-6) because `_device_baseline` belongs to Task 2; switched to `TSODSO._device_baseline` in Task 2.
- An OptOut-only standalone model has no variable, which makes Clarabel throw a BoundsError; the OptOut test reads constants off the returned expressions instead of solving. `_device_baseline` handles variable-free devices (FixedCapacitor) by returning constants.
- `Rebound`'s curtailment variable `u` is only lower-bounded (the recovery inequality is checked on `u = max(0, p - b)`), which is the weakest and equivalent form.
- HeatPump/Thermostatic respond weakly to the swing price at the fixture scale, so the Rebound test uses a 60 spike on hours 10..12 (HeatPump) where the unwrapped device does curtail.
- Added unexported names to `test_exports.jl`'s `unexported` list (`_BEH_TAG_OPTOUT`, `_device_baseline`, `baseline_net_load`) next to the required `keep` additions.

## Known Stubs

None.

## Self-Check: PASSED

Files `src/devices/Behavioural.jl`, `test/test_behaviour.jl` exist; commits `c9bcd03`, `ed760c3` exist. REQUIREMENTS.md not touched (ACTOR-04 is marked by plan 44-07).
