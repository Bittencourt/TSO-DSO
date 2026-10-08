---
phase: 28-goldens-re-derivation-thesis-reproduction-restatement
plan: 05
subsystem: testing
tags: [documenter, literate, pkg-test, audit, python, cairomakie, julia]

# Dependency graph
requires:
  - phase: 28-goldens-re-derivation-thesis-reproduction-restatement
    plan: "01"
    provides: "audit_goldens.py + 28-CROSS-PHASE-AUDIT.md (SC-1 mechanical golden-move audit)"
  - phase: 28-goldens-re-derivation-thesis-reproduction-restatement
    plan: "02"
    provides: "REPRO-01 re-run + old-vs-new restatement table"
  - phase: 28-goldens-re-derivation-thesis-reproduction-restatement
    plan: "03"
    provides: "EXACT-04 dual-mode gate-1/gate-2 re-verification"
  - phase: 28-goldens-re-derivation-thesis-reproduction-restatement
    plan: "04"
    provides: "MPC truth-settlement + DLMP naming restatement"
provides:
  - "Full-suite certification at final Phase 28 HEAD: 30703 pass / 0 fail / 0 error / 5 broken -- exact match to the Phase 27 close baseline, zero deltas"
  - "Full Documenter/Literate docs build certified green (exit 0) after fixing 2 genuine pre-existing bugs unrelated to any Phase 28 plan's own edits"
  - "audit_goldens.py's known ±5-line-window false negative resolved via a documented, cited ALLOWLIST mechanism -- script now exits 0 at final HEAD"
  - "28-FINDINGS.md: consolidated per-plan findings log for the whole phase"
  - "28-RESTATEMENT-SUMMARY.md: one table of every headline old->new value with named cause, linked from PROJECT.md"
  - "PROJECT.md Current State section: Phase 28 COMPLETE paragraph"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Documented, cited ALLOWLIST for a mechanical audit script's own known detector limitations -- never silently absorbed, never used to hide a genuinely new finding"

key-files:
  created:
    - .planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-final-suite.log
    - .planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-final-suite.done
    - .planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-docs-build.log
    - .planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-docs-build.done
    - .planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-FINDINGS.md
    - .planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-RESTATEMENT-SUMMARY.md
  modified:
    - docs/literate/prosumer_welfare.jl
    - docs/make.jl
    - .planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/scripts/audit_goldens.py
    - .planning/PROJECT.md

key-decisions:
  - "docs-build task 1: relaunched the docs build detached TWICE (not the plan's single-launch expectation) because the first two attempts each hit a genuine, unrelated pre-existing bug; fixed each in place (Rule 1/Rule 3) rather than declaring the gate 'as designed, not our scope' -- the plan's own acceptance criterion is that the WHOLE docs build succeeds, not just the 6 phase-touched pages"
  - "audit_goldens.py Task 2: fixed via an explicit, cited ALLOWLIST keyed by (file, new_lineno) rather than widening the +/-5-line WINDOW_RADIUS -- avoids changing detection behavior on FUTURE diffs the script has not yet seen, per the plan's own explicit instruction to choose one of these two paths and never silence via a test-file edit"
  - "docs/make.jl size_threshold: raised generously (1024/800 KiB, ~1.5x headroom over the measured 676.24 KiB) rather than the minimum needed to pass today, to avoid a near-certain re-bump next phase as the API surface keeps growing organically"

requirements-completed: [FIX-11]

# Metrics
duration: ~50min
completed: 2026-09-30
---

# Phase 28 Plan 05: Phase-Closing Gate (Full Suite + Docs Build Certification, Audit Re-Run, Restatement Consolidation) Summary

**Certified the full test suite (30703/0/0/5, an exact match to the Phase 27 baseline) and the full Documenter/Literate docs build (green after fixing two genuine pre-existing bugs — a latent `DimensionMismatch` in `prosumer_welfare.jl`'s SOC plot and `api.md`'s outgrown HTML size threshold) at the final Phase 28 HEAD, re-confirmed the Wave-1 golden-move audit script exits 0 via a documented allowlist entry, and consolidated every plan's findings into `28-FINDINGS.md` + `28-RESTATEMENT-SUMMARY.md`, closing FIX-11.**

## Performance

- **Duration:** ~50 min (dominated by a ~29-min full-suite run and 3 sequential docs-build attempts)
- **Started:** 2026-09-30T09:01:56Z
- **Completed:** 2026-09-30T09:52:00Z (approx.)
- **Tasks:** 3/3 completed
- **Files modified:** 4 tracked source/config files + 4 new log/marker files + 2 new consolidation docs + 1 PROJECT.md edit

## Accomplishments

- **Task 1:** Certified the full suite (`julia --project=. -e 'import Pkg; Pkg.test()'`, detached, polled to completion, ~29 min) at HEAD=817ada4: **30703 pass / 0 fail / 0 error / 5 broken** — an EXACT match to the Phase 27 close baseline (30703/0/0/5 at `40ccff2`), zero deltas to attribute. `git worktree list` confirmed no `.claude/worktrees/agent-*` contamination (only unrelated sibling worktrees under a different path, `TSO-DSO.worktrees/*`); the suite log itself contains zero `.claude/worktrees/` lines. Certified the full Documenter/Literate docs build (`julia --project=docs docs/make.jl`, also detached) — after two sequential failures from genuine, pre-existing, phase-unrelated bugs (see Deviations), a third attempt completed with exit code 0 and zero thrown exceptions; all 6 phase-touched literate pages confirmed non-throwing.
- **Task 2:** Re-ran `scripts/audit_goldens.py` at the final HEAD; it reproduced the same single known false-negative row Plan 28-01 already investigated (`test/test_admm.jl:113->145`). Added an explicit, cited `ALLOWLIST` entry to the script (keyed by file+lineno, citing `28-CROSS-PHASE-AUDIT.md` Section 1) rather than widening the detection window or editing any `test/` file. The script's `--selftest` still passes; the real re-run now reports 12 attributed + 1 allowlisted (cited) + 0 unattributed, exit code 0.
- **Task 3:** Wrote `28-FINDINGS.md` (one section per plan, consolidating every Phase 28 finding) and `28-RESTATEMENT-SUMMARY.md` (one table of every headline old->new value with named cause, plus a closing paragraph). Added a "Phase 28 COMPLETE" paragraph to `.planning/PROJECT.md`'s Current State section, linking to the restatement summary — confirmed via diff that only the Current State section changed, no historical milestone prose touched.

## Task Commits

1. **Task 1: Full-suite + docs-build certification, detached** - `e57f044` (feat)
2. **Task 2: Re-run the Wave-1 audit script against final HEAD** - `dd0131f` (fix)
3. **Task 3: Consolidate findings, write the restatement summary, update PROJECT.md** - `0c0d336` (docs)

## Files Created/Modified

- `docs/literate/prosumer_welfare.jl` - Fixed a `DimensionMismatch` in the SOC plot (`bvars.soc` is `T+1`-long since Phase 26 FIX-04; `hours` is `T`-long) by truncating to `[1:T]`, matching the project's established convention
- `docs/make.jl` - Raised `api.md`'s HTML `size_threshold`/`size_threshold_warn` from 600/400 KiB to 1024/800 KiB (the page organically grew to 676.24 KiB, exceeding the old hard limit)
- `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/scripts/audit_goldens.py` - Added a documented, cited `ALLOWLIST` mechanism for the script's own known ±5-line-window false negative; reports allowlisted rows in a separate visible section
- `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-final-suite.log`/`.done` - Full-suite certification log (HEAD=817ada4, 30703/0/0/5, exit 0)
- `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-docs-build.log`/`.done` - Final successful docs-build log (exit 0, zero thrown exceptions)
- `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-FINDINGS.md` - Consolidated per-plan findings log for the whole phase
- `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-RESTATEMENT-SUMMARY.md` - One table of every headline old->new value with named cause
- `.planning/PROJECT.md` - New "Phase 28 COMPLETE" paragraph in the Current State section

## Decisions Made

- Relaunched the docs build detached three times total (not the plan's implicit single-shot expectation): attempt 1 failed on `prosumer_welfare.jl`'s SOC-plot crash, attempt 2 (after that fix) failed on `api.md`'s size threshold, attempt 3 (after both fixes) succeeded. Both root causes were unrelated to any Phase 28 plan's own file edits — the first is the same latent Phase-26-FIX-04-driven class of bug Plans 28-02/28-04 already found and fixed elsewhere, never previously caught in this specific page; the second is organic API-surface growth against a limit set once, years earlier. Both are squarely Rule 1 (bug)/Rule 3 (blocking) auto-fixes: the plan's own acceptance criterion requires the WHOLE docs build to succeed with zero thrown exceptions, not merely the 6 phase-touched pages.
- Chose the ALLOWLIST path (not widening `WINDOW_RADIUS`) for `audit_goldens.py`'s Task 2 fix, per the plan's own explicit either/or instruction — widening the window changes the script's behavior on diffs it has not yet seen (a broader, less-audited change), while a cited allowlist entry is a narrow, fully-transparent fix scoped to exactly the one already-investigated row.
- Raised `docs/make.jl`'s size thresholds with headroom (1024/800 KiB, ~1.5x over the measured 676.24 KiB) rather than the bare minimum, since the page's own history (600 KiB set once at `dc0de79`, tripped once already by Phase 28) shows it grows roughly monotonically as the API surface expands — a minimal bump would likely need re-doing again soon.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `docs/literate/prosumer_welfare.jl`'s SOC plot threw `DimensionMismatch`**
- **Found during:** Task 1, first docs-build attempt
- **Issue:** `scatterlines!(ax3, hours, value.(bvars.soc); ...)` — `hours = 1:T` (length `T=4` on this page's fixture) but `bvars.soc` is `T+1`-long since Phase 26 FIX-04 closed the battery SOC recursion over the whole window. This is the SAME latent class of bug Plans 28-02 (`scripts/thesis_caseA.jl`) and 28-04 (`scripts/demo_mpc_plots.jl`) already found and fixed elsewhere this phase — never previously caught here because this specific literate page had not been exercised end-to-end since FIX-04 landed.
- **Fix:** `scatterlines!(ax3, hours, value.(bvars.soc)[1:T]; ...)`, truncating to the `T`-long `hours` axis, matching the established project convention (`demo_mpc_plots.jl:173`, `thesis_caseA.jl`).
- **Files modified:** `docs/literate/prosumer_welfare.jl`
- **Verification:** Re-ran the full docs build; this page's markdown generation and `@example` block execution completed without throwing.
- **Committed in:** `e57f044` (Task 1 commit)

**2. [Rule 3 - Blocking] `docs/make.jl`'s `api.md` HTML output exceeded the configured `size_threshold`**
- **Found during:** Task 1, second docs-build attempt (after fixing #1 above)
- **Issue:** `makedocs` threw `HTMLSizeThresholdError`: the generated `api.md` HTML is 676.24 KiB, exceeding the 600 KiB hard `size_threshold` set once post-v1 (commit `dc0de79`) and never revisited across Phases 9-27's organic growth in exported symbols/docstrings.
- **Fix:** Raised `size_threshold`/`size_threshold_warn` from 600/400 KiB to 1024/800 KiB, with an updated comment explaining the history and margin.
- **Files modified:** `docs/make.jl`
- **Verification:** Re-ran the full docs build; exit code 0, `grep -c ERROR` returns 0, zero `failed to run` lines.
- **Committed in:** `e57f044` (Task 1 commit)

**3. [Rule 3 - Blocking, per plan's own explicit instruction] `audit_goldens.py`'s known false negative at final HEAD**
- **Found during:** Task 2
- **Issue:** Re-running the audit script at the final HEAD reproduced the exact same single unattributed row (`test/test_admm.jl:113->145`) Plan 28-01 already investigated and resolved by direct inspection — a window-radius false negative, not a genuinely unattributed golden move. The plan's own `<verify>` requires the script to exit 0.
- **Fix:** Per the plan's own explicit either/or instruction ("fix the SCRIPT's heuristic or add an explicit, documented allowlist entry citing the audit row"), added a documented `ALLOWLIST` dict keyed by `(file, new_lineno)` with a mandatory citation string, rather than widening `WINDOW_RADIUS` (which would change detection behavior on future, unaudited diffs) or editing any `test/` file.
- **Files modified:** `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/scripts/audit_goldens.py`
- **Verification:** `--selftest` still passes; real re-run at `--base 5939799 --head HEAD` now reports 12 attributed + 1 allowlisted (cited) + 0 unattributed, exit code 0.
- **Committed in:** `dd0131f` (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (2 Rule-1/Rule-3 docs-build bugs unrelated to any Phase 28 plan's own scope, 1 Rule-3 fix explicitly anticipated and pre-authorized by this plan's own text).
**Impact on plan:** All three were necessary for this plan's own stated acceptance criteria (whole docs build succeeds; audit script exits 0). No scope creep — no `src/` model code touched, no test goldens edited or re-pinned.

## Issues Encountered

- A transient `ps aux` check during the ~29-minute full-suite run showed no `julia` process, briefly suggesting the run had died; a follow-up check moments later confirmed it was still running (memory/CPU active, log still growing) — a race in the observation, not an actual interruption. The run completed normally at exit 0. No corrective action was needed; documented here per this project's "verify, don't assume" convention rather than silently ignored.
- The docs build needed 3 sequential detached launches (not the plan's implicit single-shot flow) due to the two genuine pre-existing bugs above — each was diagnosed from its own log, fixed, and the build relaunched; no wasted full-suite re-runs were needed since the docs build is independent of and did not require re-running `Pkg.test()`.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- FIX-11 is fully closed: the SC-1 cross-phase audit, SC-2 thesis-reproduction re-run, and SC-3 SOCP-inexactness + deferred restatements are all resolved and certified together at one commit (this plan's own Task 1), per the phase's own closing-gate requirement mirroring Phase 26/27's precedent.
- Phase 28 is complete. `.planning/STATE.md` and `.planning/ROADMAP.md` are intentionally untouched by this plan — the orchestrator updates them at phase close using this SUMMARY.
- No blockers. `docs/make.jl`'s `api.md` size threshold has headroom for continued organic growth but will likely need another bump eventually — flagged in `28-FINDINGS.md`'s "carried forward" section, not urgent.

---
*Phase: 28-goldens-re-derivation-thesis-reproduction-restatement*
*Completed: 2026-09-30*

## Self-Check: PASSED

- FOUND: `28-final-suite.log`, `28-final-suite.done`, `28-docs-build.log`, `28-docs-build.done`
- FOUND: `28-FINDINGS.md`, `28-RESTATEMENT-SUMMARY.md`, `28-05-SUMMARY.md`
- FOUND: `docs/literate/prosumer_welfare.jl`, `docs/make.jl`, `scripts/audit_goldens.py`, `.planning/PROJECT.md`
- FOUND commit: `e57f044` (Task 1)
- FOUND commit: `dd0131f` (Task 2)
- FOUND commit: `0c0d336` (Task 3)
