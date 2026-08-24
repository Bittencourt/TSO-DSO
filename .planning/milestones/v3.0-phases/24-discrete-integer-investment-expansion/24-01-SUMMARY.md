---
phase: 24-discrete-integer-investment-expansion
plan: 01
subsystem: planning
tags: [jump, highs, milp, benders, binary-expansion, solver-factory]

# Dependency graph
requires:
  - phase: 11-planning-benders-foundation
    provides: "BendersMaster/build_master (continuous LP master, Pitfall M1 epigraph
      lower bounds), solve_planning_oracle!/solve_follower! entrypoints"
provides:
  - "select_optimizer(::MILP()) with mip_rel_gap => 0.0 (exact HiGHS MILP solves)"
  - "BendersMasterInteger struct + build_master_integer builder (K-binary-expansion
    MILP master, D-01/D-02/D-03) + its own solve_master! method (dual=false)"
  - "L = α_op_lb + α_x_lb pinned on the struct, empirically confirmed valid over
    [0, y_max] against the real oracle/follower entrypoints (Assumption A1 closed)"
affects: [24-02-cut-mechanics, 24-03-cut-algebra-trace, 24-04-benders-loop-integration,
  24-05-certification, 24-06-literate-docs]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "New, completely separate builder alongside an untouched sibling (BendersMasterInteger/
      build_master_integer next to BendersMaster/build_master) to keep a byte-identical
      continuous baseline by construction, not by argument."
    - "Binary-expansion investment variable as a JuMP @expression over raw Bin @variables,
      never a @variable itself — keeps the raw binaries individually addressable for a
      future combinatorial cut while the derived quantity behaves like the continuous
      master's y_inv everywhere else (constraints/objective)."

key-files:
  created:
    - src/planning/master_integer.jl
    - test/test_solver_factory_milp.jl
    - test/test_planning_master_integer.jl
  modified:
    - src/solver/factory.jl
    - src/TSODSO.jl

key-decisions:
  - "mip_rel_gap => 0.0 added to select_optimizer(::MILP()) in src/solver/factory.jl even
    though 24-CONTEXT.md's <domain> statement says the phase touches only src/planning/ —
    this is an orchestrator-confirmed amendment (MILP() had zero prior call sites
    repo-wide), not scope creep."
  - "Chose a genuinely separate BendersMasterInteger struct (RESEARCH.md Pattern 2 option
    (a)) over retrofitting BendersMaster with an abstract supertype (option (b)) — keeps
    master.jl completely untouched, the safest reading of D-05's byte-identical-continuous-
    path requirement."
  - "solve_master!(::BendersMasterInteger) deliberately passes dual=false to
    solve_with_retry! — HiGHS/MOI reports no meaningful LP dual for a genuine MIP solve;
    dual=true (the continuous default) would spuriously fail is_solved_and_feasible on
    every solve of this master."

requirements-completed: [INT-01]

# Metrics
duration: 27min
completed: 2026-08-23
---

# Phase 24 Plan 01: HiGHS MILP Exactness Fix + Binary-Expansion Investment Master Summary

**Exact-gap HiGHS MILP factory fix plus a new `BendersMasterInteger`/`build_master_integer`
binary-expansion MILP master, with the Laporte-Louveaux cut's required lower bound `L`
confirmed valid over `[0, y_max]` by an executed sweep against the real oracle/follower
entrypoints (not the archived closed form).**

## Performance

- **Duration:** ~27 min (base commit 18:26:16 -> Task 2 commit 18:53:49, America/Sao_Paulo)
- **Started:** 2026-08-23T21:26:16Z
- **Completed:** 2026-08-23T21:53:49Z
- **Tasks:** 2 completed
- **Files modified:** 5 (2 modified, 3 created)

## Accomplishments

- `select_optimizer(::MILP())` now sets `mip_rel_gap => 0.0` in addition to the existing
  `output_flag => false`, closing RESEARCH.md Priority Finding 4 — the HiGHS 1.24.1 runtime
  default `mip_rel_gap = 1e-4` was previously unset, meaning any later "exact lattice
  termination" claim (D-13) would have silently inherited that slack from the inner MILP
  solve. Verified (both by the new standalone `@testitem` and manually) that the exact gap
  does not stall branch-and-bound on this project's tiny toy instances.
- New `src/planning/master_integer.jl`: `BendersMasterInteger` + `build_master_integer`
  build a completely separate K-binary-expansion MILP master (default `K = 4`, 16 levels,
  step `y_max/16`) alongside the untouched continuous `BendersMaster`/`build_master`. The
  derived investment expression `y_inv = (y_max/2^K) * Σ_k 2^(k-1) b_k` is a JuMP
  `@expression` over raw `Bin` variables, so the raw binaries remain individually
  addressable for plan 24-02's Laporte-Louveaux cut.
- `solve_master!(::BendersMasterInteger)` deliberately diverges from the continuous
  master's `dual = true` default, passing `dual = false` to `solve_with_retry!` — documented
  in the docstring and exercised by the zero-cut-solve regression test.
- Assumption A1 (RESEARCH.md's flagged open item) is closed by MEASUREMENT: a new test
  builds the D-12 canonical fixture's real `oracle`/`follower` objects and sweeps
  `z ∈ {0.0, 1.0, 2.0, 4.0, 8.0}` against `solve_planning_oracle!`/`solve_follower!`,
  confirming `L = α_op_lb + α_x_lb = -5.0` bounds `Q(z)` at every FEASIBLE sampled point.

## Task Commits

Each task was committed atomically:

1. **Task 1: HiGHS MILP exactness fix + standalone verification** - `4e92296` (fix)
2. **Task 2: BendersMasterInteger + build_master_integer + solve_master! + wiring** - `2f862d7` (feat)

_No plan-metadata commit yet — STATE.md/ROADMAP.md/REQUIREMENTS.md updates are owned by the
orchestrator per this plan's execution constraints._

## Files Created/Modified

- `src/solver/factory.jl` - `select_optimizer(::MILP())` now sets `"mip_rel_gap" => 0.0`
  alongside the existing `"output_flag" => false`; comment cites RESEARCH.md Priority
  Finding 4 and names Phase 24 as the first `MILP()` consumer.
- `test/test_solver_factory_milp.jl` (new) - standalone binary-knapsack smoke test:
  asserts `MOI.OPTIMAL` with the exact known integer optimum (value 5.0, items 1+2), and
  that the exact gap does not stall B&B.
- `src/planning/master_integer.jl` (new) - `BendersMasterInteger` struct, `build_master_integer`
  builder (boundary guards first: `T>=1`, `K>=1`, `y_max>0`, `c_y>=0`), and its own
  `solve_master!` method (`dual=false`).
- `src/TSODSO.jl` - one additive `include("planning/master_integer.jl")` line, positioned
  between `master.jl` and `benders.jl`.
- `test/test_planning_master_integer.jl` (new) - four `@testitem`s: boundary guards,
  zero-cut first solve (`MOI.OPTIMAL`), D-02 lattice-reachability (all-ones corner reaches
  `y_max*(1-2^-K) = 7.5`, never `8.0`), and the L-validity/Assumption-A1 sweep.

## Decisions Made

- **`src/solver/factory.jl` in scope despite 24-CONTEXT.md's `<domain>` statement.** The
  orchestrator explicitly confirmed this amendment before execution (zero prior `MILP()`
  call sites repo-wide, so the change is additive-only). Noted here so a reviewer does not
  read the factory.jl diff as unauthorized scope creep.
- **New struct over abstract-supertype retrofit (RESEARCH.md Pattern 2).** Chose option
  (a) — a wholly separate `BendersMasterInteger` — over option (b)'s one-line
  `abstract type AbstractBendersMaster` retrofit to `master.jl`. This keeps `master.jl`
  completely untouched (not even a supertype annotation), the strictest possible reading
  of D-05's "byte-identical continuous path by construction."
- **`dual = false` in the new `solve_master!` method.** HiGHS/MOI reports no meaningful LP
  dual for a genuine MIP solve at the integer optimum; the continuous master's
  `dual = true` default would spuriously fail `is_solved_and_feasible` on every call.
  Documented in the function's own docstring (T-24-02 mitigation) and exercised by the
  zero-cut-solve regression.
- **D-02's unreachable-`y_max` artifact stated in the builder's own docstring**, in the
  same paragraph as the K=4 default lattice description (not a separate, easy-to-miss
  note), per the plan's explicit requirement.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] L-validity test's literal z-sweep included a follower-
infeasible sample point (`z = 8.0`)**
- **Found during:** Task 2, writing the L-validity/Assumption-A1 regression test.
- **Issue:** The plan's `<interfaces>` block specifies sweeping `z ∈ {0.0, 1.0, 2.0, 4.0,
  8.0}` and asserting `follower_res.cost >= 0.0` at every sampled `z`. A standalone
  measurement script (reproducing the exact D-12 fixture) showed that at `z = 8.0` the
  follower is genuinely INFEASIBLE: `solve_follower!` returns `(; feasible = false, v, u)`,
  a NamedTuple with no `cost` field, so a literal implementation of the plan's described
  assertion would error (`v = 2.0`, a valid Farkas certificate). This is NOT a modeling
  bug — the follower's own corridor capacity `corridor_cap * x_inv_max = 2.0 * 2.0 = 4.0`
  caps deliverable flow INDEPENDENTLY of the master's `y_inv`/`y_max`, and 24-RESEARCH.md's
  Priority Finding 1 explicitly documents this exact mechanism ("the master's LP
  relaxation can still propose an intermediate `z_k`... that the follower cannot
  deliver... orthogonal to LL-cut applicability... keep it exactly as-is").
- **Fix:** The test now branches on `follower_res.feasible`: on the feasible branch it
  asserts `follower_res.cost >= 0.0` and `master.L <= -oracle_res.cost + follower_res.cost`
  exactly as the plan intended; on the infeasible branch (only `z = 8.0` on this fixture)
  it asserts the returned Farkas certificate is genuinely valid (`isfinite(v) && v > 0`,
  already guaranteed by `solve_follower!`'s own contract) rather than asserting a `cost`
  field that does not exist there. A separate assertion confirms `z = 0.0` is ALWAYS
  feasible (complete recourse, the concrete anchor A1's Laporte-Louveaux-cut applicability
  actually needs — per RESEARCH.md, `L`'s validity claim is only required at points where
  `Q(z)` is even defined, i.e. feasible points; the master's own existing feasibility-cut
  branch, unchanged by this plan, handles the infeasible-trial case).
- **Files modified:** `test/test_planning_master_integer.jl`.
- **Verification:** Confirmed via a standalone script reproducing the D-12 fixture
  (inline `two_bus_feeder`/`ToyElasticDevice` construction, since the real fixtures live
  in test-only `@testmodule`s unreachable from a raw script) — the full corrected sweep
  passes at every sampled `z`, printing `A1 CONFIRMED by measurement`.
- **Committed in:** `2f862d7` (part of Task 2 commit).

---

**Total deviations:** 1 auto-fixed (Rule 3 — blocking issue).
**Impact on plan:** Necessary for the L-validity test to even execute without erroring;
the underlying Assumption A1 claim (L bounds Q(z) at every point where recourse is
defined) is STILL closed by measurement exactly as the plan required — the fix only
corrects how the infeasible sample is handled, not the claim itself. No scope creep.

## Issues Encountered

**Known, deliberate, wave-sequenced gap in the PVAL-04 no-binaries guard
(`test/test_planning_noninteger.jl`) — NOT fixed in this plan, by design.** Adding the new
exported `build_master_integer` symbol trips that file's existing source-scan tripwire
(the `found` set now includes `"build_master_integer"`, which is not yet a registry key),
so running that ONE `@testitem` in isolation currently fails. This is expected and
explicitly out of scope for plan 24-01: D-06/D-07/24-CONTEXT.md and 24-VALIDATION.md's
per-task verification map (row `24-02-02`) assign the registry/EXEMPT-list update to plan
24-02 Task 2, and this plan's own constraints forbid touching other phase-24 plans' files.
24-VALIDATION.md's own Sampling Rate section defers full-suite (`@testitem`) execution to
the phase-closing gate (plan 24-06 Task 2) for exactly this reason — a temporary,
single-test gap between wave 1 and wave 2 is anticipated, not a regression to chase down
here. No `Pkg.test()` was run in this plan (per the phase's own environment-trap guidance
and the per-task quick-command sampling rate); all verification here used direct,
Test-free `julia --project=.` scripts and the plan's own `<verify>` blocks.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

`BendersMasterInteger`/`build_master_integer` are ready for plan 24-02 to add the
`add_optimality_cut!`/`add_feasibility_cut!` method overloads for this new type, register
`build_master_integer` in `test/test_planning_noninteger.jl`'s EXEMPT list (closing the
known gap noted above), and begin the Laporte-Louveaux cut implementation using
`master.b` (the raw binary vector) and `master.L` (the pinned recourse lower bound), both
already exposed on the struct exactly as plan 24-02 needs them.

No blockers. The `mip_rel_gap => 0.0` factory fix and the confirmed `L`-validity bound are
both prerequisites plan 24-02's cut algebra depends on, and both are now in place and
verified.

---
*Phase: 24-discrete-integer-investment-expansion*
*Completed: 2026-08-23*

## Self-Check: PASSED

All 5 created/modified files confirmed present on disk; both task commit hashes
(`4e92296`, `2f862d7`) confirmed present in `git log --oneline --all`.
