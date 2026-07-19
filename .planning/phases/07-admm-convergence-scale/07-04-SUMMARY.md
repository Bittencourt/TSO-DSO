---
phase: 07-admm-convergence-scale
plan: 04
subsystem: optimization
tags: [admm, boyd, adaptive-rho, dual-residual, socp, clarabel, jump, transactive-pricing]

# Dependency graph
requires:
  - phase: 07-01
    provides: extended AdmmResiduals ledger (8-arg record!, two-residual converged predicate)
  - phase: 07-03
    provides: set_rho! in-place quadratic-penalty updater on AGR-OPT/DSO-OPT (build-once preserved)
  - phase: 06-04
    provides: the hand-rolled dual-ascent solve_admm loop (build-once, welfare-from-primals, PF-04 gate)
provides:
  - solve_admm two-residual stop on the Boyd z-block dual residual s = ρ·‖Δ(pag_dso)‖₂
  - per-unit-normalized stopping tolerances (ε_pri = √p·ε_abs + ε_rel·max(‖a‖,‖pag_dso‖); ε_dual = √p·ε_abs + ε_rel·‖λ‖)
  - residual-balancing adaptive ρ (Boyd §3.4.1) on ε-normalized residuals, driving set_rho! on both subproblems
  - scale-invariant convergence (same config) on the 2-bus AND IEEE-13, PF-04 exact at convergence
affects: [07-05, 07-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Boyd two-residual (primal 2-norm + z-block dual) per-unit stopping"
    - "ε-normalized residual-balancing adaptive ρ (r/ε_pri vs s/ε_dual) with clamp + freeze"
    - "adaptive penalty via set_rho! in lockstep with the unscaled dual ascent (no rebuild, no λ rescale)"

key-files:
  created: []
  modified:
    - src/admm/solve_admm.jl

key-decisions:
  - "Balance ρ on ε-NORMALIZED residuals (r/ε_pri vs s/ε_dual), not raw ‖r‖/‖s‖ — the raw form leaves ρ too small and Clarabel NUMERICAL_ERRORs on IEEE-13"
  - "Retain the tol keyword for call-site compatibility but supersede it with the per-unit two-residual stop"
  - "ρ keyword is the INITIAL ρ₀; freeze adaptation once both normalized residuals ≤ 10×"

patterns-established:
  - "Pattern: ε-normalized residual balancing makes the same (ε_abs,ε_rel,τ,μ,ρ_min,ρ_max) scale-invariant across feeders"

requirements-completed: [ADMM-02]

# Metrics
duration: ~55min
completed: 2026-07-19
---

# Phase 7 Plan 04: Adaptive-ρ Two-Residual ADMM Hardening Summary

**solve_admm now stops on the Boyd z-block dual residual s = ρ·‖Δ(pag_dso)‖₂ with per-unit two-residual tolerances and drives a residual-balancing adaptive ρ (via set_rho!) that converges the 2-bus AND IEEE-13 with one scale-invariant config — the Phase-6 centralized cross-validation stays exact.**

## Performance

- **Duration:** ~55 min
- **Tasks:** 2 (both TDD, `type=auto`)
- **Files modified:** 1 (`src/admm/solve_admm.jl`)
- **Full suite:** 1865 passed, 0 failed, 1 errored (pre-existing IEEE-123 fixture blocker — see below), 2 broken (pre-existing)

## Accomplishments

- **Correct Boyd dual residual (T-07-09 mitigated):** replaced the Phase-6 x-block diagnostic `ρ·Δa` with the z-block change `s = ρ·‖pag_dso − pag_dso_prev‖₂`; primal residual is now the 2-norm `‖a − pag_dso‖₂`. Stop requires BOTH `‖r‖ ≤ ε_pri` AND `‖s‖ ≤ ε_dual` (switched to the extended 8-arg `record!` + `converged(res, ε_pri, ε_dual)`).
- **Per-unit tolerances:** `ε_pri = √p·ε_abs + ε_rel·max(‖a‖,‖pag_dso‖)`, `ε_dual = √p·ε_abs + ε_rel·‖λ‖`, `p = n_load_nodes·T`, defaults `ε_abs=1e-4`, `ε_rel=1e-3`.
- **Residual-balancing adaptive ρ (T-07-10/11/12 mitigated):** `ρ ← τ·ρ` when the primal lags, `ρ ← ρ/τ` when the dual lags, clamped to `[ρ_min, ρ_max]`, frozen once both normalized residuals ≤ 10×. On an actual ρ change, `set_rho!` updates the DSO-OPT and every AGR-OPT penalty in lockstep with the unscaled dual step (no rebuild, no λ rescale, build-once preserved).
- **Scale-invariance proven:** the SAME `(ε_abs,ε_rel,τ,μ,ρ_min,ρ_max)` converge both fixtures; fail-loud maxiter cap intact (now naming both residuals).

## Task Commits

1. **Task 1: Boyd z-block dual residual + per-unit two-residual stopping** — `eef0927` (fix)
2. **Task 2: residual-balancing adaptive ρ driving set_rho!** — `2ac82dc` (feat)

_Both tasks were TDD: the RED @testitems (07-01/07-03 waves) drove the implementation GREEN without editing the tests._

## Files Created/Modified

- `src/admm/solve_admm.jl` — two-residual per-unit stop; z-block dual residual with `pag_dso_prev`; extended `record!`; ε-normalized residual-balancing adaptive ρ with clamp/freeze; `set_rho!` in lockstep; new keywords `ε_abs/ε_rel/τ/μ/ρ_min/ρ_max`; updated header + docstrings; fail-loud cap now reports both residuals.

## Convergence report (success-criterion metric)

Same config `ρ₀=5.0, ε_abs=1e-4, ε_rel=1e-3, τ=2.0, μ=10.0, ρ_min=1e-2, ρ_max=1e4`:

| Case    | iters | ρ schedule                    | welfare gap | PF-04 `exact_maxgap` | DADP match |
|---------|-------|-------------------------------|-------------|----------------------|------------|
| 2-bus   | 2     | 5.0 → 2.5 (dual-lag ÷τ once)  | ≈0 (exact)  | n/a (uncongested)    | +sign, isapprox OK |
| IEEE-13 | 43    | 5 → 10 → 20 → 40 → 80 → 160 (climb), freeze at k=16 (ρ=160) | 2.2e-7 | 7.8e-10 (exact) | norm-isapprox OK (atol 1e-2, rtol 1e-3) |

The IEEE-13 dual residual `s` is the lagging one: primal `‖r‖` reaches ~1e-5 by k~35 while `s` slowly declines to just under `ε_dual≈0.0746` at k=43 — the two-residual stop correctly waits for the price to stop moving.

## Decisions Made

- **ρ keyword = initial ρ₀** (adaptive thereafter); `tol` kept only for call-site compatibility, superseded by the per-unit two-residual stop.
- **Freeze at normalized 10× band** to enter Boyd's fixed-ρ convergence tail; `α=1` (no over-relaxation — out of MVP scope, Pitfall 6).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Balance ρ on ε-normalized residuals, not raw ‖r‖/‖s‖**
- **Found during:** Task 2 (adaptive ρ on IEEE-13)
- **Issue:** The RESEARCH Pattern-4 raw-residual rule (`ρ↑ if ‖r‖ > μ‖s‖`) leaves ρ stuck at ρ₀=5 on IEEE-13: ε_pri (∝ the tiny per-unit injection magnitude ≈1.7e-3) and ε_dual (∝ ‖λ‖, the O(1–10) price ≈9e-2) differ ~50×, so raw ‖r‖=0.10 vs ‖s‖=0.27 reads "balanced" while the primal is 60× its tolerance and the dual only 3×. With ρ too small to regularize the DSO SOCP, Clarabel returns `NUMERICAL_ERROR` by iteration 3 and solve_admm fails loudly.
- **Fix:** Balance on the dimensionless normalized residuals `r̂ = ‖r‖/ε_pri`, `ŝ = ‖s‖/ε_dual` (`ρ↑ if r̂ > μ·ŝ`, `ρ↓ if ŝ > μ·r̂`). This is the standard scaled-residual balancing form and is self-consistent with the freeze/stop tests (which already use `r/ε_pri`, `s/ε_dual`). ρ then climbs 5→160 on IEEE-13 and converges (43 iters); the 2-bus still converges in 2 iters.
- **Files modified:** `src/admm/solve_admm.jl`
- **Verification:** `test_admm_adaptive.jl` scale-invariant item GREEN (2-bus AND IEEE-13); `test_admm.jl` IEEE-13 crossval GREEN.
- **Committed in:** `2ac82dc` (Task 2 commit)

**2. [Rule 3 - Blocking] Restored `converged_flag = false`**
- **Found during:** Task 2 (first adaptive run threw `UndefVarError: converged_flag`)
- **Issue:** Inserting the ρ-state block accidentally displaced the `converged_flag = false` initializer.
- **Fix:** Re-added it immediately before the loop.
- **Files modified:** `src/admm/solve_admm.jl`
- **Verification:** loop runs; all admm items GREEN.
- **Committed in:** `2ac82dc` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 correctness bug in the balancing rule, 1 blocking self-inflicted regression fixed same-task).
**Impact on plan:** The ε-normalized balancing is the load-bearing fix that makes the "same config converges 2-bus AND IEEE-13" success criterion actually hold; no scope creep, no test edits, cross-validation tolerances untouched.

## Issues Encountered

- **IEEE-123 end-to-end crossval (`test_ieee123_admm.jl`) remains RED — pre-existing, out of scope, owned by 07-05.** The failure is an `INFEASIBLE` termination inside the CENTRALIZED `solve_welfare` oracle (line 40 of the test), which runs BEFORE `solve_admm` is even called. The Phase7Fixtures IEEE-123 population (`LOAD_SCALE_IEEE123=0.005`, `PV_SCALE_IEEE123=0.03`, `SEED_IEEE123`) is explicitly documented in the fixture as *"provisional, tuned to green by plan 07-05"*. This error is present at my base commit (8bf57d0) and is NOT caused by `solve_admm`; the fixture is not in this plan's `files_modified`. Verified by faithful replication: the centralized SOCP is infeasible on that population, so neither the oracle nor `solve_admm` (which builds the same infeasible DSO-OPT) can succeed until 07-05 rescales the fixture. No `solve_admm` defect. Not editing the fixture (07-05's parallel-wave domain) or the test (not mine; never edit tests to go green).

## Next Phase Readiness

- `solve_admm` is correct, adaptive, and scale-invariant on the 2-bus + IEEE-13 (43 iters, welfare gap 2.2e-7, PF-04 exact). Ready for 07-05 to green IEEE-123 once the fixture population is tuned to a feasible, voltage-binding regime.
- Extended residual ledger (ρ/ε/price traces) is populated every iteration — ready for the 07-06 CairoMakie plotting extension.

## Self-Check: PASSED

- `src/admm/solve_admm.jl` contains `pag_dso_prev` (plan artifact) — FOUND
- Task 1 commit `eef0927` — FOUND
- Task 2 commit `2ac82dc` — FOUND
- `07-04-SUMMARY.md` — FOUND

---
*Phase: 07-admm-convergence-scale*
*Completed: 2026-07-19*
