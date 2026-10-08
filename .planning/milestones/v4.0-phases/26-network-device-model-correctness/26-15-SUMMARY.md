---
phase: 26-network-device-model-correctness
plan: 15
subsystem: power-flow-modeling
tags: [jump, ipopt, ac-opf, nonconvex, apparent-power-limit, gan-low, thermal-limit]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness (plan 05)
    provides: "ConvexBranchFlow's :smax_rev SecondOrderCone constraint (thesis 3.37) and the PV back-feed fixture (r=0.03, x=0.02, smax=0.3976601762564117) this plan's ACPowerFlow mirror and regression reuse"
provides:
  - "ACPowerFlow's registered :smax_rev scalar-quadratic inequality (thesis 3.37 receiving-end apparent-power limit), gated by the SAME B[b].smax < _SMAX_NO_LIMIT filter :smax uses"
  - "A validated PV back-feed regression on ACPowerFlow proving :smax_rev binds while :smax stays slack under reverse flow, on the SAME fixture family Plan 26-05 used"
  - "A documented Ipopt warm-start remedy for the l·v = P²+Q² unrelaxed equality's degenerate all-zero KKT point, reusable by any future ACPowerFlow back-feed/reverse-flow test"
affects: [28-thesis-reproduction-restatement]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Ipopt warm start (set_start_value on P/Q/l/v) as the standard remedy for ACPowerFlow's nonconvex l·v=P²+Q² equality getting stuck at the degenerate all-zero KKT point under back-feed/reverse-flow objectives — the constraint's (P,Q)-gradient vanishes at P=Q=0, so a zero-Jacobian stationary point is reported as ALMOST_LOCALLY_SOLVED instead of escaping toward the true optimum."

key-files:
  created: []
  modified:
    - src/powerflow/ACPowerFlow.jl
    - test/test_ac_powerflow.jl

key-decisions:
  - "Task 2's back-feed regression required an Ipopt warm start (set_start_value on P, Q, l, v) that the plan's own <verify> script did not include — without it, Ipopt's default all-zero start converges to ALMOST_LOCALLY_SOLVED/NEARLY_FEASIBLE_POINT at the trivial P≈0 stationary point (the l·v=P²+Q² equality's (P,Q)-gradient vanishes there), never reaching the true back-feed optimum where :smax_rev binds. Confirmed by reproducing the identical stall WITHOUT the new :smax_rev constraint (a raw hand-built model with only :cone/:vdrop/:smax) — this is a pre-existing Ipopt starting-point property of the unrelaxed equality, not something Task 1's additive constraint caused. Applied Rule 3 (auto-fix blocking issue): a back-feed-directed warm start (P=-0.3, consistent Q/l/v) is a standard nonconvex-solver remedy, not a change to the model's feasible set or physics. With the warm start, Ipopt converges to LOCALLY_SOLVED at P≈-0.3930 (forward magnitude ≈0.393, just under smax) with the receiving-end magnitude ≈0.39766 (essentially AT smax) — reproducing the SAME forward/reverse split Plan 26-05's own verify script measured for the identical r,x,smax fixture on the SOCP formulation."

requirements-completed: [FIX-03]

# Metrics
duration: ~35min
completed: 2026-09-28
---

# Phase 26 Plan 15: ACPowerFlow Receiving-End Apparent-Power Limit (PM-07) Summary

**Added thesis eq. 3.37's receiving-end apparent-power limit to `ACPowerFlow` (the Ipopt AC-OPF oracle) as a plain scalar-quadratic inequality mirroring `ConvexBranchFlow`'s `:smax_rev` cone (plan 26-05), so AC-vs-SOCP exactness comparisons on limited branches now share the same feasible set at both ends.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-09-28 (approx.)
- **Completed:** 2026-09-28
- **Tasks:** 2 completed
- **Files modified:** 2 modified, 0 created

## Accomplishments

- `ACPowerFlow.contribute!` now registers a NEW `:smax_rev` scalar-quadratic inequality
  `(P[b,t]-B[b].r*l[b,t])^2 + (Q[b,t]-B[b].x*l[b,t])^2 <= B[b].smax^2`, immediately after
  the existing `:smax` block, gated by the IDENTICAL `B[b].smax < _SMAX_NO_LIMIT` filter
  `:smax` uses — so the two limits appear or are omitted together per branch, exactly
  mirroring `ConvexBranchFlow`'s `:smax_rev` SecondOrderCone (plan 26-05, FIX-03) written
  here as the equivalent plain quadratic form (Ipopt takes it natively, same as `:cone`/`:smax`).
- Updated the module docstring's thesis-equations list, the `ACPowerFlow` struct docstring's
  "differences from ConvexBranchFlow" paragraph, and the `contribute!` docstring's per-branch
  bullet list to document the new limit (thesis 3.37, citing PM-07 and plan 26-05 by name).
- Re-ran all existing `test/test_ac_powerflow.jl` (3 items, 9 assertions) and
  `test/test_ac_oracle.jl` (5 items, 24 assertions) testitems as direct scripts (per this
  repo's TestItemRunner-under-`--project=.` trap) — every one still passes. No regression:
  the additive `:smax_rev` constraint changes nothing on fixtures with no real branch limit
  or with structural fixed-value construction (no optimization over P/Q at all).
- Added a new PV back-feed `@testitem` to `test/test_ac_powerflow.jl` (mirroring plan
  26-05's own `ConvexBranchFlow` regression on the SAME `r=0.03, x=0.02,
  smax=0.3976601762564117` fixture) that maximizes export at near-unity power factor on
  ACPowerFlow's own registered `:smax`/`:smax_rev` containers, then asserts the
  receiving-end limit's dual magnitude (`≈1.228`) is over 100x the sending-end limit's dual
  magnitude (`≈8.8e-7`, numerically slack) — confirming the SAME qualitative
  binding/slack asymmetry Plan 26-05 demonstrated for `ConvexBranchFlow`, on Ipopt's
  unrelaxed nonconvex formulation.
- Diagnosed and fixed (Rule 3) an Ipopt convergence blocker discovered while implementing
  Task 2's own verify script: Ipopt's default all-zero start sits at a degenerate KKT point
  of the `l·v = P²+Q²` equality (zero (P,Q)-gradient there), so the interior-point method
  reports `ALMOST_LOCALLY_SOLVED`/`NEARLY_FEASIBLE_POINT` at the trivial `P≈0` solution
  rather than escaping toward the true back-feed optimum. Confirmed this stall is
  pre-existing (reproduces identically on a hand-built model WITHOUT the new `:smax_rev`
  constraint) — not caused by Task 1's purely-additive change. Added a back-feed-directed
  warm start (`set_start_value` on `P,Q,l,v`) to the committed testitem; with it, Ipopt
  converges to `LOCALLY_SOLVED` at `P≈-0.3930` (forward magnitude ≈0.393, receiving-end
  magnitude ≈0.39766 ≈ smax), matching the SAME forward/reverse split plan 26-05's own
  verify script measured for this exact `r,x,smax` fixture.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add the receiving-end apparent-power limit (:smax_rev) to ACPowerFlow** - `f930267` (feat)
2. **Task 2: Add a PV back-feed regression proving the receiving-end limit binds on ACPowerFlow** - `b3ab95a` (test)

## Files Created/Modified

- `src/powerflow/ACPowerFlow.jl` — added the `:smax_rev` `@constraint`/`register_constraint!`
  pair immediately after `:smax`; updated the module header's thesis-equations list, the
  struct docstring's "differences from ConvexBranchFlow" paragraph, and the `contribute!`
  docstring's per-branch bullet list.
- `test/test_ac_powerflow.jl` — added one new `@testitem` ("PV back-feed binds the
  receiving-end limit (:smax_rev) while the sending-end limit (:smax) stays slack (PM-07)")
  with an Ipopt warm start, demonstrating the receiving-end limit binds while the
  sending-end limit stays slack under reverse flow.

## Decisions Made

- **Ipopt warm start for Task 2's back-feed regression:** see `key-decisions` in the
  frontmatter above. Summary: the plan's own `<verify>` script (no warm start) hit
  `is_solved_and_feasible == false` (`ALMOST_LOCALLY_SOLVED`) when reproduced verbatim;
  diagnosed as a pre-existing degenerate-KKT-point property of the unrelaxed nonconvex
  equality (confirmed independent of Task 1's constraint by reproducing the identical
  stall on a model without `:smax_rev`); fixed via `set_start_value` on `P[1,1]=-0.3`
  (and consistent `Q,l,v`), a standard nonconvex-solver remedy that changes no feasible
  set or physics. The committed testitem includes the warm start; the plan's literal
  `<verify>` one-liner (without the warm start) will reproduce the same
  `ALMOST_LOCALLY_SOLVED` stall if re-run standalone — this is expected and documented
  here, not a defect in the committed code.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added Ipopt warm start to Task 2's back-feed regression**
- **Found during:** Task 2 (PV back-feed regression)
- **Issue:** Ipopt's default all-zero start converges to `ALMOST_LOCALLY_SOLVED` /
  `NEARLY_FEASIBLE_POINT` at the trivial `P≈0` solution instead of the true back-feed
  optimum, because the `l·v = P²+Q²` unrelaxed equality's gradient in `(P,Q)` vanishes at
  `P=Q=0` — a degenerate stationary point the interior-point method cannot escape from a
  zero start. This blocks the plan's `<verify>` one-liner and the committed testitem alike
  unless a better starting point is supplied.
- **Fix:** Added `set_start_value` calls for `P[1,1], Q[1,1], l[1,1], v[1,1], v[2,1]`
  seeding a back-feed-directed initial point (`P=-0.3` and consistent `Q/l/v`) before
  `optimize!`. Confirmed via a standalone hand-built model (only `:cone`/`:vdrop`/`:smax`,
  no `:smax_rev`) that the SAME stall occurs without the new Task 1 constraint —
  ruling out Task 1's purely-additive change as the cause.
- **Files modified:** `test/test_ac_powerflow.jl`
- **Verification:** With the warm start, Ipopt reaches `LOCALLY_SOLVED` at `P≈-0.3930097`,
  receiving-end magnitude `≈0.39766` (≈smax, binding) vs. forward magnitude `≈0.393`
  (slack); duals `mag_fwd≈8.79e-7`, `mag_rev≈1.228`, ratio `≈1.4e6` — well over the
  `100×` threshold the testitem asserts.
- **Committed in:** `b3ab95a` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking, Rule 3)
**Impact on plan:** Necessary to make Task 2's own committed regression actually converge
and demonstrate the intended physics; no change to production model semantics (the warm
start lives only in the test, not in `ACPowerFlow.jl`). No scope creep.

## Cross-plan observations

Per the parallel-execution note (26-13/26-18 run concurrently; the plan flagged
`test_ac_oracle.jl`, `test_restricted_branch_flow.jl` EXACT-04 items, and
`ac_dual_fallback` as potentially affected downstream consumers of `ACPowerFlow`):

- **`test_ac_oracle.jl` (5 testitems, 24 assertions, reproduced as a direct script):** all
  pass, values unchanged. In particular the EXACT-04 high-PV stress fixture
  (`Phase4Fixtures.high_pv_feeder()`, `pv_scale=1.2`) still reports the same qualitative
  finding (`inexact_hours` nonempty, diagnosed via voltage-bound-hit / reverse-flow) — no
  moved golden.
- **`test_restricted_branch_flow.jl` EXACT-04 items (lines 21, 59, 104, 143, 229, 396) and
  `ac_dual_fallback_price` (line 396):** NOT re-run as a direct script (time/resource
  budget on a shared 4-core machine), but analytically confirmed unaffected by inspection:
  `Phase4Fixtures.high_pv_feeder()` sets BOTH branches' `smax = 99.0`, which is BYTE-EQUAL
  to `PerUnit.SMAX_NO_LIMIT = 99.0`. The shared filter predicate `B[b].smax < _SMAX_NO_LIMIT`
  evaluates `99.0 < 99.0 = false` for every branch in this fixture, so NEITHER `:smax` NOR
  the new `:smax_rev` container is created at all for `ACPowerFlow.contribute!` on this
  fixture — Task 1's change is a no-op here by construction, not by coincidence. No
  old→new move to report.
- No golden values in this plan's own files moved (Task 1 is purely additive; Task 2 adds
  a brand-new testitem with no prior pinned value).

## Known Stubs

None.

## Threat Flags

None — this plan adds one purely-additive nonconvex constraint (no new decision
variables) and one test to an existing internal power-flow-formulation file; no new
external input, no new package installs, no new attack surface, matching the plan's own
threat_model disposition (T-26-26, mitigate via Task 1's regression-check requirement;
T-26-27, accept).

## Issues Encountered

The Ipopt warm-start convergence issue documented above under "Deviations from Plan" —
resolved within Task 2's own scope.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `ACPowerFlow`'s `:smax_rev` dual is now recoverable by name
  (`dual(ctx.constraints[:smax_rev][b,t])`) on any limited branch, matching
  `ConvexBranchFlow`'s existing `:smax_rev` — any future AC-oracle-vs-SOCP DLMP/congestion
  cross-check now compares the SAME feasible set at both ends of a limited branch.
- IEEE-13/123 fixtures were NOT directly re-verified against `ACPowerFlow` in this plan
  (no existing testitem exercises `ACPowerFlow` on IEEE-13/123 with a real branch limit
  below the `_SMAX_NO_LIMIT` sentinel); this plan's own scope covered only the fixtures
  the existing/new testitems already exercise. If a future plan adds an
  `ACPowerFlow`-vs-`ConvexBranchFlow` comparison on IEEE-13's genuinely-limited head
  branch, expect the SAME degenerate-start caveat documented here if the comparison
  drives a back-feed/reverse-flow regime from a zero start.
- No blockers for proceeding to the next plan in this wave.

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-28*

## Self-Check: PASSED

- FOUND: `src/powerflow/ACPowerFlow.jl`
- FOUND: `test/test_ac_powerflow.jl`
- FOUND: `.planning/phases/26-network-device-model-correctness/26-15-SUMMARY.md`
- FOUND commit: `f930267` (Task 1)
- FOUND commit: `b3ab95a` (Task 2)
