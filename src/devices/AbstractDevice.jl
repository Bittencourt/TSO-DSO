# src/devices/AbstractDevice.jl
#
# SEAM: swappable device (prosumer/flexible-load) interface contract.
#
# The abstract device supertype + the dispatched `contribute!` contract only. A device
# is NETWORK-AGNOSTIC: it receives its bus index and horizon `T` (never the network
# object), adds its variables/limits to `ctx.model`, injects its affine power terms into
# `ctx.residuals[:Rp]` (and the reactive residual when reactive-capable) via the indexed
# `add_to_residual!`, and accumulates its concave-quadratic utility into the welfare
# objective via `add_to_objective!` (QuadExpr — never the affine residual). This is the
# device-network decoupling that lets the DC / LinDistFlow swap leave device code
# untouched.

"""
    AbstractDevice

Abstract supertype for a swappable device (prosumer, flexible/interruptible load,
generator, storage — the full library is built on this contract). Concrete subtypes implement
[`contribute!`](@ref) — the SAME generic already declared for `AbstractPowerFlow`; a
device adds a METHOD to that shared generic rather than introducing a competing one
(the `contribute!` generic is reused, never redeclared here).

# The device contract — AGGREGATABLE device (aggregator-as-writer)

A device method `contribute!(dev::AbstractDevice, ctx::ModelContext; T::Int)` ALWAYS
creates the device's own decision variables plus their temporal/bound constraints on
`ctx.model`. Every live device ([`Interruptible`](@ref), [`Thermostatic`](@ref),
[`Deferrable`](@ref), [`PVBattery`](@ref), `FourQuadBESS`) is network-agnostic to the
point of touching NEITHER the residual NOR the objective — an [`Aggregator`](@ref)
is the SOLE network-facing `:Rp`/`:Rq` writer:

 1. it builds ONLY its variables/constraints on `ctx.model`;
 2. it writes NOTHING to `ctx.residuals` and calls NO `add_to_objective!`; and
 3. it RETURNS a `(; vars, p_inject, utility)` NamedTuple — `vars` is its decision-variable
    container, `p_inject::Vector{AffExpr}` its signed active injection per time step (load
    negative), and `utility::QuadExpr` its concave preference. Its [`Aggregator`](@ref)
    (the SOLE :Rp/:Rq writer) rolls these member terms up into ONE nodal net active
    injection, ONE nodal net reactive injection (from the load power factor, eq. 3.23), and
    ONE summed utility at the aggregator's bus (thesis eqs. 3.21-3.23).

An aggregatable device need not even hold a bus — the aggregator supplies it.

(Historical note: an earlier "Variant 1 — self-injecting" contract, where a device wrote
directly to `ctx.residuals`/`ctx.objective` and returned a bare variable container,
existed for `Interruptible` only. `Interruptible` has since been converted to this
Variant-2 contract, so Variant 1 has zero live members and has been removed from this
docstring; `src/models/linear_solve.jl`'s device roll-up loop performs the residual/objective write generically for any Variant-2 device.)

### Widened contract: optional `q_inject` field

A device with a genuine reactive decision variable — today, only [`FourQuadBESS`](@ref) —
MAY additionally include a `q_inject::Vector{AffExpr}` field in its returned NamedTuple:
`(; vars, p_inject, q_inject, utility)`. This is the device's own signed reactive
injection per time step, meant to be summed into the aggregator's net reactive injection
alongside the load-power-factor term (eq. 3.23).

A device WITHOUT a genuine reactive decision — every PRE-EXISTING device
([`Thermostatic`](@ref), [`Deferrable`](@ref), [`PVBattery`](@ref)) — simply OMITS the
`q_inject` key; the [`Aggregator`](@ref) checks for its presence via `hasproperty` before
summing it, so omitting it is a complete, correct, zero-effort contract for every existing
device. Consequently, **no existing device file needs to change** for this widening: the
default path (no `q_inject` key present) is bit-for-bit identical to the contract before this widening.

# Network decoupling

A device is NEVER passed the network object. It is constructed with only its bus id and
receives the horizon `T` at `contribute!` time; it references no network topology, line
impedance, or voltage object. Devices meet the network ONLY at the
`ctx.residuals[:Rp]` seam, which is exactly what lets the power-flow formulation swap
(DC / LinDistFlow) without touching any device code.
"""
abstract type AbstractDevice end

"""
    is_flexible_load(d::AbstractDevice) -> Bool

Trait identifying devices whose CONSUMPTION should draw power-factor reactive power via
the Aggregator roll-up (thesis eq. 3.23), distinguishing them from active-only DERs
(PV/battery, per Assumption A3) which never draw power-factor reactive power regardless of
this trait. Defaults to `false` for any device; a flexible-load device
([`Interruptible`](@ref), [`Thermostatic`](@ref), [`Deferrable`](@ref)) overrides it to
`true`.
"""
is_flexible_load(::AbstractDevice) = false

"""
    has_reactive_decision(d::AbstractDevice) -> Bool

Trait identifying devices whose reactive power involves a genuine per-time-step
DECISION (a decision variable, or a decision-coupled draw) — the devices for
which the reactive-consensus machinery must run `LIVE`, and for which an explicit
`OFF`/`CERTIFIED` override fails loud. Defaults to `is_flexible_load(d)`: the
default IS the historical probe's flexible-load half, made explicit — the probe
this trait replaces was the hard-coded `dv isa FourQuadBESS || is_flexible_load(dv)`
inside `DsoOpt.jl`'s `_any_flexible_reactive` (shared by `build_dso_opt`'s and
`solve_admm`'s smart `reactive_consensus` default) and its inline OFF/CERTIFIED
guard copy. A `FourQuadBESS` (genuine `q` decision) overrides it to `true`;
`FixedCapacitor` deliberately does NOT (its `q_inject` is a constant nameplate
injection — part of the `-Pdc·tanφ` draw, not a decision — so the trait stays
`false`, reproducing the probe's historical asymmetry, research A8).

EV-SAFETY MOTIVATION: a future `ElectricVehicle` carries `p_ch`/`p_dch` decision
variables of its own; a SHAPE-based probe could false-match such active-only
storage devices into reactive-consensus (or certificate) semantics. Routing
classification through a dispatched trait makes "what can this device decide?"
a property of the TYPE hierarchy, not of variable names — an EV can never
acquire another regime's semantics by resembling it.
"""
has_reactive_decision(d::AbstractDevice)::Bool = is_flexible_load(d)

"""
    storage_kind(d::AbstractDevice) -> Symbol
    storage_kind(T::Type{<:AbstractDevice}) -> Symbol

Storage-regime classification trait driving certificate selection over the
type-paired device stash (`ModelContext.agg_device_types`): `:battery`
([`PVBattery`](@ref) — the App. C complementarity regime), `:four_quadrant`
(`FourQuadBESS` — its own independently-measured peer certificate), `:none`
(default — no storage semantics; the `:ev` value is reserved for the device
plan that introduces EVs). The historical classification SNIFFED the stashed
vars' shape (`haskey(v,:p_ch) && haskey(v,:p_dch) && (!)haskey(v,:q)`) —
correctness debt, because an ElectricVehicle's vars would false-match the
battery shape and run battery-certificate semantics on a legitimate optimum.
Dispatching on the TYPE closes that door: the stash stores `DataType`s
(appended in lockstep with the vars by `Aggregator.contribute!`), instance
reads forward to the type-level method (ONE override point per class), and
only type-unprovenanced (hand-built test-context) stash entries fall back to
the legacy shape predicate.
"""
storage_kind(::Type{<:AbstractDevice}) = :none
storage_kind(d::AbstractDevice) = storage_kind(typeof(d))

export AbstractDevice
