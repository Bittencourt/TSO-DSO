---
phase: 3
slug: prosumer-device-library-social-welfare-solve
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-18
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `Test` (stdlib) + TestItems/TestItemRunner |
| **Config file** | `test/Project.toml` + `test/runtests.jl` |
| **Quick run command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (per-seam via `@run_package_tests filter=...`) |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Estimated runtime** | ~90 seconds |

---

## Sampling Rate

- **After every task commit:** relevant per-seam `@testitem` filter
- **After every plan wave:** full suite
- **Before verify:** full suite green
- **Max feedback latency:** 90 seconds

---

## Per-Task Verification Map

| Task | Requirement | Secure Behavior | Test Type | Command (filter substring) | Status |
|------|-------------|-----------------|-----------|----------------------------|--------|
| StableRNGs dep + profiles | DATA-04 | Seeded first-order Markov demand+PV; same seed → identical profiles (reproducible) | unit | `occursin("profile", ti.name)` | ⬜ pending |
| thermostatic | DEV-01 | Temp-linear-in-power recursion + comfort band + concave utility; network-agnostic | unit | `occursin("thermostatic", ti.name)` | ⬜ pending |
| deferrable | DEV-02 | Energy-within-window coupling + concave utility; network-agnostic | unit | `occursin("deferrable", ti.name)` | ⬜ pending |
| pv_battery | DEV-04 | SOC dynamics, PV-limited charge, NO binaries; post-solve p_ch·p_dch≈0 asserted (App. C) | unit | `occursin("battery", ti.name)` | ⬜ pending |
| aggregator | DEV-05 | Rolls devices into nodal net P/Q + total utility; aggregator-as-writer; devices stay network-agnostic | unit | `occursin("aggregator", ti.name)` | ⬜ pending |
| welfare_solve | OPT-01 | GLB-CVX = Σ util − MEM purchase; q_import root source added; global optimum; OPTIMAL-gated | integration | `occursin("welfare", ti.name)` | ⬜ pending |
| complementarity | DEV-04, OPT-01 | At the welfare optimum, every battery satisfies p_ch·p_dch < τ (numeric verification) | integration | `occursin("welfare", ti.name)` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `StableRNGs` added to Project.toml `[deps]` with `[compat]`, Manifest(s) re-resolved on 1.10/1.11/1.12
- [ ] RED `@testitem` stubs: profiles, thermostatic, deferrable, battery, aggregator, welfare_solve (+ complementarity assertion)
- [ ] Multi-period (T=24) test fixture + seeded profile fixture

---

## Manual-Only Verifications

*All Phase 3 behaviors have automated verification (including the numeric battery-complementarity check).*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity maintained
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true`

**Approval:** pending
