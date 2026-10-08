---
phase: 36-code-export-cleanup
plan: 09
subsystem: hygiene
tags: [planning-id-scrub, planning-layer]
requires: ["36-08"]
provides:
  - src/planning/*.jl free of planning identifiers (classifier TOTAL 0 over all of src/planning)
affects: [36-10]
key-files:
  modified:
    - src/planning/master.jl
    - src/planning/master_integer.jl
    - src/planning/bilevel_kkt.jl
    - src/planning/subproblem.jl
    - src/planning/coupling.jl
    - src/planning/trace.jl
    - src/planning/retry.jl
    - src/planning/follower.jl
    - src/planning/feasibility_oracle.jl
    - src/planning/checkpoint.jl
    - src/planning/ac_recheck.jl
requirements-completed: [HYG-01]
completed: 2026-10-05
---

# Phase 36 Plan 09: Scrub of the remaining src/planning files Summary

Planning identifiers (phase, plan, requirement, decision, review-finding, pitfall and research-artifact references) were removed from the 11 remaining `src/planning` files (about 470 classifier hits), keeping each rationale as plain prose. The classifier reports TOTAL 0 over all of `src/planning`.

## Commits
- af95b08: scrub master, master_integer, bilevel_kkt, subproblem
- 2bcaf44: JuliaFormatter 2.10.2 pass (check_content_loss OK)
- 84e6671: scrub coupling, trace, retry, follower, feasibility_oracle, checkpoint, ac_recheck
- d11e54a: JuliaFormatter 2.10.2 pass (check_content_loss OK)

## Verification
- Classifier: TOTAL 0 on the plan file set and on all of `src/planning`.
- ast_equiv.jl against the plan-start commit (6677efd): EQUAL for all 11 files.
- thesis_tokens.py: OK. format210.jl re-run over the whole set is a no-op and check_content_loss.py HEAD prints OK.
- Targeted tests: Task 1 set 592 pass; Task 2 set 191 pass; Task 3 set (goldens, hardening, migration gate, noninteger) 72 pass. 0 failed, 0 errored. Canary and goldens untouched.

## Message changes
Runtime strings changed (grep of `test/` found no assertion on any of them; `ast_equiv.jl --strings` output reviewed):

master.jl (2 `@warn`s) and master_integer.jl (2 `@warn`s)
- `(Option A, Phase 31 WR-03)` became `(clamped to the certified minimum)` (build_master x2, build_master_integer `... instead (...)` x2).

master_integer.jl
- add_ll_cut! clamp `@warn`: `... stays valid at every corner (WR-04)` became `... stays valid at every corner`.

bilevel_kkt.jl (2 `ArgumentError`s)
- `(a strictly affine network; CONTEXT.md locked decision: DSO network LinDistFlow (LP) only) — got` became `(a strictly affine network; the DSO network must be LinDistFlow (LP)) — got`.
- `an integer follower is not supported in this phase (continuous-only investment, 29-RESEARCH.md Open Question 3) — pass` became `an integer follower is not supported (continuous-only investment) — pass`.

retry.jl (SolveFailedError text)
- `Rungs >= 2 REQUIRE a Clarabel backend (D-09: never a cross-solver fallback)` became `(never a cross-solver fallback)`.

ac_recheck.jl (SolveFailedError text)
- `... never a reported physical violation (BILEV-04b). Original error:` became `... never a reported physical violation. Original error:`.

No `@testitem` names changed. (Other test files still carry the old "Option A, Phase 31" wording in their own testitem names and comments; those belong to the test-scrub plans.)

## Hand-edited MIXED lines
The classifier reported no MIXED lines for these files. Thesis and literature references (eq. 3.38, Laporte-Louveaux 1993, Birge-Louveaux, Geoffrion 1972, Pineda-Morales 2019, App. C) were left verbatim, confirmed by thesis_tokens.py.

## Deviations from Plan
- [Rule 1] Cleanup of text the classifier cannot catch but that is process wording: `pre-27-07`, `pre-Phase-30`, `pre-30-04`, `Pitfall-3`, `Priority Finding N`, `Open Question N`, `plan-checker ... revision 1`, `Amendment (revision 1)`, `STATE.md carried blocker`, `quick task 260825-eme`, "this phase" and "gap-closure" were reworded in the same files. `byte-identical` became `bit-for-bit identical`; `byte-for-bit` typo became `bit-for-bit`.
- A semi-automatic first pass (scratch script outside the repo) removed ID tokens; every changed hunk was then reviewed and dangling fragments rewritten by hand.

## Known Stubs
None.

## Self-Check: PASSED
