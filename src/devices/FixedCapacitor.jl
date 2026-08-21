# src/devices/FixedCapacitor.jl
#
# SEAM: fixed-Q shunt capacitor device (SCALE-03, D-10/D-11).
# OWNER: plan 25-04.
#
# Models the 4 IEEE-8500 capacitor banks as fixed-Q injections via the existing OPTIONAL
# `q_inject` seam (MESH-04/D-09) — the SECOND consumer of that widened AGGREGATABLE-device
# contract after `FourQuadBESS`. Unlike `FourQuadBESS`, this device has NO JuMP decision
# variables and NO constraints at all: its reactive injection is a compile-time-known
# constant (the bank's nameplate rating), always on (D-11: CapControl switching is
# explicitly out of scope — a documented assumption, not a silent omission). It never
# touches `ctx.residuals` or `ctx.meta[:objective]` directly — like every AGGREGATABLE
# device it RETURNS its `(; vars, p_inject, q_inject, utility)` terms for the wrapping
# `Aggregator` (DEV-05, the SOLE `:Rp`/`:Rq` writer) to roll up.

using JuMP

"""
    FixedCapacitor <: AbstractDevice

A fixed-Q shunt capacitor bank (SCALE-03/D-10): a nameplate reactive-power injection with
NO JuMP decision variable and NO constraint — the simplest possible AGGREGATABLE device.
Models the 4 IEEE-8500 capacitor banks (`IEEE8500_CAPACITOR_KVAR`), each wrapped in its own
zero-`Pdc` `Aggregator` at its promoted bus (D-12).

# Fields

  - `bus::Int` — the bus id the bank sits at (network-agnostic per `AbstractDevice`'s
    contract; the wrapping `Aggregator` supplies this bus to the network, this field is
    carried for documentation/inspection only — `contribute!` never reads it).
  - `q_nom_pu::Float64` — the bank's nameplate reactive injection, in per-unit power,
    ALWAYS ON (D-11: no switching state field — CapControl is out of scope).

# D-11: CapControl switching is out of scope

The real IEEE-8500 feeder's capacitor banks are voltage/var-controlled (CapControl),
switching in and out around a setpoint. This benchmark phase models them as ALWAYS-ON at
nameplate rating instead — a documented assumption (SCALE-03), not a silent omission: the
bank injects `q_nom_pu` at every time step regardless of the solved voltage/var state.
"""
struct FixedCapacitor <: AbstractDevice
    bus::Int
    q_nom_pu::Float64
end

"""
    FixedCapacitor(bus, q_nom_pu)

Convenience outer constructor (IN-01): converts `bus` to `Int` and `q_nom_pu` to `Float64`
so a natural mixed-type call (e.g. an integer `q_nom_pu`) just works instead of throwing a
`MethodError`.
"""
FixedCapacitor(bus::Integer, q_nom_pu::Real) = FixedCapacitor(Int(bus), Float64(q_nom_pu))

"""
    contribute!(d::FixedCapacitor, ctx::ModelContext; T::Int)

Contribute the fixed-Q capacitor bank into the shared model context over `t = 1:T`,
following the AGGREGATABLE-device contract (D-10): builds NO variables and NO constraints
on `ctx.model` (there is nothing to decide — the injection is a constant), writes NOTHING
to `ctx.residuals`, and calls NO `add_to_objective!`. Returns
`(; vars = NamedTuple(), p_inject, q_inject, utility)` where `p_inject` is a constant
zero-`AffExpr` vector (D-10: the bank injects NO active power) and `q_inject` is a constant
`d.q_nom_pu` `AffExpr` vector (the bank's always-on nameplate reactive injection, D-11) —
the SECOND consumer of the optional `q_inject` seam (MESH-04/D-09) after `FourQuadBESS`.
`utility` is `zero(QuadExpr)` (a capacitor bank has no preference/cost).

The wrapping `Aggregator` (DEV-05) is the ONLY consumer of this return value: it sums
`q_inject` into its own net reactive injection via the existing `hasproperty(res,
:q_inject)` roll-up, so `Aggregator` remains the SOLE `:Rp`/`:Rq` writer — `FixedCapacitor`
itself never becomes a second `:Rq` writer.
"""
function contribute!(d::FixedCapacitor, ctx::ModelContext; T::Int)
    p_inject = fill(AffExpr(0.0), T)
    q_inject = fill(AffExpr(d.q_nom_pu), T)
    utility = zero(QuadExpr)
    return (; vars = NamedTuple(), p_inject, q_inject, utility)
end

export FixedCapacitor
