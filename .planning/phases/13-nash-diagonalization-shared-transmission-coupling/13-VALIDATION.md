---
phase: 13
slug: nash-diagonalization-shared-transmission-coupling
status: approved
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-23
---

# Phase 13 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib + TestItems/TestItemRunner (established) |
| **Config file** | `test/runtests.jl` + `test/Project.toml` |
| **Quick run command** | `julia --project=. -e 'using TestItemRunner; @run_package_tests filter=ti->(:planning in ti.tags)'` |
| **Full suite command** | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~3 min quick (planning tag incl. Nash items) / ~10 min full |

---

## Sampling Rate

- **After every task commit:** Run quick `:planning`-tagged test items (or a name-filtered subset if the probe matrix pushes the tag over ~3 min)
- **After every plan wave:** Run full suite
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~180 seconds (quick command)

---

## Per-Task Verification Map

> Refined by planner — one row per task. Requirements: NASH-01, NASH-02, NASH-03, NASH-04.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 13-01-* | 01 | 1 | NASH-01 | — | N/A | testitem | quick run (`test_planning_coupling.jl`) | ❌ W0 | ⬜ pending |
| 13-02-* | 02 | 2 | NASH-02, NASH-03 | — | N/A | testitem | quick run (`test_planning_nash.jl`) | ❌ W0 | ⬜ pending |
| 13-03-* | 03 | 3 | NASH-04 | — | N/A | testitem | quick run (probe matrix items, `test_planning_nash.jl`) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_planning_coupling.jl` — SharedTransmission build/dual/capacity items (NASH-01)
- [ ] `test/test_planning_nash.jl` — Gauss-Seidel convergence, nested-tolerance guard, NashTrace, probe matrix (NASH-02/03/04)
- [ ] Plot helper test (extension-loaded CairoMakie smoke test, if plotting ships via weakdep ext)

*Existing infrastructure covers fixtures (toy Stackelberg family extends to N=2/N=3 corridor fixtures).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Convergence-plot visual sanity | NASH-03 | Plot rendering quality is visual | Run the plot helper on a converged N=2 trace; check two-level curves render with labeled axes |

*All numerical behaviors have automated verification; only the figure's visual quality is manual.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 180s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-07-23 (research Validation Architecture present in 13-RESEARCH.md)
