---
phase: 45
slug: flexibility-market-vs-price-coordination
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-11-04
revised: 2026-11-04
---

# Phase 45 — Validation Strategy

> This is the per-phase validation contract for feedback sampling during execution.
> It comes from the "Validation Architecture" section of `45-RESEARCH.md` and was refreshed to match the final plans 45-01..45-07.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems `@testitem`, run via `Pkg.test()` (TestItemRunner, configured in `test/runtests.jl`; tags `:fast`/`:slow`) |
| **Config file** | `test/runtests.jl`, `test/expected_broken.txt` |
| **Quick run command** | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=<file>.jl julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Slow run command** | `TSODSO_TEST_SET=all TSODSO_TEST_FILES=<file>.jl julia --project=. -e 'import Pkg; Pkg.test()'` (IEEE-123: background, logged) |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (orchestrator only, detached, ~100 min) |
| **Estimated runtime** | ~60–240 s per targeted fast file; the IEEE-13 slow file takes minutes; the IEEE-123 smoke takes ~6–10 min |

Hygiene rules:
- After every run, restore with `git checkout -- test/Project.toml test/Manifest.toml`.
- Never run TestItemRunner via `julia -e` or `--project=test`.
- Agents never run the full suite.
- RAM is tight (~1 GB free), so run one julia process at a time.

---

## Per-Task Verification Map

| Plan-Task | Req ID | Behavior | Test Type | Automated Command / File | Created in |
|-----------|--------|----------|-----------|--------------------------|------------|
| 01-T1 | SETL-08 | Default fence: 1.12.5 FNV digest of the 4 DataFrames + ledger (one `expected_broken.txt` skip); version-independent 37-column list, tariff order, same-process `isequal` | regression | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_flex_market_fence.jl` (precondition `git diff --quiet -- src`) | 01-T1 (before any src edit) |
| 01-T2 | SETL-07 | `FlexMarket` kwarg validation; `PriceBased <: AbstractCoordination`; `_flex_row_name` injective; exports | unit | `TSODSO_TEST_FILES=test_flex_market.jl,test_flex_market_fence.jl,test_exports.jl` + guard | 01-T2 |
| 02-T1 | SETL-07 | Ledger `flex_payments`: `nothing` ⇒ `==` default; mirror pairs; `ledger_residual == 0.0`; V5 guards | unit | `TSODSO_TEST_FILES=test_flex_market.jl,test_flex_market_fence.jl,test_settlement.jl,test_actor_settlement.jl` | 02-T1 |
| 02-T2 | SETL-07 | Bids: V(b) = stage-1 utility; Interruptible analytic anchor; PAV-monotone; g₁ < m₁; zero range ⇒ no block; probe counts | unit | `TSODSO_TEST_FILES=test_flex_market.jl,test_flex_market_fence.jl` | 02-T2 |
| 03-T1 | SETL-07 | Stage 2 on 2-bus: `ok` and exact; π via `settlement_input`; infeasible offer ⇒ `infeasible_redispatch` status, no throw; congested hours + κ interval | unit | `TSODSO_TEST_FILES=test_flex_market.jl,test_flex_market_fence.jl,test_welfare_solve.jl` | 03-T1 |
| 03-T2 | SETL-07 | Delivery: separable shortfall ≤ measured; over-reach target ⇒ shortfall = R↑; w vs 10w; `_flex_physics` status propagation | unit | `TSODSO_TEST_FILES=test_flex_market.jl,test_flex_market_fence.jl,test_settlement.jl` | 03-T2 |
| 04-T1 | SETL-07 | `clear_flex_market` record: residual `== 0.0` and Σ balances for both rules and all β; PAB dispatch `==` uniform; PAB aggregators_total ≤ uniform (measured slack); β overpayment linear, physics `==`; `bins = nothing` default | unit | `TSODSO_TEST_FILES=test_flex_market.jl,test_flex_market_fence.jl,test_exports.jl,test_settlement.jl` | 04-T1 |
| 04-T2 | SETL-07 | Liveness: W* = social welfare from utilities (Σ U − λ₀ᵀ p_import of the centralized ctx); K ∈ {1,2,4,8,16} gap shrinks, final gap ≤ 3× measured; π vs DADP λ band | integration | `TSODSO_TEST_FILES=test_flex_market.jl` | 04-T2 |
| 05-T1 | SETL-08 | `flex_market = nothing` / `welfare_optimizer = nothing` ⇒ `isequal`; counting factory reaches DADP + stage 2 (2 calls); `:admm` + `welfare_optimizer` ⇒ ArgumentError; houses / duplicates / non-FlexMarket / FixedCapacitor ⇒ ArgumentError before any solve | unit | `TSODSO_TEST_FILES=test_flex_market_fence.jl,test_settlement.jl` | 05-T1 |
| 05-T2 | SETL-08 | `compare_tariffs(...; flex_market = [...])` on 2-bus: base 4 rows `isequal`, base schema + `FLEX_EXTRA_COLUMNS`, status/feasibility sets, `delivery_shortfall` on flex bills/rebound rows; JET ratchet | integration | `TSODSO_TEST_FILES=test_flex_market.jl,test_flex_market_fence.jl,test_settlement.jl,test_actor_settlement.jl,test_exports.jl` + `scripts/jet_check.jl` (Julia 1.12.7) | 05-T2 |
| 06-T1 | SETL-08 | Script parse (`--flex-market`, `ieee123`, `ieee123-default`, flex sets); IEEE-13 ground with flex: statuses in sets, welfare gap finite (no golden) | slow | script `include` check + `TSODSO_TEST_SET=all TSODSO_TEST_FILES=test_flex_market_ieee.jl` | 06-T1 |
| 06-T2 | SETL-08 | Committed CSV invariants (flex rows, FIT row unchanged, β physics `==`, `run_wall_s`, shortfall sums in bills / `rebound_hourly.csv`); IEEE-123 smoke outcome recorded, never a crash, a `flex_uniform` row asserted on the ok path | fast + slow | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_flex_market_ieee.jl`; IEEE-123: `TSODSO_TEST_SET=all TSODSO_TEST_FILES=test_flex_market_ieee123.jl` run in the background, verified from its log (`exit=0`, `tests passed`) | 06-T1/T2 |
| 07-T1 | Both | Literate page runs standalone; make.jl + scripts index registration; required framings present | docs | `julia --project=docs docs/literate/flex_market.jl`; `python3 .github/scripts/check_scripts_index.py`; greps | 07-T1 |
| 07-T2 | Both | api.md surfacing (reduced `checkdocs = :exports` build), JuliaFormatter 2.10 + content-loss, setup names, JET, guard ≤ 355, exports, regression set | repo gates | see 45-07-PLAN.md Task 2 verify | 07-T2 |

Every plan also ends with FMT (JuliaFormatter 2.10.x on its touched `.jl` files, in a temporary environment) plus `check_content_loss.py HEAD`.

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Sampling Rate
- **Per task commit:** the task's test file (fast set), plus `test_settlement.jl` when the ledger or comparison is touched, plus the fence from 01 onward.
- **Per plan end:** FMT + content-loss on the plan's touched files; planning-ID guard ≤ 355.
- **Phase gate:** the full suite green against the baseline before `/gsd:verify-work`, with only the known Aqua/CairoMakie drift attributions.
- **Before verification:** the full suite must be green against the baseline of 35194 pass / 0 fail / 0 error / 7 allowlisted broken, plus the new tests and the one allowlisted fence skip (8 allowlisted in total).
- **Max feedback latency:** ~300 s per targeted fast file. Slow IEEE files are excluded and run in the background.

---

## Wave 0 Requirements
- [ ] `test/test_flex_market_fence.jl`: capture the digest of the default `compare_tariffs` (hermetic 2-bus T = 3) and the default ledger **before any `src/` edit** (`git diff -- src` empty at capture), plus one `skipped` line in `test/expected_broken.txt` (plan 01 Task 1).
- [ ] `test/test_flex_market.jl` (plan 01 Task 2 onward), `test/test_flex_market_ieee.jl` (`:slow` IEEE-13 plus a fast CSV item) and `test/test_flex_market_ieee123.jl` (`:slow` IEEE-123 smoke) (plan 06).
- [ ] Measured tolerances, 3× the maximum over 3 seeds (an exact `==` when the observed max is 0.0), recorded in the test header table and the SUMMARYs:
  - V(b) reproduction;
  - the analytic anchor;
  - bid repair maximum;
  - bus_nets vs target and wash;
  - separable and over-reach shortfall;
  - w-sensitivity;
  - Σ balances;
  - PAB ≤ uniform slack;
  - β linearity;
  - liveness final gap and its noise;
  - π vs λ band;
  - shortfall-sum consistency.
- [ ] Framework install: none (JuliaFormatter only in a temporary environment).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| The literate page states the first-welfare-theorem framing with the measured gap, the tariff-on-activation overlap, the lossless-vs-lossy welfare convention, baseline gaming (β) and the hour-separability shortfall | SETL-07/08 | Prose fidelity | Review `docs/literate/flex_market.jl` after it runs standalone; the 07-T1 greps check that the topics are present, not their correctness |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (each verify only references files created in the same or an earlier task)
- [x] No watch-mode flags
- [x] Feedback latency < 300s for every fast target (slow IEEE files run in the background, verified from logs)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending (wave_0_complete flips to true once plan 01 has landed and the test files exist)
