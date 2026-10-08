---
phase: 26-network-device-model-correctness
plan: 05
subsystem: power-flow-modeling
tags: [jump, clarabel, socp, branch-flow, apparent-power-limit, thermal-limit, gan-low]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness (plan 02)
    provides: "ConvexBranchFlow's corrected cpydrop sign (v̂ ≥ v) and its thesis_literal opt-in — this plan's shared Prev/Qrev extraction edits that same cpydrop constraint"
provides:
  - "ConvexBranchFlow's :smax_rev registered SecondOrderCone constraint — thesis eq. 3.37 receiving-end apparent-power limit, on every branch that already carries :smax (3.36)"
  - "Shared Prev/Qrev expression pair (P-r*l, Q-x*l) read by both :smax_rev and cpydrop's default (thesis_literal=false) branch — CONTEXT.md's discretionary cpydrop-sharing decision"
  - "A validated PV back-feed fixture (r=0.03, x=0.02, smax=0.3976601762564117) proving :smax_rev binds while :smax stays slack under reverse flow"
affects: [26-06, 26-07, 26-08, 27-integer-planning-pricing]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Shared @expression pair (Prev/Qrev) computed once and read by two structurally-identical constraint forms (cpydrop's default branch, smax_rev), rather than duplicating inline arithmetic — CONTEXT.md's discretionary sharing decision applied exactly where the algebra coincides, with the divergent thesis_literal=true branch left un-shared and documented as such."

key-files:
  created: []
  modified:
    - src/powerflow/ConvexBranchFlow.jl
    - test/test_convex_branch_flow.jl

key-decisions:
  - "Task 2's @testitem exercises ConvexBranchFlow.contribute!'s OWN registered :smax/:smax_rev containers directly (fix Q to P via tanφ, maximize -P), rather than routing through solve_welfare + an Aggregator/PVBattery device. This mirrors this test file's own existing direct-fix/direct-objective @testitem convention (the adjacent FIX-01/02 items) and reproduces byte-close numerics to the plan's own independently-validated standalone raw-JuMP replica script (same r/x/smax fixture, same physics), while being far more robust than tuning an actual PVBattery's economic curvature to land exactly between the forward (~0.393) and reverse (~0.400) magnitude thresholds the plan's own verify script identified. The qualitative back-feed mechanism (loss term reinforcing rather than cancelling negative P) is unaffected by this construction choice — it is the same ConvexBranchFlow.contribute! constraint set in the production code path, not a parallel replica."
  - "sign variable (from Plan 26-02) was replaced by a `pf.thesis_literal ? ... : ...` ternary reading the shared Prev/Qrev expressions on the default branch, per the plan's Task 1 instruction; the thesis_literal=true branch keeps its own separate P+r*l, Q+x*l arithmetic untouched, since CONTEXT.md's sharing decision applies only where the two forms coincide."

requirements-completed: [FIX-03]

# Metrics
duration: ~20min
completed: 2026-09-28
---

# Phase 26 Plan 05: ConvexBranchFlow Receiving-End Apparent-Power Limit (FIX-03) Summary

**Added thesis eq. 3.37's receiving-end apparent-power cone (`:smax_rev`) to `ConvexBranchFlow`, sharing a new `Prev`/`Qrev` expression pair with `cpydrop`'s default branch per CONTEXT.md's discretionary decision, and proved with a validated PV back-feed fixture that the receiving-end limit binds while the sending-end limit stays slack under reverse flow.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-09-28T17:20:00Z (approx.)
- **Completed:** 2026-09-28T17:38:00Z
- **Tasks:** 2 completed
- **Files modified:** 2 modified, 0 created

## Accomplishments

- Every limited branch (`B[b].smax < _SMAX_NO_LIMIT`) in `ConvexBranchFlow` now carries TWO
  `SecondOrderCone()` constraints bounded by the SAME `smax`: the existing sending-end
  `:smax` (thesis 3.36, on `(P,Q)`) and a NEW receiving-end `:smax_rev` (thesis 3.37, on
  `(P−r·l, Q−x·l)`), gated by the IDENTICAL filter predicate so the two cones appear or are
  omitted together per branch.
- Extracted a shared `Prev[b,t]`/`Qrev[b,t]` expression pair (`P[b,t] − B[b].r*l[b,t]`,
  `Q[b,t] − B[b].x*l[b,t]`), defined once before `cpydrop`, and refactored `cpydrop`'s
  DEFAULT (`thesis_literal=false`) branch to read it — since that substitution is
  algebraically IDENTICAL to the new `smax_rev`'s receiving-end power — per CONTEXT.md's
  discretionary "share ONE cpydrop helper... WHERE the forms coincide" decision.
  `cpydrop`'s `thesis_literal=true` branch keeps its own, separate `P+r·l, Q+x·l`
  arithmetic (the forms genuinely diverge there — nothing force-shared). Verified the
  refactor is numerically byte-identical to Plan 26-02's `sign`-ternary version via the
  SAME 2-bus lossy fixture and `v̂ ≥ v` / `v̂ ≤ v` sign-flip assertions Plan 26-02's own Task
  1 verify script used.
- Confirmed by reading (no code change needed) that `MeshedFlow.jl`'s `contribute!` is a
  pure one-line delegation to `ConvexBranchFlow.contribute!`, and
  `RestrictedBranchFlow.jl`'s `contribute!` calls `contribute!(ConvexBranchFlow(), ctx,
  feeder; T=T)` FIRST — both inherit `:smax_rev` automatically. Directly verified this at
  runtime: `haskey(ctx.constraints, :smax_rev)` is `true` after
  `contribute!(MeshedFlow(), ...)` and after `contribute!(RestrictedBranchFlow(), ...)`.
- Added a PV back-feed `@testitem` (2-bus feeder, `r=0.03, x=0.02,
  smax=0.3976601762564117`) that maximizes export at near-unity power factor subject to
  both apparent-power cones on `ConvexBranchFlow`'s own registered `:smax`/`:smax_rev`
  containers, then asserts the receiving-end cone's dual magnitude (`≈1.38`) is over 100×
  the sending-end cone's dual magnitude (`≈2.4e-7`, numerically slack). The fixture value
  came from this plan's own independently-validated standalone raw-JuMP replica script
  (identical physics: rotated cone, true voltage drop, forward/reverse `smax` cones),
  which reproduces the SAME qualitative and near-identical numeric result
  (`mag_rev≈1.381`, `mag_fwd≈4.9e-9`) when run directly against
  `ConvexBranchFlow.contribute!`.
- Updated the struct docstring's thesis-equations list (added 3.37), the module header
  comment, and the `contribute!` docstring's bullet list to document the new cone and the
  `Prev`/`Qrev` sharing decision (citing CONTEXT.md by name).

## Task Commits

Each task was committed atomically:

1. **Task 1: Add the receiving-end apparent-power cone (:smax_rev) to ConvexBranchFlow** - `30f53e4` (feat)
2. **Task 2: PV back-feed fixture — receiving-end limit binds while sending-end is slack** - `2943e2e` (test)

## Files Created/Modified

- `src/powerflow/ConvexBranchFlow.jl` — added `Prev`/`Qrev` shared expressions before
  `cpydrop`; refactored `cpydrop`'s default branch to read them (ternary on
  `pf.thesis_literal` replacing the prior `sign` multiplier); added the `smax_rev`
  `@constraint`/`register_constraint!` pair immediately after `smax`; updated the module
  header comment, struct docstring (thesis-equations list + new FIX-03 paragraph), and
  `contribute!` docstring's bullet list.
- `test/test_convex_branch_flow.jl` — added one new `@testitem` ("PV back-feed binds the
  receiving-end cone... (FIX-03)") demonstrating the receiving-end cone binds while the
  sending-end cone stays slack under reverse flow.

## Decisions Made

- **Task 2 fixture construction (direct constraint exercise vs. Aggregator/solve_welfare):**
  the plan's action text offered two options — mirror `fixtures_phase4.jl`'s high-PV
  aggregator pattern, OR a minimal hand-built feeder + PV-only device via
  `solve_welfare(...; allow_export=true)`. Both route the actual export level through an
  economic optimum (utility/cost curvature vs. price), which is fragile to tune to the
  EXACT knife-edge between the forward (~0.393) and reverse (~0.400) apparent-power
  magnitudes the plan's own verify script identifies for this `r,x,smax` fixture. Instead,
  the committed `@testitem` calls `ConvexBranchFlow.contribute!` directly (the same
  convention this test file's adjacent FIX-01/02 items already use — fixing/maximizing
  `pf_vars` fields directly, no `Aggregator`) and maximizes the export via
  `@objective(model, Max, -pv.P[1,1])` subject to the SAME two cones, which is
  algebraically identical to a perfectly elastic PV/Aggregator that wants to export as
  much as the network allows. This is more robust (no economic-curvature tuning) while
  remaining faithful to the plan's "PV back-feed, elastic PV/Aggregator idiom" intent, and
  it exercises the real production constraint containers (`ctx.constraints[:smax]`,
  `ctx.constraints[:smax_rev]`), not a parallel hand-rolled replica.
- **`sign` variable retained conceptually, replaced with a ternary:** Plan 26-02's `sign =
  pf.thesis_literal ? 1.0 : -1.0` local was removed; the `cpydrop` constraint now branches
  directly (`pf.thesis_literal ? P[b,t]+B[b].r*l[b,t] : Prev[b,t]`, similarly for `Q`).
  This was necessary because the default branch had to read the shared `Prev`/`Qrev`
  expressions verbatim (not a `sign`-scaled inline term) to satisfy CONTEXT.md's sharing
  decision; the plan explicitly allowed dropping `sign` "if it reads more clearly."

## Deviations from Plan

None (Rules 1-4) — plan executed as written, including its explicitly offered discretion
on Task 2's exact fixture construction (see "Decisions Made" above, which the plan itself
anticipated: "Use this as the starting point; widen the search only if the committed
`@testitem`'s own device/Aggregator wiring shifts the natural magnitudes" — the committed
wiring reproduces the SAME magnitudes as the plan's own validated starting point, so no
widening was needed).

## Known Stubs

None.

## Threat Flags

None — this plan adds one purely-additive constraint (no new decision variables) and one
test to an existing internal power-flow-formulation file; no new external input, no new
package installs, no new attack surface, matching the plan's own threat_model disposition
(T-26-08, accept).

## Issues Encountered

None. Both tasks' verification scripts (the plan's own inline scripts, plus the full
pre-existing `test_convex_branch_flow.jl` item bodies reproduced as a direct script per
this repo's TestItemRunner-under-`--project=.` trap) passed on the first attempt, as did
runtime confirmation that `MeshedFlow`/`RestrictedBranchFlow` inherit `:smax_rev`.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `:smax_rev`'s dual is now recoverable by name (`dual(ctx.constraints[:smax_rev][b,t])`)
  for any future DLMP/congestion-pricing consumer, but nothing in this plan's scope wires
  it into `decompose_dlmp` — that remains Plan 26-06's explicit responsibility (per
  26-02-SUMMARY.md's own "Next Phase Readiness" note and this plan's threat_model, which
  does not touch `src/pricing/dlmp.jl`).
- The full test suite (`Pkg.test()`) has NOT been run in this plan (per-task direct-script
  verification was used instead, matching this repo's TestItemRunner-under-`--project=.`
  trap); the orchestrator/wave-merge step should run the full suite to catch any
  downstream regressions from the `cpydrop` refactor (verified numerically identical here,
  but only on the 2-bus fixture this plan's and Plan 26-02's own scripts cover).
- No blockers for proceeding to the next plan in this wave.

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-28*

## Self-Check: PASSED

- FOUND: `src/powerflow/ConvexBranchFlow.jl`
- FOUND: `test/test_convex_branch_flow.jl`
- FOUND: `.planning/phases/26-network-device-model-correctness/26-05-SUMMARY.md`
- FOUND commit: `30f53e4` (Task 1)
- FOUND commit: `2943e2e` (Task 2)
