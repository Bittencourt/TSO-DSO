---
phase: 13-nash-diagonalization-shared-transmission-coupling
fixed_at: 2026-07-24T03:49:33Z
review_path: .planning/phases/13-nash-diagonalization-shared-transmission-coupling/13-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 13: Code Review Fix Report

**Fixed at:** 2026-07-24T03:49:33Z
**Source review:** .planning/phases/13-nash-diagonalization-shared-transmission-coupling/13-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5 (fix_scope = critical_warning; 7 Info findings out of scope)
- Fixed: 5
- Skipped: 0

**Verification:** All fixes verified beyond syntax — the full `test/test_planning_nash.jl`
suite was run from a scratch environment via
`TestItemRunner.run_tests("test"; filter = ti -> occursin("planning nash", ti.name))`
against the fixed worktree: **87 pass, 0 fail, 1 pre-existing broken** (the CairoMakie
weakdep skip). The suite includes the new CR-01 seed-liveness regression (14 assertions)
and the new WR-04 mid-sweep/guard regressions.

## Fixed Issues

### CR-01: `run_nash!` never seeds the shared model from `z0` — the multi-seed probe (NASH-04) was vacuous by construction

**Files modified:** `src/planning/nash.jl`, `test/test_planning_nash.jl`
**Commit:** fe0da05
**Status:** fixed — requires human verification (design-level seeding-rule choice, see below)
**Applied fix:** Took the review's preferred resolution (seed the state, not relabel).
Before the first sweep, `run_nash!` now commits the seed into the shared model's own
state via `write_back!(shared, j, z0[j,:], x_inv0[j])` for every distributor, so the
first best-response of every run genuinely plays against the seed instead of the
build-time all-zeros state. Added an optional `x_inv0` keyword (length-`N` seeded
investments); when omitted, each entry defaults to the minimal exactly-supporting
investment `maximum(z0[j,:]) / shared.corridor_cap`. Added seed-consistency guards
(all `ArgumentError`, before any solve): `z0` entrywise finite and `>= 0`;
`length(x_inv0) == N` and entrywise finite; per-distributor ceiling
`0 <= x_inv0[j] <= x_inv_max[j]`; and per-`t` pooled capacity feasibility
`sum(z0[:,t]) <= corridor_cap * sum(x_inv0)`. `x_inv_prev` is initialized from the
seeded investments (was `zeros`). Updated `run_nash!` and `run_nash_probe` docstrings
to document the live seed dimension.

Regression added (as the review demanded, so seed-inertness can never regress
silently): on the N=2 fixture, a cold seed converges to the hand-checked symmetric
equilibrium `z = [0.6, 0.6]` while a hot asymmetric investment seed
(`x_inv0 = [0.0, 0.3]`) produces a *different sweep-1 trajectory* (residual 0.6 vs 0.7,
asserted distinct) and settles on the genuinely different asymmetric equilibrium
`z ≈ [0.7, 0.0]` — proving a seed-dependent equilibrium is now detectable by
`run_nash_probe`'s spread. Both guard branches are also regressed.

**Human verification requested:** the default seeded-investment rule (minimal
exactly-supporting `max_t z0[j,t]/corridor_cap`, with a fail-loud ceiling guard rather
than clamping) is a design choice the fixer made within the review's suggested space.
It preserves all pre-existing fixtures/tests (verified), but the researcher should
confirm this seeding convention matches the intended NASH-04 probe semantics before
citing probe spreads as evidence of equilibrium robustness.

### WR-01: `run_nash!` ignored the feasibility flag of the load-bearing CR-01 parity re-solve

**Files modified:** `src/planning/nash.jl`
**Commit:** f8c1f24
**Applied fix:** `f_res.feasible` is now checked immediately after
`solve_follower!(result_i.follower, result_i.z)`; the infeasible branch errors loudly,
naming the distributor, instead of falling through to `value(shared.x_inv[i])` on a
no-primal-result solver state and a subsequent garbage `write_back!`.

### WR-02: Damped write-back (`ω < 1`) committed an inconsistent `(z_damped, x_inv_undamped)` pair

**Files modified:** `src/planning/nash.jl`
**Commit:** 9b0b49b
**Applied fix:** As suggested by the review: when `ω < 1`, the follower is re-solved at
the damped `z_i_new` and the *matching* investment `value(shared.x_inv[i])` is
committed (one extra cheap LP solve, only when damping is active), erroring loudly if
the damped flow is undeliverable. `ω == 1.0` keeps the zero-extra-solve path. The
committed value now also flows into `x_inv_prev`, the outer checkpoint payload, and
the returned `x_inv`, so the returned pair is exactly the pinned shared-model state.
Docstring step 5's "acceptable caveat" text replaced with the actual re-solve
contract. The existing `ω = 0.5` testitem exercises the new branch and passes.

### WR-03: Final `optimize!(shared.model)` on convergence was ungated

**Files modified:** `src/planning/nash.jl`
**Commit:** d486150
**Applied fix:** The convergence branch's final consistency re-solve is now gated with
`is_solved_and_feasible(shared.model) || error(...)`, naming the termination status —
matching the project-wide fail-loud solve discipline. A non-OPTIMAL fully-pinned solve
can no longer be returned as `converged = true`.

### WR-04: `is_converged(::NashTrace, tol, N)` mixed rows across sweeps, threw on `N <= 0`, and was dead code inside `run_nash!`

**Files modified:** `src/planning/nash.jl`, `test/test_planning_nash.jl`
**Commit:** ad68b17
**Applied fix:** All three defects, per the review's suggestion: (1) the window is now
selected by sweep index (`trace.sweep_trace .== last(trace.sweep_trace)`) with a
completed-sweep check (`count(mask) == N`), so a mid-sweep call returns `false` rather
than a verdict mixed across two sweeps; (2) `N >= 1` is guarded with an explicit
`ArgumentError` (docstring updated — an invalid sweep width is a caller bug, never a
soft `false`); (3) `run_nash!`'s sweep-end test now calls
`is_converged(trace, tol_outer, shared.N)` directly, so there is exactly one
convergence definition (the trailing-rows expression survives only as reporting for
`outer_residual`, computed inside the converged branch where it provably equals the
by-sweep window). Regressions added: `N = 0`/`N = -1` throw, mid-sweep ledger reports
`false` at a tolerance that the old trailing-2-rows window would have (wrongly)
passed, completed-sweep case reports `true`.

## Commits

All five fix commits were made on a temporary branch in an isolated worktree and
fast-forwarded onto `main`:

| Commit | Finding | Files |
|--------|---------|-------|
| fe0da05 | CR-01 | src/planning/nash.jl, test/test_planning_nash.jl |
| f8c1f24 | WR-01 | src/planning/nash.jl |
| 9b0b49b | WR-02 | src/planning/nash.jl |
| d486150 | WR-03 | src/planning/nash.jl |
| ad68b17 | WR-04 | src/planning/nash.jl, test/test_planning_nash.jl |

---

_Fixed: 2026-07-24T03:49:33Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
