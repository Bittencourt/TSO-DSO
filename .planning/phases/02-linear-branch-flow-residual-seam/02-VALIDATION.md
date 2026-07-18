---
phase: 2
slug: linear-branch-flow-residual-seam
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-18
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `Test` (stdlib) + TestItems/TestItemRunner |
| **Config file** | `test/Project.toml` + `test/runtests.jl` (established in Phase 1) |
| **Quick run command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (or per-seam `@run_package_tests filter=...`) |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Estimated runtime** | ~60–90 seconds |

---

## Sampling Rate

- **After every task commit:** Run the relevant per-seam `@testitem` filter
- **After every plan wave:** Run the full suite
- **Before verify:** Full suite green on Julia 1.11
- **Max feedback latency:** 90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Requirement | Secure Behavior | Test Type | Automated Command | Status |
|---------|------|-------------|-----------------|-----------|-------------------|--------|
| seam-ext | — | PF-02 | ModelContext extended: per-bus/time :Rp/:Rq residuals + add_to_objective! QuadExpr accumulator | unit | `@run_package_tests filter=ti->occursin("context", ti.name)` | ⬜ pending |
| dc-pf | — | PF-02 | DC formulation contributes :Rp only, dispatch not branching | unit | `@run_package_tests filter=ti->occursin("powerflow", ti.name)` | ⬜ pending |
| lindistflow | — | PF-02 | LinDistFlow contributes :Rp+:Rq+voltage; traced to thesis 3.31–3.33/3.43 | unit | `@run_package_tests filter=ti->occursin("lindistflow", ti.name)` | ⬜ pending |
| conformance | — | PF-02 | DC↔LinDistFlow swap needs zero device/assembly change (interface-conformance) | unit | `@run_package_tests filter=ti->occursin("conformance", ti.name)` | ⬜ pending |
| device | — | DEV-03 | Interruptible/elastic load: vars + concave-quad utility + signed injection, NO network reference | unit | `@run_package_tests filter=ti->occursin("device", ti.name)` | ⬜ pending |
| centralized | — | PF-02, DEV-03 | Centralized linear solve closes balance, exposes dual(nodal_balance), gated OPTIMAL | integration | `@run_package_tests filter=ti->occursin("linear", ti.name)` | ⬜ pending |
| first-price | — | PF-02, DEV-03 | 2-bus loss-less LinDistFlow: analytic DADP=λ₀, p*=(a−λ₀)/b (exact assertion, no magic number) | integration | `@run_package_tests filter=ti->occursin("price", ti.name)` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] New RED `@testitem` stubs for: extended context (Rp/Rq/objective), DC pf, LinDistFlow pf, interface conformance, device, centralized solve, analytic first-price fixture
- [ ] Small radial test feeder fixture (2–3 bus) for the conformance + dual/price tests

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Cross-version resolve (1.10 LTS) | (carried from INFRA-01) | 1.10 LTS run best on CI | CI matrix leg / `julia +1.10` local run |

*Automated verification covers all Phase 2 modeling behaviors.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
