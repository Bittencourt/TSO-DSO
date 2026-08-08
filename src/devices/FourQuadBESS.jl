# src/devices/FourQuadBESS.jl
#
# SEAM: four-quadrant (P,Q) battery + inverter device (MESH-04).
# OWNER: plan 19-02.
#
# A standalone battery + 4-quadrant inverter `AbstractDevice` (D-01: NO PV field — PV-owning
# prosumers keep using `PVBattery` alongside this device). Its inverter can inject/absorb BOTH
# active and reactive power within an apparent-power cone `p²+q²≤Smax²` (D-03: q is free, no
# cost/utility term — its price is purely the reactive nodal dual μ, plan 19-07). Grid charging
# is permitted with an explicit, asymmetric charge/discharge cap (D-02/D-04: `Pch_max≠Pdch_max`
# is legal — unlike `PVBattery`'s Assumption-A6 PV-only charge). This is the AGGREGATABLE-device
# variant of the `PVBattery` pattern: it writes NOTHING to `ctx.residuals` and calls NO
# `add_to_objective!` — it RETURNS its `(; vars, p_inject, q_inject, utility)` terms for the
# `Aggregator` (DEV-05) to roll up, via D-09's widened optional-`q_inject` contract.

using JuMP

"""
    FourQuadBESS{T<:Real} <: AbstractDevice

A standalone battery + four-quadrant (4Q) inverter prosumer device (MESH-04). Over a
horizon `t = 1:T` it schedules continuous charge `p_ch[t] ≥ 0`, discharge `p_dch[t] ≥ 0`,
state-of-charge `soc[t]`, and a sign-free reactive decision `q[t]`, subject to:

    soc[t+1] = soc[t] + (η·p_ch[t] − p_dch[t]/η)·Δt         # SOC dynamics (mirrors PVBattery 3.6)
    0 ≤ p_ch[t]  ≤ Pch_max                                  # charge bound, GRID-chargeable (D-02)
    0 ≤ p_dch[t] ≤ Pdch_max                                 # discharge bound, INDEPENDENT cap (D-04)
    Emin ≤ soc[t] ≤ Emax ;  soc[1] = soc0                   # SOC band + IC (mirrors PVBattery 3.9)
    (p_dch[t] − p_ch[t])² + q[t]² ≤ Smax²                   # apparent-power cone (D-03/D-04)

Unlike `PVBattery`, there is **no** curtailable-PV-availability field and **no**
PV-limited-charge bound (D-01/D-02): this device may import from the grid to charge, capped
only by `Pch_max`. Its
preference is the same App. C-shaped concave charge utility minus convex discharge cost, but
with the INDEPENDENT `Pch_max`/`Pdch_max` as the curvature denominators (instead of one shared
`Pmax`):

    a_ch  = λ_med ;  b_ch  = (λ_med − λ_min)/Pch_max
    a_dch = λ_med ;  b_dch = (λ_max − λ_med)/Pdch_max
    utility = Σ_t ( a_ch·p_ch − (b_ch/2)·p_ch² − a_dch·p_dch − (b_dch/2)·p_dch² )

with **no** `q` term anywhere (D-03) — `q`'s only role is inside the apparent-power cone.

# The re-derived complementarity argument (4Q, grid-charging) — MESH-04 clause 2

`PVBattery`'s App. C argument (pp. 166-168, see `PVBattery.jl:42-57`) is a PURE
ACTIVE-POWER, one-dimensional argument: with the strict ordering `λ_min < λ_med < λ_max`,
the marginal charge benefit never exceeds `λ_med` and the marginal discharge cost never
falls below it, so any simultaneous `p_ch, p_dch > 0` is strictly dominated. That
conclusion does **not** transfer here automatically merely because the field names match —
it must be re-earned for the 4Q, grid-charging case (RESEARCH.md's "Complementarity
Derivation Skeleton," re-derived below in four steps):

 1. **The internal argument is unchanged in form.** `q` never enters the objective (D-03),
    and the apparent-power cone only RESTRICTS the achievable range of the net active power
    `p = p_dch − p_ch` as a function of `|q|` (`|p| ≤ √(Smax² − q²)`) — it never rewards a
    *particular* `(p_ch, p_dch)` split for a fixed net `p`. So for a FIXED net `p`, the
    objective's dependence on `(p_ch, p_dch)` is still the SAME separable, one-dimensional
    marginal-charge-benefit-vs-marginal-discharge-cost comparison at `λ_med` that App. C
    makes — which is exactly why the constructor STILL requires the strict
    `λ_min < λ_med < λ_max` ordering: this internal, fixed-net-`p` dominance argument is
    load-bearing here too, unchanged in form.
 2. **The genuinely new failure mode is D-02's removal of the PV-limited-charge bound**, not
    the reactive cone directly. Without `PVBattery`'s charge-from-available-PV-only bound
    (Assumption A6, deliberately not inherited), `p_ch` is driven by the GRID price rather
    than only by available PV — which reopens whether this device's OWN internal indifference
    price
    `λ_med` can be strictly ordered against the EXTERNAL effective nodal price it actually
    faces (the ADMM dual `λ_j[t]`, or `dual(:balance_p[j,t])` centrally), not just against its
    own internal `λ_min/λ_max` triple.
 3. **When the effective external nodal price is NEGATIVE**, the DSO effectively PAYS to
    inject (a high-PV reverse-flow regime, the same family of regime `v2.1`'s `EXACT-04`
    found interesting for a different reason). There, grid-charging combined with
    round-trip-efficiency energy-burning (`η² < 1`: simultaneous `p_ch, p_dch > 0`, net
    `p ≈ 0`, gross throughput `> 0`) becomes a way to ABSORB MORE negatively-priced energy
    than the net-power bound alone would permit. That is NOT dominated once the external
    price enters the picture — unlike App. C's purely-internal argument, which never faced an
    external price at all.
 4. **This is why the guarantee is NOT a constructor-time invariant.** Unlike `PVBattery`'s
    strict-ordering guard — a SUFFICIENT condition the constructor can verify without knowing
    the future nodal price — the failure mode above depends on the SOLVED price, which is
    unknown at construction time. The mandatory check is therefore a POST-SOLVE numeric
    certificate (plan 19-05's `assert_4q_complementarity!`, D-05's "both routes"), and it is
    EXPECTED to legitimately throw in the negative-effective-price + grid-charging regime —
    an honest boundary (D-08), not a bug, when it does.

# Aggregatable-device contract (widened, D-09)

Like `PVBattery`, this device is network-agnostic: `contribute!` writes NOTHING to
`ctx.residuals` and calls NO `add_to_objective!`, instead RETURNING
`(; vars, p_inject, q_inject, utility)` for the `Aggregator` to roll up. The NEW
`q_inject` field (D-09) is this device's signed reactive injection — the FIRST
aggregatable device to carry one; see `AbstractDevice.jl` for the widened contract note.

# Fields

  - `bus::Int`      — the bus id the device sits at (never sees the network object).
  - `η::T`          — round-trip charge/discharge efficiency, `η ∈ (0,1]`.
  - `Δt::T`         — time-step length (h) for the SOC recursion.
  - `Pch_max::T`    — charge power bound, `Pch_max > 0`. INDEPENDENT of `Pdch_max` (D-02:
    "grid charging, capped" — this device may import from the grid to charge, unlike
    `PVBattery`'s Assumption-A6 PV-only charge, so `Pch_max` is NOT limited by any PV
    availability).
  - `Pdch_max::T`   — discharge power bound, `Pdch_max > 0`. INDEPENDENT of `Pch_max`
    (D-04: genuinely asymmetric caps, `Pch_max ≠ Pdch_max` is legal).
  - `Smax::T`       — apparent-power cone bound, `Smax > 0` (`p²+q²≤Smax²`).
  - `Emin::T`, `Emax::T` — SOC band.
  - `soc0::T`       — initial state of charge, `Emin ≤ soc0 ≤ Emax`.
  - `λ_min::T`, `λ_med::T`, `λ_max::T` — App. C-style price triple; the **strict** ordering
    `λ_min < λ_med < λ_max` is still required (see derivation step 1 above — the INTERNAL,
    fixed-net-`p` dominance argument is unchanged in form and still load-bearing).

Construction throws `ArgumentError` unless `Pch_max > 0`, `Pdch_max > 0` (checked
INDEPENDENTLY — D-04), `Smax > 0`, `η ∈ (0,1]`, `Emin ≤ soc0 ≤ Emax`, and the strict
`λ_min < λ_med < λ_max` ordering.
"""
struct FourQuadBESS{T <: Real} <: AbstractDevice
    bus::Int
    η::T
    Δt::T
    Pch_max::T
    Pdch_max::T
    Smax::T
    Emin::T
    Emax::T
    soc0::T
    λ_min::T
    λ_med::T
    λ_max::T

    function FourQuadBESS(
        bus::Int,
        η::T,
        Δt::T,
        Pch_max::T,
        Pdch_max::T,
        Smax::T,
        Emin::T,
        Emax::T,
        soc0::T,
        λ_min::T,
        λ_med::T,
        λ_max::T,
    ) where {T <: Real}
        # D-02/D-04: charge and discharge caps are INDEPENDENT — asymmetric caps means BOTH
        # must be checked, never one shared `Pmax` guard. Reject LOUDLY (project convention:
        # throw, never @assert — @assert elides under -O).
        if Pch_max <= zero(T)
            throw(
                ArgumentError(
                    "FourQuadBESS charge power bound Pch_max must be > 0 (MESH-04, D-02: " *
                    "grid-charging is capped but never non-positive); got Pch_max=$Pch_max",
                ),
            )
        end
        if Pdch_max <= zero(T)
            throw(
                ArgumentError(
                    "FourQuadBESS discharge power bound Pdch_max must be > 0 (MESH-04, " *
                    "D-04: independent of Pch_max); got Pdch_max=$Pdch_max",
                ),
            )
        end
        if Smax <= zero(T)
            throw(
                ArgumentError(
                    "FourQuadBESS apparent-power cone bound Smax must be > 0 " *
                    "(p²+q²≤Smax², MESH-04 D-03/D-04); got Smax=$Smax",
                ),
            )
        end
        if !(zero(T) < η <= one(T))
            throw(
                ArgumentError(
                    "FourQuadBESS round-trip efficiency η must lie in (0, 1]; got η=$η",
                ),
            )
        end
        if !(Emin <= soc0 <= Emax)
            throw(
                ArgumentError(
                    "FourQuadBESS initial SOC must satisfy Emin ≤ soc0 ≤ Emax; " *
                    "got Emin=$Emin, soc0=$soc0, Emax=$Emax",
                ),
            )
        end
        # CR-01 analog (see the docstring's step-1 re-derivation): the INTERNAL, fixed-net-p
        # dominance argument is UNCHANGED IN FORM from App. C and is STILL load-bearing, so
        # the STRICT λ_min < λ_med < λ_max ordering is still a hard requirement here.
        if !(λ_min < λ_med < λ_max)
            throw(
                ArgumentError(
                    "FourQuadBESS requires STRICT λ_min < λ_med < λ_max (MESH-04 D-05: the " *
                    "internal, fixed-net-p dominance argument re-derives App. C's " *
                    "no-binary conclusion unchanged in form; a non-strict ordering zeroes a " *
                    "utility curvature and admits p_ch·p_dch > 0 co-optima); got " *
                    "λ_min=$λ_min, λ_med=$λ_med, λ_max=$λ_max",
                ),
            )
        end
        return new{T}(bus, η, Δt, Pch_max, Pdch_max, Smax, Emin, Emax, soc0, λ_min, λ_med, λ_max)
    end
end

"""
    FourQuadBESS(bus, η, Δt, Pch_max, Pdch_max, Smax, Emin, Emax, soc0, λ_min, λ_med, λ_max)

Convenience outer constructor (IN-01): `promote`s the scalar parameters to a common
`Real` type before delegating to the inner constructor, so a natural mixed-type call
(e.g. an integer `Smax` among `Float64`s) just works instead of throwing a confusing
`MethodError`. `bus` is converted to `Int`. When every parameter already shares a
concrete type `T`, the inner constructor is strictly more specific and is selected
directly (no promotion, no recursion).
"""
function FourQuadBESS(
    bus::Integer,
    η::Real,
    Δt::Real,
    Pch_max::Real,
    Pdch_max::Real,
    Smax::Real,
    Emin::Real,
    Emax::Real,
    soc0::Real,
    λ_min::Real,
    λ_med::Real,
    λ_max::Real,
)
    T = promote_type(
        typeof(η),
        typeof(Δt),
        typeof(Pch_max),
        typeof(Pdch_max),
        typeof(Smax),
        typeof(Emin),
        typeof(Emax),
        typeof(soc0),
        typeof(λ_min),
        typeof(λ_med),
        typeof(λ_max),
    )
    return FourQuadBESS(
        Int(bus),
        T(η),
        T(Δt),
        T(Pch_max),
        T(Pdch_max),
        T(Smax),
        T(Emin),
        T(Emax),
        T(soc0),
        T(λ_min),
        T(λ_med),
        T(λ_max),
    )
end

"""
    contribute!(d::FourQuadBESS, ctx::ModelContext; T::Int)

Contribute the 4Q battery into the shared model context over `t = 1:T`, following the
AGGREGATABLE-device contract (mirrors `PVBattery.contribute!`'s shape, minus the PV
coupling — D-01/D-02): it builds its own variables and temporal-coupling constraints on
`ctx.model` but writes NOTHING to `ctx.residuals` and calls NO `add_to_objective!`.
Instead it RETURNS `(; vars, p_inject, q_inject, utility)` for the `Aggregator` (DEV-05)
to roll up, via D-09's widened optional-`q_inject` contract.

It creates continuous `0 ≤ p_ch[t] ≤ Pch_max`, `0 ≤ p_dch[t] ≤ Pdch_max` (INDEPENDENT
caps, D-04), `Emin ≤ soc[t] ≤ Emax`, and a FREE (unbounded) `q[t]` (D-03: no cost/utility
term on reactive power) — and **no** binary/integer variable, and **no** curtailable-PV
coupling anywhere (D-01/D-02: this device may charge from the
grid, capped only by `Pch_max`). It adds the SOC recursion + IC (mirrors `PVBattery`'s
eq. 3.6/3.9), the App. C-shaped utility (with `Pch_max`/`Pdch_max` as the INDEPENDENT
curvature denominators — no `q` term anywhere, D-03), and ONE apparent-power second-order
cone constraint per `t` tying `Smax`, the net active expression `p_dch[t] − p_ch[t]`, and
`q[t]` together (D-03/D-04). Mirroring `PVBattery`'s
device-level constraints, this cone is NOT registered via `register_constraint!` — only
network-level `ConvexBranchFlow` constraints are registered (see PATTERNS.md).

Returns `(; vars = (; p_ch, p_dch, soc, q), p_inject, q_inject, utility)` where
`p_inject[t] == p_dch[t] − p_ch[t]` (a `Vector{AffExpr}`) and `q_inject === vars.q` (the
SAME `Vector{VariableRef}` object, D-09) — the FIRST aggregatable device to carry a
`q_inject` field; see `AbstractDevice.jl`'s widened Variant-2 contract note.
"""
function contribute!(d::FourQuadBESS, ctx::ModelContext; T::Int)
    m = ctx.model

    # Continuous decision variables ONLY — NO binary/integer (App. C keeps this a QP/SOCP).
    p_ch = @variable(m, [t = 1:T], lower_bound = 0.0, upper_bound = d.Pch_max)   # (D-02/D-04)
    p_dch = @variable(m, [t = 1:T], lower_bound = 0.0, upper_bound = d.Pdch_max) # (D-04)
    soc = @variable(m, [t = 1:T], lower_bound = d.Emin, upper_bound = d.Emax)
    # q is sign-free and carries NO bound — the apparent-power cone below is its only
    # restriction (D-03: no cost/utility term on reactive power anywhere).
    q = @variable(m, [t = 1:T])

    @constraint(m, soc[1] == d.soc0)
    if T > 1
        # SOC dynamics with round-trip efficiency (mirrors PVBattery eq. 3.6): η·p_ch in,
        # p_dch/η out (η² < 1).
        @constraint(
            m,
            [t = 1:(T - 1)],
            soc[t + 1] == soc[t] + (d.η * p_ch[t] - p_dch[t] / d.η) * d.Δt
        )
    end

    # Net active injection at the device (discharge is a source, charge a withdrawal) — the
    # quantity that enters the apparent-power cone alongside q (D-03/D-04).
    p_net = @expression(m, [t = 1:T], p_dch[t] - p_ch[t])

    # Apparent-power cone (D-03/D-04): p²+q²≤Smax² ⟺ ‖(p_net,q)‖₂ ≤ Smax — the SAME idiom
    # already shipped in `ConvexBranchFlow.jl`'s per-branch `smax` limit. Un-registered
    # (device-level, mirrors PVBattery's un-registered constraints — only network-level
    # ConvexBranchFlow constraints are registered).
    @constraint(m, cone[t = 1:T], [d.Smax, p_net[t], q[t]] in SecondOrderCone())

    # App. C-shaped utility (concave charge benefit, convex discharge cost), but with the
    # INDEPENDENT Pch_max/Pdch_max as the curvature denominators (D-04). NO `q` term
    # anywhere (D-03) — q's only role is inside the cone above.
    a_ch = d.λ_med
    b_ch = (d.λ_med - d.λ_min) / d.Pch_max
    a_dch = d.λ_med
    b_dch = (d.λ_max - d.λ_med) / d.Pdch_max

    utility = @expression(
        m,
        sum(
            a_ch * p_ch[t] - (b_ch / 2) * p_ch[t]^2 - a_dch * p_dch[t] -
            (b_dch / 2) * p_dch[t]^2 for t in 1:T
        )
    )

    # Signed active injection at the device's bus for the Aggregator's :Rp: net p (D-04).
    p_inject = [p_dch[t] - p_ch[t] for t in 1:T]

    return (; vars = (; p_ch, p_dch, soc, q), p_inject, q_inject = q, utility)
end

export FourQuadBESS
