---
phase: 38-close-v4-0-audit-gaps
plan: 04
subsystem: stochastic-oos-certificate
tags: [socp-exactness, stochastic, out-of-sample, skip-and-report, status-policy, gap-closure]
requires:
  - "38-01: _socp_cone_check kernel in src/models/exactness.jl"
provides:
  - "solve_stochastic_oos_step! = solve_with_retry! + _socp_cone_check(h.ctx) (library defaults); meta[:socp_maxgap]/[:socp_maxratio]; CertificateError(:socp_exact) when ratio > 1"
  - "_stoch_solve_held_out! -> (welfare, infeasible, inexact); narrow catch of the :socp_exact refusal"
  - "run_stochastic oos.inexact_h / oos.socp_maxratio_h; realized_welfare over feasible-and-exact draws"
  - "STATUS_VOCABULARY.run_stochastic = (:solved, :oos_infeasible_skipped, :oos_inexact_skipped)"
affects: [38-05, 38-07, 38-10]
tech-stack:
  added: []
  patterns: ["low level throws a typed certificate error; orchestrator converts the documented one into a skip-and-report status"]
key-files:
  created:
    - .planning/phases/38-close-v4-0-audit-gaps/38-04-SUMMARY.md
  modified:
    - src/models/stochastic_welfare.jl
    - src/experiments/run_stochastic.jl
    - src/core/errors.jl
    - test/test_stochastic_oos_harness.jl
    - test/test_run_stochastic.jl
    - test/test_status_policy.jl
    - .planning/phases/38-close-v4-0-audit-gaps/38-MEASUREMENTS.md
decisions:
  - "Exclude + report (user decision): an inexact held-out draw keeps its uncertified objective in welfare_h for reporting, is flagged in inexact_h, and is excluded from realized_welfare/welfare_gap"
  - ":oos_inexact_skipped takes precedence over :oos_infeasible_skipped; the masks carry the full per-draw detail"
  - "Harness default optimizer unchanged; mechanics tests and the infeasible->recover item pass the tol_gap 5e-10 optimizer (same tolerance and rationale as build_stochastic_welfare); the FourQuadBESS no-Ppv item keeps the default (measured 0.373)"
  - "infeasible->recover item switched to the tightened optimizer (measured: first solve still INFEASIBLE, recovery exact at 0.078), so it asserts an exact recovery"
metrics:
  duration: ~50min
  completed: 2026-10-07
  tasks: 3
  files: 7
requirements: [ARCH-08]
---

# Phase 38 Plan 04: Out-of-sample stochastic exactness gate (exclude + report) Summary

Every held-out re-solve in `run_stochastic` now goes through the shared hybrid-floor cone check.
An inexact draw raises `CertificateError(:socp_exact)` at the step level. The orchestrator skips
and reports it: the draw is flagged in `inexact_h`, excluded from `realized_welfare`/`welfare_gap`,
and the run gets the new status `:oos_inexact_skipped`. The CI stochastic golden does not move.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Measure every stochastic consumer before the change (1.12.5 + 1.12.7) | 8cbe6af | 38-MEASUREMENTS.md |
| 2 (RED) | Refusal item, tightened mechanics optimizer, mask/status pins | 3a6e913 | 3 test files, 38-MEASUREMENTS.md |
| 3 (GREEN) | Step gate, 3-tuple helper, masks/exclusion, new status, docstrings | 63816bb | stochastic_welfare.jl, run_stochastic.jl, errors.jl |
| 3 (format) | JuliaFormatter 2.10 (docstring rewrap only) | 97b7d07 | run_stochastic.jl |
| 3 (ledger) | Test deltas + 1.10/1.11 cross-check | 795e978 | 38-MEASUREMENTS.md |

## Measured refusals (default harness optimizer, before the change)

| consumer | 1.12.5 refused | 1.12.7 refused | effect under exclusion |
|----------|----------------|----------------|------------------------|
| CI golden `T=9, Stochastic(S=3, H_oos=5)` | 0/5 (max 0.366) | 0/5 (max 0.350) | none; `welfare_gap` stays **-0.018591711034105174** (1.12.5), status `:solved` |
| docs page `S=5, p=[.05,.15,.30,.30,.20], H_oos=10` | **5/10** (max 1.634) | **2/10** (max 1.941) | gap 0.016867 -> 0.032932 (1.12.5), 0.016867 -> 0.025993 (1.12.7); status `:oos_inexact_skipped` |
| compare script (seed 42, same S/p/H_oos) | 0/10 (max 0.478) | 0/10 (max 0.520) | none (gap -0.0323949) |
| harness build-once / pin-binding / FourQuadBESS-q / recover (default tol) | 1.13, 10.57 / 51.2, 50.4 / 1.49 / 7.29 | same | covered by the tightened test optimizer (all ≤ 0.4964) |

The docs page is the one explained move. Plan 05 updates that page and the compare-script prose.
The page has to report the excluded count live, because it differs by patch.

## Verification

- RED: 15 items, 49 Pass / 2 Fail / 14 Error, each failing for the intended reason (no throw, missing vocabulary value, missing 2-mask method, 2-tuple BoundsError, missing fields).
- GREEN, Julia 1.12.5 filtered run: the three files went from 14 items / 56 Pass to 15 items / 74 Pass (+18). With `test_stochastic_welfare.jl` added: 22 items / 100 Pass. `test_strategies.jl` (26 items, including the `:slow` ones): 415 Pass, unchanged.
- Plan verify command passed: the filtered run, the `_socp_cone_check(h.ctx)` grep, `check_content_loss.py HEAD`, `check_planning_ids.py`, zero stale flat-field names in run_stochastic.jl, and the ledger heading. `check_setup_names.py`: 0 unresolved.
- Cross-version check with the committed code on 1.10.11, 1.11.9 and 1.12.7. The golden is `:solved` with every draw exact (max 0.366 / 0.366 / 0.350), and `welfare_gap` is bit-equal on 1.10/1.11 (rel. diff 2e-6 on 1.12.7). The pin-binding solve at the default optimizer throws `:socp_exact` (ratio 51.23). Every 5e-10 mechanics solve is ≤ 0.4964. The infeasible->recover item gives `(NaN, true, false)` and then an exact recovery. No manual CI risk.
- The knife-edge canary was not touched. No tolerance or golden was changed.

## Deviations from Plan

- **[Rule 2 - test strength]** The new refusal item also asserts `h.ctx.meta[:socp_maxgap] > 0`, beyond the listed behaviours.
- **[Rule 2 - test strength]** The infeasible->recover item also asserts `h.ctx.meta[:socp_maxratio] <= 1` after the recovery, and `inexact === false` on the infeasible solve.
- The FourQuadBESS (no Ppv_param) item keeps the default optimizer, as the plan lists only three mechanics items. It is now gated: measured 0.373 on 1.10, 1.11, 1.12.5 and 1.12.7.
- The cross-version scratch also ran on 1.12.7 (not required) to confirm the golden after the change on the second gate patch.
- The baseline count was taken by temporarily restoring the two already-edited test files to HEAD with `git checkout -- <file>` (copies saved in the scratchpad), then restoring the edits.

## Known Stubs

None.

## Threat Flags

None. The change narrows an existing catch and adds no new surface. T-38-08/09/10 are mitigated as planned: the mask excludes refused draws, only `:socp_exact` is converted, and the kernel runs with library defaults.

## Self-Check: PASSED

- FOUND: src/models/stochastic_welfare.jl (`_socp_cone_check(h.ctx)`), src/experiments/run_stochastic.jl (`inexact_h`), src/core/errors.jl (`:oos_inexact_skipped`), test/test_stochastic_oos_harness.jl ("skipped-and-reported, never silently averaged")
- FOUND commits: 8cbe6af, 3a6e913, 63816bb, 97b7d07, 795e978
