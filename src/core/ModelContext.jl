# src/core/ModelContext.jl
#
# SEAM: model context + residual registry (PF-01).
# OWNER: plan 01-03.
#
# The mutable `ModelContext` owns the JuMP `Model` plus named registries:
#   - `constraints` (name → ConstraintRef / array, for later `dual()` / DADP access),
#   - `residuals`   (name → AffExpr accumulator — the SHARED nodal-balance seam that
#                    `AbstractPowerFlow` formulations write into with no
#                    `if formulation ==` branching),
#   - `meta`        (per-unit base, feeder handle, config).
# Phase 1 uses it trivially (one balance residual); the shape must support Phases 2–7.

using JuMP

"""
    ModelContext

Mutable container coupling a JuMP `model` with three named registries:

- `constraints::Dict{Symbol,Any}` — constraint handles for later `dual()` / DADP access.
- `residuals::Dict{Symbol,Any}`   — `AffExpr` accumulators; the shared nodal-balance
  seam that power-flow formulations contribute into (PF-01). Contributions ADD,
  never overwrite, so there is no `if formulation ==` branching anywhere.
- `meta::Dict{Symbol,Any}`        — per-unit base, feeder handle, and other config.

Construct with [`ModelContext(model)`](@ref); populate via
[`register_constraint!`](@ref) and [`add_to_residual!`](@ref).
"""
mutable struct ModelContext
    model::Model
    constraints::Dict{Symbol,Any}
    residuals::Dict{Symbol,Any}
    meta::Dict{Symbol,Any}
end

"""
    ModelContext(model::Model)

Construct a `ModelContext` wrapping `model` with empty constraint, residual, and
meta registries.
"""
ModelContext(model::Model) =
    ModelContext(model, Dict{Symbol,Any}(), Dict{Symbol,Any}(), Dict{Symbol,Any}())

"""
    register_constraint!(ctx::ModelContext, name::Symbol, cref)

Register a constraint handle (or array of handles) under `name` so any later layer
can recover its dual (e.g. `dual(ctx.constraints[:balance])` — the future DADP).
Returns `cref`.
"""
function register_constraint!(ctx::ModelContext, name::Symbol, cref)
    ctx.constraints[name] = cref
    return cref
end

"""
    add_to_residual!(ctx::ModelContext, name::Symbol, expr)

ADD `expr` into the shared residual accumulator `ctx.residuals[name]` (creating it
on first call). This is the PF-01 no-branching seam: every power-flow formulation
contributes its branch/voltage terms into one shared nodal-balance expression by
accumulation, never overwriting. Returns the updated accumulator.
"""
function add_to_residual!(ctx::ModelContext, name::Symbol, expr)
    ctx.residuals[name] =
        haskey(ctx.residuals, name) ? ctx.residuals[name] + expr : convert(AffExpr, expr)
    return ctx.residuals[name]
end

export ModelContext, register_constraint!, add_to_residual!
