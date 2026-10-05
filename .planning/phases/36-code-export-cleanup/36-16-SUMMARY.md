---
phase: 36-code-export-cleanup
plan: 16
subsystem: hygiene
tags: [planning-id-scrub, scripts]
requires: ["36-15"]
provides:
  - scripts/ free of planning identifiers (classifier TOTAL 0 over the plan file set)
affects: [36-17]
key-files:
  modified:
    - scripts/benchmark_ieee8500.jl
    - scripts/profile_ieee8500_memory.jl
    - scripts/run_ieee8500_point.sh
    - scripts/reduce_ieee8500_impedances.jl
    - scripts/reduce_ieee123_impedances.jl
    - scripts/thesis_case123_repro.jl
    - scripts/thesis_caseA.jl
    - scripts/benders_toy.jl
    - scripts/compare_default_stochastic.jl
    - scripts/demo_mpc_plots.jl
    - scripts/pv_boom_case_study.jl
    - scripts/pv_boom_report.jl
    - scripts/pv_boom_report_v2.jl
    - scripts/reactive_flake_rate.jl
    - scripts/repro_stability_check.jl
    - scripts/run_scenario.jl
    - scripts/socp_applicability_sweep.jl
    - scripts/sweep.jl
    - scripts/demo_flexibility_plots.jl
requirements-completed: []
completed: 2026-10-05
---

# Phase 36 Plan 16: Scrub of scripts/ Summary

About 330 hit lines in 19 script files were rewritten as plain prose; the rationale, measured numbers, file citations and thesis-equation or literature references are kept. Planning-artifact citations (`.planning/` paths, `*-SUMMARY.md`, `deferred-items.md`, spike directories, research documents, quick-task numbers) were replaced by the fact itself or by a pointer to `docs/literate/ieee8500_scaling.jl`, `docs/literate/socp_applicability.jl` or the earlier documented measurement. `run_tests_filtered.jl` and `scripts/data` had no hits and are untouched. HYG-01 stays pending.

## Commits
- b85047d: scrub ieee8500, reduction and thesis-repro scripts (task 1)
- abc2e19: formatter pass (benchmark_ieee8500, profile_ieee8500_memory, reduce_ieee8500_impedances)
- 96ef08a: scrub remaining scripts (task 2)
- b30fa20: formatter pass (compare_default_stochastic, demo_mpc_plots, pv_boom_*, repro_stability_check, socp_applicability_sweep)

Formatter passes: JuliaFormatter 2.10.2 only; `check_content_loss.py HEAD` printed `OK: no content change` before each formatter commit.

## Verification
- Classifier: `TOTAL 0` over the whole plan file set.
- `ast_equiv.jl` against the pre-plan commit (recorded in `.planning/tmp/36/p16_start.txt`): EQUAL for every touched `.jl` file.
- `thesis_tokens.py` against the pre-plan commit: OK for all touched files. No memory-slug false positives this time.
- All touched `.jl` files parse; `run_ieee8500_point.sh` passes `bash -n` and its diff is comment lines only.
- Harness test `julia --project=. test/test_benchmark_ieee8500.jl`: see "Targeted test" below. `git status --short results/` is clean.
- No IEEE-8500 benchmark was run. No full suite run (last full suite remains p13 = 32202/0/0/5).

## Message changes
No `src/` messages or `@testitem` names changed. String literals inside scripts (printed output, report prose, one error text). No test asserts on any of them (grepped `test/`):

- `benchmark_ieee8500.jl`: ArgumentError text for `--admm-atol` lost the trailing `(T-35-04)`.
- `reduce_ieee8500_impedances.jl`: ArgumentError text for the degenerate-segment check lost `(deferred-items.md item 1)`.
- `reduce_ieee8500_impedances.jl` `emit_output` header printlns: the text emitted into the generated `src/data/ieee8500_impedances.jl` was rewritten to follow the already-scrubbed committed header (D-05, D-09, D-13, Assumption A1/A2, 25-RESEARCH.md and quick-task references removed). The number of `println` calls is unchanged (AST-equal), so a few line wraps differ from the committed header (the casualty-bus paragraph and the final merge paragraph are split over more lines). The committed data file is NOT regenerated; only the header comment wrap would differ on regeneration.
- `pv_boom_case_study.jl`: printed and findings text `EXACT-04 finding` became `high-PV exactness finding`; `socp_maxgap (PF-04)` lost the tag; `INEXACT (EXACT-04)` lost the tag.
- `pv_boom_report.jl`, `pv_boom_report_v2.jl`: HTML prose and headings (`3.4 The high-PV stress fixture`, `4.5 High-PV exactness boundary: ...`, `PF-04 gate` to `exactness gate`, `RESEARCH A5` reference dropped, `hours 13-18` to `hours 13 through 18`). Committed `results/pv_boom/*.html` are stale until regenerated; not regenerated here.
- `compare_default_stochastic.jl`: summary-table description strings lost `PF-04`, `D-06`, `D-07`, `D-09`, `WR-05`.
- `demo_mpc_plots.jl`: printed lines and figure labels lost `FIX-10`, `Phase-27`, `plan 27-09`, `D-10`, `D-06`.
- `reactive_flake_rate.jl`, `repro_stability_check.jl`: findings-file prose lost Phase/Plan/RESEARCH/threat references. Section headings that downstream code or tests key on (`sign_flip_survives:`, `=== RECOMMENDED BAND ===`, `=== Flake rate ===`) are unchanged. `=== Finding 2: rho vs rho_q (Open Question 1) ===` became `=== Finding 2: rho vs rho_q ===`.
- `socp_applicability_sweep.jl`: two `@warn` texts (`EXACT-04 ... drifted from PM-01/26-18`) reworded to `high-PV ... control drifted from its measured exact verdict`; printed control line lost `(EXACT-04)` and `PM-01/26-18`; `GATE-1` to `gate-1`.
- `thesis_case123_repro.jl`: figure-caption string `18-01's original` to `the original`.

## ID-bearing data literals left (guard allowlist candidates)
None left in this plan's files that determine output paths, CSV schemas, run labels or CLI flags: the classifier reports TOTAL 0, so no allowlist entries are needed from scripts/. Existing literals such as the result directory names (`results/ieee8500_benchmark`, `results/repro_stability_check`, `results/pv_boom`) and the CSV column names (`density`, `t_horizon`, `admm_atol_used`, `clarabel_tol_gap`, `diag_max_ratio`, `hybrid_diagnostic.csv`, ...) were not touched.

## Hand-edited MIXED lines
The classifier reported no MIXED lines in this plan's set. Thesis-equation and literature references (eq. 3.12, 3.24-3.28, 3.38, Case A "DSO surplus -$2829 -> +$439", Fig. 4.4, App. C, the arXiv/OpenDSS references) are verbatim; `thesis_tokens.py` confirms.

## Deviations from Plan
- [Rule 1] Process wording the classifier cannot catch was reworded: `byte-identical` to `bit-for-bit identical`/`identical`/`unchanged`, `Rule 1`/`Deviation (Rule 1 ...)` to `Note (discovered while running)`, `this research session`, `this task`/`this plan`/`this phase`, `Claude's discretion`, `Not yet wired ... (Task 2 finishes ...)`, `hours 13-18`.
- Plan Task 1 verify uses `git diff --name-only` with `scripts/data`; `thesis_tokens.py` cannot take a directory, so it was run on the changed files only (none under `scripts/data`).
- Plan step "record the pre-plan hash in `.planning/tmp/36/`": recorded as `p16_start.txt`.

## Targeted test
`julia --project=. test/test_benchmark_ieee8500.jl`: ALL TESTS PASSED (10/10 deterministic goldens on the --quick point, 34/34 harness flags, schema and rejections). `git status --short` clean afterwards (no `results/` changes).

## Known Stubs
None.
