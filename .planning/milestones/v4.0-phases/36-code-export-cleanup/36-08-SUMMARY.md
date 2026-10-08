---
phase: 36-code-export-cleanup
plan: 08
subsystem: hygiene
tags: [planning-id-scrub, rename, benders, nash]
requires: ["36-07"]
provides:
  - FIX08 constants renamed to content names
  - src/planning/benders.jl and nash.jl free of planning identifiers
affects: [36-09, 36-10]
key-files:
  modified:
    - src/models/exactness.jl
    - src/admm/solve_admm.jl
    - src/admm/DsoOpt.jl
    - test/test_admm_exactness_default.jl
    - scripts/benchmark_ieee8500.jl
    - src/planning/benders.jl
    - src/planning/nash.jl
requirements-completed: [HYG-01]
completed: 2026-10-05
---

# Phase 36 Plan 08: FIX08 rename and benders/nash scrub Summary

`MEASURED_ε_FIX08` became `MEASURED_REL_TOL_EXACT` and `TAU_SOLVER_FIX08` became `TAU_SOLVER_EXACT` (values unchanged, whole-identifier rename), and `benders.jl` and `nash.jl` were scrubbed from 344 classifier hits to TOTAL 0.

## Commits
- 18ea0b8: constant rename in exactness.jl, solve_admm.jl, DsoOpt.jl, test_admm_exactness_default.jl, benchmark_ieee8500.jl. Also dropped the `(@ref)` links to the two comment-only constants (the docs warnings reported by plan 06) and scrubbed the comment blocks above their definitions.
- 587092e: planning-ID scrub of benders.jl and nash.jl (comments, docstrings, 5 runtime strings).
- e6ce884: JuliaFormatter 2.10.2 pass (check_content_loss reported OK before commit).

## Verification
- `grep -rn FIX08` over src, ext, test, scripts, docs/literate and docs/src: empty.
- Classifier on benders.jl and nash.jl: TOTAL 0.
- ast_equiv.jl: EQUAL for benders.jl, nash.jl, solve_admm.jl, DsoOpt.jl, benchmark_ieee8500.jl. exactness.jl and test_admm_exactness_default.jl report DIFF against the plan-start commit only because of the intentional identifier rename; `--literals` run before the commit was EQUAL for all seven files.
- thesis_tokens.py: OK.
- Targeted tests (exactness, ieee13, exactness default, knife-edge canary, migration gate, noninteger, benders, nash, bilevel): 385 pass, 0 failed, 0 errored, 2 broken (pre-existing). Post-format rerun: 290 pass, 0 failed, 1 broken. The canary was not re-pinned.

## Message changes
Runtime strings changed (no test asserts any of them; verified by grep of `test/`):

benders.jl
- corner_recourse non-finite check: `report as a bug (WR-01 regression, Phase 24 code review).` became `report as a bug (zero-corner feasibility regression).`
- _corner_recourse_joint non-finite check: `(T-dimensional generalization of WR-01, Phase 27 FIX-06).` became `(T-dimensional zero-corner feasibility regression).`
- _assert_epigraph_floor: `— BILEV-05: this is a genuine modeling bug` became `— this is a genuine modeling bug`.
- oracle/feasibility disagreement error: `... carries any information (WR-01/WR-06).` became `... carries any information.`
- weak-cut stall error: `... measures only v=... (WR-06).` became `... measures only v=....`

nash.jl
- run_nash! parity re-solve: `run_nash!: CR-01 parity re-solve ...` became `run_nash!: parity re-solve ...`.
- run_nash_probe seeds and orders guards: `(CONTEXT.md's locked minimum)` became `(the required minimum)`.

No `@testitem` name strings were changed.

## Hand-edited MIXED lines
The classifier reported no MIXED lines for these files. Thesis and literature references (Rosen 1965, Laporte-Louveaux, Kelley, thesis equation numbers) were left verbatim, confirmed by thesis_tokens.py.

## Deviations from Plan
- exactness.jl: only the constant definitions, their comments and the two `(@ref)` docstring links were touched, as the task specifies. The remaining 39 hits in exactness.jl belong to plan 10, which lists that file.
- [Rule 1] The formatter drops a docstring code span wrapped so a continuation starts with `|` (nash.jl, `|Δx_inv_i|`); the span was re-wrapped before the formatter pass.
- Wording such as "byte-identical" was rewritten as "bit-for-bit identical" where the bitwise meaning matters.

## Known Stubs
None.

## Self-Check: PASSED
