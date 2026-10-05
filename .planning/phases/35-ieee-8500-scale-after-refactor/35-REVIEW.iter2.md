---
phase: 35-ieee-8500-scale-after-refactor
reviewed: 2026-10-05T02:22:12Z
depth: standard
files_reviewed: 10
files_reviewed_list:
  - docs/literate/ieee8500_scaling.jl
  - scripts/benchmark_ieee8500.jl
  - scripts/profile_ieee8500_memory.jl
  - scripts/run_ieee8500_point.sh
  - scripts/run_tests_filtered.jl
  - src/admm/DsoOpt.jl
  - src/admm/solve_admm.jl
  - src/models/exactness.jl
  - test/test_admm_exactness_default.jl
  - test/test_benchmark_ieee8500.jl
findings:
  critical: 1
  warning: 8
  info: 5
  total: 14
status: issues_found
---

# Phase 35: Code Review Report

**Reviewed:** 2026-10-05T02:22:12Z
**Depth:** standard
**Files Reviewed:** 10
**Status:** issues_found

## Summary

I reviewed the Phase 35 diff (`03f8dbc..HEAD`). It covers the ADMM `atol_exact = nothing` default, the `hybrid_ratios` diagnostic, the harness flags (`--admm-only`, `--admm-diagnostic-bypass`, `--results-dir`, `--run-label`), the per-point wrapper, the memory profiler, and the new tests.

The library change itself is small and correct: `nothing` flows through to `assert_socp_exact!`'s hybrid branch. The defects are in four other areas:
- **Mislabelled diagnostic results.** The bypass path can compute and report hybrid ratios from a non-converged iterate.
- **Stale docstrings.** Several docstrings still promise "byte-identical defaults", which is now false.
- **Wrong outcome attribution in the wrapper.** It reads the system-wide journal, so it can blame an OOM it did not cause.
- **Tests that miss the change.** No test pins the actual default change at the `solve_admm` level.

## Critical Issues

### CR-01: The diagnostic bypass reports hybrid ratios from a non-converged ADMM iterate and hides `budget_exceeded`

**File:** `scripts/benchmark_ieee8500.jl:891-929` (and `src/admm/solve_admm.jl:321-340`)
**Issue:** `run_admm_point(...; keep_ctx = true)` returns `r.dso_ctx` whenever `solve_admm` returns, and that includes the `:budget_exceeded` early exit. That path deliberately skips consolidation and returns `dso_ctx = dso.ctx` holding the last mid-loop, non-consensus solve. `solve_admm.jl:322-327` says certificates are "meaningless on a mid-loop, non-consensus point."

The bypass branch only checks `apoint.dso_ctx !== nothing`. So on a budget exit it:
- runs `hybrid_ratios` on that iterate,
- writes the rows to `hybrid_diagnostic.csv`,
- fills `diag_max_ratio`/`diag_worst_branch`,
- sets `admm_status_out = "DIAGNOSTIC_BYPASS"`, which overwrites the real `"budget_exceeded"` status.

The CSV row then cannot be told apart from a converged diagnostic. A ratio from an unconverged point would be read as a statement about the converged relaxation gap, which is the kind of claim `ieee8500_scaling.jl` section 2 makes ("The ADMM run converged in 8 iterations ... ratio 568.95"). This is a research-data integrity defect in the evidence chain for ARCH-10.

**Fix:** Run the diagnostic only on a converged result, and always keep the real status:
```julia
if bypass
    if apoint.dso_ctx !== nothing && apoint.admm_status == "converged"
        admm_status_out = "DIAGNOSTIC_BYPASS"
        # ... hybrid_ratios / CSV ...
    else
        admm_status_out = "DIAGNOSTIC_BYPASS:" * apoint.admm_status   # e.g. ...:budget_exceeded
    end
```
Also add an `admm_status` column to the `hybrid_diagnostic.csv` rows.

## Warnings

### WR-01: Docstrings still promise byte-identical defaults after the default changed

**File:** `src/admm/solve_admm.jl:180-183`, `src/admm/DsoOpt.jl:537-543`, `scripts/benchmark_ieee8500.jl:560-567`
**Issue:**
- `solve_admm`'s seam docstring still says the defaults are "copied VERBATIM from `assert_socp_exact!`'s own current defaults (`src/models/exactness.jl:78`) ... every existing caller of `solve_admm` is byte-identical at these defaults." Phase 35 changed the default from `1e-6` to `nothing` exactly so that callers are not byte-identical: gaps in (2e-7, 1e-6] now throw, and gaps up to about 9.8e-6 on branches with smax near 99 now pass. The `exactness.jl:78` line reference is also stale; the function is at line 170.
- The new `DsoOpt.jl` text contradicts itself: "can now raise `CertificateError`" is followed by "Every existing call site ... is byte-identical".
- The `run_admm_point` docstring still says "The caller ALWAYS passes `EXACTNESS_ATOL[fixture_sym]`". It now passes `nothing`, a user `--admm-atol`, or `Inf`.

In a project where traceability of gate semantics is a hard requirement (T-25-12), wrong docstrings are a defect.
**Fix:** Rewrite all three docstrings to describe the new behaviour: the default is the hybrid floor, it is stricter below smax ≈ 31.6 pu, and it is looser above that. Drop the "byte-identical" claim and the line-number reference.

### WR-02: `hybrid_ratios` re-implements the gate formula and ignores the gate's parameters

**File:** `src/models/exactness.jl:417-451`
**Issue:** The function is documented as a "mirror" of `assert_socp_exact!`'s default gate, but it copy-pastes the `head_b`, `ref_b`, `atol_b` and `tol` computation instead of sharing it. It also hard-codes `TAU_SOLVER_FIX08`/`MEASURED_ε_FIX08` and takes no `atol`, `ε` or `τ_solver` kwargs. Two consequences:
- If the gate formula changes later (for example the `head_b` convention discussed at exactness.jl:190-225), the diagnostic silently drifts.
- A caller that ran the gate with non-default `ε`/`τ_solver`/`atol` gets ratios that do not match the verdict. The docstring promises "`ratio ≤ 1` iff the gate accepts that row".

**Fix:** Move the per-(b,t) computation into one private helper, for example `_cone_rows(ctx; rtol, atol, ε, τ_solver)`, that both functions call. `assert_socp_exact!` then reduces to `maximum(r.ratio) <= 1`. Give `hybrid_ratios` the same kwargs with the same defaults.

### WR-03: The wrapper blames this point for any OOM kill on the host during the run window

**File:** `scripts/run_ieee8500_point.sh:47-58`
**Issue:** `journalctl -k --since "$START" | grep "oom-kill|Killed process"` and `journalctl -u earlyoom | grep "sending|killing|SIGTERM"` match kills of any process. The wrapper itself records `other_julia_procs`, so other processes are expected on this host. The classification is `[ "$RC" -eq 137 ] || [ -n "$KERN" ]`, which means:
- a point that finished with RC=0 is labelled `oom_source=kernel` if anything else was OOM-killed during it;
- a point that died with 143 for an unrelated reason is labelled `earlyoom`.

`point_resources.csv` feeds the memory-wall table in the docs.
**Fix:** Only attribute an OOM when `RC != 0`, and match the child PID or command (`julia`, or the PID captured via `$!` when the command is backgrounded and waited on):
```bash
if [ "$RC" -ne 0 ]; then
  if [ "$RC" -eq 137 ] && grep -q "$CHILD_PID" <<<"$KERN"; then OOM_SOURCE=kernel
  elif grep -q "$CHILD_PID" <<<"$EARLY"; then OOM_SOURCE=earlyoom; fi
fi
```

### WR-04: `--run-label` is passed only when SCRIPT is literally `scripts/benchmark_ieee8500.jl`

**File:** `scripts/run_ieee8500_point.sh:32-35`
**Issue:** The check is an exact string comparison. With `SCRIPT=./scripts/benchmark_ieee8500.jl` or an absolute path, the harness runs without `--run-label`, so `run_label` is empty in `density_sweep.csv`. The join key with `point_resources.csv` is then lost without any warning.
**Fix:** Compare the basename, `[ "$(basename "$SCRIPT")" = "benchmark_ieee8500.jl" ]`, or make the profiler accept and ignore `--run-label`.

### WR-05: In multi-point runs, completed rows are written only at the end of the sweep

**File:** `scripts/benchmark_ieee8500.jl:866-876, 991-993`
**Issue:** Each point upserts a `started` row before solving, but completed rows are collected in `rows` and written once after the loop. In a multi-density invocation (allowed: `--density 0.1,0.25`), a kill or exception on point k leaves every earlier, fully measured point saved only as `admm_status = "started"`. Two things go wrong:
- Completed measurements are lost.
- They are recorded as if they were in progress when the kill happened, which contradicts the comment "a kill mid-solve leaves a trace; the completion upsert replaces it."

An exception thrown after `run_admm_point` (for example in `hybrid_ratios` or a CSV write) has the same effect.
**Fix:** Upsert each completed `row` right after `push!(rows, row)`, for example `upsert_sweep_rows(csv_path_sweep, DataFrame([row]))`, and keep the final write for idempotence only.

### WR-06: The new tests do not detect the Phase 35 default change

**File:** `test/test_admm_exactness_default.jl:35-79`
**Issue:**
- Test (A) checks `assert_socp_exact!`'s default. That default was already `nothing` before Phase 35, so (A) passes on the pre-change code too.
- Test (B) compares `solve_admm(...)` against `solve_admm(...; atol_exact = nothing)`, which only tests that the default equals itself. If the 2-bus consolidation gap is below 2e-7, both `1e-6` and `nothing` accept it and give identical results, so reverting the default to `1e-6` would still pass every test.

Nothing checks that the `solve_admm`/`solve_dso!` default reaches the hybrid branch.
**Fix:** Add a regression check that tells the two defaults apart. One option is to assert on the method default directly. A better option is to call the final gate through `solve_dso!` (or `_admm_certify`) on a ctx like `ctx_A()`/`ctx_N()`: assert that it throws for a gap in (2e-7, 1e-6] on an `SMAX_NO_LIMIT` branch, and that it passes for gap 5e-6 at smax = 90. Both outcomes are the reverse of the old flat `1e-6`.

### WR-07: Rows refused by the gate (`CertificateError`) lose their iteration count

**File:** `scripts/benchmark_ieee8500.jl:588-597`
**Issue:** The new failure path keeps `iterations` only for `ConvergenceError`. `CertificateError` has no `iterations` field (`src/core/errors.jl:68-71`), so the main Phase 35 outcome (`ERROR:CertificateError` after ADMM converged) records `admm_iters = NaN`. The docs table still reports "ADMM iterations 8" for that row, a number the harness's own CSV cannot back up. Also, `admm_iters` is now an Int/NaN mix, while `docs/literate/ieee8500_scaling.jl:152` parses it with `tryparse(Int, ...)` and maps NaN to -1.
**Fix:** Either have `solve_admm` attach the iteration count to the gate failure (wrap it and rethrow with context), or record iterations through a residual-tracking callback. Use one sentinel consistently, for example `-1` or `missing`.

### WR-08: `--topn 0` (or negative) crashes after the full ADMM solve

**File:** `scripts/benchmark_ieee8500.jl:774, 899, 920`
**Issue:** `top = hr[1:min(topn, length(hr))]` is empty when `topn <= 0`, and `w = top[1]` then throws a `BoundsError`. This happens after a run that can take several minutes and 12 GB. The completed point is lost and its `started` row stays behind (see WR-05).
**Fix:** Validate at parse time: `topn >= 1 || throw(ArgumentError("--topn must be >= 1"))`. Take `w = hr[1]` rather than `top[1]`.

## Info

### IN-01: The docs' "except on branches with smax of 32-99 pu" statement is incomplete

**File:** `docs/literate/ieee8500_scaling.jl:221-223`
**Issue:**
- `SMAX_NO_LIMIT = 99.0`, and branches at that sentinel use the head-branch flow as `ref_b`, not `smax²`. The looser-than-`1e-6` range is therefore smax in [31.6, 99) plus every unlimited branch in hours where |S_head| > 31.6 pu.
- The statement also omits that the new default is looser (up to about 9.8x) on those branches, not only stricter elsewhere.

**Fix:** Correct the sentence.

### IN-02: `run_tests_filtered.jl` does not validate its arguments

**File:** `scripts/run_tests_filtered.jl:5-7`
**Issue:** If arguments are missing, `ARGS[1]`/`ARGS[2]` throws a `BoundsError`, and a spec without `:` throws a destructuring error. The usage message is never printed.
**Fix:** Check `length(ARGS) == 2 && occursin(':', ARGS[2])` and print the usage line otherwise.

### IN-03: The `hybrid_ratios` sort assertion checks nothing

**File:** `test/test_admm_exactness_default.jl:91`
**Issue:** `issorted(...)` runs on the single-row result of `ctx_N()`, so it is always true.
**Fix:** Build a 2+-branch or T>1 ctx so the descending-ratio ordering is actually checked.

### IN-04: An empty array expansion under `set -u` fails on bash < 4.4

**File:** `scripts/run_ieee8500_point.sh:44`
**Issue:** `"${LABEL_ARGS[@]}"` with an empty array is an "unbound variable" error on bash 4.3 and older, which is the profiler path.
**Fix:** Use `${LABEL_ARGS[@]+"${LABEL_ARGS[@]}"}`.

### IN-05: Peak-RSS columns are process-lifetime values

**File:** `scripts/benchmark_ieee8500.jl:600-606`; `scripts/profile_ieee8500_memory.jl:83`
**Issue:**
- `peak_rss_mb = Sys.maxrss()` is the process high-water mark. Without `--admm-only` it includes the centralized model.
- In multi-point runs, `admm_peak_rss_delta_mb` reads about 0 after the first point because maxrss only ever increases.
- Separately, the profiler only honours the env var for its output directory, not `--results-dir`.

**Fix:** Document the columns as process-lifetime values, or refuse multi-point runs when RSS columns matter. Add `--results-dir` handling to the profiler.

---

_Reviewed: 2026-10-05T02:22:12Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
