---
phase: 05-distribution-pricing-dadp-dlmp-decomposition
plan: 04
subsystem: distribution-pricing
tags: [pricing, dadp, dlmp, duals, economic-direction, glut, congestion, checks, tdd]
requires:
  - solve_welfare (OPT-01, plan 03-05) producing an exactness-gated ctx with a registered :balance_p
  - register_constraint! / ctx.constraints[:balance_p] (PF-01, plan 01-03) — the DADP dual seam
  - Phase4Fixtures.build_high_pv_aggregators / build_ieee13_ground_aggregators / mem_price_profile (plan 04-03)
  - ConvexBranchFlow (PF-03, plan 04-02) — the SOCP formulation whose dual is the trustworthy DADP
provides:
  - "economic_direction_checks(ctx; λ₀, regime, ...) -> (; pv_glut_ok, congestion_ok) — the qualitative economic-correctness net (PRICE-05)"
  - "A throwing directional assertion: DADP < λ₀ at PV glut, DADP > λ₀ at head-branch congestion, reading ctx.constraints[:balance_p] duals directly (independent of dlmp.jl)"
affects:
  - "Phase-5 verification (Success Criterion #4: distribution price falls below wholesale at glut, rises above at congestion)"
  - "any future price-regression that wants a cheap backwards-signal tripwire on a solved ctx"
tech-stack:
  added: []
  patterns:
    - "read the DADP directly as dual.(ctx.constraints[:balance_p]) — same primitive extract_dlmp uses — to keep a Wave-2 module independent of a parallel sibling (dlmp.jl)"
    - "regime-keyworded directional assertion (:pv_glut / :congestion / :auto) that THROWS (never @assert) on a backwards signal"
    - "optional dadp override to prove NON-VACUITY (feed a sign-flipped price → the check fires)"
    - "per-hour aligned extremum (min/max over horizon of λ_j[t]−λ₀[t]) so the regime-active hour is found without hard-coding it"
key-files:
  created: []
  modified:
    - src/pricing/checks.jl
    - test/test_economic_direction.jl
decisions:
  - "Compare the DADP to λ₀ per-hour and take the extremum over buses×hours (min for glut, max for congestion), so the check locates the regime-active window itself and stays non-vacuous without hard-coded hours"
  - "Exclude the frontier/root bus from the scan (its DADP just tracks λ₀ ⇒ ~0 deviation); confirmed empirically the excursions live at non-root buses (glut argmin bus 3, congestion argmax struct-index 10 = thesis node 9 @ 22:00)"
  - "Non-vacuity probe: negating λ₀ inverts the glut relation (below→above) so :pv_glut throws; a negated λ₀ only STRENGTHENS an above-wholesale signal, so the congestion probe flips the DADP instead via the optional dadp override — the plan's 'sign-flipped … DADP'"
  - "tol=1e-6 strict-inequality slack; the measured excursions (glut −0.51, congestion +0.28) clear it by orders of magnitude, and a backwards signal flips by whole λ₀ units"
metrics:
  tasks_completed: 1
  files_created: 0
  files_modified: 2
  duration_min: 20
  completed: 2026-07-18
---

# Phase 5 Plan 04: Economic-Direction Price Checks Summary

`economic_direction_checks` — a cheap, high-signal directional net that asserts the distribution price (DADP) falls BELOW wholesale `λ₀` at a PV-glut / reverse-flow window and rises ABOVE `λ₀` at head-branch congestion, reading the `:balance_p` dual directly so it stays independent of the parallel `dlmp.jl`, and THROWING (non-vacuously) on a backwards price signal.

## What Was Built

- **`economic_direction_checks(ctx; λ₀, regime=:auto, bus=nothing, dadp=nothing, T=ctx.meta[:T], tol=1e-6)`** in `src/pricing/checks.jl`. It reads the per-node/hour DADP `λ_j[t]` DIRECTLY as `dual.(ctx.constraints[:balance_p])` — the same primitive `extract_dlmp` uses — so the module does not depend on `dlmp.jl` (owned by the parallel plan 05-02). It computes the extremal per-hour deviation `λ_j[t] − λ₀[t]` over the scanned (non-root) buses and hours:
  - `regime=:pv_glut` asserts `min(λ_j − λ₀) < −tol` (price below wholesale at glut; thesis Fig 4.5, node 9 @ 15:00 < MEM) and throws an `ArgumentError` on a backwards signal.
  - `regime=:congestion` asserts `max(λ_j − λ₀) > tol` (price above wholesale at congestion; thesis Fig 4.6, node 9 @ 22:00 > MEM) and throws on a backwards signal.
  - `regime=:auto` (default) reports both observed booleans without throwing.
  It returns `(; pv_glut_ok, congestion_ok)`. Shape guard `length(λ₀) == T` (T-05-11) and the regime/`:balance_p`-presence checks all throw loudly (never `@assert`, which `-O` can elide).
- **GREEN `@testitem`s in `test/test_economic_direction.jl`** (rewritten from the plan 05-01 RED harness; every item name contains "econ" and "direction"), `setup=[Phase4Fixtures]`:
  - PV-glut: solve `build_high_pv_aggregators` on `high_pv_feeder` with `allow_export=true`, assert `pv_glut_ok` and (explicitly, reading `:balance_p`) `min(λ_j−λ₀) < −1e-6`.
  - Congestion: solve `build_ieee13_ground_aggregators` on `ieee13_modified` with `allow_export=true`, assert `congestion_ok` and `max(λ_j−λ₀) > 1e-6`.
  - Non-vacuity + shape guard: a negated `λ₀` (glut) and a negated DADP override (congestion) each make the check `@test_throws ArgumentError`; a truncated `λ₀` trips the horizon guard.

## How It Works (empirical anchor)

A pre-implementation probe on the two Phase-4 fixtures (Clarabel SOCP, `allow_export=true`) confirmed the directions before coding:

| Fixture | extremum of `λ_j[t] − λ₀[t]` | where |
|---------|------------------------------|-------|
| high_pv (glut) | min = **−0.510** | bus 3, hour 11 |
| ieee13 ground (congestion) | max = **+0.284** | struct-index 10 (thesis node 9), hour 21 |

The glut fixture also carries a large negative excursion at the afternoon PV peak, and the congestion fixture a large negative one at hour 16 — both regimes co-exist in the ground fixture — so the check keys off the regime-appropriate extremum rather than a single hard-coded hour.

## Verification

`@run_package_tests filter=ti->occursin("econ", ti.name) || occursin("direction", ti.name)` → all green (my worktree's 4 `@testitem`s: defined/exported, PV-glut below, congestion above, backwards-signal throws). The TSODSO package precompiles and loads cleanly, confirming no load-time regression; the change is additive (a previously-empty stub gains one exported function).

## TDD Gate Compliance

- RED: `test(05-04)` commit `aa46aac` — behavioral econ-direction `@testitem`s fail (function undefined).
- GREEN: `feat(05-04)` commit `c5be4aa` — `economic_direction_checks` lands; the filtered suite passes.

## Deviations from Plan

None affecting scope. One in-test fix during GREEN: the explicit extremum was first written as a top-level `for` loop, which hit Julia's soft-scope rule inside a `@testitem` body (`UndefVarError: below`); rewritten as `minimum(...)` / `maximum(...)` generators (the implementation's own loop is inside a function and was never affected). Tracked as `[Rule 1 - Bug] test soft-scope`.

## Scope Boundary

Touched ONLY `src/pricing/checks.jl` and `test/test_economic_direction.jl` (the two files assigned to this parallel executor). No edits to `dlmp.jl`, `fit.jl`, `welfare.jl`, any `src/models/*`, `src/powerflow/*`, `src/TSODSO.jl`, STATE.md, or ROADMAP.md.

## Self-Check: PASSED

- Files present: `src/pricing/checks.jl`, `test/test_economic_direction.jl`, `05-04-SUMMARY.md`.
- `function economic_direction_checks` + `export economic_direction_checks` + direct `balance_p` read present in `checks.jl`.
- Commits present: `aa46aac` (RED test), `c5be4aa` (GREEN feat).
