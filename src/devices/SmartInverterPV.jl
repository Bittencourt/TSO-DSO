# src/devices/SmartInverterPV.jl
#
# SEAM: PV generator with a smart-inverter reactive capability (phase 43, DEV-09).
#
# Thesis assumption A3 (DER are active-only) is LIFTED for this device alone, as a SEPARATE
# device -- the FourQuadBESS precedent -- so PVBattery's golden-tested surface is never widened.
# The inverter has apparent-power rating `S_inv`; with active output `pv_used[t]` and reactive
# output `q[t]` (sign-free: injection or absorption) the physical limit is
#
#     pv_used[t]^2 + q[t]^2 <= S_inv^2        <=>   || (pv_used[t], q[t]) ||_2 <= S_inv
#
# i.e. one rotated-free second-order cone per hour, `[S_inv, pv_used[t], q[t]] in SecondOrderCone()`.
# Re-earned for PV: the active leg is `pv_used >= 0` (generation only; the cone's lower half-plane
# `pv_used < 0` is cut off by the variable bound), so the feasible set is the quarter-disc, convex.
#
# ZERO-UTILITY-ON-Q CONVENTION (copied verbatim in spirit from FourQuadBESS): NO cost or utility
# term on reactive power -- or on pv_used -- anywhere. The returned utility is the zero
# expression. Both quantities are priced ONLY through the network balances (the active price
# lambda and the reactive dual mu, via the Aggregator's :Rp / :Rq roll-up), so a "zero-cost
# optimal Q" is the convention: the inverter supplies reactive support exactly where the network
# duals value it. The q decision reaches the network ONLY through the existing reactive-consensus
# path (CERTIFIED qag_dso pin / LIVE mu_q dual ascent) -- this file never writes :Rq itself; the
# Aggregator's `hasproperty(res, :q_inject)` branch consumes it (zero Aggregator edits).
#
# Conforms to the AGGREGATABLE-DEVICE contract: `contribute!` builds variables/constraints on
# `ctx.model`, writes NOTHING to `ctx.residuals`, calls NO `add_to_objective!`, and RETURNS
# `(; vars, p_inject, q_inject, utility)`. Network-agnostic: bus id + parameters only.

using JuMP

"""
    SmartInverterPV{T<:Real} <: AbstractDevice

A curtailable PV generator whose inverter can dispatch reactive power inside its apparent-power
rating.

# Fields

  - `bus::Int` -- network bus the (aggregator holding the) device injects at.
  - `S_inv::T` -- inverter apparent-power rating (pu); the cone bound, must be `> 0`.
  - `Ppv::Vector{T}` -- per-step PV availability (pu); `0 <= pv_used[t] <= Ppv[t]`, every entry
    must be `>= 0`. Must have `length >= T` at `contribute!` time.

The optimal reactive dispatch carries NO utility term (see the file header): it is priced only
through the network, via the certified reactive path. `has_reactive_decision(::SmartInverterPV)`
is `true`, so any population containing the device resolves the ADMM reactive default to LIVE.
"""
struct SmartInverterPV{T <: Real} <: AbstractDevice
    bus::Int
    S_inv::T
    Ppv::Vector{T}

    function SmartInverterPV(bus::Int, S_inv::T, Ppv::Vector{T}) where {T <: Real}
        if S_inv <= zero(T)
            throw(
                ArgumentError(
                    "SmartInverterPV apparent-power rating S_inv must be > 0 " *
                    "(pv_used²+q²≤S_inv²; a non-positive S_inv collapses the cone); got S_inv=$S_inv",
                ),
            )
        end
        if any(<(zero(T)), Ppv)
            throw(
                ArgumentError(
                    "SmartInverterPV PV availability profile Ppv must be >= 0 at every step; " *
                    "got minimum $(minimum(Ppv))",
                ),
            )
        end
        return new{T}(bus, S_inv, Ppv)
    end
end

"""
    SmartInverterPV(bus, S_inv, Ppv)

Convenience outer constructor: `promote`s `S_inv` and the profile element type to a common
`Real` type (a lone integer among floats just works), and converts `bus` to `Int`.
"""
function SmartInverterPV(bus::Integer, S_inv::Real, Ppv::AbstractVector{<:Real})
    T = float(promote_type(typeof(S_inv), eltype(Ppv)))
    return SmartInverterPV(Int(bus), T(S_inv), Vector{T}(Ppv))
end

# New device => the trait override lives with the struct (Thermostatic.jl placement precedent),
# not in CapabilityTraits.jl (reserved for the golden-pinned legacy devices). It is NOT a flexible
# load: `is_flexible_load` keeps its `false` default, so no power-factor term is added for its
# own active output; its reactive decision is the genuine `q_inject` below.
has_reactive_decision(::SmartInverterPV) = true

"""
    contribute!(d::SmartInverterPV, ctx::ModelContext; T::Int)

Contribute the smart-inverter PV into the shared model over `t = 1:T`. Creates continuous
`pv_used[t] >= 0` with the LITERAL per-step bound `pv_used[t] <= Ppv[t]` (no `Parameter` seam this
phase), a FREE-sign `q[t]`, and ONE ANONYMOUS apparent-power cone per `t`
`[S_inv, pv_used[t], q[t]] in SecondOrderCone()` -- never a named container, so any number of
instances (and `ConvexBranchFlow`'s named `:cone`) compose in one model. No binary/integer
variables.

Returns `(; vars = (; pv_used, q), p_inject, q_inject = q, utility)` with `p_inject[t] == pv_used[t]`
(generation is positive injection), `q_inject === vars.q` (the SAME `Vector{VariableRef}`), and
`utility` the zero `QuadExpr`.
"""
function contribute!(d::SmartInverterPV, ctx::ModelContext; T::Int)
    if length(d.Ppv) < T
        throw(
            ArgumentError(
                "SmartInverterPV.contribute! needs a PV profile of length >= T=$T; got " *
                "length(Ppv)=$(length(d.Ppv))",
            ),
        )
    end
    m = ctx.model

    # Curtailable PV: literal per-t availability bound (plain upper_bound, no Parameter).
    pv_used = @variable(m, [t = 1:T], lower_bound = 0.0, upper_bound = d.Ppv[t])
    # q is sign-free and carries NO bound -- the apparent-power cone below is its only restriction
    # (no cost/utility term on reactive power anywhere).
    q = @variable(m, [t = 1:T])

    # Apparent-power cone, the FourQuadBESS idiom with the PV leg. ANONYMOUS (see file header).
    @constraint(m, [t = 1:T], [d.S_inv, pv_used[t], q[t]] in SecondOrderCone())

    p_inject = AffExpr[1.0 * pv_used[t] for t in 1:T]
    utility = JuMP.QuadExpr()   # zero: priced only through the network balances

    return (; vars = (; pv_used, q), p_inject, q_inject = q, utility)
end

export SmartInverterPV
