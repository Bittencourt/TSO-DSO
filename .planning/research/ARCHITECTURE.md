# Architecture Research

**Domain:** Julia/JuMP multi-model, multi-solver research framework for TSO–DSO transactive energy (convex branch-flow social-welfare optimization + ADMM) with a designed-in seam for a Stackelberg–Nash planning layer (Benders + diagonalization).
**Researched:** 2026-07-18
**Confidence:** HIGH (Julia/JuMP/PowerModels idioms verified against current docs; thesis math from `.planning/research/THEORY-*.md`; planning-layer coupling MEDIUM — theory note flags some author inconsistencies).

---

## Guiding principle

The architecture is organized around **one invariant**: the *nodal power-balance residual* `R_p[j,t]`, `R_q[j,t]` (thesis eq. 3.31–3.32). This single object is:

- the constraint that couples devices to the network,
- the thing whose dual is the DADP/DLMP price (eq. 3.46),
- the ADMM consensus residual (eq. 3.47),
- and (aggregated to the feeder head) the coupling flow `z` to the planning layer (papers §"how the two layers compose").

Every swappable component (power-flow formulation, device model, solve strategy) meets at this residual registry and nowhere else. That is what keeps power-flow, devices, and solve-strategy **mutually independent and independently swappable** — the core requirement.

The concrete Julia idiom is the one proven by **PowerModels.jl**: an abstract type hierarchy for formulations, **multiple dispatch** to build formulation-specific JuMP constraints into a shared model, and a *template layer* that separates "pull parameters out of the data" from "add variables/constraints." We adopt that idiom but keep our own formulation/objective layer, because PowerModels is generator-centric OPF and does not model prosumer utilities, aggregators, ADMM price recovery, or the LinDistFlow-exactness DADP trick.

---

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│  EXPERIMENT / SCENARIO LAYER   (declarative config → run → save)       │
│  Scenario spec · seeded profile gen · DrWatson reproducibility         │
└───────────────┬──────────────────────────────────────────────────────┘
                │ builds
┌───────────────▼──────────────────────────────────────────────────────┐
│  SOLVE STRATEGY LAYER      AbstractSolveStrategy                        │
│  ┌──────────────┐   ┌─────────────────────────┐   ┌────────────────┐  │
│  │ Centralized  │   │ ADMM (outer loop:        │   │ Planning oracle│  │
│  │ (monolithic) │   │  AGR-OPT/j + DSO-OPT/t,  │   │ (Benders /     │  │
│  │              │   │  λ,μ,ρ,residuals)        │   │  diagonalize)  │  │
│  └──────┬───────┘   └────────────┬────────────┘   └───────┬────────┘  │
│         │  both reuse the SAME builders below              │ calls    │
└─────────┼───────────────────────────────────────────────┼──────────┘
          │                                                 │ oracle(z)→(cost,π)
┌─────────▼─────────────────────────────────────────────────────────────┐
│  MODEL ASSEMBLY   ModelContext{F}  (owns JuMP Model + registries)      │
│  build!: powerflow → devices → aggregate → couple(Rp,Rq) → objective   │
│  Registries:  var[]   Rp[j,t]   Rq[j,t]   utility[j]   balance_con[j,t] │
└───┬────────────────┬───────────────────┬───────────────────┬──────────┘
    │ dispatch on F  │ dispatch on device│ sums into Rp/util │ Σutil−λ₀ᵀp₀
┌───▼──────────┐ ┌───▼──────────┐ ┌──────▼────────┐ ┌────────▼──────────┐
│ POWER-FLOW   │ │ DEVICE       │ │ AGGREGATOR    │ │ OBJECTIVE          │
│ FORMULATIONS │ │ MODELS       │ │ (node roll-up)│ │ ASSEMBLY           │
│ DC·LinDist·  │ │ Thermo·Defer·│ │ p_ag,q_ag,U_ag│ │ social welfare     │
│ SOCBF·Meshed │ │ Interr·PVBatt│ │               │ │                    │
└───┬──────────┘ └───┬──────────┘ └──────┬────────┘ └────────┬──────────┘
    └────────────────┴───────────────────┴───────────────────┘
                                │ read-only
┌───────────────────────────────▼──────────────────────────────────────┐
│  DATA MODEL (pure structs, NO JuMP)                                    │
│  Network(buses,branches,R/X,Vlim,Smax) · DeviceSpec · Aggregator ·     │
│  MarketData(λ₀[t]) · Scenario(PV/demand params) · Horizon(T,Δt)        │
│  + parsers/fixtures: IEEE 13-node, IEEE 123-node                       │
└───────────────────────────────┬──────────────────────────────────────┘
                                 │ interface
┌───────────────────────────────▼──────────────────────────────────────┐
│  SOLVER ABSTRACTION   select_optimizer(::ProblemClass)                 │
│  LP/MILP→HiGHS · NLP→Ipopt · SOCP→Clarabel/SCS · fallback→Gurobi       │
└───────────────────────────────────────────────────────────────────────┘

RESULTS / PRICING (cross-cutting, reads ModelContext after solve):
DADP = dual(balance_con) or ADMM λ_j · DLMP decomposition · exactness check l·v≈P²+Q²
```

### Component Responsibilities

| Component | Owns | Julia realization |
|-----------|------|-------------------|
| **Data model** | Immutable problem data; feeder fixtures; seeded profile generation | Plain `struct`s + parsers; no JuMP dependency |
| **Power-flow formulations** | Network variables (`v,l,P,Q`) and constraints; contributes branch terms to `Rp/Rq` | `abstract type AbstractPowerFlow` + concrete types, dispatched builders |
| **Device models** | Per-device variables, temporal-coupling constraints, power-injection expr, utility expr | `abstract type AbstractDevice` + concrete types, dispatched builders |
| **Aggregator** | Rolls houses/devices at a node into `p_ag,q_ag,U_ag` (eq. 3.21–3.23); injects into `Rp/Rq` and `utility` | Pure function over a device set + `ModelContext` |
| **Objective assembly** | Social welfare `Σ U_ag − λ₀ᵀp₀` (eq. 3.38) | Dispatch on an `AbstractObjective` (welfare / FIT baseline) |
| **Model assembly (`ModelContext`)** | The shared JuMP model + all registries; orchestrates build order; asserts balance | `mutable struct ModelContext{F}` + `build!` |
| **Solve strategy** | *How* the problem is solved; owns iteration state | `abstract type AbstractSolveStrategy`: `Centralized`, `ADMM` |
| **Pricing / results** | Extract DADP from duals; DLMP decomposition; exactness validation | Functions reading the post-solve `ModelContext` |
| **Solver abstraction** | Map problem class → configured optimizer | `select_optimizer(::ProblemClass)` |
| **Experiment layer** | Declarative scenario → assemble → run → persist reproducibly | Config structs + DrWatson |
| **Planning layer (future)** | Benders master, Gauss–Seidel diagonalization; treats operational solve as an oracle | `abstract type AbstractEquilibriumSolver`; calls `operational_oracle(z)` |

---

## Recommended Project Structure

Single registered-style package (working name `TSODSO.jl`; rename freely), submodules by concern. Single package (not a monorepo of packages) is correct for a solo/small-team PhD bench: one `Project.toml`/`Manifest.toml` to pin, one test suite, one doc build.

```
TSODSO.jl/
├── Project.toml                 # deps + [compat]; the reproducibility anchor
├── Manifest.toml                # pinned resolve — commit it
├── src/
│   ├── TSODSO.jl                # top module: includes, exports, public API
│   ├── data/                    # LAYER 0 — pure data, no JuMP
│   │   ├── network.jl           # Network, Bus, Branch (R/X, limits, Vmin/Vmax, Smax)
│   │   ├── devices_spec.jl      # ThermoSpec, DeferSpec, InterrSpec, BatterySpec
│   │   ├── aggregator.jl        # Aggregator = node + its houses/devices
│   │   ├── market.jl            # MarketData: λ₀[t]; Horizon: T, Δt
│   │   ├── scenario.jl          # Scenario: PV/demand parameter profiles (+ RNG seed)
│   │   ├── profilegen.jl        # Markov-chain PV/occupancy → hourly params (DATA-GEN only)
│   │   └── fixtures/            # ieee13.jl, ieee123.jl parsed test feeders
│   ├── powerflow/               # LAYER 1 — swappable formulations
│   │   ├── interface.jl         # AbstractPowerFlow; required-method contract + docstrings
│   │   ├── dc.jl                # DCPowerFlow (toy rung)
│   │   ├── lindistflow.jl       # LinDistFlow (linear branch flow)
│   │   ├── socbf.jl             # SOCBranchFlow: DistFlow SOC (3.39) + LinDistFlow exactness (3.43,3.45)
│   │   └── meshed.jl            # MeshedSOCBranchFlow (future extension — stub + docs)
│   ├── devices/                 # LAYER 1 — pluggable devices (sibling of powerflow)
│   │   ├── interface.jl         # AbstractDevice; required-method contract
│   │   ├── thermostatic.jl      # eq. 3.2–3.3, utility 3.11
│   │   ├── deferrable.jl        # eq. 3.4–3.5, utility 3.12
│   │   ├── interruptible.jl     # utility 3.10
│   │   └── pvbattery.jl         # eq. 3.6–3.9, utility 3.15–3.20 (no binaries — App. C)
│   ├── aggregate.jl             # LAYER 2 — device set → nodal p_ag,q_ag,U_ag (3.21–3.23)
│   ├── model/                   # LAYER 3 — assembly
│   │   ├── context.jl           # ModelContext{F}; registries; residual API
│   │   ├── build.jl             # build_operational!: orchestrates the build order
│   │   └── objective.jl         # AbstractObjective: SocialWelfare (3.38), FIT baseline (benchmark)
│   ├── solve/                   # LAYER 4 — strategies
│   │   ├── interface.jl         # AbstractSolveStrategy
│   │   ├── centralized.jl       # one ModelContext → optimize!
│   │   ├── admm.jl              # AGR-OPT/j + DSO-OPT/t + outer dual loop (3.46–3.47)
│   │   └── diagnostics.jl       # residual norms, iteration log, convergence test
│   ├── solvers.jl               # LAYER -1 — select_optimizer(::ProblemClass)
│   ├── results/                 # cross-cutting — pricing & validation
│   │   ├── pricing.jl           # DADP extraction; DLMP decomposition (energy/loss/cong/volt)
│   │   ├── exactness.jl         # assert l·v ≈ P²+Q² at optimum
│   │   └── solution.jl          # OperationalSolution struct (immutable result)
│   ├── planning/                # FUTURE — Stackelberg–Nash (stubs + interfaces now)
│   │   ├── oracle.jl            # operational_oracle(z) → (cost, π): the Benders subproblem
│   │   ├── benders.jl          # single-distributor Stackelberg master (4a–4f)
│   │   └── diagonalize.jl      # Gauss–Seidel Nash over distributors
│   └── experiments/             # LAYER 5
│       ├── config.jl            # declarative ExperimentSpec (TOML/struct)
│       └── run.jl               # assemble → solve → collect → persist (DrWatson)
├── test/                        # unit per layer + validation vs thesis numbers
│   ├── runtests.jl
│   ├── test_powerflow.jl        # each formulation against a mock ModelContext
│   ├── test_devices.jl          # each device against a mock ModelContext
│   ├── test_exactness.jl        # SOCP exact on IEEE 13 (v₉[16]≈1.0493)
│   └── test_admm_vs_central.jl  # ADMM optimum ≈ centralized optimum & duals
├── docs/                        # Documenter.jl: math + assumptions per model (hard requirement)
└── experiments/                 # runnable scripts + saved outputs (git-tracked configs)
```

### Structure Rationale

- **`data/` has no JuMP dependency.** It is the only layer everything else reads, and keeping it pure means fixtures and profile generation are trivially unit-testable and the whole domain model can be inspected without building an optimization model. Profile generation (Markov chains) lives here because it is *data generation, not optimization* (thesis §2.8).
- **`powerflow/` and `devices/` are siblings that never import each other.** They only know `ModelContext`. Their coupling happens one layer up (`aggregate.jl` + `model/build.jl`). This is the linchpin of swappability: you can replace `SOCBranchFlow` with `MeshedSOCBranchFlow` without touching any device, and add a new device without touching any formulation.
- **`model/` is the only place that knows both** the balance residuals (from powerflow) and the injections (from devices). Concentrating that knowledge in one small, well-tested module is what keeps the dependency graph acyclic.
- **`solve/` sits above assembly** and consumes builder *functions*, not concrete models — so `Centralized` and `ADMM` share every constraint/variable definition and cannot drift apart.
- **`planning/` ships as interfaces + stubs in v1** (the `operational_oracle` signature especially), so the operational engine is built oracle-shaped from day one and the later Benders loop is additive, not a refactor.

---

## Architectural Patterns

### Pattern 1: Formulation-as-type + dispatched builders (the PowerModels idiom)

**What:** The power-flow model is a *type*, not a flag. Builder functions dispatch on it to emit different JuMP constraints into the shared model. Verified as the current PowerModels.jl mechanism (`AbstractPowerModel` subtypes + method dispatch across formulations).

**When:** Whenever you need multiple mathematically-different models behind one interface. This is the answer to "swap DC / LinDistFlow / SOCP / meshed."

**Trade-offs:** Maximum extensibility and zero `if formulation == ...` branching; cost is that adding a formulation means implementing a known method set (mitigated by a documented interface + an interface-conformance test).

```julia
abstract type AbstractPowerFlow end
abstract type AbstractBranchFlow <: AbstractPowerFlow end   # shared DistFlow structure

struct DCPowerFlow        <: AbstractPowerFlow  end          # toy rung
struct LinDistFlow        <: AbstractBranchFlow end          # linear branch flow
struct SOCBranchFlow      <: AbstractBranchFlow end          # SOC (3.39) + exactness (3.43,3.45)
struct MeshedSOCBranchFlow<: AbstractBranchFlow end          # future

# Required interface (documented in powerflow/interface.jl):
"""add v,l,P,Q (and the LinDistFlow copy v̂) to ctx for this formulation."""
function powerflow_variables! end
"""add branch/voltage/current constraints; SUBTRACT branch terms into ctx.Rp/ctx.Rq."""
function powerflow_constraints! end

# Concrete: SOCP branch flow (thesis 2.4)
function powerflow_constraints!(ctx::ModelContext, ::SOCBranchFlow)
    jm, net = ctx.jm, ctx.net
    for (i,j) in branches(net)
        # voltage drop (3.33), SOC relaxation (3.39), thermal (3.36-3.37) ...
        @constraint(jm, ctx.var[:l][i,j,:] .>= ...)          # l ≥ (P²+Q²)/v
        # LinDistFlow exactness copy (3.43,3.45) — ESSENTIAL for meaningful duals
        # accumulate branch contribution into the nodal residual:
        add_to_residual_p!(ctx, j, ctx.var[:P][i,j,:] .- net.r[i,j].*ctx.var[:l][i,j,:])
    end
end
```

### Pattern 2: Device-as-type contributing (vars, constraints, injection, utility)

**What:** Each prosumer device is a type implementing four methods; the aggregator sums their `injection` into the nodal residual and their `utility` into the objective. Devices never reference the power-flow model.

**When:** Any component that adds decision variables + a power contribution + a preference term. New device (e.g., EV smart charger, four-quadrant inverter reactive support) = one new file.

**Trade-offs:** Clean plug-in and per-device unit testing; requires a disciplined contract so aggregation can treat all devices uniformly.

```julia
abstract type AbstractDevice end
struct Thermostatic  <: AbstractDevice; spec::ThermoSpec  end
struct Deferrable    <: AbstractDevice; spec::DeferSpec   end
struct Interruptible <: AbstractDevice; spec::InterrSpec  end
struct PVBattery     <: AbstractDevice; spec::BatterySpec end

device_variables!(ctx, d::AbstractDevice)          # register p[t], soc[t], T_in[t]...
device_constraints!(ctx, d::AbstractDevice)        # temporal coupling (3.2-3.9)
device_injection(ctx, d::AbstractDevice)           # -> (p[t], q[t]) signed net power (3.22-3.23)
device_utility(ctx, d::AbstractDevice)             # -> QuadExpr, concave (3.10-3.20)

# PV+battery needs NO binaries (App. C proof) — pure continuous:
function device_constraints!(ctx, d::PVBattery)
    @variable(ctx.jm, 0 <= p_ch[t in T] <= d.spec.Pmax)
    @variable(ctx.jm, 0 <= p_dch[t in T] <= d.spec.Pmax)
    @constraint(ctx.jm, [t in T[1:end-1]],           # SOC dynamics (3.6)
        soc[t+1] == soc[t] + (d.spec.η*p_ch[t] - p_dch[t]/d.spec.η)*Δt)
    # (3.7-3.9) bounds; λ_min≤λ_med≤λ_max parametrization prevents simultaneous ch/dch
end
```

### Pattern 3: Residual registry as the universal coupling seam

**What:** `ModelContext` holds `Rp[j,t]`, `Rq[j,t]` as accumulating `AffExpr` registries plus a `utility[j]` accumulator. Power-flow subtracts branch terms; devices/aggregator add injections. Assembly then *chooses how to close the balance* — the ONE line that differs between centralized and ADMM.

**When:** Always. This is the architectural keystone that makes centralized and ADMM share 100% of model code.

**Trade-offs:** A tiny amount of indirection (you add to an expression rather than writing the constraint inline) buys the entire swappability + decomposition story.

```julia
mutable struct ModelContext{F<:AbstractPowerFlow}
    jm::Model
    net::Network
    form::F
    var::Dict{Symbol,Any}                    # variable registry by name
    Rp::Matrix{AffExpr}                      # nodal active residual [node, t]  (3.31)
    Rq::Matrix{AffExpr}                      # nodal reactive residual [node, t] (3.32)
    utility::Vector{AffExpr}                 # per-node utility accumulator (3.21)
    balance_con::Union{Nothing,Matrix{ConstraintRef}}   # set only in centralized
end

# CENTRALIZED closes the balance and remembers the ref (its dual = DADP):
function close_balance_centralized!(ctx)
    ctx.balance_con = @constraint(ctx.jm, [j in nodes, t in T], ctx.Rp[j,t] == 0)  # dual = λ_j (DADP)
    @constraint(ctx.jm, [j in nodes, t in T], ctx.Rq[j,t] == 0)
end
# ADMM instead penalizes the SAME Rp/Rq with (ρ/2)‖·‖² and prices λ,μ (see Pattern 4).
```

### Pattern 4: Solve-strategy as type; ADMM reuses the builders

**What:** `Centralized` builds one context and calls `close_balance_centralized!`. `ADMM` builds *per-node AGR contexts* (devices + aggregator only) and *per-hour DSO contexts* (power-flow only), each adding the `(ρ/2)‖R‖²` proximal term and a `−λᵀp_ag`/dual term to the exact same `Rp/Rq` expressions, then runs the outer dual-ascent loop. No constraint is written twice.

**When:** Selectable per experiment (PROJECT requirement). Centralized for clarity/small cases + shadow-price cross-check; ADMM for scale + native price recovery.

**Trade-offs:** The outer loop is custom code (iteration, residual bookkeeping, parallel `AGR-OPT` solves), but it is thin because all heavy model-building is shared.

```julia
abstract type AbstractSolveStrategy end
struct Centralized <: AbstractSolveStrategy end
struct ADMM <: AbstractSolveStrategy; ρ::Float64; ε::Float64; maxiter::Int end

solve(::Centralized, spec) = ( build one ModelContext; close_balance_centralized!; optimize!;
                               DADP = dual.(ctx.balance_con) )

function solve(s::ADMM, spec)
    agr = [build_agr_context(spec, j) for j in nodes]   # per-node QP (3.46), device builders reused
    dso = build_dso_context(spec)                       # per-hour SOCP (3.47), powerflow builders reused
    λ, μ = init_prices(); 
    for k in 1:s.maxiter
        p_ag = solve_all(agr; λ, μ, ρ=s.ρ)              # AGR-OPT, parallelizable over j
        R    = solve_dso(dso; p_ag, λ, μ, ρ=s.ρ)        # DSO-OPT → residuals R_p,R_q
        λ .+= s.ρ .* R.p;  μ .+= s.ρ .* R.q             # dual update (3.47 tail)
        converged(R, s.ε) && break                      # |R|≤ε ∀t,j  (~28 iters, thesis)
    end
    return DADP = λ                                     # λ_j IS the DADP at convergence
end
```

### Pattern 5: Operational engine as a Benders oracle (planning seam)

**What:** The planning layer never sees inside the operational model. It calls `operational_oracle(z)` — fix/penalize the distributor's import profile `z` (≈ feeder-head net `p₀`, papers §"compose"), solve operationally, return `(cost, π)` where `π` is the dual of the frontier coupling (≈ DADP at node 0). Benders master adds cut `α ≥ w^k + Σ_s π_s^k (z − z^k)` (eq. 4f). Multiple distributors → wrap the whole thing in Gauss–Seidel diagonalization (fix others' `z`, optimize each in turn).

**When:** v2+. But the `operational_oracle` signature is defined and stubbed in v1 so the operational solve is oracle-shaped from the start.

**Trade-offs:** Requires the operational solve to accept a *parameterized/fixed import* and return the coupling dual — a small extra output, not a redesign, if planned in.

```julia
"Benders subproblem: import profile z fixed → (operational cost, coupling dual π)."
function operational_oracle(spec, z; strategy=Centralized())
    ctx = build_operational!(spec)
    con = @constraint(ctx.jm, feeder_head_flow(ctx) .== z)   # coupling (2e)/(1j)
    optimize_with!(ctx, strategy)
    return (cost = objective_value(ctx.jm), π = dual.(con))  # π_s = ∂cost/∂z (2e)
end
```

---

## Data Flow

### Build-time flow (assembling one operational model)

```
Scenario spec ─► Network + Devices + Market (data structs, no JuMP)
                     │
                     ▼
   build_operational!(ModelContext{SOCBranchFlow})
     1. powerflow_variables!  + powerflow_constraints!   → var[:v,:l,:P,:Q], subtract into Rp/Rq
     2. for each aggregator: for each device:
          device_variables! → device_constraints! → collect injection & utility
     3. aggregate!:  add p_ag,q_ag into Rp/Rq ;  add U_ag into utility  (3.21-3.23)
     4. set_objective!:  max Σ utility − λ₀ᵀ p₀          (3.38)
     5. close balance:  centralized → Rp==0 (keep ref) │ ADMM → proximal penalty
```

### Solve-time & price flow

```
CENTRALIZED:  optimize! ─► status check ─► DADP = dual(balance_con[j,t])
ADMM:         outer loop (AGR/j ∥, DSO/t) ─► residuals ─► dual update ─► DADP = λ_j at convergence
                     │
                     ▼
POST:  exactness check  l_{ij}·v_i ≈ P²+Q²   (must hold — else duals meaningless)
       DLMP decomposition:  λ_j = energy + loss + congestion + voltage terms
       OperationalSolution (immutable) ─► experiment layer ─► DrWatson save
```

### Dependency direction (strictly acyclic)

```
solvers ◄─ data ◄─ powerflow ─┐
                   devices ────┤ (siblings; no mutual dep)
                   aggregate ◄─┘ (knows both)
                   model/assembly ◄─ objective
                   solve/strategy ◄─ model
                   results ◄─ model            (reads post-solve)
                   experiments ◄─ solve, results, data
                   planning ◄─ solve (via oracle only)   [future]
```

No arrow points downward. `powerflow` and `devices` are leaves that share only the `ModelContext` type. This is what makes each layer unit-testable against a *mock* `ModelContext` in isolation (a device test never constructs a network; a formulation test never constructs a device).

---

## Scaling Considerations (problem-size, not users)

| Scale | Architecture response |
|-------|-----------------------|
| Toy: 11-node, 24h, 1 device, DC, centralized | Monolith solve in HiGHS/Ipopt; validates plumbing end-to-end. |
| IEEE 13-node, full devices, SOCP, centralized | Single SOCP in Clarabel; cross-check that duals reproduce thesis DADP; confirm exactness (`v₉[16]≈1.0493`). |
| IEEE 123-node, 85 nodes, ADMM | ADMM with **parallel `AGR-OPT` over nodes** (`Threads`/`Distributed`); DSO-OPT per hour also parallel over `t`. This is where decomposition pays off (~28 iters, thesis). |
| Stochastic (S scenarios × horizon) | Scenario is a *parameter axis* on the data model; extend objective to `(1/S)Σ_s`; scenario decomposition (progressive hedging / SDDP-style) slots in as another `AbstractSolveStrategy`. |
| Planning (multi-distributor Stackelberg–Nash) | Benders master (HiGHS/Gurobi MILP) + operational oracle per scenario; diagonalization outer loop over distributors; integer imports → binary expansion + Lagrangian cuts. |

**First bottleneck:** SOCP solve time on the 123-node feeder → answered by ADMM parallelism (the primary reason ADMM is in scope). **Second:** scenario explosion under stochastic uncertainty → scenario decomposition as a pluggable strategy. **Third:** MILP planning master growth → Lagrangian/integer L-shaped cuts (papers §integer case). Do **not** pre-optimize; PROJECT explicitly favors clarity/traceability over premature performance.

---

## Anti-Patterns

### Anti-Pattern 1: Baking the power-flow formulation into device/aggregator code
**What people do:** Write the branch-flow balance inline where devices are summed, or `if formulation == :socp` branches.
**Why it's wrong:** Couples devices to a specific network model; adding meshed/DC/LinDistFlow means editing device code; kills independent swappability (a hard requirement).
**Instead:** Devices only *add to* `ctx.Rp/ctx.Rq`; formulations only *subtract into* them; assembly closes the balance. Dispatch on types, never branch on formulation flags.

### Anti-Pattern 2: Separate constraint code for centralized vs ADMM
**What people do:** Re-derive `AGR-OPT`/`DSO-OPT` constraints by hand, parallel to the monolithic model.
**Why it's wrong:** The two drift; a fix in one is forgotten in the other; validation (`ADMM ≈ centralized`) fails for the wrong reasons.
**Instead:** Both call the same `device_*!`/`powerflow_*!` builders; the *only* difference is how the residual is closed (hard constraint vs proximal penalty + dual). Make `test_admm_vs_central.jl` a first-class validation.

### Anti-Pattern 3: Dropping the LinDistFlow exactness copy
**What people do:** Implement only the SOC relaxation `l ≥ (P²+Q²)/v` and read the duals.
**Why it's wrong:** Without the LinDistFlow affine voltage constraints (3.43,3.45), the relaxation is not exact at the optimum and **the DADP/DLMP prices are meaningless** (thesis §2.4, papers cautionary flag).
**Instead:** Always emit the parallel loss-less copy; add `test_exactness.jl` asserting `l·v ≈ P²+Q²`; refuse to report prices if exactness fails.

### Anti-Pattern 4: Hard-coding the solver in model code
**What people do:** `Model(Clarabel.Optimizer)` inside builders; `import Gurobi` at top of a model file.
**Why it's wrong:** Violates the solver-abstraction constraint; makes Gurobi a hard dep; blocks per-problem-class solver choice.
**Instead:** `select_optimizer(::ProblemClass)` returns a configured optimizer; models are solver-agnostic; Gurobi is an optional weak dependency behind the abstraction.

### Anti-Pattern 5: Reading duals/results without status + exactness gating
**What people do:** `dual(con)` immediately after `optimize!`.
**Why it's wrong:** A non-optimal/near-feasible SOCP yields garbage prices silently.
**Instead:** Gate on `termination_status == OPTIMAL` (or ADMM convergence) *and* exactness before any pricing extraction.

### Anti-Pattern 6: Non-reproducible profile generation
**What people do:** Global RNG, unseeded Markov chains, unpinned `Manifest.toml`.
**Why it's wrong:** Breaks the reproducibility requirement; experiments can't be re-run.
**Instead:** Explicit seeded RNG passed through `Scenario`; commit `Manifest.toml`; use DrWatson to bind config↔output.

### Anti-Pattern 7: Over-engineering the abstraction before rung 2
**What people do:** Build the full formulation/device/strategy/planning type lattice before a single model solves.
**Why it's wrong:** YAGNI risk; the interfaces will be wrong until validated against real math.
**Instead:** Grow interfaces from the toy rung upward (build order below). The seams named here are justified *only* because they map to declared research axes — do not add speculative ones.

---

## Suggested Build Order (the abstraction ladder → phase implications)

Each rung is independently runnable and validated before the next. Dependencies flow strictly upward; later rungs add components without editing earlier ones.

| Rung | Deliverable | Adds | Validates | Roadmap phase implication |
|------|-------------|------|-----------|---------------------------|
| **0. Plumbing** | Data model + `ModelContext` + solver abstraction + toy DC single-period, centralized | `data/`, `model/context.jl`, `solvers.jl`, `DCPowerFlow`, one trivial device | Model builds, solves, extracts an objective. End-to-end skeleton. | First phase = *scaffolding*; low research risk. |
| **1. LinDistFlow + one device** | Linear branch flow, single node, one flexible load, centralized | `LinDistFlow`, `Interruptible`, residual registry closing | Nodal balance dual appears; interface shape confirmed. | Establishes the residual-seam contract that everything reuses. |
| **2. SOCP + all devices + exactness** | Full `GLB-CVX` (3.38) on IEEE 13-node, centralized | `SOCBranchFlow` (+ LinDistFlow exactness copy), Thermostatic/Deferrable/PVBattery, aggregator, social-welfare objective, fixtures | **Exactness** (`l·v≈P²+Q²`, `v₉[16]≈1.0493`); centralized DADP reproduces thesis numbers | The correctness milestone — validation-heavy phase; the "if all else fails this must work" core. |
| **3. Pricing** | DADP extraction + DLMP decomposition | `results/pricing.jl`, `exactness.jl` | Price decomposition (energy/loss/congestion/voltage) matches thesis Case A/B | Small phase; depends only on rung 2 duals. |
| **4. ADMM** | Decomposed solve, selectable | `solve/admm.jl`, per-node AGR + per-hour DSO contexts, dual loop, diagnostics | `ADMM optimum ≈ centralized`; `λ_j → DADP`; ~28 iters; IEEE 123-node voltage case | The scale/decomposition phase; reuses ALL rung-2 builders — pure orchestration. |
| **5. Extensions (parallel, independent)** | Any of the four research axes | stochastic (`Scenario` axis + scenario-decomp strategy) · MPC/RTP (rolling `Horizon` + re-solve) · meshed + 4Q-BESS (`MeshedSOCBranchFlow` + reactive device) · **planning** (`planning/` Benders + diagonalization via `operational_oracle`) | each against its own reference | Later phases; each is *additive* thanks to the seams. Planning is the largest and depends on the oracle shape being present since rung 2. |

**Ordering rationale:** rungs 0→2 build the vertical slice and lock the interfaces via real math before generalizing; rung 3 is cheap and derisks pricing; rung 4 is orchestration over already-validated builders; rung 5 items are mutually independent and can be scheduled by research priority. **Critical dependency:** the `operational_oracle` signature (return the frontier coupling dual) must exist by rung 2 so the planning layer is additive later, not a refactor.

---

## Integration Points

### External libraries

| Library | Role | Notes |
|---------|------|-------|
| **JuMP.jl** | Modeling layer | The whole `ModelContext` wraps a JuMP `Model`; follow JuMP style guide (concrete-typed args at leaves, defensive checks at call-chain top). |
| **HiGHS.jl** | LP/MILP | Primary open-source for planning masters, DC/LinDistFlow. |
| **Ipopt.jl** | NLP | For any nonlinear rung / QP fallback. |
| **Clarabel.jl / SCS.jl** | SOCP/conic | Primary for the `SOCBranchFlow` operational solve. Clarabel is the modern, fast, pure-Julia conic default; SCS as cross-check. |
| **Gurobi.jl** | Commercial fallback | Behind `select_optimizer` only; weak/optional dep — no model may hard-import it. |
| **DrWatson.jl** | Experiment reproducibility | `@dict`/`savename`/`produce_or_load` bind config↔output; the idiomatic Julia scientific-project harness. |
| **Documenter.jl** | Docs | Per-model math + assumptions (hard requirement). |
| **PowerModels.jl / PowerModelsDistribution.jl** | *Reference + optional parsers* | **Do not build on top of it** — its OPF objective/variable model is generator-centric and doesn't fit prosumer-utility social welfare + ADMM price recovery. Optionally borrow its Matpower/OpenDSS *feeder parsers* to load fixtures; reimplement the formulation layer. |
| **BilevelJuMP.jl** | Optional, small planning cases | Compact MPEC/KKT single-level reductions for tiny Stackelberg instances as a cross-check on Benders. Not the main path. |

### Internal boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| data ↔ formulations/devices | Read-only struct access | Data has zero JuMP dependency; enables pure unit tests. |
| powerflow ↔ devices | **None (via `ModelContext` only)** | The keystone decoupling. Enforce by convention + code review; neither module imports the other. |
| assembly ↔ powerflow/devices | Dispatched builder calls | Assembly is the sole knower of both residual side and injection side. |
| solve ↔ assembly | Consumes builder functions, not concrete models | Guarantees centralized/ADMM share model code. |
| results ↔ assembly | Reads post-solve `ModelContext` (duals, values) | Gated on status + exactness. |
| planning ↔ operational | `operational_oracle(z) → (cost, π)` **only** | Coupling variable = interconnection flow `z` ≈ feeder-head `p₀`; linking price = DADP ≈ `π`. The single, narrow seam between the two layers. |

---

## Sources

- [PowerModels.jl — Network Formulations](https://lanl-ansi.github.io/PowerModels.jl/stable/formulations/) — abstract/concrete formulation type hierarchy; how to add a formulation (intermediate abstract type + `@pm_fields` concrete struct). HIGH.
- [PowerModels.jl — Constraints & constraint templates](https://lanl-ansi.github.io/PowerModels.jl/dev/constraints/) — the template layer separating data extraction from constraint building; `constraint_template.jl` vs `constraint.jl`. HIGH.
- [PowerModels.jl — Power Models and Types (DeepWiki)](https://deepwiki.com/lanl-ansi/PowerModels.jl/2.2-power-models-and-types) — `AbstractPowerModel` fields (JuMP model + ref + var/con dicts), dispatch mechanism, `instantiate_model`/`solve_model` flow. MEDIUM-HIGH (third-party summary of source).
- [JuMP.jl — Style Guide (abstract types & multiple dispatch trade-offs)](https://jump.dev/JuMP.jl/stable/developers/style/) — concrete-typed leaves vs defensive abstract methods; where to validate assumptions. HIGH.
- `.planning/research/THEORY-thesis.md` — operational formulation (eq. 3.2–3.47), ADMM split, DADP-as-dual, LinDistFlow exactness, no-binaries battery proof, IEEE 13/123 validation numbers. HIGH (primary source extraction).
- `.planning/research/THEORY-papers.md` — planning layer (Benders eq. 2/4, diagonalization, binary expansion + Lagrangian cuts), two-layer composition (operational solve as Benders subproblem; coupling flow `z` ↔ DADP `π`). MEDIUM (author-flagged inconsistencies on leader/follower labeling).
- `.planning/PROJECT.md` — constraints (Julia+JuMP, open-source solvers, reproducibility, independent swappability), abstraction-ladder decision, extension axes. HIGH.

---
*Architecture research for: Julia/JuMP multi-model, multi-solver TSO–DSO transactive-energy + Stackelberg–Nash research framework*
*Researched: 2026-07-18*
