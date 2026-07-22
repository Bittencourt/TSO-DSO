---
phase: 11-single-distributor-stackelberg-benders-certified
plan: 02
subsystem: optimization
tags: [jump, highs, benders, stackelberg, planning-layer]

# Dependency graph
requires:
  - phase: 10-oracle-coupling-wiring-resilience
    provides: "PlanningOracle/solve_planning_oracle! (D-06 sign convention), solve_with_retry!/checkpoint_iteration!"
  - phase: 11-single-distributor-stackelberg-benders-certified (plan 11-01)
    provides: "FollowerLP/solve_follower! (genuine Farkas certificates), BendersMaster/add_optimality_cut!/add_feasibility_cut!/solve_master! (persistent cut rows, bounded epigraph)"
provides:
  - "solve_stackelberg!: the build-once outer Benders orchestration loop wiring PlanningOracle + FollowerLP + BendersMaster into a single-distributor Stackelberg equilibrium (PLAN-06)"
  - "Documented UB/LB relative-gap convergence criterion (default tol=1e-6), fail-loud on max_iter exhaustion"
  - "Per-iteration checkpointing via checkpoint_iteration! on both the feasibility-cut and optimality-cut loop branches"
affects: [11-03-bileveljump-certification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Build-once orchestration loop (mirrors solve_admm.jl): guards -> build oracle/follower/master ONCE -> iterate solve/cut/checkpoint -> fail-loud maxiter cap"
    - "UB/LB relative-gap convergence criterion, structurally distinct from ADMM's residual test (no AdmmResiduals reuse)"
    - "Feasibility cut short-circuits the UB update via an early continue, never touching UB on an infeasible trial"

key-files:
  created:
    - src/planning/benders.jl
    - test/test_planning_benders.jl
  modified:
    - src/TSODSO.jl

key-decisions:
  - "Re-derived (not blindly reused) 11-01-PLAN.md's stated toy_fixture hand-enumerated optimum: that plan's claimed y*=1.0/z*=1.0/total-cost=-0.2 is not a stationary point of the fixture's own cost function. The leader's true unconstrained minimization total(z) = c_y*z + m_f*z - welfare(z) = 0.5*z^2 - 0.7*z has its minimum at z* = (a-λ₀-c_y-m_f)/b = 0.7, giving total(0.7) = -0.245 < total(1.0) = -0.2. solve_stackelberg! converges (gap <= 1e-6) to y*=z*≈0.699, matching the re-derived z*=0.7 to within 1e-3 — this is the mathematically correct behavior of the implemented sign convention and cut forms, not a bug in benders.jl. Test assertions target the re-derived 0.7, per Task 2's own escape-hatch instruction (widen atol/document rather than force a match by changing cut-sign logic)."
  - "UB formula uses master.c_y * lb_res.y + follower_res.cost - oracle_res.cost (MINUS oracle_res.cost), following 11-02-PLAN.md's explicit action text over 11-RESEARCH.md's Pattern 2 sketch (which shows PLUS) — the minus is correct because oracle_res.cost is a MAX-sense welfare (a benefit to be subtracted from the leader's cost-to-minimize), not itself a cost."

requirements-completed: [PLAN-06]

# Metrics
duration: ~35min
completed: 2026-07-22
---

# Phase 11 Plan 02: Single-Distributor Benders Loop Summary

**`solve_stackelberg!` — a build-once hand-rolled Benders loop wiring the Phase-10 `PlanningOracle`, plan 11-01's `FollowerLP`, and `BendersMaster` into an end-to-end single-distributor Stackelberg equilibrium, converging to a documented UB/LB relative-gap tolerance (1e-6) on the Phase-11 toy fixture, matching a re-derived (corrected) analytic optimum.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-07-22 (session start, after worktree base correction)
- **Completed:** 2026-07-22
- **Tasks:** 2 completed
- **Files modified:** 3 (2 created, 1 modified — `src/TSODSO.jl`)

## Accomplishments

- `src/planning/benders.jl`: `solve_stackelberg!` builds the oracle/follower/master EXACTLY ONCE outside the loop, then iterates `solve_master!` → `solve_planning_oracle!` → `solve_follower!` (the follower called DIRECTLY, never `solve_with_retry!`-wrapped) per Benders trial `z_k`, appending a feasibility cut (skipping the `UB` update) or both an oracle `:op` and a follower `:x` optimality cut per iteration, checkpointing exactly once per iteration on both branches, and raising a loud `ErrorException` naming the exhausted iteration count and last observed gap if `max_iter` is exhausted without converging.
- `test/test_planning_benders.jl`: two `@testitem`s — end-to-end convergence (gap ≤ 1e-6, checkpoint-file count == `result.iters`, converged `y`/`z` matching a re-derived analytic optimum) and an iteration-cap loud-failure regression (`max_iter=1` raises `ErrorException` containing `"exhausted"`).
- Discovered and corrected a latent arithmetic error in 11-01-PLAN.md's own `<toy_fixture>` block: the stated hand-enumerated optimum (`y*=1.0`, `z*=1.0`, cost=-0.2) is not the true minimizer of the fixture it defines. Re-derived the correct analytic optimum (`z*=0.7`) and verified the Benders loop converges to it — confirming `solve_stackelberg!`'s cut-sign logic and UB/LB formula are correct, not the source of the discrepancy.
- Full `[:planning]`-tagged suite (105 items: 99 from plan 11-01 + 6 new) green; full project suite (4008 tests: 4004 passed, 4 pre-existing documented `broken` items unrelated to this plan, 0 failures) green in two independent runs — no Phase 1-11 regression.

## Task Commits

Each task was committed atomically:

1. **Task 1: solve_stackelberg! — build-once orchestration, UB/LB gap loop, checkpointing, fail-loud maxiter** - `d57cb2f` (feat)
2. **Task 2: End-to-end convergence test, hand-enumerated (re-derived) cross-check, iteration-cap regression** - `d7d8222` (test)

_Note: no TDD RED/GREEN split commits were made — this is a greenfield orchestration file with no pre-existing behavior to regress against, and the test was written and verified green alongside the implementation (mirrors plan 11-01's own noted TDD framing without a separate failing-test commit)._

## Files Created/Modified

- `src/planning/benders.jl` — `solve_stackelberg!`: the build-once outer Benders loop (guards → build oracle/follower/master once → iterate → fail-loud maxiter)
- `test/test_planning_benders.jl` — end-to-end convergence + checkpoint-count regression, iteration-cap loud-failure regression (2 `@testitem`s, tagged `[:planning]`)
- `src/TSODSO.jl` — wired `include("planning/benders.jl")` as the SIXTH (final) line of the `planning/` include block, after `master.jl`

## Decisions Made

- **UB formula sign:** `UB = min(UB, master.c_y * lb_res.y + follower_res.cost - oracle_res.cost)` — MINUS `oracle_res.cost`, following 11-02-PLAN.md's own explicit action text (which supersedes 11-RESEARCH.md's Pattern 2 sketch showing a PLUS). Oracle's `cost` is a MAX-sense welfare value (a benefit), so it must be subtracted from the leader's MIN-sense total cost, not added.
- **Re-derived the fixture's analytic optimum rather than force a match to 11-01-PLAN.md's stated numbers:** verified analytically (`total(z) = 0.5z² − 0.7z`, minimized at `z* = 0.7`, giving `total(0.7) = -0.245`, strictly lower/better than `total(1.0) = -0.2`) and empirically (the converged Benders loop lands at `y=z≈0.699`, matching `z*=0.7` within `atol=1e-3`). Test assertions target `0.7`, with the derivation documented in the test file's header comment, per Task 2's own explicit escape-hatch instruction ("if the converged values are qualitatively wrong ... that is a genuine bug ... [otherwise] widen atol and document why — do NOT change `benders.jl`'s cut-sign logic to force a match"). The converged values are strictly positive and feasible (not qualitatively wrong), so this is documented as a corrected test expectation, not a code bug.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug in a prior plan's derived toy-fixture numbers, not in this plan's code] Corrected the test's expected converged optimum from 11-01-PLAN.md's stated (incorrect) hand-enumeration**
- **Found during:** Task 2, first test run — `result.y`/`result.z[1]` converged to ≈0.699, failing the plan's literal `isapprox(..., 1.0; atol=1e-3)` assertions while `result.gap <= 1e-6` passed cleanly.
- **Issue:** 11-01-PLAN.md's `<toy_fixture>` block states a "hand-enumerated optimum" of `y*=1.0, z*=1.0, total leader cost=-0.2` for later reuse by this plan and plan 11-03. Re-deriving the leader's true minimization analytically (`total(z) = c_y*z + m_f*z - welfare(z) = 0.5z² - 0.7z`) shows the first-order-optimal point is `z*=0.7` (`total(0.7)=-0.245`), which is strictly better (lower) than `total(1.0)=-0.2` — i.e. `z*=1.0` is not even a stationary point of the fixture's own cost function. This is an arithmetic slip in 11-01-PLAN.md's own toy-fixture documentation, not a defect in `solve_stackelberg!`.
- **Fix:** Verified the implementation's sign convention and UB/LB formula are exactly as specified in 11-02-PLAN.md's own action text (independently confirmed via a standalone debug script reproducing the same iteration trace and converged values). Updated `test/test_planning_benders.jl`'s assertions to the re-derived, verified analytic optimum (`y*=z*=0.7`), with the full derivation documented in the file's header comment for plan 11-03's own certification test to independently re-derive (not blindly reuse) rather than assume 11-01-PLAN.md's stated numbers.
- **Files modified:** `test/test_planning_benders.jl` (assertion values + documentation only — `src/planning/benders.jl` was NOT changed as a result of this finding).
- **Verification:** Re-ran the full `[:planning]`-tagged suite (105/105 green) and the full project suite (4004/4008 passed, 4 pre-existing `broken`, 0 failed) twice independently after the correction.
- **Committed in:** `d7d8222` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — corrected a prior plan's incorrect hand-derived toy-fixture expectation; zero change to `src/planning/benders.jl`'s logic)
**Impact on plan:** Process-level correction to a test's expected value; the delivered `solve_stackelberg!` implementation exactly matches 11-02-PLAN.md's specified sign convention, UB/LB formula, and loop structure. No scope creep. Plan 11-03's own certification test should independently re-derive the certification instance's optimum rather than reuse 11-01-PLAN.md's stated (incorrect) numbers — flagged here for visibility.

## Issues Encountered

- **Worktree base mismatch at spawn time:** this worktree's HEAD was initially at an unrelated commit (main-checkout drift), predating the Phase-11 wave-1 tracking update. The mandatory `<worktree_branch_check>` merge-base comparison correctly identified the mismatch and `git reset --hard` to the expected base (`6cbfae2`) resolved it before any file was read or written. Resolved per the documented step; no plan-execution impact.
- **`TestItemRunner.runtests(filter=...)` (as used in the plan's own `<verify>` automated commands) does not exist in the installed TestItemRunner 1.1.5** — same finding as plan 11-01; the correct API is `@run_package_tests filter=...`. A temporary merged Julia environment (`Pkg.develop` on the package root + the `test/Project.toml` deps) was built once in the scratchpad and reused for all filtered/full-suite runs this session, mirroring what `Pkg.test()` does internally.
- **Background full-suite runs initially appeared to produce no output** — two earlier `run_in_background` invocations of the full suite (~10 min each) reported empty `.output` capture files while running, giving the appearance of a silent crash; both in fact completed successfully (exit code 0) once their completion notifications arrived, with the real results in the redirected log files. No product-code impact; a verification-tooling timing note for future plans in this phase.

## User Setup Required

None — no external service configuration required. No new package dependencies were added (`Project.toml`/`Manifest.toml` unchanged).

## Next Phase Readiness

- `solve_stackelberg!` is built, tested, and exported — the single-distributor Stackelberg equilibrium now solves end-to-end via the hand-rolled Benders loop (PLAN-06 complete).
- **Flag for plan 11-03:** 11-01-PLAN.md's `<toy_fixture>` "hand-enumerated optimum" (`y*=1.0, z*=1.0, total leader cost=-0.2`) is NOT the correct analytic optimum for the stated fixture — the correct value is `y*=z*=0.7`, `total=-0.245` (see this plan's test file header for the full derivation). Plan 11-03's BilevelJuMP certification gate should independently re-derive/verify its own certification instance's optimum from first principles rather than reuse this specific stated number set. If plan 11-03 reuses the SAME toy fixture (T=1, same numeric constants), it should expect its BigMMode/StrongDualityMode/hand-enumeration triple to agree on `z*≈0.7`, not `1.0`.
- No other blockers. The oracle's sign convention, the follower's pinned dual sign, and the master's multi-cut epigraph structure (all from plan 11-01) are consumed here exactly as documented, with no re-derivation needed.

---
*Phase: 11-single-distributor-stackelberg-benders-certified*
*Completed: 2026-07-22*

## Self-Check: PASSED

- FOUND: src/planning/benders.jl
- FOUND: test/test_planning_benders.jl
- FOUND: .planning/phases/11-single-distributor-stackelberg-benders-certified/11-02-SUMMARY.md
- FOUND commit: d57cb2f
- FOUND commit: d7d8222
