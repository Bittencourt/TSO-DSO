---
phase: 43-flexible-devices-ev-heat-pump-smart-inverter
verified: 2026-11-02T00:00:00Z
status: passed
score: 5/5 success criteria verified (researcher decisions recorded 2026-11-02)
overrides_applied: 0
re_verification: false
gaps: []
human_verification:
  - test: "WR-01 wrap-session EV semantics: decide whether the same-day approximation (soc0 at hour 1, only hours 1..t_dep count toward the target, no trip energy) is acceptable for the flex-population EV results you intend to cite"
    expected: "Either accept the documented limitation, or schedule a cyclic-SOC / trip-consumption overnight model before citing EV-population results"
    why_human: "Modeling-fidelity judgment about the thesis use case; the limitation is documented in code, docs and pinned by a test, but whether it is adequate is a research decision"
  - test: "High-PV regime reading: 4 of 30 points are refused_battery (pv 1.2) and physics status is infeasible at pv 1.2 on most points; confirm the framing 'SOCP exact, battery certificate refuses' is the intended thesis statement"
    expected: "Researcher agrees the re-measurement answers DEV-09 (cone certificate never refused; refusals are battery-complementarity, reported with harvested cone gap 0.013-0.065)"
    why_human: "Interpretation of research findings, not code correctness"
---

# Phase 43: Flexible Devices (EV, Heat Pump, Smart Inverter) Verification Report

**Phase Goal:** A researcher can add EVs, heat pumps and smart-inverter PV as convex, binary-free devices, each validated against the centralized solve before ADMM use.
**Status:** human_needed (no gaps; two research-judgment items)
**Re-verification:** No, initial verification

Evidence basis: direct reading of source, tests, CSV and docs at HEAD f9feeea, plus the pre-established full-suite result (34468 pass / 0 fail / 0 error / 7 broken, all allowlisted). SUMMARY claims were not taken as evidence.

## Observable Truths (roadmap success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Capability-trait refactor lands first; existing fixtures keep reactive mode and goldens unchanged | VERIFIED | `has_reactive_decision` / `storage_kind` defined in `src/devices/AbstractDevice.jl` with defaults; typed overrides for existing classes isolated in `src/devices/CapabilityTraits.jl`. `DsoOpt.jl:176-181,336` now uses the trait instead of the isa probe. `git diff 0fe0777..HEAD` touches NONE of the golden device files (PVBattery, Thermostatic, FourQuadBESS, FixedCapacitor, Deferrable, Interruptible, Scenario) and no golden/test-fixture files. `test_device_traits.jl` has 5 testitems (truth table over every existing device type, reactive-default resolution on existing populations, stash pairing, legacy shape fallback, OFF/CERTIFIED guard); full suite green. |
| 2 | EV V1G with seeded sessions + soft target, V2G with c_deg > 0, certificate reports simultaneous charge/discharge incl. negative-price fixture | VERIFIED | `ElectricVehicle.jl` (406 lines): window as variable bounds, quadratic soft target, `c_deg` rejected at construction when `<= 0` under V2G. `complementarity_ev.jl` (145 lines) = EV-specific certificate, routed by `storage_kind === :ev`; wired into `welfare_solve.jl` and `AgrOpt.jl`/`admm_state.jl` (`check_ev`, final consolidation only, default false so the default path is byte-identical). `test_electricvehicle.jl`: 11 testitems including "V2G negative-price fixture -- certificate REPORTS co-charge, battery cert silent", V1G no-op, zero-binary, constructor guards. Seeded sessions: `_flex_mix` portable integer mix, pinned by test (WR-02 fix). |
| 3 | Heat pump 2R2C, exogenous COP(T_out), comfort band, consistent terminal rule | VERIFIED | `HeatPump.jl` (393 lines); `test_heatpump.jl` 8 testitems (closed-form 2R2C step, comfort band through T+1 with terminal variants, short Tout/COP throws, flexible-load roll-up via traits, zero binaries, crossval). |
| 4 | PV optimal Q within apparent-power cone; SOCP exactness re-measured in high-PV regime; Volt-VAR droop only post hoc | VERIFIED | `SmartInverterPV.jl` (131 lines), `has_reactive_decision = true`, Q routed through the reactive consensus. `test_smartinverterpv.jl` 9 testitems (cone binds, widened 4-tuple contract, zero utility, routing proof). Droop (`DROOP_V`, `droop_qfrac`) exists ONLY in `scripts/socp_highpv_remeasure.jl` (and the docs page); grep of `src/` finds no droop — it never enters a constraint. `results/socp_highpv/highpv_exactness.csv` committed: 30 rows (2 pv scales x 3 variants x 5 seeds). Re-measured, verdict counts: 26 exact, 4 refused_battery (all pv 1.2: 1 active_only, 3 with_optimal_q). Cone gate passed (`socp_gate_passed=true`, `n_ratio_gt1=0`) on all 30 rows; max ratio 0.0687 (with_optimal_q) except a 0.159 q_only point, all < 1. Refused rows carry `gap_source=diag_resolve_after_refused_battery` and a `detail` string. The literate page (`docs/literate/socp_highpv_exactness.jl`, registered in `docs/make.jl`) states the refused fraction, distinguishes `refused_battery` (later battery certificate) from `refused_socp_exact`, and says refusals are not SOCP inexactness; it also reports the physics voltage violations as measured. |
| 5 | Each new device class matches the centralized solve before ADMM use | VERIFIED | Each device file has a crossval testitem ("centralized vs ADMM crossval", measured bands pinned) in test_electricvehicle/heatpump/smartinverterpv; `test_flex_population.jl` ("flex EV population solves through solve_welfare and solve_admm", welfare band 3x measured max over 6 seeds = 1.2e-4). All ran and passed in the full suite. |

**Score:** 5/5 truths verified.

## Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| src/devices/CapabilityTraits.jl, AbstractDevice.jl | VERIFIED | Substantive, wired into DsoOpt/welfare_solve/admm_state |
| src/devices/ElectricVehicle.jl, HeatPump.jl, SmartInverterPV.jl | VERIFIED | Exported (test_exports), contribute! contract honored, included before Aggregator |
| src/models/complementarity_ev.jl | VERIFIED | Wired in welfare_solve and AgrOpt consolidation |
| src/experiments/materialize.jl (`flex_devices` opt-in) | VERIFIED | Byte-identity fence: full-field FNV digests for `:default` and `:case_a_784` computed at pre-phase commit 0fe0777 and still match |
| scripts/socp_highpv_remeasure.jl, results CSV, literate page | VERIFIED | CSV 30 rows, honest about refusals |

## Policy checks

- Goldens/gates not re-pinned or loosened: no golden or existing-device file changed since 0fe0777; new tolerances are new constants (TAU_EV_ADMM) rather than relaxations of existing ones.
- Tolerances measured, not picked: EV crossval/welfare bands are 3x measured maxima (WR-03, WR-06).
- Refused certificates reported honestly: yes (CSV `verdict`, `detail`, `gap_source`; docs refused fraction).

## Classification of known items

| Item | Classification | Rationale |
|------|----------------|-----------|
| WR-01 wrap-session EV semantics | Human-verification item | Documented in `ElectricVehicle.jl` header, docs, and pinned by a test; the true overnight cyclic-SOC model is deferred. Research decision whether it is needed before citing flex-population EV results. Not a goal-failing gap: roadmap criteria do not require it. |
| IN-01 TAU_EV_ADMM = 3.6e-3 (ADMM final consolidation only; centralized TAU_EV = 2e-7 unchanged) | Acceptable documented limitation | Measured from a heavy-tailed sample, applied only to the opt-in EV final check; centralized gate untouched. |
| IN-02 MPC flex guard unreachable via run_mpc | Acceptable | Scenario cannot carry flex_devices; guard is defensive and tested at helper level. |
| IN-03 Base.hash seeds in `_case_a_house_seed`/`sub_seed` | Acceptable (deferred) | Pre-existing, golden-pinned; the new flex seeding avoids Base.hash (WR-02). Fix would re-pin `:case_a_784` goldens, forbidden by policy. |
| 43-04 deviation: explicit OFF/CERTIFIED throws for aggregators with reactive decisions | Acceptable | Fail-loud by design (prevents silently dropped q); routing proof test asserts it; no guard loosened. Only affects new SmartInverterPV/HeatPump populations. |
| High-PV CSV 4 refused_battery rows | Acceptable, satisfies "re-measured" | Refusals are by the later battery certificate, with harvested cone gap (0.013-0.065, overall max ratio 0.0687 < 1); disclosed in the docs. Interpretation flagged as human item 2. |

## Anti-patterns

No blocker found. No TBD/FIXME/XXX gating issues observed in the touched files from the greps performed on key sources; review fixes (6 warnings) all applied (REVIEW-FIX iteration 2 re-review clean).

## Gaps Summary

None. All five success criteria are met by code and passing tests. Status is human_needed only because of the two research-judgment items listed in the frontmatter.

_Verified: 2026-11-02_
_Verifier: Claude (gsd-verifier)_


## Human Verification Outcome (2026-11-02)

The researcher accepted both human-verification items:
- **WR-01 wrap-session EV semantics:** accepted as a documented limitation. The overnight cyclic-SOC +
  trip-energy model is tracked as backlog todo
  `.planning/todos/pending/2026-11-02-ev-overnight-cyclic-soc-model.md`.
- **High-PV (pv 1.2) framing:** accepted. The cone certificate never refused. The 4/30 refusals are
  battery-complementarity refusals, reported as such.
