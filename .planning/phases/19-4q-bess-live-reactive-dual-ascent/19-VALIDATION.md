---
phase: 19
slug: 4q-bess-live-reactive-dual-ascent
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-07
---

# Phase 19 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib + TestItems/TestItemRunner |
| **Config file** | test/runtests.jl (entrypoint) |
| **Quick run command** | targeted `@testitem` runs via TestItemRunner filter |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Estimated runtime** | ~minutes (full suite: 2358 pass / 1 known-fail / 3 broken baseline) |

---

## Sampling Rate

- **After every task commit:** Run targeted test items for the touched module
- **After every plan wave:** Run full suite via `julia --project=. -e 'import Pkg; Pkg.test()'`
- **Before `/gsd:verify-work`:** Full suite must be green (modulo the known Aqua CairoMakie stale-deps drift)
- **Max feedback latency:** ~600 seconds (full suite)

---

## Per-Task Verification Map

*To be filled by the planner — one row per task, mapping MESH-04/MESH-05 to test items.*

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | — | — | MESH-04 | — | N/A | unit | TBD | ⬜ | ⬜ pending |
| TBD | — | — | MESH-05 | — | N/A | integration | TBD | ⬜ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Test fixture with a `FourQuadBESS` on the small radial feeder (byte-identity baseline captured BEFORE any src/ change — gate-then-golden ordering)
- [ ] Solver-noise-floor calibration on the chosen fixture before any tolerance is pinned (measurement-before-golden)

---

## Manual-Only Verifications

*None expected — all phase behaviors (device cone, complementarity certificate, μ-ascent convergence, byte-identity) have automated verification. IEEE-13 supporting evidence runs under the existing bounded-retry quarantine.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 600s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
