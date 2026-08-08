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

# The device contract — TWO variants

A device method `contribute!(dev::AbstractDevice, ctx::ModelContext; T::Int)` ALWAYS
creates the device's own decision variables plus their temporal/bound constraints on
`ctx.model`. Two contract variants then differ ONLY in how the device's power injection
and utility reach the network — a difference driven by whether the device is grouped
under an [`Aggregator`](@ref) (DEV-05, the network-facing writer):

## Variant 1 — SELF-INJECTING device (Phase-2 pattern)

Used by [`Interruptible`](@ref). The device is itself the network writer:

 1. it ADDS a signed affine power injection into the shared per-bus/per-time nodal-balance
    residual `ctx.residuals[:Rp]` (and the reactive residual only for reactive-capable
    devices) via the indexed `add_to_residual!(ctx, :Rp, bus, t, expr)` seam — a consumed
    load is a NEGATIVE injection (`-p`), matching the toy-DC sign convention;
 2. it ADDS its concave-quadratic utility into the welfare objective via
    [`add_to_objective!`](@ref) (a `QuadExpr`, so curvature is retained — utility must
    NOT be routed through the affine residual, which would drop the quadratic term); and
 3. it RETURNS its own per-device decision-variable container (e.g. the served-power
    vector `p`). Unlike an `AbstractPowerFlow` `contribute!` (which returns `ctx`), a
    self-injecting device returns its variables so the assembly can stash them
    (`ctx.meta[:device_vars]`) for post-solve inspection (IN-02).

A self-injecting device holds a `bus::Int` and writes at that bus.

## Variant 2 — AGGREGATABLE device (Phase-3 pattern, aggregator-as-writer)

Used by [`Thermostatic`](@ref), [`Deferrable`](@ref), and [`PVBattery`](@ref) (DEV-05,
RESEARCH Q1 resolved). The device is network-agnostic to the point of touching NEITHER
the residual NOR the objective:

 1. it builds ONLY its variables/constraints on `ctx.model`;
 2. it writes NOTHING to `ctx.residuals` and calls NO `add_to_objective!`; and
 3. it RETURNS a `(; vars, p_inject, utility)` NamedTuple — `vars` is its decision-variable
    container, `p_inject::Vector{AffExpr}` its signed active injection per time step (load
    negative), and `utility::QuadExpr` its concave preference. Its [`Aggregator`](@ref)
    (the SOLE :Rp/:Rq writer) rolls these member terms up into ONE nodal net active
    injection, ONE nodal net reactive injection (from the load power factor, eq. 3.23), and
    ONE summed utility at the aggregator's bus (thesis eqs. 3.21-3.23).

An aggregatable device need not even hold a bus — the aggregator supplies it.

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

export AbstractDevice
