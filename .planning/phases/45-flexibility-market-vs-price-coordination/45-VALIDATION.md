---
phase: 45
slug: flexibility-market-vs-price-coordination
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-11-04
---

# Phase 45 — Validation Strategy

> This is the per-phase validation contract for feedback sampling during execution.
> It comes from the "Validation Architecture" section of `45-RESEARCH.md`.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems `@testitem`, run via `Pkg.test()` (TestItemRunner, configured in `test/runtests.jl`; tags `:fast`/`:slow`) |
| **Config file** | `test/runtests.jl`, `test/expected_broken.txt` |
| **Quick run command** | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=<file>.jl julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (orchestrator only, detached, ~100 min) |
| **Estimated runtime** | ~60–240 s per targeted fast file; IEEE-123 slow items take minutes |

Hygiene rules:
- If a run mutated them, restore with `git checkout -- test/Project.toml test/Manifest.toml`.
- Never run TestItemRunner via `julia -e` or `--project=test`.
- Agents never run the full suite.
- RAM is tight (~1 GB free), so run one julia process at a time.

---

## Per-Task Verification Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SETL-07 | `FlexMarket` kwarg validation (rule ∈ {:uniform, :pay_as_bid}, tariff ∈ {:flat, :tou}, n_blocks ≥ 1, β ≥ 0 finite); `PriceBased <: AbstractCoordination`; `_flex_row_name` injective, duplicates throw | unit | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_flex_market.jl` | ❌ Wave 0 |
| SETL-07 | Bids: Interruptible analytic anchor `m_k = π₀ + b(δ_{k−1}+δ_k)/2`; V(b) = stage-1 utility (measured tol); monotone after the floor; g₁ < m₁; zero range ⇒ no block | unit | same | ❌ Wave 0 |
| SETL-07 | Stage 2 on 2-bus: OPTIMAL + exact; π read via `settlement_input`; infeasible offer (smax below the reachable range) ⇒ `infeasible_redispatch` status, no throw | unit | same | ❌ Wave 0 |
| SETL-07 | Delivery: separable fixture ⇒ shortfall ≤ measured tol; coupled fixture ⇒ shortfall reported > 0; w vs 10w identical within measured tol | unit | same | ❌ Wave 0 |
| SETL-07 | Ledger: `flex_payments = nothing` ⇒ `==` default; uniform and PAB both `ledger_residual == 0.0` and Σ actor balances == 0; PAB dispatch `==` uniform dispatch; PAB aggregators_total ≤ uniform (truthful convex) | unit | same | ❌ Wave 0 |
| SETL-07 | β: overpayment linear in β (0, 0.05, 0.10); physics columns identical across β; congested hours from `decompose_dlmp` | unit | same | ❌ Wave 0 |
| SETL-07 | Liveness: 2-bus Interruptible φ = 1, K ∈ {1,2,4,8,16} ⇒ welfare gap vs `solve_welfare` decreasing and final gap ≤ 3× measured; π vs DADP λ within measured band | integration | same | ❌ Wave 0 |
| SETL-08 | Default fence: 1.12.5 FNV digest of the 4 DataFrames + version-independent column list + same-process `isequal` | regression | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_flex_market_fence.jl` | ❌ Wave 0 (capture BEFORE src edits) |
| SETL-08 | `welfare_optimizer = nothing` ⇒ `isequal` to the default call; a supplied factory reaches both DADP and stage 2 (signature contract, the `agr_optimizer` test precedent at `test_settlement.jl:984-1090`) | unit | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_flex_market_fence.jl` | ❌ Wave 0 |
| SETL-08 | `compare_tariffs(...; flex_market = [...])` on the hermetic 2-bus: base 4 rows equal the default, flex rows appended with the full base schema + new columns, statuses populated | integration | `TSODSO_TEST_FILES=test_flex_market.jl` | ❌ Wave 0 |
| SETL-08 | IEEE-13 ground with flex: rows present, status ∈ allowed set, feasibility ∈ status set, welfare gap reported (no golden on the gap until measured over seeds) | slow | `TSODSO_TEST_SET=slow TSODSO_TEST_FILES=test_flex_market_ieee.jl` | ❌ Wave 0 |
| SETL-08 | IEEE-123 smoke: outcome recorded (ok or status row), never a crash | slow | same | ❌ Wave 0 |
| Both | exports set, JET ratchet, scripts index, docs registration | repo gates | `TSODSO_TEST_FILES=test_exports.jl`; `julia --project=. scripts/jet_check.jl --selftest`; `python3 .github/scripts/check_scripts_index.py` | ✅ |


*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Sampling Rate
- **Per task commit:** the task's test file (fast set), plus `test_settlement.jl` when the ledger or comparison is touched.
- **Per wave merge:** `test_flex_market.jl, test_flex_market_fence.jl, test_settlement.jl, test_actor_settlement.jl, test_exports.jl, test_welfare_solve.jl`.
- **Phase gate:** the full suite green against the baseline before `/gsd:verify-work`, with only the known Aqua/CairoMakie drift attributions.


- **Before verification:** the full suite must be green against the baseline of 35194 pass / 0 fail / 0 error / 7 allowlisted broken, plus the new phase-45 tests and any allowlisted fence skip.
- **Max feedback latency:** ~300 s per targeted file.

---

## Wave 0 Requirements
- [ ] `test/test_flex_market_fence.jl`: capture the digest of the default `compare_tariffs` (hermetic 2-bus T = 3) and the default ledger **before any `src/` edit** (`git diff -- src` empty at capture), plus one `skipped` line in `test/expected_broken.txt`.
- [ ] `test/test_flex_market.jl` and `test/test_flex_market_ieee.jl` (`:slow`).
- [ ] Measured tolerances, 3× the maximum over 3 seeds:
  - V(b) reproduction;
  - bid repair maximum;
  - separable shortfall;
  - liveness final gap;
  - π vs λ band;
  - w-sensitivity.
- [ ] Framework install: none.


---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| The literate page states the first-welfare-theorem framing, the tariff-on-activation overlap, the lossless-vs-lossy welfare convention, baseline gaming (β) and the hour-separability loss | SETL-07/08 | Prose fidelity | Review the new page under `docs/literate/` after the docs build |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 300s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
