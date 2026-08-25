---
quick_id: 260824-vct
subsystem: testing
tags: [julia, soft-scope, testitem, stochastic-welfare, socp-exactness, pf-04-gate]

# Dependency graph
requires:
  - phase: v3.0 Phase 22 (Stochastic PV/Demand Uncertainty)
    provides: test/test_stochastic_welfare.jl's D-06 PF-04 gate scan
provides:
  - test/test_stochastic_welfare.jl's D-06 item passes for the right reason (gate
    genuinely trips at pv_scale=2.0), soft-scope-warning-free
affects: [future-touches-of-test_stochastic_welfare.jl]

tech-stack:
  added: []
  patterns:
    - "wrap mutable scan/accumulator state assigned inside a for-loop-in-@testitem-body
      in a `let ... end` block (hard scope) and destructure the returned tuple at the
      @testitem top level, instead of assigning bare names directly in the testitem body
      (module top-level = soft scope, ambiguous inside a subsequent for-loop)"

key-files:
  created: []
  modified:
    - test/test_stochastic_welfare.jl

key-decisions:
  - "Root-caused as a genuine Julia soft-scope bug (not a solver/package-resolution
    flake) using CI's own 'Assignment to ... in soft scope is ambiguous' warning plus
    the single-entry outcomes vector as direct evidence; retracted the stale
    Pkg.test()-sandbox-drift hypothesis from the file's comments rather than layering a
    new theory on top of a wrong one."
  - "Fixed via `let`-block hard-scoping the three accumulator names (tripped,
    trip_pv_scale, outcomes) rather than declaring `global` inside the loop — the `let`
    form keeps the scan's state properly encapsulated and is the idiomatic fix for this
    exact soft-scope class."
  - "Added `@test trip_pv_scale == 2.0` (not just `@test tripped`) so the assertion
    verifies the trip happened at the specific measured pv_scale, closing the dead-
    binding gap the plan flagged."

requirements-completed: []

duration: ~20min
completed: 2026-08-24
---

# Quick Task 260824-vct: Fix the soft-scope bug in the D-06 PF-04 gate scan Summary

**Wrapped the D-06 PF-04 gate scan's `tripped`/`trip_pv_scale`/`outcomes` state in a `let` block, fixing the Julia soft-scope bug that silently discarded the loop's `tripped = true` assignment; the item now passes twice consecutively with zero soft-scope warnings and a verified trip at exactly pv_scale=2.0.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-08-24
- **Tasks:** 2 of 2 completed as planned
- **Files modified:** 1

## Accomplishments

- Replaced the stale, retracted diagnosis comment (previously blaming `Pkg.test()`
  sandbox package-resolution drift / uncommitted `Project.toml`/`Manifest-v1.12.toml`
  state) with the real root cause: `tripped`, `trip_pv_scale`, `outcomes` were assigned
  at `@testitem` top level (module global scope); the `for pv_scale in (...)` loop is a
  soft scope, so the `tripped = true` / `trip_pv_scale = pv_scale` assignments inside it
  created brand-new locals that died with the loop instead of updating the outer
  globals — matching CI's own `Warning: Assignment to 'tripped' in soft scope is
  ambiguous ...` diagnostic and the single-entry `outcomes` vector exactly.
- Wrapped the scan's mutable state (`tripped`, `trip_pv_scale`, `outcomes`
  initializers plus the full `for` loop, body byte-identical) in a `let` block (hard
  scope), returning a tuple destructured at `@testitem` top level:
  `tripped, trip_pv_scale, outcomes = let tripped = false, trip_pv_scale = NaN,
  outcomes = String[] ... (tripped, trip_pv_scale, outcomes) end`.
- Reworded the `if !tripped` self-diagnosis block's leading comment to drop the
  reference to the retracted sandbox-resolution hypothesis and state plainly that the
  block is retained as a general-purpose self-diagnosis for any future unrelated
  no-trip failure — the `resolved = try ... catch ... end` logic and the final `@info`
  call are unchanged.
- Added `@test trip_pv_scale == 2.0` immediately after `@test tripped`.
- Verified the fix functionally: ran the D-06 item in isolation via
  `TestItemRunner.run_tests` twice, consecutively. Both runs: `Pass 5 / Total 5`
  (~32s each after a one-time ~14s precompile), and
  `grep -c "Assignment to .* in soft scope is ambiguous"` on each captured log
  returned `0`. Since `@test trip_pv_scale == 2.0` is now part of the item, a passing
  run already proves the trip occurred at exactly `pv_scale=2.0` — not merely that some
  value tripped it.

## Task Commits

1. **Task 1: wrap the scan's mutable state in a `let`, and correct the diagnosis
   comment** — `d8e8999` (fix)
2. **Task 2: verify the gate now trips for the right reason** — verification only, no
   commit (per plan; two consecutive passing runs, logs at
   `/tmp/claude-1000/.../scratchpad/d06-gate-run{1,2}.log`)

## Files Created/Modified

- `test/test_stochastic_welfare.jl` — corrected the D-06 diagnosis comment, `let`-wrapped
  the scan's `tripped`/`trip_pv_scale`/`outcomes` state, reworded the self-diagnosis
  block's comment, added `@test trip_pv_scale == 2.0`.

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

None — plan executed exactly as written. No `src/` files touched; only the comment
block, the `let`-wrapping, the reworded `if !tripped` comment, and the new
`@test trip_pv_scale == 2.0` line changed, matching the plan's Task 1 `done` criterion
exactly (confirmed via `git diff test/test_stochastic_welfare.jl`).

## Issues Encountered

None. Task 1's plan-specified verify command
(`julia --project=. -e 'include("test/test_stochastic_welfare.jl")'`) reproduces a
pre-existing `UndefVarError: @testitem not defined` on BOTH the original file and the
edited file (confirmed by diffing behavior against `git show HEAD:...`) because
`@testitem` requires `using TestItems` to be loaded first and is not itself exported
into `Main` by a bare `include`. This is not a regression from this task's edit; the
functional parse/behavior proof is Task 2's TestItemRunner-based run, which is the
plan's own stated fallback ("the real functional proof is Task 2").

## Known Stubs

None — this task only modified test-file comments and control-flow scoping; no UI or
data-rendering surface was touched.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes.
This task only fixed a scoping bug and corrected stale diagnosis prose inside an
existing test file.

## Self-Check: PASSED

- `test/test_stochastic_welfare.jl` exists and contains the `let`-wrapped scan and the
  new `@test trip_pv_scale == 2.0` line (verified by direct read after edit).
- Commit `d8e8999` exists: `git log --oneline --all | grep d8e8999` → found.
- Two consecutive `TestItemRunner.run_tests` runs filtered to "D-06 PF-04 gate runs per
  scenario" both report `Pass 5 / Total 5`, and both captured logs return `0` for
  `grep -c "Assignment to .* in soft scope is ambiguous"`.

## Next Phase Readiness

- No blockers. `test/test_stochastic_welfare.jl`'s D-06 item is now a trustworthy,
  soft-scope-free gate check; no follow-up required for this file.

---
*Quick task: 260824-vct*
*Completed: 2026-08-24*
