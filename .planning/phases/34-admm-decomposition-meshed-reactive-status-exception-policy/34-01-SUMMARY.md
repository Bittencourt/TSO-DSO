---
phase: 34-admm-decomposition-meshed-reactive-status-exception-policy
plan: 01
subsystem: core
tags: [exceptions, julia, error-handling, retry-ladder]
requires: []
provides:
  - "Exported TSODSOError hierarchy (SolveFailedError, CertificateError, ConvergenceError)"
  - "Internal _is_solver_failure legacy-union predicate"
  - "All production ErrorException catch sites widened (no source throw converted)"
affects: [34-02, 34-03, 34-04, 34-06]
tech-stack:
  added: []
  patterns: ["typed exceptions print exactly .msg via showerror", "widen catch sites before converting throw sites"]
key-files:
  created: [src/core/errors.jl, test/test_tsodso_errors.jl]
  modified: [src/TSODSO.jl, docs/src/api.md, src/planning/retry.jl, src/planning/benders.jl, src/planning/coupling.jl, src/planning/ac_recheck.jl, src/planning/subproblem.jl, src/pricing/fit.jl, src/experiments/run_stochastic.jl]
key-decisions:
  - "MOI aliased via `const MOI = JuMP.MOI` (MathOptInterface is not a direct project dependency)"
patterns-established:
  - "Catch sites use _is_solver_failure(e) instead of `e isa ErrorException`"
requirements-completed: []
duration: ~25min
completed: 2026-10-04
---

# Phase 34 Plan 01: Typed exception hierarchy and catch-site widening Summary

Typed `TSODSOError` hierarchy plus `_is_solver_failure` predicate added, and all 10 legacy `isa ErrorException` catch sites widened, with zero behaviour change.

## Tasks
1. Created `src/core/errors.jl` (included between balance.jl and status.jl), api.md Pages entry, and `test/test_tsodso_errors.jl` (2 testitems). Commit 24549ab.
2. Widened sites in retry.jl, benders.jl (4), coupling.jl, ac_recheck.jl, subproblem.jl, fit.jl, run_stochastic.jl. No extra sites found. Commit 641e6af.

## Verification
- Batch 1 (errors, status, canary, retry, fit, ac_recheck, coupling, inexact_policy): 211/211 pass.
- Batch 2 (benders, benders_integer, run_stochastic, oos_harness, stochastic_welfare): 112/112 pass.
- Canary untouched and passing (iters = 56); no test file other than test_tsodso_errors.jl changed.

## Deviations from Plan
**[Rule 3 - Blocking]** `import MathOptInterface as MOI` failed (not a direct dep); replaced with `const MOI = JuMP.MOI` in errors.jl and the test. Otherwise as written.

## Known Stubs
None.

## Self-Check: PASSED
