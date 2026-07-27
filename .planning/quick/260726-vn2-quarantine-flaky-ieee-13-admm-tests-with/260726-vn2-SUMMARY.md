---
quick_id: 260726-vn2
subsystem: testing
tags: [testitem, testmodule, admm, clarabel, flaky-test, retry]

# Dependency graph
requires:
  - phase: 6/16 (ADMM core + reactive consensus)
    provides: solve_admm and its internal assert_solved! choke point (src/core/status.jl)
provides:
  - test-only bounded retry helper for the two documented flaky IEEE-13 solve_admm test items
affects: [test/test_acceptance.jl, test/test_admm.jl, future ADMM test items solving the IEEE-13 ground fixture at ρ=100]

# Tech tracking
tech-stack:
  added: []
  patterns: ["test-only @testmodule bounded-retry wrapper around a documented solver flake, narrowly matched on exact error message prefix, distinct from src/planning/retry.jl's solver-attribute escalation ladder"]

key-files:
  created: [test/fixtures_retry.jl]
  modified: [test/test_acceptance.jl, test/test_admm.jl]

key-decisions:
  - "Retry lives in test/ only (AdmmRetryFixtures @testmodule) — solve_admm itself is never modified and never auto-retries"
  - "Catch narrowly on ErrorException with message prefix 'Solve failed — refusing to trust results' (assert_solved!'s exact signature) — any other error/message rethrows immediately, never swallowed"
  - "Plain re-call with no input perturbation between attempts — the flake is Clarabel's non-deterministic iterate path on identical seeded inputs"
  - "Rethrow on exhaustion (max_attempts=3 default) so a persistent, non-transient failure still fails the test loudly"

requirements-completed: []

# Metrics
duration: 25min
completed: 2026-07-27
---

# Quick Task 260726-vn2: Bounded retry for the flaky IEEE-13 `solve_admm` test items Summary

**Added a test-only bounded-retry `@testmodule` that wraps the two documented flaky IEEE-13 `solve_admm` calls, catching only `assert_solved!`'s exact Clarabel-flake error signature and leaving every assertion byte-identical.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-07-27T01:37:00Z (approx, worktree reset + file reads)
- **Completed:** 2026-07-27T02:02:29Z
- **Tasks:** 2/2 completed
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments
- Created `test/fixtures_retry.jl` defining `AdmmRetryFixtures.retry_flaky_admm_solve`, a test-only bounded-retry helper matching the exact plan spec (guard, narrow catch, `@warn` per attempt, rethrow on exhaustion or on any non-matching error).
- Wired the helper into both documented flaky items — `test/test_acceptance.jl`'s "acceptance: IEEE-13 congestion..." item and `test/test_admm.jl`'s "admm: cross-validation ieee13 welfare + DADP (crossval, ieee13)" item — wrapping only the `solve_admm(...)` call in a do-block; every assertion/tolerance line stays untouched.
- Verified 3/3 explicit-path TestItemRunner runs pass on both target items (no flake observed in any of the 3 runs; the retry path was not exercised this session but the exhaustion/rethrow and narrow-catch logic is unit-verifiable by inspection and matches `assert_solved!`'s exact message).

## Task Commits

Each task was committed atomically:

1. **Task 1: create the shared retry fixture module** - `34ad1f7` (feat)
2. **Task 2: wire the helper into both flaky test items and verify locally** - `e015529` (test)

**Plan metadata:** (this commit, handled by orchestrator)

## Files Created/Modified
- `test/fixtures_retry.jl` - New `@testmodule AdmmRetryFixtures` defining `retry_flaky_admm_solve(f; max_attempts=3, label)`, a plain re-call retry loop narrowly matching `assert_solved!`'s exact error message prefix.
- `test/test_acceptance.jl` - Added `AdmmRetryFixtures` to the IEEE-13 congestion acceptance item's `setup` list; wrapped its `solve_admm(...)` call in `AdmmRetryFixtures.retry_flaky_admm_solve(; label = "acceptance ieee13") do ... end`.
- `test/test_admm.jl` - Added `AdmmRetryFixtures` to the ieee13 crossval item's `setup` list; wrapped its `solve_admm(...)` call in `AdmmRetryFixtures.retry_flaky_admm_solve(; label = "admm crossval ieee13") do ... end`.

## Decisions Made
- Followed the plan's decisions #2–#7 exactly (narrow catch, `@warn` every retry, rethrow on exhaustion, shared test-only helper, no input perturbation, `solve_admm` unmodified).
- No new decisions beyond what the plan already specified.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - blocking issue] Task 1's literal verify command needed `using TestItemRunner` first**
- **Found during:** Task 1 verification
- **Issue:** The plan's stated verify command `julia --project=test -e 'include("test/fixtures_retry.jl")'` fails with `UndefVarError: @testmodule not defined in Main`, because `@testmodule` is exported by `TestItemRunner`/`TestItems` and is not in scope by a bare `include` without first loading that package.
- **Fix:** Ran the equivalent syntax smoke check as `julia --project=test -e 'using TestItemRunner; include("test/fixtures_retry.jl")'`, which parses cleanly. No code change was needed — this is a verification-command correction only, not a file change.
- **Files modified:** none (verification-only)
- **Verification:** Ran the corrected command; exits cleanly with no error.
- **Committed in:** n/a (no code change)

## Verification Results

Explicit-path TestItemRunner run (per plan, never `julia -e '@run_package_tests'`), filtered to the target items, executed 3 times in a row from the repo root with `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib"`:

- Run 1: `test_admm.jl` "admm: cross-validation ieee13 welfare + DADP (crossval, ieee13)" — Pass 5/5; `test_acceptance.jl` "acceptance: IEEE-13 congestion..." — Pass 7/7.
- Run 2: same two items — Pass 5/5 and Pass 7/7.
- Run 3: same two items — Pass 5/5 and Pass 7/7.

(The filter substring `"IEEE-13 congestion"` also incidentally matches an unrelated third item, `test_thesis_repro.jl`'s "thesis_repro: IEEE-13 congestion — DSO-surplus sign-flip qualitative cross-check (secondary, non-gated)" — out of scope for this task, not modified, and it passed in all 3 runs too.)

No `@warn "retry_flaky_admm_solve: ..."` line appeared in any of the 3 runs — the documented Clarabel flake did not trigger this session, so the retry path itself was not exercised end-to-end by these runs. This is a valid, expected outcome given the ~55% single-call baseline (not a guaranteed trigger every run); the narrow-catch/rethrow-on-exhaustion logic was verified by code inspection against `assert_solved!`'s exact message format (`src/core/status.jl:57-63`).

## Known Stubs

None.

## Threat Flags

None — this task adds no new network endpoint, auth path, file-access pattern, or schema change; it is a test-only retry wrapper around an existing, unmodified `solve_admm` call path.

## Self-Check: PASSED

- FOUND: test/fixtures_retry.jl
- FOUND: 34ad1f7 (in git log)
- FOUND: e015529 (in git log)
- Both test files' diffs confirmed to touch only the `setup` list and the `solve_admm` call site — no `@test` line changed (confirmed via `git diff`).
