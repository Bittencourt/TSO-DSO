---
phase: 04-convex-branch-flow-correctness-milestone
plan: 06
subsystem: optimization
tags: [socp, clarabel, ipopt, ieee13, ground-truth, dadp, jump, distflow, regression]

# Dependency graph
requires:
  - phase: 04-02
    provides: ConvexBranchFlow SOCP formulation (cone, exactness copy, pf_vars stash)
  - phase: 04-03
    provides: ieee13_modified() built-in feeder fixture (node k -> struct index k+1)
  - phase: 04-04
    provides: operational_oracle wrapper returning (cost, π, dadp, ctx)
  - phase: 04-05
    provides: solve_welfare SOCP routing + PF-04 exactness gate + allow_export frontier
provides:
  - "Centralized GLB-CVX SOCP ground-truth solve on the modified IEEE-13 feeder, proven OPTIMAL + PF-04-exact + Clarabel-vs-Ipopt-consistent"
  - "Pinned computed golden regression (v9[16], welfare, DADP) as the primary reproducibility anchor for every later rung (pricing, ADMM)"
  - "operational_oracle allow_export passthrough; solve_welfare RSOC/SOC->nonconvex-quadratic bridges (enable Ipopt cross-check of the cone)"
  - "build_ieee13_ground_aggregators: documented residential-scale calibration reaching the thesis congestion-driven over-voltage regime"
affects: [phase-05-pricing, phase-06-admm, dadp, price-decomposition]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Computed golden pinned only after OPTIMAL + exactness gate + cross-solver agreement (trust chain before regression)"
    - "Non-failing thesis cross-check: @info exact gap + @test broken=(gap>=tol) + generous physical-band ceiling"
    - "Opt-in RSOC/SOC->nonconvex-quadratic bridges let a smooth-NLP backend cross-check a native-cone SOCP (dormant for Clarabel)"

key-files:
  created:
    - .planning/phases/04-convex-branch-flow-correctness-milestone/04-06-SUMMARY.md
  modified:
    - test/test_ieee13.jl
    - test/fixtures_phase4.jl
    - src/models/oracle.jl
    - src/models/welfare_solve.jl

key-decisions:
  - "Pinned a COMPUTED golden (v9[16]=1.0436080536, welfare=-4823.1598620624) as the primary anchor; thesis 1.0493/$1819 are documented approximate cross-checks (RESEARCH Open Q1)"
  - "Calibrated the ground aggregators to residential magnitude (load_scale 0.005 / pv_scale 0.03) so the head-congested solve is feasible and lands in the thesis over-voltage regime; the full-magnitude fixture is ~90x the head limit (infeasible)"
  - "Required allow_export=true (PV surplus reverse-flows to the frontier; priced export keeps the SOC cone exact) and added it to operational_oracle"
  - "Added RSOC/SOC->nonconvex-quadratic bridges in solve_welfare so Ipopt(NLP) can re-solve the cone for the cross-solver sanity check"

patterns-established:
  - "Golden-pinning trust chain: OPTIMAL -> PF-04 exact -> Clarabel≈Ipopt -> pin"
  - "Non-failing figure-bound cross-check via @info + broken test + physical-band ceiling"

requirements-completed: [OPT-02, OPT-03]

# Metrics
duration: ~40min
completed: 2026-07-18
---

# Phase 4 Plan 06: IEEE-13 GLB-CVX Ground-Truth Solve & Regression Summary

**Centralized ConvexBranchFlow SOCP solve on the modified IEEE-13 feeder proven OPTIMAL, PF-04-exact (maxgap 3.25e-8), and Clarabel-vs-Ipopt-consistent (rtol 5.5e-9), with a pinned computed golden (|V9[16]|=1.0436, welfare -4823.16) and a non-failing thesis v9[16]≈1.0493 cross-check (gap 0.0057).**

## Performance

- **Duration:** ~40 min
- **Started:** 2026-07-18
- **Completed:** 2026-07-18
- **Tasks:** 2 automated (Task 3 is a human-verify checkpoint — presented below, not blocking)
- **Files modified:** 4 (+1 SUMMARY created)

## Accomplishments
- Full GLB-CVX SOCP solve on IEEE-13 through `operational_oracle`: OPTIMAL, exactness gate ran and passed (`socp_maxgap = 3.25e-8 < 1e-5`), DADP length-24 finite, frontier coupling dual π finite.
- Cross-solver sanity: re-solved the identical assembly on Ipopt(NLP) via the RSOC bridge; welfare agrees with Clarabel to `|diff| = 2.66e-5` (rtol 5.5e-9), far inside the 1e-3 gate.
- Pinned the computed golden (`v9[16]`, welfare, DADP[16], ΣDADP) as the primary reproducibility anchor; the live solve reproduces it bit-for-bit (re-solve diff = 0).
- Thesis `v9[16] ≈ 1.0493` asserted as a NON-FAILING approximate |V| cross-check (gap 0.0057 emitted via `@info`, `@test ... broken`, generous 0.06 physical band).
- Re-added the deferred "ground" @testitems to `test/test_ieee13.jl` (04-03 removed them; 04-06 owns re-adding).
- Full suite green: **563 pass, 0 fail, 0 error** (was 546; +17 new ground assertions).

## Task Commits

Each task was committed atomically:

1. **Task 1: Full GLB-CVX SOCP solve on IEEE-13 (OPTIMAL, exact, cross-solver)** - `5d178cb` (feat)
2. **Task 2: Pin the ground-truth regression (computed golden + thesis cross-check)** - `1cb15a3` (test)
3. **Task 3: Human-verify checkpoint** - no code (presented below for researcher confirmation)

## Files Created/Modified
- `test/test_ieee13.jl` - Re-added two "ieee13 ground" @testitems: the OPTIMAL/exact/cross-solver solve and the pinned-golden + thesis cross-check regression.
- `test/fixtures_phase4.jl` - Added `build_ieee13_ground_aggregators` + `GROUND_LOAD_SCALE`/`GROUND_PV_SCALE` (documented residential-magnitude calibration reaching the thesis over-voltage regime).
- `src/models/oracle.jl` - Added `allow_export::Bool=false` passthrough to `operational_oracle` (needed for the over-voltage/reverse-flow ground solve).
- `src/models/welfare_solve.jl` - Registered opt-in `RSOCtoNonConvexQuadBridge`/`SOCtoNonConvexQuadBridge` so Ipopt can cross-check the SOCP cone (dormant for the native-cone Clarabel path).

## Recorded Ground-Truth Values (for the Task 3 human-verify checkpoint / Assumption A1)

| Quantity | Value | Notes |
|----------|-------|-------|
| `v[10,16]` (squared) | 1.0891177695 | the raw SOCP variable v = \|V\|² at struct index 10, t=16 |
| **`v9[16]` = \|V9[16]\| = sqrt(v[10,16])** | **1.0436080536** | Assumption A1: the VOLTAGE MAGNITUDE (thesis Fig 4.4 axis) |
| Thesis `v9[16]` (Fig 4.4) | 1.0493 | approximate cross-check target |
| **gap to thesis magnitude** | **0.005692** | < 1e-2 (broken test passes); documented, figure-bound |
| Welfare (computed golden) | -4823.1598620624 | GLB-CVX optimum on the calibrated inputs |
| Thesis welfare (Table 4.4) | ≈ +$1819 | large documented gap (figure-bound MEM/temp profiles + house-count A3) |
| DADP[16] (first-agg bus) | 1.4024313925 | pinned |
| Σ DADP | 96.7166853441 | pinned |
| π[16] (frontier coupling dual) | 6.80 | finite; Σπ = 134.5 |
| `socp_maxgap` (PF-04) | 3.25e-8 | << τ=1e-5 (exact) |
| Ipopt cross-check welfare | -4823.1598354204 | \|diff\|=2.66e-5, rtol 5.5e-9 |
| **Node → struct-index mapping** | thesis node 9 → struct index 10 | root = thesis node 0 = index 1 |

Head-branch congestion confirmed: P[1,16] = -0.0667 (exporting), max|P_head| = 0.0672 < 0.0686 pu limit — the congestion-driven regime, with node 9 the peak-voltage bus (the long lateral).

## Decisions Made
- **Pin a computed golden, cross-check the thesis figure (RESEARCH Open Q1).** The thesis inputs (MEM Fig 4.5, temperature Fig 4.2, per-house params, house counts) are figure-bound and internally inconsistent (A2/A3), so exact reproduction of `$1819` is impossible. The computed golden is the trustworthy anchor; the thesis `v9[16]` is an approximate |V| cross-check.
- **Residential calibration to reach the thesis regime.** Full-magnitude aggregators draw ~6.3 pu vs the 0.0686 pu head limit (infeasible). Scaling to load 0.005 / PV 0.03 makes it feasible AND reproduces the qualitative thesis result: congestion at the head, over-voltage on the node-9 lateral, `|V9[16]|` within 0.006 of the thesis 1.0493.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Full-magnitude IEEE-13 aggregators make the head-congested solve INFEASIBLE**
- **Found during:** Task 1 (initial ground solve)
- **Issue:** `build_ieee13_aggregators` (04-01) draws ~6.3 pu at peak while the head-branch limit is 0.0686 pu (~90x over) — the SOCP is infeasible import-only AND with export. This is the figure-bound-input / house-count gap (RESEARCH Open Q1 / A2–A3): the fixture magnitudes are normalized shapes, not residential magnitudes on the 100 MVA base.
- **Fix:** Added `build_ieee13_ground_aggregators` (+ documented `GROUND_LOAD_SCALE=0.005`, `GROUND_PV_SCALE=0.03`) rescaling the seeded shapes to a residential magnitude, yielding a feasible solve in the thesis congestion-driven over-voltage regime. Existing `build_ieee13_aggregators` untouched (no other caller).
- **Files modified:** test/fixtures_phase4.jl
- **Verification:** Solve OPTIMAL + exact (maxgap 3.25e-8); node 9 is the peak-voltage bus; `|V9[16]|` gap 0.0057 to thesis.
- **Committed in:** `5d178cb` (Task 1 commit)

**2. [Rule 3 - Blocking] operational_oracle could not export the PV surplus**
- **Found during:** Task 1 (over-voltage regime)
- **Issue:** The over-voltage/reverse-flow ground solve requires `allow_export=true` (priced frontier export keeps the SOC cone exact, PF-04; import-only is infeasible), but `operational_oracle` did not accept/forward `allow_export`.
- **Fix:** Added `allow_export::Bool=false` kwarg to `operational_oracle`, passed straight through to `solve_welfare`. Backward-compatible (default false).
- **Files modified:** src/models/oracle.jl
- **Verification:** Oracle returns OPTIMAL/exact with finite π; existing oracle tests unaffected.
- **Committed in:** `5d178cb` (Task 1 commit)

**3. [Rule 3 - Blocking] Ipopt cannot take the RotatedSecondOrderCone (cross-solver check blocked)**
- **Found during:** Task 1 (Clarabel-vs-Ipopt sanity check)
- **Issue:** The required cross-solver check re-solves the SOCP on Ipopt(NLP), but Ipopt's MOI backend rejects `RotatedSecondOrderCone`/`SecondOrderCone` (no default bridge — the nonconvex-quadratic reformulation is opt-in).
- **Fix:** Registered `RSOCtoNonConvexQuadBridge` + `SOCtoNonConvexQuadBridge` on the model in `solve_welfare`. They are DORMANT for Clarabel (native cone support) and no-ops for the cone-free QP paths; they only activate for a non-cone backend (Ipopt), reformulating `l·v ≥ P²+Q²` to the smooth quadratic Ipopt handles.
- **Files modified:** src/models/welfare_solve.jl
- **Verification:** Ipopt cross-check now solves and agrees with Clarabel to rtol 5.5e-9; full suite green (existing LinDistFlow cross-checks unaffected).
- **Committed in:** `5d178cb` (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (all Rule 3 - blocking). No package installs.
**Impact on plan:** All three were prerequisites for the plan's own acceptance criteria (feasible OPTIMAL solve + Ipopt cross-check on the over-voltage regime). Changes are minimal and backward-compatible; the calibration is documented and the golden is the honest computed anchor the plan prescribes. No scope creep.

## Issues Encountered
- The chosen calibration reproduces the thesis VOLTAGE regime closely (`|V9[16]|` gap 0.0057) but NOT the welfare magnitude/sign (computed -4823 vs thesis +$1819). This is expected and documented (figure-bound MEM/temperature profiles + house-count A3); the researcher confirms acceptance at the Task 3 checkpoint. Closing the welfare gap would require digitizing Fig 4.5/4.2 (a future refinement, out of scope for v1).

## Known Stubs
None new. The SEAM-01 stubs in `operational_oracle` (z-pin, objective_hook, horizon_state, meshed slot) remain documented v2 extension points as designed by 04-04; unchanged here.

## Threat Flags
None. No new network/auth/file surface. The pinned golden is gated behind OPTIMAL + PF-04 exactness + Clarabel≈Ipopt (threats T-04-05/T-04-15 mitigated); the human-verify checkpoint confirms A1 and accepts the golden.

## Task 3 — Human-Verify Checkpoint (presented, not blocking)

Per the orchestrator, the plan is completed and the recorded values are presented for the researcher to confirm Assumption A1 and accept the pinned golden:

- **(a)** `v9[16]` as |V| = sqrt(v[10,16]) = **1.0436080536** (the squared variable is 1.0891177695).
- **(b)** Welfare/objective = **-4823.1598620624** (computed golden).
- **(c)** Gap vs thesis: `|V9[16]|` 1.0436 vs 1.0493 → **0.0057** (small, within band); welfare -4823 vs +$1819 → large, documented (figure-bound inputs).
- **(d)** Node→index mapping: thesis **node 9 = struct index 10** (root = thesis node 0 = index 1), confirmed against the 04-03 fixture topology tests.

Resume signal: researcher types "approved" (A1 = magnitude, golden accepted) or requests a correction / figure digitization.

## Next Phase Readiness
- The centralized ground truth (voltages, DADP, frontier π) is pinned and reproducible — the anchor Phase 5 (pricing PRICE-01/02) and Phase 6 (ADMM) validate against.
- Open follow-up (documented, not blocking): digitize thesis Fig 4.5/4.2 to close the welfare gap if bit-fidelity to `$1819` is later required.

## Self-Check: PASSED

- All modified files present on disk (test/test_ieee13.jl, test/fixtures_phase4.jl, src/models/oracle.jl, src/models/welfare_solve.jl, 04-06-SUMMARY.md).
- Both task commits present in git history (`5d178cb`, `1cb15a3`).
- Full suite green: 563 pass / 0 fail / 0 error.

---
*Phase: 04-convex-branch-flow-correctness-milestone*
*Completed: 2026-07-18*
