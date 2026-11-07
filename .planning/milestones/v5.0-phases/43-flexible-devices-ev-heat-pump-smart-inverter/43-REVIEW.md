---
phase: 43-flexible-devices-ev-heat-pump-smart-inverter
reviewed: 2026-11-02T00:00:00Z
depth: standard
iteration: 2
files_reviewed: 26
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
  - src/pricing/fit.jl
  - src/experiments/mpc_loop.jl
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
  warning: 0
  info: 4
  total: 4
status: clean
---

# Phase 43: Code Review Report (iteration 2)

**Reviewed:** 2026-11-02
**Depth:** standard
**Status:** clean (0 critical, 0 warning; 4 info carried or new)

## Summary

I re-inspected each fix commit (`d7f7ed6`, `797e2be`, `459778a`, `5177a0b`, `c1190cb`, `fa5d7e6`). The fixed warnings WR-01..WR-06 are resolved and I found no regressions. I did not run the test suite.

- **WR-02 (seeds).** `_flex_mix` uses only UInt64 arithmetic and integer tag codes. The `Base.hash` calls are gone from `_flex_ev` and `_flex_heatpump`. `v % UInt64` is safe for negative inputs, and the `Int(h % UInt64(typemax(UInt32)))` reduction always fits `Int`. `sub_seed` and `_case_a_house_seed` are untouched, so the golden-pinned `:case_a_784` path is intact. The fixer recorded the remaining `Base.hash` use there as a known follow-up.
- **WR-05 (FIT and MPC guards).** `_reject_unsupported_flex_devices` is defined in `pricing/fit.jl`. It is called at module scope inside functions, so include order does not matter. In `_run_mpc` the guard runs after `aggs` is bound, so there is no scoping problem. The guard takes only `agg.devices` and does not change the legacy path.
- **WR-06 (welfare band and fence).** The welfare band is now 3x the measured maximum over 6 seeds, and the digest fence covers every field. The docs and code agree. I did not recompute the digests.
- **WR-03 (EV certificate).** `TAU_EV_ADMM` is applied only at the two ADMM final-consolidation call sites in `admm_state.jl` (lines 159 and 195). The centralized `TAU_EV` default in `AgrOpt.jl` and `assert_ev_complementarity!` is unchanged. The header table documents how the constant was measured, which meets the measured-not-picked policy.
- **WR-01 (wrap-session EV).** The model was not changed. The header, docstring and calibration comment now agree with the model: `soc0` is the SOC at hour 1, only hours `1..t_dep` count toward the target, and there is no trip energy. A test pins this. This is acceptable as documented and pinned. The researcher must still decide whether a true overnight model is needed before citing flex-population EV results.
- **WR-04 (high-PV re-measurement).** For `refused_battery` rows the script re-solves with the battery `τ = 1e12` and keeps the cone gate at `1e-4`. The verdict is unaffected. The harvested cone gap is still gated, and the `gap_source` column records provenance. If the cone gate itself refused, that row falls into the `:socp_exact` branch, so there is no path that silently ungates the cone.

## Info

### IN-01: `TAU_EV_ADMM` is large relative to typical values and the sample is heavy-tailed

**File:** `src/models/complementarity_ev.jl:82`
**Issue:** 45 of 48 flex runs sit at or below 1.6e-6, but two runs reach 4.3e-4 and 1.197e-3. The tolerance of 3.6e-3 is 3x the sample maximum of a heavy-tailed distribution, and it sits about 1e3 to 1e4 above typical values. A real simultaneous charge/discharge of about 6% of Pmax would pass. It is still about 220x below the negative-price co-charge fixture (ratio near 0.8), so the certificate does catch gross violations. No production flex population uses V2G yet, so the measured sample is a proxy.
**Fix:** Re-measure on a larger seed sweep when V2G flex populations are enabled in production. Consider a dedicated test that fixes the ratio of the worst seeded runs (h=4 and h=13) so that drift is visible.

### IN-02: The MPC guard is unreachable from the public API

**File:** `src/experiments/mpc_loop.jl:289-291`
**Issue:** `Scenario` cannot carry `flex_devices`, so `_reject_unsupported_flex_devices` in `_run_mpc` can never fire from `run_mpc`. The test covers it only at the helper level. This is defensive and harmless, but the code gives no indication that it is untested through `run_mpc`.
**Fix:** Keep the guard, and leave a comment saying it is defensive until `Scenario` gains a `flex_devices` field.

### IN-03: `Base.hash` seeds remain in `_case_a_house_seed` and `sub_seed` (carried forward)

**File:** `src/experiments/materialize.jl` (`_case_a_house_seed`, `sub_seed`)
**Issue:** The fixer documented this as deferred because changing it would re-pin the goldens. Cross-Julia-version reproducibility is at risk. The memory notes on td6node and Julia 1.12.7 show this class of drift is real in this repo.
**Fix:** Run a dedicated golden-re-pin task, or pin the Julia version in CI and in the docs.

### IN-04: Previously reported IN-01..IN-06 remain untouched (carried forward)

**File:** see `43-REVIEW.iter2.md`
**Issue:** The Info findings were out of the fix scope and are unchanged.
**Fix:** Triage them in a later pass.

---

_Reviewed: 2026-11-02_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
