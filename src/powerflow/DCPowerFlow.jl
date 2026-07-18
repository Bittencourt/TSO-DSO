# src/powerflow/DCPowerFlow.jl
#
# SEAM: DC (active-only) power-flow formulation (PF-02).
# OWNER: plan 02-02.
#
# An `AbstractPowerFlow` subtype implementing the dispatched `contribute!` contract:
# it writes the active-power branch terms of a loss-less DC linearization into the
# per-bus/per-time residual `ctx.residuals[:Rp]` via the indexed `add_to_residual!`
# seam (PF-02) — NO reactive channel, NO voltage magnitudes. This is the simplest
# linear rung; swapping it for `LinDistFlow` must touch neither device nor assembly
# code (the conformance criterion).
#
# Filled in wave 2 (plan 02-02) — comment-only stub for now.
