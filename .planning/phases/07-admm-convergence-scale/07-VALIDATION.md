---
phase: 7
slug: admm-convergence-scale
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-19
---

# Phase 7 — Validation Strategy

> Hardens the Phase-6 ADMM: correct dual residual + per-unit-normalized adaptive ρ, plottable
> diagnostics, and the IEEE-123 scale case. The Phase-6 cross-validation (ADMM ≈ centralized) must
> still pass on 2-bus/IEEE-13; IEEE-123 converges in ~tens of iters with exactness holding.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `Test` (stdlib) + TestItems/TestItemRunner |
| **Config file** | `test/Project.toml` + `test/runtests.jl` |
| **Quick run command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (per-seam `@run_package_tests filter=...`) |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Estimated runtime** | ~4–6 minutes (IEEE-123 ADMM iterates SOCP subproblems; still headless/plot-free) |

---

## Sampling Rate

- After every task commit: relevant per-seam `@testitem` filter
- After every plan wave: full suite
- Before verify: full suite green
- Max feedback latency: ~360s

---

## Per-Task Verification Map

| Task | Requirement | Secure Behavior | Test Type | Command (filter substring) | Status |
|------|-------------|-----------------|-----------|----------------------------|--------|
| dual-residual fix | ADMM-02 | correct Boyd dual residual s=ρ·Δ(pag_dso) (z-block, not the Phase-6 ρ·Δa bug); primal+dual 2-norm per-unit stopping | unit | `occursin("dual", ti.name) \|\| occursin("admm", ti.name)` | ⬜ pending |
| adaptive ρ | ADMM-02 | residual-balancing ρ (Boyd §3.4.1) via set_objective_coefficient(m,x,x,ρ) quadratic-weight update — NO rebuild; scale-invariant | unit | `occursin("rho", ti.name) \|\| occursin("adaptive", ti.name)` | ⬜ pending |
| transit-node relax | ADMM-02 | build_dso_opt supports zero-injection transit nodes (decouple load_nodes from non-root buses); IEEE-13/2-bus unaffected | unit | `occursin("transit", ti.name) \|\| occursin("dso", ti.name)` | ⬜ pending |
| IEEE-123 fixture | ADMM-02 | thesis App. E feeder as radial per-unit Feeder (relabel + radialize; passes assert_radial + magnitude bands); SparseArrays | unit | `occursin("ieee123", ti.name)` | ⬜ pending |
| convergence regression | ADMM-02 | Phase-6 cross-validation still passes (2-bus/IEEE-13); IEEE-123 converges ~tens of iters, λ_j→DADP, PF-04 exact at convergence | integration | `occursin("crossval", ti.name) \|\| occursin("ieee123", ti.name)` | ⬜ pending |
| diagnostics ledger | ADMM-05 | AdmmResiduals carries primal/dual/ρ/price traces + iters; reported | unit | `occursin("diag", ti.name) \|\| occursin("resid", ti.name)` | ⬜ pending |
| Makie extension | ADMM-05 | TSODSOMakieExt weakdep: plot functions light up only when CairoMakie loaded; core solve + CI plot-free | unit | `occursin("plot", ti.name) \|\| occursin("makie", ti.name)` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `CairoMakie` added as `[weakdeps]` + `ext/TSODSOMakieExt.jl` wired; manifests re-resolved (1.10/1.11/1.12)
- [ ] RED `@testitem` stubs: dual-residual fix, adaptive ρ, transit-node relax, IEEE-123 fixture, convergence regression, diagnostics, plotting extension
- [ ] IEEE-123 radial per-unit fixture (thesis App. E)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| CairoMakie figure visual quality | ADMM-05 | Vector-figure aesthetics (residual/price convergence) are visual; the plot FUNCTIONS are unit-tested (return a Figure), the look is eyeballed | Load CairoMakie, call the plot fns, inspect the PDFs |
| IEEE-123 centralized cross-check (if monolithically solvable) | ADMM-02 | If the centralized SOCP is too large to solve monolithically on IEEE-123, the convergence-correctness check falls back to primal+dual→0 + PF-04 exactness + price sanity | Attempt centralized solve; if infeasible/too slow, use the residual+exactness convergence certificate |

*Adaptive-ρ convergence, the dual-residual correctness, the transit-node relax, and the exactness-at-convergence are fully automated.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity maintained
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] `nyquist_compliant: true`

**Approval:** pending
