---
phase: 16
slug: reactive-power-consensus
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-25
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `16-RESEARCH.md` § Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `TestItemRunner.jl` + `TestItems.jl` (existing convention) |
| **Config file** | `test/runtests.jl` (`@run_package_tests`) |
| **Quick run command** | `julia --project -e 'using TestItemRunner, TSODSO; @run_package_tests filter=ti->occursin("reactive", ti.name) \|\| occursin("dlmp", ti.name)'` (narrow to `reactive` once `test_admm_reactive.jl` items are named) |
| **Full suite command** | `julia --project -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~10–30 s quick (2-bus/IEEE-13); full suite minutes (IEEE-13/123 ADMM regression) |

---

## Sampling Rate

- **After every task commit:** quick filtered `@run_package_tests`.
- **After every plan wave:** full `Pkg.test()` — catches accidental perturbation of the UNCHANGED default-path regression suite via any stray shared-code edit.
- **Phase gate:** full `Pkg.test()` green **PLUS** the empirical flake-rate re-measurement (Open Question 2) explicitly run and its number recorded in the phase findings — the measured rate is a *deliverable*, not a pass/fail (mirrors Phase 15 treating a genuine finding as citable, not a bug).
- **Max feedback latency:** ~30 s quick loop.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 16-01-* | 01 | 1 | REACT-03 (naming) | manual/plan gate | grep-audit review (BLOCKING first task) | N/A (task-ordering gate) | ⬜ pending |
| 16-02-* | 02 | 2 | REACT-01 | unit + regression | `... occursin("admm"/"dso", ti.name)` | Partial — regressions ✅ must stay green; new `reactive_consensus=true` asserts ❌ W0 | ⬜ pending |
| 16-03-* | 03 | 3 | REACT-02 | unit | `... occursin("dlmp", ti.name)` | ❌ W0 `test_pricing_dlmp.jl` new asserts | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

### Requirement → Behavior detail

- **REACT-03 (first, BLOCKING)**: the `μ` naming-collision grep-audit (16-RESEARCH.md § "μ Naming Collision") is documented and a **distinct identifier chosen** (e.g. `qag_dso` variable; never bare `μ`, which today means only the adaptive-ρ band) **before** any `AgrOpt`/`DsoOpt`/`Dlmp` diff lands. Also: `Scenario.jl` must NOT be touched (would perturb the DrWatson `savename` golden-hash).
- **REACT-01**: with `reactive_consensus=false` (default) `build_dso_opt`/`solve_admm` produce byte-identical models/results (existing `test_admm.jl`, `test_admm_adaptive.jl`, `test_ieee123_admm.jl`, `test_dso.jl` pass UNCHANGED); with `reactive_consensus=true`, `:balance_q` closes via a genuine `qag_dso[j,t]` coupling variable in the ADMM solve (centralized already enforces the equality — verify, don't re-add).
- **REACT-02**: `decompose_dlmp(ctx)` returns a NEW `reactive` field = `dual(:balance_q)`, **gated by the SAME PF-04-style no-slack certificate** as the existing components (new `assert_no_slack` on `:balance_q`, mirroring `:balance_p` — publishing an uncertified dual under `strict=false` would cite a numerically meaningless price). Hand-computed 2-bus reactive-price pin matches.

---

## Wave 0 Requirements

- [ ] `test/test_admm_reactive.jl` — NEW; REACT-01/03 (mirror `test_admm_adaptive.jl`: RED `isdefined` guards → behavioral asserts)
- [ ] `test/test_dso.jl` — MODIFIED; `reactive_consensus=true` builder-shape asserts (mirror existing `@test haskey(dso.ctx.constraints, :balance_q)`)
- [ ] `test/test_pricing_dlmp.jl` — MODIFIED; new `reactive` field asserts + hand-computed 2-bus reactive-price pin
- [ ] Repeated-run (N≥20) flake-rate measurement script (`scripts/*.jl` convention) — long-running, not a CI `@testitem`; its measured-rate OUTPUT recorded in phase completion notes
- [ ] Framework install: none — dev-deps already present

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| μ naming-collision resolved before any code diff | REACT-03 | Task-ordering discipline is not machine-checkable | Plan-checker/reviewer confirms the identifier pick + grep-audit is its own first BLOCKING task, sequenced before every `AgrOpt`/`DsoOpt`/`Dlmp` diff |
| Clarabel flake-rate under Q-consensus | (finding) | The measured number is the deliverable, no fixed threshold | Run N≥20 repeats on IEEE-13/123 with `reactive_consensus=true`; record rate vs a same-session baseline |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies (or are documented plan-gate tasks)
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] Default-path byte-identical regression is a first-class gate (REACT-01/03 non-regression)
- [ ] No watch-mode flags
- [ ] `nyquist_compliant: true` set by plan-checker

**Approval:** pending
