---
phase: 35-ieee-8500-scale-after-refactor
plan: 05
subsystem: docs-closure
tags: [ieee8500, docs, arch-10, phase-gate, golden-repin]
requires: ["35-04"]
provides:
  - "Phase 35 measured-results docs section; append-only supersession notes; phase-gate suite result"
key-files:
  modified:
    - docs/literate/ieee8500_scaling.jl
    - test/test_benchmark_ieee8500.jl
    - .planning/STATE.md
    - .planning/PROJECT.md
    - .planning/REQUIREMENTS.md
    - .planning/milestones/v3.0-phases/25-ieee-8500-scalability-benchmark/25-VERIFICATION.md
    - .planning/milestones/v3.0-phases/25-ieee-8500-scalability-benchmark/deferred-items.md
decisions:
  - "ARCH-10 stays Complete: SC1 (hybrid default + genuine-refusal proof, ratio 568.95) and SC2 (re-characterized wall between d=0.1 and 0.25 at T=24) are both evidenced"
  - "Stale --quick golden re-pinned 137144/274218 -> 137258/274570 with a bisected cause (v4.0 P26 model fixes, not topology)"
metrics:
  completed: 2026-10-04
---

# Phase 35 Plan 05: Docs and status closure, phase gate Summary

The IEEE-8500 docs page now has a "Post-refactor measured results (Phase 35)" section with the measured numbers, the Phase 25 status notes are appended as dated supersessions, and the full suite passes with 32157 passed / 0 failed / 0 errored / 5 broken.

## Commits
- test(35-05): re-pin stale IEEE-8500 `--quick` golden with bisected cause; isolate results dir
- docs(35-05): IEEE-8500 post-refactor measured results section
- docs(35-05): append Phase 35 supersession notes and ARCH-10 evidence

## Task 1: docs
`docs/literate/ieee8500_scaling.jl` gained the five-part section (library default change and its stricter-gate consequence; SC1 diagnostic with worst branch `L2916620->N1136366`, gap 1.21e-4, ratio 568.95, loss impact 4.4e-9 pu; headline T=10 vs v3.0; ladder/wall table; protocol), plus an appended update note after the "did not converge" paragraph. Phase 25 history is kept and its kills are stated as T=24 combined-process kills (not T=10). Result figures were copied from the CSVs.

## Task 2: status notes
Appended dated notes to 25-VERIFICATION.md (after the SCALE-05 row), deferred-items.md (items 3/4, as one new section), STATE.md (new row beside verification_gap), PROJECT.md (SCALE-STRETCH bullet) and REQUIREMENTS.md (ARCH-10 evidence). Only additions were made to the two Phase 25 files. ARCH-10 was already ticked/Complete by 35-01 and stays so.

## Task 3: phase-gate suite
Detached `Pkg.test()` on the main checkout, no other julia process (only earlyoom), no `.claude/worktrees`. Result: **32157 passed, 0 failed, 0 errored, 5 broken** (total 32162, 27m28s), "Testing TSODSO tests passed". The two known Aqua items did not fail on this run. Canary literal `-4823.66604824162` is untouched in test/ (no diff vs 2a0ddca).

## Deviations from Plan
1. **[Rule 1 - stale golden, orchestrator-directed]** `test/test_benchmark_ieee8500.jl` Test 2 pinned 137144/274218 vs HEAD 137258/274570. Cause measured by running `--quick` at candidate commits in throwaway worktrees: cfa7e6e (26-03, battery soc extended to T+1) gives 137258/274560 (+114 vars, +342 cons); 30f53e4 (26-05, `:smax_rev` receiving-end cone) adds +10 cons (one per hour, T=10). The fixture topology did not change. Re-pinned with the cause in the test comment. `run_quick()` now writes to a tmpdir via `--results-dir`, so it no longer upserts into the committed CSV. Whole file passes (10 + 17); `git status --short results/` empty. Resolution recorded in the phase deferred-items.md.
2. **docs/src/generated/ieee8500_scaling.md is gitignored, not tracked** (`.gitignore` line 15), contrary to the plan and orchestrator note. It was regenerated locally with Literate and contains the section (4 matches for the key figures), but cannot be committed; only the literate source is committed.
3. ROADMAP.md plan checkbox and progress are updated via the SDK in the final metadata step.

## Known Stubs
None.

## Self-Check: PASSED
