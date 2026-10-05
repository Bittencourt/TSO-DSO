---
phase: 36-code-export-cleanup
plan: 17
subsystem: hygiene
tags: [planning-id-scrub, tests, fixtures]
requires: ["36-16"]
provides:
  - test fixtures, runtests.jl, test/Project.toml and test_a* through test_d* free of planning identifiers (classifier TOTAL 0 over the plan file set)
affects: [36-18]
key-files:
  modified:
    - test/fixtures_*.jl (11 files)
    - test/runtests.jl
    - test/Project.toml
    - test/test_abstract_feeder.jl
    - test/test_ac_oracle.jl
    - test/test_ac_powerflow.jl
    - test/test_acceptance.jl
    - test/test_admm.jl
    - test/test_admm_adaptive.jl
    - test/test_admm_dualresid.jl
    - test/test_admm_exactness_default.jl
    - test/test_admm_generic_pf.jl
    - test/test_admm_knifeedge_canary.jl
    - test/test_admm_meshed.jl
    - test/test_admm_phases.jl
    - test/test_admm_reactive.jl
    - test/test_admm_timeout.jl
    - test/test_aggregator.jl
    - test/test_agr.jl
    - test/test_benchmark_ieee8500.jl
    - test/test_close_balance.jl
    - test/test_conformance.jl
    - test/test_context.jl
    - test/test_convex_branch_flow.jl
    - test/test_deferrable.jl
    - test/test_device.jl
    - test/test_diagnostics_plot.jl
    - test/test_dlmp.jl
    - test/test_dso.jl
requirements-completed: []
completed: 2026-10-05
---

# Phase 36 Plan 17: Scrub of fixtures, runtests and test files a-d Summary

About 650 hit lines in 39 files (11 fixtures, runtests.jl, test/Project.toml and 26 test files) were rewritten as plain prose. Rationale, measured numbers, thesis-equation and literature references were kept; planning-artifact citations (`.planning/` paths, `*-SUMMARY.md`, `26-POSTMERGE-TRIAGE.md`, research documents, quick-task numbers, `softscope_scan.py`) were replaced by the fact itself. HYG-01 stays pending.

## Commits
- 3f18398: scrub fixtures, runtests, Project.toml, test_a*, test_admm.jl, test_admm_[a-g]* (task 1)
- c2c0dc0: formatter pass for task 1 (test_abstract_feeder, test_ac_oracle, test_ac_powerflow, test_admm, test_admm_exactness_default, test_admm_generic_pf, fixtures_mesh, fixtures_planning, fixtures_planning_ieee13_short)
- 065df9c: scrub test_admm_[h-z]*, test_ag*, test_[b-d]* (task 2)
- 4e22f5d: formatter pass for task 2

Formatter passes: JuliaFormatter 2.10.2 only. `check_content_loss.py HEAD` printed `OK: no content change` before each formatter commit, with one exception handled by hand: on `test_benchmark_ieee8500.jl` the formatter rewrote the one-line docstring of `run_harness` as a triple-quoted block (+4 quote characters, AST equal). That single hunk was reverted to the original one-line form before the formatter commit, so the file keeps its original docstring form and the final check is OK. Re-running the formatter would re-apply it; it is harmless but was left out to keep the content-loss gate green.

## Verification
- Classifier: `TOTAL 0` over the whole plan file set.
- `ast_equiv.jl` against the pre-plan commit (recorded in `.planning/tmp/36/p17_start.txt`, 5f8a8e7): EQUAL for all 38 changed `.jl` files; `ast_equiv.jl --literals` against the same commit: EQUAL for all of them, so no golden, tolerance, canary number (iters = 56, welfare = -4823.66604824162) or assertion changed.
- `thesis_tokens.py` against the pre-plan commit: OK for all changed files (one early DIFF on `fixtures_small_radial.jl` caused by added "thesis" wording was fixed).
- Targeted tests (pass counts equal the AST-equal pre-edit state; 0 failed, 0 errored):
  - task 1 set (`test_admm_exactness_default`, `test_admm_adaptive`, `test_ac_oracle`, `test_ac_powerflow`, `test_abstract_feeder`, `test_admm_dualresid`, `test_admm_generic_pf`): 173/173 pass.
  - task 2 set (`test_admm_knifeedge_canary`, `test_admm_phases`, `test_dso`, `test_close_balance`, `test_admm_meshed`, `test_agr`, `test_aggregator`, `test_convex_branch_flow`, `test_context`, `test_deferrable`, `test_device`, `test_dlmp`, `test_conformance`, `test_diagnostics_plot`, `test_admm_reactive`): 607 pass, 1 broken (existing `@test_broken`), 0 fail.
  - plain scripts: `test/test_admm_timeout.jl` 19/19, `test/test_benchmark_ieee8500.jl` all pass.
- No full suite run (last full suite remains p13 = 32202/0/0/5).

## Message changes
No `src/` messages changed. Strings changed in `test/`:

Renamed `@testitem` names (IDs and process wording removed; no CI, script or doc filter references any old name, grepped):
- `test_ac_oracle.jl`: five items lost `(EXACT-01, ...)`, `(RED-guard for plan 15-02)`, `(EXACT-02/EXACT-03)`, `(EXACT-03 ...)`, `(EXACT-04)`.
- `test_ac_powerflow.jl`: four items lost `(EXACT-01)`, `(EXACT-01 / INFRA-02)`, `(EXACT-01)`, `(PM-07)`.
- `test_admm_exactness_default.jl`: lost `(WR-06)`. `test_admm_generic_pf.jl`: lost `IN-07`.
- `test_admm_meshed.jl`: three items lost `(ARCH-06)`, `(ARCH-06)`, `(ARCH-06, T-34-33)`.
- `test_admm_reactive.jl`: "kwarg absent today, qag_dso coupling variable pinned once landed" became "kwarg exists, qag_dso coupling variable has the expected shape"; "is byte-identical to today" became "is unchanged"; `(WR-04)` removed.
- `test_aggregator.jl`: ten items lost `DEV-05`, `IN-01`, `MESH-04, D-09/D-10`, `FIX-05`, `26-07`, `WR-03, phase-26 review`, `MPC-01`; "byte-identity/byte-identical" became "bit-for-bit identity/identical". Equation references (eqs. 3.21-3.23) kept.
- `test_close_balance.jl`: four items lost `(ARCH-04)`, `(WR-05)`.
- `test_conformance.jl`: lost `crit 4`. `test_context.jl`: eight items lost `PF-01`, `PF-02`, `WR-04`, `ARCH-07`.
- `test_convex_branch_flow.jl`: eight items lost `PF-03`, `INFRA-02`, `FIX-01/02`, `FIX-02`, `PRICE-02`, `FIX-03`.
- `test_deferrable.jl`: seven items lost `DEV-02`, `WR-01`; thesis 3.4/3.12 references kept.
- `test_device.jl`: two items lost `DEV-03`, `FIX-05`. `test_dlmp.jl`: two items lost `PRICE-02`. `test_dso.jl`: `PF-04 gate` became `the exactness gate`.
- `@testset` labels: `solve_admm time_limit_s (D-18)` became `solve_admm time_limit_s`; `D-16 deterministic goldens on the --quick point` became `deterministic goldens on the --quick point`; `phase 35-02 harness flags, schema, rejections` became `harness flags, schema, rejections`.

Other string literals (no test asserts on any):
- `fixtures_experiment_harness.jl`: scenario `name = "phase8-fixture"` became `"harness-fixture"` (used only there).
- `test_admm_meshed.jl`: `@info` labels `ARCH-06 measured/worst price gap/angle uniform/angle heterogeneous` became `meshed ADMM ...`.
- `test_acceptance.jl`: `@info` note `(Open Q1: inputs figure-bound)` became `(inputs are figure-bound)`.

## Hand-edited MIXED lines
Lines that mixed an ID with a thesis-equation reference were edited by hand with the reference verbatim: `test_aggregator.jl` (eqs. 3.21-3.23, thesis eq. 3.23), `test_agr.jl` (thesis eq. 3.46, 3.22/3.23/3.46), `test_deferrable.jl` (thesis eq. 3.4, 3.4/3.12), `test_dso.jl` (thesis eq. 3.47). `thesis_tokens.py` confirms.

## Deviations from Plan
- [Rule 1] Process wording the classifier cannot catch was reworded: `RED/GREEN` gates ("RED until plan ... lands", "RED test-item harness (Wave 0)"), `Rule 1/3 auto-fix`, `DEVIATION`, `Open Q`, `this plan`, `this session`, `per the plan`, `byte-identical`, `Claude's discretion`, `pre-33-05`, memory-slug references, and the `softscope_scan.py` path in `runtests.jl`.
- The reactive-consensus naming audit header in `test_admm_reactive.jl` (about 85 lines of grep transcript with stale file:line numbers) was condensed to its conclusion, chosen identifiers and out-of-scope note; the rationale is kept.
- Plan Task 3 asks to record the pre-plan hash in `.planning/tmp/36/`: recorded as `p17_start.txt`.

## Known Stubs
None.

## Self-Check: PASSED
