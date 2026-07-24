---
phase: 14-validation-oracle-regression-hardening-docs
plan: 01
subsystem: testing
tags: [testitems, testitemrunner, benders, nash, bileveljump, regression]

# Dependency graph
requires:
  - phase: 11-single-distributor-stackelberg-benders-certified
    provides: "solve_stackelberg! + the N=1 BilevelJuMP-certified toy equilibrium (y*=z*=0.7, cost=-0.245)"
  - phase: 13-nash-diagonalization-shared-transmission-coupling
    provides: "run_nash!/run_nash_probe + the N=2 hand-checked congested Nash equilibrium (z=[0.6,0.6], x_inv=[0.3,0.3])"
provides:
  - "test/fixtures_planning.jl — PlanningFixtures @testmodule with 8 pinned/bounded consts"
  - "test/test_planning_goldens.jl — 3 gate-then-golden @testitems, tag [:planning]"
  - "Permanent, dedicated PVAL-02 regression: N=1/N=2 equilibria and N=2 probe spread bound"
affects: [14-02-noninteger-guard, 14-03-docs]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "gate-then-golden assertion ordering: production entrypoint's own convergence/gap flag asserted BEFORE the pinned golden value, so a solver regression cannot be masked by weakening only the value check"
    - "loose-upper-bound spread regression (not exact-value pin) for solver-numerics-sensitive diagnostics, derived empirically in a scratch dev-linked environment"

key-files:
  created:
    - test/fixtures_planning.jl
    - test/test_planning_goldens.jl
  modified: []

key-decisions:
  - "PlanningFixtures built as a @testmodule (not a plain include-file), mirroring fixtures_phase4.jl exactly, for setup=[...] consumption by test_planning_goldens.jl"
  - "N2_PROBE_*_SPREAD_MAX pinned as loose upper bounds (1e-4 / 1e-4 / 1e-3), not exact values — empirically derived by running the production run_nash_probe entrypoint in a scratch dev-linked environment (observed spread ~1e-16, floating-point noise on this fully-symmetric fixture); bounds sit many orders of magnitude above that noise floor while remaining far below the ~0.01-0.7 spread a genuinely seed-dependent equilibrium would produce"

patterns-established:
  - "Gate-then-golden pattern (T-14-01): a testitem must assert the production entrypoint's own convergence/gap flag on an earlier source line than any pinned-value isapprox assertion"

requirements-completed: [PVAL-02]

# Metrics
duration: 35min
completed: 2026-07-24
---

# Phase 14 Plan 01: Planning-Layer Validation-Oracle Goldens Summary

**Extracted the N=1 BilevelJuMP-certified Stackelberg equilibrium and N=2 hand-checked Nash equilibrium into a dedicated `PlanningFixtures` goldens module and a gate-then-golden regression file, plus a newly-bounded (not just non-negative) N=2 probe spread check.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-07-24
- **Tasks:** 2/2
- **Files modified:** 2 (both new)

## Accomplishments
- `test/fixtures_planning.jl` — new `@testmodule PlanningFixtures` pinning the N=1 certified equilibrium (`y*=z*=0.7`, `cost=-0.245`), the N=2 hand-checked equilibrium (`z=[0.6,0.6]`, `x_inv=[0.3,0.3]`), and three loose upper-bound consts for the N=2 multi-seed/multi-order probe spread.
- `test/test_planning_goldens.jl` — new file, 3 `@testitem`s tagged `[:planning]`, each asserting the production entrypoint's own convergence/gap gate BEFORE the pinned golden value (mirrors `test/test_acceptance.jl`'s gate-before-golden convention).
- The probe-spread bounds were derived empirically, not guessed: ran the identical 3-seed x 2-order `run_nash_probe` shape directly against the production entrypoint in a scratch dev-linked Julia environment this session (observed `z_spread ≈ 2.22e-16`, `x_inv_spread = 0.0`, `cost_spread ≈ 3.33e-16` — floating-point noise on this fully-symmetric fixture), then pinned bounds with generous headroom above that noise floor.
- Verified via `TestItemRunner.run_tests(<abs test dir>; filter=...)` from a scratch dev-linked environment (never the bare `@run_package_tests` macro, which would scan the shared `.claude/worktrees/` parent): 14/14 assertions pass on the new file; the full `[:planning]`-tagged suite (327 items) stays green — 326 pass / 1 expected-broken (documented CairoMakie-weakdep skip in `test_planning_nash.jl`) / 0 fail.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create test/fixtures_planning.jl — PlanningFixtures goldens module** - `9cd714d` (test)
2. **Task 2: Create test/test_planning_goldens.jl — gate-then-golden regression** - `2611567` (test)

_Note: this plan's tasks are documentation/test-fixture work, not TDD-tagged; each task is a single commit._

## Files Created/Modified
- `test/fixtures_planning.jl` - `@testmodule PlanningFixtures` with 8 named consts (N1_Y_HAND, N1_Z_HAND, N1_OBJ_HAND, N2_Z_HAND, N2_XINV_HAND, N2_PROBE_Z_SPREAD_MAX, N2_PROBE_XINV_SPREAD_MAX, N2_PROBE_COST_SPREAD_MAX), each with a rationale/derivation comment, exported at module end.
- `test/test_planning_goldens.jl` - 3 `@testitem`s tagged `[:planning]`: N=1 Stackelberg gap-gate-then-golden, N=2 Nash convergence-gate-then-golden, N=2 probe gating-checks-then-spread-bound.

## Decisions Made
- Followed the plan's explicit instruction to make `PlanningFixtures` a `@testmodule` (matching `fixtures_phase4.jl`'s shape) rather than a plain include-file, since `test_planning_goldens.jl` consumes it via `setup=[..., PlanningFixtures]`.
- Pinned the three probe-spread bounds as LOOSE upper bounds (1e-4 for z_spread and x_inv_spread, 1e-3 for cost_spread — looser since cost is a derived/scaled quantity) rather than tight exact-value pins, per CONTEXT.md's Claude's-Discretion resolution that spread-across-seeds/orders is a solver-numerics-sensitive diagnostic, not a stable quantity like the equilibrium point itself.

## Deviations from Plan

None - plan executed exactly as written. Both tasks' acceptance criteria (const count/values, export list, gate-before-value line ordering, `TestItemRunner` pass count) were verified directly, matching the plan's `<verify>` blocks.

## Issues Encountered

None. The scratch dev-linked environment setup (copy `test/Project.toml` to a scratch dir, `Pkg.develop(path=pwd())`, `Pkg.instantiate()`) worked on the first attempt, following the exact workaround documented in 13-02-SUMMARY.md/13-03-SUMMARY.md.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

`test/fixtures_planning.jl` and `test/test_planning_goldens.jl` are self-contained additions with no impact on the parallel 14-02 (`test/test_planning_noninteger.jl`) or 14-03 (`docs/`) executor work — no shared files touched. The PVAL-02 roadmap success criterion ("canonical N=1/N=2 fixtures pinned as computed goldens, gated by BilevelJuMP agreement and diagonalization convergence") is satisfied.

---
*Phase: 14-validation-oracle-regression-hardening-docs*
*Completed: 2026-07-24*
