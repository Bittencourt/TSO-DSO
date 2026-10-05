# src/devices/AbstractDevice.jl
#
# SEAM: swappable device (prosumer/flexible-load) interface contract (DEV-03).
# OWNER: plan 02-03.
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
generator, storage — the full library lands in Phase 3). Concrete subtypes implement
[`contribute!`](@ref) — the SAME generic already declared for `AbstractPowerFlow`; a
device adds a METHOD to that shared generic rather than introducing a competing one
(the `contribute!` generic is reused, never redeclared here).

# The device contract — AGGREGATABLE device (aggregator-as-writer)

A device method `contribute!(dev::AbstractDevice, ctx::ModelContext; T::Int)` ALWAYS
creates the device's own decision variables plus their temporal/bound constraints on
`ctx.model`. Every live device ([`Interruptible`](@ref), [`Thermostatic`](@ref),
[`Deferrable`](@ref), [`PVBattery`](@ref), `FourQuadBESS`) is network-agnostic to the
point of touching NEITHER the residual NOR the objective — an [`Aggregator`](@ref)
(DEV-05) is the SOLE network-facing `:Rp`/`:Rq` writer:

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
existed for `Interruptible` only. Plan 26-07 (FIX-05) converted `Interruptible` to this
Variant-2 contract, so Variant 1 has zero live members and has been removed from this
docstring; `src/models/linear_solve.jl`'s device roll-up loop was updated in the same plan
to perform the residual/objective write generically for any Variant-2 device.)

### Widened contract: optional `q_inject` field (MESH-04, D-09)

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
default path (no `q_inject` key present) is byte-identical to the pre-MESH-04 contract.

# Network decoupling (success criterion 2)

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
`true` (FIX-05).
"""
is_flexible_load(::AbstractDevice) = false

export AbstractDevice
