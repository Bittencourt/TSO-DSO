---
phase: 18-directional-thesis-reproduction
plan: 02
subsystem: test-validation
tags: [julia, testitems, welfare-accounting, fit-baseline, reproducibility, gate-then-golden]

# Dependency graph
requires:
  - phase: 18-directional-thesis-reproduction
    plan: 01
    provides: "results/repro_stability_check/findings.txt's committed RECOMMENDED BAND line (DSO_BAND_LO=0.0, DSO_BAND_HI=5.58855710237937), the golden band this plan pins verbatim"
provides:
  - "test/test_thesis_repro.jl — the REPRO-01 gate-then-golden @testitem regression anchor: primary IEEE-123 real-impedance item (5 hard gates incl. the pinned DSO-surplus magnitude band) + secondary non-gated IEEE-13 qualitative cross-check"
affects: [18-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Gate-then-golden @testitem (test_acceptance.jl's convention): exactness gate -> sign gates -> pinned magnitude-band golden, all hard, no percentage ratio"
    - "Non-gated qualitative cross-check via `@test cond broken = !cond` (mirrors test_acceptance.jl's `gap < tol broken = (gap >= tol)` shape) — records the honest pass/fail state without ever failing CI"
    - "FIT-fallback-on-infeasibility wrapped in a local function (not a bare top-level try/catch) to avoid Julia's top-level soft-scope assignment ambiguity inside `@testitem` bodies"

key-files:
  created:
    - test/test_thesis_repro.jl
  modified: []

key-decisions:
  - "DSO_BAND_LO/DSO_BAND_HI are hard-coded as local `const`s inside the primary @testitem, copied verbatim from Plan 18-01's committed findings.txt RECOMMENDED BAND line — never re-derived or rounded, preserving the depends_on: [\"18-01\"] integrity boundary (threat T-18-04)"
  - "The primary IEEE-123 item gates at the EXACT Phase-17-retuned point (no population-scale perturbation) where 18-01 confirmed the sign flip holds and the SOCP stays exact — 18-01's sign_flip_survives=false finding is about the +-2%/+-5% sensitivity sweep only, not this pinned point, so none of the 5 primary gates were weakened because of it"
  - "The secondary IEEE-13 item's fit_baseline fallback (manual S_max-relaxed FIT solve, mirroring scripts/thesis_caseA.jl:97-131) was wrapped in a local function rather than a bare try/catch at the testitem's top level — a Rule-1 bug fix discovered when the initial bare try/catch version left `fit_dso` UndefVarError'd due to Julia's soft-scope assignment ambiguity for a variable declared `local` at top-level script scope but assigned from within a nested try/catch scope"

patterns-established:
  - "Any future @testitem needing a try/catch fallback with values used AFTER the catch block should compute those values inside a local helper function returning a NamedTuple, not via bare top-level try/catch assignment — avoids the soft-scope UndefVarError trap this plan hit"

requirements-completed: [REPRO-01]

# Metrics
duration: ~35min
completed: 2026-07-26
---

# Phase 18 Plan 02: Thesis Reproduction Gate-Then-Golden Test Summary

**Wrote and green-lit `test/test_thesis_repro.jl`'s primary IEEE-123 real-impedance `@testitem` (5 hard gates: SOCP exactness, DADP DSO-surplus > 0, FIT DSO-surplus < 0, prosumer surplus decrease, and the DSO-surplus magnitude pinned in [0.0, 5.58855710237937] sourced verbatim from Plan 18-01's committed findings) plus a secondary non-gated IEEE-13 qualitative cross-check — full suite gained exactly the 6 new test items with zero new failures.**

## Performance

- **Duration:** ~35 min (dominated by three Julia runs: two scoped `thesis_repro`-filtered runs (~25s / ~23s) and one full-suite `Pkg.test()` run (~16 min, includes precompilation + all 2354 test items))
- **Started:** 2026-07-26 (approx.)
- **Completed:** 2026-07-26
- **Tasks:** 2/2 completed
- **Files modified:** 1 (new: `test/test_thesis_repro.jl`)

## Accomplishments

- Wrote `test/test_thesis_repro.jl` (172 lines) with two `@testitem`s:
  - **Primary** (`Phase7Fixtures`, IEEE-123 real-impedance, Phase-17-retuned population): calls `solve_welfare`/`welfare_accounting`/`fit_baseline` and asserts, in order, all HARD: (1) `ctx.meta[:socp_maxgap] < 1e-5`; (2) `acct.dso > 0.0`; (3) `fit_dso < 0.0`; (4) `acct.prosumer < fb.prosumer_surplus`; (5) `DSO_BAND_LO < acct.dso < DSO_BAND_HI` with `DSO_BAND_LO=0.0`/`DSO_BAND_HI=5.58855710237937` copied verbatim from Plan 18-01's committed `results/repro_stability_check/findings.txt`.
  - **Secondary** (`Phase4Fixtures`, IEEE-13 congestion, non-gated): attempts `fit_baseline` first (confirmed `INFEASIBLE` on this congestion-driven fixture, per 18-RESEARCH.md Pitfall 2), falls back to a manual `S_max`-relaxed FIT solve (mirroring `scripts/thesis_caseA.jl:97-131`, via `TSODSO._fit_opt_solve`), then asserts the same sign-flip pattern as a NON-FAILING `@test sign_flip_holds broken = !sign_flip_holds`.
- **Scoped run** (`filter=ti->occursin("thesis_repro", ti.name)`): both items pass — primary 5/5 hard tests green; secondary's fallback triggered as expected (`fit_baseline` threw `INFEASIBLE`) and its sign-flip check evaluated `true` (`acct.dso=2.564`, `fit_dso=-5.322`, `acct.prosumer=-4825.72 < fit_prosumer=-4816.76`), so it recorded as a genuine Pass, not a `broken=` marker.
- **Full suite** (`julia --project=. -e 'using Pkg; Pkg.test()'`): **2348 passed, 2 failed, 3 broken** (out of 2354 total test items). The 2 failures are the pre-existing, unrelated Aqua CairoMakie/Makie drift pair (`Stale dependencies`, `Persistent tasks` — memory `local-project-toml-drift`, caused by Pedro's local uncommitted `Project.toml`/`Manifest-v1.12.toml` drift, confirmed unrelated: `git diff --stat HEAD` shows zero task-related changes to those files). The 3 broken markers are pre-existing (`test_planning_nash.jl`, `test_pricing_welfare.jl`, `test_diagnostics_plot.jl`), unchanged by this plan. `test/test_thesis_repro.jl` contributed exactly **6 passed, 0 failed, 0 broken** — zero new hard failures introduced.

## Task Commits

1. **Task 1: Write test/test_thesis_repro.jl** — `b27a21c` (feat) — includes a Rule-1 bug fix (soft-scope `try/catch` assignment) discovered while running the scoped test the first time.
2. **Task 2: Run the scoped test and the full suite; verify zero new failures** — no file changes (verification-only task); counts confirmed above.

**Plan metadata:** (this commit, following SUMMARY.md write)

## Files Created/Modified

- `test/test_thesis_repro.jl` — the REPRO-01 gate-then-golden `@testitem`(s): a primary hard-gated IEEE-123 real-impedance item (SOCP exactness + DSO-surplus sign flip + prosumer-decrease + pinned magnitude band) and a secondary non-gated IEEE-13 qualitative cross-check falling back to a manual FIT solve when `fit_baseline` is infeasible.

## Decisions Made

- **Band sourced verbatim, never re-derived.** `DSO_BAND_LO=0.0`/`DSO_BAND_HI=5.58855710237937` are hard-coded local `const`s in the primary `@testitem`, read directly from Plan 18-01's committed `results/repro_stability_check/findings.txt` "RECOMMENDED BAND:" line — confirmed matching before writing the assertion (REPRO-02 ordering constraint, threat T-18-04).
- **Primary gates stayed hard despite 18-01's `sign_flip_survives: false` finding**, because that finding is scoped to the +-2%/+-5% population-scale sensitivity sweep, not the exact pinned Phase-17-retuned point the primary item solves at — 18-01's own measurement confirms the sign flip holds AND the SOCP stays exact at that exact point (`socp_maxgap=3.060e-07`).
- **Secondary item's non-failing assertion actually passed, not "broken."** The plan anticipated the secondary IEEE-13 item might raise the repo's broken count from 3 to 4; in practice the sign-flip mechanism holds on this seed/population (`acct.dso=2.564 > 0`, `fit_dso=-5.322 < 0`, `acct.prosumer < fit_prosumer`), so `broken = !sign_flip_holds` evaluates to `broken=false` and the assertion records as a genuine Pass. This is a stronger outcome than the plan projected (an honest positive result, not a documented gap) and does not violate any success criterion — "zero new failures" and "non-failing" are both still satisfied; the broken count simply stayed at 3 instead of rising to 4.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Bare top-level `try/catch` in the secondary `@testitem` left `fit_dso` undefined via Julia's soft-scope assignment ambiguity**
- **Found during:** Task 1, first scoped-run verification attempt
- **Issue:** The initial implementation declared `local fit_prosumer, fit_dso` before a `try/catch` block, then assigned both inside `catch` (the fallback branch). `@testitem` bodies execute at a script-like top level, where Julia's "soft scope" rule makes an assignment to an outer `local` variable from within a nested scope (here, the `try/catch` block itself introduces a scope) ambiguous — non-interactive execution silently creates a NEW local shadowing the outer one instead of updating it. The scoped test run failed with `UndefVarError: fit_dso not defined`, even though the `catch` branch executed correctly (confirmed by the `@info` log line preceding the error).
- **Fix:** Wrapped the entire try/catch fallback logic in a local helper function `_fit_ieee13(feeder, aggs, Th, λ₀)` that `return`s a `NamedTuple` (`(; fit_prosumer, fit_dso)`) from both the `try` and `catch` branches. Ordinary function-local scoping has no such ambiguity, so both branches' assignments are unambiguous local bindings of the function's own scope.
- **Files modified:** `test/test_thesis_repro.jl`
- **Verification:** Re-ran the scoped `thesis_repro`-filtered command; both items passed (6/6), with the secondary item's `@info` log confirming the fallback path executed and `sign_flip_holds = true`.
- **Committed in:** `b27a21c` (folded into the Task 1 commit, since the bug was discovered and fixed while executing Task 1's own verify step)

---

**Total deviations:** 1 auto-fixed (Rule 1 — a Julia scoping bug in the test file introduced and caught within Task 1, before any commit).
**Impact on plan:** Necessary for correctness — without the fix, the secondary `@testitem` would error on every run (a hard suite failure), directly contradicting the plan's "zero new failures" success criterion. No scope creep: the fix only makes the already-planned fallback logic actually execute as intended.

## Issues Encountered

None beyond the auto-fixed scoping bug above. The full-suite run's overall Julia process exit code was nonzero (`Pkg.test()` reports "Package TSODSO errored during testing" because of the 2 pre-existing Aqua failures), which is EXPECTED per this plan's own guidance ("judge success by output counts, not exit code") and the `local-project-toml-drift` memory note — not a regression.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plan 18-03 can now cite `test/test_thesis_repro.jl` as the committed REPRO-01 regression anchor when writing the consolidated assumptions/reduction doc page, and should carry forward the same "directional, public-data" framing (DSO-surplus sign flip + pinned band, never the aggregate welfare ratio) established here.
- No blockers for Plan 18-03.

---
*Phase: 18-directional-thesis-reproduction*
*Completed: 2026-07-26*

## Self-Check: PASSED

- FOUND: test/test_thesis_repro.jl
- FOUND commit: b27a21c (Task 1 — includes the Rule-1 fix)
- `grep -c "thesis_repro" test/test_thesis_repro.jl` >= 2 (both item names contain the substring; confirmed 7 total occurrences including header/setup lines)
- `grep -c "welfare_accounting\|fit_baseline" test/test_thesis_repro.jl` >= 4 (confirmed 6 occurrences)
- `grep -c "reactive_consensus" test/test_thesis_repro.jl` == 0 (confirmed)
- Full-suite counts confirmed via live `julia --project=. -e 'using Pkg; Pkg.test()'` run: 2348 passed / 2 failed (pre-existing Aqua pair only) / 3 broken (pre-existing, unchanged) / 2354 total — `test/test_thesis_repro.jl` itself: 6 passed / 0 failed / 0 broken.
