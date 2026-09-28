---
phase: 26
slug: network-device-model-correctness
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-28
---

# Phase 26 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` stdlib + TestItems/TestItemRunner (`@testitem`, discovered by `test/runtests.jl`) |
| **Config file** | `test/runtests.jl` |
| **Quick run command** | Direct script reproducing the touched `@testitem` body: `julia --project=. <scratch>/check_<task>.jl` (NEVER TestItemRunner under `--project=.`) |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` — launched DETACHED (`nohup setsid bash -c "... > LOG 2>&1; echo $? > DONE" </dev/null &`), poll marker |
| **Estimated runtime** | quick: ~60–180 s (precompile-dominated); full: ~16–23 min |

---

## Sampling Rate

- **After every task commit:** direct-script reproduction of touched `@testitem`(s)
- **After every plan wave:** full suite (detached), log start timestamp checked against HEAD
- **Before `/gsd:verify-work`:** full suite green (only known, pre-existing flakes / the 2 known-false Aqua failures discounted, with evidence)
- **Max feedback latency:** ~180 s per task

---

## Per-Task Verification Map

| Requirement | Behavior | Test Type | Automated Command | File Exists | Status |
|-------------|----------|-----------|-------------------|-------------|--------|
| FIX-01 | 3-bus heavy-load/low-V: Ipopt AC-feasible, default SOCP feasible, thesis-literal variant infeasible | integration | direct script of new `test/test_exactness_verdict.jl` items | ❌ W0 | ⬜ pending |
| FIX-02 | `v̂ ≥ v` at solution; docstring load-bearing bound == actual binding constraint | unit | direct script of `test/test_convex_branch_flow.jl` + flipped `test/test_restricted_branch_flow.jl` spot-check | ⚠️ edit | ⬜ pending |
| FIX-03 | PV back-feed: receiving-end limit active (nonzero dual), sending-end slack | integration | direct script of new back-feed `@testitem` | ❌ W0 | ⬜ pending |
| FIX-04 | soc[1:T+1]; soc0=Emin + hour-T discharge incentive → zero discharge; MPC terminal on soc[H+1] | unit | direct script of `test/test_pvbattery.jl`, `test/test_fourquadbess.jl`, `test/test_mpc_window.jl` | ⚠️ edit | ⬜ pending |
| FIX-05 | per-device `:Rq` contribution == `p·tanφ` (interruptible, thermostatic, deferrable) | unit | direct script of `test/test_aggregator.jl` / device test files | ⚠️ edit + new | ⬜ pending |
| SC-6 | every moved golden: old→new + cause comment; SUMMARY table; full suite green | process | full-suite before/after diff | n/a | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Baseline full-suite run on current HEAD (pass/fail/error counts recorded) before any fix
- [ ] `test/test_exactness_verdict.jl` — FIX-01 3-bus regression (fixture tuned empirically)
- [ ] PV back-feed fixture for FIX-03
- [ ] Single-member `Aggregator` fixture wrapping converted (Variant-2) `Interruptible` for FIX-05
- [ ] `git grep -n "soc\[H\]\|soc\[T\]\|length(soc)\|soc\[end\]"` sweep over `src/` + `test/` to enumerate FIX-04 index-shift touch points

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Verdict docs page accurately quotes thesis 3.43/3.45 and Gan–Low 2015 | FIX-01 | Source fidelity to a PDF | Compare quoted equations against `docs/references/86. Tesis…pdf` pages cited |
| Golden-move audit (no silent re-pin) | SC-6 | Judgment on stated cause | Review SUMMARY golden table vs `git diff` of test files |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 180s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
