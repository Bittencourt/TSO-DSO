---
phase: 11
slug: single-distributor-stackelberg-benders-certified
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-22
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib + TestItems/TestItemRunner (established, v1.0) |
| **Config file** | `test/runtests.jl` (TestItemRunner entry) + `test/Project.toml` |
| **Quick run command** | `julia --project=. -e 'using TestItemRunner; @run_package_tests filter=ti->(:planning in ti.tags)'` |
| **Full suite command** | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~60s quick (planning tag) / ~8-9 min full |

---

## Sampling Rate

- **After every task commit:** Run quick `:planning`-tagged test items
- **After every plan wave:** Run full suite
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~120 seconds (quick command)

---

## Per-Task Verification Map

> Filled by planner — one row per task. Requirements: PLAN-04, PLAN-05, PLAN-06, PLAN-07, PVAL-01.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 1 | PLAN-04 | — | N/A | testitem | quick `:planning` run (`test_planning_follower.jl`) | ❌ W0 | ⬜ pending |
| 11-01-02 | 01 | 1 | PLAN-05 | — | N/A | testitem | quick `:planning` run (`test_planning_master.jl`) | ❌ W0 | ⬜ pending |
| 11-02-01 | 02 | 2 | PLAN-06 | — | N/A | testitem | quick `:planning` run (`test_planning_benders.jl`) | ❌ W0 | ⬜ pending |
| 11-03-01 | 03 | 3 | PLAN-07, PVAL-01 | — | N/A | testitem | quick `:planning` run (`test_bilevel_certification.jl`) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_planning_follower.jl` — follower LP `α(z)` duals + Farkas certificate items (PLAN-04)
- [ ] `test/test_planning_master.jl` — persistent cut-row accumulation, no-rebuild invariance (PLAN-05)
- [ ] `test/test_planning_benders.jl` — end-to-end convergence gap items (PLAN-06)
- [ ] `test/test_bilevel_certification.jl` — BilevelJuMP BigM/StrongDuality vs hand enumeration vs Benders (PLAN-07, PVAL-01)
- [ ] `test/Project.toml` — add BilevelJuMP (test-only dependency) + Ipopt if StrongDualityMode needs NLP

*Existing infrastructure (TestItemRunner, Phase6Fixtures, ToyElasticDevice) covers fixture needs; new files follow `test_planning_*.jl` conventions. Note the sanctioned INFRA-02 exception: the BilevelJuMP certification item must import solvers directly (BilevelModel requires a bare optimizer constructor) — document the exception in the test file header.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|

*None expected: all phase behaviors (duals, certificates, convergence gaps, certification agreement) have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
