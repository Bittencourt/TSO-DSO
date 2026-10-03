# Phase 32: Declarative Power-Flow & Strategy Dispatch - Research

**Researched:** 2026-10-03
**Domain:** Julia API restructuring (Scenario struct, strategy types, multiple dispatch) over an existing JuMP research framework. Pure orchestration, no new model or solver.
**Confidence:** HIGH (every behavioral claim below was measured against the live repo on Julia 1.12.5, or read from source with file:line)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Power-Flow Selection in Scenario**
- Representation: primitive `pf::Symbol` selector (default `:convex_branch_flow`) plus primitive option fields (`pf_thesis_literal::Bool`, `pf_ε::Float64`), materialized by a new `build_powerflow(s)` in `materialize.jl`. Preserves the "Scenario holds only primitives → savename works" invariant (Phase 8).
- Selectable set: `:convex_branch_flow` (default; `thesis_literal` option), `:restricted_branch_flow` (`ε`), `:lindistflow`, `:ac`. `MeshedFlow` NOT exposed (needs a meshed feeder, not a Scenario selector yet). `DCPowerFlow` not exposed.
- Invalid strategy × pf combos (e.g. `ADMM` + `:lindistflow`/`:ac`) throw `ArgumentError` at `Scenario` construction (ADMM accepts only SOCP-family formulations until Phase 34 / ARCH-05).
- `exact_maxgap` for non-cone formulations (`:lindistflow`, `:ac`) is `NaN`, documented as "not applicable" — keeps the common `Float64` result shape.

**Strategy Types & Entry Point**
- `abstract type AbstractStrategy`; concrete structs carry their own knobs and validate in their constructors (validation moves out of `Scenario`): `Centralized()`, `ADMM(; ρ, ε_abs, ε_rel, maxiter, τ_ratio, μ)`, `MPC(; H, step, terminal_soc, forecast_error)`, `Stochastic(; S, probabilities, H_oos)`. Defaults identical to today's flat-field defaults (incl. `ρ = 100.0`, probabilities empty-sentinel → uniform, defensive copy).
- Entry point: `run(strategy::AbstractStrategy, s::Scenario)` as package-owned `TSODSO.run`, NOT exported (avoid `Base.run` collision); documented as `TSODSO.run(...)`.
- `run_scenario`, `run_mpc`, `run_stochastic` kept as thin wrappers (no deprecation) so all existing tests/docs/goldens keep working. `run_scenario(s)` dispatches on `s.strategy`.
- `Scenario` holds `strategy::AbstractStrategy` (default `Centralized()`); `run(s) = run(s.strategy, s)`.

**Scenario Restructure & Compatibility**
- Legacy flat kwargs (`Scenario(; strategy = :admm, ρ = 50.0, mpc_H = 6, …)`) keep working via an outer kwarg constructor that maps `strategy::Symbol` + flat knobs to the strategy struct. Passing a knob foreign to the chosen strategy (e.g. `mpc_H` with `:centralized`) throws `ArgumentError`. In-repo tests/docs migrate to the new form.
- Filename identity: `scenario_filename` flattens the strategy to prefixed primitive fields (`strategy=ADMM`, `admm_ρ=…`), keeping `digits = 10`, `safe = true`, and the non-uniform probability FNV-1a digest. Only the active strategy's knobs appear (shorter names — also relieves the NAME_MAX pressure noted in store.jl).
- Goldens: every NUMERIC golden must be bit-identical — this phase is pure orchestration/dispatch, no model change. Only savename/filename STRINGS change (documented, accepted).
- New file `src/experiments/strategies.jl`, included before `Scenario.jl`; `run` methods co-located with each existing entry point (`run.jl`, `mpc_loop.jl`, `run_stochastic.jl`).

**Common Result Shape**
- Every strategy returns `ScenarioResult`: common fields `scenario`, `welfare`, `dadp`, `exact_maxgap`, `elapsed` + typed strategy-specific `details` (ADMM: iters/final_r/final_s/reactive_consensus_mode; MPC: regret/trace/…; Stochastic: in_sample/oos).
- Headline mapping: MPC → `welfare = realized_welfare` (truth-settled), `dadp` = published DADP; Stochastic → `welfare = in_sample.welfare` (expected), `dadp = expected_dadp`. Documented.
- Existing ADMM fields stay accessible: `getproperty` forwarding keeps `r.iters`, `r.final_r`, `r.final_s`, `r.reactive_consensus_mode` working; `result_to_dict` updated accordingly.
- `run_mpc`/`run_stochastic` keep returning their current NamedTuples (goldens untouched); `run(::MPC, s)` / `run(::Stochastic, s)` wrap them into `ScenarioResult`.

### Claude's Discretion
- Exact concrete type of `details` (per-strategy NamedTuple vs small structs), as long as it is type-stable enough for JET and serializable by `result_to_dict`.

### Deferred Ideas (OUT OF SCOPE)
- `solve_admm` accepting any `AbstractPowerFlow` (ARCH-05 → Phase 34); lift the ADMM×pf construction-time restriction then.
- Meshed feeder / `MeshedFlow` as a `Scenario` selector (after Phase 33's `AbstractFeeder`).
- Removing the legacy flat-kwarg constructor (a later cleanup, e.g. Phase 36).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ARCH-01 | Select power-flow formulation declaratively in `Scenario`; `run_scenario` honours it; nothing hard-coded to `ConvexBranchFlow()` | Three hard-codes located (run.jl:112, mpc_loop.jl:298, run_stochastic.jl:151). Per-pf behaviour of `solve_welfare`/`extract_dlmp`/`:socp_maxgap` measured (see "Measured pf behaviour"). Two latent bugs found that the pf wiring must guard: LinDistFlow has no `:socp_maxgap` (KeyError), AC needs `allow_local = true`. |
| ARCH-02 | Strategies are types dispatched by one `run(strategy, scenario)` returning a common shape; `Scenario` no longer a flat bag | Strategy type design, ScenarioResult reshaping, legacy-kwarg constructor, filename flattening, wrapper plan, caller inventory. |
</phase_requirements>

## Summary

The phase is a refactor of `src/experiments/*.jl` plus ~50 call sites. No model or solver code changes. Three entry points exist today with three different return shapes: `run_scenario` (`ScenarioResult`, strategies `:centralized`/`:admm` only), `run_mpc` (NamedTuple), `run_stochastic` (NamedTuple). `Scenario` is a 21-field `@kwdef` struct with ADMM/MPC/Stochastic knobs flattened in (Scenario.jl:~128-150). Three places hard-code `pf = ConvexBranchFlow()`.

Measured findings that CHANGE or refine CONTEXT.md (planner must apply these):

1. **ADMM silently ignores `pf`.** `solve_admm` is typed `pf::ConvexBranchFlow` (solve_admm.jl:241) but the body never reads `pf`; `build_dso_opt` hard-codes `contribute!(ConvexBranchFlow(), ...)` (DsoOpt.jl:396). `RestrictedBranchFlow` is NOT a subtype of `ConvexBranchFlow`, so `:restricted_branch_flow` + ADMM would be a `MethodError`, and `pf_thesis_literal = true` + ADMM would be silently ignored. So "SOCP-family" in CONTEXT must be tightened: **ADMM accepts only `pf = :convex_branch_flow` with `pf_thesis_literal = false`** until ARCH-05.
2. **MPC and Stochastic break on every non-default pf** (measured, T=24 ieee13): Stochastic + `RestrictedBranchFlow` throws battery-complementarity (τ=1e-3); + `LinDistFlow` throws battery-complementarity; + `ACPowerFlow` throws solve_with_retry exhaustion. MPC window with AC throws at solve; with LinDistFlow it builds and solves but the per-resolve certificate (`_mpc_certify_and_price`, mpc_loop.jl:865-874) and warm-start (mpc_loop.jl:698-709) read `pf_vars.l`, absent under LinDistFlow. **Recommend: ADMM, MPC, Stochastic accept only `:convex_branch_flow` (default options) at construction; Centralized accepts all four.** Loosening later is cheap; a silently wrong run is not.
3. **Centralized + each pf (measured)**: convex OK; convex+thesis_literal OK (maxgap 8.3e-9); restricted OK (maxgap 2.2e-8); lindistflow solves and `extract_dlmp` works (11×24) but **`ctx.meta[:socp_maxgap]` is ABSENT, so `run.jl:105` (`ctx.meta[:socp_maxgap]`) would throw KeyError**; ac **throws** with `solve_welfare`'s default (LOCALLY_SOLVED is refused unless `allow_local = true`), works with `allow_local = true`, and then stashes a near-zero `:socp_maxgap` (2.7e-9) via the documented ":l-keyed double-fire" (ACPowerFlow.jl:30-34), which is NOT the "NaN, not applicable" CONTEXT specifies, so run_scenario must override it to `NaN`.
4. **The common `dadp` shape cannot be `(n_load_nodes × T)` for MPC/Stochastic.** MPC publishes one price per published hour (`trace.dadp_trace`, length `T-H+1`); Stochastic's `expected_dadp` is a length-`T` vector at the first aggregator's bus. Recommend `dadp::Matrix{Float64}` stays the type, with MPC/Stochastic as a `1 × n` matrix (`reshape(v, 1, :)`), documented as "single priced-bus row"; the full vectors/matrices live in `details`.
5. **`savename` silently drops a nested `strategy::AbstractStrategy` field** (verified: `savename(Sc("a", A1(1.0), 3), "jld2")` → `"T=3_name=a.jld2"`). `scenario_filename` MUST build its name from an explicit flattened `Dict` (`savename(::Dict, "jld2"; digits=10)` works, keys sorted alphabetically; verified). Also today's filename already exceeds the 255-byte NAME_MAX for every Scenario (245-byte stem hits the `_h<hash>` fallback even for `name="x"`, measured), so flattening only the active strategy materially helps.
6. **Legacy-kwarg strictness breaks existing in-repo usage by design**: today `Scenario(; mpc_H = 3, ...)` + `run_mpc(s)` works on a `:centralized` Scenario. Under the locked "foreign knob throws" rule, ~20 sites must migrate (inventory below). `run_mpc(s)` / `run_stochastic(s)` wrappers must define what happens when `s.strategy` is not `MPC`/`Stochastic` (recommend: use `MPC()`/`Stochastic()` defaults, so `run_mpc(Scenario(name=..))` keeps working).

**Primary recommendation:** Implement in 3 waves: (W1) `strategies.jl` + new `Scenario` + `build_powerflow` + legacy constructor + `scenario_filename`/`result_to_dict`/`collate_summary` flattening, with a legacy-vs-new equivalence test; (W2) `ScenarioResult` reshape + `run(::Centralized/ADMM)` with pf wiring + guards, then `run(::MPC)`/`run(::Stochastic)` extracted from the existing bodies (bodies unchanged except `pf` and knob reads); (W3) migrate callers/docs/scripts, `api.md` Pages, full-suite gate (31260/0/0/5).

## Project Constraints (from CLAUDE.md)

- Julia + JuMP; no new packages are needed or allowed to be assumed (this phase adds ZERO dependencies).
- Solver names must not appear in orchestration code (INFRA-02): `run.jl` etc. route through `select_optimizer`/`solve_welfare`; do not name Clarabel/HiGHS/Ipopt in new code.
- Validation = `throw(ArgumentError(...))`, never `@assert` (Scenario.jl convention, threat T-08-05).
- Reproducibility: seeded via `sub_seed`; same-seed bit-for-bit (INFRA-04) must hold.
- Documentation is a hard requirement: every new exported symbol needs a docstring, and `docs/make.jl` has `checkdocs = :exports` (a documented-but-unsurfaced exported symbol FAILS the docs build). Every `@autodocs` block must keep `:constant` in `Order`.
- Clean idiomatic code, JuliaFormatter 2.x config committed; Aqua must pass (see Aqua section).
- GSD workflow: repo edits go through GSD commands (not relevant to the researcher, relevant to executors).
- Memory-note constraints (test execution): see "Validation Architecture".

## Architectural Responsibility Map

(Single-process Julia library; "tiers" are the library's own layers.)

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Strategy knob types + validation | `experiments/strategies.jl` (new) | — | Validation moves out of `Scenario` into strategy constructors (locked). |
| pf selector → `AbstractPowerFlow` object | `experiments/materialize.jl` (`build_powerflow`) | `Scenario` (primitive fields only) | Mirrors `build_feeder`/`build_price`: Scenario holds primitives, materialize builds heavy objects. |
| strategy × pf compatibility check | `Scenario` inner constructor | strategies (a per-strategy `supports_pf` trait) | Needs both fields; must throw at construction (locked). |
| Entry point + dispatch | `TSODSO.run(strategy, scenario)` methods co-located with `run.jl`/`mpc_loop.jl`/`run_stochastic.jl` | `run_scenario`/`run_mpc`/`run_stochastic` wrappers | Locked. |
| Common result | `ScenarioResult` (`run.jl`) | per-strategy `details` | Locked. |
| On-disk identity | `store.jl` `scenario_filename` + `result_to_dict` | `sweep.jl` `collate_summary` column lists | Only place that serializes Scenario identity. |

## Standard Stack

No new packages. Everything below is already in `Project.toml`.

### Core
| Library | Version (repo) | Purpose | Why |
|---------|----------------|---------|-----|
| Julia | 1.12.5 local (compat floor 1.10) | language | Code must stay 1.10-compatible: avoid `public` keyword (1.11+), avoid newer syntax. [VERIFIED: `julia --version`] |
| DrWatson | 2.19.1 | `savename`, `@tagsave`, `dict_list`, `struct2dict` | Existing identity mechanism. [CITED: CLAUDE.md stack table] |
| JuMP / Clarabel / Ipopt | existing | unchanged | No model change. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-written flattened `Dict` for filenames | `DrWatson.default_allowed(::Scenario)` / `DrWatson.allaccess` overloads | CLAUDE.md/Scenario.jl invariant: ZERO `default_allowed` overloading. A flatten-to-Dict helper in `store.jl` keeps that invariant and also controls "active knobs only". Use the Dict. |
| `details` as `NamedTuple` | small concrete structs (`ADMMDetails`, `MPCDetails`, `StochasticDetails`) | Structs are JET-friendly, documentable via autodocs, and give `getproperty` forwarding a type to dispatch on. Recommend structs, with `ScenarioResult.details::Union{Nothing,ADMMDetails,MPCDetails,StochasticDetails}` (small-union, JET-friendly). |

**Installation:** none.

## Package Legitimacy Audit

No external packages are installed or recommended in this phase. **Packages removed:** none. **Flagged [SUS]:** none. slopcheck not applicable.

## Architecture Patterns

### System Architecture Diagram

```
Scenario(; flat kwargs | strategy=Struct)  --(outer ctor maps legacy kwargs -> strategy struct; foreign knob => ArgumentError)-->
        |
        v  inner ctor: validate selectors, pf option ranges, strategy x pf compatibility (ArgumentError)
   Scenario{name,feeder,seed,T,population,price,allow_export, pf, pf_thesis_literal, pf_ε, strategy::AbstractStrategy}
        |
        +-- run_scenario(s) -----------------------+
        +-- run(s) = run(s.strategy, s) -----------+--> run(st, s)  [st wins; result.scenario = with_strategy(s, st)]
        +-- run_mpc(s) / run_stochastic(s) (wrap) -+       |
                                                            v   materialize: build_feeder, generate_profiles(sub_seed),
                                                                 build_price, build_population, build_powerflow(s)
              +-----------------+-----------------+-----------------+
              v                 v                 v                 v
        run(::Centralized)  run(::ADMM)      run(::MPC)       run(::Stochastic)
        solve_welfare       solve_admm       _run_mpc body    _run_stochastic body
        (+allow_local for   (pf=Convex only) (pf=Convex only) (pf=Convex only)
         AC; maxgap guard)
              \                 |                 |                 /
               +-----> ScenarioResult(scenario, welfare, dadp, exact_maxgap, elapsed, details)
                                   |
         run_and_store -> result_to_dict (flatten strategy/details to primitives) -> @tagsave(scenario_filename(s))
         run_sweep: Dict -> Scenario(; legacy flat keys) -> run_and_store ; collate_summary (column lists)
```

### Recommended Project Structure
```
src/experiments/
├── strategies.jl     # NEW: AbstractStrategy, Centralized, ADMM, MPC, Stochastic, `function run end`, supports_pf, with_strategy-free helpers
├── Scenario.jl       # restructured Scenario (+ outer legacy kwarg ctor), SCENARIO_VALID_PFS
├── materialize.jl    # + build_powerflow(s::Scenario)
├── run.jl            # ScenarioResult (+details, getproperty), run(::Centralized), run(::ADMM), run_scenario, run(s)
├── mpc_loop.jl       # run(::MPC, s) wrapper around existing run_mpc body
├── run_stochastic.jl # run(::Stochastic, s) wrapper
├── store.jl          # scenario_filename / result_to_dict flatten
└── sweep.jl          # collate_summary column lists
```
`TSODSO.jl` include order: `strategies.jl` before `Scenario.jl` (TSODSO.jl:227 region). `run.jl` is included BEFORE `mpc_loop.jl`/`run_stochastic.jl` (TSODSO.jl:229 vs 238/247), so `run_scenario`'s MPC/Stochastic branch calls `run(::MPC,…)` defined later: fine at runtime (generic function), but `ScenarioResult`'s `details` types for MPC/Stochastic must be defined in `strategies.jl` or `run.jl`, not in the later files.

### Pattern 1: Strategy types owning their validation
```julia
# strategies.jl  (sketch; names are the locked ARCH-02 names)
abstract type AbstractStrategy end
struct Centralized <: AbstractStrategy end
struct ADMM <: AbstractStrategy
    ρ::Float64; ε_abs::Float64; ε_rel::Float64; maxiter::Int; τ_ratio::Float64; μ::Float64
    function ADMM(ρ, ε_abs, ε_rel, maxiter, τ_ratio, μ)   # inner ctor: the SAME checks/messages as Scenario.jl today
        ρ > 0 || throw(ArgumentError("ADMM: ρ must be > 0 (ADMM penalty); got ρ=$ρ"))
        # ... ε_abs/ε_rel > 0, τ_ratio/μ > 0, maxiter ≥ 1
        new(ρ, ε_abs, ε_rel, maxiter, τ_ratio, μ)
    end
end
ADMM(; ρ=100.0, ε_abs=1e-4, ε_rel=1e-3, maxiter=200, τ_ratio=2.0, μ=10.0) = ADMM(ρ, ε_abs, ε_rel, maxiter, τ_ratio, μ)
# Stochastic: probabilities empty-sentinel -> fill(1/S, S); non-empty validated then copy()'d (WR-01 aliasing fix).
function run end          # TSODSO.run — NOT exported
```
Keep the existing error-message text (tests only check `ArgumentError`, but docs quote messages). Constructor argument types are `Float64`/`Int` strictly today (positional inner ctor); keep the kwarg ctor converting (`Float64(ρ)`) so `ρ = 50` (Int) works as it does via `@kwdef` today? NOTE: today `Scenario(; ρ = 50)` would throw `MethodError` (inner ctor requires Float64; `@kwdef` does not convert). Do not widen behaviour accidentally; converting is a harmless superset.

### Pattern 2: pf as primitive selector + materialization
```julia
const SCENARIO_VALID_PFS = (:convex_branch_flow, :restricted_branch_flow, :lindistflow, :ac)
function build_powerflow(s::Scenario)
    s.pf === :convex_branch_flow     && return ConvexBranchFlow(; thesis_literal = s.pf_thesis_literal)
    s.pf === :restricted_branch_flow && return RestrictedBranchFlow(; ε = s.pf_ε)
    s.pf === :lindistflow            && return LinDistFlow()
    s.pf === :ac                     && return ACPowerFlow()      # limits = true (default) — see Pitfall 3
    throw(ArgumentError("build_powerflow: unknown pf selector $(repr(s.pf)); expected one of $(SCENARIO_VALID_PFS)"))
end
```
`ConvexBranchFlow(; thesis_literal = false)` is a struct with one `Bool`, so `build_powerflow` for the default yields a value `==`/behaviour-identical to today's `ConvexBranchFlow()` (struct is isbits; `===`) — bit-identity of goldens holds. `RestrictedBranchFlow(; ε)` validates `ε ≥ 0` itself (RestrictedBranchFlow.jl:~160), but validate `pf_ε ≥ 0` in `Scenario` too so the error is at construction. `build_powerflow` takes `s::Scenario` (CONTEXT) — the function is dispatch-light; do not add a trait.

### Pattern 3: Centralized + non-SOCP pf (the guards)
```julia
# inside run(::Centralized, s)  — replaces run.jl:92-120 body
pf = build_powerflow(s)
ctx, welfare, _ = solve_welfare(feeder, pf, aggs; T = s.T, λ₀ = λ₀, allow_export = s.allow_export,
                                allow_local = pf isa ACPowerFlow)         # AC: Ipopt LOCALLY_SOLVED
maxgap = (pf isa Union{ConvexBranchFlow,RestrictedBranchFlow}) ? Float64(ctx.meta[:socp_maxgap]) : NaN
```
`allow_local` is a `solve_welfare` kwarg (welfare_solve.jl:25). For `ConvexBranchFlow`/`LinDistFlow`/`RestrictedBranchFlow` leaving it `false` keeps the existing call byte-identical. Use `get(ctx.meta, :socp_maxgap, NaN)` only if combined with the explicit AC override; an explicit `isa` check is clearer and prevents the AC near-zero value leaking.

### Pattern 4: `ScenarioResult` with details and forwarding
```julia
struct ScenarioResult
    scenario::Scenario
    welfare::Float64
    dadp::Matrix{Float64}
    exact_maxgap::Float64
    elapsed::Float64
    details::Union{Nothing,ADMMDetails,MPCDetails,StochasticDetails}
end
function Base.getproperty(r::ScenarioResult, name::Symbol)
    name in (:iters, :final_r, :final_s, :reactive_consensus_mode) || return getfield(r, name)
    d = getfield(r, :details)
    return d isa ADMMDetails ? getfield(d, name) : missing     # centralized/MPC/stochastic => missing
end
Base.propertynames(r::ScenarioResult, private::Bool=false) = (fieldnames(ScenarioResult)..., :iters, :final_r, :final_s, :reactive_consensus_mode)
```
CRITICAL: forwarded ADMM fields must return `missing` (not throw) for non-ADMM results — `test_experiments.jl:42,47` assert `ismissing(r1.iters)` / `ismissing(r1.reactive_consensus_mode)` for `:centralized`, and `src/experiments/store.jl:138-141` / `scripts/run_scenario.jl:22` read `res.iters` unconditionally.

### Anti-Patterns to Avoid
- **`Base.@kwdef` on the new `Scenario`**: it defines a `Scenario(; fields...)` method that collides with the hand-written legacy kwarg constructor (same signature → method overwrite/precompile error). Write the outer kwarg constructor by hand; drop `@kwdef`.
- **Keeping the strategy as a `savename` field**: silently dropped (verified). Always go through the flattened-Dict helper.
- **`struct2dict(s)` / storing strategy objects in the JLD2 dict**: custom struct instances round-trip through JLD2 only if the type is loadable at read time; `collect_results` in `collate_summary` would then yield opaque columns. Flatten to primitives.
- **Rebuilding the legacy-kwarg → strategy mapping in two places** (Scenario outer ctor and `run_sweep`): `run_sweep` must keep calling `Scenario(; nt...)` so there is exactly one mapping.
- **Re-implementing `run_mpc`/`run_stochastic` bodies**: extract the body into an internal function taking the strategy struct (e.g. `_run_mpc(s, st::MPC; _truth_settlement)`), keep `run_mpc(s; _truth_settlement)` as the wrapper. Replace only `pf = ConvexBranchFlow()` → `build_powerflow(s)` and `s.mpc_*`/`s.stoch_*` reads → `st.H` etc. 90+ read sites in mpc_loop.jl; use a mechanical, reviewable substitution, and keep the NamedTuple return byte-identical.

## Measured pf behaviour (ieee13, `:default` population, T=24, seed 1; probe script `scratchpad/pf_probe.jl`)

| pf | `solve_welfare` default kwargs | `extract_dlmp` | `ctx.meta[:socp_maxgap]` | Notes |
|----|-------------------------------|----------------|--------------------------|-------|
| `ConvexBranchFlow()` | OK, welfare -4823.5269334868735 | OK (11,24) | 1.1e-8 | baseline (first call includes ~35 s compile) |
| `ConvexBranchFlow(thesis_literal=true)` | OK, -4823.5269332955895 | OK | 8.3e-9 | |
| `RestrictedBranchFlow()` (ε=0) | OK, -4823.526935971745 | OK | 2.2e-8 | gate at rtol 1e-4 passes on this fixture |
| `LinDistFlow()` | OK, -4822.377935227229 | OK (11,24) | **ABSENT** | emits many "Battery complementarity violated" `@warn`s (QP path uses `on_violation = :warn`, welfare_solve.jl:292) — noisy, not an error |
| `ACPowerFlow()` | **THROWS** "Solve failed — refusing to trust results: LOCALLY_SOLVED" | — | — | needs `allow_local = true` |
| `ACPowerFlow()` + `allow_local=true` | OK, -4823.526907437314 | OK | 2.7e-9 (spurious "double-fire"; override to NaN) | Ipopt NLP |

`:ieee123` + `:ac`/`:lindistflow` was NOT probed (potentially slow/ill-conditioned) — the plan's tests should use `:ieee13` only; document that large-feeder AC is the researcher's responsibility.

Strategy × pf (measured, T=24): Stochastic (S=3) + restricted → throws battery-complementarity (App. C check at τ=1e-3); + lindistflow → throws battery-complementarity (τ=1e-6); + ac → throws `solve_with_retry!` exhaustion. MPC window (`build_mpc_window`, H=6): restricted builds+solves (but certificate ladder is convex-specific); lindistflow builds+solves with `pf_vars` keys `(:v,:P,:Q)` (no `:l`, which `_mpc_certify_and_price` reads at mpc_loop.jl:865-868); ac throws at solve.

**Valid combination matrix to implement (recommended, enforced in `Scenario` inner ctor via an `ArgumentError`):**

| strategy \ pf | convex (literal=false) | convex (literal=true) | restricted | lindistflow | ac |
|---|---|---|---|---|---|
| Centralized | yes | yes | yes | yes | yes |
| ADMM | yes | NO (silently ignored today) | NO (MethodError) | NO | NO |
| MPC | yes | NO (untested; conservative) | NO | NO | NO |
| Stochastic | yes | NO (untested; conservative) | NO | NO | NO |

Express as a per-strategy trait/method `supports_pf(::AbstractStrategy, pf::Symbol, thesis_literal::Bool)` in `strategies.jl` (single place Phase 34 will relax for ADMM). Error message should name the strategy, the pf and which pfs ARE valid.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Stable filename hashing | New hash scheme | existing `_stable_hex64` FNV-1a (store.jl) for non-uniform probabilities | Julia-version-stable; keeps uniform filenames' rule. Keep `allequal` test. |
| Filename generation from a flattened spec | string concatenation | `DrWatson.savename(::Dict, "jld2"; digits = 10)` | Sorted keys, lossless floats; verified works for Dict with Symbol/Float/Bool values. |
| Sweep expansion | custom Cartesian product | `dict_list` + `Scenario(; nt...)` (existing) | Legacy flat keys keep working. |
| Per-pf dispatch of solver choice | `if pf isa ...` solver branching | `problem_class(pf)` trait inside `solve_welfare` (existing) | The only new `isa` needed is the maxgap/allow_local guard in `run(::Centralized)`. |

## Runtime State Inventory

(Refactor of identity/serialization; included because filenames/column names change.)

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `data/sims/*.jld2` (gitignored) written by old `scenario_filename`; dicts carry flat keys `ρ`, `ε_abs`, `mpc_H`, `stoch_S` … | None committed. Old files become orphaned (different filenames); document. `results/sweeps/` contains only `.gitkeep` [VERIFIED: `git ls-files`] — no committed CSV to regenerate. Other `results/*` dirs (pv_boom, benders_toy, …) are not Scenario artifacts (not verified file-by-file; low risk). |
| Live service config | None — verified: no external service references Scenario names. | none |
| OS-registered state | None | none |
| Secrets/env vars | None | none |
| Build artifacts | `docs/src/generated/*.md` is gitignored and regenerated from `docs/literate/*.jl` [VERIFIED: `git check-ignore`]; `graphify-out/GRAPH_REPORT.md` mentions `Scenario(` (derived artifact, not edited by hand) | Re-run docs build after migrating literate files. |

## Caller / Reader Inventory (file:line)

`Scenario(` construction sites outside `Scenario.jl` (counts from grep):
- `src/experiments/sweep.jl:` `run_sweep` → `[Scenario(; nt...) for nt in dict_list(params)]` (sweep.jl ~L36). Legacy flat keys incl. `:strategy => [:centralized,:admm]` (scripts/sweep.jl:19) must keep working.
- `test/fixtures_phase8.jl` (`minimal_scenario_kwargs()` → `strategy = :centralized`; splatted by ~12 testitems). Legacy form works unchanged.
- `test/test_experiments.jl` (18 sites; `strategy = :admm`, `strategy = :bogus` must throw `ArgumentError`, `stoch_probabilities = p` at L221-235 incl. the `s.stoch_probabilities !== p` copy test at L232-234, WR-02 filename test L237-270, tagsave test L274-).
- `test/test_admm_knifeedge_canary.jl:40` (`strategy = :admm`).
- `test/test_mpc_loop.jl` L26, 76, 277, 647-648, 658, 665, 671, 704 (all use `mpc_*` knobs on default `:centralized` → MUST MIGRATE to `strategy = MPC(...)` or `run(MPC(...), s)`).
- `test/test_run_stochastic.jl` L23, 38, 92, 106 (`stoch_S`, `stoch_H_oos` on default `:centralized` → MUST MIGRATE; reads `s.stoch_S` / `s.stoch_H_oos` at L28-29, 95 → `s.strategy.S` etc.).
- `test/test_mpc_window.jl:66` — comment only. 
- `scripts/`: `run_scenario.jl:16` (ADMM, flat; works unchanged), `demo_mpc_plots.jl` L67, 131, 146 + reads `s.mpc_H/mpc_terminal_soc/mpc_step/mpc_forecast_error` at L205, 222-223, 273 (MIGRATE), `compare_default_stochastic.jl` L47, 67 (stochastic knobs; MIGRATE), `pv_boom_case_study.jl:184` (centralized; unchanged), `sweep.jl:19` (legacy keys; unchanged).
- `docs/literate/`: `experiments.jl` L42, 129 (bogus feeder, must still throw), 145 (`strategy = :admm`; prose at L51 mentions `s.strategy` and the "ADMM-only fields populated" at ~L147 — update wording), `mpc_rolling_horizon.jl:47` (MIGRATE), `stochastic_pv_demand.jl:49` (MIGRATE; reads `s.stoch_S`, `s.stoch_probabilities[k]`, `s.stoch_H_oos` at L95, 113-114, 129, 173-179, 256 → `s.strategy.S`/`.probabilities`/`.H_oos`).
- `README.md:96` (`strategy = :admm`; legacy form still valid, but update to show new form + `pf`).

Readers of flat Scenario fields in src: `run.jl:92-149` (`s.ρ`, `s.maxiter`, `s.ε_abs`, `s.ε_rel`, `s.τ_ratio`, `s.μ`, `s.strategy`), `mpc_loop.jl:255-486 + ~L440-740` (`s.mpc_H/step/terminal_soc/forecast_error` at 272-282, 324, 332-333, 386-387, 432-486, plus `s.T`, `s.seed`, `s.allow_export`, `s.feeder`, `s.price`, `s.population`), `run_stochastic.jl:156-271` (`s.stoch_S/probabilities/H_oos`), `store.jl:135,` (`struct2dict(s)`), `sweep.jl` collate column lists. Only `ScenarioResult` constructor call: `run.jl:179` (no test constructs it).

Hard-coded `ConvexBranchFlow()`: `run.jl:112` (the pf variable), `mpc_loop.jl:298`, `run_stochastic.jl:151`. Also `src/admm/DsoOpt.jl:396` (OUT of scope, ARCH-05).

## Store / Sweep Details

- `scenario_filename` (store.jl:~69-97): currently `savename(s, "jld2"; digits = 10)` + `_p<digest>` when `!allequal(s.stoch_probabilities)` + NAME_MAX fallback (`target = 255 - 10`, `_h<hash(full)>` suffix with `thisind` UTF-8 snapping). New: build `d::Dict{Symbol,Any}` = common fields (`name, feeder, seed, T, population, price, allow_export, pf` + only relevant pf options) + `strategy => nameof(typeof(st))`-as-Symbol + prefixed active-strategy knobs (`admm_ρ`, `admm_ε_abs`, `admm_ε_rel`, `admm_maxiter`, `admm_τ_ratio`, `admm_μ`, `mpc_H`, `mpc_step`, `mpc_terminal_soc`, `mpc_forecast_error`, `stoch_S`, `stoch_H_oos`), then `savename(d, "jld2"; digits = 10)`; keep digest fold (read `s.strategy.probabilities`) and the NAME_MAX fallback verbatim. `strategy` value must be a Symbol/String (DrWatson-allowed), e.g. `:ADMM` → `strategy=ADMM` per CONTEXT.
- Uniqueness requirement (CR-01 lineage): two Scenarios differing in ANY identity-bearing primitive must map to different filenames. Test with a property-style loop (vary each knob) in a new testitem. Caveat: Dict keys sort alphabetically so non-ASCII `ρ`/`ε` keys sort after ASCII — irrelevant to uniqueness.
- `result_to_dict` (store.jl:~133-145): replace `struct2dict(s)` by a flatten helper shared with `scenario_filename` (single source of truth; the docstring warns about independently-maintained call sites). Stamp: common fields; `:pf`, `:pf_thesis_literal`, `:pf_ε`; `:strategy` (Symbol, as today `:centralized`/`:admm` lowercase — recommend keeping the lowercase Symbols `:centralized/:admm/:mpc/:stochastic` in the dict so `collate_summary`/`docs/literate/experiments.jl:283` (`Symbol(st) for st in df.strategy`) stay valid, while the filename uses CONTEXT's `strategy=ADMM`); the legacy flat knob keys (`:ρ`, `:ε_abs`, `:ε_rel`, `:maxiter`, `:τ_ratio`, `:μ`, …) for the ACTIVE strategy only (others absent); results `:welfare, :dadp, :exact_maxgap, :iters, :final_r, :final_s, :reactive_consensus_mode` (keep stamping `missing` for non-ADMM as today), plus scalar MPC/Stochastic summaries only (e.g. `:regret`, `:steps`, `:welfare_gap`) — never `MpcTrace` objects. Also `:julia_version`. Test `INFRA-04 provenance tagsave` only checks keys `gitcommit`, `julia_version`, `seed`.
- `collate_summary` (sweep.jl): `keep`/`selector_cols` lists reference `:ρ, :ε_abs, ...`. Mixed sweeps (`strategy => [:centralized, :admm]`) already yield `missing` for ADMM-only columns; keys absent from some JLD2 files become `missing` cells in `collect_results` (DataFrames joins on union of keys — VERIFY with a mixed-strategy test; `sort!` over columns containing `missing` works, missing sorts last). Add `:pf`, `:pf_thesis_literal`, `:pf_ε`, and MPC/Stochastic knob columns to both lists (intersect with `present` already tolerates absence). Keep the byte-identical-collation test (test_experiments.jl:116-143) green.

## Common Pitfalls

### Pitfall 1: `savename` drops `strategy`
**What goes wrong:** filename lacks the strategy; ADMM and Centralized runs collide (`safesave` then appends `_1`, hiding the bug).
**How to avoid:** flattened-Dict helper; add a test asserting `occursin("strategy=ADMM", scenario_filename(s))` and that centralized/admm/mpc/stochastic Scenarios have 4 distinct filenames.

### Pitfall 2: `ctx.meta[:socp_maxgap]` KeyError under LinDistFlow
**What goes wrong:** `run.jl:105` indexes the key unconditionally. **How to avoid:** `isa Union{ConvexBranchFlow,RestrictedBranchFlow}` guard (Pattern 3). Add a test that `:lindistflow` + Centralized returns `isnan(exact_maxgap)`.

### Pitfall 3: AC requires `allow_local = true`; AC returns a spurious tiny maxgap
**What goes wrong:** default `solve_welfare` throws on Ipopt LOCALLY_SOLVED. **How to avoid:** pass `allow_local = pf isa ACPowerFlow`; force `NaN`. Memory note exactness-gate-hybrid-floor: for fixed-dispatch SOCP re-solves use `ACPowerFlow(limits = false)` — not relevant here (this path solves the full welfare problem, so `limits = true`, the default, is correct). Expect ~1.4 s solve on ieee13 T=24.

### Pitfall 4: Legacy kwarg ambiguity — `strategy` kwarg can be a Symbol or a struct
**What goes wrong:** `Scenario(; strategy = ADMM(ρ=50.0), ρ = 10.0)` is contradictory. **How to avoid:** if `strategy isa AbstractStrategy`, any flat knob kwarg throws `ArgumentError` (not silently ignored). If `strategy isa Symbol`, map the symbol (`:centralized`, `:admm`, `:mpc`, `:stochastic`; unknown → `ArgumentError`, preserving `test_experiments.jl:93`) and any knob not belonging to that strategy throws. Implement by detecting supplied-vs-default knobs: use `kwargs...` capture + `haskey`, NOT comparison against defaults (a user passing `mpc_H = 6` explicitly with `:centralized` is still foreign).

### Pitfall 5: `run_mpc`/`run_stochastic` on a Scenario whose strategy is not MPC/Stochastic
**What goes wrong:** after migration `s.strategy` is `Centralized()` for a plain `Scenario(name=..)`; `run_mpc(s)` has no knobs to read. **How to avoid (recommended):** wrappers use `st = s.strategy isa MPC ? s.strategy : MPC()` (defaults identical to today's flat defaults → same results as today for knob-less Scenarios). `run(st::MPC, s)` uses the explicit `st` and sets `result.scenario` via a `with_strategy(s, st)` copy (re-validates strategy×pf) so provenance is accurate. Also `ScenarioResult.scenario.strategy` then reflects what ran.

### Pitfall 6: `ADMM` silently ignoring pf (see Summary 1)
Reject `thesis_literal = true`/non-convex pf with ADMM at construction; do NOT "fix" `DsoOpt.jl:396` (ARCH-05, Phase 34).

### Pitfall 7: Common `dadp` shape for MPC/Stochastic
`ScenarioResult.dadp::Matrix{Float64}` can only be `(n_load_nodes × T)` for Centralized/ADMM. Use a `1 × n` row for MPC/Stochastic (document in the `ScenarioResult` docstring), full data in `details`. `exact_maxgap` for MPC = `NaN` (the run does not return a numeric gap; only `cert_status_trace`); Stochastic = `maximum(in_sample.socp_maxgap)` (it is a per-scenario vector; `NaN` if empty).

### Pitfall 8: Struct equality
Strategy structs holding a `Vector{Float64}` (`Stochastic.probabilities`) compare by identity under default `==`. Define `Base.:(==)` and `Base.hash` for strategy structs (value-based) — cheap, makes `Scenario ==` meaningful for tests and sweeps. (Today `Scenario` has the same hole; not required, but recommended.)

### Pitfall 9: Aqua/ambiguity and the name `run`
Verified: `function run end` inside `module M` with `using Base` implicit import defines `M.run` without extending `Base.run`; `using .M` does not shadow `Base.run` for a caller who also gets Base's (a bare `run(M.A(), 1)` after `using .M` gave a `MethodError` pointing at Base's `run` — i.e. ambiguity-free, just not callable unqualified). `src/` contains no bare `run(` call that would be shadowed (grep: only a string in planning/nash.jl:1247). Because `run` is not exported, call it as `TSODSO.run(...)` everywhere (tests, docs). **Do not `import Base: run`** (that would make it piracy-adjacent and Aqua-noisy). The `function run end` declaration must appear before any use inside the module — put it first in `strategies.jl`.

## Aqua / JET / Docs Implications

- Aqua: single gate `test/test_toy_dc.jl:30` (`Aqua.test_all(TSODSO)`, default config → includes ambiguities, piracies, undefined exports, stale deps, persistent tasks, compat). Risks: (a) a new `Base.getproperty(::ScenarioResult, ::Symbol)` is on an owned type → not piracy; (b) defining `Base.:(==)`/`hash` for owned strategy types → fine; (c) outer kwarg `Scenario(; ...)` + inner positional constructor → distinct signatures, no ambiguity; (d) `Base.propertynames(::ScenarioResult, ::Bool)` fine. Known false failures on the main checkout (memory local-project-toml-drift): CairoMakie "Stale dependencies" and "Persistent tasks" — baseline 31260/0/0/5 recorded in STATE after Phase 31 so treat any NEW Aqua failure as real. [CITED: memory/local-project-toml-drift.md]
- JET: referenced in CLAUDE.md and `test/Project.toml` but **no test file imports JET** [VERIFIED: grep of test/*.jl and .github] — there is no JET gate to break. Still keep `details` a small `Union` of concrete structs (not `Any`) and avoid `getproperty` returning `Union{Missing,...}` from untyped paths.
- Documenter: `docs/make.jl` uses `checkdocs = :exports`; `docs/src/api.md:126` "Experiment Harness" `@autodocs` `Pages = [...]` list must gain `"experiments/strategies.jl"` (new types, `Order = [:type, :constant, :function]`) or exported strategy types would FAIL the docs build as documented-but-unsurfaced. Add exports in `strategies.jl`: `export AbstractStrategy, Centralized, ADMM, MPC, Stochastic` (names verified free: no existing `ADMM`, `MPC`, `Stochastic`, `Centralized`, `AbstractStrategy` identifiers anywhere in src/ext/test/scripts [VERIFIED: grep]). Non-exported `run` with a docstring is surfaced by `@autodocs` (private included by default; `checkdocs = :exports` does not require it) — still include it. New `ADMMDetails/MPCDetails/StochasticDetails` need docstrings; export or not consistently (recommend not exported, accessed through `res.details`, but then `@autodocs` still lists them). `run_mpc` already surfaced via `api.md:102` (Pages list includes `experiments/mpc_loop.jl`); `run_stochastic` via `api.md:110`. `warnonly = [:cross_references]` so a `[`TSODSO.run`](@ref)` slip is non-fatal.
- Literate docs execute code at docs-build time (`docs/make.jl` runs Literate); un-migrated `Scenario(; mpc_H=…)` in `mpc_rolling_horizon.jl`/`stochastic_pv_demand.jl` will THROW at build. Run literate files with `JULIA_LOAD_PATH="docs:.:@stdlib" julia docs/literate/<file>.jl` (memory note).

## Code Examples

### Legacy → strategy mapping (outer constructor)
```julia
# Scenario.jl — hand-written; no @kwdef.
function Scenario(; name::String, feeder=:ieee13, strategy::Union{Symbol,AbstractStrategy}=Centralized(),
                  seed=1, T=24, population=:default, price=:mem, allow_export=true,
                  pf::Symbol=:convex_branch_flow, pf_thesis_literal::Bool=false, pf_ε::Real=0.0,
                  knobs...)                       # ρ, ε_abs, ε_rel, maxiter, τ_ratio, μ, mpc_*, stoch_*
    st = _resolve_strategy(strategy, knobs)       # Symbol -> struct, foreign/unknown knob => ArgumentError
    return Scenario(name, feeder, seed, T, population, price, allow_export, pf, pf_thesis_literal, Float64(pf_ε), st)
end
```
`name` is currently a REQUIRED kwarg (no default in `@kwdef`) — keep it required.
Mapping table to implement in `_resolve_strategy`: `:centralized` → no knobs allowed; `:admm` → `ρ, ε_abs, ε_rel, maxiter, τ_ratio, μ`; `:mpc` → `mpc_H→H, mpc_step→step, mpc_terminal_soc→terminal_soc, mpc_forecast_error→forecast_error`; `:stochastic` → `stoch_S→S, stoch_probabilities→probabilities, stoch_H_oos→H_oos`. NB: legacy `strategy ∈ (:centralized,:admm)` only; `:mpc`/`:stochastic` Symbols are NEW (accept them — the success criterion lists them as strategies).

### Targeted verification (see Validation Architecture)
```bash
JULIA_LOAD_PATH="@:.:test:@stdlib" julia --project=. -e 'using TestItemRunner; TestItemRunner.run_tests(joinpath(pwd(),"test"); filter = ti -> endswith(ti.filename, "test_experiments.jl"))'
```
[VERIFIED: ran this session; 70 pass, 2m03s]. Other load-path forms (`--project=test`, `JULIA_LOAD_PATH="test:.:@stdlib"`) FAIL with "Package TSODSO not found" [VERIFIED].

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Flat Scenario with `strategy::Symbol` + strategy knobs | `strategy::AbstractStrategy` field + knobs in strategy structs | Names collapse; validation moves; filenames shorter. |
| Three independent entry points with three result shapes | `TSODSO.run(strategy, scenario)` → `ScenarioResult` | Wrappers keep old shapes. |

**Deprecated:** none removed this phase (legacy kwarg ctor stays until a later cleanup).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | MPC/Stochastic with `ConvexBranchFlow(thesis_literal=true)` was not tested; recommended to reject at construction | Valid-combination matrix | Low: only loses a (possibly working) option; relaxable. [ASSUMED conservative choice] |
| A2 | `:ieee123` + `:ac`/`:lindistflow` Centralized behaviour not measured | Measured pf behaviour | Medium: a researcher could hit slow/failed AC on 123 bus; tests should stay on ieee13. [ASSUMED] |
| A3 | `collect_results` yields `missing` cells (not an error) when JLD2 dicts in one dir have different key sets (mixed-strategy sweep) | Store/Sweep | Medium: would break `collate_summary`; the plan must include a mixed-strategy collate test to confirm. [ASSUMED from DrWatson docs; today's `:centralized`+`:admm` sweep shares keys, so not exercised before] |
| A4 | Recommending foreign `pf_*` options (e.g. `pf_ε` with `:convex_branch_flow`) throw, like foreign strategy knobs | Scenario design | Low; CONTEXT silent — user may prefer silently ignoring. Planner/discuss may confirm. [ASSUMED] |
| A5 | `run_mpc(s)`/`run_stochastic(s)` fallback to `MPC()`/`Stochastic()` defaults when `s.strategy` is another type | Pitfall 5 | Low-medium: CONTEXT silent; alternative is an `ArgumentError`. |

## Open Questions

1. **`exact_maxgap` for MPC** — `run_mpc` returns no numeric gap. Recommend `NaN` + doc. Alternative: add the max `cone_maxratio` to the trace (touches `MpcTrace`; out of scope).
2. **Should `run(st, s)` accept `st` different from `s.strategy`?** Recommend yes (explicit arg wins; result's scenario is rebuilt). CONTEXT's `run(s) = run(s.strategy, s)` is compatible.
3. **Dict-key lowercase vs CONTEXT's filename `strategy=ADMM`.** Recommend lowercase Symbols in the stored dict/CSV (compat with `collate_summary` consumers) and the type name in the filename; planner to confirm.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | everything | yes | 1.12.5 | — |
| TestItemRunner (test env) | targeted tests | yes (via stacked LOAD_PATH) | 1.1.x | `julia test/runtests.jl` (full) |
| Ipopt (AC pf) | `:ac` centralized | yes (bundled) | — | — |
| Documenter/Literate/CairoMakie (docs env) | literate + docs build | present in `docs/Project.toml` per memory | — | `JULIA_LOAD_PATH="docs:.:@stdlib"` |
| Sibling git worktrees | full-suite contamination | `git worktree list` shows 2 siblings under `/home/pedro/programming/TSO-DSO.worktrees/` (not under `.claude/worktrees/`; none there) | — | Re-check `git worktree list` before the certifying full run per memory note |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Test + TestItems/TestItemRunner (`@testitem`), Aqua |
| Config file | `test/runtests.jl` (`@run_package_tests`), `test/Project.toml` |
| Quick run command (per file) | `JULIA_LOAD_PATH="@:.:test:@stdlib" julia --project=. -e 'using TestItemRunner; TestItemRunner.run_tests(joinpath(pwd(),"test"); filter = ti -> endswith(ti.filename, "test_<name>.jl"))'` |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (detached, see below) |

Measured wall times of targeted files (this session, in parallel on one machine): `test_experiments.jl` 70 tests / 2m03s; `test_run_stochastic.jl` 14 / ~1m55s; `test_admm_knifeedge_canary.jl` 2 / ~2m02s; `test_mpc_loop.jl` 356 / ~2m09s (each includes ~35-60 s compile/first-solve). Full suite ≈ 16-36 min.

Memory-note rules the plans' `<verify>` blocks MUST follow:
- Never use `@run_package_tests` via `julia -e`; never `julia --project=. -e` with a bare TestItemRunner `using` (not resolvable). Use the stacked `JULIA_LOAD_PATH="@:.:test:@stdlib"` recipe above (verified) or direct scripts. [CITED: memory gsd-plan-verify-testitemrunner-trap, local-project-toml-drift]
- `@testitem` bodies: no `try x = ... end` (assign the try expression's value), no `for`-loop reassignment of outer variables (use `let`/function). New tests that check `@test_throws` are fine. [CITED: memory testitem-try-scoping-trap]
- Full-suite: launch detached with a done-marker (`nohup setsid bash -c "... ; echo \$? > DONE"`), poll; foreground tool calls max 10 min and kill it; confirm log start time is after the final commit; `git worktree list` has no `.claude/worktrees/agent-*`. Executors must not end a turn waiting on a background child. [CITED: memory background-suite-orphan-race]
- Baseline to match: **31260 passed / 0 failed / 0 errored / 5 broken** (STATE after Phase 31). The 2 known-false Aqua failures from local `Project.toml` drift only appear if the main checkout carries that drift; the git status at phase start is clean.

### Bit-identity gates (goldens that must not move)
| Golden | Location | What it pins |
|--------|----------|--------------|
| ADMM knife-edge | `test_admm_knifeedge_canary.jl:71,81` | `r.iters == 56`, `welfare ≈ -4823.66604824162 (rtol 1e-6, atol 1e-3)` via `run_scenario(Scenario(...; strategy = :admm))` |
| Stochastic golden | `test_run_stochastic.jl:102-150` | `in_sample.welfare`, `oos.welfare_gap` literals + 3-fresh-call bit stability on `Scenario(name="t", feeder=:ieee13, T=9, stoch_S=3, stoch_H_oos=5)` |
| MPC loop | `test_mpc_loop.jl` (356 asserts, e.g. L36-49 `steps == T-H+1`, `realized_welfare ≈ forecast_settled_welfare`, L92, L653-656 step-stride, L717) | closed-loop semantics |
| Centralized/ADMM repro | `test_experiments.jl:26-80, 145-220` | same-seed `==` on welfare/dadp/exact_maxgap/iters |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ARCH-01 | `Scenario(pf=…)` honoured by `run_scenario` for all 4 selectors (ieee13, T=24); `build_powerflow` returns right type/options; default is byte-identical to `ConvexBranchFlow()` | integration | `…filter endswith "test_experiments.jl"` (add items) or new `test_scenario_pf.jl` | NO — Wave 0 |
| ARCH-01 | `:lindistflow` → `isnan(exact_maxgap)`, no KeyError; `:ac` → `isnan(exact_maxgap)`, no throw (allow_local); `:restricted_branch_flow` → finite maxgap | integration | same | NO — Wave 0 |
| ARCH-01 | Convex default result bit-identical to pre-phase: `welfare == -4823.5269334868735` at `Scenario(name,T=24,seed=1)`? (use re-measured same-process comparison against direct `solve_welfare(feeder, ConvexBranchFlow(), …)` call, NOT a literal, to avoid pinning toolchain digits) | integration | same | NO — Wave 0 |
| ARCH-01 | invalid selectors/options throw `ArgumentError`: `pf=:bogus`, `pf_ε<0`, ADMM+`:lindistflow`/`:ac`/`:restricted_branch_flow`/`thesis_literal=true`, MPC/Stochastic + non-convex pf | unit | `…test_scenario_pf.jl` | NO — Wave 0 |
| ARCH-02 | Strategy constructors validate (ρ≤0, ε≤0, maxiter<1, H<1, step<1, forecast_error∉[0,1), S∉[3,5], H_oos∉[5,10], probs length/positivity/sum) and keep defaults (ρ=100.0 …); `Stochastic()` uniform probs, defensive copy | unit (fast) | `…test_strategies.jl` | NO — Wave 0 |
| ARCH-02 | `TSODSO.run(Centralized(), s)`/`run(ADMM(), s)`/`run(MPC(…), s)`/`run(Stochastic(…), s)` all return `ScenarioResult` with `welfare::Float64`, `dadp::Matrix{Float64}`, `exact_maxgap::Float64`, `elapsed`, typed `details`; `run(s) == run(s.strategy, s)`; MPC/Stochastic wrapped values equal `run_mpc`/`run_stochastic` NamedTuple fields (`welfare == realized_welfare` / `in_sample.welfare`) | integration | `…test_strategies.jl` (T=9 cases from test_mpc_loop/test_run_stochastic for speed) | NO — Wave 0 |
| ARCH-02 | `getproperty` forwarding: `r.iters` etc. present for ADMM, `missing` for others; `propertynames` | unit | `…test_experiments.jl` (existing items cover centralized/admm) | partial |
| ARCH-02 | Legacy kwargs map identically: `Scenario(;strategy=:admm, ρ=50.0, …) == Scenario(; strategy=ADMM(ρ=50.0, …))`; foreign knob / contradictory struct+knob throws; `strategy=:bogus` throws; `:mpc`/`:stochastic` Symbols accepted | unit | same | NO — Wave 0 |
| ARCH-02 | `Scenario` has no flat strategy fields: `!hasproperty(s, :ρ)`/`:mpc_H`/`:stoch_S`; `fieldnames(Scenario)` pinned | unit | same | NO — Wave 0 |
| ARCH-02 | `scenario_filename`: 4 strategies → 4 distinct names, contains `strategy=<Name>`, only active knobs, `sizeof ≤ 255`, deterministic, probability digest for non-uniform / none for uniform, vary-each-knob uniqueness | unit | `…test_experiments.jl` (update WR-02 item L237-270) | partial — update |
| ARCH-02 | `run_and_store` JLD2 round-trips with flattened dict (no struct values), mixed-strategy `run_sweep` + `collate_summary` byte-identical twice, no `path` column | integration | `…test_experiments.jl` L99-143 (extend with `:strategy => [:centralized,:admm]`) | partial |
| ARCH-02 | Aqua (ambiguities/piracy/exports), docs build `checkdocs = :exports` | quality | full suite / `julia --project=docs docs/make.jl` (docs env) | exists |

### Sampling Rate
- **Per task commit:** the single touched test file via the quick-run command (each ≈ 2 min; new `test_strategies.jl` should be < 1 min by using T=9 and `Centralized` on ieee13).
- **Per wave merge:** the 5 files `test_experiments`, `test_mpc_loop`, `test_run_stochastic`, `test_admm_knifeedge_canary`, new `test_scenario_pf`/`test_strategies` (run in parallel ≈ 3-4 min wall).
- **Phase gate:** full `Pkg.test()` detached; must reproduce 31260/0/0/5 PLUS the newly added passes (counts rise by the new asserts; "0 failed / 0 errored / 5 broken" is the invariant). Also run the 3 literate docs (`experiments.jl`, `mpc_rolling_horizon.jl`, `stochastic_pv_demand.jl`) under the docs env.

### Wave 0 Gaps
- [ ] `test/test_strategies.jl` — strategy constructors, `run` dispatch/common shape, legacy-kwarg mapping, flat-field removal (ARCH-02).
- [ ] `test/test_scenario_pf.jl` — `build_powerflow`, per-pf `run_scenario` behaviour, combination guards (ARCH-01).
- [ ] Update `test/test_experiments.jl` WR-01/WR-02 items (probability access via `s.strategy.probabilities`, filename assertions) and add mixed-strategy sweep collate.
- [ ] Migrate `test_mpc_loop.jl`/`test_run_stochastic.jl` Scenario constructions (≈14 sites) — keep numeric assertions untouched.
- [ ] Framework install: none.

## Security Domain

`security_enforcement` is absent from `.planning/config.json` (treated as enabled), but this phase has no auth, session, network, or crypto surface. Applicable ASVS:

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2/V3/V4 Auth/Session/Access | no | — |
| V5 Input Validation | yes | `throw(ArgumentError(...))` in `Scenario`/strategy constructors for every selector/knob/combination (never `@assert`, which `-O` elides) |
| V6 Cryptography | no | FNV-1a is a filename disambiguator, NOT a security hash (already documented in store.jl; keep that wording) |

| Pattern | STRIDE | Mitigation |
|---------|--------|------------|
| Silent misconfiguration (knob ignored, e.g. ADMM + thesis_literal) producing wrong science | Tampering (of results) | construction-time `ArgumentError` for unsupported combos and foreign knobs |
| Filename collision overwriting a prior run | Tampering/DoS (data loss) | `digits=10`, `safe=true`, flattened-identity uniqueness test; NAME_MAX fallback retained |
| Path injection via `name` in filename | Tampering | existing behaviour (`name` is a savename component; unchanged); do not add path separators handling regression — keep `safesave` |

## Sources

### Primary (HIGH confidence — read or executed this session)
- Repo source: `src/experiments/{Scenario,run,store,sweep,materialize,mpc_loop,run_stochastic}.jl`, `src/models/{welfare_solve,stochastic_welfare,mpc_window}.jl`, `src/pricing/dlmp.jl`, `src/powerflow/*.jl`, `src/admm/{solve_admm,DsoOpt}.jl`, `src/TSODSO.jl`, `docs/make.jl`, `docs/src/api.md`.
- Executed probes (scratchpad `pf_probe.jl`, `pf_probe2.jl`, `sn.jl`, `m.jl`): per-pf solve behaviour, strategy×pf failures, DrWatson `savename` nested-struct drop and Dict form, `function run end` module behaviour.
- Executed targeted test runs: test_experiments (70/2m03s), test_run_stochastic (14/~115s), canary (2/~122s), test_mpc_loop (356/~129s).
- Memory notes under `/home/pedro/.claude/projects/-home-pedro-programming-TSO-DSO/memory/` (test-run rules, baselines).

### Secondary / Tertiary
- None. No web sources needed (internal refactor; no external library API questions). Context7 not consulted because no new library is introduced and DrWatson `savename` behaviour was verified empirically on the pinned 2.19.1.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies.
- Architecture: HIGH — grounded in the actual code; two CONTEXT assumptions corrected with measurement (ADMM pf ignoring, MPC/Stochastic pf failures).
- Pitfalls: HIGH for items measured (1-3, 6, 7, 9); MEDIUM for A3 (mixed-key `collect_results`).

**Research date:** 2026-10-03
**Valid until:** until Phase 33/34 land (they change `Feeder`/`ModelContext`/`solve_admm`); otherwise stable ~30 days.
