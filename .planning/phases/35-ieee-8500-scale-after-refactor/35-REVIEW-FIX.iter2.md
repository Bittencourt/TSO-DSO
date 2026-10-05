---
phase: 35-ieee-8500-scale-after-refactor
fixed_at: 2026-10-05T03:20:00Z
review_path: .planning/phases/35-ieee-8500-scale-after-refactor/35-REVIEW.md
iteration: 1
findings_in_scope: 9
fixed: 9
skipped: 0
status: all_fixed
---

# Phase 35: Code Review Fix Report

**Fixed at:** 2026-10-05T03:20:00Z
**Source review:** .planning/phases/35-ieee-8500-scale-after-refactor/35-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 9 (1 critical, 8 warning; the 5 Info findings are out of scope for `critical_warning`)
- Fixed: 9
- Skipped: 0

**Verification run on the final tree (isolated worktree, no other julia process running):**
- `scripts/run_tests_filtered.jl <wt> tag:admm`: 287/287 pass. This was 277 after WR-02; the 10 new assertions were added by WR-02, WR-06 and WR-07.
- `file:test_admm_knifeedge_canary.jl`: 2/2 pass. The canary still gives `iters == 56` and welfare `-4823.66604824162`. It was not re-pinned and the file is untouched.
- `file:test_admm_exactness_default.jl`: 34/34 pass. `file:test_tsodso_errors.jl`: 58/58 pass. `file:test_exactness.jl`: 20/20 pass.
- `julia --project=. test/test_benchmark_ieee8500.jl`: D-16 goldens 10/10 and harness flags 24/24, all passing. `git status --short results/` was empty afterwards. No real IEEE-8500 point was run; this file runs only the `--quick` points, into tmpdirs.
- Mutation check for WR-06: I temporarily set both `solve_admm` and `solve_dso!` back to `atol_exact = 1e-6`. The new tests then failed (4 failures, 1 error), and I restored the files before committing.
- Gate semantics are unchanged: τ/ε constants, `assert_socp_exact!` verdict/message, and the `nothing` defaults are all as before.

## Fixed Issues

### CR-01: The diagnostic bypass reports hybrid ratios from a non-converged ADMM iterate and hides `budget_exceeded`

**Files modified:** `scripts/benchmark_ieee8500.jl`, `test/test_benchmark_ieee8500.jl`
**Commit:** aa897d1
**Applied fix:**
- The bypass branch now runs `hybrid_ratios`, writes `hybrid_diagnostic.csv`, fills `diag_*` and sets `DIAGNOSTIC_BYPASS` only when `apoint.admm_status == "converged"`.
- Every other outcome is recorded as `DIAGNOSTIC_BYPASS:<real status>` (for example `DIAGNOSTIC_BYPASS:budget_exceeded`) and writes no diagnostic rows.
- Diagnostic rows now carry an `admm_status` column, and the USAGE text was updated.
- New harness test (f): `--quick --admm-only --admm-diagnostic-bypass` gives `DIAGNOSTIC_BYPASS:budget_exceeded` and no `hybrid_diagnostic.csv`.

### WR-01: Docstrings still promise byte-identical defaults after the default changed

**Files modified:** `src/admm/solve_admm.jl`, `src/admm/DsoOpt.jl`, `scripts/benchmark_ieee8500.jl`
**Commit:** 70b76ac
**Applied fix:**
- Rewrote the `solve_admm` exactness-seam docstring, the `solve_dso!` `atol_exact` paragraph and the `run_admm_point` docstring.
- They now describe the hybrid floor `max(2e-7, 1e-9·ref_b)`:
  - stricter where `ref_b < 1000` (smax below about 31.6 pu, or an unlimited branch whose head-branch |S| is below about 31.6 pu);
  - looser above that (up to about 9.8e-6 near smax = 99, and unbounded in principle on unlimited branches with a large head flow).
- Dropped the "byte-identical" claims and the stale `exactness.jl:78` reference.
- `run_admm_point` now lists the three values it is actually passed: `nothing`, a finite `--admm-atol`, or `Inf` (bypass only). It also documents that `keep_ctx` returns a ctx on `:budget_exceeded` too.

### WR-02: `hybrid_ratios` re-implements the gate formula and ignores the gate's parameters

**Files modified:** `src/models/exactness.jl`, `test/test_admm_exactness_default.jl`
**Commit:** fd4b1c0
**Applied fix:**
- This is a pure refactor. The per-(b,t) computation (`lhs`, `rhs`, `gap`, `ref_b`, `atol_b`, `tol`, `ratio = gap / tol`) moved verbatim into the private `@inline _cone_row(pv, br, b, t, head_b, rtol, atol, ε, τ_solver)`. The head-branch lookup moved into `_socp_head_branch(feeder)`. Both `assert_socp_exact!` and `hybrid_ratios` call them.
- `assert_socp_exact!` keeps the same expressions, evaluation order, `maxgap`/`maxratio` accumulation, throw condition and messages.
- `hybrid_ratios` now takes the gate's own kwargs with identical defaults: `rtol = 1e-4`, `atol = nothing`, `ε = MEASURED_ε_FIX08`, `τ_solver = TAU_SOLVER_FIX08`.
- New tests show that `hybrid_ratios` and the gate agree for a flat `atol`, a smaller `ε`, and a custom `τ_solver`.

### WR-03: The wrapper blames this point for any OOM kill on the host during the run window

**Files modified:** `scripts/run_ieee8500_point.sh`
**Commit:** 7d05acf
**Applied fix:**
- The child writes its own pid to `runs/<label>.pid` and then `exec`s julia, so the pid is julia's. `/usr/bin/time -v` still measures the same process.
- An OOM is attributed only when `RC != 0` and a kernel or earlyoom journal line names that pid. The match is `(process |pid[= ])<pid>(non-digit|end)`, checked against this host's real earlyoom line format.
- `RC` 137/143 with no matching log line is now `signal_unattributed`, not `kernel`/`earlyoom`. `RC = 0` is always `none`.
- The full host-wide journal excerpts are still saved as evidence.
- Smoke-tested with a trivial script: RC 0 gives `none`, RC 137 gives `signal_unattributed`, and peak RSS is still captured.

### WR-04: `--run-label` is passed only when SCRIPT is literally `scripts/benchmark_ieee8500.jl`

**Files modified:** `scripts/run_ieee8500_point.sh`
**Commit:** a4376e7
**Applied fix:** The check now compares `basename "$SCRIPT"` with `benchmark_ieee8500.jl`. Smoke-tested with an absolute path: `--run-label <label>` was appended.

### WR-05: In multi-point runs, completed rows are written only at the end of the sweep

**Files modified:** `scripts/benchmark_ieee8500.jl`
**Commit:** 3e41b36
**Applied fix:** Each completed `row` is upserted into `density_sweep.csv` straight after `push!(rows, row)`, using the same key so it replaces that point's `started` row. The end-of-sweep upsert stays, for idempotence only.

### WR-06: The new tests do not detect the Phase 35 default change

**Files modified:** `src/admm/DsoOpt.jl`, `src/admm/solve_admm.jl`, `test/test_admm_exactness_default.jl`
**Commit:** ffe30ce
**Applied fix:**
- `solve_dso!(...; check_exact = true)` now records the `atol_exact` it judged with in `dso.ctx.meta[:socp_atol_exact]`. It records the value before the gate runs, so the value is there even on a refusal. This is metadata only; the gate is unchanged.
- Test (B) now asserts `r1.dso_ctx.meta[:socp_atol_exact] === nothing` for the `solve_admm` default, and `== Inf` for the explicit override. The 2-bus gap (about 8e-9) cannot distinguish the two defaults by verdict, which is why the test checks the recorded value instead.
- A new testitem runs the real `solve_dso!` final-gate path on a fixed-value ctx wrapped as a coupling-free `DsoOpt`:
  - gap 5e-7 on an `SMAX_NO_LIMIT` branch throws under the default and passes with `atol_exact = 1e-6`;
  - gap 5e-6 at smax = 90 passes under the default and throws with `1e-6`.
- Mutation-verified: setting either default back to `1e-6` fails these tests. Runtime is under 1 s beyond the existing 2-bus solves.

### WR-07: Rows refused by the gate (`CertificateError`) lose their iteration count

**Files modified:** `src/core/errors.jl`, `src/admm/solve_admm.jl`, `scripts/benchmark_ieee8500.jl`, `test/test_admm_exactness_default.jl`, `test/test_tsodso_errors.jl`
**Commit:** af2feda
**Applied fix:**
- `CertificateError` gained an `iterations::Union{Nothing,Int}` field (keyword, default `nothing`). A 2-arg positional constructor was kept for compatibility.
- `solve_admm` wraps `_admm_certify`: a `CertificateError` with no iteration count is rethrown with the same `msg` and `kind` plus `iterations = residuals.iters`. The refusal itself is unchanged, and this is documented under `# Throws`.
- The harness takes `iterations` from `ConvergenceError` or `CertificateError`. When it is unknown it records the Int sentinel `-1`, the same value `docs/literate/ieee8500_scaling.jl` maps unparsable cells to, so the column is no longer an Int/NaN mix.
- Tests: the final-gate refusal carries `iterations == r1.iters`, and the constructor defaults are covered.
- **This affects future rows only.** Committed measurement CSVs, such as the `ERROR:CertificateError` row with `admm_iters = NaN` behind the docs' "ADMM iterations 8" claim, were not rewritten. A re-run of that point is needed before the CSV can back that number.

### WR-08: `--topn 0` (or negative) crashes after the full ADMM solve

**Files modified:** `scripts/benchmark_ieee8500.jl`, `test/test_benchmark_ieee8500.jl`
**Commit:** 5bdbca0
**Applied fix:**
- `topn >= 1` is validated at parse time in both the sweep mode and `--gap-report` mode, which also parses `--topn`.
- The worst row is now taken as `hr[1]`, not `top[1]`.
- New harness test (g): `--topn 0` and `--topn -3` exit non-zero and write no CSV.

## Notes

- Info findings IN-01..IN-05 are out of scope (`fix_scope: critical_warning`) and were not touched.
- A formatting slip from the WR-07 commit (`r3 =solve_admm`) was corrected inside the WR-06 commit.

---

_Fixed: 2026-10-05T03:20:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
