---
phase: 34-admm-decomposition-meshed-reactive-status-exception-policy
plan: 10
subsystem: admm
tags: [admm, meshed, reactive, cross-validation, julia]
requires: ["34-09"]
provides:
  - "mesh_aggregators_phi(φ; bess) fixture helper; test_admm_meshed.jl (meshed LIVE ADMM vs centralized, angle composition, negative pairs)"
affects: []
key-files:
  created: [test/test_admm_meshed.jl]
  modified: [test/fixtures_phase23.jl]
key-decisions:
  - "Tolerances measured, not picked: price atol 5e-4 (8.2x headroom over worst observed 6.10e-5), welfare rtol 1e-4"
requirements-completed: []
duration: ~25min
completed: 2026-10-04
---

# Phase 34 Plan 10: Meshed live-reactive ADMM cross-validation Summary

Meshed ADMM (`MeshedFeeder` + `MeshedFlow`, `reactive_consensus = LIVE`) reproduces the centralized meshed `:balance_p` / `:balance_q` duals and welfare; the angle certificate composes on `r.dso_ctx`. No `src` change.

## Measured gaps (eps_abs 1e-6, eps_rel 1e-5, het diamond, phi = 0.95)

| rho0 | iters | max abs dP | max abs dQ | abs dW |
|------|-------|-----------|-----------|--------|
| 1 | 37 | 5.40e-5 | 5.27e-5 | 4.11e-7 |
| 10 | 16 | 3.16e-5 | 4.10e-5 | 5.81e-6 |
| 100 | 6 | 5.48e-5 | 6.10e-5 | 7.52e-6 |

These reproduce the research table exactly. Centralized reactive price is nonzero (>0.05 asserted, ~0.2511 / 0.1354). Angle residuals (phi = 1 + FourQuadBESS): uniform central 0.0071986 vs ADMM 0.0071997 (`:angle_certified`); heterogeneous 0.0712824 vs 0.0712808 (`:angle_unrecoverable`).

## Commits
- e888d9b test(34-10): add phi-parametrized heterogeneous diamond aggregator helper
- 7ed68b2 test(34-10): meshed live-reactive ADMM vs centralized cross-validation

## Verification (foreground)
Batch (canary, test_admm_meshed, generic_pf, abstract_feeder, all test_mesh*, test_fourquadbess): 229 pass, 0 fail. Canary never re-pinned.

## Deviations from Plan
- The FourQuadBESS parameters were taken from `docs/literate/meshed_reactive_price.jl` (0.05, 0.05, 0.08, 0.0, 0.2, 0.1, 3.8, 6.2, 8.9), the construction behind the research numbers, not the test_fourquadbess unit values. With the latter the heterogeneous profile certified instead of being unrecoverable (a first-run failure fixed before commit).

## Known Stubs
None.

## Self-Check: PASSED
REQUIREMENTS.md intentionally untouched (ARCH-06 not marked complete).
