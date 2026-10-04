---
phase: 34
slug: admm-decomposition-meshed-reactive-status-exception-policy
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-10-04
---

# Phase 34 — Validation Strategy

> Source: 34-RESEARCH.md "Validation Architecture".

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems/TestItemRunner (`@testitem`), Aqua |
| **Config file** | `test/runtests.jl`, `test/Project.toml` |
| **Quick run command** | `JULIA_LOAD_PATH="@:.:test:@stdlib" julia --project=. -e 'using TestItemRunner; TestItemRunner.run_tests(joinpath(pwd(),"test"); filter = ti -> endswith(ti.filename, "test_<name>.jl"))'` |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` — DETACHED, owned by the orchestrator |
| **Estimated runtime** | ~25–240 s per targeted file; full suite ~35–45 min |

---

## Sampling Rate

- **After every task commit:** targeted test file(s) for the touched seam
- **After every plan:** all files for that wave + `test_admm_knifeedge_canary.jl` (canary NEVER re-pinned)
- **Before `/gsd:verify-work`:** full suite ≥ 31915 passes, 0 failed / 0 errored / 5 broken; docs build exit 0
- **Max feedback latency:** ~240 seconds

---

## Per-Task Verification Map

| Req | Behavior | Test Type | Automated Command | File Exists | Status |
|-----|----------|-----------|-------------------|-------------|--------|
| ARCH-05 | default path bit-identical (iters 56, welfare -4823.66604824162) | canary | `test_admm_knifeedge_canary.jl` | ✅ | ⬜ pending |
| ARCH-05 | all ADMM goldens unchanged | integration | admm/admm_reactive/admm_adaptive/admm_dualresid/admm_timeout/dso/agr/ieee123_admm | ✅ | ⬜ pending |
| ARCH-05 | phase functions + hook dispatch; no `mode == LIVE` outside hooks | unit + audit | `test_admm_phases.jl` | ❌ W0 | ⬜ pending |
| ARCH-05 | `admm_supported` matrix; LinDist NaN maxgap; Restricted/LinDist vs centralized | integration | `test_admm_generic_pf.jl` | ❌ W0 | ⬜ pending |
| ARCH-06 | meshed ADMM LIVE vs centralized (measured tolerances); angle-certificate agreement | integration | `test_admm_meshed.jl` | ❌ W0 | ⬜ pending |
| ARCH-08 | typed exceptions; byte-identical messages | unit | `test_tsodso_errors.jl` | ❌ W0 | ⬜ pending |
| ARCH-08 | status vocabulary per entry point; DC+reactive pin | integration | `test_status_policy.jl` | ❌ W0 | ⬜ pending |
| ARCH-08 | retry ladder retries on `SolveFailedError` | unit | `test_planning_retry.jl` | ✅ edit | ⬜ pending |
| ARCH-09 | MethodError/BoundsError propagate from mpc tiers; solver/cert failures still ledgered | unit | `test_mpc_loop.jl` | ✅ edit | ⬜ pending |
| ARCH-09 | stochastic skip-and-report narrowed | unit | `test_run_stochastic.jl` / `test_stochastic_oos_harness.jl` | ✅ edit | ⬜ pending |
| all | docs build; Aqua | quality | docs build; full suite | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_tsodso_errors.jl`
- [ ] `test/test_status_policy.jl`
- [ ] `test/test_admm_phases.jl`
- [ ] `test/test_admm_generic_pf.jl`
- [ ] `test/test_admm_meshed.jl` + φ=0.95 heterogeneous-diamond fixture helper

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 240s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
