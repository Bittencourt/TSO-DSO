---
phase: 22
slug: stochastic-pv-demand-uncertainty
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-08-09
approved: 2026-08-09
---

# Phase 22 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` (stdlib) for per-task quick checks; TestItems 1.0.0 / TestItemRunner 1.1.5 (test-only, discovered via `test/runtests.jl`) for the real `@testitem` suite |
| **Config file** | `test/runtests.jl` (TestItemRunner entrypoint; no separate config file) |
| **Quick run command** | A plain `julia --project=. -e '...'` script using `Test` (NOT TestItemRunner) that inlines the fixture construction directly (mirrors `Phase22Fixtures`' own shape once 22-01 lands) and asserts the same behavioral claim(s) as the corresponding `@testitem`(s). Per this repo's MANDATORY testing constraint: **never** `julia --project=test -e '...@run_package_tests...'`, and **never** TestItemRunner invoked under `--project=.` for a quick loop. One such command is embedded in each per-task `<verify><automated>` across 22-01..22-05's PLAN.md files. |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (the real `test/runtests.jl` entrypoint, runs every `@testitem` including the new ones; ~13-20 min per this project's documented Phase-21 baseline: 2685 passed / 0 failed / 3 pre-existing broken; run in background) |
| **Estimated runtime** | Quick command: <20s per task. Full suite: ~13-20 min (run once, only as the phase-closing gate in plan 22-05 Task 2 — not run per task or per wave). |

---

## Sampling Rate

- **After every task commit:** Run that task's own plain-`Test.jl` quick command (`<20s`)
- **After every plan wave:** Re-run each wave's task-level `<verify>` inline scripts (idempotent); defer `@testitem` execution to the phase-closing gate
- **Before `/gsd:verify-work`:** Full suite must be green — `julia --project=. -e 'import Pkg; Pkg.test()'` (plan 22-05 Task 2 is the ONLY plan in this phase permitted to run it, per the "reserve the full suite for the final acceptance plan" constraint), `0` failed, exactly `3` pre-existing broken, `passed` = pre-phase baseline (2685) + this phase's tallied new-`@testitem` count
- **Max feedback latency:** 20 seconds for the per-task quick command; the full-suite gate is intentionally infrequent (once, at phase close) because it is a genuinely ~13-20 min background run — the SAME discipline Phases 20 and 21 already established

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 22-01-01 | 01 | 1 | STOCH-01 | T-22-01 / T-22-02 | `Scenario` gains additive `stoch_S`/`stoch_probabilities`/`stoch_H_oos` `@kwdef` fields with `ArgumentError` construction-time validation (band checks, length/sum/positivity checks, default-uniform sentinel resolution); byte-identical default for every existing `:centralized`/`:admm`/`mpc_*` path | unit | plain Test.jl quick command (22-01-PLAN.md Task 1 `<verify>`) | ❌ Wave 0 — modifies `src/experiments/Scenario.jl` | ⬜ pending |
| 22-01-02 | 01 | 1 | STOCH-01 | — | `Phase22Fixtures` (`stoch_feeder`/`stoch_scenario_aggregators`/`stoch_lambda0`/`temperature_profile`) constructs a Deferrable-free 2-bus fixture that solves `OPTIMAL` and exact via `solve_welfare` | unit | plain Test.jl quick command (22-01-PLAN.md Task 2 `<verify>`) | ❌ Wave 0 — new `test/fixtures_phase22.jl` | ⬜ pending |
| 22-02-01 | 02 | 2 | STOCH-01, STOCH-02 | T-22-03 / T-22-04 | `build_stochastic_welfare` assembles S independently-`contribute!`'d, `JuMP.unregister`-decoupled scenario blocks tied by battery nonanticipativity constraints; degenerate S=1 reproduces `solve_welfare` (D-08); de-scaled per-scenario DADP matches deterministic baseline on 2-identical-scenario construction (D-05); per-scenario PF-04 gate never aggregated (D-06); structural-congruence + probability guards each throw `ArgumentError`; `num_variables`/`num_constraints` measured (not assumed) for S=1,3,5 on the actual small CI fixture | unit/regression | plain Test.jl quick command (22-02-PLAN.md Task 1 `<verify>`, includes the S=1,3,5 capacity print) | ❌ Wave 0 — new `src/models/stochastic_welfare.jl` | ⬜ pending |
| 22-02-02 | 02 | 2 | STOCH-01, STOCH-02 | T-22-03 | Three `@testitem`s: non-uniform probabilities genuinely change the objective (D-04); a scanned extreme `pv_scale` trips `assert_socp_exact!` on one scenario while the SAME scenario solved alone still passes (D-06, "never aggregated"); structural-mismatch guard | unit/regression | plain Test.jl quick command (22-02-PLAN.md Task 2 `<verify>`, `pv_scale` scan) | ❌ Wave 0 — new `test/test_stochastic_welfare.jl` | ⬜ pending |
| 22-03-01 | 03 | 3 | STOCH-03 | T-22-05 | `StochasticOosHarness`/`build_stochastic_oos_harness`/`solve_stochastic_oos_step!` build a single-scenario, Parameter-pinned model ONCE; three heterogeneous re-solve cycles (different pins + PV/demand slides) leave `num_variables`/`num_constraints` unchanged (build-once invariant); solved `value.(p_ch)` equals the pinned value exactly; boundary guards throw `ArgumentError` | unit | plain Test.jl quick command (22-03-PLAN.md Task 1 `<verify>`) | ✅ extends `src/models/stochastic_welfare.jl` | ⬜ pending |
| 22-03-02 | 03 | 3 | STOCH-03 | T-22-05 / T-22-06 | Three `@testitem`s: build-once invariant across heterogeneous re-solves, pin is genuinely binding (not vacuous — changing the pin changes the solved value), boundary guards | unit | plain Test.jl quick command (22-03-PLAN.md Task 2 `<verify>`) | ❌ Wave 0 — new `test/test_stochastic_oos_harness.jl` | ⬜ pending |
| 22-04-01 | 04 | 4 | STOCH-03 | T-22-06 | `run_stochastic(s::Scenario)` materializes S in-sample + H held-out disjoint-seeded scenarios (`:stoch_insample_*` / `:stoch_oos_*` tag families), pins the harness ONCE to the in-sample-solved battery schedule, re-solves per held-out scenario, reports `welfare_gap` (D-09); two same-seed calls return `==`-identical results (INFRA-04). **Checker revision 1 fix: verify script now constructs `Scenario(...T=9...)` (was `T=6`, which throws `ArgumentError` at population materialization for `:ieee13`'s Deferrable device below `T=9` — RESEARCH.md Pitfall 3); `expected_dadp` length assertion corrected to `9` to match** | unit/integration | plain Test.jl quick command (22-04-PLAN.md Task 1 `<verify>`, `T=9`) | ❌ Wave 0 — new `src/experiments/run_stochastic.jl` | ⬜ pending |
| 22-04-02 | 04 | 4 | STOCH-03 | T-22-06 / T-22-07 | Three `@testitem`s: in-sample/held-out seed families are provably disjoint, same-seed reproducibility, D-11 measurement-before-golden ordering (repeated-run stability assertion textually precedes the one pinned golden literal). **Checker revision 1 fix: verify script now constructs `Scenario(...T=9...)` (was `T=6`, same Pitfall-3 fix as 22-04-01)** | regression | plain Test.jl quick command (22-04-PLAN.md Task 2 `<verify>`, `T=9`) | ❌ Wave 0 — new `test/test_run_stochastic.jl` | ⬜ pending |
| 22-05-01 | 05 | 5 | STOCH-04 | T-22-08 | Live-executed literate page (`docs/literate/stochastic_pv_demand.jl`) builds a `Scenario` (`T=9`, non-uniform `stoch_probabilities`), calls `run_stochastic` once, shows per-scenario DADPs (primary), expected DADP (derived summary), per-scenario SOCP exactness, and the out-of-sample welfare gap; wired into `docs/make.jl` | integration | `run_stochastic`-only quick command (22-05-PLAN.md Task 1 `<verify>`); full Documenter build (`julia --project=docs docs/make.jl`) is a separate, slower invocation, not run by this inline check | ❌ Wave 0 — new `docs/literate/stochastic_pv_demand.jl` | ⬜ pending |
| 22-05-02 | 05 | 5 | STOCH-01..04 | T-22-09 | Full suite green: `0` failed, exactly `3` pre-existing broken, `passed` = baseline (2685) + this phase's tallied new-`@testitem` count; Documenter build (`checkdocs = :exports`) completes without error | full-suite | `julia --project=. -e 'import Pkg; Pkg.test()'` (22-05-PLAN.md Task 2 `<verify>`) | n/a (acceptance gate) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/fixtures_phase22.jl` — new `@testmodule Phase22Fixtures`, plan 22-01 Task 2 (the phase's Deferrable-free small CI substrate)
- [ ] `test/test_stochastic_welfare.jl` — new file, plan 22-02 Task 2 (STOCH-01/STOCH-02, non-uniform weighting + per-scenario never-aggregated exactness gate)
- [ ] `test/test_stochastic_oos_harness.jl` — new file, plan 22-03 Task 2 (STOCH-03, build-once invariant + pin correctness)
- [ ] `test/test_run_stochastic.jl` — new file, plan 22-04 Task 2 (STOCH-03, seed disjointness + reproducibility + D-11 measurement-before-golden)

*Existing infrastructure (`test/runtests.jl`'s `TestItemRunner.@run_package_tests`, plus `src/experiments/Scenario.jl` extended in-place by plan 22-01 Task 1 and `src/models/stochastic_welfare.jl` extended in-place by plan 22-03 Task 1) covers discovery for every new item; no changes to `test/runtests.jl` are required.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.* The literate page (plan 22-05) is built and
checked automatically via `julia --project=docs docs/make.jl`; there is no behavior in this
phase that requires a human-only manual check (no UI, no external service, no visual review).
The per-scenario DADP spread and the out-of-sample welfare gap in the literate page are
LIVE-COMPUTED, honestly-reported quantities — not a manual verification step, but an automated
build artifact per D-11's discipline.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 20s (per-task quick commands; the full-suite gate is an intentional,
      documented exception run exactly once, at phase close, matching this project's own
      `~13-20 min` Phase-21 baseline)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-08-09 (checker revision 1 — populated from `22-RESEARCH.md`'s
"Validation Architecture" section and the final 22-01..22-05 PLAN.md files, including plan
22-04's `T=6` → `T=9` verify-script fix for the Deferrable small-T pitfall and the corresponding
`expected_dadp` length correction).
