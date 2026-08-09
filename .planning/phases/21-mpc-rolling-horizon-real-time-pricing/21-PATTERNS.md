# Phase 21: MPC / Rolling-Horizon / Real-Time Pricing - Pattern Map

**Mapped:** 2026-08-09
**Files analyzed:** 9 new + 3 modified (device files) = 12
**Analogs found:** 12 / 12 (all files have a strong analog; zero "no analog" entries)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/models/mpc_window.jl` (NEW) | model/service (JuMP builder) | request-response (build-once, re-solve-many) | `src/planning/subproblem.jl` (`PlanningOracle`) | exact |
| `src/experiments/mpc_loop.jl` (NEW) | service/orchestrator | event-driven (stepped loop over time) | `src/planning/subproblem.jl` + `src/models/oracle.jl` (`operational_oracle`) | role-match |
| `src/models/mpc_trace.jl` (NEW) | model (diagnostics ledger) | event-driven (append-only record) | `src/admm/residuals.jl` (`AdmmResiduals`) | exact |
| `src/devices/PVBattery.jl` (MODIFIED) | device (JuMP contribute!) | CRUD (constraint/var mutation via Parameter) | `src/planning/subproblem.jl:194-195` (`z in Parameter`) applied to own file | exact (self + oracle precedent) |
| `src/devices/Thermostatic.jl` (MODIFIED) | device (JuMP contribute!) | CRUD (constraint/var mutation via Parameter) | same as above | exact |
| `src/devices/FourQuadBESS.jl` (MODIFIED) | device (JuMP contribute!) | CRUD (constraint/var mutation via Parameter) | same as above | exact |
| `test/test_mpc_window.jl` (NEW) | test | request-response (build-once regression) | `test/test_planning_oracle.jl:59-88` | exact |
| `test/test_mpc_terminal.jl` (NEW, or folded) | test | request-response (A/B regression) | `test/test_planning_oracle.jl` + Phase-20 A/B-style certificate tests | role-match |
| `test/test_mpc_trace.jl` (NEW) | test | event-driven (ledger append) | `test/test_admm_residuals.jl` (sequential-`k` guard tests) | exact |
| `test/test_mpc_loop.jl` (NEW) | test | integration (end-to-end closed loop) | `test/test_planning_oracle.jl` (integration section) + Phase-20 certificate-ladder tests | role-match |
| `docs/literate/mpc_rolling_horizon.jl` (NEW) | docs (literate rung page) | batch (live-executed demonstration) | `docs/literate/restricted_branch_flow.jl` | exact |
| `src/experiments/Scenario.jl` (MODIFIED, additive fields) | config/model (`@kwdef` struct) | CRUD (construction + validation) | itself (extend existing pattern in-place) | exact |

## Pattern Assignments

### `src/models/mpc_window.jl` (model/service, build-once request-response)

**Analog:** `src/planning/subproblem.jl` (`PlanningOracle` / `build_planning_oracle` / `solve_planning_oracle!`)

**Imports pattern** (subproblem.jl:28):
```julia
using JuMP
```
No other imports — the module relies on already-`using`'d project types (`ModelContext`, `contribute!`, `select_optimizer`, `problem_class`, `add_to_residual!`, `register_constraint!`, `solve_with_retry!`, `assert_socp_exact!`, `assert_battery_complementarity!`) exactly as `subproblem.jl` does. Mirror this — no new package imports (RESEARCH: zero new runtime packages).

**Struct shape** (subproblem.jl:59-69):
```julia
struct PlanningOracle{Z, PC, PI, F}
    model::Model
    ctx::ModelContext
    z::Z
    pin::PC
    p_import::PI
    agg_bus::Int
    T::Int
    feeder::F
    λ₀::Vector{Float64}
end
```
Copy this shape for a new `MpcWindow{...}` struct: `model::Model`, `ctx::ModelContext`, the per-device `Parameter` handles (`soc0` / `Tin0` / terminal-target handles, keyed by bus or device index), `agg_bus::Int`, `H::Int` (window length), `feeder`, and a mutable or separately-tracked `λ₀_window`/`t_offset` for the `set_objective_coefficient` slide (Pattern 2 below — NOT a field the struct mutates via `Parameter`, since it moves via objective-coefficient updates, not model state).

**Build-once construction pattern** (subproblem.jl:110-211, esp. 130-149 boundary/model-build, 194-198 the Parameter+pin+objective seam):
```julia
model = Model(select_optimizer(problem_class(pf)))
JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)
ctx = ModelContext(model)
ctx.meta[:feeder] = feeder
ctx.meta[:T] = T
ctx.meta[:problem_class] = problem_class(pf)
contribute!(pf, ctx, feeder; T = T)
# ... aggregator contribute! loop, residual closing, balance_p/balance_q registration ...
@variable(model, z[t = 1:T] in Parameter(0.0))
@constraint(model, pin[t = 1:T], p_import[t] == z[t])
@objective(model, Max, ctx.meta[:objective] - sum(λ₀[t] * p_import[t] for t in 1:T))
```
For `mpc_window.jl`, build the SAME shape over a fixed window length `H` (Pitfall 5 fixed-window convention, RESEARCH), reusing `contribute!(pf,...)`/`contribute!(agg,...)` verbatim, NEVER calling `solve_welfare` itself (Anti-Pattern in RESEARCH). Register `balance_p`/`balance_q` exactly like `subproblem.jl:180-189`.

**Re-solve pattern (Parameter-only, no rebuild)** (subproblem.jl:267-313):
```julia
set_parameter_value.(o.z, z_trial)
solve_with_retry!(o.model; max_attempts = max_attempts, dual = true, attempts_out = attempts_out)
if haskey(o.ctx.meta, :pf_vars) && haskey(o.ctx.meta[:pf_vars], :l)
    o.ctx.meta[:socp_maxgap] = assert_socp_exact!(o.ctx; rtol = rtol_exact)
end
assert_battery_complementarity!(o.ctx; τ = τ, T = o.T)
π = dual.(o.pin)
dadp = dual.(o.ctx.constraints[:balance_p][o.agg_bus, :])
cost = objective_value(o.model)
```
**Critical deviation from this analog for MPC-01:** `subproblem.jl`'s exactness gate is the THROWING `assert_socp_exact!` — D-04 forbids throwing mid-loop. Replace this call with Pattern 4's inline non-throwing reimplementation (see `restriction_exactness.jl` below), NOT a bare `try`/`catch` around `assert_socp_exact!` (RESEARCH Pitfall 3 / Anti-Pattern).

**Error handling pattern** (subproblem.jl:117-128, guard style):
```julia
isempty(aggregators) &&
    throw(ArgumentError("build_planning_oracle needs at least one aggregator"))
length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
for (k, agg) in enumerate(aggregators)
    1 <= agg.bus <= N || throw(ArgumentError("aggregator[$k] bus=$(agg.bus) is outside feeder buses 1:$N"))
end
```
Copy this "throw `ArgumentError`, never `@assert`" boundary-guard idiom verbatim for `build_mpc_window`'s own boundary checks (H ≤ T, terminal-SOC trajectory length, etc.).

---

### Device `Parameter`-widening pattern — `src/devices/PVBattery.jl`, `Thermostatic.jl`, `FourQuadBESS.jl` (device, CRUD constraint mutation)

**Analog:** `src/planning/subproblem.jl:194-195` (the `z in Parameter(0.0)` idiom), applied additively inside each device's own `contribute!`.

**PVBattery.jl — current IC constraint** (`PVBattery.jl:253`, full `contribute!` body at lines 233-291):
```julia
@constraint(m, soc[1] == d.soc0)                                          # (3.9 IC)
```
**Rewrite (additive, byte-identical default):**
```julia
@variable(m, soc0 in Parameter(d.soc0))
@constraint(m, soc[1] == soc0)
```
Return-tuple widening (`PVBattery.jl:290`, current):
```julia
return (; vars = (; p_ch, p_dch, soc, pv_used), p_inject, utility)
```
becomes (additive key, mirrors the `q_inject` widening precedent in `AbstractDevice.jl:67-80`):
```julia
return (; vars = (; p_ch, p_dch, soc, pv_used, soc0), p_inject, utility)
```
**Pitfall 4 (PV bound → constraint rewrite):** `pv_used`'s current declaration bakes `Ppv[t]` as a literal `upper_bound` (`PVBattery.jl:251`):
```julia
pv_used = @variable(m, [t = 1:T], lower_bound = 0.0, upper_bound = d.Ppv[t])
```
A `Parameter` cannot be passed as `upper_bound=`. If the forecast-slice PV profile must move per-window (D-08), rewrite as:
```julia
pv_used = @variable(m, [t = 1:T], lower_bound = 0.0)
@variable(m, Ppv_param[t = 1:T] in Parameter.(d.Ppv[1:T]))
@constraint(m, [t = 1:T], pv_used[t] <= Ppv_param[t])
```

**Thermostatic.jl — current IC constraint** (`Thermostatic.jl:237`, full `contribute!` body at lines 219-253):
```julia
@constraint(m, Tin[1] == d.Tin0)
@constraint(m, [t = 1:(T - 1)], Tin[t + 1] == Tin[t] + d.α * (d.Tout[t] - Tin[t]) - d.β * p[t])
```
**Rewrite:**
```julia
@variable(m, Tin0 in Parameter(d.Tin0))
@constraint(m, Tin[1] == Tin0)
```
`Tout[t]` is SAFER to Parameterize (per RESEARCH Pitfall 4) — it already enters as an additive term inside an equality, not a bound:
```julia
@variable(m, Tout_param[t = 1:(T-1)] in Parameter.(d.Tout[1:(T-1)]))
@constraint(m, [t = 1:(T - 1)], Tin[t + 1] == Tin[t] + d.α * (Tout_param[t] - Tin[t]) - d.β * p[t])
```
Return-tuple widening (`Thermostatic.jl:252`, current `return (; vars = (; p, Tin), p_inject, utility)`) becomes `(; vars = (; p, Tin, Tin0), p_inject, utility)`.

**FourQuadBESS.jl — current IC constraint** (`FourQuadBESS.jl:300`, full `contribute!` body at lines 289-345):
```julia
@constraint(m, soc[1] == d.soc0)
```
**Rewrite:** identical idiom to `PVBattery.jl` — `@variable(m, soc0 in Parameter(d.soc0)); @constraint(m, soc[1] == soc0)`, widen return (currently line 344: `return (; vars = (; p_ch, p_dch, soc, q), p_inject, q_inject = q, utility)`) to `(; vars = (; p_ch, p_dch, soc, q, soc0), p_inject, q_inject = q, utility)`.

**Why this is safe (no bilinear risk):** every one of these ICs is a pure additive constant on an equality RHS — never multiplied by a decision variable — the SAME shape as `PlanningOracle`'s `z`/`p_import[t] == z[t]` pin, NOT the shape of ADMM's price coefficient (Pattern below).

**Terminal-SOC wiring** (MPC-02, new code, no existing device-level analog — build inside `mpc_window.jl`'s per-battery wiring, not inside the device file itself):
```julia
@variable(m, soc_terminal_target in Parameter(soc_da[bus][H]))
terminal_pin = @constraint(m, soc[H] == soc_terminal_target)
```
Toggle for the MPC-02 negative-control regression: guard behind a `terminal_soc::Bool` build-time kwarg (one rebuild per regression A/B run — acceptable, NOT the hot per-step loop).

---

### `src/models/mpc_trace.jl` — `MpcTrace` (diagnostics, event-driven ledger)

**Analog:** `src/admm/residuals.jl` (`AdmmResiduals`)

**Struct + constructor pattern** (`residuals.jl:63-99`):
```julia
mutable struct AdmmResiduals
    N::Int
    T::Int
    primal_trace::Vector{Float64}
    dual_trace::Vector{Float64}
    rho_trace::Vector{Float64}
    eps_pri_trace::Vector{Float64}
    eps_dual_trace::Vector{Float64}
    price_gap_trace::Vector{Float64}
    iters::Int
end
AdmmResiduals(N::Integer, T::Integer) = AdmmResiduals(Int(N), Int(T), Float64[], Float64[], Float64[], Float64[], Float64[], Float64[], 0)
AdmmResiduals() = AdmmResiduals(0, 0)
```
Copy this shape for `MpcTrace`: fields `dadp_trace::Vector{Float64}` (published price per step), `jump_trace::Vector{Float64}` (|Δprice| step-to-step), `cum_deviation_trace::Vector{Float64}` (cumulative |published − day-ahead| deviation), `cert_status_trace::Vector{Symbol}` (`:certified_convex_dual` / `:cert_failed` / `:local_ac_dual`, mirroring Phase-20's `price_provenance.status` vocabulary — see `restriction_exactness.jl:294-298` and `ac_dual_fallback.jl:121`), `steps::Int`.

**Sequential-`k` fail-loud guard** (`residuals.jl:101-107`):
```julia
@inline function _assert_sequential(res::AdmmResiduals, k::Integer)
    expected = res.iters + 1
    k == expected || throw(ArgumentError("record!: expected sequential iteration $expected, got k=$k"))
    return nothing
end
```
Copy verbatim (renamed) for `MpcTrace`'s `record!` — this is the exact idiom `test/test_admm_residuals.jl` tests against; mirror both the guard AND its test.

**`record!` pattern** (`residuals.jl:120-139`):
```julia
function record!(res::AdmmResiduals, k::Integer, primal::Real, dual::Real, ρ::Real, ε_pri::Real, ε_dual::Real, price_gap::Real)
    _assert_sequential(res, k)
    push!(res.primal_trace, abs(float(primal)))
    # ... push! each trace ...
    res.iters += 1
    return res
end
```
Same shape for `MpcTrace`'s `record!(trace, t, dadp, jump, cum_deviation, cert_status)`.

**Query predicate pattern** (`residuals.jl:169-192`, `converged`):
```julia
function converged(res::AdmmResiduals, ε_pri::Real, ε_dual::Real)
    res.iters == 0 && return false
    return last(res.primal_trace) <= ε_pri && last(res.dual_trace) <= ε_dual
end
```
Analogous query for `MpcTrace` if needed (e.g. `any_cert_failed(trace)`), same "empty ledger ⇒ false/no-op" convention.

**Export line** (`residuals.jl:194`): `export AdmmResiduals, record!, converged` — mirror with `export MpcTrace, record!, ...` (remember: every new exported symbol MUST be wired into `docs/src/api.md`'s `@autodocs` `Pages` list, per Phase-20's checkdocs lesson).

---

### `src/experiments/mpc_loop.jl` — orchestrator (service, event-driven stepped loop)

**Analog A (loop/dispatch shape):** `src/models/oracle.jl` (`operational_oracle`, lines 90-138) — for the "accept structured kwargs, dispatch to a builder, extract dual, return NamedTuple" shape and the loud `ArgumentError` guard style (`oracle.jl:105-110`).

**Analog B (price-slide-without-rebuild mechanics):** `src/admm/AgrOpt.jl:282-290` (`solve_agr!`'s coefficient update loop) — the per-step `set_objective_coefficient` pattern for sliding `λ₀`:
```julia
for t in 1:agr.T
    set_objective_coefficient(agr.model, agr.pag[t], -λ_j[t] - ρ * c_j[t])
end
```
For `mpc_loop.jl`'s per-step λ₀ slide:
```julia
for τ in 1:H
    set_objective_coefficient(window.model, window.p_import[τ], -λ0_window[τ])
end
```
**Never** wrap `λ₀` in a `Parameter` — see Anti-Pattern below (this is the DOCUMENTED, twice-hit `AgrOpt.jl:23-24`/`DsoOpt.jl:27,131` pitfall).

**Seeded forecast-error draw** (`src/experiments/materialize.jl:16-25`):
```julia
sub_seed(master::Integer, tag::Symbol) = Int(hash((master, tag)) % typemax(UInt32))
```
Use `sub_seed(scenario.seed, :mpc_forecast_error)` (a NEW independent tag, never reusing `:profiles`/`:population`) feeding a fresh `StableRNGs.LehmerRNG` per step draw — never `Random.seed!`/the global RNG.

**Per-step certificate dispatch (D-04, non-throwing inline check)** — analog: `src/models/restriction_exactness.jl:251-270` (inline reimplementation, not delegation):
```julia
cone_maxratio = 0.0
for (b, br) in enumerate(feeder.branches), t in 1:T
    lhs = value(pv.l[b, t]) * value(pv.v[br.from, t])
    rhs = value(pv.P[b, t])^2 + value(pv.Q[b, t])^2
    gap = abs(lhs - rhs)
    tol = cone_atol + cone_rtol * max(abs(lhs), abs(rhs))
    cone_maxratio = max(cone_maxratio, gap / tol)
end
step_certified = cone_maxratio <= 1     # NEVER throws
```
On failure, escalate per Phase-20's OWN ladder (`restriction_exactness.jl:228-322` → `ac_dual_fallback.jl:79-124`), publishing `price_status = :local_ac_dual` with `agreement_report`, and recording the status string into `MpcTrace` (never inventing a new tolerance/ladder — RESEARCH "Don't Hand-Roll").

**Error handling pattern (boundary guards):** `oracle.jl:105-110` style —
```julia
role in (:leader, :follower) || throw(ArgumentError("... expected :leader or :follower ..."))
```
Copy for `run_mpc`'s own guards (H ≤ T, step ≥ 1, forecast magnitude ∈ (0,1), etc.).

**Do NOT** wire this through `run_scenario`'s `strategy` dispatch (Pitfall 7) — give it its own entry point `run_mpc(scenario::Scenario; ...)` reading the new additive `Scenario` fields directly, mirroring how `oracle.jl`/`subproblem.jl` are called directly rather than through `run.jl`'s two-branch `if`/`elseif`.

---

### `src/experiments/Scenario.jl` (MODIFIED, additive `@kwdef` fields)

**Analog:** itself — extend the existing `Base.@kwdef struct Scenario` in place, following its own established idiom.

**Current field-plus-validation pattern** (`Scenario.jl:92-106` fields, `108-213` constructor validation):
```julia
Base.@kwdef struct Scenario
    name::String
    feeder::Symbol = :ieee13
    strategy::Symbol = :centralized
    ...
    ρ::Float64 = 100.0
    ...
    function Scenario(name::String, feeder::Symbol, ...)
        if feeder ∉ SCENARIO_VALID_FEEDERS
            throw(ArgumentError("Scenario: unknown feeder selector $(repr(feeder)); expected one of $(SCENARIO_VALID_FEEDERS)"))
        end
        ...
        if ρ <= 0
            throw(ArgumentError("Scenario: ρ must be > 0 (ADMM penalty); got ρ=$ρ"))
        end
        return new(name, feeder, strategy, ...)
    end
end
```
Add MPC fields (`mpc_H::Int`, `mpc_step::Int`, `mpc_terminal_soc::Bool`, `mpc_forecast_error::Float64`, etc. — naming at Claude's discretion) with defaults that are structurally no-ops for `:centralized`/`:admm` strategies (D-12/Pitfall 6), each guarded by the SAME "throw `ArgumentError`, never `@assert`" idiom as the existing `ρ`/`T`/`seed`/`maxiter` guards (lines 159-196). Update the inner constructor's positional-argument list AND the `return new(...)` call correspondingly — do NOT add a new `SCENARIO_VALID_STRATEGIES` entry (Pitfall 7 — this stays additive fields only, not a new dispatch branch).

**Do NOT touch** `SCENARIO_VALID_STRATEGIES` (`Scenario.jl:32`) or `run.jl`'s dispatch — confirmed by RESEARCH Pitfall 7/Open Question 4 resolution.

---

### `docs/literate/mpc_rolling_horizon.jl` (literate rung page)

**Analog:** `docs/literate/restricted_branch_flow.jl`

**Header/narrative pattern** (`restricted_branch_flow.jl:1-16`):
```julia
# # Rung N — <Title>
#
# <narrative connecting to the previous page's finding, citing the exact mechanism this
# page demonstrates, with literature citation if applicable>. Every number shown below is
# RECOMPUTED live during this page's build.

using TSODSO
using TSODSO.JuMP
```

**Fixture-construction pattern** (`restricted_branch_flow.jl:17-90`): inline, VERBATIM-constructed small fixture (feeder + `mem_price`/`temperature` literal vectors + `Bus`/`Branch`/`Feeder` construction) — literate pages do NOT load test-only fixture modules; build the small MPC CI-fixture-shaped scenario inline here too (mirroring the SAME construction idiom, scaled to `H`/short `T`).

**Wiring into `docs/make.jl`** (`make.jl:20-38` list, `62-70` `pages=` list):
```julia
for src in (
    ...
    "restricted_branch_flow.jl",
    ...
    "mpc_rolling_horizon.jl",   # NEW
)
    Literate.markdown(joinpath(LITERATE_DIR, src), GENERATED_DIR; flavor = Literate.DocumenterFlavor())
end
```
and add `"Rung N: MPC / RTP" => "generated/mpc_rolling_horizon.md"` to the `pages=` tree (`make.jl:62-70` region).

**Wiring into `docs/src/api.md`:** add a new `@autodocs` block (mirroring the `## Prosumer Devices & Aggregator` block at `api.md:49-60`) with `Pages = ["models/mpc_window.jl", "models/mpc_trace.jl", "experiments/mpc_loop.jl"]` — remember every new exported symbol (`MpcTrace`, `record!` overload, `build_mpc_window`, `run_mpc`, etc.) MUST appear here or the docs build fails (Phase-20 checkdocs lesson, cited in RESEARCH `<code_context>`/Integration Points).

---

### `test/test_mpc_window.jl` (unit, build-once regression)

**Analog:** `test/test_planning_oracle.jl:59-88`

**Build-once invariance idiom** (verbatim, `test_planning_oracle.jl:69-87`):
```julia
o = build_planning_oracle(feeder, LinDistFlow(), aggs; λ₀ = λ₀, T = T)
nv0 = num_variables(o.model)
nc0 = num_constraints(o.model; count_variable_in_set_constraints = true)

set_parameter_value.(o.z, fill(0.01, T))
optimize!(o.model)
set_parameter_value.(o.z, fill(-0.02, T))
optimize!(o.model)

@test num_variables(o.model) == nv0
@test num_constraints(o.model; count_variable_in_set_constraints = true) == nc0
```
Copy verbatim for `build_mpc_window`, cycling `set_parameter_value!` on `soc0`/`Tin0`/terminal-target Parameters (and `set_objective_coefficient` on λ₀) at several DIFFERENT measured states between the `num_variables`/`num_constraints` snapshot and its final assertion. `count_variable_in_set_constraints = true` is REQUIRED (`Parameter`s are variable-in-`MOI.Parameter`-set constraints — omitting this flag hides exactly what a rebuild would change).

**Test file structure** (`@testitem "..." tags = [:planning] setup = [Phase6Fixtures] begin ... end`, `test_planning_oracle.jl:59-60`): follow the SAME `@testitem`-with-`tags`-and-`setup` convention, using a small NEW `fixtures_phase21.jl`-style setup module per the RESEARCH Wave-0-Gaps recommendation (mirrors `fixtures_phase19.jl`/`fixtures_phase4.jl`).

---

### `test/test_mpc_trace.jl` (unit)

**Analog:** the ADMM residuals test file's sequential-`k` guard tests (mirror `AdmmResiduals`'s own tests — same file family as `residuals.jl`'s tests). Pattern: construct empty ledger, `record!` sequentially, assert `ArgumentError` on an out-of-order `k`, assert trace lengths stay equal after N records, assert query predicates on empty vs populated ledgers.

---

## Shared Patterns

### Build-once / re-solve via JuMP `Parameter` (additive constants only)
**Source:** `src/planning/subproblem.jl:194-195,279`
**Apply to:** `mpc_window.jl`'s window builder, all three device files' IC-constraint rewrites.
```julia
@variable(model, z[t = 1:T] in Parameter(0.0))
@constraint(model, pin[t = 1:T], p_import[t] == z[t])
# ... later:
set_parameter_value.(o.z, z_trial)   # mutate, NEVER rebuild
```

### Price-coefficient sliding via `set_objective_coefficient` (NEVER a `Parameter`)
**Source:** `src/admm/AgrOpt.jl:282-290`, `src/admm/DsoOpt.jl:128-131`
**Apply to:** `mpc_loop.jl`'s per-step λ₀ window slide.
```julia
for t in 1:agr.T
    set_objective_coefficient(agr.model, agr.pag[t], -λ_j[t] - ρ * c_j[t])
end
```

### Non-throwing, report-style certificate check (D-04)
**Source:** `src/models/restriction_exactness.jl:245-270` (inline reimplementation, NOT delegation to the throwing `assert_socp_exact!`)
**Apply to:** `mpc_loop.jl`'s per-step certificate dispatch.
```julia
cone_maxratio = max(cone_maxratio, gap / tol)  # accumulate, never error() here
step_certified = cone_maxratio <= 1
```

### Escalation ladder on certificate failure (D-04)
**Source:** `src/models/restriction_exactness.jl:228-322` → `src/models/ac_dual_fallback.jl:79-124`
**Apply to:** `mpc_loop.jl`, ONLY on `step_certified == false` — never invent a new tolerance/fallback path.

### Trace-struct convention (append-only, sequential-`k` guard, `abs`-normalized magnitudes)
**Source:** `src/admm/residuals.jl:63-194` (`AdmmResiduals`)
**Apply to:** `mpc_trace.jl`'s `MpcTrace`.

### Boundary guards: `throw(ArgumentError(...))`, never `@assert`
**Source:** project-wide convention, exemplified at `src/planning/subproblem.jl:119-128`, `src/experiments/Scenario.jl:127-196`, `src/models/oracle.jl:105-110`
**Apply to:** every new function's input validation (`build_mpc_window`, `run_mpc`, `Scenario`'s widened constructor, `MpcTrace`'s `record!`).

### Seeded independent RNG stream (never the global RNG)
**Source:** `src/experiments/materialize.jl:16-25` (`sub_seed`)
**Apply to:** `mpc_loop.jl`'s forecast-error draw (D-08) — derive a NEW `:mpc_forecast_error` tag, never reuse `:profiles`/`:population`.

### Docs wiring discipline (every new exported symbol → api.md, every new literate page → make.jl)
**Source:** `docs/make.jl:20-70`, `docs/src/api.md:17-60` (per-subsystem `@autodocs` blocks)
**Apply to:** `mpc_window.jl`, `mpc_trace.jl`, `mpc_loop.jl`, `mpc_rolling_horizon.jl`.

## Anti-Patterns to Avoid (carried from RESEARCH, load-bearing for plan `must_haves`)

- Calling `solve_welfare` inside the per-step loop (rebuilds a fresh `Model` every step, `welfare_solve.jl:117` — violates MPC-01's "never rebuilt" criterion). Reserve the real `solve_welfare` call for the ONE-TIME day-ahead perfect-foresight benchmark only.
- Making `λ₀` a `Parameter` (indefinite bilinear the conic backend rejects — `AgrOpt.jl:23-24`/`DsoOpt.jl:27,131`). Use `set_objective_coefficient`.
- Wrapping `solve_welfare`'s throwing `assert_socp_exact!` in a bare `try`/`catch Exception` (masks genuine bugs as cone-inexactness). Use the inline report-style reimplementation instead.
- Passing a `Parameter` as a variable's `upper_bound=` kwarg (JuMP requires a `Real` literal at construction time). Rewrite as an explicit constraint (`pv_used[t] <= Ppv_param[t]`).
- Adding `:mpc` to `SCENARIO_VALID_STRATEGIES`/`run_scenario`'s dispatch (Pitfall 7). Use an independent `run_mpc(scenario)` entry point.

## No Analog Found

None — every file in this phase's scope has a strong, directly-cited existing analog (see table above). The overall MPC-loop ARCHITECTURE itself is a NEW synthesis (RESEARCH confidence: MEDIUM on architecture, HIGH on each individual mechanic), but every individual mechanic it composes (build-once `Parameter`, `set_objective_coefficient` price slide, trace-struct convention, non-throwing certificate check, seeded RNG, literate page, `Scenario` additive fields) has an exact, cited precedent.

## Metadata

**Analog search scope:** `src/planning/`, `src/models/`, `src/admm/`, `src/devices/`, `src/experiments/`, `test/`, `docs/literate/`, `docs/`
**Files read this session (full or targeted):** `src/planning/subproblem.jl`, `src/admm/residuals.jl`, `src/devices/PVBattery.jl` (lines 228-294), `src/devices/Thermostatic.jl` (lines 210-256), `src/devices/FourQuadBESS.jl` (lines 280-348), `src/models/restriction_exactness.jl` (lines 220-325), `src/experiments/Scenario.jl` (full), `src/models/oracle.jl` (lines 60-189), `src/admm/AgrOpt.jl` (lines 270-300 + grep), `src/admm/DsoOpt.jl` (grep), `test/test_planning_oracle.jl` (lines 55-94), `docs/literate/restricted_branch_flow.jl` (lines 1-90), `docs/make.jl` (lines 1-70), `docs/src/api.md` (lines 1-60), `src/experiments/materialize.jl` (lines 1-30), `src/models/welfare_solve.jl` (grep), `src/models/ac_dual_fallback.jl` (grep), `src/devices/AbstractDevice.jl` (grep)
**Pattern extraction date:** 2026-08-09
