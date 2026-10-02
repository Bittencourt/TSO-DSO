---
phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh
plan: 01
subsystem: planning
tags: [julia, jump, benders, moi, laporte-louveaux, integer-planning]

# Dependency graph
requires:
  - phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder
    provides: "feas_oracle (FeasibilityOracle/build_feasibility_oracle/solve_feasibility_oracle!), _feas_cut_class, _accepted_lb_slack dispatcher, BendersMaster.lb_slack (WR-05)"
provides:
  - "WR-01 fix (confirmed, committed): _oracle_or_infeasible now requires feas_oracle confirmation before treating MOI.ALMOST_INFEASIBLE as a genuine infeasibility"
  - "WR-03 fix (NOT implemented — blocked, see Deviations): convergence-certificate widening via _accepted_lb_slack was found to break multiple pre-existing pinned goldens when implemented exactly as the plan/30-REVIEW.md directs"
affects: [31-04, 31-05, 31-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "MOI.Utilities.MockOptimizer + direct_model to deterministically pin termination_status for a fake oracle in a unit test, with no real solve"

key-files:
  created: []
  modified:
    - src/planning/benders.jl
    - test/test_planning_benders_integer.jl

key-decisions:
  - "Task 1 (WR-01) implemented and committed exactly as specified; verified via 6 regression files (157/157 pass, 0 fail, 0 error)."
  - "Task 2 (WR-03) NOT implemented. Direct measurement showed the plan-specified fix (Option B from 30-REVIEW.md, widening the convergence certificate by _accepted_lb_slack) breaks the project's flagship, pinned N=1/N=2 Benders goldens (test_planning_benders.jl, test_planning_goldens.jl, test_planning_nash.jl, test_planning_certification.jl, test_planning_noninteger.jl all use the SAME toy fixture's explicit α_op_lb=-5.0/α_x_lb=0.0 at the project's default tol=1e-6) — reverted to the Task-1-only state and stopped per Rule 4 (architectural ask) rather than silently moving pre-existing goldens or masking the issue by loosening tolerances project-wide."

patterns-established:
  - "Unit-testing MOI termination-status-dependent code paths via MOI.Utilities.MockOptimizer + direct_model, no real solver call needed"

requirements-completed: []  # BILEV-07 NOT completed this plan — WR-03 half of the carried-over Phase-30 fix is blocked; see Deviations.

# Metrics
duration: 100min
completed: 2026-10-02
---

# Phase 31 Plan 01: Carried-over Phase-30 integer-path warnings (WR-01 fixed, WR-03 blocked) Summary

**Confirmed `_oracle_or_infeasible`'s `MOI.ALMOST_INFEASIBLE` handling via the real slack-min `feas_oracle` (WR-01, committed); found and stopped short of committing a widened-convergence-certificate fix (WR-03) that empirically breaks the project's own flagship pinned Benders goldens at the standard `tol=1e-6`.**

## Performance

- **Duration:** ~100 min
- **Started:** 2026-10-01T22:02:14-03:00 (prior session handoff)
- **Completed:** 2026-10-02T01:39Z
- **Tasks:** 1 of 2 completed (Task 1 committed; Task 2 blocked, reverted)
- **Files modified:** 2 (`src/planning/benders.jl`, `test/test_planning_benders_integer.jl`)

## Accomplishments

- **Task 1 (WR-01) — DONE.** `_oracle_or_infeasible` no longer maps an unconfirmed `MOI.ALMOST_INFEASIBLE` straight to `+Inf`. It now requires confirmation via the same slack-min `feas_oracle` the outer Benders loop already uses: with no `feas_oracle` supplied, the status is treated as unconfirmed and the original throw is rethrown (fail loud); with a `feas_oracle` supplied, `solve_feasibility_oracle!(feas_oracle, z).v` is classified via `_feas_cut_class`, and only a `:disagree` verdict rethrows. `feas_oracle` is threaded through `corner_recourse` → `_corner_recourse_ternary`/`_corner_recourse_joint` → `ll_cut_recourse(::BendersMasterInteger, ...)`, and the ONE production call site inside `solve_stackelberg!` now passes the already-built `feas_oracle` (previously built but unused for this purpose). 4 new regression tests added using a `MOI.Utilities.MockOptimizer`-backed fake oracle to deterministically pin `termination_status` without a real solve.
- **Task 2 (WR-03) — BLOCKED, not committed.** See Deviations below for the full finding.

## Task Commits

1. **Task 1: WR-01 — confirm ALMOST_INFEASIBLE via feas_oracle** - `986aa4b` (fix)

**Plan metadata:** this commit (SUMMARY + STATE/ROADMAP update)

_Note: Task 2 has NO commit — its code change was written, measured to regress existing goldens, and reverted via `git checkout --` before any commit, per the destructive-git-prohibition's sanctioned single-file-revert path._

## Files Created/Modified

- `src/planning/benders.jl` - `CORNER_INFEASIBLE_STATUSES` added (documentation constant); `_oracle_or_infeasible` gains a `feas_oracle = nothing` keyword and confirms `MOI.ALMOST_INFEASIBLE` before returning `nothing`; `corner_recourse`/`_corner_recourse_ternary`/`_corner_recourse_joint`/`ll_cut_recourse` (both methods) thread `feas_oracle` through; the production `ll_cut_recourse` call site inside `solve_stackelberg!` passes `feas_oracle = feas_oracle`.
- `test/test_planning_benders_integer.jl` - 4 new regression tests (`FakeOracleWR01`/`FakeFeasOracleWR01` + `MOI.Utilities.MockOptimizer`) covering: unconfirmed `ALMOST_INFEASIBLE` rethrows; a `:separating`-class confirmation returns `nothing`; a `:disagree`-class confirmation rethrows; a plain `MOI.INFEASIBLE` is unaffected (non-regression).

## Decisions Made

- Implemented Task 1 exactly as specified — no deviations.
- Declined to implement Task 2 exactly as specified after direct measurement proved it breaks pre-existing pinned goldens; reverted rather than commit a breaking change or silently work around it by touching out-of-scope files/tolerances. See Deviations.

## Deviations from Plan

### Blocked work (not auto-fixed — Rule 4, architectural)

**1. [Rule 4 — architectural conflict] Task 2's directed WR-03 fix (convergence-certificate widening via `_accepted_lb_slack`) breaks multiple pre-existing pinned Benders goldens**

- **Found during:** Task 2, immediately after implementing the plan's `<action>` verbatim and running its own `<verify>` block against `test_planning_alpha_bounds_stackelberg.jl` plus a broader sweep.
- **What the plan specifies:** widen `solve_stackelberg!`'s `converged_at` closure (when `known_optimum === nothing`) from `(UBx - LB_k) / max(1, abs(UBx)) <= tol` to `(UBx - (LB_k - lb_slack_total)) / max(1, abs(UBx)) <= tol`, where `lb_slack_total = _accepted_lb_slack(master, :op) + _accepted_lb_slack(master, :x)` — Option B from `30-REVIEW.md`, quoted verbatim in the plan and in `31-RESEARCH.md`.
- **The plan's own premise (must_haves.truths #4):** "lb_slack is 0.0 on every pre-existing call site, so the widened formula is byte-identical there." **This premise is false for `BendersMaster`** (it is true only for `BendersMasterInteger`, which has no `lb_slack` field until plan 31-02 adds one). Phase 30's BILEV-05 already made `solve_stackelberg!`'s `_bounds_ctx` construction **unconditional** — every call that supplies an explicit (non-`:auto`) `α_op_lb`/`α_x_lb` through `solve_stackelberg!` validates that bound against a genuine relaxed-solve derivation and records a nonzero build-time acceptance slack (`master.lb_slack`, Phase 30 WR-05) **regardless of how far below the derived optimum the explicit bound actually is** — the recorded slack is a worst-case constant (`alpha_lb_margin(...) + |gap|`, floor `ALPHA_LB_REJECTION_TOL = 1e-6`), not a measurement of how much of the slack was actually used.
- **Measured impact:** on the project's own canonical toy fixture (`Phase6Fixtures.two_bus_feeder()` + `ToyElasticDevice(2,6.0,1.0,10.0)`, `master_kwargs=(;c_y=0.3,y_max=8.0,α_op_lb=-5.0,α_x_lb=0.0)`), `build_master`'s own recorded `lb_slack ≈ (op=1.0028508990723707e-6, x=1.0e-6)` — i.e. `lb_slack_total ≈ 2.0e-6`, which **exceeds** the project's own standard `tol=1e-6` default used throughout the planning-layer test suite. Implementing the widened formula exactly as specified causes `solve_stackelberg!` to exhaust `max_iter=100` without converging (raising its own loud `ErrorException`) on:
  - `test_planning_benders.jl`'s flagship "converges end-to-end ... matches the re-derived analytic optimum (z*=0.7)" golden (the project's N=1 reference case),
  - `test_planning_alpha_bounds_stackelberg.jl`'s pre-existing "a valid explicit bound converges with zero regression" and "a pre-built follower with no sound α_x_lb derivation (DistributorView) is accepted" tests,
  - and (by the same fixture/tol pattern, confirmed by grep, not individually re-run to avoid an unbounded verification cost) is very likely to equally affect `test_planning_goldens.jl` (PVAL-02 N1/N2 goldens), `test_planning_certification.jl`, `test_planning_nash.jl`, and `test_planning_noninteger.jl` — all of which use the identical `α_op_lb=-5.0, α_x_lb=0.0, tol=1e-6` pattern on the same or a closely related toy fixture.
- **Why this is NOT a simple auto-fixable bug (Rules 1-3):** every remediation path that stays sound requires either (a) touching `src/planning/master.jl` (Option A from `30-REVIEW.md`: clamp an accepted explicit bound down to the certified derivation minimum at build time, so `lb_slack` is genuinely `0.0` for every sound clamp and the runtime certificate needs no change at all) — `master.jl` is **not** in this plan's `files_modified` or Task 2's own `<files>` list; or (b) loosening `tol` across a broad, multi-file swath of the existing pinned-golden test suite to comfortably exceed `lb_slack_total` — itself a cross-file change far outside Task 2's declared scope, and arguably masks a real tightness rather than fixing it, violating the project's "every tolerance measured, not picked" discipline. Rule 3's package-install exclusion aside, this is the closest analogue: a blocking issue whose only sound fixes are out-of-scope architectural choices, not a 3-line patch.
- **Action taken:** reverted the Task 2 code change via `git checkout -- src/planning/benders.jl test/test_planning_alpha_bounds_stackelberg.jl` (returning both files to the Task-1-only committed state) rather than commit a breaking change, mask it with loosened tolerances, or silently touch `master.jl` outside the plan's declared scope. **Zero pre-existing goldens were moved** — confirmed by re-running the full regression set on the reverted state: `test_planning_benders.jl` + `test_planning_benders_integer.jl` + `test_planning_certification_integer.jl` + `test_planning_hardening.jl` + `test_planning_alpha_bounds_stackelberg.jl` (157/157 pass) and `test_planning_inexact_policy.jl` + `test_planning_benders_ieee13.jl` + `test_planning_nash.jl` (242 pass, 1 pre-existing documented-broken, 0 fail, 0 error).
- **Recommendation for follow-up (not actioned here):** revisit WR-03 as part of plan 31-02 (which already owns giving `BendersMasterInteger` its own `bounds_ctx`/`lb_slack` wiring and touches `master_integer.jl`) or a dedicated follow-up plan, implementing **Option A** (build-time clamp in `master.jl`, `slack_op`/`slack_x` → `0.0` for every sound clamp) instead of Option B, so the runtime certificate never needs widening in the common case; keep a defense-in-depth widened-certificate fallback (this plan's reverted `benders.jl` diff, preserved below) ONLY for any future case where a bound genuinely cannot be clamped. The reverted diff is fully reproducible: add `lb_slack_total = _accepted_lb_slack(master, :op) + _accepted_lb_slack(master, :x)` before `converged_at`'s definition and change its `known_optimum === nothing` branch to `((UBx - (LB_k - lb_slack_total)) / max(1, abs(UBx)) <= tol)`.

---

**Total deviations:** 1 blocked (Rule 4 — architectural conflict with the plan's own stated premise, discovered by direct measurement)
**Impact on plan:** Task 1 (WR-01) is complete, committed, and independently regression-tested. Task 2 (WR-03) is **not implemented** — BILEV-07's "Phase-30 open integer-path review warnings are FIXED here" claim is only half true after this plan: WR-01 is fixed; WR-03 remains open, carried forward with a concrete, measured finding and a recommended fix direction (Option A) for whichever plan picks it up next.

## Issues Encountered

- The quick-run emulator's `@testitem` filter/fixture-inclusion requirements meant several early verification runs errored on `UndefVarError: ... not defined` purely from omitting a required `@testmodule` fixture file (e.g. `fixtures_planning_ieee13_short.jl` for `IEEE13ShortHorizonFixtures`) from the file list — not a code regression. Resolved by including the correct fixture file list per test target.
- `rtk`'s `grep` proxy rewrites `grep -c`'s plain numeric output into a non-standard `"N matches in MF:"` format, breaking a `<verify>` block's `awk`-based numeric gate (`grep -c ... | awk '{if ($1<3) ...}'`). Worked around via `rtk proxy grep -c ...` for the one gate that needed raw `grep` semantics; the underlying wiring count (6) was independently confirmed correct either way.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Task 1 (WR-01) is production-wired and regression-tested; the integer corner search's `ALMOST_INFEASIBLE` classification is now honest for any future caller, including plan 31-04's N>1 integer Nash work.
- **Task 2 (WR-03) is NOT ready** — BILEV-07's full carried-over-warnings closure is blocked pending a design decision (Option A build-time clamp vs. an alternative) that is out of this plan's file scope. Plan 31-02 (parallel, already touching `master_integer.jl`/giving `BendersMasterInteger` its own `bounds_ctx`) is the natural place to revisit this, since it already owns the sibling design question for the integer master's own acceptance rule.
- Recommend the orchestrator/user decide between: (a) scope a follow-up plan to implement Option A in `master.jl` (preferred — keeps `lb_slack` genuinely sound, zero regression risk); (b) accept a broader, carefully-measured `tol` increase across the affected pinned-golden test files alongside Option B; or (c) defer WR-03 entirely and re-flag it as a standing known-limitation in STATE.md's Blockers/Concerns, same as the other carried-over Phase-30 items.

---
*Phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh*
*Completed: 2026-10-02*

## Self-Check: PASSED

- FOUND: .planning/phases/31-gne-nash-fixture-integer-n-1-planning-docs-refresh/31-01-SUMMARY.md
- FOUND: src/planning/benders.jl
- FOUND: test/test_planning_benders_integer.jl
- FOUND commit: 986aa4b
