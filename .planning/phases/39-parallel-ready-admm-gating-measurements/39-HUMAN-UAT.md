---
status: complete
phase: 39-parallel-ready-admm-gating-measurements
source: [39-VERIFICATION.md]
started: 2026-10-24T00:00:00Z
updated: 2026-10-27T00:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Researcher opt-in reproduction at -t 4
expected: `JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_admm_parallel.jl julia --project=. -e 'import Pkg; Pkg.test()'` — all pass, both equality legs at the canary values (iters 56, welfare −4823.66604824162); confirms the host-dependent threaded proof on the researcher's own machine (the two binding items are allowlisted skips in the certified 1-thread default suite).
result: pass
evidence: "Run 2026-10-27 on this host: 33/33 pass, exit 0, 3m16.5s. Bitwise equality leg: serial_iters=56, threaded_iters=56, serial_welfare=threaded_welfare=-4823.66604824162. Error parity: CertificateError/CertificateError, ConvergenceError/ConvergenceError, SolveFailedError/SolveFailedError (bare types, no TaskFailedException/CompositeException wrappers). Guard silent at -t 4."

### 2. T=24 full attribution — complete or accept the honest record (optional, resource decision)
expected: run the attribution harness with `--t-horizon 24` on a ~12 GiB-available host, or accept the Phase-35 standing T=24 figures into Phase 40. The earlyoom kill at 7.45 GiB peak and the stage-2 build-only attribution (6.07 GiB) are already recorded honestly in results/ieee8500_benchmark/memory_attribution.csv.
result: pass
evidence: "Option A executed on this host 2026-10-27 (user choice 'A'): COMPLETED, exit 0, ~13.4 min, no earlyoom kill (10 GiB RAM + 16 GiB swap headroom). 26 T=24 rows landed in results/ieee8500_benchmark/memory_attribution.csv incl. full stage-3/4/5 loop-stage attribution. Measured: anchor solve_admm maxrss delta 9.296 GiB (peak HWM 11.75 GiB) at iters=7 with an honest CertificateError refusal (SOCP gap 223.7 > 1, prices REFUSED). Reconciliation: Σ components +8.917 ± 0.555 GiB, residual 0.379 ± 0.555 GiB. This SUPERSEDES the Phase-35 standing figures (11.52/10.17 GiB) as the accepted T=24 record."

## Summary

total: 2
passed: 2
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none]
