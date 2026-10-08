---
phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh
reviewed: 2026-10-02T18:00:00Z
depth: standard
iteration: 2
files_reviewed: 12
files_reviewed_list:
  - src/planning/benders.jl
  - src/planning/coupling.jl
  - src/planning/master.jl
  - src/planning/master_integer.jl
  - src/planning/nash.jl
  - test/test_planning_benders_integer.jl
  - test/test_planning_master_integer.jl
  - test/test_planning_nash.jl
  - test/test_planning_nash_integer.jl
  - test/test_planning_coupling.jl
  - docs/writeups/stackelberg_vs_psr_n1n2.typ
  - docs/writeups/modelo_stackelberg_dso_unico.typ
findings:
  critical: 1
  warning: 2
  info: 3
  total: 6
status: issues_found
---

# Phase 31: Code Review Report (iteration 2)

**Reviewed:** 2026-10-02 · **Depth:** standard (fix range `b07bfa9..2383876`) · **Status:** issues_found

## Summary

This pass re-reviewed the iteration-1 fixes (876a83d..2383876) and checked each item the fixer marked
"requires human verification". Resolved iteration-1 items are not raised again.

Verified sound:

- **WR-01 (presolve-off re-solve):**
  - The attribute is read, set and restored with `MOI.get`/`MOI.set` on `unsafe_backend(shared.model)` inside a `finally`.
  - HiGHS.jl's `MOI.set(::Optimizer, ::RawOptimizerAttribute)` only writes `model.options` and the HiGHS option. It does not clear the solution, and JuMP's dirty flag is never touched, so `value(shared.x_inv[i])` stays queryable.
  - The CachingOptimizer cache keeps the original value, so a later re-attach cannot leak `"off"`.
  - Every `shared.model` is HiGHS (`select_optimizer(LP())`).
  - On the NaN route, `_corner_recourse_joint` now passes `feas_cut = nothing` into the existing depth-bounded bisection (`JOINT_RECOURSE_BISECT_MAX_DEPTH`). That bisection terminates, and a feasible midpoint yields a valid epigraph cut, because the follower-feasible set is convex and `z_best` is feasible.
- **WR-04 (`max(Q_nu, L)` clamp):**
  - With `Q_eff = L` the cut reads `θ >= L`, which the epigraph bounds already imply, so it is valid at every corner.
  - With `Q_nu >= L` the cut is unchanged.
  - The `master.cuts` consumers (the literate doc and the certification test) rebuild the right-hand side from `Q_nu`, which is now the installed value. `master.cuts` is `Vector{Any}`, so the new `Q_nu_raw` field breaks nothing.
- **WR-05 (corner-search confirmation):**
  - Only a `:separating` verdict confirms. `:weak`, `:disagree` and a missing `feas_oracle` rethrow, which fails loudly and is never an invalid `+Inf`.
  - Accepting `INFEASIBLE_OR_UNBOUNDED` is sound. With z pinned and every device boxed, the welfare objective is bounded. An unbounded `l` with `r = 0` would leave the feasible set unbounded but not the objective, so "or unbounded" can only mean infeasible.
- **WR-06 (integer-path inputs):**
  - `_integer_alpha_x_lb` is a valid bound: `x_inv ∈ [0, x_inv_max]`, `x_op = z ∈ [0, y_inv] ⊆ [0, y_max]`, and each term is bounded by `min(0,c)·ub`. It reduces to 0.0 for nonnegative costs.
  - No caller in `src/`, `docs/literate/` or `scripts/` passes `integer=`. The only callers are in `test/test_planning_nash_integer.jl`, and they were updated, so nothing breaks.
  - The new key rejection is correct. See WR-02 for the one gap.
- **CR-02 asymmetric fixture:**
  - I re-derived and independently re-solved it (scratch `gne_branch.jl`, standalone Clarabel QPs with no TSODSO code).
  - The VE is `x_inv = (0.7, 0)`, `z = (0.7, 0.7)`, μ = 0.5 for both players, costs `[0.105, −0.595]`. It is unique: μ = 0.7 would violate player 1's x-stationarity, μ = 0 is infeasible, and `x_1 = 1` would force μ = 0.2 < 0.5.
  - The Gauss-Seidel GNE `(0.35, 0.25)`, `z = (0.7, 0.5)`, μ = (0.5, 0.7) is correct for both orders.
  - Reading μ_i from z-stationarity through the oracle dual is the right identification. At player 2's kink the follower LP's capacity dual is genuinely degenerate (anything in [0, 0.7] is optimal), so it cannot be used.
  - The sign `π_capacity = −μ` matches the measured value (−0.4999999998).
  - But see IN-01: this check adds no evidence beyond the `z` assertion.
- **The claim that exact best responses cannot cycle is correct, with the stated caveat.**
  - Player i's best response is computed with j's `(z_j, x_inv_j)` pinned, so the joint state stays feasible for j.
  - j's cost depends only on j's own variables, so it is unchanged by i's move.
  - Hence Φ = Σ cost is a generalized exact potential: ΔΦ = Δcost_i ≤ 0, strictly negative unless i's move is a tie.
  - A recurrent state therefore requires every move in the loop to be a tie, which is exactly the "ties aside" caveat. That caveat is material, because the interior-cap fixtures have tied, degenerate best responses.
- **WR-03 (brute force):** the hand-derived lattice costs `0, −0.225, −0.12` and the argmin `y = 0.5` check out, and the brute-force QP is genuinely independent of production code.

One blocker. The new cycle predicate still false-fires, demonstrated with the production `_integer_cycle_hit`. The corrected docs also introduce a new false mathematical claim: "VE set = GNE set" on the symmetric fixture.

## Critical Issues

### CR-01: `_integer_cycle_hit` still flags converging runs as CYCLED (oscillatory contraction; demonstrated on the production predicate)

**File:** `src/planning/nash.jl:319-334` (docstring claim at 300-311)

**Issue:**
- **The broken claim:** the docstring says "condition 3 independently rejects any contracting trajectory". That holds only when the residual drops by more than `atol = ω·tol_outer/2` between the matched sweeps. The "committed state moves" argument covers only consecutive sweeps, but `history` is scanned for any earlier sweep `h`.
- **The failing case:** a trajectory contracting with an oscillating factor c (d_k = c^k e, r_k = (1+|c|)|d_{k−1}|), compared against sweep k−2:
  - the two-sweep state difference is (1−c²)|d_{k−2}|;
  - the residual drop is (1−c²)·r_{k−2}.
  - Near the end of the run, with r slightly above `tol_outer`, both fall under `atol` whenever |c| ≳ 0.82 at ω = 1.
  - Binaries are typically already settled by then, so condition 1 holds too, and the predicate reports a cycle on a run that converges a few sweeps later.
- **Reproduced (scratch `cycle_osc.jl`):** the production `TSODSO._integer_cycle_hit` was fed the synthetic history c = −0.9, z* = 0.7, e = 0.01, ω = 1, tol_outer = 1e-4, fixed `b`. It returns `FALSE CYCLE at sweep 44 (matches sweep 42): r=2.05e-4, |Δs|=2.27e-5`. The same run converges about 6 sweeps later.
- **Why it can happen live:** a negative-slope Gauss-Seidel sweep map arises when one player's best response increases in the other's committed state while the other's decreases. That is free-riding on pooled capacity, exactly the mechanism of this game.
- **Secondary:** the `ω·tol_outer/2` separation argument (docstring 306-311) assumes the committed state moves by ω × residual. Under ω < 1 only `z` is damped. `x_inv_committed` is re-solved at the damped `z`, so when the residual is `x_inv`-dominated even consecutive sweeps are not guaranteed to differ by `atol`.
- **Missed cycles:** the other direction is acceptable. A genuine cycle whose recurring states differ by inner-solve noise (about 2–3e-4 measured, against `atol = 5e-5`) goes undetected and still fails at `max_sweeps`, as documented.

**Fix:** drop the tolerance slack in the no-progress test so that any strict residual decrease vetoes the match. Missed detections stay safe.
```julia
for h in history
    h.joint_b == joint_b || continue
    length(h.state) == length(state) || continue
    maximum(abs.(state .- h.state)) <= atol || continue
    residual >= h.residual || continue          # no slack: any decrease = progress
    return h.sweep
end
```
A stricter alternative also requires that no sweep between `h` and `k` had a lower residual than `h.residual`. Add the oscillatory-contraction history above to the synthetic predicate test as a must-not-fire case, and correct the docstring's "rejects any contracting trajectory" and ω < 1 separation claims.

## Warnings

### WR-01: New false claim: "the VE set equals the GNE set" on the symmetric interior-cap fixture (and the GNE set itself is mis-stated)

**Files:**
- `src/planning/nash.jl:357-361, 1221-1227, 1264-1269`
- `docs/writeups/stackelberg_vs_psr_n1n2.typ:227, 233`
- `test/test_planning_nash.jl:695-700, 1174-1186, 1303-1306`

**Issue:**
- **What the docs claim:** on `c_inv = [1,1]`, `x_inv_max = [1,1]` the GNE set is `{(x_1, 0.7 − x_1)}` with `z = (0.7, 0.7)`, and "o conjunto de VEs É o conjunto de GNEs … não há 'seleção' alguma nesse fixture".
- **Why it is false:** a free-riding branch exists, the same branch the new asymmetric derivation describes for player 2 ("x_2 = 0, μ_2 = p").
  - x_2 = 0, μ_1 = 0.5 ⇒ z_1 = 0.7.
  - μ_2 = p ∈ [0, 0.5] ⇒ z_2 = 1.2 − p.
  - x_1 = (1.9 − p)/2 ∈ [0.7, 0.95], below the cap of 1.
- **Checked independently:** standalone Clarabel QPs (scratch `gne_branch.jl`) at `x = (0.95, 0)`, `z = (0.7, 1.2)`:
  - player 1's best response is `x_1 = 0.95`, `z_1 = 0.70`, μ_1 = 0.5;
  - player 2's best response is `x_2 = 0`, `z_2 = 1.19996`, μ_2 ≈ 0.
- **Consequence:** this is a GNE off the claimed segment, with unequal multipliers, so it is not a VE. The VE set (the segment, μ = 0.5) is a strict subset of the GNE set, and the VE does select on this fixture: it excludes the free-riding branch.
- **What is still correct:** the narrower claims hold. The segment points all share μ = 0.5, the VE is non-unique, and the returned point is solver-dependent. `modelo_stackelberg_dso_unico.typ:192` ("o conjunto de VEs é o próprio continuum") is also correct.
- **Why it matters here:** this is the thesis writeup, and the project treats exact traceability of every modelling claim as a hard requirement.

**Fix:**
- Restate in all listed places: "the VE set is the whole split segment `x_1 + x_2 = 0.7`, `z = (0.7, 0.7)` (non-unique, solver-dependent point); the GNE set is strictly larger and also contains free-riding equilibria `x_j = 0`, `z_j = 1.2 − p`, `p ∈ [0, 0.5]`, with unequal multipliers."
- Remove "nothing is selected" and "VE set = GNE set", including from the testitem name at test/test_planning_nash.jl:1186.
- Correct the test comment at 697 ("the GNE set is …") to "the GNE set contains …".

### WR-02: Newly honoured `integer.α_op_lb` is not validated at `run_nash!`'s boundary; `α_x_lb = :auto` gives a MethodError

**File:** `src/planning/nash.jl:574-579, 732`

**Issue:**
- **The docstring's promise:** guards run "BEFORE any solve call".
- **`α_op_lb` is unchecked:** `integer.α_op_lb` is now forwarded (`get(integer, :α_op_lb, :auto)`), but nothing at the boundary validates it.
  - **NaN** passes `build_master_integer`'s explicit-bound branch (`NaN > d.optimum + slack` is false) and is then installed, because `min(NaN, d.bound) === NaN`, at master_integer.jl:288.
  - **`-Inf`** is installed as the bound, so `L = -Inf`. It surfaces only after a full inner Benders loop, as `add_ll_cut!`'s "L must be finite".
- **`α_x_lb = :auto` is mishandled:** the existing guard `isfinite(get(integer, :α_x_lb, 0.0))` throws `MethodError: isfinite(::Symbol)`, not an `ArgumentError`. `build_master_integer` accepts `:auto` for this key, and here it can never work, because `bounds_ctx.follower_kwargs = nothing`.

**Fix:** in the `integer !== nothing` guard block:
```julia
a_op = get(integer, :α_op_lb, :auto)
(a_op === :auto || (a_op isa Real && isfinite(a_op))) || throw(ArgumentError(
    "run_nash!: integer.α_op_lb must be :auto or a finite Real, got $(repr(a_op))"))
a_x = get(integer, :α_x_lb, 0.0)
(a_x isa Real && isfinite(a_x)) || throw(ArgumentError(
    "run_nash!: integer.α_x_lb must be a finite Real (no :auto — a DistributorView " *
    "follower has no derivation), got $(repr(a_x))"))
```
and add `NaN`/`-Inf`/`:auto` cases to the WR-06 guard testitem.

## Info

### IN-01: The CR-02 "own shared-row multiplier" check is a reparametrization of the `z` check, not independent evidence

**File:** `test/test_planning_nash.jl` (CR-02 testitem, `own_multiplier` and its uses)

`own_multiplier(z) = −π_oracle(z) − c_y − c_op = W′(z) − λ₀ − c_y − c_op = 1.2 − z` is a fixed function of `z`. So `own_multiplier(result_i.z) ≈ 0.5` is exactly `result_i.z ≈ 0.7`, which the line above already asserts with the same `BR_ATOL`. The same holds for `μ_gne ≈ (0.5, 0.7)`, which equals `gne.z ≈ (0.7, 0.5)`. The identification is mathematically right, since z-stationarity pins μ_i. But the comment's framing ("the VE's defining property, checked per player") overstates what the test certifies. Either say so in the comment, or add a genuinely independent multiplier read, for example the dual of the shared row in a standalone per-player QP like scratch `gne_branch.jl`, which gives −0.5 for both players at the VE.

### IN-02: Stale test-file header describes the pre-WR-01 NaN-sentinel flow

**File:** `test/test_planning_nash_integer.jl:40-56`

The header still says that a certificate-less infeasibility returns the NaN sentinel directly, and that a cut-needing caller "hits THAT function's pre-existing finiteness guard". Since 381644a the shared model is first re-solved without presolve. The T>1 corner search bisects, and `solve_stackelberg!` raises a named error before `add_feasibility_cut!`. Update the header to match `coupling.jl`'s docstring.

### IN-03: The WR-05 strictness trades a possibly-invalid +Inf for a hard abort near feasibility boundaries

**File:** `src/planning/benders.jl:322-331`

When the per-corner minimizer sits on the oracle's feasibility boundary, the ternary or Kelley trials approach it from outside. A Clarabel `ALMOST_INFEASIBLE` there, with `v` in the `:weak` band, now aborts the whole best response or Nash run. The behaviour is sound, because it fails loudly, but it is a new liveness risk on boundary-binding fixtures. None of the certified batches hit it. If it appears, the documented alternative is to bisect toward `z_best`, as the no-certificate path already does, rather than rethrow.

---

_Reviewed: 2026-10-02_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Scratch evidence (not committed): `/tmp/claude-1000/-home-pedro-programming-TSO-DSO/981f784b-8b89-4fdd-b64d-2c7c39f9b271/scratchpad/cycle_osc.jl`, `gne_branch.jl`_
