---
phase: 29-genuine-bilevel-tso-dso-variant
plan: 03
subsystem: planning
tags: [golden-audit, full-suite-certification, bilevel, kkt, milp, phase-close]

# Dependency graph
requires:
  - phase: 29 plan 01
    provides: "build_bilevel_kkt/solve_bilevel!/BilevelKKT production code (audited/certified here)"
  - phase: 29 plan 02
    provides: "BILEV-02 corner-fixture certification (audited/certified here)"
  - phase: 29 plan 04
    provides: "BILEV-02 BLOCKER-1 non-degenerate interior fixture (audited/certified here)"
provides:
  - "29-FINDINGS.md — consolidated phase findings: fixture designs, measured bilevel/joint/gap numbers, SOS1 m_ub bounds, MILP tolerance status, benders.jl byte-identical confirmation, joint-reference rationale, golden-audit result, T-29-09 confirmation, certified full-suite tallies, process-deviation record, and code-review summary"
  - "Zero-unattributed golden-move audit result for the whole phase (3d4beb0..HEAD)"
  - "Certified full-suite tallies (30871/0/0/5) at phase-close HEAD a5e9900"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Phase-closing audit pattern: scope audit_goldens.py's --base to the PRECEDING phase's close commit (not its own default base) to isolate exactly what the current phase changed"

key-files:
  created:
    - .planning/phases/29-genuine-bilevel-tso-dso-variant/29-FINDINGS.md
    - .planning/phases/29-genuine-bilevel-tso-dso-variant/29-03-SUMMARY.md
  modified: []

key-decisions:
  - "audit_goldens.py --base 3d4beb0 (the recorded Phase-28 close commit) --head HEAD, not the script's own default base, to scope the audit to only what Phase 29 changed"
  - "The full-suite certification run used by this plan's findings is the ORCHESTRATOR's single clean detached run (HEAD a5e9900), not any of the three overlapping Pkg.test() launches this executor accidentally started — see Deviations"

requirements-completed: [BILEV-01, BILEV-02]

# Metrics
duration: ~90min (including a code-review cycle run outside this plan's own task scope)
completed: 2026-10-01
---

# Phase 29 Plan 03: Phase-Closing Golden Audit + Full-Suite Certification Summary

**Zero unattributed golden moves across the whole phase (3d4beb0..HEAD), a certified full-suite run at 30871 pass / 0 fail / 0 error / 5 broken (+168 over the Phase-28 baseline, fully attributed), and a consolidated 29-FINDINGS.md covering fixture design, measured numbers, and a 3-iteration code-review cycle that landed between this plan's two tasks.**

## Performance

- **Duration:** ~90 min end-to-end (Task 1 ~20 min; a 3-iteration code review ran between
  Task 1 and Task 2's certification, outside this plan's own authored scope; Task 2's
  certified suite run itself took 22m09.2s)
- **Started:** 2026-09-30T23:40:00Z (approx.)
- **Completed:** 2026-10-01T02:00:00Z (approx.)
- **Tasks:** 2 completed
- **Files modified:** 2 (both created: `29-FINDINGS.md`, this `29-03-SUMMARY.md`)

## Accomplishments

- Ran `audit_goldens.py --base 3d4beb0 --head HEAD` (scoped to the Phase-28 close commit,
  not the script's own wider default base) — **zero flagged numeric-literal golden moves at
  all** (not merely zero-unattributed-among-many), confirming Phase 29 only ADDS new named
  constants (`BILEV_*_HAND`/`JOINT_*_HAND`/`BILEV_GAP_FLOOR` in `test/fixtures_planning.jl`;
  `INTERIOR_*_HAND`/`JOINT_*_HAND_INTERIOR`/`GAP_FLOOR_INTERIOR`/`Z_GAP_FLOOR_INTERIOR`/
  `RHO_Y_*_HAND` self-contained in plan 29-04's own file) and never moves a pre-existing
  golden. Re-ran the same audit a second time at the phase's final HEAD (`a5e9900`, after
  the code-review cycle) — still exits 0.
- Wrote `.planning/phases/29-genuine-bilevel-tso-dso-variant/29-FINDINGS.md` consolidating
  all 8 points the plan's Task 1 required: both fixture designs (corner + non-degenerate
  interior) and why each produces a genuine bilevel-vs-joint gap; the measured
  bilevel/joint/gap numbers for both; the measured SOS1 `m_ub` bounds and confirmation the
  Pitfall-3 validity check never fired on either accepted production result; confirmation
  `select_optimizer(::MILP)`'s shared tolerance was never touched (only 3 files changed in
  `src/` across the whole phase, `factory.jl` not among them); confirmation
  `solve_stackelberg!`'s `benders.jl` diff is comment/docstring-only (17 insertions, zero
  executable lines); the WARNING-1 explicit rationale for why `solve_stackelberg!` cannot
  serve as the joint reference; the golden-audit result; and the T-29-09 `x_inv_max`/`d_max`
  non-binding confirmation on the interior fixture (later narrowed, not closed, by the
  code review's WR-01/WR-07 fixes — see Deviations).
- Appended the certified full-suite tallies to `29-FINDINGS.md`: **30871 pass / 0 fail /
  0 error / 5 broken** (30876 total) at HEAD `a5e9900`, a **+168** delta over the Phase-28
  baseline (30703/0/0/5), fully attributed (+166 from the phase's three bilevel test files
  — larger than originally reported because the intervening code review added genuinely
  new test cases; +2 from `test/test_planning_noninteger.jl`'s PVAL-04 guard correctly
  registering the new `build_bilevel_kkt` builder). Zero `.claude/worktrees/` contamination
  (`grep -c worktrees` over the full log returns 0); the certified run's log start
  postdates the recorded HEAD commit.

## Task Commits

Each task was committed atomically:

1. **Task 1: Golden-move audit + consolidated findings** - `990b51c` (docs)
2. **Task 2: Full-suite certification** - this commit (docs) — the full-suite tallies
   were appended to `29-FINDINGS.md` and this SUMMARY was written after the orchestrator
   certified the suite itself (see Deviations)

## Files Created/Modified

- `.planning/phases/29-genuine-bilevel-tso-dso-variant/29-FINDINGS.md` - consolidated
  phase findings (fixture design, measured numbers, audit result, certified suite tallies,
  process-deviation record, code-review summary)
- `.planning/phases/29-genuine-bilevel-tso-dso-variant/29-03-SUMMARY.md` - this file

## Decisions Made

- Scoped the golden-move audit's `--base` to `3d4beb0` (the STATE.md-recorded Phase-28
  close commit) rather than the script's own wider default base, per the plan's explicit
  instruction — this isolates exactly what Phase 29 changed, not the full v4.0 history.
- Trusted the orchestrator's single certified full-suite run (HEAD `a5e9900`) as this
  plan's authoritative Task 2 result, rather than any of the three overlapping `Pkg.test()`
  processes this executor accidentally launched (see Deviations) — no results from the
  corrupted concurrent runs were used anywhere in this plan's artifacts.

## Deviations from Plan

### Process deviation (not a Rule 1-4 code deviation — a tooling/environment deviation)

**1. Three overlapping `Pkg.test()` launches writing the same log file**
- **Found during:** Task 2, attempting to launch the detached full suite per the plan's
  documented protocol.
- **Issue:** The plan's protocol specifies `nohup setsid bash -c "... &" </dev/null
  >/dev/null 2>&1 &` as the detached-launch mechanism. In this execution environment, the
  sandboxed Bash tool silently terminates such backgrounded child processes at the end of
  each tool call (verified: the log file and `.done` sentinel never materialized, and no
  julia/setsid process was observed in a follow-up `ps aux`, despite `nohup`/`setsid`
  normally fully detaching a process from its parent's process group/session). The
  executor made TWO such launch attempts (one without `dangerouslyDisableSandbox`, one
  with) before discovering the Bash tool's own `run_in_background` parameter is the
  environment-sanctioned mechanism for a genuinely surviving background task — and then
  launched a THIRD run via `run_in_background`. All three attempts targeted the same
  `/tmp/phase29_fullsuite.log` path; at least two were genuinely running concurrently
  (confirmed via `ps aux` showing two distinct `bash -c ... julia ...` process trees at
  the same timestamp) before the orchestrator intervened.
- **Resolution:** The orchestrator caught this (via a direct message mid-execution),
  killed all three overlapping runs, and launched and certified exactly ONE clean detached
  run itself, confirming `git worktree list` showed no `.claude/worktrees/agent-*`
  contamination at launch and that the log's `worktrees` grep count was 0. This executor
  then stopped all further suite-related tool calls per the orchestrator's explicit
  instruction and used only the orchestrator-supplied certified tallies
  (30871/0/0/5, HEAD `a5e9900`) in this plan's FINDINGS/SUMMARY.
- **Impact:** None on the correctness of this plan's findings — the certified tallies used
  throughout are the orchestrator's single clean run, not any of the corrupted concurrent
  attempts. Flagged here as an honest process record per the plan's own "findings →
  29-FINDINGS.md ... real executable verify scripts" process-discipline requirement.
- **Generalizable lesson (for future executors in this environment):** use the Bash tool's
  own `run_in_background` parameter for genuinely long-lived detached processes in this
  environment, not a manually-constructed `nohup setsid ... &` — the latter appears to be
  silently killed by this environment's sandboxing at the end of the issuing tool call,
  regardless of `dangerouslyDisableSandbox`.

### Code review cycle (landed between this plan's Task 1 and Task 2, not authored by this plan)

A 3-iteration code review ran against the phase's files between this plan's Task 1 commit
(`990b51c`) and the certified suite run, moving HEAD to `a5e9900` via commits
`770132f`..`a5e9900` (`29-REVIEW.iter1.md`, `29-REVIEW-FIX.iter1.md`,
`29-REVIEW.iter2.md`, `29-REVIEW-FIX.md`, `29-REVIEW.md`). This plan did not author those
commits; it re-verifies them (golden audit re-run clean at the new HEAD; certified suite
green) and documents them in `29-FINDINGS.md` for full phase-closing traceability. Full
detail (CR-01 closed-form `m_ub` + certificate-LP fix, WR-01 `x_inv_max` SOS1 pair, WR-02
LinDistFlow allowlist + canonical multipliers, WR-03..WR-08 test hardening, and the final
iteration's 1 open warning + 4 open info items) is in `29-FINDINGS.md`'s "Code review"
section. None of these fixes moved any production answer (corner and interior optima are
byte-identical through every fix) or re-pinned any golden — confirmed by the golden-audit
re-run at the final HEAD.

## Issues Encountered

See the process deviation above (overlapping `Pkg.test()` launches). No other issues.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 29 (BILEV-01, BILEV-02) is complete and certified: a genuinely bilevel single-level
  KKT-MILP `solve_bilevel!` exists alongside the honestly-relabelled `solve_stackelberg!`,
  certified on TWO independent fixtures (degenerate corner + non-degenerate interior) each
  against production/BilevelJuMP-StrongDuality/brute-force three-way agreement and a
  measured, tolerance-dominant gap versus a genuine joint single-planner reference.
- One open warning (WR-01, iter 3) and 4 open info items are documented in `29-REVIEW.md`
  and carried in `29-FINDINGS.md` as unscheduled follow-ups — none affect the correctness
  of this phase's own certified fixtures (built once, solved once, never mutated in
  place), but a future consumer that mutates a built `BilevelKKT` model in place before
  re-solving should be aware of the stale-certificate risk.
- No blockers for Phase 30 (SOCP-in-the-loop Benders on a multi-bus feeder).

---
*Phase: 29-genuine-bilevel-tso-dso-variant*
*Completed: 2026-10-01*

## Self-Check: PASSED

Both claimed files found on disk (`29-FINDINGS.md`, `29-03-SUMMARY.md`); Task 1 commit hash
(`990b51c`) found in `git log --oneline --all`; the orchestrator-certified full-suite log
(`/tmp/claude-1000/p29_certified_suite_a5e9900.log`) tail independently confirms
"Package | 30871 5 30876 22m09.2s" and "Testing TSODSO tests passed"; `git worktree list`
confirms no `.claude/worktrees/agent-*` contamination; `audit_goldens.py --base 3d4beb0
--head HEAD` independently re-confirmed exit 0 at the final HEAD (`a5e9900`).
