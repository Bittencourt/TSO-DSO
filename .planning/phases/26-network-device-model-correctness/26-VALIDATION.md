---
phase: 26
slug: network-device-model-correctness
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-28
---

# Phase 26 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` stdlib + TestItems/TestItemRunner (`@testitem`, discovered by `test/runtests.jl`) |
| **Config file** | `test/runtests.jl` |
| **Quick run command** | Direct script reproducing the touched `@testitem` body: `julia --project=. <scratch>/check_<task>.jl` (NEVER TestItemRunner under `--project=.`) |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` — launched DETACHED (`nohup setsid bash -c "... > LOG 2>&1; echo $? > DONE" </dev/null &`), poll marker |
| **Estimated runtime** | quick: ~60–180 s (precompile-dominated); full: ~16–23 min |

---

## Sampling Rate

- **After every task commit:** direct-script reproduction of touched `@testitem`(s)
- **After every plan wave:** full suite (detached), log start timestamp checked against HEAD
- **Before `/gsd:verify-work`:** full suite green (only known, pre-existing flakes / the 2 known-false Aqua failures discounted, with evidence)
- **Max feedback latency:** ~180 s per task

---

## Per-Task Verification Map

| Requirement | Behavior | Test Type | Automated Command | File Exists | Status |
|-------------|----------|-----------|-------------------|-------------|--------|
| FIX-01 | 3-bus heavy-load/low-V: Ipopt AC-feasible, default SOCP feasible, thesis-literal variant infeasible | integration | direct script of new `test/test_exactness_verdict.jl` items | ❌ W0 | ⬜ pending |
| FIX-02 | `v̂ ≥ v` at solution; docstring load-bearing bound == actual binding constraint | unit | direct script of `test/test_convex_branch_flow.jl` + flipped `test/test_restricted_branch_flow.jl` spot-check | ⚠️ edit | ⬜ pending |
| FIX-03 | PV back-feed: receiving-end limit active (nonzero dual), sending-end slack | integration | direct script of new back-feed `@testitem` | ❌ W0 | ⬜ pending |
| FIX-04 | soc[1:T+1]; soc0=Emin + hour-T discharge incentive → zero discharge; MPC terminal on soc[H+1] | unit | direct script of `test/test_pvbattery.jl`, `test/test_fourquadbess.jl`, `test/test_mpc_window.jl` | ⚠️ edit | ⬜ pending |
| FIX-05 | per-device `:Rq` contribution == `p·tanφ` (interruptible, thermostatic, deferrable) | unit | direct script of `test/test_aggregator.jl` / device test files | ⚠️ edit + new | ⬜ pending |
| SC-6 | every moved golden: old→new + cause comment; SUMMARY table; full suite green | process | full-suite before/after diff | n/a | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Per-Task Verification Map — Gap-Closure Wave (revision: Plans 26-09..26-20, 26-08 revised)

Added by the post-merge triage/gap-closure revision (`26-POSTMERGE-TRIAGE.md`,
`26-CONTEXT.md`'s PM-01..08 decisions). Each row's "Automated Command" is the plan's own
`<verify>` — a real `julia --project=.` script (inline or a committed
`.planning/phases/26-network-device-model-correctness/26-NN-repro-*.jl` file), never a
placeholder — per the TestItemRunner-under-`--project=.` trap.

| Plan | Requirement(s) | Behavior | Automated Command | Status |
|------|----------------|----------|--------------------|--------|
| 26-09 | FIX-03 | `build_stochastic_welfare` unregister-list fix (`:Prev`/`:Qrev`/`:smax_rev`) + `test_run_stochastic.jl:104` welfare_gap re-pin | direct script of `build_stochastic_welfare` (S=2) + the `:104` measurement | ⬜ pending |
| 26-10 | FIX-03, FIX-04 | `decompose_dlmp` reads the `:smax_rev` receiving-end dual; D-26-01 near-lossless `tol_gap` calibration | direct script of `test_pricing_dlmp.jl:128`/`:22`/`:221` | ⬜ pending |
| 26-11 | FIX-04 | `run_mpc`'s `soc_da[t+H]` terminal retarget; `mpc_step` guard re-scoped to Thermostatic only | direct script of `run_mpc` + `26-11-repro-mpc-terminal.jl` | ⬜ pending |
| 26-12 | FIX-05 | `reactive_consensus` smart default (LIVE when flexible loads present) + WR-04 guard widened to `is_flexible_load` | direct script of `build_dso_opt`/`solve_admm` + `test_admm.jl:121` | ⬜ pending |
| 26-13 | FIX-05 | `mesh_aggregators()` φ=1.0 pin restoring MESH-02/03 intent; exactness-loss finding documented | direct script of `test_mesh_flow.jl`/`test_mesh_angle_certificate.jl` on both impedance profiles | ⬜ pending |
| 26-14 | FIX-04 | `assert_battery_complementarity!` `on_violation` mode (`:warn` for AC/NLP only); App. C eta<1 finding recorded in `26-FINDINGS.md` | direct script of the EXACT-04 AC solve (`test_ac_oracle.jl:182`) | ⬜ pending |
| 26-15 | FIX-03 | `ACPowerFlow` gains the additive `:smax_rev` receiving-end limit (PM-07) | direct script confirming `:smax_rev` registered + back-feed regression (receiving dual dominates sending) | ⬜ pending |
| 26-16 | FIX-03, FIX-04 | Phase6 two-bus/`test_planning_oracle.jl` `tol_gap` calibration; `test_admm_reactive.jl` mu_q tolerance re-pin (depends on 26-12) | direct script of the calibrated solves + `26-16-repro-mu-q-sweep.jl` (asserts against the atol parsed live from the edited file) | ⬜ pending |
| 26-17 | FIX-03, FIX-04, FIX-05 | `test_ieee13.jl`/`test_pricing_fit.jl`/`test_pricing_welfare.jl` golden re-pins (PM-06); `:66` near-lossless `tol_gap` calibration | direct script + `26-17-repro-fit-ratio.jl` + `26-17-repro-pricing-welfare.jl` (both parse the pinned literals live and fail on a wrong re-pin) | ⬜ pending |
| 26-18 | FIX-01, FIX-02 | Gan-Low default relabelled restriction-not-relaxation (PM-01); escalation-ladder + AC-infeasibility tests re-forced with `thesis_literal=true`; finding recorded in `26-FINDINGS.md` | grep sweep for "genuine relaxation" + direct script of the re-forced `test_mpc_loop.jl`/`test_restricted_branch_flow.jl` items | ⬜ pending |
| 26-19 | FIX-01, FIX-02, FIX-03, FIX-04, FIX-05 | `test_acceptance.jl` golden constants cross-referenced to Plan 26-17's re-pin; IEEE-123 `tol_gap` calibration (4 testitems) | direct script of `test_acceptance.jl`/`test_ieee123_admm.jl`/`test_thesis_repro.jl` at the calibrated `tol_gap` | ⬜ pending |
| 26-20 | FIX-05 | ADMM knife-edge canary (`test_admm_knifeedge_canary.jl`) re-measured and re-pinned strictly after Plan 26-12 lands | direct script of `run_scenario` reproducing the canary's `r.iters`/`r.welfare` | ⬜ pending |
| 26-08 (revised) | FIX-01, FIX-02, FIX-03, FIX-04, FIX-05 | Cross-phase golden-move audit (`26-GOLDEN-AUDIT.md`) covering BOTH waves; final full-suite diff vs `26-BASELINE.md`; PM-01/02/04 + v2.1 finding-consistency check across `26-FINDINGS.md` | final detached full-suite log diff; `26-GOLDEN-AUDIT.md` row-count/verdict check | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky — `nyquist_compliant` stays `false` and
Approval stays `pending` until Plan 26-08 closes the gap-closure wave and the checker re-runs.*

---

## Wave 0 Requirements

- [ ] Baseline full-suite run on current HEAD (pass/fail/error counts recorded) before any fix
- [ ] `test/test_exactness_verdict.jl` — FIX-01 3-bus regression (fixture tuned empirically)
- [ ] PV back-feed fixture for FIX-03
- [ ] Single-member `Aggregator` fixture wrapping converted (Variant-2) `Interruptible` for FIX-05
- [ ] `git grep -n "soc\[H\]\|soc\[T\]\|length(soc)\|soc\[end\]"` sweep over `src/` + `test/` to enumerate FIX-04 index-shift touch points

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Verdict docs page accurately quotes thesis 3.43/3.45 and Gan–Low 2015 | FIX-01 | Source fidelity to a PDF | Compare quoted equations against `docs/references/86. Tesis…pdf` pages cited |
| Golden-move audit (no silent re-pin) | SC-6 | Judgment on stated cause | Review SUMMARY golden table vs `git diff` of test files |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 180s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
