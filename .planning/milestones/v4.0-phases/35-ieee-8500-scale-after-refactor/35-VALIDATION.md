---
phase: 35
slug: ieee-8500-scale-after-refactor
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-10-04
---

# Phase 35 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems/TestItemRunner 1.1.5 (`@testitem`) |
| **Config file** | `test/runtests.jl`, `test/Project.toml` |
| **Quick run command** | Runner FILE (never `julia -e`), absolute paths: `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib" julia -t2 <runner.jl> $PWD` with `TestItemRunner.run_tests(joinpath(ARGS[1],"test"); filter = ti -> :exact in ti.tags)` |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (background, detached; 2 known-false Aqua items) |
| **Harness golden** | `julia --project=. test/test_benchmark_ieee8500.jl` |
| **Estimated runtime** | quick < 60 s; `:admm` filter ~8 min; full ~60 min |

---

## Sampling Rate

- **After every task commit:** new `:exact`/default-floor items + `test/test_benchmark_ieee8500.jl` when the harness changes
- **After every plan wave:** runner filter `:admm` (~8 min) incl. knife-edge canary (iters = 56, welfare = -4823.66604824162 — NEVER re-pin)
- **Before `/gsd:verify-work`:** full suite green except the 2 known Aqua items
- **Max feedback latency:** 60 s (quick), 8 min (wave)
- Never run two suites concurrently, and never run a suite while an IEEE-8500 measurement is in flight.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 35-01-xx | 01 | 1 | ARCH-10 SC1 | — | N/A | unit (assert-level, smax≈90 hybrid vs flat 1e-6) | runner filter `:exact` | ❌ W0 | ⬜ pending |
| 35-01-xx | 01 | 1 | ARCH-10 SC1 | — | N/A | integration (2-bus default == `nothing`; tiny atol → `CertificateError`) | runner filter `:exact` | ❌ W0 | ⬜ pending |
| 35-01-xx | 01 | 1 | ARCH-10 SC1 | — | N/A | unit (near-zero-r negative throws under default) | runner filter `:exact` | ❌ W0 | ⬜ pending |
| 35-01-xx | 01 | 1 | ARCH-10 SC1 | — | N/A | regression (ADMM goldens + canary) | runner filter `:admm` | ✅ | ⬜ pending |
| 35-02-xx | 02 | 1–2 | ARCH-10 SC2 | — | N/A | script golden (flags, row schema, typed exceptions) | `julia --project=. test/test_benchmark_ieee8500.jl` | ✅ extend | ⬜ pending |
| 35-0x-xx | — | 2–3 | ARCH-10 SC1/SC2 | — | N/A | measurement (manual, one point per process) | `scripts/run_ieee8500_point.sh` | ❌ W0 | ⬜ pending |
| 35-0x-xx | — | 3 | ARCH-10 docs | — | N/A | docs build | docs env literate run | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Default-floor test items (assert-level hybrid acceptance, 2-bus plumbing, near-zero-r negative)
- [ ] `scripts/run_ieee8500_point.sh` (per-process `/usr/bin/time -v`, `journalctl -k` + `journalctl -u earlyoom` capture)
- [ ] Harness flags `--admm-only`, `--admm-atol` + golden extension

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| IEEE-8500 headline point(s) measured / wall re-characterized | ARCH-10 SC2 | multi-GiB, OOM risk, not CI-safe | quiet machine; one point per process via wrapper; record row + peak RSS + OOM evidence |
| IEEE-8500 bypass diagnostic proves the gate refusal is genuine | ARCH-10 SC1 | requires the 8500 solve | `atol_exact=Inf` run, per-branch hybrid ratios from `res.dso_ctx` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s (quick)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
