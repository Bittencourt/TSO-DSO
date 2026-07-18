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
    assert_solved!(model::Model; dual::Bool = true, allow_local::Bool = false)

Optimize `model` and assert the result is trustworthy. This is the single INFRA-03
choke point: it calls `optimize!` then `is_solved_and_feasible(model; dual, allow_local)`
and, on failure, raises loudly with the full status diagnostics
(`termination_status`, `primal_status`, `dual_status`, `raw_status`).

`allow_local=false` (the default) rejects `LOCALLY_SOLVED` — correct for the convex
core, where a local point is not acceptable (Pitfall 2). Pass `allow_local=true`
only on a deliberately nonconvex experiment rung. `dual=true` additionally requires
a feasible dual point (prices are duals). Returns `model` on success.
"""
function assert_solved!(model::Model; dual::Bool = true, allow_local::Bool = false)
    optimize!(model)
    if !is_solved_and_feasible(model; dual = dual, allow_local = allow_local)
        error(
            """
            Solve failed — refusing to trust results:
              termination_status : $(termination_status(model))
              primal_status      : $(primal_status(model))
              dual_status        : $(dual_status(model))
              raw_status         : $(raw_status(model))
            """,
        )
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
        error(
            """
            Hidden constraint slack detected — refusing to trust results:
              constraint : $(cref)
              lhs(value) : $(lhs)
              rhs        : $(rhs)
              residual   : $(residual)  (atol = $(atol))
            """,
        )
    end
    return residual
end

export assert_solved!, assert_no_slack
