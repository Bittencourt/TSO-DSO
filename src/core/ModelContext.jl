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
#   - `meta`        (per-unit base, feeder handle, config, and the welfare objective).
# Phase 1 uses it trivially (one balance residual); the shape must support Phases 2–7.
#
# TWO ACCUMULATOR FLAVORS (Phase-2 extension, PF-02 / RESEARCH Pattern 4):
#   1. AFFINE PRICE-BEARING RESIDUAL — the physical nodal balance is affine in the
#      decision variables (P, Q, v, p_load), so the residual accumulators stay
#      `AffExpr`. Phase 1 exposed a SCALAR `add_to_residual!(ctx, name, expr)`; Phase 2
#      ADDS an INDEXED `add_to_residual!(ctx, name, i, t, expr)` backed by a lazily
#      grown `Matrix{AffExpr}` (bus × time). The dual of the pinned residual is the
#      distribution price (DADP), so the value type is pinned to `AffExpr` — a
#      non-affine (quadratic) term routed here fails LOUDLY via `convert(AffExpr, ·)`.
#   2. QUADRATIC WELFARE OBJECTIVE — the concave-quadratic prosumer/aggregator utility
#      (thesis eq. 3.38, welfare shape `Σ U_ag − λ₀ᵀp₀`) is NOT affine and must NOT
#      flow through `add_to_residual!` (which would drop its curvature). It is
#      accumulated separately as a `QuadExpr` under `ctx.meta[:objective]` via
#      `add_to_objective!`. Keeping the residual strictly affine and the objective
#      quadratic is the load-bearing separation every downstream phase (3–7) reuses.

using JuMP

"""
    ModelContext

Mutable container coupling a JuMP `model` with three named registries:

- `constraints::Dict{Symbol,Any}` — constraint handles for later `dual()` / DADP access.
- `residuals::Dict{Symbol,Any}`   — `AffExpr` accumulators; the shared nodal-balance
  seam that power-flow formulations contribute into (PF-01/PF-02). Contributions ADD,
  never overwrite, so there is no `if formulation ==` branching anywhere. A residual
  is either a SCALAR `AffExpr` (Phase-1 rung-0 seam) or an INDEXED `Matrix{AffExpr}`
  (Phase-2 per-bus/time seam) — the physical balance is affine, so the value type is
  always `AffExpr`.
- `meta::Dict{Symbol,Any}`        — per-unit base, feeder handle, other config, and the
  quadratic welfare objective under `:objective` (a `QuadExpr`, see
  [`add_to_objective!`](@ref)).

Construct with [`ModelContext(model)`](@ref); populate via
[`register_constraint!`](@ref), [`add_to_residual!`](@ref) (affine residual), and
[`add_to_objective!`](@ref) (quadratic welfare).
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

"""
    add_to_residual!(ctx::ModelContext, name::Symbol, i::Int, t::Int, expr)

INDEXED variant (PF-02): ADD `expr` into cell `(i, t)` of the per-bus/per-time
residual `Matrix{AffExpr}` held under `ctx.residuals[name]`, lazily allocating and
growing the matrix as indices demand. New cells are initialized to `zero(AffExpr)`.
Sizing is derived from the indices ALONE — no `ctx.meta[:feeder]` is consulted, so the
network-agnostic device seam can accumulate before any feeder is attached.

The value type is pinned to `Matrix{AffExpr}`: `expr` is passed through
`convert(AffExpr, expr)`, so a quadratic term routed into the price-bearing residual
fails loudly (it belongs in [`add_to_objective!`](@ref) instead). Returns the updated
`(i, t)` cell.
"""
function add_to_residual!(ctx::ModelContext, name::Symbol, i::Int, t::Int, expr)
    M =
        (haskey(ctx.residuals, name) && ctx.residuals[name] isa Matrix{AffExpr}) ?
        ctx.residuals[name]::Matrix{AffExpr} : Matrix{AffExpr}(undef, 0, 0)
    nr, nc = size(M)
    if i > nr || t > nc
        newnr, newnc = max(nr, i), max(nc, t)
        M = AffExpr[
            (r <= nr && c <= nc) ? M[r, c] : zero(AffExpr) for r in 1:newnr, c in 1:newnc
        ]
    end
    M[i, t] += convert(AffExpr, expr)
    ctx.residuals[name] = M
    return M[i, t]
end

"""
    add_to_objective!(ctx::ModelContext, expr)

ADD `expr` into the shared welfare-objective accumulator `ctx.meta[:objective]`
(initialized to `zero(QuadExpr)` on first call), returning the updated accumulator.

This is the QUADRATIC-welfare counterpart of [`add_to_residual!`](@ref): the concave
prosumer/aggregator utility (thesis eq. 3.38) is a `QuadExpr` and must NOT be routed
through the affine residual (which would `convert(AffExpr, ·)` and drop its curvature).
Assembly reads it as, e.g., `@objective(m, Max, ctx.meta[:objective] − λ₀ᵀ·p_import)`.
Storing under `ctx.meta[:objective]` keeps `residuals` strictly affine/physical
(RESEARCH Open-Question Q1, resolved).
"""
function add_to_objective!(ctx::ModelContext, expr)
    ctx.meta[:objective] = get(ctx.meta, :objective, zero(QuadExpr)) + expr
    return ctx.meta[:objective]
end

export ModelContext, register_constraint!, add_to_residual!, add_to_objective!
