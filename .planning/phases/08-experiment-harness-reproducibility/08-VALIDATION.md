---
phase: 8
slug: experiment-harness-reproducibility
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-19
---

# Phase 8 — Validation Strategy

> The load-bearing gate is INFRA-04 bit-for-bit reproducibility: same Scenario (selectors + seed) →
> identical result through the FULL solve on the single-threaded Clarabel path.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `Test` (stdlib) + TestItems/TestItemRunner |
| **Config file** | `test/Project.toml` + `test/runtests.jl` |
| **Quick run command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (per-seam `@run_package_tests filter=...`) |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Estimated runtime** | ~5–7 minutes (harness runs full solves; DrWatson/CSV/DataFrames precompile) |

---

## Sampling Rate

- After every task commit: relevant per-seam `@testitem` filter
- After every plan wave: full suite
- Before verify: full suite green
- Max feedback latency: ~420s

---

## Per-Task Verification Map

| Task | Requirement | Secure Behavior | Test Type | Command (filter substring) | Status |
|------|-------------|-----------------|-----------|----------------------------|--------|
| deps + manifests | INFRA-04 | DrWatson/CSV/DataFrames as hard [deps]; manifests re-resolved 1.10/1.11/1.12 (main+test) | integration | `occursin("scenario", ti.name) \|\| occursin("harness", ti.name)` | ⬜ pending |
| Scenario schema | EXP-01 | immutable declarative Scenario of PRIMITIVE selectors (feeder/devices/profile/seed/strategy/config); savename-able | unit | `occursin("scenario", ti.name)` | ⬜ pending |
| run_scenario dispatch | EXP-01 | run_scenario(scn) dispatches :centralized→solve_welfare / :admm→solve_admm, reusing builders; returns a result record (welfare, DADP, iters/ρ if admm, PF-04 cert, timings) | integration | `occursin("run", ti.name) \|\| occursin("scenario", ti.name)` | ⬜ pending |
| sweeps + flat storage | EXP-02 | dict_list sweep → per-run JLD2 (gitignored) + a deterministically-sorted diff-friendly CSV summary (scalars, no :path) | integration | `occursin("sweep", ti.name)` | ⬜ pending |
| provenance / tagsave | INFRA-04 | tagsave stamps git commit + Julia VERSION; the committed Manifest is the env pin; seed logged | unit | `occursin("provenance", ti.name) \|\| occursin("tagsave", ti.name)` | ⬜ pending |
| bit-for-bit reproducibility | INFRA-04 | same Scenario (selectors+seed) → IDENTICAL result through the full solve (single-thread Clarabel; == same-process, isapprox rtol 1e-8 cross-process; timings excluded) | integration | `occursin("repro", ti.name) \|\| occursin("bitfor", ti.name)` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] DrWatson/CSV/DataFrames added to main [deps] (+ test if testitems `using` them) with [compat]; manifests re-resolved 1.10/1.11/1.12
- [ ] RED `@testitem` stubs: Scenario schema, run_scenario dispatch, sweep+storage, provenance/tagsave, bit-for-bit reproducibility
- [ ] a small scenario + a 2-point sweep fixture

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Cross-machine bit-for-bit | INFRA-04 | Exact `==` cross-MACHINE depends on BLAS/CPU; the automated gate uses `==` same-process + `isapprox(rtol=1e-8)` cross-process (single-thread Clarabel), which is the robust portable guarantee | Re-run a scenario on a second machine and compare the diff-friendly CSV summary within rtol |

*The same-process `==` and cross-process `isapprox` reproducibility, provenance stamping, and sweep storage are fully automated.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity maintained
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] `nyquist_compliant: true`

**Approval:** pending
