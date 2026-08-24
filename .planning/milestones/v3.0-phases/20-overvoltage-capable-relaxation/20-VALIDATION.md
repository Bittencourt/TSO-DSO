---
phase: 20
slug: overvoltage-capable-relaxation
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-08-08
approved: 2026-08-08
---

# Phase 20 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` (stdlib) for per-task quick checks; TestItems 1.0.0 / TestItemRunner 1.1.5 (test-only, discovered via `test/runtests.jl`) for the real `@testitem` suite |
| **Config file** | `test/runtests.jl` (TestItemRunner entrypoint; no separate config file) |
| **Quick run command** | A plain `julia --project=. -e '...'` script using `Test` (NOT TestItemRunner) that inlines the EXACT-04 fixture construction verbatim (same recipe as `docs/literate/ac_oracle.jl` and `test/fixtures_phase4.jl`'s `Phase4Fixtures.high_pv_feeder`/`build_high_pv_aggregators(feeder; pv_scale=1.2)`) and asserts the same behavioral claim(s) as the corresponding `@testitem`(s). One such command is embedded in each per-task `<verify><automated>` in 20-01..20-04's PLAN.md files. |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (the real `test/runtests.jl` entrypoint, runs every `@testitem` including the new ones; ~12–20 min per this project's documented baseline; run in background) |
| **Estimated runtime** | Quick command: <20s per task. Full suite: ~12-20 min (run once per plan wave, at the closing `<verification>` gate, not per task). |

**CORRECTION (checker revision 1, 2026-08-08):** the originally-planned per-task verify command
(`julia --project=. -e 'using TestItemRunner; include("test/test_restricted_branch_flow.jl")'`) is
BROKEN on two independent counts: (a) `TestItemRunner` is a test-only dependency (see
`test/Project.toml`) — `--project=.` cannot resolve it (`ArgumentError: Package TestItemRunner not
found`); (b) even under `--project=test`, a bare `include()` of a file containing `@testitem` blocks
executes ZERO tests (exits 0, no output) — `@testitem` bodies only run via
`TestItemRunner.runtests`/`@run_package_tests`, i.e. through `Pkg.test()`. Both plain-script fixture
construction (empirically verified live against this repo, `mingap = 0.0` and `cost_ac =
-922.9416693226153` reproduced) and the `Pkg.test()`-only path for actual `@testitem` execution are
confirmed working. All 20-01..20-04 PLAN.md `<verify>` and `<verification>` blocks were revised
accordingly.

---

## Sampling Rate

- **After every task commit:** Run the task's own plain-Test.jl quick command (`<10s`)
- **After every plan wave:** Run `julia --project=. -e 'import Pkg; Pkg.test()'` (background, ~12-20 min — this is the plan's closing `<verification>` command in 20-01..20-04, and Task 2 of 20-05)
- **Before `/gsd:verify-work`:** Full suite must be green (`Pkg.test()`, pass count ≥ pre-phase baseline + 7 new `test_restricted_branch_flow.jl` items)
- **Max feedback latency:** 20 seconds for the per-task quick command; the full-suite gate is intentionally infrequent (once per plan, not per task) because it is a genuinely ~12-20 min background run — this is the SAME discipline `docs/literate/ac_oracle.jl`'s own phase (15) validation used.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 20-01-01 | 01 | 1 | OVR-01 | T-20-02 | `v[j,t] - v̂[j,t] >= -1e-9` on the EXACT-04 fixture (RESEARCH.md Assumption A1 spot-check) | unit | plain Test.jl quick command (20-01-PLAN.md Task 1 `<verify>`) | ✅ Wave 0 creates `test/test_restricted_branch_flow.jl` | ⬜ pending |
| 20-01-02 | 01 | 1 | OVR-01 | T-20-02 | `recover_lossfree_shadow_voltage` exists, Lemma 1 (`v̂_GL ≥ v`) holds, `ε_measured > 0` | unit | plain Test.jl quick command (20-01-PLAN.md Task 2 `<verify>`) | ✅ same file, plus `src/models/ac_oracle.jl` | ⬜ pending |
| 20-02-01 | 02 | 2 | OVR-01 | T-20-04 | `RestrictedBranchFlow` exported, `problem_class(::RestrictedBranchFlow) isa SOCP` | unit | `@assert isdefined(...)` one-liner (20-02-PLAN.md Task 1 `<verify>`) | ✅ `src/powerflow/RestrictedBranchFlow.jl` | ⬜ pending |
| 20-02-02 | 02 | 2 | OVR-01 | T-20-06 | `RestrictedBranchFlow` passes `assert_socp_exact!` at DEFAULT tolerance on EXACT-04; plain `ConvexBranchFlow`'s own inexactness unchanged | unit/regression | plain Test.jl quick command (20-02-PLAN.md Task 2 `<verify>`) | ✅ same file | ⬜ pending |
| 20-03-01 | 03 | 3 | OVR-02 | T-20-07 | `assert_restriction_exact!` exists, `price_provenance` stashed, own-measured `rtol`/`atol` (not copied from `assert_ac_exact!`'s defaults) | unit | `@assert isdefined(...)` one-liner (20-03-PLAN.md Task 1 `<verify>`) | ✅ `src/models/restriction_exactness.jl` | ⬜ pending |
| 20-03-02 | 03 | 3 | OVR-02 | T-20-08 | Certificate positive-path (`ac_feasible`, `optimality_loss`) + throws on structural T-mismatch | unit | plain Test.jl quick command (20-03-PLAN.md Task 2 `<verify>`) | ✅ same file | ⬜ pending |
| 20-04-01 | 04 | 4 | OVR-03 | T-20-11 | `ac_dual_fallback_price` exists, never references the certificate function (D-09 discipline) | unit | `@assert isdefined(...)` one-liner (20-04-PLAN.md Task 1 `<verify>`) | ✅ `src/models/ac_dual_fallback.jl` | ⬜ pending |
| 20-04-02 | 04 | 4 | OVR-03 | T-20-10 | Fallback `price_status = :local_ac_dual`, 2-seed cost agreement, all-finite `dadp` | unit | plain Test.jl quick command (20-04-PLAN.md Task 2 `<verify>`) + quarantined spike | ✅ same file, plus `.planning/spikes/004-ovr-fallback-multistart/` | ⬜ pending |
| 20-05-01 | 05 | 5 | OVR-04 | T-20-13 / T-20-14 | Literate page builds live, every number recomputed at doc-build time, Gan-Low condition subsection present | integration | `julia --project=docs docs/make.jl` (20-05-PLAN.md Task 1 `<verify>`) | ✅ `docs/literate/restricted_branch_flow.jl` | ⬜ pending |
| 20-05-02 | 05 | 5 | OVR-01..04 | T-20-15 | Full suite green, 0 new failures, pass count ≥ 2520 | full-suite | `julia --project=. -e 'import Pkg; Pkg.test()'` (20-05-PLAN.md Task 2 `<verify>`) | n/a (acceptance gate) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_restricted_branch_flow.jl` — new file, created by plan 20-01 Task 1 (first `@testitem`); grows to 7 `@testitem`s by the end of plan 20-04. No separate Wave-0-only stub plan is needed: plan 20-01 Task 1 IS the Wave 0 creation, immediately followed by its own real (not stub) assertion, per this phase's "blocking analytic spot-check before any restriction code exists" design (RESEARCH.md).
- [ ] `.planning/spikes/004-ovr-fallback-multistart/` — new quarantined spike directory, created by plan 20-04 Task 2 (not CI-gated; supporting evidence per D-11).

*Existing infrastructure (`test/runtests.jl`'s `TestItemRunner.@run_package_tests`, `test/fixtures_phase4.jl`'s `Phase4Fixtures` `@testmodule`) covers discovery and fixture-building for the new file; no changes to either are required.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.* The literate page (plan 20-05) is built and
checked automatically via `julia --project=docs docs/make.jl`; there is no behavior in this phase
that requires a human-only manual check (no UI, no external service, no visual review).

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 20s (per-task quick commands; full-suite gate is an intentional, documented exception run once per plan, matching this project's own `~12-20 min` baseline)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-08-08 (checker revision 1 — see `20-01..20-04-PLAN.md`'s corrected `<verify>`/`<verification>` blocks and `20-RESEARCH.md`'s corrected Quick run command entry)
