# src/models/toy_dc.jl
#
# SEAM: rung-0 walking-skeleton model (integration).
#
# The end-to-end proof that every architectural seam connects: a trivial
# single-node, single-period DC problem built via `Model(select_optimizer(LP()))`
# (this file NEVER names a concrete solver), routed through the
# `ModelContext` residual registry, solved through the `assert_solved!`
# status choke point, and returning the objective plus the
# nodal-balance dual (the price seam consumed by the pricing layer).
#
# Rung 0 is strictly single-node (by design), yet the
# nodal balance is STILL routed through `ctx.residuals[:nodal_balance]` so the
# accumulation seam is exercised even at the simplest rung — a later rung swaps
# in a real branch-flow contribution without touching this call site.

using JuMP

"""
    solve_toy_dc(feeder::Feeder) -> (ctx::ModelContext, objective::Float64, price::Float64)

Build and solve the rung-0 toy DC problem for `feeder`, exercising the full
walking-skeleton spine:

 1. build `Model(select_optimizer(LP()))` — the solver is chosen by problem class
    only; no concrete solver is named here;
 2. wrap it in a [`ModelContext`](@ref) and stash the `feeder` in `ctx.meta`;
 3. add a trivial servable load `p_load` and frontier import `p_import` (per-unit);
 4. write the nodal balance `p_import - p_load` into the shared residual registry
    via [`add_to_residual!`](@ref) (`:nodal_balance`, the seam) and pin it to
    zero with an equality constraint registered under `:balance`
    (via [`register_constraint!`](@ref)) so its dual is recoverable;
 5. maximise the toy welfare `3·p_load - 1·p_import`;
 6. solve through [`assert_solved!`](@ref)`(...; dual = true, allow_local = false)`
    — the function returns only on a trustworthy optimal+feasible solve.

Returns the populated `ctx`, the optimal `objective_value`, and `dual(balance)` —
the nodal-balance dual that becomes the distribution price (DADP) in later phases.
"""
function solve_toy_dc(feeder::AbstractFeeder)
    model = Model(select_optimizer(LP()))       # factory — NO solver named here
    ctx = ModelContext(model)
    ctx.feeder = feeder

    @variable(model, p_import >= 0)              # power drawn from the frontier node (pu)
    @variable(model, 0 <= p_load <= 1.0)         # trivial servable load (pu)

    # Route the nodal balance through the SHARED residual registry even at
    # rung 0: contributions ADD into `:nodal_balance`, so a branch-flow
    # formulation contributes here with no `if formulation ==` branching. The
    # equality constraint pins the accumulated residual to zero.
    add_to_residual!(ctx, :nodal_balance, p_import - p_load)
    balance = @constraint(model, ctx.residuals[:nodal_balance] == 0)   # nodal balance
    register_constraint!(ctx, :balance, balance)

    @objective(model, Max, 3.0 * p_load - 1.0 * p_import)  # toy welfare

    assert_solved!(model; dual = true, allow_local = false)  # choke point

    return ctx, objective_value(model), dual(balance)        # dual ready for pricing
end

# --- Parameter pattern (wired-but-unused; for ADMM re-solves) -----------
# JuMP native `Parameter`s let the ADMM/Benders outer loops update price/penalty
# terms and re-solve WITHOUT rebuilding the model (avoiding the
# "rebuilding the JuMP model to change data" pitfall). Left commented here as the
# canonical shape the ADMM layer adopts inside `solve_toy_dc`-style builders:
#
#     @variable(model, ρ in Parameter(1.0))    # penalty / price parameter
#     # ... between re-solves, no rebuild:
#     set_parameter_value(ρ, new_value)
#     optimize!(model)

export solve_toy_dc
