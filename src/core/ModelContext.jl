# src/core/ModelContext.jl
#
# SEAM: model context + residual registry.
#
# The mutable `ModelContext` owns the JuMP `Model` plus named registries:
#   - `constraints` (name → ConstraintRef / array, for later `dual()` / DADP access),
#   - `residuals`   (name → AffExpr accumulator — the SHARED nodal-balance seam that
#                    `AbstractPowerFlow` formulations write into with no
#                    `if formulation ==` branching),
#   - `meta`        (experiment/result-specific keys; builder state lives in typed fields).
# The simplest use is one balance residual; the shape must also support indexed per-bus/time
# residuals and the later layers.
#
# TWO ACCUMULATOR FLAVORS:
#   1. AFFINE PRICE-BEARING RESIDUAL — the physical nodal balance is affine in the
#      decision variables (P, Q, v, p_load), so the residual accumulators stay
#      `AffExpr`. A SCALAR `add_to_residual!(ctx, name, expr)` is exposed, and an
#      INDEXED `add_to_residual!(ctx, name, i, t, expr)` backed by a lazily
#      grown `Matrix{AffExpr}` (bus × time). The dual of the pinned residual is the
#      distribution price (DADP), so the value type is pinned to `AffExpr` — a
#      non-affine (quadratic) term routed here fails LOUDLY via `convert(AffExpr, ·)`.
#   2. QUADRATIC WELFARE OBJECTIVE — the concave-quadratic prosumer/aggregator utility
#      (thesis eq. 3.38, welfare shape `Σ U_ag − λ₀ᵀp₀`) is NOT affine and must NOT
#      flow through `add_to_residual!` (which would drop its curvature). It is
#      accumulated separately as a `QuadExpr` in `ctx.objective` via
#      `add_to_objective!`. Keeping the residual strictly affine and the objective
#      quadratic is the load-bearing separation every downstream layer reuses.

using JuMP

"""
    ModelContext

Mutable container coupling a JuMP `model` with named registries and typed builder state:

  - `constraints::Dict{Symbol,Any}` — constraint handles for later `dual()` / DADP access.
  - `residuals::Dict{Symbol,Any}`   — `AffExpr` accumulators; the shared nodal-balance
    seam that power-flow formulations contribute into. Contributions ADD,
    never overwrite, so there is no `if formulation ==` branching anywhere. A residual
    is either a SCALAR `AffExpr` (rung-0 seam) or an INDEXED `Matrix{AffExpr}`
    (per-bus/time seam) — the physical balance is affine, so the value type is
    always `AffExpr`.
  - `meta::Dict{Symbol,Any}`        — experiment/result-specific keys only (`p_import`,
    `q_import`, `socp_maxgap`, `price_provenance`, `qag_dso`, `problem_class`,
    `formulation`, `device_vars`, ...).
  - `feeder::Union{Nothing,AbstractFeeder}` — the feeder handle (`nothing` until set).
  - `T::Int` — the horizon length (`0` = unset).
  - `pf::Union{Nothing,AbstractPowerFlow}` — the formulation that last contributed.
  - `pf_vars::Union{Nothing,NamedTuple}` — the formulation's flow/voltage variables
    (`nothing` for DC, which defines none).
  - `objective::QuadExpr` — the quadratic welfare accumulator, see
    [`add_to_objective!`](@ref).
  - `agg_device_vars::Dict{Int,Vector{Any}}` — per-aggregator-bus device variable lists.

The struct is deliberately NOT parametric: it is filled incrementally. Unset reads of
`T`/`feeder`/`pf_vars` must go through the checked accessors `_require_T`,
`_require_feeder`, `_require_pf_vars`, which throw rather than default silently.

Construct with [`ModelContext(model)`](@ref); populate via
[`register_constraint!`](@ref), [`add_to_residual!`](@ref) (affine residual), and
[`add_to_objective!`](@ref) (quadratic welfare).
"""
mutable struct ModelContext
    model::Model
    constraints::Dict{Symbol, Any}
    residuals::Dict{Symbol, Any}
    meta::Dict{Symbol, Any}
    feeder::Union{Nothing, AbstractFeeder}
    T::Int
    pf::Union{Nothing, AbstractPowerFlow}
    pf_vars::Union{Nothing, NamedTuple}
    objective::QuadExpr
    agg_device_vars::Dict{Int, Vector{Any}}
end

"""
    ModelContext(model::Model)

Construct a `ModelContext` wrapping `model` with empty registries, `feeder === nothing`,
`T == 0`, `pf === nothing`, `pf_vars === nothing`, a zero objective and no aggregator
device variables.
"""
ModelContext(model::Model) = ModelContext(
    model,
    Dict{Symbol, Any}(),
    Dict{Symbol, Any}(),
    Dict{Symbol, Any}(),
    nothing,
    0,
    nothing,
    nothing,
    zero(QuadExpr),
    Dict{Int, Vector{Any}}(),
)

# Checked accessors: unset state fails loudly instead of defaulting silently.
function _require_T(ctx::ModelContext)
    ctx.T <= 0 && throw(
        ArgumentError(
            "ModelContext.T is unset or non-positive ($(ctx.T)); the builder must set ctx.T",
        ),
    )
    return ctx.T
end

function _require_feeder(ctx::ModelContext)
    ctx.feeder === nothing && throw(
        ArgumentError("ModelContext.feeder is unset; the builder must set ctx.feeder"),
    )
    return ctx.feeder
end

function _require_pf_vars(ctx::ModelContext)
    ctx.pf_vars === nothing && throw(
        ArgumentError(
            "ModelContext.pf_vars is unset; no power-flow formulation has stashed variables (DCPowerFlow defines none)",
        ),
    )
    return ctx.pf_vars
end

"""
    has_branch_current(ctx::ModelContext) -> Bool

Consistency-guarded gate for the SOCP exactness certificate. Returns
`has_branch_current(ctx.pf)` but first checks it against the data (`ctx.pf_vars` carries a
branch-current `l`); a disagreement (a formulation that stashes `l` without implementing the
trait, or `pf_vars` populated without `ctx.pf`) throws `ArgumentError` instead of silently
skipping the exactness gate.
"""
function has_branch_current(ctx::ModelContext)
    declared = has_branch_current(ctx.pf)
    pfv = ctx.pf_vars
    actual = pfv !== nothing && haskey(pfv, :l)
    declared == actual || throw(
        ArgumentError(
            "ModelContext: has_branch_current($(typeof(ctx.pf))) = $declared but pf_vars " *
            "$(actual ? "carries" : "has no") branch current :l — implement " *
            "`has_branch_current` for this formulation (and set ctx.pf in contribute!)",
        ),
    )
    return declared
end

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
on first call). This is the no-branching seam: every power-flow formulation
contributes its branch/voltage terms into one shared nodal-balance expression by
accumulation, never overwriting. Returns the updated accumulator.
"""
function add_to_residual!(ctx::ModelContext, name::Symbol, expr)
    # A scalar accumulation must not silently collide with an INDEXED one of the
    # same name. If `name` already holds a `Matrix{AffExpr}`, adding a scalar `AffExpr`
    # would either error obscurely or (worse) corrupt the per-bus/time balance — reject
    # the accumulator-kind mismatch loudly instead.
    if haskey(ctx.residuals, name) && ctx.residuals[name] isa Matrix{AffExpr}
        error(
            "residual :$name already holds an indexed matrix accumulator; " *
            "refusing to add a scalar contribution to it",
        )
    end
    ctx.residuals[name] =
        haskey(ctx.residuals, name) ? ctx.residuals[name] + expr : convert(AffExpr, expr)
    return ctx.residuals[name]
end

"""
    add_to_residual!(ctx::ModelContext, name::Symbol, i::Int, t::Int, expr)

INDEXED variant: ADD `expr` into cell `(i, t)` of the per-bus/per-time
residual `Matrix{AffExpr}` held under `ctx.residuals[name]`, lazily allocating and
growing the matrix as indices demand. New cells are initialized to `zero(AffExpr)`.
Sizing is derived from the indices ALONE — no `ctx.feeder` is consulted, so the
network-agnostic device seam can accumulate before any feeder is attached.

The value type is pinned to `Matrix{AffExpr}`: `expr` is passed through
`convert(AffExpr, expr)`, so a quadratic term routed into the price-bearing residual
fails loudly (it belongs in [`add_to_objective!`](@ref) instead). Returns the updated
`(i, t)` cell.
"""
function add_to_residual!(ctx::ModelContext, name::Symbol, i::Int, t::Int, expr)
    # Refuse to silently overwrite a pre-existing SCALAR accumulator of the same
    # name. Previously a non-matrix value under `name` was discarded (a fresh 0×0 matrix
    # replaced it), losing the scalar contribution without warning — exactly the kind of
    # silent balance corruption this seam must never allow.
    if haskey(ctx.residuals, name) && !(ctx.residuals[name] isa Matrix{AffExpr})
        error(
            "residual :$name already holds a scalar accumulator; " *
            "refusing to convert it to an indexed matrix",
        )
    end
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

ADD `expr` into the shared welfare-objective accumulator `ctx.objective` (initially
`zero(QuadExpr)`), returning the updated accumulator.

This is the QUADRATIC-welfare counterpart of [`add_to_residual!`](@ref): the concave
prosumer/aggregator utility (thesis eq. 3.38) is a `QuadExpr` and must NOT be routed
through the affine residual (which would `convert(AffExpr, ·)` and drop its curvature).
Assembly reads it as, e.g., `@objective(m, Max, ctx.objective − λ₀ᵀ·p_import)`.
Keeping it in its own typed field keeps `residuals` strictly affine/physical.
"""
function add_to_objective!(ctx::ModelContext, expr)
    ctx.objective = ctx.objective + expr
    return ctx.objective
end

export ModelContext, register_constraint!, add_to_residual!, add_to_objective!
