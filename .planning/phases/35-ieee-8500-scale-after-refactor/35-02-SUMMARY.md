---
phase: 35-ieee-8500-scale-after-refactor
plan: 02
subsystem: benchmark-harness
tags: [ieee8500, harness, admm, diagnostics, oom-capture]
requires: ["35-01"]
provides:
  - "benchmark_ieee8500.jl --admm-only / --admm-atol / --admm-diagnostic-bypass / --run-label / --results-dir / --help"
  - "scripts/run_ieee8500_point.sh per-process wrapper (peak RSS, journalctl -k + earlyoom, rc 137/143)"
  - "scripts/profile_ieee8500_memory.jl staged VmRSS/VmHWM/gc_live profiler"
affects: [scripts/benchmark_ieee8500.jl, test/test_benchmark_ieee8500.jl]
key-files:
  created: [scripts/run_ieee8500_point.sh, scripts/profile_ieee8500_memory.jl]
  modified: [scripts/benchmark_ieee8500.jl, test/test_benchmark_ieee8500.jl]
decisions:
  - "Harness ADMM gate = library hybrid floor (atol_exact=nothing); --admm-atol accepts finite values only; Inf exists solely in the labelled DIAGNOSTIC_BYPASS mode"
  - "density_sweep upsert key now includes T_horizon; admm-only rows use solver=admm, bypass rows solver=admm_bypass so they never overwrite the standard rows"
metrics:
  completed: 2026-10-04
---

# Phase 35 Plan 02: IEEE-8500 harness (one point per process) Summary

The harness can now run a single ADMM point in its own process with the hybrid-floor gate, record OOM evidence from both the kernel and earlyoom, and run a labelled diagnostic bypass that dumps per-branch `hybrid_ratios`. No measurement was run, and no committed CSV under `results/` was changed.

## Commits
- f6ad6db: harness flags, hybrid default, `--admm-only`, bypass diagnostic, started rows, `PROGRAM_FILE` guard, results-dir redirect
- 55de981: `run_ieee8500_point.sh` wrapper and `profile_ieee8500_memory.jl`
- cd1756a: extended golden for flags, schema and rejections

## What was built
- **Gate default:** `run_admm_point` takes `atol_exact::Union{Nothing,Real}`. `EXACTNESS_ATOL` only feeds the centralized `exact_verdict` column. `admm_atol_used` is recorded as `"hybrid"`, a number, or `"Inf(DIAGNOSTIC_BYPASS)"`.
- **CLI input checks:** `--admm-atol` rejects non-finite values (T-35-04). `--admm-diagnostic-bypass` requires `--admm-only`.
- **Bypass diagnostic:** runs `atol_exact = Inf`, writes the top-N `hybrid_ratios` rows to `hybrid_diagnostic.csv`, and adds `diag_max_ratio`, `diag_worst_branch` and `diag_loss_impact_max` to the sweep row. The row status is `DIAGNOSTIC_BYPASS`.
- **Failure rows:** a failed point keeps `wall_s` and `peak_rss_mb`. `admm_iters` comes from `ConvergenceError.iterations`, else NaN. `admm_error_msg` holds the first 200 characters, and the error name is recorded as `ERROR:CertificateError` or `ERROR:ConvergenceError`.
- **Incremental rows:** a `started` row is written before the solve and replaced on completion.
- **GC and ctx:** `GC.gc()` runs between the centralized and ADMM stages and after the point. The DSO context is never retained beyond the diagnostic.
- **Entry point:** `main` only runs under a `PROGRAM_FILE` guard, so `include` never launches a sweep. `--help` prints usage and exits 0 before any solve or CSV write.
- **Wrapper:** records `/usr/bin/time -v` peak RSS and a `free -m` snapshot before the run. It checks `journalctl -k` and `journalctl -u earlyoom` and classifies rc 137 as kernel and rc 143 as earlyoom. It appends a row to `point_resources.csv` and exits 0 on OOM. `--run-label` is passed only when the benchmark script is the target.
- **Profiler:** stages 0-5 with `VmRSS`, `VmHWM` and `gc_live_MB`, upserted into `memory_profile.csv`. Stage 3 or higher is refused unless T <= 10.

## Verification
- The new harness testset passes (rejections, `--help`, hybrid label, run label, `1e-30` recorded). It was run in isolation, because the first (existing) testset aborts the script on 2 stale assertions; see Deviations.
- The wrapper was smoke-tested with `--help` into a temp `OUTDIR`. The profiler was run to stage 1 into a temp results dir. Neither touched committed CSVs.
- Existing goldens: 8 of 10 pass. The 2 failures are model_vars and model_cons only. They fail identically against the HEAD version of the harness.

## Deviations from Plan

**1. [Rule 3 - Blocking] Plan verify command for the profiler is invalid.** `Meta.parse` on a whole file errors with "extra token". I used `Meta.parseall` and checked for error nodes instead.

**2. [Scope] Stale pre-existing golden.** Test 2 pins `model_vars` 137144 and `model_cons` 274218. The `--quick` point now gives 137258 and 274570. I checked this with the original harness from HEAD run before any edit of mine, so it is not caused by this plan. I did not edit existing goldens, as instructed, and logged it in `deferred-items.md`. The existing `run_quick()` also writes into the committed `density_sweep.csv`; I restored it with `git checkout -- results/` after each run.

**3. [Design] Sweep upsert key now includes `T_horizon`,** and `--admm-only` and bypass rows use `solver = admm` and `admm_bypass`. Rows measured at different horizons or modes no longer overwrite each other.

## Known Stubs
None.

## Threat Flags
None. T-35-04 and T-35-05 are mitigated (finite-only CLI, `"$@"` quoting, no `eval`).

## Self-Check: PASSED
