---
phase: 05-distribution-pricing-dadp-dlmp-decomposition
plan: 03
subsystem: pricing
tags: [fit-baseline, fit-opt, counterfactual, welfare, socp, branch-flow, jump, clarabel]

# Dependency graph
requires:
  - phase: 05-01
    provides: src/pricing/fit.jl comment-only stub wired onto the include graph
  - phase: 04 (welfare_solve / ConvexBranchFlow / Aggregator / devices / profiles)
    provides: solve_welfare, ConvexBranchFlow SOCP AC power flow, Aggregator roll-up,
      PVBattery/Deferrable device builders, seeded generate_profiles, assert_solved!,
      select_optimizer(problem_class(pf))
provides:
  - "fit_baseline: the FIT feed-in-tariff counterfactual (FIT-OPT 3.24-3.28 + plain AC-PF)"
  - "social_fit — the FIT social welfare that is the denominator of the +25% headline ratio"
  - "German-FIT price constants FIT_λ_IMPORT/EXPORT/SELF (thesis page 93)"
  - "_fit_opt_solve — per-prosumer FIT-OPT sub-model with the three FIT flows"
affects: [05-05 welfare-accounting, phase-8 experiments]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Self-contained counterfactual solve inside src/pricing/ (builds+solves; never touches the Phase-4 seam)"
    - "Voltage-limit relaxation via a _relax_voltage feeder copy (reuse ConvexBranchFlow unchanged)"
    - "FIT flow-split via two equalities + non-negativity (reproduces max/min without a nonconvex min)"

key-files:
  created:
    - .planning/phases/05-distribution-pricing-dadp-dlmp-decomposition/05-03-SUMMARY.md
    - test/test_pricing_fit.jl
  modified:
    - src/pricing/fit.jl

key-decisions:
  - "FIT AC-PF reuses ConvexBranchFlow on a voltage-RELAXED feeder ([0.8,1.2] per-unit sanity band) so 3.35 is not enforced without editing the PF formulation (Open Q3)"
  - "social_fit = Σ U_flex − λ₀ᵀ p_import (thesis 3.38 evaluated on the FIT schedule); FIT transfers cancel in social welfare"
  - "fit_baseline signature is superset-compatible with the Wave-1 RED harness (accepts λ_fit, returns .welfare and .ratio) AND the plan's contract (returns .ctx, .social_fit)"
  - "The internal efficiency ratio (social_DADP/social_fit) is solved on the same relaxed network for feasibility+comparability; the AUTHORITATIVE +25% ratio is 05-05's job"

patterns-established:
  - "Drop-the-battery / keep-the-PV device split for the FIT prosumer (Assumption A4)"
  - "Fixed-injection AC-PF: FIT-OPT numeric net injections fixed into :Rp/:Rq, closed with a priced frontier"

requirements-completed: [PRICE-03]

# Metrics
duration: ~40min
completed: 2026-07-18
---

# Phase 5 Plan 03: FIT Feed-in-Tariff Baseline Counterfactual Summary

**`fit_baseline` — the thesis-faithful FIT-OPT (3.24-3.28, no battery, German-FIT prices) aggregated onto a plain voltage-unenforced AC power flow, returning the reproducible FIT social welfare that anchors the +25% headline ratio.**

## Performance

- **Duration:** ~40 min
- **Tasks:** 2 (both TDD `auto`)
- **Files modified:** 2 (`src/pricing/fit.jl`, `test/test_pricing_fit.jl`)

## Accomplishments
- Implemented the ONE genuinely-new solve of Phase 5: the FIT feed-in-tariff counterfactual, as a self-contained builder in `src/pricing/fit.jl` that never touches the Phase-4 seam.
- Per-prosumer FIT-OPT (thesis 3.24-3.28): drops the PVBattery storage (keeps its PV availability), reuses flexible-load device builders, and enforces the import/self-consume/export split as exact structural identities (`self+imp==p_h`, `self+exp==Ppv`).
- German-FIT price triple as auditable named constants (`FIT_λ_IMPORT=6.6`, `FIT_λ_EXPORT=9.6`, `FIT_λ_SELF=5.6` ¢$/kWh, thesis page 93), kept in the same unit as λ₀ (Pitfall 5).
- Aggregation (3.22-3.23) + a plain AC power flow reusing `ConvexBranchFlow` on a voltage-RELAXED feeder so the voltage limit (3.35) is NOT enforced (Open Q3).
- Returns a finite, magnitude-sane, reproducible `social_fit` (the +25% ratio denominator) plus a self-contained efficiency-ratio cross-check.
- Every solve routes through `select_optimizer(problem_class(pf))` (no concrete solver named, INFRA-02) and is gated on `assert_solved!`.
- `fit @testitem` filter GREEN: 87/87 assertions pass (the Wave-1 RED harness `test/test_fit.jl` + the new richer `test/test_pricing_fit.jl`).

## Task Commits

Each task was committed atomically:

1. **Task 1: FIT-OPT per-prosumer schedule with the three German-FIT flows (3.24-3.28)** - `d1d5dc2` (feat)
2. **Task 2: fit_baseline — aggregate + AC-PF + FIT social welfare (3.22-3.23, 4.1)** - `65feb6d` (feat)

_TDD note: the Wave-1 RED harness `test/test_fit.jl` (from plan 05-01) was the pre-existing failing test; both task commits drive it (and the new richer items) GREEN._

## Files Created/Modified
- `src/pricing/fit.jl` - FIT constants, `_fit_pv_and_flex` (drop battery / keep PV), `_fit_opt_solve` (per-prosumer FIT-OPT), `_relax_voltage`, and `fit_baseline` (aggregate + plain AC-PF + `social_fit` + ratio).
- `test/test_pricing_fit.jl` - `@testitem`s (name contains "fit"): flow-split identities, FIT constants, OPTIMAL + finite magnitude-sane welfare, same-seed reproducibility, and the voltage-limit-not-enforced structural check.

## Decisions Made
- **Voltage limit "not enforced" via feeder relaxation.** `ConvexBranchFlow` reads voltage bounds from the feeder, so — without editing that (out-of-scope) file — the FIT AC-PF runs on a `_relax_voltage` copy whose bounds are widened to `[0.8, 1.2]` (the widest `assert_magnitudes` permits). The original tighter limit therefore never binds, reproducing the thesis "AC-PF, observe 3.35 not enforced" step (Open Q3).
- **`social_fit` definition.** The FIT social welfare uses the SAME functional as the DADP solve (thesis 3.38): flexible-device utility minus the true MEM cost of the net imported energy + losses. The internal FIT transfers (λ_self/λ_export/λ_import) cancel in social welfare.
- **Superset-compatible signature.** `fit_baseline` satisfies both the plan's contract (`.ctx`, `.social_fit`) and the pre-existing Wave-1 RED harness contract (`λ_fit` kwarg, `.welfare`, `.ratio`) so no regression is introduced and `test/test_fit.jl` is left untouched (parallel-executor file boundary).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reconciled the plan's `fit_baseline(...; social_fit)` contract with the pre-existing RED harness `fit_baseline(...; λ_fit) -> (.welfare, .ratio)`**
- **Found during:** Task 2
- **Issue:** `test/test_fit.jl` (created by plan 05-01, outside this executor's file boundary and thus unmodifiable) calls `fit_baseline(feeder, pf, aggregators; λ_fit, T)` and reads `.welfare` / `.ratio`, whereas the plan specifies `fit_baseline(...; social_fit)` returning `.ctx` / `.social_fit`. Implementing only the plan's shape would leave the RED harness `fit` @testitems failing (regression).
- **Fix:** Implemented a superset signature/return that satisfies both: accepts `λ_fit` (flat FIT/MEM price → default λ₀) and `seed`; returns a NamedTuple with `ctx`, `social_fit`, `welfare` (= `social_fit`), `ratio`, `prosumer_surplus`, `fit_flows`. `ratio = social_DADP / social_fit` from an internal `solve_welfare` cross-check.
- **Files modified:** src/pricing/fit.jl
- **Verification:** `@run_package_tests filter=ti->occursin("fit", ti.name)` → 87/87 pass (RED harness + new items).
- **Committed in:** 65feb6d (Task 2 commit)

**2. [Rule 1 - Bug] Efficiency-ratio reference solve was INFEASIBLE on the original tight-voltage feeder**
- **Found during:** Task 2 (first end-to-end run)
- **Issue:** Computing the ratio via `solve_welfare(feeder, …)` on the original `[0.95, 1.05]` feeder threw `INFEASIBLE` — the heavy seeded load drops voltage below 0.95 (the FIT AC-PF avoids this only because it relaxes the bounds).
- **Fix:** Solve the ratio's reference welfare on the SAME `_relax_voltage` network as the FIT AC-PF, keeping the two welfares directly comparable and always feasible. Documented that the authoritative +25% ratio is (re)computed by 05-05 against the real DADP ctx.
- **Files modified:** src/pricing/fit.jl
- **Verification:** ratio finite and positive on all fit test fixtures.
- **Committed in:** 65feb6d (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both necessary for a GREEN, no-regression `fit` suite and a feasible reference solve. No scope creep — all work is confined to `src/pricing/fit.jl` + `test/test_pricing_fit.jl`.

## Issues Encountered
- The environment's `TestItemRunner` lives only in `test/Project.toml`; running the `fit`-filtered items required temporarily `Pkg.develop`-ing TSODSO into the test env and restoring the tracked `test/Project.toml` / `test/Manifest.toml` afterward (both restored, unmodified in the final tree).

## Threat Flags

None — no new network endpoints, auth paths, or trust-boundary surface. The FIT baseline is an offline research solve routed through the open-source solver factory (T-05-10 mitigated), with named-constant FIT prices (T-05-04) and a seeded-reproducibility guarantee (T-05-09).

## Next Phase Readiness
- `fit_baseline` returns `social_fit` (and per-aggregator `fit_flows`), ready for plan 05-05 `welfare_accounting` to divide `social_DADP / social_fit` for the authoritative +25% headline ratio.
- No STATE.md / ROADMAP.md updates performed (per orchestrator instruction; wave-merge owns those).

## Self-Check: PASSED

- Files verified present: `src/pricing/fit.jl`, `test/test_pricing_fit.jl`, `05-03-SUMMARY.md`.
- Commits verified present: `d1d5dc2` (Task 1), `65feb6d` (Task 2).
- `fit` @testitem filter GREEN (87/87 assertions).

---
*Phase: 05-distribution-pricing-dadp-dlmp-decomposition*
*Completed: 2026-07-18*
