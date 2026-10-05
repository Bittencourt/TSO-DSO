---
phase: 35-ieee-8500-scale-after-refactor
fixed_at: 2026-10-05T03:50:00Z
review_path: .planning/phases/35-ieee-8500-scale-after-refactor/35-REVIEW.md
iteration: 3
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 35: Code Review Fix Report

**Fixed at:** 2026-10-05T03:50:00Z
**Source review:** .planning/phases/35-ieee-8500-scale-after-refactor/35-REVIEW.md
**Iteration:** 3 (final)

**Summary:**
- Findings in scope: 4 (WR-01, WR-02, plus IN-06 and IN-07 by orchestrator request; IN-08 out of scope)
- Fixed: 4
- Skipped: 0

No `src/` changes, no gate/tolerance/canary changes. No new profile run was made (the optional stage-5
run was not used; the docs were reworded to the measured figures instead).

## Fixed Issues

### WR-01: "The rest is state kept across iterations" is not supported by the profile

**Files modified:** `docs/literate/ieee8500_scaling.jl`, `results/ieee8500_benchmark/memory_wall_recharacterization.csv`
**Commit:** 9dedcb1
**Applied fix:** Docs section 4 now separates the two measured figures and their metrics: the staged
profile (one `build_dso_opt` +0.23 GiB, first `optimize!` +0.89 GiB = 1.12 GiB VmRSS; 1.20 GiB VmHWM
from 1,254,188 to 2,515,692 KiB; profile stops at stage 3, stage 5 `after_agr_opts` never reached) and
the whole-`solve_admm` peak-RSS delta (4.56 / 10.17 GiB), which also covers 122 AgrOpt builds and solves,
per-iteration state and the final `check_exact` consolidation. The ~3.4 GiB remainder is stated as
UNATTRIBUTED; "per-hour DSO solver state" is labelled a hypothesis; only "~linear in T" (two points) is
claimed; "linear in nodes" is dropped as unmeasured; the no-mitigation rationale now reads "no consumer was
shown to be dominant". The `dominant_consumer` cells of the four `p35-*` rows were rewritten the same way
(no commas added; all rows still have 11 fields). Verified: 122 = `n_agg` of both `p35-head-d0.1` rows in
`density_sweep.csv`; 1.12/4.56 = 24.5%.

### WR-02: The Phase-25 headline anon-rss range includes an `ieee8500-mv` kill

**Files modified:** `results/ieee8500_benchmark/memory_wall_recharacterization.csv`
**Commit:** 85d39f7
**Applied fix:** Verified against `density_sweep_full.csv`: the three `ieee8500` OOM rows record
6,991,636 / 8,548,328 / 8,393,224 KiB, so the range is 6991636-8548328 KiB (6.67-8.15 GiB). The cell now
states that, and names the 9,753,068 KiB (9.30 GiB) maximum separately as the `ieee8500-mv` density 1.0
row. The docs do not quote this range (no matches for 9.30 / 9753068 / 9.75).

### IN-06: `memory_wall_recharacterization.csv` still calls `admm_time_s` "wall"

**Files modified:** `results/ieee8500_benchmark/memory_wall_recharacterization.csv`
**Commit:** 4023a31
**Applied fix:** `677 s wall` -> `admm_time_s 678 s; process wall 728 s` (verified: `admm_time_s` =
677.50 in `density_sweep.csv`; `runs/p35-head-d0.1-T24.time` Elapsed 12:07.62).

### IN-07: The docs say the head row "records" -1

**Files modified:** `docs/literate/ieee8500_scaling.jl`
**Commit:** ab3949e
**Applied fix:** "...was written before WR-07 with `NaN`, normalized to the unknown sentinel `-1` by the
WR-04 repair (`aa6277e`)".

## Verification

- Docs file parses (`Meta.parseall`); CSV field count checked (11 per row) after each edit.
- Harness test `julia --project=. test/test_benchmark_ieee8500.jl` (run on `main` after the commits landed,
  no other Julia process at start): ALL TESTS PASSED (D-16 goldens 10/10; 35-02 harness 34/34).
- `git status --short results/` is clean.

---

_Fixed: 2026-10-05T03:50:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 3_
