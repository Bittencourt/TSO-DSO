---
phase: 38-close-v4-0-audit-gaps
plan: 10
subsystem: phase-gate
tags: [gate, full-suite, jet, docs-build, count-sets, validation]
requires:
  - phase: 38-01..38-09
    provides: "shared cone kernel, MPC hybrid first tier, OOS exactness gate, ADMM timeout items, ADMM import-only rejection, Symbol reactive mode, prose and FRAMEWORK_GUIDE sweeps, per-plan test deltas in 38-MEASUREMENTS.md"
provides:
  - "38-FINAL-GATES.md: phase gate evidence (static gates, both full runs, docs build, pass arithmetic, explained moves, success-criterion mapping, MANUAL list)"
  - "38-VALIDATION.md signed off (status complete, nyquist_compliant true, wave_0_complete true)"
affects: [v4.0 milestone close, Phase 38 verification]
tech-stack:
  added: []
  patterns: ["validate each detached log with check_suite_log.py before the next commit; post-commit verifies read .done/.totals"]
key-files:
  created:
    - .planning/phases/38-close-v4-0-audit-gaps/38-FINAL-GATES.md
  modified:
    - .planning/phases/38-close-v4-0-audit-gaps/38-VALIDATION.md
key-decisions:
  - "The ledger's count-sets total (all=517 fast=480 slow=37 files=99) is authoritative over the CONTEXT estimate 513/476; measured equal"
  - "Pass arithmetic closes exactly: 32224 + 80 = 32304 (1.12.5) and 32219 + 80 = 32299 (1.12.7), no unexplained unit"
  - "TSODSO_TEST_VERBOSE=1 prints only the outer totals row, so the admm_timeout items have no in-suite timing; the 38-06 measurement (about 13 s warm) stands and they stay fast"
requirements-completed: [FIX-08, FIX-10, ARCH-02, ARCH-08, HYG-02, HYG-03, HYG-05]
duration: ~80min
completed: 2026-10-07
---

# Phase 38 Plan 10: Phase gate Summary

**Both full runs close exactly against the ledger: 1.12.5 Pass 32304 = 32224 + 80 and 1.12.7 Pass 32299 = 32219 + 80, both with 0 Fail, 0 Error and Broken 5. The canary holds at iters 56, count-sets is 517/480/37/99, JET has 0 NEW, the docs build is OK, and every guard is green.**

## Performance

- **Duration:** about 80 min (two 28-minute detached suites and a docs build, run sequentially)
- **Started:** 2026-10-07 22:35 -0300 (HEAD ab18f3e)
- **Completed:** 2026-10-07 23:50 -0300
- **Tasks:** 3
- **Files modified:** 2 (+ this summary)

## Gate table

| Gate | 1.12.5 | 1.12.7 |
|---|---|---|
| Full suite (`check_suite_log.py --broken 5`) | `suite OK`: Pass 32304 / Fail 0 / Error 0 / Broken 5 / Total 32309 | `suite OK`: Pass 32299 / Fail 0 / Error 0 / Broken 5 / Total 32304 |
| Expected Pass (baseline + 80) | 32224 + 80 = 32304, delta 0 | 32219 + 80 = 32299, delta 0 |
| Canary | iters 56, welfare -4823.66604824162 | iters 56, welfare -4823.666048218671 (4.8e-12 rel) |
| soft-scope warnings | 0 | 0 |
| MPC escalation warnings | 7 (6 high-PV + new regression item) | 10 (+3 for scenario B at t=4, ratio 1.165, the predicted explained move) |
| JET (`jet_check.jl`, `--selftest`) | — | 12 current / 12 baseline, 0 NEW, 0 FIXED; selftest OK |
| count-sets `--strict` | all=517 fast=480 slow=37 files=99 canary=1 outside=0 (= ledger) | — |
| Docs build (`--mode docs`) | `docs OK`, exit 0, 0 `Cannot resolve @ref`; stochastic page 5/10 excluded live | — |
| Guards | planning IDs OK (250) + selftest; scripts index OK (37) + selftest; setup names 0 unresolved + selftest; script API OK (40) + selftest (55); runner selftest OK; format210 no change; content loss OK; CI.yml / slow.yml parse | — |

Per-plan Pass deltas (ledger): 38-01 +8, 38-02 +7, 38-04 +18, 38-06 +19, 38-07 T1 +7, 38-07 T2 +21 = **+80**.
Plans 03, 05, 08 and 09 changed no assertion.

## Task Commits

1. **Task 1: Static guards, formatter, count-sets and JET.** Commit `958cc98`.
2. **Task 2: 1.12.5 full run, validated, then pass arithmetic.** Commit `806c4cd`.
3. **Task 3: 1.12.7 full run and docs build, validated, then FINAL-GATES completion and validation sign-off.** Commit `c563c09`.

## Files Created/Modified

- `.planning/phases/38-close-v4-0-audit-gaps/38-FINAL-GATES.md`: gate evidence.
- `.planning/phases/38-close-v4-0-audit-gaps/38-VALIDATION.md`: signed off; every row green.

## Decisions Made

See key-decisions in the frontmatter. No src/test change. No golden or canary was touched.

## Deviations from Plan

None. The plan ran as written. The formatter produced no changes, so there was no separate style commit. The
admm_timeout in-suite timing could not be read from the verbose log, which the plan allowed for ("if verbose timings exist").

## Issues Encountered

- `gsd-sdk query state.record-metric` rejected positional arguments and needed `--phase/--plan/...` flags.
  `state.advance-plan` left the "Current Position" wording stale, so STATE.md was corrected by hand.

## MANUAL (needs GitHub)

The CI format job's setup-name guard, the Actions matrix (1.10/1.11/1.12), the jet job and nightly slow.yml, plus the
FRAMEWORK_GUIDE prose spot-check. See 38-FINAL-GATES.md.

## Next Phase Readiness

Phase 38 is ready for verification (`/gsd-verify-work 38`). After that the v4.0 milestone can close. REQUIREMENTS.md was
intentionally not modified (all seven IDs were already complete; this phase closed audit gaps against them).

## Self-Check: PASSED

- FOUND: .planning/phases/38-close-v4-0-audit-gaps/38-FINAL-GATES.md
- FOUND: .planning/phases/38-close-v4-0-audit-gaps/38-VALIDATION.md (nyquist_compliant: true)
- FOUND commits: 958cc98, 806c4cd, c563c09
- FOUND: .planning/tmp/36/p38-full125.totals, p38-full127.totals, p38-docs-final.done (0)
