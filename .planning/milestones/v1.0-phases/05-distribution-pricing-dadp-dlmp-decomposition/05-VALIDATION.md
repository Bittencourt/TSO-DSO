---
phase: 5
slug: distribution-pricing-dadp-dlmp-decomposition
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-18
---

# Phase 5 — Validation Strategy

> Post-processing over the exactness-gated Phase-4 duals. The DLMP 4-way decomposition is a KKT
> derivation (thesis gives it only qualitatively) whose safety net is the sum-to-nodal-price assertion.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `Test` (stdlib) + TestItems/TestItemRunner |
| **Config file** | `test/Project.toml` + `test/runtests.jl` |
| **Quick run command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (per-seam `@run_package_tests filter=...`) |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Estimated runtime** | ~2 minutes |

---

## Sampling Rate

- After every task commit: relevant per-seam `@testitem` filter
- After every plan wave: full suite
- Before verify: full suite green
- Max feedback latency: ~120s

---

## Per-Task Verification Map

| Task | Requirement | Secure Behavior | Test Type | Command (filter substring) | Status |
|------|-------------|-----------------|-----------|----------------------------|--------|
| register constraint handles | PRICE-02 | ConvexBranchFlow registers :vdrop/:smax so their duals are recoverable (additive; no Phase-4 regression) | unit | `occursin("socp", ti.name) \|\| occursin("conform", ti.name)` | ⬜ pending |
| extract DADP | PRICE-01 | extract_dlmp(ctx) → dual(balance_p[node,t]) per node/hour; sign verified vs hand-solved 2-bus | unit | `occursin("dlmp", ti.name)` | ⬜ pending |
| decompose DLMP | PRICE-02 | energy+loss+congestion+voltage components SUM to nodal price (correct sign) — hard sum assertion | unit+integration | `occursin("dlmp", ti.name)` | ⬜ pending |
| welfare accounting | PRICE-03 | social/DSO/prosumer surplus; social = prosumer+DSO = GLB-CVX objective (transfer cancels); FIT baseline; +25% as computed ratio + thesis cross-check | integration | `occursin("welfare", ti.name) \|\| occursin("surplus", ti.name)` | ⬜ pending |
| FIT baseline | PRICE-03 | FIT-OPT counterfactual (no battery) solves; used as the welfare baseline | integration | `occursin("fit", ti.name)` | ⬜ pending |
| economic direction | PRICE-04 | DADP < λ₀ at PV glut; DADP > λ₀ at congestion (reuse high-PV + ground fixtures) | integration | `occursin("econ", ti.name) \|\| occursin("direction", ti.name)` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] RED `@testitem` stubs: dlmp extraction+decomposition, welfare/surplus, fit baseline, economic-direction
- [ ] 2-bus hand-solved DADP sign fixture; PV-glut + congestion scenario fixtures (reuse Phase-4)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Exact +25% / $1457→$1819 absolute match | PRICE-03 | Thesis absolute welfare is figure-bound (Phase-4 caveat); primary anchor is the computed ratio (~1.25) with the thesis ratio as a non-failing cross-check | Compare computed social-welfare ratio to ~1.25; document gap in SUMMARY |

*The DADP sign, the decomposition sum-to-price assertion, the surplus identity, and the economic-direction checks are fully automated.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity maintained
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] `nyquist_compliant: true`

**Approval:** pending
