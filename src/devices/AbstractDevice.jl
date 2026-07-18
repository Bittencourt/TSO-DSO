# src/devices/AbstractDevice.jl
#
# SEAM: swappable device (prosumer/flexible-load) interface contract (DEV-03).
# OWNER: plan 02-03.
#
# The abstract device supertype + the dispatched `contribute!` contract only. A device
# is NETWORK-AGNOSTIC: it receives its bus index and horizon `T` (never the `feeder`),
# adds its variables/limits to `ctx.model`, injects its affine power terms into
# `ctx.residuals[:Rp]` (and `:Rq` when reactive-capable) via the indexed
# `add_to_residual!`, and accumulates its concave-quadratic utility into the welfare
# objective via `add_to_objective!` (QuadExpr — never the affine residual). This is the
# device↔network decoupling that lets the DC↔LinDistFlow swap leave device code
# untouched.

"""
    AbstractDevice

Abstract supertype for a swappable device (prosumer, flexible/interruptible load,
generator, storage — the full library lands in Phase 3). Concrete subtypes implement
[`contribute!`](@ref) — the SAME generic already declared for `AbstractPowerFlow`; a
device adds a METHOD to that shared generic rather than introducing a competing one
(the `contribute!` generic is reused, never redeclared here).

# The device contract

A device method `contribute!(dev::AbstractDevice, ctx::ModelContext; T::Int)`:

1. creates the device's own decision variables plus their temporal/bound constraints on
   `ctx.model`;
2. ADDS a signed affine power injection into the shared per-bus/per-time nodal-balance
   residual `ctx.residuals[:Rp]` (and `ctx.residuals[:Rq]` only for reactive-capable
   devices) via the indexed `add_to_residual!(ctx, :Rp, bus, t, expr)` seam — a consumed
   load is a NEGATIVE injection (`-p`), matching the toy-DC sign convention; and
3. ADDS its concave-quadratic utility into the welfare objective via
   [`add_to_objective!`](@ref) (a `QuadExpr`, so curvature is retained — utility must
   NOT be routed through the affine residual, which would drop the quadratic term).

# Network decoupling (success criterion 2)

A device is NEVER passed the `feeder`. It is constructed with only its bus id and
receives the horizon `T` at `contribute!` time; it references no `Feeder`, `Branch`,
line resistance/reactance, or voltage object. Devices meet the network ONLY at the
`ctx.residuals[:Rp]` seam, which is exactly what lets the power-flow formulation swap
(DC ↔ LinDistFlow) without touching any device code.
"""
abstract type AbstractDevice end

export AbstractDevice
