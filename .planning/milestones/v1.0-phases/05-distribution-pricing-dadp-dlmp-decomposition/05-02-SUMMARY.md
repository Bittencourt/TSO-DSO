---
phase: 05-distribution-pricing-dadp-dlmp-decomposition
plan: 02
subsystem: pricing
tags: [dlmp, dadp, duality, kkt, socp, branch-flow, jump]

# Dependency graph
requires:
  - phase: 05-01
    provides: "registered SOCP branch-flow duals (:cone 3.39, :vdrop 3.33, :cpydrop 3.43, :smax 3.36) + ctx.meta[:pf_vars]"
  - phase: 04
    provides: "solve_welfare / ConvexBranchFlow SOCP solve, :balance_p dual, PF-04 exactness gate (ctx.meta[:socp_maxgap])"
provides:
  - "extract_dlmp(ctx): per-node/hour DADP = dual.(:balance_p), sign-pinned positive, PF-04-gated"
  - "decompose_dlmp(ctx): energy/loss/congestion/voltage four-way split with a hard sum-to-nodal-price assertion"
affects: [05-03 fit baseline, 05-04 economic-direction checks, 05-05 welfare accounting, phase-8 planning-layer prices]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "KKT dual attribution: DLMP branch increment λ_j−λ_i = −(cone_dual[3] + 2r(β+γ) + smax_dual[2]), telescoped along the radial root→j tree path"
    - "Independent (strategy B) component reconstruction + hard relative-tolerance sum assertion as the non-tautological correctness net"
    - "Price-refusal gate: refuse to price an :l-bearing SOCP ctx lacking the PF-04 exactness certificate"

key-files:
  created:
    - "test/test_pricing_dlmp.jl"
  modified:
    - "src/pricing/dlmp.jl"

key-decisions:
  - "Voltage component sourced from the vdrop/cpydrop equation duals (β,γ), which propagate the v/v̂ bound pressure through the voltage-drop recursion — NOT the v/v̂ bound duals directly (that would double-count and break the sum). The sum-to-price assertion certifies completeness (RESEARCH Assumption A1)."
  - "Loss reconstructed independently from the rotated-SOC cone dual P-slot (strategy B), never as the residual — so a dropped congestion/voltage term surfaces as an O(price) residual instead of hiding."
  - "extract_dlmp/decompose_dlmp accept an optional `bus`/`T` keyword: bus===nothing returns (N,T) matrices (the plan API), a given bus returns per-bus length-T vectors (the 05-01 module-API harness contract). One method serves both."

patterns-established:
  - "Empirically-certified KKT decomposition: derive the dual identity, validate it sums to machine precision on the 2-bus / IEEE-13 / high-PV solves, then encode it behind a hard assertion."

requirements-completed: [PRICE-01, PRICE-02]

# Metrics
duration: 35min
completed: 2026-07-18
---

# Phase 5 Plan 02: DADP/DLMP Extraction & Four-Way Decomposition Summary

**Trustworthy per-node/hour distribution prices: the DADP read as the dual of the nodal active balance (PF-04-gated, sign-pinned) plus a KKT-derived energy/loss/congestion/voltage split that provably sums to the nodal price to machine precision on IEEE-13 and high-PV.**

## Performance

- **Duration:** ~35 min
- **Tasks:** 2 completed
- **Files modified:** 2 (1 filled from stub, 1 test file created)

## Accomplishments
- `extract_dlmp(ctx)` returns the day-ahead dynamic price (DADP/DLMP) — `dual.(ctx.constraints[:balance_p])` (thesis 3.31) — per node per hour, sign-pinned POSITIVE and ≈ λ₀ on a hand-solved lossless 2-bus, and REFUSING prices (throwing `ArgumentError`) when handed an ungated/inexact SOCP ctx (the `:l`-present-but-no-`:socp_maxgap` PF-04 guard).
- `decompose_dlmp(ctx)` splits the DADP into `energy + loss + congestion + voltage`, each reconstructed INDEPENDENTLY from a distinct registered dual and summed along each node's unique radial root→j tree path, guarded by a HARD relative-tolerance assertion (`energy+loss+congestion+voltage ≈ dual(balance_p)`, worst per-node residual reported on failure).
- The decomposition identity was empirically certified to machine precision (worst residual ~3.5e-15) on the IEEE-13 ground solve (congestion binds at the head branch, component ≈ −5.37) and the high-PV over-voltage solve (voltage engaged, congestion identically 0).
- All `dlmp` `@testitem`s are GREEN: 337 assertions in the new `test/test_pricing_dlmp.jl` plus the 7 in the pre-existing `test/test_dlmp.jl` RED harness (extract + decompose now defined).

## Task Commits

Each task was committed atomically (TDD-validated by running the `dlmp`-filtered testitems):

1. **Task 1: extract_dlmp + PF-04 gate + 2-bus DADP sign regression (PRICE-01)** — `256ffbc` (feat)
2. **Task 2: decompose_dlmp four-way split with sum-to-price net (PRICE-02)** — `13ca196` (feat)

## Files Created/Modified
- `src/pricing/dlmp.jl` — filled the plan-05-01 stub: `extract_dlmp`, `decompose_dlmp`, the PF-04 price-refusal guard `_assert_priceable`, the radial `_path_branches` parent-walk, and the `_smax_P` sparse-container reader. Every component cites its thesis equation (3.31/3.33/3.36/3.39/3.43).
- `test/test_pricing_dlmp.jl` — behavioral `@testitem`s (names contain "dlmp"): 2-bus energy-only sign, the ungated-SOCP refusal, the IEEE-13 (N,T) matrix + congestion-binding sum, the high-PV voltage-engaged sum, and the uncongested-in-bound ≈0 congestion/voltage case.

## Decomposition Derivation (KKT)

For branch `b = (i→j)`, stationarity of the welfare Lagrangian w.r.t. the branch active flow `P_b` gives the price increment across the branch:

```
λ_j − λ_i = −( cone_dualᵦ[3]  +  2·rᵦ·(βᵦ + γᵦ)  +  smax_dualᵦ[2] )
```

with `βᵦ = dual(:vdrop[b])` (3.33), `γᵦ = dual(:cpydrop[b])` (3.43), `cone_dualᵦ[3]` the P-slot of the rotated-SOC dual (3.39), and `smax_dualᵦ[2]` the P-slot of the apparent-power SOC dual (3.36, present only where a real limit binds). On the radial tree each node has a unique path root→j, so summing telescopes to `λ_j − λ_0`, attributing energy = λ₀ (same at every node), loss = Σ −cone_dual[3], congestion = Σ −smax_dual[2], voltage = Σ −2r(β+γ). The four therefore sum to `dual(balance_p[j,t])` by the KKT identity — verified, not assumed.

## Deviations from Plan

**Attribution refinement (documented, within plan intent):** the plan's Pattern 2 sketch attributed the voltage component to the `v`/`v̂` bound duals (`dual(UpperBoundRef(v))`, etc.) *plus* the `β`/`γ` contribution. The empirical KKT P-stationarity showed the exact voltage attribution is `−2r(β+γ)` **alone** — the `v`/`v̂` bound shadow prices are already propagated into `β`/`γ` through the voltage-drop recursion (3.33/3.43), so adding them separately would double-count and break the sum. This is the plan's own Assumption A1 (the sum assertion validates completeness regardless of attribution convention) and RESEARCH strategy B; the labels match the thesis' qualitative loss/congestion/voltage split. No architectural change; no user decision required.

Otherwise the plan executed as written.

## Notes for Downstream Plans
- `extract_dlmp` and `decompose_dlmp` accept an optional `bus`/`T` keyword: omit for the full `(N,T)` matrices, pass `bus` for a per-bus length-`T` vector.
- 6 suite failures remain in `test_fit.jl` / `test_economic_direction.jl` / `test_pricing_welfare.jl` — these are the pre-existing (commit `0c4b51d`, plan 05-01) RED harnesses for the concurrently-developed wave-2 plans 05-03/05-04/05-05, NOT regressions from this plan. All `dlmp` items are green.

## Self-Check: PASSED
