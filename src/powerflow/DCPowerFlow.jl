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
# code (the conformance criterion). Selection is PURELY by Julia dispatch on the
# singleton type `DCPowerFlow` — no formulation-flag branching anywhere.

using JuMP

"""
    DCPowerFlow <: AbstractPowerFlow

Active-power-only linear power-flow formulation. As a loss-less linearization it keeps
just the branch active-flow variables `P[b,t]` and contributes the per-bus active
balance — thesis eq. 3.31 with the loss/current terms dropped — into the shared
`ctx.residuals[:Rp]` accumulator. It allocates NO reactive residual `:Rq` and NO
squared-voltage variable, so a downstream assembly keying off `haskey(ctx.residuals, :Rq)`
naturally closes only the active balance for DC (registry contents, never a formulation
flag). Contrast with [`LinDistFlow`](@ref), which adds `:Rq` and the squared-voltage drop.
"""
struct DCPowerFlow <: AbstractPowerFlow end

"""
    contribute!(::DCPowerFlow, ctx::ModelContext, feeder; T::Int=1)

Write the DC (active-only) branch terms into the shared per-bus/per-time residual.

For each branch `b` a signed active flow variable `P[b,t]` is created (parent→child,
`t = 1:T`). For each bus `j` and time `t` the net active injection

    R_p,j,t = (Σ P[b,t] over branches with br.to == j)      # inflow
            − (Σ P[b,t] over branches with br.from == j)     # outflow

is accumulated into `ctx.residuals[:Rp]` via the INDEXED `add_to_residual!`
(thesis eq. 3.31, loss-less: the `r·l`/`x·l` current-loss terms are dropped). DC has no
reactive channel and no voltage magnitudes, so `:Rq` and any voltage variable are never
allocated. Returns `ctx`.
"""
function contribute!(::DCPowerFlow, ctx::ModelContext, feeder; T::Int = 1)
    m = ctx.model
    B = feeder.branches
    N = length(feeder.buses)

    # Branch active flows P[b,t], parent→child (thesis 3.31 flow variable, DC subset).
    @variable(m, P[b = 1:length(B), t = 1:T])

    # Per-bus active balance: inflow − outflow, accumulated into the shared :Rp
    # (thesis 3.31, loss-less). ONLY :Rp — DC carries no reactive/voltage terms.
    for j in 1:N, t in 1:T
        inflow = sum(P[b, t] for (b, br) in enumerate(B) if br.to == j; init = 0.0)
        outflow = sum(P[b, t] for (b, br) in enumerate(B) if br.from == j; init = 0.0)
        add_to_residual!(ctx, :Rp, j, t, inflow - outflow)
    end
    return ctx
end

export DCPowerFlow
