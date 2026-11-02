---
phase: 44
slug: aggregator-as-actor
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-11-02
---

# Phase 44 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> The source is the "Validation Architecture" section of `44-RESEARCH.md`.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems `@testitem`, run through `Pkg.test()`. TestItemRunner is configured by `test/runtests.jl`, with tags `:fast`/`:slow`. |
| **Config file** | `test/runtests.jl`, `test/expected_broken.txt`. Fixtures: `test/fixtures_two_bus.jl`, `fixtures_ieee13.jl`, `fixtures_ieee123.jl`. |
| **Quick run command** | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=<file>.jl julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (run by the orchestrator only, detached, ~90 min) |
| **Estimated runtime** | ~60–240 s per targeted fast file, including load and precompile. IEEE-123 slow items take longer. |

Hygiene:
- If a run mutated them, run `git checkout -- test/Project.toml test/Manifest.toml` afterwards.
- Never run TestItemRunner via `julia -e` or `--project=test`.
- Agents do not run the full suite.

---

## Sampling Rate

- **After every task commit:** run that task's new test file (fast set) plus `test_admm_phases.jl`.
- **After every plan wave:** run the new files plus `test_admm_knifeedge_canary.jl, test_admm.jl, test_agr.jl, test_dso.jl, test_admm_reactive.jl, test_welfare_solve.jl, test_settlement.jl, test_flex_population.jl, test_exports.jl`.
- **Before verification:** the full suite must be green against the baseline of 34468 pass / 0 fail / 0 error / 7 allowlisted broken.
- **Max feedback latency:** about 300 s for a targeted file.

---

## Per-Task Verification Map

| Req | Behavior | Test Type | Automated Command | File Exists | Status |
|-----|----------|-----------|-------------------|-------------|--------|
| ACTOR-01 | `WelfareObjective` gives a bit-identical AGR build. Per-actor objective selection works. A non-zero `m` changes dispatch. | unit | `TSODSO_TEST_FILES=test_actor_objective.jl` | ❌ W0 | ⬜ pending |
| ACTOR-01 | The default-path digest fence holds and the canary stays at 56 iters / −4823.66604824162. | regression | `TSODSO_TEST_FILES=test_admm_knifeedge_canary.jl,test_admm.jl,test_agr.jl,test_admm_phases.jl` | ✅ | ⬜ pending |
| ACTOR-02 | ADMM with `ProfitObjective(0)` equals ADMM welfare bitwise. Centralized `m=0` matches within a measured tolerance. ADMM and centralized agree for `m≠0` (DEV-10 pattern). | integration | `TSODSO_TEST_FILES=test_actor_objective.jl` | ❌ W0 | ⬜ pending |
| ACTOR-02 | `W_soc(profit) ≤ W_opt`. ΔW is reported both absolute and relative. `welfare` is social welfare, reported separately from the actor objective. | integration | same | ❌ W0 | ⬜ pending |
| ACTOR-03 | The "each site its own actor" slot branch equals legacy bitwise. A portfolio on distinct buses equals legacy. A split bus is equivalent to the merged aggregator within a measured tolerance. The slot-λ certificate is reported. `dadp` has shape `(n_load_nodes,T)`. LIVE reactive + FourQuadBESS works multi-slot. | integration | `TSODSO_TEST_FILES=test_actor_portfolio.jl` | ❌ W0 | ⬜ pending |
| ACTOR-03 | The existing 1:1 guards and tests are unchanged. Threaded equals serial bitwise. | regression | `TSODSO_TEST_FILES=test_admm.jl,test_dso.jl,test_admm_reactive.jl,test_admm_exactness_default.jl`; `JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_admm_parallel.jl` | ✅ | ⬜ pending |
| ACTOR-04 | `BehaviourSpec()` returns its input `===`, with a digest fence. Seeded draws are deterministic (SplitMix64). ξ=1 matches the unwrapped device. `opt_out=1` gives the baseline. Wrapper traits forward. The rebound constraint is feasible and holds. FIT/MPC/stochastic guards throw `ArgumentError`. | unit | `TSODSO_TEST_FILES=test_behaviour.jl` | ❌ W0 | ⬜ pending |
| ACTOR-04 | Settlement effects on IEEE-13: `ledger_residual == 0.0`, the actor-profit line equals `Σ m·load`, and the rebound ratio is present. | integration | `TSODSO_TEST_FILES=test_actor_settlement.jl` | ❌ W0 | ⬜ pending |
| ACTOR-04 | IEEE-123 sweep CSV schema is checked, and a reference point reproduces. | slow | `TSODSO_TEST_SET=all TSODSO_TEST_FILES=test_actor_sweep.jl` | ❌ W0 | ⬜ pending |
| All | Exact export set, JET ratchet, scripts index and docs registration. | repo gates | `TSODSO_TEST_FILES=test_exports.jl`; `julia --project=. scripts/jet_check.jl --selftest`; `python3 .github/scripts/check_scripts_index.py` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_actor_objective.jl`, `test/test_actor_portfolio.jl`, `test/test_behaviour.jl`, `test/test_actor_settlement.jl` and `test/test_actor_sweep.jl` are created by the plans that own them.
- [ ] Pre-phase golden digests of the default `solve_admm` result fields and the default `build_population` are captured BEFORE any change under `src/`. Use the FNV fold pattern from `test_flex_population.jl`.
- [ ] Tolerances are measured before they are pinned (3 seeds, 3x the observed max):
  - centralized pass-through gap;
  - ADMM-vs-centralized profit cross-validation gap;
  - split-bus equivalence gap;
  - ΔW ≥ 0 slack.
- [ ] Framework install: none.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| The literate page reads correctly: the wedge semantics carry the first-welfare-theorem disclaimer, and the per-device FIT baseline is labelled honestly. | ACTOR-02/04 | Prose fidelity | Review `docs/literate/` for the actor/behaviour page after the docs build. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 300s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
