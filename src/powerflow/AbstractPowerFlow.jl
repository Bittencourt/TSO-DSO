# src/powerflow/AbstractPowerFlow.jl
#
# SEAM: swappable power-flow interface contract (PF-01).
# OWNER: plan 01-03.
#
# When filled, this file will provide the abstract type `AbstractPowerFlow` and
# the `contribute!(pf, ctx, feeder)` contract: a formulation writes its branch/
# voltage terms into `ctx.residuals[:nodal_balance]` so the framework never
# branches on `if formulation ==`. Concrete formulations (DC, LinDistFlow, SOCP
# Convex Branch Flow) land in Phases 2+. Declares its own exports.
#
# Intentionally empty in plan 01-01: the package must precompile with this stub.
