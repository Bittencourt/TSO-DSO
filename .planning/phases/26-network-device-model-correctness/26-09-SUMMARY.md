---
phase: 26-network-device-model-correctness
plan: 09
subsystem: optimization-models
tags: [jump, unregister, stochastic-welfare, gap-closure, golden-repin]

requires:
  - phase: 26-network-device-model-correctness
    provides: "Plan 26-05's ConvexBranchFlow FIX-03 receiving-end thermal limit (thesis 3.37), adding Prev/Qrev/smax_rev named JuMP containers"
provides:
  - "build_stochastic_welfare (src/models/stochastic_welfare.jl) works again for S>1 scenarios with ConvexBranchFlow — no JuMP name-collision"
  - "test_run_stochastic.jl's D-11 welfare_gap golden re-measured and re-pinned against the CURRENT merged code (Plans 26-01..09)"
affects: [26-network-device-model-correctness cluster A closure, run_stochastic, StochasticOosHarness]

tech-stack:
  added: []
  patterns: ["JuMP.unregister must name EVERY container a contribute! method registers, including @expression containers (Prev/Qrev), not just @constraint/@variable ones — the per-scenario unregister list is a closed enumeration that must be kept in lockstep with ConvexBranchFlow.contribute!'s own registrations"]

key-files:
  created: []
  modified:
    - src/models/stochastic_welfare.jl
    - test/test_run_stochastic.jl

key-decisions:
  - "Extended the per-scenario unregister tuple from 9 to 12 names (added :Prev, :Qrev, :smax_rev) rather than making Prev/Qrev anonymous — matches the plan's stated preference and keeps ConvexBranchFlow.jl untouched (this plan's files_modified list excludes it)."
  - "Re-pinned test_run_stochastic.jl:104's oos.welfare_gap from -0.02515629356082627 to -0.018591711034105174 with an inline old->new+cause comment, per SC-6 (measured live in this worktree, not copied from the triage's approximate figures)."

requirements-completed: [FIX-03]

duration: 25min
completed: 2026-09-29
---

# Phase 26 Plan 09: Stochastic-welfare Prev/Qrev/smax_rev unregister fix + D-11 golden re-pin Summary

**Fixed the JuMP name-collision that broke every multi-scenario `build_stochastic_welfare` call since Plan 26-05, and re-measured the one golden the fix moves.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-09-29T00:15:00Z (approx)
- **Completed:** 2026-09-29T00:41:51Z
- **Tasks:** 2/2 completed
- **Files modified:** 2

## Accomplishments
- `build_stochastic_welfare` with 2+ scenarios and `ConvexBranchFlow()` no longer throws `"object of name Prev is already attached to this model"` (or the Qrev/smax_rev equivalent).
- All 9 cluster-A testitems (10 records) from `26-POSTMERGE-TRIAGE.md` verified passing via direct-script reproduction: 6 in `test/test_stochastic_welfare.jl`, and all 5 items in `test/test_run_stochastic.jl` (including the previously-erroring `:36`/`:90`-equivalent items and the golden-only-failing `:104`).
- `test_run_stochastic.jl`'s D-11 `oos.welfare_gap` golden re-measured live in this worktree and re-pinned with an old->new+cause comment.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add :Prev, :Qrev, :smax_rev to stochastic_welfare.jl's per-scenario unregister list** - `2639efc` (fix)
2. **Task 2: Re-measure and re-pin test_run_stochastic.jl's D-11 welfare_gap golden** - `99610c5` (docs)

**Plan metadata:** (this commit)

## Files Created/Modified
- `src/models/stochastic_welfare.jl` - Per-scenario unregister tuple extended from `(:v, :v̂, :P, :Q, :l, :cone, :vdrop, :cpydrop, :smax)` to also include `:Prev, :Qrev, :smax_rev`; module and function docstrings' stale "nine named containers" count corrected to "twelve".
- `test/test_run_stochastic.jl` - D-11 testitem's pinned `oos.welfare_gap` literal updated from `-0.02515629356082627` to `-0.018591711034105174`, with an inline old->new+cause comment.

## Decisions Made
- Extended the unregister tuple (rather than making `Prev`/`Qrev` anonymous in `ConvexBranchFlow.jl`) — this plan's `files_modified` scope is `src/models/stochastic_welfare.jl` + `test/test_run_stochastic.jl` only, and the plan's own Task 1 instructions specify extending the tuple, not touching `ConvexBranchFlow.jl`.
- Re-measured the D-11 golden live (three fresh same-process `run_stochastic(s)` calls, bit-for-bit stable at `-0.018591711034105174`) rather than copying the triage's approximate `-0.018592`/`-0.019226` figures verbatim, per the plan's explicit instruction and SC-6's no-silent-re-pin policy. The measured value matches the triage's `fix` snapshot figure (`-0.018592`) to 5 significant figures, confirming the collision fix plus the already-landed device-correctness fixes (26-03..05) fully account for the move — no additional gap-closure plan effects were present at measurement time.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical / documentation accuracy] Corrected stale "nine" container-count docstrings**
- **Found during:** Task 1
- **Issue:** `stochastic_welfare.jl`'s module-level header comment and `build_stochastic_welfare`'s own docstring both stated `contribute!(::ConvexBranchFlow, ...)` registers "NINE named JuMP containers" and instructed unregistering "the nine formulation container names" — stale since Plan 26-05 added three more (Prev, Qrev, smax_rev), and left uncorrected would silently mis-document the very fix this plan makes, violating this project's CLAUDE.md hard requirement for rich, accurate per-decision documentation.
- **Fix:** Updated both occurrences to "TWELVE"/"twelve", added a parenthetical noting the three FIX-03 additions.
- **Files modified:** `src/models/stochastic_welfare.jl`
- **Verification:** Read back the full diff; no other stale count references remain (`grep -n "nine\|NINE" src/models/stochastic_welfare.jl` returns empty post-edit).
- **Committed in:** `2639efc` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 documentation-accuracy fix, Rule 2)
**Impact on plan:** Documentation-only correction alongside the code fix; no scope creep, no behavior change beyond what the plan specified.

## Issues Encountered
- **TestItemRunner-under-`--project=.` trap (known project memory):** the plan's own `<verify>` blocks and the test files' `@testmodule`/`@testitem` macros are TestItems constructs that don't resolve under plain `julia --project=.` (TestItems is a test-only dependency). Worked around by defining minimal stub `@testmodule`/`@testitem` macros at the top of throwaway driver scripts in the scratchpad directory — `@testmodule` expands to a real `module` block; `@testitem` expands to a fresh anonymous module (via `Expr(:toplevel, ...)`, required because a `module` expression must appear at Julia top level, not nested inside another block) that brings in `using Test` plus a `using Main: <SetupModule>` derived from the item's own `setup=[...]` kwarg. This reproduced all 8 previously-erroring cluster-A testitems (6 in `test_stochastic_welfare.jl`, 2 in `test_run_stochastic.jl`) plus the golden-only-failing 9th (`test_run_stochastic.jl`'s D-11 item), all passing after the fix. No project files were changed by this workaround; the driver scripts live only under the session scratchpad.
- **Macro hygiene pitfall while building the stub `@testitem` macro:** an early version of the driver script's macro left its returned `Expr(:toplevel, ...)` un-escaped, which triggered Julia's default macro-hygiene pass to rewrite the bare module-name `Symbol` into a `GlobalRef`, producing `TypeError: in module, expected Symbol, got a value of type GlobalRef`. Fixed by wrapping the returned expression in `esc(...)`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Cluster A of `26-POSTMERGE-TRIAGE.md` (9 testitems, 10 records) is fully closed: all items verified passing via direct-script reproduction.
- `build_stochastic_welfare`/`run_stochastic`/the OOS harness are restored to working order for any downstream gap-closure plan (26-10 through 26-20) that exercises multi-scenario stochastic builds.
- No blockers identified for subsequent phase-26 gap-closure plans running in parallel on disjoint files.

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-29*

## Self-Check: PASSED

- FOUND: src/models/stochastic_welfare.jl
- FOUND: test/test_run_stochastic.jl
- FOUND: .planning/phases/26-network-device-model-correctness/26-09-SUMMARY.md
- FOUND commit: 2639efc (Task 1)
- FOUND commit: 99610c5 (Task 2)
