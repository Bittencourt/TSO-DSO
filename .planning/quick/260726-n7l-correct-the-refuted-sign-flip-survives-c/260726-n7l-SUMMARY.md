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
repo tree), which looked like a regression introduced during the session.

### First diagnosis — WRONG

I blamed my own `Pkg.develop(path=".")` for re-resolving the pinned test environment, then "confirmed"
it by restoring the manifests **and** switching to `Pkg.test()` in one step, and attributing the pass
to the restore. Two changes, one conclusion — not a discriminating test.

### Actual cause — the `-e` invocation, pre-existing and already documented

Re-running the `-e` form against a **clean** environment reproduces the failure bit-for-bit
(`1.3781586234547918`). So the environment was never implicated.

This is the known TestItemRunner hazard: in a `julia -e '...'` string there is no real
`__source__.file`, so TestItemRunner resolves the package/test root via cwd and its `joinpath(…,"..")`
walk picks up the **stale sibling worktree**
`/home/pedro/programming/TSO-DSO.worktrees/pdf-documentation-thesis-results/`, whose fixtures still
carry the pre-Phase-17-retune `LOAD_SCALE_IEEE123 = 0.03`. That population point yields exactly gap
ratio **1.378**. It was diagnosed in a prior session and recorded in project memory — **which I did
not read before diagnosing.**

**New detail worth recording:** filtering on `ti.filename` for `.worktrees` does **not** protect you.
The erroring item is reported under the *main* path (`TSO-DSO/test/test_thesis_repro.jl:33`) because
the contamination is in **setup-module / fixture** resolution, not the item's filename. Only a real
entrypoint file is immune.

### The separate, real mistake

`Pkg.develop(path=".")` genuinely **did** mutate the pinned test environment —
`test/Manifest.toml` (1232 lines) and `test/Project.toml` (14 lines), both clean at session start.
CLAUDE.md pins those for reproducibility. Reverted with
`git checkout -- test/Project.toml test/Manifest.toml`. It did **not** cause the REPRO-01 error, and
the verification below ran under the restored environment, so nothing rests on the mutated state.

**Correct invocation:** `julia --project=. -e 'import Pkg; Pkg.test()'` — real `test/runtests.jl`
entrypoint, immune to the sibling-worktree walk, builds a temp env from the pinned manifest, mutates
nothing. The trap: `@run_package_tests` discovers **zero** items via `--project=test` without the
`develop` call, so the hazardous invocation is the one that appears to work.

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

**Coincidence worth noting, since it nearly misled the whole diagnosis:** the spurious sibling-worktree
failure ratio (**1.378**, gap 1.54e-6) sits in exactly the same numeric band as the genuine noise-floor
artifacts this session characterized (ratios 1.10–4.76, gaps 1.5e-6–5.1e-6). Two unrelated defects
producing indistinguishable symptoms — which is precisely why the tolerance ladder and the
`-e`-invocation check are both needed, and why "the number looks like noise" is not a diagnosis.

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
