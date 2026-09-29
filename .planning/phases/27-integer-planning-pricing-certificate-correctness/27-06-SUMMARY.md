---
phase: 27-integer-planning-pricing-certificate-correctness
plan: 06
subsystem: testing
tags: [julia, testitemrunner, golden-audit, sc-6, phase-closing]

# Dependency graph
requires:
  - phase: 27-integer-planning-pricing-certificate-correctness
    provides: "Plans 27-01..05 (original 5-plan wave) and gap plans 27-07/27-08/27-09
      (post-merge fixes and USER-DECISION physics-only settlement reformulations) — this
      plan is the SC-6 phase-closing gate over the union of all of them"
provides:
  - "27-GOLDEN-AUDIT.md: cross-phase golden-move audit table covering every golden Phase 27
    moved across all 8 executed plans (27-01..05, 27-07..09), including the 3-stage
    truth-settlement/SITE-2 reformulation and the seed round-trip (1 -> 5 -> 1)"
  - "Certifying full-suite run at HEAD ebd94ac: 30392 pass / 0 fail / 0 error / 5 broken,
    exit code 0, 20m58.1s — diffed against the Phase 26 close baseline (30213/0/0/5 at
    9d00b82) with every count delta attributed"
  - "27-FINDINGS.md closed out: 27-07/27-08/27-09's Findings sections folded in, the
    seed=5 finding chain (F-27-07-2, F-27-08-1) marked SUPERSEDED by the final physics-only
    disposition (F-27-09-1), phase completion note recording every escalation's final state"
affects: [28-thesis-reproduction-restatement]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Cross-phase golden-move audit table (mirrors 26-GOLDEN-AUDIT.md's format): Golden |
      File:Line | Old Value | New Value | Cause | Plan, spot-checked directly against
      source/test diffs (git diff <phase-base>..HEAD -- test/), not just plan SUMMARYs"
    - "Multi-hop golden provenance: when a golden moved 3+ times across successive gap
      plans (the truth-settlement mechanism: SOCP -> limited AC -> physics-only AC), each
      intermediate move is individually attributed rather than collapsed into one
      unexplained final diff"

key-files:
  created:
    - .planning/phases/27-integer-planning-pricing-certificate-correctness/27-GOLDEN-AUDIT.md
    - .planning/phases/27-integer-planning-pricing-certificate-correctness/27-final-suite.log
    - .planning/phases/27-integer-planning-pricing-certificate-correctness/27-final-suite.done
  modified:
    - .planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md

key-decisions:
  - "Used the plan's own cited Phase 26 close baseline (30213/0/0/5 at 9d00b82) rather than
    26-GOLDEN-AUDIT.md's own measured final count (30195/0/0/5 at 6c25f27) — the plan's
    <key_links> pattern explicitly requires matching '30213' against .planning/STATE.md,
    and the two numbers' small gap reflects additional commits between 26-08 and STATE.md's
    own recorded phase-close snapshot, not a discrepancy in this plan's own measurement."
  - "Did not re-run or re-derive any Plan 27-01..05/07..09 golden independently — this plan's
    scope is auditing (cross-referencing SUMMARYs against source/test diffs) and the final
    certifying suite run, not re-deriving any individual measurement a prior plan already
    made and documented in-line."
  - "Committed the suite run (Task 1) and the audit+findings write-up (Task 2) as two
    separate atomic commits, mirroring the plan's own two-task structure, even though both
    touch 27-GOLDEN-AUDIT.md (Task 1's commit adds only the log/done marker; Task 2's
    commit adds the audit document's content)."

patterns-established: []

requirements-completed: [FIX-06, FIX-07, FIX-08, FIX-09, FIX-10]

# Metrics
duration: ~30min (dominated by the 20m58s detached full-suite run)
completed: 2026-09-29
---

# Phase 27 Plan 06: SC-6 Golden Audit + Certifying Full Suite Summary

**Certified the full test suite GREEN at HEAD `ebd94ac` (30392 pass / 0 fail / 0 error / 5 broken, +179 pass vs. the Phase 26 baseline, all additive) and wrote the cross-phase golden-move audit table covering every golden FIX-06 through FIX-10 moved across all 8 executed plans, including a golden that moved through 3 successive reformulations (SOCP → limited AC → physics-only AC) before reaching its final shipped state.**

## Performance

- **Duration:** ~30 min (dominated by the detached full-suite run, 20m58.1s)
- **Completed:** 2026-09-29
- **Tasks:** 2/2 completed
- **Files modified:** 1 modified (`27-FINDINGS.md`), 3 created (`27-GOLDEN-AUDIT.md`, `27-final-suite.log`, `27-final-suite.done`)

## Accomplishments

- Launched the certifying full suite detached at HEAD `ebd94ac` (all of Plans 27-01 through
  27-09 landed), per the `background-suite-orphan-race` protocol: verified `git worktree list`
  showed no `.claude/worktrees/agent-*` contamination and `git status --porcelain` was clean
  before launch; confirmed the log's `HEAD=ebd94ac` / start-timestamp line postdates every
  Phase-27 commit.
- **Result: GREEN.** Exit code `0`, `30392 pass / 0 fail / 0 error / 5 broken` in 20m58.1s.
  Diffed against the Phase 26 close baseline (`30213/0/0/5` at `9d00b82`): `+179` pass
  (entirely attributable to net-new Phase-27 test coverage across 27-01/02/04/05/07/08/09 —
  no golden removed), `0` fail delta, `0` error delta, `0` broken delta (the SAME 5 named
  items — 2 thesis `v₉[16]` cross-checks, 2 CairoMakie weakdep skips, 1 v2.1 welfare-ratio
  figure-bound cross-check — confirmed present at unchanged causes).
- Confirmed no `.claude/worktrees/` or sibling `TSO-DSO.worktrees/` path anywhere in the
  20,000+-line log (grep count 0 for both), and that the 2 literal `ERROR:` lines in the log
  are HiGHS's own intentional "cannot solve MIQP" negative-path test output, not suite
  failures.
- Wrote `27-GOLDEN-AUDIT.md`: a full cross-phase golden-move table (8 rows in §1 alone, plus
  5 renames in §2 and 9 additive changes in §3) covering FIX-06's T=2 tolerance/enumeration
  oracle, FIX-08's hybrid floor + head-branch orientation fix + 3 precision-floor tol_gap
  pins, FIX-07's `.cone`/`.drop` rename with deprecation shim, FIX-09/FIX-10's 3-stage
  truth-settlement reformulation (SOCP → limited AC → physics-only AC, spanning plans
  27-03/27-05 → 27-07 → 27-08 → 27-09), and the `seed` round-trip (`1`→`5`→`1`, net zero
  golden left on a non-default value at phase close, verified by direct grep).
- Closed out `27-FINDINGS.md`: folded in the Findings sections from 27-07 (head-branch
  lookup, SOCP knife-edge), 27-08 (AC-limited-settlement genuine thermal violation), and
  27-09 (physics-only resolution) — explicitly marking 27-07's `F-27-07-2` and 27-08's
  `F-27-08-1` as **SUPERSEDED** by 27-09's `F-27-09-1` (the final, shipped disposition), and
  appended a phase completion note with a table recording every escalated finding's final
  status (2 resolved-in-plan, 2 superseded-then-resolved, 2 genuinely open/out-of-scope for
  Phase 28 awareness).

## Task Commits

1. **Task 1: Launch the final full suite, diff against the Phase 26 baseline** - `ddc3aec` (test)
2. **Task 2: Cross-phase golden-move audit table + close out 27-FINDINGS.md** - `c488014` (docs)

## Files Created/Modified

- `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-final-suite.log` (NEW) — full detached suite run output, HEAD/timestamp-stamped.
- `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-final-suite.done` (NEW) — exit code marker (`0`).
- `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-GOLDEN-AUDIT.md` (NEW) — the SC-6 cross-phase audit table, format mirroring `26-GOLDEN-AUDIT.md`.
- `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md` — appended 27-07/27-08/27-09 Findings sections (with explicit SUPERSEDED markers on the seed-finding chain) and a phase completion note.

## Decisions Made

- **Baseline number used:** `30213/0/0/5` (the plan's own explicitly-cited `key_links` target,
  matched against `.planning/STATE.md`), not `26-GOLDEN-AUDIT.md`'s own independently-measured
  `30195/0/0/5` — the two differ because additional commits landed on `main` between Plan
  26-08's own certifying run and STATE.md's final phase-close snapshot; the plan's own
  acceptance criterion names `30213` specifically, so that is the number this audit diffs
  against.
- **No independent re-derivation of any prior plan's golden** — this plan's role is
  cross-phase auditing and the final certifying suite run, not re-measuring what 27-01..09
  already measured and documented in-line (per the plan's own scope, `files_modified` is
  limited to the audit table and the findings closeout).
- **Two separate atomic commits** (suite run, then audit+findings), matching the plan's
  Task 1/Task 2 structure even though both nominally list `27-GOLDEN-AUDIT.md` — Task 1's
  commit contains only the log/done marker, Task 2's contains the document's actual content.

## Deviations from Plan

None — plan executed exactly as written. Both tasks' acceptance criteria were met directly:
the suite ran green with every delta attributed, and the audit table has well over the
required 8 rows with a stated "GREEN" verdict.

## Issues Encountered

- The suite run emitted repeated `DrWatson`/`JLD2` warnings ("Git repository is dirty!
  Appending -dirty to the commit ID", "you passed a key as a symbol instead of a string") —
  both pre-existing, cosmetic DrWatson/JLD2 library warnings unrelated to test correctness
  (the "dirty" warning fired because this plan's own in-progress `27-GOLDEN-AUDIT.md`/
  `27-FINDINGS.md` edits were uncommitted while the suite ran in parallel; it affects only a
  DrWatson experiment-metadata tag string, not any test assertion or result).
- No worktree contamination, no orphaned/stale-log risk (the background-suite-orphan-race
  memory's two failure modes) — this run was launched fresh, detached, with the log's own
  HEAD/timestamp line verified against the commit it covers before trusting the result.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **Phase 27 is CLOSED.** FIX-06 through FIX-10 are all implemented, tested, and certified
  green at HEAD `ebd94ac` (plus this plan's own 2 closing commits, `ddc3aec`/`c488014`,
  which touch only planning documents, not source/test).
- `27-GOLDEN-AUDIT.md` and `27-FINDINGS.md` are the two documents Phase 28 (thesis-
  reproduction restatement) should consult first: the audit table names the FINAL state of
  every reformulated mechanism (physics-only AC settlement for both MPC truth and FIT
  SITE-2), and the findings closeout names the 2 genuinely open items for Phase 28 awareness
  (F-27-01-2's `solve_follower!` HiGHS certificate-loss fragility, out of scope; F-27-05-2's
  worsened flake landscape on the Phase-17-retuned IEEE-123 population point, not
  independently bisected).
- Per this plan's explicit instruction, `.planning/STATE.md` and `.planning/ROADMAP.md` are
  UNTOUCHED by this plan — the orchestrator folds `27-FINDINGS.md`'s contents into
  `STATE.md` at phase close.

## Self-Check

- FOUND: `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-GOLDEN-AUDIT.md`
- FOUND: `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-final-suite.log`
- FOUND: `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-final-suite.done`
- FOUND: `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md` (modified)
- FOUND commit: `ddc3aec`
- FOUND commit: `c488014`
- Confirmed `27-final-suite.done` contains `0` (exit code)
- Confirmed `27-final-suite.log`'s Test Summary line: `Package | 30392 5 30397 20m58.1s`

## Self-Check: PASSED

---
*Phase: 27-integer-planning-pricing-certificate-correctness*
*Plan: 06*
*Completed: 2026-09-29*
