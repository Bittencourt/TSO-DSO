# src/core/status.jl
#
# SEAM: solve-status discipline (INFRA-03).
# OWNER: plan 01-03.
#
# The SINGLE choke point wrapping `optimize!`. It delegates to JuMP's built-in
# `is_solved_and_feasible(model; dual, allow_local=false)` — the modern idiom that
# SUPERSEDES hand-checking `termination_status == OPTIMAL` (it also checks
# primal/dual status). On failure it errors loudly with full diagnostics. A
# companion `assert_no_slack` recomputes a constraint's LHS to catch a solver
# reporting OPTIMAL while silently violating a constraint within loose tolerance.

using JuMP

"""
    assert_solved!(model::Model; dual::Bool = true, allow_local::Bool = false,
                   allow_almost::Bool = false)

Optimize `model` and assert the result is trustworthy. This is the single INFRA-03
choke point: it calls `optimize!` then `is_solved_and_feasible(model; dual, allow_local)`
and, on failure, raises loudly with the full status diagnostics
(`termination_status`, `primal_status`, `dual_status`, `raw_status`).

`allow_local=false` (the default) rejects `LOCALLY_SOLVED` — correct for the convex
core, where a local point is not acceptable (Pitfall 2). Pass `allow_local=true`
only on a deliberately nonconvex experiment rung. `dual=true` additionally requires
a feasible dual point (prices are duals). Returns `model` on success.

`allow_almost=false` (the default) rejects `ALMOST_OPTIMAL` / `NEARLY_FEASIBLE_POINT`.
Pass `allow_almost=true` ONLY for an intermediate re-solve whose DUALS are NOT read and
whose PRIMAL only needs to be near-feasible — e.g. a mid-loop ADMM subproblem, where the
interior-point conic backend may stop just shy of its (deliberately tight, centralized-grade)
gap tolerance under the ρ-penalty, and the outer residual loop self-corrects (RESEARCH
Pitfall 2/4). It accepts `termination_status ∈ {OPTIMAL, ALMOST_OPTIMAL}` with
`primal_status ∈ {FEASIBLE_POINT, NEARLY_FEASIBLE_POINT}`. The FINAL/converged solve must
still use the STRICT gate (`allow_almost=false`) so no near-feasible price is ever published.
"""
function assert_solved!(
    model::Model;
    dual::Bool = true,
    allow_local::Bool = false,
    allow_almost::Bool = false,
)
    optimize!(model)
    ok = is_solved_and_feasible(model; dual = dual, allow_local = allow_local)
    if !ok && allow_almost
        ts = termination_status(model)
        ps = primal_status(model)
        # Primal-only near-feasibility (duals intentionally NOT required here — the caller
        # reads only the primal at this intermediate solve). NEARLY_* covers the interior-point
        # "stopped just short of the tight gap" case that is benign for an ADMM inner solve.
        ok =
            (ts == MOI.OPTIMAL || ts == MOI.ALMOST_OPTIMAL) &&
            (ps == MOI.FEASIBLE_POINT || ps == MOI.NEARLY_FEASIBLE_POINT)
    end
    if !ok
        error("""
              Solve failed — refusing to trust results:
                termination_status : $(termination_status(model))
                primal_status      : $(primal_status(model))
                dual_status        : $(dual_status(model))
                raw_status         : $(raw_status(model))
              """)
    end
    return model
end

"""
    assert_no_slack(model::Model, cref; atol::Real = 1e-6)

Hidden-slack guard: recompute the left-hand side of an equality constraint `cref`
from the solved variable values and assert it matches the constraint's right-hand
side within `atol`. This catches a solver reporting `OPTIMAL` while silently
violating the constraint within its loose feasibility tolerance (INFRA-03).

`cref` must reference a scalar equality constraint. Errors with the observed LHS,
RHS, and residual on violation. Returns the (signed) residual `lhs - rhs` on success.
"""
function assert_no_slack(model::Model, cref; atol::Real = 1e-6)
    obj = constraint_object(cref)
    lhs = value(obj.func)                 # AffExpr evaluated at the solution
    rhs = MOI.constant(obj.set)           # RHS for EqualTo / scalar sets
    residual = lhs - rhs
    if abs(residual) > atol
        error("""
              Hidden constraint slack detected — refusing to trust results:
                constraint : $(cref)
                lhs(value) : $(lhs)
                rhs        : $(rhs)
                residual   : $(residual)  (atol = $(atol))
              """)
    end
    return residual
end

export assert_solved!, assert_no_slack
