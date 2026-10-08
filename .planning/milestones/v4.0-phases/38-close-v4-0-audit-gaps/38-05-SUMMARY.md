---
phase: 38-close-v4-0-audit-gaps
plan: 05
subsystem: stochastic-oos-reporting
tags: [status-policy, stochastic, out-of-sample, docs, writeup, results, explained-moves]
requires:
  - "38-04: run_stochastic oos.inexact_h / socp_maxratio_h, status :oos_inexact_skipped"
provides:
  - "status_policy.md documents :oos_inexact_skipped (RETURN line, throws cell, meaning, handler rule)"
  - "stochastic literate page reports excluded-inexact/infeasible counts and worst ratio live; figure plots usable draws only"
  - "compare_default_stochastic.jl inexact-aware (usable mask, inexact count/status printed, oos_inexact_draws row, inexact column)"
  - "refreshed seed-42 results/ and Portuguese writeup with an explained-move table"
affects: [38-07, 38-10]
tech-stack:
  added: []
  patterns: ["counts that depend on the solver build are computed live in the docs, never stated in prose"]
key-files:
  created:
    - .planning/phases/38-close-v4-0-audit-gaps/38-05-SUMMARY.md
  modified:
    - docs/src/status_policy.md
    - docs/literate/stochastic_pv_demand.jl
    - scripts/compare_default_stochastic.jl
    - docs/writeups/compare_default_stochastic.typ
    - results/compare_default_stochastic/{summary,oos_draws,dadp_tidy}.csv
    - results/compare_default_stochastic/{dadp_comparison,price_envelope,welfare_robustness}.{pdf,png}
    - .planning/phases/38-close-v4-0-audit-gaps/38-MEASUREMENTS.md
decisions:
  - "The stochastic page states no sign for welfare_gap; it points to the live value, because the usable-draw set (5/10 on 1.12.5, 2/10 excluded on 1.12.7) changes with the solver build"
  - "Seed-42 compare: the gate refused nothing, but the tracked artifacts (2026-09-08) were stale versus the current code; all moved numbers were refreshed and recorded as explained moves rather than left inconsistent with the regenerated CSVs"
metrics:
  duration: ~40min
  completed: 2026-10-07
  tasks: 2
  files: 15
requirements: [ARCH-08]
---

# Phase 38 Plan 05: Reporting the out-of-sample inexact skip (policy, docs page, compare script) Summary

The new out-of-sample failure mode now shows up everywhere a researcher reads stochastic
results. The status policy page documents `:oos_inexact_skipped`. The stochastic docs page
computes and prints the excluded-draw counts and plots only usable draws. The seed-42 comparison
script uses the same exclusion and reports its inexact count.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Status policy + stochastic literate page report the inexact skip live | c801de5 | status_policy.md, stochastic_pv_demand.jl, 38-MEASUREMENTS.md |
| 2 | Inexact-aware compare script, seed-42 re-run, writeup + results refresh | f6626b7 | compare_default_stochastic.{jl,typ}, results/compare_default_stochastic/*, 38-MEASUREMENTS.md |

The formatter (JuliaFormatter 2.10.2) changed nothing in either .jl file. `ast_equiv.jl HEAD` returned EQUAL, so no separate style commit was needed.

## Stochastic docs page (live, Julia 1.12.5)

held_out 10, excluded_inexact **5** (draws 4, 6, 7, 9, 10), excluded_infeasible 0, usable 5,
status `:oos_inexact_skipped`, worst ratio 1.6338, `welfare_gap` 0.032932 (it was 0.016867 before
the gate). This matches the 38-04 prediction exactly.

## compare_default_stochastic (seed 42) explained moves

**Gate effect: none.** 0/10 draws were refused and the status is `:solved`. `welfare_gap`
-0.0323948881649585 matches the pre-gate 38-04 measurement to the last digit.

The tracked artifacts were stale, though. They were last regenerated on 2026-09-08, before the
v4.0 modeling fixes. Re-running with the current code moves these numbers (cause not bisected):

| quantity | HEAD (2026-09-08 artifact) | re-run (1.12.5) | cause |
|----------|----------------------------|-----------------|-------|
| oos inexact draws | (not reported) | **0 / 10** | new row/column; gate refused nothing |
| run status | (not reported) | `:solved` | — |
| `oos_welfare_gap` | -0.03598937873448449 | **-0.0323948881649585** | stale artifact, not the gate |
| `oos_realized_welfare` | -538.7522475069767 | -538.786882964557 | same |
| `stoch_insample_welfare` | -538.7162581282422 | -538.754488076392 | same |
| `default_welfare` | -538.8475100160589 | -538.8957427671698 | same |
| `default_exact_maxgap` | 1.0646e-8 | 2.1427e-8 | same |
| `stoch_exact_maxgap_max` | 3.6416e-9 | 1.8695e-9 | same |
| DADP hours 4–6 (all sources) | ≈ 0.217–0.339 | ≈ 0.003–0.025 | same; hours 1–3, 7–9 unchanged to 3 decimals |
| `dadp_spread_max` (hour 7) | 0.12739706 | 0.12739705 | same |
| per-hour spread h4–h6 | 0.012–0.026 | 0.007–0.017 | same |
| solve times | 51.27 s / 9.59 s | 47.93 s / 9.45 s | wall time |

The writeup was updated for every moved number. The "< 1 % / ≤ 2.7 % of the local price" claims
were qualified, because they no longer hold in the PV valley where the price is near zero. A
held-out certification sentence (0/10 inexact) and a refresh note were added.

## Verification

- The literate page runs end to end as a script (exit 0). `check_planning_ids.py` passes.
- The compare script run via `suite_detached.sh` finished with done marker `0`. `oos_draws.csv` has the `inexact` column.
- `typst compile --root .` succeeds. `check_scripts_index.py`, `check_script_api.jl` (40 files), `ast_equiv.jl HEAD` (EQUAL) and `check_content_loss.py HEAD` all pass.

## Deviations from Plan

- **[Rule 1 - stale published numbers]** The plan expected to touch only the welfare_robustness figure and the CSVs. The re-run also moved `dadp_tidy.csv` and the dadp_comparison and price_envelope figures, because the 2026-09-08 artifacts predate later modeling changes. Those files were committed too, so results/ is consistent with itself and with the writeup. `scenario_fan.pdf` changed only in metadata and was restored. The writeup changes go beyond the single certification sentence for the same reason. Each move is in the ledger.
- The live counts for the ledger came from a one-off `-e 'include(...); println(...)'` run of the page. The plan's verify command (running the page as a script) was also run separately.

## Known Stubs

None.

## Threat Flags

None. T-38-11: seed 42 was re-run and the old/new values are in the ledger and the writeup. T-38-12: the page computes its counts live.

## Self-Check: PASSED

- FOUND: docs/src/status_policy.md (`oos_inexact_skipped`), docs/literate/stochastic_pv_demand.jl (`count(r.oos.inexact_h)`, `inexact_h`), scripts/compare_default_stochastic.jl (`inexact_h`), results/compare_default_stochastic/oos_draws.csv (`inexact`)
- FOUND commits: c801de5, f6626b7
