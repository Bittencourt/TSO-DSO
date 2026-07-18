# src/powerflow/LinDistFlow.jl
#
# SEAM: LinDistFlow (linear branch-flow) power-flow formulation (PF-02).
# OWNER: plan 02-02.
#
# An `AbstractPowerFlow` subtype implementing the dispatched `contribute!` contract:
# it writes the loss-less linear branch-flow terms — active AND reactive nodal
# balance plus the linear voltage-drop relation — into `ctx.residuals[:Rp]` and
# `ctx.residuals[:Rq]` via the indexed `add_to_residual!` seam (PF-02). Traces thesis
# eqs. 3.31–3.33 (nodal balances / branch flows) and the exactness copy 3.43 / 3.45
# (the LinDistFlow relaxation that later becomes the SOCP cone in Phase 4).
#
# Filled in wave 2 (plan 02-02) — comment-only stub for now.
