---
phase: 1
slug: plumbing-solver-abstraction
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-18
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `Test` (stdlib) + TestItems/TestItemRunner |
| **Config file** | `Project.toml` (`[extras]`/`[targets]`), `test/runtests.jl` — Wave 0 installs |
| **Quick run command** | `julia --project=. -e 'using TestItemRunner; @run_package_tests'` |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Estimated runtime** | ~60 seconds (first run includes precompilation) |

---

## Sampling Rate

- **After every task commit:** Run the quick run command (single `@testitem` filter where possible)
- **After every plan wave:** Run the full suite command
- **Before `/gsd:verify-work`:** Full suite must be green on Julia 1.11
- **Max feedback latency:** 90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 0 | INFRA-01 | — | N/A | integration | `julia --project=. -e 'import Pkg; Pkg.instantiate(); Pkg.status()'` | ❌ W0 | ⬜ pending |
| 1-01-02 | 01 | 1 | DATA-01, DATA-02 | — | Per-unit convert-once; magnitude assertions | unit | `@run_package_tests filter=ti->occursin("perunit", ti.name)` | ❌ W0 | ⬜ pending |
| 1-01-03 | 01 | 1 | PF-01 | — | Radial feeder validation; non-tree raises | unit | `@run_package_tests filter=ti->occursin("feeder", ti.name)` | ❌ W0 | ⬜ pending |
| 1-01-04 | 01 | 1 | INFRA-02 | — | Solver factory; no model names a solver | unit | `@run_package_tests filter=ti->occursin("solver", ti.name)` | ❌ W0 | ⬜ pending |
| 1-01-05 | 01 | 1 | INFRA-05 | — | ModelContext + residual registry seam | unit | `@run_package_tests filter=ti->occursin("context", ti.name)` | ❌ W0 | ⬜ pending |
| 1-01-06 | 01 | 2 | INFRA-03 | — | assert OPTIMAL / is_solved_and_feasible; fail loudly | unit | `@run_package_tests filter=ti->occursin("status", ti.name)` | ❌ W0 | ⬜ pending |
| 1-01-07 | 01 | 2 | INFRA-02, INFRA-03 | — | Toy DC single-node solve returns objective | integration | `@run_package_tests filter=ti->occursin("toy", ti.name)` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/runtests.jl` — TestItemRunner entrypoint (`@run_package_tests`)
- [ ] `Project.toml` `[extras]`/`[targets]` wiring for `Test`, `TestItems`, `TestItemRunner`
- [ ] Per-seam `@testitem` stubs: perunit, feeder, solver factory, model context, status discipline, toy DC solve
- [ ] `.github/workflows/CI.yml` — Julia matrix 1.10/1.11(/1.12) via `julia-actions`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Clean-checkout resolution on Julia 1.10 LTS | INFRA-01 | 1.10 LTS not installed locally (only 1.11/1.12); needs `juliaup add 1.10` or CI | Run CI matrix, or `juliaup add 1.10 && julia +1.10 --project=. -e 'import Pkg; Pkg.instantiate()'` |

*Automated verification covers all other phase behaviors.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
