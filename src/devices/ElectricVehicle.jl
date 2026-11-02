# src/devices/ElectricVehicle.jl
#
# SEAM: electric-vehicle (EV) prosumer device -- V1G smart charging with an OPT-IN V2G leg.
#
# An `AbstractDevice` implementing one EV session: continuous charge (and, for V2G, discharge)
# power inside an arrival/departure window, a battery SOC recursion with efficiency η, a SOC band,
# and a SOFT departure-energy target. It is the PVBattery storage anatomy (thesis eqs. 3.6, 3.8,
# 3.9: SOC recursion with η·p_ch in / p_dch/η out, power bounds, SOC band + initial condition)
# with three EV-specific differences:
#
#   1. SESSION WINDOWS ARE HARD ZERO-UPPER BOUNDS. `p_ch[t]` (and V2G `p_dch[t]`) get
#      `upper_bound = (in_window(t) ? Pmax : 0.0)` -- the `Deferrable` window idiom (thesis eq.
#      3.5). Pure variable bounds: no big-M, no mask variable, no binary. An overnight session
#      that wraps the horizon edge (`t_dep < t_arr`) is the UNION `t >= t_arr ∪ t <= t_dep` of two
#      intervals -- still pure bounds.
#   2. A SOFT DEPARTURE TARGET. A shortfall variable `s >= 0` with `s >= E_target - soc[t_dep+1]`
#      and a welfare penalty `-(κ/2)·s²` (quadratic, matching the codebase's QuadExpr utility
#      style). The target can always be missed at a price, so the device is always feasible.
#   3. V2G (`v2g = true`) adds a `p_dch` leg whose utility carries a STRICTLY positive linear
#      degradation cost `-c_deg·Σ p_dch`.
#
# NO BINARY -- the no-binary argument, RE-EARNED for the EV. No constraint forbids
# `p_ch[t]·p_dch[t] > 0`; adding one (or a charge/discharge mode binary) would break QP convexity
# and destroy the duals the transactive prices ARE. V1G has no `p_dch` variable at all, so the
# question does not arise. For V2G the App. C argument (thesis pp. 166-168) carries over with the
# SAME strict λ_min < λ_med < λ_max parametrization (concave charge utility, convex discharge
# cost, both with strictly positive curvature) PLUS the strictly positive linear cost c_deg:
# the marginal charge benefit never exceeds the marginal discharge cost, and with η² < 1 any
# SOC-neutral round trip is strictly wasteful -- AT NON-NEGATIVE EFFECTIVE PRICES. The repo's own
# App. C η<1 finding (welfare_solve.jl:309-321; FourQuadBESS.jl's grid-charging derivation)
# shows the argument implicitly assumes η = 1: at a sufficiently NEGATIVE effective price an
# SOC-neutral round trip earns (1 - η²)(λ_med + |λ|) - η²·c_deg > 0 and simultaneous
# charge/discharge IS the KKT-consistent optimum. Hence c_deg > 0 is necessary but NOT
# sufficient, and `assert_ev_complementarity!` (models/complementarity_ev.jl) is a MANDATORY
# post-solve certificate that REPORTS it (honesty policy: the report is the certificate working).
# c_deg = 0 is rejected at construction because it would re-enable free round-trip economics.
#
# AGGREGATABLE-device contract (identical to PVBattery): writes NOTHING to ctx.residuals and
# calls NO add_to_objective!; it RETURNS `(; vars, p_inject, utility)`. ACTIVE-ONLY: no `q_inject`
# (Assumption A1), `is_flexible_load` stays the default `false`. Every JuMP object it creates is
# ANONYMOUS (no object-dictionary names) so any number of EVs coexist in one model. Network-
# agnostic: bus + parameters only, never a Feeder.

using JuMP

"""
    ElectricVehicle{T<:Real} <: AbstractDevice

A single EV charging session (V1G) with an opt-in V2G discharge leg. Over a horizon `t = 1:T`
it schedules `p_ch[t] ≥ 0` (and, if `v2g`, `p_dch[t] ≥ 0`) and the state of charge `soc[t]`:

    soc[t+1] = soc[t] + (η·p_ch[t] − p_dch[t]/η)·Δt            # SOC dynamics (3.6), t = 1:T
    0 ≤ p_ch[t] ≤ (in_window(t) ? Pmax : 0)                     # session window as bounds (3.5/3.8)
    Emin ≤ soc[t] ≤ Emax, t = 1:(T+1) ;  soc[1] = soc0         # SOC band + arrival IC (3.9)
    s ≥ 0,  s ≥ E_target − soc[t_dep+1]                        # soft departure target

`in_window(t)` is `t_arr ≤ t ≤ t_dep` when `t_arr ≤ t_dep`, else (wrap / overnight session)
`t ≥ t_arr || t ≤ t_dep`. The recursion closes the WHOLE horizon `t = 1:T` (so `soc` is `T+1`
long and hour-`T` charge is never free energy).

The preference is the App. C charge utility, the quadratic shortfall penalty, and (V2G only) the
discharge cost with the strictly positive degradation term:

    utility = Σ_t ( a_ch·p_ch − (b_ch/2)·p_ch² )  −  (κ/2)·s²
              [ − Σ_t ( a_dch·p_dch + (b_dch/2)·p_dch² + c_deg·p_dch ) ]      # V2G leg only

    a_ch = a_dch = λ_med ;  b_ch = (λ_med − λ_min)/Pmax ;  b_dch = (λ_max − λ_med)/Pmax

# Fields

  - `bus::Int` — the bus id (the only topology handle).
  - `η::T` — one-way-squared efficiency parameter, `η ∈ (0,1]` (3.6).
  - `Δt::T` — time-step length (h).
  - `Pmax::T` — charge (and V2G discharge) power bound inside the window, `Pmax > 0`.
  - `Emin::T`, `Emax::T` — SOC band; `soc0::T` — arrival SOC, `Emin ≤ soc0 ≤ Emax`.
  - `E_target::T` — departure energy target, `Emin ≤ E_target ≤ Emax` (soft).
  - `κ::T` — shortfall penalty weight, `κ ≥ 0`.
  - `λ_min::T`, `λ_med::T`, `λ_max::T` — App. C price triple, STRICT `λ_min < λ_med < λ_max`.
  - `t_arr::Int`, `t_dep::Int` — session window, `≥ 1` and `t_arr ≠ t_dep` (the upper bound `T` is
    re-guarded by `contribute!`).
  - `v2g::Bool` — opt-in V2G discharge leg. `c_deg::T` — degradation cost, strictly `> 0` iff `v2g`.

Construction throws `ArgumentError` on any violated invariant (never `@assert`).
"""
struct ElectricVehicle{T <: Real} <: AbstractDevice
    bus::Int
    η::T
    Δt::T
    Pmax::T
    Emin::T
    Emax::T
    soc0::T
    E_target::T
    κ::T
    λ_min::T
    λ_med::T
    λ_max::T
    t_arr::Int
    t_dep::Int
    v2g::Bool
    c_deg::T

    function ElectricVehicle(
        bus::Int,
        η::T,
        Δt::T,
        Pmax::T,
        Emin::T,
        Emax::T,
        soc0::T,
        E_target::T,
        κ::T,
        λ_min::T,
        λ_med::T,
        λ_max::T,
        t_arr::Int,
        t_dep::Int,
        v2g::Bool,
        c_deg::T,
    ) where {T <: Real}
        # App. C strict ordering: makes b_ch, b_dch > 0 so the dominance argument is strict.
        if !(λ_min < λ_med < λ_max)
            throw(
                ArgumentError(
                    "ElectricVehicle requires STRICT λ_min < λ_med < λ_max (App. C no-binary " *
                    "sufficient condition); got λ_min=$λ_min, λ_med=$λ_med, λ_max=$λ_max",
                ),
            )
        end
        if Pmax <= zero(T)
            throw(
                ArgumentError(
                    "ElectricVehicle power bound Pmax must be > 0; got Pmax=$Pmax",
                ),
            )
        end
        if !(zero(T) < η <= one(T))
            throw(
                ArgumentError(
                    "ElectricVehicle efficiency η must lie in (0, 1] (eq. 3.6); got η=$η",
                ),
            )
        end
        if !(Emin <= Emax)
            throw(
                ArgumentError(
                    "ElectricVehicle SOC band must satisfy Emin ≤ Emax; got Emin=$Emin, Emax=$Emax",
                ),
            )
        end
        if !(Emin <= soc0 <= Emax)
            throw(
                ArgumentError(
                    "ElectricVehicle arrival SOC must satisfy Emin ≤ soc0 ≤ Emax (eq. 3.9 IC); " *
                    "got Emin=$Emin, soc0=$soc0, Emax=$Emax",
                ),
            )
        end
        if !(Emin <= E_target <= Emax)
            throw(
                ArgumentError(
                    "ElectricVehicle departure target must satisfy Emin ≤ E_target ≤ Emax; " *
                    "got Emin=$Emin, E_target=$E_target, Emax=$Emax",
                ),
            )
        end
        if κ < zero(T)
            throw(
                ArgumentError("ElectricVehicle shortfall penalty κ must be ≥ 0; got κ=$κ"),
            )
        end
        if t_arr < 1 || t_dep < 1
            throw(
                ArgumentError(
                    "ElectricVehicle session indices must be ≥ 1; got t_arr=$t_arr, t_dep=$t_dep",
                ),
            )
        end
        if t_arr == t_dep
            throw(
                ArgumentError(
                    "ElectricVehicle session must have t_arr ≠ t_dep (degenerate session); " *
                    "got t_arr=t_dep=$t_arr",
                ),
            )
        end
        # V2G needs a STRICTLY positive degradation cost: c_deg = 0 silently re-enables free
        # round-trip economics (the first half of the no-binary justification).
        if v2g && !(c_deg > zero(T))
            throw(
                ArgumentError(
                    "ElectricVehicle V2G requires a STRICTLY positive degradation cost " *
                    "c_deg > 0 (c_deg = 0 re-enables free round-trip economics); got c_deg=$c_deg",
                ),
            )
        end
        return new{T}(
            bus,
            η,
            Δt,
            Pmax,
            Emin,
            Emax,
            soc0,
            E_target,
            κ,
            λ_min,
            λ_med,
            λ_max,
            t_arr,
            t_dep,
            v2g,
            c_deg,
        )
    end
end

"""
    ElectricVehicle(bus, η, Δt, Pmax, Emin, Emax, soc0, E_target, κ, λ_min, λ_med, λ_max,
                    t_arr, t_dep; v2g = false, c_deg = 0.0)

Convenience outer constructor: promotes the scalar parameters to one common `Real` type, converts
`bus`/`t_arr`/`t_dep` to `Int`, and delegates to the throw-guarded inner constructor. V1G is the
default; `v2g = true` requires `c_deg > 0`.
"""
function ElectricVehicle(
    bus::Integer,
    η::Real,
    Δt::Real,
    Pmax::Real,
    Emin::Real,
    Emax::Real,
    soc0::Real,
    E_target::Real,
    κ::Real,
    λ_min::Real,
    λ_med::Real,
    λ_max::Real,
    t_arr::Integer,
    t_dep::Integer;
    v2g::Bool = false,
    c_deg::Real = 0.0,
)
    T = promote_type(
        typeof(η),
        typeof(Δt),
        typeof(Pmax),
        typeof(Emin),
        typeof(Emax),
        typeof(soc0),
        typeof(E_target),
        typeof(κ),
        typeof(λ_min),
        typeof(λ_med),
        typeof(λ_max),
        typeof(c_deg),
    )
    return ElectricVehicle(
        Int(bus),
        T(η),
        T(Δt),
        T(Pmax),
        T(Emin),
        T(Emax),
        T(soc0),
        T(E_target),
        T(κ),
        T(λ_min),
        T(λ_med),
        T(λ_max),
        Int(t_arr),
        Int(t_dep),
        v2g,
        T(c_deg),
    )
end

# Session-window membership; supports the wrap (overnight) case t_dep < t_arr.
_ev_in_window(t::Int, t_arr::Int, t_dep::Int) =
    t_arr <= t_dep ? (t_arr <= t <= t_dep) : (t >= t_arr || t <= t_dep)

"""
    contribute!(d::ElectricVehicle, ctx::ModelContext; T::Int,
                soc_terminal::Union{Nothing,Real,Symbol} = nothing)

Contribute the EV into the shared model context over `t = 1:T` under the AGGREGATABLE contract:
own variables and constraints on `ctx.model`; NOTHING written to `ctx.residuals`, NO
`add_to_objective!`. Returns `(; vars, p_inject, utility)` with `p_inject[t] = p_dch[t] − p_ch[t]`
(V1G: `−p_ch[t]`) and a concave `QuadExpr` utility. `vars` is `(; p_ch, soc, soc0)` for V1G and
`(; p_ch, p_dch, soc, soc0)` for V2G; `soc0` is an anonymous `Parameter` (receding-horizon seam).

Creates no binary/integer variable. The session must fit the horizon: `1 ≤ t_arr, t_dep ≤ T`
(`ArgumentError` otherwise). `soc_terminal` behaves exactly as in `PVBattery.contribute!`
(`nothing` | `Real` | `:cyclic` against the SAME `soc0` Parameter) and is orthogonal to the soft
departure target at `soc[t_dep+1]`.
"""
function contribute!(
    d::ElectricVehicle,
    ctx::ModelContext;
    T::Int,
    soc_terminal::Union{Nothing, Real, Symbol} = nothing,
)
    if soc_terminal isa Symbol && soc_terminal !== :cyclic
        throw(
            ArgumentError(
                "ElectricVehicle.contribute!'s soc_terminal keyword accepts nothing, a Real " *
                "value, or :cyclic only; got Symbol :$soc_terminal",
            ),
        )
    end
    # Temporal guard (Deferrable idiom): the session must fit the horizon.
    if d.t_arr > T || d.t_dep > T
        throw(
            ArgumentError(
                "ElectricVehicle session (t_arr=$(d.t_arr), t_dep=$(d.t_dep)) exceeds " *
                "horizon T=$T",
            ),
        )
    end
    m = ctx.model

    # Continuous variables ONLY. The window is a zero upper bound outside the session.
    p_ch = @variable(
        m,
        [t = 1:T],
        lower_bound = 0.0,
        upper_bound = (_ev_in_window(t, d.t_arr, d.t_dep) ? d.Pmax : 0.0),
    )
    p_dch = if d.v2g
        @variable(
            m,
            [t = 1:T],
            lower_bound = 0.0,
            upper_bound = (_ev_in_window(t, d.t_arr, d.t_dep) ? d.Pmax : 0.0),
        )
    else
        nothing
    end
    soc = @variable(m, [t = 1:(T + 1)], lower_bound = d.Emin, upper_bound = d.Emax)
    # Anonymous scalar Parameter (a named one collides on the 2nd EV in the same model).
    soc0 = @variable(m, set = Parameter(d.soc0))
    @constraint(m, soc[1] == soc0)

    # Whole-horizon SOC recursion t = 1:T (closes on soc[T+1]).
    if d.v2g
        @constraint(
            m,
            [t = 1:T],
            soc[t + 1] == soc[t] + (d.η * p_ch[t] - p_dch[t] / d.η) * d.Δt
        )
    else
        @constraint(m, [t = 1:T], soc[t + 1] == soc[t] + (d.η * p_ch[t]) * d.Δt)
    end
    if soc_terminal isa Real
        @constraint(m, soc[T + 1] == soc_terminal)
    elseif soc_terminal === :cyclic
        @constraint(m, soc[T + 1] >= soc0)
    end

    # Soft departure target: shortfall epigraph, always feasible.
    s = @variable(m, lower_bound = 0.0)
    @constraint(m, s >= d.E_target - soc[d.t_dep + 1])

    a_ch = d.λ_med
    b_ch = (d.λ_med - d.λ_min) / d.Pmax
    charge_utility = @expression(
        m,
        sum(a_ch * p_ch[t] - (b_ch / 2) * p_ch[t]^2 for t in 1:T) - (d.κ / 2) * s^2
    )
    utility = if d.v2g
        a_dch = d.λ_med
        b_dch = (d.λ_max - d.λ_med) / d.Pmax
        @expression(
            m,
            charge_utility -
            sum((a_dch + d.c_deg) * p_dch[t] + (b_dch / 2) * p_dch[t]^2 for t in 1:T)
        )
    else
        charge_utility
    end

    p_inject = if d.v2g
        [p_dch[t] - p_ch[t] for t in 1:T]
    else
        [-1.0 * p_ch[t] for t in 1:T]
    end

    vars = d.v2g ? (; p_ch, p_dch, soc, soc0) : (; p_ch, soc, soc0)
    return (; vars, p_inject, utility)
end

export ElectricVehicle
