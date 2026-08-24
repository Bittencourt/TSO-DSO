---
phase: 24-discrete-integer-investment-expansion
plan: 05
subsystem: planning
tags: [benders, laporte-louveaux, certification, enumeration, testitem, ternary-search]

# Dependency graph
requires:
  - phase: 24-discrete-integer-investment-expansion
    plan: 04
    provides: "solve_stackelberg!'s master=nothing/known_optimum injection kwargs,
      converged_now mutually-exclusive termination, apply_integer_cuts! wiring with
      nogood_count/converged_via surfaced"
provides:
  - "enumerate_lattice — an independent, exhaustive 16-point K=4 lattice oracle using the
    REAL production solve_follower!/solve_planning_oracle! entrypoints (never the archived
    closed-form shortcut), the PRIMARY certificate for INT-03 (D-10)"
  - "The INT-03 certification @testitem: attempts solve_stackelberg!(...; master =
    build_master_integer(...), known_optimum = enumerated optimum), with D-15
    certificate 1 (per-cut LL validity against the real enumerated optimum), D-15
    certificate 2 (continuous-baseline diff against the PVAL-02 N1 golden), and D-16
    visibility (nogood_count/converged_via)"
  - "The negative-control regression proving plan-checker Blocker 2's exclusive
    termination branch (converged_now) is genuinely authoritative, not coincidentally
    consistent with a lingering gap<=tol escape hatch"
  - "CONFIRMED, DOCUMENTED FINDING: a genuine, pre-existing defect in already-merged
    plan 24-03/24-04 code (add_ll_cut!'s caller in benders.jl passes the recourse at the
    master's current z trial, not the true per-corner minimized recourse), discovered by
    this certification effort — exactly what a certify-before-build gate exists to catch"
affects: [24-05.1-gap-closure, 24-06-literate-docs]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Exhaustive-enumeration-as-independent-oracle: enumerate_lattice re-derives
      y_inv(b) via the IDENTICAL formula build_master_integer uses (T-24-13), so the
      certificate can never silently agree with the production builder due to a
      shared bug, then finds each point's true recourse via a deterministic ternary
      search over the ALREADY-BUILT oracle/follower (build once, re-solve many)."
    - "TestItemRunner AST-based-discovery workaround: a plain top-level helper function
      (enumerate_lattice) is dead code from the runner's per-testitem isolated-module
      perspective — each certifying @testitem must carry its OWN nested, independently-
      verified-identical copy of the same logic to make it genuinely execute under
      Pkg.test()."
    - "@test_broken as an honest, non-silent failure marker: when a certificate detects
      a genuine pre-existing defect, the victim assertions are marked @test_broken
      (not weakened, removed, or worked around) so the suite stays informative about
      exactly what still needs fixing, while every other, genuinely-passing assertion
      in the same @testitem is asserted for real."

key-files:
  created:
    - test/test_planning_certification_integer.jl
  modified: []

key-decisions:
  - "Rule 1 auto-fix to the plan's own literal inline verify script: 7 of the 16
    lattice points have y_inv > corridor_cap*x_inv_max = 4.0 (the follower's own
    deliverable capacity, independent of y_max=8.0), so solve_follower! genuinely
    returns its infeasible branch (no .cost field) for those points' ternary-search
    upper bound. Fixed by treating an infeasible trial z as +Inf in the extended-value
    sense — a convex function restricted to a feasible sub-interval and set to +Inf
    outside remains convex, and the feasible sub-interval [0, 4.0] is always nonempty
    on this fixture, so ternary search still converges to the true constrained minimum."
  - "The two D-15 certificate assertions that are victims of the newly-discovered
    Q_nu defect are marked @test_broken, per the plan's own explicit instruction not
    to weaken the certificate/cut/atol to force a green run. Every other assertion in
    the same @testitem (the loop failing loudly rather than silently, the cut
    mechanism's own violation-detection working correctly, D-15 certificate 2, D-16
    visibility, the negative-control regression) is asserted for real, not skipped."
  - "The D-11 BilevelJuMP non-blocker finding is recorded as a code comment citing
    RESEARCH.md's own verified Priority Finding 3 and the EXISTING negative MIQP
    regression in test_planning_certification.jl by name/line-range — no new
    BilevelJuMP @testitem is written, since it is known in advance to fail on this
    fixture for two independently-verified reasons."

requirements-completed: [INT-03]

# Metrics
duration: ~40min
completed: 2026-08-23
---

# Phase 24 Plan 05: INT-03 Exhaustive-Enumeration Certification Summary

**Built an independent, exhaustive 16-point enumeration oracle for the D-12 tiny
instance and used it to certify the integer Benders loop — which caught a genuine,
pre-existing Laporte-Louveaux cut defect in already-merged plan 24-03/24-04 code,
documented via `@test_broken` rather than weakened away.**

## Performance

- **Duration:** ~40 min wall clock (Task 1 commit `3a30317` — Task 2 commit `503b6e1`)
- **Completed:** 2026-08-23
- **Tasks:** 2 completed
- **Files modified:** 1 (created)

## Accomplishments

- `enumerate_lattice(oracle, follower; K=4, y_max=8.0, c_y=0.3)` — exhaustively walks
  all `2^K = 16` binary-expansion lattice points using the IDENTICAL `y_inv(b)` formula
  `build_master_integer` uses (T-24-13), finding each point's exact recourse
  `Q(y_inv) = min_{z∈[0,y_inv]}[follower_cost(z) - oracle_welfare(z)]` via a
  deterministic 100-iteration ternary search that re-solves the ALREADY-BUILT
  `oracle`/`follower` through `solve_planning_oracle!`/`solve_follower!` — never the
  archived closed-form `0.5*z^2-0.7*z` shortcut from `11-01-PLAN.md`.
- The primary INT-03 certification `@testitem`: builds the D-12 fixture, runs the
  exhaustive enumeration, attempts
  `solve_stackelberg!(...; master = build_master_integer(...), known_optimum =
  enum_result.best_total, max_iter = 50)`, and runs:
  - **D-15 certificate 1** (per-cut LL validity): every fired `:ll` cut's own RHS,
    evaluated at the TRUE enumerated optimum, must not exceed the true optimum's
    total — `@test_broken` (see Confirmed Finding below).
  - **D-15 certificate 2** (continuous-baseline diff): the continuous relaxation
    objective (`PlanningFixtures.N1_OBJ_HAND`) is a valid lower bound on a
    (separately, uncertified-path) integer result, and that integer `y` is within
    one lattice step (`0.5`) of the continuous `y*=0.7` — both genuinely pass.
  - **D-16 visibility**: `nogood_count`/`converged_via` present and well-typed on the
    uncertified-path result — genuinely passes.
- A second `@testitem`, the negative-control regression: a deliberately WRONG
  `known_optimum` (`enum_result.best_total - 1.0`, comfortably outside
  `KNOWN_OPTIMUM_ATOL` and every other lattice point's own total) with `max_iter = 30`
  correctly raises `ErrorException` — never falsely converges via a stray `gap<=tol`
  match. This is the assertion with real teeth against plan-checker Blocker 2's
  forbidden `||`: under the pre-existing bug it would have wrongly returned `true`.

## CONFIRMED FINDING — a genuine, pre-existing defect in already-merged code

Via the enumeration harness run against the REAL certified `solve_stackelberg!` path
(exactly what INT-03/this plan exists to run), the Laporte-Louveaux cut wired by
plans 24-03/24-04 (`add_ll_cut!`/`apply_integer_cuts!`, `src/planning/master_integer.jl`)
was found to use `Q_nu = follower_res.cost - oracle_res.cost` evaluated AT THE
MASTER'S CURRENT `z` TRIAL — the recourse at whatever `z` the master happened to pick
for the incumbent corner `b^ν` — not the TRUE, exactly-minimized recourse
`Q(y_inv(b^ν))` the Laporte-Louveaux "cut with a value" theorem requires
(`add_ll_cut!`'s own docstring states this precondition; the CALLER, `benders.jl`, was
the one that failed to honor it). Since the master's box constraint only guarantees
`z_k <= y_inv(b^ν)` (feasibility), not `z_k` = the minimizer, `Q_nu >= Q(y_inv(b^ν))`
in general — an upper-bound surrogate. Because cut rows are never retracted, an early,
loose `Q_nu` permanently over-constrains `theta` at that corner.

Concretely, on the D-12 fixture: a fired LL cut at the TRUE enumerated optimum's own
corner (`b=[1,0,0,0]`, `y=0.5`) had RHS `-0.1756`, exceeding the true enumerated total
`-0.225` — a genuine "excludes the true optimal lattice point" violation. With
`max_iter=50`, the accumulated over-tight cuts eventually no-good-ban all 16 lattice
corners and the master MILP goes genuinely `MOI.INFEASIBLE` before ever matching the
certified target — `solve_stackelberg!` raises a loud `ErrorException` (D-10's
discipline holds: it never silently returns a wrong answer), but does not return a
certified result.

Per this plan's own explicit instruction ("do not weaken the certificate, the cut, or
the atol to obtain a green run — an honest failure here is a legitimate deliverable"),
the two assertions that are victims of this defect were marked `@test_broken`. Every
other assertion in the same `@testitem` — the loop failing LOUDLY rather than
silently, the cut mechanism's own violation-detection correctly DETECTING the
violation, D-15 certificate 2, D-16 visibility, and the negative-control regression —
was asserted for real and genuinely passed. A follow-up plan was flagged as required
to fix `add_ll_cut!`'s caller to pass the TRUE per-corner minimized recourse
(Rule 4: architectural fix, out of scope for this certification-only plan).

**This finding was resolved in the gap-closure wave 24-05.1** — see
`24-05.1-SUMMARY.md`. Two ADDITIONAL, independently-discovered defects (an over-eager
no-good "stall" heuristic, and a too-loose HiGHS `mip_feasibility_tolerance`) were also
found and fixed during that wave's re-verification of this same certification.

## Task Commits

1. **Task 1: exhaustive K=4 lattice enumeration harness** - `3a30317` (feat)
2. **Task 2: INT-03 certification + D-15 certs + negative control** - `503b6e1` (test)

## Files Created/Modified

- `test/test_planning_certification_integer.jl` (new, 455 lines pre-gap-closure) —
  `enumerate_lattice` (Task 1), the primary INT-03 certification `@testitem` and the
  negative-control regression `@testitem` (Task 2).

## Decisions Made

See `key-decisions` in frontmatter: the Rule 1 infeasible-trial-as-+Inf fix, the
`@test_broken` marking discipline for the two victim assertions, and the D-11
citation-only documentation choice (no new BilevelJuMP code).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Infeasible ternary-search trial crashes with FieldError**
- **Found during:** Task 1 (enumeration harness)
- **Issue:** The plan's own literal inline `<verify>` script crashes with a
  `FieldError` when a ternary-search trial `z` exceeds the follower's deliverable
  capacity (`corridor_cap * x_inv_max = 4.0`), which is strictly below `y_max = 8.0` —
  true for 7 of the 16 lattice points (`y_inv > 4.0`). `solve_follower!`'s genuine
  infeasible branch has no `.cost` field.
- **Fix:** Treat an infeasible trial `z` as `+Inf` in the extended-value sense — a
  convex function restricted to a feasible sub-interval and set to `+Inf` outside
  remains convex, and `[0, 4.0]` is always nonempty on this fixture, so ternary
  search still converges to the true constrained minimum.
- **Files modified:** test/test_planning_certification_integer.jl
- **Verification:** Direct `include()` of the committed file (bypassing
  TestItemRunner) confirms `best_y=0.5`, `best_total ∈ (-0.25, -0.2)` on the D-12
  fixture.
- **Committed in:** `3a30317`

---

**Total deviations:** 1 auto-fixed (Rule 1).
**Impact on plan:** Necessary for the enumeration harness to run at all on this
fixture's own follower-capacity geometry; no scope creep.

## Issues Encountered

None beyond the CONFIRMED FINDING documented above (which is the certification
working as designed, not an execution problem) and the Rule 1 auto-fix. Verified: a
JuliaSyntax-based `TestItemDetection` pass confirms both `@testitem`s parse and are
discovered cleanly (2 items, 0 errors); a standalone `Test.jl` emulation of both
items' exact logic (bypassing the sibling-worktree TestItemRunner hazard, per
MEMORY.md) passes 11 Pass + 2 Broken for item 1, 1 Pass for item 2 — exactly the
expected shape given the confirmed defect.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

The certification exists and genuinely detects the LL-cut `Q_nu` defect it was built
to catch — this is the "certify before build" gate working as intended. A follow-up
gap-closure wave is required to fix `benders.jl`'s recourse computation before this
phase's `INT-02`/`INT-03` requirements can be considered fully closed with a green
suite. (Resolved in `24-05.1` — see that plan's summary.)

---
*Phase: 24-discrete-integer-investment-expansion*
*Completed: 2026-08-23*

## Self-Check: PASSED

`test/test_planning_certification_integer.jl` confirmed present (pre-gap-closure
content reconstructed from commits `3a30317`/`503b6e1`, since superseded by
`24-05.1`'s edits); both task commit hashes (`3a30317`, `503b6e1`) confirmed present
in `git log --oneline`.
