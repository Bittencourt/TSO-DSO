---
phase: 43-flexible-devices-ev-heat-pump-smart-inverter
fixed_at: 2026-11-02T00:00:00Z
review_path: .planning/phases/43-flexible-devices-ev-heat-pump-smart-inverter/43-REVIEW.md
iteration: 1
findings_in_scope: 6
fixed: 6
skipped: 0
status: all_fixed
---

# Phase 43: Code Review Fix Report

**Fixed at:** 2026-11-02
**Source review:** .planning/phases/43-flexible-devices-ev-heat-pump-smart-inverter/43-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 6 (0 critical, 6 warning; Info findings out of scope)
- Fixed: 6
- Skipped: 0

Work was done directly on branch `agents/session-2026-10-23` (as directed by the orchestrator),
not in a separate worktree. The default path (no `flex_devices`, `:default`, `:case_a_784`) is
byte-identical: the new WR-06 digest fence was computed at the pre-phase commit `0fe0777` and
matches today. No existing golden or gate was re-pinned or loosened.

Verification run (fast set, foreground): test_electricvehicle, test_flex_population,
test_heatpump, test_smartinverterpv, test_exports, test_device_traits, test_fit,
test_pricing_fit, test_mpc_loop, test_admm: 1389/1389 pass, 0 soft-scope warnings.

## Fixed Issues

### WR-02: Seeds derived from `hash((...))` are not stable across Julia versions

**Files modified:** `src/experiments/materialize.jl`, `test/test_flex_population.jl`
**Commit:** d7f7ed6
**Applied fix:** Added `_flex_mix` (SplitMix64 fold over integer-coded tags, with integer
constants `_FLEX_TAG_*` / `_FLEX_SUB_*`). `_flex_ev` and `_flex_heatpump` no longer touch
`Base.hash`. The seeding test now uses literal integer population seeds, and a new test pins
`_flex_mix` values. `sub_seed` and `_case_a_house_seed` were NOT changed (golden-pinned).
**Known follow-up:** `_case_a_house_seed` (and `sub_seed`) still derive from `Base.hash` and
carry the same cross-Julia-version risk; changing them re-pins the `:case_a_784` goldens, so
that is deferred.

### WR-05: New devices are not handled by the FIT tariff path or the MPC loop

**Files modified:** `src/pricing/fit.jl`, `src/experiments/mpc_loop.jl`,
`src/experiments/materialize.jl`, `test/test_flex_population.jl`
**Commit:** 797e2be
**Applied fix:** New `_reject_unsupported_flex_devices(devices, caller)` throws an
`ArgumentError` naming the offending types (`ElectricVehicle` / `HeatPump` / `SmartInverterPV`).
It is called at the top of `_fit_pv_and_flex` and right after population materialization in
`_run_mpc`. The `build_population` docstring now documents the limitation. A test checks each
device type, alone, through `fit_baseline` and the MPC guard, and checks that legacy devices
are not rejected. Note: `Scenario` cannot carry `flex_devices`, so the MPC guard is defensive
and is tested at the helper level.

### WR-06: Weak or picked tolerances and a thin byte-identity fence

**Files modified:** `test/test_flex_population.jl`
**Commit:** 459778a
**Applied fix:**
- The welfare check is now measured over 6 seeds (`SEED_2BUS + 0:5`): relative ADMM-vs-centralized
  gaps lie in [2.6e-5, 3.91e-5]. The band is 3 x the measured maximum = 1.2e-4 (was 1e-3).
- The fence now folds every field of every device and profile (FNV-1a over bit patterns) and
  pins digests for `:default` (`0x9358a27f6c14df69`) and `:case_a_784` (`0x2c853fe6bee1cb41`).
  They were computed at the pre-phase commit `0fe0777` in a scratch worktree and are identical to
  the current tree. It also asserts kwarg-absent == `flex_devices = nothing` on the full digest.

### WR-03: EV certificate tolerance and ADMM cross-validation bands

**Files modified:** `src/models/complementarity_ev.jl`, `src/admm/admm_state.jl`,
`test/test_electricvehicle.jl`
**Commit:** 5177a0b
**Applied fix:**
- ADMM-final `max_ratio` was measured at the call site (a hook on the certificate in
  `solve_admm`), over about 64 runs on 2 fixture families: the two-bus swing/flat price test EV,
  two-EV sessions, and flex-population seeded EVs (`_flex_ev`, 24 houses) converted to V2G.
  Results:
  - swing test EV: max 3.19e-8
  - two EVs: max 4.80e-9
  - flat price: up to 5.65e-5
  - flex-seeded: swing h=13 4.30e-4, swing h=4 1.197e-3
- 3 of 48 flex runs and all 3 flat test-EV runs exceed the centralized `TAU_EV = 2e-7`, so
  reusing it would make `solve_admm` throw on compliant consolidations. Per the honesty policy,
  a separate `TAU_EV_ADMM = 3.6e-3` (3 x the measured max 1.197e-3, rounded up) is used at the two
  ADMM final-consolidation call sites. The centralized `TAU_EV` is unchanged, and the new constant
  affects only the new V2G EV certificate. The measurement table is in the
  `complementarity_ev.jl` header.
- A new test item exercises ADMM final consolidation on the flat-price fixture and on flex house
  4 (both would have thrown under `TAU_EV`).
- Crossval bands are now 3 x the 5-seed observed maxima: welfare V1G 1.166e-4 / V2G 5.422e-5;
  lambda V1G 1.239e-5 / V2G 2.897e-5. These replace the "maximum rounded up" bands. The test
  header is updated.
- Caveat: no flex-population V2G case exists in production, because `_flex_ev` builds V1G
  sessions. The flex fixtures here are seeded sessions with V2G enabled for measurement only.

### WR-01: Wrap-around EV sessions have no link between evening charging and the departure target

**Files modified:** `src/devices/ElectricVehicle.jl`, `src/experiments/materialize.jl`,
`test/test_electricvehicle.jl`
**Commit:** c1190cb
**Status:** fixed: requires human verification (a semantic limitation was documented, not removed)
**Applied fix:** Chose the minimal, honest option. The model was not silently redefined. The
`ElectricVehicle.jl` header and docstring and the `materialize.jl` calibration comment now state
precisely that:
- `soc0` is the SOC at hour 1, not at arrival.
- For wrap sessions only hours `1..t_dep` count toward the departure target.
- The evening window only raises `soc[T+1]`, which is free unless `soc_terminal` is set.
- No trip energy is modelled.

A new test pins the behaviour: with morning charging fixed to 0, evening charging at Pmax leaves
the shortfall unchanged while raising `soc[T+1]` by more than 10. A true overnight model
(cyclic SOC plus trip consumption) remains deferred, and the researcher should decide whether it is
needed before the flex-population results are cited.

### WR-04: The high-PV re-measurement is censored exactly where the question is asked

**Files modified:** `scripts/socp_highpv_remeasure.jl`, `results/socp_highpv/highpv_exactness.csv`,
`docs/literate/socp_highpv_exactness.jl`
**Commit:** fa5d7e6
**Applied fix:** A clean seam exists: `solve_welfare` already takes `τ` (the battery tolerance).
For `refused_battery` rows the script re-solves with `τ = 1e12` and the cone gate kept at
`1e-4`, purely to harvest `maxgap` / `max_ratio`; verdicts are unchanged. A new `gap_source`
column records provenance. The script was re-run (30 rows; all other verdicts identical) and the
CSV regenerated. The 4 refused rows (pv=1.2: active_only 1/5, with_optimal_q 3/5) now report
cone ratios 0.013 / 0.019 / 0.065 / 0.018, all far below 1. The stress-regime exactness with
optimal Q therefore holds with no censoring (max ratio 0.0687 over all 5 seeds). The literate
page now prints the refused fraction (`refused/n`) and a `harvested` count, and its honesty note
explains the re-solve and its limits. The page runs end-to-end.

## Skipped Issues

None.

## Notes

- Info findings IN-01..IN-06 were out of scope (`fix_scope = critical_warning`) and are untouched.
- No `Project.toml` / `Manifest.toml` changes were committed.

---

_Fixed: 2026-11-02_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
