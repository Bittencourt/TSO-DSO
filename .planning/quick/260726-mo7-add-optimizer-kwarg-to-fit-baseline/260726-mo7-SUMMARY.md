---
quick_id: 260726-mo7
description: Add optimizer kwarg to fit_baseline
date: 2026-07-26
status: complete
commit: c099ee6
---

# Quick Task 260726-mo7 — Summary

Added an `optimizer` kwarg to `fit_baseline` and threaded it to all three internal solve sites.
**It unblocked what it was meant to unblock, and the result reverses a shipped v2.1 claim.**

## What changed

`src/pricing/fit.jl`

- New kwarg: `optimizer = select_optimizer(problem_class(pf))` — the same expression each site used
  before, so **the default path is byte-for-byte unchanged** and INFRA-02 holds (no concrete solver
  named; the default is the factory).
- Threaded to all three sites, now labelled `SITE n of 3` in source:
  1. `_fit_opt_solve` (per-prosumer FIT-OPT)
  2. `Model(optimizer)` (FIT AC-PF)
  3. **the nested `solve_welfare`** that forms the efficiency ratio — the site that actually matters,
     because it carries its own PF-04 gate (`assert_socp_exact!`). The FIT AC-PF calls only
     `assert_solved!`. Threading 1-2 without 3 would have fixed nothing.
- Docstring updated: the old "Every solve routes through `select_optimizer(problem_class(pf))`
  (INFRA-02)" sentence would have become false, so it now states that the *default* is the factory
  and records why the kwarg exists.

`test/test_pricing_fit.jl` — 4 new `@testitem`s, all passing:

| test | what it pins |
|---|---|
| default byte-identical to factory | implicit ≡ explicit on `social_fit`/`ratio`/`prosumer_surplus` |
| caller optimizer actually consumed | a 1-iteration factory must throw; if the kwarg were ignored it would solve |
| tightening preserves the optimum | the spike-003 property: residuals shrink, optimum does not move |
| **source tripwire** | exactly one `select_optimizer(` inside `fit_baseline` — the default |

The tripwire is the test that actually covers *all three* sites, and it catches a future new solve
site that no behavioural test would.

## Verification

**Suite:** 85 fit-tagged tests pass, 0 fail (filtering the stale sibling worktree — see Notes).

**The real verification** — spike 003's check re-run with the optimizer threaded into `fit_baseline`
(`.planning/spikes/003-phase18-fragility-tolerance/run-after-kwarg.log`):

```
default 1e-8  : 2/5 gate THREW   1/5 show the sign flip     ← unchanged, as required
tight   1e-10 : 0/5 gate THREW   5/5 show the sign flip     ← was 2/5 flipping before

delta    socp_maxgap    dadp_dso      fit_dso    flip
-0.05    3.505e-08      2.709838     -182.9611   YES
-0.02    1.900e-08      3.277535     -190.8755   YES   ← was unmeasurable
 0.00    1.162e-08      3.725742     -196.2165   YES
+0.02    4.610e-08      4.163925     -201.6167   YES   ← was unmeasurable
+0.05    1.342e-08      4.807417     -209.9950   YES   ← was unmeasurable
```

Equivalence control `MATCH ✓` (δ=0 @ default reproduces the committed `dso = 3.725705`,
`socp_maxgap = 3.060e-07`), so the default path is provably untouched and the comparison is valid.

Both surpluses are **monotone** across the band: `dadp_dso` 2.71 → 4.81, `fit_dso` −183 → −210. No
boundary, no discontinuity.

## What this settles

Spike 003 Finding 5 left open whether `fit_baseline`'s exactness failures were *also* numerical —
explicitly untestable at the time, for want of this kwarg. **Answered: yes.** Same noise-floor
mechanism as `solve_welfare`'s gate.

Consequently **v2.1's `sign_flip_survives: false` is refuted outright**, not merely narrowed. The
DSO-surplus sign flip holds at all five swept population points. The recorded "honest negative
robustness result" was a tolerance artifact end to end.

## Corrections now owed upstream (NOT done here — out of scope for this task)

1. `results/repro_stability_check/findings.txt` — `sign_flip_survives: false` and its
   HONEST-NEGATIVE-RESULT paragraph.
2. `.planning/milestones/v2.1-phases/18-directional-thesis-reproduction/18-01-SUMMARY.md`.
3. The published assumptions literate page (per 18-03) which carries the fragility caveat.
4. **Plan 18-02's golden band.** `DSO_BAND_HI` was derived as `1.5 × max|dso|` over
   successfully-solved points — which was 1 point. With 5 solving, `max|dso| = 4.807417`, so the rule
   now implies **7.211** against the pinned **5.5886**. `test_thesis_repro.jl` does not break
   (4.8074 < 5.5886), but the rule and the pinned value disagree and should be re-derived
   deliberately.
5. `scripts/repro_stability_check.jl` — its single try/catch wraps three solves, which is *why*
   Phase 18-01 misattributed 2 of 4 failures to `solve_welfare`. Split it per stage, and thread the
   new kwarg so the script can be re-run at a chosen tolerance.

## Notes / deviations

- **Executed inline rather than via `gsd-planner`/`gsd-executor` subagents.** The workflow delegates;
  session instructions prohibit spawning agents unprompted. Workflow guarantees were kept: task
  directory, PLAN.md, atomic commit, this SUMMARY, STATE.md row.
- **First test draft did `using Clarabel` and errored** — Clarabel is not a test-env dep, and adding
  one would mean re-resolving the pinned manifests. Fixed by deriving `base.optimizer_constructor`
  from the project's own factory, which is *more* INFRA-02-consistent than importing a solver.
- **Pre-existing gotcha (untouched):** `@run_package_tests` also discovers
  `TSO-DSO.worktrees/pdf-documentation-thesis-results/`, a stale sibling worktree, and runs its copy
  of the suite. Filtered out for these runs. An unfiltered `Pkg.test()` runs the suite twice.
- `.planning/spikes/003-phase18-fragility-tolerance/check.jl` was updated to pass the optimizer to
  `fit_baseline`; both logs are retained (`run.log` before, `run-after-kwarg.log` after).
