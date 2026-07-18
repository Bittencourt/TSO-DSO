---
phase: 04-convex-branch-flow-correctness-milestone
plan: 01
subsystem: testing
tags: [socp, clarabel, testitems, powerflow, problem-class-trait, ieee13, tdd, red-harness]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: ProblemClass/SOCP + select_optimizer factory, AbstractPowerFlow/contribute! seam, ModelContext
  - phase: 02-linear-rungs
    provides: DCPowerFlow / LinDistFlow stub convention, solve_linear, conformance test
  - phase: 03-devices-welfare
    provides: Aggregator + Thermostatic/Deferrable/PVBattery devices, solve_welfare, generate_profiles, fixtures_phase3
provides:
  - "Include graph wired for all five Phase-4 source files (comment-only SEAM/OWNER stubs)"
  - "problem_class(::AbstractPowerFlow) = QP() generic solver-routing trait"
  - "Confirmed SOCP() routes to the tight-gap Clarabel factory (no factory edit needed)"
  - "RED @testitem harness for all six Phase-4 requirements (socp/exact/ieee13/oracle/ground + SOCP conformance arm)"
  - "Shared Phase4Fixtures test module (IEEE-13 aggregators, MEM/temp profiles, high-PV over-voltage stress fixture)"
affects: [04-02, 04-03, 04-04, 04-05, 04-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "problem_class Holy-trait maps AbstractPowerFlow → ProblemClass, decoupled from the SOCP formulation"
    - "RED @testitem harness: lead with @test isdefined(TSODSO,:Sym), guard behavioral asserts behind the same isdefined so items go GREEN automatically when their owning wave lands"
    - "Shared @testmodule defines functions/consts only; feeder-consuming builders take the feeder as an arg so no later-wave symbol is called at module-load time"

key-files:
  created:
    - src/solver/problem_class_trait.jl
    - src/powerflow/ConvexBranchFlow.jl
    - src/data/ieee13.jl
    - src/models/exactness.jl
    - src/models/oracle.jl
    - test/test_convex_branch_flow.jl
    - test/test_exactness.jl
    - test/test_ieee13.jl
    - test/test_oracle.jl
    - test/fixtures_phase4.jl
  modified:
    - src/TSODSO.jl
    - test/test_conformance.jl

key-decisions:
  - "Created Phase4Fixtures BEFORE (not after) the RED harness: a missing setup=[Phase4Fixtures] makes TestItemRunner ABORT the whole run, so the fixtures module must exist for any RED-harness commit to be healthy"
  - "SOCP routing needed NO factory edit — select_optimizer(SOCP()) already returns the tight-gap Clarabel factory from plan 01-03; confirmed by a GREEN @testitem"
  - "Added a 'ground:'-named RED item (thesis-golden voltage/DADP regression) to test_ieee13.jl to carry the VALIDATION-contract filter substring"

patterns-established:
  - "problem_class trait lives in its own file, included after both solver/ProblemClass.jl and the powerflow formulations; the ::ConvexBranchFlow => SOCP() method is deferred to 04-02"
  - "RED items fail ONLY on a missing-symbol isdefined() check (clean RED), never a runner crash or setup abort"

requirements-completed: [PF-03, PF-04, OPT-02, OPT-03, DATA-03, SEAM-01]

# Metrics
duration: ~50min
completed: 2026-07-18
---

# Phase 4 Plan 01: Convex Branch-Flow Foundation Summary

**Wired the five Phase-4 source stubs + the `problem_class`→QP() trait into the include graph, confirmed `SOCP()` already routes to Clarabel, and stood up a RED `@testitem` harness (14 clean missing-symbol failures) plus the shared `Phase4Fixtures` module — Phase-3's 470 tests stay green.**

## Performance

- **Duration:** ~50 min
- **Started:** 2026-07-18T22:15Z (approx)
- **Completed:** 2026-07-18T23:06Z
- **Tasks:** 3 (committed as 3 atomic commits; Task 3 split for commit-health, see Deviations)
- **Files modified:** 12 (10 created, 2 modified)

## Accomplishments
- `src/TSODSO.jl` now includes all five new Phase-4 files in dependency order (`data/ieee13.jl`, `powerflow/ConvexBranchFlow.jl`, `solver/problem_class_trait.jl`, `models/exactness.jl`, `models/oracle.jl`); the package precompiles clean.
- Generic `problem_class(::AbstractPowerFlow) = QP()` trait is live: `problem_class(LinDistFlow())` and `problem_class(DCPowerFlow())` both return `QP` — DC/LinDistFlow keep the QP Clarabel backend, decoupled from the not-yet-existing SOCP method (04-02).
- Confirmed the SOCP→Clarabel routing requires **no factory change**: `select_optimizer(SOCP())` builds a `Clarabel` factory with `tol_gap_abs/rel = 1e-8` (GREEN `@testitem`).
- RED harness for all six requirements: `test_convex_branch_flow.jl` (PF-03, `socp`), `test_exactness.jl` (PF-04, `exact`), `test_ieee13.jl` (DATA-03/OPT-02/OPT-03, `ieee13`+`ground`), `test_oracle.jl` (OPT-03/SEAM-01, `oracle`), and the SOCP arm of the interchange contract in `test_conformance.jl` — all discovered, all RED on missing symbols.
- Shared `Phase4Fixtures` module: IEEE-13 aggregator builder, digitized MEM-price / temperature profiles, and a seeded high-PV/over-voltage stress fixture.

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire include graph + problem_class trait + stub files** — `0c9e83b` (feat)
2. **Task 3 (fixtures, done early): Phase4Fixtures test module** — `0860842` (test)
3. **Task 2 + Task 3 routing-confirmation: RED @testitem harness + SOCP routing GREEN item** — `a5260df` (test)

**Plan metadata:** _(this SUMMARY commit)_ (docs)

_Note: Tasks 2 and 3 were reordered/split into two commits — see Deviations._

## Files Created/Modified
- `src/solver/problem_class_trait.jl` - generic `problem_class(::AbstractPowerFlow)=QP()` trait (INFRA-02/Pattern 5)
- `src/powerflow/ConvexBranchFlow.jl` - comment-only SEAM/OWNER stub (filled by 04-02, PF-03)
- `src/data/ieee13.jl` - comment-only stub (filled by 04-03, DATA-03)
- `src/models/exactness.jl` - comment-only stub (filled by 04-05, PF-04)
- `src/models/oracle.jl` - comment-only stub (filled by 04-04, OPT-03/SEAM-01)
- `src/TSODSO.jl` - added the five includes in dependency order (the sole shared-file edit for Phase 4)
- `test/test_convex_branch_flow.jl` - RED `socp` items + GREEN SOCP→Clarabel routing confirmation
- `test/test_exactness.jl` - RED `exact` items (throw-on-inexact, pass-on-exact, high-PV stress)
- `test/test_ieee13.jl` - RED `ieee13`/`ground` items (fixture shape, SOCP solve, thesis-golden regression)
- `test/test_oracle.jl` - RED `oracle` item (operational_oracle + SEAM-01 stub kwargs)
- `test/test_conformance.jl` - ADDED the SOCP arm; existing DC↔LinDistFlow item unchanged
- `test/fixtures_phase4.jl` - shared `@testmodule Phase4Fixtures`

## Decisions Made
- **SOCP routing = zero factory edit.** RESEARCH said `SOCP()`→Clarabel was already present; verified live and encoded a GREEN confirmation test instead of touching `factory.jl`.
- **`problem_class` in its own file**, included after the powerflow formulations and after `ProblemClass.jl`, so the generic `QP()` default exists independent of `ConvexBranchFlow` (which 04-02 adds as a more-specific `SOCP()` method) — keeps Wave-2 plans file-disjoint.
- **RED-for-the-right-reason pattern:** every RED item leads with `@test isdefined(TSODSO, :Sym)` and guards its behavioral asserts behind the same `isdefined`, so the failure is always a clean missing-symbol check and the item flips GREEN automatically once its owning wave lands (no test edit needed).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Created Phase4Fixtures before the RED harness (Task 3 reordered ahead of Task 2)**
- **Found during:** Task 2 (RED harness) verification
- **Issue:** The plan sequenced the RED test files (Task 2) before the `Phase4Fixtures` module (Task 3). But a `@testitem ... setup=[Phase4Fixtures]` referencing a not-yet-defined setup makes **TestItemRunner abort the entire run** (`Test setup Phase4Fixtures is not defined`) — only 41 of ~487 items ran. This is exactly the "LoadError that aborts discovery" the plan's own acceptance criteria forbid.
- **Fix:** Committed `test/fixtures_phase4.jl` first (`0860842`, keeps the suite at 470 green as an unused-yet setup module), then the RED harness (`a5260df`). Net file set and final state are identical to the plan; only the commit order of Tasks 2/3 changed.
- **Files modified:** commit ordering only (no code change vs. plan)
- **Verification:** Full `Pkg.test()` → 487 total: **473 passed, 14 failed, 0 errored, 0 broken**; every failure is a clean `isdefined(...)` miss; no discovery abort.
- **Committed in:** `0860842`, `a5260df`

**2. [Rule 2 - Missing Critical] Added a `ground:`-named RED regression item**
- **Found during:** Task 2 (test_ieee13.jl)
- **Issue:** The VALIDATION contract + phase success criteria require a `ground`-substring test (thesis-golden `v₉[16]`/DADP regression, OPT-02/OPT-03), but the plan's Task-2 enumeration only listed socp/exact/ieee13/oracle.
- **Fix:** Added a guarded RED `@testitem "ground: IEEE-13 SOCP reproduces thesis voltage/DADP within tolerance …"` to `test_ieee13.jl` (√v magnitude cross-check ≈ 1.0493 within a documented tolerance per Open Q1; the tight golden is pinned later by 04-04/04-06).
- **Files modified:** test/test_ieee13.jl
- **Verification:** appears in the run as a RED `ground`/`ieee13` item, failing on missing symbols.
- **Committed in:** `a5260df`

---

**Total deviations:** 2 (1 blocking commit-reorder, 1 missing-critical test). 
**Impact on plan:** No scope creep. Same files, same final state; deviation 1 is a commit-order fix forced by TestItemRunner setup semantics, deviation 2 completes the VALIDATION filter-substring set.

## Issues Encountered
- **TestItemRunner is a test-only dep** (in `test/Project.toml`, not the main project), so the plan's literal Task-2 verify (`julia --project=. -e 'using TestItemRunner; @run_package_tests filter=…'`) cannot run in the main environment. Used the authoritative `Pkg.test()` gate instead, which discovers every `@testitem` and confirms the green/RED split.
- **Missing-setup abort** (see Deviation 1) — resolved by committing fixtures first.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `src/TSODSO.jl` is fully wired for Phase 4; Waves 2–4 (04-02 ConvexBranchFlow, 04-03 ieee13_modified, 04-04 oracle, 04-05 exactness) are file-disjoint on the include graph and each has a concrete RED target.
- The SOCP conformance arm and the exactness/high-PV items give 04-02/04-05 an end-to-end failing target from the first commit.
- No STATE.md / ROADMAP.md updates were made (per plan instruction — the orchestrator owns those).

## Self-Check: PASSED

All 10 created source/test files + this SUMMARY exist on disk; all three task commits (`0c9e83b`, `0860842`, `a5260df`) are present in the git history.

---
*Phase: 04-convex-branch-flow-correctness-milestone*
*Completed: 2026-07-18*
