---
phase: 34-admm-decomposition-meshed-reactive-status-exception-policy
plan: 03
subsystem: models
tags: [exceptions, julia, certificates, exactness]
requires: ["34-02"]
provides:
  - "assert_socp_exact!, assert_restriction_exact!, certify_angle_recoverable!, assert_battery_complementarity!, assert_4q_complementarity! throw CertificateError"
affects: [34-04, 34-06]
key-files:
  modified: [src/models/exactness.jl, src/models/restriction_exactness.jl, src/models/mesh_angle_certificate.jl, src/models/welfare_solve.jl, src/models/complementarity_4q.jl, test/test_tsodso_errors.jl, test/test_fourquadbess.jl, test/test_mesh_angle_certificate.jl, test/test_planning_inexact_policy.jl, test/test_planning_nash.jl]
key-decisions:
  - "Only the exception type changed; message text, report/on_violation semantics and every tolerance untouched"
requirements-completed: []
duration: ~60min
completed: 2026-10-04
---

# Phase 34 Plan 03: Certificate family typed throws Summary

The five exactness/complementarity certificate refusals now raise `CertificateError` (kinds `:socp_exact`, `:restriction`, `:angle`, `:battery`, `:four_quadrant`) with byte-identical message text; `report = true` / `on_violation = :warn` paths still warn instead of throwing.

Single atomic commit a2db6c3 (source + test migration). Docstrings updated from "loud `error(...)`" to `CertificateError`. `assert_ac_exact!` and the subproblem.jl `_is_solver_failure` swallow untouched.

## Migrated test lines
- test_fourquadbess.jl:546, 549, 587
- test_mesh_angle_certificate.jl:46
- test_planning_inexact_policy.jl:82, 318, 342, 361, 494, 499
- test_planning_nash.jl:1152 (`.msg` assertion unchanged)
- New in test_tsodso_errors.jl: socp_exact throw, battery throw (+ `:warn` no-throw), angle `report=true` no-throw / `report=false` throw.

## Left on ErrorException
- test_planning_inexact_policy.jl:198 (`:reject stalled`) -> Plan 04 (ConvergenceError).
- test_planning_nash.jl:519/873, test_planning_benders.jl:253 (exhausted) -> Plan 04.
- test_planning_benders_integer.jl, test_stochastic_welfare.jl, test_fit.jl, etc.: runs passed unchanged (their throwers are not the five certificates, or assertions go through `.msg`/`_is_solver_failure`); no edit needed.

## Verification
Foreground batches, all 0 failures: (1) canary + errors + exactness + fourquad + mesh angle + restricted_branch_flow + ac_oracle: 254 pass; (2) inexact_policy/nash/benders/mpc/stochastic_welfare/admm/admm_reactive: 716 pass, 1 broken (pre-existing); (3) integer planning/welfare_solve/pvbattery/ieee123/run_stochastic/oos: 358 pass; (4) fit/pricing_*/mesh_flow/feasibility_oracle/planning_oracle: 717 pass, 1 broken; (5) benders_ieee13/acceptance/thesis_repro: 30 pass, 1 broken. Canary unchanged (iters = 56, welfare -4823.66604824162, never re-pinned). Caller-closure grep files all covered by these batches (fixtures_* files excluded; they are not test files).

## Deviations from Plan
None.

## Known Stubs
None.

## Self-Check: PASSED
