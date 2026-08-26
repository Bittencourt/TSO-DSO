---
quick_id: 260826-cjh
description: Replace the environment-fragile result.iters >= 50 bound in the planning-hardening load test with intent-shaped assertions, and correct the item's now-false name
date: 2026-08-26
mode: quick
---

# Quick Task 260826-cjh: Replace the fragile `iters >= 50` bound in the planning-hardening load test

## Why

CI run 32950768236 failed on Julia 1.11 ONLY:

    planning hardening: load test ...
      Expression: result.iters >= 50
       Evaluated: 47 >= 50

Everything else passed (30155 passed, 1 failed). This is NOT a regression from recent work:
between the last all-green commit and the failing one there are ZERO `src/` changes, and
`test/test_planning_hardening.jl` itself was never touched between them — only test-suite
MEMBERSHIP changed (one item deleted, one added elsewhere), which shifted TestItemRunner's worker
scheduling and, with it, the Benders cutting-plane trajectory, even though nothing about the model
changed.

MEASURED spread of `result.iters` for this byte-identical T=8 fixture:

    66   the value the item's own header note tuned T=8 to reach ("comfortably inside 50:100")
    55   local Julia 1.11.9, clean detached worktree, run 1 -- whole suite PASSED
    55   local Julia 1.11.9, clean detached worktree, run 2 -- whole suite PASSED
    47   the CI 1.11 runner (32950768236) -- FAILED
    16   the ORIGINAL T=1 fixture's hard, bit-exact TRIVIAL-convergence floor, documented in the
         item's own header note, that never moves no matter how many iterations run (superlinear
         1-D Kelley cutting-plane convergence)

So: deterministic WITHIN one environment, but ranging 47..66 ACROSS environments, with the old
threshold of 50 sitting inside that spread (~10% margin on a quantity that itself moves ~30%). The
CI failure is NOT locally reproducible (this machine's Julia 1.11 always yields 55), so it cannot
be "fixed" by iterating locally until a number passes.

USER DECISION, LOCKED: assert the load test's INTENT directly (many rounds of an 8-dimensional
cutting-plane epigraph, never a trivial 1-3-round convergence), rather than using a tight iteration
count as a proxy. Do NOT simply lower the threshold to a new tuned magic number close to 47, and do
NOT re-tune the T=8 fixture shape.

The item's audited assertion block also has two genuinely VACUOUS assertions (`@test
total_retries_from_trace >= 0` and `@test all(result.trace.retry_count_trace .>= 0)` — both
non-negativity checks on a sum/elements of a non-negative counter, which can never fail) and a now
partly-FALSE name ("retry ... machinery active" — measured `total_retries_from_trace == 0` on this
fixture; the retry ladder never fires here). Both are fixed in the same edit.

## Context

- `test/test_planning_hardening.jl` — THE target file, unique scope. The item under repair starts
  at line 206 (`@testitem "planning hardening: load test — >=50 Benders iterations, ..."`); its
  file-header deviation note spans roughly lines 152-205 (documents the T=1 -> T=8 fixture tuning
  the ">=50" requirement drove); the assertion block to edit is roughly lines 245-263, followed by
  the cut-store/checkpoint assertions at roughly lines 265-289 which stay untouched.
- `test/test_run_stochastic.jl` (read-only precedent) — commit `ff8f71f`'s D-11 golden fix shows
  this repo's house style for a "measured tolerance, with the cross-environment measurement table
  recorded inline in a comment" fix — the same shape this task applies to an iteration-count bound
  instead of a `rtol`.
- `test/test_admm_knifeedge_canary.jl` (read-only precedent) — commit `2648dfb`'s shape for "hard
  assert the stable invariants, only REPORT the environment-dependent quantity" (there: pin
  `iters == 58` and the welfare value across every environment measured, but deliberately do NOT
  assert on `escalations`, only `@info` it). This task's item already has an unconditional `@info
  ... result.iters` line (kept as-is) — the analogous "report loudly" half is already present;
  this task only needs to fix the "assert" half.
- `test/test_planning_certification_integer.jl` (read-only precedent, commit `d53db27`) — this
  session's own precedent for removing a genuinely vacuous gate with an honest removal comment,
  which the retry-count fix in this task mirrors.
- `.github/scripts/check_content_loss.py` — compares tracked `.jl` files against a git ref,
  ignoring whitespace/commas, to catch content the JuliaFormatter pass silently drops. Usage:
  `python3 .github/scripts/check_content_loss.py <ref>`. Against a PRE-EDIT ref it will also flag
  this task's own deliberate additions (new comment prose, the renamed item, the removed
  assertions) as "content changed" — that is expected, not evidence of loss. Task 2 below uses it
  correctly: isolate the formatter PASS itself (post-manual-edit vs post-format), not the manual
  edit.

## Scope

Only `test/test_planning_hardening.jl` changes. No `src/` changes — there is no product defect
here. Do not touch the fixture shape (T=8, `α_op_lb=-50.0`, `λ₀`, `c_op`, `tol=1e-6`, `max_iter`,
etc.) or any of the four other `@testitem`s in this file — re-tuning the fixture was explicitly
rejected. Do not weaken `@test result.gap <= tol`, `@test result.iters < 200`, the retry
trace/log cross-check, the cut-store monotonicity/length checks, or the checkpoint round-trip /
resume / checkpoint-file-count checks (lines ~265-289) — all of these are already environment-
independent (relative to `result.iters`, not a magic constant) and must survive byte-for-byte
except where this task's own diff explicitly touches them.

## Tasks

### Task 1 — Rewrite the load-test item's header note, assertion block, and name

- **files:** `test/test_planning_hardening.jl`
- **action:**
  1. Read the whole file first (it is ~290 lines, one pass is enough) to confirm current line
     numbers before editing, since the numbers below are from the pre-edit file and any earlier
     edit in this same task shifts them.
  2. In the file-header deviation note's title line (currently reading `# Task 1 (revision 1):
     load test — >=50-iteration Benders run, retry/checkpoint` / `# machinery active, empirical
     retry-rate measurement.`), change the label to `Task 1 (revision 2)` and rewrite the
     one-line description to no longer claim `>=50-iteration` or `retry ... machinery active` —
     state instead that this is a T=8 multi-iteration Benders load test with checkpoint machinery
     exercised at scale and a retry-trace/log cross-check, and add one sentence noting that the
     prior revision's `>=50 iterations` framing and `retry ... machinery active` claim are both
     retired below, with a pointer ("see the REVISION 2 note after the FIX/RUNTIME NOTE
     paragraphs").
  3. Leave the existing "FIXTURE-SHAPE DEVIATION" paragraph, the "FIX" paragraph (the T=1->T=8
     derivation, the `α_op_lb` correctness argument, the closed-form `z*=1.4` re-derivation), and
     the "RUNTIME NOTE" paragraph (`:slow` tag rationale) completely UNTOUCHED — all three are
     still-valid history of why T=8 was chosen and why tightening `tol` alone cannot work; only
     the title line above them changes.
  4. Immediately after the existing RUNTIME NOTE paragraph and before the `@testitem` line, insert
     a new comment paragraph headed `REVISION 2 (this quick task, 260826-cjh):` that:
     - States that the `result.iters >= 50` assertion and this item's name were both retired as
       environment-fragile, and states the CI failure verbatim: CI run 32950768236 failed on
       Julia 1.11 with `result.iters == 47` on this byte-identical T=8 fixture, and that this is
       NOT a regression (zero `src/` changes and this file itself unchanged between the last
       green commit and the failing one; only test-suite membership shifted TestItemRunner's
       worker scheduling and, with it, the Benders trajectory).
     - Records the measured `result.iters` spread as a 4-row list, reusing exactly the wording and
       numbers from this plan's Why section: 66 (the value that originally tuned T=8, "comfortably
       inside 50:100"), 55 (local Julia 1.11.9, clean detached worktree, run 1, suite PASSED), 55
       (same, run 2, suite PASSED), 47 (CI Julia 1.11 runner 32950768236, FAILED against the old
       `>=50` bound).
     - States the conclusion: deterministic within one environment, ranging 47..66 across
       environments, the old threshold of 50 sat inside that spread (~10% margin on a quantity
       that itself moves ~30%); the CI failure is not locally reproducible (this machine's Julia
       1.11 always yields 55), so it could not be fixed by iterating locally; states the locked
       user decision to assert intent rather than a tight count, and not to re-tune to a new magic
       number close to 47.
     - Justifies the replacement floor (`result.iters >= 30`, used in step 6 below) as a
       STRUCTURAL threshold, not a re-tuned one: derive and state the two ratios explicitly —
       30 is ~1.9x the T=1 fixture's hard trivial-convergence floor of 16 (documented in the
       FIXTURE-SHAPE DEVIATION paragraph above), and ~36% below the lowest `result.iters` ever
       measured for T=8 (47) — i.e. generous headroom in both directions, unlike the old bound's
       ~10% margin. State explicitly that this floor would still catch the regression class this
       task is guarding against: a hypothetical bug that made this T=8 problem converge trivially
       (e.g. in 3 iterations, the way the T=1 fixture converges in 16) trips it immediately
       (`3 < 30`), and that no environment measured to date (47..66) comes anywhere close to
       tripping it.
     - States that the item's name was corrected because the old name's "retry ... machinery
       active" clause was false — `total_retries_from_trace` measures `0` on this fixture every
       time (the retry ladder never fires here) — so the new name no longer claims otherwise.
  5. Rename the `@testitem` string itself (currently `"planning hardening: load test — >=50
     Benders iterations, retry + checkpoint machinery active, empirical retry-rate measurement"`)
     to: `"planning hardening: load test — T=8 multi-iteration Benders run (measured 47-66 iters
     across environments), checkpoint machinery exercised at scale, retry-trace/log cross-check
     (load, benders)"`. Keep the item's `tags = [:planning, :slow]` and `setup = [Phase6Fixtures,
     ToyDeviceFixture]` exactly as-is. Before renaming, `grep -rn "load test — >=50 Benders
     iterations" test/ src/ docs/ .github/` to confirm nothing else in currently-tracked, non-
     archived files references the old name by string (expected: no matches outside this file
     itself and the already-archived `.planning/milestones/` plan doc, which is historical record
     and must not be edited).
  6. Leave the item's body completely unchanged from `T = 8` through the `@info "planning
     hardening load test: empirical retry rate" ...` line (i.e. everything up through and
     including the existing `@test total_retries_from_trace == n_retry_warnings` line stays
     byte-identical — this is the one real cross-check in the retry block and must survive
     verbatim). Immediately after that `@test`, replace the next two lines (`@test
     total_retries_from_trace >= 0` and `@test all(result.trace.retry_count_trace .>= 0)`) with a
     comment (no assertion) stating: these two were REMOVED this revision as VACUOUS — both are
     non-negativity checks on a sum/elements of a non-negative counter vector and can never fail;
     they looked like coverage but asserted nothing; precedent for the same removal pattern is
     `test_planning_certification_integer.jl` commit `d53db27`.
  7. Leave `@test result.gap <= tol` and `@test result.iters < 200` (with its existing "converged
     comfortably before the fail-loud cap" comment) exactly as-is.
  8. Replace the line `@test result.iters >= 50` with `@test result.iters >= 30`, preceded by a
     short comment (not a repeat of the full REVISION 2 rationale — just a pointer) stating this
     replaces the old `>=50` bound and pointing back at the REVISION 2 note above the `@testitem`
     for the full measured-spread rationale and the 30 = ~1.9x-trivial / ~36%-below-min-observed
     justification.
  9. Leave every line from the "cut-store growth instrumentation" comment through the end of the
     item (`@test all(diff(result.trace.n_cuts_trace) .>= 0)` through the final `@test
     length(checkpoint_files) == result.iters`) completely untouched, including `k_check = min(50,
     result.iters)` — that `50` is an unrelated fixed checkpoint-sampling index (already correctly
     guarded via `min`), not the assertion this task is replacing.
  10. Format-check: run `julia --project=. -e 'using JuliaFormatter; println(format(
      "test/test_planning_hardening.jl"; overwrite=false))'`. If it prints `false`, apply
      `overwrite=true` once, then re-run the check to confirm it now prints `true`. Never let a
      wrapped comment line begin with `|` (JuliaFormatter 2.10.2 silently deletes such text) — the
      new prose in steps 4/6/8 must not produce one; check visually after formatting.
- **verify:**
  - Syntax parses: `julia -e 'ex = Meta.parseall(read("test/test_planning_hardening.jl", String));
    bad = any(a isa Expr && a.head === :error for a in ex.args); println(bad ? "PARSE ERROR" :
    "PARSE OK")'` prints `PARSE OK`.
  - `grep -c "result.iters >= 50" test/test_planning_hardening.jl` is `0` (old bound gone).
  - `grep -c "result.iters >= 30" test/test_planning_hardening.jl` is `1` (new bound present,
    exactly once).
  - `grep -c "total_retries_from_trace >= 0" test/test_planning_hardening.jl` is `0` and `grep -c
    "retry_count_trace .>= 0" test/test_planning_hardening.jl` is `0` (both vacuous asserts gone).
  - `grep -c "retry + checkpoint machinery active" test/test_planning_hardening.jl` is `0` (old,
    now-false name string gone).
  - `grep -c "REVISION 2" test/test_planning_hardening.jl` is `>= 1`.
  - `grep -c "47" test/test_planning_hardening.jl` and `grep -c "66" test/test_planning_hardening.jl`
    are each `>= 1` (the measured spread is recorded, not just asserted-away).
  - `julia --project=. -e 'using JuliaFormatter; println(format("test/test_planning_hardening.jl";
    overwrite=false))'` prints `true`.
- **done:** `git diff --stat` shows only `test/test_planning_hardening.jl` changed; the diff
  contains the renamed `@testitem` string, the rewritten header title + new REVISION 2 paragraph,
  the two vacuous-assertion deletions (replaced by an honest removal comment), and the `>=50` ->
  `>=30` assertion swap with its pointer comment — no other line in the file (including the four
  other `@testitem`s and the checkpoint/cut-store assertions in this same item) differs from the
  pre-edit version; the file parses and is JuliaFormatter-clean.

### Task 2 — Prove the formatter pass lost no content, and prove the new assertions hold across the full measured range (analytic + local run)

- **files:** none committed (verification only)
- **action:**
  1. **Formatter content-loss isolation** (correct use of the guard per the Context note above —
     never against a pre-edit ref for this step, since that would flag Task 1's own intentional
     edits): before Task 1's step 10 formatter pass is applied, save a copy of the manually-edited
     (not-yet-formatted) file to the scratchpad, e.g. `cp test/test_planning_hardening.jl
     /tmp/claude-*/.../scratchpad/pre-format-test_planning_hardening.jl` (use the actual scratchpad
     path). After Task 1's formatter pass completes, diff the two with whitespace/commas stripped
     — reuse the same normalization `check_content_loss.py` uses (`re.sub(r'[\s,]+', '', t)`) via
     a short inline Python one-liner comparing the saved pre-format copy against the current
     working-tree file — and confirm they are IDENTICAL once normalized (proves the formatter
     pass itself dropped nothing).
  2. **Repo-wide content-loss sanity** (informational, not gating — per the Context note, this
     will legitimately flag `test/test_planning_hardening.jl` itself since this task adds real
     content): run `python3 .github/scripts/check_content_loss.py HEAD` and read its output.
     Confirm exactly ONE file is listed (`test/test_planning_hardening.jl`) and its reported char
     delta is POSITIVE (net addition, consistent with the new REVISION 2 comment paragraph and the
     removed-assertion comment being added, not evidence of unexpected loss elsewhere). Confirm NO
     other tracked `.jl` file appears in the report.
  3. **Analytic proof across the full measured range** (this IS the real proof — the CI-measured
     47 is not locally reproducible, so a single local pass does not by itself demonstrate the fix
     holds at 47): write out, as plain arithmetic (in your response, not a new file), that `result
     .iters >= 30` holds for every value in the measured set {47, 55, 55, 66} with large margin
     (17 to 36 iterations of headroom), and that it would FAIL for a hypothetical 3-iteration
     regression (`3 >= 30` is false) — i.e. the new floor separates every real measurement from
     the trivial-convergence failure mode it exists to catch, unlike the old `>=50` bound which
     the real CI measurement (47) fell below.
  4. **Local run of the renamed item**: from the repo root, run the item in isolation via the
     explicit-path TestItemRunner form confirmed working in this repo (never `julia -e
     '@run_package_tests'`, never a plain `--project=.` TestItemRunner invocation):
     `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib" julia -e 'using TestItemRunner, TSODSO;
     TestItemRunner.run_tests(joinpath(pwd(), "test"); filter=ti->occursin("(load, benders)",
     ti.name))' > /tmp/planning-hardening-load-run.log 2>&1; echo "exit=$?"`. Budget several
     minutes (the item alone measured ~33s of Benders solving, plus TestItemRunner/package
     precompilation on a cold run) — do not treat a slow-but-completing run as a failure, and do
     not kill a run and report it as a pass.
  5. Note explicitly in your final report: the local run is expected to show `result.iters` around
     47-66 (this machine's Julia 1.11 has previously shown 55) and therefore PASSES trivially —
     this is expected-but-insufficient evidence; the analytic argument in step 3 is what actually
     establishes the fix holds at the CI-measured value of 47.
- **verify:**
  - Step 1's normalized diff is empty (identical strings).
  - Step 2's `check_content_loss.py HEAD` output lists exactly one file
    (`test/test_planning_hardening.jl`) with a positive char delta, and no other file.
  - `/tmp/planning-hardening-load-run.log`: exit code `0`, TestItemRunner summary shows the
    filtered item's `Pass` count equal to its `Total` count (no `Fail`/`Error`), and `grep -v
    '^#' /tmp/planning-hardening-load-run.log | grep -c "Test Failed"` is `0`.
  - The `@info "planning hardening load test: empirical retry rate" ...` line's logged
    `result.iters` value in the log is `>= 30` (confirms the new floor's own precondition — the
    local environment's measured value, whatever it is this run, clears the structural floor).
- **done:** all four verify checks above hold with the evidence captured in
  `/tmp/planning-hardening-load-run.log`; the analytic argument from action step 3 is stated in
  the final report; formatter content-loss is proven clean via the isolated pre/post-format diff,
  not via a misapplied `check_content_loss.py <pre-edit-ref>` gate.

## Constraints

- Only `test/test_planning_hardening.jl` changes. No `src/` edits — there is no product defect.
- Do not touch the T=8 fixture shape (`T=8`, `α_op_lb=-50.0`, `λ₀=fill(4.0,8)`, `c_op=fill(0.5,8)`,
  `follower_kwargs`, `master_kwargs`, `tol=1e-6`, `max_iter=200`) — re-tuning was explicitly
  rejected by the user.
- Do not weaken `@test result.gap <= tol`, `@test result.iters < 200`, `@test
  total_retries_from_trace == n_retry_warnings`, the cut-store monotonicity/length assertions, or
  any of the checkpoint round-trip / resume / checkpoint-file-count assertions (lines ~265-289 in
  the pre-edit file) — these are the genuinely environment-independent assertions and must survive
  unchanged.
- Do not lower the new floor toward the CI-observed 47 (that would just relocate the same fragile-
  margin failure mode) — it must stay a structural threshold with the documented headroom on both
  sides (~1.9x the T=1 trivial floor of 16, ~36% below the min-observed 47).
- Do not touch any of the file's other four `@testitem`s.
- Repo stays format-clean under pinned JuliaFormatter 2.10.2 (check with `format(path;
  overwrite=false)` before any `overwrite=true` — bare `format(path)` defaults to
  `overwrite=true` and can silently rewrite content). Never let a wrapped comment line begin with
  `|`.
- Use `check_content_loss.py` correctly per the Context note: isolate the formatter pass itself
  (pre-format vs post-format snapshot of the manually-edited file) rather than gating on a
  pre-edit-ref comparison that would misreport this task's own intentional additions as "loss."
- Verification uses the explicit-path `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib"` TestItemRunner
  form — never bare `julia -e '@run_package_tests'`.
- A passing local run (expected ~47-66 iters, this machine previously measured 55) does NOT by
  itself prove the fix — the CI-measured value of 47 is not locally reproducible. The analytic
  argument (Task 2, action step 3) is the load-bearing proof and must be stated explicitly in the
  final report.

## must_haves

- **truths:**
  - `test/test_planning_hardening.jl`'s load-test item no longer contains the environment-fragile
    `result.iters >= 50` assertion; it asserts a structural floor (`result.iters >= 30`) justified
    by explicit arithmetic against the measured T=1-trivial floor (16) and the measured T=8
    min-observed value (47), recorded inline as a comment.
  - The item's two vacuous assertions (`total_retries_from_trace >= 0`,
    `all(result.trace.retry_count_trace .>= 0)`) are removed, with an honest comment explaining
    why, and the one real retry cross-check (`total_retries_from_trace == n_retry_warnings`)
    survives unchanged.
  - The item's name no longer claims "retry ... machinery active" (a measured falsehood on this
    fixture) or ">=50 Benders iterations" (the retired assertion).
  - The measured cross-environment spread (66/55/55/47) and the T=1 trivial floor (16) are
    recorded in a comment in the file, so a future contributor does not re-pin a tight bound.
  - Every other assertion in the item (gap, iters<200, retry cross-check, cut-store monotonicity/
    length, checkpoint round-trip, resume, checkpoint-file-count) is byte-identical to before this
    task.
  - No `src/` file changed; no other `@testitem` in the file changed.
- **artifacts:**
  - `test/test_planning_hardening.jl` (modified — renamed `@testitem` string, rewritten header
    title + new REVISION 2 comment paragraph documenting the measured spread and floor
    justification, two vacuous assertions replaced by a removal comment, `>=50` replaced by
    `>=30` with a pointer comment; everything else byte-identical).
- **key_links:**
  - The REVISION 2 comment paragraph (above the `@testitem`) -> the renamed `@testitem` string
    (no longer claims retired/false properties) -> the `@test result.iters >= 30` assertion (the
    structural floor the paragraph justifies) -> the retained `@test result.iters < 200` and
    checkpoint/cut-store assertions (unchanged, still relative to `result.iters` so they remain
    environment-independent).
</content>
