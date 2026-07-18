# src/powerflow/AbstractPowerFlow.jl
#
# SEAM: swappable power-flow interface contract (PF-01).
# OWNER: plan 01-03.
#
# The abstract type + `contribute!` contract only — concrete formulations (DC,
# LinDistFlow, SOCP Convex Branch Flow) land in Phases 2+. A formulation writes its
# branch/voltage terms into `ctx.residuals[:nodal_balance]` via `add_to_residual!`,
# so the framework never branches on `if formulation ==`.

"""
    AbstractPowerFlow

Abstract supertype for a swappable power-flow formulation. Concrete subtypes
(DC, LinDistFlow, SOCP Convex Branch Flow — Phases 2+) implement
[`contribute!`](@ref) to write their branch/voltage terms into the shared
nodal-balance residual held by a `ModelContext`. This is the PF-01 seam that lets
the solve model swap formulations without any `if formulation ==` branching.
"""
abstract type AbstractPowerFlow end

"""
    contribute!(pf::AbstractPowerFlow, ctx, feeder)

Contract (stub in Phase 1): a formulation `pf` adds its branch/voltage terms into
`ctx.residuals[:nodal_balance]` (via `add_to_residual!`) for the given `feeder`.
Concrete methods are defined by the formulations in Phases 2+.
"""
function contribute! end

export AbstractPowerFlow, contribute!
