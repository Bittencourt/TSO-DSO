---
phase: 26-network-device-model-correctness
plan: 08
subsystem: testing
tags: [julia, jump, socp, golden-audit, full-suite, sc-6, phase-close]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness
    provides: "All of Plans 26-01 through 26-20 (original wave + gap-closure wave), including Plan 26-14's App. C throw-to-diagnostic conversion and Plan 26-20's ADMM knife-edge canary re-pin"
provides:
  - "RestrictedBranchFlow._EXACT04_MEASURED_ε re-measured against the fully-merged code (base 0.005811069127373614 -> 0.010189528427785532)"
  - "A certified GREEN full-suite run (0 fail, 0 error, exit 0) at HEAD 6c25f27, 30195 pass / 5 broken / 30200 total"
  - ".planning/phases/26-network-device-model-correctness/26-GOLDEN-AUDIT.md — the cross-phase SC-6 golden-move audit table"
  - "A fixed downstream regression in test/test_dso.jl and test/test_admm_reactive.jl (4 REACT-0x testitems), surfaced by Plan 26-12's PM-03 smart default, via a new flexible-load-free Phase6Fixtures.build_two_bus_aggregators_no_flex fixture"
  - "deferred-items.md's D-26-02 marked RESOLVED (Plans 26-16, 26-19)"
affects: [phase-27, phase-28-thesis-reproduction-restatement]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Additive, flexible-load-free sibling fixture (build_two_bus_aggregators_no_flex) added to a shared TestItems @testmodule rather than mutating the existing (now genuinely flexible-load-carrying) fixture consumed by many other passing testitems"

key-files:
  created:
    - .planning/phases/26-network-device-model-correctness/26-GOLDEN-AUDIT.md
    - .planning/phases/26-network-device-model-correctness/26-final-suite.log
    - .planning/phases/26-network-device-model-correctness/26-final-suite.done
  modified:
    - src/powerflow/RestrictedBranchFlow.jl
    - .planning/phases/26-network-device-model-correctness/26-08-repro-restricted-and-canary.jl
    - test/fixtures_phase6.jl
    - test/test_dso.jl
    - test/test_admm_reactive.jl
    - .planning/phases/26-network-device-model-correctness/26-FINDINGS.md
    - .planning/phases/26-network-device-model-correctness/deferred-items.md

key-decisions:
  - "The REACT-0x regression (test_dso.jl/test_admm_reactive.jl) discovered during Task 2's full-suite run was fixed in-plan (Rule 1 auto-fix) despite not being in this plan's declared files_modified list — Task 2's own acceptance criteria requires every suite delta to be attributed or fixed before the plan closes, and this is squarely a downstream call-site consequence of Plan 26-12's PM-03 fix that predates the 41-testitem post-merge triage (which was captured before Plan 26-12 existed)"
  - "Fixed via an ADDITIVE flexible-load-free fixture (build_two_bus_aggregators_no_flex) rather than mutating build_two_bus_aggregators itself, since that fixture is consumed by many other ALREADY-PASSING testitems (including ones that explicitly pass reactive_consensus=:live and depend on it having flexible-load members)"
  - "The ADMM knife-edge canary section of 26-08-repro-restricted-and-canary.jl was brought into sync with Plan 26-20's already-landed re-pin (56 / -4823.66604824162) rather than independently re-derived — a live re-run in this fully-merged worktree reproduces it bit-identically, confirming no discrepancy, per this plan's own instruction to cross-reference rather than re-derive that canary"

requirements-completed: [FIX-01, FIX-02, FIX-03, FIX-04, FIX-05]

# Metrics
duration: ~1h
completed: 2026-09-28
---

# Phase 26 Plan 08: Final SC-6 Golden Audit + Full-Suite Green Gate Summary

**Re-measured `RestrictedBranchFlow._EXACT04_MEASURED_ε` against the fully-merged code (base
`0.005811069127373614` → `0.010189528427785532`), discovered and fixed a downstream
`reactive_consensus`-smart-default regression Plan 26-12 surfaced in 4 pre-Phase-26 testitems,
certified the full suite GREEN (0 fail / 0 error, exit 0) at HEAD `6c25f27` — 30195 pass / 5
broken / 30200 total versus the Plan 26-01 baseline's 30154 pass / 3 broken / 30157 total — and
wrote the cross-phase `26-GOLDEN-AUDIT.md` table closing Phase 26's SC-6 golden-policy
obligation.**

## Performance

- **Duration:** ~1h
- **Started:** 2026-09-28T22:40:00-03:00 (approx, after context-gathering)
- **Completed:** 2026-09-28T23:36:00-03:00
- **Tasks:** 3/3 completed (plus 1 in-scope discovered regression fix, folded into Task 2)
- **Files modified:** 7 modified, 3 created (excluding this SUMMARY)

## Accomplishments

- **Task 1 — ε re-measurement.** Ran `.planning/phases/26-network-device-model-correctness/
  26-08-repro-restricted-and-canary.jl` against the fully-merged code (all of Plans 26-01
  through 26-20). Plan 26-14's App. C throw-to-diagnostic conversion (`on_violation=:warn` on
  the AC/NLP oracle path) unblocked the measurement, which now runs to completion instead of
  throwing. `ε_measured` moved from the previously-pinned base `0.005811069127373614` to
  `0.010189528427785532` — updated `src/powerflow/RestrictedBranchFlow.jl`'s
  `_EXACT04_MEASURED_ε` constant with a full old→new+cause inline comment (cumulative effect of
  FIX-01..05 on the AC oracle's EXACT-04 operating point). Brought the repro script's stale
  ADMM knife-edge canary literals (58 / `-4822.903616694139`) into sync with Plan 26-20's
  already-landed re-pin (56 / `-4823.66604824162`) — a live re-run reproduces Plan 26-20's
  pinned values bit-identically, so this is cross-reference sync, not independent
  re-derivation.
- **Task 2 — full-suite certification.** Launched the full suite detached
  (`nohup setsid ... > 26-final-suite.log 2>&1; echo $? > 26-final-suite.done`), confirming the
  log's start timestamp postdates the certifying commit each time. The FIRST run (at commit
  `936ecdd`, Task 1 alone) surfaced 3 fail + 3 error records in `test/test_dso.jl` and
  `test/test_admm_reactive.jl`, unattributable to any existing plan SUMMARY or the
  41-testitem post-merge triage (both predate Plan 26-12's PM-03 smart-default/widened-guard
  fix). Root-caused: `Phase6Fixtures.build_two_bus_aggregators` (a pre-Phase-26 fixture)
  carries Thermostatic+Deferrable members that FIX-05 made `is_flexible_load`, so 4 pre-existing
  REACT-0x testitems' "default is OFF / explicit CERTIFIED override works" assumptions broke
  once PM-03 correctly started recognizing them as flexible loads. Fixed (Rule 1) by adding a
  genuinely flexible-load-free `build_two_bus_aggregators_no_flex` (PVBattery-only) fixture to
  `test/fixtures_phase6.jl` and swapping 3 testitems onto it, plus updating one WR-04 testitem's
  stale `@test_throws` on the omitted-kwarg path (which now correctly smart-resolves to LIVE
  instead of throwing) to assert the new, correct behavior. Verified all 4 fixes via
  direct-script reproduction (TestItemRunner does not resolve under `--project=.`) before
  re-running the full suite. The SECOND run (at commit `6c25f27`, after the fix) is fully
  GREEN: exit code 0, 30195 pass / 0 fail / 0 error / 5 broken / 30200 total.
- **Task 3 — cross-phase golden-move audit table.** Wrote
  `.planning/phases/26-network-device-model-correctness/26-GOLDEN-AUDIT.md`: a full table of
  every golden this phase moved (both the original wave 26-02..07 and the gap-closure wave
  26-09..20), cross-referenced against all 20 plans' own SUMMARYs and spot-checked directly
  against 9 edited source/test/docs files. Verified (not re-authored) that PM-01, PM-02, PM-04,
  and the v2.1 knife-edge restatement are consistently documented across every location the
  governing plans wrote them — no gap found. Appended a closing section to `26-FINDINGS.md`
  confirming the gap-closure wave is complete. Marked `deferred-items.md`'s D-26-02 RESOLVED
  (Plans 26-16, 26-19), per the orchestrator's explicit instruction.

## Task Commits

Each task/discovery was committed atomically:

1. **Task 1: Re-measure `_EXACT04_MEASURED_ε` against the fully-merged code** - `936ecdd` (test)
2. **Discovered regression fix (Rule 1, folded into Task 2): restore REACT-0x `reactive_consensus` tests broken by PM-03's smart default** - `6c25f27` (fix)
3. **Task 2: certify the final full-suite GREEN at HEAD `6c25f27`** - `b2968db` (test)
4. **Task 3: write the cross-phase golden-move audit table** - `fac69ba` (docs)
5. **D-26-02 RESOLVED marker (orchestrator-instructed)** - `283ba44` (docs)

## Files Created/Modified

- `src/powerflow/RestrictedBranchFlow.jl` — `_EXACT04_MEASURED_ε` re-measured and re-pinned with a full old→new+cause comment.
- `.planning/phases/26-network-device-model-correctness/26-08-repro-restricted-and-canary.jl` — ε assertion base updated to match; ADMM knife-edge canary literals synced to Plan 26-20's re-pin.
- `test/fixtures_phase6.jl` — new `build_two_bus_aggregators_no_flex` function (PVBattery-only, flexible-load-free), exported.
- `test/test_dso.jl` — one testitem swapped onto the new flexible-load-free fixture.
- `test/test_admm_reactive.jl` — two testitems swapped onto the new fixture; one WR-04 testitem's stale `@test_throws` (omitted-kwarg path) replaced with an assertion matching the new smart-default (LIVE) behavior.
- `.planning/phases/26-network-device-model-correctness/26-GOLDEN-AUDIT.md` (new) — the full cross-phase golden-move audit table, additive/behavioral-change table, final-suite result table, and finding-consistency check.
- `.planning/phases/26-network-device-model-correctness/26-FINDINGS.md` — closing "Plan 26-08" section appended.
- `.planning/phases/26-network-device-model-correctness/deferred-items.md` — D-26-02 marked RESOLVED (Plans 26-16, 26-19).
- `.planning/phases/26-network-device-model-correctness/26-final-suite.log`, `26-final-suite.done` (new) — the certifying full-suite run's evidence artifacts.

## Decisions Made

- Fixed the discovered REACT-0x regression in-plan (Rule 1) rather than merely documenting it as an unattributed delta, per Task 2's own acceptance criteria ("a delta with no attribution is a genuine regression and must be fixed before this plan closes, not waved through").
- Added a NEW, additive flexible-load-free fixture function rather than mutating the existing `build_two_bus_aggregators` (which many OTHER already-passing testitems depend on carrying flexible-load members).
- Synced (not re-derived) the repro script's ADMM canary literals against Plan 26-20's already-landed re-pin, since Task 1's own action text explicitly scopes the canary re-measurement to Plan 26-20.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] REACT-0x `reactive_consensus` testitems broken by Plan 26-12's PM-03 smart default**
- **Found during:** Task 2 (first full-suite run, at commit `936ecdd`)
- **Issue:** `test/test_dso.jl`'s "reactive_consensus=true pins qag_dso..." testitem and `test/test_admm_reactive.jl`'s "default reactive_consensus omitted...", "converged reactive_consensus=true certifies...", and "OFF/CERTIFIED with a q_inject-carrying device fails loud... (WR-04)" testitems all built their fixture from `Phase6Fixtures.build_two_bus_aggregators`, which (per Plan 26-12's own SUMMARY discovery) carries Thermostatic+Deferrable members that FIX-05 (Plan 26-04) made `is_flexible_load`. Post-PM-03 (Plan 26-12), `build_dso_opt`'s smart default now resolves to LIVE (not OFF) for this population, and an explicit `reactive_consensus=true` now correctly trips the widened WR-04 guard — breaking these 4 pre-Phase-26 testitems' assumptions. None of this is attributable to any existing plan SUMMARY or the 41-testitem post-merge triage, since both predate Plan 26-12's own guard-widening.
- **Fix:** Added `Phase6Fixtures.build_two_bus_aggregators_no_flex` (a genuinely flexible-load-free PVBattery-only variant, mirroring the ad hoc fixture Plan 26-12's own verification already used) and swapped 3 testitems onto it. Replaced the WR-04 testitem's stale `@test_throws` on the omitted-kwarg path with an assertion confirming the smart default now resolves directly to LIVE.
- **Files modified:** `test/fixtures_phase6.jl`, `test/test_dso.jl`, `test/test_admm_reactive.jl`
- **Verification:** All 4 fixes reproduced and verified via direct Julia scripts (TestItemRunner does not resolve under `--project=.`) against the exact edited testitem bodies before the second full-suite run, which is fully GREEN.
- **Committed in:** `6c25f27`

---

**Total deviations:** 1 auto-fixed (Rule 1 bug fix, discovered during Task 2's own full-suite verification, squarely within Task 2's mandate to fix unattributed regressions before closing).
**Impact on plan:** No scope creep beyond what Task 2's own acceptance criteria requires — every full-suite delta is now either attributed to a named prior plan or fixed in this plan.

## Known Stubs

None.

## Threat Flags

None — this plan re-measures a research constant, runs the test suite, fixes 4 downstream test
regressions, and writes an audit document; no new external input, no new package installs, no
new attack surface (matching the plan's own threat_model, T-26-12/T-26-38 mitigate, T-26-13
accept).

## Issues Encountered

- The full suite's first run (at `936ecdd`) surfaced the REACT-0x regression documented above —
  resolved in-plan before re-running.
- TestItemRunner-under-`--project=.` trap (known project memory): every verification of the
  fixed testitems used a direct-script reproduction (plain-`module` transform of the
  `@testmodule` fixture files), per the established project convention.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 26's SC-6 golden-policy obligation is closed: every golden moved (both waves) is
  re-derived in-phase with a stated old→new value and cause, the full suite is GREEN at HEAD
  `6c25f27`, and no golden is silently re-pinned.
- The 4 cross-phase findings (PM-01, PM-02, PM-04, v2.1 restatement) are confirmed consistently
  documented — Phase 28's thesis-reproduction restatement can cite `26-GOLDEN-AUDIT.md` and
  `26-FINDINGS.md` directly.
- `deferred-items.md` has no remaining open items (D-26-01 resolved by Plan 26-10, D-26-02
  resolved by Plans 26-16/26-19, both confirmed here).
- `.planning/STATE.md` and `.planning/ROADMAP.md` are untouched by this plan — the orchestrator
  folds `26-FINDINGS.md`'s full contents in at phase close.

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-28*

## Self-Check: PASSED

- FOUND: `src/powerflow/RestrictedBranchFlow.jl`
- FOUND: `.planning/phases/26-network-device-model-correctness/26-08-repro-restricted-and-canary.jl`
- FOUND: `test/fixtures_phase6.jl`
- FOUND: `test/test_dso.jl`
- FOUND: `test/test_admm_reactive.jl`
- FOUND: `.planning/phases/26-network-device-model-correctness/26-GOLDEN-AUDIT.md`
- FOUND: `.planning/phases/26-network-device-model-correctness/26-FINDINGS.md`
- FOUND: `.planning/phases/26-network-device-model-correctness/deferred-items.md`
- FOUND: `.planning/phases/26-network-device-model-correctness/26-final-suite.log`
- FOUND: `.planning/phases/26-network-device-model-correctness/26-final-suite.done` (contains `0`)
- FOUND commit: `936ecdd` (Task 1)
- FOUND commit: `6c25f27` (discovered regression fix)
- FOUND commit: `b2968db` (Task 2)
- FOUND commit: `fac69ba` (Task 3)
- FOUND commit: `283ba44` (D-26-02 RESOLVED marker)
