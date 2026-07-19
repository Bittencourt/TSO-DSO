---
phase: 07-admm-convergence-scale
plan: 05
subsystem: testing
tags: [admm, ieee123, socp, clarabel, cross-validation, dadp, exactness, adaptive-rho]

# Dependency graph
requires:
  - phase: 07-admm-convergence-scale (07-02)
    provides: ieee123_modified() fixture + ieee123_load_nodes() load/transit split
  - phase: 07-admm-convergence-scale (07-04)
    provides: adaptive-ρ two-residual solve_admm + set_rho! + transit DSO-OPT relaxation
provides:
  - IEEE-123 voltage-constrained ADMM convergence certified end-to-end (~17 iters, λ→DADP, PF-04 exact)
  - Feeder-scale (1 MVA) rescale of the IEEE-123 fixture for numerically-robust exactness at scale
  - Seeded 85-load-node population that is feasible AND voltage-binding, exercising the 37 transit buses
  - Phase-6/7 regression re-confirmed green under adaptive ρ + tightened per-unit tolerances
affects: [phase-08-experiment-harness, phase-09-regression-docs]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Feeder-scale per-unit base for distribution SOCP: keep quantities O(0.1-1) pu so the PF-04 atol floor and Clarabel ρ-conditioning stay well away from the numerical noise floor"
    - "Centralized-SOCP cross-validation as the load-bearing λ→DADP gate at IEEE-123 scale (A5), with PF-04 exactness + PRICE-04 economic-direction as additional certificates"

key-files:
  created:
    - .planning/phases/07-admm-convergence-scale/07-05-SUMMARY.md
  modified:
    - src/data/ieee123.jl
    - test/fixtures_phase7.jl
    - test/test_ieee123_admm.jl

key-decisions:
  - "Rescale the IEEE-123 fixture to a 1 MVA feeder-scale base (was 100 MVA) — the 100 MVA transmission base put every distribution quantity at ~1e-3 pu, at the numerical noise floor of both the PF-04 exactness atol and Clarabel's ρ-penalty conditioning, making convergence + exactness fragile."
  - "Populate only the 85 spot-load nodes (not all 122 non-root buses) so the ~37 junction buses are genuine zero-injection transit nodes, exercising the 07-03 relaxation — and matching the thesis Case-B 85-load-node design."
  - "Tighten the SHARED per-unit stopping tolerances to ε_abs=1e-5 / ε_rel=1e-4 (from 1e-4 / 1e-3) uniformly across all fixtures — a strictly-stronger, still scale-invariant stop that settles the fast-collapsing IEEE-123 primal's DADP tail onto the centralized dual."
  - "Take the centralized-SOCP cross-validation path (A5): the monolithic 123-bus × 24h SOCP solves in Clarabel in seconds on the feeder-scale base, so λ→DADP is certified directly against extract_dlmp rather than the residual-only fallback certificate."

patterns-established:
  - "IEEE-123 convergence certificate: centralized OPTIMAL + welfare rgap + per-node λ match + PF-04 exact_maxgap + PRICE-04 direction"

requirements-completed: [ADMM-02]

# Metrics
duration: 90min
completed: 2026-07-19
---

# Phase 7 Plan 05: IEEE-123 ADMM Convergence & Scale Summary

**Adaptive-ρ ADMM converges on the voltage-constrained IEEE-123 feeder in ~17 iterations with λ_j → DADP cross-validated against the centralized SOCP (max gap ~0.003 pu), PF-04 exact at the converged point (exact_maxgap ~1e-9), and the ~37 transit buses handled — full suite 0 fail / 0 error.**

## Performance

- **Duration:** ~90 min
- **Started:** 2026-07-19
- **Completed:** 2026-07-19
- **Tasks:** 2 (1 with a code artifact; 1 verification/regression gate)
- **Files modified:** 3

## Accomplishments

- **IEEE-123 scenario made FEASIBLE and voltage-binding.** The centralized SOCP oracle now solves OPTIMAL (was INFEASIBLE). Solved voltages span V ∈ [0.9155, 1.0406] — under-voltage on the long load laterals and over-voltage under midday PV reverse flow — a genuinely voltage-constrained case, not a slack one.
- **ADMM converges in ~tens of iterations.** With the SAME shared adaptive-ρ config as 2-bus / IEEE-13 (RHO0=5, τ=2, μ=10, ρ∈[1e-2, 1e4]), the run converges in ~17 iterations (both residuals below their per-unit thresholds).
- **λ_j → DADP certified by centralized cross-validation (A5).** ADMM welfare matches the monolithic objective to relative gap ~1.2e-6; per-load-node max |λ − extract_dlmp| ≈ 0.0026 pu, inside the atol=1e-2 / rtol=1e-3 cross-validation tolerance.
- **PF-04 exactness robust at scale.** Converged exact_maxgap ≈ 1e-9 (cone magnitude O(1) → several orders above the atol floor) — no relaxation slack, prices trustworthy. This was the crux: the prior 100 MVA base gave cone magnitudes ~1e-6 right at the atol floor, where exactness flickered on/off.
- **Transit buses handled.** The 85-load-node population leaves ~37 junction buses as zero-injection transit nodes; build_dso_opt accepts them (no throw), and the test asserts the split is real.
- **Regression + phase gate green.** Full suite: 1874 passed, 2 broken (pre-existing), 0 failed, 0 errored. The Phase-6/7 2-bus + IEEE-13 cross-validation and scale-invariance items stay green under adaptive ρ and the tightened tolerances; no PF-04 / App. C gate weakened.

## Task Commits

1. **Task 1: IEEE-123 ADMM convergence + λ→DADP cross-validation + PF-04 exactness** — `74324a3` (test)
2. **Task 2: Phase-6 regression + full-suite green gate** — no new code artifact; the regression is already covered by the `test_admm_adaptive` scale-invariance items (2-bus + IEEE-13) and the `test_admm` crossval items, all green in the full-suite run. Convergence certificate recorded here.

**Plan metadata:** committed with this SUMMARY.

## Files Created/Modified

- `src/data/ieee123.jl` — Rescaled the fixture to a feeder-scale `S_base = 1 MVA` base (head limit 3.8 MVA ⇒ 3.8 pu) and re-tuned the representative line/switch per-unit impedances (line r/x 0.005/0.0025, switch 0.0003/0.00015) so distribution quantities land at O(0.1–1) pu, keeping the SOC cone well above the exactness atol floor and the solved voltages binding the Case-B band. Structure (radial, relabel, 85-load split) unchanged; all `test_ieee123.jl` structural invariants still hold.
- `test/fixtures_phase7.jl` — Tuned the IEEE-123 seeded population: default to the 85 `ieee123_load_nodes()` (transit buses exercised), `LOAD_SCALE=0.03`, `PV_SCALE=0.06`, new `DEV_SCALE=0.05` (shrinks the O(1)-pu flexible thermostatic/deferrable ratings to residential order); tightened the shared per-unit tolerances to `EPS_ABS=1e-5`, `EPS_REL=1e-4`.
- `test/test_ieee123_admm.jl` — Filled the `ieee123`/`crossval` @testitem: transit-split assertion, centralized cross-validation (documented A5 path taken), ~tens-of-iters bound (`≤ 100`), welfare + per-node λ match, PF-04 exact_maxgap, and a PRICE-04 economic-direction certificate (all DADPs > 0; feeder-average DADP tracks the λ₀ evening-peak-vs-trough shape).

## Convergence Certificate (recorded for Task 2)

| Quantity | Value | Method / Gate |
|----------|-------|---------------|
| ρ schedule | ρ₀ = 5, τ = 2, μ = 10, ρ ∈ [1e-2, 1e4], clamp+freeze | shared config (ADMM-02) |
| ADMM iterations | ~17 | two-residual per-unit stop |
| Welfare relative gap | ~1.2e-6 | vs centralized `objective_value` |
| max \|λ − DADP\| | ~0.0026 pu | vs centralized `extract_dlmp` (A5 cross-validation) |
| Converged exact_maxgap | ~1e-9 | PF-04 `assert_socp_exact!` |
| Solved voltage band | V ∈ [0.9155, 1.0406] | voltage-binding, in Case-B band |
| Load / transit split | 85 load nodes / 37 transit | transit relaxation exercised |

Convergence-check method: **centralized cross-validation** (A5) — the monolith is solvable, so it is used directly (the strongest gate, T-07-14); the residual→0 + PF-04 + PRICE-04 fallback certificate was NOT needed.

## Decisions Made

See `key-decisions` frontmatter. The load-bearing one: the infeasibility + fragility were a *scale* problem, not a tuning problem — the 100 MVA transmission base is wrong for a 4.16 kV distribution feeder and pushed every quantity to the numerical noise floor. A feeder-scale base fixes both feasibility and exactness robustness at once.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Rescaled the IEEE-123 fixture base + impedances beyond the plan's declared file set**
- **Found during:** Task 1 (IEEE-123 convergence)
- **Issue:** The plan declared `files_modified: [test/test_ieee123_admm.jl]` only, but the centralized oracle was INFEASIBLE and — once feasible via population tuning — the exactness gate and ADMM conditioning were numerically fragile because the 100 MVA base put all distribution quantities at ~1e-3 pu (at the PF-04 atol floor and Clarabel's ρ-conditioning noise floor). Test-layer population tuning alone could not fix this; the fixture's per-unit base and representative impedances had to be rescaled. The task objective explicitly authorized tuning the population and "if needed, the representative per-unit impedances … keep radial + magnitude-band valid."
- **Fix:** Changed `IEEE123_BASE` to a 1 MVA feeder-scale base and re-tuned the representative line/switch impedances in-band; retuned the Phase7Fixtures population (85 load nodes, load/PV/device scales) and tightened the shared per-unit tolerances.
- **Files modified:** `src/data/ieee123.jl`, `test/fixtures_phase7.jl` (in addition to the planned `test/test_ieee123_admm.jl`)
- **Verification:** `test_ieee123.jl` structural invariants (radial, contiguous ids, 85-load split, r>0, x>0, 0<smax<100) all still green; centralized OPTIMAL; ADMM converges with λ→DADP and PF-04 exact; full suite 0 fail / 0 error.
- **Committed in:** `74324a3` (Task 1 commit)

**2. [Rule 3 - Blocking] Tightened the SHARED per-unit stopping tolerances (ε_abs 1e-4→1e-5, ε_rel 1e-3→1e-4)**
- **Found during:** Task 1
- **Issue:** On the healthy-magnitude IEEE-123 case the primal residual collapses in a handful of iterations, so at the original 1e-4/1e-3 tolerances the two-residual stop fired while the DADP tail was still ~0.02 pu from the centralized dual (just over the cross-val atol=1e-2).
- **Fix:** Tightened the tolerances UNIFORMLY across all fixtures (a strictly-stronger, never-weaker stop, preserving scale-invariance). Settles the IEEE-123 DADP to ~0.003 pu at the cost of a few extra iterations.
- **Files modified:** `test/fixtures_phase7.jl`
- **Verification:** The `test_admm_adaptive` scale-invariance item (2-bus AND IEEE-13) and `test_admm_dualresid` (2-bus) still converge and pass; full suite green.
- **Committed in:** `74324a3` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 3 - blocking feasibility/correctness).
**Impact on plan:** Necessary to make the IEEE-123 scenario feasible and its prices trustworthy at scale. No gate weakened (both changes are strictly-stronger or numerically-neutralizing); no scope creep beyond making the declared success criterion achievable. The base/impedance change is confined to representative fixture data (numerical fidelity is explicitly not the fixture's gate per T-07-05).

## Issues Encountered

- **Initial INFEASIBLE centralized oracle:** the provisional population put ~0.4–6 pu of mandatory inelastic load across the feeder against a 0.038 pu head limit. Diagnosed by sweeping load/PV scales.
- **Numerical exactness fragility at the 100 MVA base:** even feasible small-magnitude configs tripped `assert_socp_exact!` (cone gap ~1e-6 ≈ atol floor) or Clarabel `NUMERICAL_ERROR` under a climbing ρ. Root-caused to the transmission-scale base and resolved by the feeder-scale rescale (cone magnitudes O(1), exactness ratio ~1e-7 — robust).

## Next Phase Readiness

- IEEE-123 convergence + cross-validation is the phase's scale target (Success Criterion 3); it is met. The plottable diagnostics (`AdmmResiduals` traces) are available for the Phase-9 literate convergence study.
- Phase 8 (experiment harness) can reuse `ieee123_modified()` + `build_ieee123_aggregators` as a ready, feasible, voltage-binding scale scenario.
- Note for Phase 9 regression: the fixture impedances are representative (not thesis App. E verbatim); the exact per-terminal r/x table drops into `IEEE123_BRANCH_DATA` when available without touching topology or tests.

## Self-Check: PASSED

- `74324a3` (Task 1) present in git history.
- `src/data/ieee123.jl`, `test/fixtures_phase7.jl`, `test/test_ieee123_admm.jl` present.
- Full suite verified: 1874 passed, 2 broken (pre-existing), 0 failed, 0 errored.

---
*Phase: 07-admm-convergence-scale*
*Completed: 2026-07-19*
