---
phase: 16-reactive-power-consensus
plan: 01
subsystem: testing
tags: [julia, jump, testitems, admm, reactive-power, naming-convention]

# Dependency graph
requires:
  - phase: 15-ac-exactness-oracle
    provides: literate rung page + AC-exactness certification conventions (unrelated code path, sequencing precedent only)
provides:
  - Re-confirmed, documented grep-audit resolving the mu/mu/MU naming collision BEFORE any AgrOpt/DsoOpt/Dlmp production diff
  - Three chosen, distinct reactive-power identifiers (qag_dso, reactive, mu_q) referenced (not re-derived) by later Phase-16 plans
  - RED @testitem harness (test/test_admm_reactive.jl) pinning the REACT-01/02/03 contract that plans 16-02/16-03 turn green
affects: [16-02-dso-opt-reactive-consensus, 16-03-dlmp-reactive-pricing, 16-04-flake-rate-measurement]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "hasmethod(f, Tuple{...}, (:kwarg,)) 3-arg kwarg-detection RED gate for a not-yet-existing keyword argument (kwargs are invisible to isdefined/dispatch, so this is the non-crashing analog for a kwarg addition)"

key-files:
  created:
    - test/test_admm_reactive.jl
  modified: []

key-decisions:
  - "Reactive-power JuMP coupling variable named qag_dso (no Greek letter -- it's a variable, not a dual), the decompose_dlmp NamedTuple field named reactive, and mu_q reserved only if a future scalar/vector price handle is needed -- never bare mu/mu/MU, which continues to mean ONLY the adaptive-rho residual-balancing band."
  - "src/experiments/Scenario.jl is explicitly out of scope for the ENTIRE Phase 16 (all 4 plans), documented in the test file's own header, to avoid a second DrWatson savename golden-hash perturbation."

patterns-established:
  - "3-arg hasmethod kwarg-detection RED gate: mirrors the project's isdefined(TSODSO, :symbol) RED-guard convention but adapted for a keyword-argument addition, since kwargs don't participate in dispatch/isdefined."

requirements-completed: [REACT-03]

# Metrics
duration: ~45min
completed: 2026-07-26
---

# Phase 16 Plan 01: Reactive-Power Naming Decision + RED Harness Summary

**Re-confirmed the mu/mu/MU naming-collision grep-audit live against the current tree, pinned three distinct reactive-power identifiers (qag_dso / reactive / mu_q), and scaffolded a 3-item RED @testitem harness (test/test_admm_reactive.jl) pinning the REACT-01/02/03 contract for plans 16-02/16-03 to turn green.**

## Performance

- **Duration:** ~45 min
- **Tasks:** 2
- **Files modified:** 1 (new file: test/test_admm_reactive.jl)

## Accomplishments

- Re-ran the full `grep -rln "\bμ\b" src/ test/` and `grep -rn "\bmu\b"`/`"\bMU\b"` audit live against the current worktree tree (not merely re-cited from the same-day research pass) and confirmed the result set is EXACTLY the set 16-RESEARCH.md predicted: `solve_admm.jl`, `AgrOpt.jl`/`DsoOpt.jl` (docstrings), `Scenario.jl`, `run.jl`, `store.jl`, `sweep.jl`, `fixtures_phase7.jl`, and three consumer test files -- every binding means exactly one thing today (the Boyd adaptive-rho residual-balancing band). No second meaning found; safe to introduce a distinct reactive-power identifier.
- Documented the chosen identifiers (`qag_dso`, `reactive`, `mu_q`) and the `Scenario.jl` out-of-scope boundary as the file header of the new `test/test_admm_reactive.jl` -- the single reference point plans 16-02/16-03 cite rather than re-deriving.
- Authored 3 `@testitem`s pinning the REACT-01/02/03 contract: a RED `hasmethod`-gated coupling-variable-shape probe, a POSITIVE default-path byte-identical regression (passes now), and a RED `hasmethod`-gated `:balance_q` no-hidden-slack certificate probe.
- Verified the 3-arg `hasmethod(f, Tuple{...}, (:kwarg,))` kwarg-detection form works correctly against the project's live `build_dso_opt`/`solve_admm` signatures (both the "kwarg absent" and "kwarg present" cases were empirically checked in a scratch REPL session before committing to the pattern).

## Task Commits

Each task was committed atomically:

1. **Task 1: Re-confirm the mu/mu grep-audit and pick the distinct reactive identifiers (BLOCKING)** - `99a1a4e` (test)
2. **Task 2: Author the RED @testitem harness pinning REACT-01/02/03** - `420b7f5` (test)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified

- `test/test_admm_reactive.jl` - NEW. Header: re-confirmed live grep audit + chosen identifiers (`qag_dso`/`reactive`/`mu_q`) + `Scenario.jl` out-of-scope statement (Task 1, commit `99a1a4e`). Body: 3 `@testitem`s -- (1) RED `hasmethod`-gated `qag_dso` coupling-variable-shape probe on `build_dso_opt`, (2) POSITIVE default-path (`reactive_consensus` omitted) byte-identical regression, (3) RED `hasmethod`-gated `:balance_q` no-hidden-slack certificate probe on a converged `solve_admm(...; reactive_consensus=true)` (Task 2, commit `420b7f5`). 177 lines total (>= 60 required).

## Decisions Made

- **Reactive-power identifier set:** `qag_dso` (JuMP coupling variable, no Greek letter), `reactive` (decompose_dlmp NamedTuple field), `mu_q` (reserved scalar/vector price handle, only if a future task needs one) -- never bare `μ`/`mu`/`MU`. Rationale: the bare identifier already has exactly one meaning (adaptive-rho band) threaded through `solve_admm`'s kwarg, `Scenario`'s golden-hash-serialized struct field, and `fixtures_phase7.jl`'s `const MU`; reusing it for anything reactive-power-related would create a genuine collision the moment plan 16-02 lands.
- **`src/experiments/Scenario.jl` untouched for the entire phase:** confirmed as an explicit, written-down constraint in the test file's own header (not just cited from RESEARCH/PATTERNS docs) so every later Phase-16 plan has a single, in-repo reference point rather than needing to re-read the research doc.
- **`hasmethod`-based kwarg-detection RED gate** (rather than an `isdefined`-only gate): chosen because `reactive_consensus` is a NEW KEYWORD ARGUMENT on an EXISTING function (`build_dso_opt`/`solve_admm` both already exist and are `isdefined` today), so `isdefined(TSODSO, :build_dso_opt)` alone cannot detect kwarg-level RED/GREEN state. The 3-arg `hasmethod(f, Tuple{...}, (:kwarg,))` form was verified empirically (both directions: kwarg absent -> `false`, kwarg present -> `true`) against the live `build_dso_opt`/`solve_admm` signatures before being committed to the harness.

## Deviations from Plan

None - plan executed exactly as written. Both tasks' acceptance criteria were met and automated-verified as specified in 16-01-PLAN.md.

## Issues Encountered

- **Positional-type sensitivity of `hasmethod`'s 3-arg kwarg-detection form:** an initial trial using `Tuple{Any, Any, Int}` (fully generic positional types) for `solve_admm`'s probe incorrectly returned `false` even for an EXISTING kwarg, because `hasmethod` requires the supplied tuple type to be a subtype of the target method's declared signature (`aggregators::AbstractVector{<:Aggregator}` is not satisfied by a bare `Any` in that slot). Resolved by using `typeof(aggs)` (the fixture's concrete `Vector{Aggregator}` runtime type) and the concrete `ConvexBranchFlow` type for the power-flow-model argument, which correctly resolves against the real method signature. Verified both the "kwarg absent" (returns `false` today) and "kwarg present" (would return `true` once plan 16-02 lands) directions in a scratch REPL session before committing the pattern to the harness -- this is implementation detail internal to Task 2's acceptance criteria, not a plan deviation.
- **Full-suite `Pkg.test()` sanity check exceeded the practical session timeout** (killed after ~590s without completing; this is a large, multi-thousand-test suite spanning the operational + planning layers). Given this plan is test-only (zero `src/` diff), the regression risk from a new, isolated test file is negligible. In lieu of the full suite, the more precisely-scoped filtered run specified by the plan's own Task 2 verification command (`occursin("reactive", ti.name)`) was run to completion and passed cleanly: 131/131 assertions green across `test_dso.jl`, `test_welfare_solve.jl`, `test_admm_reactive.jl` (the new file, all 3 items behaving as specified -- items (1)/(3) report a benign RED PASS since the kwarg is absent, item (2) passes as a live regression), and `test_aggregator.jl`. The full-suite check remains a gate for a later wave/phase-merge point per 16-VALIDATION.md's own sampling-rate table ("per wave merge: full Pkg.test()"), not a hard requirement of this single test-only plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The naming decision (`qag_dso` / `reactive` / `mu_q`) is committed and documented in `test/test_admm_reactive.jl`'s header -- plan 16-02 (DsoOpt/solve_admm `reactive_consensus` kwarg + coupling variable + certificate) can proceed directly, referencing rather than re-deriving this decision.
- The RED harness (`test/test_admm_reactive.jl` items (1) and (3)) is in place and will report a clear, expected transition from RED (benign, `hasmethod`-gated) to full behavioral assertion the moment plan 16-02 lands the `reactive_consensus` kwarg -- no test-file edits needed at that point.
- No blockers. `src/experiments/Scenario.jl` remains untouched, satisfying the phase-wide non-regression constraint for this plan's scope.

---
*Phase: 16-reactive-power-consensus*
*Completed: 2026-07-26*

## Self-Check: PASSED

- FOUND: test/test_admm_reactive.jl
- FOUND: .planning/phases/16-reactive-power-consensus/16-01-SUMMARY.md
- FOUND: commit 99a1a4e (test(16-01): resolve mu naming collision + document reactive identifiers)
- FOUND: commit 420b7f5 (test(16-01): RED harness pinning REACT-01/02/03 contract)
