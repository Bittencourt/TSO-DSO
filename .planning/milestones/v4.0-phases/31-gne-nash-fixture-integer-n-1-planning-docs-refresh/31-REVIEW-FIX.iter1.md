---
phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh
fixed_at: 2026-10-02T00:00:00Z
review_path: .planning/phases/31-gne-nash-fixture-integer-n-1-planning-docs-refresh/31-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 31: Code Review Fix Report

**Fixed at:** 2026-10-02
**Source review:** .planning/phases/31-gne-nash-fixture-integer-n-1-planning-docs-refresh/31-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope (Critical + Warning): 8
- Fixed: 8 (5 flagged "requires human verification" because they change logic)
- Skipped: 0
- Info items, outside the scope but fixed because each was small: IN-01, IN-02, IN-03, IN-04, IN-05. Skipped: IN-06, IN-07 (reasons below)

Worked directly on `main` as the orchestrator instructed. No worktree or recovery sentinel was created.

## Fixed Issues

### CR-01: Integer cycle detection fires on runs that are still converging

**Files modified:** `src/planning/nash.jl`, `test/test_planning_nash_integer.jl`, `docs/writeups/stackelberg_vs_psr_n1n2.typ` (+ PDF)
**Commit:** 876a83d (code + tests), cee8330 (writeup + PDF)
**Status:** fixed: requires human verification (logic change)
**Applied fix:**
- The cycle key is now the full committed state, checked by the new internal predicate `_integer_cycle_hit`. A cycle is reported only when all of these hold on a sweep that has not converged:
  - the joint `b` is identical;
  - the committed `(vec(z), x_inv)` is within `ω·tol_outer/2`;
  - the residual has not decreased.
- Why `ω·tol_outer/2`: with `ω = 1` the committed state moves by exactly the residual, and by ω times it for the damped `z`. The docstring documents this.
- A missed detection is safe, because the run still fails loudly at `max_sweeps`.
- Tests:
  - **Predicate test:** the production predicate on synthetic histories. A damped converging history must not fire; genuine period-1 and period-2 cycles must fire. Also covered: one flipped bit, a moved state, and a decreased residual.
  - **Live test:** a damped `run_nash!(...; integer=(;K=4), ω=0.5)` on the BILEV-07 fixture, seeded at `z0=0.46` with `tol_outer=0.015`. `b` is identical at sweeps 1 and 2 while sweep 2 has not converged. The pre-fix code threw `CYCLED ... recurred at sweep 2` on it (verified with the fix stashed). The fixed code converges in 3 sweeps; residuals `[0.04,0.04,0.02,0.02,0.01,0.01]` are pinned.
- The seed is chosen so the test takes about 1 minute. The reviewer's repro (`z0=0`, `tol_outer=1e-4`) needs about 14 sweeps.
- **Limitation, stated in the docstring and writeup:** no live cycling instance exists. With objectives separable except through the shared row, the summed cost is a potential that exact Gauss-Seidel best responses cannot cycle on. The genuine-cycle side is therefore tested on synthetic histories against the production predicate.

### CR-02: The VE is not unique on the interior-cap fixture

**Files modified:** `src/planning/nash.jl`, `test/test_planning_nash.jl`, `docs/writeups/stackelberg_vs_psr_n1n2.typ`, `docs/writeups/modelo_stackelberg_dso_unico.typ` (+ both PDFs, force-added)
**Commit:** 515e57c
**Applied fix:**
- **Docs:** the `run_nash!` caveat, the VE section header, the `solve_variational_equilibrium` docstring and both Portuguese writeups now say:
  - On the symmetric fixture the VE set equals the GNE set (every point has multiplier 0.5), and the solver's choice of point is arbitrary (Clarabel picks the analytic centre).
  - Rosen's uniqueness theorem does not apply, because the game is linear in `x_inv`.
- **Symmetric testitem:** renamed to describe a point of the non-unique VE face. It now pins `π_capacity = -0.5`, the multiplier every GNE shares, instead of only checking `isfinite`.
- **New CR-02 testitem** on an asymmetric fixture (`c_inv = [1.0, 1.4]`, derivation in the test comment):
  - The unique hand-derived VE is `x_inv = (0.7, 0)`, `z = (0.7, 0.7)`, `y = (0.7, 0.7)`, `π_capacity = -0.5`, `cost_per_distributor = [0.105, -0.595]`. Measured within 1.1e-9; asserted at 1e-6.
  - For each player, a `solve_stackelberg!` best response (the run_nash! building block, other player pinned at the VE) is checked. It reproduces the VE `z` and cost, and the player's own shared-row multiplier equals `-π_capacity` within 1e-3 (measured offset 2.1e-4).
  - The multiplier is computed as `-π_oracle - c_y - c_op`, from z-stationarity. The follower LP's capacity dual cannot be used: it is degenerate at player 2's kink (measured 0.0 against -0.5).
  - Selection is shown explicitly: `run_nash!` from `z0 = 0` lands on a different GNE, `x_inv = (0.35, 0.25)`, `z = (0.7, 0.5)`, with unequal multipliers `(0.5, 0.7)`.

### WR-01: The no-Farkas-ray infeasible branch is a dead end

**Files modified:** `src/planning/coupling.jl`, `src/planning/benders.jl`, `test/test_planning_coupling.jl`, `test/test_planning_benders_integer.jl`
**Commit:** 381644a
**Status:** fixed: requires human verification (solver-interaction change)
**Applied fix:**
- **Diagnosis:** I instrumented the integer-Nash run. Every no-ray case was a tolerance-borderline trial: `z = 0.6000001` against a capacity of 0.6, a 1e-7 violation. Presolve declares it INFEASIBLE with no ray; simplex without presolve declares it OPTIMAL.
- **coupling.jl:**
  - `solve_follower!(::DistributorView)` now re-solves such a verdict once with presolve off.
  - The attribute is set and restored on the inner optimizer (`unsafe_backend`) inside a `finally`. JuMP's `set_attribute` would mark the model dirty and break `run_nash!`'s subsequent `value(shared.x_inv[i])`; I verified this with a scratch script.
  - The NaN sentinel is returned only if the re-solve still gives no trusted result. The classification logic is factored into `_classify_shared_solve`.
- **benders.jl:**
  - `_corner_recourse_joint.evaluate` returns `feas_cut = nothing` for a non-finite certificate, which routes it to the bisection fallback. No NaN can reach the small LP.
  - `solve_stackelberg!`'s outer feasibility branch raises a named diagnostic error instead of `add_feasibility_cut!`'s generic one.
- **Tests:**
  - The borderline trial now returns `feasible = true`, `x_inv` stays queryable, and presolve is restored to `"on"`.
  - A T=2 joint corner search with a follower that returns one certificate-less verdict now converges to the hand-derived `Q = -1.44`.
  - Both tests fail on the pre-fix code; the second fails with JuMP's `Invalid coefficient NaN`.

### WR-02: Writeup claims `inexact_policy` applies to the bilevel KKT variant

**Files modified:** `docs/writeups/modelo_stackelberg_dso_unico.typ` (+ PDF)
**Commit:** 873a21f
**Applied fix:** The claim is restricted to rows 1 and 3 (`solve_stackelberg!`, and `run_nash!` forwarding it unchanged). Row 2 (`solve_bilevel!`/`build_bilevel_kkt`) is stated to be LinDistFlow-only: it never calls `solve_stackelberg!`, has no `inexact_policy`, and rejects SOCP/QP/NLP with `ArgumentError`.

### WR-03: The integer brute-force certification is not independent

**Files modified:** `test/test_planning_nash_integer.jl`
**Commit:** 361e83d
**Applied fix:**
- **Hand derivation**, in a test comment: player cost at lattice `y` against `(z_j, x_j) = (0.5, 0.25)` gives `y=0 → 0`, `y=0.5 → -0.225`, `y=1 → -0.12`, plus 0.15 per further step. The unique argmin is `y = 0.5`.
- **Pinned equilibrium:** `z = [0.5,0.5]`, `x_inv = [0.25,0.25]`, `UB = [-0.225,-0.225]`, asserted at 1e-9 (measured -0.2249999999999959).
- **Independent brute force:** `corner_recourse` is replaced by a fresh, hand-written JuMP QP per lattice point. The QP has device `p`, lossless balance `p == z`, the master box, the pooled row with `j` pinned, and the player's full cost, solved once. It uses no `corner_recourse`, oracle, `DistributorView` or `SharedTransmission`. The test asserts the argmin, the first three lattice costs, and no profitable deviation. Measured diff 2.2e-9; tolerance 1e-6.

### WR-04: `add_ll_cut!` tolerance band still appends an invalid cut

**Files modified:** `src/planning/master_integer.jl`, `test/test_planning_master_integer.jl`
**Commit:** 1c28fbc
**Status:** fixed: requires human verification (logic change)
**Applied fix:**
- After the guard, the cut is built with `Q_eff = max(Q_nu, L)`, and a `@warn` fires when the clamp is active.
- `master.cuts` records `Q_nu = Q_eff`, the installed value, so consumers that rebuild the RHS (`test_planning_certification_integer.jl`, `docs/literate/integer_investment.jl`) stay consistent. A new `Q_nu_raw` field keeps the caller's value.
- The test that used `atol=10` and `Q = L-0.5` now asserts:
  - the warning fires;
  - `Q_nu == L` and `Q_nu_raw == L-0.5`;
  - pinning `b` at the farthest corner (Hamming distance 4) and minimizing θ reaches exactly `L`. The unclamped cut demanded `L + 1.5`.
- An unclamped case (`Q_nu > L`) is also covered.

### WR-05: Weak or unconfirmed infeasibility verdicts become +Inf in the corner search

**Files modified:** `src/planning/benders.jl`, `test/test_planning_benders_integer.jl`
**Commit:** 0145b9d
**Status:** fixed: requires human verification (logic change)
**Applied fix:**
- `_oracle_or_infeasible` now requires a `:separating` slack-min verdict for statuses in the new `CORNER_UNCONFIRMED_STATUSES = (ALMOST_INFEASIBLE, LOCALLY_INFEASIBLE)`.
- `:weak` and `:disagree` verdicts rethrow, and so does a missing `feas_oracle`.
- `INFEASIBLE_OR_UNBOUNDED` stays accepted as certified. The assumption is now explicit: the welfare oracle at a pinned z is bounded.
- The docstrings explain why the corner search is stricter than the outer loop: there a weak cut is still valid, but here the verdict becomes `+Inf`.
- New mock tests cover: `:weak` rethrows; `LOCALLY_INFEASIBLE` without confirmation rethrows; with `:separating` it returns `nothing`; with `:weak` it rethrows; `INFEASIBLE_OR_UNBOUNDED` returns `nothing`.
- This also fixes IN-01: the dead `CORNER_INFEASIBLE_STATUSES` is replaced by the live constant.

### WR-06: The `integer` path silently ignores user bounds and assumes nonnegative costs

**Files modified:** `src/planning/nash.jl`, `test/test_planning_nash_integer.jl`
**Commit:** b06310c
**Status:** fixed: requires human verification (logic change)
**Applied fix:** I chose to reject ignored inputs rather than silently honour them.
- **Validation:** with `integer !== nothing`, `run_nash!` throws `ArgumentError` when:
  - a `master_kwargs` key other than `c_y`/`y_max` is present, for example an α bound; the message points the caller at `integer`;
  - `c_y` or `y_max` is missing;
  - an `integer` key other than `K`/`α_op_lb`/`α_x_lb` is present.
- **Bounds:** `integer.α_op_lb` is now honoured (default `:auto`). The default `α_x_lb` is derived from the cost signs by `_integer_alpha_x_lb`: `min(0,c_inv[i])*x_inv_max[i] + Σ_t min(0,c_op[i][t])*y_max`. That is 0.0 for nonnegative costs (unchanged on existing fixtures) and still valid when a cost is negative.
- **Test fixtures:** the integer test fixtures now carry `master_kwargs = (; c_y, y_max)` only.
- **Tests:** new tests cover each rejection and the derived bound, including a negative-cost case.

## Info Items (outside the scope)

- **IN-01:** fixed in 0145b9d, as part of WR-05.
- **IN-02:** fixed in 4f675c6. The stale comment now says the `accepted_slack` term is always 0.0 since plan 31-07's clamp. The field and `_accepted_lb_slack` are kept as a seam, because removing them is a refactor touching asserted tests.
- **IN-03:** fixed in 7d0ce39. The garbled Algorithm step 4 is rewritten.
- **IN-04:** fixed in 2383876. The writeup now says `b[1:K]` are the only *declared* investment binaries, and that `bilevel_kkt.jl`'s SOS1 pairs are bridged to binaries by `SOS1ToMILPBridge`. PDF recompiled.
- **IN-05:** fixed in 978a50c. `run_nash!` asserts the integer best response lies on the K-lattice and `idx < 2^K` before `digits`. The tolerance is `1e-6·y_max` rather than the reviewer's `1e-9·y_max`, because `y` is not rounded and binaries can be off by HiGHS's 1e-6 MIP integrality tolerance.
- **IN-06 skipped:** explaining why the probe's `z_spread` (5.8e-4) exceeds `tol_outer` needs an investigation (likely the inner-Benders flatness also seen here: best responses stop about 2-3e-4 from the analytic `z`). It is not a trivial fix, and no tolerance was changed without measuring.
- **IN-07 skipped:** removing `maxlog=1` from the build-time clamp warnings is a log-volume design choice that would flood multi-build Nash runs. Letting `run_nash_probe` forward `integer` is a feature addition, not a fix.

## Verification

All runs used the top-level `@testitem` emulator (`JULIA_LOAD_PATH="test:.:@stdlib"`) in the foreground. `Pkg.test()` was never run. Every chunk also includes `test_planning_oracle.jl`, which defines the `ToyDeviceFixture` test module, so its items are counted in each chunk.

| Batch | Files | Result |
|---|---|---|
| 1a | oracle, benders, master, master_integer, hardening | 583 / 583 pass |
| 1b | oracle, benders_integer, alpha_bounds_stackelberg | 75 / 75 pass |
| 1c | oracle, certification_integer | 59 / 59 pass |
| 2a | oracle, nash | 182 pass, 1 broken (pre-existing), 0 fail |
| 2b | oracle, nash_integer, coupling, certification, goldens | 131 / 131 pass |
| 3 | inexact_policy, feasibility_oracle, ac_recheck, benders_ieee13 | 161 / 161 pass |
| literate | `docs/literate/nash_diagonalization.jl`, `docs/literate/integer_investment.jl` | both exit 0 |

**Golden-move audit** (`audit_goldens.py`):
- From `36e3c1e` (the Phase-30 close) to HEAD: 0 flagged moves. No pre-Phase-31 golden moved.
- From `b07bfa9` (the pre-fix head) to HEAD: 3 flagged items, all `old = NONE`. These are new assertions in Phase-31-only test files (`π_capacity = -0.5`, `UB = -0.225`, and the predicate test's `tol_outer = 1e-4`), not moved values.

All new tolerances were measured; the measurements are recorded in the test comments.

---

_Fixed: 2026-10-02_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
