---
phase: 35-ieee-8500-scale-after-refactor
plan: 04
subsystem: benchmark-measurement
tags: [ieee8500, memory-wall, ladder, honest-refusal]
requires: ["35-03"]
provides:
  - "memory_wall_recharacterization.csv; p35-head-d0.1-T24 and p35-head-d0.25-T24 rows"
key-files:
  created: [results/ieee8500_benchmark/memory_wall_recharacterization.csv]
  modified: [results/ieee8500_benchmark/density_sweep.csv, results/ieee8500_benchmark/point_resources.csv]
decisions:
  - "No src/ memory mitigation adopted (names mitigation not dominant, not provably risk-free); src/ unchanged"
  - "Ladder: T=24 d=0.1 survives (12.08 GB peak); T=24 d=0.25 killed by earlyoom at 12.6 GB peak; stop rule applied, SCS scouting skipped"
metrics:
  completed: 2026-10-04
---

# Phase 35 Plan 04: Memory mitigation decision and ladder Summary

The memory wall is now between density 0.1 and 0.25 at T=24 on this host (15.9 GB RAM, earlyoom at 12%). The T=24 density 0.1 point ran to completion and refused prices at the hybrid gate. The density 0.25 T=24 point was killed by earlyoom. `src/` is unchanged and no tolerance, golden or canary was touched.

## Task 1: mitigation decision (not adopted)
The 35-03 profile shows one DSO build adds +151 MB RSS and the first optimize +441 MB. The full T=10 ADMM run adds 4.67 GB, so the growth is per-hour solver state held across the ADMM loop, not JuMP names. Turning off string names would save only a fraction of the 151 MB build share per model. Nothing else is both bit-identical and low-risk, so nothing in `src/` changed. The canary and `tag:admm` suite were therefore not re-run (no `src/` diff). The table was seeded with Phase 25 baseline rows and the Phase 35 T=10 rows.

## Task 2: ladder (one attempt per step, one process at a time)
| label | density | T | rc | peak RSS | wall | outcome |
|---|---|---|---|---|---|---|
| p35-head-d0.1-T24 | 0.1 | 24 | 0 | 12.08 GB | 678 s | ERROR:CertificateError (ratio 223.68, genuine refusal); RSS delta 10.4 GB |
| p35-head-d0.25-T24 | 0.25 | 24 | 143 | 12.64 GB | 213 s | OOM, earlyoom SIGTERM at 10.6 GiB anon RSS; stopped, no retry |

Preflight before each point: no other julia process, available memory 10.3 to 11.5 GB. The memory delta grows about linearly in T (4.67 GB at T=10, 10.4 GB at T=24). Versus Phase 25, whose combined centralized+ADMM process was OOM-killed at density 0.1 T=24 (its T=10 density 0.1 point fit at ~5.9 GB), an ADMM-only process now completes density 0.1 T=24 (12.08 GB peak) and the wall moved to density 0.25 at T=24. (Corrected by orchestrator 2026-10-04: an earlier draft said Phase 25 died at T=10.) SCS scouting was skipped: it would use the same memory class and add no price claim.

## Deviations from Plan
- The first launch (backgrounded inside a background command) was killed with its parent shell before any run started. It produced no result rows. The point was relaunched once as the foreground command of a background task, so the ladder still has one real attempt per step.

## Known Stubs
None.

## Self-Check: PASSED
