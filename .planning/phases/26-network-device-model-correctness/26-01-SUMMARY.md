---
phase: 26-network-device-model-correctness
plan: 01
subsystem: test-infrastructure
tags: [baseline, ci, full-suite, provenance]
requirements: [FIX-01, FIX-02, FIX-03, FIX-04, FIX-05]
dependency-graph:
  requires: []
  provides:
    - ".planning/phases/26-network-device-model-correctness/26-BASELINE.md"
    - ".planning/phases/26-network-device-model-correctness/26-baseline-suite.log"
  affects:
    - "Plan 26-08 (SC-6 golden-move audit diffs against this baseline)"
tech-stack:
  added: []
  patterns:
    - "Detached nohup/setsid full-suite launch + bounded background-poll loop (no foreground sleep chain, no bare `&` that dies with the turn)"
key-files:
  created:
    - .planning/phases/26-network-device-model-correctness/26-baseline-suite.log
    - .planning/phases/26-network-device-model-correctness/26-baseline-suite.done
    - .planning/phases/26-network-device-model-correctness/26-BASELINE.md
  modified: []
decisions:
  - "Ran the baseline suite directly inside this plan's own isolated worktree-agent checkout (already pinned to PRE_PHASE_SHA by the mandatory branch check) instead of nesting a second `git worktree add` inside it — the outer worktree already satisfies the plan's self-enforcing isolation requirement, and the sandbox refuses git commands that would point outside the current worktree root."
metrics:
  duration: "~35 minutes (suite run ~31-33 min + attribution/writeup)"
  completed: 2026-09-28
---

# Phase 26 Plan 01: Pre-Fix Full-Suite Baseline Summary

**One-liner:** Captured a clean, isolation-certified, HEAD-attributed pre-fix baseline —
30154 pass / 0 fail / 0 error / 3 broken (all individually attributed), 0 soft-scope warnings —
for Plan 26-08's final golden-move audit to diff against.

## What Was Built

Two tasks, both fully autonomous:

1. **Task 1** — Launched the full test suite (`julia --project=. -e 'import Pkg; Pkg.test()'`)
   detached (`nohup setsid ... </dev/null &`) inside this plan's own isolated worktree-agent
   checkout, pinned at `PRE_PHASE_SHA = 5939799852270a1e6cc894d2d8d676496b7cf9d6`. Polled the
   `.done` exit-code marker via two bounded background-tracked polling loops (25 min each,
   completed on the second) rather than a foreground sleep chain or a bare backgrounded `&` job
   that would die with the agent's turn — per the `background-suite-orphan-race` project memory.
   Captured the worktree's `rev-parse HEAD` and `status --porcelain` immediately after completion
   as the isolation certificate for Task 2.
2. **Task 2** — Parsed the 140,500-line log's final `Test Summary` and wrote
   `26-BASELINE.md`: exact counts, the `grep -c "soft scope is ambiguous"` invariant (0), and a
   named, file:line-cited cause for every one of the 3 non-pass ("Broken") items, plus the
   isolation certificate assertion (HEAD match + clean tree, both confirmed).

## Baseline Result

| Metric | Count |
|---|---|
| Pass | 30154 |
| Fail | 0 |
| Error | 0 |
| Broken | 3 (all named below) |
| Total | 30157 |
| Soft-scope warnings | 0 |
| Suite exit code | 0 |
| HEAD | `5939799852270a1e6cc894d2d8d676496b7cf9d6` |

**The 3 broken items**, each confirmed by direct log inspection (not assumed):

1. `test/test_diagnostics_plot.jl:106` — `@test_skip Base.find_package("CairoMakie") !== nothing`.
   CairoMakie is a clean-checkout weakdep, absent here (this worktree carries none of Pedro's
   main-checkout uncommitted CairoMakie-as-hard-dep drift).
2. `test/test_planning_nash.jl:588` — identical CairoMakie weakdep `@test_skip`.
3. `test/test_pricing_welfare.jl:358` — `@test (gap < 0.1) broken = (gap >= 0.1)`, measured
   `gap = 0.2500261432433949 ≥ 0.1` this run. This is the already-shipped, documented v2.1
   finding (PROJECT.md: "+25% welfare magnitude does NOT [reproduce] (~+0.045%)", REPRO-02) — a
   deliberately non-failing figure-bound cross-check against the thesis's undigitized headline
   number, not a Phase-26 defect.

A consequential absence: because this worktree's `Project.toml`/`Manifest*.toml` are the clean
committed state (no local drift), the historically-known **2 Aqua CairoMakie stale-deps /
persistent-tasks failures** documented in `local-project-toml-drift` are **absent** from this
baseline — not fixed, but never present in a clean checkout. Documented explicitly in
`26-BASELINE.md` so this absence is never later mistaken for a regression or a fix.

Also confirmed NOT broken this run (checked to rule out being the 3rd item, since they share the
identical `@test ... broken=` idiom): `test_ieee13.jl:229` (gap=0.00569 < 1e-2, genuine pass),
`test_acceptance.jl:95` (same), `test_thesis_repro.jl:216` (`sign_flip_holds = true`, genuine
pass). Named flakes from project memory (Clarabel `NUMERICAL_ERROR` on IEEE-13 ADMM,
`test_stochastic_welfare.jl:197`) did not fire this run — 0 errors, 0 fails total.

## Isolation Certificate

- `git rev-parse HEAD` after the run: `5939799852270a1e6cc894d2d8d676496b7cf9d6` — matches
  `PRE_PHASE_SHA` exactly.
- `git status --porcelain -- src/ test/ Project.toml Manifest.toml Manifest-v1.12.toml` after the
  run: empty.
- **Verdict: not contaminated.** No parallel wave-1 commit or suite side-effect touched this
  worktree's tracked tree during the ~31-minute run.

## Deviations from Plan

### Auto-fixed / Adapted (Rule 3 — adapting to the actual execution context)

**1. [Rule 3 — execution-context adaptation] Ran the suite in this plan's own worktree instead of nesting a second detached `git worktree add`**
- **Found during:** Task 1.
- **Issue:** The plan was written assuming the executor runs from the main checkout and must
  self-enforce isolation by creating a brand-new detached worktree sibling to it. This executor
  instead runs as a parallel wave-1 worktree agent (`worktree-agent-a82a99045b32f5f8b`), which the
  mandatory pre-execution branch check already resets/pins to `PRE_PHASE_SHA`. The sandbox also
  explicitly refuses `git worktree add ../...` invocations that reach outside the current
  worktree root.
- **Fix:** Ran the suite directly in this already-isolated worktree checkout. The isolation
  property the plan wanted (no parallel wave-1 fix commit can contaminate the measured run) is
  structurally guaranteed the same way: this worktree is a separate git working directory that
  sibling agents' commits never touch.
- **Verified:** Isolation certificate above (HEAD unchanged, tree clean) proves no contamination
  occurred, satisfying the plan's acceptance criteria in substance.
- **Files modified:** None (process-only deviation).
- **Commits:** N/A (documented here, not a code change).

No other deviations. Both tasks' acceptance criteria were met as specified.

## Self-Check: PASSED

- `FOUND: .planning/phases/26-network-device-model-correctness/26-baseline-suite.log` (140500 lines, committed in `d477b80`)
- `FOUND: .planning/phases/26-network-device-model-correctness/26-baseline-suite.done` (contains `0`, committed in `f3bfb48`)
- `FOUND: .planning/phases/26-network-device-model-correctness/26-BASELINE.md` (committed in `f3bfb48`)
- `FOUND: d477b80` in `git log --oneline --all`
- `FOUND: f3bfb48` in `git log --oneline --all`
