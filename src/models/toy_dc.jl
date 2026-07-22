# src/models/toy_dc.jl
#
# SEAM: rung-0 walking-skeleton model (integration).
# OWNER: plan 01-04.
#
# The end-to-end proof that every architectural seam connects: a trivial
# single-node, single-period DC problem built via `Model(select_optimizer(LP()))`
# (INFRA-02 — this file NEVER names a concrete solver), routed through the
# `ModelContext` residual registry (PF-01), solved through the `assert_solved!`
# status choke point (INFRA-03), and returning the objective plus the
# nodal-balance dual (the price seam consumed from Phase 5 onward).
#
# Rung 0 is strictly single-node (RESEARCH Open-Question 2, RESOLVED), yet the
# nodal balance is STILL routed through `ctx.residuals[:nodal_balance]` so the
# PF-01 accumulation seam is exercised even at the simplest rung — Phase 2 swaps
# in a real branch-flow contribution without touching this call site.

using JuMP

"""
    solve_toy_dc(feeder::Feeder) -> (ctx::ModelContext, objective::Float64, price::Float64)

Build and solve the rung-0 toy DC problem for `feeder`, exercising the full
walking-skeleton spine:

 1. build `Model(select_optimizer(LP()))` — the solver is chosen by problem class
    only (INFRA-02); no concrete solver is named here;
 2. wrap it in a [`ModelContext`](@ref) and stash the `feeder` in `ctx.meta`;
 3. add a trivial servable load `p_load` and frontier import `p_import` (per-unit);
 4. write the nodal balance `p_import - p_load` into the shared residual registry
    via [`add_to_residual!`](@ref) (`:nodal_balance`, the PF-01 seam) and pin it to
    zero with an equality constraint registered under `:balance`
    (via [`register_constraint!`](@ref)) so its dual is recoverable;
 5. maximise the toy welfare `3·p_load - 1·p_import`;
 6. solve through [`assert_solved!`](@ref)`(...; dual = true, allow_local = false)`
    (INFRA-03) — the function returns only on a trustworthy optimal+feasible solve.

Returns the populated `ctx`, the optimal `objective_value`, and `dual(balance)` —
the nodal-balance dual that becomes the distribution price (DADP) in later phases.
"""
function solve_toy_dc(feeder::Feeder)
    model = Model(select_optimizer(LP()))       # factory — NO solver named here (INFRA-02)
    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder

    @variable(model, p_import >= 0)              # power drawn from the frontier node (pu)
    @variable(model, 0 <= p_load <= 1.0)         # trivial servable load (pu)

    # Route the nodal balance through the SHARED residual registry (PF-01) even at
    # rung 0: contributions ADD into `:nodal_balance`, so a Phase-2 branch-flow
    # formulation contributes here with no `if formulation ==` branching. The
    # equality constraint pins the accumulated residual to zero.
    add_to_residual!(ctx, :nodal_balance, p_import - p_load)
    balance = @constraint(model, ctx.residuals[:nodal_balance] == 0)   # nodal balance
    register_constraint!(ctx, :balance, balance)

    @objective(model, Max, 3.0 * p_load - 1.0 * p_import)  # toy welfare

    assert_solved!(model; dual = true, allow_local = false)  # INFRA-03 choke point

    return ctx, objective_value(model), dual(balance)        # dual ready for Phase 5
end

# --- Parameter pattern (wired-but-unused; for Phase 6 ADMM re-solves) -----------
# JuMP native `Parameter`s let the ADMM/Benders outer loops update price/penalty
# terms and re-solve WITHOUT rebuilding the model (RESEARCH §Parameter pattern,
# Pitfall: "rebuilding the JuMP model to change data"). Left commented here as the
# canonical shape Phase 6 will adopt inside `solve_toy_dc`-style builders:
#
#     @variable(model, ρ in Parameter(1.0))    # penalty / price parameter
#     # ... between re-solves, no rebuild:
#     set_parameter_value(ρ, new_value)
#     optimize!(model)

export solve_toy_dc
