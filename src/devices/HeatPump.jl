# src/devices/HeatPump.jl
#
# SEAM: heat-pump flexible-load device with a 2R2C building thermal model.
#
# An `AbstractDevice` implementing an electric heat pump heating a building described by the
# standard 2R2C ("TiTe") equivalent circuit: an indoor-air temperature `Tin` and an
# envelope-mass temperature `Tem`, coupled to each other and to the ambient by a LINEAR
# recursion. The heat delivered is `COP[t]·p[t]` with `COP` an EXOGENOUS per-step vector, so
# the model stays convex and binary-free (no endogenous Carnot expression, no Parameter seam
# for COP). The 2R2C topology follows the Kircher / Bacher-Madsen RC lineage (MEDIUM
# bibliographic confidence — see the phase-43 research notes); this file does not claim a
# specific paper's parameter values.
#
# DELIBERATE DEVIATION from `Thermostatic.jl` (which stays untouched — byte-identical golden
# policy): Thermostatic's 1-state recursion covers `t = 1:(T-1)`; the HeatPump follows the
# whole-horizon (PVBattery) rule — both states exist on `1:(T+1)`, the recursion runs
# `t = 1:T`, and the comfort band applies through `T+1`. Conforms to the AGGREGATABLE-DEVICE
# contract (aggregator-as-writer): `contribute!` builds variables + constraints on
# `ctx.model` and RETURNS `(; vars, p_inject, utility)`; it writes NOTHING to `ctx.residuals`
# and calls NO `add_to_objective!`. Network-agnostic: holds a bus id + parameters only.

using JuMP

"""
    HeatPump{T<:Real} <: AbstractDevice

An electric heat pump heating a building modelled as a 2R2C circuit. It draws electric power
`p[t] ∈ [0, Pmax]` (heating convention) and delivers heat `COP[t]·p[t]`. The two temperature
states evolve by the coupled Forward-Euler recursion (`t = 1:T`)

    Tin[t+1] = Tin[t] + α_ie·(Tem[t] − Tin[t]) + α_ia·(Tout[t] − Tin[t]) + β·COP[t]·p[t]
    Tem[t+1] = Tem[t] + α_me·(Tin[t] − Tem[t]) + α_ma·(Tout[t] − Tem[t])

with indoor air `Tin` held in the hard comfort band `Tmin ≤ Tin ≤ Tmax` for `t = 1:(T+1)`,
the envelope mass `Tem` in a wide physical band `[Tem_min, Tem_max]`, and the concave
comfort utility `U = −(b/2)·Σ_{t=1:T} (Tin[t] − Tmin)²` with `b > 0` (convex QP welfare).
All quantities are in the single model per-unit system; coefficients are not rescaled.

# Fields

  - `bus::Int` — the bus id (the ONLY topology handle; network-agnostic).
  - `α_ie`, `α_ia` — air↔envelope and air↔ambient coupling fractions (`≥ 0`).
  - `α_me`, `α_ma` — envelope↔air and envelope↔ambient coupling fractions (`≥ 0`).
  - `β::T` — electric-to-temperature gain per unit COP (`β > 0` so heating RAISES `Tin`; a
    non-positive `β` silently flips heating into cooling).
  - `Tmin`, `Tmax` — indoor comfort band (`Tmin < Tmax`).
  - `Tem_min`, `Tem_max` — envelope-mass physical band (`Tem_min < Tem_max`).
  - `Tin0`, `Tem0` — initial states, each inside its own band.
  - `Pmax::T` — heat-pump electric power bound, `Pmax > 0`.
  - `b::T` — comfort-utility curvature, `b > 0`.
  - `Tout::Vector{T}`, `COP::Vector{T}` — exogenous ambient and coefficient-of-performance
    profiles; both lengths are validated against the horizon `T` at `contribute!`.
  - `φ::Union{Nothing,T}` — optional per-device power-factor override (eq. 3.23), in `(0, 1]`.
  - `terminal::Union{Nothing,T,Symbol}` — joint terminal rule for BOTH states at `T+1`:
    `nothing` leaves them free (within bands), a `Real` pins both `Tin[T+1]` and `Tem[T+1]`
    to that value, `:cyclic` closes each state onto its own initial condition.

# Discretization and the stability guard

The recursion is Forward-Euler (maximal traceability to `Thermostatic`). Euler is only
well-behaved when the discrete update is diagonally dominant, i.e. each state keeps a
non-negative weight on itself: `α_ie + α_ia ≤ 1` and `α_me + α_ma ≤ 1`. Otherwise the
recursion overshoots and diverges, turning a feasible comfort band into an infeasible one.
This guard is LOAD-BEARING: the constructor throws `ArgumentError` for either violation.

Construction also throws on: `b ≤ 0`, `Pmax ≤ 0`, inconsistent bands, any negative `α`,
`β ≤ 0`, an initial state outside its band, `φ ∉ (0, 1]`, or a `terminal` that is not
`nothing`, `:cyclic`, or a value inside BOTH bands.
"""
struct HeatPump{T <: Real} <: AbstractDevice
    bus::Int
    α_ie::T
    α_ia::T
    α_me::T
    α_ma::T
    β::T
    Tmin::T
    Tmax::T
    Tem_min::T
    Tem_max::T
    Tin0::T
    Tem0::T
    Pmax::T
    b::T
    Tout::Vector{T}
    COP::Vector{T}
    φ::Union{Nothing, T}
    terminal::Union{Nothing, T, Symbol}

    function HeatPump(
        bus::Int,
        α_ie::T,
        α_ia::T,
        α_me::T,
        α_ma::T,
        β::T,
        Tmin::T,
        Tmax::T,
        Tem_min::T,
        Tem_max::T,
        Tin0::T,
        Tem0::T,
        Pmax::T,
        b::T,
        Tout::Vector{T},
        COP::Vector{T},
        φ::Union{Nothing, T},
        terminal::Union{Nothing, T, Symbol},
    ) where {T <: Real}
        if b <= zero(T)
            throw(
                ArgumentError(
                    "HeatPump comfort-utility curvature b must be > 0 for concavity " *
                    "(thesis eqs. 3.11/3.14); got b=$b",
                ),
            )
        end
        if !(Tmin < Tmax)
            throw(
                ArgumentError(
                    "HeatPump comfort band requires Tmin < Tmax; got Tmin=$Tmin, Tmax=$Tmax",
                ),
            )
        end
        if !(Tem_min < Tem_max)
            throw(
                ArgumentError(
                    "HeatPump envelope band requires Tem_min < Tem_max; got " *
                    "Tem_min=$Tem_min, Tem_max=$Tem_max",
                ),
            )
        end
        if Pmax <= zero(T)
            throw(ArgumentError("HeatPump power bound Pmax must be > 0; got Pmax=$Pmax"))
        end
        # Physical-sign guards, one per coefficient so the message names the culprit.
        for (name, val) in (("α_ie", α_ie), ("α_ia", α_ia), ("α_me", α_me), ("α_ma", α_ma))
            if val < zero(T)
                throw(
                    ArgumentError(
                        "HeatPump thermal coupling $name must be ≥ 0; a negative coupling " *
                        "reverses heat flow (non-physical); got $name=$val",
                    ),
                )
            end
        end
        if β <= zero(T)
            throw(
                ArgumentError(
                    "HeatPump power-to-temperature gain β must be > 0 so that power HEATS " *
                    "the indoor air; a non-positive β silently flips heating/cooling; " *
                    "got β=$β",
                ),
            )
        end
        # Forward-Euler stability (diagonal dominance of the discrete update).
        if α_ie + α_ia > one(T)
            throw(
                ArgumentError(
                    "HeatPump Euler stability requires α_ie + α_ia ≤ 1 (indoor-air state " *
                    "must keep a non-negative self-weight, else the recursion overshoots); " *
                    "got α_ie + α_ia = $(α_ie + α_ia)",
                ),
            )
        end
        if α_me + α_ma > one(T)
            throw(
                ArgumentError(
                    "HeatPump Euler stability requires α_me + α_ma ≤ 1 (envelope-mass " *
                    "state must keep a non-negative self-weight, else the recursion " *
                    "overshoots); got α_me + α_ma = $(α_me + α_ma)",
                ),
            )
        end
        if !(Tmin <= Tin0 <= Tmax)
            throw(
                ArgumentError(
                    "HeatPump initial indoor temperature must satisfy Tmin ≤ Tin0 ≤ Tmax " *
                    "(comfort-band IC); got Tmin=$Tmin, Tin0=$Tin0, Tmax=$Tmax",
                ),
            )
        end
        if !(Tem_min <= Tem0 <= Tem_max)
            throw(
                ArgumentError(
                    "HeatPump initial envelope temperature must satisfy Tem_min ≤ Tem0 ≤ " *
                    "Tem_max; got Tem_min=$Tem_min, Tem0=$Tem0, Tem_max=$Tem_max",
                ),
            )
        end
        if φ !== nothing && !(zero(T) < φ <= one(T))
            throw(
                ArgumentError(
                    "HeatPump power-factor override φ must lie in (0, 1] " *
                    "(thesis eq. 3.23); got φ=$φ",
                ),
            )
        end
        if terminal isa Symbol
            if terminal !== :cyclic
                throw(
                    ArgumentError(
                        "HeatPump terminal must be nothing, :cyclic, or a Real; " *
                        "got terminal=:$terminal",
                    ),
                )
            end
        elseif terminal !== nothing
            # A pinned value applies to BOTH states, so it must lie in both bands.
            if !(Tmin <= terminal <= Tmax) || !(Tem_min <= terminal <= Tem_max)
                throw(
                    ArgumentError(
                        "HeatPump pinned terminal=$terminal must lie inside both the " *
                        "comfort band [$Tmin, $Tmax] and the envelope band " *
                        "[$Tem_min, $Tem_max]",
                    ),
                )
            end
        end
        return new{T}(
            bus,
            α_ie,
            α_ia,
            α_me,
            α_ma,
            β,
            Tmin,
            Tmax,
            Tem_min,
            Tem_max,
            Tin0,
            Tem0,
            Pmax,
            b,
            Tout,
            COP,
            φ,
            terminal,
        )
    end
end

# A HeatPump's own consumption draws power-factor reactive power via the Aggregator
# roll-up (thesis eq. 3.23); has_reactive_decision follows from this by the 43-01 default.
is_flexible_load(::HeatPump) = true

"""
    HeatPump(bus, α_ie, α_ia, α_me, α_ma, β, Tmin, Tmax, Tem_min, Tem_max, Tin0, Tem0,
             Pmax, b, Tout, COP; φ = nothing, terminal = nothing)

Convenience outer constructor: PROMOTEs every scalar and the `Tout`/`COP` element types to a
common `Real` type before delegating to the inner constructor. The optional `φ` and
`terminal` keywords may be `nothing` (or `:cyclic` for `terminal`) and so are converted
separately into the common type when they are `Real`.
"""
function HeatPump(
    bus::Integer,
    α_ie::Real,
    α_ia::Real,
    α_me::Real,
    α_ma::Real,
    β::Real,
    Tmin::Real,
    Tmax::Real,
    Tem_min::Real,
    Tem_max::Real,
    Tin0::Real,
    Tem0::Real,
    Pmax::Real,
    b::Real,
    Tout::AbstractVector{<:Real},
    COP::AbstractVector{<:Real};
    φ::Union{Nothing, Real} = nothing,
    terminal::Union{Nothing, Real, Symbol} = nothing,
)
    Tp = promote_type(
        typeof(α_ie),
        typeof(α_ia),
        typeof(α_me),
        typeof(α_ma),
        typeof(β),
        typeof(Tmin),
        typeof(Tmax),
        typeof(Tem_min),
        typeof(Tem_max),
        typeof(Tin0),
        typeof(Tem0),
        typeof(Pmax),
        typeof(b),
        eltype(Tout),
        eltype(COP),
    )
    φp = φ === nothing ? nothing : convert(Tp, φ)
    termp = (terminal === nothing || terminal isa Symbol) ? terminal : convert(Tp, terminal)
    return HeatPump(
        Int(bus),
        convert(Tp, α_ie),
        convert(Tp, α_ia),
        convert(Tp, α_me),
        convert(Tp, α_ma),
        convert(Tp, β),
        convert(Tp, Tmin),
        convert(Tp, Tmax),
        convert(Tp, Tem_min),
        convert(Tp, Tem_max),
        convert(Tp, Tin0),
        convert(Tp, Tem0),
        convert(Tp, Pmax),
        convert(Tp, b),
        convert(Vector{Tp}, Tout),
        convert(Vector{Tp}, COP),
        φp,
        termp,
    )
end

"""
    contribute!(d::HeatPump, ctx::ModelContext; T::Int)

Contribute the heat pump into the shared model over `t = 1:T`, conforming to the
AGGREGATABLE-DEVICE contract. It creates `p[t] ∈ [0, Pmax]` (`t = 1:T`), the banded states
`Tin[t] ∈ [Tmin, Tmax]` and `Tem[t] ∈ [Tem_min, Tem_max]` for `t = 1:(T+1)`, the anonymous
initial-condition Parameters `Tin0`, `Tem0` (`Tin[1] == Tin0`, `Tem[1] == Tem0`), the coupled
2R2C recursion for `t = 1:T`, and the optional joint terminal rule. `length(Tout) ≥ T` and
`length(COP) ≥ T` are validated (`ArgumentError` otherwise — a short profile must never
silently truncate the horizon). Every JuMP object is ANONYMOUS so several heat pumps share
one model without name collisions.

RETURNS `(; vars = (; p, Tin, Tem, Tin0, Tem0), p_inject, utility)` with
`p_inject[t] = −p[t]` (a heating load is a negative injection) and
`utility = −(b/2)·Σ_{t=1:T}(Tin[t] − Tmin)²` as a `QuadExpr`. Writes nothing to
`ctx.residuals` and calls no `add_to_objective!`.
"""
function contribute!(d::HeatPump, ctx::ModelContext; T::Int)
    if length(d.Tout) < T
        throw(
            ArgumentError(
                "HeatPump ambient profile Tout has length $(length(d.Tout)) < horizon T=$T",
            ),
        )
    end
    if length(d.COP) < T
        throw(
            ArgumentError(
                "HeatPump COP profile has length $(length(d.COP)) < horizon T=$T " *
                "(COP is an exogenous per-step vector)",
            ),
        )
    end

    m = ctx.model
    p = @variable(m, [t = 1:T], lower_bound = zero(d.Pmax), upper_bound = d.Pmax)
    Tin = @variable(m, [t = 1:(T + 1)], lower_bound = d.Tmin, upper_bound = d.Tmax)
    Tem = @variable(m, [t = 1:(T + 1)], lower_bound = d.Tem_min, upper_bound = d.Tem_max)

    # ICs as ANONYMOUS Parameters (a named container would collide for a second instance).
    Tin0 = @variable(m, set = Parameter(d.Tin0))
    Tem0 = @variable(m, set = Parameter(d.Tem0))
    @constraint(m, Tin[1] == Tin0)
    @constraint(m, Tem[1] == Tem0)

    # Coupled 2R2C recursion, whole horizon t = 1:T (states reach T+1).
    @constraint(
        m,
        [t = 1:T],
        Tin[t + 1] ==
        Tin[t] +
        d.α_ie * (Tem[t] - Tin[t]) +
        d.α_ia * (d.Tout[t] - Tin[t]) +
        d.β * d.COP[t] * p[t]
    )
    @constraint(
        m,
        [t = 1:T],
        Tem[t + 1] == Tem[t] + d.α_me * (Tin[t] - Tem[t]) + d.α_ma * (d.Tout[t] - Tem[t])
    )

    # Joint terminal rule on BOTH states.
    if d.terminal === :cyclic
        @constraint(m, Tin[T + 1] == Tin0)
        @constraint(m, Tem[T + 1] == Tem0)
    elseif d.terminal !== nothing
        @constraint(m, Tin[T + 1] == d.terminal)
        @constraint(m, Tem[T + 1] == d.terminal)
    end

    utility = sum(-(d.b / 2) * (Tin[t] - d.Tmin)^2 for t in 1:T)
    p_inject = AffExpr[-p[t] for t in 1:T]

    return (; vars = (; p, Tin, Tem, Tin0, Tem0), p_inject, utility)
end

export HeatPump
