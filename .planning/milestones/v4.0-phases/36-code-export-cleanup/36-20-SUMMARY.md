---
phase: 36-code-export-cleanup
plan: 20
subsystem: hygiene
tags: [planning-id-scrub, tests]
requires: ["36-19"]
provides:
  - whole test/ tree free of planning identifiers (classifier TOTAL 0 over `test`)
affects: [36-21]
key-files:
  modified:
    - test/test_oracle.jl, test_perunit.jl, test_powerflow.jl, test_pricing_dlmp.jl, test_pricing_fit.jl, test_pricing_welfare.jl
    - test/test_profiles.jl, test_pvbattery.jl, test_restricted_branch_flow.jl, test_run_stochastic.jl
    - test/test_scenario_pf.jl, test_solver_factory_milp.jl, test_status.jl, test_status_policy.jl
    - test/test_stochastic_oos_harness.jl, test_stochastic_welfare.jl, test_strategies.jl, test_thermostatic.jl
    - test/test_thesis_repro.jl, test_topology.jl, test_toy_dc.jl, test_tsodso_errors.jl, test_welfare_solve.jl
requirements-completed: []
completed: 2026-10-05
---

# Phase 36 Plan 20: Scrub of remaining test files Summary

About 420 classifier hit lines (plus process phrasing the classifier cannot see) in 23 test files (o, p non-planning, q through z) were rewritten as plain prose; rationale, measured numbers and thesis/literature references were kept. After this plan `classify_planning_ids.py test --count` prints `TOTAL 0`. HYG-01 stays pending (guard plan remains).

## Commits
- de24e32: scrub test_o*, test_p[!l]*, test_r* (task 1)
- 948a69a: scrub test_s* through test_w* (task 2)
- 3444402: JuliaFormatter 2.10.2 pass (touched test_oracle, powerflow, pricing_dlmp, pricing_fit, profiles, pvbattery, run_stochastic, scenario_pf, status_policy, stochastic_oos_harness, stochastic_welfare, strategies, tsodso_errors, welfare_solve)

## Verification
- Classifier: `TOTAL 0` for `test`. Extended grep (RED until, gap-closure, Rule N, Open Q, USER DECISION, .planning/, byte-identical, "this phase/plan") finds nothing in `test/`.
- `ast_equiv.jl` and `--literals` against the pre-plan commit 79a14e3: EQUAL for all touched files. `--literals` against 801fb0c: EQUAL (numeric literals) for test_admm_knifeedge_canary.jl, test_planning_goldens.jl, test_thesis_repro.jl.
- `thesis_tokens.py`: OK. `check_setup_names.py`: 20 testmodules, 219 setup uses, 0 unresolved.
- `check_content_loss.py HEAD`: OK before the formatter commit. The formatter also rewrote an unrelated file (`test/test_benchmark_ieee8500.jl`, a one-line docstring); that change was reverted and not committed.
- Full suite `p20` after the final code commit: Pass 32202 / Fail 0 / Error 0 / Broken 5, same pass as p13; canary welfare -4823.66604824162 present.
- Targeted per-file runs were not done separately; the full suite covers them (comment-only plus name-only changes).

## Message changes
No `src/` messages changed. Non-`@testitem` string literals changed (none asserted on; `--literals` AST EQUAL):
- test_pricing_dlmp.jl: `@info "WR-02 PV back-feed + decompose_dlmp"` -> `@info "PV back-feed + decompose_dlmp"`.
- test_restricted_branch_flow.jl: `@info` labels `... on EXACT-04` -> `... on the high-PV fixture` (two labels).
- test_stochastic_welfare.jl: `@info "D-06 scan NEVER tripped the PF-04 gate ..."` -> `@info "scan NEVER tripped the exactness gate ..."`.

Renamed `@testitem` names (121 string changes in total, all by dropping IDs; descriptive core, module words and tags kept; nothing in `scripts/`, `.github/`, `docs/make.jl`, `test/runtests.jl` filters on a name; no duplicate names across `test/`):
- Trailing `(REQ-ID)`/`(WR-nn)`/`(T-nn-nn)`/`(spike 003 ...)`/`(plan 27-09 ...)` suffixes dropped in oracle, perunit, powerflow, pricing_dlmp, pricing_fit, pricing_welfare, profiles, pvbattery, restricted_branch_flow (also `(phase 26-02 FIX-01/02)`, `(D-05, ...)`, `(D-09/D-10/D-11 CI subset)` -> `(CI subset)`), thermostatic, stochastic_welfare, run_stochastic.
- `ARCH-01 ...` -> `scenario_pf: ...` (10 items, test_scenario_pf.jl); `ARCH-02 ...` and `REVIEW WR-0n ...` -> `strategies: ...` (test_strategies.jl).
- `restricted_branch_flow: EXACT-04 fixture` wording -> `high-PV fixture`; `WR-06`/`CR-01` prefixes dropped.
- `stochastic_welfare: D-04/D-06/WR-03/WR-04/WR-09/WR-10 ...` prefixes dropped; `stochastic_oos_harness: CR-01/WR-04` prefixes dropped; `run_stochastic: WR-05/D-11` prefixes dropped.
- `byte-identically` -> `bit-for-bit identically` (pricing_fit); `byte-identical default (MPC-01 seam)` -> `bit-for-bit identical default` (pvbattery, thermostatic).

## Hand-edited / notable
- test_thesis_repro.jl header (about 80 lines of provenance narrative) was condensed to technical rationale; all numeric band values and the measurement numbers kept. The word count of "thesis" was kept equal for the thesis-token check.
- test_restricted_branch_flow.jl: `EXACT-04` fixture ID replaced by "high-PV fixture" (pv_scale = 1.2); hour ranges rewritten as "hours 9 through 12 and 14 through 15".
- Lines mixing thesis equations with IDs (3.24-3.28, 3.37, 3.38/3.46/3.47, 3.43/3.45) kept verbatim.
- Pre-existing trailing spaces in three plan-19 `@testitem` names in test_planning_* were left alone (out of scope).

## Deviations from Plan
- [Rule 3] The `rtk` hook rewrites `git diff --name-only`; changed-file lists were taken from `git status --porcelain` instead.
- [Rule 1] An automated first pass for pure-ID parentheticals left a few dangling commas/parentheses; all were found in the diff review and fixed by hand.

## Known Stubs
None.

## Self-Check: PASSED
