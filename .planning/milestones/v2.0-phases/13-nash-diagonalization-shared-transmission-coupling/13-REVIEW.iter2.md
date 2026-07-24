---
phase: 13-nash-diagonalization-shared-transmission-coupling
reviewed: 2026-07-24T03:34:15Z
depth: standard
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
  critical: 1
  warning: 4
  info: 7
  total: 12
status: issues_found
---

# Phase 13: Code Review Report

**Reviewed:** 2026-07-24T03:34:15Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found

## Summary

Phase 13 adds the `SharedTransmission` corridor model (`coupling.jl`), the `run_nash!`
Gauss-Seidel outer loop + `NashTrace` ledger, the `run_nash_probe` multi-seed/multi-order
gate (`nash.jl`), the additive `follower` keyword on `solve_stackelberg!` (`benders.jl`),
and `plot_nash_convergence` (`plots.jl` + Makie ext). The JuMP modeling in `coupling.jl` is
sound: the per-distributor cost-slice/gradient argument is mathematically correct (other
distributors' terms are constants at fixed pins, so `dual.(coupling[i,:])` is a valid
subgradient of the slice), the Farkas-restriction argument for the feasibility cut is valid
under the fresh-cut-store-per-best-response regime, and the bound-pinning lifecycle is
well-regressed by the asymmetric fixture in `test_planning_coupling.jl`.

However, there is one critical defect: **the `z0` seed never enters the shared model's
state**, which makes the multi-seed dimension of `run_nash_probe` — the honesty gate this
phase's own comments say "the entire phase exists to implement" (NASH-04) — structurally
vacuous. Four warnings cover an unchecked re-solve result, an inconsistent damped
write-back that can commit an infeasible state, an ungated final solve, and a defective
`is_converged(::NashTrace)` method.

## Critical Issues

### CR-01: `run_nash!` never seeds the shared model from `z0` — the multi-seed probe (NASH-04) is vacuous by construction

**File:** `src/planning/nash.jl:377` (also `nash.jl:481-664` `run_nash_probe`, `src/planning/coupling.jl:233-237`)
**Issue:** `z0` is consumed exactly once: `z_prev = Matrix{Float64}(z0)` (line 377). It is
never written into the shared model — no `update_coupling!`/`set_parameter_value` call
initializes `shared.z[j,:]` from `z0[j,:]`, and every `x_inv[j]` stays at its build-time
`0.0` pin (`coupling.jl:235-237`). Consequently the first best-response of every run is
computed against the identical state `z_{-i} = 0`, `x_inv_{-i} = 0`, **regardless of the
seed**. Trace the trajectory under the probe's defaults (`ω = 1.0`, the only value
`run_nash_probe` can use since it does not forward `ω`):

- Sweep 1, distributor `i`: `result_i` depends only on the shared model's state (all
  zeros) — seed-independent. `z_i_new = result_i.z` (ω=1) — seed-independent.
  `write_back!` commits seed-independent values; `z_prev[i,:]` is overwritten.
- Sweep 2 onward: `z_prev` contains only sweep-1 write-backs; the seed is gone.

The seed's only observable effect is the sweep-1 `nash_residual` values recorded in the
trace (`|result_i.z − z0[i,:]|`). The returned equilibrium `(z, x_inv, UB)` is **bitwise
identical across all seeds**. Therefore `run_nash_probe`'s `z_spread`/`x_inv_spread`
"across 3 seeds × 2 orders" measures only the forward-vs-reverse difference; the seed
dimension of the probe matrix is dead. The gate reports "a converged equilibrium (spread:
z=...) across 6 probe run(s) (3 seed(s) x 2 order(s))" to a researcher, implying
seed-robustness was tested when it structurally cannot detect a seed-dependent
equilibrium — exactly the "silently presenting one run as canonical" failure NASH-04
exists to prevent (STATE.md's carried blocker: Gauss-Seidel diagonalization has no
uniqueness guarantee). The tests cannot catch this: `test_planning_nash.jl:631-633` only
asserts `spread >= 0.0 && isfinite(spread)`, which is trivially true when the spread is
identically ~0.

Note: `13-02-PLAN.md` itself specifies `z0` only as the `z_prev` initializer, so the
implementation matches the plan — but the plan's design defeats the phase's own NASH-04
contract ("probe across a matrix of initial-`z` seeds"). This is a design-level
correctness gap, not an implementation slip; it must be resolved before the probe's
output is presented as evidence of equilibrium robustness.

**Fix:** Make the seed actually enter the game state before the first sweep, e.g.:
```julia
# after boundary guards, before `for k in 1:max_sweeps`:
for j in 1:shared.N
    # seed every distributor's committed flow AND a consistent investment so the
    # pooled capacity row supports z0 (otherwise the first best-response may be
    # globally infeasible at a hot seed):
    x_inv0_j = min(shared.x_inv_max[j],
                   maximum(z0[j, :]) / shared.corridor_cap)  # or caller-supplied x_inv0
    write_back!(shared, j, z0[j, :], x_inv0_j)
    x_inv_prev[j] = x_inv0_j
end
```
(or add an explicit `x_inv0` keyword and guard that the seeded state is
capacity-feasible). Then add a probe regression that two different seeds produce
*different sweep-1 trajectories* (e.g., differing sweep-1 `nash_residual` AND at least one
differing intermediate write-back), so seed-inertness can never regress silently.
Alternatively, if seeding the state is deliberately out of scope, rename the parameter
(`residual_baseline`), strip the "initial-z seeds" claims from `run_nash_probe`'s
docstring/summary string, and drop the seed dimension from the probe — do not report a
seed spread that was never probed.

## Warnings

### WR-01: `run_nash!` ignores the feasibility flag of the load-bearing CR-01 parity re-solve

**File:** `src/planning/nash.jl:405-406`
**Issue:** `f_res = solve_follower!(result_i.follower, result_i.z)` is called for its side
effect only; `f_res.feasible` is never checked (and `f_res` is otherwise dead — flagged
by the compiler-level unused-variable smell too). `solve_follower!(::DistributorView, …)`
has a documented three-way contract: it can return `(; feasible = false, v, u)` without
raising. The incumbent `result_i.z` was feasible when it was solved inside
`solve_stackelberg!`, but this re-solve happens against the *same* shared state only by
construction — nothing enforces it, and boundary-tolerance drift (an incumbent that was
feasible within HiGHS's tolerance at solve time) can flip the branch. If the infeasible
branch is hit, the very next line `value(shared.x_inv[i])` throws an opaque
`JuMP.OptimizeNotCalled`/no-primal-result error (or reads ray-related values on some
solver states) far from the cause, and `write_back!` would then pin garbage.
**Fix:**
```julia
f_res = solve_follower!(result_i.follower, result_i.z)
f_res.feasible || error(
    "run_nash!: CR-01 parity re-solve at incumbent z for distributor $i " *
    "returned infeasible — shared state inconsistent with incumbent")
```

### WR-02: Damped write-back (`ω < 1`) commits an inconsistent `(z_damped, x_inv_undamped)` pair that can render the shared model globally infeasible for the next distributor

**File:** `src/planning/nash.jl:413-416` (write side: `src/planning/coupling.jl:318-335`)
**Issue:** With `ω < 1`, `write_back!(shared, i, z_i_new, x_inv_i_converged)` pins
`x_op[i,:] = z_i_new` (damped) against an investment `x_inv_i_converged` computed for the
*undamped* `result_i.z`. Whenever damping moves `z` upward (`z_prev[i,t] > result_i.z[t]`,
i.e. any decreasing segment of the trajectory — guaranteed to occur on non-monotone/
oscillating dynamics, which is precisely when a user reaches for damping), the committed
flow can exceed what the pinned pooled capacity supports:
`Σⱼ z_committed[j,t] > corridor_cap · Σⱼ x_inv_pinned[j]`. The next distributor's model is
then infeasible at **every** trial `z`, so its Benders loop emits only feasibility cuts
until the master goes infeasible or `max_iter` exhausts — a confusing mid-run crash whose
root cause is two files away. The docstring caveat ("acceptable because this phase's own
fixtures use ω = 1.0") documents the hazard but leaves `ω` an exposed, tested public
keyword (`test_planning_nash.jl:486-522` exercises `ω = 0.5` on a fixture whose monotone
increasing trajectory happens never to trigger it).
**Fix:** After computing `z_i_new` for `ω < 1`, re-solve the follower at `z_i_new` and pin
the *matching* investment:
```julia
if ω != 1.0
    f_damped = solve_follower!(result_i.follower, z_i_new)
    f_damped.feasible || error("run_nash!: damped write-back z is undeliverable for distributor $i")
    x_inv_i_committed = value(shared.x_inv[i])
else
    x_inv_i_committed = x_inv_i_converged
end
write_back!(shared, i, z_i_new, x_inv_i_committed)
```
(one extra cheap LP re-solve per best-response, only when damping is active). Otherwise
restrict the guard to `ω == 1.0` until damping is properly supported.

### WR-03: Final `optimize!(shared.model)` on convergence is ungated — violates the project's fail-loud solve discipline

**File:** `src/planning/nash.jl:456`
**Issue:** The convergence branch runs a bare `optimize!(shared.model)` with no status
check before returning `shared` "in a genuinely solved state". Every other solve in this
codebase is gated (`assert_solved!`/`solve_with_retry!`/`is_solved_and_feasible` with a
loud three-way branch — the discipline `coupling.jl:404-435` itself follows). If this
fully-pinned solve terminates non-OPTIMAL (e.g., tolerance-level infeasibility between the
pinned `z` parameters and the pinned `x_inv` bounds — a state WR-02 can produce), the
function still returns `converged = true`, and the caller's subsequent
`value(...)`/`dual(...)` queries either throw far from the cause or, for `dual`, return
values from a solver state the project's own conventions say must never be trusted
ungated.
**Fix:**
```julia
optimize!(shared.model)
is_solved_and_feasible(shared.model) || error(
    "run_nash!: final consistency re-solve of the fully-pinned shared model failed " *
    "(termination_status=$(termination_status(shared.model))) — converged state is " *
    "not mutually feasible")
```

### WR-04: `is_converged(::NashTrace, tol, N)` mixes rows across sweeps mid-sweep, throws on `N <= 0` despite its "never throws" contract, and is dead code inside `run_nash!`

**File:** `src/planning/nash.jl:187-190` (duplicated logic at `nash.jl:445`)
**Issue:** Three defects in one method:
1. The window `trace.nash_residual_trace[(end - N + 1):end]` is "the last N rows", not
   "the last completed sweep": called mid-sweep (trace rows = 1.5 sweeps, a legitimate
   state for any external consumer of the exported generic), the window spans two
   different sweeps and can report convergence from a mixture of sweep-`k` and
   sweep-`k−1` residuals — silently wrong for the documented "most recently completed
   sweep" semantics.
2. For `N <= 0` (or `N > 0` with `trace.iters >= N` but `N` exceeding... specifically
   `N = 0`): `trace.iters < 0` is false, so `maximum` runs over the empty range
   `(end+1):end` and throws `ArgumentError`/`MethodError` — contradicting the docstring's
   explicit "empty-ledger-safe, never throws" contract. `N` is entirely unvalidated.
3. `run_nash!` does not call it — line 445 re-implements the same expression inline
   (`maximum(trace.nash_residual_trace[(end - shared.N + 1):end])`), so the exported
   method and the loop's actual convergence test can drift independently, and the method
   is only exercised by the unit test's happy path.
**Fix:** Guard `N >= 1 || throw(ArgumentError(...))`; select the window by sweep index
rather than row count (`mask = trace.sweep_trace .== last(trace.sweep_trace)` combined
with a completed-sweep check `count(mask) == N`); and make `run_nash!` line 445 call
`is_converged(trace, tol_outer, shared.N)` so there is one convergence definition.

## Info

### IN-01: `run_nash!` outer checkpoint index is unguarded against `checkpoint_iteration!`'s `0:99_999` filename contract

**File:** `src/planning/nash.jl:432-442`
**Issue:** The outer checkpoint index `(k - 1) * shared.N + findfirst(==(i), sweep_order)`
can exceed 99 999 for large `max_sweeps * N` (e.g. `max_sweeps = 5_000`, `N = 20`), at
which point `checkpoint_iteration!` (`checkpoint.jl:49`) throws deep inside a late sweep
after hours of wasted solves. `solve_stackelberg!` guards its analogous case
(`benders.jl:157-163`); `run_nash!` guards only `max_sweeps >= 1`.
**Fix:** Add `max_sweeps * shared.N <= 99_999 || throw(ArgumentError(...))` to the
boundary-guard block.

### IN-02: `run_nash_probe` accepts duplicate `orders` entries, silently double-running combinations into one shared checkpoint directory

**File:** `src/planning/nash.jl:599-611,629`
**Issue:** The guard checks only membership (`order in (:forward, :reverse)`), not
uniqueness: `orders = (:forward, :forward)` passes `length >= 2`, runs each seed twice
with identical results (inflating `n_runs` and the "2 order(s)" summary claim), and both
duplicate runs write checkpoints to the same `"$(seed_name)_forward"` directory.
**Fix:** `allunique(orders) || throw(ArgumentError("run_nash_probe: orders must be distinct"))`.

### IN-03: No consistency check between `solve_stackelberg!`'s `T` and a supplied follower's own horizon

**File:** `src/planning/benders.jl:129-179` (surfaces in `src/planning/coupling.jl:392`)
**Issue:** When `follower = DistributorView(...)` is supplied, nothing verifies
`view.shared.T == T` at the guard block. A mismatch passes all boundary guards, builds
oracle and master at `T`, then dies mid-loop inside `solve_follower!`'s
`length(z_trial) != shared.T` check — violating the file's own guards-before-build
discipline. (`run_nash!` passes `T = shared.T` so the internal path is safe; the exposure
is direct callers of the new keyword.)
**Fix:** In the guard block: `follower === nothing || !hasproperty(follower, :shared) ||
follower.shared.T == T || throw(ArgumentError(...))` (or document a duck-typed
`horizon(follower)` accessor and check it).

### IN-04: `runs = Vector{NamedTuple}()` — abstractly-typed accumulator

**File:** `src/planning/nash.jl:615`
**Issue:** `Vector{NamedTuple}` is an abstract element type; every access
(`runs[a].result.z`) is dynamically dispatched. Harmless at 6-run scale but contrary to
the project's stated type-stability convention (CLAUDE.md "Type stability" bullet).
**Fix:** Collect via comprehension over the `(seed, order)` product so the element type is
inferred, or `map` over `Iterators.product(pairs(seeds), orders)`.

### IN-05: Makie ext palette silently reuses colors beyond 3 distributors

**File:** `ext/TSODSOMakieExt.jl:158-171`
**Issue:** `palette = [:seagreen, :orange, :teal]` with `mod1(idx, 3)` means distributors
1 and 4 (etc.) render identically — indistinguishable series on a thesis-grade figure,
with no linestyle/marker differentiation as a fallback. Also, an empty `NashTrace`
produces `lines!` on empty vectors under `yscale = log10`, which can trip Makie's
autolimits; a loud "empty trace" `ArgumentError` would fail better.
**Fix:** Use `Makie.wong_colors()` (7 colorblind-safe entries) or cycle linestyles when
`idx > length(palette)`; guard `trace.iters == 0 && throw(ArgumentError("empty NashTrace"))`.

### IN-06: `update_coupling!`/`write_back!` accept non-finite and out-of-range values silently

**File:** `src/planning/coupling.jl:286-296,318-335`
**Issue:** Both mutators guard index and length but not values: `set_parameter_value` with
`NaN`/`Inf` poisons the model for every later solve (surfacing as a confusing solver
failure), and `write_back!` will happily pin `x_inv[i]` above the declared
`x_inv_max[i]` ceiling or below 0, silently voiding the build-time bound contract. The
project elsewhere enforces finiteness at the seam (e.g. the Farkas-certificate `isfinite`
gate in this same file).
**Fix:** `all(isfinite, z_i_trial) || throw(ArgumentError(...))` in both;
`0 - ε <= x_inv_i_converged <= shared.x_inv_max[i] + ε || throw(ArgumentError(...))` in
`write_back!` (ε for solver tolerance).

### IN-07: Nested-tolerance guard compares dimensionally different quantities

**File:** `src/planning/nash.jl:367-375`
**Issue:** The guard enforces `inner_tol < tol_outer`, but `inner_tol` is a *relative*
UB/LB gap tolerance (`(UB−LB)/max(1,|UB|)` in `benders.jl:279`) while `tol_outer` is an
*absolute* ∞-norm on `z`/`x_inv` in flow units. The comparison is a heuristic, not the
mathematical nesting the comment claims: on a problem where `|UB| >> 1` or where `z`
sensitivity to the gap is large, `tol = 1e-6 < tol_outer = 1e-4` does not guarantee inner
noise in `z`-space is below the outer residual test. This is a locked CONTEXT.md decision
so no code change is demanded, but the docstring should state the relative-vs-absolute
mismatch explicitly so a thesis reader does not take "strictly nested tolerances" as a
proven property.
**Fix:** Amend the guard comment/docstring; optionally convert the outer test to a
relative residual to make the nesting genuine.

---

_Reviewed: 2026-07-24T03:34:15Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
