---
phase: 33
slug: shared-abstractions-feeder-balance-model-context
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-10-03
---

# Phase 33 — Validation Strategy

> Source: 33-RESEARCH.md "Validation Architecture".

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems/TestItemRunner (`@testitem`), Aqua |
| **Config file** | `test/runtests.jl`, `test/Project.toml` |
| **Quick run command** | `JULIA_LOAD_PATH="@:.:test:@stdlib" julia --project=. -e 'using TestItemRunner; TestItemRunner.run_tests(joinpath(pwd(),"test"); filter = ti -> endswith(ti.filename, "test_<name>.jl"))'` |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` — DETACHED, owned by the orchestrator |
| **Estimated runtime** | ~60–240 s per targeted file; full suite ~30 min |

---

## Sampling Rate

- **After every task commit:** targeted test file(s) for the touched module
- **After every plan wave:** affected family (welfare/linear/mpc/stochastic/dso/admm/exactness/pricing/mesh/restricted)
- **Before `/gsd:verify-work`:** full suite ≥ 31782 passes, 0 failed / 0 errored / 5 broken; docs build exit 0; grep gates zero
- **Max feedback latency:** ~240 seconds

---

## Per-Task Verification Map

| Req | Behavior | Test Type | Automated Command | File Exists | Status |
|-----|----------|-----------|-------------------|-------------|--------|
| ARCH-03 | `Feeder`/`MeshedFeeder <: AbstractFeeder`; constructors still gate | unit | quick-run `test_feeder.jl`, `test_mesh_feeder.jl` | partial | ⬜ pending |
| ARCH-03 | invalid pairs (Restricted/Convex/LinDistFlow × MeshedFeeder) throw `ArgumentError`; DC/AC/MeshedFlow on meshed still solve | unit | quick-run `test_abstract_feeder.jl` | ❌ W0 | ⬜ pending |
| ARCH-04 | `close_balance!` contract (tuple, registration, anonymous names, label error text, reactive=false) | unit | quick-run `test_close_balance.jl` | ❌ W0 | ⬜ pending |
| ARCH-04 | constraint-order fingerprint unchanged | golden | quick-run `test_close_balance.jl` | ❌ W0 | ⬜ pending |
| ARCH-04 | five sites bit-identical | golden | welfare/linear/mpc_window/stochastic/dso/admm/knife-edge files | ✅ | ⬜ pending |
| ARCH-07 | typed fields + incremental fill; traits `has_branch_current`/`has_reactive` truth tables (6 formulations) | unit | quick-run `test_model_context_traits.jl`, `test_context.jl` | ❌ W0 | ⬜ pending |
| ARCH-07 | grep gate: zero `meta[:pf_vars|:T|:feeder|:objective|:agg_device_vars]` in src/test/docs/literate/scripts | source-scan | grep-gate testitem | ❌ W0 | ⬜ pending |
| all | docs build `checkdocs = :exports`; Aqua | quality | docs build; full suite | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_abstract_feeder.jl`
- [ ] `test/test_close_balance.jl` (incl. constraint-order fingerprint captured BEFORE migration)
- [ ] `test/test_model_context_traits.jl`
- [ ] grep-gate testitem (added in the last migration plan)

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 240s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
