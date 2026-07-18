# src/models/linear_solve.jl
#
# SEAM: rung-1 linear central-assembly model (integration).
# OWNER: plan 02-04.
#
# The rung-1 counterpart of `models/toy_dc.jl`: builds a `ModelContext`, lets a chosen
# `AbstractPowerFlow` (DC or LinDistFlow) and the feeder's devices each `contribute!`
# into the SHARED residual / welfare accumulators with no `if formulation ==`
# branching, pins the per-bus/time nodal balance to zero (registering the constraint so
# its dual — the distribution price / DADP — is recoverable), sets the welfare
# objective from `ctx.meta[:objective]` minus the priced frontier import, and solves as
# `QP()`→Clarabel through `assert_solved!(...; dual = true)`. Central, single-solve
# assembly; the ADMM decomposition lands in Phase 6.
#
# Filled in wave 3 (plan 02-04) — comment-only stub for now.
