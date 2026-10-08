---
phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh
plan: 04
subsystem: planning
tags: [julia, jump, benders, nash-equilibrium, game-theory, integer-planning, laporte-louveaux, highs]

# Dependency graph
requires:
  - phase: 31-01
    provides: "WR-01 fix (_oracle_or_infeasible confirms MOI.ALMOST_INFEASIBLE via feas_oracle), feas_oracle threaded through corner_recourse/ll_cut_recourse"
  - phase: 31-02
    provides: "build_master_integer's bounds_ctx/:auto/lb_slack machinery (byte-identical to build_master's); add_ll_cut!'s Q_nu >= L precondition guard"
  - phase: 31-03
    provides: "run_nash!/run_nash_probe current state (seed-dispatch extension, solve_variational_equilibrium) this plan's diff applies on top of"
provides:
  - "run_nash!'s new integer::Union{Nothing,NamedTuple} = nothing kwarg — every distributor's best response in the N-distributor Gauss-Seidel diagonalization builds a FRESH build_master_integer (bounds_ctx-validated :auto alpha_op_lb, explicit alpha_x_lb) and passes it via solve_stackelberg!'s existing master= keyword"
  - "Exact-binary-state cycle detection (Dict{Vector{Int},Int}, exact equality) — a genuinely cycling integer diagonalization raises a loud, NAMED ErrorException reporting the full cycle shape"
  - "Rule 1 fix: solve_follower!(::DistributorView) now handles a CONFIRMED MOI.INFEASIBLE without a Farkas dual ray (returns feasible=false instead of raising) — required for corner_recourse's ternary search to function at all against a DistributorView follower"
  - "test/test_planning_nash_integer.jl: N=2 K=4 integer Nash convergence + per-player 16-point brute-force certification (production corner_recourse, no profitable unilateral deviation) + integer kwarg boundary guards + cycle-detection dictionary-logic standalone replication"
affects: ["31-05", "31-06 (docs refresh should cite this plan's integer-N>1 wiring + the DistributorView infeasibility-without-certificate finding)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Fresh build_master_integer per best response inside run_nash!'s own sweep loop, mirroring the continuous path's existing 'fresh oracle/follower/master per best-response, by construction' discipline — never persisted across best responses or sweeps"
    - "Exact-equality Dict{Vector{Int},Int} cycle bookkeeping over a FIXED canonical distributor order (1:shared.N, independent of sweep_order) — mirrors master_integer.jl's own visited::Dict{Vector{Int},...} anti-stall pattern, generalized one level up to the Nash diagonalization"
    - "A confirmed-but-uncertified MOI.INFEASIBLE (termination_status says INFEASIBLE, dual_status has no Farkas ray) is a DISTINCT, additive branch from both the genuine-certificate-infeasible and the generic-solver-failure branches — the caller that only needs .feasible (a ternary search) is unaffected; the caller that needs a real cut still fails loudly downstream (add_feasibility_cut!'s own finiteness guard)"

key-files:
  created:
    - test/test_planning_nash_integer.jl
  modified:
    - src/planning/nash.jl
    - src/planning/coupling.jl

key-decisions:
  - "Reused the corner-cap control fixture (x_inv_max=[0.3,0.3]) from test_planning_nash.jl verbatim rather than inventing a new one, per the plan's own interface note — the known continuous equilibrium (z=[0.6,0.6], x_inv=[0.3,0.3]) is a documented reference point for where the K=4 lattice equilibrium (z=[0.5,0.5], the nearest lattice point at/below 0.6) is expected to land."
  - "Combined Task 1's own Test 1 (wiring smoke test) and Task 2's Test 1 (N=2 convergence) into ONE testitem, and Task 2's own Test 2 (brute-force certification) into the SAME testitem — avoids a second ~60-70s run_nash! solve purely to re-derive the same equilibrium, while still covering every <behavior> point in both tasks."
  - "Asserted result.converged directly (no try/catch) rather than the 'either outcome acceptable' hedge the plan's <behavior> describes — empirically confirmed via two independent scratchpad runs that this fixture converges RELIABLY in 2 sweeps once the Rule-1 coupling.jl fix (below) is applied; asserting convergence directly is the honest claim this project's own 'fail loud, no try/catch around run_nash!' convention (T-13-10) already establishes for every OTHER Nash testitem in this phase."
  - "Downgraded Task 2's own Test 3 (end-to-end cycling demonstration) to the standalone dictionary-logic replication (Task 1's own Test 3), per the plan's own explicit allowance — constructing a genuinely cycling integer diagonalization deterministically on this toy N=2/K=4 fixture would require a purpose-built oscillating fixture, disproportionate effort relative to this item's own marginal value once the detection MECHANISM itself (exact Vector{Int} dictionary equality) is independently verified."
  - "NO_DEVIATION_TOL = 1e-6 for the brute-force certification's 'no strictly lower cost' comparison — measured diff was 2.22e-16 (machine epsilon) on this fixture for both distributors; 1e-6 (this project's own standard tol order of magnitude) is a generous ceiling that stays robust to ordinary solver-to-solver noise without masking a genuine profitable deviation, which would be orders of magnitude larger than 1e-6 on this fixture's cost scale."

requirements-completed: ["BILEV-07"]

# Metrics
duration: 95min
completed: 2026-10-02
---

# Phase 31 Plan 04: run_nash! Integer N>1 Wiring + Exact-State Cycle Detection Summary

**`run_nash!` gains a new `integer` kwarg threading `build_master_integer` through the N-distributor Gauss-Seidel diagonalization (a fresh MILP master per best response, never persisted), plus exact-binary-state cycle detection; a Rule-1 bug in `solve_follower!(::DistributorView)` (a confirmed `MOI.INFEASIBLE` without a Farkas ray was previously treated as an unrecoverable solver failure) had to be fixed for the new wiring to run at all, since `corner_recourse`'s own ternary search routinely explores trial `z` values beyond what the OTHER-distributor-pinned shared capacity permits.**

## Performance

- **Duration:** ~95 min
- **Tasks:** 2 of 2 completed
- **Files modified:** 2 (`src/planning/nash.jl`, `src/planning/coupling.jl`); 1 created (`test/test_planning_nash_integer.jl`)

## Accomplishments

- `run_nash!` accepts a new `integer::Union{Nothing,NamedTuple} = nothing` kwarg
  (e.g. `integer = (; K = 4, α_x_lb = 0.0)`). When supplied, every distributor's best
  response inside the sweep loop builds a FRESH `build_master_integer` (`α_op_lb = :auto`
  via the same `bounds_ctx` machinery `build_master`/`solve_stackelberg!` already use,
  `α_x_lb` an explicit, unvalidated bound defaulting to `0.0` — the same accepted,
  documented skip the continuous path already uses for `DistributorView`'s pooled-capacity
  coupling) and passes it to `solve_stackelberg!` via its existing `master=` keyword
  (`master_kwargs = NamedTuple()`). The continuous (`integer === nothing`) path is
  byte-identical to every pre-Phase-31 call — confirmed via the full pre-existing
  `test_planning_nash.jl` suite (132 pass / 1 pre-existing broken / 0 fail) and
  `docs/literate/nash_diagonalization.jl`'s own end-to-end foreground run (exit 0).
- Exact-binary-state cycle detection: a `Dict{Vector{Int}, Int}` (declared fresh per
  `run_nash!` call, alongside `trace`/`certificates`) maps each visited JOINT binary
  investment state — the concatenation, in FIXED canonical distributor order `1:shared.N`
  (independent of `sweep_order`), of every distributor's own exact `b` recovered from
  `result_i.y` via the lattice step `y_max/2^K` — to the sweep it was first seen at. A
  revisited state that occurs WITHOUT the loop having already converged at that sweep
  raises a loud, NAMED `ErrorException` reporting the full cycle shape (first-seen sweep,
  current sweep, every distributor's own `b` at the repeat) — never silently continuing
  toward `max_sweeps`.
- **Rule 1 auto-fixed bug** (found empirically during this plan's own execution, see
  Deviations): `solve_follower!(::DistributorView, ...)` (`src/planning/coupling.jl`)
  raised a generic, unnamed `ErrorException` whenever HiGHS confirmed a genuine primal
  infeasibility (`MOI.INFEASIBLE`) via presolve WITHOUT ever computing a Farkas dual ray
  — a code path THIS plan's `corner_recourse` ternary search triggers routinely (it
  explores trial `z` values across the full `[0, y_inv]` MASTER lattice range, which
  regularly exceeds what the OTHER, currently-pinned distributor's shared capacity
  permits). Fixed by adding a third, additive branch returning
  `(; feasible = false, v = NaN, u = fill(NaN, T))` for this confirmed-but-uncertified
  case; transparent to `corner_recourse`'s own `Qfun` (reads only `.feasible`), while a
  caller that DOES need a real cut (`solve_stackelberg!`'s own outer feasibility-cut
  branch) still hits `add_feasibility_cut!`'s own pre-existing finiteness guard and fails
  loudly there instead.
- `test/test_planning_nash_integer.jl` (new): N=2, K=4 integer Nash converges in 2 sweeps
  (`z=[0.5,0.5]`, `x_inv=[0.25,0.25]`, `UB=[-0.225,-0.225]`, the nearest lattice point
  at/below the known continuous optimum `z=0.6`); per-player 16-point brute-force
  certification via the PRODUCTION `corner_recourse` (never a re-derived enumeration)
  confirms no profitable unilateral deviation (diff `2.22e-16`, machine epsilon, against a
  measured `1e-6` tolerance ceiling); `integer` kwarg boundary guards (`K` must be a
  positive `Integer`, `α_x_lb` must be finite); cycle-detection dictionary-logic standalone
  replication (exact `Vector{Int}` equality, never tolerance).

## Task Commits

1. **Task 1: `run_nash!` integer kwarg + fresh `build_master_integer` per best response +
   exact-state cycle detection** (includes the Rule-1 `coupling.jl` fix, load-bearing for
   this task to run at all) - `639ce99` (feat)
2. **Task 2: N=2 integer Nash fixture — convergence, per-player brute-force certification,
   cycling-detection regression** - `bd03ce2` (test)

**Plan metadata:** this commit (SUMMARY + STATE/ROADMAP update)

## Files Created/Modified

- `src/planning/nash.jl` — `run_nash!` gains the `integer` kwarg (docstring: new
  "`integer`" and "Cycle detection" paragraphs, a `Throws` entry for the cycle
  `ErrorException`), a boundary guard (`integer.K` positive `Integer`, `integer.α_x_lb`
  finite) before any solve call, a conditional `build_master_integer`/`solve_stackelberg!`
  branch inside the sweep loop (continuous branch unchanged), and the
  `visited_joint_b`/`integer_buffer`/cycle-check machinery around the existing
  `is_converged` check.
- `src/planning/coupling.jl` — `solve_follower!(::DistributorView, ...)` gains a third,
  additive branch (confirmed `MOI.INFEASIBLE` without a Farkas ray → `feasible = false`,
  `v = NaN`, `u = fill(NaN, T)`), plus an updated docstring documenting all three branches.
- `test/test_planning_nash_integer.jl` (new) — 3 `@testitem`s: (1) N=2 K=4 convergence +
  per-player brute-force certification (the load-bearing item); (2) `integer` kwarg
  boundary guards; (3) cycle-detection dictionary-logic standalone replication.

## Decisions Made

See `key-decisions` in frontmatter: fixture reuse, test consolidation (avoiding a second
~60-70s solve), asserting convergence directly rather than hedging with try/catch, the
Test-3 downgrade (with explicit scope note below), and the measured `1e-6`
no-profitable-deviation tolerance.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `solve_follower!(::DistributorView)` raised an unnamed, generic
`ErrorException` on a CONFIRMED `MOI.INFEASIBLE` trial lacking a Farkas dual ray**

- **Found during:** Task 1, first live execution of the new `integer` wiring
  (`scratchpad/probe_nash_integer.jl`) — `run_nash!(specs, shared; z0, integer = (; K=4),
  ...)` crashed with `solve_follower!(::DistributorView): neither a trusted solve nor a
  genuine infeasibility certificate for distributor i=1 — ... termination_status :
  INFEASIBLE ... dual_status : NO_SOLUTION`, at a ternary-search trial `z =
  0.6000001614226328` (a hair above this distributor's own true feasible boundary `0.6`).
- **Issue:** `solve_follower!(::DistributorView, ...)`'s own two-branch contract (feasible,
  or infeasible-with-certified-Farkas-ray) treated any OTHER outcome as an unrecoverable
  solver failure. But HiGHS's presolve can confirm genuine primal infeasibility
  (`MOI.INFEASIBLE`, never the unconfirmed `MOI.ALMOST_INFEASIBLE`) directly, without ever
  running the dual simplex that would produce a Farkas ray — a standard HiGHS/MOI behavior
  this plan's `corner_recourse` ternary search reaches routinely (it searches the FULL
  `[0, y_inv]` range the MASTER's own lattice permits, which is generally much larger than
  what the OTHER, currently-pinned distributor's shared capacity allows). Reproduced in
  isolation (`scratchpad/probe_followerview.jl` showed the SAME model solving cleanly with
  a proper Farkas ray at hand-picked `z` values — the bug is specific to the knife-edge
  trial points a ternary search naturally converges toward).
- **Fix:** added a third, additive branch to `solve_follower!(::DistributorView, ...)`:
  `termination_status(shared.model) == MOI.INFEASIBLE` (without a certificate) now returns
  `(; feasible = false, v = NaN, u = fill(NaN, shared.T))` instead of raising.
  `corner_recourse`'s own `Qfun` (both `_corner_recourse_ternary` and
  `_corner_recourse_joint`, `src/planning/benders.jl`) only reads `.feasible` (returns
  `+Inf`, identical treatment to a certificate-bearing infeasible trial) — zero change
  needed there. A caller that DOES need a genuine cut (`solve_stackelberg!`'s own outer
  feasibility-cut branch, `add_feasibility_cut!`) still hits that function's own
  pre-existing `isfinite` guard and fails loudly — never silently accepts a vacuous cut.
- **Files modified:** `src/planning/coupling.jl`.
- **Verification:** re-ran the exact failing scenario (`probe_nash_integer.jl`) after the
  fix — converges cleanly in 2 sweeps (67s); re-ran the full `test_planning_coupling.jl`
  suite (13/13 pass, no regression to the existing feasible/infeasible-with-certificate
  branches); re-ran `test_planning_benders_integer.jl`/`test_planning_certification_integer.jl`
  (98/98 pass combined with `test_planning_oracle.jl`/`fixtures_planning.jl`) confirming the
  single-distributor integer path (which never reaches `DistributorView`) is unaffected.
- **Committed in:** `639ce99` (Task 1 commit, alongside the `nash.jl` wiring it unblocks).

### Scope note (downgrade, not a deviation from correctness)

**Task 2's own Test 3 (end-to-end cycling demonstration) downgraded to the standalone
dictionary-logic replication**, per the plan's own explicit allowance ("if no genuine cycle
is reachable within reasonable effort on this toy fixture, downgrade this ONE test to Task
1's own Test 3 standalone dictionary-logic replication... document this explicitly").
Constructing a fixture/seed combination that genuinely CYCLES the integer diagonalization
(a Gauss-Seidel best-response oscillation between two or more joint binary states) was not
attempted on this toy N=2/K=4 fixture — per 31-RESEARCH.md's own stated honesty about this
being hard to force deterministically, and disproportionate effort relative to this item's
marginal value once the detection MECHANISM itself (exact `Vector{Int}` dictionary
equality, mirroring `master_integer.jl`'s own `visited` pattern) is independently verified
in isolation (`test/test_planning_nash_integer.jl`'s third `@testitem`). The mechanism
itself is also exercised implicitly by every converged run in this file (the
`visited_joint_b` dictionary is populated and checked on every sweep; it simply never
triggers the error branch on a converging fixture) — not a dead code path.

---

**Total deviations:** 1 auto-fixed (Rule 1 — a genuine, previously-unreachable bug this
plan's own new code path exposed, load-bearing for Task 1 to run at all), 1 explicitly
documented scope downgrade (per the plan's own stated allowance, not a correctness gap).
**Impact on plan:** Both tasks completed as specified; BILEV-07 is fully implemented and
regression-tested; the `coupling.jl` fix was necessary, not optional — without it, NO
integer-Nash run on this fixture (or any fixture where a `DistributorView`'s own
capacity-reduced feasible range is smaller than the master's own lattice ceiling) could
ever complete.

## Issues Encountered

- **Runtime impact (measured, per 31-RESEARCH.md's own flag):** a single N=2, K=4 integer
  Nash run (2 sweeps, 4 best responses total) took ~67s wall time on this toy fixture —
  noticeably slower than the continuous fixture's own sub-second convergence
  (`test_planning_nash.jl`'s corner-cap control). Each best response is a genuine MILP
  solve (HiGHS branch-and-bound) PLUS a Laporte-Louveaux corner-recourse ternary search
  (itself several `solve_follower!`/`solve_planning_oracle!` re-solves per Benders
  iteration) — consistent with 31-RESEARCH.md's own single-distributor measurement
  (~4s/best-response) scaled up by the extra ternary-search solves the shared-transmission
  `DistributorView` follower's own capacity ceiling now triggers more often than the
  single-distributor `FollowerLP` fixture did.
- The quick-run emulator's `@testitem` filter/fixture-inclusion requirements meant one
  early verification run errored on `UndefVarError: PlanningFixtures not defined` purely
  from omitting `fixtures_planning.jl` from the file list for
  `test_planning_benders_integer.jl`'s first test item — not a code regression; resolved by
  including the correct fixture file.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `run_nash!`'s `integer` kwarg and the `coupling.jl` Rule-1 fix are both production-wired
  and regression-tested; BILEV-07 is complete.
- Plan 31-06 (BILEV-08, docs refresh) should cite this plan's integer-N>1 wiring in
  `docs/writeups/stackelberg_vs_psr_n1n2.typ`'s "Equilíbrio de Nash multi-distribuidor"
  section (per 31-RESEARCH.md's own Docs Refresh Scope), and may want to mention the
  `DistributorView`-infeasibility-without-certificate finding as a worked example of why
  the integer corner search needs its own careful infeasibility handling.
- No blockers for plan 31-05/31-06.

---
*Phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh*
*Completed: 2026-10-02*

## Self-Check: PASSED

- FOUND: src/planning/nash.jl
- FOUND: src/planning/coupling.jl
- FOUND: test/test_planning_nash_integer.jl
- FOUND commit: 639ce99
- FOUND commit: bd03ce2
