---
phase: 19-4q-bess-live-reactive-dual-ascent
plan: 01
subsystem: infra
tags: [julia, jump, admm, enum, seam-wiring, testitems]

# Dependency graph
requires: []
provides:
  - Three new Phase-19 include lines wired into src/TSODSO.jl's include graph (FourQuadBESS.jl,
    complementarity_4q.jl, ReactiveMode.jl), each positioned per the plan's exact ordering
    constraints, so 19-02 through 19-08 fill file CONTENT without ever touching TSODSO.jl again
  - Fully implemented, exported, unit-tested ReactiveMode 3-state enum (OFF/CERTIFIED/LIVE) +
    normalize_reactive_mode(m) with Bool/Symbol/ReactiveMode dispatch and D-12 back-compat
  - Two comment-only seam stub files (FourQuadBESS.jl for plan 19-02, complementarity_4q.jl for
    plan 19-05) ready to be filled without any further TSODSO.jl edit
  - Recorded pre-Phase-19 byte-identity baseline (2359 pass / 0 fail / 3 broken, 19m28.9s) for
    Plan 19-08's final diff (ROADMAP success criterion 4)
affects: [19-02, 19-03, 19-05, 19-06, 19-07, 19-08]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Comment-only SEAM/OWNER stub files (mirrors src/data/ieee123.jl's Wave-1 precedent):
      header + SEAM + OWNER + prose, zero struct/function/export tokens, grep-verified inert"
    - "Self-contained @enum + normalize_* accessor function for a multi-representation
      (Bool/Symbol/enum) input, with ArgumentError-not-@assert on invalid input (project
      convention, mirrors src/data/profiles.jl / src/data/topology.jl)"

key-files:
  created:
    - src/admm/ReactiveMode.jl
    - src/devices/FourQuadBESS.jl
    - src/models/complementarity_4q.jl
    - test/test_reactive_mode.jl
  modified:
    - src/TSODSO.jl

key-decisions:
  - "Verified the plan's literal targeted-verification command (`julia --project=. -e 'using
    TestItemRunner; ...'`) does not work standalone: TestItemRunner is a test/Project.toml-only
    dependency, not resolvable under a bare `--project=.` (confirmed by direct reproduction —
    ArgumentError: Package TestItemRunner not found in current path). It only resolves inside
    Pkg.test()'s ephemeral sandboxed temp environment. Substituted an equivalent direct
    Test.jl assertion script under `--project=.` (same behavioral assertions as
    test/test_reactive_mode.jl's @testitem bodies) to verify Task 2 without needing
    TestItemRunner, per orchestrator guidance to avoid re-running the ~19.5 min full suite."
  - "Per orchestrator instruction (after the baseline Pkg.test() run measured ~19.5 min), did
    NOT re-run the full suite a second time to re-confirm Task 2's byte-identity claim.
    Confidence instead rests on: (1) TSODSO precompiles cleanly with zero warnings/errors
    after all three new includes + new files are added, (2) all changes are strictly additive
    (3 new include lines pointing to files with zero existing-symbol overlap; the two device/
    certificate stubs are comment-only with a grep-verified absence of struct/function/export
    tokens), (3) the new ReactiveMode enum/function is a brand-new name with no ambiguity risk
    against any existing method. This is documented as a deviation below."

requirements-completed: [MESH-04, MESH-05]

# Metrics
duration: ~35min (dominated by the one-time 19m28.9s baseline Pkg.test() run)
completed: 2026-08-08
---

# Phase 19 Plan 01: Seam Wiring + ReactiveMode Enum Summary

**Wired 3 new Phase-19 includes into `src/TSODSO.jl` (FourQuadBESS.jl, complementarity_4q.jl,
ReactiveMode.jl) and fully implemented the self-contained `ReactiveMode` 3-state enum
(OFF/CERTIFIED/LIVE) + `normalize_reactive_mode` accepting Bool/Symbol/ReactiveMode, unit-tested,
with the pre-Phase-19 byte-identity baseline (2359 pass / 0 fail / 3 broken) recorded for Plan
19-08's final diff.**

## Performance

- **Duration:** ~35 min (the baseline `Pkg.test()` run alone took 19m28.9s)
- **Tasks:** 2 completed
- **Files modified:** 5 (1 modified, 4 created)

## Accomplishments
- `src/TSODSO.jl` now has exactly 3 new, correctly-positioned `include(...)` lines — Waves 2/3
  of Phase 19 (19-02, 19-03, 19-05) can add file CONTENT without ever touching this shared file
  again, letting device (19-02) and DsoOpt (19-03) plans run in the same wave with zero
  `files_modified` overlap.
- `ReactiveMode` (OFF/CERTIFIED/LIVE) + `normalize_reactive_mode` fully implemented, exported,
  and unit-tested — the single source of truth for the 3-way reactive-consensus distinction
  that plans 19-03/19-06/19-07 will consume in `build_dso_opt`/`build_agr_opt`/`solve_admm`.
- Two comment-only stub files created (`FourQuadBESS.jl` for plan 19-02, `complementarity_4q.jl`
  for plan 19-05), each inert (zero `struct`/`function`/`export` tokens, grep-verified).
- Pre-Phase-19 byte-identity baseline captured and recorded: **2359 pass / 0 fail / 3 broken /
  2362 total, 19m28.9s** — ready for Plan 19-08's final gate-then-golden diff.

## Task Commits

Each task was committed atomically:

1. **Task 1: Capture the pre-Phase-19 byte-identity baseline** — no commit (read-only task;
   no file created or modified per the plan's own `<files>none</files>` spec). Baseline recorded
   in this SUMMARY (see "Baseline Reconciliation" below).
2. **Task 2: Wire the three Phase-19 seam stubs + implement ReactiveMode** - `6a79a93` (feat)

**Plan metadata:** (this commit) - `docs(19-01): complete plan`

## Files Created/Modified
- `src/TSODSO.jl` - 3 new include lines (FourQuadBESS.jl, complementarity_4q.jl, ReactiveMode.jl)
- `src/admm/ReactiveMode.jl` - Fully implemented `@enum ReactiveMode OFF CERTIFIED LIVE` +
  `normalize_reactive_mode(m)` (Bool/Symbol/ReactiveMode dispatch, `ArgumentError` on invalid
  input), exported
- `src/devices/FourQuadBESS.jl` - Comment-only stub, owned by plan 19-02
- `src/models/complementarity_4q.jl` - Comment-only stub, owned by plan 19-05
- `test/test_reactive_mode.jl` - 4 `@testitem`s (tag `[:reactive]`) covering Bool back-compat,
  Symbol dispatch, ReactiveMode identity, and invalid-input `ArgumentError`

## Baseline Reconciliation (Task 1)

Ran `julia --project=. -e 'import Pkg; Pkg.test()'` (the correct invocation per STATE.md's
test-invocation hazard note) BEFORE Task 2 touched any file.

**Result: `2359 pass / 0 fail / 3 broken / 2362 total`, 19m28.9s.**

**Reconciliation against STATE.md's recorded "last-known-good" figure (2358 pass / 1 fail / 3
broken):** the counts drift by ±1 (pass 2358→2359, fail 1→0). This is called out explicitly per
the plan's own acceptance criteria, not silently accepted. Per
`memory/local-project-toml-drift.md` (project memory), there are 2 known-false Aqua failures on
a dirty main checkout (CairoMakie stale-deps drift + a Makie persistent-tasks drift) but this
worktree exhibits a documented "TestItemRunner worktree gotcha" that suppresses one of the two —
consistent with the observed 1-fewer-failure count in a fresh worktree checkout vs. the main
checkout's `Project.toml`/`Manifest.toml` drift state. This is environmental (worktree vs. main
checkout `Project.toml` state), not a regression introduced by this plan — Task 1 ran before any
Task 2 file was touched. The 2359/0/3 figures are the correct baseline for THIS worktree's
`Pkg.test()` behavior and are what Plan 19-08 should diff against if it also runs in a fresh
worktree; if 19-08 runs on the main checkout instead, the 2358/1/3 figure remains the right
comparison there.

## Decisions Made

- The plan's literal targeted-verification command for Task 2
  (`julia --project=. -e 'using TestItemRunner; ...'`) does not work standalone under
  `--project=.` — `TestItemRunner` is declared only in `test/Project.toml`, not the root
  `Project.toml`, and is only resolvable inside `Pkg.test()`'s ephemeral sandboxed temp
  environment (confirmed: reproducing the exact command throws
  `ArgumentError: Package TestItemRunner not found in current path`). Verified equivalently with
  a direct `Test.jl` script under `--project=.` asserting the same behavior as
  `test/test_reactive_mode.jl`'s four `@testitem` bodies (Bool/Symbol/ReactiveMode dispatch +
  `ArgumentError` on invalid input) — all assertions passed, and `TSODSO` precompiled cleanly
  with the three new includes and files in place.
- Per explicit orchestrator instruction (issued after the baseline `Pkg.test()` run was measured
  at ~19.5 minutes), did not re-run the full suite a second time to re-confirm Task 2's
  byte-identity claim ("Full suite still matches Task 1's recorded baseline exactly"). Confidence
  instead rests on the change being strictly additive (3 new include lines with zero overlap
  with any existing exported symbol; the two device/certificate stub files are comment-only,
  grep-verified to contain zero `struct`/`function`/`export` tokens; `ReactiveMode` and
  `normalize_reactive_mode` are brand-new names with no ambiguity risk) plus a clean
  precompilation of the full `TSODSO` module. This is a documented, sanctioned deviation from
  the plan's literal acceptance criterion — see "Deviations from Plan" below.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Plan's literal TestItemRunner verify command unusable under `--project=.`**
- **Found during:** Task 2 verification
- **Issue:** The plan's `<verify><automated>` command
  (`julia --project=. -e 'using TestItemRunner; using TSODSO; TestItemRunner.runtests(...)'`)
  fails with `ArgumentError: Package TestItemRunner not found in current path` — confirmed by
  direct reproduction. `TestItemRunner` is a `test/Project.toml`-only dependency, not present in
  the root `Project.toml`, and only resolvable inside `Pkg.test()`'s ephemeral sandboxed temp
  environment (visible in the baseline run's `Status /tmp/jl_.../Project.toml` listing). This
  affects the identical verify-command pattern used across plans 19-01 through 19-08.
- **Fix:** Substituted a direct `Test.jl` script under `--project=.` (no `TestItemRunner`
  needed) asserting the exact same behavioral claims as `test/test_reactive_mode.jl`'s four
  `@testitem` bodies. All assertions passed; `TSODSO` precompiled cleanly.
- **Files modified:** None (verification-only substitution; the plan's target files —
  `test/test_reactive_mode.jl` itself — are written exactly as specified, so the
  `@testitem`-based tests remain in place for TestItemRunner to discover during any future
  `Pkg.test()` run; only the AD-HOC targeted-verification command used during this execution
  session was substituted).
- **Verification:** `julia --project=. -e '... 10 @test/@test_throws assertions ...'` printed
  `ALL_REACTIVE_MODE_CHECKS_PASSED`; `TSODSO` precompiled with 0 warnings/errors.
- **Committed in:** N/A (verification-only; no additional commit needed — Task 2's `6a79a93`
  already contains the correctly-written `test/test_reactive_mode.jl`)

---

**Total deviations:** 1 auto-fixed (1 blocking — verification tooling substitution)
**Impact on plan:** No scope creep; no src/ or test/ file content differs from what the plan
specified. Only the ad-hoc command used to interactively verify Task 2 during this execution
session differs from the plan's literal `<verify>` text; `test/test_reactive_mode.jl` itself is
written exactly per plan and will run correctly under `TestItemRunner` in any future
`Pkg.test()` invocation. Flagging this tooling gap for the plan-checker/planner on plans
19-02 through 19-08, which reuse the identical broken invocation pattern.

## Issues Encountered

- The full `julia --project=. -e 'import Pkg; Pkg.test()'` baseline run took 19m28.9s — much
  longer than typical iterative dev cycles. Per orchestrator guidance, subsequent Phase-19 plans
  should prefer targeted verification (direct `Test.jl` scripts under `--project=.`, or a
  corrected `TestItemRunner` invocation once the tooling gap above is resolved) rather than
  re-running the full suite for every task-level check.
- DrWatson's `tagsave`/`gitpatch` emitted many benign `git diff`/`gitpatch` "Not a git
  repository" and `ProcessFailedException` warnings during the baseline run (worktree
  `--git-dir`/`--work-tree` layout interacting with DrWatson's provenance-stamping helpers).
  These are pre-existing, non-fatal warnings (the baseline's 0-fail/3-broken result already
  accounts for them) — not a regression from this plan, not investigated further (out of scope
  for a read-only Task 1).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plans 19-02 (FourQuadBESS device) and 19-03 (DsoOpt reactive-consensus promotion) can now
  proceed in the same wave: both fill file CONTENT into a location already wired into
  `src/TSODSO.jl`, with zero `files_modified` overlap on this shared assembly file.
- `ReactiveMode`/`normalize_reactive_mode` is ready for plans 19-03/19-06/19-07 to consume as
  the single source of truth for the OFF/CERTIFIED/LIVE distinction.
- Plan 19-08's final byte-identity diff has its baseline: **2359 pass / 0 fail / 3 broken / 2362
  total** (this worktree) — or **2358 pass / 1 fail / 3 broken** if 19-08 instead runs against
  the main checkout's `Project.toml`/`Manifest.toml` drift state (see Baseline Reconciliation).
- Flag for the planner/plan-checker: the `julia --project=. -e 'using TestItemRunner; ...'`
  targeted-verification pattern used in plans 19-01 through 19-08's `<verify>` blocks does not
  work standalone; either add `TestItemRunner`/`TestItems` as root `[extras]`/weak test deps
  resolvable under `--project=.`, or switch the pattern to `Pkg.test()` with a runtime filter
  argument, or document the direct-`Test.jl` substitution as the sanctioned targeted-verify
  pattern project-wide.

---
*Phase: 19-4q-bess-live-reactive-dual-ascent*
*Completed: 2026-08-08*
