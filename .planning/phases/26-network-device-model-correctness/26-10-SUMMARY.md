---
phase: 26-network-device-model-correctness
plan: 10
subsystem: pricing
tags: [dlmp, congestion, socp-exactness, tol_gap, gap-closure]

# Dependency graph
requires:
  - phase: 26-network-device-model-correctness (plan 05)
    provides: "ConvexBranchFlow's :smax_rev receiving-end apparent-power cone (thesis 3.37, FIX-03)"
  - phase: 26-network-device-model-correctness (plan 06)
    provides: "decompose_dlmp's volt_b re-certification + deferred-items.md's D-26-01 bisection record"
provides:
  - "decompose_dlmp's congestion component reads BOTH :smax and :smax_rev duals — correct under any back-feed regime where the receiving-end limit binds instead of the sending-end one"
  - "test_pricing_dlmp.jl's two near-lossless 2-bus fixtures (D-26-01) solve cleanly at a calibrated tol_gap without throwing inside assert_socp_exact!"
affects: [27-integer-planning-pricing]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Soft-guarded (haskey/get) dual read for an optional cone, mirroring the required-containers hard guard's style but degrading gracefully when :smax_rev is absent from a hand-built ctx"
    - "select_optimizer(SOCP(); tol_gap_abs=5e-10, tol_gap_rel=5e-10) per-fixture tol_gap override, mirroring the stochastic_welfare.jl precedent — never touching assert_socp_exact!'s own atol/rtol"

key-files:
  created: []
  modified:
    - src/pricing/dlmp.jl
    - test/test_pricing_dlmp.jl
    - .planning/phases/26-network-device-model-correctness/deferred-items.md

key-decisions:
  - "Congestion sign convention for :smax_rev: SAME sign as the sending-end :smax term (cong_b = -_smax_P(smax,...) - _smax_P(smax_rev,...)), empirically verified — no need to try the opposite sign, the first attempt dropped IEEE-13's back-feed-window residual to machine precision (3.55e-15)"
  - "tol_gap=5e-10 (the stochastic_welfare.jl precedent value) cleared the D-26-01 gate on the FIRST sweep point for both fixtures — the plan's fallback sweep ladder {3e-10, 1e-10, 3e-11} was executed anyway (for the record) but was not needed to pick a working value"
  - "D-26-01 resolved as a genuine Clarabel convergence-precision artifact, NOT a PVBattery/ConvexBranchFlow SOCP-exactness defect — objective value stable to 8+ significant digits across the whole tol_gap ladder from 5e-10 down to 1e-12"
  - "Corrected deferred-items.md's and test_pricing_dlmp.jl's stale 'uncongested' fixture label per 26-POSTMERGE-TRIAGE.md's 'Latent issues found': the smax=10 branch IS a :smax/:smax_rev-bearing limited branch, merely un-binding (slack) at this fixture's tiny flow magnitudes"

requirements-completed: [FIX-03, FIX-04]

# Metrics
duration: ~45min
completed: 2026-09-28
---

# Phase 26 Plan 10: DLMP Receiving-End Congestion + D-26-01 tol_gap Calibration Summary

**decompose_dlmp now attributes congestion from BOTH the sending-end (:smax, 3.36) and
receiving-end (:smax_rev, 3.37) apparent-power cones — closing the IEEE-13 back-feed residual
from 6.23 to machine precision (3.55e-15) — and the two D-26-01 near-lossless 2-bus DLMP
fixtures now solve cleanly at a calibrated `tol_gap=5e-10`, with the PF-04 gate itself
provably untouched.**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-09-28 (approx.)
- **Completed:** 2026-09-28
- **Tasks:** 2 completed
- **Files modified:** 3

## Accomplishments

- **Task 1 (cluster B):** Added a soft-guarded (`get(ctx.constraints, :smax_rev, nothing)`) read
  of the receiving-end apparent-power cone's dual into `decompose_dlmp`'s `cong_b` term,
  alongside the pre-existing sending-end `:smax` read. Same sign convention as the sending-end
  term (`cong_b[b,t] = -_smax_P(smax,...) - _smax_P(smax_rev,...)`), empirically verified on
  the FIRST attempt: IEEE-13's PV-back-feed window (t=9-16, bus 10, where `:smax_rev` binds and
  `:smax` is slack) dropped from a 6.23 hard-assertion residual to `3.55e-15` (machine
  precision). Cross-checked the high-PV over-voltage regime (residual `1.78e-15`, congestion
  correctly still all-zero — no thermal limit exists on that fixture) and the reactive-price
  testitem (all 7 assertions pass) to confirm no regression elsewhere.
- **Task 2 (cluster E / D-26-01):** Added
  `optimizer = select_optimizer(SOCP(); tol_gap_abs = 5e-10, tol_gap_rel = 5e-10)` to both
  `solve_welfare` calls in `test_pricing_dlmp.jl`'s `:22` ("extract_dlmp on a lossless 2-bus")
  and `:221` ("decompose_dlmp has ≈0 congestion/voltage...") testitems, mirroring the
  `stochastic_welfare.jl` precedent exactly. `5e-10` cleared the PF-04 gate on the FIRST sweep
  point for both fixtures (no need to fall back to the `{3e-10, 1e-10, 3e-11}` ladder the plan
  allowed for) — swept anyway for the record: objective value stable at
  `47.7991455...` across the full ladder (`5e-10` through `1e-12`, 8+ significant digits
  unchanged). `assert_socp_exact!`'s own `atol`/`rtol` in `src/models/exactness.jl` is
  confirmed UNCHANGED (`git diff src/models/exactness.jl` is empty).
- Resolved `deferred-items.md`'s D-26-01 entry with a "RESOLVED (Plan 26-10)" marker: measured
  tol_gap ladder table, confirmation this was a precision-floor artifact (not a genuine
  `PVBattery`/`ConvexBranchFlow` interaction), and a correction of the entry's own stale
  "uncongested" fixture label (the `smax=10` branch is genuinely LIMITED — `10 < SMAX_NO_LIMIT
  = 99.0` — merely un-binding at this fixture's tiny flow magnitudes, per
  `26-POSTMERGE-TRIAGE.md`'s "Latent issues found"). `test_pricing_dlmp.jl`'s own `:221`
  comment updated to match.
- Updated `src/pricing/dlmp.jl`'s file-header derivation comment and `decompose_dlmp`'s
  docstring to document the two-cone congestion split (thesis 3.36 + 3.37).

## Task Commits

1. **Task 1: Add the :smax_rev receiving-end dual to decompose_dlmp's congestion term** -
   `86e9944` (fix) — `src/pricing/dlmp.jl`.
2. **Task 2: Tighten Clarabel tol_gap on the two near-lossless test_pricing_dlmp.jl fixtures
   (D-26-01)** - `0cde17c` (test) — `test/test_pricing_dlmp.jl`,
   `.planning/phases/26-network-device-model-correctness/deferred-items.md`.

## Files Created/Modified

- `src/pricing/dlmp.jl` — `decompose_dlmp`'s `cong_b` loop now reads `:smax_rev` (soft-guarded)
  in addition to `:smax`; file header + docstring updated to document the 3.36+3.37 split.
- `test/test_pricing_dlmp.jl` — both near-lossless-fixture testitems (`:22`, `:221`) now pass an
  explicit tightened `tol_gap` optimizer override; `:221`'s comment corrected re: the fixture's
  actual (limited-but-slack) `smax` status.
- `.planning/phases/26-network-device-model-correctness/deferred-items.md` — D-26-01 marked
  RESOLVED with the measured tol_gap ladder and the fixture-label correction.

## Decisions Made

- **Congestion sign for `:smax_rev`:** same convention as `:smax` (both subtracted). Verified
  empirically on the first attempt — no need to try the opposite sign per the plan's own
  fallback instruction.
- **tol_gap value:** `5e-10` (the `stochastic_welfare.jl` precedent), not a more aggressive
  value — it cleared both fixtures on the first try with objective value stable to 8+
  significant digits; no evidence a looser or tighter value was needed.
- **D-26-01 verdict:** genuine Clarabel convergence-precision artifact (the true optimum is
  cone-tight; the default `tol_gap=1e-8` simply stops short of it on this near-lossless
  fixture), confirmed by the objective value's stability across the full tol_gap ladder — NOT
  the PVBattery/ConvexBranchFlow SOCP-exactness defect Plan 26-06 could not rule out.

## Deviations from Plan

### Auto-fixed Issues

None beyond what the plan itself specified — both tasks executed exactly as scoped. The one
discretionary choice (whether to sweep past `5e-10`) resolved in the plan's own preferred
direction (no further tightening needed).

### Out-of-Scope Discovery (logged, not auto-fixed)

None found within this plan's `src/pricing/dlmp.jl` / `test/test_pricing_dlmp.jl` scope.
Cross-checked (read-only) `test/test_dlmp.jl`, `test/test_admm_reactive.jl`,
`test/test_thesis_repro.jl` for other `decompose_dlmp`/`congestion` consumers that might be
affected by the `:smax_rev` congestion-term addition: `test_dlmp.jl`'s
`decompose_dlmp`-consuming testitem only checks the sum-to-price invariant (unaffected by
which cone congestion is attributed to); the other two files only reference `decompose_dlmp`
in comments, no live calls. No regression risk identified; not modified (out of this plan's
file scope).

## Cross-plan observations

None — no failures observed outside this plan's own files during verification.

## TDD Gate Compliance

Neither task carries `tdd="true"`; plan `type` is `execute`. Both `<verify>` blocks are inline
diagnostic/reproduction Julia scripts (per the project's TestItemRunner-trap memory), not a
separately-committed RED→GREEN pair — consistent with the plan's own execution model.

## Issues Encountered

None. Both tasks solved on the first attempt at the plan's own suggested parameters (sign
convention, `tol_gap=5e-10`).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `decompose_dlmp`'s congestion component is now correct under any back-feed regime, closing
  cluster B from `26-POSTMERGE-TRIAGE.md`.
- D-26-01 is fully resolved; `deferred-items.md` can be considered closed for this item pending
  the phase's own close-out review.
- No blockers for proceeding to the next plan in this wave.

---
*Phase: 26-network-device-model-correctness*
*Completed: 2026-09-28*

## Self-Check: PASSED

- FOUND: `src/pricing/dlmp.jl`
- FOUND: `test/test_pricing_dlmp.jl`
- FOUND: `.planning/phases/26-network-device-model-correctness/deferred-items.md`
- FOUND: `.planning/phases/26-network-device-model-correctness/26-10-SUMMARY.md`
- FOUND commit: `86e9944` (Task 1)
- FOUND commit: `0cde17c` (Task 2)
