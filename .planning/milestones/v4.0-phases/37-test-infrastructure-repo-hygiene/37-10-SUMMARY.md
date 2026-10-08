---
phase: 37-test-infrastructure-repo-hygiene
plan: 10
subsystem: case-studies
tags: [pv-boom, exactness-gate, fixture-retune, planning-layer]
requires: [37-09]
provides:
  - pv_boom case study passes the SOCP exactness gate end to end at HEAD (Part A, A2, B)
  - regenerated data/pv_boom/results.jld2 (gitignored) and tracked results/pv_boom summary.csv + findings.txt
key-files:
  modified: [scripts/pv_boom_case_study.jl, results/pv_boom/summary.csv, results/pv_boom/findings.txt]
decisions:
  - Part B planning sub-horizon PLANNING_HOURS 13:18 -> 11:16 (script-level only); user approved
  - no src, gate or tolerance change
metrics:
  tasks: 3
  completed: 2026-10-06
---

# Phase 37 Plan 10: PV-boom fixture re-tune Summary

The boom case study's Part B planning window moved from hours 13:18 to 11:16, so the first Benders trial passes the exactness gate. The case study now runs end to end, and its results are regenerated. No src, gate or tolerance changed.

## Commits
- 1ff6147: script re-tune with Calibration header; regenerated summary.csv and findings.txt

## Diagnosis (scratch copy; note in .planning/tmp/37/pv_boom_diagnosis.md, ignored)
- Failure: `run_nash!` first trial (z=0) was refused. Worst gap/bound was 4679 and max |l*v-(P^2+Q^2)| was 1.78e-3, identical on all three bound-widening attempts, so it is a fixture property.
- Where: only hour 18 (last hour of 13:18) for the boom distributor (pv_mult 2.5), on every branch. Hours 13-17 had gap <= 1.1e-7. The baseline (0.7) was exact on every window tested (gap <= 1.3e-7).
- Mechanism: at z=0 boom PV is about 10x demand (0.2-0.5 vs 0.03 p.u.), surplus is curtailed at zero value, so the price is about 0. Hour 18 is the surplus-to-deficit crossover (dadp 5.5e-5 vs lambda0 9), and reactive circulation on the feeder head makes dissipation free, so the cone goes slack.
- Windows: 13:18 inexact (1.78e-3); 12:17 inexact (1.63e-3); 11:16 converges on attempt 1; 10:15 exact at z=0 (probe only, not run through `run_nash!`).
- Rejected: lowering boom penetration (1.5 converges but dilutes the boom; 2.0 trips the separate battery-complementarity gate).

## Calibration rationale
11:16 is a contiguous six-hour block around the solar peak with the same boom PV-to-demand ratio, and it covers the 8:16 deferrable window entirely (local hours 1:6). It drops only the evening ramp (hours 17-18), where the pinned-import oracle sits at a degenerate zero-price crossover. Retained: the 0.7 vs 2.5 contrast and the qualitative outcome (converged in 1 sweep, x_inv = [0, 0], not differentiated, reported as found). Lost: the evening ramp is no longer in the planning game. The full text is in the script's Calibration header.

## Results
- Run exit 0; no `REFUSED` and no `SOCP relaxation INEXACT` in the log. Part B converged on attempt 1, sweeps = 1, x_inv = [0, 0].
- Part A: 6/6 points exact (exact_maxgap 1.0e-9 to 3.5e-8); welfare at 2.5 is -4822.791 (delta +7.34 vs baseline). ADMM cross-check relative gap 5.1e-6, 92 iterations. Part A2 reproduces INEXACT at 10 of 24 hours.
- results.jld2 keys: ac_stress, admm_crosscheck, nash_result, pv_mults, sweep.
- The old committed CSV was stale versus HEAD (earlier model corrections); the differences from it are not caused by this re-tune, which only changes Part B.
- `git diff -- src` empty; non-comment diff has no gate or tolerance lines; `check_script_api.jl` and `check_planning_ids.py` pass.

## Deviations from Plan
1. [Rule 3 - Blocking] `results/pv_boom/findings.txt` is tracked, rewritten by the script and was stale, so it was committed with summary.csv (the plan listed only summary.csv).
2. Plan wording says `decomp` NamedTuples keyed cone/drop. In fact `decomp` is a `DlmpDecomposition` struct with fields `energy, cone, drop, congestion, reactive, total`. The `.cone` and `.drop` access the report scripts use works as intended.

## Checkpoint
Task 3 (human-verify) was reached and the user approved the re-tune (11:16, commit 1ff6147).

## Known Stubs
None.

## Self-Check: PASSED
Commit 1ff6147 exists; the modified files are present.
