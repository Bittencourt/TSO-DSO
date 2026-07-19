---
phase: 6
slug: admm-decomposition-core
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-19
---

# Phase 6 — Validation Strategy

> The load-bearing correctness gate is the centralized cross-validation: ADMM welfare AND duals must
> match the Phase-4 SOCP monolithic optimum on every small fixture (the false-convergence net).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `Test` (stdlib) + TestItems/TestItemRunner |
| **Config file** | `test/Project.toml` + `test/runtests.jl` |
| **Quick run command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (per-seam `@run_package_tests filter=...`) |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Estimated runtime** | ~3 minutes (ADMM iterates SOCP subproblems) |

---

## Sampling Rate

- After every task commit: relevant per-seam `@testitem` filter
- After every plan wave: full suite
- Before verify: full suite green
- Max feedback latency: ~180s

---

## Per-Task Verification Map

| Task | Requirement | Secure Behavior | Test Type | Command (filter substring) | Status |
|------|-------------|-----------------|-----------|----------------------------|--------|
| coupling seam | ADMM-01 | explicit pag_j[t] coupling var + augmented-Lagrangian coupling closure reusing device/PF builders; NO λ-as-Parameter bilinear | unit | `occursin("admm", ti.name)` | ⬜ pending |
| AGR-OPT subproblem | ADMM-01 | per-node aggregator/device QP reusing contribute!; objective = util − λ·pag − (ρ/2)‖pag−z‖² | unit | `occursin("agr", ti.name) \|\| occursin("admm", ti.name)` | ⬜ pending |
| DSO-OPT subproblem | ADMM-01 | per-hour SOCP network reusing ConvexBranchFlow.contribute!; PF-04 exactness gated | unit | `occursin("dso", ti.name) \|\| occursin("admm", ti.name)` | ⬜ pending |
| build-once re-solve | ADMM-03 | subproblems built ONCE; loop updates via set_objective_coefficient / Parameter penalty target; NO rebuild | unit | `occursin("resolve", ti.name) \|\| occursin("admm", ti.name)` | ⬜ pending |
| dual-ascent loop | ADMM-01 | λ_j ← λ_j + ρ·R_{p,j}; primal-residual stopping + maxiter cap; residual struct | integration | `occursin("admm", ti.name)` | ⬜ pending |
| cross-validation 2-bus | ADMM-04 | ADMM welfare ≈ centralized objective + λ_j ≈ extract_dlmp(centralized) on 2-bus (dual sign pinned here) | integration | `occursin("crossval", ti.name) \|\| occursin("admm", ti.name)` | ⬜ pending |
| cross-validation IEEE-13 | ADMM-04 | ADMM ≈ centralized welfare+duals on IEEE-13 within tolerance; DSO-OPT exact | integration | `occursin("crossval", ti.name) \|\| occursin("ieee13", ti.name)` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] RED `@testitem` stubs: coupling seam, AGR-OPT, DSO-OPT, build-once re-solve, dual-ascent loop, cross-validation (2-bus + IEEE-13)
- [ ] 2-bus fixture (dual-sign anchor) + IEEE-13 fixture reused from Phase 4/5
- [ ] a "no per-iteration rebuild" assertion (e.g. model object identity / build-count instrumentation)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| ρ/ε tuning per fixture | ADMM-01 | Empirical fixed-ρ sweep on the 2-bus during implementation (adaptive-ρ is Phase 7) | Pick ρ that converges within maxiter; document |

*The cross-validation (ADMM ≈ centralized welfare+duals) and the build-once/no-rebuild assertion are fully automated.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity maintained
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] `nyquist_compliant: true`

**Approval:** pending
