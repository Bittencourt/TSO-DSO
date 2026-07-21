# Phase 1: Plumbing & Solver Abstraction - Research

**Researched:** 2026-07-18
**Domain:** Julia package scaffolding, JuMP solver abstraction, immutable data modeling, solve-status discipline, per-unit systems
**Confidence:** HIGH (all flagged JuMP/Clarabel/PkgTemplates/TestItems APIs verified this session against official docs via Context7)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
This is an infrastructure phase — CONTEXT.md marks **all implementation choices as Claude's Discretion**, anchored to the authoritative `CLAUDE.md` Technology Stack. The following are treated as binding (from CONTEXT.md `## Implementation Decisions` and CLAUDE.md):

- **Modeling:** JuMP (not Convex.jl); models never name a concrete solver.
- **Solver factory:** one thin `select_optimizer(::ProblemClass)` / `make_solver` factory — HiGHS (LP/MILP), Clarabel (conic/QP), Ipopt (NLP) as open-source defaults; Gurobi/Mosek opt-in only behind the factory, never a hard dependency.
- **Data model:** immutable, JuMP-free, concretely-typed parametrized structs (`struct Feeder{T<:Real} … end`); `SparseArrays` for incidence/topology.
- **Status discipline:** every solve asserts `termination_status == OPTIMAL`; fail loudly on non-optimal status or hidden constraint slack.
- **Per-unit:** one documented per-unit system, converted once at ingestion, with magnitude-sanity assertions on electrical and monetary quantities.
- **Radial validation:** feeder validated as a tree (N nodes → N−1 branches, connected, one root); non-tree feeder raises a clear error.
- **Reproducibility:** committed `Project.toml` + `Manifest.toml`, `[compat]` floors at Julia 1.10 LTS, tested on 1.10 and 1.11.

### Claude's Discretion
All src/ layout, struct field design, `ProblemClass` type strategy, residual-registry shape, and validation-helper internals are at Claude's discretion, anchored to CLAUDE.md.

### Deferred Ideas (OUT OF SCOPE)
None — infrastructure phase. (Do not implement power-flow physics beyond the toy DC node, any prosumer devices, ADMM/Benders, pricing, or IEEE fixtures. Those are Phases 2–9.)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INFRA-01 | Pinned environment (`Project.toml` + committed `Manifest.toml`, `[compat]` floors) resolving cleanly on Julia 1.10 LTS + 1.11 | PkgTemplates scaffold + `[compat]` floor pattern (§Standard Stack, §Reproducibility); GitHubActions matrix `extra_versions=["1.10","1.11"]` |
| INFRA-02 | Any model requests its solver via a single `select_optimizer(::ProblemClass)` factory; no model file names a concrete solver | Singleton `ProblemClass` + `select_optimizer` dispatch pattern (§Pattern 1); weakdeps/extension gating for Gurobi/Mosek (§Pattern 2) |
| INFRA-03 | Every solve asserts `termination_status == OPTIMAL` (tight duality gap for conic) and fails loudly on non-optimal status or hidden constraint slack | `assert_is_solved_and_feasible` / `is_solved_and_feasible(model; dual, allow_local)` (§Pattern 3); Clarabel `tol_gap_abs/rel` for conic gap |
| INFRA-05 | One consistent per-unit system; all external data converted once at ingestion, with magnitude-sanity assertions | `PerUnitBase` struct + convert-at-ingestion + `@assert` magnitude bands (§Pattern 5) |
| DATA-01 | Radial feeder (buses, branches r/x, limits, MEM frontier node) as immutable JuMP-free structs | `Feeder{T}` / `Bus{T}` / `Branch{T}` immutable parametrized structs (§Pattern 4) |
| DATA-02 | Framework validates radial (tree) and reports a clear error otherwise | Tree check via SparseArrays incidence + BFS connectivity: `B == N-1 ∧ connected ∧ designated root` (§Pattern 4, §Don't Hand-Roll) |
| PF-01 | Swappable `AbstractPowerFlow` interface contributes branch/voltage terms into a shared nodal-balance residual with no `if formulation ==` branching | `AbstractPowerFlow` abstract type + residual-registry seam in `ModelContext` (§Pattern 6) — stub only in Phase 1 |
</phase_requirements>

## Summary

Phase 1 is a **walking skeleton** for a JuMP research bench: scaffold the package, define a JuMP-free immutable feeder data model, build a solver factory keyed on a `ProblemClass` type, wrap solve-status discipline, define a per-unit system, and prove the whole spine end-to-end on a toy single-node single-period DC solve. Every architectural choice here is reused by all eight later phases, so correctness and clean seams dominate over features.

The CLAUDE.md Technology Stack is authoritative and already version-pinned (verified against the Julia General registry on 2026-07-18). This research does **not** re-litigate library choices. Instead it resolves the open **implementation-API** questions CLAUDE.md flagged for re-check, all now verified against official docs via Context7:

- **JuMP solver factory:** `Model(optimizer_with_attributes(HiGHS.Optimizer, "presolve"=>"on"))`, `set_optimizer`, `set_attribute` — all current and stable in JuMP 1.30.x.
- **Status assertion:** the modern idiom is `assert_is_solved_and_feasible(model; allow_local=false, dual=true)` (or `is_solved_and_feasible` returning a Bool) — this **supersedes** hand-writing `termination_status(model) == OPTIMAL` and is the prescribed pattern for INFRA-03.
- **JuMP `Parameter`:** `@variable(model, p in Parameter(1.0))` + `set_parameter_value` / `parameter_value` — confirmed (needed for ADMM re-solves in Phase 6, wire the pattern now).
- **Clarabel:** handles quadratic objectives natively (P-matrix), duals via `solution.z`/JuMP `dual()`, tolerances `tol_gap_abs`/`tol_gap_rel`/`tol_feas` (default 1e-8) — set via `set_optimizer_attribute(model, "tol_gap_abs", …)`.
- **Clarabel + `direct_model`: NOT SUPPORTED.** Clarabel is a `copy_to`-only solver (`supports_incremental_interface == false`); `direct_model(Clarabel.Optimizer())` errors. This **contradicts the CLAUDE.md perf note** suggesting `direct_model` for hot Clarabel subproblems. Use a regular `Model` (auto-wrapped in `CachingOptimizer`). Reserve `direct_model` for HiGHS-backed hot loops only.

**Primary recommendation:** Scaffold with PkgTemplates (Tests+Aqua+JET, GitHubActions matrix 1.10/1.11/1.12, Documenter, Codecov); build a subfoldered `src/` with explicit seams (`units/`, `data/`, `solver/`, `core/`, `powerflow/`, `models/`); implement `ProblemClass` as **singleton types** (not an enum) so `select_optimizer` dispatches; make the status wrapper delegate to `is_solved_and_feasible`; make Gurobi/Mosek **package extensions (weakdeps)** so they stay out of the default install and Manifest.

## Architectural Responsibility Map

Tiers here are the framework's software layers (this is a library, not a web app). Each Phase-1 capability maps to the layer that owns it.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Feeder / bus / branch representation | Data model (`data/`) | — | JuMP-free structs; no solver or model knowledge (DATA-01) |
| Radial (tree) validation | Data model (`data/topology.jl`) | — | Topology is a property of the data, checked at construction (DATA-02) |
| Per-unit conversion + magnitude sanity | Units (`units/`) | Data model | Convert once at ingestion, before structs are frozen (INFRA-05) |
| Solver selection by problem class | Solver abstraction (`solver/`) | — | Only place that names concrete solvers (INFRA-02) |
| Model build (toy DC) | Model build (`models/`) | Core | Consumes data + factory; never names a solver |
| Nodal-balance residual seam | Core (`core/ModelContext.jl`) | Power-flow | Shared registry that formulations write into (PF-01) |
| Solve-status / slack discipline | Core (`core/status.jl`) | — | Wraps `optimize!`; single choke point for INFRA-03 |
| Power-flow interface contract | Power-flow (`powerflow/`) | Core | `AbstractPowerFlow` stub; real formulations land Phase 2+ (PF-01) |

## Standard Stack

All libraries and versions are **authoritative from CLAUDE.md** (verified against the Julia General registry `Versions.toml`, fetched 2026-07-18). Phase 1 uses only the subset below; the rest of the stack (device libs, plotting, decomposition tooling) arrives in later phases.

### Core (Phase 1 runtime deps)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Julia | 1.10 LTS floor, dev on 1.11/1.12 | Language/runtime | LTS floor for reproducibility; test matrix spans LTS→current [VERIFIED: CLAUDE.md / Julia General registry] |
| JuMP | 1.30.1 | Algebraic modeling | Solver-agnostic, per-constraint `dual()`, native `Parameter`, `SecondOrderCone` [VERIFIED: Context7 /jump-dev/jump.jl] |
| MathOptInterface (MOI) | 1.51.2 | Solver abstraction under JuMP | The "swap any solver" mechanism; `TerminationStatus`/`DualStatus` read for INFRA-03. Let Pkg resolve — do not pin independently [VERIFIED: CLAUDE.md] |
| HiGHS | 1.24.1 | LP/MILP default; the toy DC solve | Fast open-source simplex/MIP; supports `direct_model` [VERIFIED: CLAUDE.md; direct_model VERIFIED: JuMP docs] |
| SparseArrays | stdlib | Incidence/topology matrices | Feeder incidence is sparse; tree check builds on it [VERIFIED: Julia stdlib] |

### Supporting (Phase 1 dev/test/docs deps)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Clarabel | 0.11.1 | Conic/QP solver (wire into factory now) | No SOCP in Phase 1, but register it in the factory so `ProblemClass` dispatch is real, not a stub [VERIFIED: Context7 /oxfordcontrol/clarabeldocs] |
| Ipopt | 1.15.0 | NLP fallback (wire into factory now) | Same — register the NLP branch so the factory is complete [VERIFIED: CLAUDE.md] |
| Test | 1.1.5 (stdlib) | Test primitives | `@test`, `@testset` under TestItems [VERIFIED: CLAUDE.md] |
| TestItems | 1.0.0 | `@testitem` macro | One test item per model-variant rung (the "ladder") [VERIFIED: WebSearch julia-vscode docs] |
| TestItemRunner | 1.1.5 | Run test items via `Pkg.test` | `@run_package_tests` in `test/runtests.jl` [VERIFIED: WebSearch julia-vscode/TestItemRunner.jl] |
| Aqua | current | Package-quality auto-tests | Undefined exports, stale deps, ambiguities, compat-bound gaps [VERIFIED: CLAUDE.md] |
| JET | current | Static analysis / type-stability | Run on model-build kernels in CI [VERIFIED: CLAUDE.md] |
| Documenter | 1.17.0 | Docs site (KaTeX math) | Model equations beside code; Phase 1 sets up the skeleton [VERIFIED: CLAUDE.md] |
| Literate | 2.21.0 | Literate experiment scripts | One toy-DC Literate page proves the docs pipeline [VERIFIED: CLAUDE.md] |
| JuliaFormatter | 2.10.1 | Formatting | Commit `.JuliaFormatter.toml` to freeze v2 style; enforce in CI [VERIFIED: CLAUDE.md] |
| PkgTemplates | current | One-time scaffold | Generates Project.toml/src/test/docs/CI [VERIFIED: Context7 /juliaci/pkgtemplates.jl] |

### Opt-in behind the factory (NOT in default deps / Manifest)
| Library | Version | Purpose | Gating |
|---------|---------|---------|--------|
| Gurobi | 1.9.2 | Commercial LP/QP/MILP/SOCP fallback | `[weakdeps]` + package extension; loads only if user has a license [VERIFIED: CLAUDE.md] |
| MosekTools | current | Commercial SOCP gold-standard | Same weakdep/extension gating [VERIFIED: CLAUDE.md] |

**Installation (in the activated package env):**
```julia
# Core + open-source solvers
Pkg.add(["JuMP", "HiGHS", "Clarabel", "Ipopt"])
# Dev/test/docs
Pkg.add(["TestItems", "TestItemRunner", "Aqua", "JET", "Documenter", "Literate", "JuliaFormatter"])
# SparseArrays / Test are stdlib — no add needed
# Gurobi / MosekTools: DO NOT add to package deps — declared as [weakdeps] only
```

**Version verification:** Versions above are from CLAUDE.md's registry snapshot (2026-07-18, same day as this research) — no drift possible. Re-run `Pkg.status` after scaffold to confirm the resolver landed on these. No independent MOI pin (JuMP owns it).

## Package Legitimacy Audit

All packages are Julia General-registry packages verified in CLAUDE.md against the registry's `Versions.toml` (the authoritative source) on 2026-07-18. `slopcheck` targets npm/PyPI/crates and does not cover the Julia registry, so it does not apply here; registry-existence + official-org provenance is the Julia-ecosystem equivalent gate.

| Package | Registry | Source Org | Provenance | Disposition |
|---------|----------|-----------|-----------|-------------|
| JuMP | Julia General | jump-dev | Official, verified this session via Context7 | Approved |
| HiGHS | Julia General | jump-dev / ERGO-Code | Verified CLAUDE.md | Approved |
| Clarabel | Julia General | oxfordcontrol | Official, verified this session via Context7 | Approved |
| Ipopt | Julia General | jump-dev / COIN-OR | Verified CLAUDE.md | Approved |
| TestItems / TestItemRunner | Julia General | julia-vscode | Verified this session (official VS Code Julia org) | Approved |
| PkgTemplates | Julia General | JuliaCI | Verified this session via Context7 | Approved |
| Aqua / JET / Documenter / Literate / JuliaFormatter | Julia General | JuliaTesting / aviatesk / JuliaDocs / fredrikekre / domluna | Verified CLAUDE.md | Approved |
| Gurobi / MosekTools | Julia General | jump-dev (commercial vendor bindings) | Verified CLAUDE.md; weakdep only | Approved (gated) |

**Packages removed due to slopcheck [SLOP] verdict:** none (slopcheck N/A for Julia registry).
**Packages flagged as suspicious [SUS]:** none.

## Architecture Patterns

### System Architecture Diagram

```
                    ┌─────────────────────────────────────────────┐
 raw external data  │  units/PerUnit.jl                            │
 (SI: kV, MVA, $)   │  to_pu(...)  ── convert ONCE at ingestion ── │──► magnitude-sanity @assert
        │           └─────────────────────────────────────────────┘        (INFRA-05)
        ▼                          │ per-unit numbers
 ┌──────────────────────────────┐  ▼
 │ data/Feeder.jl               │  build immutable Feeder{T}(buses, branches, root)
 │  Bus{T}, Branch{T}, Feeder{T}│──────────────┐
 └──────────────────────────────┘              │
        │ construct-time validation             │ frozen, JuMP-free data
        ▼                                        ▼
 ┌──────────────────────────────┐   ┌───────────────────────────────────────────┐
 │ data/topology.jl             │   │ models/toy_dc.jl                          │
 │  incidence (SparseArrays)    │   │  build_toy_dc(feeder, ctx)                 │
 │  tree check: B==N-1 ∧        │   │   - @variable / @constraint                 │
 │  connected ∧ 1 root (DATA-02)│   │   - writes nodal balance into ctx.residuals│
 └──────────────────────────────┘   │   - NEVER names a solver                    │
        │ error if non-radial         └───────────────────────────────────────────┘
        ▼                                        │ JuMP model + residual registry
   clear exception                               ▼
                                    ┌───────────────────────────────────────────┐
                       ProblemClass │ solver/factory.jl                          │
                          (LP())───►│  select_optimizer(::LP) → HiGHS factory    │──► Model(optimizer)
                                    │  (::SOCP) → Clarabel ; (::NLP) → Ipopt     │
                                    │  weakdep ext: (::MILP; gurobi) → Gurobi    │
                                    └───────────────────────────────────────────┘
                                                 │ optimize!(model)
                                                 ▼
                                    ┌───────────────────────────────────────────┐
                                    │ core/status.jl                            │
                                    │  assert_solved(model; dual, allow_local)   │──► error w/ diagnostics
                                    │   → is_solved_and_feasible + slack check    │    on non-OPTIMAL (INFRA-03)
                                    └───────────────────────────────────────────┘
                                                 │
                                                 ▼  (objective, duals) returned to caller
```

### Recommended Project Structure

Package name is not fixed in CLAUDE.md — recommend `TSODSO` (short, matches repo) or `TransactiveGridOpt`; confirm at plan time. Below assumes module `TSODSO`.

```
TSODSO/
├── Project.toml            # deps + [compat] floors + [weakdeps] + [extensions]
├── Manifest.toml           # COMMITTED (INFRA-01 reproducibility)
├── .JuliaFormatter.toml    # freeze v2 style
├── .github/workflows/
│   ├── CI.yml              # matrix: 1.10 (LTS), 1.11, 1.12; + Aqua/JET/format check
│   └── Documenter.yml      # docs deploy (or folded into CI)
├── src/
│   ├── TSODSO.jl           # top module: includes + exports
│   ├── units/
│   │   └── PerUnit.jl      # PerUnitBase{T}, to_pu/from_pu, magnitude assertions
│   ├── data/
│   │   ├── Feeder.jl       # Bus{T}, Branch{T}, Feeder{T} immutable structs
│   │   └── topology.jl     # incidence matrix + is_radial / assert_radial
│   ├── solver/
│   │   ├── ProblemClass.jl # abstract ProblemClass + LP/MILP/QP/SOCP/NLP singletons
│   │   └── factory.jl      # select_optimizer(::ProblemClass); solver registry
│   ├── core/
│   │   ├── ModelContext.jl # ModelContext + constraint/residual registry
│   │   └── status.jl       # assert_solved wrapper (INFRA-03)
│   ├── powerflow/
│   │   └── AbstractPowerFlow.jl  # PF-01 interface stub (contract only)
│   └── models/
│       └── toy_dc.jl       # walking-skeleton build+solve (rung 0)
├── ext/                    # package extensions (loaded only when weakdep present)
│   ├── TSODSOGurobiExt.jl
│   └── TSODSOMosekExt.jl
├── test/
│   ├── Project.toml        # test-only deps (TestItemRunner, Aqua, JET)
│   ├── runtests.jl         # `using TestItemRunner; @run_package_tests`
│   ├── test_perunit.jl     # @testitem blocks
│   ├── test_feeder.jl
│   ├── test_topology.jl
│   ├── test_factory.jl
│   ├── test_status.jl
│   └── test_toy_dc.jl
└── docs/
    ├── make.jl
    ├── literate/toy_dc.jl  # Literate source → rendered page
    └── src/
```

### Pattern 1: `ProblemClass` singleton types + `select_optimizer` dispatch (INFRA-02)

**What:** A sealed set of problem classes as **singleton types** under one abstract type, so `select_optimizer` uses multiple dispatch (no `if class == …`). This is more idiomatic Julia than an `@enum` (which would force branching) and lets weakdep extensions add methods for commercial solvers without editing the core file.

**When to use:** Every model requests its optimizer this way; models never name a solver.

```julia
# Source: pattern derived from JuMP docs (optimizer_with_attributes / set_optimizer),
#         verified via Context7 /jump-dev/jump.jl
# src/solver/ProblemClass.jl
abstract type ProblemClass end
struct LP   <: ProblemClass end   # linear (toy DC lives here)
struct MILP <: ProblemClass end   # mixed-integer linear
struct QP   <: ProblemClass end   # convex quadratic
struct SOCP <: ProblemClass end   # second-order cone (Phase 4+)
struct NLP  <: ProblemClass end   # general smooth nonlinear

# src/solver/factory.jl
using JuMP, HiGHS, Clarabel, Ipopt

"select_optimizer(pc) -> a JuMP-ready optimizer factory (never a live solver object in a model file)."
select_optimizer(::LP)   = optimizer_with_attributes(HiGHS.Optimizer, "presolve" => "on")
select_optimizer(::MILP) = optimizer_with_attributes(HiGHS.Optimizer)
select_optimizer(::QP)   = optimizer_with_attributes(Clarabel.Optimizer, "verbose" => false)
select_optimizer(::SOCP) = optimizer_with_attributes(Clarabel.Optimizer,
                              "verbose" => false, "tol_gap_abs" => 1e-8, "tol_gap_rel" => 1e-8)
select_optimizer(::NLP)  = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0)

# a model file then does ONLY:
#   model = Model(select_optimizer(LP()))
```

**Verified API:** `optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => true)` and `Model(solver)` [VERIFIED: Context7 /jump-dev/jump.jl — docs/src/manual/models.md]. Attribute names are solver-specific strings passed through MOI; Clarabel accepts `"verbose"`, `"max_iter"`, `"tol_gap_abs"`, `"tol_gap_rel"`, `"tol_feas"` [VERIFIED: Context7 /oxfordcontrol/clarabeldocs + WebSearch].

### Pattern 2: Optional commercial solvers as package extensions (INFRA-02, "removable from Manifest")

**What:** Keep Gurobi/Mosek out of the default dependency graph using Julia's native **weakdeps + extensions** (Julia ≥ 1.9; we floor at 1.10 so this is safe). The extension adds `select_optimizer` methods (or registers into a solver `Dict`) only when the user has the commercial package loaded. This is the modern replacement for `Requires.jl`.

**When to use:** For any solver that must not be a hard dependency and must remain removable.

```toml
# Project.toml
[deps]
JuMP = "..."
HiGHS = "..."
Clarabel = "..."
Ipopt = "..."

[weakdeps]
Gurobi = "2e9cd046-0924-5485-92f1-d5272153d98b"
MosekTools = "1ec41992-ff65-5c91-ac43-2df89e9693a4"

[extensions]
TSODSOGurobiExt = "Gurobi"
TSODSOMosekExt  = "MosekTools"
```

```julia
# ext/TSODSOGurobiExt.jl — loads ONLY when both TSODSO and Gurobi are present
module TSODSOGurobiExt
using TSODSO, Gurobi, JuMP
# add a commercial method dispatched on a solver-choice marker so the default stays open-source
TSODSO.commercial_optimizer(::TSODSO.GurobiChoice, pc) =
    optimizer_with_attributes(Gurobi.Optimizer)  # ... map pc → attributes
end
```

**Tradeoff:** weakdeps DO appear in the Manifest as *weak* entries but are **not installed/loaded** unless the user adds Gurobi to their environment — satisfying "never a hard dependency." If truly zero-Manifest-footprint is required, the fallback is a runtime solver-registry `Dict{Symbol,Any}` that the user populates from their own script (`register_solver!(:gurobi, Gurobi.Optimizer)`); recommend the extension approach as primary (cleaner, dispatch-based).

### Pattern 3: Solve-status discipline (INFRA-03)

**What:** A single choke-point wrapper around `optimize!` that uses JuMP's built-in `is_solved_and_feasible` / `assert_is_solved_and_feasible` — the **modern idiom that supersedes** hand-checking `termination_status(model) == OPTIMAL`. It checks termination **and** primal (and, with `dual=true`, dual) statuses, and `allow_local=false` demands a *global* optimum (correct for the convex problems in this project).

**When to use:** Wrap every solve in the whole framework.

```julia
# Source: VERIFIED Context7 /jump-dev/jump.jl — docs/src/manual/solutions.md
# src/core/status.jl
using JuMP

function assert_solved!(model::Model; dual::Bool = true, allow_local::Bool = false)
    optimize!(model)
    if !is_solved_and_feasible(model; dual = dual, allow_local = allow_local)
        error("""
        Solve failed — refusing to trust results:
          termination_status : $(termination_status(model))
          primal_status      : $(primal_status(model))
          dual_status        : $(dual_status(model))
          raw_status         : $(raw_status(model))
        """)
    end
    return model
end
# Equivalent one-liner JuMP provides: assert_is_solved_and_feasible(model; allow_local=false, dual=true)
```

- `is_solved_and_feasible(model; dual=true, allow_local=false)` returns `Bool`; checks `termination_status ∈ {OPTIMAL}` (not LOCALLY_SOLVED when `allow_local=false`) and `primal_status`/`dual_status == FEASIBLE_POINT` [VERIFIED: Context7].
- **Conic "tight duality gap" (INFRA-03):** with Clarabel, tighten `tol_gap_abs`/`tol_gap_rel` (default 1e-8) via the factory; `OPTIMAL` from Clarabel already reflects the gap tolerance. Later phases (PF-04) add the SOCP-exactness invariant on top.
- **Hidden constraint slack:** for the toy DC, additionally recompute the objective from `value.(vars)` and assert it matches `objective_value(model)` within tolerance, and (optionally) recompute constraint LHS via `value.(model[:balance])` and assert `≈ rhs`. This catches a solver reporting OPTIMAL while silently violating a constraint within loose feasibility. Keep this as a reusable `assert_no_slack(model, cref; atol)` helper.

### Pattern 4: Immutable JuMP-free feeder + radial validation (DATA-01, DATA-02)

**What:** Concretely-typed, parametrized immutable structs holding per-unit numbers only. Validation runs at construction; a non-tree feeder throws.

```julia
# src/data/Feeder.jl
struct Bus{T<:Real}
    id::Int
    vmin::T; vmax::T        # per-unit voltage bounds
    is_root::Bool           # MEM / substation frontier node
end

struct Branch{T<:Real}
    from::Int; to::Int
    r::T; x::T              # per-unit resistance/reactance
    smax::T                 # per-unit apparent-power limit
end

struct Feeder{T<:Real}
    buses::Vector{Bus{T}}
    branches::Vector{Branch{T}}
    root::Int               # index of the single frontier bus
end

function Feeder(buses::Vector{Bus{T}}, branches::Vector{Branch{T}}, root::Int) where {T}
    assert_radial(buses, branches, root)     # DATA-02 — throws on failure
    return Feeder{T}(buses, branches, root)  # only reached if valid
end
```

```julia
# src/data/topology.jl  — tree check (DATA-02)
using SparseArrays
function assert_radial(buses, branches, root)
    N, B = length(buses), length(branches)
    B == N - 1 || throw(ArgumentError(
        "Non-radial feeder: $N buses require exactly $(N-1) branches, got $B."))
    # node-branch incidence (sparse); +1 at `from`, -1 at `to`
    I = Int[]; J = Int[]; V = Int[]
    for (b, br) in enumerate(branches)
        push!(I, br.from); push!(J, b); push!(V, +1)
        push!(I, br.to);   push!(J, b); push!(V, -1)
    end
    A = sparse(I, J, V, N, B)
    # BFS from root over adjacency; connected + (B==N-1) ⟺ tree
    adj = [Int[] for _ in 1:N]
    for br in branches; push!(adj[br.from], br.to); push!(adj[br.to], br.from); end
    seen = falses(N); stack = [root]; seen[root] = true; count = 1
    while !isempty(stack)
        u = pop!(stack)
        for v in adj[u]; seen[v] || (seen[v] = true; count += 1; push!(stack, v)); end
    end
    count == N || throw(ArgumentError(
        "Non-radial feeder: graph is disconnected from root $root ($count/$N reachable)."))
    sum(b.is_root for b in buses) == 1 || throw(ArgumentError(
        "Feeder must have exactly one frontier (root) bus."))
    return A   # reusable incidence for the model layer
end
```

**Key theorem used:** for a simple undirected graph, `edges == nodes − 1` **and** connected ⟺ it is a tree (acyclic, single component). BFS-connectivity + the edge-count check is sufficient; no explicit cycle detection needed.

### Pattern 5: Per-unit system, converted once (INFRA-05)

```julia
# src/units/PerUnit.jl
struct PerUnitBase{T<:Real}
    S_base::T   # MVA (system apparent-power base)
    V_base::T   # kV  (base voltage at the relevant level)
end
Z_base(b::PerUnitBase) = b.V_base^2 / b.S_base            # Ω
I_base(b::PerUnitBase) = b.S_base / (sqrt(3) * b.V_base)  # kA (3-phase)

to_pu_power(x_MW, b)  = x_MW / b.S_base
to_pu_impedance(z_Ω, b) = z_Ω / Z_base(b)
# monetary: keep prices in $/MWh but assert magnitude bands

function assert_magnitudes(f::Feeder)
    for bus in f.buses
        @assert 0.8 ≤ bus.vmin ≤ bus.vmax ≤ 1.2 "voltage bounds out of per-unit band at bus $(bus.id)"
    end
    for br in f.branches
        @assert 0 ≤ br.r < 5 && 0 ≤ br.x < 5 "per-unit impedance implausibly large on branch $(br.from)->$(br.to)"
        @assert 0 < br.smax < 100 "per-unit power limit out of band on branch $(br.from)->$(br.to)"
    end
end
```

Convert **at ingestion only** (before struct construction), document the chosen `S_base`/`V_base` in a Documenter page, and never mix SI and pu downstream. Magnitude bands are deliberately loud tripwires for unit/scale mistakes, not physics.

### Pattern 6: `ModelContext` + residual registry seam (PF-01)

**What:** A mutable context that owns the JuMP model plus **named registries** for (a) constraint handles (so any layer can later call `dual(ctx.constraints[:balance][j,t])` — the future DADP) and (b) residual contributions (so `AbstractPowerFlow` formulations write branch/voltage terms into a shared nodal-balance expression with no `if formulation ==`). Phase 1 uses it trivially (one balance constraint); the shape must support Phases 2–7.

```julia
# src/core/ModelContext.jl
using JuMP
mutable struct ModelContext
    model::Model
    constraints::Dict{Symbol,Any}   # name → ConstraintRef (or array) for dual() access
    residuals::Dict{Symbol,Any}     # name → AffExpr accumulator (nodal balance seam)
    meta::Dict{Symbol,Any}          # per-unit base, feeder handle, config
end
ModelContext(model::Model) = ModelContext(model, Dict(), Dict(), Dict())

register_constraint!(ctx, name::Symbol, cref) = (ctx.constraints[name] = cref)
"Formulations ADD their contribution into the shared residual (no branching)."
add_to_residual!(ctx, name::Symbol, expr) =
    (ctx.residuals[name] = haskey(ctx.residuals, name) ? ctx.residuals[name] + expr : expr)

# src/powerflow/AbstractPowerFlow.jl  (PF-01 contract — stub in Phase 1)
abstract type AbstractPowerFlow end
"contribute!(pf, ctx, feeder): write branch/voltage terms into ctx.residuals[:nodal_balance]."
function contribute! end
```

**Design note:** `Dict{Symbol,Any}` is the pragmatic choice for a research registry (heterogeneous handles). Guard the hot loop later with function barriers when reading from it (per CLAUDE.md type-stability guidance); Phase 1 is not perf-critical.

### Pattern 7: TestItems "rung ladder" scaffolding

```julia
# test/runtests.jl
using TestItemRunner
@run_package_tests            # optionally: @run_package_tests verbose=true

# test/test_toy_dc.jl — one @testitem per rung / variant; Test + TSODSO auto-loaded
@testitem "rung0: toy DC single-node solves and is OPTIMAL" tags=[:rung0] begin
    feeder = # ... build a trivial 1-node feeder
    ctx, obj = TSODSO.solve_toy_dc(feeder)
    @test is_solved_and_feasible(ctx.model; allow_local=false)
    @test isfinite(obj)
end
```

Use `tags=[:rung0, :rung1, …]` so `@run_package_tests filter=ti->:rung0 in ti.tags` can run one rung; tags also gate slow/CI-only items (`:skipci`) [VERIFIED: WebSearch julia-vscode docs].

### Anti-Patterns to Avoid
- **Naming a concrete solver inside a model file.** Breaks INFRA-02. Only `solver/factory.jl` (and weakdep extensions) may import HiGHS/Clarabel/Ipopt/Gurobi.
- **`@enum ProblemClass` + `if class == LP`.** Fights Julia dispatch and blocks weakdep extension methods. Use singleton types.
- **`direct_model(Clarabel.Optimizer())`.** Errors — Clarabel is copy_to-only. (See Pitfall 1.)
- **Checking only `termination_status == OPTIMAL`.** Misses primal/dual-status pathologies. Use `is_solved_and_feasible`.
- **Rebuilding the JuMP model to change data.** Wire `Parameter` now (Pattern in §Code Examples) so Phase 6 ADMM inherits it.
- **Mutating a `Feeder` after construction.** Structs are immutable by design; validation is a construction invariant.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Solve-status checking | Custom `if termination_status(...) ...` ladders everywhere | `is_solved_and_feasible` / `assert_is_solved_and_feasible` | Built-in, checks primal+dual+termination, `allow_local` handles convex-global correctly [VERIFIED: Context7] |
| Solver-attribute plumbing | Manual `set_optimizer` + `set_attribute` scattered per model | `optimizer_with_attributes(Solver, "k"=>v)` in the factory | Single source of truth; attaches attributes to the factory not the model [VERIFIED: Context7] |
| Efficient re-solves | Rebuild model each data change | JuMP `Parameter` + `set_parameter_value` | Native, warm-start-friendly; ADMM/Benders depend on it [VERIFIED: Context7] |
| Optional commercial-solver loading | `Requires.jl` runtime hooks | `[weakdeps]` + `[extensions]` (Julia ≥1.9) | Native package extensions; precompilable, removable [VERIFIED: JuMP/Julia docs] |
| Sparse incidence | Dense N×B matrices | `SparseArrays.sparse` | Feeders are sparse; scales to 123-node cases (CLAUDE.md) |
| Package scaffold + CI/docs/format | Hand-writing Project.toml/CI YAML | PkgTemplates plugins | Generates CI matrix, Documenter, Codecov, formatter wiring correctly [VERIFIED: Context7] |
| Graph connectivity (tree check) | Pulling in Graphs.jl for a one-shot check | ~15-line BFS on an adjacency list | Zero extra dep; `edges==nodes-1 ∧ connected ⟺ tree` is trivial. Add Graphs.jl only if richer topology ops appear later |

**Key insight:** In the JuMP ecosystem the "hard" infrastructure (status semantics, attribute plumbing, parametric re-solves, optional deps) is already solved by first-party APIs. Phase-1 value is in *wiring these correctly into reusable seams*, not reimplementing them.

## Common Pitfalls

### Pitfall 1: Assuming `direct_model` works with Clarabel
**What goes wrong:** Following the CLAUDE.md perf note "`direct_model` for hot subproblems (Clarabel does [support it])" leads to a `MethodError`/`copy_to`-related failure when you call `direct_model(Clarabel.Optimizer())`.
**Why it happens:** Clarabel does **not** implement the incremental MOI interface (`supports_incremental_interface(::Clarabel.Optimizer) == false`); it is a copy-at-once solver. `direct_model` requires incremental `add_variable`/`add_constraint`.
**How to avoid:** Use a standard `Model(select_optimizer(SOCP()))` (auto-wrapped in `CachingOptimizer`) for anything Clarabel-backed. Reserve `direct_model` for **HiGHS**-backed hot loops. **Correct the CLAUDE.md note during this phase** (leave a doc comment in `factory.jl`). [VERIFIED: WebSearch — jump.dev models docs + Clarabel discourse]
**Warning signs:** Any `direct_model(...Clarabel...)` line; errors mentioning `copy_to` / `supports_incremental_interface`.

### Pitfall 2: `LOCALLY_SOLVED` silently accepted as optimal
**What goes wrong:** Ipopt (and some paths) return `LOCALLY_SOLVED`; a naive `== OPTIMAL` check fails confusingly, while a lenient check accepts a non-global point.
**Why it happens:** `termination_status` distinguishes local vs global; the convex problems here should be global.
**How to avoid:** `is_solved_and_feasible(model; allow_local=false)` for the convex core; only pass `allow_local=true` on a deliberately nonconvex experiment rung.
**Warning signs:** Tests passing on Ipopt but the objective disagreeing with a HiGHS/Clarabel cross-check.

### Pitfall 3: Uncommitted or drifting Manifest.toml (INFRA-01)
**What goes wrong:** "Resolves cleanly on a clean checkout" fails on CI or a collaborator's machine because Manifest wasn't committed or `[compat]` floors are missing.
**Why it happens:** Default `.gitignore` from some templates ignores `Manifest.toml` for libraries.
**How to avoid:** Explicitly commit `Manifest.toml`; set `Git(; manifest=true)` in PkgTemplates; add `[compat]` entries with the pinned versions and `julia = "1.10"`; CI job that runs `Pkg.instantiate()` on a clean checkout on 1.10 **and** 1.11.
**Warning signs:** `Manifest.toml` in `.gitignore`; missing `[compat]` block; CI green only on the dev machine.

### Pitfall 4: JuliaFormatter v1↔v2 style drift
**What goes wrong:** CI format check fails because contributors run different formatter versions (v2 default style differs from v1).
**Why it happens:** No committed config to freeze the style.
**How to avoid:** Commit `.JuliaFormatter.toml`; pin JuliaFormatter 2.10.x in the (dev/test) environment; run `format(".")` check in CI.

### Pitfall 5: Mixing SI and per-unit downstream (INFRA-05)
**What goes wrong:** A branch impedance in Ω sneaks into a model expecting pu; results are numerically plausible but wrong.
**Why it happens:** Conversion done ad hoc rather than once at ingestion.
**How to avoid:** All conversion in `units/`, at ingestion, before struct construction; magnitude-sanity `@assert`s on every constructed feeder; document the base.
**Warning signs:** `to_pu` called inside a model builder; voltage bounds outside [0.8, 1.2].

## Code Examples

### Toy DC single-node build + solve (walking skeleton, INFRA-02/03 + rung 0)
```julia
# Source: composed from VERIFIED JuMP APIs (Context7 /jump-dev/jump.jl)
# src/models/toy_dc.jl
using JuMP
function solve_toy_dc(feeder::Feeder)
    model = Model(select_optimizer(LP()))       # factory — no solver named here
    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder
    @variable(model, p_import >= 0)              # power from the frontier node
    @variable(model, 0 <= p_load <= 1.0)         # trivial servable load (pu)
    balance = @constraint(model, p_import - p_load == 0)   # nodal balance
    register_constraint!(ctx, :balance, balance)
    @objective(model, Max, 3.0 * p_load - 1.0 * p_import)  # toy welfare
    assert_solved!(model; dual = true, allow_local = false)  # INFRA-03
    return ctx, objective_value(model), dual(balance)        # dual ready for Phase 5
end
```

### Parameter pattern (wire now for Phase 6 ADMM)
```julia
# Source: VERIFIED Context7 /jump-dev/jump.jl — docs/src/manual/variables.md
@variable(model, ρ in Parameter(1.0))           # penalty / price parameter
# later, between re-solves (no rebuild):
set_parameter_value(ρ, new_value)
optimize!(model)
```

### PkgTemplates scaffold invocation (one-time)
```julia
# Source: VERIFIED Context7 /juliaci/pkgtemplates.jl
using PkgTemplates
t = Template(;
    user = "pedro-...",                          # confirm GitHub handle at plan time
    julia = v"1.10",                             # [compat] floor
    plugins = [
        License(; name = "MIT"),
        Git(; manifest = true, ssh = true),      # COMMIT the Manifest (INFRA-01)
        GitHubActions(; linux = true, extra_versions = ["1.10", "1.11", "1.12"]),
        Codecov(),
        Documenter{GitHubActions}(),
        Tests(; project = true, aqua = true, jet = true),
    ],
)
t("TSODSO")
```

## Runtime State Inventory

Not applicable — Phase 1 is greenfield scaffolding (no rename/refactor/migration; there is no `src/` yet). No stored data, live-service config, OS-registered state, secrets, or build artifacts exist to migrate. **None — verified by `ls src/` (absent) and clean-repo git status.**

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `termination_status(m) == MOI.OPTIMAL` hand-checks | `is_solved_and_feasible` / `assert_is_solved_and_feasible` | JuMP 1.21+ (2024) | Prescribed for INFRA-03; checks primal+dual too |
| `Requires.jl` for optional deps | `[weakdeps]` + `[extensions]` | Julia 1.9 (2023) | Native, precompilable optional Gurobi/Mosek |
| Plain `@testset` files | `@testitem` + TestItemRunner | TestItems 1.0 (2024) | Parallel/filterable "rung ladder"; VS Code first-class |
| ECOS as default conic | Clarabel | 2023–2024 | Native QP objective, accurate duals (CLAUDE.md) |
| Julia 1.11 "current stable" (per CLAUDE.md) | **Julia 1.12 is now current stable** (1.12.5 installed locally; 1.13-dev in flight) | ~2026 | Add 1.12 to CI matrix; LTS floor stays 1.10 |

**Deprecated/outdated:**
- `direct_model` + Clarabel: never valid (not a deprecation — a capability Clarabel lacks). Correct the CLAUDE.md perf note.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Package/module name `TSODSO` | Project structure, examples | Cosmetic — rename before first commit; planner should confirm with user |
| A2 | Per-unit magnitude bands ([0.8,1.2] V, impedance <5, smax <100) are appropriate tripwires | Pattern 5 | Too tight → false failures; loosen per feeder data. These are heuristic sanity bounds, not physics — confirm against IEEE-13/123 thesis parameters in Phase 4 |
| A3 | Adding Julia 1.12 to the CI matrix is desirable | State of the Art, scaffold example | Low — success criteria mandate only 1.10+1.11; 1.12 is additive insurance |
| A4 | `S_base`/`V_base` per-unit base choice is a single-level balanced base | Pattern 5 | Thesis may specify particular bases; confirm at data-fixture phase (DATA-03, Phase 4) |
| A5 | GitHub is the CI/host and `manifest=true` desired | Scaffold | Low — matches repo; confirm handle/host at plan time |

## Open Questions (RESOLVED)

1. **Final package name.**
   - Known: CLAUDE.md never fixes it; repo dir is `TSO-DSO`.
   - Unclear: exact module identifier (must be a valid Julia identifier — no hyphen).
   - Recommendation: `TSODSO` or `TransactiveGridOpt`; planner confirms with user before `t("...")`.
   - **RESOLVED:** Package/module = `TSODSO` (planner discretion, recorded in SKELETON.md and all plan frontmatter). Non-blocking, renameable.

2. **Does the toy DC need a nontrivial nodal balance, or is single-node sufficient for rung 0?**
   - Known: success criteria say "single-node, single-period."
   - Unclear: whether a 2-node DC would better exercise the incidence/residual seam without over-scoping.
   - Recommendation: keep strictly single-node for rung 0 (Phase 2 adds the branch-flow residual on a real feeder); but still route the balance through `ctx.residuals` so the seam is exercised.
   - **RESOLVED:** Rung 0 is strictly single-node; the balance is still routed through `ModelContext` residuals so the seam is exercised (plan 01-04 T1).

3. **Per-unit base values for the toy.**
   - Known: convention is `S_base` MVA, `V_base` kV.
   - Unclear: specific numbers (defer to thesis fixtures in Phase 4).
   - Recommendation: pick documented placeholders (e.g., `S_base=1.0 MVA`, `V_base=4.16 kV` matching IEEE-13) and note they will be superseded by real fixtures.
   - **RESOLVED:** Placeholder base `S_base=1.0 MVA`, `V_base=4.16 kV`, documented in `src/units/PerUnit.jl`; superseded by real fixtures in Phase 4.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia (current stable) | Everything | ✓ | 1.12.5 (default), 1.11.9 (installed) | — |
| Julia 1.10 LTS | INFRA-01 local test on LTS floor | ✗ | — | `juliaup add 1.10` (or rely on CI matrix for LTS coverage) |
| juliaup | Multi-version testing | ✓ | present (release + 1.11 channels) | — |
| git | Repo / CI | ✓ | present | — |
| Internet / GitHub | CI, Documenter deploy, `Pkg.add` | assumed ✓ | — | — |
| ctx7 (Context7 CLI) | (research only) | ✓ | present | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:**
- **Julia 1.10 LTS not installed locally.** Run `juliaup add 1.10` to test the compat floor locally; otherwise the GitHub Actions matrix (`extra_versions=["1.10","1.11","1.12"]`) provides LTS coverage. Recommend installing locally so INFRA-01's "resolves cleanly on 1.10" is verifiable before push.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Test (stdlib 1.1.5) + TestItems 1.0.0 + TestItemRunner 1.1.5 |
| Config file | `test/Project.toml` (created in Wave 0) + `test/runtests.jl` |
| Quick run command | `julia --project -e 'using TestItemRunner; @run_package_tests filter=ti->:rung0 in ti.tags'` (or run a single file's `@testitem` in VS Code) |
| Full suite command | `julia --project -e 'using Pkg; Pkg.test()'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFRA-01 | Clean instantiate + resolve on 1.10/1.11 | integration (CI) | `julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.status()'` on matrix | ❌ Wave 0 (CI.yml) |
| INFRA-02 | `select_optimizer(::ProblemClass)` returns a working factory; no model names a solver | unit | `@testitem` in `test/test_factory.jl` (build+solve toy via each class) | ❌ Wave 0 |
| INFRA-03 | Non-optimal solve raises; optimal passes; slack detected | unit | `@testitem` in `test/test_status.jl` (feed an infeasible model, `@test_throws`) | ❌ Wave 0 |
| INFRA-05 | Per-unit conversion + magnitude assertions fire on bad scale | unit | `@testitem` in `test/test_perunit.jl` (`@test_throws AssertionError`) | ❌ Wave 0 |
| DATA-01 | Immutable feeder constructs from valid data | unit | `@testitem` in `test/test_feeder.jl` | ❌ Wave 0 |
| DATA-02 | Non-tree feeder throws clear error; valid tree passes | unit | `@testitem` in `test/test_topology.jl` (`@test_throws ArgumentError` on N branches, disconnected) | ❌ Wave 0 |
| PF-01 | `AbstractPowerFlow` contract + residual registry accumulates | unit | `@testitem` in `test/test_toy_dc.jl` (assert `ctx.residuals[:balance]` populated) | ❌ Wave 0 |
| — (rung 0) | Toy DC builds, solves OPTIMAL, returns finite objective + balance dual | integration | `@testitem "rung0..."` in `test/test_toy_dc.jl` | ❌ Wave 0 |
| — (quality) | No stale deps / ambiguities / export issues | quality | `@testitem` running `Aqua.test_all(TSODSO)` | ❌ Wave 0 |
| — (quality) | Type-stability / no latent MethodErrors | quality | JET report on model-build kernel in CI | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** quick rung filter (`filter=ti->:rung0 in ti.tags`) — sub-second.
- **Per wave merge:** `Pkg.test()` (full suite incl. Aqua/JET).
- **Phase gate:** Full suite green on 1.10 + 1.11 (+1.12) in CI before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/Project.toml` — test-only deps (TestItemRunner, Aqua, JET)
- [ ] `test/runtests.jl` — `using TestItemRunner; @run_package_tests`
- [ ] `test/test_perunit.jl`, `test/test_feeder.jl`, `test/test_topology.jl`, `test/test_factory.jl`, `test/test_status.jl`, `test/test_toy_dc.jl` — one `@testitem` set per requirement
- [ ] `.github/workflows/CI.yml` — matrix 1.10/1.11/1.12 + format/Aqua/JET (generated by PkgTemplates)
- [ ] Framework install: `Pkg.add(["TestItems","TestItemRunner","Aqua","JET"])` (test env)

## Security Domain

This is a pure local optimization research library — no auth, sessions, access control, network endpoints, or untrusted remote input. Most ASVS categories are N/A. The relevant controls are **input validation** (feeder data) and **software supply-chain integrity** (dependency pinning).

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — (no auth surface) |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | Radial/tree validation (DATA-02), per-unit magnitude assertions (INFRA-05), struct construction invariants — all "fail loudly" |
| V6 Cryptography | no | — (no secrets) |
| V14 Config & Dependencies | yes | Committed `Manifest.toml` + `[compat]` floors (INFRA-01) = reproducible, pinned supply chain; deps sourced from Julia General registry (official orgs) |

### Known Threat Patterns for a Julia research bench
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed/adversarial feeder data causing silent-wrong results | Tampering | Construction-time validation + magnitude assertions; solve-status discipline refuses non-OPTIMAL |
| Dependency drift / unpinned versions → non-reproducible builds | Tampering | Committed Manifest, `[compat]` floors, CI `instantiate` on clean checkout |
| Typosquatted / hallucinated package | Spoofing | All deps verified against Julia General registry from official orgs (jump-dev, oxfordcontrol, JuliaCI, julia-vscode) — see Package Legitimacy Audit |

## Sources

### Primary (HIGH confidence)
- Context7 `/jump-dev/jump.jl` — Parameter API, `optimizer_with_attributes`/`set_optimizer`/`set_attribute`, `is_solved_and_feasible`/`assert_is_solved_and_feasible`, `direct_model` (docs/src/manual/{variables,models,solutions}.md)
- Context7 `/oxfordcontrol/clarabeldocs` — JuMP interface, `set_optimizer_attribute`, native quadratic (P-matrix), `Clarabel.Settings`
- Context7 `/juliaci/pkgtemplates.jl` — Template plugins (GitHubActions `extra_versions`, Tests aqua/jet, Documenter, Codecov, Git manifest)
- CLAUDE.md Technology Stack — authoritative library/version choices (verified against Julia General registry `Versions.toml`, 2026-07-18)

### Secondary (MEDIUM confidence)
- WebSearch (jump.dev models docs + Julia Discourse) — Clarabel does **not** support `direct_model` (`supports_incremental_interface == false`); cross-confirms Context7 `direct_model` "solver support varies" note
- WebSearch (oxfordcontrol clarabel docs / CRAN mirror) — `tol_gap_abs`/`tol_gap_rel`/`tol_feas` default 1e-8
- WebSearch (julia-vscode/TestItemRunner.jl, julia-vscode docs) — `@testitem`, `@run_package_tests`, tag filtering

### Tertiary (LOW confidence)
- None — all load-bearing claims cross-verified against an official source.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — versions from CLAUDE.md's same-day registry snapshot; Phase-1 APIs re-verified via Context7.
- Architecture (factory, status, registry, validation patterns): HIGH — built directly on verified JuMP APIs; singleton-dispatch and weakdep patterns are established Julia idioms.
- Pitfalls: HIGH — Clarabel/`direct_model` and `is_solved_and_feasible` semantics verified; per-unit/Manifest pitfalls are well-established.
- Assumptions (package name, per-unit bases): flagged LOW in Assumptions Log — need user/plan confirmation, non-blocking.

**Research date:** 2026-07-18
**Valid until:** 2026-08-17 (stable ecosystem; re-check only if Julia LTS changes or JuMP majors)
