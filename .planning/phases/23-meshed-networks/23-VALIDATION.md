---
phase: 23
slug: meshed-networks
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-08-10
approved: 2026-08-10
---

# Phase 23 -- Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` (stdlib) for per-task quick checks; TestItems 1.0.0 / TestItemRunner 1.1.5 (test-only, discovered via `test/runtests.jl`) for the real `@testitem` suite |
| **Config file** | `test/runtests.jl` (TestItemRunner entrypoint; no separate config file) |
| **Quick run command** | A plain `julia --project=. -e '...'` script using `Test` (NOT TestItemRunner) that inlines the fixture construction directly (mirrors `Phase23Fixtures`' own shape once plan 23-02 lands) and asserts the same behavioral claim(s) as the corresponding `@testitem`(s). Per this repo's MANDATORY testing constraint: **never** `julia --project=test -e '...@run_package_tests...'`, and **never** TestItemRunner invoked under `--project=.` for a quick loop, and **never** a bare `include()` of an `@testitem`/`@testmodule` file. One such command is embedded in each per-task `<verify><automated>` across 23-01..23-04's PLAN.md files. |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (the real `test/runtests.jl` entrypoint, runs every `@testitem` including the new ones; ~12-20 min per the phase's documented green reference: 2752 passed / 0 failed / 3 pre-existing errored / 3 broken, +known-false Aqua pair on drifted checkouts, +the documented D-06 stochastic sandbox-skew diagnostic; run in background) |
| **Estimated runtime** | Quick command: <20s per task. Full suite: ~12-20 min (run once, only as the phase-closing gate in plan 23-04 Task 2 -- not run per task or per wave). |

---

## Sampling Rate

- **After every task commit:** Run that task's own plain-`Test.jl` quick command (<20s)
- **After every plan wave:** Re-run each wave's task-level `<verify>` inline scripts (idempotent); defer `@testitem` execution to the phase-closing gate
- **Before `/gsd:verify-work`:** Full suite must be green -- `julia --project=. -e 'import Pkg; Pkg.test()'` (plan 23-04 Task 2 is the ONLY plan in this phase permitted to run it, per the "reserve the full suite for the final acceptance plan" constraint), `0` failed, pre-existing errored/broken counts unchanged from the documented green reference, `passed` = pre-phase baseline (2752) + this phase's tallied new-`@testitem` count
- **Max feedback latency:** 20 seconds for the per-task quick command; the full-suite gate is intentionally infrequent (once, at phase close) because it is a genuinely ~12-20 min background run -- the SAME discipline Phases 20/21/22 already established

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 23-01-01 | 01 | 1 | MESH-01 | T-23-01 | `assert_connected` accepts a genuine loop (nB > N-1) and rejects every malformed input `assert_radial` also rejects (minus the tree-count theorem) | unit | plain Test.jl quick command (23-01-PLAN.md Task 1 `<verify>`) | ❌ Wave 0 -- new `src/data/mesh_topology.jl` | ⬜ pending |
| 23-01-02 | 01 | 1 | MESH-01 | T-23-01 / T-23-02 | `MeshedFeeder` constructs on a cyclic edge list `Feeder` rejects on the SAME edge list (D-09 regression); exposes `buses`/`branches`/`root` identically to `Feeder` | unit/regression | plain Test.jl quick command (23-01-PLAN.md Task 2 `<verify>`) | ❌ Wave 0 -- new `src/data/MeshedFeeder.jl` | ⬜ pending |
| 23-01-03 | 01 | 1 | MESH-01 | T-23-02 | `test/test_mesh_feeder.jl` `@testitem` exercises the structural cases + D-09 regression, ready for the full suite | unit/regression | plain Test.jl quick command (23-01-PLAN.md Task 3 `<verify>`) | ❌ Wave 0 -- new `test/test_mesh_feeder.jl` | ⬜ pending |
| 23-02-01 | 02 | 2 | MESH-02 | T-23-03 | `MeshedFlow.contribute!` delegates byte-faithfully to `ConvexBranchFlow.contribute!` (identical objective/dadp on a radial regression fixture); `problem_class(::MeshedFlow) = SOCP()` | unit/regression | plain Test.jl quick command (23-02-PLAN.md Task 1 `<verify>`) | ❌ Wave 0 -- new `src/powerflow/MeshedFlow.jl` | ⬜ pending |
| 23-02-02 | 02 | 2 | MESH-02 | T-23-04 | `Phase23Fixtures` (3-bus triangle, `:uniform`/`:heterogeneous` profiles, asymmetric pinned loads) solves OPTIMAL and exact via `MeshedFlow` + `solve_welfare` on BOTH profiles | unit | plain Test.jl quick command (23-02-PLAN.md Task 2 `<verify>`) | ❌ Wave 0 -- new `test/fixtures_phase23.jl` | ⬜ pending |
| 23-02-03 | 02 | 2 | MESH-02 | T-23-03 | `test/test_mesh_flow.jl` `@testitem` exercises both profiles' solves + the D-09-adjacent Feeder-throw defense-in-depth | unit/regression | plain Test.jl quick command (23-02-PLAN.md Task 3 `<verify>`) | ❌ Wave 0 -- new `test/test_mesh_flow.jl` | ⬜ pending |
| 23-03-01 | 03 | 3 | MESH-03 | T-23-05 / T-23-06 | `certify_angle_recoverable!` distinguishes `:uniform` (recoverable, angles returned, `:angle_certified`) from `:heterogeneous` (unrecoverable, `angles===nothing`, `:angle_unrecoverable`, warns not throws under default `report=true`); tolerances measured fresh on `Phase23Fixtures`, never copied | unit/regression | plain Test.jl quick command (23-03-PLAN.md Task 1 `<verify>`, includes the residual-ordering print) | ❌ Wave 0 -- new `src/models/mesh_angle_certificate.jl` | ⬜ pending |
| 23-03-02 | 03 | 3 | MESH-03 | T-23-05 / T-23-06 | `test/test_mesh_angle_certificate.jl` `@testitem`: both profiles' verdicts, `report=false` strict-mode throw, provenance-never-fabricated check | unit/regression | plain Test.jl quick command (23-03-PLAN.md Task 2 `<verify>`) | ❌ Wave 0 -- new `test/test_mesh_angle_certificate.jl` | ⬜ pending |
| 23-04-01 | 04 | 4 | MESH-06 | T-23-07 | Live-executed literate page (`docs/literate/meshed_reactive_price.jl`) builds both loop profiles, solves via `MeshedFlow`, certifies via `certify_angle_recoverable!`, demonstrates the 4Q-BESS reactive price via a real `:balance_q` dual; wired into `docs/make.jl` | integration | `MeshedFlow`/`certify_angle_recoverable!`/`FourQuadBESS`-only quick command (23-04-PLAN.md Task 1 `<verify>`); full Documenter build is a separate, slower invocation, not run by this inline check | ❌ Wave 0 -- new `docs/literate/meshed_reactive_price.jl` | ⬜ pending |
| 23-04-02 | 04 | 4 | MESH-01..03,06 | T-23-08 | Full suite green: `0` failed, pre-existing errored/broken counts unchanged from the documented baseline, `passed` = baseline + this phase's tallied new-`@testitem` count; Documenter build (`checkdocs = :exports`) completes without error | full-suite | `julia --project=. -e 'import Pkg; Pkg.test()'` (23-04-PLAN.md Task 2 `<verify>`) | n/a (acceptance gate) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_mesh_feeder.jl` -- new file, plan 23-01 Task 3 (MESH-01, D-09 regression)
- [ ] `test/fixtures_phase23.jl` -- new `@testmodule Phase23Fixtures`, plan 23-02 Task 2 (the phase's committed loop fixture, both impedance profiles)
- [ ] `test/test_mesh_flow.jl` -- new file, plan 23-02 Task 3 (MESH-02)
- [ ] `test/test_mesh_angle_certificate.jl` -- new file, plan 23-03 Task 2 (MESH-03, D-05 strict-mode exercise)

*Existing infrastructure (`test/runtests.jl`'s `TestItemRunner.@run_package_tests`) covers
discovery for every new item; no changes to `test/runtests.jl` are required.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.* The literate page (plan 23-04) is built
and checked automatically via `julia --project=docs docs/make.jl`; there is no behavior in
this phase that requires a human-only manual check (no UI, no external service, no visual
review). The angle-recoverability certificate's two verdicts and the 4Q-BESS reactive price
are LIVE-COMPUTED, honestly-reported quantities -- not a manual verification step, but an
automated build artifact per D-10's discipline.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 20s (per-task quick commands; the full-suite gate is an intentional,
      documented exception run exactly once, at phase close, matching this project's own
      ~12-20 min Phase-20/21/22 baseline)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-08-10 -- populated from `23-RESEARCH.md`'s "Validation
Architecture" section and the final 23-01..23-04 PLAN.md files during phase planning.
