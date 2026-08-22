---
quick_id: 260822-f0b
description: Phase-25 follow-up — clarabel-tol flag, ADMM exactness-gate override seam, harness time-limit raise
date: 2026-08-22
status: complete
commits:
  - 8b259d5 (Task 1 — --clarabel-tol flag)
  - e57cb86 (Task 2 — atol_exact/rtol_exact seam)
  - 748fc50 (Task 3 — time-limit raise)
---

# Quick Task 260822-f0b — Summary

Three small, additive seams identified by `25-VERIFICATION.md` so the IEEE-8500 headline fixture
can eventually be run end-to-end honestly: a fixture-aware `--clarabel-tol` sweep flag, an
additive `atol_exact`/`rtol_exact` override on `solve_admm`'s final exactness gate, and a raised
default sweep time budget. None of the three touches the OOM/memory wall or the SCS-crossover
gap — those remain separate follow-up work, as scoped.

## What changed

### Task 1 — `--clarabel-tol` flag, fixture-aware default (`scripts/benchmark_ieee8500.jl`)

- New `IEEE8500_CLARABEL_TOL_GAP = 1.0e-7` (a MEASURED value, traceable to
  `results/ieee8500_benchmark/noise_floor_calibration.csv`: `ieee8500, 1e-7 -> 0.0049691451`,
  the last rung that resolved; `ieee8500, 1e-8 -> NaN`).
- New `DEFAULT_CLARABEL_TOL_GAP::Dict{Symbol,Float64}` — `:ieee8500 => IEEE8500_CLARABEL_TOL_GAP`,
  every other fixture (`:ieee13`, `:ieee123`, `:ieee8500_mv`) reuses the existing
  `CLARABEL_TOL_GAP = 1e-8` unchanged.
- `run_sweep_mode` parses `--clarabel-tol` (absent → the fixture-aware default), threads it
  through a new `clarabel_tol::Float64` parameter on `run_centralized_point`, into
  `select_optimizer(SOCP(); time_limit, tol_gap_abs = clarabel_tol, tol_gap_rel = clarabel_tol)`
  (mirrors the existing `run_calibrate_mode` precedent exactly).
- Bug fix: the CSV row's `clarabel_tol_gap` column now records the tolerance ACTUALLY used
  (`clarabel_tol`), not the hardcoded `CLARABEL_TOL_GAP` constant it previously always echoed
  regardless of fixture.
- Module header CLI-usage comment updated to document the new flag.

### Task 2 — `atol_exact`/`rtol_exact` override seam (`src/admm/DsoOpt.jl`, `src/admm/solve_admm.jl`)

- `solve_dso!` gains `atol_exact::Real = 1e-6, rtol_exact::Real = 1e-4` (copied verbatim from
  `assert_socp_exact!`'s own current defaults, `src/models/exactness.jl:78`), threaded into the
  `check_exact` branch: `assert_socp_exact!(dso.ctx; rtol = rtol_exact, atol = atol_exact)`.
- `solve_admm` gains the same two kwargs, threaded ONLY into the final consolidation `solve_dso!`
  call. The mid-loop `check_exact = false` call (line 439) is untouched — the gate never runs
  there.
- Both docstrings document the seam and its anti-certificate-laundering constraint (T-25-12):
  additive only, never used to manufacture a passing verdict for a point that would otherwise be
  inexact under the project's own default gate.

### Task 3 — raised sweep default time budget (`scripts/benchmark_ieee8500.jl`)

- `_DEFAULT_TIME_LIMIT_S` raised from `"120"` to `"1200"` (20 minutes), justified in-code from
  the measured ~20s/iteration on the headline point (6 iterations in 120s) and this project's
  observed 4-99 iteration convergence range. `_QUICK_TIME_LIMIT_S = "5"` and every comment
  justifying it are untouched — `run_sweep_mode`'s `quick ? _QUICK_TIME_LIMIT_S :
  _DEFAULT_TIME_LIMIT_S` never consults the raised constant under `--quick`.

## Verification

All verification ran on the plan's named cheap fixtures only (`ieee13`, `ieee8500-mv` at density
0.1) — no full IEEE-8500 density sweep and no true `ieee8500` headline fixture run, per the
task's hard constraint.

| Check | Result |
|---|---|
| `DEFAULT_CLARABEL_TOL_GAP` wiring (grep) | `:ieee8500 => IEEE8500_CLARABEL_TOL_GAP`, other three → `CLARABEL_TOL_GAP` |
| `julia --project=. test/test_benchmark_ieee8500.jl` (after Task 1) | 10/10 D-16 goldens pass |
| `ieee13 --density 1.0 --solver clarabel --time-limit 5` | `clarabel_tol_gap == 1.0e-8`, `termination_status == OPTIMAL` — byte-identical |
| `ieee8500-mv --density 0.1 --clarabel-tol 1e-6 --time-limit 30` | resulting row's `clarabel_tol_gap == 1.0e-6` — flag actually threaded, not discarded |
| `julia --project=. test/test_admm_timeout.jl` | 17/17 pass, unchanged |
| Targeted no-op-default + tight-override-throws script (IEEE-13/ρ=100 fixture) | `r_default.status == r_explicit.status == :converged`; `r_default.exact_maxgap == r_explicit.exact_maxgap`; `atol_exact=1e-30, rtol_exact=1e-30` correctly threw |
| `grep _DEFAULT_TIME_LIMIT_S / _QUICK_TIME_LIMIT_S` | `"1200"` / `"5"` (unchanged) |
| Final combined `julia --project=. test/test_benchmark_ieee8500.jl` (all 3 tasks landed) | 10/10 D-16 goldens still pass |

`results/ieee8500_benchmark/density_sweep.csv` was rewritten as a side effect of every harness
invocation above; each time, only wall-clock columns (`assembly_time_s`, `solve_time_s`,
`admm_time_s`, `total_time_s`, `admm_peak_rss_delta_mb`) and row order moved — every structural
golden value (`model_vars`, `model_cons`, `termination_status`, `exact_verdict`,
`clarabel_tol_gap`, `admm_status`, `admm_iters`) was confirmed identical before restoring via
`git checkout --`. The committed CSV is unchanged from before this task.

## Deviations from Plan

None — plan executed exactly as written. All three tasks landed additively; no defaults changed
except the two the plan explicitly authorized (`:ieee8500`'s `--clarabel-tol` default, and
`_DEFAULT_TIME_LIMIT_S`).

## Notes

- The `.planning/quick/260822-f0b-.../260822-f0b-PLAN.md` file was authored in the main checkout
  before this worktree existed; it was copied into this worktree (and committed alongside Task
  1) so the quick-task directory is self-contained on this branch.
- STATE.md's "Quick Tasks Completed" table is the orchestrator's responsibility, not touched here.

## Self-Check: PASSED

- FOUND: `.planning/quick/260822-f0b-phase-25-followup-clarabel-tol-flag-admm/260822-f0b-SUMMARY.md`
- FOUND: `.planning/quick/260822-f0b-phase-25-followup-clarabel-tol-flag-admm/260822-f0b-PLAN.md`
- FOUND: commit `8b259d5`
- FOUND: commit `e57cb86`
- FOUND: commit `748fc50`
