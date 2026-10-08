---
phase: 38-close-v4-0-audit-gaps
plan: 03
subsystem: docs-prose
tags: [stale-prose, strategy-dispatch, mpc, stochastic, comment-only]
requires:
  - "38-02: MPC first tier through _socp_cone_check (hybrid floor)"
provides:
  - "Include-site comments and Rung 8/9 literate pages state run(::MPC)/run(::Stochastic) dispatch, run_scenario(s) = run(s.strategy, s), thin run_mpc/run_stochastic wrappers, knobs on s.strategy"
  - "MPC test/fixture/literate comments name the first-tier exactness check (shared kernel, rtol = 1e-4, hybrid per-branch floor); old ratio literals restated as ≈ 9.2×10³"
affects: [38-10]
tech-stack:
  added: []
  patterns: ["comment-only edits proven with ast_equiv.jl (EQUAL) + parse check + content-loss guard"]
key-files:
  created:
    - .planning/phases/38-close-v4-0-audit-gaps/38-03-SUMMARY.md
  modified:
    - src/TSODSO.jl
    - docs/literate/mpc_rolling_horizon.jl
    - docs/literate/stochastic_pv_demand.jl
    - docs/literate/ac_oracle.jl
    - test/fixtures_mpc.jl
    - test/test_mpc_loop.jl
    - test/test_ac_oracle.jl
decisions:
  - "Kept the fixture's historic pv_scale scan figures (0.0036 / 8510) but marked them as measured under the original flat-floor formula, rather than re-measuring"
metrics:
  duration: ~15min
  completed: 2026-10-07
  tasks: 2
  files: 7
requirements: [FIX-10, ARCH-02]
---

# Phase 38 Plan 03: Stale dispatch and first-tier prose corrected Summary

The prose now matches the code. The include-site comments in `src/TSODSO.jl` and the Rung 8/9
literate pages describe the `TSODSO.run(::MPC, s)` / `TSODSO.run(::Stochastic, s)` dispatch,
how `run_scenario(s)` reaches it through `run(s.strategy, s)`, the thin
`run_mpc(s)` / `run_stochastic(s)` NamedTuple wrappers, and the knobs on `s.strategy`. Every
test, fixture and literate comment that called MPC's first tier an "inline atol=1e-6" check now
names the shared exactness kernel (rtol = 1e-4, hybrid per-branch floor).

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Strategy-dispatch prose | fc67d5c | src/TSODSO.jl, docs/literate/mpc_rolling_horizon.jl, docs/literate/stochastic_pv_demand.jl |
| 2 | Retire inline first-tier wording and old ratio literals | ef6a7e1 | test/fixtures_mpc.jl, test/test_mpc_loop.jl, docs/literate/mpc_rolling_horizon.jl, docs/literate/ac_oracle.jl, test/test_ac_oracle.jl |

## Verification

- Task 1 grep gates: there are 0 "NOT wired" and 0 "additive mpc_/stoch_ / independent sibling" matches. `run(::MPC` is present in src/TSODSO.jl. `check_planning_ids.py` is OK.
- Task 2 grep gate: there are 0 `inline cone|inline check|9157|9432` matches across the 5 files.
- `JuliaSyntax.parseall` succeeds on every touched file. `ast_equiv.jl HEAD` returns EQUAL for all 7 files (default mode, so only comments and docstrings changed).
- `format210.jl` made no changes to the 7 files. `check_content_loss.py HEAD` is OK.
- `file:test_mpc_loop.jl` gives 12 items / 376 Pass on 1.12.5, the same as after 38-02. The live high-PV first-tier ratio logged during the run is 9177.66, which matches the "≈ 9.2×10³" wording.
- Untouched, as the plan required: the `assert_ac_exact!(...; atol = 1e-6)` calls, the `isapprox` tolerances, `MPC_HIGH_PV_SCALE_MEASURED`, and the 38-02 regression item's deliberate `hybrid_ratios(o.ctx; atol = 1e-6)` old-formula comparison.

## Deviations from Plan

- In `test/fixtures_mpc.jl` I added a short note that the knife-edge scan figures (0.0036 at pv_scale 2.0 and 8510 at 2.5) came from the original flat-floor formula. They are historic measurements that were not re-run. The note keeps them from being read as hybrid-floor numbers. It is a comment only (ast_equiv EQUAL).

## Known Stubs

None.

## Self-Check: PASSED

- FOUND commits fc67d5c, ef6a7e1; all 7 modified files present with the edits above.
