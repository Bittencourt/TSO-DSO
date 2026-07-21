---
phase: 09-documentation-regression-acceptance-gate
plan: 03
subsystem: testing
tags: [testitems, acceptance-gate, regression-golden, socp, admm, dadp, fit]

# Dependency graph
requires:
  - phase: 04-convex-branch-flow-correctness-milestone
    provides: "IEEE-13 ground-truth GLB-CVX SOCP solve + pinned goldens (test_ieee13.jl, Phase4Fixtures)"
  - phase: 05-distribution-pricing-dadp-dlmp-decomposition
    provides: "fit_baseline FIT-vs-DADP counterfactual (src/pricing/fit.jl), extract_dlmp (src/pricing/dlmp.jl)"
  - phase: 07-admm-convergence-scale
    provides: "IEEE-123 ADMM convergence + DADP cross-validation (test_ieee123_admm.jl, Phase7Fixtures), solve_admm"
provides:
  - "test/test_acceptance.jl — the SC3 v1 acceptance gate: two :acceptance-tagged @testitems (IEEE-13 congestion, IEEE-123 voltage) that each prove exact SOC relaxation + recovered DADP + ADMM ≈ centralized welfare"
  - "test/test_pricing_fit.jl — a new pinned FIT-vs-DADP ratio regression golden (FIT_RATIO_GOLDEN) on the file's own FitFixtures scenario"
affects: [10-milestone-close, future-regression-ci]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Consolidated acceptance-gate @testitem file that calls only real src/ entrypoints (operational_oracle, solve_welfare, solve_admm, extract_dlmp) and reuses already-pinned per-phase goldens/tolerances rather than inventing new ones"
    - "Non-failing thesis cross-check idiom (@info + `@test gap < tol broken = (gap >= tol)`) reused verbatim for the SC3 gate"

key-files:
  created:
    - test/test_acceptance.jl
  modified:
    - test/test_pricing_fit.jl

key-decisions:
  - "IEEE-13 acceptance item compares admm.λ (the full (n_load_nodes, T) converged DADP matrix) against an extract_dlmp-built cross-check on the SAME centralized ctx, not operational_oracle's res.dadp (which is only the first aggregator's bus, a length-T vector) — a dimension mismatch the plan skeleton did not anticipate. Tolerances (atol=1e-2, rtol=1e-3) unchanged."
  - "FIT_RATIO_GOLDEN (0.6428101637491034) pinned on FitFixtures' 3-bus scenario (seed=20260718), additive to and distinct from test_pricing_welfare.jl's RATIO_GOLDEN (IEEE-13 ground scenario)."

patterns-established:
  - "SC3 acceptance gate: `julia --project=. -e 'using Pkg; Pkg.test(; test_args=[\"acceptance\"])'` runs exactly the two consolidated end-to-end items."

requirements-completed: [EXP-04]

# Metrics
duration: 40min
completed: 2026-07-20
---

# Phase 9 Plan 3: SC3 Consolidated Acceptance Gate + FIT Regression Golden Summary

**Consolidated `test/test_acceptance.jl` proving IEEE-13 congestion + IEEE-123 voltage exact-relaxation/DADP/ADMM≈centralized end-to-end, plus a new FIT-vs-DADP regression golden in `test_pricing_fit.jl`.**

## Performance

- **Duration:** ~40 min (2026-07-20T08:24Z start of phase branch → 09:03Z last commit)
- **Started:** 2026-07-20T08:24:19-03:00
- **Completed:** 2026-07-20T09:03:14-03:00
- **Tasks:** 3 (2 committed as one file-level commit, 1 separate)
- **Files modified:** 2 (1 created, 1 extended)

## Accomplishments
- Closed EXP-04 and the SC3 v1 acceptance-gate success criterion with `test/test_acceptance.jl`: two `:acceptance`-tagged `@testitem`s that call the real `operational_oracle`/`solve_welfare`/`solve_admm`/`extract_dlmp` entrypoints on the SAME ground-truth fixtures (`Phase4Fixtures`, `Phase7Fixtures`) already exercised by `test_ieee13.jl` and `test_ieee123_admm.jl`, reusing every tolerance/golden verbatim.
- Both acceptance items pass: IEEE-13 exact relaxation (`socp_maxgap < 1e-5`), golden welfare match (`GOLDEN_WELFARE = -4823.1598620624` at `rtol=1e-4`), ADMM ≈ centralized welfare and DADP; IEEE-123 five-line contract (`iters<300`, `iters<=100`, welfare `rtol=1e-4`, `exact_maxgap<1e-3`, `λ` vs centralized DLMP `atol=1e-2, rtol=1e-3`).
- Thesis `v₉[16] ≈ 1.0493` cross-check present as a non-failing `@info` + `broken`-`@test` — never a hard-failing assertion, exactly per CONTEXT.md's lock.
- Added a sixth `@testitem` to `test/test_pricing_fit.jl` pinning `fit_baseline`'s self-contained `ratio` (`social_dadp/social_fit`) as a new regression golden on the file's own `FitFixtures` 3-bus scenario, additive to (not duplicating) `test_pricing_welfare.jl`'s IEEE-13-scenario `RATIO_GOLDEN`.
- Full `Pkg.test()` (via both `test_args=["acceptance"]` and `test_args=["fit"]` runs, each of which exercised the entire package test suite) stays green: 1944 passed, 0 failed, 0 errored, 2 broken (the two documented non-failing thesis cross-checks — pre-existing +25% headline check plus the new v₉[16] check in the acceptance item).

## Task Commits

Each task was committed atomically:

1. **Task 1 + Task 2: IEEE-13 + IEEE-123 acceptance testitems** - `206e4b4` (feat) — both testitems were authored and verified together in the single new `test/test_acceptance.jl` file, so they share one commit (see Deviations).
2. **Task 3: FIT-vs-DADP regression golden extension** - `cd41045` (test)

_No plan-metadata commit yet — orchestrator handles STATE.md/ROADMAP.md updates for the wave._

## Files Created/Modified
- `test/test_acceptance.jl` - New SC3 consolidated acceptance gate: IEEE-13 congestion + IEEE-123 voltage `@testitem`s tagged `:acceptance`.
- `test/test_pricing_fit.jl` - Extended with one new `@testitem` (`FIT_RATIO_GOLDEN` regression golden); the five pre-existing `@testitem`s are unchanged.

## Decisions Made
- **Task 1/2 combined into one commit.** Both acceptance `@testitem`s live in the same new file and were authored/verified as a unit (a single `Pkg.test(; test_args=["acceptance"])` run exercises both); splitting them into two commits would have required an artificial partial-file commit. Documented here rather than force-split.
- **IEEE-13 DADP comparison fixed to use `extract_dlmp` cross-check, not `res.dadp`.** See Deviations below — this is the one substantive fix required beyond the plan's literal skeleton.
- **FIT_RATIO_GOLDEN captured from the first trusted solve**, `0.6428101637491034`, on `FitFixtures.aggregators(seed=20260718)` — verified deterministic (the file's pre-existing "reproducible bit-for-bit" `@testitem` already proves seed-determinism for this exact builder).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed dimension-mismatched DADP comparison in the IEEE-13 acceptance item**
- **Found during:** Task 1 (IEEE-13 congestion acceptance testitem)
- **Issue:** The plan's skeleton asserted `isapprox(admm.λ, res.dadp; atol=1e-2, rtol=1e-3)`. `solve_admm` returns `admm.λ` as the full `(n_load_nodes, T) = (10, 24)` converged DADP matrix (per its own docstring, one row per load node in ascending bus order), while `operational_oracle`'s `res.dadp` is documented as "the distribution price at the FIRST aggregator's bus... a length-T vector" (`src/models/oracle.jl`). Running the test threw `DimensionMismatch: a has size (10, 24), b has size (24,)`.
- **Fix:** Replaced the comparison with the SAME pattern already used by the IEEE-123 item (and by `test_ieee123_admm.jl`): build a `(n_load_nodes, T)` cross-check matrix via `extract_dlmp(ctx; bus=b, T=24)` for each load bus (ascending order, matching `solve_admm`'s documented row ordering) on the SAME centralized `ctx` from `operational_oracle`, then compare `admm.λ` against that matrix at the SAME tolerances (`atol=1e-2, rtol=1e-3` — unchanged, no loosening).
- **Files modified:** `test/test_acceptance.jl`
- **Verification:** `julia --project=. -e 'using Pkg; Pkg.test(; test_args=["acceptance"])'` — both acceptance items pass (1943 passed, 2 broken, 0 failed on the first post-fix full-suite run).
- **Committed in:** `206e4b4` (Task 1/2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug fix; no new tolerance introduced, only a dimensionally-correct comparison substituted for the plan's literal skeleton).
**Impact on plan:** Necessary for correctness — the plan's literal `res.dadp` comparison could never have passed (shape mismatch, not a numerical near-miss). No scope creep; the fix reuses the exact tolerance the plan specified and the exact pattern the plan's own IEEE-123 task already used.

## Issues Encountered
- Full-suite `Pkg.test()` runs take ~8 minutes each (IEEE-123 ADMM solves dominate); both verification runs (`test_args=["acceptance"]` and `test_args=["fit"]`) were run as backgrounded `nohup` processes polled to completion rather than a single foreground call, to stay under tool timeouts. No code issue — purely an execution-environment accommodation.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- SC3 v1 acceptance gate is closed: `julia --project=. -e 'using Pkg; Pkg.test(; test_args=["acceptance"])'` is now the single command that proves both headline cases end-to-end.
- EXP-04 regression-fixture requirement is satisfied for the FIT-vs-DADP comparison; the existing 1933+ per-phase pins are untouched.
- Ready for plans 09-01/09-02/09-04/09-05 (the literate-docs work) — this plan touched only `test/`, no overlap.
- No blockers.

---
*Phase: 09-documentation-regression-acceptance-gate*
*Completed: 2026-07-20*

## Self-Check: PASSED
- FOUND: test/test_acceptance.jl
- FOUND: test/test_pricing_fit.jl
- FOUND commit: 206e4b4
- FOUND commit: cd41045
