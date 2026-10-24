---
phase: 40
slug: 784-house-thesis-population
status: final
nyquist_compliant: true
wave_0_complete: false
created: 2026-10-24
---

# Phase 40 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + `TestItemRunner` (test/runtests.jl), `:slow` tag split |
| **Config file** | `test/Project.toml` (pinned test env) |
| **Quick run command** | `julia --project=. -e 'import Pkg; Pkg.test()'` with `TSODSO_TEST_FILES=<file>` targeted |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Estimated runtime** | ~30 min full suite; targeted files minutes; measurement runs tens of minutes |

---

## Sampling Rate

- **After every task commit:** Targeted test file(s) for the touched seam
- **After every plan wave:** Full suite — 0 fail / 0 error; `:default` population goldens unchanged
- **Before phase verification:** Full suite green; agreement band pinned gate-then-golden
- **Max feedback latency:** ~30 min

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 40-0x-0x | 0x | x | POP-01 | — | `:case_a_784` selector returns 10 bus-level aggregators totalling 784 houses; `:default` byte-identical | unit | targeted test file | ❌ W0 | ⬜ pending |
| 40-0x-0x | 0x | x | POP-02 | — | 784 distinct house seeds; rebuild reproduces population exactly | unit | targeted test file | ❌ W0 | ⬜ pending |
| 40-0x-0x | 0x | x | POP-03 | — | Household map: house → bus, aggregator, device set, PV group; deterministic rebuild | unit | targeted test file | ❌ W0 | ⬜ pending |
| 40-0x-0x | 0x | x | POP-04 | — | Centralized vs ADMM at 784/T=24 agree within MEASURED stated band (gate-then-golden) | slow test + measurement | `:slow` testitem | ❌ W0 | ⬜ pending |
| 40-0x-0x | 0x | x | POP-05 | — | Scaling CSV: wall time vs -t 1/2/4 + iters vs ladder; measured, subprocess-driven | measurement script | harness run + artifact check | ❌ W0 | ⬜ pending |
| 40-0x-0x | 0x | x | POP-06 | — | Doc page: composition totals + calibration provenance + Appendix-E unavailability list | doc | grep checks + figures sourced from built population | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*(Task IDs finalized when plans are written — planner keeps this coverage.)*

---

## Wave 0 Requirements

- [ ] `:case_a_784` builder + house seeding + household map (POP-01/02/03 basis)
- [ ] Measurement harness scripts (scaling ladder + threads sweep) under `scripts/`
- [ ] `:slow` agreement testitem skeleton (POP-04)

*Existing infrastructure covers: TestItemRunner, `:slow` tag, goldens, committed-CSV literate pattern.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Speedup interpretation | POP-05 | Perf claim — negative result valid | Read scaling CSV + doc page; confirm measured-not-assumed framing |
| Composition doc plausibility | POP-06 | Researcher judgment | Read doc page; totals match built-population measurement |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30 min
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-10-24 (autonomous — finalized at planning)
