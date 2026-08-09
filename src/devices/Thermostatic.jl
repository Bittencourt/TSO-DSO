# src/devices/Thermostatic.jl
#
# SEAM: thermostatic (A/C) flexible-load device (DEV-01).
# OWNER: plan 03-03.
#
# An `AbstractDevice` implementing a thermostatically-controlled load: an indoor
# temperature state that evolves by an RC/ETP-style linear recursion in power
# (thesis eqs. 3.2-3.3), kept inside a comfort band, with a concave-quadratic
# comfort utility (eq. 3.11, curvature b > 0 for concavity per 3.13-3.14). Follows
# the `Interruptible` pattern structurally (immutable concretely-typed struct,
# throw-based constructor guards, promotion outer constructor) but conforms to the
# Phase-3 AGGREGATABLE-DEVICE contract (aggregator-as-writer, DEV-05): `contribute!`
# builds its variables + temporal-coupling constraints on `ctx.model` and RETURNS
# `(; vars, p_inject, utility)` — it writes NOTHING to `ctx.residuals` and calls NO
# `add_to_objective!`. The Aggregator (plan 03-05) is the sole network-facing writer.
# Network-agnostic: holds only a bus id + parameter vectors, never a Feeder.

using JuMP

"""
    Thermostatic{T<:Real} <: AbstractDevice

A thermostatically-controlled (A/C) flexible load (DEV-01). It draws power `p[t]` within
`[Pmin, Pmax]` to drive an indoor-temperature state `Tin[t]` that evolves by the linear
RC/ETP recursion (thesis eq. 3.2)

    Tin[t+1] = Tin[t] + α·(Tout[t] − Tin[t]) − β·p[t]                       (3.2)

held inside the comfort band `Tmin ≤ Tin[t] ≤ Tmax` (eq. 3.3), and derives the
concave-quadratic comfort utility (eq. 3.11, constant `c` dropped — RESEARCH A5)

    U(Tin) = − (b/2)·Σ_t (Tin[t] − Tmin)²                                   (3.11)

The strictly-positive curvature `b > 0` (traces eqs. 3.13–3.14) keeps `U` concave, so the
assembled welfare stays a convex QP. All quantities are in the single model per-unit
system; coefficients are not rescaled here.

# Fields

  - `bus::Int` — the bus id the load withdraws at (the ONLY topology handle a device holds;
    it never sees the network object or line parameters — network-agnostic, DEV-05).
  - `α::T` — thermal coupling to the ambient (eq. 3.2); `α ≥ 0` required (a negative
    coupling reverses heat flow — non-physical, WR-02).
  - `β::T` — power-to-temperature gain (eq. 3.2); `β > 0` required so power COOLS via the
    `−β·p` term (a non-positive β silently flips the sign, WR-02).
  - `Tmin::T`, `Tmax::T` — comfort band (eq. 3.3).
  - `Tin0::T` — initial indoor temperature (state IC for the recursion); `Tmin ≤ Tin0 ≤ Tmax`
    required (comfort-band IC, WR-02).
  - `Pmin::T`, `Pmax::T` — A/C power bounds.
  - `b::T` — utility curvature, `b > 0` required for concavity (eqs. 3.11/3.14).
  - `Tout::Vector{T}` — ambient-temperature profile parameter (eq. 3.2); its length is
    validated against the horizon `T` at `contribute!` time (it is not known at construction).

Construction throws `ArgumentError` when `b ≤ 0` (concavity guard, threat T-03-06), when
`Tmax < Tmin` (inconsistent comfort band), when `Pmax < Pmin` (inconsistent power bounds),
when `α < 0` or `β ≤ 0` (non-physical recursion signs, WR-02), or when `Tin0` starts
outside the comfort band `Tmin ≤ Tin0 ≤ Tmax` (comfort-band IC guard, WR-02).
"""
struct Thermostatic{T <: Real} <: AbstractDevice
    bus::Int
    α::T
    β::T
    Tmin::T
    Tmax::T
    Tin0::T
    Pmin::T
    Pmax::T
    b::T
    Tout::Vector{T}

    function Thermostatic(
        bus::Int,
        α::T,
        β::T,
        Tmin::T,
        Tmax::T,
        Tin0::T,
        Pmin::T,
        Pmax::T,
        b::T,
        Tout::Vector{T},
    ) where {T <: Real}
        # Concavity guard (thesis eqs. 3.11/3.14, b > 0): a non-positive curvature makes
        # the comfort utility convex → welfare maximization unbounded/non-convex. Reject
        # LOUDLY (project convention: throw, never @assert). Threat T-03-06.
        if b <= zero(T)
            throw(
                ArgumentError(
                    "Thermostatic utility curvature b must be > 0 for concavity " *
                    "(thesis eqs. 3.11/3.14); got b=$b",
                ),
            )
        end
        if Tmax < Tmin
            throw(
                ArgumentError(
                    "Thermostatic comfort band requires Tmax ≥ Tmin (thesis eq. 3.3); " *
                    "got Tmin=$Tmin, Tmax=$Tmax",
                ),
            )
        end
        if Pmax < Pmin
            throw(
                ArgumentError(
                    "Thermostatic power bounds require Pmax ≥ Pmin; got " *
                    "Pmin=$Pmin, Pmax=$Pmax",
                ),
            )
        end
        # WR-02 physical-sign guards on the RC/ETP recursion (eq. 3.2)
        #   Tin[t+1] = Tin[t] + α·(Tout − Tin) − β·p.
        # α is the ambient-coupling fraction: a NEGATIVE α makes heat flow from cold to hot
        # (2nd-law violation) and destabilizes the discrete recursion — reject α < 0.
        if α < zero(T)
            throw(
                ArgumentError(
                    "Thermostatic ambient-coupling α must be ≥ 0 (eq. 3.2); a negative α " *
                    "reverses heat flow (non-physical); got α=$α",
                ),
            )
        end
        # β is the power-to-temperature gain entering as −β·p: with β > 0 more A/C power
        # COOLS (the intended direction). A NON-POSITIVE β silently flips the sign so power
        # would heat (or do nothing), inverting the whole comfort model — reject β ≤ 0.
        if β <= zero(T)
            throw(
                ArgumentError(
                    "Thermostatic power-to-temperature gain β must be > 0 so that power " *
                    "COOLS in eq. 3.2 (−β·p); a non-positive β silently flips the sign; " *
                    "got β=$β",
                ),
            )
        end
        # Initial-condition guard (mirrors PVBattery's soc0 IC): the state IC Tin[1] = Tin0
        # must start INSIDE the comfort band, else the band constraint (3.3) makes the very
        # first step infeasible for a cryptic reason. Reject up front.
        if !(Tmin <= Tin0 <= Tmax)
            throw(
                ArgumentError(
                    "Thermostatic initial temperature must satisfy Tmin ≤ Tin0 ≤ Tmax " *
                    "(eq. 3.3 comfort-band IC); got Tmin=$Tmin, Tin0=$Tin0, Tmax=$Tmax",
                ),
            )
        end
        return new{T}(bus, α, β, Tmin, Tmax, Tin0, Pmin, Pmax, b, Tout)
    end
end

"""
    Thermostatic(bus, α, β, Tmin, Tmax, Tin0, Pmin, Pmax, b, Tout)

Convenience outer constructor (IN-01): PROMOTEs the scalar parameters and the `Tout`
element type to a common `Real` type before delegating to the inner constructor, so a
natural mixed-type call (e.g. an integer `0` among `Float64`s) just works instead of
throwing a `MethodError`. `bus` is converted to `Int`. When every scalar already shares a
type and `Tout` is a `Vector{T}`, the inner constructor is strictly more specific and is
selected directly (no promotion, no recursion).
"""
function Thermostatic(
    bus::Integer,
    α::Real,
    β::Real,
    Tmin::Real,
    Tmax::Real,
    Tin0::Real,
    Pmin::Real,
    Pmax::Real,
    b::Real,
    Tout::AbstractVector{<:Real},
)
    Tp = promote_type(
        typeof(α),
        typeof(β),
        typeof(Tmin),
        typeof(Tmax),
        typeof(Tin0),
        typeof(Pmin),
        typeof(Pmax),
        typeof(b),
        eltype(Tout),
    )
    return Thermostatic(
        Int(bus),
        convert(Tp, α),
        convert(Tp, β),
        convert(Tp, Tmin),
        convert(Tp, Tmax),
        convert(Tp, Tin0),
        convert(Tp, Pmin),
        convert(Tp, Pmax),
        convert(Tp, b),
        convert(Vector{Tp}, Tout),
    )
end

"""
    contribute!(d::Thermostatic, ctx::ModelContext; T::Int)

Contribute the thermostatic load into the shared model context over the horizon
`t = 1:T`, conforming to the Phase-3 AGGREGATABLE-DEVICE contract (aggregator-as-writer,
DEV-05). It:

 1. creates a bounded served-power variable `Pmin ≤ p[t] ≤ Pmax` and a bounded
    indoor-temperature state `Tmin ≤ Tin[t] ≤ Tmax` (comfort band, eq. 3.3) on `ctx.model`;
 2. fixes the state IC `Tin[1] == Tin0` and adds the RC/ETP temperature recursion (eq. 3.2)
    `Tin[t+1] == Tin[t] + α·(Tout[t] − Tin[t]) − β·p[t]` for `t = 1:T-1` (validating
    `length(Tout) ≥ T`, throwing `ArgumentError` otherwise — the temporal-infeasibility
    guard, threat T-03-07); and
 3. builds the concave comfort utility `− (b/2)·Σ_t (Tin[t] − Tmin)²` (eq. 3.11) as a
    `QuadExpr`.

It then RETURNS `(; vars = (; p, Tin, Tin0, Tout_param), p_inject, utility)` where
`p_inject[t] = −p[t]` is the signed ACTIVE injection (a consumed load is a NEGATIVE
injection, matching the `Interruptible` sign convention). The device writes NOTHING to
`ctx.residuals` and calls NO `add_to_objective!`: the Aggregator consumes this tuple and
is the sole `:Rp`/`:Rq` writer. The device references only `d.bus` (never the network),
so the power-flow swap leaves this code untouched.

`Tin0` and `Tout_param` (MPC-01 seam, D-01/D-03) are genuine JuMP `Parameter` handles for
the temperature initial condition and the per-step ambient-temperature profile (only
`t = 1:(T-1)` entries — the recursion never reads `Tout[T]`), respectively — a future
receding-horizon window re-targets them via `set_parameter_value`/`set_parameter_value.`
WITHOUT rebuilding any constraint. Both default to the EXACT prior literal value
(`parameter_value(Tin0) == d.Tin0`, `parameter_value.(Tout_param) == d.Tout[1:(T-1)]`), so
no caller that never calls `set_parameter_value` observes any behavior change
(byte-identical-default invariant).
"""
function contribute!(d::Thermostatic, ctx::ModelContext; T::Int)
    # Temporal-infeasibility guard (threat T-03-07): the recursion (3.2) reads Tout[t] for
    # t = 1:T-1, so the ambient profile must cover the requested horizon.
    if length(d.Tout) < T
        throw(
            ArgumentError(
                "Thermostatic ambient profile Tout has length $(length(d.Tout)) < " *
                "horizon T=$T (thesis eq. 3.2 recursion)",
            ),
        )
    end

    m = ctx.model
    # Bounded served-power variable per step and the comfort-band temperature state (3.3).
    p = @variable(m, [t = 1:T], lower_bound = d.Pmin, upper_bound = d.Pmax)
    Tin = @variable(m, [t = 1:T], lower_bound = d.Tmin, upper_bound = d.Tmax)

    # State IC + RC/ETP recursion (thesis eq. 3.2) — the inter-temporal coupling.
    #
    # MPC-01 seam (D-01/D-03): both the temperature IC and the ambient-temperature profile
    # are now genuine Parameters (Tin0, Tout_param), not baked-in literals — re-settable via
    # `set_parameter_value`/`set_parameter_value.` without rebuilding either constraint, and
    # both defaulting to the exact prior literal value. `Tout_param` covers ONLY
    # `t = 1:(T-1)` since the recursion never reads `Tout[T]` (guarded against T == 1: no
    # recursion constraint — and hence no Tout_param — is built in that case, unchanged).
    @variable(m, Tin0 in Parameter(d.Tin0))
    @constraint(m, Tin[1] == Tin0)
    if T > 1
        @variable(m, Tout_param[t = 1:(T - 1)] in Parameter.(d.Tout[1:(T - 1)]))
        @constraint(
            m,
            [t = 1:(T - 1)],
            Tin[t + 1] == Tin[t] + d.α * (Tout_param[t] - Tin[t]) - d.β * p[t]
        )
    else
        Tout_param = JuMP.VariableRef[]
    end

    # Concave comfort utility (eq. 3.11, constant c dropped — RESEARCH A5). Curvature
    # −(b/2) ≤ 0 keeps it concave; built as a QuadExpr so the curvature is retained.
    utility = sum(-(d.b / 2) * (Tin[t] - d.Tmin)^2 for t in 1:T)

    # Signed ACTIVE injection: an A/C is a load ⇒ NEGATIVE injection −p (Interruptible sign
    # convention). Returned to the aggregator, NOT written to any residual here.
    p_inject = AffExpr[-p[t] for t in 1:T]

    return (; vars = (; p, Tin, Tin0, Tout_param), p_inject, utility)
end

export Thermostatic
