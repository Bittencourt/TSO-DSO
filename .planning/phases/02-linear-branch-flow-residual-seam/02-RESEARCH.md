# Phase 2: Linear Branch-Flow Residual Seam - Research

**Researched:** 2026-07-18
**Domain:** Julia/JuMP convex optimization modeling — linear power-flow (DC / LinDistFlow) + one flexible device, meeting at a shared nodal residual, exposing the first nodal-balance dual (price)
**Confidence:** HIGH (theory equations are primary-source extracted; Phase-1 seam signatures read verbatim from source; solver routing already verified in `factory.jl`)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
CONTEXT.md declares **no user-preference grey areas** for this phase: "All modeling choices follow the source thesis/papers and the Phase 1 seam — correctness follows the theory." The following are therefore treated as locked anchors:

- **`AbstractPowerFlow` contract (Phase 1):** DC and LinDistFlow are concrete subtypes; each `contribute!`s branch/voltage terms into `ctx.residuals[:nodal_balance]` (and a reactive residual for LinDistFlow). Dispatch on the formulation type — never `if formulation ==` branching.
- **LinDistFlow:** the linearized branch-flow (DistFlow without the loss/quadratic term) with voltage-magnitude-squared variables, per the thesis. DC is the pure active-power linearization. Both must be interchangeable behind the same residual interface (success criterion 4).
- **Flexible device (DEV-03):** an interruptible/elastic load contributing decision variables, a **concave quadratic utility** term to the objective, and a **signed injection** into the residual — and it must NOT reference the network/topology (device↔network decoupling is the whole point).
- **Centralized solve:** assemble device + power-flow contributions into one convex model, solve via the Phase-1 `select_optimizer` factory (LP for DC-only; QP once the concave-quadratic utility is present → Clarabel or HiGHS as the factory decides), gate on `OPTIMAL` via `assert_solved!`, and expose `dual(nodal_balance)` as the first price signal.
- **Solver discipline (CLAUDE.md):** no model file names a concrete solver; use `select_optimizer`.
- **Interface-conformance testing:** a conformance test must prove DC↔LinDistFlow swap requires zero change to device or assembly code, and that the device contributes without touching the network.

### Claude's Discretion
All modeling choices are anchored to the source thesis/papers + the Phase 1 seam (see `## Architecture Patterns` for the prescriptive resolutions this research reached).

### Deferred Ideas (OUT OF SCOPE)
- SOCP / exact convex branch flow → Phase 4.
- Full prosumer device library + aggregator roll-up → Phase 3.
- DADP/DLMP price decomposition (beyond raw nodal-balance dual) → Phase 5.
- ADMM decomposition → Phase 6.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PF-02 | DC / LinDistFlow linear formulations conforming to `AbstractPowerFlow`, contributing branch/voltage terms into the shared nodal-balance residual with no `if formulation ==` branching. | LinDistFlow eqs traced to thesis 3.31–3.33/3.43/3.45 (loss-less); DC = active-only subset. Both implement `contribute!(::AbstractPowerFlow, ctx, feeder; T)` by dispatch. See `## Architecture Patterns` P1, P2. |
| DEV-03 | Interruptible/elastic-load model (power bounds) with concave quadratic utility, contributing a signed injection into the residual without referencing the network. | Utility from thesis 3.10 `U = Σ_t[a·p − (b/2)p²]`; coefficients 3.13–3.14. Device contract proposed in `## Architecture Patterns` P3 (`AbstractDevice` + `contribute!`). Network-agnostic: device sees only its bus id + horizon T, never the feeder topology. |
</phase_requirements>

## Summary

This phase turns the Phase-1 *stub* `contribute!(::AbstractPowerFlow, ctx, feeder)` into two concrete, dispatch-selected formulations (DC and LinDistFlow) and introduces the project's first *device* contract (`AbstractDevice` + `contribute!`), then assembles both into one centralized convex model whose nodal-balance dual is the first price signal. Everything meets at one place: the shared residual registry in `ModelContext`. The power-flow formulation *subtracts* branch/voltage terms into the per-bus active (and, for LinDistFlow, reactive) residual; the device *adds* a signed power injection into the same residual; assembly closes each residual with an equality constraint (whose dual is the price) and maximizes welfare. No code branches on which formulation or device is in play — selection is by Julia multiple dispatch, exactly as `select_optimizer(::ProblemClass)` already does.

Two design realities the planner must absorb up front. **(1) The residual seam must generalize from Phase-1's single scalar `ctx.residuals[:nodal_balance]` to per-bus (and per-time) residuals** — a real feeder has ≥2 buses. The recommended shape is `ctx.residuals[:Rp]` / `[:Rq]` holding an indexed `Matrix{AffExpr}` (bus × T), with an indexed accumulator. The physical nodal balance is *affine* in the decision variables (P, Q, v, p_load), so keeping the residual an `AffExpr` accumulator — as Phase 1 designed — is correct and must not change. **(2) The concave quadratic utility is NOT affine**, so it cannot flow through `add_to_residual!` (which converts to `AffExpr`). The objective/welfare needs its own `QuadExpr` accumulator (`add_to_objective!`). This cleanly separates the *affine physical residual* (the price-bearing constraint) from the *quadratic welfare objective* — a separation that will pay off through Phases 3–6.

The concave quadratic utility makes the centralized solve a **QP**, which the Phase-1 factory already routes to **Clarabel** (native quadratic objective, accurate duals — and the prices *are* duals, so accuracy matters). A tiny 2-bus radial feeder gives a closed-form price to assert against, keeping the first price test analytic rather than a magic number.

**Primary recommendation:** Implement `DCPowerFlow` and `LinDistFlow` as `AbstractPowerFlow` subtypes (dispatched `contribute!`), and `Interruptible` as the first `AbstractDevice` subtype (dispatched `contribute!`). Generalize the residual registry to per-bus `:Rp`/`:Rq` `Matrix{AffExpr}`; add an `add_to_objective!` QuadExpr accumulator to `ModelContext`. Assemble centrally, solve as `QP()`→Clarabel through `assert_solved!(dual=true)`, and recover `dual(ctx.constraints[:balance_p][bus,t])` as the DADP. Validate on a 2-bus radial fixture with a hand-derived closed-form price (`DADP = λ₀`, `p* = (a−λ₀)/b`), plus a conformance test proving the DC↔LinDistFlow swap touches neither device nor assembly code.

## Architectural Responsibility Map

Single-tier research library (no client/server/CDN). "Tiers" here are the framework's architectural layers (ARCHITECTURE.md).

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Branch/voltage variables & constraints (P, Q, v) | Power-flow formulation (`src/powerflow/`) | — | Only the formulation knows the network model; it owns network variables and *subtracts* branch terms into the residual. |
| Device decision variables + temporal constraints | Device (`src/devices/`) | — | Devices own their own variables/bounds; must never see the feeder. |
| Signed power injection into nodal balance | Device → residual registry | Aggregator (Phase 3) | Device adds `+p_load` (a signed injection) into `:Rp`; at this rung there is no aggregator roll-up yet. |
| Nodal-balance residual accumulation | `ModelContext` residual registry (`src/core/`) | — | The single coupling seam; both power-flow and device write here and nowhere else. |
| Objective (welfare) accumulation | `ModelContext` objective accumulator (`src/core/`) | Assembly | Quadratic utility can't live in the affine residual; needs a `QuadExpr` accumulator. |
| Balance closure + dual naming | Assembly model (`src/models/`) | — | Only assembly knows both sides; it pins residuals to 0 and registers the constraint so its dual (price) is recoverable. |
| Solver selection | `select_optimizer(::ProblemClass)` (`src/solver/`) | — | QP → Clarabel by dispatch; model names no solver. |
| Status/dual trust gate | `assert_solved!` (`src/core/status.jl`) | — | Single choke point; `dual=true` required before reading prices. |

## Standard Stack

**No new packages are introduced by this phase.** Every dependency required (JuMP, Clarabel, HiGHS, SparseArrays) is already declared and pinned in `Project.toml`. This phase adds only *source files* and *test items* to the existing `TSODSO` package.

### Core (already present — versions from `Project.toml` `[compat]`, verified in repo 2026-07-18)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JuMP | 1.30.1 | Algebraic modeling; `@variable`, `@constraint`, `@objective`, `dual()` | Project modeling layer; per-constraint dual access is the whole point (prices are duals). [CITED: Project.toml] |
| Clarabel | 0.11.1 | QP/SOCP solver; native quadratic objective, accurate duals | `QP()` factory target; the concave-quadratic utility makes this a QP. [CITED: src/solver/factory.jl] |
| HiGHS | 1.24.1 | LP/MILP (DC-only, no quadratic utility) | `LP()` factory target for the pure-DC conformance-only path. [CITED: Project.toml] |
| SparseArrays | stdlib | Feeder incidence / adjacency | Already used by `topology.jl` for incidence. [CITED: src/data/topology.jl] |

### Supporting (test-only — already in `test/Project.toml`)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| TestItems / TestItemRunner | 1.0.0 / 1.1.5 | `@testitem` per seam, discovered by `@run_package_tests` | Every new test in this phase. [CITED: test/Project.toml] |
| Aqua | current | Package-quality gate | Existing suite runs `Aqua.test_all(TSODSO)`; new exports must keep it green. [CITED: test/test_toy_dc.jl] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Clarabel for the QP solve | HiGHS (`QP` also supported by HiGHS) | HiGHS solves convex QP, but the factory routes `QP()`→Clarabel because Clarabel returns higher-accuracy duals, and the DADP *is* a dual (Pitfall 4). Keep the factory choice; do not override. |
| Multi-bus + single-period (T=1) | Multi-period (T>1) now | Recommend indexing by `(bus, t)` in code but running the MVP fixture at **T=1** for a clean analytic price. The interruptible load (3.10) is time-separable, so T>1 adds nothing correctness-wise at this rung; but coding the index as `(bus,t)` now keeps Phase 3 (multi-period devices) additive, not a refactor. |

**Installation:** none — no `Pkg.add` in this phase.

**Version verification:** performed by reading the committed `Project.toml`/`[compat]` (the reproducibility anchor) rather than a registry query, since no packages are added. Julia runtime verified present: **1.12.5** on PATH (compat floor `julia = "1.10"`; 1.12 resolves). [VERIFIED: `julia --version`]

## Package Legitimacy Audit

**Not applicable — this phase installs no external packages.** All four libraries touched (JuMP, Clarabel, HiGHS, SparseArrays) are pre-existing, pinned dependencies committed in `Project.toml` and vetted during Phase 1 / project stack research (CLAUDE.md Sources: Julia General registry `Versions.toml`, fetched 2026-07-18). No `Pkg.add`, no new registry entries, no postinstall surface. Disposition for all: **pre-approved, unchanged.**

## Architecture Patterns

### System Architecture Diagram

```
                        Feeder (immutable data, no JuMP)
                        buses[] · branches[] · root · per-unit
                                    │ read-only
        ┌───────────────────────────┴────────────────────────────┐
        │                                                          │
        ▼ dispatch on formulation type                             ▼ dispatch on device type
┌─────────────────────────┐                          ┌──────────────────────────────┐
│ contribute!(pf, ctx,     │                          │ contribute!(dev, ctx; bus,T)  │
│             feeder; T)   │                          │                               │
│  DCPowerFlow:            │                          │  Interruptible:               │
│   - vars P_ij[t]         │                          │   - var p_load[bus,t] in bnds │
│   - active bal only      │                          │   - SUBTRACT nothing from net │
│  LinDistFlow:            │                          │   - ADD +p_load into :Rp[bus] │
│   - vars P_ij,Q_ij,v_j   │                          │   - ADD  a·p−(b/2)p² to obj   │
│   - voltage drop (3.33') │                          │     (never reads `feeder`)    │
│  SUBTRACT branch terms   │                          └───────────────┬───────────────┘
│  into :Rp[j] / :Rq[j]    │                                          │
└──────────┬───────────────┘                                          │
           │  both write ONLY here                                    │
           ▼                                                          ▼
   ┌────────────────────────────────────────────────────────────────────────┐
   │  ModelContext residual registry (the ONE coupling seam)                  │
   │    residuals[:Rp]  :: Matrix{AffExpr}  (bus × T)   ← affine, price-bearing│
   │    residuals[:Rq]  :: Matrix{AffExpr}  (bus × T)   ← LinDistFlow only     │
   │    objective accum  :: QuadExpr        ← welfare (quadratic utility)      │
   └───────────────────────────────┬──────────────────────────────────────────┘
                                    │ assembly (sole knower of both sides)
                                    ▼
   ┌────────────────────────────────────────────────────────────────────────┐
   │  close balance:  @constraint(m,[j,t], Rp[j,t]==0)  → register :balance_p  │
   │                  (and Rq==0 → :balance_q  IF present)                     │
   │  @objective(m, Max, welfare_accum − λ₀ᵀ·p_import)                         │
   │  Model(select_optimizer(QP()))  → Clarabel                               │
   │  assert_solved!(m; dual=true, allow_local=false)                          │
   │  DADP = dual(ctx.constraints[:balance_p][priced_bus, t])   ← first price  │
   └────────────────────────────────────────────────────────────────────────┘
```

Trace the primary use case (get the first price): Feeder → formulation writes branch terms into `:Rp` → device writes `+p_load` into `:Rp` and utility into the objective accumulator → assembly closes `Rp==0`, sets welfare objective, solves QP → reads the dual of the closed balance = DADP.

### Recommended Project Structure
Additive to Phase 1 (do not touch `TSODSO.jl`'s include order surface except to add the new includes — see include-order note below).
```
src/
├── powerflow/
│   ├── AbstractPowerFlow.jl   # EXISTS — make `contribute!` concrete (extend signature; see P1)
│   ├── DCPowerFlow.jl         # NEW — active-power-only linearization
│   └── LinDistFlow.jl         # NEW — loss-less branch flow + squared-voltage drop
├── devices/                   # NEW directory
│   ├── AbstractDevice.jl      # NEW — device contract (abstract type + contribute! generic)
│   └── Interruptible.jl       # NEW — elastic load, concave quadratic utility (DEV-03)
├── core/
│   └── ModelContext.jl        # EXTEND — indexed residual accumulator + add_to_objective!
└── models/
    ├── toy_dc.jl              # EXISTS — leave working (rung 0 regression)
    └── linear_solve.jl        # NEW — centralized assembly generalizing toy_dc (rung 1)
```

### Pattern 1: Formulation-as-type with a dispatched `contribute!` (extend the Phase-1 stub)
**What:** `DCPowerFlow` and `LinDistFlow` are singleton (or thin) subtypes of `AbstractPowerFlow`. Each has a `contribute!` method; assembly calls `contribute!(pf, ctx, feeder; T=...)` and Julia dispatches. No `if formulation ==`.

**Confirmed against the actual stub:** `src/powerflow/AbstractPowerFlow.jl` declares `abstract type AbstractPowerFlow end` and `function contribute! end` with documented contract `contribute!(pf, ctx, feeder)` writing into `ctx.residuals[:nodal_balance]` via `add_to_residual!`. **The stub signature is `(pf, ctx, feeder)` — this phase must extend it to carry the horizon** (recommended `contribute!(pf::AbstractPowerFlow, ctx, feeder; T::Int=1)`), and generalize `:nodal_balance` to per-bus `:Rp` / `:Rq`. Update the docstring accordingly. [VERIFIED: src/powerflow/AbstractPowerFlow.jl]

**When to use:** Always — this is the PF-02 requirement and success criterion 1/4.

**Example (LinDistFlow — traced to thesis eqs, loss-less l=0 specialization of 3.31–3.33/3.43):**
```julia
# Source: thesis eqs 3.31 (active bal), 3.32 (reactive bal), 3.43 (voltage drop, l→0)
# — LinDistFlow = DistFlow with the loss/current terms (r·l, x·l, (r²+x²)·l) dropped.
struct LinDistFlow <: AbstractPowerFlow end

function contribute!(::LinDistFlow, ctx::ModelContext, feeder; T::Int = 1)
    m = ctx.model
    N = length(feeder.buses)
    B = feeder.branches
    # squared-voltage variable v = |V|²  (Pitfall: v is SQUARED — bounds are squared too)
    @variable(m, v[j = 1:N, t = 1:T])
    @variable(m, P[b = 1:length(B), t = 1:T])   # branch active flow, parent→child
    @variable(m, Q[b = 1:length(B), t = 1:T])   # branch reactive flow
    # root (frontier) squared voltage fixed to reference 1.0² (thesis: v_0 fixed)
    fix.(v[feeder.root, :], 1.0; force = true)
    for j in 1:N, t in 1:T                       # squared voltage bounds (3.35/3.45)
        vb = feeder.buses[j]
        set_lower_bound(v[j, t], vb.vmin^2)      # V²_min  ← square the pu bound
        set_upper_bound(v[j, t], vb.vmax^2)      # V²_max
    end
    for (b, br) in enumerate(B), t in 1:T        # voltage drop (3.33 with l=0 ⇒ 3.43)
        @constraint(m, v[br.to, t] == v[br.from, t]
                       - 2 * (br.r * P[b, t] + br.x * Q[b, t]))
    end
    # SUBTRACT branch terms into the shared residual (active 3.31 / reactive 3.32, loss-less):
    #   R_p,j = (inflow P into j) − (Σ outflow P from j) − p_ag_j ; device ADDS −p_load later.
    for j in 1:N, t in 1:T
        inflow  = sum(P[b, t] for (b, br) in enumerate(B) if br.to   == j; init = 0.0)
        outflow = sum(P[b, t] for (b, br) in enumerate(B) if br.from == j; init = 0.0)
        add_to_residual!(ctx, :Rp, j, t, inflow - outflow)
        qin  = sum(Q[b, t] for (b, br) in enumerate(B) if br.to   == j; init = 0.0)
        qout = sum(Q[b, t] for (b, br) in enumerate(B) if br.from == j; init = 0.0)
        add_to_residual!(ctx, :Rq, j, t, qin - qout)
    end
    ctx.meta[:pf_vars] = (; v, P, Q)   # stash for post-solve inspection / exactness later
    return ctx
end
```
```julia
# Source: DC = active-power-only linear flow (subset of the above; no v, no Q).
struct DCPowerFlow <: AbstractPowerFlow end
function contribute!(::DCPowerFlow, ctx::ModelContext, feeder; T::Int = 1)
    m = ctx.model
    B = feeder.branches
    @variable(m, P[b = 1:length(B), t = 1:T])
    for j in 1:length(feeder.buses), t in 1:T
        inflow  = sum(P[b, t] for (b, br) in enumerate(B) if br.to   == j; init = 0.0)
        outflow = sum(P[b, t] for (b, br) in enumerate(B) if br.from == j; init = 0.0)
        add_to_residual!(ctx, :Rp, j, t, inflow - outflow)   # ONLY :Rp — DC has no reactive/voltage
    end
    return ctx
end
```
[ASSUMED] The concrete `contribute!` bodies above are illustrative reconstructions from thesis equations + the Phase-1 seam — the planner should treat them as the intended shape, not verbatim final code. The *equation mapping* (3.31/3.32/3.33/3.43, l→0) is [CITED: THEORY-thesis.md §2.4].

**Note on the frontier (root) active balance.** The root bus is the MEM/TSO–DSO frontier priced at λ₀ (thesis §1). Model the frontier import as a variable `p_import[t] ≥ 0` (or free) injected at the root and included in the objective as `−λ₀·p_import`. Options: (a) add `p_import` into `:Rp[root,t]` as a device-like injection so the root balance closes; or (b) treat the head branch flow into node 1 as the import. Recommend (a) for symmetry with `toy_dc` (which used `p_import − p_load`). The **priced/DADP bus** for the first-price test is the load bus, not the root.

### Pattern 2: Assembly closes *every* residual present — zero formulation branching
**What:** Assembly does not know whether `:Rq` exists. It loops over the residual keys that were populated and pins each to zero, registering the constraint so its dual is recoverable. DC populates only `:Rp`; LinDistFlow populates `:Rp` and `:Rq`. Swapping formulations changes *which residuals exist*, and assembly handles both with the same loop — this is what makes success criterion 4 pass with no assembly edit.

```julia
# Close active balance (always present) and remember refs so dual(...) = DADP.
Np, T = size(ctx.residuals[:Rp])
@constraint(m, balance_p[j = 1:Np, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
register_constraint!(ctx, :balance_p, balance_p)          # dual = λ_j (DADP)
if haskey(ctx.residuals, :Rq)                             # LinDistFlow only — NOT an `if formulation ==`
    @constraint(m, balance_q[j = 1:Np, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
    register_constraint!(ctx, :balance_q, balance_q)
end
```
The `haskey(:Rq)` test keys off *what the residual registry contains*, not off a formulation flag — it stays true to "dispatch/data, not branching" (ARCHITECTURE.md Anti-Pattern 1). Document this distinction explicitly so a reviewer does not mistake it for formulation branching.

### Pattern 3: Device-as-type with a dispatched `contribute!` — the new `AbstractDevice` contract
**What:** Propose `abstract type AbstractDevice end` + a generic `function contribute! end` extended per device (mirrors `AbstractPowerFlow` exactly for consistency). The device's `contribute!` (a) creates its decision variables, (b) adds temporal/bound constraints, (c) **adds a signed injection into `ctx.residuals[:Rp]`** (and `:Rq` if it models reactive — the Interruptible load at this rung does **not**), and (d) **adds its concave quadratic utility into the objective accumulator**. The device is passed only its **bus id and horizon T** — never the `feeder`. That is the enforced decoupling.

**Interruptible/elastic load (DEV-03), traced to thesis eqs 3.10, 3.13–3.14:**
```julia
# Source: thesis 3.10 U = Σ_t[a·p − (b/2)p²] ; coeffs 3.13 a=λ_max+P_min·b, 3.14 b=(λ_max−λ_min)/(P_max−P_min)
struct Interruptible{T<:Real} <: AbstractDevice
    bus::Int          # node label ONLY — not topology
    Pmin::T
    Pmax::T
    a::T              # linear utility coeff  (price units, per-unit-power consistent)
    b::T              # quadratic utility coeff > 0  ⇒ CONCAVE utility ⇒ convex maximization
end

function contribute!(d::Interruptible, ctx::ModelContext; T::Int = 1)
    m = ctx.model
    @variable(m, d.Pmin <= p[t = 1:T] <= d.Pmax)          # power bounds (elastic load)
    # signed injection: a CONSUMED load is NEGATIVE net injection at its bus (sign matches toy_dc:
    #   balance was `p_import − p_load`; here the device contributes the −p_load part).
    for t in 1:T
        add_to_residual!(ctx, :Rp, d.bus, t, -p[t])       # ADD −p_load into shared :Rp
    end
    # concave quadratic utility into the WELFARE accumulator (QuadExpr — cannot use add_to_residual!)
    add_to_objective!(ctx, sum(d.a * p[t] - (d.b / 2) * p[t]^2 for t in 1:T))
    return ctx
end
```
The device references `d.bus` (a node index) and `T` (horizon) only. It never sees `feeder`, `branches`, `r`, `x`, or `v`. That is the conformance property success criterion 2 demands. [CITED: THEORY-thesis.md §2.2 eqs 3.10, 3.13–3.14; sign convention aligned with `test/test_toy_dc.jl`]

### Pattern 4: Two new `ModelContext` capabilities (minimal, additive Phase-1 extension)
The Phase-1 `ModelContext` has `residuals::Dict{Symbol,Any}` with a **scalar** `add_to_residual!(ctx, name, expr)` that forces `convert(AffExpr, expr)`. Two extensions are required:

1. **Indexed residual accumulator** — physical balance is per (bus, t). Add a method
   `add_to_residual!(ctx, name::Symbol, i::Int, t::Int, expr)` that lazily allocates
   `ctx.residuals[name]::Matrix{AffExpr}` (sized on first use / from `ctx.meta`) and does
   `M[i,t] += expr`. Keep the existing scalar method for `toy_dc` backward-compatibility (rung-0
   regression must stay green). The value type stays `AffExpr` — the nodal balance is affine.
2. **Objective (welfare) accumulator** — the quadratic utility is a `QuadExpr` and must NOT go through
   `add_to_residual!` (which converts to `AffExpr` and would error on a quadratic term). Add
   `add_to_objective!(ctx, expr)` that accumulates a `QuadExpr` (store under a dedicated key, e.g.
   `ctx.meta[:objective]` or `ctx.residuals[:objective]` bypassing the AffExpr conversion). Assembly
   reads it: `@objective(m, Max, ctx…objective − λ₀ᵀ·p_import)`.

This separation — **affine residual (price-bearing) vs. quadratic objective** — is the correct model shape and generalizes cleanly to Phase 3's social welfare `Σ U_ag − λ₀ᵀp₀` (3.38) and Phase 6's ADMM proximal terms.

### Anti-Patterns to Avoid
- **`if formulation == :dc` / `if device == …` branching** — kills swappability (ARCHITECTURE.md Anti-Pattern 1). Use dispatch. The one permitted data-driven test is `haskey(ctx.residuals, :Rq)` in assembly (keys off registry contents, not a formulation flag).
- **Passing `feeder` into a device** — breaks the device↔network decoupling that success criterion 2 tests. Device gets `bus::Int` + `T` only.
- **Routing the quadratic utility through `add_to_residual!`** — it converts to `AffExpr` and will error/silently drop curvature. Use `add_to_objective!`.
- **Reading `dual()` before `assert_solved!(…; dual=true)`** — a non-optimal QP yields garbage prices (Pitfall 4/8). Always gate.
- **Confusing `v` (squared voltage) with voltage** — bounds must be squared (`vmin^2`, `vmax^2`), root fixed at `1.0` not `1.0²`-confusion (they coincide at 1.0 but not elsewhere) (Pitfall 3).
- **Rebuilding the model to change data** — not a concern at this centralized rung, but keep builders parameterizable (Phase 6 ADMM will re-solve). Do not prematurely add `Parameter`s here (Anti-Pattern 7: over-engineering).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Solver selection | `Model(Clarabel.Optimizer)` in a model file | `Model(select_optimizer(QP()))` | INFRA-02 discipline; already built and tested. [CITED: src/solver/factory.jl] |
| Optimal-status + dual-trust check | Hand `termination_status == OPTIMAL` | `assert_solved!(m; dual=true, allow_local=false)` | Single choke point; also checks primal/dual status via `is_solved_and_feasible`. [CITED: src/core/status.jl] |
| Radial-topology / incidence validation | New graph code | `Feeder(...)` constructor (runs `assert_radial`) | Validation is a construction invariant; an invalid feeder cannot exist. [CITED: src/data/Feeder.jl] |
| Per-unit conversion | Convert inside the model builder | Convert once at ingestion via `to_pu_*`; model consumes pu | Prevents SI/pu mixing (Pitfall 3); `to_pu_*` are ingestion-only by design. [CITED: src/units/PerUnit.jl] |
| Residual coupling | Inline balance constraints in device/formulation | `add_to_residual!` accumulation | The PF-01 seam; accumulation is what removes branching. [CITED: src/core/ModelContext.jl] |

**Key insight:** Phase 1 already built the four hardest-to-get-right pieces (solver factory, status gate, feeder validation, per-unit tripwires). This phase should *consume* them, not re-implement — the only genuinely new machinery is the indexed residual + objective accumulators and the two formulations + one device.

## Runtime State Inventory

Not applicable — this is a **greenfield modeling phase** (adds new source files + tests to a young package). No rename/refactor/migration, no stored data, no live services, no OS-registered state, no secrets, no build artifacts to migrate.
- Stored data: **None** — no datastore exists in the project.
- Live service config: **None**.
- OS-registered state: **None**.
- Secrets/env vars: **None**.
- Build artifacts: **None to migrate** — `TSODSO` is a source package; `Pkg.instantiate`/precompile regenerate freely. (Verified: `src/` tree has no compiled artifacts; no `*.egg-info`/binary equivalents in Julia here.)

## Common Pitfalls

### Pitfall 1: Off-by-square voltage bounds (`v = V²`)
**What goes wrong:** LinDistFlow's voltage variable is *squared* magnitude. Setting bounds to `vmin`/`vmax` (magnitude) instead of `vmin²`/`vmax²`, or fixing the root at the wrong value, silently shifts every voltage and corrupts the voltage-drop constraint.
**Why it happens:** The `Bus` struct stores `vmin`/`vmax` as *magnitude* pu (tripwire band `[0.8,1.2]`); the model needs their squares.
**How to avoid:** Square the bounds at the model boundary: `set_lower_bound(v[j,t], bus.vmin^2)`; fix root `v` at `1.0` (=1.0²). Add a comment tracing to thesis 3.35/3.45.
**Warning signs:** Voltages clustering near `0.95`/`1.05` instead of `~0.90`/`~1.10` in squared space; a voltage-drop residual that doesn't vanish. [CITED: PITFALLS.md Pitfall 3]

### Pitfall 2: Wrong dual sign — the price comes out backwards
**What goes wrong:** JuMP's dual sign depends on objective sense (Max here) and constraint sense (`== 0`). Getting it wrong flips the price (a cost looks like a credit) while everything stays feasible.
**Why it happens:** The model *maximizes* welfare; sign intuition from cost-minimization is inverted.
**How to avoid:** **Anchor to the already-passing `toy_dc` convention** — in `test_toy_dc.jl`, objective `Max 3·p_load − 1·p_import` with balance `p_import − p_load == 0` yields `dual(balance) = +1.0` (positive = marginal import cost). Keep the *same* residual orientation (frontier import positive, load negative) so the DADP is positive = marginal cost. Assert the sign in the 2-bus test against the closed form `DADP = λ₀ > 0`.
**Warning signs:** Negative price at a normally-priced bus; DADP with opposite sign to λ₀. [CITED: PITFALLS.md Pitfall 7; test/test_toy_dc.jl]

### Pitfall 3: Non-convex objective from a wrong-sign quadratic
**What goes wrong:** The utility is `a·p − (b/2)p²` (concave, `b>0`). Writing `+ (b/2)p²`, or a negative `b`, makes utility convex → maximization unbounded/non-convex → Clarabel errors or returns garbage.
**Why it happens:** Sign slip on the curvature term; or `b` derived with wrong units so it's ~0 or negative.
**How to avoid:** Enforce `b > 0` at device construction (throw, per project convention — not `@assert`). Keep the `−(b/2)p²` sign. Maximizing a concave function is a convex program → valid QP for Clarabel.
**Warning signs:** `DUAL_INFEASIBLE`/`INFEASIBLE_OR_UNBOUNDED` status; objective diverging. [CITED: THEORY-thesis.md §2.2; PITFALLS.md Pitfall 4]

### Pitfall 4: Per-unit inconsistency between device power and utility coefficients
**What goes wrong:** Thesis coefficients are in ¢$/kWh and kW; feeder aggregates are pu-MW. If `a`,`b` are calibrated for kW power but `p` is in pu-MW, the utility term is off by orders of magnitude and the optimizer effectively ignores it — the solve succeeds, the price is meaningless.
**Why it happens:** `b = (λ_max−λ_min)/(P_max−P_min)` (3.14) has units price/power; it must match whatever unit `p` carries.
**How to avoid:** Choose ONE monetary+power unit for the optimization layer (recommend $/MWh + pu-power on the common `S_base`), convert coefficients once at ingestion, document the unit of every coefficient beside its equation number. Keep `to_pu_*` ingestion-only. For the MVP fixture, pick coefficients directly in the model's own units so the closed-form check is exact.
**Warning signs:** Welfare/price off by clean factors of 10/100/1000; the utility term dwarfed by the import-cost term. [CITED: PITFALLS.md Pitfall 3]

### Pitfall 5: Reading `dual()` of the wrong (or non-optimal) constraint
**What goes wrong:** Labeling the reactive-balance dual, or a voltage-drop constraint's dual, as the DADP; or reading before an OPTIMAL solve.
**How to avoid:** The DADP is the dual of the **active** balance `:balance_p` at the priced (load) bus. Recover via `dual(ctx.constraints[:balance_p][bus,t])` only after `assert_solved!(…; dual=true)`. Register `:balance_p` and `:balance_q` under distinct names.
**Warning signs:** Price magnitude unrelated to λ₀ or to marginal utility. [CITED: PITFALLS.md Pitfall 7/8]

## Code Examples

### Centralized linear solve exposing the first price (rung-1 assembly, generalizes `toy_dc`)
```julia
# Source pattern: generalizes src/models/toy_dc.jl to a real feeder + swappable formulation + device.
"solve_linear(feeder, pf, devices; T, λ₀) -> (ctx, objective, dadp)"
function solve_linear(feeder, pf::AbstractPowerFlow, devices::Vector{<:AbstractDevice};
                      T::Int = 1, λ₀)
    model = Model(select_optimizer(QP()))          # concave-quad utility ⇒ QP ⇒ Clarabel (INFRA-02)
    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder
    ctx.meta[:T] = T

    contribute!(pf, ctx, feeder; T = T)            # formulation: subtract branch/voltage terms
    for d in devices
        contribute!(d, ctx; T = T)                 # devices: add signed injection + utility
    end

    # frontier import at the root, priced at λ₀ (thesis §1); injected like a device into :Rp[root]
    @variable(model, p_import[t = 1:T] >= 0)
    for t in 1:T
        add_to_residual!(ctx, :Rp, feeder.root, t, p_import[t])
    end

    # close every present residual (Pattern 2) — no formulation branching
    Np = length(feeder.buses)
    @constraint(model, balance_p[j = 1:Np, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
    register_constraint!(ctx, :balance_p, balance_p)
    if haskey(ctx.residuals, :Rq)
        @constraint(model, balance_q[j = 1:Np, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
        register_constraint!(ctx, :balance_q, balance_q)
    end

    welfare = ctx.meta[:objective] - sum(λ₀[t] * p_import[t] for t in 1:T)   # 3.38-shaped
    @objective(model, Max, welfare)

    assert_solved!(model; dual = true, allow_local = false)                  # INFRA-03 gate
    priced = devices[1].bus                                                   # load bus
    dadp = dual.(balance_p[priced, :])
    return ctx, objective_value(model), dadp
end
```
[ASSUMED] Illustrative — the exact objective-accumulator access (`ctx.meta[:objective]`) depends on the Pattern-4 implementation the planner chooses.

### Closed-form fixture for the first-price test (2-bus radial, T=1)
```julia
# 2-bus radial: node 1 = frontier/root (v fixed 1.0), node 2 = elastic load, 1 branch.
# LinDistFlow is loss-less ⇒ p_import == p_load == p. Objective: max a·p − (b/2)p² − λ₀·p.
# FOC: a − b·p − λ₀ = 0  ⇒  p* = (a − λ₀)/b ;  DADP at node 2 = a − b·p* = λ₀   (loss-less).
buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
branches = [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0)]          # small pu r,x within tripwire band
feeder = TSODSO.Feeder(buses, branches, 1)
load = TSODSO.Interruptible(2, 0.0, 5.0, /*a=*/ 4.0, /*b=*/ 1.0)   # concave, b>0
ctx, obj, dadp = solve_linear(feeder, TSODSO.LinDistFlow(), [load]; T = 1, λ₀ = [2.0])
# @test dadp[1] ≈ 2.0            # DADP == λ₀ (loss-less)  → first price
# @test value(p*) ≈ (4.0-2.0)/1.0 = 2.0
```
The same fixture solved with `TSODSO.DCPowerFlow()` (drop the branch, or keep — DC ignores voltage) must give the **same** price/objective, and swapping the formulation argument must require **no** edit to `Interruptible` or `solve_linear` — that is success criterion 4, made into a `@testitem`. [CITED: closed-form derived from thesis 3.10 FOC; sign per test_toy_dc.jl]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hand-check `termination_status == OPTIMAL` | `is_solved_and_feasible(m; dual, allow_local)` (wrapped by `assert_solved!`) | JuMP ≥ 1.x modern idiom | Also validates primal/dual status; rejects `LOCALLY_SOLVED` for the convex core. [CITED: src/core/status.jl] |
| `direct_model(Clarabel.Optimizer())` for speed (CLAUDE.md perf note) | Standard `Model(...)` for Clarabel — it is `copy_to`-only | Corrected in Phase 1 (`factory.jl` comment, verified 2026-07-18) | `direct_model` **errors** with Clarabel; reserve it for HiGHS hot loops (Phase 6+). Do NOT use `direct_model` here. [CITED: src/solver/factory.jl] |

**Deprecated/outdated:** none newly introduced. Note the CLAUDE.md `direct_model`-for-Clarabel perf suggestion is superseded by the `factory.jl` correction above.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Extend `contribute!` signature to `(pf, ctx, feeder; T)` and generalize `:nodal_balance`→`:Rp`/`:Rq` (the Phase-1 stub is `(pf,ctx,feeder)` writing `:nodal_balance`). | Pattern 1 | If the planner keeps the exact stub signature, multi-bus/multi-period won't fit; low risk — the stub is explicitly a Phase-1 placeholder ("Concrete methods… Phases 2+"). |
| A2 | MVP uses multi-bus + **single-period T=1** for the priced fixture, but codes indexing as `(bus,t)`. | Alternatives; Pattern 4 | If a reviewer expects full 24h now, scope grows; but thesis-separable utility + MVP mode support T=1. Confirm during planning. |
| A3 | The Interruptible load injects **active power only** at this rung (no reactive `q`); reactive coupling (φ, eq 3.23) is a Phase-3 aggregator concern. | Pattern 3 | If DEV-03 is expected to inject reactive now, LinDistFlow's `:Rq` would be device-driven; low risk — reactive roll-up is explicitly Phase 3 (DEV-05). |
| A4 | Add `add_to_objective!` (QuadExpr accumulator) + indexed `add_to_residual!` to `ModelContext` — a Phase-1 file extension. | Pattern 4 | If the planner instead overloads `add_to_residual!` to accept QuadExpr, the affine/quadratic separation blurs; the recommended split is cleaner. Design choice, not correctness. |
| A5 | Assembly closes residuals by looping present keys + `haskey(:Rq)`; this is data-driven, not formulation branching. | Pattern 2 | If a reviewer reads `haskey` as branching, cosmetic; document the distinction. |
| A6 | Frontier import modeled as a `p_import ≥ 0` variable injected at root, priced `−λ₀·p_import` (mirrors toy_dc). | Pattern 1 note; Code Examples | Alternative (price the head-branch flow) also valid; both give the same closed-form. Low risk. |
| A7 | Coefficients `a`,`b` chosen directly in the model's own ($/MWh + pu) units for the MVP fixture (not converted from thesis ¢/kWh+kW). | Pitfall 4 | If real thesis coefficients are demanded now, a unit-conversion step is needed; MVP fixture is synthetic so risk is low. |

**These are the decisions the planner (and, if needed, a discuss-phase) should confirm.** None contradict CLAUDE.md or CONTEXT.md; all are anchored to thesis equations + the Phase-1 seam.

## Open Questions

1. **Exact objective-accumulator storage location.**
   - What we know: a `QuadExpr` accumulator is required; `ModelContext` fields are fixed (`constraints`, `residuals`, `meta`).
   - What's unclear: add a new struct field vs. store under `ctx.meta[:objective]` vs. a `:objective` key in `residuals` (bypassing AffExpr conversion).
   - Recommendation: store under `ctx.meta[:objective]` via a new `add_to_objective!` helper — no struct-field churn, keeps `residuals` strictly affine/physical. Revisit if Phase 3 wants per-node utility indexing.

2. **Should the pure-DC path ever be exercised as an `LP()` solve?**
   - What we know: with the concave-quadratic utility the problem is a QP regardless of formulation.
   - What's unclear: whether the conformance test should also prove a DC-only *linear-utility* LP path.
   - Recommendation: keep ONE priced solve (`QP()`→Clarabel) for both formulations; the DC↔LinDistFlow conformance test asserts identical price/objective, not a solver switch. A separate LP path is unnecessary scope (Anti-Pattern 7).

3. **Reactive handling under DC when a future reactive device appears.**
   - What we know: at this rung the device is active-only, so DC (no `:Rq`) is consistent.
   - What's unclear: Phase 3+ reactive devices + DC would create a device-driven `:Rq` DC can't close.
   - Recommendation: out of scope now; note for Phase 3 that reactive devices require a reactive-capable formulation (LinDistFlow/SOCP), not DC.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | Everything | ✓ | 1.12.5 (compat floor 1.10) | — |
| JuMP | Modeling | ✓ | 1.30.1 (pinned) | — |
| Clarabel | QP solve (`QP()`) | ✓ | 0.11.1 (pinned) | HiGHS supports convex QP but with less-accurate duals — keep Clarabel for prices |
| HiGHS | LP path | ✓ | 1.24.1 (pinned) | — |
| SparseArrays | Incidence | ✓ | stdlib | — |
| TestItemRunner/TestItems | Tests | ✓ | 1.1.5 / 1.0.0 (test env) | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none — all pinned in `Project.toml`. (Deps are declared/pinned; run `julia --project -e 'using Pkg; Pkg.instantiate()'` if the depot isn't materialized on a fresh checkout.)

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | TestItems 1.0.0 + TestItemRunner 1.1.5 (`@testitem` blocks, isolated modules) |
| Config file | `test/runtests.jl` (`@run_package_tests`) + `test/Project.toml` |
| Quick run command | `julia --project=. -e 'using TestItemRunner; @run_package_tests filter=ti->occursin("linear", ti.name)'` |
| Full suite command | `julia --project=. -e 'using Pkg; Pkg.test()'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PF-02 | DC & LinDistFlow both contribute into `:Rp` (LinDistFlow also `:Rq`) via dispatched `contribute!`; no `if formulation ==` | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` (filter `powerflow`) | ❌ Wave 0 |
| PF-02 (crit 4) | Swap DC↔LinDistFlow → identical price/objective, zero edit to device/assembly | conformance | filter `conformance` | ❌ Wave 0 |
| DEV-03 | Interruptible adds vars + concave quad utility + signed `:Rp` injection; never references `feeder` | unit | filter `device` (build against a mock `ModelContext`, no feeder constructed) | ❌ Wave 0 |
| crit 3 | Centralized QP solve closes balance, `OPTIMAL`, exposes DADP = `dual(:balance_p[load,t])` | integration | filter `linear` | ❌ Wave 0 |
| crit 3 (analytic) | 2-bus loss-less: `DADP ≈ λ₀`, `p* ≈ (a−λ₀)/b`, sign positive | integration | filter `linear` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** run the filtered `@testitem`(s) for the file touched (`powerflow` / `device` / `linear` / `conformance`).
- **Per wave merge:** `julia --project=. -e 'using Pkg; Pkg.test()'` (includes Aqua).
- **Phase gate:** full suite green (including the rung-0 `toy_dc` regression) before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/test_powerflow.jl` — DC & LinDistFlow contribute correct residual terms against a mock `ModelContext` (no feeder-network coupling); covers PF-02.
- [ ] `test/test_device.jl` — Interruptible builds vars/utility/injection with **no `feeder` argument**; covers DEV-03 + criterion 2 (network-agnostic).
- [ ] `test/test_conformance.jl` — DC↔LinDistFlow swap yields identical results with no device/assembly edit; covers criterion 4.
- [ ] `test/test_linear_solve.jl` — 2-bus analytic DADP + objective; covers criterion 3.
- [ ] No new framework install needed (TestItemRunner already present). Keep the existing `test_toy_dc.jl` rung-0 item green (backward-compat of the extended `ModelContext`).

## Security Domain

`security_enforcement` is not set to `false` in config, but this is a **research optimization library with no attack surface** — no auth, sessions, access control, network I/O, untrusted input, or cryptography. The ASVS web-application control families do not map. The project's own framing (PITFALLS.md §Security) is explicit: *"security here maps to research integrity and reproducibility."* Applying that lens:

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — (no users/auth) |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | partial | Feeder construction invariants (`assert_radial`, `assert_magnitudes`) + `b>0` device check + `assert_solved!` status gate are the "input validation" analog — reject invalid models loudly (throw, never `@assert`). |
| V6 Cryptography | no | — (never hand-roll — but none needed) |

### Known Threat Patterns for a research optimization bench

| Pattern | STRIDE-analog | Standard Mitigation |
|---------|--------|---------------------|
| Silent wrong price (inexact/relaxed model read as truth) | Information disclosure (of a false result) | `assert_solved!(dual=true)`; analytic-fixture price assertion; positive-sign check (Pitfall 2). |
| Non-reproducible result (unpinned env) | Repudiation (can't trace a figure) | Committed `Manifest.toml`/`Project.toml [compat]`; this phase adds no deps, preserving the pin. |
| Hidden constraint slack / infeasibility masking | Tampering (with the model's meaning) | `assert_no_slack` available; no elastic slacks in the correctness path (Pitfall 8). |
| Unit/scale corruption of prices | Tampering | Per-unit tripwires (`assert_magnitudes`); coefficients documented in model units (Pitfall 4). |

## Sources

### Primary (HIGH confidence)
- `src/powerflow/AbstractPowerFlow.jl`, `src/core/ModelContext.jl`, `src/core/status.jl`, `src/solver/factory.jl`, `src/solver/ProblemClass.jl`, `src/data/Feeder.jl`, `src/data/topology.jl`, `src/units/PerUnit.jl`, `src/models/toy_dc.jl`, `src/TSODSO.jl` — read verbatim; the exact seam signatures and conventions this phase must honor.
- `test/test_toy_dc.jl`, `test/test_context.jl`, `test/test_factory.jl`, `test/runtests.jl` — established test idioms (`@testitem`, tags, `is_solved_and_feasible`), and the empirical dual-sign convention (`dual(balance)=+1.0`).
- `.planning/research/THEORY-thesis.md` — operational formulation eqs 3.10 (interruptible utility), 3.13–3.14 (coeffs), 3.31–3.33 (balances + voltage), 3.43/3.45 (LinDistFlow copy), DADP-as-dual. Primary-source extraction.
- `.planning/research/ARCHITECTURE.md` — formulation/device-as-type dispatch idiom, residual-registry keystone, build-order (rung 1 = this phase), anti-patterns.
- `.planning/research/PITFALLS.md` — off-by-square voltage (P3), dual sign (P7), convexity/solver (P4), infeasibility masking (P8).
- `Project.toml` / `test/Project.toml` — pinned versions; no new deps.
- `CLAUDE.md` — solver discipline, JuMP-over-Convex, Clarabel-for-QP-duals, no hard-coded solvers.

### Secondary (MEDIUM confidence)
- `.planning/ROADMAP.md` Phase 2 entry + `02-CONTEXT.md` — scope, success criteria, deferred boundaries.

### Tertiary (LOW confidence)
- None. (LinDistFlow standard form is corroborated by thesis 3.43 with l→0; no unverified web claims used.)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; all versions read from committed `Project.toml`.
- Architecture / seam signatures: HIGH — read verbatim from Phase-1 source; the one extension (signature + indexed residual + objective accumulator) is explicitly anticipated by the Phase-1 stub docstrings.
- Formulation/device equations: HIGH — traced to primary-source thesis equations (3.10, 3.13–3.14, 3.31–3.33, 3.43, 3.45).
- Concrete `contribute!` bodies: MEDIUM — illustrative reconstructions (tagged `[ASSUMED]`); the *shape and equation mapping* are HIGH, the *exact Julia* is for the planner/executor to finalize.
- Pitfalls: HIGH — sourced from the project's own PITFALLS.md, scoped to this rung.

**Research date:** 2026-07-18
**Valid until:** 2026-08-17 (stable — pinned environment, primary-source theory; re-check only if `ModelContext`/`AbstractPowerFlow` seams change before planning).
