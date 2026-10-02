---
phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh
plan: 07
subsystem: planning
tags: [julia, jump, benders, milp, epigraph-bounds, wr-03]

# Dependency graph
requires:
  - phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh
    provides: "31-01's WR-03 finding (Option B breaks flagship pinned goldens) and recommendation to implement Option A instead; 31-02's build_master_integer bounds_ctx/lb_slack machinery (ported verbatim from build_master) that this plan's clamp transformation is itself ported into"
provides:
  - "WR-03 fix (Option A, build-time clamp): build_master/build_master_integer now clamp any accepted-but-slack explicit epigraph bound DOWN to the certified :auto-equivalent minimum at build time, never installing the raw requested value"
  - "BendersMaster.lb_clamped / BendersMasterInteger.lb_clamped fields recording the clamp amount (0.0 unless clamping fired)"
  - "lb_slack provably always (; op=0.0, x=0.0) on BOTH master types — solve_stackelberg!'s convergence certificate and _assert_epigraph_floor (benders.jl) left completely untouched"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Build-time value clamp (min(requested, certified_minimum)) as a sound alternative to runtime-certificate widening when a validated derivation bound is already available at construction time"

key-files:
  created: []
  modified:
    - src/planning/master.jl
    - src/planning/master_integer.jl
    - test/test_planning_master.jl
    - test/test_planning_master_integer.jl
    - test/test_planning_alpha_bounds_stackelberg.jl

key-decisions:
  - "Implemented Option A (build-time clamp) exactly as specified by 31-01's own recommendation and this plan's interfaces block — never touched benders.jl's solve_stackelberg! convergence certificate or _assert_epigraph_floor, keeping Option B rejected per 31-01-SUMMARY.md's measured finding."
  - "L = α_op_lb_resolved + α_x_lb_resolved in build_master_integer is now computed from the CLAMPED resolved values (the clamp happens before L is pinned) — a strictly tighter, still-valid global lower bound for the Laporte-Louveaux cut, never a looser one."

requirements-completed: ["BILEV-07"]

# Metrics
duration: 45min
completed: 2026-10-02
---

# Phase 31 Plan 07: Build-Time Epigraph Bound Clamp (WR-03 Option A) Summary

**`build_master`/`build_master_integer` now clamp an accepted-but-slack explicit `α_op_lb`/`α_x_lb` down to the certified `:auto`-equivalent minimum at build time, recording the clamp on a new `lb_clamped` field, so `lb_slack` is provably always zero and `solve_stackelberg!`'s convergence certificate never needs widening.**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-10-02T02:00Z (approx, worktree reset to base commit `62d4456`)
- **Completed:** 2026-10-02T02:26Z
- **Tasks:** 2 of 2 completed
- **Files modified:** 5

## Accomplishments

- **Task 1 (continuous master).** `build_master`'s `α_op_lb`/`α_x_lb` resolution now computes `α_eff = min(requested, d.bound)` in the accepted-explicit-bound branch (both epigraphs), installs `α_eff` (never the raw requested value) on the JuMP variable's lower bound, logs an `@warn` (maxlog=1) when a clamp actually fires, and records `requested − α_eff` on a new `BendersMaster.lb_clamped` field. `slack_op`/`slack_x` are now unconditionally `0.0` in that branch too (previously `slack + |gap|`), so `BendersMaster.lb_slack` is `(; op=0.0, x=0.0)` for every call path — `:auto`, accepted-and-clamped, accepted-and-unclamped, and the `bounds_ctx === nothing`/`follower_kwargs === nothing` opt-out paths alike. The rejection ceiling (`α_op_lb > d.optimum + slack && throw(...)`) is byte-identical to before this plan.
- **Task 2 (integer master).** `build_master_integer` gets the IDENTICAL transformation, ported verbatim (same `α_eff`/`clamp_op`/`clamp_x` shape, `@warn` text substituting `build_master_integer`). `BendersMasterInteger` gains the matching `lb_clamped` field (appended at the END of the field list, after `visited` — `b`/`K`/`T`/`c_y`/`y_max`/`L`/`lb_slack`/`cuts`/`visited` order preserved). `L = α_op_lb_resolved + α_x_lb_resolved` is now computed from the clamped values.
- Three test files updated to prove the fix: `test_planning_master.jl`'s WR-03 headroom testitem now asserts the installed bound equals `d.bound` (not the raw requested value), that it never exceeds `d.optimum`, that `lb_clamped` records the positive clamp amount, that `lb_slack` is always zero, and adds a byte-identical unclamped sub-case (`-50.0` literal) proving `lb_clamped == (;op=0.0,x=0.0)`. `test_planning_alpha_bounds_stackelberg.jl`'s WR-05-iteration-2 testitem now asserts the clamp and changes the production-style `_assert_epigraph_floor` calls to use `lower_bound(m.α_op)` (the installed/clamped value) instead of the raw `α`, while KEEPING the one call that proves the finding is genuine (`_assert_epigraph_floor(cost_k, α, :op; gap=gk)`, raw unclamped `α`, still throws) unchanged. `test_planning_master_integer.jl`'s `_accepted_lb_slack` testitem is rewritten the same way for the integer master, plus the `plain` (no-`bounds_ctx`) regression sub-case now also asserts `lb_clamped == (;op=0.0,x=0.0)`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Option A clamp in build_master (continuous master) + update its two test files** - `7707071` (feat)
2. **Task 2: Port the identical Option A clamp into build_master_integer + update its test file** - `b12b284` (feat)

**Plan metadata:** this commit (SUMMARY)

## Files Created/Modified

- `src/planning/master.jl` — `BendersMaster` gains `lb_clamped` field (appended at the end, after `lb_slack`); `build_master`'s α_op_lb/α_x_lb resolution clamps an accepted-but-slack explicit bound to `d.bound`; `ALPHA_LB_REJECTION_TOL`'s runtime-widening paragraph rewritten to describe Option A superseding it; `build_master`'s own docstring and `BendersMaster`'s Fields list updated.
- `src/planning/master_integer.jl` — `BendersMasterInteger` gains `lb_clamped` field (appended at the very end, after `visited`); `build_master_integer`'s resolution block gets the identical verbatim-ported clamp transformation; docstrings mirrored.
- `test/test_planning_master.jl` — rewrote "build-time rejection has real headroom" testitem to assert the clamp (renamed to cite Option A/WR-03/Plan 31-07); kept the rejection-ceiling `ArgumentError` assertions unchanged.
- `test/test_planning_master_integer.jl` — rewrote the `_accepted_lb_slack` dispatch testitem to assert the clamp and zero slack (renamed).
- `test/test_planning_alpha_bounds_stackelberg.jl` — rewrote the WR-05 iteration-2 testitem to assert the clamp and route production-style `_assert_epigraph_floor` calls through the installed (clamped) bound (renamed).

## Decisions Made

See `key-decisions` in frontmatter: Option A implemented exactly as specified (31-01's own recommendation); `benders.jl`/`nash.jl` deliberately left untouched; `L` in the integer master now derives from the clamped values (strictly tighter, still valid).

## Deviations from Plan

None — plan executed exactly as written. Both tasks' `<action>` blocks were followed verbatim (the `<interfaces>` block gave the exact clamp transformation and docstring text to apply/port), and all `<behavior>`/`<acceptance_criteria>` items were implemented as rewritten test assertions.

## Issues Encountered

- The spawned worktree's HEAD was at an older commit (`3488bf5`, an ancestor of the required base `62d4456`) at agent start — the `<worktree_branch_check>`'s own `git reset --hard` branch fired as designed (working tree was clean, HEAD was a pure ancestor of the target, no divergent local work), bringing the worktree to the correct base before any edits.
- `rtk`'s git-command-complexity guard in this worktree session required splitting a few chained git inspection commands (`merge-base` + conditional `reset --hard`, `is-ancestor` checks) into separate plain `command git ...` invocations — a tooling quirk of the worktree-isolated shell wrapper, not a code issue (same pattern noted in 31-02-SUMMARY.md's own Issues Encountered).
- `test_planning_nash.jl`'s full regression run (used only as a sanity cross-check per Task 2's `<verify>` block) reports 165 pass / 1 broken / 166 total — the 1 broken item is the SAME pre-existing, already-documented broken test 31-01-SUMMARY.md's own regression sweep found ("242 pass, 1 pre-existing documented-broken, 0 fail, 0 error"), not a regression introduced by this plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- WR-03 is now fully closed on BOTH master types via Option A — `solve_stackelberg!`'s convergence certificate and `_assert_epigraph_floor` (both `benders.jl`) are provably untouched by this plan, confirmed by `grep` showing zero edits to `benders.jl`/`nash.jl` in either task's diff.
- `lb_slack` is provably always `(; op=0.0, x=0.0)` on both master types going forward — any future caller relying on `_accepted_lb_slack`'s dispatch sees a uniformly zero value, matching an `:auto` bound's own runtime behavior exactly.
- No blockers for downstream plans in this phase.

---
*Phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh*
*Completed: 2026-10-02*

## Self-Check: PASSED

- FOUND: .planning/phases/31-gne-nash-fixture-integer-n-1-planning-docs-refresh/31-07-SUMMARY.md
- FOUND: src/planning/master.jl
- FOUND: src/planning/master_integer.jl
- FOUND commit: 7707071
- FOUND commit: b12b284
