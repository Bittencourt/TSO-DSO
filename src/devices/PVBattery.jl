# src/devices/PVBattery.jl
#
# SEAM: PV + battery (BESS) prosumer device (DEV-04).
# OWNER: plan 03-04.
#
# An `AbstractDevice` implementing a co-located PV generator and battery with
# continuous charge/discharge and SOC dynamics (thesis eqs. 3.6-3.9): SOC
# recursion with round-trip efficiency, charge limited by available PV (3.7),
# discharge/charge power bounds (3.8), SOC band (3.9). Utility is a concave charge
# utility minus a convex discharge cost (eqs. 3.15-3.20). CRITICAL: NO binary and
# NO p_ch*p_dch==0 constraint -- the App. C parametrization (λ_min <= λ_med <=
# λ_max) makes simultaneous charge/discharge strictly dominated, so p_ch[t]*p_dch[t]
# = 0 holds at the optimum; this must be VERIFIED numerically post-solve
# (p_ch*p_dch < τ). This is the AGGREGATABLE-device variant of the `Interruptible`
# pattern: it writes NOTHING to ctx.residuals and calls NO add_to_objective! -- it
# RETURNS its (; vars, p_inject, utility) terms for the Aggregator (DEV-05, plan
# 03-05) to roll up. Network-agnostic (bus + parameters only; never a Feeder).

using JuMP

"""
    PVBattery{T<:Real} <: AbstractDevice

A co-located PV + battery (BESS) prosumer device (DEV-04). Over a horizon `t = 1:T`
it schedules continuous charge `p_ch[t] ≥ 0`, discharge `p_dch[t] ≥ 0`, and
state-of-charge `soc[t]`, subject to (thesis eqs. 3.6-3.9):

    soc[t+1] = soc[t] + (η·p_ch[t] − p_dch[t]/η)·Δt         # SOC dynamics (3.6)
    0 ≤ p_ch[t] ≤ Ppv[t]                                    # PV-limited charge (3.7, A6)
    0 ≤ p_ch[t], p_dch[t] ≤ Pmax                            # power bounds (3.8)
    Emin ≤ soc[t] ≤ Emax ;  soc[1] = soc0                   # SOC band + IC (3.9)

Its preference is a concave charge utility minus a convex discharge cost, whose
coefficients are the App. C parametrization (eqs. 3.15-3.20):

    a_ch  = λ_med ;  b_ch  = (λ_med − λ_min)/Pmax           # charge utility (3.15,3.17,3.18)
    a_dch = λ_med ;  b_dch = (λ_max − λ_med)/Pmax           # discharge cost (3.16,3.19,3.20)
    utility = Σ_t ( a_ch·p_ch − (b_ch/2)·p_ch²
                    − a_dch·p_dch − (b_dch/2)·p_dch² )

# The no-binary correctness argument (App. C, pp. 166-168)

There is **no** binary and **no** `p_ch·p_dch == 0` complementarity constraint — adding
one would break QP convexity and destroy the duals Phase-5 pricing relies on. Instead,
with `λ_min ≤ λ_med ≤ λ_max` the marginal charge benefit
`∂U_ch/∂p_ch = λ_med − b_ch·p_ch ≤ λ_med` never exceeds the marginal discharge cost
`∂C_dch/∂p_dch = λ_med + b_dch·p_dch ≥ λ_med`, so any round-trip through the battery is
(weakly) non-improving and, with round-trip efficiency `η² < 1`, strictly wasteful. Hence
the optimum has `p_ch[t]·p_dch[t] = 0` for every `t` **without** any complementarity
constraint. Because correctness rests entirely on this parametrization (the
`λ_min ≤ λ_med ≤ λ_max` inner-constructor guard is the load-bearing invariant), it is a
HARD requirement to VERIFY it numerically after every solve:
`value(p_ch[t])·value(p_dch[t]) < τ` (RESEARCH Pitfall 1, threat T-03-09).

# Aggregatable-device contract (LOCKED: aggregator-as-writer)

Unlike the self-injecting `Interruptible`, this device is network-agnostic to the point of
writing NOTHING to `ctx.residuals` and calling NO `add_to_objective!`. `contribute!`
RETURNS `(; vars, p_inject, utility)`; the `Aggregator` (DEV-05) is the sole `:Rp`/`:Rq`
writer and the utility roll-up point.

# Fields
- `bus::Int`   — the bus id the device sits at (the ONLY topology handle it holds; it never
  sees the network object or line parameters).
- `η::T`       — round-trip charge/discharge efficiency, `η ∈ (0,1]` (3.6). `η² < 1` for a
  real battery drives the strict energy-waste half of the App. C argument.
- `Δt::T`      — time-step length (h) for the SOC recursion (3.6).
- `Pmax::T`    — charge/discharge power bound (3.8), `Pmax > 0`.
- `Emin::T`, `Emax::T` — SOC band (3.9).
- `soc0::T`    — initial state of charge, `Emin ≤ soc0 ≤ Emax` (3.9 IC).
- `λ_min::T`, `λ_med::T`, `λ_max::T` — App. C price triple; `λ_min ≤ λ_med ≤ λ_max` is the
  sufficient condition for `p_ch·p_dch = 0` (the load-bearing guard, threat T-03-09).
- `Ppv::Vector{T}` — per-step PV-availability profile (pu power); `p_ch[t] ≤ Ppv[t]` (3.7,
  Assumption A6: the battery charges from PV only, not the grid). Must have `length ≥ T`.

Construction throws `ArgumentError` unless `λ_min ≤ λ_med ≤ λ_max` (App. C guard),
`Pmax > 0`, `η ∈ (0,1]`, and `Emin ≤ soc0 ≤ Emax`.
"""
struct PVBattery{T<:Real} <: AbstractDevice
    bus::Int
    η::T
    Δt::T
    Pmax::T
    Emin::T
    Emax::T
    soc0::T
    λ_min::T
    λ_med::T
    λ_max::T
    Ppv::Vector{T}

    function PVBattery(
        bus::Int,
        η::T,
        Δt::T,
        Pmax::T,
        Emin::T,
        Emax::T,
        soc0::T,
        λ_min::T,
        λ_med::T,
        λ_max::T,
        Ppv::Vector{T},
    ) where {T<:Real}
        # App. C sufficient condition (the load-bearing guard, threat T-03-09): with the
        # price triple ordered, the charge-utility marginal (≤ λ_med) never beats the
        # discharge-cost marginal (≥ λ_med), so p_ch·p_dch = 0 holds at the optimum with
        # NO binary/complementarity constraint. Reject LOUDLY otherwise (project
        # convention: throw, never @assert — @assert can be elided under -O).
        if !(λ_min <= λ_med <= λ_max)
            throw(
                ArgumentError(
                    "PVBattery requires λ_min ≤ λ_med ≤ λ_max (App. C no-binary sufficient " *
                    "condition, pp. 166-168); got λ_min=$λ_min, λ_med=$λ_med, λ_max=$λ_max",
                ),
            )
        end
        if Pmax <= zero(T)
            throw(
                ArgumentError(
                    "PVBattery power bound Pmax must be > 0 (eq. 3.8, and it divides the " *
                    "utility curvatures 3.17-3.20); got Pmax=$Pmax",
                ),
            )
        end
        if !(zero(T) < η <= one(T))
            throw(
                ArgumentError(
                    "PVBattery round-trip efficiency η must lie in (0, 1] (eq. 3.6); got η=$η",
                ),
            )
        end
        if !(Emin <= soc0 <= Emax)
            throw(
                ArgumentError(
                    "PVBattery initial SOC must satisfy Emin ≤ soc0 ≤ Emax (eq. 3.9 IC); " *
                    "got Emin=$Emin, soc0=$soc0, Emax=$Emax",
                ),
            )
        end
        return new{T}(bus, η, Δt, Pmax, Emin, Emax, soc0, λ_min, λ_med, λ_max, Ppv)
    end
end

"""
    PVBattery(bus, η, Δt, Pmax, Emin, Emax, soc0, λ_min, λ_med, λ_max, Ppv)

Convenience outer constructor (IN-01): `promote`s the scalar parameters and the `Ppv`
element type to a common `Real` type before delegating to the inner constructor, so a
natural mixed-type call (e.g. an integer `Pmax` among `Float64`s, or an `Int`-eltype
`Ppv`) just works instead of throwing a confusing `MethodError`. `bus` is converted to
`Int`. When every parameter already shares a concrete type `T` (with `Ppv::Vector{T}`) the
inner constructor is strictly more specific and is selected directly (no promotion, no
recursion).
"""
function PVBattery(
    bus::Integer,
    η::Real,
    Δt::Real,
    Pmax::Real,
    Emin::Real,
    Emax::Real,
    soc0::Real,
    λ_min::Real,
    λ_med::Real,
    λ_max::Real,
    Ppv::AbstractVector{<:Real},
)
    T = promote_type(
        typeof(η),
        typeof(Δt),
        typeof(Pmax),
        typeof(Emin),
        typeof(Emax),
        typeof(soc0),
        typeof(λ_min),
        typeof(λ_med),
        typeof(λ_max),
        eltype(Ppv),
    )
    return PVBattery(
        Int(bus),
        T(η),
        T(Δt),
        T(Pmax),
        T(Emin),
        T(Emax),
        T(soc0),
        T(λ_min),
        T(λ_med),
        T(λ_max),
        Vector{T}(Ppv),
    )
end

"""
    contribute!(d::PVBattery, ctx::ModelContext; T::Int)

Contribute the PV+battery into the shared model context over `t = 1:T`, following the
AGGREGATABLE-device contract: it builds its own variables and temporal-coupling
constraints on `ctx.model` but writes NOTHING to `ctx.residuals` and calls NO
`add_to_objective!`. Instead it RETURNS `(; vars, p_inject, utility)` for the `Aggregator`
(DEV-05) to roll up.

It creates continuous `0 ≤ p_ch[t], p_dch[t] ≤ Pmax` and `Emin ≤ soc[t] ≤ Emax` — and
**no** binary/integer variable — then adds the SOC recursion (3.6), the PV-limited charge
`p_ch[t] ≤ Ppv[t]` (3.7, requires `length(Ppv) ≥ T`), the SOC band + IC `soc[1] == soc0`
(3.9), and the App. C utility (3.15-3.20). It adds NO `p_ch·p_dch == 0` constraint —
App. C (pp. 166-168) makes it unnecessary; the caller MUST verify `p_ch·p_dch < τ`
numerically post-solve.

Returns `(; vars = (; p_ch, p_dch, soc), p_inject, utility)` where
`p_inject[t] = Ppv[t] − p_ch[t] + p_dch[t]` (PV export − charge draw + discharge) is a
`Vector{AffExpr}` and `utility` is a `QuadExpr` (concave charge utility − convex discharge
cost).
"""
function contribute!(d::PVBattery, ctx::ModelContext; T::Int)
    length(d.Ppv) >= T || throw(
        ArgumentError(
            "PVBattery.Ppv must have length ≥ T for the PV-limited charge (eq. 3.7); " *
            "got length(Ppv)=$(length(d.Ppv)), T=$T",
        ),
    )
    m = ctx.model

    # Continuous decision variables ONLY — NO binary/integer (App. C keeps this a QP).
    p_ch = @variable(m, [t = 1:T], lower_bound = 0.0, upper_bound = d.Pmax)   # (3.8)
    p_dch = @variable(m, [t = 1:T], lower_bound = 0.0, upper_bound = d.Pmax)  # (3.8)
    soc = @variable(m, [t = 1:T], lower_bound = d.Emin, upper_bound = d.Emax) # (3.9)

    @constraint(m, soc[1] == d.soc0)                                          # (3.9 IC)
    if T > 1
        # SOC dynamics with round-trip efficiency (3.6): η·p_ch in, p_dch/η out (η² < 1).
        @constraint(
            m,
            [t = 1:(T - 1)],
            soc[t + 1] == soc[t] + (d.η * p_ch[t] - p_dch[t] / d.η) * d.Δt
        )
    end
    # PV-limited charge (3.7, Assumption A6: charge from PV only, never the grid).
    @constraint(m, [t = 1:T], p_ch[t] <= d.Ppv[t])

    # App. C utility parametrization (3.15-3.20): concave charge utility, convex discharge
    # cost. b_ch, b_dch ≥ 0 follow from λ_min ≤ λ_med ≤ λ_max (constructor guard); the
    # strict ordering makes them > 0 and the p_ch·p_dch = 0 dominance strict.
    a_ch = d.λ_med
    b_ch = (d.λ_med - d.λ_min) / d.Pmax                                       # (3.17-3.18)
    a_dch = d.λ_med
    b_dch = (d.λ_max - d.λ_med) / d.Pmax                                      # (3.19-3.20)

    # Concave charge utility − convex discharge cost → a concave QuadExpr contribution.
    # Routed to the RETURN value (not add_to_objective!) so the Aggregator sums it.
    utility = @expression(
        m,
        sum(
            a_ch * p_ch[t] - (b_ch / 2) * p_ch[t]^2 - a_dch * p_dch[t] -
            (b_dch / 2) * p_dch[t]^2 for t in 1:T
        )
    )

    # Signed active injection at the device's bus (for the Aggregator's :Rp): PV export is
    # positive, the charge draw is a withdrawal (−p_ch), discharge is a source (+p_dch).
    p_inject = [d.Ppv[t] - p_ch[t] + p_dch[t] for t in 1:T]

    return (; vars = (; p_ch, p_dch, soc), p_inject, utility)
end

export PVBattery
