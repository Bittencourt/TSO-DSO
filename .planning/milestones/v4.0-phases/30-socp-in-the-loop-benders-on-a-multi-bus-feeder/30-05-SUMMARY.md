---
phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder
plan: 05
subsystem: testing
tags: [jump, clarabel, socp, benders, ieee13, testitems, literate, documenter]

# Dependency graph
requires:
  - phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder (plans 30-01/30-02/30-03/30-04)
    provides: "the oracle-feasibility-cut (BILEV-04a), AC-recheck (BILEV-04b),
      inexact_policy/:auto-bound (BILEV-04b/BILEV-05) wiring in solve_stackelberg!, plus
      the tuned T=4 IEEE13ShortHorizonFixtures population and independently-built
      solve_joint_reference monolithic cross-check (plan 30-03)"
provides:
  - "test/test_planning_benders_ieee13.jl: the BILEV-03 headline @testitem —
    solve_stackelberg! on ieee13_modified() with ConvexBranchFlow (T=4), the FIRST
    multi-bus fixture in the suite to exercise build_master's :auto α_op_lb/α_x_lb
    default end-to-end, cross-checked against an independently-built monolithic joint
    reference within a measured (not picked) tolerance"
  - "A measured three-source cross-check tolerance derivation (oracle's own SOCP duality
    gap, joint reference's own SOCP duality gap, and the Benders loop's own converged
    UB-LB absolute gap — the dominant, previously-missing term), documented inline"
  - "docs/literate/stackelberg_benders.jl extended with a full day-ahead (T=24) IEEE-13
    ConvexBranchFlow Stackelberg-Benders demonstration, outside the suite's ≤2min budget,
    including a third cone-gap convergence-figure panel"
affects: [31]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Cross-check tolerance measurement extended beyond the two solvers' own interior-
      point duality gaps to ALSO include the Benders loop's own converged UB-LB absolute
      gap (the dominant source here) — since the incumbent UB is only certified to lie
      within that gap of the true joint optimum, not to solver precision; omitting it
      measurably fails the cross-check (confirmed this session: 1.49e-4 discrepancy vs a
      2.79e-6 solver-precision-only guess)."
    - "A `T=24`-specific population builder (`house_agg_t24`) defined INLINE in the
      Literate script rather than generalizing the T=4 fixture's own `house_agg`, because
      that function hardcodes `T` as a `@testmodule`-level constant referenced in its own
      body — documented as a deliberate non-generalization, not an oversight."

key-files:
  created:
    - test/test_planning_benders_ieee13.jl
  modified:
    - docs/literate/stackelberg_benders.jl

key-decisions:
  - "Reused plan 30-03's own smoke-test kwargs tuple verbatim for the T=4 headline test
    (follower_kwargs: corridor_cap=1.0, x_inv_max=0.05, c_inv=0.01, c_op=fill(0.01,T);
    master_kwargs: c_y=0.01, y_max=0.05, NO α_op_lb/α_x_lb) — confirmed by probe to stay
    entirely inside the fixture's documented feasible-and-exact z∈[-0.05,0.05] window,
    converging in 6 iterations with every trace entry SOCP-exact (ac_report=nothing)."
  - "The cross-check tolerance formula is `10 * max(oracle_gap, joint_gap, |UB-LB|)`, NOT
    just `10 * max(oracle_gap, joint_gap)` as a literal reading of the plan's own
    <action> block might suggest — the UB-LB term was found necessary by direct
    measurement (the two-source formula fails the cross-check; the three-source formula
    passes with a ~13x margin). Documented as a found, not assumed, correction to the
    plan's own worked recipe."
  - "T=24's own follower_kwargs/master_kwargs are DELIBERATELY smaller than the T=4
    headline test's (y_max=0.03/corridor_cap=0.5/x_inv_max=0.03, vs 0.05/1.0/0.05) — a
    live probe found the T=4-scale kwargs throw a genuine
    assert_battery_complementarity! violation at t=7 once the full 24-hour price swing
    is in play (Phase 30's own documented OUT-OF-SCOPE-for-inexact_policy case: a
    complementarity violation, not an exactness-class throw). Tightening the investment
    ceiling keeps every T=24 Benders trial inside the complementarity-safe region;
    confirmed by a full, live, error-free run (exit code 0)."
  - "T=24's own λ₀ day-ahead price profile is a redefinition (NOT an import) of
    test/fixtures_phase4.jl's Phase4Fixtures.mem_price_profile()'s own digitized
    morning-ramp/evening-peak shape, since docs/literate/*.jl imports `using TSODSO`
    ONLY (no test-only fixture modules) per that file's own stated convention."

requirements-completed: ["BILEV-03"]

# Metrics
duration: ~50min
completed: 2026-10-01
---

# Phase 30 Plan 05: BILEV-03 Convergence Test + T=24 Literate Experiment Summary

**The phase's headline demonstration: `solve_stackelberg!` converges on a realistic
multi-bus IEEE-13 feeder with the real `ConvexBranchFlow` SOCP formulation and `:auto`
master bounds, matching an independently-built monolithic reference within a measured
(three-source) tolerance — plus a full day-ahead (T=24) Literate extension confirmed to
run clean end-to-end.**

## Performance

- **Duration:** ~50 min
- **Completed:** 2026-10-01
- **Tasks:** 2/2 completed
- **Files modified:** 2 (1 new, 1 modified)

## Accomplishments

- `test/test_planning_benders_ieee13.jl`: one `@testitem` running the REAL
  `solve_stackelberg!` Benders loop with `ConvexBranchFlow()` on `ieee13_modified()`
  (T=4, `IEEE13ShortHorizonFixtures`), the FIRST multi-bus fixture in the suite to
  exercise `build_master`'s NEW `:auto` `α_op_lb`/`α_x_lb` default end-to-end (omitting
  both keys from `master_kwargs` entirely). Measured convergence: `iters=6`,
  `gap=3.141107077821004e-7` (well inside `tol=1e-6`).
- The convergence result is cross-checked against
  `IEEE13ShortHorizonFixtures.solve_joint_reference` — an INDEPENDENTLY-BUILT monolithic
  single-shot SOCP model (never a reuse of `PlanningOracle`/`FollowerLP`/`BendersMaster`)
  — within a MEASURED tolerance derived from THREE sources: the oracle's own SOCP
  duality gap (`2.79e-7`), the joint reference's own SOCP duality gap (`1.92e-7`), and
  the Benders loop's own converged `|UB-LB|` absolute gap (`1.91e-4`, the DOMINANT and
  previously-missing term — see Deviations below). `measured_tol = 1.913e-3`; the actual
  observed discrepancy `|UB - (-welfare_total)| = 1.489e-4` sits comfortably inside it
  (~13x margin).
- A POSITIVE assertion about the incumbent's cone-gap status (BILEV-03's "never assume
  exactness" requirement): `result.ac_report === nothing` and
  `all(isnan, result.trace.socp_maxgap_trace)` — this fixture's kwargs keep the entire
  Benders trial box inside the fixture's documented feasible-and-exact `z∈[-0.05,0.05]`
  window, so every iteration came back genuinely SOCP-exact this session (a legitimate,
  confirmed outcome, contrasted in the test's own comments against
  `test_planning_inexact_policy.jl`'s fixture, which deliberately drives the inexact
  branch).
- `docs/literate/stackelberg_benders.jl` gains a new, pure-addition section
  demonstrating `solve_stackelberg!` with `ConvexBranchFlow()` on `ieee13_modified()` at
  a full day-ahead horizon (`T=24`), via an inline `house_agg_t24` population builder
  (the T=4 fixture's own `house_agg` hardcodes `T` as a module constant and does not
  generalize). Confirmed this session (`julia --project=. docs/literate/stackelberg_benders.jl`,
  exit code 0, ~130s wall time): converges in `iters=15`, `gap≈3.09e-7`, `y=0.015`,
  `ac_report=nothing` (SOCP-exact throughout — every `socp_maxgap_trace` entry is the
  `NaN` sentinel).
- The existing convergence-figure section gains a THIRD panel (for the new T=24 figure)
  plotting `result24.trace.socp_maxgap_trace`, masked with the SAME `isfinite.(...)` +
  `max.(..., eps())` log-axis-floor idiom the existing two panels already use. The
  existing T=1 toy-instance content is completely unchanged (pure addition, confirmed by
  `git diff --stat` showing only insertions).

## Task Commits

Each task was committed atomically:

1. **Task 1: BILEV-03 convergence + monolithic cross-check @testitem** - `3ef09a5` (test)
2. **Task 2: T=24 IEEE-13 Literate experiment extension** - `0808816` (feat)

## Files Created/Modified

- `test/test_planning_benders_ieee13.jl` - the BILEV-03 headline `@testitem`:
  `solve_stackelberg!` on `ieee13_modified()`/`ConvexBranchFlow()`/T=4 with `:auto`
  master bounds, cross-checked against `IEEE13ShortHorizonFixtures.solve_joint_reference`
  within a measured tolerance, plus a positive cone-gap-status assertion.
- `docs/literate/stackelberg_benders.jl` - new "Rung 6 at scale" section: inline
  `house_agg_t24`, a T=24 day-ahead price profile, a `solve_stackelberg!` call, narrated
  real-observed-number cells, and a 3-panel (bounds/gap/cone-gap) CairoMakie figure.

## Decisions Made

- **Cross-check tolerance formula extended to three sources** (see `key-decisions`
  above): `10 * max(oracle_gap, joint_gap, |UB-LB|)`. The Benders loop's own converged
  absolute bound gap dominates and was found NECESSARY by direct measurement — a
  two-source (solver-precision-only) formula measurably fails the cross-check
  (`2.79e-6` vs an observed `1.49e-4` discrepancy), while the three-source formula
  passes with a comfortable ~13x margin. This refines (not contradicts) the plan's own
  `<action>` recipe, which named "the MIP/SOCP duality gap each solver reports" as an
  acceptable alternative source — the Benders UB-LB gap is exactly that for the
  decomposed side of the comparison.
- **T=4 headline fixture kwargs** reused plan 30-03's own smoke-test tuple verbatim
  (confirmed to stay inside the documented feasible-and-exact window, converging
  cleanly in 6 iterations).
- **T=24 fixture kwargs tightened** (`y_max=0.03`/`corridor_cap=0.5`/`x_inv_max=0.03` vs
  the T=4 test's `0.05`/`1.0`/`0.05`) after a live probe found the T=4-scale kwargs throw
  a genuine `assert_battery_complementarity!` violation at `t=7` under the full 24-hour
  price swing — an OUT-OF-SCOPE-for-`inexact_policy` complementarity throw (not an
  exactness-class one), per `solve_stackelberg!`'s own documented disambiguation.
  Several alternative tunings were probed (larger `batt_emax`, smaller `batt_pmax`) and
  all either failed with the same complementarity violation or converged; the smaller
  investment-ceiling tuning was chosen as the minimal-diff fix (same population
  magnitudes as the T=4 fixture, only the leader/follower investment bounds shrunk).
- **T=24's λ₀** is a redefinition (not an import) of `Phase4Fixtures.mem_price_profile()`'s
  own digitized price shape, since Literate docs pages import `using TSODSO` only.

## Deviations from Plan

### Auto-fixed Issues

None — no Rule 1/2/3 auto-fixes to production code were needed (this is a test/docs-only
plan, consistent with its own threat model's trust-boundary note).

### Other Deviations

**1. [Found correction] The plan's own two-source tolerance recipe was insufficient — a
third source (the Benders UB-LB gap) was required and added**
- **Found during:** Task 1, deriving the measured cross-check tolerance.
- **Issue:** The plan's `<action>` block names "read BOTH models' own certified solver
  precision ... take 10x the worse of the two" (i.e., `oracle_gap`/`joint_gap` only).
  Measured directly this session: `10 * max(oracle_gap, joint_gap) = 2.79e-6`, which
  FAILS `isapprox(result.UB, -joint.welfare_total; atol=2.79e-6)` — the actual measured
  discrepancy is `1.489e-4`, ~53x larger than that two-source tolerance.
- **Root cause (measured, not assumed):** `result.UB` is only certified by
  `solve_stackelberg!`'s own convergence gate to lie within the Benders loop's own
  `|UB-LB|` absolute gap (`1.913e-4` this session, matching the discrepancy's order of
  magnitude almost exactly) of the TRUE joint optimum — `LB` is a valid lower bound on it
  whenever every cut is exact (confirmed here: `ac_report === nothing`). This gap is
  STRUCTURALLY larger than either solver's own interior-point duality gap, since `tol`
  (a RELATIVE gap, `1e-6`) bounds it only loosely in absolute terms at this objective
  magnitude (`|UB| ≈ 609`).
  The plan's own `<action>` text does allow "or the MIP/SOCP duality gap each solver
  reports" as an alternative source — read here as covering exactly this case (the
  Benders loop's own certified gap is the relevant "duality gap" for the decomposed
  side of the comparison), so this is interpreted as a refinement of the plan's own
  recipe, not a contradiction of it.
- **Fix:** Added `ub_lb_gap = |result.UB - result.LB|` as a third measured source;
  `measured_tol = 10 * max(oracle_gap, joint_gap, ub_lb_gap) = 1.913e-3`. Re-verified:
  the cross-check now passes with the actual discrepancy sitting at ~13x inside the
  tolerance (a real, non-trivial margin, not a tautology).
- **Files affected:** test/test_planning_benders_ieee13.jl (the derivation is documented
  in full in that file's own header comment, mirroring `KNOWN_OPTIMUM_ATOL`'s convention).
- **Committed in:** `3ef09a5` (Task 1 commit — found and fixed before commit, never
  landed as a silently-failing or artificially-loosened check).

---

**Total deviations:** 1 (a found correction to the plan's own worked tolerance recipe,
resolved by measurement before the Task 1 commit; no production code touched).
**Impact on plan:** None on scope — the cross-check still uses a genuinely MEASURED,
documented tolerance (never a picked one), just derived from three sources instead of
two, per direct empirical necessity.

## Issues Encountered

- **TestItemRunner module-scoping trap (new instance of a known class):** an initial
  draft defined the measured cross-check tolerance as a file-level `const` outside the
  `@testitem` block (mirroring `benders.jl`'s own `KNOWN_OPTIMUM_ATOL` production-code
  convention) — this does NOT work for test files: TestItemRunner gives each `@testitem`
  its own anonymous module, so a file-level `const` is invisible inside the item body
  (confirmed via the emulator: `UndefVarError: MEASURED_CROSSCHECK_ATOL not defined`).
  Resolved by moving the constant definition inline inside the `@testitem` body (a plain
  local variable), keeping the full derivation as the file's own header comment (its sole
  documented source) — the SAME pattern already used by every other `@testitem` file in
  this suite that documents a measured constant (none of them define file-level consts
  either; only plain `Test.jl` scripts like `test_admm_timeout.jl` do that safely).
- **Background-child survival during a prior multi-call session boundary** required
  re-running the T=24 Literate script's end-to-end verification via a detached
  `nohup setsid` + foreground poll-loop pattern (per the orchestrating session's own
  guidance) to get a fully trustworthy exit-code-0 confirmation with measured wall time
  (~130s) — the underlying script and its numbers were unaffected; this was purely a
  verification-robustness step, not a code change.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 30's own ROADMAP success criterion 1 ("Run Stackelberg-Benders with
  `ConvexBranchFlow` on a real multi-bus, multi-period feeder, with oracle feasibility
  cuts and derived master bounds") is now DEMONSTRATED end-to-end: `solve_stackelberg!`
  converges on `ieee13_modified()` with `ConvexBranchFlow`/`T=4` AND `T=24`, with `:auto`
  derived master bounds, matching an independent monolithic reference within a measured
  tolerance, and the incumbent's cone-gap status is always positively reported.
- Plan 30-06 (phase close) should carry forward: (1) the refined three-source
  cross-check tolerance pattern (oracle gap / joint-reference gap / Benders UB-LB gap)
  as a reusable convention for any future Benders-vs-monolithic cross-check in this
  codebase; (2) the T=24 kwargs-tightening finding (a T=4-scale investment ceiling can
  trigger a genuine `assert_battery_complementarity!` violation once a full 24-hour price
  swing is in play) as a tuning caveat for Phase 31's own planning-docs refresh.
- No blockers.

---
*Phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder*
*Completed: 2026-10-01*

## Self-Check: PASSED

- FOUND: test/test_planning_benders_ieee13.jl
- FOUND: docs/literate/stackelberg_benders.jl
- FOUND: .planning/phases/30-socp-in-the-loop-benders-on-a-multi-bus-feeder/30-05-SUMMARY.md
- FOUND: commit 3ef09a5 (Task 1)
- FOUND: commit 0808816 (Task 2)
