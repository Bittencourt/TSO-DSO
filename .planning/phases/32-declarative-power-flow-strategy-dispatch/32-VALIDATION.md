---
phase: 32
slug: declarative-power-flow-strategy-dispatch
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-10-03
---

# Phase 32 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Source: 32-RESEARCH.md "Validation Architecture".

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems/TestItemRunner (`@testitem`), Aqua |
| **Config file** | `test/runtests.jl`, `test/Project.toml` |
| **Quick run command** | `JULIA_LOAD_PATH="@:.:test:@stdlib" julia --project=. -e 'using TestItemRunner; TestItemRunner.run_tests(joinpath(pwd(),"test"); filter = ti -> endswith(ti.filename, "test_<name>.jl"))'` |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` — launched DETACHED with a done-marker (memory: background-suite-orphan-race) |
| **Estimated runtime** | ~120 s per targeted file; full suite 16–36 min |

---

## Sampling Rate

- **After every task commit:** quick-run the touched test file(s)
- **After every plan wave:** `test_experiments`, `test_mpc_loop`, `test_run_stochastic`, `test_admm_knifeedge_canary`, `test_scenario_pf`, `test_strategies` (parallel, ~4 min)
- **Before `/gsd:verify-work`:** full suite green — 0 failed / 0 errored / 5 broken, passes ≥ 31260
- **Max feedback latency:** ~180 seconds

---

## Per-Task Verification Map

| Req | Behavior | Test Type | Automated Command | File Exists | Status |
|-----|----------|-----------|-------------------|-------------|--------|
| ARCH-01 | `Scenario(pf=…)` honoured for 4 selectors; `build_powerflow` types/options; default identical to `ConvexBranchFlow()` | integration | quick-run `test_scenario_pf.jl` | ❌ W0 | ⬜ pending |
| ARCH-01 | `:lindistflow`/`:ac` → `isnan(exact_maxgap)`, no throw; restricted → finite | integration | quick-run `test_scenario_pf.jl` | ❌ W0 | ⬜ pending |
| ARCH-01 | invalid selectors/options & strategy×pf combos throw `ArgumentError` | unit | quick-run `test_scenario_pf.jl` | ❌ W0 | ⬜ pending |
| ARCH-02 | strategy constructors validate + keep defaults | unit | quick-run `test_strategies.jl` | ❌ W0 | ⬜ pending |
| ARCH-02 | `TSODSO.run(strategy, s)` returns common-shape `ScenarioResult`; MPC/Stochastic values equal legacy NamedTuples | integration | quick-run `test_strategies.jl` | ❌ W0 | ⬜ pending |
| ARCH-02 | legacy kwargs map identically; foreign knob throws; no flat strategy fields on `Scenario` | unit | quick-run `test_strategies.jl` | ❌ W0 | ⬜ pending |
| ARCH-02 | `scenario_filename` distinct/short/deterministic; JLD2 round-trip; mixed-strategy sweep collate | integration | quick-run `test_experiments.jl` | partial | ⬜ pending |
| ARCH-01/02 | numeric goldens bit-identical (knife-edge, stochastic, MPC, repro) | integration | quick-run the 4 golden files | ✅ | ⬜ pending |
| ARCH-02 | Aqua + docs `checkdocs = :exports` | quality | full suite; docs build | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_strategies.jl` — ARCH-02 strategy/dispatch/legacy/flat-field tests
- [ ] `test/test_scenario_pf.jl` — ARCH-01 pf selection + guards
- [ ] `test/test_experiments.jl` — update WR-01/WR-02 items, mixed-strategy sweep
- [ ] migrate `test_mpc_loop.jl` / `test_run_stochastic.jl` Scenario constructions (numeric asserts untouched)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Literate docs execute | ARCH-01/02 | docs env, not in Pkg.test | run `docs/literate/{experiments,mpc_rolling_horizon,stochastic_pv_demand}.jl` under the docs env |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 180s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
