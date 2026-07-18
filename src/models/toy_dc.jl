# src/models/toy_dc.jl
#
# SEAM: rung-0 walking-skeleton model (integration).
# OWNER: plan 01-04.
#
# When filled, this file will provide `solve_toy_dc(feeder)`: build a trivial
# single-node, single-period DC problem via `Model(select_optimizer(LP()))`
# (NEVER naming a solver here), route the nodal balance through the
# `ModelContext` residual registry, solve through `assert_solved!`, and return
# `(ctx, objective_value, dual(balance))`. This is the end-to-end proof that
# every seam connects. Declares its own exports.
#
# Intentionally empty in plan 01-01: the package must precompile with this stub.
