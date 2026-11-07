---
phase: 41-settlement-ledger-equity
plan: 03
subsystem: settlement
tags: [julia, tariffs, price-taker, qp, ac-power-flow, feasibility-status, revenue-neutrality, tou]

# Dependency graph
requires:
  - phase: 41-01
    provides: "SettlementInput packed run adapter (prices, bus_nets — the A2 weights source) + the 2-bus solve_welfare test fixture"
  - phase: 41-02
    provides: "include-graph/test_exports sequencing (shared-file waves); nothing functional"
  - phase: 40 (materialize.jl)
    provides: "_case_a_house/_case_a_house_seed per-house construction primitives (separability fixture)"
  - phase: 27 (Phase-27 idiom)
    provides: "ACPowerFlow(; limits=false) physics-only settlement + per-hour diagnostics template"
provides:
  - "revenue_neutral_flat/revenue_neutral_tou — algebraically revenue-neutral flat/TOU price construction from one DADP run (pure), pinned TOU bin constants via default_tou_bins"
  - "price_taker_dispatch/price_taker_dispatches — thin penalty-free counterfactual dispatch QP (Max U + Σ p·pag, NO ρ penalty) with recorded battery-certificate statuses"
  - "FeasibilityStatus/ac_feasibility_status — AC-physics feasibility of a fixed dispatch as a reported status (:feasible/:infeasible/:solve_failed), never thrown"
  - "household_dispatches (unexported alias) — per-house re-solves for SETL-01 household attribution"
affects: [41-04 (comparison harness consumes all three layers), SETL-01 household attribution, tariff-comparison scripts]

# Tech tracking
tech-stack:
  added: []   # zero new packages (RESEARCH audit table empty by construction)
  patterns:
    - "Revenue-neutral weighted-mean derivation with a no-op-guard rescale (s ≈ 1.0 asserted, carries s on failure)"
    - "Report-don't-try/catch certificate semantics (try/catch CertificateError → recorded :refused status over the (:error,:warn) API)"
    - "Analytic DistFlow warm start (downstream-accumulated flows, lossless v drop, l = S²/v) for Ipopt's degenerate zero start"

key-files:
  created:
    - src/settlement/tariffs.jl
    - src/settlement/price_taker.jl
    - src/settlement/feasibility.jl
  modified:
    - src/TSODSO.jl
    - test/test_settlement.jl
    - test/test_exports.jl

key-decisions:
  - "A2 weights = the DADP run's OWN signed net injections (SettlementInput.bus_nets) — fairness condition (Σ p_derived·w == Σ λ·w) is then algebraic, documented at module level"
  - "TOU bins pinned as module constants (off-peak 1:6, shoulder 7:16∪23:24, peak 17:22; 6/12/6); default_tou_bins(24) only — other horizons require explicit bins"
  - "Price-taker QP drops the ρ penalty (research-locked): Max ctx.objective + Σ p·pag; τ_batt = 1e-3 never loosened; certificate refusals recorded as (:refused, message)"
  - "Feasibility warm start = analytic DistFlow point (mpc_loop physically-plausible-start remedy, analytic variant) — the ConvexBranchFlow seed variant is structurally infeasible for fixed reverse-flow dispatch (measured; Phase-26 v̂ ≥ v restriction)"
  - "Feasibility objective = total-loss Min Σ r·l (no λ₀ is consumed by a physics status; same tight-cone/numerical-freedom rationale as fit.jl's priced frontier and mpc_loop's loss objective)"

patterns-established:
  - "Gate-then-golden measured pins: tariffs real-run rel gap 2.8658034134118547e-16 → 10× (TOU 0.0 → 1e-15 floor); separability net∞ 8.302723663710515e-8 → 10×, utility gap 1.9731015754587133e-7 → 10×"
  - "Honesty certificates: flat-price battery-certificate outcome recorded either way (:ok measured on this fixture); solve-failure poison deterministically beyond loadability"

requirements-completed: [SETL-02, SETL-03]

# Metrics
duration: 99min
completed: 2026-10-25
---

# Phase 41 Plan 03: Tariff Construction, Price-Taker & Feasibility Status Summary

**Revenue-neutral flat/TOU tariff construction from one DADP run (exact on hand-computed anchors, measured-pin on real runs), a thin penalty-free price-taker QP with recorded battery-certificate statuses and measured per-house separability, and the third Phase-27 AC-feasibility status wrapper — the complete computational core 41-04's comparison harness assembles.**

## Performance

- **Duration:** 99 min (includes a 17 min background fast-suite gate)
- **Started:** 2026-10-25T19:42:13Z
- **Completed:** 2026-10-25T21:21:51Z
- **Tasks:** 3/3 complete (each TDD: RED commit → GREEN commit)
- **Files modified:** 6 (3 created, 3 modified)

## Accomplishments

- **SETL-02 construction layer:** `revenue_neutral_flat`/`revenue_neutral_tou` derive flat/TOU prices from one solved DADP run such that total payments under the derived tariff equal total payments under DADP — algebraically exact (hand-computed 2-bus/2-hour certificate asserts literal `==`: flat == [30.0, 30.0], TOU == [15.0, 37.5], rescale s == 1.0), measured-pin on the real 2-bus solve_welfare fixture. TOU bins are auditable module constants (pinned 1:6 / 7:16∪23:24 / 17:22).
- **Penalty-free counterfactual dispatch:** `price_taker_dispatch` mirrors `build_agr_opt`/`_fit_opt_solve` minus the −(ρ/2)·Σ pag² penalty (greps clean — no ρ term, no `set_objective_coefficient`); the arbitrage certificate pins the unshaded dispatch (charge-low/sell-high at the device's rated bounds: measured net ≈ [0, 0.6655] on prices [10, 50], matching the hand derivation); per-house separability reconciles Σ_h to the aggregator within measured pins (never claimed bitwise).
- **SETL-03 status layer:** `ac_feasibility_status` reports `:feasible` (benign DADP dispatch), `:infeasible` with the exact `_fit_ac_settlement_violations` field set (12-pu stress: ratio 1.2000097738789337 ≥ 1), `:solve_failed` carrying the termination status (500-pu beyond-loadability poison, deterministic) — no throw path for violations or non-convergence; SMAX_NO_LIMIT branches skip-listed (ratio 0.0).
- **Golden policy held:** `git diff --exit-code src/pricing/ src/admm/ src/models/` clean at every step; solver abstraction held (zero code-line solver names in `src/settlement/`).
- **Full fast suite green:** 32399 pass / 0 fail / 0 error / 6 broken (all `expected_broken.txt`-listed) — no regressions across the 32k-test suite.

## Task Commits

Each task was committed atomically (TDD: RED → GREEN):

1. **Task 1: tariffs.jl — revenue-neutral flat/TOU price construction (pure)** — `6019fe3` (test, RED) → `b9ada95` (feat, GREEN)
2. **Task 2: price_taker.jl — thin penalty-free counterfactual dispatch + per-house separability** — `cc5502c` (test, RED) → `4932420` (feat, GREEN)
3. **Task 3: feasibility.jl — AC-physics feasibility status (report, never throw)** — `c79523a` (test, RED) → `452d2dc` (feat, GREEN)

**Plan metadata:** (this commit) docs(41-03)

## Files Created/Modified

- `src/settlement/tariffs.jl` (created) — pure price-construction kernels (`revenue_neutral_flat`, `revenue_neutral_tou`), pinned TOU bin constants + `default_tou_bins`, `flat_prices`/`tou_prices` wrappers over `SettlementInput`; zero solver references (grep `JuMP` == 0)
- `src/settlement/price_taker.jl` (created) — `price_taker_dispatch` (QP: Max U + Σ p·pag, coupling 3.22, `assert_solved!` gate, try/catch CertificateError → recorded refusal), `price_taker_dispatches`, unexported `household_dispatches`
- `src/settlement/feasibility.jl` (created) — `FeasibilityStatus` struct + `ac_feasibility_status` (ACPowerFlow limits=false, analytic DistFlow warm start, per-hour diagnostics — third deliberate copy of the Phase-27 idiom, un-shared per fit.jl:741-744)
- `src/TSODSO.jl` (modified) — settlement include block completed in dependency order: types → adapters → tariffs → price_taker → feasibility → equity
- `test/test_settlement.jl` (modified) — 8 new `@testitem`s (tariff anchors/real-run/guards, price-taker DADP/flat/arbitrage/separability/guards, feasibility benign/stress/skip-list/solve-failed/guards) with measured-value comments at every pin site
- `test/test_exports.jl` (modified) — 9 new exports registered in the curated public-surface guard

## Decisions Made

- **A2 weights:** signed net injections from the run itself (`input.bus_nets`) — the fairness condition then coincides with the settlement quantities; documented in the module header.
- **A4 bins:** pinned 6/12/6 constants with hour-of-day comments; `default_tou_bins(T ≠ 24)` throws naming itself (test fixtures pass explicit bins).
- **Battery certificate τ_batt = 1e-3** (ADMM-consolidation discipline) — never loosened; the flat-price leg measured `:ok` on this fixture and is recorded honestly either way (the test accepts both outcomes).
- **Feasibility objective:** total-loss `Min Σ r·l` (no λ₀ in the wrapper signature; loss-min drives the DistFlow point physical and only resolves numerical freedom — mpc_loop's documented rationale).
- **Utility semantics:** `price_taker_dispatch.utility` is the pure device-utility term EXCLUDING price revenue — revenue settles as ledger transfers, matching `welfare_accounting`'s U.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] ConvexBranchFlow seed solve replaced by an analytic DistFlow warm start**
- **Found during:** Task 3 (feasibility.jl)
- **Issue:** The plan prescribed mirroring fit.jl's two-solve structure verbatim (SOCP seed → warm-started ACPF). Measured immediately on GREEN: the seed terminates INFEASIBLE even on the BENIGN fixture — the `v̂ ≥ v` exactness copy is a conservative restriction (Phase-26 v4.0 finding) that excludes the true AC point of any reverse-flow fixed dispatch (`v₂ = v̂₂ + (r²+x²)·l` sits above the copy while the cone forces `l > 0` — a contradiction; fit.jl's own header documents the same structural behavior).
- **Fix:** Warm start = `_analytic_distflow_start!` (downstream-accumulated flows, lossless `v = 1 − 2(rP+xQ)` drops, `l = S²/v`) — the mpc_loop production remedy's physically-plausible-start idiom, analytic variant, deterministic, no solver. Same degenerate-zero-start purpose; documented in the SEAM header with the measurement.
- **Files modified:** src/settlement/feasibility.jl
- **Verification:** all feasibility items green (benign :feasible, stress :infeasible, poison :solve_failed); fast suite green
- **Committed in:** 452d2dc

**2. [Rule 1 - Bug] Stress-test poison re-derived: plan's "~50× the branch rating" belongs to the :solve_failed contract, not :infeasible**
- **Found during:** Task 3 (feasibility.jl)
- **Issue:** 50× the 10-pu rating = 500 pu sits far beyond the 2-bus feeder's AC loadability (≈ V²/2X ≈ 25 pu) — no AC solution exists, so the call records :solve_failed, never the thermal :infeasible the test asserts.
- **Fix:** Stress dispatch = 12 pu (1.2× the rating, within loadability) ⇒ converged power flow, thermal ratio 1.2000097738789337, status :infeasible with full diagnostics. The plan's own adjust-the-poison note covers this; the 500-pu poison was reassigned to the solve-failure test where it is deterministic. Status-contract asserts unchanged.
- **Files modified:** test/test_settlement.jl
- **Verification:** measured ratio > 1 with a converged solve; committed in 452d2dc

**3. [Rule 1 - Bug] Arbitrage certificate fixture made energy-scarce (soc0 1.0 → 0.3); ordering assert corrected to the prose intent**
- **Found during:** Task 2 (price_taker.jl)
- **Issue:** Two defects in the plan's Test 3 as literally written: (a) with soc0 = 1.0 the battery is POWER-limited — stranded initial SOC discharges into the cheap hour (measured net[1] = 0.65) and charging never happens, so "charge-low/sell-high" is not exercised; (b) the inline assertion "net_h(1) > net_h(2)" contradicts the plan's own prose (charging DEPRESSES the cheap-hour net; discharging RAISES the dear-hour net).
- **Fix:** soc0 = 0.3 (energy-scarce) makes cheap-hour charging genuinely optimal; asserts follow the prose/physics intent: net[1] < net[2], net[1] < 1e-5 (full PV stored), net[2] > 0.2 (discharging on top of PV), |net| within rated bounds. Measured net ≈ [0, 0.6655] = hand-derived 0.2 + 0.95·(0.3 + 0.95·0.2).
- **Files modified:** test/test_settlement.jl
- **Verification:** measured dispatch matches the hand derivation; committed in 4932420

**4. [Rule 1 - Bug] Separability fixture horizon T=4 → T=12 (Deferrable energy-budget guard)**
- **Found during:** Task 2 (price_taker.jl)
- **Issue:** `_case_a_house`'s internal Deferrable window is `[min(8,T), min(16,T)]` with E/Pmax = 2 — at T = 4 the window collapses to length 1 and the device's own thesis-eq-3.4 guard throws at construction.
- **Fix:** T = 12 (window 8..12, length 5) keeps the production device constants intact; 12-hour strictly-varying price vector.
- **Files modified:** test/test_settlement.jl
- **Verification:** item green; committed in 4932420

**5. [Rule 1 - Bug] Interface-arity fixes in the new tests**
- **Found during:** Tasks 2–3
- **Issue:** (a) `household_dispatches` is deliberately UNEXPORTED (plan exports only the two dispatch names) — the test initially called it bare; (b) the empty-aggs guard test passed `[[ ]]` which fails the typed signature (`Vector{<:Vector{<:Real}}`) with a MethodError before the guard can fire.
- **Fix:** qualify `TSODSO.household_dispatches`; empty-aggs call uses `[[0.0]]` with `T = 1` (the empty-aggs check runs first).
- **Files modified:** test/test_settlement.jl
- **Verification:** guards item green; committed in 4932420 / 452d2dc

---

**Total deviations:** 5 auto-fixed (2 × Rule 3-class design necessity folded into #1; 4 × Rule 1)
**Impact on plan:** All fixes were forced by measured codebase behavior (the v̂ ≥ v restriction, the loadability bound, the device guard) or plan-internal inconsistencies; no scope creep, no golden-file touches, all contracts asserted as planned.

## Issues Encountered

- During Task 1's include-block registration, the `settlement/equity.jl` include was briefly dropped from `src/TSODSO.jl`; the export guard caught it within the same task (7 equity names missing from the exported set) and it was restored before the GREEN commit — never committed broken.
- The RED commit for Task 1 carried provisional pins (1e-12) on the real-run revenue-neutrality item; the GREEN commit re-pinned gate-then-golden from live measurement (2.8658034134118547e-16 → 10×; 0.0 → 1e-15 floor), per the project's measurement-before-golden discipline.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **41-04 (comparison harness)** has everything it needs: `flat_prices`/`tou_prices` for the `:flat`/`:tou` legs, `price_taker_dispatch(es)` (+ `household_dispatches`) for counterfactual dispatch, `ac_feasibility_status` for per-tariff status rows — all exported, all tested, all status/refusal semantics recorded rather than thrown (the CSV contract can record them as rows directly).
- **SETL-01 household attribution** can consume `household_dispatches` for per-house bills at any tariff's price vector.
- No blockers; the full fast suite is green at this HEAD.

## Self-Check: PASSED

- Files exist: src/settlement/tariffs.jl, src/settlement/price_taker.jl, src/settlement/feasibility.jl — verified on disk.
- Commits exist: 6019fe3, b9ada95, cc5502c, 4932420, c79523a, 452d2dc — verified in `git log`.
- Fast suite: 32399 pass / 0 fail / 0 error / 6 broken (expected_broken.txt-listed), exit 0.
- Golden diff clean; solver-abstraction greps clean; export guard green.

---
*Phase: 41-settlement-ledger-equity*
*Completed: 2026-10-25*
