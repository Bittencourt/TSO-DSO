# src/powerflow/AbstractPowerFlow.jl
#
# SEAM: swappable power-flow interface contract (PF-01).
# OWNER: plan 01-03.
#
# The abstract type + `contribute!` contract only — concrete formulations (DC,
# LinDistFlow, SOCP Convex Branch Flow) land in Phases 2+. A formulation writes its
# per-bus/time branch/voltage terms into `ctx.residuals[:Rp]` (and `:Rq` for
# reactive-capable formulations) via the indexed `add_to_residual!`, so the framework
# never branches on `if formulation ==`.

"""
    AbstractPowerFlow

Abstract supertype for a swappable power-flow formulation. Concrete subtypes
(DC, LinDistFlow, SOCP Convex Branch Flow — Phases 2+) implement
[`contribute!`](@ref) to write their per-bus/time branch/voltage terms into the shared
nodal-balance residual held by a `ModelContext`. This is the PF-01/PF-02 seam that lets
the solve model swap formulations without any `if formulation ==` branching.
"""
abstract type AbstractPowerFlow end

"""
    contribute!(pf::AbstractPowerFlow, ctx, feeder; T::Int=1)

Contract (concrete methods land in Phase 2): a formulation `pf` adds its per-bus,
per-time branch/voltage terms into `ctx.residuals[:Rp]` — and, for reactive-capable
formulations (e.g. LinDistFlow), `ctx.residuals[:Rq]` — via the INDEXED
`add_to_residual!(ctx, :Rp, bus, t, expr)` seam, over the horizon `t = 1:T`. Active-only
formulations (e.g. DC) write `:Rp` alone and never allocate `:Rq`; assembly keys off
`haskey(ctx.residuals, :Rq)` (registry contents, not a formulation flag), so swapping DC
↔ LinDistFlow touches neither device nor assembly code.
"""
function contribute! end

export AbstractPowerFlow, contribute!
