# src/devices/Deferrable.jl
#
# SEAM: deferrable (shiftable) flexible-load device (DEV-02).
# OWNER: plan 03-03.
#
# An `AbstractDevice` implementing a deferrable / shiftable load (washer, EV charge):
# power drawn per hour within a time window whose integral must meet an energy budget
# (thesis eqs. 3.4-3.5), with a concave-quadratic utility (eq. 3.12). Follows the
# `Interruptible`/`Thermostatic` pattern structurally (immutable concretely-typed struct,
# throw-based constructor guards, promotion outer constructor) but conforms to the
# Phase-3 AGGREGATABLE-DEVICE contract (aggregator-as-writer, DEV-05): `contribute!`
# builds its variables + the energy-window coupling constraint on `ctx.model` and RETURNS
# `(; vars, p_inject, utility)` — it writes NOTHING to `ctx.residuals` and calls NO
# `add_to_objective!`. The Aggregator (plan 03-05) is the sole network-facing writer.
# Network-agnostic: holds only a bus id + scalar parameters, never a Feeder.

using JuMP

"""
    Deferrable{T<:Real} <: AbstractDevice

A deferrable / shiftable flexible load (DEV-02): a task (washer, EV charge) that draws an
energy budget within the band `[E_min, E]` somewhere inside a contiguous time window
`[t_start, t_end]`, drawing zero outside it (thesis eqs. 3.4–3.5)

    E_min ≤ Σ_{t ∈ [t_start,t_end]} p[t] ≤ E ,   0 ≤ p[t] ≤ Pmax (t in window), p[t]=0 (else)

and derives the concave-quadratic utility (eq. 3.12, constant `c` dropped — RESEARCH A5)

    U(p) = − (b/2)·( Σ_{t ∈ window} p[t] − E )²                             (3.12)

The upper budget is an INEQUALITY (thesis eq. 3.4 `E_max` role), NOT a hard equality (WR-01):
this makes the utility a LIVE soft target — `U` peaks at `Σ p = E` and penalizes consuming
less, so the load reaches the budget when energy is cheap but backs off (Σ p < E) when the
network price is high. The strictly-positive curvature `b > 0` keeps `U` concave (welfare
stays a convex QP) AND sets how strongly the load insists on reaching `E` versus saving money
— with the earlier hard equality `Σ p == E`, `U ≡ 0` on the feasible set and `b` was a dead
parameter. The lower bound `E_min` (thesis eq. 3.4 `E_min` role) is the **must-complete
floor**: `E_min = 0` is a purely elastic deferrable load (may consume nothing when prices are
high); `E_min > 0` is a task that MUST consume at least that much energy (e.g. an EV that has
to charge), so only the slack `[E_min, E]` is traded against price. A deferrable load is
indifferent to *when* it runs within the window (the utility depends only on the total),
which this still captures. All quantities are in the single model per-unit system.

# Fields
- `bus::Int` — the bus id the load withdraws at (the ONLY topology handle a device holds;
  it never sees the network object — network-agnostic, DEV-05).
- `t_start::Int`, `t_end::Int` — inclusive window bounds (eq. 3.5 `T_{h,d}`); require
  `1 ≤ t_start ≤ t_end`.
- `E::T` — upper energy-budget target over the window (thesis `E_max`, eq. 3.4); the total
  draw satisfies `Σ p ≤ E` and the utility peaks at `Σ p = E`; require
  `0 ≤ E ≤ Pmax·(t_end−t_start+1)`.
- `Pmax::T` — per-hour power bound (eq. 3.5).
- `b::T` — utility curvature, `b > 0` required for concavity (eq. 3.12).
- `E_min::T` — must-complete energy floor (thesis `E_min`, eq. 3.4); keyword, default `0`;
  the total draw satisfies `Σ p ≥ E_min`; require `0 ≤ E_min ≤ E`.

Construction throws `ArgumentError` when `b ≤ 0` (concavity guard, threat T-03-06), when
the window is inconsistent (`t_start < 1` or `t_end < t_start`), when the energy budget is
infeasible/negative (`E < 0` or `E > Pmax·window_length`) — the temporal-infeasibility
guard, threat T-03-07 — or when the floor is out of band (`E_min < 0` or `E_min > E`).
"""
struct Deferrable{T<:Real} <: AbstractDevice
    bus::Int
    t_start::Int
    t_end::Int
    E::T
    Pmax::T
    b::T
    E_min::T

    function Deferrable(
        bus::Int,
        t_start::Int,
        t_end::Int,
        E::T,
        Pmax::T,
        b::T;
        E_min::T = zero(T),
    ) where {T<:Real}
        # Concavity guard (thesis eq. 3.12, b > 0): a non-positive curvature makes the
        # utility convex → welfare maximization unbounded/non-convex. Threat T-03-06.
        if b <= zero(T)
            throw(
                ArgumentError(
                    "Deferrable utility curvature b must be > 0 for concavity " *
                    "(thesis eq. 3.12); got b=$b",
                ),
            )
        end
        # Window consistency (eq. 3.5): a contiguous, non-empty window starting at hour ≥ 1.
        if t_start < 1 || t_end < t_start
            throw(
                ArgumentError(
                    "Deferrable window requires 1 ≤ t_start ≤ t_end (thesis eq. 3.5); " *
                    "got t_start=$t_start, t_end=$t_end",
                ),
            )
        end
        # Energy-budget feasibility (eq. 3.4 `E_min ≤ Σp ≤ E_max`): the band must be
        # reachable within the window at Pmax, non-negative, and ordered. `E_min` is the
        # must-complete floor (0 = purely elastic; > 0 = a task that MUST consume at least
        # this much energy, e.g. an EV charge). Threat T-03-07 (reject infeasibility at build).
        window_length = t_end - t_start + 1
        if E < zero(T) || E > Pmax * window_length
            throw(
                ArgumentError(
                    "Deferrable energy budget E (E_max) must satisfy 0 ≤ E ≤ " *
                    "Pmax·window_length = $(Pmax * window_length) (thesis eq. 3.4); " *
                    "got E=$E, Pmax=$Pmax, window_length=$window_length",
                ),
            )
        end
        if E_min < zero(T) || E_min > E
            throw(
                ArgumentError(
                    "Deferrable must-complete floor E_min must satisfy 0 ≤ E_min ≤ E " *
                    "(thesis eq. 3.4 lower band); got E_min=$E_min, E=$E",
                ),
            )
        end
        return new{T}(bus, t_start, t_end, E, Pmax, b, E_min)
    end
end

"""
    Deferrable(bus, t_start, t_end, E, Pmax, b; E_min = 0)

Convenience outer constructor (IN-01): PROMOTEs the numeric parameters `E`, `Pmax`, `b`,
`E_min` to a common `Real` type before delegating to the inner constructor, so a natural
mixed-type call (e.g. an integer budget among `Float64`s) just works instead of throwing a
`MethodError`. `bus`, `t_start`, `t_end` are converted to `Int`. `E_min` defaults to 0 (a
purely elastic deferrable load); pass `E_min > 0` for a must-complete task. When `E`,
`Pmax`, `b` already share a type and `E_min` is omitted, the inner constructor is strictly
more specific and is selected directly (no promotion, no recursion).
"""
function Deferrable(
    bus::Integer,
    t_start::Integer,
    t_end::Integer,
    E::Real,
    Pmax::Real,
    b::Real;
    E_min::Real = 0,
)
    Ep, Pmaxp, bp, Eminp = promote(E, Pmax, b, E_min)
    return Deferrable(Int(bus), Int(t_start), Int(t_end), Ep, Pmaxp, bp; E_min = Eminp)
end

"""
    contribute!(d::Deferrable, ctx::ModelContext; T::Int)

Contribute the deferrable load into the shared model context over the horizon `t = 1:T`,
conforming to the Phase-3 AGGREGATABLE-DEVICE contract (aggregator-as-writer, DEV-05). It:

1. creates a per-hour power variable `0 ≤ p[t] ≤ Pmax` inside the window and `p[t] = 0`
   outside it (bounds pinned to zero — eq. 3.5) on `ctx.model`, validating that the window
   fits the horizon (`t_end ≤ T`, throwing `ArgumentError` otherwise — the
   temporal-infeasibility guard, threat T-03-07);
2. adds the energy-within-window budget BAND coupling `E_min ≤ Σ_{t ∈ [t_start,t_end]} p[t]
   ≤ E` (thesis eq. 3.4; upper bound an inequality — WR-01, NOT an equality; lower bound
   `E_min` added only when `E_min > 0`, the must-complete floor) — the inter-temporal
   coupling; and
3. builds the concave-quadratic utility `− (b/2)·(Σ p[t] − E)²` (eq. 3.12) as a `QuadExpr`,
   a LIVE soft target at `E` now that the budget above is an inequality.

It then RETURNS `(; vars = (; p), p_inject, utility)` where `p_inject[t] = −p[t]` is the
signed ACTIVE injection (a consumed load is a NEGATIVE injection, matching the
`Interruptible` sign convention; outside the window `p[t]` is pinned to 0 so the injection
is 0). The device writes NOTHING to `ctx.residuals` and calls NO `add_to_objective!`: the
Aggregator consumes this tuple and is the sole `:Rp`/`:Rq` writer. The device references
only `d.bus` (never the network), so the power-flow swap leaves this code untouched.
"""
function contribute!(d::Deferrable, ctx::ModelContext; T::Int)
    # Temporal-infeasibility guard (threat T-03-07): the window must fit the horizon.
    if d.t_end > T
        throw(
            ArgumentError(
                "Deferrable window end t_end=$(d.t_end) exceeds horizon T=$T " *
                "(thesis eq. 3.5)",
            ),
        )
    end

    m = ctx.model
    # Per-hour power: bounded in [0,Pmax] inside the window, pinned to 0 outside (eq. 3.5).
    p = @variable(
        m,
        [t = 1:T],
        lower_bound = 0.0,
        upper_bound = (d.t_start <= t <= d.t_end ? d.Pmax : 0.0),
    )

    # Energy-within-window budget BAND (thesis eq. 3.4 `E_min ≤ Σp ≤ E_max`) — the
    # inter-temporal coupling. WR-01: the UPPER bound `Σ p ≤ E` is an INEQUALITY (not a hard
    # equality), so the soft utility below is a LIVE preference and `b` genuinely shapes the
    # solution. The LOWER bound `Σ p ≥ E_min` is the must-complete floor: with `E_min = 0`
    # the load is purely elastic (can consume nothing when prices are high); with `E_min > 0`
    # it MUST consume at least that much (e.g. an EV that has to charge), trading only the
    # slack `[E_min, E]` against price.
    total_energy = sum(p[t] for t in d.t_start:d.t_end)
    @constraint(m, total_energy <= d.E)
    if d.E_min > zero(d.E_min)
        @constraint(m, total_energy >= d.E_min)
    end

    # Concave-quadratic utility (eq. 3.12, constant c dropped — RESEARCH A5): a soft target
    # at `E` (thesis `E_max`). The negative semidefinite quadratic form keeps it concave;
    # built as a QuadExpr so curvature holds. Because the budget above is now an inequality,
    # this term is a LIVE preference (0 only when the load actually reaches Σ p = E), so `b`
    # trades reaching the target against the price the network charges for consumption.
    utility = -(d.b / 2) * (total_energy - d.E)^2

    # Signed ACTIVE injection: a deferrable task is a load ⇒ NEGATIVE injection −p
    # (Interruptible sign convention). Returned to the aggregator, NOT written here.
    p_inject = AffExpr[-p[t] for t in 1:T]

    return (; vars = (; p), p_inject, utility)
end

export Deferrable
