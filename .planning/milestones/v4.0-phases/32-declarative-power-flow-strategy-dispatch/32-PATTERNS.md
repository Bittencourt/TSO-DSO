# Phase 32: Declarative Power-Flow & Strategy Dispatch - Pattern Map

**Mapped:** 2026-10-03
**Files analyzed:** 14 (1 new src, 6 modified src, TSODSO.jl, api.md, 2 new tests, ~6 migrated test/doc/script files)
**Analogs found:** 14 / 14 (all in-repo; this is a refactor, so most analogs are the files being modified)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/experiments/strategies.jl` (NEW) | model (strategy types + validation) | transform | `src/experiments/Scenario.jl` (inner-ctor validation) + `src/powerflow/RestrictedBranchFlow.jl:148` (struct w/ validating inner ctor) | role-match |
| `src/experiments/Scenario.jl` (MOD) | model (declarative spec) | transform | itself (current `@kwdef` + inner ctor) | exact |
| `src/experiments/materialize.jl` (MOD, add `build_powerflow`) | utility (selector -> object) | transform | `build_feeder` / `build_price` in same file | exact |
| `src/experiments/run.jl` (MOD) | service (dispatch + result) | request-response | itself (`run_scenario`, `ScenarioResult`) | exact |
| `src/experiments/mpc_loop.jl` (MOD, add `run(::MPC,s)`) | service | request-response | `run_mpc` (L~255-777) | exact |
| `src/experiments/run_stochastic.jl` (MOD, add `run(::Stochastic,s)`) | service | request-response | `run_stochastic` (L~151-310) | exact |
| `src/experiments/store.jl` (MOD) | utility (identity/serialization) | file-I/O | itself (`scenario_filename`, `result_to_dict`) | exact |
| `src/experiments/sweep.jl` (MOD) | utility | batch | itself (`collate_summary` column lists) | exact |
| `src/TSODSO.jl` (MOD include order) | config | n/a | lines 227-247 | exact |
| `docs/src/api.md` (MOD) | config | n/a | line 126 Pages list | exact |
| `test/test_strategies.jl` (NEW) | test | request-response | `test/test_experiments.jl` | role-match |
| `test/test_scenario_pf.jl` (NEW) | test | request-response | `test/test_experiments.jl` + `test/fixtures_phase8.jl` | role-match |
| `test/test_experiments.jl`, `test_mpc_loop.jl`, `test_run_stochastic.jl` (MIGRATE) | test | n/a | themselves | exact |
| `docs/literate/{experiments,mpc_rolling_horizon,stochastic_pv_demand}.jl`, `scripts/{demo_mpc_plots,compare_default_stochastic}.jl`, `README.md` (MIGRATE) | docs/script | n/a | themselves | exact |

## Pattern Assignments

### `src/experiments/strategies.jl` (NEW; model, transform)

**Analog:** validation text/semantics come verbatim from `src/experiments/Scenario.jl` (inner constructor, L~150-300); struct-with-validating-inner-ctor idiom from `src/powerflow/RestrictedBranchFlow.jl:148-160`.

**Validation pattern to MOVE into strategy ctors** (Scenario.jl, ADMM block; keep the message text, change prefix `Scenario:` -> `ADMM:` etc.):
```julia
if maxiter < 1
    throw(ArgumentError("Scenario: maxiter must be ≥ 1 (ADMM iteration cap); got maxiter=$maxiter"))
end
if ρ <= 0
    throw(ArgumentError("Scenario: ρ must be > 0 (ADMM penalty); got ρ=$ρ"))
end
if ε_abs <= 0 || ε_rel <= 0
    throw(ArgumentError("Scenario: ε_abs/ε_rel must be > 0; got ε_abs=$ε_abs, ε_rel=$ε_rel"))
end
if τ_ratio <= 0 || μ <= 0
    throw(ArgumentError("Scenario: τ_ratio/μ must be > 0; got τ_ratio=$τ_ratio, μ=$μ"))
end
```
**MPC knobs** (Scenario.jl): `mpc_H < 1`, `mpc_step < 1`, `!(0 <= mpc_forecast_error < 1)` all throw ArgumentError.

**Stochastic knobs + sentinel + defensive copy** (Scenario.jl):
```julia
!(3 <= stoch_S <= 5)          -> ArgumentError
!(5 <= stoch_H_oos <= 10)     -> ArgumentError
if isempty(stoch_probabilities)
    stoch_probabilities = fill(1 / stoch_S, stoch_S)
else
    length(stoch_probabilities) != stoch_S      -> ArgumentError
    !all(>(0), stoch_probabilities)             -> ArgumentError
    !isapprox(sum(stoch_probabilities), 1; atol = 1e-8) -> ArgumentError
    stoch_probabilities = copy(stoch_probabilities)   # WR-01 aliasing fix
end
```

**Skeleton to copy** (struct + positional inner ctor + `@kwdef`-free kwarg ctor, mirrors RESEARCH Pattern 1):
```julia
abstract type AbstractStrategy end
function run end        # TSODSO.run, NOT exported; must precede any use
struct ADMM <: AbstractStrategy
    ρ::Float64; ε_abs::Float64; ε_rel::Float64; maxiter::Int; τ_ratio::Float64; μ::Float64
    function ADMM(ρ, ε_abs, ε_rel, maxiter, τ_ratio, μ) ... new(...) end
end
ADMM(; ρ=100.0, ε_abs=1e-4, ε_rel=1e-3, maxiter=200, τ_ratio=2.0, μ=10.0) = ADMM(Float64(ρ), ...)
```
Plus: `Base.:(==)`/`Base.hash` on all strategy structs (Pitfall 8), `supports_pf(::AbstractStrategy, pf::Symbol, thesis_literal::Bool)` (Centralized: all four; others: only `:convex_branch_flow` with `thesis_literal=false`), `export AbstractStrategy, Centralized, ADMM, MPC, Stochastic`, docstring on every symbol (docs `checkdocs = :exports`).
Also define `ADMMDetails`/`MPCDetails`/`StochasticDetails` here (run.jl is included BEFORE mpc_loop.jl/run_stochastic.jl).

---

### `src/experiments/Scenario.jl` (MOD; model, transform)

**Analog:** itself. Keep: selector-validation blocks for feeder/price/population/T/seed (L~165-215), `SCENARIO_VALID_*` constants + docstrings, `export Scenario`.

**Selector validation idiom to reuse for `pf`** (Scenario.jl):
```julia
if feeder ∉ SCENARIO_VALID_FEEDERS
    throw(ArgumentError("Scenario: unknown feeder selector $(repr(feeder)); expected one of " * "$(SCENARIO_VALID_FEEDERS)"))
end
```
Add `const SCENARIO_VALID_PFS = (:convex_branch_flow, :restricted_branch_flow, :lindistflow, :ac)` (replace `SCENARIO_VALID_STRATEGIES`, or retain as legacy-symbol set `(:centralized,:admm,:mpc,:stochastic)` for the outer ctor).

**Changes:** drop `Base.@kwdef` (it would collide with the hand-written outer kwarg ctor; RESEARCH Anti-Pattern); fields become `name, feeder, seed, T, population, price, allow_export, pf, pf_thesis_literal, pf_ε, strategy::AbstractStrategy`; inner ctor additionally checks `pf ∈ SCENARIO_VALID_PFS`, `pf_ε >= 0`, foreign `pf_*` options (pf_ε only with `:restricted_branch_flow`, pf_thesis_literal only with `:convex_branch_flow`), and `supports_pf(strategy, pf, pf_thesis_literal)`. Outer kwarg ctor `Scenario(; name, ..., strategy::Union{Symbol,AbstractStrategy}=Centralized(), knobs...)` calls `_resolve_strategy(strategy, knobs)`; detect supplied-vs-default via `knobs` keys (`haskey`), never compare to defaults. `name` stays REQUIRED. Legacy mapping: `:admm` -> `ρ, ε_abs, ε_rel, maxiter, τ_ratio, μ`; `:mpc` -> `mpc_H->H, mpc_step->step, mpc_terminal_soc->terminal_soc, mpc_forecast_error->forecast_error`; `:stochastic` -> `stoch_S->S, stoch_probabilities->probabilities, stoch_H_oos->H_oos`. Contradictory struct + flat knob -> ArgumentError; unknown symbol -> ArgumentError (test_experiments.jl:93 `strategy = :bogus`). Also add a `with_strategy(s, st)` helper that re-runs the inner ctor.

---

### `src/experiments/materialize.jl` (MOD; utility, transform)

**Analog:** `build_feeder` / `build_price` in the same file (symbol dispatch, ArgumentError terminal branch).
```julia
function build_feeder(sym::Symbol)
    if sym === :ieee13
        return ieee13_modified()
    elseif sym === :ieee123
        ...
    else
        throw(ArgumentError("build_feeder: unknown feeder selector $(repr(sym)); expected :ieee13, ..."))
    end
end
```
Add `build_powerflow(s::Scenario)` per RESEARCH Pattern 2 (`ConvexBranchFlow(; thesis_literal = s.pf_thesis_literal)`, `RestrictedBranchFlow(; ε = s.pf_ε)`, `LinDistFlow()`, `ACPowerFlow()` with default `limits=true`; terminal `ArgumentError`). Append to the trailing `export sub_seed, build_feeder, build_price, build_population` line. Default must be `===` today's `ConvexBranchFlow()` (isbits struct) so goldens stay bit-identical.

---

### `src/experiments/run.jl` (MOD; service, request-response)

**Analog:** itself. Materialize block (L~92-111) is the template for `run(::Centralized/ADMM, s)`:
```julia
feeder = build_feeder(s.feeder)
profiles = generate_profiles(; seed = sub_seed(s.seed, :profiles), T = s.T)
λ₀ = build_price(s.price, s.T, profiles)
aggs = build_population(s.population, feeder, s.feeder, profiles, sub_seed(s.seed, :population))
pf = ConvexBranchFlow()            # <-- run.jl:112, replace with build_powerflow(s)
```
**Centralized core to keep byte-identical** (run.jl L~117-131), adding only the guards:
```julia
ctx, welfare, _ = solve_welfare(feeder, pf, aggs; T = s.T, λ₀ = λ₀, allow_export = s.allow_export
                                , allow_local = pf isa ACPowerFlow)          # NEW
load_buses = sort!([a.bus for a in aggs])
dadp = extract_dlmp(ctx)[load_buses, :]
maxgap = pf isa Union{ConvexBranchFlow,RestrictedBranchFlow} ? Float64(ctx.meta[:socp_maxgap]) : NaN   # NEW (KeyError on LinDistFlow; AC spurious ~1e-9)
```
**ADMM core** (run.jl L~133-157): `solve_admm(feeder, pf, aggs; T, λ₀, ρ = st.ρ, maxiter = st.maxiter, ε_abs = st.ε_abs, ε_rel = st.ε_rel, τ = st.τ_ratio, μ = st.μ, allow_export)`; read `st.*` instead of `s.*`. `solve_admm` is typed `pf::ConvexBranchFlow` (solve_admm.jl:241) — hence the construction-time restriction.
**ScenarioResult reshape:** current 9-field struct (`scenario, welfare, dadp, exact_maxgap, iters, final_r, final_s, reactive_consensus_mode, elapsed`) -> `scenario, welfare, dadp, exact_maxgap, elapsed, details::Union{Nothing,ADMMDetails,MPCDetails,StochasticDetails}` + `Base.getproperty` forwarding returning `missing` for non-ADMM (RESEARCH Pattern 4) and `Base.propertynames`. Only constructor call site is run.jl:~179. `run_scenario(s) = run(s.strategy, s)`; `run(s::Scenario) = run(s.strategy, s)`. Keep the `@elapsed begin ... end` wrapper (timings excluded from equality). Update docstrings (docs/literate quotes them).
**Error handling:** `throw(ArgumentError(...))`; no solver names (INFRA-02).

---

### `src/experiments/mpc_loop.jl` (MOD; service, request-response)

**Analog:** `run_mpc(s::Scenario; _truth_settlement::Symbol = :ac)` (L~255). Extract the body into `_run_mpc(s, st::MPC; _truth_settlement)`; `run_mpc(s; ...)` wrapper uses `st = s.strategy isa MPC ? s.strategy : MPC()`; `run(st::MPC, s)` calls `_run_mpc` and wraps.

**Mechanical substitutions (47 sites):** `s.mpc_H` -> `st.H`, `s.mpc_step` -> `st.step`, `s.mpc_terminal_soc` -> `st.terminal_soc`, `s.mpc_forecast_error` -> `st.forecast_error`; `pf = ConvexBranchFlow()` (L298) -> `pf = build_powerflow(s)`. Keep boundary guards verbatim:
```julia
s.mpc_H > s.T && throw(ArgumentError("run_mpc: window length cannot exceed the day-ahead horizon " * "(mpc_H=$(s.mpc_H) > T=$(s.T))"))
s.mpc_step > s.mpc_H && throw(ArgumentError("run_mpc: step size cannot exceed window length H " * ...))
```
**Return NamedTuple stays unchanged** (L767-777): `trace, day_ahead_welfare, forecast_settled_welfare, realized_welfare, regret, day_ahead_dadp, steps, settlement_violations, pvbattery_truth_trace`. Wrap: `welfare = r.realized_welfare`, `dadp = reshape(r.trace.dadp_trace, 1, :)` (`MpcTrace.dadp_trace::Vector{Float64}`, models/mpc_trace.jl:56), `exact_maxgap = NaN`, `details = MPCDetails(...)` (regret/trace/steps/...). Do not rename NamedTuple fields (goldens in test_mpc_loop.jl).

---

### `src/experiments/run_stochastic.jl` (MOD; service, request-response)

**Analog:** `run_stochastic(s::Scenario)` (L~151). Same extract pattern (`_run_stochastic(s, st::Stochastic)`); replace `pf = ConvexBranchFlow()` (L151) with `build_powerflow(s)`; `s.stoch_S` -> `st.S`, `s.stoch_probabilities` -> `st.probabilities`, `s.stoch_H_oos` -> `st.H_oos`.
```julia
scenario_aggs = Vector{Vector{Aggregator}}(undef, s.stoch_S)
for k in 1:s.stoch_S
    profiles_k = generate_profiles(; seed = sub_seed(s.seed, Symbol(:stoch_insample_profiles_, k)), T = s.T)
...
r = build_stochastic_welfare(feeder, pf, scenario_aggs; probabilities = s.stoch_probabilities, T = s.T, λ₀ = λ₀, allow_export = s.allow_export)
```
Return NamedTuple `(; in_sample = (; welfare, dadp, expected_dadp, probabilities, socp_maxgap), oos = (; welfare_h, infeasible_h, realized_welfare, welfare_gap))` (L299-310) stays byte-identical. Wrap: `welfare = r.in_sample.welfare`, `dadp = reshape(r.in_sample.expected_dadp, 1, :)`, `exact_maxgap = isempty(socp_maxgap) ? NaN : maximum(socp_maxgap)`, `details = StochasticDetails(in_sample, oos)`.

---

### `src/experiments/store.jl` (MOD; utility, file-I/O)

**Analog:** itself. Keep verbatim: `_stable_hex64`, the NAME_MAX fallback, `run_and_store`'s `@tagsave(joinpath(dir, scenario_filename(s)), dict; storepatch = true, gitpath = pkgdir(@__MODULE__), safe = true)`.

**`scenario_filename`** — replace the first lines:
```julia
full = savename(s, "jld2"; digits = 10)           # OLD: savename silently DROPS a nested strategy struct
if !allequal(s.stoch_probabilities)               # OLD
    digest = _stable_hex64(reinterpret(UInt8, s.stoch_probabilities))
    full = string(chop(full; tail = 5), "_p", digest, ".jld2")
end
```
with a flattened `Dict{Symbol,Any}` helper (shared with `result_to_dict`, single source of truth): common fields (`name, feeder, seed, T, population, price, allow_export, pf` + only relevant pf option) + `:strategy => :ADMM`-style type-name Symbol + only active-strategy prefixed knobs (`admm_ρ, admm_ε_abs, ..., mpc_H, ..., stoch_S, stoch_H_oos`), then `savename(d, "jld2"; digits = 10)`; digest fold reads `s.strategy.probabilities` when `s.strategy isa Stochastic && !allequal(...)`. Imports: `using DrWatson: @tagsave, datadir, savename` (`struct2dict` no longer needed).

**`result_to_dict`** — replace `d = struct2dict(s)` with the flatten helper; stamp lowercase `:strategy => :centralized/:admm/:mpc/:stochastic`, legacy flat knob keys (`:ρ, :ε_abs, ...`) for the active strategy only, `:pf, :pf_thesis_literal, :pf_ε`; keep stamping `:iters/:final_r/:final_s/:reactive_consensus_mode` (via forwarding, `missing` for non-ADMM) and `:julia_version = string(VERSION)`; MPC/Stochastic add scalar summaries only (never `MpcTrace`).

---

### `src/experiments/sweep.jl` (MOD; utility, batch)

**Analog:** itself. `run_sweep` keeps `Scenario(; nt...)` (single legacy-kwarg mapping). In `collate_summary`, extend BOTH the `keep` list and `selector_cols` list (L~96-110 / L~121-135) with `:pf, :pf_thesis_literal, :pf_ε` and MPC/Stochastic knob columns; rule order / `intersect(..., present)` / `black_list = ["gitpatch","script"]` / CSV.write unchanged. Needs a mixed-strategy sweep test (assumption A3: `collect_results` yields `missing` for absent keys).

---

### `src/TSODSO.jl` and `docs/src/api.md` (MOD)

**TSODSO.jl** (L227): insert `include("experiments/strategies.jl")` BEFORE `include("experiments/Scenario.jl")`; order otherwise unchanged (`run.jl` L229 precedes `mpc_loop.jl`/`run_stochastic.jl` L238/247 — fine for generic functions, but Details types must live in strategies.jl).
**api.md:126:**
```
Pages = ["experiments/Scenario.jl", "experiments/materialize.jl", "experiments/run.jl", "experiments/store.jl", "experiments/sweep.jl"]
```
add `"experiments/strategies.jl"` (keep `:constant` in `Order`).

---

### `test/test_strategies.jl`, `test/test_scenario_pf.jl` (NEW; test)

**Analog:** `test/test_experiments.jl` (`@testitem` structure, fixtures via `Phase8Fixtures.minimal_scenario_kwargs()` in `test/fixtures_phase8.jl`, `@test_throws ArgumentError Scenario(...)`, mktempdir for stores). Follow memory traps: no `try x = ...` / for-loop reassignment of outer vars inside `@testitem` bodies (wrap in functions/`let`); use `ieee13`, small T (9) for speed; call as `TSODSO.run(...)`. Run per-file via `JULIA_LOAD_PATH="@:.:test:@stdlib" julia --project=. -e 'using TestItemRunner; TestItemRunner.run_tests(joinpath(pwd(),"test"); filter = ti -> endswith(ti.filename, "test_<name>.jl"))'`.

---

## Shared Patterns

### Construction-time validation
**Source:** `src/experiments/Scenario.jl` inner constructor.
**Apply to:** strategies.jl ctors, Scenario inner ctor (pf selectors/options/combos), `build_powerflow`.
Always `throw(ArgumentError(...))`, never `@assert`; message names the offending value and the valid set (`repr(x)` + `$(SCENARIO_VALID_*)`).

### Symbol-selector dispatch with terminal ArgumentError
**Source:** `src/experiments/materialize.jl` `build_feeder`/`build_price`.
**Apply to:** `build_powerflow`, `_resolve_strategy`.

### Materialize block (seeded, global-RNG free)
**Source:** `src/experiments/run.jl:92-111`, duplicated in `mpc_loop.jl:~285-298` and `run_stochastic.jl:151` (uses distinct `sub_seed` tag families `:stoch_insample_*`).
**Apply to:** every `run(::Strategy, s)`; do not alter seeds/tags (INFRA-04 bit-identity).

### On-disk identity
**Source:** `store.jl` `scenario_filename` (digits = 10, safe = true, FNV-1a digest, NAME_MAX `_h<hash>` fallback).
**Apply to:** the flatten helper; one helper serves both `scenario_filename` and `result_to_dict`.

### Docstring + export discipline
**Source:** every file in `src/experiments/` (long docstrings per symbol; `export` at file bottom).
**Apply to:** all new types/functions; docs build uses `checkdocs = :exports`; `warnonly = [:cross_references]`.

### No solver names in orchestration
**Source:** `run.jl` header (INFRA-02). Route through `solve_welfare`/`solve_admm` only.

## No Analog Found

| File/Concern | Role | Data Flow | Reason |
|--------------|------|-----------|--------|
| `getproperty` forwarding on `ScenarioResult` | model | transform | No existing `Base.getproperty` override on a result struct in `src/`; use RESEARCH Pattern 4 verbatim (must return `missing`, not throw, for non-ADMM: test_experiments.jl:42,47, store.jl, scripts/run_scenario.jl:22). |
| Legacy-kwarg outer constructor w/ `knobs...` foreign-knob detection | model | transform | No prior hand-written outer kwarg ctor; use RESEARCH "Legacy -> strategy mapping" sample. |
| `supports_pf` trait | utility | transform | New; single place Phase 34 relaxes for ADMM. |

## Metadata

**Analog search scope:** `src/experiments/*.jl`, `src/powerflow/*.jl`, `src/models/{welfare_solve,mpc_trace}.jl`, `src/TSODSO.jl`, `docs/src/api.md`
**Files scanned:** ~12 (plus RESEARCH/CONTEXT)
**Pattern extraction date:** 2026-10-03
