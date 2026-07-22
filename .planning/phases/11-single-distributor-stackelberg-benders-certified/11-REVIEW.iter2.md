---
phase: 11-single-distributor-stackelberg-benders-certified
reviewed: 2026-07-22T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - src/TSODSO.jl
  - src/planning/benders.jl
  - src/planning/follower.jl
  - src/planning/master.jl
  - test/Project.toml
  - test/test_planning_benders.jl
  - test/test_planning_certification.jl
  - test/test_planning_follower.jl
  - test/test_planning_master.jl
findings:
  critical: 1
  warning: 5
  info: 5
  total: 11
status: issues_found
---

# Phase 11: Code Review Report

**Reviewed:** 2026-07-22
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Reviewed the single-distributor Stackelberg–Benders implementation: `FollowerLP` with
genuine HiGHS Farkas certificates (`follower.jl`), the build-once Benders master with
persistent cut rows (`master.jl`), the `solve_stackelberg!` outer loop (`benders.jl`),
the include-graph wiring (`TSODSO.jl`), and the test suite including the BilevelJuMP
certification gate.

**Cut algebra verified correct** (the areas flagged for special attention):

- *Optimality-cut sign convention*: `subproblem.jl`'s D-06 contract pins
  `π = dual.(pin)` as the negation of `∂W/∂z` under the Max-sense welfare objective,
  i.e. `π` is exactly the subgradient of the convex cost `-W(z)`. With
  `cost_k = -oracle_res.cost`, the `:op` cut `α_op ≥ -W(z_k) + π·(z - z_k)` is a valid
  convex underestimator. The follower's `:x` cut uses the Min-sense coupling dual as-is
  (empirically pinned to `+m_f` in `test_planning_follower.jl`) — also correct.
- *Feasibility-cut direction*: verified by direct execution in this environment on the
  toy corridor LP. At `z_trial = -1.0`, HiGHS returns `v = 1.0, u = [-1.0]`, and the cut
  `v_k + Σ u_k(z - z_k) ≤ 0` reduces to exactly `z ≥ 0`; at `z_trial = 10.0` it returns
  `v = 3.0, u = [0.5]`, reducing to exactly `z ≤ 4.0 = corridor_cap · x_inv_max`. The
  `u = dual.(f.coupling)` restriction is valid because `z` appears only in the coupling
  rows (dual-feasibility of the ray on the free parameter column forces the
  parameter-fixing-row ray to equal the coupling-row ray).
- *Epigraph bound initialization*: finite `α_op_lb`/`α_x_lb` declared at build time;
  the zero-cut first solve is regression-tested to be `MOI.OPTIMAL`.
- *Gap formula*: `(UB - LB) / max(1, |UB|)` is the documented relative gap and is
  computed consistently.

One Critical defect was found in the UB/incumbent bookkeeping of `solve_stackelberg!`,
plus five Warnings (solve ordering, non-exact compat pins contradicting their own
comment, missing finiteness validation on cut inputs, an untested production branch,
and a solver-version fragility in Farkas-ray availability under presolve).

## Critical Issues

### CR-01: `solve_stackelberg!` returns the last master iterate, not the incumbent that achieved `UB` — converged result can be suboptimal beyond `tol`

**File:** `src/planning/benders.jl:147-167`
**Issue:** `UB` is tracked as a running minimum
(`UB = min(UB, master.c_y * lb_res.y + follower_res.cost - oracle_res.cost)`), but the
`(y, z)` pair that achieved that minimum is never stored. On convergence the function
returns `y = lb_res.y, z = lb_res.z` from the **current** iteration `k`. When the
incumbent `UB` was set at an earlier iteration `j < k` and convergence triggers because
`LB` rose to meet that older `UB`, the returned point's true cost
`c_y·y_k + φ_x(z_k) - W(z_k)` can exceed `UB` — and the excess is **not** bounded by
`tol` (it equals the gap between the true cost-to-go at `z_k` and the cut
underestimates `α_op + α_x`, which is unbounded at a point whose cuts have not yet been
added). Two consequences:

1. The returned tuple is internally inconsistent: `UB` and `gap` certify the incumbent,
   while `y`/`z` describe a different, possibly worse point.
2. The docstring's contract — "`y` = the leader's **converged** investment" with a
   certified `gap ≤ tol` — is violated in reachable multi-iteration runs. The toy-fixture
   tests do not catch this because on that instance the final iterate coincides with the
   incumbent.

**Fix:**
```julia
UB = Inf
y_best = NaN
z_best = fill(NaN, T)
...
cost_k = master.c_y * lb_res.y + follower_res.cost - oracle_res.cost
if cost_k < UB
    UB = cost_k
    y_best = lb_res.y
    z_best = copy(lb_res.z)
end
gap = (UB - lb_res.LB) / max(1, abs(UB))
...
if gap <= tol
    return (; y = y_best, z = z_best, UB, LB = lb_res.LB, gap, iters = k,
              oracle, follower, master)
end
```
The incumbent is the certified point: `c(y_best, z_best) = UB ≤ LB + tol·max(1,|UB|)`
and `LB ≤ optimum`, so `c(y_best, z_best) - optimum ≤ tol·max(1,|UB|)` — exactly the
guarantee the docstring claims. (If the certification test's `result.y/z` comparisons
are meant to pin the *optimal* point, they should be asserted against the incumbent,
which this fix makes them.)

## Warnings

### WR-01: Oracle is solved before the follower feasibility check — wasted solve and a reachable crash the feasibility cut exists to prevent

**File:** `src/planning/benders.jl:125-129`
**Issue:** Each iteration calls `solve_planning_oracle!(oracle, lb_res.z)` **before**
`solve_follower!`. On a follower-infeasible trial `z_k`, `oracle_res` is computed and
then discarded (`continue` at line 138). Worse: the master's box allows
`z` up to `y_max` (8.0 on the fixture) while the follower can only deliver
`corridor_cap · x_inv_max` (4.0), so early iterations can propose a `z_k` far outside
the follower's feasible set. `solve_planning_oracle!` is documented (its own CR-03
comment) to be *more* fragile at pinned off-optimal `z` — the SOCP exactness gate and
battery-complementarity gate both throw. If the oracle's gates raise at an extreme
`z_k` that the follower would have vetoed, the whole loop crashes even though adding
the feasibility cut and continuing was the designed recovery path.
**Fix:** Reorder inside the loop — solve the follower first, take the
feasibility-cut/`continue` branch before ever touching the oracle:
```julia
follower_res = solve_follower!(follower, lb_res.z)
if !follower_res.feasible
    add_feasibility_cut!(...); checkpoint_iteration!(...); continue
end
oracle_res = solve_planning_oracle!(oracle, lb_res.z)
```

### WR-02: `test/Project.toml` compat entries are caret ranges, not the "EXACT version" pins the file's own comment claims

**File:** `test/Project.toml:16-27`
**Issue:** The comment states "pin an EXACT version for the new test-only BilevelJuMP
dependency, never a floating range", but Julia compat semantics make
`BilevelJuMP = "0.6.3"` a caret specifier: it permits any `0.6.x ≥ 0.6.3`. Likewise
`HiGHS = "1.24.1"` permits everything up to `< 2.0.0` and `Ipopt = "1.15.0"` up to
`< 2.0.0`. The stated supply-chain-integrity intent is not implemented — a future
`Pkg.update()` can silently float all three. This also compounds WR-05 (Farkas-ray
behavior verified only on the currently-resolved HiGHS build).
**Fix:** Use equality specifiers if exact pinning is the intent:
```toml
[compat]
BilevelJuMP = "= 0.6.3"
HiGHS = "= 1.24.1"
Ipopt = "= 1.15.0"
```
or amend the comment to state that caret-compat (plus the committed `test/Manifest.toml`)
is the actual pinning mechanism.

### WR-03: Cut appenders validate length but not finiteness — a NaN/Inf cut silently corrupts the persistent master

**File:** `src/planning/master.jl:145-176, 197-222` (and `src/planning/follower.jl:180-184`)
**Issue:** `add_optimality_cut!`/`add_feasibility_cut!` enforce the T-11-03 shape guard
("a malformed cut triple must fail loudly BEFORE corrupting the master's persistent
constraint set") for lengths only. A non-finite `cost_k`, `grad_k[t]`, `v_k`, or
`u_k[t]` passes straight into `@constraint`, permanently poisoning the build-once
master with an unremovable NaN/Inf row. `solve_follower!`'s docstring *promises* the
certificate values are "both `isfinite`", but nothing in production enforces it — only
the unit tests assert it, and the Benders loop feeds `follower_res.v/u` to the master
unchecked.
**Fix:** In both appenders:
```julia
isfinite(cost_k) || throw(ArgumentError("cost_k must be finite, got $cost_k"))
all(isfinite, grad_k) || throw(ArgumentError("grad_k contains a non-finite entry"))
```
(and the analogous `v_k`/`u_k` checks in `add_feasibility_cut!`), or enforce the
documented `isfinite` guarantee inside `solve_follower!`'s infeasible branch before
returning.

### WR-04: The production feasibility-cut branch of `solve_stackelberg!` is never exercised end-to-end by any test

**File:** `src/planning/benders.jl:131-139`; `test/test_planning_benders.jl`, `test/test_planning_certification.jl`
**Issue:** The Farkas branch is unit-tested in isolation (`test_planning_follower.jl`)
and `add_feasibility_cut!` row-growth is unit-tested (`test_planning_master.jl`), but
no test drives `solve_stackelberg!` through an infeasible follower trial. The
`continue`-without-`UB`-update path (T-11-06 — a design concern the file's own header
calls out), the `gap = NaN` checkpoint payload, and the interplay of feasibility
iterations with the `checkpoint_files == result.iters` invariant are all untested in
the production loop. On the sole end-to-end fixture, the master's first trial is
`z = 2.5 ≤ 4.0` (deliverable), so the branch is structurally unreachable in every
existing test.
**Fix:** Add a `@testitem` with a fixture whose master draws an undeliverable first
trial (e.g. lower `α_op_lb` so the zero-cut master proposes `z > corridor_cap · x_inv_max`,
or shrink `x_inv_max`), then assert: at least one `master.cuts` entry has
`kind == :feasibility`, the run still converges, and the checkpoint count equals
`result.iters`.

### WR-05: Follower's infeasible branch depends on HiGHS returning a Farkas ray with `presolve => "on"` — verified in this environment, but a solver-version-dependent behavior, not a contract

**File:** `src/planning/follower.jl:173-184`; `src/solver/factory.jl:42`
**Issue:** `select_optimizer(LP())` sets `"presolve" => "on"`. Farkas/dual-ray
availability when presolve concludes infeasibility is a HiGHS implementation detail:
historically HiGHS withholds the ray unless the model is solved by simplex, and the
common guidance for certificate extraction is to disable presolve. I verified by direct
execution that the currently resolved HiGHS build **does** return
`MOI.INFEASIBILITY_CERTIFICATE` with presolve on for both infeasible regimes of this
LP, so the code is correct today. But the failure mode on a HiGHS upgrade (see WR-02 —
compat allows floating to any `1.x`) is the loud `error(...)` branch of
`solve_follower!`, which aborts the entire Benders run at the exact moment a
feasibility cut was the designed recovery. PLAN-04's success criterion (a *genuine*
certificate on the infeasible branch) hinges on this unpinned behavior.
**Fix:** Make certificate availability deterministic for this small LP — e.g. build the
follower with presolve disabled (cost-free at this scale):
```julia
model = Model(select_optimizer(LP()))
set_optimizer_attribute(model, "presolve", "off")   # guarantee Farkas ray extraction
```
with a comment citing the certificate requirement, or add a documented one-shot
re-solve with presolve off inside the `else` branch when
`termination_status == MOI.INFEASIBLE` but no certificate is exposed.

## Info

### IN-01: Exhaustion error reports a stale `gap` when the final iterations took the feasibility branch

**File:** `src/planning/benders.jl:171-174`
**Issue:** The feasibility branch `continue`s before `gap` is recomputed, so the
"last gap=$gap" in the max-iter `error(...)` can name a gap from an arbitrarily older
optimality iteration (or `NaN` if no optimality iteration ever ran) as "last".
**Fix:** Track the iteration index at which `gap` was last computed and include it in
the message, or report `UB`/`LB` alongside.

### IN-02: `tol` is the one unchecked numeric input in the boundary guards

**File:** `src/planning/benders.jl:103-112`
**Issue:** `T`, `max_iter`, and `length(λ₀)` are guarded, but a `NaN` or negative `tol`
silently guarantees exhaustion (every `gap <= tol` comparison is false for NaN).
Fail-loud is preserved but the diagnosis is misleading ("exhausted 100 iterations").
**Fix:** `isfinite(tol) && tol > 0 || throw(ArgumentError(...))` alongside the other guards.

### IN-03: `max_iter` above 99999 throws deep in the loop instead of at the boundary guards

**File:** `src/planning/benders.jl:108-111`; `src/planning/checkpoint.jl:49-53`
**Issue:** `checkpoint_iteration!` enforces `iter ∈ 0:99999` (the 5-digit filename
contract), so `solve_stackelberg!(...; max_iter = 200_000)` would run 99,999 iterations
and then die inside `checkpoint_iteration!` — violating this file's own "fail here, not
deep in the loop" guard discipline.
**Fix:** Add `max_iter <= 99_999 || throw(ArgumentError(...))` to the guard block,
citing the checkpoint filename contract.

### IN-04: `solve_master!` requires duals it never reads

**File:** `src/planning/master.jl:238-241`
**Issue:** `solve_with_retry!(master.model; ..., dual = true)` gates the master solve
on dual availability, but `solve_master!` reads only primal values and the objective.
A solve with a clean primal but unavailable duals would be needlessly rejected.
**Fix:** Pass `dual = false` (or document why dual-status strictness is wanted on the
master too).

### IN-05: Certification test pins a HiGHS-version-specific failure status (`MOI.OTHER_ERROR`)

**File:** `test/test_planning_certification.jl:166-167`
**Issue:** The BigMMode negative regression asserts
`termination_status == MOI.OTHER_ERROR`, which encodes the exact way the current HiGHS
build reports "Cannot solve MIQP". A HiGHS upgrade that adds MIQP support or changes
the status code fails this test. Per the file's DEVIATION note this is an intentional
tripwire (so the finding is never silently rediscovered), so no change is required —
just be aware the failure will surface as a broken test rather than a documentation
note when HiGHS floats (see WR-02).
**Fix:** None required; optionally widen to
`termination_status(r_bigm.model) != MOI.OPTIMAL` with a comment if the tripwire intent
is "never silently certifies", not "pins this exact status".

---

_Reviewed: 2026-07-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
