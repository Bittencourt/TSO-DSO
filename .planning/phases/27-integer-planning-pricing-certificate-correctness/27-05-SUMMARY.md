---
phase: 27-integer-planning-pricing-certificate-correctness
plan: 05
subsystem: pricing-certificate
tags: [socp, exactness-gate, jump, clarabel, fit-baseline, almost-optimal, fix-09]

# Dependency graph
requires:
  - phase: 27-integer-planning-pricing-certificate-correctness
    plan: 02
    provides: assert_socp_exact! HYBRID per-branch exactness floor (atol_b = max(τ_solver,
      ε*ref_b)), the gate this plan wires into fit_baseline's previously-ungated SITE 2
provides:
  - fit_baseline(...; on_inexact::Symbol=:error) — SITE 2 (FIT AC-PF) is now exactness-
    certified by default (throws on a genuinely inexact cone); :report returns the measured
    certificate (a new socp_maxgap field) instead of throwing
  - solve_welfare(...; allow_almost::Bool=false) — a new, narrowly-scoped kwarg forwarded
    verbatim to assert_solved!, defaulting false everywhere
  - fit_baseline's SITE-3 nested solve_welfare cross-check: a bounded ALMOST_OPTIMAL retry-
    and-verify fallback gated behind a measured, named FIT_SITE3_ALMOST_GAP_TOL
  - scripts/repro_stability_check.jl's REPRO_MAX_ITER env var (mirrors REPRO_TOL_GAP),
    combinable, used to root-cause the flake
  - 27-FINDINGS.md entries: the max_iter hypothesis REFUTED (byte-identical Clarabel
    iteration traces at max_iter=200/400/2000), a related "flake landscape worsened since
    Phase 18" drift finding, and a "Task 1's new gate now catches a genuine O(100) cone
    slack on 2 sweep points" discovery
affects: [28-thesis-reproduction-restatement (should re-measure solve_welfare's own flake
  rate at tight tol_gap before assuming the Phase-18 0/5 figure still holds)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "on_inexact::Symbol kwarg-gated assertion (:error default throws, :report returns a
      certificate) mirroring assert_battery_complementarity!'s on_violation idiom"
    - "Retry-once-then-verify bounded ALMOST_OPTIMAL acceptance: retry with allow_almost=true
      ONLY for a specifically-identified failure class (occursin(\"ALMOST_OPTIMAL\", e.msg)),
      then independently verify the achieved primal-dual gap against a measured, named
      threshold before trusting the near-feasible result — never a bare 'trust ALMOST_OPTIMAL'"
    - "Measure-then-pin gap tolerance via abs(objective_value(model) - dual_objective_value(model))
      at the SAME near-feasible point (no second reference solve), mirroring
      KNOWN_OPTIMUM_ATOL's protocol"

key-files:
  created: []
  modified:
    - src/pricing/fit.jl
    - src/models/welfare_solve.jl
    - test/test_fit.jl
    - scripts/repro_stability_check.jl
    - .planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md

key-decisions:
  - "The pv_scale=2.0 high-PV stress fixture (Phase4Fixtures.high_pv_feeder, EXACT-04's own
    substrate) was chosen as the synthetic inexact-FIT regression because fit_baseline's SITE
    2 relaxes the voltage band to [0.8,1.2] internally, so EXACT-04's own pv_scale=1.2
    (tuned against the tighter [0.95,1.05] band) stays EXACT there — a larger back-feed
    (measured maxgap≈6.1, an O(1) cone slack) was needed to pin the wider relaxed cap."
  - "max_iter root-cause: tested 200/400/2000 with verbose=true iteration traces, not just
    the terminal status — found BYTE-IDENTICAL termination at iteration 24 across all three,
    conclusively refuting slow convergence and confirming a genuine Clarabel conditioning
    wall (matching the IEEE-8500 precedent)."
  - "FIT_SITE3_ALMOST_GAP_TOL set to 10x the measured achieved gap (7.749e-6 -> 7.749e-5),
    reusing KNOWN_OPTIMUM_ATOL's own margin convention rather than inventing a new one."
  - "The retry-and-verify wrapper discriminates on occursin(\"ALMOST_OPTIMAL\", e.msg) before
    retrying — verified via a negative control (an unrelated ArgumentError is never retried)
    — mirroring solve_with_retry!'s RETRYABLE_STATUSES discipline of never retrying a genuine
    modeling failure."

patterns-established:
  - "A cross-check solve whose dual output is never read by its caller is the ONE sanctioned
    class of caller for assert_solved!'s allow_almost=true, PROVIDED the caller independently
    verifies precision (primal-dual gap) before trusting the accepted objective value — never
    a bare relaxation of the gate."

requirements-completed: [FIX-09]

# Metrics
duration: ~40min
completed: 2026-09-29
---

# Phase 27 Plan 05: FIT-Baseline Certificate + ALMOST_OPTIMAL Root Cause Summary

**`fit_baseline`'s previously-ungated FIT AC-PF step is now exactness-certified via a new `on_inexact::Symbol` kwarg, and its nested `solve_welfare` cross-check's `ALMOST_OPTIMAL` flake is root-caused (a genuine Clarabel conditioning wall, conclusively NOT fixable by raising `max_iter` — byte-identical iteration traces at 200/400/2000) and bounded behind a measured, named gap tolerance.**

## Performance

- **Duration:** ~40 min
- **Started:** 2026-09-29T09:34:29Z (worktree base assertion)
- **Completed:** 2026-09-29T10:12:00Z (approx)
- **Tasks:** 2 plan tasks completed
- **Files modified:** 5 (`src/pricing/fit.jl`, `src/models/welfare_solve.jl`, `test/test_fit.jl`, `scripts/repro_stability_check.jl`, `27-FINDINGS.md`)

## Accomplishments

- `fit_baseline`'s FIT AC-PF step (SITE 2 of 3) — previously gated ONLY by `assert_solved!`,
  silently assuming its SOC relaxation's exactness — now runs `assert_socp_exact!` via a new
  `on_inexact::Symbol = :error` kwarg (default: throw; `:report`: return the measured
  `socp_maxgap` certificate instead), mirroring `assert_battery_complementarity!`'s
  `on_violation` idiom exactly. Verified on both a genuinely-exact canonical fixture
  (unchanged behavior) and a genuinely-inexact synthetic fixture (pv_scale=2.0 on
  `Phase4Fixtures.high_pv_feeder`, measured maxgap≈6.1) via direct scripts and a new
  `@testitem`.
- The `fit_baseline` `ALMOST_OPTIMAL` flake at `tol_gap=1e-10` (carried over from Phase 18,
  never root-caused by any prior session) is DEFINITIVELY root-caused this plan: the untried
  `max_iter` hypothesis was tested via a new `REPRO_MAX_ITER` env var on
  `scripts/repro_stability_check.jl`, and Clarabel's own `verbose=true` iteration trace is
  BYTE-IDENTICAL at `max_iter ∈ {200, 400, 2000}` — every run stalls at iteration 24 with an
  identical `pcost`/`dcost`/`gap`, conclusively refuting slow convergence.
- Applied CONTEXT's locked fallback: a new `allow_almost::Bool = false` kwarg on
  `solve_welfare` (defaults `false` everywhere — every pre-existing call site unaffected).
  `fit_baseline`'s SITE-3 cross-check is the ONLY caller that ever passes `allow_almost=true`,
  and only as a one-shot retry after a SPECIFICALLY `ALMOST_OPTIMAL`-class failure, verified
  against a NEW measured constant `FIT_SITE3_ALMOST_GAP_TOL = 7.74884392740205e-5` (10x the
  measured achieved gap) before accepting the near-feasible result.
- A related, honestly-documented discovery: the flake landscape has WORSENED since Phase 18
  (likely Phase 26's SOC T+1 extension) — `solve_welfare`'s OWN top-level call now flakes
  100% (20/20) at `tol_gap=1e-10` on the documented fixture, vs. the Phase-18-documented 0/5.
  This is out of this plan's scope (it is not `fit_baseline`) but recorded in `27-FINDINGS.md`
  for Phase 28 awareness.
- A THIRD discovery surfaced during the closing full-suite confirmation: Task 1's NEW SITE-2
  gate correctly catches a genuine, large (`maxgap≈155-200`) cone slack in `fit_baseline` on
  2 of 5 population-scale sweep points — a pre-existing silent-wrongness FIX-09 exists to
  close, now visible for the first time (not a regression).

## Task Commits

Each task was committed atomically (Task 1 as a TDD RED/GREEN pair):

1. **Task 1 (RED): failing test for fit_baseline SITE-2 exactness gate** - `fc1f22b` (test)
2. **Task 1 (GREEN): wire assert_socp_exact! into fit_baseline's FIT AC-PF via on_inexact** - `cb9e470` (feat)
3. **Task 2: root-cause the ALMOST_OPTIMAL flake (max_iter experiment) and bound it** - `24fee51` (fix)

## TDD Gate Compliance

Task 1 (`tdd="true"`): RED gate confirmed by temporarily reverting `src/pricing/fit.jl` to
`HEAD` and observing the expected `MethodError` (unsupported `on_inexact` kwarg) before
restoring and committing `fc1f22b`. GREEN gate confirmed via the plan's own Task-1 `<verify>`
script plus the new synthetic-inexact-fixture script, both passing after `cb9e470`. No
REFACTOR commit was needed (no behavior-preserving cleanup pass followed).

## Files Created/Modified

- `src/pricing/fit.jl` — `fit_baseline` gains `on_inexact::Symbol=:error` (SITE 2 exactness
  gate), the new `FIT_SITE3_ALMOST_GAP_TOL` measured constant, and SITE 3's bounded
  `ALMOST_OPTIMAL` retry-and-verify wrapper. Returns a new `socp_maxgap` field.
- `src/models/welfare_solve.jl` — `solve_welfare` gains `allow_almost::Bool=false`, forwarded
  verbatim to `assert_solved!`. Docstring updated.
- `test/test_fit.jl` — new `@testitem` (synthetic inexact-FIT fixture, `on_inexact=:error`
  throws / `:report` returns a finite certificate / invalid value raises `ArgumentError`).
- `scripts/repro_stability_check.jl` — new `REPRO_MAX_ITER` env var, combinable with
  `REPRO_TOL_GAP`, threaded through the existing `optimizer` kwarg mechanism.
- `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md` —
  appended (did not touch 27-01/27-02's existing sections): the max_iter root-cause finding
  (F-27-05-1), the Phase-18-drift finding (F-27-05-2), and the full-suite confirmation run.

## Decisions Made

- Chose the `pv_scale=2.0` high-PV stress fixture (not EXACT-04's own `pv_scale=1.2`) as the
  synthetic inexact-FIT regression, since SITE 2's internal voltage-relaxation to `[0.8,1.2]`
  needs a larger back-feed to pin its own, wider cap than EXACT-04's tighter-band fixture.
- Followed `KNOWN_OPTIMUM_ATOL`'s 10x-margin convention for `FIT_SITE3_ALMOST_GAP_TOL` rather
  than inventing a new measurement formula.
- Discriminated the SITE-3 retry on `occursin("ALMOST_OPTIMAL", e.msg)` rather than blindly
  retrying any exception, verified via a negative control (an unrelated `ArgumentError` from
  an empty-aggregator boundary guard is never retried) — mirrors `solve_with_retry!`'s
  `RETRYABLE_STATUSES` discipline.
- Did not attempt to fix the OUT-OF-SCOPE Phase-18-drift finding (raw `solve_welfare` calls
  flaking outside `fit_baseline`) — recorded as a fact for Phase 28, not silently absorbed or
  fixed beyond this plan's `files_modified`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] N/A — no bugs found requiring auto-fix beyond the plan's own scope**

No Rule 1/2/3 deviations were needed. The plan's own Task 2 `<action>` anticipated BOTH
outcomes ((a) resolved by max_iter, (b) genuine conditioning wall) and specified the exact
fallback mechanism for outcome (b), which is what was measured and implemented — this is
plan-anticipated work, not a deviation.

---

**Total deviations:** 0
**Impact on plan:** None — both tasks executed within the plan's own anticipated branches.

## Issues Encountered

- The shared 4-core/15GB machine was heavily loaded during Task 2's investigation (other
  parallel executors' Julia processes; load average observed up to ~5.5), causing several
  background verification runs to take much longer than expected or appear to stall. Worked
  around by using smaller, targeted diagnostic scripts (isolated iteration-trace comparison,
  isolated SITE-3 wrapper logic tests) to obtain rigorous, direct evidence before the full
  `scripts/repro_stability_check.jl` run eventually completed and confirmed the same
  conclusions.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- FIX-09 is closed: `fit_baseline`'s FIT AC-PF step is exactness-certified by default; the
  `ALMOST_OPTIMAL` flake is root-caused (genuine conditioning wall, NOT max_iter-fixable) and
  bounded behind a measured gap tolerance, narrowly scoped to SITE 3 only.
- Every other `assert_socp_exact!` call site and every other `solve_welfare` call site is
  confirmed unaffected (`allow_almost` defaults `false` everywhere else).
- **Carried forward for Phase 28 (thesis-reproduction restatement) awareness:** the flake
  landscape on the Phase-17-retuned IEEE-123 population point has WORSENED since Phase 18
  (`solve_welfare`'s own top-level call now flakes 20/20 at `tol_gap=1e-10` vs. the documented
  0/5), plausibly from Phase 26's SOC T+1 extension (not confirmed — a bisection was out of
  this plan's scope). A SECOND full run at DEFAULT settings (no env override at all) shows the
  SAME 20/20 flake rate, but via `assert_socp_exact!` throwing (maxgap≈4.38e-6) rather than
  `ALMOST_OPTIMAL` — confirmed NOT a FIX-08 regression (the pre-FIX-08 flat `atol=1e-6` is
  itself smaller than the measured gap and would have thrown too). This population point can
  no longer produce ANY exactness-certified price at this session's code state. Also:
  `fit_baseline`'s NEW SITE-2 gate now genuinely refuses population-scale sweep points (2/5 at
  the tight tolerance, `δ=-0.05,-0.02`; 1/5 at default, `δ=0.05`) for a large, real cone slack
  — any Phase 28
  work reusing this population point's FIT baseline should expect this.

---
*Phase: 27-integer-planning-pricing-certificate-correctness*
*Completed: 2026-09-29*

## Self-Check: PASSED

- FOUND: `src/pricing/fit.jl`
- FOUND: `src/models/welfare_solve.jl`
- FOUND: `test/test_fit.jl`
- FOUND: `scripts/repro_stability_check.jl`
- FOUND: `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md`
- FOUND: `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-05-SUMMARY.md`
- FOUND commit: `fc1f22b`
- FOUND commit: `cb9e470`
- FOUND commit: `24fee51`
