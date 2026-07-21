---
phase: 02-linear-branch-flow-residual-seam
reviewed: 2026-07-18T19:18:32Z
depth: deep
files_reviewed: 6
files_reviewed_list:
  - src/core/ModelContext.jl
  - src/powerflow/DCPowerFlow.jl
  - src/powerflow/LinDistFlow.jl
  - src/devices/AbstractDevice.jl
  - src/devices/Interruptible.jl
  - src/models/linear_solve.jl
findings:
  critical: 1
  warning: 4
  info: 2
  total: 7
status: issues_found
---

# Phase 2: Code Review Report

**Reviewed:** 2026-07-18T19:18:32Z
**Depth:** deep (per-file + cross-file call-chain tracing + runtime verification against the phase fixtures)
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Phase 2's core modeling is sound and I verified it empirically. I built the 2-bus
loss-less fixture, solved it through `solve_linear` on both `DCPowerFlow` and
`LinDistFlow`, and confirmed the load-bearing facts the phase is judged on:

- The **DADP sign is correct**: `dual(balance_p[load,·])` comes out **+2.0 = λ₀ > 0**
  (positive marginal cost) on both formulations, matching the analytic FOC
  `a − b·p − λ₀ = 0 ⇒ p* = (a−λ₀)/b = 2`. My hand-derivation of `∂obj/∂rhs = −λ₀`
  and JuMP's Max-sense dual-sign flip cancel to the positive price the tests assert.
  No sign error in the nodal-balance dual, the device `−p` injection, the `+p_import`
  frontier injection, or the LinDistFlow `v_to = v_from − 2(rP+xQ)` voltage drop.
- The **DC↔LinDistFlow swap is genuinely branch-free**: identical objective (2.0) and
  identical DADP (2.0) with only the `pf` argument changed, driven by
  `haskey(ctx.residuals, :Rq)` on registry contents. Success criterion 4 holds.
- The additive scalar/indexed `add_to_residual!` extension, `zero`-init on matrix
  growth, `AffExpr` pinning via `convert`, and the concavity guard `b > 0` are all
  correct; matrix growth does not alias or mutate shared `AffExpr` objects.

However, the **assembly's balance-closure loop is not defended against the one input
it cannot see the network for**: a device whose `bus` index exceeds the feeder's bus
count is *silently* dropped from the nodal balance, producing wrong-but-plausible
prices and welfare with no error (CR-01, verified). Several robustness gaps
(empty devices, `λ₀` length, missing reactive frontier source, scalar/indexed name
collision) round out the findings.

## Critical Issues

### CR-01: Device at an out-of-range bus is silently dropped from the nodal balance (wrong prices/welfare, no error)

**File:** `src/models/linear_solve.jl:80-81` (interacting with `src/core/ModelContext.jl:107-121`)

**Issue:** The indexed `add_to_residual!` grows `ctx.residuals[:Rp]` to whatever
`(i, t)` index is handed to it — sizing is derived "from the indices ALONE" by design
(ModelContext.jl:99-100). A device contributes at `(d.bus, t)` with no check that
`d.bus` lies within the feeder. But the balance-closure loop pins only the first `Np`
rows:

```julia
Np = length(feeder.buses)
@constraint(model, balance_p[j = 1:Np, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
```

Any residual row beyond `Np` (i.e. a device at `bus > Np`) is **never pinned to
zero** and never enters any constraint. The device's `−p` injection therefore
vanishes from the network balance: the solver is free to set that device's power to
its unconstrained welfare optimum (`p = a/b`), manufacturing utility "for free" from
power that is never sourced or delivered.

I verified this on the 2-bus fixture with a valid priced load at bus 2 plus a second
load at nonexistent bus 3:

```
SOLVE SUCCEEDED silently.
Rp size=(3, 1)  Np=2  balance rows=(2, 1)
obj=10.0   dadp=[2.0]
good p=2.0   bad p (dropped from balance)=4.0
```

The welfare is reported as 10.0 (should be 2.0); the phantom device draws 4.0 pu from
nowhere; no error is raised. For a research bench whose core value is "trustworthy,
reproducible results and prices," a silently-wrong optimum is the worst possible
failure mode. (With a *single* out-of-range device the `dadp = dual.(balance_p[priced, :])`
extraction happens to `BoundsError`, but that is incidental — the moment the priced
device is in range, the extra device is dropped silently, as shown.)

**Fix:** Validate every device bus against the feeder at assembly time, and assert the
residual matrix matches `Np` before closing it — so a mis-indexed device fails loudly
instead of corrupting the solve:

```julia
Np = length(feeder.buses)
for (k, d) in enumerate(devices)
    1 <= d.bus <= Np || throw(ArgumentError(
        "device[$k] bus=$(d.bus) is outside feeder buses 1:$Np"))
end
# after all contribute! calls:
size(ctx.residuals[:Rp]) == (Np, T) || error(
    "residual :Rp is $(size(ctx.residuals[:Rp])), expected ($Np, $T) — an index escaped the feeder")
@constraint(model, balance_p[j = 1:Np, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
```

(The same guard should cover `:Rq` when present.)

## Warnings

### WR-01: `solve_linear` crashes cryptically on an empty `devices` vector

**File:** `src/models/linear_solve.jl:89` and `:97`

**Issue:** `devices::Vector{<:AbstractDevice}` may be empty. With no device, nothing
ever calls `add_to_objective!`, so `ctx.meta[:objective]` is never created and line 89
(`welfare = ctx.meta[:objective] - …`) throws a bare `KeyError` (verified). Line 97
(`priced = devices[1].bus`) would additionally `BoundsError`. The welfare of a
device-free feeder is a perfectly well-defined model (`Max −λ₀ᵀp_import`), so this
should either be supported or rejected with a clear message — not a raw `KeyError`.

**Fix:** Mirror `add_to_objective!`'s own default and validate up front:

```julia
isempty(devices) && throw(ArgumentError("solve_linear needs at least one device (the priced load)"))
...
welfare = get(ctx.meta, :objective, zero(QuadExpr)) - sum(λ₀[t] * p_import[t] for t in 1:T)
```

### WR-02: `λ₀` length is not validated against `T`

**File:** `src/models/linear_solve.jl:70-71`, `:89`

**Issue:** `λ₀` is an untyped keyword consumed as `λ₀[t]` for `t = 1:T`. If
`length(λ₀) < T` this `BoundsError`s deep inside objective assembly; if a *scalar*
`λ₀` is passed it silently "works" only for `T == 1` (scalar `[1]` indexing) and
breaks for `T > 1`. For a reproducible research bench a shape mismatch should fail at
the boundary with a clear message.

**Fix:**

```julia
length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
```

### WR-03: No reactive frontier source — assembly bakes in `Q ≡ 0` and will be infeasible once reactive loads land

**File:** `src/models/linear_solve.jl:70-73` (frontier injection is active-only)

**Issue:** The frontier import is injected only into `:Rp`
(`add_to_residual!(ctx, :Rp, feeder.root, t, p_import[t])`); there is no reactive
counterpart. When `LinDistFlow` closes `:Rq` for every bus including the root, the
root reactive balance becomes `−Σ Q_out == 0`, which (with no reactive injection
anywhere) forces `Q ≡ 0` on the whole feeder. That is consistent *today* because no
device injects reactive power, but the assembly — not a device — is the thing that
lacks a frontier reactive source. As soon as Phase 3 adds a reactive load, the root
reactive balance will be infeasible (or force the load's reactive draw to zero)
because the substation cannot supply Q. This is an assembly-level seam gap, distinct
from the accepted "reactive-load deferred" note.

**Fix:** When `haskey(ctx.residuals, :Rq)`, also inject a (free-sign) reactive
frontier variable `q_import[t]` at the root before closing `:Rq`, mirroring
`p_import`. Track it under `ctx.meta` alongside `p_import`.

### WR-04: Indexed `add_to_residual!` silently discards a pre-existing scalar accumulator of the same name

**File:** `src/core/ModelContext.jl:108-119`

**Issue:** The indexed method starts from a fresh `Matrix{AffExpr}(undef, 0, 0)`
whenever `ctx.residuals[name]` is present but is *not* already a `Matrix{AffExpr}`:

```julia
M = (haskey(ctx.residuals, name) && ctx.residuals[name] isa Matrix{AffExpr}) ?
    ctx.residuals[name]::Matrix{AffExpr} : Matrix{AffExpr}(undef, 0, 0)
...
ctx.residuals[name] = M   # overwrites whatever scalar AffExpr was there
```

If a scalar `add_to_residual!(ctx, name, expr)` accumulation and an indexed one ever
land on the same `name`, the scalar contribution is silently overwritten (lost) rather
than raising. Current code keeps the names disjoint (`:nodal_balance` scalar vs
`:Rp`/`:Rq` indexed), so this is latent — but it is exactly the kind of silent-drop
that corrupts a balance without warning.

**Fix:** Reject the mismatch loudly instead of overwriting:

```julia
if haskey(ctx.residuals, name) && !(ctx.residuals[name] isa Matrix{AffExpr})
    error("residual :$name already holds a scalar accumulator; refusing to convert it to an indexed matrix")
end
```

## Info

### IN-01: `Interruptible` constructor requires a homogeneous element type

**File:** `src/devices/Interruptible.jl:47`

**Issue:** `Interruptible(bus::Int, Pmin::T, Pmax::T, a::T, b::T) where {T<:Real}`
forces `Pmin`, `Pmax`, `a`, `b` to share one type. A natural call like
`Interruptible(2, 0, 5.0, 4.0, 1.0)` (integer `0`) throws a confusing `MethodError`
rather than promoting. Tests always pass all-`Float64`, so this is an ergonomics
sharp edge, not a correctness bug.

**Fix:** Promote in an outer constructor:
`Interruptible(bus, Pmin, Pmax, a, b) = Interruptible(bus, promote(Pmin, Pmax, a, b)...)`.

### IN-02: `contribute!` methods return inconsistent types

**File:** `src/powerflow/DCPowerFlow.jl:60`, `src/powerflow/LinDistFlow.jl:97`
(return `ctx`) vs `src/devices/Interruptible.jl:107` (returns the variable array `p`)

**Issue:** The power-flow methods return `ctx`; the device method returns its variable
container (which `solve_linear` relies on for `ctx.meta[:device_vars]`). The shared
generic's two method families have divergent return contracts. It works, but the
`AbstractDevice`/`AbstractPowerFlow` docstrings do not state the device-returns-vars
convention that assembly depends on.

**Fix:** Document the device return contract in `AbstractDevice.jl` (or stash device
vars inside `contribute!` and return `ctx` uniformly).

---

_Reviewed: 2026-07-18T19:18:32Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
