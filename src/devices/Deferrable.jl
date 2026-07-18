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

A deferrable / shiftable flexible load (DEV-02): a task (washer, EV charge) that must draw
a fixed energy budget `E` somewhere inside a contiguous time window `[t_start, t_end]`,
drawing zero outside it (thesis eqs. 3.4–3.5)

    Σ_{t ∈ [t_start, t_end]} p[t] == E ,    0 ≤ p[t] ≤ Pmax  (t in window),  p[t] = 0 (else)

and derives the concave-quadratic utility (eq. 3.12, constant `c` dropped — RESEARCH A5)

    U(p) = − (b/2)·( Σ_{t ∈ window} p[t] − E )²                             (3.12)

The strictly-positive curvature `b > 0` keeps `U` concave, so the assembled welfare stays
a convex QP. On the feasible set the budget equality is met exactly, so this utility is a
soft target consistent with 3.12 (with `E` in the role of the thesis `E_max`); a pure
deferrable load is indifferent to *when* it runs so long as the budget is met inside the
window, which this captures. All quantities are in the single model per-unit system.

# Fields
- `bus::Int` — the bus id the load withdraws at (the ONLY topology handle a device holds;
  it never sees the network object — network-agnostic, DEV-05).
- `t_start::Int`, `t_end::Int` — inclusive window bounds (eq. 3.5 `T_{h,d}`); require
  `1 ≤ t_start ≤ t_end`.
- `E::T` — energy budget over the window (eq. 3.4); require `0 ≤ E ≤ Pmax·(t_end−t_start+1)`.
- `Pmax::T` — per-hour power bound (eq. 3.5).
- `b::T` — utility curvature, `b > 0` required for concavity (eq. 3.12).

Construction throws `ArgumentError` when `b ≤ 0` (concavity guard, threat T-03-06), when
the window is inconsistent (`t_start < 1` or `t_end < t_start`), or when the energy budget
is infeasible/negative (`E < 0` or `E > Pmax·window_length`) — the temporal-infeasibility
guard, threat T-03-07.
"""
struct Deferrable{T<:Real} <: AbstractDevice
    bus::Int
    t_start::Int
    t_end::Int
    E::T
    Pmax::T
    b::T

    function Deferrable(
        bus::Int,
        t_start::Int,
        t_end::Int,
        E::T,
        Pmax::T,
        b::T,
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
        # Energy-budget feasibility (eq. 3.4): the budget must be reachable within the
        # window at Pmax and non-negative. Threat T-03-07 (reject infeasibility at build).
        window_length = t_end - t_start + 1
        if E < zero(T) || E > Pmax * window_length
            throw(
                ArgumentError(
                    "Deferrable energy budget E must satisfy 0 ≤ E ≤ Pmax·window_length " *
                    "= $(Pmax * window_length) (thesis eq. 3.4); got E=$E, Pmax=$Pmax, " *
                    "window_length=$window_length",
                ),
            )
        end
        return new{T}(bus, t_start, t_end, E, Pmax, b)
    end
end

"""
    Deferrable(bus, t_start, t_end, E, Pmax, b)

Convenience outer constructor (IN-01): PROMOTEs the numeric parameters `E`, `Pmax`, `b`
to a common `Real` type before delegating to the inner constructor, so a natural
mixed-type call (e.g. an integer budget among `Float64`s) just works instead of throwing a
`MethodError`. `bus`, `t_start`, `t_end` are converted to `Int`. When `E`, `Pmax`, `b`
already share a type the inner constructor is strictly more specific and is selected
directly (no promotion, no recursion).
"""
Deferrable(bus::Integer, t_start::Integer, t_end::Integer, E::Real, Pmax::Real, b::Real) =
    Deferrable(Int(bus), Int(t_start), Int(t_end), promote(E, Pmax, b)...)

"""
    contribute!(d::Deferrable, ctx::ModelContext; T::Int)

Contribute the deferrable load into the shared model context over the horizon `t = 1:T`,
conforming to the Phase-3 AGGREGATABLE-DEVICE contract (aggregator-as-writer, DEV-05). It:

1. creates a per-hour power variable `0 ≤ p[t] ≤ Pmax` inside the window and `p[t] = 0`
   outside it (bounds pinned to zero — eq. 3.5) on `ctx.model`, validating that the window
   fits the horizon (`t_end ≤ T`, throwing `ArgumentError` otherwise — the
   temporal-infeasibility guard, threat T-03-07);
2. adds the energy-within-window budget coupling constraint
   `Σ_{t ∈ [t_start,t_end]} p[t] == E` (eqs. 3.4–3.5) — the inter-temporal coupling; and
3. builds the concave-quadratic utility `− (b/2)·(Σ p[t] − E)²` (eq. 3.12) as a `QuadExpr`.

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

    # Energy-within-window budget (thesis eqs. 3.4–3.5) — the inter-temporal coupling.
    @constraint(m, sum(p[t] for t in d.t_start:d.t_end) == d.E)

    # Concave-quadratic utility (eq. 3.12, constant c dropped — RESEARCH A5). The negative
    # semidefinite quadratic form keeps it concave; built as a QuadExpr so curvature holds.
    utility = -(d.b / 2) * (sum(p[t] for t in d.t_start:d.t_end) - d.E)^2

    # Signed ACTIVE injection: a deferrable task is a load ⇒ NEGATIVE injection −p
    # (Interruptible sign convention). Returned to the aggregator, NOT written here.
    p_inject = AffExpr[-p[t] for t in 1:T]

    return (; vars = (; p), p_inject, utility)
end

export Deferrable
