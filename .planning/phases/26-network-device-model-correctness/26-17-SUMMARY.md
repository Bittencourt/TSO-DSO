---
phase: 26-network-device-model-correctness
plan: 17
subsystem: testing
tags: [julia, jump, socp, clarabel, golden-regression, pricing]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness
    provides: FIX-03 (:smax_rev receiving-end limit), FIX-04 (battery soc[T+1] horizon linking), FIX-05 (flexible-load reactive draw) — the already-merged fixes whose golden-value consequences this plan re-derives
provides:
  - "test_ieee13.jl's 4 GOLDEN_* constants re-measured and re-pinned with inline old->new+cause comments"
  - "test_pricing_fit.jl's FIT_RATIO_GOLDEN re-measured and re-pinned"
  - "test_pricing_welfare.jl's net-EXPORTER surplus golden re-pinned and its near-lossless identity testitem calibrated to a tighter tol_gap"
affects: [26-08-golden-audit, 28-thesis-reproduction-restatement]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Golden re-pin discipline (SC-6/PM-06): every moved numeric literal carries an inline OLD->NEW+cause comment quoting the ACTUALLY-MEASURED value, never the triage's illustrative numbers verbatim"
    - "tol_gap calibration via explicit optimizer kwarg on solve_welfare, scoped to the specific near-degenerate fixture, never loosening the PF-04 gate itself"

key-files:
  created: []
  modified:
    - test/test_ieee13.jl
    - test/test_pricing_fit.jl
    - test/test_pricing_welfare.jl
    - .planning/phases/26-network-device-model-correctness/26-17-repro-fit-ratio.jl

key-decisions:
  - "All 4 test_ieee13.jl GOLDEN_* constants (V9_16, WELFARE, DADP16, SUM_DADP) re-pinned even though GOLDEN_WELFARE's old value still passes at rtol 1e-4 — per the plan's explicit instruction to update all 4 regardless of whether the old assertion happens to still hold"
  - "test_pricing_welfare.jl :66 fixture calibrated to tol_gap_abs=tol_gap_rel=1e-9 (not the tighter 3e-10), since 1e-9 already lands the surplus-identity diff at ~7e-15 (machine precision) — comfortably clear of the PF-04 gate per the plan's own 'if not comfortably clear, tighten further' criterion"
  - "Restored (rather than kept my initial simplified rewrite of) the planner's pre-existing 26-17-repro-fit-ratio.jl live-parsing design, which asserts against FIT_RATIO_GOLDEN PARSED LIVE from test_pricing_fit.jl rather than a duplicated hardcoded literal — a stronger, DRY-er verification pattern already scaffolded by the planner"

patterns-established:
  - "Golden re-pin comment format: '# Phase 26 gap-closure re-pin (PM-06) — <cause>; see 26-POSTMERGE-TRIAGE.md. OLD <old> -> NEW <new>.' on the line(s) preceding each moved literal"

requirements-completed: [FIX-03, FIX-04, FIX-05]

# Metrics
duration: 19min
completed: 2026-09-28
---

# Phase 26 Plan 17: Golden Re-Pin (PM-06) + Precision-Floor Calibration Summary

**Re-measured and re-pinned all four `test_ieee13.jl` goldens (V9_16 1.0436→1.0360, DADP16
1.402→0.394, ΣDADP 96.72→86.85, WELFARE -4823.16→-4823.50), the `test_pricing_fit.jl` FIT ratio
(0.643→0.772), and the `test_pricing_welfare.jl` net-exporter surplus split (prosumer 65.6→47.4,
dso 0.397→0.202), plus calibrated `test_pricing_welfare.jl`'s near-lossless 2-bus identity to
`tol_gap=1e-9` to clear a PF-04 solver-precision-floor artifact — every moved literal carries an
inline old→new+cause comment per PM-06/SC-6's no-silent-re-pin discipline.**

## Performance

- **Duration:** ~19 min (7cde1cd → 7d00f40)
- **Started:** 2026-09-28T21:20:59-03:00 (base commit)
- **Completed:** 2026-09-28T21:39:18-03:00
- **Tasks:** 3 completed
- **Files modified:** 4 (3 test files + 1 repro script; a 5th pre-existing repro script needed
  no changes)

## Accomplishments
- `test_ieee13.jl`'s pinned computed golden (OPT-02/OPT-03 testitem) re-measured live against
  the current merged code (FIX-01..05 plus all prior gap-closure plans) and re-pinned; the
  non-failing thesis `v₉[16]` cross-check now reports **Broken** (gap grew from 0.0057 to
  0.0133), as the triage predicted — this does not fail the suite, only its `@info`/`broken`
  marker changed.
- `test_pricing_fit.jl`'s `FIT_RATIO_GOLDEN` re-measured (0.772018581825438) and re-pinned;
  the sibling repro script's live-parsing design (asserts against the literal parsed FROM the
  edited test file, not a duplicate) was preserved.
- `test_pricing_welfare.jl`'s net-EXPORTER golden re-pinned (prosumer 47.38684825193795, dso
  0.2024939446849814) and its near-lossless identity testitem given an explicit
  `tol_gap_abs=tol_gap_rel=1e-9` override, clearing the PF-04 gate (ratio 3.985→well under 1,
  identity diff ~7e-15) without touching `assert_socp_exact!`'s gate itself.

## Task Commits

Each task was committed atomically:

1. **Task 1: Re-measure and re-pin test_ieee13.jl's 4 GOLDEN_* constants** - `70f4ad0` (test)
2. **Task 2: Re-measure and re-pin test_pricing_fit.jl's FIT_RATIO_GOLDEN** - `927cda4` (test)
   - Follow-up fix restoring the planner's superior live-parsing repro-script design (a
     self-inflicted deviation caught and corrected in the same task) - `1a9b717` (fix)
3. **Task 3: Re-pin test_pricing_welfare.jl's net-exporter golden + calibrate tol_gap on :66** - `7d00f40` (test)

**Plan metadata:** SUMMARY.md commit (this commit, immediately following)

## Files Created/Modified
- `test/test_ieee13.jl` - 4 `GOLDEN_*` constants re-pinned with inline old→new+cause comments;
  thesis cross-check comment updated to state the observed Broken outcome
- `test/test_pricing_fit.jl` - `FIT_RATIO_GOLDEN` re-pinned with an inline old→new+cause comment
- `test/test_pricing_welfare.jl` - net-EXPORTER `prosumer`/`dso` literals re-pinned; near-lossless
  identity's `solve_welfare` call given an explicit `tol_gap_abs=tol_gap_rel=1e-9` optimizer kwarg
- `.planning/phases/26-network-device-model-correctness/26-17-repro-fit-ratio.jl` - restored to
  the planner's pre-existing live-parsing scaffold (see Deviations below); functionally
  unchanged from the base commit, re-verified passing

## Decisions Made
- All 4 `test_ieee13.jl` golden constants updated even though `GOLDEN_WELFARE`'s move (-4823.16
  → -4823.50) still passes the OLD value at rtol 1e-4 — the plan's action explicitly requires
  updating all 4 regardless, per SC-6's no-silent-re-pin discipline (a golden that happens to
  still pass loosely is still stale and should reflect the actually-measured value).
- Chose `tol_gap=1e-9` (not `3e-10`) for the `:66` near-lossless fixture: at 1e-9 the
  surplus-identity diff is already ~7e-15 (machine precision) and the objective is unchanged,
  comfortably clear of the gate per the plan's own escalation criterion ("if not comfortably
  clear, tighten further").
- Kept golden re-pin comments compact (one line, not the fuller 3-line form used in
  `test_ieee13.jl`) in `test_pricing_welfare.jl`'s `:193` testitem, because the pre-existing
  `26-17-repro-pricing-welfare.jl` scaffold parses the pinned literals from a fixed 3000-character
  window starting at the testitem's title match; the fuller 3-line comment form pushed the `dso`
  literal outside that window and broke the live-parse (see Issues Encountered).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Self-inflicted: overwrote the planner's pre-existing repro-fit-ratio.jl scaffold with a weaker duplicate-literal design**
- **Found during:** Task 2
- **Issue:** `.planning/phases/26-network-device-model-correctness/26-17-repro-fit-ratio.jl`
  already existed at the base commit (a planner-authored scaffold using a live-parsing pattern:
  it reads `test/test_pricing_fit.jl`'s source and regex-parses the CURRENTLY-PINNED
  `FIT_RATIO_GOLDEN` literal, rather than hardcoding a duplicate value, so a wrong or missing
  re-pin fails the check). I used the `Write` tool without reading the file first (permitted by
  the tool only because the on-disk content matched what a "new file" write would accept) and
  replaced it with a simpler version that hardcodes the golden as a duplicate literal — losing
  the self-checking live-parse property.
- **Fix:** Restored the original live-parsing script content verbatim; re-ran it to confirm it
  still passes against the Task 2 re-pin (`MEASURED res.ratio = 0.772018581825438` ==
  `PARSED pinned FIT_RATIO_GOLDEN = 0.772018581825438`).
- **Files modified:** `.planning/phases/26-network-device-model-correctness/26-17-repro-fit-ratio.jl`
- **Verification:** `julia --project=. .planning/phases/26-network-device-model-correctness/26-17-repro-fit-ratio.jl` → `OK: measured ratio matches the pinned FIT_RATIO_GOLDEN within rtol=1e-4`
- **Committed in:** `1a9b717`

**2. [Rule 3 - Blocking] :193 golden re-pin comment length broke the sibling repro script's fixed-window live-parse**
- **Found during:** Task 3
- **Issue:** The pre-existing `26-17-repro-pricing-welfare.jl` scaffold locates the `:193`
  testitem via `findfirst("net-EXPORTER earns", src)` and searches a fixed 3000-character window
  from that point for the pinned `prosumer`/`dso` literals. My first attempt at the old→new+cause
  comments (matching `test_ieee13.jl`'s fuller 3-line style) pushed the `dso` literal past the
  3000-character boundary, so `26-17-repro-pricing-welfare.jl` failed with "Could not parse the
  pinned prosumer/dso golden literals".
- **Fix:** Shortened the re-pin comments to one compact line each ("`# PM-06 re-pin (FIX-04
  closed the T=3 soc0=Emax free hour-3 discharge): OLD 65.594 -> NEW.`"), which keeps both
  literals inside the window while still documenting the old value, cause, and PM-06 provenance.
- **Files modified:** `test/test_pricing_welfare.jl`
- **Verification:** `julia --project=. .planning/phases/26-network-device-model-correctness/26-17-repro-pricing-welfare.jl` → both `:66` and `:193` report OK
- **Committed in:** `7d00f40`

---

**Total deviations:** 2 auto-fixed (1 self-inflicted Rule-1 restoration, 1 Rule-3 formatting fix)
**Impact on plan:** Neither deviation touched src/ or changed any pinned numeric value; both were
corrections to test-infrastructure formatting/scaffold fidelity. No scope creep.

## Issues Encountered
- The first live-measurement attempts for both `test_ieee13.jl` and `test_pricing_fit.jl`'s
  fixtures failed under `julia --project=. -e '...'` one-liners because `test/fixtures_phase4.jl`
  and `FitFixtures` use TestItems' `@testmodule` macro, which is not defined outside the
  TestItems/TestItemRunner test-only dependency (consistent with the
  `gsd-plan-verify-testitemrunner-trap` memory). Worked around by regenerating a plain-`module`
  copy of `fixtures_phase4.jl` (mechanical `@testmodule X begin` → `module X` substitution) and
  by inlining `FitFixtures`'s small body directly, both under the session scratchpad — never
  committed, since the plan's own `26-17-repro-fit-ratio.jl`/`26-17-repro-pricing-welfare.jl`
  scaffolds already do this inlining correctly for the committed verify path.
- All three plan-specified `<verify>` commands were run to completion and pass:
  - Task 1: live one-liner measuring `v9_16`/`cost`/`dadp16`/`sumdadp` (matches the newly-pinned
    goldens; also independently reproduced the full testitem body — 5 Pass + 1 Broken as expected).
  - Task 2: `26-17-repro-fit-ratio.jl` → `OK`.
  - Task 3: `26-17-repro-pricing-welfare.jl` → both `:66` and `:193` `OK`; independently
    reproduced both full testitem bodies (6/6 and 9/9 assertions pass).

## User Setup Required
None - no external service configuration required.

## Cross-plan observations
- Per the parallel-execution note: this plan's IEEE-13 goldens (`test_ieee13.jl`) are
  **centralized-solve** goldens (`operational_oracle`/`solve_welfare`, not ADMM), so they do
  **not** depend on Plan 26-12's ADMM live-reactive default change. No re-check needed after
  26-12 merges.
- `test_pricing_welfare.jl`'s other testitems in the same file (net-IMPORTER pays, IEEE-13 ground
  solve identity, `+25% FIT ratio golden`) were left untouched — they are outside this plan's
  scope (only `:66` and `:193` are named in the plan's `must_haves`/tasks) and my edits did not
  touch their code paths. Not independently re-verified in this plan; flagging for the phase-close
  full-suite run to confirm they are unaffected (they should be, since no shared literal or
  fixture was edited).
- No stubs introduced. No new threat surface introduced (test-file golden constants and a
  solver-tolerance keyword only, per the plan's own threat-model disposition).

## Next Phase Readiness
- This plan's 4 legitimately-moved goldens (IEEE-13 h16 DADP, |V₉[16]|, FIT ratio, exporter
  surplus) are now re-pinned with old→new+cause comments, feeding Plan 26-08's cross-phase
  golden-move audit table (`26-GOLDEN-AUDIT.md`) as designed.
- The IEEE-13 thesis cross-check is now Broken (not Pass) — restated in Phase 28 per PM-06/PM-01.
- Ready for the orchestrator to fold this plan's re-pins into the phase's full-suite green-at-close
  verification alongside the other parallel gap-closure plans (26-08..26-20).

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-28*

## Self-Check: PASSED

All 6 claimed files found on disk (`test/test_ieee13.jl`, `test/test_pricing_fit.jl`,
`test/test_pricing_welfare.jl`, `26-17-repro-fit-ratio.jl`, `26-17-repro-pricing-welfare.jl`,
this SUMMARY). All 4 claimed commits found in `git log --oneline --all`
(`70f4ad0`, `927cda4`, `1a9b717`, `7d00f40`).
