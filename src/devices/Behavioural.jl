# src/devices/Behavioural.jl
#
# SEAM: exogenous, seeded behavioural scenarios expressed as WRAPPER devices (phase 44, ACTOR-04).
#
# WHY THIS FILE EXISTS: a behavioural scenario ("only a share xi of prosumers respond to the price
# signal", "a share opts out", "curtailed energy is recovered afterwards") is a property of how a
# device's realised injection relates to its no-response BASELINE. It is modelled here as three
# transparent wrappers around an existing aggregatable device. Nothing changes inside the solves:
# every wrapper satisfies the ordinary `contribute!` contract (`(; vars, p_inject, utility)`,
# nothing written to `ctx.residuals` / `ctx.objective`, anonymous JuMP objects, ZERO binaries).
# The baseline `b` (a per-device vector) and its utility `Ub` are computed ONCE at population
# transform time (see `apply_behaviour` / `_device_baseline` in experiments/materialize.jl) and
# stored in the wrapper; contribute! never solves anything.
#
# THE MATH (assumption A2 -- expectation interpretation):
#   PartialCompliance(inner, xi, b, Ub):  p' = b + xi (p - b),   U' = (1 - xi) Ub + xi U(p)
#   OptOut(inner, b, Ub):                 p' = b,                U' = Ub          (the xi = 0 case)
# Both are the EXACT expectation over a population in which a fraction xi of identical devices
# responds to the price while the remaining (1 - xi) keep their baseline schedule: injection and
# utility are linear in the responding share, so the blended device IS the expected device. For a
# single physical device it is an interpretation, not a physical statement.
#   Rebound(inner, b, W, r):  curtailment u_t >= 0, u_t >= c^b_t - c_t   (c = -p_inject consumption)
#                             sum_{tau=t+1}^{min(t+W,T)} (c_tau - c^b_tau) >= r u_t,   r >= 1
# i.e. curtailed energy must be recovered within the next W hours (window clipped at the horizon,
# no wrap). The baseline p = b gives u = 0, so the wrapper never makes a feasible device infeasible.
#
# TRAITS: wrappers forward `is_flexible_load`, `has_reactive_decision` and the type-level
# `storage_kind` of the inner device (OptOut is `:none`: a constant has no storage dynamics), and
# EXPOSE the inner `phi` field (Aggregator reads `hasproperty(d, :phi) && d.phi !== nothing`).
# The FIT / MPC / stochastic entries have no model for wrapped devices and reject them
# (`_reject_unsupported_flex_devices`).
#
# STACK ORDER: Rebound(PartialCompliance(inner)). Wrapping is scoped to active-only devices without
# `q_inject`; FourQuadBESS, SmartInverterPV and FixedCapacitor are rejected at wrap time.

using JuMP

# Devices that carry a reactive decision / constant q_inject: not wrappable (active-only scope).
_beh_unwrappable(d) = d isa Union{FourQuadBESS, SmartInverterPV, FixedCapacitor}

function _beh_check_inner(inner, who::AbstractString; allow_compliance::Bool = false)
    _beh_unwrappable(inner) && throw(
        ArgumentError(
            "$who cannot wrap a $(nameof(typeof(inner))): behavioural wrappers are scoped to " *
            "active-only devices without q_inject (FourQuadBESS, SmartInverterPV and " *
            "FixedCapacitor are rejected).",
        ),
    )
    ok = inner isa AbstractDevice
    ok || throw(ArgumentError("$who needs an AbstractDevice, got $(typeof(inner))"))
    if inner isa Aggregator
        throw(ArgumentError("$who cannot wrap an Aggregator; wrap its member devices."))
    end
    if inner isa Union{OptOut, Rebound} || (inner isa PartialCompliance && !allow_compliance)
        throw(
            ArgumentError(
                "$who cannot wrap an already-wrapped device ($(nameof(typeof(inner)))); the only " *
                "supported stack is Rebound(PartialCompliance(inner)).",
            ),
        )
    end
    return nothing
end

function _beh_check_baseline(b, Ub, who::AbstractString)
    all(isfinite, b) || throw(ArgumentError("$who: baseline b has a non-finite entry"))
    isfinite(Ub) || throw(ArgumentError("$who: baseline utility Ub is non-finite ($Ub)"))
    return nothing
end

_beh_phi(inner) =
    (hasproperty(inner, :φ) && inner.φ !== nothing) ? Float64(inner.φ) : nothing

function _beh_check_T(b, T::Int, who::AbstractString)
    length(b) == T || throw(
        ArgumentError(
            "$who: baseline b has length $(length(b)), expected the horizon T=$T (the baseline " *
            "is solved per horizon at transform time)",
        ),
    )
    return nothing
end

"""
    PartialCompliance(inner, xi, b, Ub)

Partial-compliance wrapper: only a share `xi` of the population behind `inner` responds to the
price. Realised injection `p' = b + xi (p - b)` and utility `U' = (1 - xi) Ub + xi U(p)`, with `b`
the per-device no-response baseline injection (length `T`) and `Ub` its utility. `xi` must lie in
`(0, 1]`; `xi = 0` is [`OptOut`](@ref). This is the exact expectation over a population in which a
`xi`-share responds (assumption A2), an interpretation for one physical device. The baseline is the
FIT flat-price single-device solve of `apply_behaviour`, NOT `fit_baseline`'s output. Fields:
`inner`, `xi`, `b`, `Ub`, `φ` (copied from `inner`, else `nothing`). Zero binaries; `q_inject`-carrying
devices are rejected at construction.
"""
struct PartialCompliance{D <: AbstractDevice} <: AbstractDevice
    inner::D
    xi::Float64
    b::Vector{Float64}
    Ub::Float64
    φ::Union{Nothing, Float64}

    function PartialCompliance(
        inner::D,
        xi::Real,
        b::AbstractVector{<:Real},
        Ub::Real,
    ) where {D <: AbstractDevice}
        _beh_check_inner(inner, "PartialCompliance")
        (isfinite(xi) && 0 < xi <= 1) || throw(
            ArgumentError(
                "PartialCompliance: xi must lie in (0, 1]; got $xi (xi = 0 is OptOut)",
            ),
        )
        _beh_check_baseline(b, Ub, "PartialCompliance")
        return new{D}(inner, Float64(xi), Float64[b...], Float64(Ub), _beh_phi(inner))
    end
end

"""
    OptOut(inner, b, Ub)

Opt-out wrapper (`xi = 0`): the device ignores the price and keeps its baseline, `p_inject = b`,
`utility = Ub`, `vars = (;)` (no decision variables). Stores only the baseline, the inner type
(phantom parameter) and the inner traits; `storage_kind` is `:none`. See [`PartialCompliance`](@ref).
"""
struct OptOut{D <: AbstractDevice} <: AbstractDevice
    b::Vector{Float64}
    Ub::Float64
    φ::Union{Nothing, Float64}
    flexible::Bool
    reactive::Bool

    function OptOut(inner::D, b::AbstractVector{<:Real}, Ub::Real) where {D <: AbstractDevice}
        _beh_check_inner(inner, "OptOut")
        _beh_check_baseline(b, Ub, "OptOut")
        return new{D}(
            Float64[b...],
            Float64(Ub),
            _beh_phi(inner),
            is_flexible_load(inner),
            has_reactive_decision(inner),
        )
    end
end

"""
    Rebound(inner, b, W, r)

Rebound wrapper: curtailing consumption relative to the baseline must be paid back. With
`c = -p_inject` the consumption and `c^b = -b` the baseline, curtailment `u_t >= 0`,
`u_t >= c^b_t - c_t` and `sum_{tau=t+1}^{min(t+W,T)} (c_tau - c^b_tau) >= r u_t`, `r >= 1`, `W >= 1`.
Convex, linear, binary-free; the baseline is always feasible (`u = 0`). Window clipped at the
horizon (no wrap): curtailment that cannot be recovered is forced to zero. Stack as
`Rebound(PartialCompliance(inner), b, W, r)`. Realised injection and utility are the inner ones;
`vars` gains `rebound_u` when the inner `vars` is a `NamedTuple`.
"""
struct Rebound{D <: AbstractDevice} <: AbstractDevice
    inner::D
    b::Vector{Float64}
    W::Int
    r::Float64
    φ::Union{Nothing, Float64}

    function Rebound(
        inner::D,
        b::AbstractVector{<:Real},
        W::Integer,
        r::Real,
    ) where {D <: AbstractDevice}
        _beh_check_inner(inner, "Rebound"; allow_compliance = true)
        W >= 1 || throw(ArgumentError("Rebound: window W must be >= 1; got $W"))
        (isfinite(r) && r >= 1) ||
            throw(ArgumentError("Rebound: recovery ratio r must be finite and >= 1; got $r"))
        all(isfinite, b) || throw(ArgumentError("Rebound: baseline b has a non-finite entry"))
        return new{D}(inner, Float64[b...], Int(W), Float64(r), _beh_phi(inner))
    end
end

"""
    contribute!(d::PartialCompliance, ctx::ModelContext; T, kwargs...)

Contribute the inner device on `ctx.model` and return the blended `(; vars, p_inject, utility)`;
`kwargs` are forwarded to the inner `contribute!`. Performs no solve.
"""
function contribute!(d::PartialCompliance, ctx::ModelContext; T::Int, kwargs...)
    _beh_check_T(d.b, T, "PartialCompliance")
    res = contribute!(d.inner, ctx; T = T, kwargs...)
    hasproperty(res, :q_inject) && throw(
        ArgumentError("PartialCompliance: inner device returned q_inject (unsupported)"),
    )
    xi = d.xi
    p_inject = AffExpr[(1 - xi) * d.b[t] + xi * res.p_inject[t] for t in 1:T]
    utility = xi * res.utility + (1 - xi) * d.Ub
    return (; vars = res.vars, p_inject, utility)
end

function contribute!(d::OptOut, ctx::ModelContext; T::Int, kwargs...)
    _beh_check_T(d.b, T, "OptOut")
    p_inject = AffExpr[AffExpr(d.b[t]) for t in 1:T]
    utility = zero(QuadExpr) + d.Ub
    return (; vars = (;), p_inject, utility)
end

function contribute!(d::Rebound, ctx::ModelContext; T::Int, kwargs...)
    _beh_check_T(d.b, T, "Rebound")
    res = contribute!(d.inner, ctx; T = T, kwargs...)
    m = ctx.model
    u = @variable(m, [t = 1:T], lower_bound = 0.0)
    # consumption c = -p_inject, baseline c^b = -b: c^b_t - c_t = p_t - b_t
    @constraint(m, [t = 1:T], u[t] >= res.p_inject[t] - d.b[t])
    # recovery over the next W hours (clipped at T): sum (c - c^b) = sum (b - p) >= r u_t
    @constraint(
        m,
        [t = 1:T],
        sum(d.b[τ] - res.p_inject[τ] for τ in (t + 1):min(t + d.W, T); init = zero(AffExpr)) >=
        d.r * u[t]
    )
    vars = res.vars isa NamedTuple ? merge(res.vars, (; rebound_u = u)) : res.vars
    return (; vars, res.p_inject, res.utility)
end

export PartialCompliance, OptOut, Rebound
