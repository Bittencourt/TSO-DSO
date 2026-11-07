---
phase: 39
slug: parallel-ready-admm-gating-measurements
status: final
nyquist_compliant: true
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
| 39-01-01 | 01 | 1 | PAR-02 | — | Spike records bitwise-equality verdict under `-t 4` (indirect + direct_model legs, positive/negative controls) — gates enabling the threaded executor | script + doc | `julia -t 4 --project=. .planning/spikes/005-clarabel-concurrency/sweep.jl` + README verdict | ❌ W0 (created by 39-01 T1) | ⬜ pending |
| 39-02-01 | 02 | 2 | PAR-01 | T-39-02-04 | `parallel` kwarg default false (byte-identical serial); fail-loud ArgumentError at 1 thread; flag threaded down with same-task callee signature extension (no MethodError mid-plan) | unit + regression | `TSODSO_TEST_FILES=test_admm_knifeedge_canary.jl julia --project=. -e 'import Pkg; Pkg.test()'` (canary doubles as MethodError detector) | ✅ canary file | ⬜ pending |
| 39-02-02 | 02 | 2 | PAR-01 | T-39-02-01 | Task-safe solve grain (no st/ls writes in task bodies); serial statement order preserved | unit | `TSODSO_TEST_FILES=test_admm_phases.jl,test_admm_reactive.jl julia --project=. -e 'import Pkg; Pkg.test()'` | ✅ | ⬜ pending |
| 39-02-03 | 02 | 2 | PAR-01, PAR-03 | T-39-02-01/03/05 | Split execute step + fetch-in-order join; TaskFailedException unwrap to original exception; no @sync/threadid; BLAS/MOI pinning on threaded path only | unit | `TSODSO_TEST_FILES=test_admm_phases.jl,test_admm_reactive.jl,test_admm_timeout.jl,test_admm_exactness_default.jl julia --project=. -e 'import Pkg; Pkg.test()'` | ✅ | ⬜ pending |
| 39-03-01/02 | 03 | 1 | PAR-04 | — | julia_threads/blas_threads additive provenance keys; `_scenario_identity`/`==`/`hash`/filename stay executor-blind | unit | `TSODSO_TEST_FILES=test_experiments.jl julia --project=. -e 'import Pkg; Pkg.test()'` | ✅ (extends existing item) | ⬜ pending |
| 39-04-01 | 04 | 3 | PAR-05 | — | Per-aggregator dispatch/utility/import/prices as TRAILING additive keys; existing keys unchanged in name/order/value | unit | `TSODSO_TEST_FILES=test_admm_phases.jl,test_admm.jl julia --project=. -e 'import Pkg; Pkg.test()'` | ✅ | ⬜ pending |
| 39-04-02 | 04 | 3 | PAR-02 | T-39-04-01/02/03 | Guard item (1-thread-safe) + bitwise threaded==serial equality; BLAS save/restore hygiene; Item B skip allowlisted in expected_broken.txt within the task | unit (thread-gated) | `TSODSO_TEST_FILES=test_admm_parallel.jl julia --project=. -e 'import Pkg; Pkg.test()'` (1-thread, green via allowlist) + `JULIA_NUM_THREADS=4` same command | ❌ W0 (created by 39-04 T2) | ⬜ pending |
| 39-04-03 | 04 | 3 | PAR-03 | T-39-04-04 | Error parity: type + msg + iterations + node attribution; NOT TaskFailedException/CompositeException; Item C allowlist entry; canary-after-parallel in same process | unit (thread-gated) | `JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_admm_parallel.jl,test_admm_knifeedge_canary.jl julia --project=. -e 'import Pkg; Pkg.test()'` | ❌ W0 (created by 39-04 T3) | ⬜ pending |
| 39-05-01/02/03 | 05 | 4 | SCALE-06 | T-39-05-01/02/03 | Staged RSS attribution at boundary points; reconciliation rows (components + tolerances + residual); dated doc note citing CSV row keys | measurement + doc | `julia --project=. scripts/profile_ieee8500_memory_attribution.jl --fixture ieee8500-mv --density 0.1 --t-horizon 10 --stage 2` (smoke) → full T=10/24 runs per 39-05 T2 | ❌ W0 (created by 39-05 T1) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*(Task IDs finalized 2026-10-24 — post-planning revision; requirement coverage complete: PAR-01…PAR-05, SCALE-06 all mapped.)*

---

## Wave 0 Requirements

- [ ] `.planning/spikes/005-clarabel-concurrency/` spike (sweep.jl + sweep.csv + README verdict) — PAR-02 gate; created by plan 39-01 T1
- [ ] `test/test_admm_parallel.jl` (guard / bitwise equality / error-parity items + expected_broken.txt entries) — PAR-02/03 basis, PAR-05 assertions; created by plan 39-04 T2/T3
- [ ] `scripts/profile_ieee8500_memory_attribution.jl` staged RSS attribution harness — SCALE-06; created by plan 39-05 T1

*Existing infrastructure covers: knife-edge canary test (quick task 260825-w5b), TestItemRunner, golden-audit script. PAR-04 extends the existing `test/test_experiments.jl` provenance item (no new file needed).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Threaded run wall-clock improvement is real | PAR-02 | Perf claim, not correctness | Compare recorded timings serial vs threaded on multi-aggregator fixture; record, never assert |
| SCALE-06 attribution plausibility | SCALE-06 | Numbers need researcher judgment | Read CSV + doc note; confirm residual explained or honestly bounded |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (each ❌ W0 artifact has a creating task: 39-01 T1, 39-04 T2/T3, 39-05 T1)
- [x] No watch-mode flags
- [x] Feedback latency < 25 min (targeted runs seconds–minutes; full suite ~10–25 min)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planner-approved (post-planning revision, 2026-10-24); execution pending
