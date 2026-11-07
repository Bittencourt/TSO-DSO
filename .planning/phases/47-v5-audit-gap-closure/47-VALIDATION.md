---
phase: 47
slug: v5-audit-gap-closure
status: approved
nyquist_compliant: true
wave_0_complete: true
created: 2026-11-06
---

# Phase 47 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Source: the
> "Validation Architecture" section of `47-RESEARCH.md`, with the post-research corrections in
> `47-CONTEXT.md` applied (W3 predicate `has_reactive_decision && !is_flexible_load`, EV τ
> `TAU_EV_ADMM`, untyped `actors = nothing` keyword).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems `@testitem` / `@testmodule` via `Pkg.test()`; TestItemRunner 1.1.5 configured by `test/runtests.jl` with `TSODSO_TEST_SET` / `TSODSO_TEST_FILES` |
| **Config file** | `test/runtests.jl`, `test/runner_support.jl`, `test/expected_broken.txt` (untouched) |
| **Quick run command** | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=<a.jl,b.jl> julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Full suite command** | Not used in this phase (agents never run the full suite) |
| **Estimated runtime** | ~2 min load/compile overhead per run; `test_flex_market_fence.jl` fast set measured 162 s (86/86, digests equal to the pin on 1.12.5) |

After every run, restore with `git checkout -- test/Project.toml test/Manifest.toml`.
Never run TestItemRunner via `julia -e` directly or with `--project=test`. One julia process at a
time, in the foreground; split a batch if it nears the 10-minute foreground limit. Default `julia`
(1.12.5) only: the digest fences assert on 1.12.5.

---

## Sampling Rate

- **After every task commit:** the touched file's fast set (plan 01: `test_settlement.jl`, then
  `test_flex_market.jl`; plan 02: `test_flex_market_fence.jl,test_flex_market.jl`).
- **After every plan:** plan 01 runs `test_settlement.jl,test_electricvehicle.jl` and
  `test_flex_market.jl,test_flex_market_fence.jl`; plan 02 runs
  `test_flex_market_fence.jl,test_behaviour.jl,test_flex_population.jl` and
  `test_settlement.jl,test_device_traits.jl`; then the formatter (touched files only), content-loss,
  planning-ID (≤ 355), scripts-index and JET (20 baseline, 0 new) checks.
- **Phase gate (plan 03):** `test_admm_knifeedge_canary.jl,test_actor_default_fence.jl` and
  `test_flex_market_ieee.jl,test_exports.jl,test_electricvehicle.jl`; SC3 diff
  `git diff 9e9b709..HEAD -- src/admm src/models/exactness.jl src/solver/factory.jl test/expected_broken.txt`
  empty; `git diff 9e9b709..HEAD --stat -- results src/models src/admm` empty.
- **Max feedback latency:** ~300 s for a targeted file.

---

## Per-Task Verification Map

| Task | Req | Behavior | Test Type | Automated Command | File Exists | Status |
|------|-----|----------|-----------|-------------------|-------------|--------|
| 47-01-01 | DEV-07 | `price_taker_dispatch` on the negative-price V2G EV: battery `:not_checked`, `ev_certificate === :refused`, message contains "EV complementarity" | unit | `TSODSO_TEST_FILES=test_settlement.jl` | ✅ edit (new item) | ⬜ pending |
| 47-01-01 | DEV-07 | V1G → `:not_checked`; compliant V2G at the swing price → `:ok`; EV-free unchanged; PVBattery + V2G both run; wrapped V2G routed to the EV certificate | unit | `TSODSO_TEST_FILES=test_settlement.jl` | ✅ edit (new item) | ⬜ pending |
| 47-01-02 | SETL-07 | `_deliver` key-set pin updated additively (`:ev_certificate, :ev_message` before `:shortfall`) | schema | `TSODSO_TEST_FILES=test_flex_market.jl` | ✅ edit | ⬜ pending |
| 47-01-02 | SETL-07 | `_deliver` at −50 → `:refused`; negative-price hand-built `SettlementInput` clear → `physics.baseline.ev_certificate == [:refused]`, battery `[:not_checked]`, `n_ev_refused == 1` (status not pinned); compliant clear → battery `[:not_checked]`, EV in `(:ok, :refused)` | integration | `TSODSO_TEST_FILES=test_flex_market.jl` | ✅ edit (new item) | ⬜ pending |
| 47-01-03 | all | Fence digests, formatter, content loss, planning ids, scripts index, JET, SC3 | fence + gates | Task 3 verify chain in `47-01-PLAN.md` | ✅ | ⬜ pending |
| 47-02-01 | SETL-07, SETL-08 | `actors = [Portfolio(...)]` (and a non-vector value) → `ArgumentError` naming the scope decision, before any solve (counting factory `n == 0`; `FailAtCall` calls 0); explicit `actors = nothing` equals the default | guard | `TSODSO_TEST_FILES=test_flex_market_fence.jl,test_flex_market.jl` | ✅ edit (new cases) | ⬜ pending |
| 47-02-01 | SETL-08 | `compare_tariffs` with EV / HeatPump / SmartInverterPV / wrapper → `ArgumentError` with `n == 0`, message contains `compare_tariffs` and the type name | guard | `TSODSO_TEST_FILES=test_flex_market_fence.jl` | ✅ edit (new cases) | ⬜ pending |
| 47-02-01 | SETL-07 | A behaviour-wrapped population clears through `clear_flex_market` with status "ok" and residual 0.0 (wrappers are not an actor channel) | regression | `TSODSO_TEST_FILES=test_flex_market.jl` | ✅ edit (new item) | ⬜ pending |
| 47-02-02 | SETL-07, SETL-08 | `FourQuadBESS` and `SmartInverterPV` refused by `_stage2_aggregators`, `_flex_physics`, `clear_flex_market` and `compare_tariffs(flex_market)` before any solve; Interruptible / Thermostatic / Deferrable / HeatPump / PVBattery / FailAtCall not refused | guard | `TSODSO_TEST_FILES=test_flex_market.jl,test_flex_market_fence.jl` | ✅ edit (new item + case) | ⬜ pending |
| 47-02-03 | all | Fence batches, formatter, content loss, planning ids, scripts index, JET, SC3 | fence + gates | Task 3 verify chain in `47-02-PLAN.md` | ✅ | ⬜ pending |
| 47-03-01 | SETL-07, SETL-08 | Scope decision recorded (REQUIREMENTS.md SETL-F2 + row notes, audit gap-closure section, docs section 12); W3 sentence in docs section 1; backlog todo lists W1, W4–W9, both `@ref` warnings, the SettlementInput provenance flag; Literate file parses | doc check | grep + `Meta.parseall` chain in `47-03-PLAN.md` | ❌ todo file created by the task | ⬜ pending |
| 47-03-02 | DEV-07, SETL-07, SETL-08 | Knife-edge canary 56 iterations / −4823.66604824162; actor default fence; committed comparison CSV rows; exports; SC3 and results/ diffs empty | fence + diff gate | Task 2 verify chain in `47-03-PLAN.md` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] Framework, fixtures (`FlexMarketFixtures`, `FlexFenceFixtures`, `TwoBusFixtures`, `BehaviourFixtures`) and the before-any-solve harnesses (`counting()` / `refused(g)`, `FailAtCall` with `fail_at = 0`) already exist. New test items only.
- [x] Framework install: none (no new packages).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| The docs limitations read honestly (scope decision stated as future work; the undetected SettlementInput channel stated plainly; the reactive refusal explained by the stage-2 model, not by convenience) | SETL-07, SETL-08 | Prose fidelity | Review section 1 and section 12 of `docs/literate/flex_market.jl`. The full docs build (about 9 min) is not run in this phase; the file is comment-only and is parse-checked. |
| The refined W3 predicate matches the user's intent (refuse SmartInverterPV and FourQuadBESS only) | SETL-07 | Confirmed by the user in the post-research corrections | Check that `test_flex_market.jl` negative controls pass for every flexible load. |

---

## Validation Sign-Off

- [x] Every task has an `<automated>` verify or a Wave 0 dependency
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers every MISSING reference
- [x] No watch-mode flags
- [x] Feedback latency < 300 s per targeted file
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-11-06
