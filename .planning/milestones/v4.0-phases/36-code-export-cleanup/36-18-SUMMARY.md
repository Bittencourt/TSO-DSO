---
phase: 36-code-export-cleanup
plan: 18
subsystem: hygiene
tags: [planning-id-scrub, tests]
requires: ["36-17"]
provides:
  - test/test_[e-m]*.jl free of planning identifiers (classifier TOTAL 0 over the plan file set)
affects: [36-19]
key-files:
  modified:
    - test/test_economic_direction.jl
    - test/test_exactness.jl
    - test/test_exactness_verdict.jl
    - test/test_experiments.jl
    - test/test_factory.jl
    - test/test_feeder.jl
    - test/test_fit.jl
    - test/test_fourquadbess.jl
    - test/test_ieee123.jl
    - test/test_ieee123_admm.jl
    - test/test_ieee13.jl
    - test/test_ieee8500.jl
    - test/test_linear_solve.jl
    - test/test_mesh_angle_certificate.jl
    - test/test_mesh_feeder.jl
    - test/test_mesh_flow.jl
    - test/test_model_context_traits.jl
    - test/test_mpc_loop.jl
    - test/test_mpc_terminal.jl
    - test/test_mpc_trace.jl
    - test/test_mpc_window.jl
    - test/test_exports.jl (formatter only)
    - test/test_model_context_migration_gate.jl (formatter only)
requirements-completed: []
completed: 2026-10-05
---

# Phase 36 Plan 18: Scrub of test files e-m Summary

About 350 hit lines in 21 files were rewritten as plain prose; rationale, measured numbers and thesis-equation or literature references were kept. Planning-artifact citations (research documents, `*-SUMMARY.md`, `*-REVIEW.md`, `.planning/` paths, quick-task numbers, plan/task/decision IDs) were replaced by the fact itself. HYG-01 stays pending.

## Commits
- 846aacd: scrub test_[e-i]* (task 1)
- e67006d: scrub test_[j-m]* (task 2)
- 092c2d3: JuliaFormatter 2.10.2 pass over test_[e-m]* (task 3; touched 13 files, including the two formatter-only files test_exports.jl and test_model_context_migration_gate.jl)

Formatter: `check_content_loss.py HEAD` printed `OK: no content change` before the formatter commit; no hunk had to be reverted. A second formatter run is a no-op.

## Verification
- Classifier: `TOTAL 0` over `test/test_[e-m]*.jl`.
- `ast_equiv.jl` and `ast_equiv.jl --literals` against the pre-plan commit 8447eea (recorded in `.planning/tmp/36/p18_start.txt`): EQUAL for all changed `.jl` files, so no golden, tolerance, canary number or assertion changed.
- `thesis_tokens.py` against 8447eea: OK for all changed files.
- Targeted tests (0 failed, 0 errored): 17 files (exactness, experiments, ieee13, fit, economic_direction, exactness_verdict, ieee123_admm, fourquadbess, ieee8500, ieee123, factory, feeder, mesh_flow, mesh_angle_certificate, mesh_feeder, mpc_terminal, mpc_window, mpc_trace plus mpc_loop and linear_solve) pass 27674 + 379 with the one existing `@test_broken`.
- No full suite run (last full suite remains p13 = 32202/0/0/5).

## Message changes
No `src/` messages changed. No test asserts on any changed string.

Renamed `@testitem` names (IDs and process wording removed; grepped `scripts/`, `.github/`, `docs/make.jl`, `test/runtests.jl`, fixtures: no filter references any old name):
- `test_experiments.jl`: `EXP-01 scenario centralized/admm/strategy guard`, `EXP-02 sweep`, `EXP-02 sweep diff-friendly`, `INFRA-04 same-seed repro (admm)`, `INFRA-04 seed sensitivity (admm)`, `INFRA-04 provenance tagsave`, `ARCH-02 filename identity/result_to_dict flat primitives/run_and_store round-trip/mixed-strategy sweep collate`, `REVIEW WR-05 over-length filename fallback ...`, `WR-01 (phase-22 review): Scenario copies ...`, `WR-02 (phase-22 review): scenario_filename identifies ...` all became `experiments: <same description>` (the substrings scenario, sweep, repro, provenance, tagsave are kept).
- Trailing `(PRICE-05)`, `(PF-04)`, `(WR-01)`, `(FIX-08)`, `(FIX-08, plan 27-07)`, `(PRICE-04)`, `(FIX-09, plan 27-09)`, `(DATA-01)`, `(DATA-03)`, `(OPT-02/OPT-03)`, `(INFRA-02)`, `(MESH-04)`, `(D-0x)`, `(FIX-04)`, `(MPC-01 seam)`, `(CR-01)`, `(T-19-11)`, `(WR-0x)`, `(MESH-0x/D-0x)`, `(review CR-01/WR-03)`, `(MPC-03 price-consistency metrics)`, `(MPC-02 mechanism)`, `(CR-02, 27-REVIEW.md)`, `(WR-04, 27-REVIEW.md iteration 2)`, `(D-03, checker revision 1)`, `(plan 25-04)`, `(ieee8500)` etc. were stripped from the item names in the corresponding files.
- `test_exactness_verdict.jl`: `... 3-way regression (FIX-01)` lost the suffix.
- `test_fourquadbess.jl`: `... byte-identical default (MPC-01 seam)` became `... bit-for-bit identical default`; `D-08` removed from the `honest boundary` item name.
- `test_ieee8500.jl`: `D-06 measured per-unit impedance spread is reported (ieee8500)` became `measured per-unit impedance spread is reported`; `... byte-identical to its pre-plan-25-04 golden` became `... bit-for-bit identical to its golden`; `DEV-05` dropped from the FixedCapacitor item name.
- `test_linear_solve.jl`: `(crit 3, price)` became `(price)`.
- `test_mpc_loop.jl`: `Phase-20's ladder` became `the escalation ladder`; `(CR-02, 27-REVIEW.md)`, `(WR-04, 27-REVIEW.md iteration 2)`, `(D-03, checker revision 1)` removed.
- `@testset` labels in `test_ieee8500.jl`: `(6) D-06 measured ...` became `(6) measured ...`; `(9) ... byte-identical golden (plan 25-04)` became `(9) ... bit-for-bit identical golden`; `(plan 25-04)` removed from items (7), (8), (10).

Other string literals (printed or logged only, no assertion):
- `test_ieee8500.jl`: two `println` strings `"D-06 measured per-unit impedance spread: ..."` became `"measured per-unit impedance spread: ..."`.
- `test_ieee13.jl`: `@info` label `ieee13 ground: thesis v₉[16] cross-check (Assumption A1)` lost `(Assumption A1)`; its `note` text `(Open Q1: inputs figure-bound)` became `(inputs figure-bound)`.
- `test_mpc_terminal.jl`: `@info "mpc_terminal MPC-02 measured deviations"` became `"mpc_terminal measured deviations"`.

## Hand-edited MIXED lines
Lines that mixed an ID with a thesis or literature reference were edited by hand with the reference verbatim: `test_ieee13.jl` (thesis Table 4.1, Fig 4.2/4.4/4.5, App. E figures), `test_ieee123.jl` (thesis App. E), `test_exactness.jl` (Gan-Low direction in `test_exactness_verdict.jl`), `test_fourquadbess.jl` (App. C), `test_linear_solve.jl`. `thesis_tokens.py` confirms.

## Deviations from Plan
- [Rule 1] Process wording the classifier cannot catch was reworded: `RED/GREEN` and `Wave N` harness headers and `RED until plan ... lands` guards (removed or rephrased as guard descriptions), `USER DECISION`, `DEVIATION`, `Rule 1 fix`, `Claude's discretion`, `this session`, `Open Q`, `Pitfall N`, `byte-identical`, `plan-checker`, `the plan's ...`, `RESEARCH ...`, `git stash` mention in a test comment, `.planning/` paths.
- Large historical narrative comments (seed-1 restoration history in `test_mpc_loop.jl`, the price-choice header of `test_mpc_terminal.jl`, the item header comment of `test_experiments.jl`) were condensed to their technical rationale and measured numbers.
- The A1/A2/A3/A6 assumption labels that the classifier does not flag were removed where they appeared in `test_ieee13.jl`; `Assumption A6` remains in two comments of `test_fourquadbess.jl`/`test_mpc_loop.jl` (a model assumption, not a process ID).
- Plan Task 3 asked to run format210 once more as a no-op: confirmed no-op after the formatter commit.

## Known Stubs
None.

## Self-Check: PASSED
