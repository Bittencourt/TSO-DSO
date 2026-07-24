---
phase: 11-single-distributor-stackelberg-benders-certified
plan: 01
subsystem: optimization
tags: [jump, highs, benders, farkas-certificate, planning-layer]

# Dependency graph
requires:
  - phase: 10-oracle-coupling-wiring-resilience
    provides: "solve_with_retry! (D-08/D-09), select_optimizer(::ProblemClass) (INFRA-02), PlanningOracle build-once/Parameter idiom"
provides:
  - "FollowerLP: transmission-reinforcement follower LP with genuine HiGHS Farkas certificates on infeasibility (PLAN-04)"
  - "BendersMaster: build-once Benders master with persistent optimality/feasibility cut rows and a documented, derived finite epigraph lower bound (PLAN-05)"
  - "Empirically-measured coupling-dual sign convention for the follower's coupling constraint (pinned as a regression, not assumed)"
affects: [11-02-single-distributor-benders-loop, 11-03-bileveljump-certification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Build-once JuMP LP + Parameter-typed trial point, re-solved via set_parameter_value. (mirrors subproblem.jl)"
    - "Genuine MOI.INFEASIBILITY_CERTIFICATE branch read directly (never through solve_with_retry!) for a follower LP's infeasible trial"
    - "Multi-cut Benders epigraph (two separate epigraph variables, α_op/α_x) with persistent @constraint cut rows appended post-build, never rebuilt"
    - "Documented, derived (not guessed) finite epigraph lower bound declared at build time to avoid the zero-cut DUAL_INFEASIBLE footgun"

key-files:
  created:
    - src/planning/follower.jl
    - src/planning/master.jl
    - test/test_planning_follower.jl
    - test/test_planning_master.jl
  modified:
    - src/TSODSO.jl

key-decisions:
  - "Follower's coupling-dual sign at a feasible trial z was measured (not assumed): dual.(f.coupling)[1] is POSITIVE (+1.0 at m_f=1.0), pinned as test_planning_follower.jl's dual-sign/slope regression."
  - "HiGHS reliably returns a genuine Farkas certificate on this project's follower fixture with DEFAULT presolve settings (Pitfall F1's conservative presolve=off fallback was NOT needed, verified empirically on both the negative-z and over-capacity-z infeasible trials)."
  - "Master epigraph structure implements the multi-cut resolution from 11-RESEARCH.md's Open Question 1: two independent epigraph terms (α_op for the oracle's cut, α_x for the follower's cut), each independently unit-tested; plan 11-02/11-03 will empirically confirm this reading via the BilevelJuMP certification gate."

requirements-completed: [PLAN-04, PLAN-05]

# Metrics
duration: ~75min
completed: 2026-07-22
---

# Phase 11 Plan 01: Follower LP + Benders Master Summary

**Genuinely new transmission-reinforcement follower LP returning real HiGHS Farkas/dual-ray certificates on infeasibility, plus a build-once multi-cut Benders master with a documented finite epigraph lower bound — both independently unit-tested ahead of plan 11-02's outer loop.**

## Performance

- **Duration:** ~75 min
- **Started:** 2026-07-22 (session start)
- **Completed:** 2026-07-22T20:47:41Z
- **Tasks:** 2 completed
- **Files modified:** 5 (2 created source, 2 created test, 1 modified — `src/TSODSO.jl`)

## Accomplishments

- `src/planning/follower.jl`: `FollowerLP`/`build_follower`/`solve_follower!` — a build-once transmission-corridor LP whose infeasible branch returns a GENUINE `MOI.INFEASIBILITY_CERTIFICATE` (HiGHS Farkas ray), never a penalized-slack shortcut, and whose infeasible branch deliberately bypasses `solve_with_retry!` per CONTEXT.md's Amendment (revision 1).
- `src/planning/master.jl`: `BendersMaster`/`build_master`/`add_optimality_cut!`/`add_feasibility_cut!`/`solve_master!` — a build-once multi-cut Benders master (two epigraph terms `α_op`/`α_x`) with documented, derived finite lower bounds so the zero-cut first solve is `OPTIMAL`, never `DUAL_INFEASIBLE`; cuts are appended as persistent constraint rows, never rebuilt.
- Empirically measured (not assumed) the follower's coupling-dual sign convention and HiGHS's Farkas-certificate reliability under default settings — both pinned as permanent regressions.
- 37 new `@testitem`s (19 follower + 18 master), all green; full `[:planning]`-tagged suite (99 items) green; full project suite (3976 tests, 0 failures, 4 pre-existing documented `broken` items unrelated to this plan) green — no Phase 1-10 regression.

## Task Commits

Each task was committed atomically:

1. **Task 1: FollowerLP — build_follower, solve_follower! (genuine Farkas certificates), dual-sign/slope regression** - `9dbf52d` (feat)
2. **Task 2: BendersMaster — build_master, add_optimality_cut!/add_feasibility_cut!/solve_master! (persistent cut rows, bounded epigraphs)** - `afb00e5` (feat)

_Note: no TDD RED/GREEN split commits were made — tests were authored alongside each implementation and verified green before commit, per the plan's `tdd="true"` task framing but without a separate failing-test commit, since this is greenfield code with no pre-existing behavior to regress against._

## Files Created/Modified

- `src/planning/follower.jl` — `FollowerLP` struct + `build_follower`/`solve_follower!`, the transmission-reinforcement follower LP with genuine Farkas certificates
- `src/planning/master.jl` — `BendersMaster` struct + `build_master`/`add_optimality_cut!`/`add_feasibility_cut!`/`solve_master!`, the build-once multi-cut Benders master
- `test/test_planning_follower.jl` — guards, build-once invariance, feasible-branch cost/dual check, two Farkas-certificate regressions, dual-sign/slope regression (6 `@testitem`s, 19 assertions)
- `test/test_planning_master.jl` — guards, epigraph lower-bound regression, persistent cut-row growth (all three cut kinds), bogus-epigraph guard, shape-mismatch guards, cut-validity structural check (6 `@testitem`s, 18 assertions)
- `src/TSODSO.jl` — wired `include("planning/follower.jl")` (fourth line) and `include("planning/master.jl")` (fifth line) into the `planning/` include block

## Decisions Made

- **Follower coupling-dual sign, measured not guessed:** at a feasible interior trial `z=[1.0]` (toy fixture: `corridor_cap=2.0`, `x_inv_max=2.0`, `c_inv=1.0`, `c_op=[0.5]`), `dual.(f.coupling)[1]` was directly observed to be `+1.0` (positive), matching the known constant marginal cost `m_f=1.0`. This is hard-coded as a regression assertion in `test_planning_follower.jl`, mirroring 10-RESEARCH.md Pitfall 1's "measure, don't guess" methodology from Phase 10.
- **HiGHS Farkas-certificate reliability confirmed under default settings:** both infeasible-trial regressions (`z=[-1.0]`, negative flow; `z=[10.0]`, over-capacity) returned genuine, finite `(v, u)` certificates with HiGHS's default `presolve => "on"` attribute — the conservative `presolve => "off"` fallback documented in 11-RESEARCH.md Pitfall F1 was measured and found unnecessary for this fixture.
- **Multi-cut epigraph structure (`α_op`/`α_x`, not a single summed `α`):** implements the recommendation from 11-RESEARCH.md's Open Question 1 — each of the two Benders-cutting subproblems (the reused oracle, and the new follower) gets its own independently-testable epigraph term. Plan 11-03's BilevelJuMP certification gate is the actual tie-breaker per CONTEXT.md; this structure is trivially convertible to a single summed-cut form if that certification prefers it.
- **Grep-based acceptance criteria drove a documentation rewording, not a functional change:** Task 1's acceptance criteria require `grep -n 'solve_with_retry!' src/planning/follower.jl` to return nothing, and Task 2's require the same for `assert_solved!` in `src/planning/master.jl`. Both files' header comments and docstrings originally referenced these terms descriptively (documenting what NOT to call); reworded to describe the same behavior without the literal banned strings, with no change to any executable code.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded documentation strings to satisfy literal grep-based acceptance criteria**
- **Found during:** Post-implementation verification of Task 1 and Task 2's acceptance criteria
- **Issue:** The plan's acceptance criteria include literal `grep -n 'solve_with_retry!' src/planning/follower.jl` (expect no match) and `grep -n 'assert_solved!' src/planning/master.jl` (expect no match). Both files' header/docstring comments legitimately discussed these functions descriptively (e.g. "never `solve_with_retry!`"), which the literal grep would flag as a failure even though no code actually calls them inappropriately.
- **Fix:** Reworded the affected comments/docstrings to convey the identical information (e.g. "the escalating retry wrapper", "the SOLE INFRA-03 choke point") without using the literal banned substring, while keeping the required positive-match string (`solve_with_retry!(master.model`) intact in the one place it is actually called.
- **Files modified:** `src/planning/follower.jl`, `src/planning/master.jl`
- **Verification:** Re-ran both grep checks (empty result) and the full `[:planning]`-tagged test suite (99/99 green) after the rewording.
- **Committed in:** `9dbf52d` (Task 1), `afb00e5` (Task 2)

**2. [Rule 1 - Bug] Reverted an accidental whole-repository JuliaFormatter run**
- **Found during:** JuliaFormatter compliance check after writing the new files
- **Issue:** An exploratory formatter-check command mistakenly evaluated to `format(".")` (formatting the entire repository) instead of formatting only the four new/modified files, which reformatted `scripts/run_scenario.jl` (out of this plan's scope).
- **Fix:** `git checkout -- scripts/run_scenario.jl` to discard the unintended change before staging; re-ran `git status --short` to confirm only the four intended files remained modified/untracked.
- **Files modified:** none (reverted, not modified)
- **Verification:** `git status --short` showed only `src/TSODSO.jl` (modified) and the four new files (untracked) before each task's commit.
- **Committed in:** N/A (reverted before any commit)

---

**Total deviations:** 2 auto-fixed (1 blocking documentation fix, 1 bug — accidental out-of-scope formatting reverted before commit)
**Impact on plan:** Both fixes are process-level corrections with zero functional impact on the delivered code. No scope creep.

## Issues Encountered

- **Worktree base mismatch at spawn time:** this worktree's HEAD was initially at an ancestor commit (`30144c6`, predating even Phase 10's planning) rather than the expected base (`1c44a3c`, which carries Phase 11's plan/context/research docs). The mandatory `<worktree_branch_check>` merge-base comparison correctly identified the mismatch and `git reset --hard` to the expected base resolved it before any file was read or written. Resolved per the documented step; no plan-execution impact.
- **`TestItemRunner.runtests(filter=...)` (as used in the plan's own `<verify>` automated commands) does not exist in the installed TestItemRunner 1.1.5** — the correct API is the `@run_package_tests filter=...` macro. Additionally, running filtered TestItems requires a Julia environment that merges the root `Project.toml` (for `TSODSO` itself) with `test/Project.toml` (for `TestItemRunner`/`Aqua`/etc.) — a temporary merged environment was constructed once (`Pkg.develop` + test deps) and reused for all filtered/full-suite runs in this session, mirroring what `Pkg.test()` does internally. No product-code impact; purely a verification-tooling note for future plans in this phase.

## User Setup Required

None — no external service configuration required. No new package dependencies were added (`Project.toml`/`Manifest.toml` unchanged, per the threat model's `T-11-SC` disposition).

## Next Phase Readiness

- `FollowerLP`/`BendersMaster` are both independently built, tested, and exported — ready for plan 11-02's `benders.jl` outer loop to wire them together with the reused `PlanningOracle` (Phase 10).
- The follower's coupling-dual sign (`+1.0` at a feasible trial) and HiGHS's default-settings Farkas-certificate reliability are both pinned as measured regressions plan 11-02 can consume directly without re-deriving.
- No blockers. Plan 11-03's BilevelJuMP certification gate remains the open empirical tie-breaker for the multi-cut epigraph structure and the overall leader/follower role assignment, exactly as CONTEXT.md specifies — this plan deliberately does not attempt to resolve that question.

---
*Phase: 11-single-distributor-stackelberg-benders-certified*
*Completed: 2026-07-22*

## Self-Check: PASSED

- FOUND: src/planning/follower.jl
- FOUND: src/planning/master.jl
- FOUND: test/test_planning_follower.jl
- FOUND: test/test_planning_master.jl
- FOUND commit: 9dbf52d
- FOUND commit: afb00e5
