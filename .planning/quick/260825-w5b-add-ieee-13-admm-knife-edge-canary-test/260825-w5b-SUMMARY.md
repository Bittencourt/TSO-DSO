---
quick_id: 260825-w5b
subsystem: testing
tags: [julia, admm, socp, clarabel, testitem, numerical-conditioning, canary]

# Dependency graph
requires:
  - phase: .planning/debug/resolved/ieee13-admm-numerical-error.md
    provides: root cause, fix (RESET-01), and the 4 known-good welfare references this
      canary pins against
provides:
  - test/test_admm_knifeedge_canary.jl — a new, always-on @testitem in the default suite
    that pins the IEEE-13 ADMM mid-loop knife-edge trajectory (iters==58, welfare within
    rtol=1e-6) and reports (never asserts on) whether the conditioning ladder fired
  - closes carry-over backlog item C4
affects: [future-touches-of-src/admm/DsoOpt.jl, future-touches-of-src/planning/retry.jl,
  future-Julia-patch-bumps, future-additive-src-changes-that-perturb-codegen]

tech-stack:
  added: []
  patterns:
    - "Logging.SimpleLogger(buf, Warn) + with_logger(...) do ... end + count(needle,
      String(take!(buf))) to capture and count a specific @warn message from test code,
      without needing a custom AbstractLogger subtype (unverified legality of `struct`
      definitions inside a @testitem-generated module) or any src/ API surface change"
    - "pin a numerically-marginal solve's OUTCOME (iteration count + welfare, tight
      rtol) rather than its qualitative convergence, when 'did it converge' has already
      been shown to be true on every measured toolchain and therefore uninformative"

key-files:
  created:
    - test/test_admm_knifeedge_canary.jl
  modified: []

key-decisions:
  - "Reused the EXACT same Phase8Fixtures admm scenario EXP-01/INFRA-04 already
    exercise (one more ADMM solve added to the suite's runtime, not a second expensive
    fixture class), per the plan's explicit instruction not to duplicate fixture
    classes."
  - "No src/ change to wire attempts_out through solve_admm's public surface — the plan
    identified this gap and deliberately scoped it out as separable work with its own
    review surface; the header comment states this finding verbatim so a future reader
    doesn't re-derive it."
  - "Dropped JULIA_LOAD_PATH=\"$PWD/test:$PWD:@stdlib\" from the Task B verification
    invocation (kept only --project=.). MEASURED that including test/ on the load path
    stacks test/Project.toml's environment ahead of the main one, reintroducing the
    exact PrecompileTools/StaticData UndefVarError the debug doc documents for
    test/Manifest.toml on Julia 1.10/1.11 — even though this run never touches
    TestItemRunner. Without it, both toolchains ran cleanly, matching the debug doc's
    own successful `julia +1.10 --project=. probe.jl` recipe."

requirements-completed: []

duration: ~40min
completed: 2026-08-26
---

# Quick Task 260825-w5b: IEEE-13 ADMM knife-edge canary test Summary

**Added `test/test_admm_knifeedge_canary.jl`, a single always-on `@testitem` that pins the IEEE-13 ADMM mid-loop SOCP's converged trajectory (`iters == 58`, `welfare ≈ -4822.903616694139` at `rtol = 1e-6`) on the same `Phase8Fixtures` scenario EXP-01/INFRA-04 already exercise, and reports — but never asserts on — the conditioning-ladder escalation count captured via `Logging.SimpleLogger`; verified in a disposable detached worktree to pass on both measured sides of the knife-edge (Julia 1.10 ladder-rescued, escalations=1; Julia 1.12 native convergence, escalations=0) and to fail loudly with a propagated `NUMERICAL_ERROR` when the ladder wiring is reverted.**

## Performance

- **Duration:** ~40 min
- **Completed:** 2026-08-26
- **Tasks:** 2 of 2 completed as planned (Task A: write; Task B: verify both sides + regression A/B)
- **Files modified:** 1 created (committed), 0 `src/` changes

## Accomplishments

- Wrote `test/test_admm_knifeedge_canary.jl`: one `@testitem` named with the
  `(canary, admm)` filter substring (mirroring `test_admm_adaptive.jl`'s
  `(adaptive, rho)`/`(transit, dso)` convention), `setup = [Phase8Fixtures]`,
  `tags = [:admm, :canary]`.
- Header comment (plain `#` lines, no docstring — avoids this JuliaFormatter version's
  wrapped-`|` data-loss hazard) summarizes the knife-edge finding, states plainly that a
  bare "did it converge" assertion is no longer informative since the production fix
  converges on every toolchain tested, restates the `attempts_out`-does-not-reach-the-
  public-surface finding verbatim, and cross-references
  `.planning/debug/resolved/ieee13-admm-numerical-error.md`.
- Body captures ladder-escalation `@warn` text with a plain `Logging.SimpleLogger`
  (`buf = IOBuffer()`, `with_logger(SimpleLogger(buf, Warn)) do ... end`), counts
  `"escalating conditioning"` occurrences, and unconditionally `@info`-logs
  `iters`/`welfare`/`escalations` before any assertion runs — the "make a future flip
  attributable" mechanism.
- PINNED: `@test r.iters == 58` and
  `@test isapprox(r.welfare, -4822.903616694139; rtol = 1e-6, atol = 1e-3)`, each with
  an inline comment pointing at the resolved debug doc and explaining the ~500x
  headroom over the measured ~1.86e-9 cross-environment spread.
  Deliberately NO assertion on `escalations` — a trailing comment states this is a
  legitimate, already-documented environment difference.
- Verified JuliaFormatter-clean under the pinned 2.10.x scratch env
  (`format(...; overwrite=false)` returned `true` — no reformatting needed) and that
  `julia --project=. -e 'using TSODSO'` still loads cleanly.
- **Task B, step-by-step, in a disposable `git worktree add <scratchpad>/wt-canary HEAD
  --detach`** (never the working tree):
  - Built a minimal `@testmodule`/`@testitem` macro shim (per the debug doc's own
    validated recipe) that splices the real test file's body verbatim, including
    `Phase8Fixtures` via `import Main: Phase8Fixtures`.
  - **Julia 1.10.11** (ladder-rescued side): `iters=58`,
    `welfare=-4822.90361661042` (1.7e-11 relative from the pinned reference, well inside
    `rtol=1e-6`), `escalations=1` — matches the debug doc's "EXACTLY ONE escalation
    warning" measurement on this exact toolchain. No exception; both `@test`s passed.
  - **Julia 1.12.7** (native-convergence side): `iters=58`,
    `welfare=-4822.903625595291` (bit-identical to the debug doc's own 1.12.7
    reference), `escalations=0`. No exception; both `@test`s passed.
  - **Regression A/B**: in the SAME throwaway worktree, replaced
    `solve_with_retry!(dso.model; dual = false, allow_almost = true)` with the pre-fix
    bare `assert_solved!(dso.model; dual = false, allow_almost = true)` in
    `src/admm/DsoOpt.jl` (never touching the real working tree). Re-ran the Julia 1.10
    script: it THREW `Solve failed — refusing to trust results: termination_status :
    NUMERICAL_ERROR`, propagating out of the `@testitem` body as an uncaught error
    (exit code 1) — the canary goes LOUD, not silently green, when the ladder wiring
    regresses.
  - Discarded the worktree entirely (`git worktree remove --force`); confirmed
    `git status --short` on the real tree shows no trace of the throwaway edit.

## Task Commits

1. **Task A: write the canary test** — `2648dfb` (test)
2. **Task B: prove the canary works on both sides + catches a regression** —
   verification only, no commit (per plan; runs entirely in a disposable detached
   worktree at `<scratchpad>/wt-canary`, removed after use; logs captured at
   `<scratchpad>/run_1.10.log`, `<scratchpad>/run_1.12.log`,
   `<scratchpad>/run_1.10_regression.log`)

## Files Created/Modified

- `test/test_admm_knifeedge_canary.jl` — new file, one `@testitem`, pins
  `iters == 58` and `welfare ≈ -4822.903616694139` (rtol=1e-6) on the
  `Phase8Fixtures` admm scenario; reports (never asserts on) ladder-escalation count.

## Decisions Made

See `key-decisions` in frontmatter. Most consequential: dropping `JULIA_LOAD_PATH` from
the Task B verification invocation after it was measured to reintroduce the exact
`test/Manifest.toml`-on-1.10/1.11 incompatibility this shim exists to sidestep, even
though the shim never invokes TestItemRunner — `--project=.` alone (matching the debug
doc's own successful `probe.jl` recipe) was sufficient and correct.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug in verification approach] `JULIA_LOAD_PATH` as literally specified broke both toolchains**
- **Found during:** Task B, step 3 (first Julia 1.10 shim run)
- **Issue:** Running the shim with
  `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib" julia +1.10 --project=. shim.jl` (exactly as
  the plan's literal recipe specifies) failed with
  `UndefVarError: StaticData not defined` from `PrecompileTools` — the identical
  signature the resolved debug doc attributes to `test/Manifest.toml` resolving only on
  Julia 1.12. Root cause: stacking `test/` onto `JULIA_LOAD_PATH` makes Julia consider
  `test/Project.toml`'s environment (and its incompatible `test/Manifest.toml`) during
  package resolution, even though the shim script never imports `TestItemRunner` or
  activates that project directly.
- **Fix:** Dropped `JULIA_LOAD_PATH` entirely; ran
  `julia +<version> --project=. <script> <worktree-root>` (worktree root passed as an
  explicit `ARGS[1]` so the script's `include(joinpath(...))` calls don't depend on
  relative-include-from-cwd semantics either). This matches the debug doc's own
  successful `probe.jl` invocation form.
- **Files modified:** none in the repo — only the throwaway
  `<scratchpad>/shim_canary.jl` verification script.
- **Verification:** both Julia 1.10 and Julia 1.12 runs completed cleanly after the
  change, with the exact `iters`/`welfare`/`escalations` values reported above.
- **Committed in:** not applicable (verification-only artifact; the finding is recorded
  here and in this SUMMARY's key-decisions since no `src/` or `test/` file needed
  changing).

---

**Total deviations:** 1 auto-fixed (Rule 1, verification methodology only — no
committed test file or `src/` logic changed by this deviation).
**Impact on plan:** None on the shipped canary. The deviation only corrected HOW the
Task B verification was invoked; the plan's own literal recipe text should be read as
"if `JULIA_LOAD_PATH` inclusion of `test/` breaks the run with the `StaticData` error,
drop it" for any future re-run of this verification.

## Issues Encountered

None beyond the `JULIA_LOAD_PATH` verification-methodology correction above. The canary
itself required no `src/` changes and no weakening of any existing assertion.

## Known Stubs

None — this task adds a test file only; no UI or data-rendering surface was touched.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes.
This task adds a regression test that reads an existing public API
(`TSODSO.run_scenario`) and a `Logging.SimpleLogger`-captured warning stream; no new
attack surface.

## Self-Check: PASSED

- `test/test_admm_knifeedge_canary.jl` exists at the committed path (verified via
  `git show --stat HEAD`).
- Commit `2648dfb` exists: `git log --oneline -1 -- test/test_admm_knifeedge_canary.jl`
  → `2648dfb test(quick-260825-w5b): add IEEE-13 ADMM knife-edge canary`.
- `julia --project=<jf210> -e 'using JuliaFormatter; println(format(path;
  overwrite=false))'` → `true`.
- `python3 .github/scripts/check_content_loss.py HEAD` → `OK: no content change
  (whitespace/commas only)`.
- `julia --project=. -e 'using TSODSO'` → loads cleanly (`LOAD OK`).
- Julia 1.10.11, disposable worktree: no exception, `iters=58`,
  `welfare=-4822.90361661042`, `escalations=1`.
- Julia 1.12.7, disposable worktree: no exception, `iters=58`,
  `welfare=-4822.903625595291`, `escalations=0`.
- Regression A/B (ladder wiring reverted, throwaway edit, same disposable worktree):
  Julia 1.10 run threw `NUMERICAL_ERROR`, exit code 1 — canary fails loudly as
  designed.
- Worktree removed (`git worktree remove --force`); `git status --short` on the real
  working tree shows no trace of the throwaway `src/admm/DsoOpt.jl` edit.

## Next Phase Readiness

- No blockers. Carry-over backlog item C4 ("knife-edge canary: assert IEEE-13 ADMM
  converges with recorded iters/welfare...") is now CLOSED.
- The canary is live in the default suite (`test/runtests.jl`'s bare
  `@run_package_tests`, no tag-based filtering exists) and will run on every future CI
  invocation; a future codegen-level or Julia-patch-level flip will now fail this named
  test with the measured `iters`/`welfare`/`escalations` in the log, instead of
  resurfacing as an unattributed mystery flake.

---
*Quick task: 260825-w5b*
*Completed: 2026-08-26*
