---
phase: 34
slug: admm-decomposition-meshed-reactive-status-exception-policy
status: complete
nyquist_compliant: true
wave_0_complete: true
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
| ARCH-05 | default path bit-identical (iters 56, welfare -4823.66604824162) | canary | `test_admm_knifeedge_canary.jl` | ✅ | ✅ green |
| ARCH-05 | all ADMM goldens unchanged | integration | admm/admm_reactive/admm_adaptive/admm_dualresid/admm_timeout/dso/agr/ieee123_admm | ✅ | ✅ green |
| ARCH-05 | phase functions + hook dispatch; no `mode == LIVE` outside hooks | unit + audit | `test_admm_phases.jl` | ✅ | ✅ green |
| ARCH-05 | `admm_supported` matrix; LinDist NaN maxgap; Restricted/LinDist vs centralized | integration | `test_admm_generic_pf.jl` | ✅ | ✅ green |
| ARCH-06 | meshed ADMM LIVE vs centralized (measured tolerances); angle-certificate agreement | integration | `test_admm_meshed.jl` | ✅ | ✅ green |
| ARCH-08 | typed exceptions; byte-identical messages | unit | `test_tsodso_errors.jl` | ✅ | ✅ green |
| ARCH-08 | status vocabulary per entry point; DC+reactive pin | integration | `test_status_policy.jl` | ✅ | ✅ green |
| ARCH-08 | retry ladder retries on `SolveFailedError` | unit | `test_planning_retry.jl` | ✅ | ✅ green |
| ARCH-09 | MethodError/BoundsError propagate from mpc tiers; solver/cert failures still ledgered | unit | `test_mpc_loop.jl` | ✅ | ✅ green |
| ARCH-09 | stochastic skip-and-report narrowed | unit | `test_run_stochastic.jl` / `test_stochastic_oos_harness.jl` | ✅ | ✅ green |
| all | docs build; Aqua | quality | docs build; full suite | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `test/test_tsodso_errors.jl`
- [x] `test/test_status_policy.jl`
- [x] `test/test_admm_phases.jl`
- [x] `test/test_admm_generic_pf.jl`
- [x] `test/test_admm_meshed.jl` + φ=0.95 heterogeneous-diamond fixture helper

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 240s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** certified 2026-10-04 — full suite 32128/0/0/5 at 45bb659 (log start 10:50:14 > commit 10:49:37); docs build exit 0; knife-edge canary iters=56, welfare=-4823.66604824162 (never re-pinned)
