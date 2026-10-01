---
phase: 30
slug: socp-in-the-loop-benders-on-a-multi-bus-feeder
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-10-01
---

# Phase 30 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems (`@testitem`), run by TestItemRunner via `Pkg.test()` |
| **Config file** | `test/runtests.jl` (`@run_package_tests`), `test/Project.toml` |
| **Quick run command** | `EMU_FILTER=<substr> JULIA_LOAD_PATH="test:.:@stdlib" julia <scratchpad>/emu.jl <fixture files> <test file>` (top-level `@testitem` emulator) or a direct Test.jl script — NEVER TestItemRunner under `--project=.` |
| **Full suite command** | ONE detached, orchestrator-run `julia --project=. -e 'import Pkg; Pkg.test()'`, HEAD recorded, no `.claude/worktrees/agent-*` present |
| **Estimated runtime** | quick: ~1–3 min per file (dominated by package load; oracle SOCP solve ~30 ms, AC re-check ~15 s); full suite ~22–25 min |

---

## Sampling Rate

- **After every task commit:** run the changed/new `test_planning_*.jl` file via the quick command
- **After every plan wave:** re-run every new/changed planning test file via the quick command, plus the existing planning files touched by the α-bound default change (`test_planning_master.jl`, `test_planning_benders.jl`, `test_planning_hardening.jl`)
- **Before `/gsd:verify-work`:** full suite must be green (single certified run)
- **Max feedback latency:** ~180 s (quick command)

---

## Per-Requirement Verification Map

| Requirement | Behavior | Test Type | Automated Command | File Exists | Status |
|-------------|----------|-----------|-------------------|-------------|--------|
| BILEV-03 | `solve_stackelberg!` + `ConvexBranchFlow` on `ieee13_modified()`, T∈3..6, converges with closed LB/UB gap and matches an independently built monolithic joint model within a MEASURED tolerance | integration | quick command on `test/test_planning_benders_ieee13.jl` | ❌ W0 | ⬜ pending |
| BILEV-04a (voltage) | voltage-infeasible pin (thermally-widened fixture variant) → feasibility cut emitted, loop still converges | integration | quick command on `test/test_planning_feasibility_oracle.jl` | ❌ W0 | ⬜ pending |
| BILEV-04a (thermal) | thermal-infeasible pin (e.g. `z≥0.0686` on IEEE-13 T=4) → feasibility cut emitted, loop still converges | integration | same file, second testitem | ❌ W0 | ⬜ pending |
| BILEV-04b | `inexact_policy ∈ {:strict, :reject, :certify_incumbent}` each behave as documented at the measured-inexact pin (`z=0.06`, gap ratio ≈4852× or the final fixture's measured equivalent); `BendersTrace` records `socp_maxgap` + policy action; `:certify_incumbent` AC re-check reported, never thrown | unit/integration | quick command on `test/test_planning_inexact_policy.jl` | ❌ W0 | ⬜ pending |
| BILEV-05 | `:auto` α-bounds derived and valid; over-high explicit bound → `ArgumentError` at build; runtime `Q_j` below bound → error | unit | quick command on `test/test_planning_master.jl` (extended) | ⚠️ extend | ⬜ pending |
| BILEV-05 (audit) | every existing explicit `α_op_lb`/`α_x_lb` call site at T>1 checked against the derived bound; any now-rejected bound reported as a found bug | one-off audit script (phase tooling, not a suite test) | phase script under `.planning/phases/30-*/scripts/` | ❌ W0 | ⬜ pending |
| regression | PVAL-04 registry gains every new planning `build_*`; existing planning goldens unmoved (golden-move audit) | unit + audit | quick command on `test/test_planning_noninteger.jl`; `audit_goldens.py` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_planning_benders_ieee13.jl` — BILEV-03 (IEEE-13 short-T population helper, convergence, monolithic cross-check)
- [ ] `test/test_planning_feasibility_oracle.jl` — BILEV-04a (voltage + thermal fixtures)
- [ ] `test/test_planning_inexact_policy.jl` — BILEV-04b (three policies, trace columns)
- [ ] extend `test/test_planning_master.jl` — BILEV-05
- [ ] α-bound audit script — BILEV-05 found-bug report
- [ ] PVAL-04 registry entries for any new planning builder

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| T=24 IEEE-13 run | BILEV-03 (documentation) | exceeds the ≤2-min suite budget by design (CONTEXT.md) | run the Literate experiment script end-to-end; confirm it converges and records gap + incumbent exactness |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 180s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
