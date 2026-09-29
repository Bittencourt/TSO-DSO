---
phase: 27-integer-planning-pricing-certificate-correctness
plan: 02
subsystem: pricing-certificate
tags: [socp, exactness-gate, jump, clarabel, pf-04, fix-08]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness
    provides: per-fixture Clarabel tol_gap calibrations (cluster-E fixtures) that interact
      with the new per-branch exactness floor
provides:
  - assert_socp_exact! per-branch relative exactness floor (atol_b = ε * ref_b), replacing
    the flat atol=1e-6 default
  - MEASURED_ε_FIX08 = 1e-4, a measured (not guessed) named constant
  - A synthetic regression proving a slack cone on a small-smax branch is now caught
  - A documented, escalated ε conflict between the new floor and a pre-existing WR-01
    regression test in test_exactness.jl
affects: [28-thesis-reproduction-restatement, any future FIX-08 follow-up on the escalated
  WR-01 conflict]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Backward-compatible kwarg override: atol::Union{Nothing,Real}=nothing bypasses a new
      default computation entirely when the caller passes an explicit value, preserving
      byte-identical behavior at 2 existing call sites"
    - "Measured-constant discipline: MEASURED_ε_FIX08 mirrors KNOWN_OPTIMUM_ATOL's
      cite-the-raw-sweep-numbers comment convention rather than a hand-picked value"

key-files:
  created:
    - .planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md
  modified:
    - src/models/exactness.jl
    - test/test_exactness.jl

key-decisions:
  - "MEASURED_ε_FIX08 = 1e-4, chosen to satisfy the plan's explicitly-named cluster-E/
    canonical fixture set (IEEE-13/IEEE-123 acceptance, test_pricing_dlmp.jl,
    test_pricing_welfare.jl, test_admm.jl, test_planning_oracle.jl) plus the new Task-2
    synthetic regression, all with >=2x margin"
  - "Escalated (not silently resolved) an irreconcilable conflict: no single ε keeps BOTH
    the new required fixture set passing AND test_exactness.jl's pre-existing WR-01
    regression item throwing (thresholds ~5e-5 vs <5e-8, three orders of magnitude apart)"

patterns-established:
  - "Per-branch exactness floor: ref_b = br.smax^2 for thermally-limited branches, else the
    head branch's own flow magnitude squared, for any future exactness-adjacent certificate
    that needs a scale-aware floor"

requirements-completed: [FIX-08]

# Metrics
duration: ~75min
completed: 2026-09-29
---

# Phase 27 Plan 02: Per-Branch Exactness Floor Summary

**`assert_socp_exact!` now gates on a per-branch relative floor `atol_b = ε·ref_b` (ε=1e-4, measured) instead of a flat `atol=1e-6`, closing a scale-blind gap on lightly-loaded branches — but the same measurement surfaced an irreconcilable conflict with a pre-existing WR-01 regression test, escalated rather than hidden.**

## Performance

- **Duration:** ~75 min
- **Started:** 2026-09-29T06:55:00Z (approx, worktree setup)
- **Completed:** 2026-09-29T08:22:00Z
- **Tasks:** 2 completed
- **Files modified:** 2 (`src/models/exactness.jl`, `test/test_exactness.jl`), 1 created (`27-FINDINGS.md`)

## Accomplishments

- `assert_socp_exact!` computes a per-branch, per-hour reference scale `ref_b` (the branch's
  own `smax^2` if thermally limited, else the head branch's own flow magnitude squared) and
  gates on `atol_b = ε * ref_b` by default, replacing the flat `atol = 1e-6` that was
  calibrated only against head-branch-scale fixtures.
- An explicit `atol` kwarg still bypasses the new computation entirely — verified
  byte-identical (same `maxgap`, no throw) on the existing exact-point fixture under both the
  new default path and the explicit-override path, and confirmed the 2 real call sites
  (`src/admm/DsoOpt.jl:671`, `test/fixtures_phase19.jl:359`) already pass an explicit `atol`
  and so take the unchanged bypass path.
- A new `@testitem` in `test/test_exactness.jl` demonstrates the regression this plan closes:
  a `smax=0.01` branch with an injected `l=5e-7` gap — below the OLD flat `atol=1e-6` (would
  have silently passed) but ~5x its own `ref_b=1e-4` scale (now correctly thrown).
- `MEASURED_ε_FIX08 = 1e-4` was measured (not guessed) via a direct-script sweep against the
  synthetic regression and the plan's explicitly-named cluster-E/canonical fixture set — see
  "ε Sweep" below for the full raw table.
- **A genuine, irreconcilable ε conflict was found and escalated** (not hidden): see
  "Escalation" below.

## Task Commits

Each task was committed atomically:

1. **Task 1: Per-branch relative exactness floor in assert_socp_exact!** - `9374e5c` (feat)
2. **Task 2: Measure ε, add synthetic regression, re-verify cluster-E fixtures** - `9876322` (test)

**Plan metadata:** pending (this SUMMARY + STATE/ROADMAP updates are owned by the orchestrator per this plan's instructions — this executor does not touch STATE.md/ROADMAP.md)

## Files Created/Modified

- `src/models/exactness.jl` - `assert_socp_exact!` per-branch floor (`atol_b = ε*ref_b`),
  new `MEASURED_ε_FIX08` constant with a full measured-sweep comment, backward-compatible
  `atol` override, head-branch lookup with a loud `ArgumentError` on a malformed feeder.
- `test/test_exactness.jl` - new `@testitem` "per-branch floor flags a slack cone on a
  small-smax branch the old flat atol missed (FIX-08)".
- `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md` -
  NEW file (didn't exist before this plan), documenting the escalated ε conflict.

## ε Sweep (measured, direct scripts reproducing each fixture body under `julia --project=.`)

| Fixture | ref_b | gap (measured) | ε threshold |
|---|---|---|---|
| Task-2 synthetic (smax=0.01, injected l=5e-7) | 1e-4 | 5e-7 | throws for ε ≲ 5e-3 |
| IEEE-13 ground (`test_acceptance.jl`/`test_admm.jl:78`) | head_flow_mag2≈4.56e-3 (2 interior branches) | ≈3.1e-8 | passes for ε ≳ 5e-5 (binary search: throws@4e-5, passes@5e-5) |
| IEEE-123 (`test_acceptance.jl`) | (real impedances) | ≈9.47e-8 | passes for ε ≳ 1e-6 |
| two_bus_feeder (`test_admm.jl:25`/`test_planning_oracle.jl:267`) | own head-branch flow mag2 | ≈1.40e-9 | passes at every ε tried (1e-9..1e-3) |
| near-lossless smax=10 pair (`test_pricing_dlmp.jl:20/226`, `test_pricing_welfare.jl:64`) | 100 | ≈6.2-6.3e-6 | passes at every ε tried |
| **test_exactness.jl's pre-existing WR-01 item** (smax=10, injected l=5e-6) | 100 | 5e-6 | **throws ONLY for ε < 5e-8** |

`ε = 1e-4` clears every row in the REQUIRED set (synthetic + cluster-E + IEEE-13/123
canonical) with ≥2x margin on the tightest (IEEE-13 ground). It does NOT keep the
pre-existing WR-01 item throwing — see Escalation.

## Decisions Made

- Chose `ε = 1e-4` (matches `rtol`'s own order of magnitude) over a tighter value: the
  binding lower bound from the REQUIRED fixture set is ≈5e-5 (IEEE-13 ground); `1e-4` gives
  ~2x margin without being needlessly loose relative to the Task-2 synthetic fixture's
  tolerance ceiling (≈5e-3).
- Did NOT attempt to satisfy the pre-existing WR-01 regression item's `ε<5e-8` requirement
  by choosing a smaller ε, because doing so would newly flag the IEEE-13 ground canonical
  fixture (and IEEE-123) as inexact — the LOCKED policy explicitly forbids resolving this
  either direction silently. Recorded as an escalation instead.
- Left `test/test_exactness.jl`'s 3 pre-existing `@testitem`s completely untouched (only a
  NEW item was added) — modifying an existing item's fixture to "work around" the ε
  conflict would itself be a silent re-pin, which the plan's locked decision forbids.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed a `julia -e` top-level soft-scope bug in the plan's own Task 2 `<verify>` script**
- **Found during:** Task 2 verification
- **Issue:** The plan's literal verify script uses `threw = false; try ... catch e; threw = true; end`. Under `julia -e` (non-interactive top-level), Julia's soft-scope rule treats the `catch`-block assignment as a NEW local that dies with the block — the outer `threw` never updates, silently vacating the assertion (same failure class documented in this repo's `test/runtests.jl` header and the `testitem-try-scoping-trap` project memory, but here reproduced under plain `julia -e`, not TestItemRunner).
- **Fix:** Added `global threw = ...` in the verify script when running interactively via `-e` (not needed in the actual `test/test_exactness.jl` `@testitem`, which uses `@test_throws Exception` directly instead of a try/catch accumulator, avoiding the trap entirely).
- **Files modified:** none (only affected an ad hoc verify invocation, not committed code).
- **Verification:** Re-ran with the `global` keyword; script now correctly reports the exception was caught.
- **Committed in:** N/A (verify-script-only fix, not part of any commit).

---

**Total deviations:** 1 auto-fixed (1 blocking, verify-script-only, no source change)
**Impact on plan:** No impact on shipped code; the actual regression test in
`test/test_exactness.jl` uses `@test_throws Exception` directly and never hits this trap.

## Issues Encountered

See "Escalation" below — the significant finding of this plan.

## Escalation (prominent — read before proceeding)

**A single `ε` cannot simultaneously satisfy the plan's required fixture set AND the
pre-existing `test/test_exactness.jl` WR-01 regression item.** Full detail in
`.planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md`
("Plan 27-02 — FIX-08 per-branch exactness floor: irreconcilable ε conflict (ESCALATED)").

Summary:

- `test/test_exactness.jl`'s pre-existing item "exact: relative gate refuses a base-shrunk
  cone slack an absolute τ would accept (WR-01)" (a `smax=10` branch, injected `l=5e-6` gap)
  needs `ε < 5e-8` to keep throwing (its whole documented purpose).
- The IEEE-13 ground canonical acceptance fixture (`test_acceptance.jl`, and the identical
  fixture reused by `test_admm.jl:78`/planning-oracle cross-validation) needs `ε ≳ 5e-5` to
  keep NOT throwing (it is genuinely exact; the residual is a Clarabel precision-floor
  artifact on 2 interior branches at PV-back-feed reverse-flow hours).
- These thresholds are 3 orders of magnitude apart — not a matter of finding a better
  constant. Root cause: for a thermally-limited branch, `ref_b = smax^2` scales UP with the
  branch's own `smax`; the WR-01 item's `smax=10` synthetic branch and the IEEE-13 fixture's
  interior branches (whose `ref_b` inherits the SMALL-`smax=0.0686` head branch's own flow
  magnitude) sit at very different points on that scale, while Clarabel's actual achievable
  cone-residual noise floor (~1e-8) does not shrink with network `smax`.
- **Per the locked policy, `MEASURED_ε_FIX08 = 1e-4` was chosen to satisfy the plan's
  EXPLICITLY-NAMED required set (Task 2's own acceptance criterion: the synthetic regression
  + the cluster-E/canonical fixtures). This leaves the pre-existing WR-01 item now PASSING
  (no longer throwing) — a "should-be-flagged now passes" case, escalated per the objective's
  locked decision rather than resolved by raising OR lowering ε.**
- **Consequence for the suite:** running `test/test_exactness.jl`'s full item set will show
  this ONE pre-existing item failing (its `@test_throws Exception` no longer observes an
  exception) until the orchestrator/user makes an explicit follow-up decision. This item was
  NOT edited by this plan.
- **Candidate resolutions (none applied, awaiting user triage):** (a) accept the item's
  regression as a documented consequence of FIX-08 and update it to use a smaller `smax`
  that still demonstrates the same "small absolute ≠ exact" lesson under the new per-branch
  floor; (b) give the near-zero-flow/WR-01 regime a separate, smaller floor constant distinct
  from the interior-branch head-flow-magnitude reference (an architectural change, Rule 4
  territory, out of scope here); (c) explicitly retire/relabel the WR-01 item's claim.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- FIX-08's per-branch floor is implemented, measured, and the 2 backward-compat call sites
  are verified unaffected.
- **Blocker for suite-green claims:** `test/test_exactness.jl`'s pre-existing WR-01 item will
  read as failing until the escalated ε conflict above is triaged by the user — the
  orchestrator should surface this prominently before declaring the phase/suite green.
- IEEE-8500 was NOT swept (not explicitly named in the plan's required fixture list; a much
  larger fixture) — if a future plan touches IEEE-8500's exactness gating, sweep it too
  before assuming `ε=1e-4` is universally safe there.

---
*Phase: 27-integer-planning-pricing-certificate-correctness*
*Completed: 2026-09-29*

## Self-Check: PASSED

- FOUND: `src/models/exactness.jl`
- FOUND: `test/test_exactness.jl`
- FOUND: `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-FINDINGS.md`
- FOUND: `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-02-SUMMARY.md`
- FOUND commit: `9374e5c`
- FOUND commit: `9876322`
