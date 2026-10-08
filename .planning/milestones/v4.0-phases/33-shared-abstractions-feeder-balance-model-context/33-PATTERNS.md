# Phase 33: Shared Abstractions — Feeder, Balance, Model Context - Pattern Map

**Mapped:** 2026-10-03
**Files analyzed:** 22 new/modified file groups
**Analogs found:** 22 / 22 (this is a refactor: every new file has an in-repo analog; most "analogs" are the very code being refactored)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/data/Feeder.jl` (add `AbstractFeeder{T}` + `<:`) | model (data) | transform | itself + `src/data/MeshedFeeder.jl` | exact |
| `src/data/MeshedFeeder.jl` (`<: AbstractFeeder{T}`) | model (data) | transform | `src/data/Feeder.jl:57-72` | exact |
| `src/powerflow/AbstractPowerFlow.jl` (add `has_reactive`, `has_branch_current`) | seam / trait | request-response | `src/solver/problem_class_trait.jl` (`problem_class(::X)` trait) | role-match |
| `src/powerflow/{DC,LinDist,Convex,Restricted,Meshed,AC}*.jl` (trait methods, `ctx.pf=`, `ctx.pf_vars=`, invalid-pair methods, `_contribute_convex!`) | formulation | CRUD (residual writes) | `src/powerflow/MeshedFlow.jl:79-85` (`problem_class(::MeshedFlow)` one-liner after `contribute!`) | exact |
| `src/core/balance.jl` (NEW `close_balance!`) | utility | CRUD | `src/models/welfare_solve.jl:236-251`; anonymous form `src/models/stochastic_welfare.jl:348-365` | exact |
| `src/core/ModelContext.jl` (typed struct) | model/core | CRUD | itself (`:51-65`) | exact |
| `src/TSODSO.jl` (include order) | config | n/a | itself `:45-54` | exact |
| `src/models/welfare_solve.jl` | model builder | request-response | itself | exact |
| `src/models/linear_solve.jl` | model builder | request-response | `welfare_solve.jl` | exact |
| `src/models/mpc_window.jl` | model builder | event-driven (re-solve) | `welfare_solve.jl` | role-match |
| `src/models/stochastic_welfare.jl` (2 sites) | model builder | batch | `welfare_solve.jl` | role-match |
| `src/admm/DsoOpt.jl` (balance, `reactive=true`) | model builder | request-response | `welfare_solve.jl` | role-match |
| `src/admm/AgrOpt.jl`, `src/devices/Aggregator.jl` (typed `objective`/`agg_device_vars`) | device / service | CRUD | `ModelContext.add_to_objective!` | exact |
| Reader migration: `models/exactness.jl`, `ac_oracle.jl`, `restriction_exactness.jl`, `mesh_angle_certificate.jl`, `complementarity_4q.jl`, `pricing/{welfare,dlmp,checks,fit}.jl`, `planning/*`, `experiments/mpc_loop.jl` | consumers | request-response | `welfare_solve.jl:275` gate site | exact |
| `test/test_abstract_feeder.jl` (NEW) | test | request-response | `test/test_mesh_flow.jl`, `test/test_mesh_feeder.jl` | role-match |
| `test/test_close_balance.jl` (NEW) | test | CRUD | `test/test_context.jl` | role-match |
| `test/test_model_context_traits.jl` (NEW) | test | request-response | `test/test_context.jl` | role-match |
| `test/test_context.jl` (modified) | test | CRUD | itself | exact |
| `test/test_pricing_dlmp.jl` (hand-built ctx needs `ctx.pf`) | test | request-response | itself `:85-103` | exact |
| Grep-gate testitem (NEW, last plan) | test | file-I/O | `test/test_pricing_fit.jl:306` (reads `src/` text) | exact |
| `docs/src/api.md` | config | n/a | itself (`@autodocs` Pages lists, lines 29/45/70) | exact |
| `docs/literate/*.jl`, `scripts/*.jl` (key migration) | docs | n/a | grep-gate list | exact |

## Pattern Assignments

### `src/data/Feeder.jl` and `src/data/MeshedFeeder.jl` (model, transform)

**Analog:** `src/data/Feeder.jl:57-72` (inner-constructor gate), `src/data/MeshedFeeder.jl:42-57`.

Current struct (to change only the header, bodies unchanged):
```julia
struct Feeder{T <: Real}                       # -> struct Feeder{T <: Real} <: AbstractFeeder{T}
    buses::Vector{Bus{T}}
    branches::Vector{Branch{T}}
    root::Int
    function Feeder{T}(buses::Vector{Bus{T}}, branches::Vector{Branch{T}}, root::Int) where {T <: Real}
        feeder = new{T}(buses, branches, root)
        assert_radial(feeder.buses, feeder.branches, feeder.root)  # DATA-02
        assert_magnitudes(feeder)                                  # INFRA-05
        return feeder
    end
end
```
`MeshedFeeder` is identical except `assert_connected(...)`. Put `abstract type AbstractFeeder{T<:Real} end` (with docstring documenting the `buses/branches/root` contract) BEFORE `struct Feeder` in `Feeder.jl` (after `Bus`/`Branch`), since `Feeder.jl` loads first (`TSODSO.jl:18`) and `MeshedFeeder.jl` loads at `:28`. If a new file is used, add it to the `docs/src/api.md:45` Pages list. Export style: follow `export` line at file bottom (e.g. `export ModelContext, ...` in ModelContext.jl:161).

Only existing `::Feeder` annotation: `src/models/toy_dc.jl:41` `function solve_toy_dc(feeder::Feeder)` (keep or loosen to `AbstractFeeder`; also `toy_dc.jl:44` `ctx.meta[:feeder] = feeder` -> `ctx.feeder = feeder`).

Struct-parameter constraints to tighten (`F` -> `F<:AbstractFeeder`): `PlanningOracle{Z,PC,PI,F}` `planning/subproblem.jl:59,67`; `FeasibilityOracle` `feasibility_oracle.jl:56,65`; `DsoOpt{P,Q,PI,F}` `admm/DsoOpt.jl:85,93`; `MpcWindow{F}` `mpc_window.jl:63,68`; `StochasticOosHarness{F}` `stochastic_welfare.jl:552,556`.

---

### `src/powerflow/AbstractPowerFlow.jl` — traits (seam, request-response)

**Analog:** the file itself (`:21`, `:34`, `:36`) plus the per-formulation one-liner trait pattern at `src/powerflow/MeshedFlow.jl:85` (`problem_class(::MeshedFlow) = SOCP()`, with a comment, placed after `contribute!` in the formulation's own file).

Add beside `function contribute! end` (`AbstractPowerFlow.jl:34`):
```julia
has_reactive(::AbstractPowerFlow) = true            # contribute! writes :Rq
has_branch_current(::AbstractPowerFlow) = false     # default: no :l
has_branch_current(::Nothing) = false               # unset ctx.pf == absent pf_vars
```
and per-file one-liners (each concrete formulation file loads after `AbstractPowerFlow.jl`):
`has_reactive(::DCPowerFlow) = false` in `DCPowerFlow.jl`; `has_branch_current(::ConvexBranchFlow|::RestrictedBranchFlow|::MeshedFlow|::ACPowerFlow) = true` in their own files. Update export line (`AbstractPowerFlow.jl:36`) and docstrings (checkdocs = :exports needs a docstring for each exported trait). Update the docstring at `:28-32`, which says assembly keys off `haskey(ctx.residuals, :Rq)`.

---

### Formulation files: `ctx.pf`/`ctx.pf_vars` writes, invalid-pair methods, `_contribute_convex!` (formulation, CRUD)

**Analog:** `src/powerflow/ConvexBranchFlow.jl:204` (`contribute!(pf::ConvexBranchFlow, ctx::ModelContext, feeder; T::Int = 1)`), stash at `:356`:
```julia
    ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)
    return ctx
```
-> `ctx.pf_vars = (; v, v̂, P, Q, l); ctx.pf = pf` (assign `ctx.pf` LAST).

Delegation sites to re-point at an internal body (Pitfall 1/2):
`src/powerflow/MeshedFlow.jl:79-83`:
```julia
function contribute!(pf::MeshedFlow, ctx::ModelContext, feeder; T::Int = 1)
    contribute!(ConvexBranchFlow(), ctx, feeder; T = T)
    ctx.meta[:formulation] = :MeshedFlow   # provenance (KEEP in meta)
    return ctx
end
```
`src/powerflow/RestrictedBranchFlow.jl:210-213`:
```julia
function contribute!(pf::RestrictedBranchFlow, ctx::ModelContext, feeder; T::Int = 1)
    contribute!(ConvexBranchFlow(), ctx, feeder; T = T)
    pv = ctx.meta[:pf_vars]          # -> pv = ctx.pf_vars
    N = length(feeder.buses)
```
Plan: rename the Convex body to `_contribute_convex!(ctx, feeder::AbstractFeeder; T)`; public `contribute!(pf::ConvexBranchFlow, ctx, feeder::Feeder; T)` calls it then sets `ctx.pf = pf`; MeshedFlow/Restricted call `_contribute_convex!` then set `ctx.pf = pf` last. Invalid-pair methods (user decision) are per-(SpecificPF, MeshedFeeder) only (Pitfall 8, avoid `(AbstractPowerFlow, MeshedFeeder)` ambiguity):
```julia
contribute!(pf::RestrictedBranchFlow, ::ModelContext, ::MeshedFeeder; T::Int = 1) =
    throw(ArgumentError("RestrictedBranchFlow requires a radial Feeder; got MeshedFeeder (use MeshedFlow)"))
# same for ConvexBranchFlow and LinDistFlow; DCPowerFlow, ACPowerFlow, MeshedFlow stay allowed (::AbstractFeeder)
```
`DCPowerFlow.jl:45` (`contribute!(::DCPowerFlow, ctx, feeder; T)`): set `ctx.pf = pf` only; never sets `pf_vars` (stays `nothing`). `LinDistFlow.jl:97` stashes `(; v, P, Q)`; `ACPowerFlow.jl:280` stashes `(; v, P, Q, l)`.

---

### `src/core/balance.jl` — `close_balance!` (utility, CRUD)

**Analog (exact):** `src/models/welfare_solve.jl:236-251` (named) and the already-anonymous `src/models/stochastic_welfare.jl:348-365`.

welfare_solve source to replace (lines 240-251):
```julia
    size(ctx.residuals[:Rp]) == (Np, T) || error(
        "residual :Rp is $(size(ctx.residuals[:Rp])), expected ($Np, $T) — an index escaped the feeder",
    )
    @constraint(model, balance_p[j = 1:Np, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
    register_constraint!(ctx, :balance_p, balance_p)          # dual = λ_j (DADP)
    if reactive
        size(ctx.residuals[:Rq]) == (Np, T) || error(
            "residual :Rq is $(size(ctx.residuals[:Rq])), expected ($Np, $T) — an index escaped the feeder",
        )
        @constraint(model, balance_q[j = 1:Np, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
        register_constraint!(ctx, :balance_q, balance_q)
    end
```
Anonymous form to copy (`stochastic_welfare.jl:353-356`):
```julia
        balance_p_s =
            @constraint(model, [j = 1:Np, t = 1:T], ctx_s.residuals[:Rp][j, t] == 0)
        register_constraint!(ctx_s, :balance_p, balance_p_s)
```
Stochastic error prefix (`:350-352`): `"scenario $s residual :Rp is ..., expected " * "($Np, $T) — an index escaped the feeder"` -> `label = "scenario $s "`. Full helper body is given verbatim in 33-RESEARCH.md lines 187-200 (add `base_name = "balance_p"` / `"balance_q"`, return `(bp, bq)`). Include after `ModelContext.jl` (needs `register_constraint!`, `:77`), add `core/balance.jl` to `docs/src/api.md:29` Pages, export it.

Per-site rewrite specifics:
- `welfare_solve.jl:240-251` -> `balance_p, balance_q = close_balance!(ctx, Np, T; reactive = has_reactive(pf))`; the `balance_p` local is used at `:297` (`dual.(balance_p[priced,:])`). Drop `reactive = haskey(ctx.residuals, :Rq)` at `:179` (still needed for the `q_import` block `:228` -> use `has_reactive(pf)`).
- `linear_solve.jl:~120-146`: reactive is `haskey(ctx.residuals, :Rq)` evaluated after devices; replace with `has_reactive(pf)`. KEEP the WR-03 invariant comment (`:132-142`) beside the call. `balance_p` used at `:159`.
- `mpc_window.jl:~208-221`: loop var `τ`, horizon `H`; `has_reactive(pf)` replaces captured `reactive` (`:189`); `N, H` passed. Reads `ctx.constraints` afterwards, no local needed.
- `stochastic_welfare.jl:348-365`: `close_balance!(ctx_s, Np, T; reactive = has_reactive(pf), label = "scenario $s ")`; `reactive_s` (`:313`) becomes `has_reactive(pf)`.
- `stochastic_welfare.jl:681-696` (OOS harness): bare text, `(N, T)`.
- `admm/DsoOpt.jl:463-475`: `close_balance!(ctx, N, T; reactive = true)` (unconditional). Frontier / transit-node zero injections (`add_to_residual!(ctx, :Rq, j, t, 0.0)` at `:460`) stay in the caller.

---

### `src/core/ModelContext.jl` — typed struct (core, CRUD)

**Analog:** itself, `:51-65` (struct + `ModelContext(model)` constructor) and `add_to_objective!` `:156-159`.

Current:
```julia
mutable struct ModelContext
    model::Model
    constraints::Dict{Symbol, Any}
    residuals::Dict{Symbol, Any}
    meta::Dict{Symbol, Any}
end
ModelContext(model::Model) =
    ModelContext(model, Dict{Symbol, Any}(), Dict{Symbol, Any}(), Dict{Symbol, Any}())
```
Target struct and constructor are in 33-RESEARCH.md lines 411-425 (Union fields `feeder`, `T::Int` (0=unset), `pf`, `pf_vars`, `objective::QuadExpr`, `agg_device_vars::Dict{Int,Vector{Any}}`). Style: keep the existing `Dict{Symbol, Any}` spacing/format (JuliaFormatter), keep `using JuMP` at `:29`.

`add_to_objective!` rewrite (`:156-159`):
```julia
function add_to_objective!(ctx::ModelContext, expr)
    ctx.objective = ctx.objective + expr     # first add == zero(QuadExpr) + expr (bit-identical)
    return ctx.objective
end
```
Rewrite docstrings at `:11`, `:25`, `:43-45`, `:109`, `:146-154` (they cite `ctx.meta[:objective]`/`ctx.meta[:feeder]`). Must preserve: `add_to_residual!` indexed variant consults no feeder (`:109`; asserted by `test/test_context.jl:47-49`).

`src/TSODSO.jl`: move `include("powerflow/AbstractPowerFlow.jl")` (currently `:54`) above `include("core/ModelContext.jl")` (`:50`); `AbstractPowerFlow.jl` has no dependency on `ModelContext`. Add `include("core/balance.jl")` after ModelContext/before `core/status.jl` (or after status).

**Aggregator writer** (`src/devices/Aggregator.jl:241-242`):
```julia
    store = get!(ctx.meta, :agg_device_vars, Dict{Int, Vector{Any}}())
    append!(get!(store, agg.bus, Vector{Any}()), device_vars)
```
-> `append!(get!(ctx.agg_device_vars, agg.bus, Vector{Any}()), device_vars)`. NOTE: today the Dict is created even for zero devices; readers using `haskey(ctx.meta, :agg_device_vars)` (`welfare_solve:368`, `mpc_window:231`, `stochastic_welfare:702`, `complementarity_4q:123`) become `!isempty(ctx.agg_device_vars)` — check that an aggregator with zero devices does not change behaviour. Do NOT touch `linear_solve.jl:106` `meta[:device_vars]` (different value; stays in meta).

---

### Builder writes (`ctx.meta[:feeder]`/`[:T]` -> typed) (model builder)

**Analog:** `welfare_solve.jl:150-152`:
```julia
    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder
    ctx.meta[:T] = T
```
-> `ctx.feeder = feeder; ctx.T = T`. Same at `linear_solve:74`, `mpc_window:167` (`= H`), `stochastic_welfare:289,645`, `DsoOpt:387`, `AgrOpt:134` (T only), `pricing/fit.jl:169,467,543`, `planning/{subproblem:155, feasibility_oracle:117, master:252, bilevel_kkt:382, nash:1471}`, `experiments/mpc_loop.jl:1336,1569`.

**Readers with unset-state hazard (Pitfall 3):** kwarg defaults `T = ctx.meta[:T]` at `pricing/welfare.jl:75`, `pricing/checks.jl:74`, `welfare_solve.jl:302,363`, `complementarity_4q.jl:25,120` become `T = ctx.T` — silently 0 on a bare ctx. Add a loud guard, e.g. a tiny checked accessor in `ModelContext.jl`:
```julia
_require_T(ctx) = ctx.T > 0 ? ctx.T : throw(ArgumentError("ModelContext.T is unset"))
```
`pricing/checks.jl:123` `get(ctx.meta, :feeder, nothing)` -> `ctx.feeder` (already nothing-tolerant).

---

### `haskey(pf_vars, :l)` gate sites -> `has_branch_current` (consumer, request-response)

**Analog:** `src/models/welfare_solve.jl:275-277`:
```julia
    if haskey(ctx.meta, :pf_vars) && haskey(ctx.meta[:pf_vars], :l)
        ctx.meta[:socp_maxgap] = assert_socp_exact!(ctx; rtol = rtol_exact)
    end
```
-> `if has_branch_current(ctx.pf)` (keep `ctx.meta[:socp_maxgap]` write in meta). Other four:
- `stochastic_welfare.jl:449`: `has_branch_current(ctxs[s].pf)` (keep per-scenario push to `socp_maxgap`).
- `planning/subproblem.jl:352`: `has_branch_current(o.ctx.pf)`, keep the try/`on_inexact` structure.
- `pricing/dlmp.jl:112-115` (`_assert_priceable`): `has_branch_current(ctx.pf) && !haskey(ctx.meta, :socp_maxgap)` -> `ArgumentError`; also update message text mentioning `ctx.meta[:socp_maxgap]` only if key changes (it does not).
- `pricing/fit.jl:522`: `has_cone = has_branch_current(pf)` (`pf` is in scope, per research) — or `seed_ctx.pf`.
- `test/fixtures_phase19.jl:357`: test copy of the same gate.
Hand-built test contexts must set `ctx.pf`: `test/test_pricing_dlmp.jl:85-103` (`ctx.meta[:pf_vars] = (; l = x)` -> `ctx.pf_vars = (; l = x); ctx.pf = ConvexBranchFlow()`; second ctx `(; P = x)` -> `ctx2.pf = LinDistFlow()`).

`pf_vars` readers needing the `nothing` branch (Pitfall 4): `exactness.jl:177,302,366`, `ac_oracle.jl:69,179,316-317`, `restriction_exactness.jl:246`, `mesh_angle_certificate.jl:186`, `ac_recheck.jl:139`, `pricing/fit.jl:580,581,638`, `experiments/mpc_loop.jl:698,865,1405,1607`. Fix stale comment `models/exactness.jl:~230` (MeshedFlow DOES run `assert_socp_exact!`).

---

### New tests

**`test/test_close_balance.jl`, `test/test_model_context_traits.jl`, `test/test_abstract_feeder.jl`**

**Analog:** `test/test_context.jl:1-20` (testitem skeleton; bare ctx on an LP model):
```julia
@testitem "context: ModelContext residual registry accumulates with no branching (PF-01)" begin
    using TSODSO, JuMP

    model = Model(TSODSO.select_optimizer(TSODSO.LP()))
    @variable(model, p >= 0)
    ctx = TSODSO.ModelContext(model)
    ...
    TSODSO.register_constraint!(ctx, :balance, c)
    @test ctx.constraints[:balance] === c
end
```
Use `tags = [:context]` as in `test_context.jl:21-22`. Qualify with `TSODSO.` (unexported helpers). Beware testitem soft-scope trap (memory): wrap loops reassigning outer vars in a function/`let`. Trait-equivalence loop over the six formulations: build a 2-bus `Feeder` (see `test/test_mesh_flow.jl`/`test_feeder.jl` for fixture construction), `contribute!(pf, ctx, feeder; T=1)`, assert `has_reactive(pf) == haskey(ctx.residuals,:Rq)`, `has_branch_current(pf) == (ctx.pf_vars !== nothing && haskey(ctx.pf_vars,:l))`, `typeof(ctx.pf) == typeof(pf)`. Invalid-pair test: `@test_throws ArgumentError contribute!(RestrictedBranchFlow(), ctx, meshed; T=1)`; valid: `MeshedFlow` on both feeder kinds (analog: `test_mesh_flow.jl` "assert_socp_exact! both pass").

**Migrate** `test/test_context.jl:47-49` (`@test !haskey(ctx.meta, :feeder)` -> `@test ctx.feeder === nothing`), `:74-80` (`haskey(ctx.meta,:objective)` -> `ctx.objective isa QuadExpr` and `!isempty(ctx.objective.terms)`). "Untouched objective" asserts (`test_pvbattery:203`, `test_fourquadbess:412`, `test_deferrable:97`, `test_device:46`, `test_thermostatic:207`) -> `iszero(ctx.objective)` style (verify predicate in REPL first, A6). Presence asserts (`test_ac_powerflow:62`, `test_convex_branch_flow:58`, `test_dso:42`, `test_planning_oracle:335`) -> `ctx.pf_vars !== nothing`. Bare ctx `test_fourquadbess.jl:461-574`: `ctx.meta[:T] = 3` -> `ctx.T = 3`.

**Grep-gate testitem — analog `test/test_pricing_fit.jl:306-311`:**
```julia
    src = read(joinpath(dirname(pathof(TSODSO)), "pricing", "fit.jl"), String)
    idx = findfirst("function fit_baseline(", src)
```
Walk `src/`, `test/`, `docs/literate/`, `scripts/`; regex over `meta\[:(pf_vars|T|feeder|objective|agg_device_vars)\]` and `(haskey|get|get!)\(\s*[\w.]*meta,\s*:(...)`; exclude the gate file itself; add in the LAST migration plan only.

**Fingerprint testitem (Wave 0):** capture `[name(c) for c in all_constraints(model; include_variable_in_set_constraints=false)]` order of a tiny `solve_welfare` model into a literal list BEFORE the `close_balance!` migration (use `test_welfare_solve.jl` fixtures); keep green after.

---

### `docs/src/api.md` (config)

**Analog:** itself. `@autodocs` with `Pages = [...]` file lists: Core (`:29`) `["core/ModelContext.jl", "core/status.jl"]` -> add `"core/balance.jl"`; Network Data Model (`:45`) add new data file only if `AbstractFeeder` gets its own file (recommend putting it in `Feeder.jl` to avoid this); Power-Flow list (`:70`) already includes `AbstractPowerFlow.jl`. Every new exported symbol (`AbstractFeeder`, `close_balance!`, `has_reactive`, `has_branch_current`) needs a docstring or `checkdocs = :exports` fails.

## Shared Patterns

### Construction-is-the-gate / loud failure
**Source:** `src/data/Feeder.jl:62-71` and `ModelContext.jl:92-97` (`error("... refusing ...")`).
**Apply to:** invalid-pair methods (`ArgumentError` naming the pair), `close_balance!` size check, unset `ctx.T`/`ctx.feeder` readers. Never default silently.

### Trait-by-dispatch instead of `haskey`/`if formulation ==`
**Source:** `src/powerflow/MeshedFlow.jl:85` (`problem_class(::MeshedFlow) = SOCP()`) and `src/solver/problem_class_trait.jl`.
**Apply to:** `has_reactive`, `has_branch_current` — one-liner per formulation in its own file, documented on the abstract type.

### `ctx.pf` assigned LAST in every concrete `contribute!`
**Source:** Pitfall 1 (research). **Apply to:** all six `contribute!` methods; delegating formulations call `_contribute_convex!`, not the public method.

### Provenance stays in `meta`
`ctx.meta[:formulation]` (`RestrictedBranchFlow.jl:~317`, `MeshedFlow.jl:81`), `:socp_maxgap`, `:p_import`, `:q_import`, `:qag_dso`, `:agg_net`, `:price_provenance`, `:restriction_ε`, `linear_solve.jl:106` `:device_vars` stay untouched. `store.jl:97-99` (`:feeder => s.feeder`, `:T => s.T`) is a result Dict, not `ctx.meta` — do not touch.

### Test-run conventions (memory)
Targeted: `JULIA_LOAD_PATH="@:.:test:@stdlib" julia --project=. -e 'using TestItemRunner; TestItemRunner.run_tests(joinpath(pwd(),"test"); filter = ti -> endswith(ti.filename, "test_<name>.jl"))'`. Plan `<verify>` blocks use direct Test.jl scripts with `JULIA_LOAD_PATH="test:.:@stdlib"`, never TestItemRunner. Full suite detached by orchestrator; baseline 31782/0/0/5. Do not commit `Project.toml`/`Manifest.toml` drift; do not raise exactness thresholds.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `has_branch_current(::Nothing)` / typed `Union{Nothing,...}` ModelContext fields | trait / struct | n/a | No existing Union-typed field context in repo; use research design (33-RESEARCH.md §5, lines 411-425). |
| Transient `meta` mirror shim (Wave 3 only) | core | CRUD | New, temporary; must be removed in the last migration plan (grep gate proves it). |

## Metadata

**Analog search scope:** `src/{core,data,powerflow,models,admm,devices,pricing,planning,experiments}`, `test/`, `docs/src/api.md`, `src/TSODSO.jl`
**Files read:** ModelContext.jl, TSODSO.jl, AbstractPowerFlow.jl, Feeder.jl, MeshedFeeder.jl (struct), welfare_solve.jl (145-295), balance excerpts from linear_solve/mpc_window/stochastic_welfare/DsoOpt, ConvexBranchFlow/DCPowerFlow/MeshedFlow/RestrictedBranchFlow excerpts, Aggregator.jl excerpt, test_context.jl, test_pricing_dlmp.jl excerpt
**Pattern extraction date:** 2026-10-03
