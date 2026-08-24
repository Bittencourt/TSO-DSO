---
phase: 24-discrete-integer-investment-expansion
plan: 04
subsystem: planning
tags: [benders, stackelberg, integer-master-injection, termination-criterion, laporte-louveaux, wiring]

# Dependency graph
requires:
  - phase: 24-discrete-integer-investment-expansion
    plan: 03
    provides: "add_ll_cut!/add_nogood_cut!/apply_integer_cuts! in
      src/planning/master_integer.jl, plus BendersTrace.nogood_count_trace"
provides:
  - "solve_stackelberg!'s master = nothing / known_optimum injection kwargs
    (D-08, D-13/D-14) — the seam every downstream integer-master call site
    reaches through"
  - "converged_now — the mutually-exclusive termination gate (never an || of
    gap<=tol and the exact-match test), the load-bearing fix for the
    plan-checker's Blocker 2"
  - "apply_integer_cuts! wired into the optimality branch; nogood_count/
    converged_via surfaced on the returned NamedTuple (D-16)"
affects: [24-05-certification, 24-06-literate-docs]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Mutually-exclusive termination branch (`known_optimum === nothing ? (gap
      <= tol) : isapprox(UB, known_optimum; atol = KNOWN_OPTIMUM_ATOL)`),
      never an `||` of the two criteria — the load-bearing anti-certificate-
      laundering pattern this plan exists to enforce."
    - "A NEW, dedicated module-level const (KNOWN_OPTIMUM_ATOL) set from an
      empirical measurement of the solvers' own achieved duality gap
      (`abs(objective_value - dual_objective_value)`), never a guessed
      literal and never reusing the `tol` kwarg's value."
    - "NamedTuple field append-only extension (`nogood_count`, `converged_via`
      appended strictly AFTER all pre-existing fields) — preserves every
      prior caller's name-based destructuring untouched."

key-files:
  created:
    - test/test_planning_benders_integer.jl
  modified:
    - src/planning/benders.jl

key-decisions:
  - "Split the single conceptual code change across two atomic commits by
    reconstructing a Task-1-only intermediate state (kwargs/guards/
    KNOWN_OPTIMUM_ATOL/converged_now, WITHOUT apply_integer_cuts!/
    nogood_count/converged_via), verifying it independently, committing, then
    re-applying the apply_integer_cuts!/nogood_count/converged_via wiring as
    a second commit. This matches the plan's own Task 1/Task 2 boundary
    ('This task does NOT yet wire apply_integer_cuts!... that is Task 2,
    kept separate so this task's own regression is easy to verify in
    isolation') even though the two tasks' edits landed in adjacent/
    overlapping regions of the same file."
  - "KNOWN_OPTIMUM_ATOL was measured, not assumed, and the measured value
    (gap_oracle=3.957388639008741e-9) was NOT comfortably below the 1e-10
    margin the measurement protocol calls for — so the constant is set to
    the full formula result (3.957388639008741e-8), not the fallback
    1e-9. This is the plan's own explicit anti-pattern warning (quick task
    260823-gea) being avoided in practice, not just cited: had the gap been
    smaller, 1e-9 would have been kept and documented as such instead."
  - "The Algorithm/Returns/Throws docstring sections were extended beyond the
    plan's literal minimum requirement (which only mandated updating the
    'BUILD ONCE' paragraph) to also document apply_integer_cuts!,
    converged_now, and the two new return fields in their natural narrative
    locations — Rule 2 (missing critical functionality: an accurate
    docstring for a public, exported function's new behavior is not
    optional), consistent with this file's own existing exhaustive
    docstring discipline."

requirements-completed: [INT-02]

# Metrics
duration: ~35min
completed: 2026-08-23
---

# Phase 24 Plan 04: Wire the Integer Master into solve_stackelberg! Summary

**Added the `master = nothing` / `known_optimum` injection seam to `solve_stackelberg!`
(D-08), replaced the termination check with a mutually-exclusive `converged_now` branch
that never `||`s the continuous loop's `tol` with the certified `known_optimum` exact-
match test (the plan-checker's Blocker 2, closed for good with a standalone adversarial
regression), and wired the generic `apply_integer_cuts!` dispatch into the optimality
branch so `nogood_count`/`converged_via` are surfaced on every returned result — the
phase's integer mechanism is now reachable end-to-end through the production entrypoint
for the first time.**

## Performance

- **Duration:** ~35 min wall clock (base commit `5210806` — Task 1 commit `11bf78b` —
  Task 2 commit `3c0d788`)
- **Completed:** 2026-08-23
- **Tasks:** 2 completed
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments

- `src/planning/benders.jl` gains `master = nothing` (mirroring the existing
  `follower = nothing` seam VERBATIM in structure: mutual-exclusion guard against
  `master_kwargs`, then `master = master === nothing ? build_master(...) : master` at the
  single construction point) and `known_optimum::Union{Nothing,Real} = nothing`
  (finiteness-guarded).
- A new module-level `const KNOWN_OPTIMUM_ATOL`, EMPIRICALLY MEASURED (not guessed) on
  the D-12 fixture at a representative interior trial `z = [1.0]`:
  `gap_oracle = 3.957388639008741e-9` (Clarabel SOCP), `gap_follower = 0.0` (HiGHS LP
  exact simplex). Since `max(gap_oracle, gap_follower)` was NOT comfortably below the
  `1e-10` margin the measurement protocol calls for, the constant was set to the full
  formula result `max(1e-9, 10 * 3.957388639008741e-9) = 3.957388639008741e-8`, not the
  `1e-9` fallback — documented in a code comment recording the exact measured values and
  date.
- **`converged_now` is a mutually exclusive branch** (the load-bearing fix for the
  plan-checker's Blocker 2):
  `converged_now = known_optimum === nothing ? (gap <= tol) : isapprox(UB, known_optimum; atol = KNOWN_OPTIMUM_ATOL)`
  — NEVER an `||` of the two criteria. Proven at the unit level by a standalone
  reimplementation of the formula in the new test file's adversarial case: `gap <= tol`
  holds (`gap=0.0`) but `known_optimum=999.0` is nowhere near `UB=5.0` → `converged_now`
  must be (and is) `false`. A forbidden `(gap <= tol) || isapprox(...)` would have wrongly
  returned `true` here.
- `apply_integer_cuts!(master, lb_res, Q_nu)` (plan 24-03's dispatched entry point) is
  now called on every optimality-branch iteration, immediately after the existing
  `:op`/`:x` cut appends, with `Q_nu = follower_res.cost - oracle_res.cost`. A running
  `nogood_total` accumulator is threaded into the existing trace `push!` call
  (`nogood_count = 0` or `1` per iteration) and into the returned NamedTuple as
  `nogood_count = nogood_total` and `converged_via = nogood_total > 0 ? :nogood_assisted : :clean`
  — both appended AFTER every pre-existing field so no prior caller's name-based
  destructuring is affected.
- The `benders.jl:62`-area docstring invariant ("no `build_*`/`Model(` call appears
  anywhere inside the loop") is UPDATED to describe the new injection seam rather than
  left silently false: "no `build_*`/`Model(` call appears anywhere inside this function
  OTHER THAN these two conditional builder calls, BOTH of which are skippable via
  injection and BOTH of which still execute strictly BEFORE the loop."
- New `test/test_planning_benders_integer.jl` — two `@testitem`s:
  1. Proves `master=nothing, known_optimum=nothing` supplied EXPLICITLY is
     byte-identical to the existing PVAL-02 N=1 golden (`y≈0.7`, `UB≈-0.245`), asserts
     `nogood_count == 0`/`converged_via === :clean` on the continuous path, and runs the
     `converged_now` mutual-exclusivity regression (three cases, including the literal
     adversarial "forbidden `||`" case).
  2. An end-to-end smoke test: `build_master_integer` (`K=4`) through `solve_stackelberg!`
     — actually converged on this run, with `y=1.0` (a genuine lattice point,
     `8.0/16 * 2`), `nogood_count=1`, `converged_via=:nogood_assisted`, proving the
     wiring runs without a `MethodError`/`UndefVarError` and that the no-good fallback
     genuinely fires and is genuinely attributed on a real run (not just theoretically
     reachable).

## Task Commits

Each task was committed atomically. The plan's own Task 1/Task 2 boundary
("this task does NOT yet wire `apply_integer_cuts!`... kept separate so this task's own
regression is easy to verify in isolation") was preserved via a reconstructed
intermediate state (see Decisions Made below):

1. **Task 1: master=nothing/known_optimum injection + docstring update + guard +
   converged_now** - `11bf78b` (feat)
2. **Task 2: apply_integer_cuts! wiring + nogood_count/converged_via return + end-to-end
   smoke** - `3c0d788` (feat)

## Files Created/Modified

- `src/planning/benders.jl` — `master = nothing`/`known_optimum` kwargs, their guards,
  the `KNOWN_OPTIMUM_ATOL` const, the updated construction line, the `converged_now`
  mutually-exclusive termination branch, the `apply_integer_cuts!`/`Q_nu`/`nogood_total`
  wiring, the extended `push!(trace, ...)` call, the extended return NamedTuple, and the
  updated docstring (signature block, "BUILD ONCE" paragraph, Algorithm step 3/4,
  Returns, Throws).
- `test/test_planning_benders_integer.jl` (new) — two `@testitem`s described above.

## Decisions Made

- **Reconstructed a Task-1-only intermediate file state to produce two genuinely atomic
  commits**, even though the plan's own edits to `benders.jl` land in
  adjacent/overlapping regions (the docstring's Algorithm step 3 paragraph and the
  optimality-branch code block both needed additions from BOTH tasks). Rather than
  landing one combined commit, the Task-2-specific docstring prose and code
  (`apply_integer_cuts!`/`Q_nu`/`nogood_total`/the two new return fields) were
  temporarily reverted, the Task-1-only state was independently verified (confirmed
  `nogood_count`/`converged_via` genuinely absent from the returned NamedTuple at that
  point, via `!haskey(pairs(result), :nogood_count)`), committed, then the Task-2 pieces
  were reapplied and independently re-verified before the second commit. This is more
  rigorous than the plan's own literal text strictly required but directly honors its
  stated intent ("kept separate so this task's own regression is easy to verify in
  isolation before the more invasive change lands").
- **`KNOWN_OPTIMUM_ATOL` was measured, and the measurement forced the harder branch of
  the plan's own conditional instruction.** The plan's Task 1 item 6 says: "if the
  measured gaps are comfortably below `1e-10`..., keep `KNOWN_OPTIMUM_ATOL = 1e-9`...;
  if not, the constant must reflect the measured precision." The measured
  `gap_oracle = 3.957388639008741e-9` is roughly 40x ABOVE `1e-10`, so the constant is
  `3.957388639008741e-8` (the full `max(1e-9, 10*gap)` formula), not `1e-9`. This is the
  concrete instance of the failure mode the orchestrator's brief warned about (quick task
  `260823-gea`) being actively avoided, not merely cited.
- **Docstring sections beyond the plan's literal minimum were also updated** (Algorithm
  step 3/4, Returns, Throws — the plan's Task 1 item 5 only mandated the "BUILD ONCE"
  paragraph) to keep the function's exhaustive existing docstring discipline internally
  consistent after the code changes — Rule 2 (an inaccurate docstring on a public,
  heavily-documented function is a correctness/documentation gap, not an optional
  polish item), consistent with this file's own pre-existing convention of documenting
  every algorithmic branch in prose.

## Deviations from Plan

None beyond the two decisions recorded above (the atomic-commit reconstruction and the
`KNOWN_OPTIMUM_ATOL` measurement landing on the harder branch) — both are executions of
the plan's own explicit instructions, not departures from them. The termination gate is
exactly the required form (`known_optimum === nothing ? (gap <= tol) :
isapprox(UB, known_optimum; atol = KNOWN_OPTIMUM_ATOL)`), with no `||` anywhere near it,
verified both by the standalone regression test and by re-running the existing PVAL-02
N=1/N=2 goldens end-to-end (unaffected).

## Known Stubs

None. `apply_integer_cuts!` genuinely fires on every optimality-branch iteration for
both master types (verified: the end-to-end integer smoke test's own run actually needed
and fired a no-good cut, `nogood_count=1`, `converged_via=:nogood_assisted` — not a
theoretical code path that happens to never execute). `known_optimum`'s exact-match
branch is implemented and unit-tested but not yet exercised by a real
`solve_stackelberg!` call with a non-`nothing` `known_optimum` in THIS plan — that is
explicitly plan 24-05's job (the enumeration-backed certification harness), not a stub
left behind here; the seam and its mutual-exclusivity are fully proven at the unit level
per this plan's own scope.

## Threat Flags

None. Both STRIDE threats this plan's own `<threat_model>` names (T-24-10, T-24-11) are
mitigated exactly as designed: the `master`/`master_kwargs` guard mirrors the reviewed
`follower`/`follower_kwargs` guard verbatim, and `KNOWN_OPTIMUM_ATOL`/`converged_now` are
both greppable, distinctly-named, and proven mutually exclusive by the new adversarial
unit test. T-24-12 (DoS via no natural convergence without `known_optimum`) is
`accept`-dispositioned per the threat model and unchanged — `max_iter` exhaustion still
raises the same loud `ErrorException` as before (verified: the end-to-end integer smoke
test's own `try`/`catch` branch explicitly tolerates and asserts on this outcome).

## Issues Encountered

None. `julia --project=. -e 'using TSODSO'` loads cleanly after each commit. Both
plan-specified `<automated>` verify scripts (Task 1's default-path + mutual-exclusivity
check, Task 2's integer end-to-end smoke) pass, run as raw `julia --project=.` scripts
per this phase's documented TestItemRunner-under-`--project=.` sibling-worktree trap
(MEMORY.md), not via `TestItemRunner`. Additionally re-ran, end-to-end, as regression
checks: the existing PVAL-02 N=1 golden (omitted-kwargs call site, unaffected), the
existing PVAL-02 N=2 Nash golden (`run_nash!` → `solve_stackelberg!` internally, using
`follower=`/`master_kwargs=` but never the new `master=`/`known_optimum=` kwargs —
confirmed unaffected), and the PVAL-04 source-scan tripwire's registry-set assertion
(confirmed `{build_follower, build_master, build_master_integer,
build_planning_oracle, build_shared_transmission}` still matches exactly — no new
`build_*` function was introduced by this plan).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

`solve_stackelberg!` now accepts a pre-built `BendersMasterInteger` via the `master =`
kwarg and reaches the full integer-cut machinery (Laporte-Louveaux + no-good fallback,
plan 24-03) on every run, with `nogood_count`/`converged_via` genuinely surfaced (not
theoretical). The `known_optimum` termination seam is implemented, guarded, and unit-
proven mutually exclusive against `gap <= tol`, ready for plan 24-05 to populate it from
an actual exhaustive-enumeration oracle on the D-12 fixture. Plan 24-05 can now:

1. Enumerate all `2^4 = 16` lattice points on the D-12 fixture, solving the follower at
   each to find the true integer optimum (D-10's primary certificate).
2. Call `solve_stackelberg!(...; master = imaster, known_optimum = <enumerated optimum>)`
   and confirm it converges via the exact-match branch, never via `gap <= tol`
   coincidentally landing first.
3. Add the per-cut validity assertion and continuous-baseline diff (D-15's two selected
   certificates).

No blockers.

---
*Phase: 24-discrete-integer-investment-expansion*
*Completed: 2026-08-23*

## Self-Check: PASSED

Both created/modified files confirmed present on disk (`src/planning/benders.jl`,
`test/test_planning_benders_integer.jl`); both task commit hashes (`11bf78b`, `3c0d788`)
confirmed present in `git log --oneline`.
