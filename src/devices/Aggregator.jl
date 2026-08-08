# src/devices/Aggregator.jl
#
# SEAM: aggregator roll-up -- the network-facing residual writer (DEV-05).
# OWNER: plan 03-05.
#
# Rolls a bus's member devices into the nodal net active/reactive power injections
# and total utility the network actually sees (thesis eqs. 3.21-3.23). Holds a bus
# id, a load power factor φ, its member `AbstractDevice`s, and the inelastic-demand
# parameter profile `Pdc` for its houses. `contribute!(agg, ctx; T)` drives each
# device once, sums their active contributions into a single net injection (3.22),
# derives the net reactive injection q = −P_dc·tan(arccos φ) from the load power
# factor (3.23; PV/battery are active-only, A3), injects BOTH into :Rp/:Rq at its
# bus, and adds the summed device utility to the objective (3.21). RESOLVED design
# (RESEARCH Q1): the Aggregator is the SOLE :Rp/:Rq writer; devices return their
# `(; vars, p_inject, utility)` terms and never touch the network.

using JuMP

"""
    reactive_factor(φ::Real) -> Real

The reactive-draw factor `tan(arccos φ) = sqrt(1 − φ²)/φ` for a load power factor
`φ ∈ (0, 1]` (thesis eq. 3.23). Single-sourced here (IN-01) and reused by the aggregator
roll-up and BOTH ADMM subproblems (AGR-OPT, DSO-OPT), so the net reactive injection
`q = −P_dc·tan(arccos φ)` is derived in exactly one place. `Aggregator` (included before the
ADMM subproblems) is the shared home reachable from all three call sites.
"""
reactive_factor(φ::Real) = sqrt(1 - φ^2) / φ

"""
    Aggregator{Tp<:Real,D<:AbstractVector{<:AbstractDevice}} <: AbstractDevice

An aggregator of prosumer devices at one distribution bus (DEV-05): the SOLE
network-facing residual writer (RESEARCH Q1, resolved). It rolls its member devices
into the single nodal quantities the network sees (thesis eqs. 3.21-3.23):

    U_ag  = Σ_d U_d                                            # summed utility (3.21)
    p_ag  = Σ_d p_inject_d − P_dc                             # net active injection (3.22)
    q_ag  = − P_dc · tan(arccos φ)                            # net reactive from φ (3.23)

Reactive power is defined at the AGGREGATOR level as a power-factor function of the
inelastic-demand active draw `P_dc` (thesis eq. 3.23); the DERs (PV/battery) are
active-only (Assumption A3), so only the inelastic load contributes reactive.

# Fields

  - `bus::Int` — the distribution bus the aggregator sits at. The aggregator SUPPLIES
    this bus to the network; its member devices need not (and do not) reference it —
    they are fully network-agnostic.
  - `φ::Tp` — load power factor, `φ ∈ (0, 1]` (thesis eq. 3.23; typically 0.85-0.95).
  - `devices::D` — the member `AbstractDevice`s (aggregatable variant: each returns its
    `(; vars, p_inject, utility)` terms from `contribute!`).
  - `Pdc::Vector{Tp}` — the inelastic-demand parameter profile in per-unit power (A4);
    its length is validated against the horizon `T` at `contribute!` time.

Construction throws `ArgumentError` when `φ ∉ (0, 1]` or when `devices` is empty.
"""
struct Aggregator{Tp <: Real, D <: AbstractVector{<:AbstractDevice}} <: AbstractDevice
    bus::Int
    φ::Tp
    devices::D
    Pdc::Vector{Tp}

    function Aggregator(
        bus::Int,
        φ::Tp,
        devices::D,
        Pdc::Vector{Tp},
    ) where {Tp <: Real, D <: AbstractVector{<:AbstractDevice}}
        # Power-factor guard (thesis eq. 3.23): φ ∈ (0,1] keeps tan(arccos φ) real and
        # finite. Reject LOUDLY (project convention: throw, never @assert).
        if !(zero(Tp) < φ <= one(Tp))
            throw(
                ArgumentError(
                    "Aggregator load power factor φ must lie in (0, 1] " *
                    "(thesis eq. 3.23); got φ=$φ",
                ),
            )
        end
        # An aggregator with no members has no utility and no injection — the roll-up
        # (3.21-3.22) is undefined. Reject up front instead of a silent empty sum.
        if isempty(devices)
            throw(
                ArgumentError(
                    "Aggregator requires at least one member device " *
                    "(thesis eqs. 3.21-3.22)",
                ),
            )
        end
        return new{Tp, D}(bus, φ, devices, Pdc)
    end
end

"""
    Aggregator(bus, φ, devices, Pdc)

Convenience outer constructor (IN-01): PROMOTEs the scalar power factor `φ` and the
`Pdc` element type to a common `Real` type before delegating to the inner constructor,
so a natural mixed-type call just works instead of throwing a `MethodError`. `bus` is
converted to `Int` and `devices` is `collect`ed into a concrete vector. When `φ` and
`eltype(Pdc)` already share a type (and `Pdc` is a `Vector`), the inner constructor is
strictly more specific and is selected directly (no promotion, no recursion).
"""
function Aggregator(
    bus::Integer,
    φ::Real,
    devices::AbstractVector{<:AbstractDevice},
    Pdc::AbstractVector{<:Real},
)
    Tp = promote_type(typeof(φ), eltype(Pdc))
    return Aggregator(Int(bus), convert(Tp, φ), collect(devices), Vector{Tp}(Pdc))
end

"""
    contribute!(agg::Aggregator, ctx::ModelContext; T::Int)

Roll the aggregator's member devices into the single nodal quantities the network sees
(thesis eqs. 3.21-3.23), as the SOLE :Rp/:Rq writer at `agg.bus`. It:

 1. drives each member device once (`res = contribute!(d, ctx; T)`), summing their
    `res.p_inject` into one net active vector and their `res.utility` into one QuadExpr,
    and collecting their `res.vars` (validating `length(Pdc) ≥ T` first — the
    temporal-consistency guard). If a member device ALSO carries an optional `q_inject`
    field (MESH-04, D-09 — today, only `FourQuadBESS`), its per-`t` reactive injection is
    additionally summed into a `q_inject` accumulator via a `hasproperty` guard; a device
    lacking the field contributes zero, so this accumulator is byte-identical to `zero`
    when no such device is present;
 2. injects, per `t`, ONE net active `Σ_d p_inject_d[t] − P_dc[t]` into `:Rp` (3.22;
    inelastic demand is a negative parameter injection, A4) and ONE net reactive
    `− P_dc[t]·tan(arccos φ) + Σ_d q_inject_d[t]` into `:Rq` (3.23 plus the D-10 additive
    device `q_inject` term; DERs are active-only by default, A3, unless a device opts in
    via `q_inject`) at `agg.bus`;
 3. adds the summed device utility to `ctx.meta[:objective]` via `add_to_objective!`
    (3.21, kept a `QuadExpr` so curvature is retained); and
 4. stashes the collected device vars under `ctx.meta[:agg_device_vars]` keyed by bus,
    so the assembly can run the post-solve battery-complementarity check.

The member devices themselves write NOTHING to the residual/objective — the aggregator
is the sole network-facing writer. Returns `(; vars, p_inject, q_inject, utility)` (the
aggregate device vars, the net active injection vector, the net device-reactive-injection
vector — `zero(AffExpr)` per `t` when no member device carries `q_inject`, MESH-04 D-09 —
and the summed utility).
"""
function contribute!(agg::Aggregator, ctx::ModelContext; T::Int)
    # Temporal-consistency guard: the net active injection reads P_dc[t] for t = 1:T.
    if length(agg.Pdc) < T
        throw(
            ArgumentError(
                "Aggregator inelastic-demand profile Pdc has length $(length(agg.Pdc)) " *
                "< horizon T=$T (thesis eq. 3.22)",
            ),
        )
    end

    tanφ = reactive_factor(agg.φ)               # tan(arccos φ) (thesis eq. 3.23)

    # Accumulate the member devices' active injections and utilities (device-agnostic).
    # q_inject (MESH-04, D-09) accumulates the OPTIONAL device reactive injection — absent
    # means zero, so this stays zero(AffExpr) per t when no member device carries it.
    p_inject = AffExpr[zero(AffExpr) for _ in 1:T]
    q_inject = AffExpr[zero(AffExpr) for _ in 1:T]
    utility = zero(QuadExpr)
    device_vars = Any[]
    for d in agg.devices
        res = contribute!(d, ctx; T = T)
        for t in 1:T
            p_inject[t] += res.p_inject[t]
        end
        if hasproperty(res, :q_inject)
            for t in 1:T
                q_inject[t] += res.q_inject[t]
            end
        end
        utility += res.utility
        push!(device_vars, res.vars)
    end

    # ONE net active + ONE net reactive injection per (bus, t) — the aggregator is the
    # sole :Rp/:Rq writer (DEV-05). :Rp carries the DER/flexible-load injections minus
    # the inelastic demand; :Rq is the power-factor reactive of that demand (A3) PLUS
    # the additive device q_inject sum (MESH-04, D-10 — purely additive on top of the
    # untouched inelastic term; byte-identical to (3.23) alone when q_inject is zero).
    for t in 1:T
        add_to_residual!(ctx, :Rp, agg.bus, t, p_inject[t] - agg.Pdc[t])            # (3.22)
        add_to_residual!(ctx, :Rq, agg.bus, t, -agg.Pdc[t] * tanφ + q_inject[t])    # (3.23) + D-10
    end

    # Σ U (thesis eq. 3.21) into the QuadExpr welfare accumulator.
    add_to_objective!(ctx, utility)

    # Stash device vars keyed by bus for the post-solve p_ch·p_dch < τ battery check.
    store = get!(ctx.meta, :agg_device_vars, Dict{Int, Vector{Any}}())
    append!(get!(store, agg.bus, Vector{Any}()), device_vars)

    return (; vars = device_vars, p_inject, q_inject, utility)
end

export Aggregator, reactive_factor
