<!-- GSD:project-start source:PROJECT.md -->
## Project

**TSO-DSO Integration Optimization Framework (Julia)**

A Julia research framework for **experimenting with a TSO–DSO integration optimization theory**
built on transactive energy / dynamic distribution pricing and Stackelberg–Nash equilibria. It
implements the two-layer framework from J.P. Palacios' PhD thesis (UNSJ/CONICET, 2022) and the
associated PSR N1–N2 expansion note: an **operational layer** (day-ahead dynamic pricing over a
convex branch-flow distribution network, solved as convex social-welfare maximization decomposed by
ADMM, with prices emerging as duals) and a **planning layer** (Stackelberg–Nash TSO–DSO investment
equilibria solved by Benders + diagonalization). It is the computational bench for Pedro's PhD:
reproducible experiments from simple to complex scenarios, with clean seams for model adaptations
and novel research extensions. Audience: the PhD researcher and collaborators (thesis, papers).

**Core Value:** **A researcher can express a scenario and a model variant declaratively, run it end-to-end with an
open-source solver, and get trustworthy, reproducible results and prices — with every model
assumption documented and every layer swappable.** If everything else fails, this must work:
correct, validated optimization models that are easy to extend for research.

### Constraints

- **Tech stack**: Julia + JuMP for optimization modeling — the natural ecosystem for research-grade
  math programming with swappable solvers and good performance.
- **Solvers**: Favor open source — HiGHS (LP/MILP), Ipopt (NLP), Clarabel/SCS (conic/SOCP). Gurobi
  permitted only as a commercial fallback, behind a solver-abstraction so no model hard-depends on it.
- **Correctness**: SOCP relaxation must be validated **exact** on radial fixtures (LinDistFlow trick);
  results must be reproducible (seeded data generation, pinned environment via `Project.toml`/`Manifest.toml`).
- **Extensibility**: architecture must let a researcher swap the power-flow model, device models,
  objective, and solve strategy independently — model adaptations are a first-class use case.
- **Documentation**: rich, step-by-step docs of every modeling decision and its math are a hard
  requirement, not optional. Clean, idiomatic, well-organized Julia code.
- **Audience/purpose**: PhD thesis research — favor clarity, correctness, and traceability to the
  source theory over premature performance optimization.
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## TL;DR (the prescription)
- **Model in JuMP, not Convex.jl.** You need direct control of individual constraints (the LinDistFlow exactness copy), first-class access to a *specific* constraint's dual (the DADP `λ_j[t]`), JuMP `Parameter`s for cheap re-solves, and warm starts inside ADMM/Benders. Convex.jl's DCP auto-transformation hides exactly those seams.
- **Default conic solver: Clarabel.jl.** Native-Julia interior-point conic solver, handles SOCP **and** quadratic objectives natively, high-accuracy duals (critical — your prices *are* duals). SCS as a large-scale fallback, Mosek if a license appears. Do **not** default to ECOS or SCS.
- **HiGHS for LP/MILP, Ipopt for any true NLP, Gurobi only behind the abstraction.** JuMP's `set_optimizer` / `Model(optimizer)` *is* the abstraction — wrap it in one thin factory function; do not hard-code any solver in a model.
- **Build the branch-flow model from scratch in JuMP.** Do not build the operational core *on top of* PowerModelsDistribution. Use PMD/PowerModels only as a data-parsing and cross-validation oracle, and as a formulation reference.
- **Hand-roll ADMM and Benders.** This matches the thesis, keeps full control of the dual updates, and is the idiomatic Julia approach for research. No decomposition mega-framework (Coluna/StructJuMP) — they impose structure that fights a research bench.
- **For the planning layer:** hand-rolled Benders + Gauss-Seidel diagonalization; keep **BilevelJuMP.jl** only as a small-case validation oracle (KKT/SOS1/Fortuny-Amat single-level reductions). PATHSolver/Complementarity.jl only if you later recast an equilibrium as a genuine MCP.
- **Tooling:** PkgTemplates scaffold, `Test` + **TestItems/TestItemRunner**, **Documenter 1.x + Literate.jl** (literate, reproducible experiment docs — a hard project requirement), **JuliaFormatter 2.x**, **Aqua.jl** + **JET.jl**, **DrWatson.jl** for experiment/scenario management, CSV + DataFrames for data, **CairoMakie** for publication figures.
## Recommended Stack
### Core Technologies
| Technology | Version (2026-07) | Purpose | Why Recommended |
|------------|-------------------|---------|-----------------|
| **Julia** | 1.11.x (compat floor **1.10 LTS**) | Language/runtime | 1.10 is the LTS; 1.11 is current stable with faster loading and better sparse support. Pin floor at 1.10 for reproducibility; test on both. |
| **JuMP** | **1.30.1** | Algebraic modeling layer | The standard for research math-programming in Julia. Solver-agnostic, exposes `dual()` per constraint (your DADP), native `Parameter`s, warm starts, `SecondOrderCone`/quadratic support, and the direct-model path for perf. Everything downstream is built on it. |
| **MathOptInterface (MOI)** | **1.51.2** | Solver abstraction / bridge layer under JuMP | You rarely call it directly, but MOI *is* the "swap any solver" mechanism. Bridges auto-reformulate (e.g. quadratic-objective ↔ rotated-SOC, absolute values) so one model text runs on Clarabel, SCS, Ipopt, Gurobi unchanged. Understand `Bridges` and `TerminationStatus`/`DualStatus` — you will read them when validating exactness. |
| **Clarabel.jl** | **0.11.1** | Primary conic solver: SOCP + convex QP (GLB-CVX, DSO-OPT, AGR-OPT) | Native-Julia interior-point method for LP/QP/SOCP/SDP/exp cones from the Oxford Control group; now the community-default open-source conic solver. Handles quadratic objectives **natively** (no manual epigraph), returns **accurate duals** — essential because your transactive prices are the duals of the nodal balance. IPM accuracy >> first-order for price recovery. |
| **HiGHS** | **1.24.1** | LP / MILP (planning masters, Benders master, LinDistFlow-only toy rungs) | The default open-source LP/MILP solver in the JuMP ecosystem: fast simplex + interior + MIP, actively developed, zero-license. Use it for the Benders master problem, binary-expansion MILP subproblems, and any linearized DC/LinDistFlow toy models. |
| **Ipopt** | **1.15.0** | General smooth NLP fallback | Interior-point NLP (MUMPS linear solver). Not needed for the convex SOCP core (Clarabel is better there), but keep it wired in for any nonconvex experiment rung (full AC-OPF, nonconvex device models) and as a sanity cross-check on convex cases. |
### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **SCS** | 2.6.4 | First-order (ADMM) conic solver | Fallback when a monolithic SOCP grows too large for Clarabel's IPM memory. Lower-accuracy duals — do **not** use it to certify SOCP exactness or to report final DADPs; use it for scale/feasibility scouting only. |
| **Gurobi.jl** | 1.9.2 | Commercial LP/QP/MILP/SOCP fallback | Only behind the solver factory, only when a license exists and open-source solvers stall on a large MILP. Never a hard dependency; must remain removable. (Same policy for Mosek/`MosekTools` if a license appears — it is the gold standard for SOCP+duals but licensed.) |
| **PATHSolver** | 1.7.9 | Mixed complementarity (MCP) solver | Only if a *future* equilibrium variant is recast as a genuine MCP/VI. Not needed for Benders-based Stackelberg-Nash. |
| **BilevelJuMP.jl** | 0.6.3 | Bilevel → single-level (KKT / SOS1 / Fortuny-Amat / strong-duality) reformulations | Planning-layer **validation oracle** on small instances: solve a tiny leader-follower case as a compact MPEC and check it against your Benders answer. Not the production planning solver (thesis method is Benders + diagonalization, not MPEC). |
| **Complementarity.jl** | 0.9.0 | Modeling MCP/equilibrium on top of JuMP+PATHSolver | Optional, same footing as PATHSolver — only for an explicit complementarity recast. |
| **InfiniteOpt.jl** | 0.6.3 | Infinite-dimensional (time + random) modeling | Strong fit for the **stochastic** and **MPC/rolling-horizon** extension axes: express continuous-time / random-parameter formulations and let it discretize. Evaluate when those milestones open; not needed for v1. |
| **SparseArrays** (stdlib) | — | Sparse incidence/admittance and RHS structures | Network topology and constraint RHS are sparse; use sparse structures for feeder data and any hand-assembled matrices. |
| **CSV.jl** | 0.10.16 | Read/write feeder + device + price data | Load IEEE 13/123 feeder fixtures, appliance data, price/PV profiles. |
| **DataFrames.jl** | 1.8.2 | Tabular data wrangling | Scenario tables, results collation, DLMP decomposition tables, sensitivity sweeps. |
| **CairoMakie.jl** | 0.15.13 (Makie 0.24.13) | Publication-quality static figures (PDF/SVG) | Thesis/paper figures: DADP-vs-hour curves, voltage profiles, ADMM residual convergence, DLMP decomposition stacks. Vector output is thesis-grade. Use GLMakie only if you want interactivity. |
| **DrWatson.jl** | 2.19.1 | Scientific-project / experiment management | Directly serves "reproducible experiments from simple to complex." `@produce_or_load`, `savename`, `tagsave` (stamps git commit + Manifest into results), `collect_results` for sweep aggregation. Adopt from day one — it is the reproducibility backbone. |
### Development Tools
| Tool | Version | Purpose | Notes |
|------|---------|---------|-------|
| **PkgTemplates.jl** | current | Scaffold the package | Generate the `Project.toml`/`src`/`test`/`docs` skeleton with CI, Documenter, formatter, and license wired up. One-time bootstrap. |
| **Test** (stdlib) + **TestItemRunner.jl** | 1.1.5 (**TestItems 1.0.0**) | Testing | Modern idiom: annotate independent tests with `@testitem`, run selectively/parallel via TestItemRunner, first-class in the VS Code Julia extension. Great for the abstraction ladder — one test item per rung/model variant. Plain `@testset` also fine; prefer TestItems for a growing framework. |
| **Aqua.jl** | current | Package-quality auto-tests | Catches undefined exports, stale deps, method ambiguities, compat-bound gaps. Cheap insurance in CI. |
| **JET.jl** | current | Static analysis / type-stability & error detection | Run in CI to catch type instabilities and latent `MethodError`s in the modeling code — directly supports the numerical/perf goals below. |
| **Documenter.jl** | **1.17.0** | Docs site (math + API) | 1.x is the current generation. Renders LaTeX (KaTeX) — put every model's equations (3.31–3.45 etc.) beside the code. Doctests keep examples honest. |
| **Literate.jl** | **2.21.0** | Literate, reproducible experiment scripts | Turns a commented `.jl` into runnable script **and** rendered docs page from one source — the ideal vehicle for "rich per-step documentation of every modeling decision." Each experiment = one Literate file that executes end-to-end. |
| **JuliaFormatter.jl** | **2.10.1** | Code formatting | Commit a `.JuliaFormatter.toml`; enforce in CI. v2 is the current line. |
| **BenchmarkTools.jl** | current | Micro/perf benchmarking | Track model-build and per-iteration ADMM/Benders solve times as the ladder scales. |
| **GitHub Actions** (`julia-actions/*`) | — | CI | Standard matrix: Julia 1.10 (LTS) + 1.11 + `nightly` (allow-fail), on Linux; run tests, Aqua, JET, formatter check, and `Documenter` deploy. |
## Installation
# In the project environment (activate the repo, then):
# Core modeling + solvers
# Solver fallbacks (SCS open; Gurobi/Mosek only if licensed)
# Pkg.add("Gurobi")            # commercial, license required
# Pkg.add("MosekTools")        # commercial, license required
# Planning-layer / equilibrium tooling (add when that milestone opens)
# Pkg.add(["BilevelJuMP", "Complementarity", "PATHSolver", "InfiniteOpt"])
# Data + figures + reproducibility
# Dev/test/docs
## Deep-Dive Decisions
### 1. JuMP vs Convex.jl for the SOCP/DCP core — **JuMP** (HIGH confidence)
- **Dual access to a *named* constraint.** The DADP `λ_j[t]` is the dual of the specific nodal active-balance constraint (3.31). In JuMP you write that constraint as a handle and call `dual(balance[j,t])`. Convex.jl builds an internal transformed problem; recovering the dual of one original physical constraint is awkward and fragile — unacceptable when duals *are* your product.
- **Manual constraint control.** The LinDistFlow exactness copy (3.43–3.45) and the SOC cone (3.39) must be written explicitly and toggled per rung. JuMP's `@constraint(m, [t; P; Q] in SecondOrderCone())` (or the rotated form matching `l·v ≥ P²+Q²`) gives you exactly that. Convex.jl's DCP ruleset auto-forms cones and can obscure which relaxation is active.
- **`Parameter`s + warm starts + re-solve.** ADMM re-solves the same subproblems ~28× with updated `λ_j,μ_j,ρ`; Benders re-solves the master with growing cuts. JuMP native `Parameter`s (`@variable(m, p in Parameter(v))` + `set_parameter_value`) and `set_normalized_rhs`/warm starts make these cheap. Convex.jl rebuilds. JuMP wins decisively on the outer-loop workloads that dominate this project.
- **Ecosystem gravity.** PowerModels, BilevelJuMP, ParametricOptInterface, InfiniteOpt, Coluna — every adjacent tool is JuMP-native. Convex.jl would silo you.
### 2. Conic solver selection — **Clarabel primary** (HIGH confidence)
# swap Clarabel→SCS/Mosek/Gurobi by changing one line; models never name a solver.
### 3. PowerModels(Distribution) vs from-scratch — **from-scratch, with PMD as oracle** (MEDIUM-HIGH confidence)
- They impose their own data model (Matpower/OpenDSS parsing, network dicts) and a fixed set of formulation types. Your model has **custom prosumer device utilities, aggregator aggregation, the specific LinDistFlow exactness copy, and a bespoke ADMM split with duals-as-prices** — none of which map cleanly onto PMD's component/variable/constraint templates. You would spend more effort overriding PMD than writing the model.
- Research control and traceability to the thesis equations (a hard requirement) argue for a transparent, from-scratch JuMP model where every constraint corresponds to a numbered thesis equation.
- Unbalanced 3-phase (PMD's core strength) is explicitly out of scope for v1 (balanced positive-sequence).
- **Data-import oracle** — PMD parses OpenDSS; PM parses Matpower. Convert IEEE 13/123 feeders once and export clean fixtures.
- **Formulation reference** — their SOC branch-flow code is a correctness reference for your cone/exactness constraints.
- **Cross-validation** — solve a plain OPF on the same feeder in PMD and check your model's power flows/voltages agree on a no-DER baseline.
### 4. Bilevel / equilibrium tooling (planning layer) — **hand-rolled Benders + diagonalization** (MEDIUM confidence)
- **Hand-roll** the Benders master/subproblem split and the diagonalization outer loop in JuMP. This gives exact control of cut generation (`α ≥ w^k + Σ_s π_s^k (z − z^k)`), the dual `π_s` of the coupling constraint, and the diagonalization sweep. HiGHS for the MILP master; Clarabel/HiGHS for continuous subproblems.
- **BilevelJuMP.jl** as a *validation oracle only*: on tiny leader-follower instances, its KKT / SOS1 / Fortuny-Amat / strong-duality single-level reductions give an independent optimum to check your Benders loop against. Do not use it as the production planning solver (MPEC single-level blowup won't match the thesis's decomposition intent and scales poorly).
- **Complementarity.jl + PATHSolver**: keep on the shelf. Only relevant if a future variant is deliberately posed as a mixed complementarity / variational-inequality equilibrium rather than Benders.
- **Gogeta.jl: not relevant** — it embeds trained ML models (NNs, trees) into optimization; no role here.
### 5. Decomposition tooling (ADMM + Benders) — **hand-rolled loop is the standard** (MEDIUM-HIGH confidence)
- **ADMM (operational):** build `AGR-OPT` (per-node QP, house-separable) and `DSO-OPT` (per-hour SOCP) as JuMP models **once**, then in the loop update the price/penalty terms via JuMP `Parameter`s and re-solve, updating duals by `λ_j ← λ_j + ρ·R_{p,j}`. Rebuilding models each iteration is the common performance mistake — parametrize and re-solve. Consider `direct_model(Clarabel.Optimizer())` for the hot subproblems to cut MOI overhead, and warm-start from the previous iterate.
- **Benders (planning):** hand-rolled master + subproblem with `@constraint` cut accumulation; optionally lazy-constraint callbacks via HiGHS/Gurobi for branch-and-Benders-cut later.
- **Frameworks considered and declined for v1:** **Coluna.jl** (0.8.2, Dantzig-Wolfe/branch-price-and-cut + Benders) is powerful but heavyweight and imposes an annotation/structure model that fights a teaching-oriented research bench. **StructJuMP** and **BendersDecomposition**-style packages are stale/immature. **DualDecomposition.jl** (0.3.4, Argonne — Lagrangian dual decomposition for stochastic MIPs) is the one worth *revisiting* when the Lagrangian-cut/stochastic planning milestone lands, but not for v1. Start hand-rolled; graduate to a framework only if scaling demands it.
### 6. Numerical / performance for scaling (MEDIUM-HIGH confidence)
- **Sparse everything structural.** Feeder incidence, branch parameters, coupling RHS → `SparseArrays`. Avoid dense `N×N` on the 123-node cases and beyond.
- **Type stability.** Wrap experiment logic in functions (no untyped globals); give structs concrete, parametrized fields (`struct Feeder{T<:Real} ... end`); use function barriers when reading heterogeneous config into the hot loop. Run **JET.jl** and `@code_warntype` on the model-build and iteration kernels.
- **Build once, re-solve many.** The dominant cost is the ADMM/Benders outer loop. Construct JuMP models once; mutate via `Parameter`s / `set_normalized_rhs` / `set_objective_coefficient`; warm-start. Never rebuild inside the loop.
- **`direct_model` for hot subproblems** to skip the MOI caching layer when the solver supports it (Clarabel does) — measurable per-iteration savings at scale.
- **Vectorized constraint construction** (`@constraint(m, [t=1:T], ...)`) over Julia-loop `push!`ing for build speed; use `@expression` to share repeated subexpressions (e.g. `R_{p,j}`).
- **Profile before optimizing** (`BenchmarkTools`, `Profile`) — the project constraints explicitly favor clarity/correctness over premature optimization; instrument, then target the true hot spot (usually subproblem solve time, i.e. solver choice, not Julia code).
## Alternatives Considered
| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Clarabel.jl | Mosek (`MosekTools`) | Licensed environment; gold-standard SOCP accuracy/robustness at scale. Behind the factory. |
| Clarabel.jl | SCS | Monolithic SOCP too large for IPM memory; scouting feasibility/scale only (not final prices). |
| JuMP | Convex.jl | Throwaway independent DCP re-check of a small SOCP. Never for the framework core. |
| From-scratch JuMP model | PowerModelsDistribution.jl | If the project pivoted to unbalanced 3-phase distribution OPF with standard formulations and no custom market layer. Not this project's v1. |
| Hand-rolled Benders | BilevelJuMP.jl | Small-instance validation of the planning equilibrium; rapid prototyping of a single-level MPEC reduction. |
| Hand-rolled ADMM/Benders | DualDecomposition.jl / Coluna.jl | Later, if stochastic Lagrangian decomposition or Dantzig-Wolfe scale genuinely demands a framework. |
| HiGHS | Gurobi.jl | Licensed; large MILP planning masters where HiGHS stalls. Behind the factory. |
| CairoMakie | Plots.jl | Quick interactive/exploratory plots; simpler API. CairoMakie preferred for final thesis vector figures. |
| TestItemRunner | plain `@testset` | Small/simple test suites; TestItems shines as the suite and model-variant ladder grows. |
## What NOT to Use
| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **ECOS** as the conic solver | Superseded by Clarabel; no native quadratic objective; low development activity | Clarabel.jl |
| **SCS for final DADP/exactness certification** | First-order accuracy; noisy duals undermine price recovery and the `l·v ≈ P²+Q²` exactness check | Clarabel.jl (or Mosek) |
| **Convex.jl for the framework core** | DCP auto-transform hides per-constraint duals and the exactness/relaxation seams you must control | JuMP |
| **Building the operational core on PowerModelsDistribution** | Its data/component/formulation model fights custom device utilities, aggregators, the exactness copy, and duals-as-prices; more overriding than building | From-scratch JuMP model; PMD as data/validation oracle only |
| **BilevelJuMP as the production planning solver** | Single-level MPEC reductions blow up and diverge from the thesis's Benders/diagonalization method | Hand-rolled Benders + Gauss-Seidel diagonalization |
| **Coluna.jl / StructJuMP in v1** | Heavyweight/stale; impose structure that obscures a teaching-oriented research model | Hand-rolled decomposition with JuMP `Parameter`s |
| **Gogeta.jl** | Solves a different problem (embedding trained ML into optimization) | n/a — not needed |
| **PowerModelsONM** | Targets unbalanced networked-microgrid restoration; orthogonal | n/a |
| **Rebuilding JuMP models each ADMM/Benders iteration** | Dominant, avoidable performance sink at scale | Build once; update `Parameter`s / RHS; warm-start; `direct_model` for hot subproblems |
| **Hard-coding any solver inside a model** | Breaks the open-source-first + Gurobi-fallback requirement | Single `make_solver` factory; models take an optimizer argument |
## Stack Patterns by Variant
- JuMP model → Clarabel, single solve, read `dual(balance[j,t])` for DADP.
- Validate exactness by checking `l[i,j]·v[i] ≈ P² + Q²` and cross-solving on Ipopt/Mosek.
- Prebuilt `AGR-OPT` (Clarabel QP, per node) + `DSO-OPT` (Clarabel SOCP, per hour) with JuMP `Parameter`s for `λ_j,μ_j,ρ`; hand-rolled dual-ascent outer loop; track residuals with a small struct, plot convergence with CairoMakie.
- Drop the SOC cone → pure LP/QP → HiGHS (LP/MILP) or Clarabel (QP). Same model interfaces, cheaper solver.
- Scenario-based extensive form (build scenarios, one big JuMP model) first; evaluate **InfiniteOpt.jl** for continuous random-domain formulations; **DrWatson** for scenario management; revisit **DualDecomposition.jl** if Lagrangian scenario decomposition is needed.
- JuMP `Parameter`s for the receding-horizon state/forecast inputs; re-solve per step with warm starts; **InfiniteOpt** as a candidate modeling front-end for continuous-time horizons.
- HiGHS master (MILP after binary expansion) + Clarabel/HiGHS subproblems; hand-rolled Benders cuts using the coupling dual `π_s`; Gauss-Seidel diagonalization loop for multiple distributors; **BilevelJuMP** to validate tiny cases.
## Version Compatibility
| Package | Compatible With | Notes |
|---------|-----------------|-------|
| JuMP 1.30.x | MOI 1.51.x | JuMP re-exports/depends on MOI; let Pkg resolve — do not pin MOI independently. |
| JuMP 1.30.x | Clarabel 0.11, HiGHS 1.24, Ipopt 1.15, SCS 2.6, Gurobi 1.9 | All expose MOI 1.x optimizers; interchangeable via the factory. |
| Clarabel 0.11 | Julia ≥ 1.10 | Native Julia; no external binary. |
| HiGHS 1.24 / Ipopt 1.15 / SCS 2.6 | Julia ≥ 1.10 | Ship precompiled binaries via `*_jll`; no system install needed. |
| BilevelJuMP 0.6.x | JuMP 1.x, PATHSolver 1.7.x | Reformulation-based; solver depends on chosen mode (KKT/SOS1/FA). |
| Makie/CairoMakie 0.24/0.15 | Julia ≥ 1.10 | Keep Makie and CairoMakie versions in lockstep (Pkg handles it). |
| DataFrames 1.8 / CSV 0.10 | Julia ≥ 1.10 | Stable, well-established. |
| TestItems 1.0 / TestItemRunner 1.1 | Julia ≥ 1.10, VS Code Julia ext | 1.0 is the first stable TestItems; API settled. |
| Documenter 1.17 / Literate 2.21 | Julia ≥ 1.10 | Documenter 1.x is the current generation (breaking vs 0.27). |
| JuliaFormatter 2.10 | Julia ≥ 1.10 | v2 default style differs slightly from v1 — commit a config to freeze style. |
## Sources
- **Julia General registry `Versions.toml`** (raw.githubusercontent.com/JuliaRegistries/General), fetched 2026-07-18 — HIGH confidence on all version numbers: JuMP 1.30.1, MOI 1.51.2, Clarabel 0.11.1, HiGHS 1.24.1, Ipopt 1.15.0, SCS 2.6.4, ECOS 1.1.3, Gurobi 1.9.2, PowerModels 0.21.6, PowerModelsDistribution 0.16.0, PowerModelsONM 4.0.0, InfrastructureModels 0.7.9, BilevelJuMP 0.6.3, Complementarity 0.9.0, PATHSolver 1.7.9, InfiniteOpt 0.6.3, DrWatson 2.19.1, Documenter 1.17.0, Literate 2.21.0, JuliaFormatter 2.10.1, TestItems 1.0.0, TestItemRunner 1.1.5, CSV 0.10.16, DataFrames 1.8.2, Makie 0.24.13, CairoMakie 0.15.13, Coluna 0.8.2, DualDecomposition 0.3.4, StructJuMP 0.3.2, Gogeta 0.3.0, ParametricOptInterface 0.15.3.
- **Project context** — `.planning/PROJECT.md`, `.planning/research/THEORY-thesis.md`, `.planning/research/THEORY-papers.md` (model math, solver mapping already sketched by prior theory extraction; this stack aligns with and sharpens those notes).
- **Ecosystem-fit judgments** (JuMP-vs-Convex, Clarabel-as-default-conic, from-scratch-vs-PMD, hand-rolled decomposition) — MEDIUM-HIGH confidence, based on the documented JuMP/MOI architecture and the packages' stated scopes; not every claim was re-verified against live docs this session. Flag for a quick doc re-check at implementation time: Clarabel quadratic-objective attribute names, JuMP `Parameter` API surface, and `direct_model` support for Clarabel.
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
