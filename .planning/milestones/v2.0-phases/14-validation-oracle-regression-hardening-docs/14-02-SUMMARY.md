---
phase: 14-validation-oracle-regression-hardening-docs
plan: 02
subsystem: testing
tags: [jump, testitem, planning-layer, no-binaries-guard, pval-04]

# Dependency graph
requires:
  - phase: 13-nash-diagonalization-shared-corridor
    provides: src/planning/coupling.jl (build_shared_transmission) and the SharedTransmission-only
      partial no-binaries checks in test/test_planning_coupling.jl and test/test_planning_nash.jl
provides:
  - Consolidated, registry-based no-binaries `@testitem` covering all four planning-layer
    subproblem builders (build_planning_oracle, build_follower, build_master,
    build_shared_transmission)
  - Source-scan tripwire that fails if a future new `build_*` function under src/planning/
    is not represented in the registry
  - Cross-reference comments in the two pre-existing partial checks, kept (not removed)
affects: [15-planning-layer-milestone-close, any-future-phase-adding-src/planning-builders]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Registry-based Dict{String,Function} mapping builder names to zero-arg model-building
      closures, looped over for a uniform semantic check"
    - "Source-scan tripwire: readdir + regex over `^function (build_\\w+)\\(` compared via
      Set-equality against the registry's keys, so new builders can't silently skip coverage"

key-files:
  created: [test/test_planning_noninteger.jl]
  modified: [test/test_planning_coupling.jl, test/test_planning_nash.jl]

key-decisions:
  - "Consolidated the guard into ONE new file rather than editing the 4 individual
    builder-owning test files, matching 14-CONTEXT.md's registry+tripwire decision."
  - "Kept both pre-existing partial checks rather than deleting them: coupling.jl's checks a
    fresh build, nash.jl's checks the POST-run_nash!-mutation state — a different code path."
  - "Deviation (Rule 1 - bug): the plan's literal action text specified `@test isempty(offenders)
    \"message\"`, which is invalid Test.jl syntax (verified directly against Julia 1.12's Test
    stdlib: `@test cond \"msg\"` throws `invalid test macro call`). Replaced with
    `@test isempty(offenders) || error(\"...\")`, which achieves the same fail-loud, builder-name-
    and-offenders-embedded failure message while being valid Julia."

requirements-completed: [PVAL-04]

# Metrics
duration: 35min
completed: 2026-07-24
---

# Phase 14 Plan 02: No-Binaries Guard Consolidation Summary

**Registry-based `@testitem` builds all four planning-layer subproblem models (oracle, follower, master, shared-transmission) and asserts zero binary/integer variables, backed by a source-scan tripwire so a future new builder can't silently skip the check.**

## Performance

- **Duration:** ~35 min
- **Tasks:** 2 completed
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments
- Created `test/test_planning_noninteger.jl`: one `@testitem` with a 4-entry builder registry
  (`build_planning_oracle`, `build_follower`, `build_master`, `build_shared_transmission`),
  each built via its exact public signature on the shared toy fixture, asserting
  `isempty(offenders)` where `offenders` collects any `is_binary`/`is_integer` variable.
- Added a source-scan tripwire: scans every `.jl` file under `src/planning/` for
  `^function (build_\w+)\(` definitions and asserts the found set exactly equals the
  registry's key set — a new builder added later without a matching registry entry fails
  this test loudly.
- Cross-referenced (not removed) the two pre-existing partial SharedTransmission-only checks
  in `test/test_planning_coupling.jl` and `test/test_planning_nash.jl` with one-line
  `NOTE:` comments pointing to the new consolidated file.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create test/test_planning_noninteger.jl** - `863e5a6` (test)
2. **Task 2: Cross-reference the two existing partial checks** - `7f1275e` (docs)

**Plan metadata:** commit pending (this SUMMARY + final metadata commit)

## Files Created/Modified
- `test/test_planning_noninteger.jl` - new consolidated 4-builder no-binaries guard + tripwire
  (82 lines)
- `test/test_planning_coupling.jl` - added a one-line cross-reference comment above its existing
  SharedTransmission-only `@testitem` (no other change)
- `test/test_planning_nash.jl` - added a one-line cross-reference comment above its existing
  post-`run_nash!` no-binaries `@test` (no other change)

## Decisions Made
- Consolidated all four builders' no-binaries coverage into one new file (per 14-CONTEXT.md's
  explicit registry+tripwire decision), rather than scattering a check per builder-owning test
  file.
- Kept both pre-existing partial checks rather than removing them, since one is a fresh-build
  check and the other exercises a genuinely different code path (post-`run_nash!` mutation).
- Reused the toy fixture verbatim from `test/test_planning_certification.jl` lines 176-181
  (`Phase6Fixtures.two_bus_feeder()`, `ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)`,
  `TSODSO.Aggregator(2, 0.9, [dev], [0.0])`) rather than inventing a new instance.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Invalid `@test cond "message"` syntax in plan's specified action text**
- **Found during:** Task 1 (writing test/test_planning_noninteger.jl)
- **Issue:** The plan's `<action>` text specifies
  `@test isempty(offenders) "builder $(name) introduced binary/integer variable(s): $(offenders)"`.
  Verified directly against Julia 1.12's `Test` stdlib that a bare trailing string is not
  accepted as a custom failure message by the `@test` macro — it throws
  `invalid test macro call: @test isempty(x) "custom message: ..."` at macro-expansion time,
  which would make the whole test file fail to load.
- **Fix:** Replaced with `@test isempty(offenders) || error("builder $(name) introduced
  binary/integer variable(s): $(offenders)")`, verified this pattern surfaces as an
  "Error During Test" with the interpolated message (embedding both the builder `name` and the
  `offenders` list) printed verbatim — satisfying the plan's fail-loud acceptance criterion
  without the invalid syntax.
- **Files modified:** test/test_planning_noninteger.jl
- **Verification:** Ran the new `@testitem` via `TestItemRunner.run_tests` filtered on
  `"no-binaries guard"` from a scratch `test/Project.toml`-based dev-linked environment: 5
  passed (4 builder checks + 1 tripwire), 0 failed.
- **Committed in:** 863e5a6 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug in plan's own specified syntax)
**Impact on plan:** Necessary for correctness — the plan's literal Julia snippet would not have
loaded. No scope creep; the fix preserves the exact fail-loud semantics the plan required.

## Issues Encountered
- Verification runs via `Pkg.develop(path=".")` + `Pkg.instantiate()` against `test/Project.toml`
  mutated `test/Manifest.toml`/`test/Project.toml` (dropped a comment block, added a redundant
  `TSODSO` entry) as a side effect of dev-linking the package for TestItemRunner. This churn was
  reverted via `git checkout -- test/Project.toml test/Manifest.toml` after each verification run
  and never staged or committed — no lasting effect on those files.
- Per this plan's own note, the root `Project.toml`/`Manifest-v1.12.toml` CairoMakie-promotion
  drift (pre-existing, user-local) was left untouched throughout — never staged or committed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- PVAL-04's roadmap success criterion ("automated no-binaries guard fails CI/tests if any
  planning-layer subproblem builder introduces a binary/integer variable") is satisfied and
  self-enforcing against future new builders via the source-scan tripwire.
- All three plan-level `<verification>` steps pass:
  1. `"no-binaries guard"` filtered run: 5 passed, 0 failed (4 builder checks + 1 tripwire).
  2. `"planning coupling"`/`"planning nash"` filtered run: 118 passed, 1 pre-existing broken,
     0 failed, 0 errored — no regression from the cross-reference comment additions.
  3. Full `julia --project=. -e 'using Pkg; Pkg.test("TSODSO")'` suite: **2263 passed, 3
     pre-existing broken, 0 failed, 2266 total, 9m37.9s** — stays green.
- No blockers for the sibling 14-01 (golden fixtures) or 14-03 (docs) plans running in parallel;
  this plan touched only `test/test_planning_noninteger.jl`, `test/test_planning_coupling.jl`,
  and `test/test_planning_nash.jl`.

## Self-Check: PASSED

- FOUND: test/test_planning_noninteger.jl
- FOUND commit 863e5a6 (Task 1)
- FOUND commit 7f1275e (Task 2)

---
*Phase: 14-validation-oracle-regression-hardening-docs*
*Completed: 2026-07-24*
