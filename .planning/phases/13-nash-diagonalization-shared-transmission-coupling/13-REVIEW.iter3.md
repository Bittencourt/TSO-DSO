---
phase: 13-nash-diagonalization-shared-transmission-coupling
reviewed: 2026-07-24T03:58:48Z
depth: standard
iteration: 2
files_reviewed: 8
files_reviewed_list:
  - src/planning/coupling.jl
  - src/planning/nash.jl
  - src/planning/benders.jl
  - src/TSODSO.jl
  - src/diagnostics/plots.jl
  - ext/TSODSOMakieExt.jl
  - test/test_planning_coupling.jl
  - test/test_planning_nash.jl
findings:
  critical: 0
  warning: 1
  info: 2
  total: 3
status: issues_found
---

# Phase 13: Code Review Report (Iteration 2 — Fix Re-Review)

**Reviewed:** 2026-07-24T03:58:48Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found (no Critical; 1 new Warning on regression coverage, 2 new Info)

## Summary

Re-review of the five fixes (commits `fe0da05`, `f8c1f24`, `9b0b49b`, `d486150`,
`ad68b17`) for iteration 1's CR-01 and WR-01..WR-04. Since the review commit
(`08c687d`), only `src/planning/nash.jl` and `test/test_planning_nash.jl` changed;
the other six in-scope files are byte-identical to the state iteration 1 reviewed.

**All five fixes are correct.** Verification highlights:

- **CR-01 — FIXED.** The seed is now committed into the shared model's own state via
  `write_back!(shared, j, z0[j,:], x_inv0_vec[j])` for every distributor before sweep 1
  (`nash.jl:479-481`). I verified the new seed-consistency guards against the actual
  model in `coupling.jl`: the per-`t` capacity guard `sum(z0[:,t]) <= corridor_cap *
  sum(x_inv0) + 1e-9` (`nash.jl:453-463`) matches the pooled `capacity[t]` row exactly
  (`coupling.jl:220-224`); the derived default `maximum(z0[j,:]) / shared.corridor_cap`
  cannot divide by zero (`build_shared_transmission` guards `corridor_cap > 0`,
  `coupling.jl:187-189`) and mathematically guarantees the pooled guard is satisfied
  whenever the per-distributor ceiling guard passes. Guard ordering is sound
  (finiteness before sign, ceiling+clamp before the capacity sum that consumes the
  clamped vector). `x_inv_prev` is correctly initialized from the seeded investments so
  sweep-1 residuals are measured against the genuine seed state. The probe's seed
  dimension is now live — the new regression proves two seeds reach genuinely distinct
  equilibria (`[0.6, 0.6]` vs `[0.7, 0.0]`); I re-derived the hot-seed equilibrium by
  hand from the fixture (`0.7 <= 2*(x_inv_1 + 0.3)` → `x_inv_1 = 0.05`; distributor 2
  then forced to `x_inv_2 = 0.3` with `z_2 = 0`) and it checks out. One coverage gap
  remains (WR-05 below).
- **WR-01 — FIXED.** `f_res.feasible` is gated with a loud, distributor-naming error
  (`nash.jl:512-516`); the previously dead `f_res` binding is now load-bearing.
- **WR-02 — FIXED.** With `ω < 1`, the follower is re-solved at the damped `z_i_new`
  and the matching `value(shared.x_inv[i])` is committed (`nash.jl:536-546`), erroring
  loudly on an undeliverable damped flow. Ordering verified: `residual_i` is computed
  from the parity re-solve's `x_inv_i_converged` *before* the damped re-solve mutates
  solver state, so the residual is uncontaminated. The committed value consistently
  flows into `write_back!`, `z_prev`/`x_inv_prev`, the trace row, the outer checkpoint
  payload, and the returned `x_inv`.
- **WR-03 — FIXED.** The final consistency re-solve is gated with
  `is_solved_and_feasible(shared.model) || error(...)` naming the termination status
  (`nash.jl:601-606`); `converged = true` can no longer be returned over an untrusted
  solver state.
- **WR-04 — FIXED.** `is_converged(::NashTrace, ...)` now selects the window by sweep
  index with a completed-sweep check (`count(mask) == N`), throws `ArgumentError` on
  `N < 1`, and `run_nash!`'s convergence decision delegates to it (`nash.jl:196-202,
  582`). The mid-sweep regression (`test_planning_nash.jl:73-106`) pins exactly the
  old trailing-2-rows false-positive.

**Empirical verification:** I independently ran the full planning-nash suite
(`TestItemRunner.run_tests` filtered to `"planning nash"`) against the fixed tree:
**88 pass, 0 fail** (2m25s), including the new CR-01 seed-liveness regression
(`test_planning_nash.jl:815-943`) and the WR-04 guard/mid-sweep regressions. This
corroborates the fixer's own reported run.

No fix introduced a Critical defect. Three new findings below: one Warning (the CR-01
regression never varies `z0` itself, leaving the z-Parameter half of the seeding
mechanism — the only dimension `run_nash_probe` actually probes — without direct
regression coverage) and two Info items introduced/retained by the fix commits. The 7
Info findings from iteration 1 (IN-01..IN-07) were deliberately out of fix scope and
are not re-reported; none became more severe.

## Narrative Findings (AI reviewer)

## Warnings

### WR-05: CR-01 seed-liveness regression never varies `z0` — the z-Parameter half of the seeding (the only dimension `run_nash_probe` probes) can silently regress

**File:** `test/test_planning_nash.jl:815-943` (mechanism under test: `src/planning/nash.jl:479-481`, `src/planning/coupling.jl:331`)
**Issue:** Both runs in the "seeds genuinely enter the shared game state" regression use
the identical `z0 = zeros(2, 1)` (lines 845, 864) and differ only in `x_inv0`
(`[0.0, 0.3]` vs derived zeros). With `z0 = 0`, the z-Parameter half of the seeding
loop — `set_parameter_value.(shared.z[j,:], z0[j,:])` inside `write_back!` — is a
no-op relative to the build-time `Parameter(0.0)` state; only the investment
bound-pinning half is exercised. But `run_nash_probe` never passes `x_inv0`: its only
seed dimension is `z0` (with the derived investment default), so the mechanism the
probe's honesty gate actually depends on — a hot `z0` changing neighbors' *consumed
pooled capacity*, not just their pinned investment headroom — has no direct regression.
Concretely: a future refactor that keeps the investment pinning but drops (or reorders
around) the z-Parameter commit would pass this regression AND all probe testitems
(which assert only `converged`, `spread >= 0`, `isfinite` — the same vacuous-spread
assertions iteration 1 flagged), while sweep-1 best-responses would silently see
neighbors consuming zero capacity at nonzero pins — a partial recurrence of CR-01
itself. Iteration 1's fix guidance explicitly asked for a regression that "two
different seeds produce different sweep-1 trajectories"; the committed regression
varies the investment seed instead of the `z0` seed.
**Fix:** Add a third run to the same testitem with a hot `z0` and derived `x_inv0`,
e.g. `z0 = [0.5; 0.1;;]` (the probe's own `skewed` seed) vs the cold run, asserting
distinct sweep-1 `nash_residual_trace[1]` — and/or assert the seeded parameter state
directly after entry, e.g. build a shared model, call `run_nash!` with a hot `z0` and
`max_sweeps = 1` on a non-converging tolerance, and check
`parameter_value.(shared.z[2, :]) == z0[2, :]` before distributor 2's turn (or unit-test
the seeding loop via `write_back!` + `parameter_value`). Either variant makes the
z-Parameter half of the seed regression-pinned.

## Info

### IN-08: `outer_residual` reporting re-implements the convergence window inline, contradicting the fix's own single-definition comment

**File:** `src/planning/nash.jl:583-584`
**Issue:** The WR-04 fix routes the convergence *decision* through
`is_converged(trace, tol_outer, shared.N)` (line 582), but the reported
`outer_residual_k` on the next line is still the trailing-row expression
`maximum(trace.nash_residual_trace[(end - shared.N + 1):end])` — the exact window
arithmetic the adjacent comment says must "never [be] re-implement[ed] inline". Inside
`run_nash!` the two windows are provably equal (each sweep pushes exactly `shared.N`
rows), so this can only mis-report, not mis-decide — but a future change to trace-push
granularity would desynchronize the reported residual from the decision silently.
**Fix:** Compute the report from the same by-sweep-index mask, e.g.
`mask = trace.sweep_trace .== last(trace.sweep_trace); outer_residual_k =
maximum(trace.nash_residual_trace[mask])`, or have `is_converged` (or a small helper)
return the window residual so there is literally one window computation.

### IN-09: Seed-guard tolerance asymmetry and docstring mismatch in the `x_inv0` ceiling check

**File:** `src/planning/nash.jl:419-425, 441-452`
**Issue:** The ceiling guard accepts up to `x_inv_max[j] + 1e-9` and then silently
clamps to the ceiling, while the lower-bound checks (`0.0 <= x_inv0_vec[j]`,
`all(>=(0), z0)`) are exact — an explicit `x_inv0`/`z0` fed from a prior solve's
`value()` output (which can carry `-1e-13`-scale solver noise) throws, whereas the same
noise above the ceiling passes. The docstring also states the exact contract
`0 <= x_inv0[j] <= shared.x_inv_max[j]` without mentioning the `+1e-9` acceptance band
or the clamp. Fail-loud on the low side is safe (never silently wrong), so this is
consistency polish only.
**Fix:** Apply the same `-1e-9` acceptance-then-clamp-to-zero on the low side of both
`z0` and `x_inv0` (or make all three exact), and state the tolerance/clamp behavior in
the docstring.

---

_Reviewed: 2026-07-24T03:58:48Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard (iteration 2 fix re-review; independent test run: 88 pass / 0 fail)_
