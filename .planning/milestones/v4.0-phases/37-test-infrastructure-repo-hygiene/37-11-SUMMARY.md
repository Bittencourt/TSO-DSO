---
phase: 37-test-infrastructure-repo-hygiene
plan: 11
subsystem: scripts
tags: [pv_boom, report, refactor, dedup]
requires: [37-10]
provides:
  - scripts/lib/pv_boom_common.jl (shared pv_boom report helpers)
  - scripts/pv_boom_report.jl (single merged report, main + guard, writes report.html)
affects: [scripts]
key-files:
  created: [scripts/lib/pv_boom_common.jl, scripts/archive/pv_boom_report_v1.jl]
  modified: [scripts/pv_boom_report.jl]
  removed: [scripts/pv_boom_report_v2.jl]
decisions:
  - "welfare_deltas_html takes (sweep, ok_rows) and exact_maxgaps_html takes ok_rows; both keep the provenance flag"
metrics:
  completed: 2026-10-06
  tasks: 3
requirements: [HYG-08]
---

# Phase 37 Plan 11: pv_boom report merge Summary

The two duplicated pv_boom report scripts are now one report script plus a shared helper library, with v1 archived. The regenerated HTML is byte-identical to the pre-merge v2 output after normalization.

## Precondition
Plan 10 ended approved (11:16 re-tune, commit 1ff6147). `data/pv_boom/results.jld2` exists, written 11:02, just before that commit (committed 11:04) at the end of the plan 10 run. It holds the `DlmpDecomposition` struct and the report ran on it.

## Tasks
1. Pre-merge baseline: ran the unmodified `pv_boom_report_v2.jl` (docs env, Julia 1.12, detached) against the regenerated results; saved to `.planning/tmp/37/report_v2_premerge.html` (530 kB, one `<h1>`). No commit (scratch, gitignored).
2. Refactor (commit fec5ce0): `scripts/lib/pv_boom_common.jl` with `pv_boom_load_results`, `pv_boom_stressed_bus`, `pv_boom_figures`, `figure_to_data_uri`, `welfare_deltas_html`, `exact_maxgaps_html`, `sweep_table_html`, `nash_table_html`. `scripts/pv_boom_report.jl` is the former v2 as `main(results_path, outdir)` plus an `abspath(PROGRAM_FILE) == @__FILE__` guard, writing `report.html`. v1 moved to `scripts/archive/pv_boom_report_v1.jl` with an archived header. `scripts/pv_boom_report_v2.jl` no longer exists. HTML prose, SVG and CSS are unchanged except the script name in the reproducibility text.
3. Regenerated `results/pv_boom/report.html` (gitignored) and compared with the baseline.

## Equivalence
Highest level achieved: normalized text equality (base64 PNG payloads masked, `report_v2` to `report`, 7-40 char hex tokens masked): EQUAL, 46454 chars each. The git stamp was identical (b6025dd) since HEAD did not move between runs. The structural fallback was not needed.

## Verification
- `check_script_api.jl`: OK, 40 files; `--selftest` OK (55 cases)
- `check_planning_ids.py`: OK, 248 files

## Deviations from Plan
None. `welfare_deltas_html` also takes `ok_rows` (plan listed `sweep` only); names were discretionary.

## Notes
HYG-08 intentionally not marked complete (plan 12 remains).

## Self-Check: PASSED
Files exist (lib, report, archived v1); commit fec5ce0 exists.
