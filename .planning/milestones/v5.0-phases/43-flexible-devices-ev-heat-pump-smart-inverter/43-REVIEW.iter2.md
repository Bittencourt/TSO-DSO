---
phase: 43-flexible-devices-ev-heat-pump-smart-inverter
reviewed: 2026-11-02T00:00:00Z
depth: standard
files_reviewed: 24
files_reviewed_list:
  - src/devices/CapabilityTraits.jl
  - src/devices/AbstractDevice.jl
  - src/devices/Aggregator.jl
  - src/devices/ElectricVehicle.jl
  - src/devices/HeatPump.jl
  - src/devices/SmartInverterPV.jl
  - src/models/complementarity_ev.jl
  - src/models/welfare_solve.jl
  - src/admm/AgrOpt.jl
  - src/admm/DsoOpt.jl
  - src/admm/admm_state.jl
  - src/core/ModelContext.jl
  - src/experiments/materialize.jl
  - src/TSODSO.jl
  - scripts/socp_highpv_remeasure.jl
  - docs/literate/socp_highpv_exactness.jl
  - docs/make.jl
  - scripts/README.md
  - test/test_device_traits.jl
  - test/test_electricvehicle.jl
  - test/test_heatpump.jl
  - test/test_smartinverterpv.jl
  - test/test_flex_population.jl
  - test/test_exports.jl
findings:
  critical: 0
  warning: 6
  info: 6
  total: 12
status: issues_found
---

# Phase 43: Code Review Report

**Reviewed:** 2026-11-02
**Depth:** standard
**Files Reviewed:** 24
**Status:** issues_found

## Summary

The default path looks preserved: the refactor traits reproduce the old
`isa FourQuadBESS || is_flexible_load` probe, and the type stash is only read for classification.
The SOC cone form `[S_inv, pv_used, q] in SecondOrderCone()` is correct, and the `q` sign
convention is consistent with the `-Pdc·tanφ + q_inject` residual. There are no blockers.

The weaknesses are:
- an EV session-semantics problem for the wrap-around sessions that `materialize.jl` generates by default;
- seed reproducibility across Julia versions;
- certificate and test tolerances that were pinned or picked rather than measured;
- a censored headline measurement;
- two code paths (the FIT tariff and MPC) that do not know the new devices.

## Warnings

### WR-01: Wrap-around EV sessions (`t_dep < t_arr`) have no link between evening charging and the departure target

**File:** `src/devices/ElectricVehicle.jl:300-345`, `src/experiments/materialize.jl:~596-612`

The model sets `soc[1] = soc0` and the soft target `s ≥ E_target − soc[t_dep+1]`. For a wrap
session (the typical `_flex_ev` draw: arrival at hour 15-22, departure at hour 5-10), the energy
needed by the target is charged only in hours `1..t_dep`.

- The evening window `t_arr..T` is disconnected from the target. Charging there is driven only by
  the `a_ch·p_ch` utility, and `soc[T+1]` is free unless `soc_terminal = :cyclic`.
- `soc0` is documented as "arrival SOC" but is applied at `t = 1`, when the car is already
  plugged in.
- No trip energy is consumed between departure and re-arrival; SOC stays flat while the window
  bounds are zero.

The "overnight session" that the docs and the `materialize` comments describe is therefore not
what is modelled: the target forces a morning top-up and the evening charge is an optional bonus.
Flex-population results (prices, DLMPs, the EV-certificate fixtures) rest on this.

**Fix:** For wrap sessions, either model the overnight need explicitly or default to
`soc_terminal = :cyclic` with a trip-consumption term. At minimum, document the limitation and
add a test that fails if a wrap EV can charge in the evening with no effect on the departure
shortfall.

### WR-02: Seeds derived from `hash((...))` are not stable across Julia versions

**File:** `src/experiments/materialize.jl:570-576` (`_flex_ev`), `:612-616` (`_flex_heatpump`);
related test: `test/test_flex_population.jl:112-135`

- Seeds are built as `Int(hash((s_pop, :ev, bus, house_index)) % typemax(UInt32))` and then fed
  to StableRNGs.
- StableRNGs guarantees a fixed stream per seed, but `Base.hash` makes no such guarantee, and its
  algorithm changed in Julia 1.12.
- The project pins the Julia version for reproducibility, so a Julia bump silently changes every
  flex session.
- The seeding test's statistical assertions (`length(s) > 30`, `length(Set(...)) > 7`) depend on
  the same hash output and could flip.
- The existing `_case_a_house_seed` precedent has the same weakness; this phase copies it into
  new code.

**Fix:** Derive seeds with a portable mix (fixed FNV or SplitMix over integer-coded tags, or the
project's existing `sub_seed`). Do not hash a `Symbol` or a tuple.

### WR-03: EV certificate tolerance and ADMM cross-validation bands have little or no measured margin

**File:** `src/models/complementarity_ev.jl:43-48`, `src/admm/admm_state.jl:~155, ~190`,
`test/test_electricvehicle.jl:19-36, 495`

- `TAU_EV = 2e-7` is about 11× the worst of 5 seeds, all on one two-bus fixture (noise floor
  1.75e-8).
- The same default is applied unmodified in the ADMM final consolidation (`check_ev = true`, no
  `τ_ev` override). For the battery, ADMM needed a loosened `τ_batt = 1e-3` for exactly this
  reason.
- The header says the ADMM final-consolidation sizing is recorded in `test_electricvehicle.jl`,
  but the test only asserts that nothing throws on one fixture. It records no measured ratio.
- The cross-validation bands are "pinned at the observed maxima rounded UP to 4 significant
  digits". That leaves effectively zero margin, so a different Julia, Clarabel or BLAS build can
  flip a deterministic test. Project memory already records numerical drift between Julia 1.12.5
  and 1.12.7.

**Fix:**
- Measure the ADMM-final `max_ratio` and size `τ_ev` for that call site separately, as was done
  for `τ_batt`, on more than one fixture, including the flex population.
- Pin the cross-validation bands at a stated multiple of the measured maximum (for example 2-3×).

### WR-04: The high-PV re-measurement is censored exactly where the question is asked

**File:** `scripts/socp_highpv_remeasure.jl:~137-170`, `results/socp_highpv/highpv_exactness.csv`,
`docs/literate/socp_highpv_exactness.jl:~95-110`

- At pv = 1.2, 3 of the 5 `with_optimal_q` seeds and 1 of the 5 `active_only` seeds end in
  `refused_battery`.
- Those rows have no `maxgap`, `max_ratio` or welfare, because a refused solve returns no context.
- The doc's "max ratio" table takes its maximum only over the surviving rows. The DEV-09 question
  — is the SOCP still exact with optimal Q in the stress regime — is therefore only partly
  answered at that point.
- The cone gate runs first, so `socp_gate_passed = true` is a legitimate lower bound, but the
  quantitative gap is missing.

**Fix:**
- Harvest the cone gap for refused non-SOCP rows too: catch the `CertificateError` and re-solve
  with `on_violation = :warn` via an oracle-path seam, or expose `maxgap` in the error payload.
- State explicitly in the doc that the stress-regime result is censored.
- Add the refused fraction to the summary table.

### WR-05: New devices are not handled by the FIT tariff path or the MPC loop

**File:** `src/pricing/fit.jl:~100-117` (`_fit_pv_and_flex`), `src/experiments/mpc_loop.jl:~525-545, 1204-1235`

- `_fit_pv_and_flex` sends every non-`PVBattery` device through the "flexible load" branch, with
  `consumption += -p_inject`.
  - A `SmartInverterPV` then contributes a negative consumption and no `Ppv`, so its generation
    is treated as load reduction and its `q` is ignored.
  - V2G EV discharge is likewise treated as negative load.
  - Nothing warns or throws.
- `mpc_loop.jl` dispatches on `isa PVBattery/FourQuadBESS/Thermostatic`, and
  `_mpc_device_hour_utility` has no method for the new types. That fails loudly with a
  `MethodError`, but it means `flex_devices` populations cannot be fed to `run_mpc`.
- `build_population(...; flex_devices=...)` is a public opt-in with no guard, so running
  `compare_tariffs` or `run_mpc` on it is a silent trap.

**Fix:** Add explicit `ArgumentError` guards for the unsupported device types in
`_fit_pv_and_flex` and `run_mpc`, or implement the methods. Document the limitation in
`build_population`.

### WR-06: Weak or picked tolerances and a thin byte-identity fence in `test_flex_population.jl`

**File:** `test/test_flex_population.jl:15-37, 183-187`

- The ADMM-vs-centralized check is `abs(res.welfare - obj) <= 1e-3 * max(1.0, abs(obj))`. The
  same fixture has measured gaps of about 1e-5 in `test_electricvehicle.jl`, so this tolerance is
  picked rather than measured, and 100× or more looser than the measurement, which makes the test
  nearly non-failing.
- The "byte-identity fence" compares only `(bus, φ, device types, Pdc)`. It does not compare any
  device parameter or profile, and it checks only the kwarg-absent case against `nothing`, not
  against a pre-phase golden. It would not catch a change in the default path's device values.

**Fix:** Pin the welfare tolerance to a measured value, as in the EV crossval. Compare device
fields (`d == d2` on the structs, or a field-wise hash), and ideally compare against a stored
pre-phase golden digest.

## Info

### IN-01: Stale and contradictory trait documentation
- `src/devices/AbstractDevice.jl:~113-121` says "the `:ev` value is reserved for the device plan
  that introduces EVs", but `CapabilityTraits.jl:25` already defines it.
- `SmartInverterPV.jl:~86` says `CapabilityTraits.jl` is "reserved for the golden-pinned legacy
  devices", yet the new `ElectricVehicle` `storage_kind` override lives there.

Pick one convention and update the comments.

### IN-02: `_with_flex` silently skips a house
In `src/experiments/materialize.jl:~676`, `scale > 0 || return a` silently drops the flex devices
of a zero-demand aggregator. This contradicts the `_flex_selectors` promise never to silently
shrink the population. Throw or warn instead.

### IN-03: Zero-panel `SmartInverterPV` is a free STATCOM
In `materialize.jl:~650` and `scripts/socp_highpv_remeasure.jl`, a device with `ppv === nothing`
(or `Ppv = 0`) still gets a cone `S_inv` of `0.1·scale` at no cost, which makes it a costless
reactive source. That is intentional for the `q_only_capability` variant, but in the flex
population it is an undocumented side effect.

### IN-04: Droop comparator uses system-max voltage and an absolute threshold
In `scripts/socp_highpv_remeasure.jl:~205-225`:
- Every inverter is evaluated at the single per-hour maximum bus voltage, while `q_opt` is summed
  over buses, so droop and optimum are compared at different locations.
- The sign-agreement and active-hour thresholds are an absolute `1e-6`, regardless of nameplate.

The comparison is qualitative only. State that in the doc.

### IN-05: `materialize.jl` docstring reformatting is non-functional
The `_case_a_rung_counts` docstring now has a very long single line, and one
`isempty(...) && throw(...)` was rewrapped. This is unrelated to phase 43 and adds diff noise to
a golden-adjacent file.

### IN-06: `HeatPump` utility form
`utility = −(b/2)·Σ(Tin − Tmin)²` penalizes being warmer than `Tmin`, so it is an energy-saving
preference rather than a comfort utility. It is a consistent QP and matches `Thermostatic`, but
the docs call it a "comfort utility". State the interpretation (the optimum is at the band floor).

---

_Reviewed: 2026-11-02_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
