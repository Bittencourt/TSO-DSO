---
status: partial
phase: 39-parallel-ready-admm-gating-measurements
source: [39-VERIFICATION.md]
started: 2026-10-24T00:00:00Z
updated: 2026-10-24T00:00:00Z
---

## Current Test

[awaiting human testing — deferred under autonomous mode (operator no-pause instruction)]

## Tests

### 1. Researcher opt-in reproduction at -t 4
expected: `JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_admm_parallel.jl julia --project=. -e 'import Pkg; Pkg.test()'` — all pass, both equality legs at the canary values (iters 56, welfare −4823.66604824162); confirms the host-dependent threaded proof on the researcher's own machine (the two binding items are allowlisted skips in the certified 1-thread default suite).
result: [pending]

### 2. T=24 full attribution — complete or accept the honest record (optional, resource decision)
expected: run the attribution harness with `--t-horizon 24` on a ~12 GiB-available host, or accept the Phase-35 standing T=24 figures into Phase 40. The earlyoom kill at 7.45 GiB peak and the stage-2 build-only attribution (6.07 GiB) are already recorded honestly in results/ieee8500_benchmark/memory_attribution.csv.
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
