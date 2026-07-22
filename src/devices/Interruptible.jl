# src/devices/Interruptible.jl
#
# SEAM: interruptible (curtailable) flexible-load device (DEV-03).
# OWNER: plan 02-03.
#
# The first `AbstractDevice` implementation: an interruptible load with a concave
# quadratic utility of served power. Implements the dispatched `contribute!` — adds its
# per-time served-power variable and bounds to `ctx.model`, injects `-p[t]` (a
# consumption withdrawal) into `ctx.residuals[:Rp]` at its bus via the indexed
# `add_to_residual!`, and accumulates `Σ_t (a·p[t] - (b/2)·p[t]^2)` into the welfare
# objective via `add_to_objective!`. Traces thesis eqs. 3.10 (utility) and 3.13–3.14
# (flexibility limits).

using JuMP

"""
    Interruptible{T<:Real} <: AbstractDevice

An interruptible / elastic load (DEV-03): a flexible consumer that draws power `p[t]`
within `[Pmin, Pmax]` and derives the concave-quadratic utility

    U(p) = Σ_t ( a·p[t] − (b/2)·p[t]² )      (thesis eq. 3.10)

from the power it is served. The marginal-utility intercept `a` traces eq. 3.13 and the
strictly-positive curvature `b > 0` traces eq. 3.14 — `b > 0` is what keeps `U` concave,
so maximizing welfare stays a convex QP. All quantities are in per-unit / model units
(RESEARCH Pitfall 4): `a`, `b` are utility coefficients in those units and are not
rescaled here.

# Fields

  - `bus::Int`  — the bus id the load withdraws at (the ONLY topology handle a device
    holds; it never sees the network object or line parameters — success criterion 2).
  - `Pmin::T`, `Pmax::T` — served-power bounds (eqs. 3.13–3.14 flexibility limits).
  - `a::T` — linear marginal-utility intercept (eq. 3.13).
  - `b::T` — quadratic curvature, `b > 0` required for concavity (eq. 3.14).

Construction throws `ArgumentError` when `b ≤ 0` (curvature guard, threat T-02-02) or
when `Pmax < Pmin` (inconsistent bounds).
"""
struct Interruptible{T <: Real} <: AbstractDevice
    bus::Int
    Pmin::T
    Pmax::T
    a::T
    b::T

    function Interruptible(bus::Int, Pmin::T, Pmax::T, a::T, b::T) where {T <: Real}
        # Concavity guard (thesis eq. 3.14, b > 0): a non-positive curvature would make
        # the utility convex → welfare maximization unbounded/non-convex → garbage or
        # solver failure. Reject LOUDLY (project convention: throw, never @assert, since
        # @assert can be elided under -O). Threat T-02-02.
        if b <= zero(T)
            throw(
                ArgumentError(
                    "Interruptible utility curvature b must be > 0 for concavity " *
                    "(thesis eq. 3.14); got b=$b",
                ),
            )
        end
        if Pmax < Pmin
            throw(
                ArgumentError(
                    "Interruptible power bounds require Pmax ≥ Pmin; got " *
                    "Pmin=$Pmin, Pmax=$Pmax",
                ),
            )
        end
        return new{T}(bus, Pmin, Pmax, a, b)
    end
end

"""
    Interruptible(bus, Pmin, Pmax, a, b)

Convenience outer constructor (IN-01): `PROMOTE`s `Pmin`, `Pmax`, `a`, `b` to a common
`Real` type before delegating to the inner constructor, so a natural mixed-type call like
`Interruptible(2, 0, 5.0, 4.0, 1.0)` (an integer `0`) just works instead of throwing a
confusing `MethodError`. `bus` is converted to `Int`. When all four already share a type
the inner constructor is strictly more specific and is selected directly (no promotion,
no recursion).
"""
Interruptible(bus::Integer, Pmin::Real, Pmax::Real, a::Real, b::Real) =
    Interruptible(Int(bus), promote(Pmin, Pmax, a, b)...)

"""
    contribute!(d::Interruptible, ctx::ModelContext; T::Int=1)

Contribute the interruptible load into the shared model context over the horizon
`t = 1:T`, meeting the network ONLY at the affine `:Rp` residual seam:

 1. creates a bounded served-power variable `Pmin ≤ p[t] ≤ Pmax` on `ctx.model`;
 2. ADDS a NEGATIVE injection `−p[t]` into `ctx.residuals[:Rp]` at cell `(d.bus, t)` via
    the indexed `add_to_residual!` — a consumed load is a withdrawal, i.e. it REDUCES the
    net injection (sign matches the toy-DC convention; threat T-02-01); and
 3. ADDS the concave utility `Σ_t ( a·p[t] − (b/2)·p[t]² )` (eq. 3.10) into the welfare
    objective via [`add_to_objective!`](@ref). The utility flows to the QuadExpr
    objective accumulator — NOT the affine residual — so its curvature is retained
    (threat T-02-02, RESEARCH Pitfall 3).

The device references only `d.bus` and `T`; it never touches the network topology, so the
DC / LinDistFlow power-flow swap leaves this code untouched (success criterion 2).
"""
function contribute!(d::Interruptible, ctx::ModelContext; T::Int = 1)
    m = ctx.model
    # Bounded served-power variable per time step (eqs. 3.13–3.14 flexibility limits).
    p = @variable(m, [t = 1:T], lower_bound = d.Pmin, upper_bound = d.Pmax)

    # Signed AFFINE injection into the price-bearing nodal-balance residual: a consumed
    # load is a NEGATIVE net injection (−p). Only :Rp — the interruptible load carries no
    # reactive term, so the reactive residual is never allocated (threat T-02-09).
    for t in 1:T
        add_to_residual!(ctx, :Rp, d.bus, t, -p[t])
    end

    # Concave-quadratic utility (eq. 3.10) → the QuadExpr welfare accumulator. Keeping the
    # −(b/2)p² sign preserves concavity; routing it here (not the residual) preserves
    # curvature (Pitfall 3, threat T-02-02).
    add_to_objective!(ctx, sum(d.a * p[t] - (d.b / 2) * p[t]^2 for t in 1:T))

    return p
end

export Interruptible
