---
phase: 21
slug: mpc-rolling-horizon-real-time-pricing
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-08-09
approved: 2026-08-09
---

# Phase 21 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` (stdlib) for per-task quick checks; TestItems 1.0.0 / TestItemRunner 1.1.5 (test-only, discovered via `test/runtests.jl`) for the real `@testitem` suite |
| **Config file** | `test/runtests.jl` (TestItemRunner entrypoint; no separate config file) |
| **Quick run command** | A plain `julia --project=. -e '...'` script using `Test` (NOT TestItemRunner) that inlines the fixture construction directly (mirrors `test/fixtures_phase4.jl`'s `Phase4Fixtures.high_pv_feeder`/`build_high_pv_aggregators` shape, or the new `Phase21Fixtures` shape once 21-03 lands) and asserts the same behavioral claim(s) as the corresponding `@testitem`(s). Per this repo's MANDATORY testing constraint: **never** `julia --project=test -e '...@run_package_tests...'`, and **never** TestItemRunner invoked under `--project=.` for a quick loop. One such command is embedded in each per-task `<verify><automated>` across 21-01..21-06's PLAN.md files. |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (the real `test/runtests.jl` entrypoint, runs every `@testitem` including the new ones; ~13-18 min per this project's documented Phase-20 baseline: 2563 passed / 0 failed / 3 pre-existing broken; run in background) |
| **Estimated runtime** | Quick command: <20s per task. Full suite: ~13-18 min (run once per plan wave at most, and always as the phase-closing gate in plan 21-06 — not run per task). |

---

## Sampling Rate

- **After every task commit:** Run that task's own plain-`Test.jl` quick command (`<20s`)
- **After every plan wave:** Re-run each wave's task-level `<verify>` inline scripts (idempotent); defer `@testitem` execution to the phase-closing gate
- **Before `/gsd:verify-work`:** Full suite must be green — `julia --project=. -e 'import Pkg; Pkg.test()'` (plan 21-06 Task 2 is the ONLY plan in this phase permitted to run it, per the "reserve the full suite for the final acceptance plan" constraint), `0` failed, exactly `3` pre-existing broken, `passed` = pre-phase baseline (2563) + this phase's tallied new-`@testitem` count
- **Max feedback latency:** 20 seconds for the per-task quick command; the full-suite gate is intentionally infrequent (once, at phase close) because it is a genuinely ~13-18 min background run — the SAME discipline Phase 20's own validation used

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 21-01-01 | 01 | 1 | MPC-01 | T-21-01 | `PVBattery`/`Thermostatic.contribute!` return genuine `Parameter`-backed `soc0`/`Tin0`/`Ppv_param`/`Tout_param`; byte-identical default; `pv_used` bound moved to a constraint | unit | plain Test.jl quick command (21-01-PLAN.md Task 1 `<verify>`) | ❌ Wave 0 — modifies `src/devices/PVBattery.jl`/`Thermostatic.jl` | ⬜ pending |
| 21-01-02 | 01 | 1 | MPC-01 | T-21-01 | `FourQuadBESS.soc0` and `Aggregator.Pdc_param` genuinely `Parameter`-backed; `:Rp`/`:Rq` residual writes read `Pdc_param`, byte-identical default | unit | plain Test.jl quick command (21-01-PLAN.md Task 2 `<verify>`) | ❌ Wave 0 — modifies `src/devices/FourQuadBESS.jl`/`Aggregator.jl` | ⬜ pending |
| 21-01-03 | 01 | 1 | MPC-01 | T-21-02 | Four new permanent `@testitem`s (one per widened file) proving Parameter defaults + no-rebuild re-solve mechanics | unit | plain Test.jl quick command (21-01-PLAN.md Task 3 `<verify>`); persistent `@testitem`s deferred to 21-06 | ❌ Wave 0 — new items in `test/test_pvbattery.jl`/`test_thermostatic.jl`/`test_fourquadbess.jl`/`test_aggregator.jl` | ⬜ pending |
| 21-02-01 | 02 | 1 | MPC-03 | T-21-04 | `MpcTrace`/`record!`/`max_jump`/`mean_jump`/`any_cert_failed` exist; sequential-`k` guard mirrors `AdmmResiduals` | unit | plain Test.jl quick command (21-02-PLAN.md Task 1 `<verify>`) | ❌ Wave 0 — new `src/models/mpc_trace.jl` | ⬜ pending |
| 21-02-02 | 02 | 1 | MPC-03 | T-21-05 | Three permanent `@testitem`s: empty-ledger defaults, sequential-`k` guard, hand-verified derived metrics (`:local_ac_dual` correctly NOT flagged by `any_cert_failed`) | unit | plain Test.jl quick command (21-02-PLAN.md Task 2 `<verify>`); persistent `@testitem`s deferred to 21-06 | ❌ Wave 0 — new `test/test_mpc_trace.jl` | ⬜ pending |
| 21-03-01 | 03 | 2 | MPC-01, MPC-02 | T-21-07 / T-21-08 | `build_mpc_window`/`solve_mpc_window!`/`MpcWindow` build-once shape; `terminal_soc` toggle; `agg_pdc_handles` explicitly captured via `res.Pdc_param` (checker revision 1 precision fix); λ₀ never a `Parameter` | unit | plain Test.jl quick command (21-03-PLAN.md Task 1 `<verify>`) | ❌ Wave 0 — new `src/models/mpc_window.jl` | ⬜ pending |
| 21-03-02 | 03 | 2 | MPC-01 | — | `Phase21Fixtures` (`mpc_feeder`/`build_mpc_aggregators`/`mpc_high_pv_feeder`/`build_mpc_high_pv_aggregators`) constructs and the happy-path shape solves cleanly through `solve_welfare` | unit | plain Test.jl quick command (21-03-PLAN.md Task 2 `<verify>`) | ❌ Wave 0 — new `test/fixtures_phase21.jl` | ⬜ pending |
| 21-03-03 | 03 | 2 | MPC-01, MPC-02 | T-21-07 | Four `@testitem`s: build-once invariance across 3+ heterogeneous re-solves, non-no-op Parameter re-solve, terminal-SOC structural toggle | unit | plain Test.jl quick command (21-03-PLAN.md Task 3 `<verify>`); persistent `@testitem`s deferred to 21-06 | ❌ Wave 0 — new `test/test_mpc_window.jl` | ⬜ pending |
| 21-04-01 | 04 | 3 | MPC-01, MPC-02 | — | `Scenario` gains `mpc_H`/`mpc_step`/`mpc_terminal_soc`/`mpc_forecast_error` additive fields with guards; `SCENARIO_VALID_STRATEGIES` untouched | unit | plain Test.jl quick command (21-04-PLAN.md Task 1 `<verify>`) | ❌ Wave 0 — modifies `src/experiments/Scenario.jl` | ⬜ pending |
| 21-04-02 | 04 | 3 | MPC-01 | T-21-10 | `propagate_soc`/`propagate_tin`/`draw_forecast_error` exist, pure/deterministic, RNG-isolated via independent `sub_seed` tags | unit | plain Test.jl quick command (21-04-PLAN.md Task 2 `<verify>`) | ❌ Wave 0 — modifies `src/models/mpc_window.jl` | ⬜ pending |
| 21-04-03 | 04 | 3 | MPC-02 | T-21-11 | Hard terminal-SOC condition demonstrably prevents dump/hoard artifact (measured margin, `dev_enabled < dev_disabled`), present when disabled | unit/regression | plain Test.jl quick command (21-04-PLAN.md Task 3 `<verify>`); persistent `@testitem` deferred to 21-06 | ❌ Wave 0 — new `test/test_mpc_terminal.jl` | ⬜ pending |
| 21-05-01 | 05 | 4 | MPC-03, MPC-04 | T-21-19 | `run_mpc` materializes + day-ahead benchmark + `mpc_step`-STRIDED loop (`1:s.mpc_step:(s.T-s.mpc_H+1)`, checker revision 1 fix — the original draft hardcoded `1:(s.T-s.mpc_H+1)` and silently ignored `mpc_step`); published-hour count invariant to `mpc_step`; `mpc_step > mpc_H` guard | unit | plain Test.jl quick command (21-05-PLAN.md Task 1 `<verify>`, includes an `mpc_step=2` structural check + `ArgumentError` guard check) | ❌ Wave 0 — new `src/experiments/mpc_loop.jl` | ⬜ pending |
| 21-05-02 | 05 | 4 | MPC-04 | T-21-13 / T-21-14 | Non-throwing per-resolve cone-residual check escalates through `RestrictedBranchFlow` → `ac_dual_fallback_price` (Phase-20's own ladder); `MPC_HIGH_PV_SCALE_MEASURED` measured, not guessed | unit | plain Test.jl quick command (21-05-PLAN.md Task 2 `<verify>`, `pv_scale` scan) | ✅ same file, plus `test/fixtures_phase21.jl` | ⬜ pending |
| 21-05-03 | 05 | 4 | MPC-03, MPC-04 | T-21-14 / T-21-19 | Three `@testitem`s: happy-path end-to-end, forced-inexact never-throw escalation, `mpc_step=1` vs `mpc_step=2` genuinely different `realized_welfare`/`dadp_trace` (load-bearing regression for the checker-flagged stride fix) | unit/integration | plain Test.jl quick command (21-05-PLAN.md Task 3 `<verify>`); persistent `@testitem`s deferred to 21-06 | ❌ Wave 0 — new `test/test_mpc_loop.jl` | ⬜ pending |
| 21-06-01 | 06 | 5 | MPC-04 | T-21-17 | Live-executed literate page (`docs/literate/mpc_rolling_horizon.jl`) demonstrates `run_mpc` on a 24h horizon, reports measured regret honestly, wired into `docs/make.jl` | integration | `run_mpc`-only quick command (21-06-PLAN.md Task 1 `<verify>`); full Documenter build (`julia --project=docs docs/make.jl`) is a separate, slower invocation, not run by this inline check | ❌ Wave 0 — new `docs/literate/mpc_rolling_horizon.jl` | ⬜ pending |
| 21-06-02 | 06 | 5 | MPC-01..04 | T-21-18 | Full suite green: `0` failed, exactly `3` pre-existing broken, `passed` = baseline (2563) + this phase's tallied new-`@testitem` count | full-suite | `julia --project=. -e 'import Pkg; Pkg.test()'` (21-06-PLAN.md Task 2 `<verify>`) | n/a (acceptance gate) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_mpc_trace.jl` — new file, plan 21-02 Task 2 (MPC-03, `MpcTrace`)
- [ ] `test/fixtures_phase21.jl` — new `@testmodule Phase21Fixtures`, plan 21-03 Task 2 (the phase's short-`T` CI substrate + high-PV forced-inexact fixture), extended with `MPC_HIGH_PV_SCALE_MEASURED` by plan 21-05 Task 2
- [ ] `test/test_mpc_window.jl` — new file, plan 21-03 Task 3 (MPC-01/MPC-02, build-once + terminal-SOC toggle)
- [ ] `test/test_mpc_terminal.jl` — new file, plan 21-04 Task 3 (MPC-02, dump/hoard A/B regression)
- [ ] `test/test_mpc_loop.jl` — new file, plan 21-05 Task 3 (MPC-03/MPC-04, end-to-end + escalation + `mpc_step` stride regression)

*Existing infrastructure (`test/runtests.jl`'s `TestItemRunner.@run_package_tests`, plus the four existing device test files `test_pvbattery.jl`/`test_thermostatic.jl`/`test_fourquadbess.jl`/`test_aggregator.jl` extended in-place by plan 21-01 Task 3) covers discovery for every new item; no changes to `test/runtests.jl` are required.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.* The literate page (plan 21-06) is built and
checked automatically via `julia --project=docs docs/make.jl`; there is no behavior in this phase
that requires a human-only manual check (no UI, no external service, no visual review). The
24-hour demonstration horizon in the literate page is a LIVE-COMPUTED, honestly-reported
quantity (regret, price-deviation path) — not a manual verification step, but an automated build
artifact per D-11's discipline.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 20s (per-task quick commands; the full-suite gate is an intentional,
      documented exception run exactly once, at phase close, matching this project's own
      `~13-18 min` Phase-20 baseline)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-08-09 (checker revision 1 — populated from `21-RESEARCH.md`'s
"Validation Architecture" section and the final 21-01..21-06 PLAN.md files, including plan
21-05's `mpc_step` loop-stride fix and its load-bearing `21-05-03` regression row).
