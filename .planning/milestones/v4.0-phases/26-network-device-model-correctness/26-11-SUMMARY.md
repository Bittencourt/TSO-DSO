---
phase: 26-network-device-model-correctness
plan: 11
subsystem: experiments-mpc
tags: [jump, mpc, battery, soc-recursion, gap-closure]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness
    provides: "Plan 26-03's soc[1:(T+1)] full-horizon battery SOC recursion and mpc_window.jl's soc[H+1] terminal retarget (FIX-04)"
provides:
  - "run_mpc's soc_da terminal-target indexing agrees with build_mpc_window's Plan-26-03 soc[H+1] retarget"
  - "The mpc_step<=mpc_H-1 guard re-scoped to Thermostatic (Tin0-carrying) devices only, since PVBattery/FourQuadBESS's soc[1:(H+1)] recursion now covers the H-th control fully"
  - "test_mpc_terminal.jl's hand-rolled loop uses the same corrected soc_da[t+H] indexing, with a live re-measured dump/hoard-prevention margin"
affects: [mpc-rolling-horizon]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A device-population guard predicate must be re-derived per-device-type whenever a
       dependent device's temporal recursion range changes (here: WR-02's stateful-device
       guard narrowed from 'any soc0/Tin0-carrying device' to 'any Tin0-carrying device only'
       once FIX-04 closed PVBattery/FourQuadBESS's recursion over the full window)"

key-files:
  created:
    - .planning/phases/26-network-device-model-correctness/26-11-repro-mpc-terminal.jl
  modified:
    - src/experiments/mpc_loop.jl
    - test/test_mpc_terminal.jl

key-decisions:
  - "Narrowed the has_stateful/mpc_step<=mpc_H-1 guard predicate from `hasproperty(d, :soc0)
     || hasproperty(d, :Tin0)` to `hasproperty(d, :Tin0)` only, renaming the local variable
     to has_uncovered_state for clarity, rather than leaving the old name with new meaning"
  - "Dropped the min(..., T) clamp entirely on both call sites (run_mpc and
     test_mpc_terminal.jl) rather than defensively keeping it — a silent clamp is exactly the
     stale-index bug this plan fixes, and the outer loop's own header bound makes every
     visited index provably in-bounds"
  - "Re-measured test_mpc_terminal.jl's dev_disabled/dev_enabled margin live instead of
     copying 26-POSTMERGE-TRIAGE.md's own figure (SC-6): 4.36e-7/8.98e-11 (~4,851x) measured
     in this isolated worktree, versus the triage's 4.35e-7/2.69e-10 (~1620x) measured with a
     different set of concurrently-landing gap-closure plans present — both are valid,
     non-noise-floor readings; the numbers differ because they were taken against different
     sibling-plan states, not because either measurement is wrong"

requirements-completed: [FIX-04]

# Metrics
duration: ~20min
completed: 2026-09-28
---

# Phase 26 Plan 11: MPC Terminal-Condition soc_da Re-indexing (Cluster C Gap Closure) Summary

**Retargeted `run_mpc`'s terminal-condition `soc_da` indexing from the stale
`soc_da[bus][min(t+mpc_H-1, T)]` to `soc_da[bus][t+mpc_H]` over a `1:(T+1)`-built `soc_da`,
matching `build_mpc_window`'s own Plan-26-03 `soc[H+1]` retarget, and re-scoped the
`mpc_step<=mpc_H-1` guard to Thermostatic-only — restoring the MPC closed loop and its
terminal-condition regression to green.**

## Performance

- **Duration:** ~20 min
- **Tasks:** 2 completed
- **Files modified:** 2 (1 source, 1 test) + 1 repro script

## Accomplishments

- `src/experiments/mpc_loop.jl`'s `soc_da` Dict comprehension now spans `1:(s.T + 1)` (the
  day-ahead battery `soc` vector's actual length since Plan 26-03), and the terminal
  `set_parameter_value` call indexes `soc_da[entry.bus][t + s.mpc_H]` with no `min(..., s.T)`
  clamp — the outer resolve loop's own header bound (`t in 1:s.mpc_step:(s.T - s.mpc_H + 1)`)
  guarantees every visited index is in-bounds by construction.
- The `has_stateful`/`mpc_step <= mpc_H - 1` guard (WR-02, PM-08) is re-scoped from "any
  `:soc0`- or `:Tin0`-carrying device" to "any `:Tin0`-carrying (Thermostatic) device only" —
  renamed `has_uncovered_state` — since PVBattery/FourQuadBESS's `soc[1:(H+1)]` recursion
  (Plan 26-03) now closes over the FULL window including hour H, while Thermostatic's `Tin`
  recursion is unchanged (`1:(H-1)`, `src/devices/Thermostatic.jl`). Verified empirically: a
  battery-only synthetic population with `mpc_step == mpc_H` runs 3 resolves cleanly
  (`termination_status == OPTIMAL` every time, no guard throw), while a Thermostatic-carrying
  synthetic population with `mpc_step > mpc_H - 1` still trips the guard.
- `run_mpc`'s own docstring (`# Guards` section) updated to describe the re-scoped guard
  accurately, replacing the "with ANY stateful device present" language.
- `test/test_mpc_terminal.jl`'s hand-rolled receding-horizon loop carried the identical stale
  index (`soc_da_bus[min(t + H - 1, T)]` over a `1:T`-built `soc_da`); fixed the same way
  (`soc_da` over `1:(T+1)`, terminal target `soc_da_bus[t + H]`), and updated the derived
  `soc_da_final` reference from `soc_da_bus[T - H + 1 + H - 1]` (i.e. `soc_da_bus[T]`) to
  `soc_da_bus[(T - H + 1) + H]` (i.e. `soc_da_bus[T + 1]`) — the equivalent post-fix index.
- Re-measured the file's own `dev_disabled`/`dev_enabled` margin live rather than trusting the
  triage's own quoted figure (SC-6): `4.36e-7` / `8.98e-11`, a `~4,851x` ratio, comfortably
  above the test's `1000x` assertion floor. Both the file-header DEVIATION note and the
  in-file margin comment were updated with this live number.
- Added `.planning/phases/26-network-device-model-correctness/26-11-repro-mpc-terminal.jl`, a
  standalone `julia --project=.` script reproducing `test_mpc_terminal.jl`'s testitem body
  directly (Phase21Fixtures' `T`/`H`/`mpc_feeder`/`build_mpc_aggregators`/`temperature_profile`
  inlined verbatim), per the `gsd-plan-verify-testitemrunner-trap` memory — TestItemRunner/
  `@testmodule` do not resolve under `--project=.`.

## Task Commits

1. **Task 1: Retarget run_mpc's soc_da terminal indexing to soc[H+1] and re-scope the
   mpc_step guard** - `1427cd2` (fix)
2. **Task 2: Fix test_mpc_terminal.jl's hand-rolled soc_da indexing and update the
   measured-margin note** - `43b119d` (test)

## Files Created/Modified

- `src/experiments/mpc_loop.jl` - `soc_da` built over `1:(T+1)`, terminal target indexed at
  `[t+H]` with no clamp; `mpc_step` guard narrowed to Thermostatic-only; docstring updated
- `test/test_mpc_terminal.jl` - hand-rolled loop's `soc_da`/terminal-target indexing fixed
  identically; `soc_da_final` reference updated; header + in-file margin notes re-measured
- `.planning/phases/26-network-device-model-correctness/26-11-repro-mpc-terminal.jl` - new
  standalone direct-script reproduction of the testitem, with fixtures inlined

## Decisions Made

- See `key-decisions` in frontmatter: guard predicate narrowing + rename, no defensive clamp
  re-added, and honest live re-measurement of the terminal-condition margin rather than
  reusing the triage's own quoted number.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Doc accuracy] `run_mpc`'s own docstring `# Guards` section described the
guard's OLD ("any stateful device") scope**
- **Found during:** Task 1, while re-scoping the guard's inline comment and error message
- **Issue:** The public `run_mpc` docstring's "Guards" section still said "with ANY stateful
  device present (battery SOC / thermostatic temperature — every `:default` population),
  `s.mpc_step > s.mpc_H − 1` throws" — this would read as stale/incorrect once the guard's
  predicate no longer covers battery-like devices.
- **Fix:** Rewrote the paragraph to describe the re-scoped Thermostatic-only guard, matching
  the inline comment and error message.
- **Files modified:** `src/experiments/mpc_loop.jl` (docstring only, no functional change)
- **Verification:** Re-read the full docstring after the edit; no other WR-02 references
  remained stale.
- **Committed in:** `1427cd2` (Task 1 commit)

**Total deviations:** 1 auto-fixed (doc accuracy). No scope creep — only the plan's own two
`files_modified` entries plus the plan-specified repro script were touched.

## Issues Encountered

None beyond the documented doc-accuracy fix above.

## Cross-plan observations

None observed — this plan's changes are confined to `src/experiments/mpc_loop.jl` and
`test/test_mpc_terminal.jl`, disjoint from other Phase-26 gap-closure plans' files. The
`test_mpc_terminal.jl` margin measurement differing from the triage's own quoted figure
(4,851x here vs 1620x in the triage) is expected and explained above — it reflects a
different set of concurrently-landing fixes present in each measurement's worktree, not a
regression or a discrepancy requiring investigation.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Cluster C of `26-POSTMERGE-TRIAGE.md` is closed: `run_mpc`'s terminal-condition wiring now
  agrees with `build_mpc_window`'s own Plan-26-03 retarget at every visited resolve hour.
- `test_mpc_loop.jl:17` and `:323` (this plan's target regressions, reproduced as direct
  scripts per the `gsd-plan-verify-testitemrunner-trap` memory) both pass, including the
  `s_free_lunch` (Thermostatic-carrying, `mpc_step == mpc_H`) case still throwing
  `ArgumentError` — confirming the re-scoped guard is not silently disabled for the
  population it still protects.
- No blockers for other Phase-26 gap-closure plans (disjoint files).

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-28*

## Self-Check: PASSED

Both claimed files (`src/experiments/mpc_loop.jl`, `test/test_mpc_terminal.jl`) and the new
repro script exist on disk. Both task commit hashes (`1427cd2`, `43b119d`) verified present in
the worktree's git history via `git log --oneline`. `test_mpc_loop.jl:17` and `:323`,
`test_mpc_terminal.jl:33`, and the Task 1 `run_mpc` verify script were all re-run directly
(`julia --project=.`) and passed, including the battery-only-guard and
Thermostatic-carrying-guard empirical checks.
