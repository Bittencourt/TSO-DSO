---
phase: 31
slug: gne-nash-fixture-integer-n-1-planning-docs-refresh
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-10-01
---

# Phase 31 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems (`@testitem`), run by TestItemRunner via `Pkg.test()` |
| **Config file** | `test/runtests.jl` (`@run_package_tests`), `test/Project.toml` |
| **Quick run command** | `EMU_FILTER=<substr> JULIA_LOAD_PATH="test:.:@stdlib" julia /tmp/claude-1000/-home-pedro-programming-TSO-DSO/981f784b-8b89-4fdd-b64d-2c7c39f9b271/scratchpad/emu.jl <fixture files...> <test file>` (top-level @testitem emulator) or a direct Test.jl script — NEVER TestItemRunner under `--project=.` |
| **Full suite command** | ONE detached, orchestrator-run `julia --project=. -e 'import Pkg; Pkg.test()'`, HEAD recorded, no `.claude/worktrees/agent-*` present |
| **Estimated runtime** | quick: ~1–3 min per file (integer best response ≈4 s each on the toy); full suite ~24 min |

---

## Sampling Rate

- **After every task commit:** run the changed/new test file(s) via the quick command
- **After every plan wave:** re-run every new/touched planning test file plus the regression set that exercises the changed code (nash, coupling, benders_integer, certification_integer, master_integer, benders, master, inexact_policy)
- **Before `/gsd:verify-work`:** full suite green (single certified run)
- **Max feedback latency:** ~180 s

---

## Per-Requirement Verification Map

| Requirement | Behavior | Test Type | Automated Command | File Exists | Status |
|-------------|----------|-----------|-------------------|-------------|--------|
| BILEV-06a | interior-cap fixture (`x_inv_max=[1.0,1.0]`, `corridor_cap=2.0`): probe with `x_inv0`-varying seeds reports nonzero spread inside the analytic GNE interval `x_inv_1 ∈ [0, 0.7]`, above a measured floor; corner-cap control spread stays 0 | unit | quick command on `test/test_planning_nash.jl` | ⚠️ extend | ⬜ pending |
| BILEV-06b | `solve_variational_equilibrium` (joint model, shared row once): every player's shared-row multiplier equal within measured tol; VE inside the GNE interval | unit | quick command on the VE test file/section | ❌ W0 | ⬜ pending |
| BILEV-07 | `run_nash!(...; integer=(; K, ...))` N=2 converges with integer master per best response; brute-force grid confirms no profitable unilateral deviation; cycling detected and reported loudly | unit/integration | quick command on `test/test_planning_nash_integer.jl` (or nash section) | ❌ W0 | ⬜ pending |
| BILEV-07 (P30 WR fixes) | `ALMOST_INFEASIBLE` classified in corner search; `build_master_integer` validates `L`; LL cut emitted only when `Q_ν ≥ L`; WR-03 LB-inflation fix on both masters | unit | quick command on `test_planning_benders_integer.jl`, `test_planning_master_integer.jl`, `test_planning_master.jl` | ⚠️ extend | ⬜ pending |
| BILEV-08 | taxonomy table present in both `.typ` writeups citing functions/tests; stale "no integer variables" claim removed; `typst compile` exits 0 for both; API docstrings updated | doc check | `~/.local/bin/typst compile docs/writeups/<file>.typ /tmp/<file>.pdf` + grep for taxonomy rows | ✅ (content missing) | ⬜ pending |
| regression | Nash goldens / integer goldens unmoved (golden-move audit); PVAL-04 registry gains any new planning `build_*` | unit + audit | quick command on `test_planning_noninteger.jl`; `audit_goldens.py --base <Phase-30 close>` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `run_nash_probe` seeds dispatch extension (vary `x_inv0` per seed; additive, backward-compatible)
- [ ] interior-cap fixture + analytic GNE interval derivation
- [ ] `solve_variational_equilibrium` + test
- [ ] `run_nash!` `integer` kwarg + `build_master_integer` `bounds_ctx` + cycle detection + tests
- [ ] Phase-30 WR-01/02/03 fixes + tests

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Writeup prose accuracy (Portuguese) | BILEV-08 | narrative correctness vs code is a reading judgment | read the refreshed taxonomy sections; each cited function/test must exist (grep) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 180s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
