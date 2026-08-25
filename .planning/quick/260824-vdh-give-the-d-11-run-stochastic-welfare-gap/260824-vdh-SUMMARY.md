---
quick_id: 260824-vdh
subsystem: testing
tags: [julia, cross-version, tolerance, run_stochastic, welfare_gap, ci]

# Dependency graph
requires:
  - phase: v3.0 Phase 22 (Stochastic PV/Demand Uncertainty)
    provides: test/test_run_stochastic.jl's D-11 measurement-before-golden item
provides:
  - test/test_run_stochastic.jl's D-11 golden now passes on Julia 1.10, 1.11, and 1.12
affects: [ci-julia-1.12-job, future-touches-of-test_run_stochastic.jl]

tech-stack:
  added: []
  patterns:
    - "pin cross-Julia-version solver-iterate goldens with a measured rtol (not a
      re-pinned value, not a loosened stability assertion) — derive the tolerance from
      the worst OBSERVED deviation across versions/commits, with explicit headroom
      documented inline, rather than picking a round number"

key-files:
  created: []
  modified:
    - test/test_run_stochastic.jl

key-decisions:
  - "Confirmed the committed golden -0.02515629356082627 is correct (bit-for-bit
    reproduced on Julia 1.10.11 and 1.11.9) and left it unchanged — the CI failure was a
    Julia-1.12-only Clarabel converged-iterate shift, not a wrong pin."
  - "Added rtol=1e-4 to the golden @test rather than loosening or reordering the
    r1==r2==r3 stability assertion, per the plan's explicit constraint — the stability
    property (within-environment determinism) and the cross-environment tolerance
    (across-version solver drift) are different properties and must stay separately
    encoded."
  - "rtol=1e-4 chosen for ~17x headroom above the worst measured cross-version/cross-commit
    relative deviation (~5.74e-6), per the plan's own derivation — not independently
    re-derived here."

requirements-completed: []

duration: ~15min
completed: 2026-08-24
---

# Quick Task 260824-vdh: Give the D-11 `run_stochastic` `welfare_gap` golden a measured `rtol` Summary

**Added `rtol = 1e-4` to the D-11 `welfare_gap` golden `@test` in `test/test_run_stochastic.jl` (golden value and the `==` stability assertion both unchanged), documented the measured cross-Julia-version Clarabel iterate spread inline, and verified the item now passes on Julia 1.12.7 — the exact version CI was failing on.**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-08-24
- **Tasks:** 2 of 2 completed as planned
- **Files modified:** 1

## Accomplishments

- Added a new comment paragraph immediately below the existing `RE-PINNED for the WR-09
  fix (phase-22 review)` block, recording: the three-row Julia 1.10.11/1.11.9/1.12.7
  measurement table, the two CI-observed 1.12 values across two different commits
  (304db38, 3b73633), the worst observed relative deviation (~5.74e-6), the ~17x
  headroom rationale for `rtol=1e-4`, and a one-sentence context note that cross-commit
  variation on the same Julia version is a separately-tracked IEEE-13 numerical-knife-
  edge finding, not something this tolerance is meant to paper over.
- Changed line 127 (now later in the file after the comment insertion) from
  `@test r1.oos.welfare_gap ≈ -0.02515629356082627` to
  `@test r1.oos.welfare_gap ≈ -0.02515629356082627 rtol = 1e-4`. The golden literal
  value is byte-identical to before. The `@test r1.oos.welfare_gap == r2.oos.welfare_gap
  == r3.oos.welfare_gap` stability assertion above it, and everything above that line,
  is untouched.
- Confirmed via `git diff test/test_run_stochastic.jl` that only the new comment
  paragraph and the `rtol = 1e-4` addition changed — no incidental reformat, no other
  line touched (28 insertions, 1 deletion, all inside the intended block).
- Verified functionally on Julia 1.12.7 (`julia +1.12`, matching the CI job that was
  failing) via the explicit-`JULIA_LOAD_PATH` TestItemRunner form:
  `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib" julia +1.12 -e 'using TestItemRunner,
  TSODSO; TestItemRunner.run_tests(joinpath(pwd(), "test");
  filter=ti->occursin("D-11 measurement-before-golden", ti.name))'`. Result:
  `Test Summary: | Pass 2 Total 2`, `exit=0`, `grep -c "Test Failed"` on the captured
  log returned `0`. The D-11 item — including the three fresh `run_stochastic` calls,
  the `==` stability assertion, and the now-tolerant golden — passes on the exact Julia
  version CI observed failing on.

## Task Commits

1. **Task 1: add `rtol=1e-4` to the golden and record the cross-version measurement** —
   `ff8f71f` (test)
2. **Task 2: verify the item now passes on Julia 1.12** — verification only, no commit
   (per plan); log at
   `/tmp/claude-1000/-home-pedro-programming-TSO-DSO/fb15e907-7729-4e8c-8dfc-10ace72db910/scratchpad/d11-golden-run.log`

## Files Created/Modified

- `test/test_run_stochastic.jl` — added a comment paragraph documenting the measured
  Julia 1.10/1.11/1.12 cross-version `welfare_gap` values and the `rtol=1e-4` rationale;
  added `rtol = 1e-4` to the golden `@test`. Golden literal value and the `==` stability
  assertion unchanged.

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

None — plan executed exactly as written. No `src/` files touched; only
`test/test_run_stochastic.jl` changed, matching the plan's Task 1 `done` criterion
exactly (confirmed via `git diff test/test_run_stochastic.jl`). No `JuliaFormatter.format`
call was made on this or any file.

## Issues Encountered

None. The verification command ran cleanly on the first attempt: ~68s TestItemRunner/
TSODSO precompile (first-run cost) plus ~71.5s for the actual test package run (three
full `run_stochastic` calls plus the earlier D-11-adjacent item in the same file), well
within the generous timeout budgeted. No hang, no retry needed.

## Known Stubs

None — this task only modified test-file comments and a tolerance keyword on an
existing `@test`; no UI or data-rendering surface was touched.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes.
This task only added a documented, measured tolerance to a pre-existing golden-value
test.

## Self-Check: PASSED

- `test/test_run_stochastic.jl` contains the new comment paragraph and
  `@test r1.oos.welfare_gap ≈ -0.02515629356082627 rtol = 1e-4` (verified by direct
  read after edit and by `git diff`).
- Commit `ff8f71f` exists: `git log --oneline -1 -- test/test_run_stochastic.jl` →
  found (`ff8f71f test(260824-vdh): give D-11 welfare_gap golden a measured rtol=1e-4`).
- The Julia 1.12.7 TestItemRunner verification run reports `Pass 2 / Total 2`, `exit=0`,
  and `0` occurrences of `Test Failed` in the captured log — the D-11 item genuinely
  passes on the CI-failing version, with no golden re-pin, no stability-assertion
  weakening, and no skipped assertion.

## Next Phase Readiness

- No blockers. `test/test_run_stochastic.jl`'s D-11 item is now cross-Julia-version
  trustworthy (1.10/1.11/1.12), with the measured basis for `rtol=1e-4` documented
  inline for any future re-derivation. No follow-up required for this file.

---
*Quick task: 260824-vdh*
*Completed: 2026-08-24*
