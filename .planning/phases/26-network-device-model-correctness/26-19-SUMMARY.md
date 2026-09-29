---
phase: 26-network-device-model-correctness
plan: 19
subsystem: testing
tags: [julia, jump, clarabel, socp, golden-regression, admm, tol-gap]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness
    provides: "FIX-03/04/05 (26-02..26-05), Plan 26-17's re-measured test_ieee13.jl goldens, Plan 26-12's PM-03 ADMM reactive_consensus smart default"
provides:
  - "test_acceptance.jl's GOLDEN_WELFARE/GOLDEN_V9_16 re-pinned byte-identical to test_ieee13.jl's Plan-26-17 values"
  - "D-26-02 resolved for test_acceptance.jl:82 record 1 — ADMM convergence budget re-tuned (maxiter=400, ε_abs=1e-5, ε_rel=1e-4) so the joint active+reactive dual-ascent clears the unchanged isapprox(atol=1e-2, rtol=1e-3) DADP match under PM-03's LIVE reactive coupling"
  - "tol_gap=3e-9 calibrated on the 4 real-impedance IEEE-123 solve_welfare call sites (test_acceptance.jl, test_ieee123_admm.jl x2, test_thesis_repro.jl), clearing the PF-04 precision-floor gate (cluster E) without touching assert_socp_exact!'s own gate"
affects: [26-08-golden-audit, 28-thesis-reproduction-restatement]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Golden re-pin discipline (SC-6/PM-06) continued: cross-referenced values from a sibling file's already-measured re-pin, never independently re-derived, per T-26-34's mitigation"
    - "Convergence-budget re-tune discipline (D-26-02): measured a sweep of (maxiter, ε_abs, ε_rel) empirically, chose the smallest budget with a comfortable (~14x) margin under the UNCHANGED isapprox tolerance, rather than loosening the assertion"
    - "tol_gap calibration via explicit optimizer kwarg on solve_welfare only, never on solve_admm (no such kwarg exists there) and never on assert_socp_exact!'s own atol/rtol"

key-files:
  created: []
  modified:
    - test/test_acceptance.jl
    - test/test_ieee123_admm.jl
    - test/test_thesis_repro.jl

key-decisions:
  - "test_acceptance.jl's GOLDEN_WELFARE/GOLDEN_V9_16 set to the EXACT literal values read from test_ieee13.jl's current source (-4823.496124912337 / 1.03604426055989), not re-measured independently, per the plan's T-26-34 mitigation and this file's own 'reused verbatim' convention"
  - "D-26-02's re-tune uses maxiter=400/ε_abs=1e-5/ε_rel=1e-4 (377 iters, norm(Δ)=0.0050, ~14x margin under bound=0.072) rather than the more aggressive maxiter=2000/ε_abs=1e-7/ε_rel=1e-8 budget 26-12-SUMMARY.md measured (792 iters, elementwise 4.2e-4) — a smaller, faster-solving budget with ample margin was empirically found via a 6-point sweep, avoiding an unnecessarily slow test"
  - "test_thesis_repro.jl's fit_baseline call was left untouched (not one of the plan's '4 affected call sites') after empirically confirming it does not trip the PF-04 gate at default tol_gap on this fixture — only the 4 solve_welfare-based centralized reference solves needed the tol_gap override"
  - "test_thesis_repro.jl's SECONDARY (IEEE-13, non-gated, already-broken=) testitem at line ~124 was left untouched — the plan's read_first and interfaces sections scope Task 2 to the ':62'/REPRO-01 PRIMARY IEEE-123 item only"

requirements-completed: [FIX-01, FIX-02, FIX-03, FIX-04, FIX-05]

# Metrics
duration: 35min
completed: 2026-09-29
---

# Phase 26 Plan 19: test_acceptance.jl golden re-pin + IEEE-123 tol_gap calibration + D-26-02 ADMM budget re-tune Summary

**Re-pinned `test_acceptance.jl`'s IEEE-13 golden constants byte-identical to `test_ieee13.jl`'s Plan-26-17 re-measured values, resolved the orchestrator-assigned D-26-02 deferred item by re-tuning `test_acceptance.jl:82` record 1's ADMM convergence budget (maxiter=400, ε_abs=1e-5, ε_rel=1e-4 — a measured 6-point sweep chose this over both the original too-tight budget and an unnecessarily large one), and calibrated `tol_gap=3e-9` on all 4 real-impedance IEEE-123 `solve_welfare` call sites to clear the PF-04 precision-floor gate (cluster E) without touching `assert_socp_exact!`'s own gate — confirming REPRO-01's DSO-surplus sign flip now holds (observed `acct.dso=3.739 > 0`, `fit_dso=-196.26 < 0`, within the pinned `[0, 7.211]` band).**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-09-28T21:47:00-03:00 (approx, worktree reset + context gathering)
- **Completed:** 2026-09-28T22:22:00-03:00
- **Tasks:** 2 completed (plus 1 orchestrator-assigned additional-scope item folded into Task 1)
- **Files modified:** 3 (`test/test_acceptance.jl`, `test/test_ieee123_admm.jl`, `test/test_thesis_repro.jl`)

## Accomplishments
- `test_acceptance.jl`'s `GOLDEN_WELFARE`/`GOLDEN_V9_16` re-pinned to `-4823.496124912337`/`1.03604426055989`, byte-identical to `test_ieee13.jl`'s current (Plan-26-17) values, with inline old→new+cause comments citing PM-06/26-POSTMERGE-TRIAGE.md.
- **D-26-02 resolved** (orchestrator-assigned additional scope, `test_acceptance.jl:82` record 1 only): measured a 6-point sweep of ADMM convergence budgets (`maxiter`, `ε_abs`, `ε_rel`) on the exact fixture/config; the pre-PM-03-tuned budget (`ρ=100, maxiter=200`, default `ε_abs=1e-4/ε_rel=1e-3`) converges in 103 iters but fails the norm-based `isapprox(atol=1e-2, rtol=1e-3)` DADP match (`norm(Δ)=0.697` vs `bound=0.072`); `maxiter=400, ε_abs=1e-5, ε_rel=1e-4` converges in 377 iters to `norm(Δ)=0.0050` (elementwise max `|Δ|=0.0020`), a ~14x margin under the SAME unchanged bound. The `isapprox` tolerances themselves are untouched — this is a genuine convergence-budget fix, not a loosened assertion.
- All 4 real-impedance IEEE-123 `solve_welfare` call sites (`test_acceptance.jl`'s IEEE-123 item, `test_ieee123_admm.jl`'s crossval and voltage-binding-margin items, `test_thesis_repro.jl`'s REPRO-01 primary item) given an explicit `optimizer = select_optimizer(SOCP(); tol_gap_abs = 3e-9, tol_gap_rel = 3e-9)` kwarg, clearing the PF-04 gate (ratio 3.94 at default → ratio well under 1 at `3e-9`, objective unchanged to 8+ significant digits).
- Confirmed `solve_admm` has no `tol_gap`/`optimizer` override path at all (no such kwarg on `solve_admm`/`build_dso_opt`) — but empirically it already clears its own (looser, `< 1e-3`) `exact_maxgap` threshold at the default solver tolerance on this fixture, so no ADMM-side tightening was needed or possible.
- Confirmed `fit_baseline`'s nested solve does NOT trip the PF-04 gate on the IEEE-123 fixture at default `tol_gap` (empirically verified) — correctly left untouched, matching the plan's "4 affected call sites" scope (not 5).
- REPRO-01's sign-flip finding is now assessable (previously masked by the gate throw): `acct.dso = 3.739 > 0`, `fit_dso = -196.26 < 0`, magnitude within the pinned `[0, 7.211]` band — the sign flip HOLDS. Restating/interpreting this finding is explicitly Phase 28's scope (26-CONTEXT.md deferred ideas); not attempted here, only the testitem's own pass/fail is confirmed.
- `src/models/exactness.jl` (the PF-04 gate itself) is confirmed unchanged (`git diff` empty) throughout both tasks.

## Task Commits

Each task was committed atomically:

1. **Task 1: Re-pin test_acceptance.jl's IEEE-13 golden constants + resolve D-26-02 (additional scope)** - `9768ce7` (test)
2. **Task 2: Calibrate tol_gap on the 4 real-impedance IEEE-123 testitems** - `b69f032` (test)

**Plan metadata:** SUMMARY.md commit (this commit, immediately following)

## Files Created/Modified
- `test/test_acceptance.jl` - `GOLDEN_WELFARE`/`GOLDEN_V9_16` re-pinned with old→new+cause comments; the IEEE-13 item's `solve_admm` call re-tuned (`maxiter=400, ε_abs=1e-5, ε_rel=1e-4`) with a D-26-02 inline comment; the WR-01 comment's stale "observed max |Δ| ≈ 0.0166" illustration updated to the new measured values; the IEEE-123 item's `solve_welfare` call given the `tol_gap=3e-9` optimizer kwarg with an inline cause comment.
- `test/test_ieee123_admm.jl` - Both `@testitem`s' `solve_welfare` calls (crossval item and voltage-binding-margin item) given the `tol_gap=3e-9` optimizer kwarg with inline cause comments.
- `test/test_thesis_repro.jl` - The REPRO-01 primary (`:62`, IEEE-123) `@testitem`'s `solve_welfare` call given the `tol_gap=3e-9` optimizer kwarg with an inline cause comment; the secondary IEEE-13 item (line ~124) left untouched (out of this plan's declared scope).

## Decisions Made
- Chose `maxiter=400, ε_abs=1e-5, ε_rel=1e-4` for the D-26-02 re-tune after measuring a 6-point sweep: this budget gives a ~14x margin under the norm-based `isapprox` bound at 377 iters (~52s wall time in isolation), versus the more conservative `maxiter=2000, ε_abs=1e-7, ε_rel=1e-8` budget 26-12-SUMMARY.md had already measured (792 iters, tighter elementwise convergence but much slower) — a smaller budget with ample (not marginal) margin was preferred to avoid slowing the suite unnecessarily.
- Left `fit_baseline`'s internal nested solve untouched after confirming empirically it does not trip PF-04 on this fixture at default `tol_gap` — matches the plan's explicit "4 affected call sites" (not 5) scope; no speculative tightening applied where it wasn't needed.
- Left `test_thesis_repro.jl`'s secondary IEEE-13 (non-gated, already `broken=`) testitem untouched — the plan's `<read_first>`/`<interfaces>` sections scope Task 2 to the primary `:62` IEEE-123 item only, and that secondary item is not part of "the SAME real-impedance IEEE-123 feeder" cohort this plan's `must_haves` describe.
- Did not attempt to tighten `solve_admm`'s own internal DSO-OPT solver tolerance for D-26-02, since no such kwarg exists (`solve_admm`/`build_dso_opt` accept no `optimizer` override) — the fix available and applied was the ADMM outer-loop's own `maxiter`/`ε_abs`/`ε_rel` stopping-criteria kwargs, which are a different (and here, sufficient) knob.

## Deviations from Plan

### Auto-fixed Issues

None beyond the plan's own explicitly-assigned additional scope (D-26-02 resolution), which was itself the orchestrator's assignment, not a self-discovered deviation.

---

**Total deviations:** 0 unplanned auto-fixes.
**Impact on plan:** Both tasks executed per the plan's `<action>`/`<interfaces>` text; the orchestrator's additional-scope D-26-02 resolution was folded into Task 1 as instructed, using a measured (not guessed) re-tune.

## Issues Encountered
- Confirmed (again, per the `gsd-plan-verify-testitemrunner-trap` memory) that `test/fixtures_phase4.jl` and `test/fixtures_phase7.jl`'s `@testmodule` macro is undefined under `julia --project=.` outside TestItemRunner. Worked around identically to prior plans: a `sed` substitution of the `@testmodule X begin` header line only (mechanical, no logic change) into a scratchpad copy, then `include`d for direct-script verification. No test file in the repository was modified by this substitution.
- The D-26-02 convergence-budget sweep (6 points) took ~5 minutes of solver wall time in the background; ran it as a background task per the environment's guidance rather than blocking, then read the result once complete.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `test_acceptance.jl`'s IEEE-13 item (both records) and IEEE-123 item, both `test_ieee123_admm.jl` items, and `test_thesis_repro.jl`'s REPRO-01 primary item are all independently verified passing via direct-script reproduction against the actual edited files.
- `D-26-02` is now fully resolved for `test_acceptance.jl:82` record 1 — the SAME deferred item's OTHER named site, `test/test_admm.jl:121`, remains open and is explicitly OUT of this plan's `files_modified` scope; whichever plan/step owns `test_admm.jl` should apply an analogous re-tune (this plan's measured sweep numbers are directly transferable, since it is the identical fixture/config).
- `assert_socp_exact!`'s gate (`src/models/exactness.jl`) is confirmed unchanged across this plan's full diff.
- Ready for the orchestrator's full-suite green-at-close verification alongside the other parallel gap-closure plans.

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-29*

## Self-Check: PASSED
