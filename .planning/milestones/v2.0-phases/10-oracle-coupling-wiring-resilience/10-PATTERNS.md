# Phase 10: Oracle Coupling Wiring & Resilience - Pattern Map

**Mapped:** 2026-07-22
**Files analyzed:** 8 (3 new src/, 1 modified src/, 4 new test/)
**Analogs found:** 8 / 8

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/planning/subproblem.jl` (`build_planning_oracle`/`solve_planning_oracle!`) | model/service (build-once JuMP subproblem) | CRUD-like build + request-response re-solve | `src/admm/DsoOpt.jl` (`build_dso_opt`/`solve_dso!`/`set_rho!`) | exact (same build-once/re-solve shape, same `contribute!` seams) |
| `src/planning/retry.jl` (`solve_with_retry!`) | middleware/utility (wraps a choke point) | event-driven (catch/branch/retry loop) | `src/core/status.jl` (`assert_solved!`) | role-match (wraps it; no prior retry-wrapper analog exists) |
| `src/planning/checkpoint.jl` (`checkpoint_iteration!`/`resume_from_checkpoint`) | utility (persistence primitive) | file-I/O | `src/experiments/store.jl` (`run_and_store`/`@tagsave`) | role-match (same DrWatson/JLD2 idiom, different granularity) |
| `src/TSODSO.jl` (modified: add `include("planning/*.jl")` block) | config (module wiring) | — | `src/TSODSO.jl`'s own `admm/` and `experiments/` include blocks (this same file, prior sections) | exact (append-only precedent already in the file) |
| `test/test_planning_oracle.jl` | test | request-response (unit + regression) | `test/test_oracle.jl` + `test/test_dso.jl` | exact (oracle-shape assertions from the former, build/dual assertions from the latter) |
| `test/test_planning_retry.jl` | test | event-driven (forced-failure injection) | `test/test_status.jl` | role-match (only existing `assert_solved!`-failure test; needs a new injection technique) |
| `test/test_planning_checkpoint.jl` | test | file-I/O (round-trip) | `test/test_experiments.jl` (`"INFRA-04 provenance tagsave"` item + `Phase8Fixtures.with_tempdir`) | exact (same `@tagsave`/hermetic-tempdir idiom, applied to a new payload shape) |
| `test/fixtures_phase10.jl` (`Phase10Fixtures` `@testmodule`) | test fixture | — | `test/fixtures_phase6.jl` (`Phase6Fixtures`, the 2-bus "dual-sign anchor") | exact (RESEARCH explicitly names this as the PLAN-02 toy-case template) |

## Pattern Assignments

### `src/planning/subproblem.jl` (model/service, build-once + re-solve)

**Analog:** `src/admm/DsoOpt.jl` (`build_dso_opt`/`solve_dso!`/`set_rho!`), cross-checked against `src/models/welfare_solve.jl` (`solve_welfare`) for the frontier/residual-closure shape being mirrored.

**Struct + docstring header pattern** (`src/admm/DsoOpt.jl` lines 37–79):
```julia
using JuMP

struct DsoOpt{P, PI, F}
    model::Model
    ctx::ModelContext
    pag::P
    p_import::PI
    load_nodes::Vector{Int}
    T::Int
    feeder::F
    ρ::Float64
    λ₀::Vector{Float64}
end
```
Mirror this exactly for a `PlanningOracle{Z, PI, F}` struct: `model::Model`, `ctx::ModelContext`, `z` (the `Parameter` container), `p_import`, `T::Int`, `feeder`, plus whatever else the pin needs (no `ρ`/`λ₀` unless the objective wants a frontier price — RESEARCH's Pattern 1 code keeps `λ₀` for the objective term). Field types stay generic (`{Z, PI, F}`) exactly as `DsoOpt` does, for the same reason (JuMP's `DenseAxisArray`/`VariableRef` container types are not fixed).

**Build-once boundary guards** (`src/admm/DsoOpt.jl` lines 127–147, `src/models/welfare_solve.jl` lines 110–116):
```julia
function build_dso_opt(feeder, aggregators, T::Int; ρ::Real, λ₀)
    isempty(aggregators) &&
        throw(ArgumentError("build_dso_opt needs at least one aggregator"))
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
    N = length(feeder.buses)
    root = feeder.root
    for (k, agg) in enumerate(aggregators)
        1 <= agg.bus <= N || throw(
            ArgumentError("aggregator[$k] bus=$(agg.bus) is outside feeder buses 1:$N"),
        )
    end
```
Copy this fail-loud boundary-guard shape verbatim for `build_planning_oracle(feeder, pf, aggregators; λ₀, T)` — same `isempty(aggregators)`, same `length(λ₀) == T`, same per-aggregator bus-range check, same `ArgumentError` wording style ("X has shape Y, expected Z").

**Model + ctx + verbatim `contribute!` reuse** (`src/admm/DsoOpt.jl` lines 180–204, matches RESEARCH Pattern 1's verified code):
```julia
model = Model(select_optimizer(SOCP()))          # SOCP factory; never names a solver
JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)

ctx = ModelContext(model)
ctx.meta[:feeder] = feeder
ctx.meta[:T] = T

contribute!(ConvexBranchFlow(), ctx, feeder; T = T)   # VERBATIM reuse — no reimplementation

@variable(model, p_import[t = 1:T])              # free-sign active frontier exchange
@variable(model, q_import[t = 1:T])              # free-sign reactive frontier import
for t in 1:T
    add_to_residual!(ctx, :Rp, root, t, p_import[t])
    add_to_residual!(ctx, :Rq, root, t, q_import[t])
end
ctx.meta[:p_import] = p_import
ctx.meta[:q_import] = q_import
```
For the new oracle, replace `select_optimizer(SOCP())` with `select_optimizer(problem_class(pf))` (mirrors `solve_welfare`'s formulation-driven routing — INFRA-02) and call `contribute!(pf, ctx, feeder; T)` generically (any `AbstractPowerFlow`, not hardcoded `ConvexBranchFlow`). Keep `p_import`/`q_import` FREE-SIGN (RESEARCH Open Question 1 recommendation, mirrors `DsoOpt`, NOT `solve_welfare`'s import-only default) so a negative Benders trial `z[t]` never structurally infeasibilizes the pin.

**The new seam — `Parameter` + pin constraint** (RESEARCH Pattern 1, verified this session against JuMP 1.30.1/Clarabel 0.11.1 — no prior codebase analog, this IS the new mechanism):
```julia
@variable(model, z[t = 1:T] in Parameter(0.0))        # the coupling-flow setpoint (D-01)
@constraint(model, pin[t = 1:T], p_import[t] == z[t]) # D-01/D-11: p_import PINNED to z

@objective(model, Max, ctx.meta[:objective] - sum(λ₀[t] * p_import[t] for t in 1:T))

# --- per-iteration re-solve (no rebuild) ---
set_parameter_value.(z, z_trial)                      # cheap; num_variables/constraints unchanged
assert_solved!(model; dual = true)                    # STRICT gate (never allow_almost on this path)
π = dual.(pin)                                         # length-T coupling dual (D-01)
```

**Residual closure pattern** (`src/admm/DsoOpt.jl` lines 230–242, identical shape in `src/models/welfare_solve.jl` lines 223–234):
```julia
size(ctx.residuals[:Rp]) == (N, T) || error(
    "residual :Rp is $(size(ctx.residuals[:Rp])), expected ($N, $T) — an index escaped the feeder",
)
@constraint(model, balance_p[j = 1:N, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
register_constraint!(ctx, :balance_p, balance_p)          # dual = λ_j (DADP)
```
Copy this defensive shape-check-before-`@constraint` idiom verbatim.

**Re-solve entry point pattern** (`src/admm/DsoOpt.jl` lines 296–335, `solve_dso!`):
```julia
function solve_dso!(dso::DsoOpt, λ, a, ρ::Real; check_exact::Bool = false, strict::Bool = true)
    for j in dso.load_nodes, t in 1:dso.T
        set_objective_coefficient(dso.model, dso.pag[j, t], -λ[j][t] - ρ * a[j][t])
    end
    if strict
        assert_solved!(dso.model; dual = true)
    else
        assert_solved!(dso.model; dual = false, allow_almost = true)
    end
    return (;
        pag_dso = value.(dso.pag),
        p_import = value.(dso.p_import),
        exact_maxgap = get(dso.ctx.meta, :socp_maxgap, nothing),
    )
end
```
Mirror the shape for `solve_planning_oracle!(o::PlanningOracle, z_trial) -> (; cost, π, π_s, dadp, ctx)`: mutate only the parameter (`set_parameter_value.`), gate through `assert_solved!` (route via the retry wrapper, see below — but ALWAYS the STRICT branch, D-06/RESEARCH: "duals only from a STRICT solve, never `allow_almost` on the price-producing path"), then read `value.(...)`/`dual.(...)` and return a `NamedTuple`.

**π_s reconciliation (PLAN-02, pure post-solve transform, no JuMP)** — new code, no direct codebase analog (a pure numeric fold over an already-solved `π`):
```julia
π_s = sum(Δt * π[t] for t in 1:T)   # duration-weighted sum (D-07); Δt = 1.0 at the framework's hourly rate
```

**Export line pattern** (every seam file ends with a bare `export`, e.g. `src/admm/DsoOpt.jl` line 372, `src/models/oracle.jl` line 190):
```julia
export PlanningOracle, build_planning_oracle, solve_planning_oracle!
```

---

### `src/planning/retry.jl` (middleware, event-driven retry over `assert_solved!`)

**Analog:** `src/core/status.jl` (`assert_solved!` — the choke point being wrapped, NOT modified).

**The choke point being wrapped** (`src/core/status.jl` lines 38–66):
```julia
function assert_solved!(
    model::Model;
    dual::Bool = true,
    allow_local::Bool = false,
    allow_almost::Bool = false,
)
    optimize!(model)
    ok = is_solved_and_feasible(model; dual = dual, allow_local = allow_local)
    if !ok && allow_almost
        ts = termination_status(model)
        ps = primal_status(model)
        ok =
            (ts == MOI.OPTIMAL || ts == MOI.ALMOST_OPTIMAL) &&
            (ps == MOI.FEASIBLE_POINT || ps == MOI.NEARLY_FEASIBLE_POINT)
    end
    if !ok
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
```
Note the exact multi-line `error("""...""")` diagnostic-dump idiom (`termination_status`/`primal_status`/`dual_status`/`raw_status`, one per line) — reuse this EXACT format for the retry-exhaustion error (D-10 "raise loudly with full status diagnostics").

**The retry wrapper itself** (RESEARCH Pattern 2, verified this session — no prior in-repo retry-wrapper to copy structurally, so this is the researched reference implementation to adapt):
```julia
const RETRYABLE_STATUSES = (MOI.NUMERICAL_ERROR, MOI.SLOW_PROGRESS, MOI.ALMOST_OPTIMAL)

function solve_with_retry!(model; max_attempts::Int = 4, dual::Bool = true)
    ladder = [ ... ]  # escalating Clarabel Settings() attribute Dicts, see RESEARCH Pattern 2
    for (attempt, settings) in enumerate(ladder[1:min(max_attempts, length(ladder))])
        for (k, v) in settings
            set_optimizer_attribute(model, k, v)      # post-build attribute change; no rebuild
        end
        try
            return assert_solved!(model; dual = dual)
        catch e
            e isa ErrorException || rethrow()
            ts = termination_status(model)
            if ts in RETRYABLE_STATUSES && attempt < max_attempts
                @warn "solve_with_retry!: attempt $attempt failed ($ts); escalating conditioning" raw = raw_status(model)
                continue
            end
            error("""
                  solve_with_retry!: exhausted $attempt attempt(s) — refusing to trust results:
                    termination_status : $(ts)
                    primal_status      : $(primal_status(model))
                    dual_status        : $(dual_status(model))
                    raw_status         : $(raw_status(model))
                  """)
        end
    end
end
```
Reuse `assert_solved!` as the inner call UNCHANGED (D-08: the wrapper sits AROUND it, never duplicates its logic). Never retry on `INFEASIBLE`/`INFEASIBLE_OR_UNBOUNDED`/`DUAL_INFEASIBLE` (RESEARCH Anti-Pattern, Pitfall 3) — re-raise immediately. Never fall back to SCS (D-09, explicitly forbidden — this project's `select_optimizer` never names SCS as a fallback path, matching `src/solver/factory.jl`'s "no solver named outside the factory" discipline).

---

### `src/planning/checkpoint.jl` (persistence primitive, file-I/O)

**Analog:** `src/experiments/store.jl` (`run_and_store`, `result_to_dict`, `scenario_filename`).

**The `@tagsave`/DrWatson idiom to reuse** (`src/experiments/store.jl` lines 25, 97–108):
```julia
using DrWatson: @tagsave, datadir, savename, struct2dict

function run_and_store(s::Scenario; dir::AbstractString = datadir("sims"))
    res = run_scenario(s)
    dict = result_to_dict(res)
    @tagsave(
        joinpath(dir, scenario_filename(s)),
        dict;
        storepatch = true,
        gitpath = pkgdir(@__MODULE__),
        safe = true,
    )
    return res
end
```
Key details to copy verbatim: `gitpath = pkgdir(@__MODULE__)` (the fix that makes `:gitcommit` stamp correctly even when `Pkg.test()` runs from a sandbox — see `store.jl`'s own docstring note, "Rule 1 fix, 08-04"); `safe = true` (routes through `safesave`, never silently overwrites); `dir` as an EXPLICIT keyword (never resolve `datadir()` directly inside a function that tests will call — RESEARCH Pitfall 6, tests pass `mktempdir()`).

**Adapted shape** (RESEARCH Pattern 3, this session's verified sketch):
```julia
function checkpoint_iteration!(state, iter::Int; dir = datadir("planning_checkpoints"))
    mkpath(dir)
    path = joinpath(dir, "iter_$(lpad(iter, 5, '0')).jld2")
    @tagsave(path, Dict(:iteration => iter, :state => state); safe = false)
    return path
end

function resume_from_checkpoint(dir = datadir("planning_checkpoints"))
    files = sort(filter(f -> endswith(f, ".jld2"), readdir(dir; join = true)))
    isempty(files) && return nothing
    last = load(files[end])
    return (; iteration = last["iteration"], state = last["state"])
end
```
Per D-10, only mark an iteration checkpoint complete AFTER its result is validated (write-then-rename, or accept `@tagsave`'s own write discipline); the resume path always treats the HIGHEST-numbered file as "redo, never trust" — do not add a "skip if latest" shortcut.

---

### `src/TSODSO.jl` (modified — append-only include wiring)

**Analog:** the file's own `admm/` and `experiments/` include blocks (lines 88–99, 108–122).

**The append-only, comment-documented include-block convention to copy:**
```julia
# --- ADMM decomposition core: AGR-OPT / DSO-OPT subproblems + the dual-ascent loop ---
# Wired (plan 06-01, this plan is the SOLE owner of this shared edit) AFTER the pricing seams
# — ADMM is ORCHESTRATION over the already-validated Phase-1–5 builders (RESEARCH Pattern 4):
# it consumes the solved-ctx / `extract_dlmp` seams and reuses device / `ConvexBranchFlow`
# `contribute!` verbatim, so NO Phase-5 source file is modified. ...
include("admm/residuals.jl")
include("admm/AgrOpt.jl")
include("admm/DsoOpt.jl")
include("admm/solve_admm.jl")
```
Append a new block in the SAME style, placed AFTER `include("admm/solve_admm.jl")` and AFTER `include("models/oracle.jl")` (per D-11/RESEARCH "Recommended Project Structure"):
```julia
# --- Planning-layer oracle: build-once Parameter-pinned coupling subproblem + resilience ---
# Wired (plan 10-0X) AFTER admm/ and models/oracle.jl — ORCHESTRATION over the already-
# validated welfare/ADMM builders (RESEARCH Pattern 4): reuses contribute!(pf, ctx, feeder),
# assert_solved! (INFRA-03), and select_optimizer (INFRA-02) verbatim. NO Phase 4-9 source
# file is modified (D-03/D-11). Phase 13's coupling.jl will join this directory.
include("planning/retry.jl")        # solve_with_retry! wraps assert_solved! (plan 10-0X, D-08/D-09)
include("planning/checkpoint.jl")   # checkpoint_iteration!/resume_from_checkpoint (plan 10-0X, D-10)
include("planning/subproblem.jl")   # build_planning_oracle/solve_planning_oracle! (plan 10-0X, D-01/D-11)
```
Order note: `subproblem.jl` should be included LAST in this block since `solve_planning_oracle!` calls `solve_with_retry!` (which itself wraps `assert_solved!`); Julia's `include` order does not enforce dependency resolution at parse time (all definitions are visible module-wide once `TSODSO.jl` finishes), but the comment-block convention orders files by "what depends on what" for readability — mirror that.

---

### `test/test_planning_oracle.jl` (test, PLAN-01/PLAN-02 coverage)

**Analogs:** `test/test_oracle.jl` (shape/kwarg-exercise pattern) + `test/test_dso.jl` (build/guard/build-once-invariance pattern).

**`@testitem` header + tag-filter convention** (`test/test_oracle.jl` lines 1–13):
```julia
@testitem "oracle: operational_oracle returns (cost, π, dadp, ctx) with finite prices (OPT-03/SEAM-01)" tags =
    [:oracle] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    ...
    res = operational_oracle(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = T, z = nothing, ...)
    @test res isa NamedTuple
    for k in (:cost, :π, :dadp, :ctx)
        @test k in keys(res)
    end
    @test isfinite(res.cost)
    @test length(res.π) == T
    @test all(isfinite, res.π)
end
```
Mirror this NamedTuple-shape-then-finiteness assertion pattern for `solve_planning_oracle!`'s `(; cost, π, π_s, dadp, ctx)` — use item names containing `"planning"` (per RESEARCH's quick-run filter convention, `occursin("planning", ti.name)`, mirroring the existing `occursin("dso"/"oracle", ...)` tags) and tag `tags = [:planning]`.

**Boundary-guard `@test_throws` pattern** (`test/test_dso.jl` lines 87–124, `"dso: build_dso_opt guards"`):
```julia
@test_throws ArgumentError build_dso_opt(feeder, typeof(aggs)(), Th; ρ = ρ, λ₀ = λ₀)
@test_throws ArgumentError build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀[1:(Th - 1)])
```
Apply the same guard-test shape to `build_planning_oracle` (empty aggregators, `λ₀` shape mismatch, aggregator bus out of range).

**Build-once invariance test** (`test/test_dso.jl` lines 224–252, `"dso: build-once — num_variables/num_constraints unchanged across re-solves"`):
```julia
nv0 = num_variables(dso.model)
nc0 = num_constraints(dso.model; count_variable_in_set_constraints = true)
solve_dso!(dso, λ1, a1, ρ)
solve_dso!(dso, λ2, a2, ρ)
@test num_variables(dso.model) == nv0
@test num_constraints(dso.model; count_variable_in_set_constraints = true) == nc0
```
Reuse this EXACT shape for `solve_planning_oracle!` called twice at two different `z_trial` values — the PLAN-01 "build-once" success criterion (RESEARCH: "confirmed this session — the build-once contract holds").

**Free-path (`z === nothing`) parity guard** — combine `test_oracle.jl`'s z=nothing assertions with `test_dso.jl`'s shape assertions to prove `operational_oracle`/`_coupling_dual`'s `z === nothing` branch stays byte-identical (D-02/D-03 regression proof) — call `operational_oracle` directly (unmodified) alongside the new `solve_planning_oracle!` in the SAME test file, asserting neither one changed the other's behavior.

---

### `test/test_planning_retry.jl` (test, PLAN-03 retry)

**Analog:** `test/test_status.jl` (the only existing `assert_solved!`-failure test).

**Failure-injection pattern to extend** (`test/test_status.jl` lines 1–18):
```julia
@testitem "status: assert_solved! passes optimal, fails loudly on non-optimal (INFRA-03)" begin
    using TSODSO, JuMP
    ok = Model(TSODSO.select_optimizer(TSODSO.LP()))
    @variable(ok, x >= 0)
    @objective(ok, Min, x)
    TSODSO.assert_solved!(ok; dual = true, allow_local = false)
    @test is_solved_and_feasible(ok)

    bad = Model(TSODSO.select_optimizer(TSODSO.LP()))
    @variable(bad, y >= 0)
    @constraint(bad, y <= -1)   # infeasible against y >= 0
    @objective(bad, Min, y)
    @test_throws Exception TSODSO.assert_solved!(bad)
end
```
This proves the "makes `assert_solved!` throw" pattern but uses a genuinely INFEASIBLE model (not retryable) — the new test needs a model that specifically returns `NUMERICAL_ERROR`/`ALMOST_OPTIMAL` (RESEARCH's Wave-0-Gaps note: "needs a way to FORCE a `NUMERICAL_ERROR` deterministically... an artificially ill-conditioned tiny model"). Structure the test the same way (build `ok`/`bad` models, assert pass/throw) but add a THIRD case: an ill-conditioned Clarabel SOCP that trips `NUMERICAL_ERROR` at attempt 1 and recovers by attempt 2+ under `solve_with_retry!`'s escalation ladder, plus a case proving `INFEASIBLE` is NEVER retried (re-raises on attempt 1, no ladder applied) — mirrors the `RETRYABLE_STATUSES` branch documented in RESEARCH Pattern 2 / Pitfall 3.

---

### `test/test_planning_checkpoint.jl` (test, PLAN-03 checkpoint round-trip)

**Analog:** `test/test_experiments.jl`'s `"INFRA-04 provenance tagsave"` item, using `Phase8Fixtures.with_tempdir`.

**Hermetic tempdir + tagsave round-trip pattern** (`test/test_experiments.jl` lines 210–246):
```julia
@testitem "INFRA-04 provenance tagsave" setup = [Phase8Fixtures] begin
    using TSODSO
    using DrWatson: wload, savename
    ...
    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_and_store)
        Phase8Fixtures.with_tempdir() do dir
            ...
            TSODSO.run_and_store(s; dir = dir)
            f = joinpath(dir, savename(s, "jld2"; digits = 10))
            @test isfile(f)
            dict = wload(f)
            @test haskey(dict, "gitcommit")
            @test haskey(dict, "julia_version")
        end
    end
end
```
Mirror `with_tempdir` (either reuse `Phase8Fixtures.with_tempdir` directly via `setup = [Phase8Fixtures]`, or define an equivalent in a new `Phase10Fixtures` module — prefer REUSING `Phase8Fixtures.with_tempdir`, since it is already the hermetic-tempdir idiom and RESEARCH gives no reason to duplicate it). Test shape: `checkpoint_iteration!(state, iter; dir)` → assert `isfile`; simulate a "crash" (nothing to undo — a fresh process would just call `resume_from_checkpoint`); `resume_from_checkpoint(dir)` → assert the round-tripped `state`/`iteration` match; write TWO iterations, assert `resume_from_checkpoint` returns the HIGHEST-numbered one (D-10 "current iteration always redone").

---

### `test/fixtures_phase10.jl` (`Phase10Fixtures` `@testmodule`)

**Analog:** `test/fixtures_phase6.jl`'s `Phase6Fixtures` module, specifically the "dual-sign anchor" 2-bus fixture.

**Fixture-module shape to reuse** (`test/fixtures_phase6.jl` lines 25, 92–112):
```julia
@testmodule Phase6Fixtures begin
    ...
    two_bus_lambda0() = fill(LAMBDA0_2BUS, T)

    function two_bus_feeder()
        buses = [
            Bus(1, 0.95, 1.05, true),    # root / MEM frontier (v fixed at 1.0 by the model)
            Bus(2, 0.95, 1.05, false),   # the single load bus (the priced node)
        ]
        branches = [
            Branch(1, 2, 1e-3, 1e-3, SMAX_NO_LIMIT),   # near-lossless, uncongested (no power cone)
        ]
        return Feeder(buses, branches, 1)
    end

    function build_two_bus_aggregators(feeder; seed::Integer = SEED_2BUS)
        ...
        return [Aggregator(bus, 0.90, [therm, defer, batt], Pdc)]
    end

    export T, ..., two_bus_lambda0, two_bus_feeder, build_two_bus_aggregators
end
```
RESEARCH explicitly names this fixture ("near-lossless, uncongested, analytically known DADP") as the correct PLAN-02 sign/scale toy-case template — REUSE `Phase6Fixtures.two_bus_feeder()`/`build_two_bus_aggregators` directly via `setup = [Phase6Fixtures]` rather than building a NEW toy network; a new `Phase10Fixtures` module (if needed at all) should only add planning-specific helpers (e.g. a small set of `z_trial` profiles to sweep for the retry-budget empirical measurement, RESEARCH Pitfall 4) — not re-derive the feeder/aggregator fixture.

## Shared Patterns

### Fail-loud boundary guards
**Source:** `src/admm/DsoOpt.jl` lines 127–147, `src/models/welfare_solve.jl` lines 110–116, `src/models/oracle.jl` lines 102–110 (role guard).
**Apply to:** `build_planning_oracle` (empty aggregators, `λ₀`/`z` length mismatch, aggregator bus range) and any new kwarg validation.
```julia
isempty(aggregators) && throw(ArgumentError("... needs at least one aggregator"))
length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
1 <= agg.bus <= N || throw(ArgumentError("aggregator[$k] bus=$(agg.bus) is outside feeder buses 1:$N"))
```

### `assert_solved!` as the sole solve choke point (never re-implemented)
**Source:** `src/core/status.jl` lines 38–66.
**Apply to:** `solve_planning_oracle!` (via `solve_with_retry!`, which wraps but never duplicates `assert_solved!`'s logic) and every test that solves a model.

### Never name a solver directly — always `select_optimizer(problem_class(pf))`
**Source:** `src/solver/factory.jl` (the sole file naming concrete solvers), `src/models/welfare_solve.jl` line 105 (`optimizer = select_optimizer(problem_class(pf))`).
**Apply to:** `build_planning_oracle`'s `Model(...)` call — route by `problem_class(pf)`, never hardcode `SOCP()`/`Clarabel.Optimizer` (unlike `DsoOpt.jl`, which is allowed to hardcode `SOCP()` because ADMM's DSO-OPT is ALWAYS the SOCP branch-flow; the planning oracle is formulation-generic like `solve_welfare`, so it must route dynamically).

### `contribute!(pf, ctx, feeder; T)` / `contribute!(agg, ctx; T)` verbatim reuse
**Source:** `src/powerflow/AbstractPowerFlow.jl` lines 23–34 (the contract), `src/admm/DsoOpt.jl` line 194 / `src/models/welfare_solve.jl` line 149 (call sites).
**Apply to:** `build_planning_oracle` — zero new device/power-flow logic; call these exactly as ADMM/`solve_welfare` do.

### `@tagsave`/DrWatson persistence idiom
**Source:** `src/experiments/store.jl` lines 25, 97–108.
**Apply to:** `checkpoint_iteration!`/`resume_from_checkpoint` — same `gitpath = pkgdir(@__MODULE__)` fix, same explicit `dir` keyword, same "never silently overwrite" discipline (`safe = true` or an equivalent atomic-write guard).

### Append-only `TSODSO.jl` include-block convention
**Source:** `src/TSODSO.jl` lines 88–99 (admm/ block), 108–122 (experiments/ block).
**Apply to:** the new `planning/` include block — same header-comment style naming the owning plan, the dependency-order rationale, and "NO Phase-N source file is modified."

### `@testitem` tag-filter + `isdefined` RED-guard convention
**Source:** `test/test_oracle.jl` (tag convention), `test/test_experiments.jl` lines 15–18 (RED-guard convention: "every behavioral body sits behind an `isdefined(TSODSO, :symbol)` check").
**Apply to:** all four new test files — `tags = [:planning]`, item names containing `"planning"`, and (if landing before the corresponding src/ file in a given wave) an `isdefined(TSODSO, :build_planning_oracle)` guard exactly like `test_experiments.jl`'s precedent.

## No Analog Found

None. Every file in Phase 10's scope has at least a role-match analog (the retry wrapper has no PRIOR retry-wrapper in the codebase to copy structurally, since this is genuinely new machinery per RESEARCH — but it has a strong analog in the choke point it wraps, `assert_solved!`, and a fully worked reference implementation in RESEARCH Pattern 2 that was empirically verified against this project's own environment).

## Metadata

**Analog search scope:** `src/admm/`, `src/models/`, `src/core/`, `src/experiments/`, `src/powerflow/`, `src/solver/`, `src/TSODSO.jl`, `test/` (all `test_*.jl` and `fixtures_phase*.jl`).
**Files scanned:** `src/admm/DsoOpt.jl`, `src/models/welfare_solve.jl`, `src/models/oracle.jl`, `src/core/status.jl`, `src/core/ModelContext.jl`, `src/solver/factory.jl`, `src/powerflow/AbstractPowerFlow.jl`, `src/experiments/store.jl`, `src/TSODSO.jl`, `test/test_oracle.jl`, `test/test_dso.jl`, `test/test_status.jl`, `test/test_experiments.jl`, `test/fixtures_phase4.jl`, `test/fixtures_phase6.jl`, `test/fixtures_phase8.jl`, `test/runtests.jl` (17 files read directly).
**Pattern extraction date:** 2026-07-22
