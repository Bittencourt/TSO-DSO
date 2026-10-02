---
phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh
plan: 02
subsystem: planning
tags: [jump, benders, milp, laporte-louveaux, bilevel, highs]

# Dependency graph
requires:
  - phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder
    provides: "build_master's opt-in bounds_ctx/:auto/lb_slack machinery (BILEV-05), ALPHA_LB_* constants, _accepted_lb_slack generic dispatcher"
provides:
  - "build_master_integer with the SAME opt-in bounds_ctx/:auto/lb_slack validation machinery as build_master, byte-identical when bounds_ctx is omitted"
  - "BendersMasterInteger.lb_slack field + type-specific _accepted_lb_slack(::BendersMasterInteger, ...) method"
  - "add_ll_cut! enforcing its own Q_nu >= L precondition with a named ErrorException, plus corrected Hamming-distance-k docstring math"
affects: ["31-04 (run_nash! integer wiring can now pass bounds_ctx/:auto to build_master_integer)", "31-01 (benders.jl's _accepted_lb_slack dispatch picks up this plan's new method automatically)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Verbatim cross-file porting of a validated bound-resolution block (guard -> three-way dispatch -> slack bookkeeping) between build_master and build_master_integer, keeping both byte-identical on the opt-out path"
    - "Precondition violations on well-typed/finite inputs raise a named ErrorException (not ArgumentError), reserving ArgumentError for malformed-argument shape/finiteness checks"

key-files:
  created: []
  modified:
    - src/planning/master_integer.jl
    - test/test_planning_master_integer.jl

key-decisions:
  - "Ported build_master's bounds_ctx/:auto/lb_slack resolution block into build_master_integer verbatim (same guard order, same three-way follower_kwargs dispatch, same WR-03/WR-05 slack bookkeeping) rather than re-deriving a MILP-specific variant, per the plan's own interface spec and to keep the two builders' validation semantics provably identical."
  - "add_ll_cut!'s new Q_nu >= L guard raises ErrorException, not ArgumentError, distinguishing a precondition violation on an otherwise well-typed/finite cut from the existing ArgumentError guards (length/finiteness) that check argument SHAPE, not VALUE semantics."
  - "_accepted_lb_slack(::BendersMasterInteger, ...) is an ADDITIVE new method on benders.jl's existing generic function, never touching benders.jl itself -- relies on Julia's dispatch to prefer the specific method automatically, avoiding any merge conflict with plan 31-01's concurrent benders.jl edit."

requirements-completed: ["BILEV-07"]

# Metrics
duration: 22min
completed: 2026-10-01
---

# Phase 31 Plan 02: Integer Master Epigraph Bound Validation + Laporte-Louveaux Cut Guard Summary

**`build_master_integer` gains `build_master`'s full `bounds_ctx`/`:auto`/`lb_slack` validation machinery verbatim, and `add_ll_cut!` now enforces its own `Q_nu >= L` precondition instead of silently appending an invalid cut.**

## Performance

- **Duration:** 22 min
- **Started:** 2026-10-01T22:02:14-03:00
- **Completed:** 2026-10-01T22:23:54-03:00
- **Tasks:** 2 completed
- **Files modified:** 2

## Accomplishments
- `build_master_integer` now accepts `α_op_lb`/`α_x_lb` as `Union{Symbol,Real}` (`:auto` default), with `bounds_ctx` opt-in validation ported verbatim from `build_master` (master.jl) — every pre-existing call site (explicit `Real`, no `bounds_ctx`) stays byte-identical.
- `BendersMasterInteger` gained a populated `lb_slack::NamedTuple{(:op,:x),Tuple{Float64,Float64}}` field and a new `_accepted_lb_slack(::BendersMasterInteger, label)` method, automatically picked up by `benders.jl`'s pre-existing generic `_accepted_lb_slack` dispatcher.
- `add_ll_cut!` gained an `atol::Real = 1e-6` keyword and now throws a named `ErrorException` (never silently appends an invalid cut) when its own documented `Q_nu >= L` precondition is violated by more than `atol * max(1, |L|)`.
- Corrected `add_ll_cut!`'s docstring: the Hamming-distance-`k` reduction was `D <= -1` / `θ >= L - 2k(Q_nu - L)` (both wrong); now correctly states `D = 1-k` / `θ >= L - (k-1)(Q_nu - L)`.

## Task Commits

Each task was committed atomically:

1. **Task 1: build_master_integer gains bounds_ctx/lb_slack (ports build_master's pattern verbatim)** - `925559e` (feat)
2. **Task 2: add_ll_cut! enforces its own Q_nu >= L precondition (WR-02) + docstring fix** - `11ffec4` (fix)

_Note: both tasks were `tdd="true"` — tests were written and run alongside each code change within the same commit (new/existing test items verified pre-commit, per the plan's `<behavior>`/`<verify>` blocks); no separate RED/GREEN commit split was used since both tasks ported/hardened existing validated machinery rather than introducing net-new untested behavior from a blank slate._

## Files Created/Modified
- `src/planning/master_integer.jl` — `build_master_integer` signature/body gains `bounds_ctx`/`rejection_tol` keywords and the full guard→three-way-dispatch→slack-bookkeeping resolution block (verbatim port from `master.jl`'s `build_master`); `BendersMasterInteger` struct gains `lb_slack` field; new `_accepted_lb_slack(::BendersMasterInteger, ...)` method; `add_ll_cut!` gains `atol` keyword, the `Q_nu >= L` guard, and corrected docstring math.
- `test/test_planning_master_integer.jl` — 6 new `@testitem`s covering Task 1's 6 behavior points (`:auto` requires `bounds_ctx`, `:auto` resolution matches direct `derive_alpha_op_lb`/`derive_alpha_x_lb` calls, build-time rejection of an over-high explicit bound, honest skip for `follower_kwargs = nothing`, `_accepted_lb_slack` dispatch to the type-specific method vs. the generic `0.0` fallback, and an IN-03 unknown-Symbol guard) and 1 new `@testitem` covering Task 2's 3 behavior points (the fix throws and leaves `master.cuts` unmutated, the boundary `Q_nu == L` does not throw, and a custom `atol` widens acceptance).

## Decisions Made
- See `key-decisions` in frontmatter: verbatim porting of the bound-resolution block, `ErrorException` vs `ArgumentError` for the new precondition guard, and additive-method dispatch for `_accepted_lb_slack` to avoid any conflict with the concurrently-edited `benders.jl` (plan 31-01).

## Deviations from Plan

None — plan executed exactly as written. Both tasks' `<action>` blocks were followed verbatim (the interfaces block gave the exact resolution logic and guard text to port/insert), and all `<behavior>`/`<acceptance_criteria>` items were implemented as new test items.

## Issues Encountered

None. The rtk git-command-complexity guard in this worktree session required splitting a few chained git inspection commands (`merge-base` + conditional `reset --hard`) into separate plain invocations at the start of the session — not a code issue, just a tooling quirk of the worktree-isolated shell wrapper.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `build_master_integer` and `build_master` now share identical `bounds_ctx`/`:auto`/`lb_slack` semantics, so plan 31-04's `run_nash!` integer wiring can pass `bounds_ctx`/`:auto` to either builder interchangeably.
- `add_ll_cut!`'s `Q_nu >= L` guard is a correctness backstop for plan 31-04/31-05's integer Benders loop wiring — any future bug in the caller's `Q_nu` computation will now fail loudly instead of silently corrupting the master's cut set.
- Verified compatible with `docs/literate/integer_investment.jl` (exit 0, full end-to-end run, no errors) and with plan 31-01's concurrent `benders.jl` edit (the new `_accepted_lb_slack(::BendersMasterInteger, ...)` method is picked up automatically by Julia's dispatch once both plans merge — no shared-file edit was needed).
- No blockers for downstream plans in this phase.

---
*Phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh*
*Completed: 2026-10-01*

## Self-Check: PASSED

- FOUND: src/planning/master_integer.jl
- FOUND: test/test_planning_master_integer.jl
- FOUND commit: 925559e
- FOUND commit: 11ffec4
