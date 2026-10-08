---
phase: 35-ieee-8500-scale-after-refactor
fixed_at: 2026-10-05T03:55:00Z
review_path: .planning/phases/35-ieee-8500-scale-after-refactor/35-REVIEW.md
iteration: 2
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 35: Code Review Fix Report

**Fixed at:** 2026-10-05T03:55:00Z
**Source review:** .planning/phases/35-ieee-8500-scale-after-refactor/35-REVIEW.md
**Iteration:** 2

**Summary:**
- Findings in scope: 5 (WR-01..WR-05; Info findings out of scope)
- Fixed: 5
- Skipped: 0

No `src/` file was touched, so the canary, `tag:admm` and `test_admm_exactness_default.jl` re-runs were not
required. Gate semantics, τ/ε and `assert_socp_exact!` are unchanged. No ADMM headline point was run.

Verification: `julia --project=. test/test_benchmark_ieee8500.jl` passed on the final harness: 10/10
goldens and 34/34 in the 35-02 set, including the new test (h). After that run, `git status --short results/`
was clean. `git diff --stat ffe30ce -- results/` lists only the intended files: the `density_sweep.csv`
`admm_iters` column, `memory_profile.csv`, `memory_wall_recharacterization.csv`, two appended
`point_resources.csv` rows, and the new `runs/p35-prof-ieee8500-s{2,3}.*` evidence.

## Fixed Issues

### WR-04: The committed `density_sweep.csv` `admm_iters` column is now Float for every row

**Files modified:** `scripts/benchmark_ieee8500.jl`, `docs/literate/ieee8500_scaling.jl`, `results/ieee8500_benchmark/density_sweep.csv`
**Commit:** aa6277e
**Applied fix:**
- Added `normalize_admm_iters!`, which `upsert_sweep_rows` calls before every write. `missing` stays `missing` (`started` rows), non-finite values become the `-1` sentinel, and everything else becomes `Int`.
- Ran the normalization once on the committed CSV. The diff touches only the `admm_iters` cells: `8.0` becomes `8`, and so on. The two pre-WR-07 `NaN` head rows become `-1`, as the review's suggested fix specifies.
- The docs parser now accepts `8.0`, `NaN` and `-1`.

### WR-02: Memory-profile figures came from the MV fixture

**Files modified:** `scripts/profile_ieee8500_memory.jl`, `results/ieee8500_benchmark/memory_profile.csv`, `results/ieee8500_benchmark/point_resources.csv`, `results/ieee8500_benchmark/runs/p35-prof-ieee8500-s{2,3}.{free_before,oom_earlyoom,oom_kernel,pid,time}`, `results/ieee8500_benchmark/memory_wall_recharacterization.csv`, `docs/literate/ieee8500_scaling.jl`, `35-03-SUMMARY.md`, `35-04-SUMMARY.md`
**Commit:** 85d2fe9
**Applied fix:**
- Added a `fixture` column to the profiler rows and made it part of the upsert key. The existing rows are backfilled as `ieee8500-mv`, which is what they were run on.
- Re-profiled `--fixture ieee8500 --density 0.1 --t-horizon 10` at stages 2 and 3 via `run_ieee8500_point.sh`, one process at a time. Before each run no other julia process was running and about 10.6 GiB was available. Both runs exited with rc 0 and no OOM. Peak RSS was 1,408,116 KiB (stage-2 run) and 2,515,692 KiB (stage-3 run).
- On the matching fixture, the build adds 238,072 KiB (0.23 GiB) and the first optimize adds 929,700 KiB (0.89 GiB). Together that is about a quarter of the 4.56 GiB T = 10 ADMM-loop delta, so the conclusion holds.
- Docs, the wall CSV, and dated errata in the 35-03 and 35-04 summaries now use these numbers. The MV numbers are kept and labelled as MV.

### WR-01: Docs table figures not traceable to the cited rows

**Files modified:** `docs/literate/ieee8500_scaling.jl`, `results/ieee8500_benchmark/memory_wall_recharacterization.csv`
**Commit:** 037b0b1
**Applied fix:** Every Phase-35 figure now names its file and `run_label`, and the source list covers all the files used.
- **Iteration count:** the 8 iterations are credited to the `p35-diag-d0.1-T10` bypass row. The docs state that the head row records `-1`. In `memory_wall_recharacterization.csv`, the head row's hand-typed "converged 8 iters" now reads "iters from p35-diag bypass row: 8; head row admm_iters = -1".
- **v3.0 source row:** the v3.0 column cites the `density_sweep.csv` row written by quick task 260822-hld (commit `262c983`). It states that row's flat `atol_exact = 4.97e-3` gate, about 5,000x looser than 1e-6.
- **Earlier v3.0 strict-gate failure:** commit `262c983` also records that the same point failed SOCP-exactness under the old flat `1e-6` gate (gap 1.3968e-4). The docs now say that this failed run left no CSV row.
- **The other v3.0 row:** the docs explain why the 8-iteration row differs from the `density_sweep_full.csv` row. That one is `budget_exceeded`, 6 iterations, 153 s, from the earlier attempt under the old 120 s budget with `clarabel_tol_gap = 1e-8`.
- **4.4e-9:** traced to `diag_loss_impact_max`, the maximum of `r_pu*gap` over all branch-hours. The 20 rows in `hybrid_diagnostic.csv` are the top ratios, and their own `loss_impact` peaks at 2.9e-10. The docs also give the smallest of those ratios (289.06).
- **"~5.9 GB":** traced to a live-monitoring anon-rss note in that `density_sweep_full.csv` row's `error_msg`.
- **Wall times:** previously these mixed `admm_time_s` and process wall. They are now split into process wall from `runs/*.time` (335 / 728 / 213 s) and `admm_time_s` (287 / 678 s / n/a).

### WR-03: Mixed and mislabelled memory units

**Files modified:** `docs/literate/ieee8500_scaling.jl`, `results/ieee8500_benchmark/memory_wall_recharacterization.csv`, `35-03-SUMMARY.md`, `35-04-SUMMARY.md`
**Commit:** 8d2c395
**Applied fix:** One convention is stated in the docs: GiB = 2^30 bytes. Every figure is converted from its raw unit (KiB / 2^20, MiB / 2^10), with the raw value kept next to it.
- **Peaks:** 5.92, 11.52 and 12.05 GiB.
- **Deltas:** 4.56 and 10.17 GiB. The diag row now shows its own delta, 5.03 GiB; it previously reused the head row's.
- **earlyoom kill:** quoted as `VmRSS 10641 MiB (10.4 GiB)`, VmRSS rather than anon RSS.
- **Host:** 15,908 MiB = 15.5 GiB.
- **Phase 25 anon-rss range:** corrected to 6.67-9.30 GiB, from the `density_sweep_full.csv` kB values.
- **v3.0 vs Phase 35 peak:** the v3.0 "~5.9" has no recorded unit. It is +0.3% or +8% against 5.92 GiB depending on the unit, and it is a different metric on a different run. The docs therefore say no peak change can be claimed, and the 35-03-SUMMARY erratum withdraws the "+5%".

### WR-05: `hybrid_diagnostic.csv` upsert mixes runs; converged path untested

**Files modified:** `scripts/benchmark_ieee8500.jl`, `test/test_benchmark_ieee8500.jl`
**Commit:** c5b5468
**Applied fix:**
- New `replace_diagnostic_rows` drops every existing row with the same `(fixture, density, T_horizon)` before appending. A non-converged bypass re-run also removes that point's stale rows.
- New harness test (h) runs the converged `DIAGNOSTIC_BYPASS` branch on `ieee13` (d = 0.1, T = 10, `--admm-only --admm-diagnostic-bypass`). It asserts:
  - `admm_status == "DIAGNOSTIC_BYPASS"`;
  - `admm_iters` is an Int;
  - the `admm_status` column is all `converged`;
  - the worst row's ratio equals `diag_max_ratio`;
  - a second run with `--topn 2` leaves exactly 2 rows, all from the second run.
- The test passed.

Not done: the committed `hybrid_diagnostic.csv` was not rewritten. Its 20 rows still predate the `admm_status` column.

---

_Fixed: 2026-10-05T03:55:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
