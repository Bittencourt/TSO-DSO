# Phase 8: Experiment Harness & Reproducibility - Research

**Researched:** 2026-07-19
**Domain:** Julia experiment management / reproducibility (DrWatson.jl) orchestrating the Phase 1–7 solve stack
**Confidence:** HIGH (DrWatson API re-verified live; registry pins confirmed against local General clone; solve seams read from source)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
No user-preference grey areas. The harness follows CLAUDE.md's explicit tooling choices verbatim.

### Claude's Discretion (anchored to CLAUDE.md tooling + Phases 1–7 seams)
- **DrWatson.jl** — the reproducibility backbone: `@produce_or_load`, `savename`, `tagsave`
  (stamps git commit + Manifest into results), `collect_results` for sweep aggregation. A
  `Scenario` struct (feeder + devices/aggregators + price profile + config incl. seed +
  solve-strategy selector) that DrWatson can `savename`/hash.
- **Declarative scenario + swappable strategy (EXP-01):** a `Scenario` is a plain declarative
  spec; `run_scenario(scenario)` dispatches to the centralized `solve_welfare`/`operational_oracle`
  OR the ADMM `solve_admm` via a strategy selector (`strategy = :centralized | :admm`), reusing
  the validated builders — the harness is orchestration, no new models. Returns a result record
  (welfare, DADP, iters/residuals for ADMM, exactness certificate, timings).
- **Parameter sweeps + flat storage (EXP-02):** `dict_list`-style sweep over scenario parameters;
  results stored in a **flat, versioned, diff-friendly format** — CSV + DataFrames for the tabular
  sweep collation, DrWatson `savename`/`tagsave` for per-run artifacts. Diff-friendly =
  deterministic key ordering, text/CSV not opaque binary for the summary tables.
- **Reproducibility / provenance (INFRA-04):** every run records inputs + config + environment +
  SEED (the StableRNGs seed threaded through profile generation) via DrWatson `tagsave` (git commit +
  Manifest stamp) so a run regenerates **bit-for-bit** on the open-source solver path. A test asserts
  same-seed → identical result (reusing the DATA-04 guarantee end-to-end through the solve).
- **Solver/status discipline (CLAUDE.md):** open-source path (Clarabel/HiGHS/Ipopt) via
  `select_optimizer`; `assert_solved!` + PF-04 exactness on the SOCP path; no model names a solver.
- **DrWatson project layout:** adopt DrWatson's project conventions where they fit a package (harness
  inside `src/experiments/`, runnable scenarios/sweeps in a `scripts/` dir) — research confirms the
  package-vs-project fit (see below).

### New dependencies
Adds **DrWatson.jl**, **CSV.jl**, **DataFrames.jl** (all in the CLAUDE.md recommended stack).
Flag them; re-resolve the version-specific manifests (main + test) on 1.10/1.11/1.12.

### Deferred Ideas (OUT OF SCOPE)
- Literate/Documenter experiment pages that USE the harness → Phase 9.
- Publication figures beyond the Phase-7 ADMM diagnostics (CairoMakie) → Phase 9.
- Stochastic / rolling-horizon scenario families → later milestone.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| EXP-01 | Researcher defines a scenario declaratively (feeder + devices + price profile + config) and runs it end-to-end with either solve strategy. | `Scenario` struct of **primitive selectors** (§Scenario Schema) + `run_scenario` strategy dispatch over the already-validated `solve_welfare` / `solve_admm` (§Architecture Pattern 1). Both entry points read from source (verified signatures below). |
| EXP-02 | Parameter sweeps over scenarios run and store results in a flat, versioned, diff-friendly format. | `dict_list` → `Vector{Dict}` → `Scenario(; nt...)` sweep (§Pattern 2); **two-tier storage**: gitignored JLD2 per-run artifacts + committed diff-friendly CSV summary with deterministic row/column ordering (§Pattern 3, §Don't Hand-Roll). |
| INFRA-04 | Every run records inputs/config/environment (seed logged) so results regenerate bit-for-bit on the open-source solver path. | `@tagsave` stamps git commit (+ optional gitpatch); committed `Manifest.toml` pins the environment at that commit (§Provenance). Seed threaded through profiles AND population via deterministic sub-seeds (§Pitfall 5). Solver-determinism analysis for Clarabel/HiGHS/Ipopt (§Solver Determinism). Same-seed→identical test is the load-bearing gate. |
</phase_requirements>

## Summary

This is a **pure-orchestration phase**: no new optimization model, no new solver, no new math. It
wraps the Phase 1–7 stack (`solve_welfare` centralized SOCP, `solve_admm` decomposed ADMM, seeded
`generate_profiles`, the `select_optimizer` factory, the PF-04 `assert_socp_exact!` certificate) in a
declarative `Scenario` → `run_scenario(scenario) -> ScenarioResult` façade, adds a `dict_list` sweep,
and layers DrWatson provenance (`@tagsave`) plus a diff-friendly CSV summary.

The single most important design decision — the one that makes `savename`, hashing, diffing, and
reproducibility all fall out for free — is that **`Scenario` fields are primitive *selectors*
(`Symbol`/`Int`/`Float64`/`Bool`), never the constructed `Feeder{T}` / `Vector{Aggregator}` /
`λ₀::Vector` objects.** The heavy objects are *materialized deterministically from the selectors +
seed inside `run_scenario`*. A `Scenario` that stores a `:ieee13` symbol and a `seed::Int` is
`savename`-able with zero `DrWatson.default_allowed` overloading, is `hash`-stable, serializes to a
one-line CSV row, and fully determines the run. A `Scenario` that stores a live `Feeder{Float64}`
would need custom `default_allowed`/`allaccess` overloads, hashes unstably, and cannot be diffed.

DrWatson's API was re-verified live (2026-07-19): `savename`, `tagsave`/`@tagsave`, `produce_or_load`/
`@produce_or_load`, `dict_list`, `collect_results` all confirmed. **One CLAUDE.md imprecision
corrected:** `tagsave` stamps the **git commit hash** (and, with `storepatch=true`, a dirty-tree
patch) — it does **not** embed the full `Manifest.toml` content. Environment reproducibility comes
from `gitcommit` + the **committed** `Manifest.toml` (INFRA-01) at that commit. Store the Julia
`VERSION` alongside for completeness.

**Primary recommendation:** Add DrWatson/CSV/DataFrames as **hard `[deps]`** (not weakdeps — the
provenance stamping *is* INFRA-04, a hard requirement, unlike the genuinely-optional CairoMakie viz).
Keep `Scenario`/`run_scenario` in `src/experiments/` dependency-light so EXP-01 is testable without
touching storage; keep the DrWatson/CSV persistence + sweep layer in the same directory. Store per-run
full artifacts as gitignored JLD2; store the sweep summary as a committed, deterministically-ordered
CSV. Thread one master seed into independent deterministic sub-seeds for profiles vs. population.
Assert same-seed→identical on the single-threaded Clarabel path (CI, same machine) with exact
equality; treat cross-machine reproducibility as tight-tolerance, not bit-identical.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Declarative scenario spec (`Scenario`) | Core library (`src/experiments/`) | — | Immutable value type; must be constructible/hashable without solvers or DrWatson loaded. |
| Materialize feeder/aggregators/profiles from selectors | Core library (`src/experiments/`) | Phase 1–7 builders | Deterministic construction from `Scenario` + seed; reuses `ieee13_modified`, `generate_profiles`, `Aggregator`. |
| Strategy dispatch (`run_scenario`) | Core library (`src/experiments/`) | `solve_welfare` / `solve_admm` | Orchestration only; delegates the actual solve to validated Phase 3–7 code. |
| Result normalization (`ScenarioResult`) | Core library (`src/experiments/`) | `extract_dlmp`, exactness gate | Unify centralized vs. ADMM outputs into one comparable schema (node×T DADP). |
| Parameter sweep (`dict_list` → runs) | Harness/storage (`src/experiments/`) | DrWatson | Cartesian expansion of scenario params. |
| Per-run persistence + git provenance | Harness/storage (`src/experiments/`) | DrWatson `@tagsave`, JLD2 | Gitignored binary artifact with `gitcommit` stamp. |
| Diff-friendly summary table | Harness/storage (`src/experiments/`) | CSV.jl, DataFrames.jl | Committed text summary; deterministic ordering. |
| Runnable entry points (scenarios, sweeps) | `scripts/` | harness API | `@quickactivate "TSODSO"` scripts a researcher edits/runs. |
| Solver selection | Phase 1 factory (`select_optimizer`) | — | Never named in the harness (INFRA-02). |

## Standard Stack

### Core (new hard `[deps]` this phase)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| **DrWatson.jl** | **2.19.1** | Experiment management: `savename`, `@tagsave`, `@produce_or_load`, `dict_list`, `collect_results`, `datadir`/`projectdir` | The de-facto Julia scientific-project reproducibility framework (JuliaDynamics). CLAUDE.md's designated backbone. `[VERIFIED: local General registry clone `~/.julia/registries/General/D/DrWatson/Versions.toml`, 2.19.1 present]` |
| **CSV.jl** | **0.10.16** | Read/write the flat diff-friendly summary table | Standard JuliaData CSV I/O. `[VERIFIED: local General registry clone, 0.10.16 present]` |
| **DataFrames.jl** | **1.8.2** | Tabular collation of sweep results before CSV write; `collect_results` returns a `DataFrame` | Standard JuliaData tabular type; `collect_results` return type. `[VERIFIED: local General registry clone, 1.8.2 present]` |

### Supporting (transitively pulled by DrWatson — no explicit add needed)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **JLD2.jl** | 0.6.5 | Binary per-run artifact format (full DADP matrix, residual traces) via DrWatson `wsave`/`@tagsave` | DrWatson dependency; the `.jld2` per-run store. `[VERIFIED: local registry, 0.6.5 present]` Gitignored (binary, not diff-friendly). |
| **FileIO.jl** | 1.20.0 | DrWatson's `wsave`/`wload` dispatch layer | Transitive; no direct use. `[VERIFIED: local registry]` |
| **StableRNGs.jl** | 1.0.4 (already a `[dep]`) | The seed stream threaded through the run | Already wired via `src/data/profiles.jl`. `[VERIFIED: Project.toml]` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| DrWatson/CSV/DataFrames as **hard deps** | **Weakdep extension** `TSODSOExperimentsExt` (mirror the CairoMakie pattern) | Keeps core `using TSODSO` lean and cuts CI precompile. **Rejected as primary:** INFRA-04 provenance stamping is a hard requirement and the same-seed reproducibility TEST must run in CI, so DrWatson would end up in test deps regardless; gating the reproducibility contract behind an optional load contradicts "reproducibility is a hard requirement." CairoMakie is genuinely optional viz; provenance is not. Keep weakdep as a documented fallback if core precompile cost becomes painful. |
| JLD2 per-run artifact | BSON.jl / Serialization stdlib | JLD2 is DrWatson's default `wsave` backend and HDF5-based (portable, versioned); no reason to deviate. |
| CSV summary | Arrow / Parquet | Binary → not diff-friendly → violates EXP-02's "diff-friendly" requirement. CSV is the correct choice for the *committed* summary. |
| Store `λ₀`/aggregators in `Scenario` | Selectors + materialize at run time | Storing built objects breaks `savename`/hash/diff (see Summary + Pitfall 1). Selectors are mandatory. |

**Installation:**
```julia
# In the TSODSO package environment (Pkg.activate at repo root):
using Pkg
Pkg.add(["DrWatson", "CSV", "DataFrames"])   # JLD2/FileIO arrive transitively via DrWatson
# Then re-resolve + commit main + test Manifest.toml on Julia 1.10 (LTS), 1.11, 1.12.
```

**Version verification (performed this session):**
```
DrWatson  2.19.1   [VERIFIED: ~/.julia/registries/General/D/DrWatson/Versions.toml]
CSV       0.10.16  [VERIFIED: ~/.julia/registries/General/C/CSV/Versions.toml]
DataFrames 1.8.2   [VERIFIED: ~/.julia/registries/General/D/DataFrames/Versions.toml]
JLD2      0.6.5    [VERIFIED: ~/.julia/registries/General/J/JLD2/Versions.toml]
FileIO    1.20.0   [VERIFIED: ~/.julia/registries/General/F/FileIO/Versions.toml]
```
All three CLAUDE.md pins are the current registry heads — no staleness.

## Package Legitimacy Audit

> Julia packages resolve through the **General registry** (a curated, PR-gated registry), not npm/PyPI.
> `slopcheck` targets npm/PyPI and is **not applicable** to the Julia ecosystem; the authoritative
> verification is the local General registry clone (done this session) plus the packages' status as
> flagship JuliaDynamics/JuliaData libraries.

| Package | Registry | Age | Adoption | Source Repo | slopcheck | Disposition |
|---------|----------|-----|----------|-------------|-----------|-------------|
| DrWatson | General | ~7 yrs | JuliaDynamics flagship | github.com/JuliaDynamics/DrWatson.jl | N/A (Julia) | Approved |
| CSV | General | ~8 yrs | JuliaData core | github.com/JuliaData/CSV.jl | N/A (Julia) | Approved |
| DataFrames | General | ~9 yrs | JuliaData core | github.com/JuliaData/DataFrames.jl | N/A (Julia) | Approved |
| JLD2 | General | ~8 yrs | JuliaIO core (transitive) | github.com/JuliaIO/JLD2.jl | N/A (Julia) | Approved (transitive) |

**Packages removed due to slopcheck [SLOP] verdict:** none.
**Packages flagged as suspicious [SUS]:** none. All four are long-established, high-adoption registry
packages verified present at the exact recommended pins in the local General clone.

## Architecture Patterns

### System Architecture Diagram

```
                          ┌────────────────────────────────────────────────┐
  researcher edits ─────► │  scripts/run_scenario.jl / scripts/sweep.jl     │
  (declarative)           │  @quickactivate "TSODSO"                        │
                          └───────────────┬────────────────────────────────┘
                                          │ Scenario(; feeder=:ieee13,
                                          │          strategy=:admm, seed=42, …)
                                          ▼
        ┌─────────────────────── run_scenario(s::Scenario) ───────────────────────┐
        │                                                                          │
        │  1. MATERIALIZE (deterministic in s.seed) ──────────────────────────┐    │
        │     feeder     = build_feeder(s.feeder)      # :ieee13→ieee13_modified()  │
        │     profiles   = generate_profiles(seed=sub_seed(s.seed,:profiles)) │    │
        │     λ₀         = build_price(s.price, s.T)                           │    │
        │     aggregators= build_population(s.pop, feeder, profiles,           │    │
        │                                   sub_seed(s.seed,:population))      │    │
        │     pf         = ConvexBranchFlow(...)                               │    │
        │                                                                     │    │
        │  2. DISPATCH on s.strategy ─────────────────────────────────────────┤    │
        │     :centralized → solve_welfare(feeder,pf,aggs; λ₀,T,allow_export)  │    │
        │                    → extract_dlmp(ctx)[load_buses,:] , exact_maxgap  │    │
        │     :admm        → solve_admm(feeder,pf,aggs; λ₀,ρ,ε_abs,…)          │    │
        │                    → (; welfare, dadp=λ, iters, residuals, maxgap)   │    │
        │                                                                     │    │
        │  3. NORMALIZE → ScenarioResult (node×T DADP, welfare, exact_maxgap,  │    │
        │     iters/final-resid[admm], timings[non-reproducible])             │    │
        └─────────────────────────────────┬───────────────────────────────────┘    │
                                          │                                         │
        ┌─────────────────────────────────┴──────── sweep layer ──────────────────┐ │
        │  dict_list(params) → [Scenario…] → run_scenario each                     │ │
        │                                                                          │ │
        │   ┌── per run ──────────────┐        ┌── aggregate ─────────────────────┐│ │
        │   │ @tagsave(datadir("sims",│        │ collect_results(datadir("sims")) ││ │
        │   │  savename(s,"jld2")),   │        │  → DataFrame → select scalars    ││ │
        │   │  result_dict)           │        │  → sort rows by savename         ││ │
        │   │  ↳ stamps :gitcommit    │        │  → CSV.write(committed summary)  ││ │
        │   │  (binary, GITIGNORED)   │        │  (text, DIFF-FRIENDLY, COMMITTED)││ │
        │   └─────────────────────────┘        └──────────────────────────────────┘│ │
        └──────────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure
```
TSODSO/
├── Project.toml            # + DrWatson, CSV, DataFrames under [deps]
├── src/
│   └── experiments/        # NEW — owned by this phase
│       ├── Scenario.jl     # immutable Scenario struct (primitive selectors) + validation
│       ├── materialize.jl  # build_feeder / build_price / build_population + sub_seed
│       ├── run.jl          # run_scenario dispatch + ScenarioResult + normalization
│       ├── store.jl        # @tagsave per-run + savename glue + provenance
│       └── sweep.jl        # dict_list sweep + collect_results → CSV summary
├── scripts/                # NEW — runnable entry points (DrWatson convention)
│   ├── run_scenario.jl     # @quickactivate "TSODSO"; single declarative run
│   └── sweep.jl            # @quickactivate "TSODSO"; parameter sweep
├── data/                   # NEW — DrWatson datadir(); GITIGNORED (binary artifacts)
│   └── sims/               # per-run .jld2 files (gitignored)
├── results/                # NEW — committed diff-friendly CSV summaries
│   └── sweeps/*.csv
└── test/
    └── test_experiments.jl # EXP-01/EXP-02/INFRA-04 + same-seed reproducibility gate
```
`src/experiments/` files are wired into `src/TSODSO.jl`'s include graph in dependency order (after
`pricing/` and `admm/`, since `run_scenario` calls `solve_welfare`/`solve_admm`/`extract_dlmp`).

### Pattern 1: Declarative selectors → deterministic materialization (EXP-01)
**What:** `Scenario` holds only primitive *selectors*; `run_scenario` materializes the heavy objects.
**When to use:** Always. This is the load-bearing decision for savename/hash/diff/reproducibility.
```julia
# Source: designed against verified Phase 1–7 signatures (solve_welfare, solve_admm, generate_profiles)
using DrWatson  # for @kwdef-friendly savename; @kwdef is Base

Base.@kwdef struct Scenario
    name::String                       # human label (also a savename component)
    feeder::Symbol      = :ieee13      # :ieee13 | :ieee123  (SELECTOR, not a Feeder)
    strategy::Symbol    = :centralized # :centralized | :admm
    seed::Int           = 1            # master seed → deterministic sub-seeds
    T::Int              = 24
    population::Symbol  = :default      # selects a build_population method
    price::Symbol       = :mem          # selects a build_price method
    allow_export::Bool  = true
    # ADMM-only knobs (ignored by the :centralized branch — kept for one flat schema)
    ρ::Float64          = 1.0
    ε_abs::Float64      = 1e-4
    ε_rel::Float64      = 1e-3
    maxiter::Int        = 200
    τ_ratio::Float64    = 2.0          # ADMM adaptive-ρ ratio (solve_admm `τ`)
    μ::Float64          = 10.0
end

function run_scenario(s::Scenario)
    feeder  = build_feeder(s.feeder)                       # :ieee13 -> ieee13_modified()
    profiles = generate_profiles(; seed = sub_seed(s.seed, :profiles), T = s.T)
    λ₀      = build_price(s.price, s.T, profiles)
    aggs    = build_population(s.population, feeder, profiles, sub_seed(s.seed, :population))
    pf      = ConvexBranchFlow(feeder)                     # SOCP formulation (Phase 4)

    if s.strategy === :centralized
        ctx, welfare, _ = solve_welfare(feeder, pf, aggs; T = s.T, λ₀,
                                        allow_export = s.allow_export)
        load_buses = sort!([a.bus for a in aggs])
        dadp    = extract_dlmp(ctx)[load_buses, :]          # normalize to node×T
        maxgap  = ctx.meta[:socp_maxgap]
        return ScenarioResult(s; welfare, dadp, exact_maxgap = maxgap,
                              iters = missing, final_r = missing, final_s = missing)
    elseif s.strategy === :admm
        r = solve_admm(feeder, pf, aggs; T = s.T, λ₀, ρ = s.ρ, maxiter = s.maxiter,
                       ε_abs = s.ε_abs, ε_rel = s.ε_rel, τ = s.τ_ratio, μ = s.μ,
                       allow_export = s.allow_export)
        return ScenarioResult(s; welfare = r.welfare, dadp = r.dadp,
                              exact_maxgap = r.exact_maxgap, iters = r.iters,
                              final_r = last(r.residuals.primal_trace),
                              final_s = last(r.residuals.dual_trace))
    else
        throw(ArgumentError("run_scenario: unknown strategy $(s.strategy); " *
                            "expected :centralized or :admm"))
    end
end
```

### Pattern 2: `dict_list` sweep (EXP-02)
**What:** Cartesian product of scenario parameters; scalars stay fixed, `Vector` values expand.
```julia
# Source: DrWatson dict_list — VERIFIED live https://juliadynamics.github.io/DrWatson.jl/stable/run&list/
params = Dict(
    :name     => "sweep1",
    :feeder   => :ieee13,
    :strategy => [:centralized, :admm],   # Vector → expanded (2 branches)
    :seed     => collect(1:5),            # Vector → expanded (5 branches)  ⇒ 10 runs total
    :T        => 24,
)
scenarios = [Scenario(; nt...) for nt in dict_list(params)]   # dict_list → Vector{Dict{Symbol,Any}}
```
`dict_list` returns a `Vector` of `Dict`s; splat each into the `@kwdef` `Scenario` constructor.
A value must be wrapped in a `Vector` to sweep; a bare scalar is held fixed. (To sweep over an
actual vector *value*, wrap it one level deeper: `[[1,2,3]]`.)

### Pattern 3: Two-tier storage — gitignored JLD2 + committed CSV summary (EXP-02)
**What:** Full per-run artifacts go to opaque binary JLD2 (gitignored); the scalar SUMMARY goes to
a deterministically-ordered CSV (committed, diff-friendly).
```julia
# Source: DrWatson @tagsave + collect_results (VERIFIED live); CSV.write/DataFrames idiom
using DrWatson, DataFrames, CSV

function run_and_store(s::Scenario)
    res  = run_scenario(s)
    dict = result_to_dict(res)                       # scalars + arrays, Symbol keys
    # @tagsave stamps :gitcommit (+ :gitpatch if storepatch & dirty) + :script; JLD2 binary.
    @tagsave(datadir("sims", savename(s, "jld2")), dict; storepatch = true)
    return res
end

function collate_summary(csvpath::String)
    df = collect_results(datadir("sims"))            # → DataFrame, one row per .jld2, + :path,:gitcommit
    keep = [:name, :feeder, :strategy, :seed, :T,    # DETERMINISTIC column order
            :welfare, :exact_maxgap, :iters, :final_r, :final_s, :gitcommit]
    df = select(df, intersect(keep, Symbol.(names(df))))
    sort!(df, [:feeder, :strategy, :seed])           # DETERMINISTIC row order — diff-friendly
    CSV.write(csvpath, df)                           # text, COMMITTED to results/sweeps/
    return df
end
```
**Diff-friendly rules (all three mandatory):** (1) fixed column order via explicit `select`;
(2) deterministic `sort!` by the scenario key columns; (3) **drop the `:path` column** — DrWatson's
`collect_results` adds an absolute machine-local path that is NOT reproducible and would churn the
diff. Keep `:gitcommit` (it is the provenance anchor).

### Pattern 4: `@quickactivate` script entry point (package-vs-project fit)
**What:** DrWatson works pointed at an existing **package** project — no `initialize_project` needed.
```julia
# Source: scripts/run_scenario.jl — DrWatson @quickactivate VERIFIED live
using DrWatson
@quickactivate "TSODSO"          # walks up to the repo-root Project.toml, activates it
using TSODSO
s = Scenario(name = "demo", feeder = :ieee13, strategy = :admm, seed = 42)
res = TSODSO.run_and_store(s)
```
`@quickactivate "TSODSO"` searches parent directories for the `Project.toml` named `TSODSO` and
activates it, so `projectdir()` == repo root and `datadir()` == `<repo>/data`. Do **NOT** call
`initialize_project` — that scaffolds a *new* project and would fight the existing package layout.
Create `data/` and `results/` manually (or let `datadir` create on first `mkpath`); gitignore `data/`.

### Anti-Patterns to Avoid
- **Storing built objects in `Scenario`** (`Feeder{Float64}`, `Vector{Aggregator}`, `λ₀::Vector`):
  breaks `savename` (needs `default_allowed` overloads), hashes unstably, cannot diff. Store selectors.
- **Putting `solve_time`/timings in the reproducibility equality check:** wall-clock is non-deterministic.
  Timings are a separate reporting column, never compared for bit-for-bit.
- **Relying on `projectdir()` inside tested code:** under the test env the active project is
  `test/Project.toml`, so `datadir()` points at `test/`. Pass an explicit `dir` argument (default
  `datadir("sims")`) so tests can use `mktempdir()`.
- **Committing JLD2 or the `collect_results` `:path` column:** binary/absolute-path churn, not diff-friendly.
- **Using the global RNG / `Random.seed!` anywhere in `build_population`:** leaks non-reproducibility;
  thread the sub-seeded `StableRNGs.LehmerRNG` (Pitfall 5).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Deterministic filename from a config | A hand-rolled hash/`join` of fields | `savename(s)` | Handles ordering, type filtering, float formatting, prefix/suffix consistently. |
| Git-commit provenance stamping | `read(\`git rev-parse HEAD\`)` glue | `@tagsave` / `tag!` | Handles dirty-tree gitpatch, gitpath discovery, and the `:script` stamp; robust to no-repo. |
| Cartesian parameter sweep | Nested `for` loops building Dicts | `dict_list(params)` | Correct scalar-vs-vector expansion, single-element edge cases. |
| Aggregating a results directory into a table | `readdir` + manual `load` + `push!` | `collect_results(dir)` | Auto-discovers heterogeneous param sets, fills `missing`, returns a `DataFrame`. |
| Skip-recompute caching | `isfile` checks + manual load/save | `@produce_or_load(f, config, path)` | Returns `(data, file)`, saves on miss, loads on hit — one call. |
| Binary result serialization | Custom format | JLD2 via DrWatson `wsave` | Versioned, portable, handles nested Julia types. |
| Radial root→bus path (for DLMP normalization) | A graph library (Graphs.jl) | existing `_path_branches` (Phase 5) | Already implemented; feeder is a validated radial tree. |

**Key insight:** DrWatson exists precisely to kill the ad-hoc "results/ dir + hand-named files + a
notebook that re-runs everything" pattern that plagues research code. Every function above replaces a
tempting hand-roll that silently loses provenance or reproducibility.

## Common Pitfalls

### Pitfall 1: `savename` on a struct with non-primitive fields
**What goes wrong:** `savename(scenario)` silently drops (or errors on) fields whose values aren't in
`default_allowed = (Real, String, SubString, Symbol, TimeType)`. A `Feeder{Float64}` field simply
vanishes from the name, so two different feeders produce the SAME filename → overwrite/collision.
**Why it happens:** `savename` filters field values by `default_allowed(::T)`; non-primitives are
excluded unless you overload `DrWatson.default_allowed`/`allaccess`/`default_expand`.
**How to avoid:** Keep every `Scenario` field a `Symbol`/`Int`/`Float64`/`Bool`/`String`. Then
`savename` works with zero overloading. (If a future selector must be non-primitive, overload
`DrWatson.default_allowed(::Scenario) = (Real, String, Symbol)` — verified API — but prefer selectors.)
**Warning signs:** Two runs with different feeders/strategies writing to the same `.jld2` path.

### Pitfall 2: `tagsave` does NOT stamp the Manifest (CLAUDE.md imprecision)
**What goes wrong:** Assuming `@tagsave` embeds the full environment. It stamps only `:gitcommit`
(+ `:gitpatch` when `storepatch=true` and the tree is dirty) and `:script`. A run recorded from a
checkout whose `Manifest.toml` later changed cannot be reproduced from the JLD2 alone.
**Why it happens:** `tag!` records the git commit, not package versions.
**How to avoid:** Rely on the **committed** `Manifest.toml` (INFRA-01, already committed) — the
`:gitcommit` stamp + that commit's `Manifest.toml` together pin the environment. Additionally store
`string(VERSION)` (Julia version) in the result dict, since the Manifest doesn't pin the Julia binary.
Use `storepatch=true` so an accidental dirty-tree run still captures its diff.
**Warning signs:** A reproduction attempt on a different commit yielding different numbers with no
recorded reason.

### Pitfall 3: JLD2 in git / `collect_results` `:path` column churn
**What goes wrong:** Committing the binary `.jld2` artifacts or the CSV's absolute `:path` column makes
every run churn the repo and defeats "diff-friendly."
**How to avoid:** Gitignore `data/`; drop `:path` before `CSV.write`; commit only the sorted scalar CSV.
**Warning signs:** Huge binary diffs; `results/*.csv` rows that differ only by an absolute path.

### Pitfall 4: Solver non-determinism breaking bit-for-bit (see §Solver Determinism)
**What goes wrong:** Multi-threaded BLAS (Ipopt/MUMPS) or multi-threaded HiGHS MILP reorders
floating-point reductions → last-ULP differences → `==` fails across runs/machines.
**How to avoid:** Run the reproducibility gate on the **Clarabel** (native-Julia, single-threaded IPM)
path; set `BLAS.set_num_threads(1)` and single-thread HiGHS if those paths are exercised; assert exact
`==` within a process / same machine, and tight `isapprox` (rtol 1e-8) across process restarts.
**Warning signs:** Same-seed test passing locally, flaking in CI on a different CPU.

### Pitfall 5: The seed not fully threaded (global-RNG leak)
**What goes wrong:** `generate_profiles` is already reproducible (seeds its own `LehmerRNG`), but if
`build_population` calls `rand()` (global RNG) for device placement/sizing, the run is NOT reproducible.
**How to avoid:** Derive **independent deterministic sub-seeds** from the master seed and thread a
`StableRNGs.LehmerRNG` into every stochastic builder. Never touch the global RNG / `Random.seed!`.
```julia
# Distinct, stable sub-streams so profiles and population don't accidentally couple or collide.
sub_seed(master::Integer, tag::Symbol) = hash((master, tag)) % typemax(UInt32) |> Int
```
Then `generate_profiles(; seed = sub_seed(s.seed, :profiles))` and
`build_population(...; rng = StableRNGs.LehmerRNG(sub_seed(s.seed, :population)))`.
**Warning signs:** Same-seed runs differing only when device population is randomized.

### Pitfall 6: `projectdir()`/`datadir()` resolving to the test env
**What goes wrong:** During `] test`, the active project is `test/Project.toml`, so `datadir()` points
at `test/data`, not the repo `data/`. Tests that write via `datadir()` litter the test env and are
non-hermetic.
**How to avoid:** Storage functions take an explicit `dir` keyword (default `datadir("sims")`); tests
pass `mktempdir()`. Keep `run_scenario` itself path-free (it returns a `ScenarioResult`; persistence is
a separate function).
**Warning signs:** Stray `.jld2` files under `test/` after a test run.

### Pitfall 7: Heavy dependency precompile / CI cost
**What goes wrong:** DrWatson pulls JLD2/FileIO/DataFrames/CSV — a non-trivial precompile added to
every `using TSODSO` and every CI job.
**How to avoid:** Accept it as a one-time tax (hard-dep decision). If it becomes painful, the documented
fallback is the weakdep-extension split (Alternatives Considered). Keep the CI matrix precompile cache
warm; do not add these to the *core* solve hot path.
**Warning signs:** CI time jumping; TTFX regressions on `using TSODSO`.

## Runtime State Inventory

> This is a **greenfield orchestration phase** (new `src/experiments/`, new `scripts/`, new deps) — no
> rename/refactor/migration of existing runtime state. The categories below are checked and confirmed empty.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no datastore renamed; `data/sims/` is newly created and gitignored. | None. |
| Live service config | None — no external service; local Julia bench only. | None. |
| OS-registered state | None — no daemons/tasks. | None. |
| Secrets/env vars | None — no secrets. `BLAS`/thread env may affect determinism (documented, not a rename). | None (document thread pinning only). |
| Build artifacts | New `[deps]` require re-resolving + committing main **and** `test/Manifest.toml` on 1.10/1.11/1.12; no stale artifact to clean. | `Pkg.resolve()` + commit both Manifests. |

**Nothing found in stored-data / service / OS / secrets categories** — verified: this phase only adds
new files and dependencies; it renames or migrates nothing.

## Solver Determinism (INFRA-04 core analysis)

| Solver | Path used | Deterministic? | Bit-for-bit conditions | Risk / mitigation |
|--------|-----------|----------------|------------------------|-------------------|
| **Clarabel** 0.11.1 | Primary SOCP/QP (welfare, ADMM DSO/AGR) | Yes — native-Julia IPM, single-threaded by default, no randomization | Same machine + same Julia + same Manifest → identical. Cross-process on same machine → identical. | Cross-machine/BLAS variation is last-ULP; Clarabel's core LDL is Julia-native but may call BLAS → assert `isapprox(rtol=1e-8)` cross-machine, `==` same machine. |
| **HiGHS** 1.24.1 | LP/MILP toy rungs only (not the operational sweep) | LP simplex deterministic single-threaded; **MILP branch-and-bound can be non-deterministic with threads** | Single-thread + presolve fixed | Not on the v1 operational reproducibility path; if used, force `threads=1`. `[CITED: HiGHS parallel MIP is non-deterministic by design]` |
| **Ipopt** 1.15.0 | NLP cross-check only (not the reproducibility gate) | Deterministic single-threaded; MUMPS + BLAS threading can perturb last ULP | `BLAS.set_num_threads(1)` | Only a cross-validation oracle; exclude from the bit-for-bit gate. |

**Prescription:** The INFRA-04 same-seed→identical gate runs the **Clarabel** path only, single-threaded,
in CI (fixed machine). Assert exact equality (`==`) of the *numerically deterministic* outputs
(`welfare`, `dadp`, `exact_maxgap`, `iters`) on repeated same-seed runs; **exclude timings** (wall-clock,
non-reproducible). For robustness across process restarts, a tight `isapprox(rtol=1e-8)` is the safe
assertion; document that within-process same-seed is truly bit-identical and cross-machine is
tolerance-bound. `[VERIFIED: Clarabel is native-Julia single-threaded IPM per CLAUDE.md stack notes;
solve_admm/solve_welfare confirmed to route through `select_optimizer(SOCP())`→Clarabel from source]`

## Code Examples

### DrWatson savename on the primitive-selector Scenario
```julia
# Source: DrWatson savename — VERIFIED live https://juliadynamics.github.io/DrWatson.jl/stable/name/
julia> s = Scenario(name="demo", feeder=:ieee13, strategy=:admm, seed=42, T=24);
julia> savename(s)                      # all fields primitive → no overloading needed
"T=24_allow_export=true_feeder=ieee13_maxiter=200_name=demo_seed=42_strategy=admm_..."
julia> savename(s, "jld2")              # with extension
"...strategy=admm.jld2"
```

### @tagsave provenance dict
```julia
# Source: DrWatson @tagsave/tag! — VERIFIED live https://juliadynamics.github.io/DrWatson.jl/stable/save/
dict = Dict(:welfare => res.welfare, :dadp => res.dadp,
            :exact_maxgap => res.exact_maxgap, :iters => res.iters,
            :julia_version => string(VERSION))          # Manifest gap workaround (Pitfall 2)
@tagsave(datadir("sims", savename(s, "jld2")), dict; storepatch = true)
# resulting dict now also carries :gitcommit, :gitpatch (if dirty), :script
```

### Reproducibility gate (the load-bearing INFRA-04 test)
```julia
# Source: designed against verified run_scenario + Clarabel determinism analysis
@testitem "INFRA-04 same-seed reproducibility through the full solve" begin
    using TSODSO
    s  = Scenario(name="repro", feeder=:ieee13, strategy=:centralized, seed=7)
    r1 = TSODSO.run_scenario(s)
    r2 = TSODSO.run_scenario(s)            # same seed, same process
    @test r1.welfare == r2.welfare          # bit-for-bit (same machine, single-thread Clarabel)
    @test r1.dadp   == r2.dadp
    @test r1.exact_maxgap == r2.exact_maxgap
    # a DIFFERENT seed must change the profile-driven result
    r3 = TSODSO.run_scenario(Scenario(name="repro", feeder=:ieee13, strategy=:centralized, seed=8))
    @test r3.dadp != r1.dadp
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Ad-hoc `results/` + hand-named files + a re-run-everything notebook | DrWatson `savename`/`tagsave`/`collect_results` project workflow | DrWatson mature since ~2019, 2.x current | Provenance and reproducibility become automatic, not manual. |
| `Requires.jl` for optional deps | Native `[weakdeps]`/`[extensions]` (Julia ≥ 1.9) | Julia 1.9 | Already used here (CairoMakie/Gurobi/Mosek ext); the fallback path for DrWatson if needed. |
| Global-RNG `Random.seed!` reproducibility | Explicit `StableRNGs.LehmerRNG` threaded per stream | StableRNGs adoption | Stable across Julia minors — the only cross-version-stable stream (already the Phase-3 convention). |

**Deprecated/outdated:** none relevant. `initialize_project` is fine for *new* projects but is the
wrong tool for this existing package (use `@quickactivate` instead).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Hard-dep (not weakdep) is the right call for DrWatson/CSV/DataFrames | Standard Stack / Alternatives | Low — reversible; weakdep fallback documented. Trades CI precompile for guaranteed provenance. |
| A2 | Clarabel is single-threaded & deterministic enough for exact `==` same-machine same-seed | Solver Determinism | Medium — if Clarabel calls multi-threaded BLAS internally, relax gate to tight `isapprox`. Mitigation already stated. |
| A3 | `build_population` may need randomness (device placement/sizing); sub-seed threading required | Pitfall 5 | Low — if the population spec is fully deterministic (no `rand`), sub-seed for `:population` is simply unused; no harm. |
| A4 | `collect_results` adds an absolute `:path` column that must be dropped for diff-friendliness | Pattern 3 / Pitfall 3 | Low — verified behavior; if column name differs, the `select(intersect(...))` guard tolerates it. |
| A5 | `ScenarioResult` normalizes ADMM `dadp` (already node×T) and centralized `extract_dlmp(ctx)[load_buses,:]` to the same shape | Pattern 1 | Low — solve_admm docstring explicitly states this match; verified from source. |

## Open Questions

1. **Exact `==` vs. tight `isapprox` for the reproducibility gate.**
   - What we know: within one process on the Clarabel single-threaded path, same-seed runs are
     bit-identical; wall-clock timings never are.
   - What's unclear: whether Clarabel's internal linear algebra invokes multi-threaded BLAS such that
     cross-process/cross-CPU runs differ at the last ULP.
   - Recommendation: assert `==` for same-process (guaranteed), and provide an `isapprox(rtol=1e-8)`
     variant for cross-process/CI-matrix; pick `==` for the primary gate and downgrade only if it flakes.

2. **Does `build_population` for the default feeders need any randomness at all?**
   - What we know: the Phase-4 fixtures build aggregators deterministically from seeded profiles.
   - What's unclear: whether the harness's declarative population spec introduces random placement.
   - Recommendation: keep the `:population` sub-seed plumbed even if unused now — future stochastic
     populations get reproducibility for free.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | Everything | ✓ | 1.10 LTS / 1.11 / 1.12 target (project) | — |
| git | `@tagsave` provenance (INFRA-04) | ✓ | repo is a git checkout (verified) | tagsave degrades gracefully with no repo (no gitcommit) — but repo present. |
| DrWatson 2.19.1 | harness core | ✗ (not yet added) | 2.19.1 in registry | none — must add (`Pkg.add`). |
| CSV 0.10.16 | summary table | ✗ (not yet added) | 0.10.16 in registry | none — must add. |
| DataFrames 1.8.2 | collation | ✗ (not yet added) | 1.8.2 in registry | none — must add. |
| StableRNGs 1.0.4 | seed stream | ✓ (existing `[dep]`) | 1.0.4 | — |
| Clarabel/HiGHS/Ipopt | solve path | ✓ (existing `[deps]`) | pinned | — |

**Missing dependencies with no fallback:** DrWatson, CSV, DataFrames — the phase's first task must
`Pkg.add` them and re-resolve/commit main + `test/Manifest.toml` on 1.10/1.11/1.12.
**Missing dependencies with fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `TestItems` 1.0.0 + `TestItemRunner` 1.1.5 (`@testitem`), stdlib `Test` |
| Config file | `test/runtests.jl` (TestItemRunner driver); per-file `@testitem`s |
| Quick run command | `julia --project -e 'using TestItemRunner; @run_package_tests filter=ti->occursin("experiment", ti.name)'` |
| Full suite command | `julia --project -e 'using Pkg; Pkg.test()'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EXP-01 | Declarative `Scenario` runs end-to-end on `:centralized` | integration | `@run_package_tests filter=ti->occursin("EXP-01 centralized", ti.name)` | ❌ Wave 0 |
| EXP-01 | Same `Scenario` runs end-to-end on `:admm` | integration | `@run_package_tests filter=ti->occursin("EXP-01 admm", ti.name)` | ❌ Wave 0 |
| EXP-01 | Unknown strategy throws `ArgumentError` | unit | `filter=ti->occursin("EXP-01 strategy guard", ti.name)` | ❌ Wave 0 |
| EXP-02 | `dict_list` sweep produces N scenarios; each runs | integration | `filter=ti->occursin("EXP-02 sweep", ti.name)` | ❌ Wave 0 |
| EXP-02 | Summary CSV has deterministic column/row order; no `:path` col; two collations byte-identical | unit | `filter=ti->occursin("EXP-02 diff-friendly", ti.name)` | ❌ Wave 0 |
| INFRA-04 | Same seed → identical welfare/dadp/maxgap through the full solve | integration | `filter=ti->occursin("INFRA-04 same-seed", ti.name)` | ❌ Wave 0 |
| INFRA-04 | Different seed → different result | integration | `filter=ti->occursin("INFRA-04 seed sensitivity", ti.name)` | ❌ Wave 0 |
| INFRA-04 | `@tagsave` output carries `:gitcommit` | unit | `filter=ti->occursin("INFRA-04 provenance", ti.name)` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** the experiment-filtered `@run_package_tests` (fast subset).
- **Per wave merge:** full `Pkg.test()` (ensures new deps didn't break Phase 1–7).
- **Phase gate:** full suite green before `/gsd:verify-work`; INFRA-04 same-seed test is the mandatory gate.

### Wave 0 Gaps
- [ ] `test/test_experiments.jl` — the `@testitem`s above (EXP-01/EXP-02/INFRA-04).
- [ ] `test/fixtures_phase8.jl` (optional) — a tiny `@testmodule` giving a minimal `Scenario` and a
  `mktempdir` storage dir helper (hermetic tests, avoids Pitfall 6).
- [ ] Add DrWatson/CSV/DataFrames to `test/Project.toml` `[deps]` and re-resolve `test/Manifest.toml`.
- [ ] Add DrWatson/CSV/DataFrames to root `Project.toml` `[deps]` + `[compat]` and re-resolve main Manifest.

## Security Domain

> The project has no `security_enforcement` key in `.planning/config.json` (treated as enabled), but this
> is a **local single-user research bench** with no auth, no network endpoints, no user-supplied runtime
> input, and no PII. Most ASVS categories are N/A. The only relevant surface is supply-chain +
> deserialization.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth surface. |
| V3 Session Management | no | No sessions. |
| V4 Access Control | no | Local files only. |
| V5 Input Validation | partial | `Scenario` constructor + `run_scenario` guard invalid selectors/strategies (throw, not silent). |
| V6 Cryptography | no | No crypto. |
| V10 Malicious Code / Supply Chain | yes | New deps verified against the curated General registry at pinned versions; committed Manifest pins the tree. |
| V12 Deserialization | yes | `collect_results`/JLD2 loads **only** artifacts this project wrote into its own gitignored `data/`; never load untrusted `.jld2`. |

### Known Threat Patterns for a Julia research harness
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Untrusted JLD2 deserialization executing arbitrary types | Tampering / Elevation | Load only self-produced artifacts from `data/sims/`; never `wload` external files. |
| Dependency substitution / typosquat | Tampering | Curated General registry + pinned committed Manifest; verified pins this session. |
| Silent bad scenario config → wrong-but-plausible result | Repudiation | Throw-based validation in `Scenario`/`run_scenario`; PF-04 exactness gate refuses bad duals. |

## Sources

### Primary (HIGH confidence)
- Local General registry clone `~/.julia/registries/General/{D,C,J,F}/…/Versions.toml` — verified pins
  DrWatson 2.19.1, CSV 0.10.16, DataFrames 1.8.2, JLD2 0.6.5, FileIO 1.20.0 (2026-07-19).
- DrWatson.jl docs (live, 2026-07-19): `/stable/save/` (tagsave, @tagsave, produce_or_load, safesave),
  `/stable/name/` (savename, allaccess/access/default_allowed/default_prefix/default_expand),
  `/stable/run&list/` + `/stable/workflow/` (dict_list, collect_results, quickactivate, projectdir,
  initialize_project, directory structure).
- Project source (read this session): `src/models/welfare_solve.jl`, `src/admm/solve_admm.jl`,
  `src/models/oracle.jl`, `src/data/profiles.jl`, `src/pricing/dlmp.jl`, `src/models/exactness.jl`,
  `src/solver/factory.jl`, `src/devices/Aggregator.jl`, `ext/TSODSOMakieExt.jl`, `Project.toml`,
  `test/Project.toml`, `.gitignore`.

### Secondary (MEDIUM confidence)
- CLAUDE.md Technology Stack (DrWatson as backbone, weakdep pattern, solver mapping) — cross-checked
  against source and registry.

### Tertiary (LOW confidence)
- HiGHS parallel-MILP non-determinism (general solver knowledge; not on the v1 operational path so not
  gate-critical) — `[CITED]`, flagged, not load-bearing.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all three pins verified in the local General registry; DrWatson API re-verified live.
- Architecture: HIGH — `run_scenario` dispatch designed against verified `solve_welfare`/`solve_admm`
  signatures read from source; DADP normalization confirmed by the `solve_admm` docstring.
- Pitfalls: HIGH — savename/tagsave behavior verified live; seed-threading grounded in `profiles.jl` source.
- Solver determinism: MEDIUM — Clarabel single-threaded determinism is well-founded but exact-`==`
  cross-machine is the one item flagged for validation at implementation time.

**Research date:** 2026-07-19
**Valid until:** 2026-08-18 (30 days — stable ecosystem; re-check DrWatson pin if a 2.20 lands).
</content>
</invoke>
