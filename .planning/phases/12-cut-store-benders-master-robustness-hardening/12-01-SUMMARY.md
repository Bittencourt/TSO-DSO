---
phase: 12-cut-store-benders-master-robustness-hardening
plan: 01
subsystem: infra
tags: [julia, jump, benders, stackelberg, highs, testitems, convergence-diagnostics]

# Dependency graph
requires:
  - phase: 11-single-distributor-stackelberg-benders-certified
    provides: solve_stackelberg! outer Benders loop, BendersMaster persistent cut store,
      FollowerLP genuine Farkas certificates, solve_with_retry! escalation ladder
provides:
  - BendersTrace convergence ledger (src/planning/trace.jl) — purpose-built, JuMP-free,
    structurally distinct from AdmmResiduals
  - Genuine per-iteration retry_count sourced from solve_with_retry!'s new attempts_out
    keyword (never a log-scrape estimate)
  - master_status_trace/oracle_status_trace per-row termination statuses
  - IN-01/IN-02/IN-03/IN-06 closed (Phase 11 final review info-level findings)
  - Three degenerate feasibility-cut edge-case regressions (near-boundary z, near-zero
    deliverable capacity, repeated/duplicate Farkas cuts) proving cut-store validity and
    LB monotonicity
affects: [13-nash-diagonalization-multi-distributor]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "attempts_out::Union{Nothing,Ref{Int}} additive-keyword idiom for threading a
       genuine per-call metric out of a wrapper function without changing its return
       type or breaking any existing call site"
    - "Mirror-but-differ struct pattern: BendersTrace copies AdmmResiduals's shape
       (parallel Vector fields, sequential-k push! guard, JuMP-free) while being
       structurally incapable of the ADMM-specific primal/dual-residual-pair semantics"

key-files:
  created:
    - src/planning/trace.jl
    - test/test_planning_hardening.jl
  modified:
    - src/planning/benders.jl
    - src/planning/retry.jl
    - src/planning/master.jl
    - src/planning/subproblem.jl
    - src/planning/follower.jl
    - src/TSODSO.jl
    - test/test_planning_benders.jl
    - test/test_planning_retry.jl

key-decisions:
  - "BendersTrace uses ten parallel Vector fields (iter/LB/UB/gap/cut_type/n_cuts/
     master_status/oracle_status/retry_count/solve_time), mirroring AdmmResiduals's
     layout but with a single relative-gap scalar instead of a primal/dual residual pair"
  - "oracle_status_trace defaults to :not_solved on the feasibility branch; the follower
     intentionally has NO third per-row status column since it is never
     solve_with_retry!-wrapped (plan 11-01 contract) — documented in trace.jl's header"
  - "Duplicate Farkas cuts are TOLERATED, not deduped (Claude's Discretion per
     12-CONTEXT.md) — verified by a dedicated test that the cut store stays valid"
  - "Near-boundary feasibility-cut test offset changed from the plan's stated 1e-9 to an
     empirically measured 1e-6 — HiGHS's own default feasibility tolerance accepted a
     1e-9 boundary violation as still feasible on this fixture"

patterns-established:
  - "Convergence-ledger structs for future outer loops (Phase 13's Nash diagonalization)
     should mirror BendersTrace's shape: JuMP-free, sequential-push! guarded, with an
     explicit header comment stating what is deliberately NOT copied from a sibling
     ledger and why"

requirements-completed: [PLAN-05, PLAN-06]

# Metrics
duration: 41min
completed: 2026-07-22
---

# Phase 12 Plan 01: Cut-Store & Benders Master Robustness Hardening Summary

**BendersTrace convergence ledger with a genuine per-iteration retry count (via a new `solve_with_retry!` `attempts_out` keyword) and both retry-gated subproblems' statuses, wired into `solve_stackelberg!`; closes IN-01/IN-02/IN-03/IN-06 from Phase 11's review; three degenerate feasibility-cut edge cases proven not to corrupt the persistent cut store.**

## Performance

- **Duration:** 41 min
- **Started:** 2026-07-22T21:39:32-03:00 (base commit)
- **Completed:** 2026-07-22T22:20:50-03:00
- **Tasks:** 2
- **Files modified:** 9 (2 created, 7 modified)

## Accomplishments

- New `src/planning/trace.jl`: `BendersTrace` mutable struct (ten parallel per-iteration
  vectors), zero-arg constructor, `push!` (sequential-`k` guarded, `ArgumentError` on
  invalid `cut_type`/non-finite `LB`/negative `retry_count`/`n_cuts`), `is_converged`,
  `trace_summary` — JuMP-free, structurally distinct from `AdmmResiduals` (no
  `primal_trace`/`dual_trace`/`eps_pri`/`eps_dual` fields anywhere in the file).
- `solve_with_retry!` gains an additive `attempts_out::Union{Nothing,Ref{Int}} = nothing`
  keyword, forwarded unchanged through `solve_master!` and `solve_planning_oracle!`,
  reporting the attempt number (1-indexed) a solve succeeded on — every pre-existing
  call site is unaffected (keyword defaults to a no-op).
- `solve_stackelberg!` wires `BendersTrace` into both loop branches (one `push!` call
  site per branch), threads `retry_count`/`oracle_status` via `attempts_out` `Ref`s, adds
  IN-02 (`tol` finite/positive) and IN-03 (`max_iter <= 99_999`) boundary guards, and
  sources the max-iter exhaustion message from the trace's last-recorded row instead of a
  possibly-stale loop-local `gap` (IN-01).
- `solve_follower!`'s Farkas guard widened to require `v > 0`, not just finiteness
  (IN-06), preventing a degenerate non-positive certificate from producing a vacuous
  feasibility cut.
- Three new `test/test_planning_hardening.jl` edge-case regressions (near-boundary `z`,
  near-zero deliverable capacity, repeated/duplicate Farkas cuts + a 4-round
  LB-monotonicity episode) plus extended assertions in `test_planning_benders.jl` and
  `test_planning_retry.jl`.
- Full `Pkg.test()` suite green: 2124 passed / 0 failed / 0 errored / 2 documented-broken
  (pre-existing thesis-figure cross-checks, unaffected).

## Task Commits

1. **Task 1: BendersTrace ledger + wire into solve_stackelberg! + close IN-01/02/03/06** - `5f4c8e6` (feat)
2. **Task 2: BendersTrace assertions + degenerate feasibility-cut edge-case tests** - `0017e8b` (test)

_Note: Task 2's commit also includes a small docstring-accuracy fix to `follower.jl`
(documenting the `v > 0` requirement added in Task 1) — folded into the test commit since
it documents the same guard the new tests exercise._

## Files Created/Modified

- `src/planning/trace.jl` - New `BendersTrace` convergence ledger (JuMP-free)
- `src/planning/benders.jl` - Wires `BendersTrace` into both loop branches; IN-01/02/03 fixes
- `src/planning/retry.jl` - Additive `attempts_out` keyword on `solve_with_retry!`
- `src/planning/master.jl` - Forwards `attempts_out` from `solve_master!`
- `src/planning/subproblem.jl` - Forwards `attempts_out` from `solve_planning_oracle!`
- `src/planning/follower.jl` - IN-06 Farkas `v > 0` guard widening + docstring update
- `src/TSODSO.jl` - `include("planning/trace.jl")` positioned third in the planning/ block
- `test/test_planning_benders.jl` - Extended trace assertions; new boundary-guard testitem
- `test/test_planning_retry.jl` - Extended + new `attempts_out` regressions
- `test/test_planning_hardening.jl` - New: three degenerate feasibility-cut edge cases

## Decisions Made

- `BendersTrace`'s ten fields and their guard semantics (see key-decisions above).
- `oracle_status_trace`'s `:not_solved` sentinel and the follower's intentional exclusion
  from a parallel status column — documented in `trace.jl`'s header comment per the
  plan-checker warning-fix requirement (revision 1).
- Duplicate Farkas cuts tolerated, not deduped (Claude's Discretion, documented + tested).
- Near-boundary test offset changed from the plan's stated `1e-9` to an empirically
  measured `1e-6` (see Deviations below).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Near-boundary feasibility-cut test offset was too small to reliably trigger infeasibility**
- **Found during:** Task 2 (writing `test/test_planning_hardening.jl`'s near-boundary
  testitem, per the plan's literal `± 1e-9` offset)
- **Issue:** The plan's action block specifies `solve_follower!(f, [0.5 - 1e-9])` /
  `solve_follower!(f, [0.5 + 1e-9])` expecting `feasible=true`/`feasible=false`
  respectively. Empirically (via a focused Julia script sweeping offsets
  1e-9..1e-3), HiGHS's own default primal-feasibility tolerance (~1e-7) accepts a
  1e-9 boundary violation as still `feasible=true` on this fixture — the first full
  `Pkg.test()` run confirmed this with 2 failed + 4 errored assertions in the new
  file (`res_bad.feasible == false` evaluated to `true == false`, then downstream
  `NamedTuple` field-access errors on the wrong branch's fields).
- **Fix:** Measured the actual feasible/infeasible split empirically (mirroring the
  project's own "measure, don't guess" convention already used in
  `test_planning_retry.jl`'s WR-04/10-RESEARCH.md Pitfall 4) and confirmed `1e-6`
  reliably reproduces both branches (`feasible=true` at `0.5-1e-6`, `feasible=false`
  with a genuine finite `v>0` Farkas certificate at `0.5+1e-6`). Updated both the
  near-boundary testitem and the duplicate-cuts testitem (which reuses the same
  trial point) to use `1e-6`, and documented the measurement in both testitems'
  comments and the file header.
- **Files modified:** `test/test_planning_hardening.jl`
- **Verification:** Full `Pkg.test()` re-run: 2124 passed / 0 failed / 0 errored / 2
  documented-broken.
- **Committed in:** `0017e8b` (Task 2 commit — the offset was corrected before the
  file was ever committed, so no separate fix commit was needed)

---

**Total deviations:** 1 auto-fixed (1 bug fix — empirical measurement correction to a test fixture parameter, no production code affected).
**Impact on plan:** No scope creep. The plan's own escape hatch language for the toy
Stackelberg fixture ("if qualitatively wrong, investigate; otherwise widen and document")
applies directly here — the corrected offset preserves the test's intent (prove the cut
store stays valid across a genuine feasible/infeasible split at a near-boundary trial)
while matching the fixture's actual solver-tolerance behavior.

## Issues Encountered

None beyond the deviation documented above — resolved during Task 2 execution before any
commit was made.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `BendersTrace` (with genuine `retry_count`/`oracle_status` columns) is ready for Phase
  13 to instantiate one-per-distributor inside the Nash diagonalization outer loop.
- Cut-store robustness at the master level (near-boundary, near-zero-capacity, duplicate
  Farkas cuts) is proven — Phase 13 nests a second outer loop on top of mechanics whose
  edge-case failure modes are now known and tested, not unknown.
- IN-04, IN-05, IN-07 (Phase 11's remaining info-level findings, judged not cheap enough
  for this hardening pass) remain open — no action needed unless a future phase's own
  scope touches them.

---
*Phase: 12-cut-store-benders-master-robustness-hardening*
*Completed: 2026-07-22*

## Self-Check: PASSED

All claimed created/modified files verified present on disk; both task commit hashes
(`5f4c8e6`, `0017e8b`) verified present in git history.
