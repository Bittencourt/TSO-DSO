---
phase: 19
slug: 4q-bess-live-reactive-dual-ascent
status: approved
nyquist_compliant: true
wave_0_complete: false
created: 2026-08-07
---

# Phase 19 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib + TestItems/TestItemRunner |
| **Config file** | test/runtests.jl (entrypoint) |
| **Quick run command** | targeted `@testitem` runs via TestItemRunner filter (per-task `<automated>` commands in each plan) |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Estimated runtime** | ~minutes (full suite: 2358 pass / 1 known-fail / 3 broken baseline) |

---

## Sampling Rate

- **After every task commit:** Run the task's `<automated>` TestItemRunner-filtered command
- **After every plan wave:** Run full suite via `julia --project=. -e 'import Pkg; Pkg.test()'`
- **Before `/gsd:verify-work`:** Full suite must be green (modulo the known Aqua CairoMakie stale-deps drift)
- **Max feedback latency:** ~600 seconds (full suite; wave-gate and final-gate tasks only, never mid-task)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 19-01-01 | 01 | 1 | MESH-04, MESH-05 | golden-contamination | pre-change byte-identity baseline captured | full suite | `julia --project=. -e 'import Pkg; Pkg.test()'` | ✅ | ⬜ pending |
| 19-01-02 | 01 | 1 | MESH-04, MESH-05 | — | ReactiveMode enum + Bool back-compat | unit | TestItemRunner filter (test_reactive_mode.jl) | ❌ W0 | ⬜ pending |
| 19-02-01 | 02 | 2 | MESH-04 | wrong-price-integrity | cone + guards throw loudly | unit | TestItemRunner filter (test_fourquadbess.jl) | ❌ W0 | ⬜ pending |
| 19-02-02 | 02 | 2 | MESH-04 | — | q_inject contract + derivation note | unit | TestItemRunner filter (test_fourquadbess.jl) | ❌ W0 | ⬜ pending |
| 19-03-01 | 03 | 2 | MESH-05 | default-path-drift | :certified branch byte-identical | unit | TestItemRunner filter (test_admm_reactive.jl) | ✅ | ⬜ pending |
| 19-03-02 | 03 | 2 | MESH-05 | — | set_rho_q! parameter path | unit | TestItemRunner filter (test_admm_reactive.jl) | ✅ | ⬜ pending |
| 19-04-01 | 04 | 3 | MESH-04 | default-path-drift | additive :Rq, absent-means-zero | unit | TestItemRunner filter (test_aggregator.jl) | ✅ | ⬜ pending |
| 19-04-02 | 04 | 3 | MESH-04 | — | hasproperty duck-typing on q_inject | unit | TestItemRunner filter (test_aggregator.jl) | ✅ | ⬜ pending |
| 19-05-01 | 05 | 3 | MESH-04 | certificate-laundering | own measured WR-01 tolerance, throw-by-default | unit | TestItemRunner filter (test_fourquadbess.jl) | ❌ W0 | ⬜ pending |
| 19-05-02 | 05 | 3 | MESH-04 | — | report-kwarg escape hatch + violating-fixture control | unit | TestItemRunner filter (test_fourquadbess.jl) | ❌ W0 | ⬜ pending |
| 19-06-01 | 06 | 4 | MESH-05 | — | AgrOpt live qag path + μ price term | unit | TestItemRunner filter | ✅ | ⬜ pending |
| 19-06-02 | 06 | 4 | MESH-05 | default-path-drift | wave-gate full suite green | full suite | `julia --project=. -e 'import Pkg; Pkg.test()'` | ✅ | ⬜ pending |
| 19-07-01 | 07 | 5 | MESH-05 | false-convergence | single stacked joint (λ,μ) converged call (count == 1) | unit | TestItemRunner filter (test_admm_reactive.jl) | ✅ | ⬜ pending |
| 19-07-02 | 07 | 5 | MESH-05 | — | μ/q first-class results surface | unit | TestItemRunner filter (test_admm_reactive.jl) | ✅ | ⬜ pending |
| 19-08-01 | 08 | 6 | MESH-04, MESH-05 | measurement-before-golden | Phase19Fixtures + noise-floor-calibrated tolerances | integration | TestItemRunner filter (fixtures_phase19.jl) | ❌ W0 | ⬜ pending |
| 19-08-02 | 08 | 6 | MESH-05 | flaky-CI | IEEE-13 under bounded-retry quarantine | integration | TestItemRunner filter (test_ieee123_admm.jl) | ✅ | ⬜ pending |
| 19-08-03 | 08 | 6 | MESH-04, MESH-05 | default-path-drift | final byte-identity regression gate, full suite green | full suite | `julia --project=. -e 'import Pkg; Pkg.test()'` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Pre-Phase-19 byte-identity baseline captured BEFORE any src/ change (plan 19-01 Task 1 — gate-then-golden ordering)
- [ ] `test/test_reactive_mode.jl` — stubs for the 3-state mode (plan 19-01)
- [ ] `test/test_fourquadbess.jl` — device + certificate test items (plans 19-02/19-05)
- [ ] `test/fixtures_phase19.jl` — `Phase19Fixtures` module with 4Q aggregator wiring (plan 19-08)
- [ ] Solver-noise-floor calibration on the chosen fixture before any tolerance is pinned (plan 19-08 — measurement-before-golden)

---

## Manual-Only Verifications

*None — all phase behaviors (device cone, complementarity certificate, μ-ascent convergence, byte-identity) have automated verification. IEEE-13 supporting evidence runs under the existing bounded-retry quarantine.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (17/17 tasks carry concrete `<automated>` commands)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (100% automated coverage)
- [x] Wave 0 covers all MISSING references (new test files created by their owning plans)
- [x] No watch-mode flags
- [x] Feedback latency < 600s (full suite reserved for wave-gate/final-gate tasks)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-08-07 (plan-checker pass: 0 blockers, 2 doc-hygiene warnings — both fixed)
