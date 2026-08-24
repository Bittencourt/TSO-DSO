---
phase: 24-discrete-integer-investment-expansion
plan: 03
subsystem: planning
tags: [benders, laporte-louveaux, integer-cuts, no-good-cuts, milp, trace]

# Dependency graph
requires:
  - phase: 24-discrete-integer-investment-expansion
    plan: 02
    provides: "BendersMasterInteger with add_optimality_cut!/add_feasibility_cut!
      methods already coexisting; master.b (raw binaries) and master.L (pinned
      recourse lower bound) exposed on the struct"
provides:
  - "add_ll_cut!/add_nogood_cut!/apply_integer_cuts! in src/planning/master_integer.jl
    — the Laporte-Louveaux 'no-good cut with a value' written over the RAW binary
    vector master.b, a classical no-good fallback (D-16), and a dispatched entry
    point that is a true no-op for BendersMaster and real logic for
    BendersMasterInteger"
  - "BendersTrace.nogood_count_trace — additive per-iteration no-good-firing count,
    surfaced via trace_summary's new total_nogoods field"
affects: [24-04-benders-loop-integration, 24-05-certification, 24-06-literate-docs]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Integer-cut algebra written directly over the raw JuMP binary VariableRefs
      (master.b), never over a derived AffExpr (y_inv) — the single load-bearing
      correctness constraint of this plan (RESEARCH.md Pitfall 1)."
    - "Dispatched no-op vs real-logic pair on the SAME generic function
      (apply_integer_cuts!) distinguished purely by the master's concrete struct
      type, with the no-op method touching zero fields of its second argument so a
      future accidental field access on the continuous path is a compile-time
      MethodError, never a silent behavior change."
    - "Additive trace column with a default kwarg (nogood_count::Integer = 0),
      mirroring the project's established attempts_out/oracle_status precedent for
      non-breaking BendersTrace extension."

key-files:
  created:
    - test/test_planning_trace.jl
  modified:
    - src/planning/master_integer.jl
    - src/planning/trace.jl
    - test/test_planning_master_integer.jl

key-decisions:
  - "add_ll_cut!/add_nogood_cut! carry their own ArgumentError guards (length
    match against master.K, finiteness of b_trial/Q_nu/L) mirroring
    add_optimality_cut!/add_feasibility_cut!'s WR-03 discipline, even though the
    plan's <behavior> block did not spell them out explicitly — a malformed trial
    must fail loudly before corrupting the build-once master's persistent
    constraint set, consistent with every other cut-adding function in this file."
  - "The exhaustive K=4 16x16-corner test does BOTH the plan-specified closed-form
    arithmetic check AND a genuine JuMP-level re-solve (fix b to the incumbent,
    re-optimize, assert alpha_op+alpha_x == Q_nu exactly) — the closed-form check
    alone proves the algebra is correct on paper; the JuMP-level check proves the
    ACTUAL @constraint call in add_ll_cut! is load-bearing in the solver, not just
    correct in isolation."
  - "nogood_count_trace is positioned immediately after retry_count_trace, before
    solve_time_trace, in both the struct field list and the constructor argument
    list — matching the plan's stated placement and its own field-by-field
    docstring convention."
  - "Created test/test_planning_trace.jl as a genuinely new file (no dedicated
    BendersTrace unit-test file existed before this plan — verified via
    grep -rn 'BendersTrace(' test/*.jl returning zero direct constructions; the
    struct was previously only exercised indirectly through solve_stackelberg!'s
    returned result.trace in test_planning_benders.jl)."

requirements-completed: [INT-02]

# Metrics
duration: ~11min
completed: 2026-08-23
---

# Phase 24 Plan 03: Laporte-Louveaux Integer Cut + No-Good Fallback + Trace Column Summary

**Implemented the genuinely new mathematics of Phase 24 — the Laporte-Louveaux "no-good
cut with a value" written strictly over the raw binary vector `b` (never the derived
`y_inv`), a classical no-good anti-stall fallback, and a dispatched
`apply_integer_cuts!` entry point — proven correct by an exhaustive 256-pair (16
incumbents x 16 corners) closed-form-plus-JuMP-solve tightness/slackness test, plus an
additive `BendersTrace` column that counts no-good firings without touching any
existing call site's behavior.**

## Performance

- **Duration:** ~11 min wall clock (base commit `a6005e6` at 19:08:45 -> Task 2 commit
  `0cb7da9` at 19:19:11, America/Sao_Paulo)
- **Completed:** 2026-08-23T22:19:11Z
- **Tasks:** 2 completed
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments

- `src/planning/master_integer.jl` gains `add_ll_cut!`, `add_nogood_cut!`, and two
  `apply_integer_cuts!` methods. `add_ll_cut!` appends the exact Laporte & Louveaux
  (1993) / Birge & Louveaux (2011 Sec 5.2) cut
  `θ >= (Q_nu - L)*D(b) + L` where `D(b) = Σ_{i∈S} b[i] - Σ_{i∉S} b[i] - |S| + 1`,
  written over `master.b` — never `master.y_inv` (the phase's single most important
  correctness constraint, RESEARCH.md Pitfall 1). `add_nogood_cut!` appends the
  classical un-weighted no-good cut forbidding exact re-visitation of a trial corner
  (D-16's fallback). `apply_integer_cuts!(::BendersMaster, lb_res, Q_nu)` is a TRUE
  no-op (zero field access on `lb_res`, always returns `(; nogood_fired = false)`);
  `apply_integer_cuts!(master::BendersMasterInteger, lb_res, Q_nu)` ALWAYS fires the LL
  cut (Finding 2: continuous + LL cuts coexist, never either/or), tracks visited
  corners in `master.visited`, and fires the no-good fallback ONLY on a detected
  exact-repeat stall.
- **Exhaustive 16x16-corner proof, actually executed, not sampled.** For every one of
  the `2^4 = 16` possible incumbents `b^ν`, a fresh `BendersMasterInteger` is built, one
  LL cut is added, and the cut's own RHS formula is evaluated in closed form against
  every one of the 15 OTHER corners (256 pairs total): tight (`isapprox(rhs, Q_nu)`) at
  the incumbent, and `<= L + 1e-9` (implied by the master's own `θ >= L` bound, adding
  zero new information) at every other corner. Additionally, for each incumbent, `b` is
  fixed to `b^ν` in the ACTUAL JuMP model and re-optimized, confirming
  `α_op + α_x == Q_nu` exactly — proving the `@constraint` call itself is load-bearing
  in the solver, not merely correct on paper. **This proof passed on first execution —
  no adjustment to the cut algebra or the bound `L` was needed.**
- A separate no-good test proves `add_nogood_cut!` makes the model `MOI.INFEASIBLE`
  when `b` is fixed to the banned corner, while `MOI.OPTIMAL` at every other tested
  corner.
- `src/planning/trace.jl` gains an additive `nogood_count_trace::Vector{Int}` field
  (positioned after `retry_count_trace`, before `solve_time_trace`), a new
  `push!` keyword `nogood_count::Integer = 0` (default preserves every existing
  `benders.jl` call site's behavior byte-for-byte — verified by re-running
  `solve_stackelberg!` end-to-end and confirming all `nogood_count_trace` entries are
  `0`), and `trace_summary`'s new `total_nogoods = sum(trace.nogood_count_trace)` field
  (including the empty-trace `0` sentinel branch).
- New `test/test_planning_trace.jl` — the first standalone `BendersTrace`
  `push!`/`trace_summary` unit-test file in the project (none existed before this
  plan): covers the omitted-keyword byte-identical case, the explicit
  `nogood_count = 2` case, the negative-value guard, and the empty-trace sentinel.

## Task Commits

Each task was committed atomically:

1. **Task 1: add_ll_cut!/add_nogood_cut!/apply_integer_cuts! dispatch** - `bed838d`
   (feat)
2. **Task 2: BendersTrace additive no-good count column** - `0cb7da9` (test)

_No plan-metadata commit — STATE.md/ROADMAP.md/REQUIREMENTS.md updates are owned by
the orchestrator per this plan's execution constraints; SUMMARY.md is created but not
committed here for the same reason._

## Files Created/Modified

- `src/planning/master_integer.jl` — appended `add_ll_cut!`, `add_nogood_cut!`, and
  the two `apply_integer_cuts!` methods after the existing
  `add_optimality_cut!`/`add_feasibility_cut!` methods (struct → builder → solve →
  continuous cuts → integer cuts section order). Export line extended to include
  `add_ll_cut!, add_nogood_cut!, apply_integer_cuts!`.
- `test/test_planning_master_integer.jl` — two new `@testitem`s: the exhaustive
  16x16-corner LL cut tightness/slackness proof (closed-form + genuine JuMP re-solve),
  and the no-good re-visitation test.
- `src/planning/trace.jl` — `nogood_count_trace` field, constructor initialization,
  `push!`'s new `nogood_count::Integer = 0` keyword + `>= 0` guard, and
  `trace_summary`'s `total_nogoods` field (both the populated and empty-trace
  branches).
- `test/test_planning_trace.jl` (new) — four `@testitem`s covering the additive
  column's byte-identical-omission behavior, explicit-value recording, the negative
  guard, and the empty-trace sentinel.

## Decisions Made

- **Guards added to `add_ll_cut!`/`add_nogood_cut!` beyond the plan's literal
  `<behavior>` text.** The plan's behavior spec did not explicitly enumerate
  `ArgumentError` guards for these two functions, but every other cut-adding function
  in this file (`add_optimality_cut!`, `add_feasibility_cut!`) carries WR-03
  finiteness/length guards before mutating the persistent constraint set. Added the
  same discipline here (length match against `master.K`, finiteness of
  `b_trial`/`Q_nu`/`L`) — Rule 2 (missing critical functionality consistent with an
  established, documented project pattern), not scope creep.
- **The exhaustive test does a genuine JuMP-level re-solve in addition to the
  plan-specified closed-form check.** The plan's own `<verify>` automated script for
  Task 1 is a pure closed-form arithmetic check (no JuMP solve), and the unit test
  mirrors that. On top of it, the test also fixes `b` to each incumbent in the actual
  built model and re-optimizes, asserting `α_op + α_x == Q_nu` exactly — this
  reinforcement directly answers the plan's own instruction to treat this as "the
  single most important correctness constraint in the phase" and "actually execute
  it," going one level deeper than closed-form arithmetic to prove the `@constraint`
  call itself is correct in the solver, not merely on paper.
- **`nogood_count_trace` placed immediately after `retry_count_trace`.** The plan
  offered "after `retry_count_trace`, before `solve_time_trace`, or at the end — pick
  one consistent position." Chose the former to keep the "retry accounting" and
  "no-good accounting" columns adjacent in both the struct field list and the
  constructor's positional argument list.

## Deviations from Plan

None — plan executed exactly as written. No auto-fixes were needed; the exhaustive
16x16-corner proof passed on first execution with the cut algebra and `L` bound
exactly as specified in `24-RESEARCH.md`/`24-CONTEXT.md`'s `<interfaces>` block, so no
adjustment to either was ever required or considered.

## Known Stubs

None. Both `add_ll_cut!`/`add_nogood_cut!`/`apply_integer_cuts!` and the
`BendersTrace` column are fully wired and exercised by executed tests; nothing here is
a placeholder. `apply_integer_cuts!` is NOT yet called from `solve_stackelberg!` —
that wiring is explicitly out of scope for this plan (plan 24-04's job, per this
plan's own `<objective>` and the orchestrator's `<plan_specific_requirements>`), not a
stub left behind by this plan.

## Threat Flags

None. All three STRIDE threats identified in this plan's own `<threat_model>`
(T-24-07, T-24-08, T-24-09) are mitigated exactly as designed and verified by this
plan's own tests — no new, unaccounted-for surface was introduced.

## Issues Encountered

None. `julia --project=. -e 'using TSODSO'` loads cleanly after each task; the
plan-specified `<verify>` scripts, the exhaustive unit tests (verified via standalone
`Test`-free scripts per this phase's documented TestItemRunner-under-`--project=.`
trap), a full end-to-end `solve_stackelberg!` re-run (confirming the continuous path
is byte-identical, `nogood_count_trace` all zeros, `total_nogoods = 0`), and the
complete PVAL-04 guard logic (confirming the new exported symbols `add_ll_cut!`/
`add_nogood_cut!`/`apply_integer_cuts!` do not match the guard's `build_\w+`
source-scan pattern and do not perturb `found == Set(keys(registry))`) all passed.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

`add_ll_cut!`, `add_nogood_cut!`, and the dispatched `apply_integer_cuts!` are fully
implemented, exported, and proven correct in isolation (exhaustive 16x16-corner
tightness/slackness, no-good re-visitation). `BendersTrace` now carries the additive
`nogood_count_trace`/`total_nogoods` bookkeeping D-16 requires, with zero impact on
any existing call site. Plan 24-04 can now:

1. Add the `master = nothing` injection kwarg to `solve_stackelberg!` (D-08, mirroring
   the existing `follower = nothing` seam).
2. Call `apply_integer_cuts!(master, lb_res, Q_nu)` from inside the loop's
   optimality-cut branch, with `Q_nu = follower_res.cost - oracle_res.cost` (the
   interfaces block's own formula, no new derivation needed).
3. Thread the returned `(; nogood_fired)` into `push!(trace, ...; nogood_count = ...)`
   and implement the `:nogood_assisted` convergence attribution downgrade.
4. Implement the D-13/D-14 lattice-gap-exact / enumeration-backed termination
   criterion (explicitly NOT this plan's scope).

No blockers.

---
*Phase: 24-discrete-integer-investment-expansion*
*Completed: 2026-08-23*

## Self-Check: PASSED

All 4 created/modified files confirmed present on disk; both task commit hashes
(`bed838d`, `0cb7da9`) confirmed present in `git log --oneline`.
