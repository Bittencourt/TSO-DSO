---
phase: 10
slug: oracle-coupling-wiring-resilience
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-22
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` stdlib + TestItems/TestItemRunner (per project stack) |
| **Config file** | `test/runtests.jl` (existing) |
| **Quick run command** | `julia --project=. -e 'using TestItemRunner; @run_package_tests filter=ti->occursin("planning", ti.name)'` |
| **Full suite command** | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~60–180 seconds (solver-backed SOCP solves dominate) |

---

## Sampling Rate

- **After every task commit:** Run the quick command (planning-oracle-scoped test items)
- **After every plan wave:** Run the full suite
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 180 seconds

---

## Per-Task Verification Map

> Task IDs are provisional until the planner finalizes plan/wave assignment. Threat refs are N/A — this is an in-process numerical optimization library with no external input, auth, or network surface.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 10-01-* | 01 | 1 | PLAN-01 | — | N/A | unit/integration | `julia --project=. test/planning/test_planning_oracle.jl` | ❌ W0 | ⬜ pending |
| 10-02-* | 02 | 2 | PLAN-02 | — | N/A | unit (toy-case invariant) | `julia --project=. test/planning/test_dual_reconciliation.jl` | ❌ W0 | ⬜ pending |
| 10-03-* | 03 | 2 | PLAN-03 | — | N/A | unit (injected NUMERICAL_ERROR) | `julia --project=. test/planning/test_oracle_resilience.jl` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/planning/test_planning_oracle.jl` — build-once oracle solve, pinned `p_import[t]==z[t]`, `dual.(pin)` returned (PLAN-01)
- [ ] `test/planning/test_dual_reconciliation.jl` — hand-computed toy case pinning the `π[t]` sign invariant + duration-weighted `π_s` (PLAN-02)
- [ ] `test/planning/test_oracle_resilience.jl` — injected/observed `NUMERICAL_ERROR` survives bounded retry; budget exhaustion raises loudly (PLAN-03)
- [ ] `test/planning/` directory + inclusion in `test/runtests.jl`

*Existing IEEE-13 fixtures and solver factory cover the model-build infrastructure; only planning-layer test files are new.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Empirical Clarabel failure-rate measurement to tune retry ladder magnitudes/budget N | PLAN-03 | Requires sweeping pinned `z` trials on real fixtures; measurement is a one-time design input, not a permanent assertion | Sweep pinned `z` trials on IEEE-13 ground fixture, record NUMERICAL_ERROR frequency, set ladder from observed rate (per CONTEXT.md Claude's Discretion) |

*The delivered retry mechanism itself has automated verification (injected error); only the tuning measurement is manual.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 180s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
