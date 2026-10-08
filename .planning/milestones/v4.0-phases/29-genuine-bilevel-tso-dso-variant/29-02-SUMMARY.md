---
phase: 29-genuine-bilevel-tso-dso-variant
plan: 02
subsystem: planning
tags: [bilevel-jump, highs, ipopt, milp, certification, lindistflow, testing]

# Dependency graph
requires:
  - phase: 29 plan 01
    provides: "build_bilevel_kkt/solve_bilevel!/BilevelKKT (production) and bilevel_toy_fixture() (fixtures_planning.jl), consumed verbatim here"
provides:
  - "test/test_planning_certification_bilevel.jl — the permanent BILEV-02 three-way certification: production == BilevelJuMP StrongDualityMode == brute-force grid enumeration, all three != joint"
  - "8 new named golden constants in PlanningFixtures (BILEV_*_HAND, JOINT_*_HAND, BILEV_GAP_FLOOR) with documented analytic + empirical derivations"
affects: [29-03, 29-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Stacked JULIA_LOAD_PATH=\"test:.:@stdlib\" verification idiom: resolves BOTH the main env's TSODSO AND the test-only BilevelJuMP/Ipopt deps in one julia process, without Pkg.develop mutation of the pinned test Manifest — a non-mutating alternative to the documented TestItemRunner trap"
    - "Hand-derived BilevelJuMP MPEC for a lossless single-branch feeder (d==z exact network coupling), kept structurally separate from contribute!/ModelContext (incompatible Upper()/Lower() variable containers)"

key-files:
  created:
    - test/test_planning_certification_bilevel.jl
  modified:
    - test/fixtures_planning.jl

key-decisions:
  - "GAP_FLOOR (now PlanningFixtures.BILEV_GAP_FLOOR) derived as 10x the production MILP's own measured mip_feasibility_tolerance=1e-9 (=> 1e-8), never as a fraction of the observed ~3.9/~2.0 gaps themselves (T-29-04 mitigation)."
  - "Cross-oracle atols set from measured residuals this session: 1e-3 for BilevelJuMP StrongDualityMode (Ipopt interior-point noise ~1e-7 near the corner), 1e-6 for brute-force (bit-identical HiGHS-vs-HiGHS agreement, residual 0.0)."
  - "BILEV_GAP_FLOOR shared between the total_cost and z assertions after explicitly checking both quantities are the same order of magnitude in THIS fixture (not assumed by default)."

requirements-completed: [BILEV-02]

# Metrics
duration: ~25min
completed: 2026-09-30
---

# Phase 29 Plan 02: BILEV-02 Three-Way Bilevel Certification Summary

**Three independent oracles (production KKT-MILP, BilevelJuMP StrongDualityMode, brute-force grid enumeration) agree with each other and all genuinely diverge from a joint single-planner reference by a measured 3.9-cost / 2.0-power gap, closing the 2026-09-28 quality-audit BILEV-02 gap.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-09-30T23:35:00-03:00 (approx.)
- **Completed:** 2026-09-30T23:58:00-03:00 (approx.)
- **Tasks:** 2 completed
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments
- New `test/test_planning_certification_bilevel.jl`: a `@testmodule BilevelKKTCertFixture` (hand-derived BilevelJuMP `StrongDualityMode` MPEC exploiting this fixture's exact lossless `d==z` network coupling; a brute-force grid-enumeration oracle re-solving the follower's own LP per grid point via `select_optimizer(LP())`; a "joint" single-planner no-tariff reference reusing `contribute!(LinDistFlow(), ...)` verbatim) plus ONE permanent `@testitem` asserting all three agree with production `solve_bilevel!` and all four genuinely diverge from the joint reference.
- `test/fixtures_planning.jl` extended with 8 new named golden constants (`BILEV_Y_HAND`/`BILEV_Z_HAND`/`BILEV_TOTAL_HAND`, `JOINT_Y_HAND`/`JOINT_XINV_HAND`/`JOINT_Z_HAND`/`JOINT_TOTAL_HAND`, `BILEV_GAP_FLOOR`), each documented with BOTH the analytic derivation and this session's live-measured confirmation, mirroring the existing `N1_Y_HAND`/`N1_Z_HAND`/`N1_OBJ_HAND` convention.
- Measured this session (live solve, no guessing): production reproduces the hand-derived corner exactly (`y=x_inv=z=total=0.0`); BilevelJuMP StrongDualityMode converges to the same corner with residual ~1e-7 (Ipopt interior-point noise, `LOCALLY_SOLVED`); brute-force grid enumeration (201 points) is bit-identical to production; the joint reference reproduces `y=x_inv=1.0, z=2.0, total=-3.9` exactly — a measured gap of 3.9 (cost) / 2.0 (power), eight orders of magnitude above the `1e-8` `BILEV_GAP_FLOOR`.
- Verified via a direct Julia/Test.jl script under a STACKED `JULIA_LOAD_PATH="test:.:@stdlib"` (a non-mutating alternative to `Pkg.develop` that resolves both the main-env `TSODSO` and the test-only `BilevelJuMP`/`Ipopt`/`HiGHS` in one process): the certification @testitem's 16 assertions pass, plus a combined battery reproducing all 4 bilevel-related @testitems (3 from plan 29-01 + 1 from this plan, 28/28 assertions) to catch any cross-file constant-naming collision ahead of plan 29-03's full-suite close.

## Task Commits

Each task was committed atomically:

1. **Task 1: Three-way certification — production, BilevelJuMP StrongDualityMode, brute-force grid enumeration, vs. joint** - `1365399` (test)
2. **Task 2: Pin the measured golden constants + full-file regression run** - `acce6e8` (test)

## Files Created/Modified
- `test/test_planning_certification_bilevel.jl` - `BilevelKKTCertFixture` (`build_toy_bilevel_jump`/`brute_force_bilevel`/`build_joint_reference`) + the single BILEV-02 `@testitem`
- `test/fixtures_planning.jl` - 8 new `BILEV_*_HAND`/`JOINT_*_HAND`/`BILEV_GAP_FLOOR` consts, documented and exported

## Decisions Made
- Verification methodology: since TestItemRunner does not resolve under `--project=.` (memory `gsd-plan-verify-testitemrunner-trap`) and this plan ALSO needs the test-only `BilevelJuMP`/`Ipopt`, a stacked `JULIA_LOAD_PATH="test:.:@stdlib"` was used instead of the memory's suggested `--project=.` direct-script approach — verified this resolves BOTH `TSODSO` (from the main env's own `Project.toml`/`Manifest.toml`) and `BilevelJuMP`/`Ipopt`/`HiGHS` (from `test/Project.toml`/`Manifest.toml`) in the SAME process, without any `Pkg.develop`/environment mutation (the documented hazard in the test-invocation memory). This generalizes to any future plan needing both environments simultaneously outside `Pkg.test()`.
- `GAP_FLOOR`/cross-oracle atols were all derived from LIVE measurements this session (never hand-picked round numbers) — see key-decisions above and the file's own inline derivation comments.

## Deviations from Plan

None - plan executed exactly as written. All function signatures, fixture numbers, and assertion structure match the plan's `<action>` blocks verbatim; the measured values (production corner `0.0`, joint optimum `-3.9`, BilevelJuMP residual `~1e-7`) matched the plan's own stated expectations (derived in 29-01-SUMMARY.md's fixture docstring) exactly, with no re-tuning needed.

## Issues Encountered
None. The stacked-`JULIA_LOAD_PATH` verification approach (see Decisions Made) was needed because this plan is the first one in the phase to require BOTH environments simultaneously in a direct script; it worked on the first attempt.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- BILEV-02 is certified: `solve_bilevel!` is now proven to be the true bilevel optimum, not an accidental match to the joint optimum, on the corner fixture.
- Plan 29-04 still owes the NON-DEGENERATE fixture (`q_op>0`, interior follower response, SOS1 branch-switching) per this plan's own header note — this plan's fixture is the corner case only, retained as a cheap sanity check, and alone cannot exercise leader-follower interaction or guard against a `z≡0` stub.
- No blockers. The 4-item bilevel battery (3 from 29-01 + 1 from this plan, 28/28 assertions) is green ahead of plan 29-03's phase-closing full suite.

---
*Phase: 29-genuine-bilevel-tso-dso-variant*
*Completed: 2026-09-30*

## Self-Check: PASSED

All claimed files found on disk (`test/test_planning_certification_bilevel.jl`, `test/fixtures_planning.jl`);
both task commit hashes (`1365399`, `acce6e8`) found in `git log --oneline --all`.
