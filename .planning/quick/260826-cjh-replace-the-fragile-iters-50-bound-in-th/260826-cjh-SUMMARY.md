---
quick_id: 260826-cjh
subsystem: testing
tags: [julia, testitemrunner, benders, planning-hardening, flaky-test, iteration-bound]

# Dependency graph
requires:
  - phase: test/test_planning_hardening.jl (Task 1 revision 1, plan 12-02)
    provides: the T=8 load-test fixture and its ">=50 Benders iterations" item this
      task revises
provides:
  - test/test_planning_hardening.jl's load-test @testitem now asserts a structural
    `result.iters >= 30` floor instead of the environment-fragile `>= 50`, with the
    measured cross-environment spread (66/55/55/47) and the T=1 trivial floor (16)
    recorded inline so a future contributor does not re-pin a tight bound
  - closes the CI failure from run 32950768236 (Julia 1.11, result.iters == 47)
affects: [future-touches-of-test/test_planning_hardening.jl, future-CI-runs-on-any-
  Julia-1.1x-toolchain-that-schedules-TestItemRunner-workers-differently]

tech-stack:
  added: []
  patterns:
    - "assert a load test's INTENT (many rounds of an N-dimensional cutting-plane
      epigraph) via a structural floor derived from two independently-measured
      anchors (a trivial-convergence floor and a min-observed value), rather than a
      tight empirically-tuned iteration count that sits inside a toolchain-dependent
      spread"
    - "record the full measured cross-environment spread as an inline comment
      alongside the assertion it justifies, so the arithmetic is auditable without
      re-deriving it"

key-files:
  created: []
  modified:
    - test/test_planning_hardening.jl

key-decisions:
  - "Structural floor of 30, not a re-tuned number close to 47: derived as ~1.9x the
    T=1 fixture's own hard trivial-convergence floor (16) and ~36% below the lowest
    T=8 value ever measured (47) — generous headroom on both sides, per the user's
    locked decision to assert intent rather than chase a tighter empirical bound."
  - "Removed two genuinely vacuous assertions (`total_retries_from_trace >= 0`,
    `all(result.trace.retry_count_trace .>= 0)`) rather than leaving them as
    decorative coverage — both are non-negativity checks on a sum/elements of a
    non-negative counter and can never fail."
  - "Verification used Pkg.test() with a throwaway, worktree-only ENV-var filter
    added to test/runtests.jl, after the plan's prescribed
    `JULIA_LOAD_PATH=\"$PWD/test:$PWD:@stdlib\"` TestItemRunner invocation
    reproduced the exact PrecompileTools/StaticData UndefVarError this session's own
    MEMORY.md documents for that load-path form on Julia 1.11. The runtests.jl edit
    lived only in the disposable `<scratchpad>/hardwt` worktree and was reverted
    after the run; nothing under test/runtests.jl changed in the real tree."

requirements-completed: []

duration: ~35min
completed: 2026-08-26
---

# Quick Task 260826-cjh: Replace the fragile `iters >= 50` bound Summary

**Replaced the environment-fragile `@test result.iters >= 50` in `test/test_planning_hardening.jl`'s T=8 Benders load test with a structural `@test result.iters >= 30` floor (analytically justified against the T=1 trivial-convergence floor of 16 and the measured T=8 cross-environment spread of 47-66), removed two vacuous non-negativity assertions, and renamed the item to drop its now-false "retry machinery active" / ">=50 iterations" claims — verified locally via `Pkg.test()` in a clean Julia 1.11 worktree (12/12 pass, `result.iters = 55`).**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-08-26T09:05Z (approx)
- **Completed:** 2026-08-26T09:20Z (approx)
- **Tasks:** 2 of 2 completed (Task 1: rewrite; Task 2: prove + verify)
- **Files modified:** 1 (`test/test_planning_hardening.jl`)

## Accomplishments

- Rewrote the file-header deviation note's title (`Task 1 (revision 1)` ->
  `Task 1 (revision 2)`) and appended a new `REVISION 2` comment paragraph after
  the existing FIXTURE-SHAPE DEVIATION / FIX / RUNTIME NOTE paragraphs (all three
  left byte-identical), stating: the CI failure verbatim (run 32950768236, Julia
  1.11, `result.iters == 47`), why it is not a regression (zero `src/` changes,
  the file itself unchanged, only test-suite membership shifted TestItemRunner's
  worker scheduling), the 4-row measured spread (66/55/55/47), and the structural
  derivation of the new floor (30 = ~1.9x the T=1 trivial floor of 16, ~36% below
  the min-observed 47).
- Renamed the `@testitem` string from `"planning hardening: load test — >=50
  Benders iterations, retry + checkpoint machinery active, empirical retry-rate
  measurement"` to `"planning hardening: load test — T=8 multi-iteration Benders
  run (measured 47-66 iters across environments), checkpoint machinery exercised
  at scale, retry-trace/log cross-check (load, benders)"`. `grep -rn` confirmed no
  other tracked, non-archived file referenced the old name string (the only other
  hit was the historical `.planning/milestones/v2.0-phases/.../12-02-PLAN.md`,
  correctly left untouched).
- Removed `@test total_retries_from_trace >= 0` and `@test
  all(result.trace.retry_count_trace .>= 0)`, replacing them with a removal
  comment citing the precedent (`test_planning_certification_integer.jl` commit
  `d53db27`). The one real cross-check, `@test total_retries_from_trace ==
  n_retry_warnings`, is untouched.
- Replaced `@test result.iters >= 50` with `@test result.iters >= 30`, preceded by
  a short pointer comment back to the REVISION 2 note. `@test result.gap <= tol`
  and `@test result.iters < 200` are byte-identical to before.
- Left every line from the cut-store growth instrumentation through the final
  `@test length(checkpoint_files) == result.iters` — including `k_check = min(50,
  result.iters)` (an unrelated fixed checkpoint-sampling index, not the assertion
  being replaced) — completely untouched.
- Confirmed format-clean under the pinned JuliaFormatter 2.10.2 scratch env
  (`format(path; overwrite=false)` returned `true` — no reformatting needed) and
  that the file parses cleanly.
- Confirmed no wrapped comment line begins with `|` (the JuliaFormatter 2.10.2
  docstring-data-loss hazard documented in STATE.md's Standing Hazard section).

## Task Commits

1. **Task 1: rewrite header note, assertion block, and item name** — `c2b95a6`
   (fix)

**Plan metadata:** not committed by this executor (SUMMARY.md/STATE.md handled by
the quick-task orchestrator per `<constraints>`).

## Files Created/Modified

- `test/test_planning_hardening.jl` — renamed `@testitem` string; rewrote the
  file-header deviation note's title and appended a REVISION 2 paragraph
  documenting the measured spread and floor justification; removed two vacuous
  assertions with an honest removal comment; replaced `>=50` with `>=30` with a
  pointer comment. Every other line in the item (and all four other `@testitem`s
  in the file) is byte-identical to before this task.

## Decisions Made

See `key-decisions` in frontmatter. Most consequential: choosing a structural
floor (30) derived from two independent anchors rather than a re-tuned number
close to the CI-observed 47, per the user's locked decision recorded in the plan's
`<why_this_change>` section.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking, verification methodology only] The plan's prescribed `JULIA_LOAD_PATH` TestItemRunner invocation reproduced a known toolchain trap**
- **Found during:** Task 2, step 4 (local run of the renamed item)
- **Issue:** `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib" julia +1.11 -e 'using
  TestItemRunner, TSODSO; TestItemRunner.run_tests(...)'` in the `<scratchpad>/
  hardwt` worktree failed with `ERROR: LoadError: UndefVarError: StaticData not
  defined in Base` while precompiling `PrecompileTools` — the exact signature this
  session's own MEMORY.md (`gsd-plan-verify-testitemrunner-trap`) attributes to
  stacking `test/`'s `Manifest.toml` onto the load path on Julia 1.10/1.11.
- **Fix:** Fell back to `Pkg.test()` (the harness fallback explicitly sanctioned
  in the plan's `<verification_honesty>` section) inside the same disposable
  worktree, with a throwaway `ENV`-gated filter added to `test/runtests.jl`
  (`GSD_TESTITEM_FILTER` selecting the `(load, benders)` item) so `Pkg.test()`
  did not have to run the full ~14 min suite. This is the plan's own sanctioned
  fallback ("Pkg.test() in a clean worktree ... or a direct script — and SAY
  which you used" — this SUMMARY states Pkg.test() was used).
- **Files modified:** none in the real tree — only
  `<scratchpad>/hardwt/test/runtests.jl` (reverted via `git checkout --` after
  the run) and `<scratchpad>/hardwt/test/test_planning_hardening.jl` (a disposable
  copy of the real edit, used only so the worktree could run the renamed item;
  never committed from that worktree).
- **Verification:** the filtered `Pkg.test()` run completed cleanly: 12/12 pass,
  `result.iters = 55`, no `Test Failed` lines, exit via `Testing TSODSO tests
  passed`.
- **Committed in:** not applicable (verification-only artifact; the throwaway
  worktree edit was reverted, never committed).

---

**Total deviations:** 1 auto-fixed (Rule 3, verification methodology only — no
committed test file or `src/` logic changed by this deviation).
**Impact on plan:** None on the shipped test-file edit. The deviation only
corrected HOW Task 2's local verification run was invoked, exactly as the plan's
own `<verification_honesty>` section anticipated as a possible outcome.

## Issues Encountered

None beyond the `JULIA_LOAD_PATH` verification-methodology correction above.

## Analytic Proof (the load-bearing evidence — Task 2, action step 3)

The new floor `result.iters >= 30` against the full measured set `{47, 55, 55,
66}`:

| Measured `result.iters` | `>= 30`? | Headroom |
|---|---|---|
| 47 (CI Julia 1.11, run 32950768236 — the value that FAILED the old `>=50` bound) | true | 17 |
| 55 (local Julia 1.11.9, worktree run 1) | true | 25 |
| 55 (local Julia 1.11.9, worktree run 2) | true | 25 |
| 66 (the value that originally tuned T=8) | true | 36 |

Headroom ranges 17 to 36 iterations across every real measurement — unlike the old
`>=50` bound, whose margin over the CI-observed 47 was negative (it FAILED).

For the regression class the floor exists to catch — a hypothetical bug that made
this T=8 problem converge trivially, the way the T=1 fixture converges in exactly
16 iterations — a 3-iteration collapse trips the new floor immediately: `3 >= 30`
is `false`. So the floor separates every real measurement (47-66, all comfortably
above 30) from the trivial-convergence failure mode (a handful of iterations, well
below 30) it exists to guard against.

**Which assertion catches a genuine regression:** `@test result.iters >= 30` is
the one that fires directly on a trivial-convergence collapse. The other
assertions in the item (`gap <= tol`, `iters < 200`, the retry cross-check, cut-
store monotonicity, the checkpoint round-trip) are either unrelated to iteration
COUNT or scale relative to `result.iters` itself (e.g. `k_check = min(50,
result.iters)`), so they would not independently flag a "converges too fast"
regression the way the floor does.

**The two removed assertions were provably vacuous:** `total_retries_from_trace
>= 0` is `sum(result.trace.retry_count_trace) >= 0` — a sum of a non-negative
`Vector{Int}` (a per-iteration retry-attempt counter) can never be negative.
`all(result.trace.retry_count_trace .>= 0)` is the elementwise version of the same
fact. Neither can ever fail regardless of what the Benders loop does, so neither
carried real coverage; nothing with real content was removed alongside them — the
one genuine cross-check in that block (`total_retries_from_trace ==
n_retry_warnings`, comparing the trace-derived count against an independently
captured log-message count) survives unchanged.

## Local Run Result (expected-but-insufficient evidence, per `<verification_honesty>`)

Local Julia 1.11.9 (via `Pkg.test()`, filtered to the renamed item, in the
disposable `<scratchpad>/hardwt` worktree): 12/12 tests passed,
`result.iters = 55`, `total_retries_from_trace = 0`, `n_retry_warnings = 0` (the
retry ladder never fires on this fixture, consistent with the item's renamed
claim). This PASSES trivially since 55 is well inside this machine's previously
measured range — it does **not** by itself prove the fix holds at the
CI-measured value of 47, since 47 has never been locally reproducible. The
analytic argument above (Task 2 action step 3) is what establishes the fix holds
across the full measured spread, including 47.

## Known Stubs

None — this task edits test assertions and comments only; no UI or
data-rendering surface touched.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema
changes. This task loosens/tightens assertions inside an existing test file only.

## Self-Check: PASSED

- `test/test_planning_hardening.jl` modified as described (verified via `git show
  --stat HEAD` after commit `c2b95a6`).
- Commit `c2b95a6` exists: `git log --oneline -1 -- test/test_planning_hardening.jl`
  -> `c2b95a6 fix(quick-260826-cjh): replace fragile iters>=50 bound with
  intent-shaped floor`.
- `julia -e 'Meta.parseall(...)'` -> `PARSE OK`.
- `julia --project=<jf210> -e 'using JuliaFormatter; println(format(path;
  overwrite=false))'` -> `true`.
- `grep -c "result.iters >= 30"` (the new `@test` assertion) present exactly once
  as an active assertion; `grep -c "result.iters >= 50"` -> `0` new occurrences
  (the sole remaining hit, line 173, is the pre-existing, deliberately-untouched
  FIXTURE-SHAPE DEVIATION paragraph the plan explicitly required to survive
  verbatim).
- `grep -c "total_retries_from_trace >= 0"` -> `0`; the vacuous elementwise
  assertion text survives only inside the new removal-explanation comment, not as
  an active `@test`.
- `git diff --diff-filter=D --name-only HEAD~1 HEAD` -> empty (no deletions).
- `python3 .github/scripts/check_content_loss.py HEAD` -> exactly one file
  (`test/test_planning_hardening.jl`), positive char delta (`+2684`), consistent
  with the new REVISION 2 comment paragraph and removal-comment additions.
- Local `Pkg.test()` run (filtered, disposable worktree, Julia 1.11.9): 12/12
  pass, `result.iters = 55`, no `Test Failed` lines, `Testing TSODSO tests
  passed`.
- Disposable worktree's throwaway `test/runtests.jl` edit reverted (`git checkout
  --`); `git status --short` on the real working tree shows only the pre-existing
  `Manifest-v1.12.toml`/`Project.toml` drift and this task's own `.planning/`
  artifacts — no trace of the worktree-only filter edit.

## Next Phase Readiness

- No blockers. The item is renamed, the fragile bound is retired, and the
  measured cross-environment spread is recorded inline for any future
  contributor who touches this file.
- A future CI failure on this item (should the Benders trajectory ever collapse
  to a handful of iterations) will now be a real regression signal, not another
  instance of the same environment-scheduling sensitivity that caused run
  32950768236's false alarm.

---
*Quick task: 260826-cjh*
*Completed: 2026-08-26*
