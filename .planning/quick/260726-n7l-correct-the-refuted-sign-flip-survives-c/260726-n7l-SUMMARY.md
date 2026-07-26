---
quick_id: 260726-n7l
description: Correct the refuted sign_flip_survives claim in findings.txt and 18-01-SUMMARY
date: 2026-07-26
status: complete
---

# Quick Task 260726-n7l — Summary

Corrected the refuted `sign_flip_survives: false` claim in both committed artifacts, and — while
verifying — **caught and reverted a pinned-environment mutation I had introduced earlier in the
session**, which had produced a false regression signal.

## Editorial principle applied

**Corrected, not rewritten.** These are an archived milestone summary and a generated measurement
artifact. What was measured at default tolerance is a real record and the raw numbers are accurate —
the *verdict* and the *attribution* were wrong. So every original assertion is preserved
(struck-through or under an "ORIGINAL REPORT" heading) with a correction attached, rather than
silently replaced. The audit trail of what was believed on 2026-07-26 06:21 stays legible.

## Task 1 — `results/repro_stability_check/findings.txt`

Prepended a `!!! CORRECTION` block (67 lines) carrying: the superseded verdict, the corrected 5-point
table, the numerical cause, the misattribution table, the golden-band inconsistency, and evidence
paths. Original report preserved verbatim below an explicit separator.

**Critical caveat stated in the banner:** this file is **generated** by
`scripts/repro_stability_check.jl:343`, so re-running that script *overwrites the correction*. The
banner names the script fix as owed (split the three-solve try/catch; thread the `optimizer` kwarg
from `c099ee6`).

## Task 2 — `18-01-SUMMARY.md`

Added a `## Correction` section (~60 lines: corrected table, cause, misattribution, the lesson, what
remains owed, evidence) and annotated **eight** specific assertions — three more than the plan
anticipated, found by grepping rather than trusting the plan's line list:

| location | what was wrong |
|---|---|
| frontmatter `provides:` | asserted the refuted finding as a deliverable |
| frontmatter `key-decisions:` | "reported honestly" — true but the verdict was still wrong |
| **bolded headline** (not in the plan) | the whole one-line summary of the plan |
| measured-results bullet | "ALL FOUR ... `solve_welfare`'s `assert_socp_exact!` throws" — the misattribution |
| measured-results bullet | `sign_flip_survives: false` |
| deviations "Fix:" bullet | the one-try/catch-for-three-solves that **caused** the misattribution |
| deviations "Verification:" bullet (not in the plan) | "all 4 points **correctly** reported" — overstated |
| 18-02 readiness (not in the plan) | band rule now implies 7.211 vs pinned 5.5886 |
| 18-03 readiness | the instruction that put a false caveat into the published page |
| files-created bullet (not in the plan) | "never hand-edited" — no longer true after Task 1 |

## The mistake I made and caught

While verifying the golden gate I found `test_thesis_repro.jl`'s primary REPRO-01 item **erroring**:

```
SOCP relaxation INEXACT: worst gap/(atol+rtol·|cone|)=1.3781586234547918 > 1
(max abs |l·v−(P²+Q²)|=1.540459323656762e-6) — prices REFUSED
```

It **passed** at the session-start commit (`1812d38`, verified in a throwaway worktree outside the
repo tree), so it was a real regression introduced during the session.

**Cause: my own `Pkg.develop(path=".")`**, used to run the fit tests earlier via
`julia --project=test`. That re-resolved the **pinned** test environment — `test/Manifest.toml`
(1232 lines) and `test/Project.toml` (14 lines), both clean at session start. Shifted solver numerics
were enough to push a gate sitting near the noise floor over its threshold.

CLAUDE.md pins those files precisely so results are reproducible; mutating them as a side effect of
running tests defeated that. **Reverted with `git checkout -- test/Project.toml test/Manifest.toml`.**

**Consequence:** every "tests pass" reported earlier in this session was measured under a mutated
environment and did not stand as stated. Re-verified below under the pinned environment.

**Correct invocation:** `julia --project=. -e 'import Pkg; Pkg.test()'` — builds a temp env from the
pinned manifest and mutates nothing. Note `@run_package_tests` discovers **zero** items without the
`develop` call, which is exactly why the wrong path was tempting.

## Verification (pinned environment, `Pkg.test()`)

```
2358 passed · 1 failed · 0 errored · 3 broken   (14m58s)

test/test_thesis_repro.jl    6 pass    ← REPRO-01 fine; the error was the env mutation
test/test_pricing_fit.jl    79 pass    ← was 70; +9 from 260726-mo7's four new testitems

The single failure: Aqua "Stale dependencies" —
  isempty(Base.PkgId[... "CairoMakie"])
  the known-false failure from the uncommitted root Project.toml drift.
```

So: **`src/pricing/fit.jl` is clean, no regression**, and the golden gate does pass — which makes the
claim written into both corrected artifacts ("`test_thesis_repro.jl` does not break, 4.8074 < 5.5886")
accurate as stated.

## Still owed (unchanged, tracked in STATE.md)

1. **The published 18-03 assumptions literate page** — carries the false fragility caveat. Highest
   priority; it is the reader-facing artifact.
2. **Plan 18-02's golden band** — `1.5 × max|dso|` now implies 7.211 vs pinned 5.5886. Not failing.
3. **`scripts/repro_stability_check.jl`** — split the per-stage try/catch; thread the `optimizer`
   kwarg. Blocks regenerating `findings.txt` without losing the correction banner.

## Notes

- No code changed. No measurement re-run.
- Executed inline rather than via `gsd-planner`/`gsd-executor`; workflow guarantees kept (task dir,
  PLAN, SUMMARY, STATE row, commit).
- A PreToolUse hook flagged a prompt-injection false positive on the PLAN ("the refuted f**act as a**
  bare truth" matching `act as a`); reworded.
