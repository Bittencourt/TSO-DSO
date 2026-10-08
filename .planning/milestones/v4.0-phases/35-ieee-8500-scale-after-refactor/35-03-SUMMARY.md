---
phase: 35-ieee-8500-scale-after-refactor
plan: 03
subsystem: benchmark-measurement
tags: [ieee8500, memory-profile, hybrid-gate, honest-refusal]
requires: ["35-01", "35-02"]
provides:
  - "hybrid_diagnostic.csv, memory_profile.csv, point_resources.csv and p35-* rows in density_sweep.csv"
key-files:
  created: [results/ieee8500_benchmark/hybrid_diagnostic.csv, results/ieee8500_benchmark/memory_profile.csv, results/ieee8500_benchmark/point_resources.csv, results/ieee8500_benchmark/runs/]
  modified: [results/ieee8500_benchmark/density_sweep.csv]
decisions:
  - "SC1 verdict: gate refusal at IEEE-8500 d=0.1 T=10 is genuine (hybrid ratio 568.95 on L2916620->N1136366); recorded as ERROR:CertificateError, no tolerance or gate change"
metrics:
  completed: 2026-10-04
---

# Phase 35 Plan 03: IEEE-8500 measurements (profile, diagnostic, headline) Summary

All three measurements ran post-refactor, one process each, with no OOM. The default-gate headline point refuses with `ERROR:CertificateError`, as predicted by the user decision. The bypass diagnostic gives the numbers behind that refusal. `src/` is unchanged and no tolerance or golden was touched.

Commit: 29a83af (all result CSVs and per-run logs under `runs/`).

## Preflight
Before each point: no other julia process, `free -m` available about 8.4 to 10.9 GB, swap used 1.5 to 2.1 GB. Other load was chrome, claude and slack. Per-run snapshots are in `runs/*.free_before`.

## Task 1: staged memory profile (density 0.1, T=10)

| stage | VmRSS kB | VmHWM kB | gc_live MB |
|---|---|---|---|
| 0 after_using | 1179328 | 1240040 | 423 |
| 1 feeder_population | 1093372 | 1240040 | 64 |
| 2 build_dso_opt | 1244884 | 1293560 | 202 |
| 3 first_optimize | 1686228 | 1788896 | 676 |

Wrapper peaks: stage 2 run 1.30 GB, stage 3 run 1.79 GB, rc 0, no OOM.

Dominant consumer: the first optimize (Clarabel copy and factorization) adds +441 MB RSS and +473 MB live heap over the build. The build itself adds only +151 MB RSS. A single optimize of the DSO is therefore small. The multi-GB peak in the full ADMM run comes from retained state across the ADMM loop and its per-iteration solves, not from one build or one solve.

## Task 2: SC1 bypass diagnostic (p35-diag-d0.1-T10)
Run with `--admm-only --admm-diagnostic-bypass`, 8 iterations, 287 s, peak RSS 6.70 GB, rc 0.
- Max hybrid ratio 568.95. All 20 recorded rows have ratio above 1.
- Worst branch L2916620->N1136366 (b=1325), r_pu 2.40e-6, cone gap 1.21e-4 at t=3, atol_b 2.0e-7.
- Max loss-weighted impact 4.40e-9 pu.

The gap is smaller than the 1.8e-3 expected in the plan, but the ratio is still far above 1. The refusal is genuine and not spurious, and the economic impact is negligible (about 4e-9 pu). SC1 is met by the library default plus this documented proof (Outcome A).

## Task 3: headline point (p35-head-d0.1-T10, library hybrid gate)
Status `ERROR:CertificateError`: worst gap/(atol_b + rtol·|cone|) = 568.95 > 1, "prices REFUSED". Wall 286.6 s, peak RSS 6.21 GB (`peak_rss_mb` 6060, delta 4673 MB), rc 0. `admm_iters` is NaN on the failed row, so iterations (8) are taken from the p35-diag bypass row, which is the same solve with atol_exact = Inf. Centralized is not run (admm-only); v3.0 evidence stands (ALMOST_OPTIMAL at T=10, conditioning wall).

Versus v3.0 (8 iters, 227 s, 3.2 GB delta, about 5.9 GB peak):

| metric | v3.0 | now | delta |
|---|---|---|---|
| iterations | 8 | 8 | 0 |
| time | 227 s | 287 s | +26% |
| RSS delta | 3.2 GB | 4.67 GB | +46% |
| peak RSS | about 5.9 GB | 6.21 GB | +5% |

The time and memory delta may include contention from the other load on the shared box and the extra GC calls added in 35-02. This was not isolated.

## Deviations from Plan
- The sweep CSV schema grew new columns (35-02), so the commit rewrote the existing rows of `density_sweep.csv` with trailing empty fields (15 insertions, 14 deletions in the file). Values were not changed.
- Per-task commits were merged into one data commit, because all three measurements only produce result files.
- The centralized-only optional point was skipped. v3.0 evidence is cited.

## Known Stubs
None.

## Self-Check: PASSED

## Correction (2026-10-05, 35-REVIEW iteration 2, WR-02)

The staged profile above ran with the profiler's default `--fixture ieee8500-mv` (2,521 buses), not the
4,875-bus `ieee8500` fixture of the headline loop deltas. It was re-run on `ieee8500` (density 0.1, T = 10,
runs `p35-prof-ieee8500-s2` / `-s3`, rows `fixture = ieee8500` in `memory_profile.csv`, which now has a
`fixture` column; the old rows are kept and labelled `ieee8500-mv`). On the matched fixture the build adds
238,072 KiB (0.23 GiB) and the first optimize 929,700 KiB (0.89 GiB); stage-3 VmHWM is 2,515,692 KiB
(2.40 GiB). The conclusion is unchanged: one build plus one solve is far below the 4.56 GiB
(4,672.8 MiB) T = 10 ADMM-loop delta.

## Correction (2026-10-05, 35-REVIEW iteration 2, WR-03: units)

The "GB" figures above mix conventions (KiB / 10^6, MiB / 1000). Restated in GiB (2^30 bytes) from the raw
values: diag peak 6,699,480 KiB = 6.39 GiB; head peak 6,205,808 KiB = 5.92 GiB; head ADMM delta 4,672.8 MiB
= 4.56 GiB; v3.0 ADMM delta 3,200.4 MiB = 3.13 GiB. The v3.0 "about 5.9 GB" peak is a live-monitoring
anon-rss note with no recorded unit (`density_sweep_full.csv`, error_msg of the budget_exceeded 25-08 row),
not a harness peak from the 8-iteration run; read as GiB it is +0.3% against 5.92 GiB, read as GB +8%.
The "+5%" peak-RSS growth in the table above is therefore withdrawn: no peak change can be claimed.

