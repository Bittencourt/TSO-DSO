---
phase: 39
slug: parallel-ready-admm-gating-measurements
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-10-24
---

# Phase 39 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + `TestItemRunner` (test/runtests.jl) |
| **Config file** | `test/Project.toml` (pinned test env) |
| **Quick run command** | `julia --project=. -e 'import Pkg; Pkg.test(test_args=["fast"])'` (NEVER `--project=test` @run_package_tests idiom) |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Estimated runtime** | ~10–25 min full suite; targeted files faster via `include`d TestItem filter |

---

## Sampling Rate

- **After every task commit:** Run targeted test file(s) for the touched seam (fast set)
- **After every plan wave:** Run full suite (`Pkg.test()`) — 0 fail / 0 error required; canary must hold
- **Before `/gsd-verify-work`:** Full suite must be green + knife-edge canary (`iters = 56`, `welfare = -4823.66604824162`) unchanged on default serial path
- **Max feedback latency:** ~25 min (full suite), seconds for targeted files

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 39-01-01 | 01 | 1 | PAR-01 | — | Spike documents bitwise equality verdict under `-t 4` (indirect + direct_model) | script + doc | `julia --project=. scripts/admm_clarabel_concurrency_spike.jl` | ❌ W0 | ⬜ pending |
| 39-0x-0x | 0x | x | PAR-02 | — | Threaded vs serial `==` on iterations/residuals/welfare/prices; serial canary unchanged | unit | targeted test file + full suite | ❌ W0 | ⬜ pending |
| 39-0x-0x | 0x | x | PAR-03 | — | Parallel task error surfaces as ORIGINAL type with same node attribution | unit | targeted test file | ❌ W0 | ⬜ pending |
| 39-0x-0x | 0x | x | PAR-04 | — | Provenance carries julia_threads/blas_threads; scenario `==`/hash/filename executor-blind | unit | targeted test file | ❌ W0 | ⬜ pending |
| 39-0x-0x | 0x | x | PAR-05 | — | Per-aggregator dispatch/utilities/import/prices present as additive keys | unit | targeted test file | ❌ W0 | ⬜ pending |
| 39-0x-0x | 0x | x | SCALE-06 | — | ~3.4 GiB growth attributed; CSV + doc note in results/ieee8500_benchmark/ | measurement script | staged RSS harness run + artifact check | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*(Task IDs finalized when plans are written — the planner must keep this map's requirement coverage.)*

---

## Wave 0 Requirements

- [ ] Clarabel concurrency spike script (`scripts/`) — PAR-01 evidence harness
- [ ] Multi-aggregator serial-vs-threaded test fixture — PAR-02/03/04 basis
- [ ] Staged RSS attribution harness for IEEE-8500 boundary points — SCALE-06

*Existing infrastructure covers: knife-edge canary test (quick task 260825-w5b), TestItemRunner, golden-audit script.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Threaded run wall-clock improvement is real | PAR-02 | Perf claim, not correctness | Compare recorded timings serial vs threaded on multi-aggregator fixture; record, never assert |
| SCALE-06 attribution plausibility | SCALE-06 | Numbers need researcher judgment | Read CSV + doc note; confirm residual explained or honestly bounded |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 25 min
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
