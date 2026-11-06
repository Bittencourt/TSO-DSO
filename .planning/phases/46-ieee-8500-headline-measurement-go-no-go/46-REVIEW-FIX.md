---
phase: 46-ieee-8500-headline-measurement-go-no-go
fixed_at: 2026-11-06T12:23:06Z
review_path: .planning/phases/46-ieee-8500-headline-measurement-go-no-go/46-REVIEW.md
iteration: 2
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
iteration_1: {review_path: 46-REVIEW.iter1.md, findings_in_scope: 11, fixed: 11, skipped: 0, status: all_fixed}
---

# Phase 46: Code Review Fix Report

> This file has two iterations. Iteration 1 comes first; its review is now kept as
> `46-REVIEW.iter1.md`, so where it says `46-REVIEW.md` it means that file. Iteration 2 is the
> section "Iteration 2" at the end, and the frontmatter describes iteration 2.

**Fixed at:** 2026-11-06
**Source review:** .planning/phases/46-ieee-8500-headline-measurement-go-no-go/46-REVIEW.md (iteration 1, now `46-REVIEW.iter1.md`)
**Iteration:** 1

**Summary:**
- Findings in scope: 11 (2 critical, 9 warning). Every one of them was fixed.
- Info findings were fixed only where trivial and safe:
  - fixed: IN-01, IN-02, IN-03, IN-04, IN-06;
  - partly fixed: IN-05 (docstring only);
  - not fixed: IN-07, IN-08.

All work was done in the main working tree, as the orchestrator instructed: no worktree and no
branch. No IEEE-8500 solve was run, and the measured row in `scenario_table.csv` was not edited.
The orchestrator re-runs the T = 10 point to regenerate it.

## Fixed Issues

### CR-01: Committed measured row and docs claim an 8G heap-size hint that was never applied

**Files modified:** `scripts/ieee8500_scenario_point.jl`, `scripts/run_ieee8500_point.sh`, `scripts/README.md`, `docs/literate/ieee8500_scaling.jl`, `.planning/research/STACK.md`, `test/test_ieee8500_scenario.jl`
**Commit:** 0e19996

**Applied fix:**
- **Script.** `heap_size_hint` now records the effective hint in bytes, `Int(Base.JLOptions().heap_size_hint)`, where 0 means none. It is no longer read from the environment variable.
- **Wrapper.** The change is opt-in and backward compatible:
  - When `HEAP_SIZE_HINT` is set, the wrapper validates it and passes `--heap-size-hint=$HEAP_SIZE_HINT` to julia.
  - When it is unset, the julia command line is byte-identical to before.
  - When only `JULIA_HEAP_SIZE_HINT` is set, the wrapper warns on stderr that julia ignores it.
- **Launch commands.** README, `--help`, the script header and the docs commands now use `HEAP_SIZE_HINT`.
- **Docs.**
  - The divergence-table row is corrected: the harness passed no hint, and the Scenario row records the process's effective hint.
  - The provenance line interprets the value. The legacy `8G` prints as "never applied: none in effect".
  - A dated correction note is added.
- **Earlier claim.** `.planning/research/STACK.md` said the hint was "set in `run_ieee8500_point.sh`". It now has a dated correction note; the old text is not edited. I checked that no `runs/*.time` file contains `--heap-size-hint`.
- **Test.** Provenance equals `JLOptions` even when `JULIA_HEAP_SIZE_HINT=8G` is set.

### CR-02: The upsert key omits seed and run_label

**Files modified:** `scripts/ieee8500_scenario_point.jl`, `docs/literate/ieee8500_scaling.jl`, `test/test_ieee8500_scenario.jl`
**Commits:** 3e1a398, 18c66cd, 1ad9df6

**Applied fix:**
- **Key.** `ROW_KEY` now adds `:seed` and `:run_label`.
- **Transient rows.** A transient new row never displaces a final row of the same key. Transient means `started` or `preflight_refused`, plus `crashed:*` from WR-02. Such a row only replaces older transient rows of that key. The attempt's final row then replaces both.
- **Old tables.** A key column missing from an older table reads as missing, so tables written before this change stay readable.
- **Docs reader.**
  - It selects the row by its full key and prefers the final row. An unfinished later attempt is printed beside it.
  - It joins the wrapper row whose MaxRSS equals the row's VmHWM, instead of the label's last wrapper row. A refused re-launch therefore cannot break the page.
  - The "two wrapper rows" prose is dated.
- **Tests:**
  - a `preflight_refused` row and a `started` row both leave a `refused_certificate` row in place;
  - the final row replaces both rows of its key;
  - another seed or another label is a separate row;
  - a table in the old schema stays readable, and its NO-GO row is replaced in place.

### WR-01: Non-atomic CSV rewrite

**Files modified:** `scripts/ieee8500_scenario_point.jl`, `test/test_ieee8500_scenario.jl`
**Commit:** a5eb498

**Applied fix:**
- `write_table_atomic` writes a hidden temporary file in the same directory, then calls `Base.Filesystem.rename` (`rename(2)`). `mv(...; force = true)` is not used, because it deletes the target first.
- On failure, the temporary file is removed and the old table is kept.
- There is still no lock against concurrent writers. The docstring says so.
- Tests: no temporary file is left behind, and a failed write keeps the old table byte-identical.

### WR-02: Expected memory outcomes and validation errors leave a misleading `started` row

**Files modified:** `scripts/ieee8500_scenario_point.jl`, `docs/literate/ieee8500_scaling.jl`, `test/test_ieee8500_scenario.jl`
**Commit:** 82750a8

**Applied fix:**
- `run_measured_point` wraps the phases:
  - `OutOfMemoryError` becomes the final status `memory_infeasible_inprocess`;
  - any other non-`TSODSOError` becomes the transient `crashed:<Type>`.
  - Each row records VmHWM and the error text. It is written on a best-effort basis, and then the error is rethrown.
- The `Scenario` is now constructed before the `started` row, so a validation error writes no row.
- The phase runner is injectable, so the tests use stubs and nothing is solved.
- The status vocabulary is extended in both the script and the docs.

### WR-03: Iteration count and certify timing lost on non-certificate certify errors

**Files modified:** `scripts/ieee8500_scenario_point.jl`
**Commit:** f7bc2d0

**Applied fix:**
- Certify is timed with `time_ns`. The time, the VmHWM sample and (since WR-07) the compile time are recorded in `finally`.
- The outer catch keeps `st.residuals.iters` once the loop has finished. It reports -1 only for a failure before that.

**Status:** fixed: requires human verification. This is a logic change. I found no cheap way to force a non-certificate `TSODSOError` from certify on IEEE-13, so this exact branch has no dedicated test.

### WR-04: B2 depends on the host running `--record-nogo`; the docs back-derive the host total

**Files modified:** `scripts/ieee8500_scenario_point.jl`, `docs/literate/ieee8500_scaling.jl`, `test/test_ieee8500_scenario.jl`, `results/ieee8500_benchmark/scenario_table.csv` (recorded_no_go row only)
**Commits:** 3532148 (code), 88d0c14 (row re-derived)

**Applied fix:**
- **Script.** The host total now comes from the measurement host's evidence: `free_total_kb(runs/p39-attr-d0.1-T24.free_before)`, 15,396 MiB. That is the attribution run of this point, the same run whose earlyoom log gives the 12 %. The source is cited in the note. `/proc/meminfo` is no longer read for this.
- **Docs.** B2 is recomputed from the same file and checked with `@assert` (rtol 1e-9). The circular `(B2 - B1) / 0.12` print is removed. The `free -m` totals of the other runs are printed too (15,908 MiB at the p35 run, 15,396 MiB at the p46 run).
- **Row.** I re-derived the row with `--record-nogo` (CSV only).
  - B2 is 13.323952 GiB, down from 13.323960, and still 13.324 to 3 decimals.
  - The measured row was checked byte-identical.

### WR-05: The verdict used `min` of the peaks

**Files modified:** `scripts/ieee8500_scenario_point.jl`, `docs/literate/ieee8500_scaling.jl`, `test/test_ieee8500_scenario.jl`
**Commit:** 06eb0fc

**Applied fix:**
- The script and the docs both decide on the larger peak, B1.
- The docs assert `(hm_verdict == "NO-GO") == (status == "memory_infeasible")`.
- Test: a threshold of 11.3 GiB, which lies between the two peaks, is now recorded as NO-GO.

**Status:** fixed: requires human verification. This is a logic change.

### WR-06: Hard-coded "completed twice" counter-fact

**Files modified:** `scripts/ieee8500_scenario_point.jl`, `docs/literate/ieee8500_scaling.jl`, `test/test_ieee8500_scenario.jl`
**Commit:** a382343

**Applied fix:**
- **What counts as completed.** A run is counted only for:
  - a head run with rc 0;
  - an `anchor_after` row with at least one iteration.
- **Wording.** The note says "once" or "twice" from that count, or that no completed run is claimed. It cites the head run's launch-time MemAvailable against B1. It states that the mechanism (swap-out, or memory that other processes released) was not measured.
- **Missing data.** A missing or duplicated d = 0.25 row is now an `ArgumentError`.
- **Docs.** The prose was revised and is asserted against the rows: rc 0, launch MemAvailable below B1, anchor iterations > 0, killer `earlyoom`.
- **Tests.** A synthetic head row with rc 143 gives "once" and no claim for the head run. A missing killed row throws.

### WR-07: Phase timings include JIT compilation, unlabelled

**Files modified:** `scripts/ieee8500_scenario_point.jl`, `docs/literate/ieee8500_scaling.jl`, `test/test_ieee8500_scenario.jl`
**Commit:** 7a91224

**Applied fix:**
- **Script.**
  - `Base.cumulative_compile_timing` is switched on for the call and off again in `finally`.
  - The compile time of each phase goes into four new columns after `certify_s`: `materialize_compile_s`, `build_compile_s`, `solve_compile_s` and `certify_compile_s`. Older rows get them through the column union.
- **Docs.**
  - A paragraph states that the times include compilation.
  - The page prints the compile part and its share when the row has them. Otherwise it prints "not recorded on this row".
  - A "compilation" row is added to the divergence table.
- **Test.** On IEEE-13, every phase satisfies `0 <= compile_s <= phase_s + 1e-3`.

### WR-08: Only the `ok` path was tested

**Files modified:** `scripts/ieee8500_scenario_point.jl`, `test/test_ieee8500_scenario.jl`
**Commit:** 52b9c1c

**Applied fix:**
- **Knobs.** `scenario_admm_phases` gains `atol_exact = nothing, rtol_exact = 1e-4`.
  - These are `solve_admm`'s own defaults.
  - The command line never sets them, and no library default changed.
- **New IEEE-13 test item:**
  - **`refused_certificate`:** forced with a flat floor of `atol_exact = 1e-300, rtol_exact = 0.0`, passed only in the test. It checks iters, a finite ratio above 1, the certify time and `kind=socp_exact`. The result matches `solve_admm`'s own `CertificateError` exactly: same `.iterations`, same parsed ratio.
  - **`convergence_error`:** `maxiter = 3` gives iters 3, which matches `run_scenario`'s `ConvergenceError.iterations`.
  - **`budget_exceeded`:** a 1e-6 s cap.
- **Other branches.** The `memory_infeasible_inprocess` and `crashed:*` branches are covered by the WR-02 stub test. The `preflight_refused` branch is covered by the WR-09 test.
- `error:<Type>` has no dedicated test. It needs a non-certificate `TSODSOError`, and I found no cheap way to force one.

### WR-09: Pre-flight measured after package load

**Files modified:** `scripts/ieee8500_scenario_point.jl`, `scripts/README.md`, `docs/literate/ieee8500_scaling.jl`, `test/test_ieee8500_scenario.jl`
**Commit:** e5b31ec

**Applied fix:**
- **Script.**
  - `MEMAVAIL_AT_START_KB` is read from `/proc/meminfo` with Base only, before `using DrWatson`.
  - `run_measured_point` judges that reading. For tests it can be injected with `avail_kb`.
  - The row notes say where the reading was taken.
- **Help, README and docs** say "read at script start, before any package load".
- **Docs.** The 2026-11-05 post-load history is kept, and the footprint line now says which kind of reading the row carries.
- **Test.** A refused pre-flight writes one row and never calls the phase runner.

### Info findings fixed

| ID | Commit | What changed |
|---|---|---|
| IN-01 | 309deb2 | Column-order docstring corrected: the docs reader is quote-aware. |
| IN-02 | 109893b | Removed the dead `certified` flag and the `:socp_maxratio` lookup, which only the stochastic path ever sets. `ok` rows get `gap_ratio = missing`, with a comment. |
| IN-03 | 55ff076 | `n_load_buses` is computed on every feeder. The docs label it "feeder total, before sampling". The parity test pins 10 on IEEE-13. |
| IN-04 | ffe5481 | `git_head`, `run_label`, `julia_version` and `heap_size_hint` are read as String (with `validate = false`). A test shows the leading zeros survive. |
| IN-05 | 26aa29f | Docstring only: the docstring now says the result equals a single-density harness invocation. I checked against `benchmark_ieee8500.jl:977` that a sweep shares one generator. |
| IN-06 | b82fe06 | The docs `hm_ratio` uses the script's anchored pattern, which accepts exponent notation. |

Other commits:
- `6039969`: style pass with JuliaFormatter 2.10, on touched in-scope files only;
- `4fb260f`: comment re-wraps, and the "run once" wording removed ahead of the re-run.

## Skipped Issues

### IN-05 (partial): test copy of the harness bus lists

**File:** `test/test_ieee8500_scenario.jl:189`
**Reason:** not trivial. The test would need its own copies of the harness's per-feeder bus lists, and I chose not to do that within "trivial and safe" for an Info finding. Only the docstring part was fixed.
**Original issue:** the inline "harness" copy in the test calls the same `TSODSO._load_buses` as the selector, so the harness's own mirror is not pinned.

### IN-07: The IEEE-8500 horizon floor lives only in the script

**File:** `src/experiments/Scenario.jl:181`
**Reason:** the fix would change the behaviour of the library's `Scenario` constructor, which is outside "trivial and safe" for an Info finding. The script's guard (`T_MIN_8500`) still blocks the case on the measured path.
**Original issue:** `Scenario(feeder = :ieee8500, T = 5)` constructs fine and only fails later, at materialization.

### IN-08: Test items that include the script run `@quickactivate`

**File:** `test/test_ieee8500_scenario.jl` (script `:57-58`)
**Reason:** not trivial. Skipping the activation would change which `projectdir()` and package environment the included helpers see inside `Pkg.test`, for example the default results directory and `git_head()`. This follows existing precedent (`test_case_a_magnitude.jl`).
**Original issue:** each include runs `@quickactivate`, which can switch the active project in the middle of a test run.

## Verification

- **Regression set.** `TSODSO_TEST_SET=fast` over these six files passed **837/837** in 3m57s; the baseline was 753:
  - `test_ieee8500_scenario.jl`
  - `test_strategies.jl`
  - `test_experiments.jl`
  - `test_flex_population.jl`
  - `test_admm_knifeedge_canary.jl`
  - `test_exports.jl`

  `test/Project.toml` and `test/Manifest.toml` were restored afterwards. The knife-edge canary passed.
- **Formatter.** JuliaFormatter 2.10.2 ran on the touched in-scope files only (`test/test_ieee8500_scenario.jl`, `docs/literate/ieee8500_scaling.jl`, `src/experiments/materialize.jl`). A second pass changed nothing. `check_content_loss.py` was OK.
- **Planning IDs.** 355 hits against a baseline of 355. All hits are in older text.
- **Scripts index.** Complete (48 files).
- **Script-API lint.** Only the 2 known findings in `profile_ieee8500_memory_attribution.jl`; nothing new.
- **JET.** 20 current, 20 baseline, 0 NEW, 0 FIXED (Julia 1.12.5).
- **SC3.** `git diff 7f13ec4..HEAD -- src/admm src/models/exactness.jl src/solver/factory.jl test/expected_broken.txt` is empty.
- **Docs page.** `julia --project=docs docs/literate/ieee8500_scaling.jl` exits 0. It still shows the old measured row, as expected:
  - the heap hint prints as the legacy, never-applied value;
  - the compile line prints "not recorded on this row".
- **Not run:** no IEEE-8500 solve, no full suite, no full docs build.

---

_Fixed: 2026-11-06_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_

---

# Iteration 2

**Fixed at:** 2026-11-06T12:23:06Z
**Source review:** .planning/phases/46-ieee-8500-headline-measurement-go-no-go/46-REVIEW.md (iteration 2)
**Iteration:** 2

**Summary:**
- Findings in scope: 5 (1 critical, 4 warning). All 5 were fixed.
- Info findings: IN-01 to IN-05 were fixed (each was trivial and safe). IN-06 was handled by listing
  iteration-1 IN-07 and IN-08 in `deferred-items.md`.
- As instructed, all work was done in the main working tree: no worktree, no branch. No IEEE-8500
  run was launched. No measured CSV row was edited: `scenario_table.csv` and
  `point_resources.csv` are untouched in this iteration.

## Fixed Issues

### CR-01: After the re-run, the docs page contradicted its own evidence and printed numbers, and omitted the 2026-11-06 gate override

**Files modified:** `docs/literate/ieee8500_scaling.jl`, `.planning/research/STACK.md`
**Commits:** 0bfbe83, 1a9ed86 (rewording for the planning-ID guard)

**Applied fix (docs page):**
- **Correction note.** It now cites the 2026-11-05 evidence by commit
  (`git show f60857e:results/ieee8500_benchmark/runs/p46-scn-ieee8500-d10-T10.time`). It also
  says why the working-tree file differs: the re-run overwrote the label's `runs/` files.
- **New dated "Re-run (2026-11-06)" paragraph.**
  - The measured row is attempt 3. It was launched with the corrected script and
    `HEAP_SIZE_HINT=8G`, so `--heap-size-hint=8G` was applied.
  - It replaced attempt 2's row under the same key.
  - The `runs/` files now belong to attempt 3.
  - The page now checks the current `.time` command line for the flag and prints it:
    `--heap-size-hint=8G`.
- **"Wrapper rows" prose** now covers all three attempts:
  - **Attempts 1 and 2 (2026-11-05):** user-approved launch at about 7.1 GiB, with the
    pre-flight read after package load.
    - Attempt 1 was `preflight_refused`.
    - Attempt 2 used a 5.5 GiB floor and had no hint. It ended `refused_certificate` with 5
      iterations and ratio 309.67; its row is cited at f60857e.
  - **Attempt 3 (2026-11-06):** pre-load reading, and the user explicitly approved a 6.5 GiB
    floor below the 8 GiB gate.
  - Asserts tie this prose to the first three wrapper rows (dates and floors 7 / 5.5 / 6.5).
    Those rows cannot change because the file is append-only.
- **The ~0.92 GiB footprint and the ~8.9 GiB launch level.** These are now described as
  properties of the post-load pre-flight that attempts 1 and 2 used, and are no longer derived.
  The 6,455,204 kB reading and the 965,724 kB difference are cited at commit f60857e.
- **Printed footprint lines.**
  - They name the joined attempt: "the measured row joins attempt 3".
  - They label the difference by reading point ("wrapper minus in-script reading (bare runtime
    startup) 77496 kB = 0.074 GiB").
  - The implied launch level is printed conditional on the reading point (about 8.07 GiB).
- **Divergence-table heap row:** "an applied `--heap-size-hint=8G` on the current row (attempt
  3, 2026-11-06); none on the replaced 2026-11-05 row (attempt 2)".
- **Reproducing section:** the "about one more GiB (printed above)" clause is gone.

**Applied fix (STACK.md):**
- The correction note is now scoped to "the 2026-11-05 launches" of the T = 10 point and cites
  f60857e.
- A dated update records that the 2026-11-06 re-run did apply the hint.

### WR-01: Reusing a run label overwrote the `runs/` evidence and could replace the committed measurement

**Files modified:** `scripts/run_ieee8500_point.sh`, `scripts/ieee8500_scenario_point.jl`, `scripts/README.md`, `docs/literate/ieee8500_scaling.jl`, `test/test_ieee8500_scenario.jl`
**Commit:** eadc747

**Applied fix:**
- **Wrapper.** A label that already has `runs/<label>.time` or `.free_before`, or a
  `point_resources.csv` row, is refused with exit 2 before anything is written.
  `REPLACE_LABEL=1` overrides.
- **Script.**
  - The new `--replace` flag. Without it, a measured run whose key already holds a final row is
    refused with an `ArgumentError`. The refusal comes before the pre-flight, so no row is
    written.
  - The new helper `final_status_for_key` does the lookup.
  - An `opts` without `replace` counts as `false`.
- **Reproduce commands.** The docs, the README, the script header and `--help` now use a fresh
  dated label (`LABEL=<name>-$(date +%Y%m%d-%H%M)`). The docs say that the committed label
  `p46-scn-ieee8500-d10-T10` and its row stay as they are.
- **Not done.** The committed measured row was not renamed, regenerated or edited. The optional
  explicit join key (WR-01 fix 3) was not added.
- **Tests:**
  - **Script guard:** the run is refused without starting, the table stays byte-identical, a
    pre-flight on that key is refused too, and a fresh label and `replace` both run.
  - **Wrapper guard:** exit 2 for runs/ evidence and for a CSV-row-only label, and nothing is
    written. SCRIPT points at a nonexistent file, so a missing guard would show up as a julia
    failure.
  - The in-process-failure item now passes `replace = true`, because it reuses a key on purpose.

### WR-02: The docs page crashed on `started` and `preflight_refused` rows

**Files modified:** `docs/literate/ieee8500_scaling.jl`
**Commit:** 5f08835

**Applied fix:**
- A row without a VmHWM joins no wrapper row, and neither does a final row whose VmHWM differs
  from MaxRSS.
- In that case the page prints the last wrapper row (attempt, rc, oom_source) as the launch
  outcome, instead of `@assert`, and skips the footprint lines.
- **Verified** by evaluating the page's `hm_*` function definitions on synthetic rows. Five cases
  all render: started, preflight_refused, a final row with no peak match, a final row that
  matches, and no wrapper rows.

### WR-03: A solver-layer error inside the ADMM loop discarded the solve time and the iterations already run

**Files modified:** `scripts/ieee8500_scenario_point.jl`, `test/test_ieee8500_scenario.jl`
**Commit:** 5a5dc7f
**Status:** fixed: requires human verification (logic change in the error path)

**Applied fix:**
- The solve phase is timed with `time_ns`. Its time, compile time and `:solve` VmHWM sample are
  recorded in `finally`, the same pattern as certify.
- The outer catch takes `st.residuals.iters` as soon as the ADMM state exists, but only when the
  error carries no `iterations` of its own.
- A mid-loop count is marked `iters_partial:` in the message.
- **Seams.** New test-only keywords `iterate_fn` and `certify_fn`. Their defaults are the real
  `_admm_iterate!` and `_admm_certify`, and the command line never sets them.
- **Test (IEEE-13).** A stub runs 2 real iterations, then raises `SolveFailedError`. The result
  has:
  - status `error:SolveFailedError`;
  - `iters == 2`, with the `iters_partial` marker;
  - solve and compile times recorded;
  - VmHWM samples `[materialize, build, solve]`.

### WR-04: A `memory_infeasible_inprocess` row could not say which phase ran out of memory

**Files modified:** `scripts/ieee8500_scenario_point.jl`, `test/test_ieee8500_scenario.jl`
**Commit:** 45ad85c
**Status:** fixed: requires human verification (logic change in the error path)

**Applied fix:**
- `scenario_admm_phases` catches `OutOfMemoryError` and returns `memory_infeasible_inprocess`.
- **Kept fields:** phase times, compile times, sizes, VmHWM samples and completed iterations.
- **Message:** names the phase under way (a new `phase` tracker), the sampled phases and the
  iteration count.
- **Exit status.** `run_measured_point` writes the full row, then raises `OutOfMemoryError`, so
  the exit stays nonzero as documented. Its existing catch still covers a custom phase runner
  that lets an OOM through.
- **Tests (IEEE-13, a stub runs 1 real iteration, then OOM).**
  - The phases return the status, iters 1, "during phase solve", the build and solve times, and
    the sizes.
  - Through `run_measured_point`, the full row is written and the error still propagates. This
    part runs only where `/proc/self/status` exists.

### Info findings fixed

| ID | Commit | What changed |
|---|---|---|
| IN-01 | 8f837aa | `HEAP_SIZE_HINT` must be a whole number with a K/M/G/T unit; `8`, `50%`, `8.5G` and `0G` are refused with exit 2 (tested). When a hint is passed, the `args` column gets a `[julia --heap-size-hint=...]` suffix; rows without a hint are unchanged (checked by hand in a scratch OUTDIR). |
| IN-02 | 396a924 | The counter-fact counts the anchor as completed only if it has at least one iteration and is not a budget exit. The docs assert mirrors this. Test: a budget_exceeded anchor gives "once" and the new wording. The committed row's note is unchanged. |
| IN-03 | 00726f6 | NO-GO when `B1 >= threshold`, in both the script and the docs. The message now says "reaches". Test: a threshold equal to B1 is recorded as NO-GO. |
| IN-04 | 04d4a77 | The atomic-write test now fails mid-stream: CSV.jl's `string` call on a stub cell confirms the temporary file exists, then throws. The test asserts the file is removed and the table is byte-identical. `.gitignore` gains `/results/**/.*.tmp.*`, which matches no tracked file. |
| IN-05 | 6919388 | The `error:<Type>` branch is tested through the `certify_fn` seam. The result has the converged iteration count (no partial marker), the certify time and compile time, and all four VmHWM samples. |
| IN-06 | 7975215 | Iteration-1 IN-07 and IN-08 are listed in `deferred-items.md` (items 3 and 4), with the fix each one needs. |

Other commit: `f8977d8` is a style pass with JuliaFormatter 2.10.2, on `test/test_ieee8500_scenario.jl` and `docs/literate/ieee8500_scaling.jl` only.

## Verification (iteration 2)

- **Regression set.** `TSODSO_TEST_SET=fast` over the six files passed **895/895** in 4m18s; the
  baseline was 837. The new assertions are the WR-01, WR-03, WR-04 and IN-01 to IN-05 tests.
  `test/Project.toml` and `test/Manifest.toml` were restored afterwards. The knife-edge canary
  passed.
- **Formatter.** Run on the touched in-scope files only. The second pass was a no-op, and
  `check_content_loss.py HEAD` reported whitespace and commas only.
- **Planning IDs.** 355 hits against a baseline of 355. The first draft had 3 new `[artifact]`
  hits on "review-fixed"; the follow-up commit `1a9ed86` reworded them.
- **Scripts index.** Complete (48 files).
- **Script-API lint.** Only the 2 known findings in `profile_ieee8500_memory_attribution.jl`;
  nothing new.
- **JET.** 20 current, 20 baseline, 0 NEW, 0 FIXED (Julia 1.12.5).
- **SC3.** `git diff 7f13ec4..HEAD -- src/admm src/models/exactness.jl src/solver/factory.jl test/expected_broken.txt` is empty.
- **Docs page.** `julia --project=docs docs/literate/ieee8500_scaling.jl` exits 0, and its
  output agrees with the prose:
  - verdict NO-GO;
  - provenance hint `8589934592 bytes`;
  - `runs/...time command line: --heap-size-hint=8G`;
  - attempts 1 to 3 with floors 7 / 5.5 / 6.5;
  - "the measured row joins attempt 3";
  - a pre-load difference of 77,496 kB and about 8.07 GiB at launch.
- **Not run:** no IEEE-8500 solve, no full suite, no full docs build.

---

_Fixed: 2026-11-06T12:23:06Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
