---
phase: 28-goldens-re-derivation-thesis-reproduction-restatement
plan: 01
subsystem: testing
tags: [audit, golden-values, regression-testing, python, git-diff-parsing]

requires: []
provides:
  - "audit_goldens.py: stdlib-only Python script mechanically detecting unattributed numeric-literal golden moves in test/ diffs"
  - "28-CROSS-PHASE-AUDIT.md: consolidated Phase 26+27 golden-move audit with independent cross-reference and prose-citation check"
affects: [28-05]

tech-stack:
  added: []
  patterns:
    - "Diff-hunk replace-block pairing: group consecutive removed/added lines, pair only lines qualifying as code-value lines (assignment or @test/isapprox/atol=/rtol= markers), scan a fixed +/-N line window for attribution comments"

key-files:
  created:
    - .planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/scripts/audit_goldens.py
    - .planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-CROSS-PHASE-AUDIT.md
  modified: []

key-decisions:
  - "Script's ±5-line attribution window produced one false negative (test_admm.jl maxiter override); resolved by direct inspection and documented as a known detector limitation rather than editing test/ files outside this plan's scope"
  - "Discovered a second detector blind spot during cross-reference: bare-integer literals compared via '==' (equality assertions like `@test r.iters == 58`) are invisible to all three extraction regexes since GOLDEN_NAME_RE requires a single '=' assignment; corroborated independently via direct diff/grep inspection rather than silently absorbed"
  - "No open findings routed to Plan 28-05 — both irregularities found were resolved in-place by direct verification, not deferred"

requirements-completed: [FIX-11]

duration: 20min
completed: 2026-09-30
---

# Phase 28 Plan 01: SC-1 Golden-Move Audit Script + Cross-Phase Audit Doc Summary

**Stdlib-only Python script mechanically parses `git diff 5939799..HEAD -- test/` for unattributed numeric-literal golden moves, self-tests deterministically, and its independent findings are merged with the Phase 26/27 GOLDEN-AUDIT tables plus a re-verified prose-citation check into `28-CROSS-PHASE-AUDIT.md`.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-09-30T00:40:16Z
- **Tasks:** 2/2 completed
- **Files modified:** 2 created (`scripts/audit_goldens.py`, `28-CROSS-PHASE-AUDIT.md`)

## Accomplishments
- Built `audit_goldens.py`: parses `git diff <base>..<head> -- test/` into hunks, pairs qualifying replace-block lines (assignment / `@test`/`isapprox`/`atol=`/`rtol=` markers only — excluding pure comment-prose lines), flags numeric literals (≥3-decimal floats, scientific notation, or bare integers assigned to GOLDEN/ATOL/RTOL/TOL/SEED/ITER/MAXITER-named constants), and checks a ±5-line hunk window for `OLD`/`->`or`→`/`NEW` or `Plan-`/`FIX-`/`PM-`/`WR-`/`D-` or "moved"/"re-derived"/"re-pin" attribution signals.
- `--selftest` mode proves both the flag and no-flag paths deterministically (ran twice in a row, `SELFTEST: PASS` both times, no git access needed).
- Ran the script against the real diff `5939799..9ff2127` (this plan's own re-resolved HEAD, not the research session's stale `8a96361`): 13 flagged numeric-literal moves, 12 independently attributed, 1 mis-flagged by the script's own ±5-line window (resolved — see Deviations).
- Cross-referenced every row of `26-GOLDEN-AUDIT.md`'s and `27-GOLDEN-AUDIT.md`'s "Golden-value moves" tables against the script's own output — not just reformatted the tables (Pitfall 2). Rows the script structurally cannot observe (pure `tol_gap`/`maxiter` override additions, `src/`-only changes, formula/behavioral changes, renames, one equality-assertion blind spot) were independently checked via direct `grep`/diff inspection rather than trusted from prose.
- Re-verified the prose-citation audit of `.planning/PROJECT.md` and `docs/literate/*.jl`/`docs/writeups/*.typ` for the six headline moved values: PROJECT.md clean (zero hits), `docs/literate/convex_branch_flow.jl` and `thesis_reproduction_assumptions.jl` cite only CURRENT, correct values.

## Task Commits

1. **Task 1: Write the audit script + its own self-test** - `e0ba682` (feat)
2. **Task 2: Run against the real diff, cross-reference, write 28-CROSS-PHASE-AUDIT.md** - `6665f5b` (docs)

## Files Created/Modified
- `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/scripts/audit_goldens.py` - mechanical golden-move detector with embedded synthetic self-test fixtures
- `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-CROSS-PHASE-AUDIT.md` - 3-section consolidated audit (script results, cross-reference, prose-citation check) + closing verdict

## Decisions Made
- Used a fixed ±5-line hunk-position window for the attribution scan (per plan spec) rather than a whole-file scan, accepting the small false-negative risk this creates on multi-paragraph attribution comments placed further away — documented as a known limitation rather than widening the window ad hoc (would have been an undocumented scope change to the plan's own script-design spec).
- Restricted literal extraction to lines containing an assignment (`=`) or `@test`/`isapprox(`/`atol=`/`rtol=` markers, per criterion 5 — this correctly excludes comment-prose numbers but also means bare `==` equality-assertion literals (e.g. `@test r.iters == 58`) are invisible; documented as a design limitation, independently corroborated in the audit doc rather than silently ignored.
- Did not edit any `test/` file to add a missing attribution comment (Task 2's action text permits this conditionally), because (a) the one flagged row was already fully attributed both in-file and in `26-GOLDEN-AUDIT.md` — nothing was actually missing — and (b) the phase's own parallel-execution constraint explicitly forbids this plan from touching files outside `.planning/phases/28-*/`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Worktree branch was stale relative to the plan's base commit**
- **Found during:** Setup, before Task 1
- **Issue:** The worktree's HEAD (`3488bf5`) was an ancestor of, not equal to, the expected base commit `9ff2127` — the plan file and phase-28 directory did not exist yet at that HEAD.
- **Fix:** `git reset --hard 9ff21276109322df149f157731bdde20379226ee` (per the plan's own `<worktree_branch_check>` protocol — HEAD was confirmed an ancestor of the target, not a divergent/protected branch, before resetting).
- **Files modified:** none (branch pointer only).
- **Verification:** `git rev-parse HEAD` confirmed `9ff2127`; `.planning/phases/28-*/` directory and plan files present afterward.

**2. [Rule 1 - Bug] Script's naive positional pairing would have mismatched code lines against attribution comments**
- **Found during:** Task 1, script design
- **Issue:** A straightforward position-wise zip of a removed-line run against an added-line run pairs the FIRST added line (often the newly-inserted attribution COMMENT) against the removed code line, never reaching the actual replacement code line in the same run.
- **Fix:** Filtered both the removed-run and added-run candidate lists to only lines qualifying as code-value lines (criterion 5) before pairing position-wise, so comment-only insertions are skipped as pairing candidates but remain visible to the attribution window scan.
- **Files modified:** `scripts/audit_goldens.py` (design decision, not a post-hoc fix — caught via the plan's own two-fixture self-test design before it could reach the real-diff run).
- **Verification:** `--selftest` fixture with a comment+code 2-line added-run correctly pairs the OLD code line against the NEW code line (not the comment), confirmed `SELFTEST: PASS`.

---

**Total deviations:** 2 auto-fixed (1 blocking/setup, 1 bug caught during design)
**Impact on plan:** Both necessary for correctness; no scope creep. Neither required editing any file outside this plan's own `files_modified`.

## Issues Encountered
- The script flagged 1 of 13 pairs as unattributed (`test/test_admm.jl:113->145`) and a cross-reference pass surfaced a second, more fundamental blind spot (`==`-equality-assertion literals, e.g. `test_admm_knifeedge_canary.jl`'s `r.iters 58->56`). Both were investigated by direct diff/grep inspection rather than accepted or ignored; both are already fully attributed in-file and in the Phase 26 audit table. Full detail in `28-CROSS-PHASE-AUDIT.md` §1/§2. **No open finding is routed to Plan 28-05** — nothing here requires further action from the closing plan.

## Next Phase Readiness
- SC-1's audit artifact and consolidated document are complete and committed. Plan 28-05 (closing gate) can rely on `28-CROSS-PHASE-AUDIT.md`'s "no open findings" verdict without re-running this plan's investigation.
- No blockers for Plans 28-02/28-03/28-04 (disjoint files, this plan touched none of `src/`, `test/`, `docs/`, or top-level `scripts/`).

---
*Phase: 28-goldens-re-derivation-thesis-reproduction-restatement*
*Completed: 2026-09-30*

## Self-Check: PASSED

- FOUND: `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/scripts/audit_goldens.py`
- FOUND: `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-CROSS-PHASE-AUDIT.md`
- FOUND commit: `e0ba682` (Task 1)
- FOUND commit: `6665f5b` (Task 2)
