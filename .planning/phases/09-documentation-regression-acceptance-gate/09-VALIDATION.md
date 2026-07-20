---
phase: 9
slug: documentation-regression-acceptance-gate
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-20
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | TestItemRunner (`@testitem`) over `Test` stdlib; Documenter `makedocs` (`@example` execution) for docs |
| **Config file** | `test/Project.toml` (test env), `docs/Project.toml` (docs env), `test/runtests.jl` (`@run_package_tests`) |
| **Quick run command** | `julia --project=. -e 'using Pkg; Pkg.test()'` (full suite is the quick unit for this repo) |
| **Full suite command** | `julia --project=. -e 'using Pkg; Pkg.test()'` + `julia --project=docs docs/make.jl` |
| **Estimated runtime** | ~6 min (test suite, incl. IEEE-123 ADMM) + ~1–3 min (docs build) |

---

## Sampling Rate

- **After every task commit:** Run the affected testitem(s), e.g. the acceptance testitem or a docs build for the touched page.
- **After every plan wave:** Run the full `Pkg.test()` suite.
- **Before `/gsd:verify-work`:** Full suite green AND `docs/make.jl` builds without error.
- **Max feedback latency:** ~360 s (full suite).

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 9-acceptance | acceptance | — | EXP-04 | — | N/A | integration | `Pkg.test()` (test_acceptance.jl testitem) | ❌ W0 | ⬜ pending |
| 9-docs-build | docs | — | EXP-03 | — | N/A | build | `julia --project=docs docs/make.jl` | ✅ (extend) | ⬜ pending |
| 9-regression-fit | regression | — | EXP-04 | — | N/A | unit | `Pkg.test()` (FIT regression testitem) | ✅ (extend) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_acceptance.jl` — consolidated E2E acceptance testitem (IEEE-13 congestion + IEEE-123 voltage): exact relaxation + recovered DADP + ADMM≈centralized, reusing existing pinned goldens/tolerances (Phase4Fixtures / Phase7Fixtures).
- [ ] New `docs/literate/*.jl` pages per model rung — validated by `@example` execution during `makedocs`.

*Existing per-phase inline pins + `docs/make.jl` pipeline cover the bulk; Phase 9 adds breadth, not new infra.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `deploydocs` repo slug correctness | EXP-03 | Repo GitHub slug not discoverable from local state; deploy only runs under CI env | Set `deploydocs(repo=...)`, push to CI, confirm GitHub Pages publishes (checkpoint: human-verify) |
| CairoMakie figure aesthetics | EXP-03 | Vector-figure visual quality is subjective; CairoMakie is weakdep (may be absent in headless build) | In a non-headless env with CairoMakie installed, build docs and eyeball the rendered convergence/voltage figures |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 360s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
