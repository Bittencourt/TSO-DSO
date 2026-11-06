---
phase: 46-ieee-8500-headline-measurement-go-no-go
fixed_at: 2026-11-06T00:00:00Z
review_path: .planning/phases/46-ieee-8500-headline-measurement-go-no-go/46-REVIEW.md
iteration: 1
findings_in_scope: 11
fixed: 11
skipped: 0
status: all_fixed
---

# Phase 46: Code Review Fix Report

**Fixed at:** 2026-11-06
**Source review:** .planning/phases/46-ieee-8500-headline-measurement-go-no-go/46-REVIEW.md
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
