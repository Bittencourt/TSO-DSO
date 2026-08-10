# Phase 22: Stochastic PV/Demand Uncertainty - Pattern Map

**Mapped:** 2026-08-09
**Files analyzed:** 6 new files (per RESEARCH.md's Recommended Project Structure)
**Analogs found:** 6 / 6

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|---------------|
| `src/models/stochastic_welfare.jl` | model-builder (JuMP model assembly) | CRUD-like build + batch (S-scenario loop) | `src/models/welfare_solve.jl` (core shape) + `src/models/mpc_window.jl` (build-once/Parameter idiom, unregister precedent not present but nearest orchestration analog) | role-match (exact for the per-scenario replicated core; no prior file does the multi-`contribute!`-per-model loop, so the "unregister" mechanic itself has no analog — flagged below) |
| `src/experiments/run_stochastic.jl` | orchestrator / experiment entry-point | request-response (one call → NamedTuple result) + batch (S in-sample + H held-out) | `src/experiments/mpc_loop.jl` (`run_mpc(s::Scenario)`) | exact |
| `src/experiments/Scenario.jl` (MODIFIED — additive `stoch_*` fields) | config / declarative spec | CRUD (construction + validation) | itself, prior additive edit: the existing `mpc_*` field block (lines 87–99, 121–124, 219–235) | exact (self-referential precedent within the same file) |
| `docs/literate/stochastic_pv_demand.jl` | docs / literate page | transform (build Scenario → call entry point → render numbers) | `docs/literate/mpc_rolling_horizon.jl` | exact |
| `test/fixtures_phase22.jl` | test fixture module | file-I/O-adjacent (in-memory fixture construction, no I/O) | `test/fixtures_phase21.jl` | exact |
| `test/test_stochastic_welfare.jl` + `test/test_run_stochastic.jl` | test | request-response (direct-script assertions) | `test/fixtures_phase21.jl`'s consuming `@testitem`s (not read directly — pattern inferred from CONTEXT.md's "direct Julia/Test.jl scripts under --project=." mandate) | role-match |

**Unmodified byte-for-byte (verbatim reuse, not new files):** `src/models/welfare_solve.jl`,
`src/models/oracle.jl`, `src/models/exactness.jl`, `src/devices/*.jl`,
`src/powerflow/ConvexBranchFlow.jl`, `src/planning/retry.jl`, `src/data/profiles.jl`,
`src/experiments/materialize.jl`, `src/core/ModelContext.jl` — every one of these is consumed,
none is edited (RESEARCH.md's own explicit list).

## Pattern Assignments

### `src/models/stochastic_welfare.jl` (model-builder, CRUD/batch)

**Primary analog:** `src/models/welfare_solve.jl` (`solve_welfare`) — the deterministic core
each scenario block replicates verbatim, S times, on ONE shared `Model`.
**Secondary analog:** `src/models/mpc_window.jl` (`build_mpc_window`/`MpcWindow`) — for the
build-once + `ModelContext`-per-unit + guard-clause + boundary-throw conventions, and (for the
out-of-sample harness half of this same builder concern) the `terminal_param`/pin-`Parameter`
idiom.

**Imports pattern** (mirrors both analogs, `src/models/welfare_solve.jl` lines 1, 20 and
`src/models/mpc_window.jl` lines 1, 25):
```julia
using JuMP
```
No other imports — every device/pf/context symbol is already `export`ed into the `TSODSO`
module scope this file is compiled inside (project convention: no explicit `import` of
sibling `src/` files).

**Boundary guards pattern** (`src/models/welfare_solve.jl` lines 111–115, mirrored by
`src/models/mpc_window.jl` lines 133–157):
```julia
isempty(aggregators) &&
    throw(ArgumentError("solve_welfare needs at least one aggregator"))
length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
```
Apply the SAME idiom to: `isempty(scenario_aggs)`, `length(probabilities) != S`,
`!isapprox(sum(probabilities), 1)`, `any(<=(0), probabilities)`, and the existing
aggregator-bus-in-range check per scenario (loop the `welfare_solve.jl` lines 142–146 check
over every scenario's aggregator list).

**Core scenario-loop pattern** (verified live this session — RESEARCH.md Code Examples,
"The verified `unregister` workaround"):
```julia
model = Model(optimizer)                 # optimizer = select_optimizer(problem_class(pf)) default
ctxs = ModelContext[]
for s in 1:S
    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder; ctx.meta[:T] = T
    contribute!(pf, ctx, feeder; T = T)          # ConvexBranchFlow: NAMED containers
    if s < S
        for name in (:v, :v̂, :P, :Q, :l, :cone, :vdrop, :cpydrop, :smax)
            JuMP.unregister(model, name)          # frees the NAME only, not the objects
        end
    end
    push!(ctxs, ctx)
end
```
This is the ONE genuinely new mechanical fact this phase introduces — no existing file in
the codebase calls `contribute!(::ConvexBranchFlow, ...)` more than once per `Model`, so
there is no direct analog for the `unregister` loop itself (see "No Analog Found" below).
Everything else in the per-scenario block (aggregator `contribute!`, frontier `p_import`/
`q_import`, residual-closure guard, `@constraint(model, balance_p[...], ...)`,
`register_constraint!`) is `welfare_solve.jl` lines 148–234 REPEATED per scenario `ctx_s`,
verbatim in shape.

**Nonanticipativity pattern** (RESEARCH.md Code Examples, "Nonanticipativity equality
constraints"; the equality-constraint SHAPE mirrors `mpc_window.jl`'s own
`soc[H] == terminal_param` line 244 idiom, generalized from one Parameter-pin to a
cross-scenario variable-tie):
```julia
batt_vars = Vector{NamedTuple}(undef, S)
for s in 1:S
    res = contribute!(battery, ctxs[s]; T = T)     # fresh p_ch_s/p_dch_s/soc_s/pv_used_s
    batt_vars[s] = res.vars
end
for s in 2:S
    @constraint(model, [t = 1:T], batt_vars[s].p_ch[t] == batt_vars[1].p_ch[t])
    @constraint(model, [t = 1:T], batt_vars[s].p_dch[t] == batt_vars[1].p_dch[t])
    @constraint(model, [t = 1:T], batt_vars[s].soc[t] == batt_vars[1].soc[t])
end
```
`PVBattery.contribute!`'s return shape (`src/devices/PVBattery.jl` line 326):
```julia
return (; vars = (; p_ch, p_dch, soc, pv_used, soc0, Ppv_param), p_inject, utility, ...)
```
confirms `res.vars.p_ch`/`.p_dch`/`.soc` are the exact handles to tie.

**Objective + solve + gate pattern** (`src/models/welfare_solve.jl` lines 236–264, D-05/D-06/
D-07 layered on top per RESEARCH.md Code Examples "De-scaled per-scenario DADP"):
```julia
@objective(model, Max,
    sum(probabilities[s] * (ctxs[s].meta[:objective] -
                             sum(λ₀[t] * p_imports[s][t] for t in 1:T)) for s in 1:S))
assert_solved!(model; dual = true)
for s in 1:S
    assert_socp_exact!(ctxs[s]; rtol = rtol_exact)     # D-06: per-scenario, never aggregated
end
dadp = [dual.(balance_ps[s][priced_bus, :]) ./ probabilities[s] for s in 1:S]   # D-05, PRIMARY
expected_dadp = sum(probabilities[s] .* dadp[s] for s in 1:S)                    # D-07, DERIVED ONLY
```
`assert_socp_exact!`'s exact signature/ordering-contract is `src/models/exactness.jl` lines
78 (`assert_socp_exact!(ctx::ModelContext; rtol::Real = 1e-4, atol::Real = 1e-6) -> maxgap`) —
call it once per `ctxs[s]`, AFTER `assert_solved!`, BEFORE any `dual()` read (the SAME
ordering `welfare_solve.jl` line 256–258 already enforces once; this file enforces it S
times in a loop, never aggregated per D-06).

**Out-of-sample harness half (D-09) — separate build-once model, mirrors `MpcWindow` idiom**
(`src/models/mpc_window.jl` lines 62–72 struct shape, lines 236–260 pin-Parameter
construction, RESEARCH.md Code Examples "Out-of-sample Parameter-pin harness"):
```julia
res = contribute!(battery, ctx; T = T)               # fresh p_ch/p_dch/soc/pv_used
pin_p_ch = @variable(model, [t = 1:T], set = Parameter.(in_sample_p_ch))
@constraint(model, [t = 1:T], res.vars.p_ch[t] == pin_p_ch[t])
for h in 1:H_budget
    set_parameter_value.(res.vars.Ppv_param, held_out_scenarios[h].pv)
    set_parameter_value.(agg_pdc_param, held_out_scenarios[h].demand)
    solve_with_retry!(model; dual = true)
    welfare_h[h] = objective_value(model)
end
```
The exact anonymous-`Parameter`-plus-equality-constraint pattern is `mpc_window.jl` lines
238–248 (`term = @variable(model, base_name = "...", set = Parameter(...)); @constraint(model,
v.soc[H] == term)`) — reuse the SAME anonymous `base_name` discipline (never a named/
object-dictionary symbol) so multiple held-out re-solves compose without collision, exactly
as `FourQuadBESS`'s apparent-power cone and `mpc_window.jl`'s own terminal pin already
establish.

**Error handling pattern:** `throw(ArgumentError(...))` for construction-time boundary
violations (never `@assert`), `error(...)` for post-solve invariant violations (mirrors
`assert_socp_exact!`'s own `error(...)` at `src/models/exactness.jl` line 101) — this file
introduces NO new error idiom, it reuses the project's two-tier convention verbatim.

---

### `src/experiments/run_stochastic.jl` (orchestrator, request-response + batch)

**Analog:** `src/experiments/mpc_loop.jl` (`run_mpc(s::Scenario)`)

**Imports pattern** (`src/experiments/mpc_loop.jl` line 59):
```julia
using JuMP
```

**Entry-point signature + materialization pattern** (`mpc_loop.jl` lines 144–178, the
"MATERIALIZE, verbatim per run_scenario's own :centralized block" comment):
```julia
function run_stochastic(s::Scenario)
    # Boundary guards FIRST, before any materialization.
    ...
    feeder = build_feeder(s.feeder)
    # S in-sample scenarios: S disjoint seeded draws, mirroring generate_profiles/sub_seed
    scenario_data = [
        generate_profiles(; seed = sub_seed(s.seed, Symbol(:stoch_insample_, k)), T = s.T)
        for k in 1:s.stoch_S
    ]
    scenario_aggs = [
        build_population(s.population, feeder, s.feeder, scenario_data[k],
                          sub_seed(s.seed, Symbol(:stoch_population_, k)))
        for k in 1:s.stoch_S
    ]
    pf = ConvexBranchFlow()
    λ₀ = build_price(s.price, s.T, scenario_data[1])   # or a scenario-independent price source
    ...
end
```
`sub_seed`/`build_population`/`build_feeder`/`build_price`/`generate_profiles` signatures
(read from `src/experiments/materialize.jl` and `src/data/profiles.jl`, exercised identically
by `mpc_loop.jl` lines 169–178):
```julia
build_feeder(sym::Symbol)
build_price(sym::Symbol, T::Int, profiles)
build_population(sym::Symbol, feeder, feeder_sym::Symbol, profiles, seed::Integer)
generate_profiles(; seed::Integer, T::Int = 24, ...) -> (; demand, pv)
```
Use S DISJOINT seeded draws (one `sub_seed` tag per in-sample scenario, another disjoint
family of tags for held-out scenarios) — mirrors `mpc_window.jl`'s own `draw_forecast_error`
independent-sub-seed discipline (lines 382–383) rather than manually offsetting one seed.

**Return-tuple pattern** (`mpc_loop.jl` lines 92–142 docstring + lines 427–434 the actual
`return (; trace, day_ahead_welfare, realized_welfare, regret, day_ahead_dadp, steps)`):
```julia
return (;
    in_sample,      # per-scenario DADPs (D-05, PRIMARY) + expected_dadp (D-07, DERIVED)
    oos,            # realized-vs-in-sample welfare gap (D-09)
    trace,          # optional, if a per-scenario/held-out ledger is warranted
)
```
Mirror `run_mpc`'s convention of ONE `NamedTuple` with clearly-named, self-documenting
fields; never a bare `Vector`/`Tuple` return.

**Boundary-guard-first pattern** (`mpc_loop.jl` lines 144–166):
```julia
s.mpc_H > s.T && throw(ArgumentError("run_mpc: window length cannot exceed the day-ahead horizon ..."))
s.mpc_step > s.mpc_H && throw(ArgumentError("run_mpc: step size cannot exceed window length H ..."))
```
Apply the SAME "guards before any materialization" idiom to the new `stoch_*` fields (e.g.
`s.stoch_S` within `[3,5]`, `s.stoch_H_oos` within `[5,10]`, per D-10's locked bands — though
CONTEXT.md leaves the exact enforcement point to Claude's discretion, the GUARD-FIRST
ORDERING itself is not discretionary, it is the established idiom).

---

### `src/experiments/Scenario.jl` (MODIFIED — additive `stoch_*` fields)

**Analog:** itself — the existing Phase-21 `mpc_*` additive-field precedent in the SAME file
(lines 87–99 docstring, 121–124 `@kwdef` fields, 219–235 constructor validation).

**Additive `@kwdef` field pattern** (lines 121–124):
```julia
mpc_H::Int = 6
mpc_step::Int = 1
mpc_terminal_soc::Bool = true
mpc_forecast_error::Float64 = 0.05
```
Mirror with e.g.:
```julia
stoch_S::Int = 3                      # in-sample scenario count (D-10, band [3,5])
stoch_H_oos::Int = 5                  # held-out scenario budget (D-10, band [5,10])
stoch_probabilities::Vector{Float64} = fill(1 / stoch_S, stoch_S)  # D-04 default-uniform
                                       # NOTE: @kwdef cannot self-reference a sibling default
                                       # this way — resolve via an explicit inner-constructor
                                       # default (see below) rather than a literal kwdef default.
```

**Constructor validation pattern** (lines 219–235, the "D-12: Phase-21 MPC-only additive
fields — same checked LOUDLY convention" comment):
```julia
if mpc_H < 1
    throw(ArgumentError("Scenario: window length H must be ≥ 1; got mpc_H=$mpc_H"))
end
if !(0 <= mpc_forecast_error < 1)
    throw(ArgumentError("Scenario: mpc_forecast_error must be a bounded fraction in [0, 1); got mpc_forecast_error=$mpc_forecast_error"))
end
```
Mirror for the new fields: `stoch_S` within the locked `[3,5]` band (or documented as
Claude's-discretion-widened), `stoch_H_oos` within `[5,10]`, `length(stoch_probabilities) ==
stoch_S`, `all(>(0), stoch_probabilities)`, `isapprox(sum(stoch_probabilities), 1; atol=1e-8)`
— every check `throw`s `ArgumentError`, never `@assert` (project-wide convention, restated at
this file's own header line 22: "an explicit inner constructor `throw`s `ArgumentError`
(never `@assert`...)").

**Docstring-update pattern:** the existing `mpc_*` field bullet block (lines 87–99) is the
template for a new `stoch_*` bullet block — explicitly note the accepted `savename` STRING
change cost (mirrors line 96–99's own "Adding them changes every `Scenario`'s `savename`
STRING ... while preserving every EXISTING numeric golden result").

---

### `docs/literate/stochastic_pv_demand.jl` (docs, transform)

**Analog:** `docs/literate/mpc_rolling_horizon.jl` (Rung 8)

**Structure pattern** (whole-file shape, lines 1–54 building the `Scenario`, lines 56–74
calling the ONE entry point, lines 76–188 walking the result fields with prose + live
`round.(...)`/scalar expressions between comment blocks):
```julia
# # Rung 9 — Stochastic PV/Demand Uncertainty
#
# <framing prose: why per-scenario DADPs, why the expectation is a DERIVED summary only>

using TSODSO

const T = ...
s = Scenario(; name = "stochastic-pv-demand-demo", feeder = :ieee13, T = T,
             stoch_S = 5, stoch_probabilities = [...non-uniform for the demo...])

r = run_stochastic(s)

# ## 1. Per-scenario DADPs (PRIMARY output, D-02/D-05)
round.(r.in_sample.dadp[1]; digits = 4)
#-
round.(r.in_sample.dadp[2]; digits = 4)
# ...

# ## 2. Expected DADP — a DERIVED SUMMARY, never a constraint-backed price (D-07)
round.(r.in_sample.expected_dadp; digits = 4)

# ## 3. Out-of-sample realized-vs-in-sample welfare gap (STOCH-03/D-09)
r.oos.welfare_gap

# ## Finding
# <honest closing prose, mirrors mpc_rolling_horizon.jl's own "Finding" section discipline
#   of never tuning a number to look small/large>
```
Every live-executed page in this manual (mirrors this precedent) uses `Scenario` + ONE entry
point rather than an inline hand-built fixture (mpc_rolling_horizon.jl lines 21–32's own
explicit rationale for that choice) — reuse the SAME rationale sentence pattern for why this
page also builds a `Scenario` rather than a bespoke feeder.

**`docs/make.jl` wiring:** the literate-list registration and `api.md` cross-reference for
this page's new exported symbols follow the SAME pattern `mpc_rolling_horizon.jl` was wired
in under (not read directly this session — CONTEXT.md's own "Established Patterns" section
already states this as a locked convention: "every new exported symbol wired into
`docs/src/api.md` (`checkdocs=:exports` blocking)"). Locate the literate-file list in
`docs/make.jl` and the `mpc_rolling_horizon.jl` entry, and add the new page adjacent to it
using the identical registration call shape.

---

### `test/fixtures_phase22.jl` (test fixture, in-memory construction)

**Analog:** `test/fixtures_phase21.jl` (`Phase21Fixtures` `@testmodule`)

**Module shape pattern** (whole-file structure, lines 1–27 header comment conventions, line
28 `@testmodule` wrapper, lines 42–46 pinned scaling constants, lines 100–109 feeder builder,
lines 115–157 private per-house aggregator builder, lines 170–186 public population builder):
```julia
@testmodule Phase22Fixtures begin
    using TSODSO

    const T = 9              # Pitfall 3: T ≥ 9 for :ieee13 :default population if
                              # Deferrable is included; smaller/Deferrable-free is lower-risk
                              # for a CI fixture the planner controls end-to-end
    const S_INSAMPLE = 3      # or the fixture's chosen in-sample count within [3,5]
    const H_OOS = 5           # held-out count within [5,10]

    const BATT_λ_MIN = 3.8
    const BATT_λ_MED = 6.2
    const BATT_λ_MAX = 8.9

    const SEED_STOCH = 20260809   # a fresh, distinct seed literal from Phase 21's SEED_MPC
    const LOAD_SCALE_STOCH = 0.02
    const PV_SCALE_STOCH = 0.01
    const LAMBDA0_STOCH = 4.0

    function stoch_feeder()
        # mirrors Phase21Fixtures.mpc_feeder()'s 2-bus (or a Deferrable-free 3-bus,
        # Phase-4 high_pv_feeder-style) radial fixture — built INSIDE the function,
        # never at module top level (same discipline).
    end

    function build_stoch_scenario_aggregators(feeder, seed; ...)
        # mirrors Phase21Fixtures._mpc_house_aggregator's per-house Thermostatic+PVBattery
        # shape fed by a seeded generate_profiles draw — called once per in-sample scenario
        # with a DISJOINT seed per scenario (S calls), and again for each held-out scenario
        # (H_OOS calls) with a seed family DISJOINT from the in-sample family.
    end

    export T, S_INSAMPLE, H_OOS, BATT_λ_MIN, BATT_λ_MED, BATT_λ_MAX, SEED_STOCH,
        LOAD_SCALE_STOCH, PV_SCALE_STOCH, LAMBDA0_STOCH,
        stoch_feeder, build_stoch_scenario_aggregators
end
```
**Self-containment contract** (fixtures_phase21.jl lines 11–15, "CONTRACT ... this module is
SELF-CONTAINED, i.e. it makes NO top-level call to any symbol filled by a later wave"): apply
identically — every feeder-consuming builder takes `feeder` as an argument, nothing evaluated
at module-load time.

**Deliberate-exclusion-of-Deferrable pattern** (fixtures_phase21.jl lines 17–23, "DELIBERATE
EXCLUSION (RESEARCH Pitfall 8)"): directly reusable rationale for D-12/Pitfall-3's own
"Deferrable-free small fixture is the lower-risk choice" — copy the SAME comment shape,
substituted for this phase's own reasoning (S-way duplication cost, not rolling-horizon-reset
confusion).

**Reproducibility footer pattern** (fixtures_phase21.jl line 25–26): "every aggregator flows
from a seeded `generate_profiles`... regenerates bit-for-bit" — restate identically.

---

### `test/test_stochastic_welfare.jl` / `test/test_run_stochastic.jl` (test, request-response)

**Analog:** the project's own MANDATORY testing-constraint convention (CONTEXT.md
`<code_context>` "Testing constraints" section, and RESEARCH.md's Validation Architecture
table) — no single file was read as a literal template this session since the mandate is a
project-wide rule, not a per-file pattern:

```julia
# direct Julia/Test.jl script under --project=. — NEVER TestItemRunner under --project=.,
# NEVER a bare include() of an @testitem file, per this project's MANDATORY testing constraint.
using Test, TSODSO
# ... build fixture, call build_stochastic_welfare/run_stochastic, @test assertions ...
```
For the CI-integrated `@testitem` form (consumed later by `test/runtests.jl`'s
`@run_package_tests`), mirror the shape any existing Phase-21 `@testitem` uses with
`setup=[Phase21Fixtures]` — substitute `setup=[Phase22Fixtures]`. (Not read directly this
session; flagged in RESEARCH.md's own Wave-0 Gaps as "new files," so no live `@testitem`
body exists yet to excerpt from for THIS phase — the closest existing consuming pattern is
Phase 21's own `test_mpc_loop.jl`/`test_mpc_terminal.jl`, referenced but not opened this
session per the "stop at 3–5 analogs" budget.)

## Shared Patterns

### Build-once, re-solve via Parameters — never rebuild
**Source:** `src/models/mpc_window.jl` (whole-file header comment, lines 1–23) +
`src/planning/subproblem.jl` (the ORIGINAL build-once model, cited but not this phase's
direct analog)
**Apply to:** `src/models/stochastic_welfare.jl`'s out-of-sample harness half (D-09) —
build the single-scenario pin model EXACTLY ONCE, re-solve H times via
`set_parameter_value`/`set_parameter_value.`, NEVER rebuild inside the held-out loop.

### Solve entry point — `solve_with_retry!`, never a bare `optimize!`
**Source:** `src/planning/retry.jl` (`solve_with_retry!(model; max_attempts, dual,
attempts_out)`, lines 32 signature)
**Apply to:** every solve in `stochastic_welfare.jl` and `run_stochastic.jl` — the in-sample
extensive-form solve AND every held-out re-solve (Pitfall 6: repeated re-solves amplify the
documented intermittent Clarabel `NUMERICAL_ERROR`/`SLOW_PROGRESS` flake).

### PF-04 exactness gate ordering
**Source:** `src/models/exactness.jl` (`assert_socp_exact!`, lines 78–107) +
`src/models/welfare_solve.jl` (call-site ordering, lines 241–258: AFTER `assert_solved!`,
BEFORE any `dual()` read)
**Apply to:** every scenario block in `stochastic_welfare.jl`, called ONCE per `ctx_s` in a
plain loop (D-06: never aggregated) — same ordering constraint, S times.

### Solver-agnostic factory routing — never name a concrete solver
**Source:** `src/models/welfare_solve.jl` line 117 (`optimizer = select_optimizer(problem_class(pf))`
default kwarg) + `src/models/mpc_window.jl` line 161 (`model = Model(select_optimizer(problem_class(pf)))`)
**Apply to:** `build_stochastic_welfare`'s `Model(optimizer)` construction and the
out-of-sample harness's model construction — both route through `select_optimizer(
problem_class(pf))`, never hardcoding `Clarabel.Optimizer` (CLAUDE.md hard constraint,
restated in RESEARCH.md's own "Project Constraints" section).

### Throw-ArgumentError construction validation, never `@assert`
**Source:** `src/experiments/Scenario.jl` (header comment line 19–22 + every constructor
check lines 149–235) + `src/data/profiles.jl` (`generate_profiles`/`markov_path`'s own
`throw(ArgumentError(...))` guards, lines 56–82, 184–216)
**Apply to:** every new boundary guard in `stochastic_welfare.jl`, `run_stochastic.jl`, and
the `Scenario.jl` `stoch_*` field additions — probabilities-vector shape/sum-to-1/positivity,
scenario-count bands, aggregator-bus-range checks.

## No Analog Found

| File/Mechanism | Role | Data Flow | Reason |
|------|------|-----------|--------|
| The `JuMP.unregister` multi-`contribute!`-per-model loop inside `stochastic_welfare.jl` | model-builder (network-layer orchestration) | batch | No prior file in this codebase calls `contribute!(::ConvexBranchFlow, ...)` more than once against the same `Model` — every prior phase (1 through 21) builds exactly one network per model (RESEARCH.md's own "This formulation file was never previously exercised with more than one call per model" — Pitfall 1). The mechanism itself was empirically verified live this session (RESEARCH.md Code Examples) and is fully specified there; the planner should treat RESEARCH.md's own verified code block as the primary source for this ONE genuinely-new mechanic, not a codebase file. |
| Nonanticipativity via cross-scenario equality constraints, generalized from a single device to S independently-built copies | model-builder | batch | The NEAREST existing analog (`mpc_window.jl`'s single `soc[H] == terminal_param` pin) ties ONE variable to ONE Parameter, not S device copies to each other — the S-way generalization is RESEARCH.md's own Pattern 2, not a direct codebase excerpt. Treat RESEARCH.md's Code Examples "Nonanticipativity equality constraints" block as the primary source. |

## Metadata

**Analog search scope:** `src/models/`, `src/experiments/`, `src/devices/`, `src/core/`,
`src/data/`, `src/planning/`, `test/`, `docs/literate/` — the exact set RESEARCH.md's own
Sources section already names as "read directly this session," re-confirmed by direct Read
calls in this pattern-mapping pass (`welfare_solve.jl`, `mpc_window.jl`, `mpc_loop.jl`,
`Scenario.jl`, `profiles.jl`, `exactness.jl`, `fixtures_phase21.jl`,
`mpc_rolling_horizon.jl`, `ModelContext.jl`, plus targeted grep/sed excerpts of
`retry.jl`, `materialize.jl`, `PVBattery.jl`, `oracle.jl`).
**Files scanned (Read/Grep):** 13.
**Pattern extraction date:** 2026-08-09.
