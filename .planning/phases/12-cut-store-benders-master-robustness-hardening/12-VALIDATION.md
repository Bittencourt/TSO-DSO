---
phase: 12
slug: cut-store-benders-master-robustness-hardening
status: approved
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-22
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib + TestItems/TestItemRunner (established) |
| **Config file** | `test/runtests.jl` + `test/Project.toml` |
| **Quick run command** | `julia --project=. -e 'using TestItemRunner; @run_package_tests filter=ti->(:planning in ti.tags)'` |
| **Full suite command** | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~2 min quick (planning tag, incl. new hardening items) / ~9 min full |

---

## Sampling Rate

- **After every task commit:** Run quick `:planning`-tagged test items (or name-filtered subset if the load test pushes the tag over ~2 min)
- **After every plan wave:** Run full suite
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~120 seconds (quick command)

---

## Per-Task Verification Map

> Refined by planner — one row per task. Phase owns no new requirement IDs (deepens PLAN-05/PLAN-06).

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 12-01-01 | 01 | 1 | PLAN-06 (deepen) | T-12-01..T-12-04 | N/A | testitem | `@run_package_tests filter=ti->occursin("planning",ti.name)&&occursin("benders",ti.name)` (`BendersTrace` wiring + IN-01/02/03/06 regressions in `test_planning_benders.jl`) | ❌ W0 | ⬜ pending |
| 12-01-02 | 01 | 1 | PLAN-05 (deepen) | T-12-01, T-12-02 | N/A | testitem | `@run_package_tests filter=ti->(:planning in ti.tags)` (edge-case items, `test_planning_hardening.jl`) | ❌ W0 | ⬜ pending |
| 12-02-01 | 02 | 2 | PLAN-05/06 (deepen) | T-12-06, T-12-07 | N/A | testitem | `@run_package_tests filter=ti->occursin("planning",ti.name)&&occursin("hardening",ti.name)` (load-test item, `test_planning_hardening.jl`) | ❌ W0 | ⬜ pending |
| 12-02-02 | 02 | 2 | — (doc only) | T-12-08 | N/A | grep | `grep -c "Phase 12 measured" .planning/STATE.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_planning_hardening.jl` — degenerate feasibility-cut edge cases + load test
- [ ] Extensions to `test/test_planning_benders.jl` / `test_planning_master.jl` for `BendersTrace`

*Existing infrastructure (TestItemRunner, toy Stackelberg fixture, boundary variant) covers fixture needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|

*None: all phase behaviors (trace contents, cut-store integrity, retry-rate measurement, checkpoint round-trip) have automated verification.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-07-22 (orchestrator, no-research hardening path)
