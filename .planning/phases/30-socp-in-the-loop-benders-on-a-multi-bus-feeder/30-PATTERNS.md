# Phase 30: SOCP-in-the-Loop Benders on a Multi-Bus Feeder - Pattern Map

**Mapped:** 2026-10-01
**Files analyzed:** 10 (5 src/planning additions/modifications, 1 IEEE-13 fixture helper,
4 new/extended test files + 1 Literate experiment)
**Analogs found:** 10 / 10 (every file has a strong, in-repo analog — this phase is
explicitly a "small variant of an existing pattern" phase, per RESEARCH.md's own framing)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|---------------|
| `src/planning/feasibility_oracle.jl` (NEW — slack-min oracle, BILEV-04a) | service/model-builder | build-once + Parameter re-solve | `src/planning/subproblem.jl` (`PlanningOracle`/`build_planning_oracle`) | exact (same build-once/Parameter/pin shape, different objective) |
| `src/planning/benders.jl` (MODIFIED — `inexact_policy`, oracle-feasibility-cut branch, `:auto` α wiring) | orchestrator | iterative build-once/re-solve loop | itself (`solve_stackelberg!`, pre-existing feasibility-cut branch at lines 795-822) | exact (extending its own established branch pattern) |
| `src/planning/ac_recheck.jl` (NEW — incumbent-only AC re-check, BILEV-04b) | service/diagnostic | one-shot direct-solve bypass | `src/experiments/mpc_loop.jl`'s `_mpc_truth_import_acpf` (lines 1557-1650ish) | exact (CONTEXT.md explicitly mandates mirroring this function) |
| `src/planning/alpha_bounds.jl` (NEW — relaxed α-bound derivation, BILEV-05) | service/model-builder | one-time relaxed solve, discard | `test/test_planning_certification_bilevel.jl`'s `build_joint_reference` (lines 187+) + `subproblem.jl`'s `contribute!`-wiring shape | role-match (a genuinely separate model reusing `contribute!`, not a `PlanningOracle` variant) |
| `src/planning/master.jl` (MODIFIED — `α_op_lb`/`α_x_lb` gain `Union{Symbol,Real}` + `:auto` resolution + rejection) | model-builder | build-once LP | itself (`build_master`, boundary-guard style) | exact |
| `src/planning/trace.jl` (MODIFIED — `socp_maxgap_trace`, policy-action column) | diagnostics ledger | pure-data accumulator | itself (`BendersTrace`/`push!`, `nogood_count_trace`'s additive-keyword precedent) | exact |
| T=3–6 IEEE-13 aggregator population helper (new test/experiment fixture code) | fixture/test-data builder | pure data construction | `test/fixtures_phase4.jl`'s `_house_aggregator` / `build_ieee13_ground_aggregators` | role-match (same shape, must NOT reuse verbatim — T=24-locked `Deferrable` window) |
| `test/test_planning_benders_ieee13.jl` (NEW — BILEV-03) | test (integration) | `@testitem` + `setup=[...]` | `test/test_planning_benders.jl` (converges end-to-end `@testitem`) + `test_planning_hardening.jl`'s T=8 load-test shape | exact |
| `test/test_planning_feasibility_oracle.jl` (NEW — BILEV-04a) | test (integration) | `@testitem` | `test/test_planning_master.jl`/`test_planning_follower.jl`'s guard-`@testitem` shape + RESEARCH.md's own relax-one-constraint probe pattern | role-match |
| `test/test_planning_inexact_policy.jl` (NEW — BILEV-04b) | test (unit/integration) | `@testitem` | `test/test_planning_oracle.jl`'s exactness-gate tests (uses `assert_socp_exact!`) | role-match |
| `docs/literate/stackelberg_benders.jl` (EXTEND, optional T=24 run) | experiment script | Literate `.jl` | itself (the existing file, verbatim structure) | exact |

## Pattern Assignments

### `src/planning/feasibility_oracle.jl` (NEW — BILEV-04a slack-min oracle)

**Analog:** `src/planning/subproblem.jl` (`PlanningOracle`/`build_planning_oracle`)

**Imports / module-header pattern** (subproblem.jl lines 1-28):
```julia
# src/planning/subproblem.jl
#
# SEAM: build-once planning-layer oracle subproblem (...)
# OWNER: plan 10-02.
# ...
using JuMP
```
Copy the SEAM/OWNER header-comment convention and `using JuMP` — every `src/planning/*.jl`
file in this repo opens this way (see `benders.jl`, `master.jl`, `follower.jl`, `retry.jl`
headers all read above).

**Build-once struct + Parameter pin pattern** (subproblem.jl lines 59-69, 115-225):
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

function build_planning_oracle(feeder, pf::AbstractPowerFlow, aggregators; λ₀, T::Int = 24,
                                optimizer = select_optimizer(problem_class(pf)))
    isempty(aggregators) && throw(ArgumentError(...))
    length(λ₀) == T || throw(ArgumentError(...))
    model = Model(optimizer)
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)
    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder; ctx.meta[:T] = T; ctx.meta[:problem_class] = problem_class(pf)
    contribute!(pf, ctx, feeder; T = T)
    @variable(model, p_import[t = 1:T])
    for t in 1:T; add_to_residual!(ctx, :Rp, feeder.root, t, p_import[t]); end
    reactive = haskey(ctx.residuals, :Rq)
    # ... aggregators, balance closure identical to build_planning_oracle ...
    @variable(model, z[t = 1:T] in Parameter(0.0))
    @constraint(model, pin[t = 1:T], p_import[t] == z[t])
    @objective(model, Max, ctx.meta[:objective] - sum(λ₀[t] * p_import[t] for t in 1:T))
    return PlanningOracle(model, ctx, z, pin, p_import, aggregators[1].bus, T, feeder, Vector{Float64}(λ₀))
end
```
The NEW feasibility oracle is a SMALL VARIANT of this exact shape (per RESEARCH.md's
"Key insight"): keep `contribute!(pf, ctx, feeder; T)` and the aggregator-writer loop
verbatim; replace steps 4/7/8 with:
```julia
@variable(model, s_plus[t = 1:T] >= 0)
@variable(model, s_minus[t = 1:T] >= 0)
@variable(model, z[t = 1:T] in Parameter(0.0))        # SAME Parameter idiom
@constraint(model, pin[t = 1:T], p_import[t] == z[t] + s_plus[t] - s_minus[t])
@objective(model, Min, sum(s_plus[t] + s_minus[t] for t in 1:T))   # L1 slack-min
```
The pin's dual (`dual.(pin)`) yields the cut gradient in the SAME `v + u'(z - z_k) <= 0`
form `add_feasibility_cut!` already consumes (master.jl lines 189-242) — no new cut-form
plumbing needed on the master side.

**Error handling / boundary-guard pattern** (subproblem.jl lines 130-141):
```julia
isempty(aggregators) && throw(ArgumentError("build_planning_oracle needs at least one aggregator"))
length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
N = length(feeder.buses)
for (k, agg) in enumerate(aggregators)
    1 <= agg.bus <= N || throw(ArgumentError("aggregator[$k] bus=$(agg.bus) is outside feeder buses 1:$N"))
end
```
Reuse verbatim — same guard ordering (fail BEFORE any `@variable`/`@objective` assembly).

**Solve/re-solve pattern** (subproblem.jl lines 281-327, `solve_planning_oracle!`):
```julia
function solve_planning_oracle!(o::PlanningOracle, z_trial::AbstractVector{<:Real}; max_attempts::Int = 4, ...)
    length(z_trial) == o.T || throw(ArgumentError(...))
    set_parameter_value.(o.z, z_trial)
    solve_with_retry!(o.model; max_attempts = max_attempts, dual = true, attempts_out = attempts_out)
    # exactness gate + battery complementarity gate here (NOT needed on the slack-min
    # oracle — it has no SOC-exactness-sensitive pin removal to certify)
    π = dual.(o.pin)
    ...
end
```
The feasibility oracle's own `solve_feasibility_oracle!` should mirror this shape minus
the `assert_socp_exact!`/`assert_battery_complementarity!` calls (RESEARCH.md does not
require a trust gate on the slack oracle itself — it is a diagnostic probe, not a
cut-producing optimality subproblem in the Benders sense). It MUST still route through
`solve_with_retry!` (D-08's "sole solve entry point" convention is repo-wide), since a
genuinely infeasible slack-min solve would itself be a bug (minimizing ‖s‖₁ with free-sign
slack is ALWAYS feasible by construction — any genuine solve failure here is numerical,
not modeling, so `solve_with_retry!`'s escalation ladder is exactly the right gate).

**PVAL-04 registry requirement (CRITICAL):** any new `build_*` function here (e.g.
`build_feasibility_oracle`) MUST be added to `test/test_planning_noninteger.jl`'s
`registry` Dict (see that file's pattern below) or the suite's source-scan tripwire fails.

---

### `src/planning/benders.jl` (MODIFIED — `inexact_policy`, oracle-feasibility-cut branch)

**Analog:** itself — the EXISTING follower-feasibility-cut branch is the direct template
for the NEW oracle-feasibility-cut branch.

**Existing feasibility-cut branch to mirror** (benders.jl lines 795-822):
```julia
if !follower_res.feasible
    add_feasibility_cut!(master, follower_res.v, follower_res.u, lb_res.z)
    checkpoint_iteration!((; k, LB = lb_res.LB, UB, gap = NaN, z_k = lb_res.z, feasible = false), k; dir = checkpoint_dir)
    push!(trace, k; LB = lb_res.LB, UB = UB, gap = NaN, cut_type = :feasibility,
          n_cuts = length(master.cuts), master_status = master_status_k,
          oracle_status = :not_solved, retry_count = master_attempts[] - 1, solve_time = t_solve)
    continue   # T-11-06: a feasibility cut NEVER updates UB
end
```
The NEW oracle-feasibility branch slots in AFTER the existing oracle call
(`solve_planning_oracle!`, line ~827), wrapped in a `try`/`catch` that distinguishes
"genuine `MOI.INFEASIBLE`, no exactness issue" (RESEARCH.md's Pitfall 3: `solve_with_retry!`
never retries genuine infeasibility, so the throw is observed on attempt 1 and is
reliably classifiable) from "SOCP-inexact" (the `assert_socp_exact!` throw path inside
`solve_planning_oracle!`). Reuse the IDENTICAL `add_feasibility_cut!`/`checkpoint_iteration!`/
`push!`/`continue` shape above — CONTEXT.md's own locked decision: "a second, built-ONCE
slack-minimization feasibility oracle ... yields the cut `v + u'(z − z_k) ≤ 0`, in the SAME
form as the existing `add_feasibility_cut!`."

**Loop order to preserve** (CONTEXT.md, confirmed against WR-01's existing ordering in
benders.jl): follower feasibility check FIRST (already first, lines 792-822) → THEN oracle
feasibility (new) → THEN the optimality cut. Insert the new branch between the existing
`oracle_res = solve_planning_oracle!(...)` call and the `add_optimality_cut!(master, :op, ...)`
call, catching the oracle's throw there.

**`inexact_policy` dispatch pattern — model on `ll_cut_recourse`'s existing dispatch-by-type
idiom** (benders.jl lines 488-524):
```julia
ll_cut_recourse(::BendersMaster, oracle, follower, lb_res, Q_nu_iterate::Real) = Q_nu_iterate
function ll_cut_recourse(master::BendersMasterInteger, oracle, follower, lb_res, Q_nu_iterate::Real)
    return corner_recourse(oracle, follower, lb_res.y, master.T)
end
```
For `inexact_policy`, a plain `if/elseif` on the `Symbol` value (`:strict`/`:reject`/
`:certify_incumbent`) inside the `catch` block is simpler and consistent with this file's
existing `Symbol`-based branching (`cut_type in (:optimality, :feasibility)` in trace.jl,
`epigraph in (:op, :x)` in master.jl) — no need for a type-dispatch hierarchy here, since
there is no analogous "master type" carrying the policy.

**Boundary-guard pattern to extend** (benders.jl lines 679-735): add the `inexact_policy`
validity guard (`inexact_policy in (:strict, :reject, :certify_incumbent)`) in the SAME
`ArgumentError`-before-any-build-call block as the existing `T >= 1`/`max_iter >= 1`/
`length(λ₀) == T` guards.

**The AT-CONVERGENCE, once-only AC re-check hook:** insert the call to the new
`ac_recheck.jl` function immediately before each `return (; y = y_best, z = z_best, ...)`
(there are TWO such return points in the current file: the converged-loop return at line
938 and none other — `max_iter` exhaustion raises instead) — never inside the per-iteration
loop body (measured ~15s per AC solve vs ~30ms per SOCP solve, per RESEARCH.md Pattern 2).

---

### `src/planning/ac_recheck.jl` (NEW — incumbent-only AC re-check, BILEV-04b)

**Analog:** `src/experiments/mpc_loop.jl`'s `_mpc_truth_import_acpf` (lines 1557 onward)

**The exact bypass pattern to mirror** (mpc_loop.jl lines 1565-1571, 1631-1650):
```julia
ac = ACPowerFlow(; limits = false)   # physics only
model_t = Model(select_optimizer(problem_class(ac)))
ctx_t = ModelContext(model_t)
ctx_t.meta[:feeder] = feeder
ctx_t.meta[:T] = 1
contribute!(ac, ctx_t, feeder; T = 1)
# ... fix realized injections, balance closure, warm-start, objective ...
optimize!(model_t)
ok = is_solved_and_feasible(model_t; dual = false, allow_local = true, allow_almost = false)
if !ok
    throw(ErrorException("... AC power-flow truth settlement FAILED to reach LOCALLY_SOLVED ..."))
end
```
RESEARCH.md's own confirmed-working recipe (Code Examples, "AC re-check must bypass
`solve_planning_oracle!`"):
```julia
oracle_ac = TSODSO.build_planning_oracle(feeder, TSODSO.ACPowerFlow(; limits=false), aggs; λ₀=λ0, T=T)
set_parameter_value.(oracle_ac.z, z_incumbent)
TSODSO.assert_solved!(oracle_ac.model; dual = false, allow_local = true)   # the ONLY path that works
```
This is actually SIMPLER than `_mpc_truth_import_acpf` because `build_planning_oracle`
already builds the full pinned model generically (any `AbstractPowerFlow`, including
`ACPowerFlow`) — so the new `ac_recheck.jl` function can literally call
`build_planning_oracle(feeder, ACPowerFlow(; limits=false), aggregators; λ₀=λ₀, T=T)` once
at the incumbent, pin `z_incumbent`, and call `assert_solved!(...; dual=false,
allow_local=true)` DIRECTLY — never `solve_planning_oracle!`/`solve_with_retry!` (both
reject `LOCALLY_SOLVED` by default and have no `allow_local` passthrough, per RESEARCH.md
Pitfall/Pattern 2 — this is THE verified, load-bearing constraint on this file's design).

**Error/report pattern (never throw, per BILEV-04b):** mirror `_mpc_truth_import_acpf`'s
loud-`ErrorException`-on-non-convergence shape for the "the Ipopt solve itself failed"
case (that's still a genuine tooling failure, throw is fine there) — but the "AC solve
converged and REVEALS a physical violation" case must NOT throw; it must be captured into
a returned `NamedTuple`/report field, per CONTEXT.md: "its violation REPORTED on the
result — never thrown, never silently passed."

---

### `src/planning/alpha_bounds.jl` (NEW — `:auto` α-bound derivation, BILEV-05)

**Analog:** `test/test_planning_certification_bilevel.jl`'s `build_joint_reference`
(lines 187-230ish) for the "build a genuinely separate model reusing `contribute!`"
shape, combined with `subproblem.jl`'s aggregator-wiring loop.

**The one-time relaxed, pin-free model pattern** (RESEARCH.md Code Examples, confirmed
working this session — this IS the pattern to implement, not just reference):
```julia
function build_relaxed_oracle(feeder, pf, aggregators; λ₀, T, y_max)
    model = Model(TSODSO.select_optimizer(TSODSO.problem_class(pf)))
    ctx = TSODSO.ModelContext(model)
    ctx.meta[:feeder] = feeder; ctx.meta[:T] = T; ctx.meta[:problem_class] = TSODSO.problem_class(pf)
    TSODSO.contribute!(pf, ctx, feeder; T = T)
    @variable(model, 0 <= p_import[t=1:T] <= y_max)              # BOX, not a Parameter pin
    for t in 1:T; TSODSO.add_to_residual!(ctx, :Rp, feeder.root, t, p_import[t]); end
    # ... reactive channel, aggregator contribute!, balance closure — verbatim as build_planning_oracle ...
    @objective(model, Max, ctx.meta[:objective] - sum(λ₀[t]*p_import[t] for t in 1:T))
    return model, ctx
end
TSODSO.solve_with_retry!(model_r; dual=true)
α_op_lb = -objective_value(model_r)
```
Reuse `contribute!(pf, ctx, feeder; T)` and the aggregator loop VERBATIM from
`build_planning_oracle` (subproblem.jl lines 162-203) — the ONLY structural difference is
`p_import` as a boxed `@variable` instead of a `Parameter`-pinned one (RESEARCH.md Pattern
3: "you cannot 'free' that pin into an inequality box by re-setting the Parameter's
value"). Route the solve through `solve_with_retry!` (D-08 convention), never
`optimize!` directly.

**`build_master`'s own boundary-guard-before-assembly pattern to extend** (master.jl
lines 92-116): `build_master`'s `α_op_lb`/`α_x_lb` keywords need to accept
`Union{Symbol,Real}` with `:auto` resolved by calling into `alpha_bounds.jl` BEFORE the
existing `T >= 1`/`y_max > 0`/`c_y >= 0` guards' sibling guard for the NEW over-high-bound
rejection:
```julia
# existing pattern (master.jl lines 93-96) to mirror for the NEW guard:
T >= 1 || throw(ArgumentError("build_master needs T >= 1, got T=$T"))
y_max > 0 || throw(ArgumentError("build_master needs y_max > 0, got $y_max"))
c_y >= 0 || throw(ArgumentError("build_master needs c_y >= 0, got $c_y"))
# NEW (BILEV-05): same style —
α_op_lb_derived > α_op_lb_user + tol && throw(ArgumentError("build_master: α_op_lb=$α_op_lb_user exceeds the derived minimum $α_op_lb_derived (+tol) — would silently produce a wrong-converged answer, see test_planning_hardening.jl's own T=8 finding"))
```

---

### `src/planning/master.jl` (MODIFIED — `:auto` α-bound resolution)

**Analog:** itself (`build_master`, lines 92-116) — see Pattern Assignment above
(alpha_bounds.jl section) for the extension shape. No new file-level pattern beyond what's
already shown; this is a surgical extension of the existing boundary-guard block and the
existing `@variable(model, α_op >= α_op_lb)` line (which becomes
`@variable(model, α_op >= α_op_lb_resolved)` after `:auto` resolution).

---

### `src/planning/trace.jl` (MODIFIED — `socp_maxgap_trace`, policy-action column)

**Analog:** itself — the existing ADDITIVE-keyword precedent for `nogood_count_trace`
is the EXACT template for adding `socp_maxgap`/policy-action columns.

**The additive-field pattern to replicate verbatim** (trace.jl lines 77-84, 106, 117-130,
172-176, 189, 205-206, 217):
```julia
# struct field (trace.jl line 106):
nogood_count_trace::Vector{Int}

# constructor (trace.jl line 127, inside BendersTrace()):
Int[],   # one more empty Vector per new field, in the SAME position as the struct field

# push! keyword, DEFAULTED so every pre-existing call site keeps compiling (trace.jl line 189):
nogood_count::Integer = 0,

# push! guard (trace.jl lines 205-206):
nogood_count >= 0 || throw(ArgumentError("push!: nogood_count must be >= 0, got $nogood_count"))

# push! body (trace.jl line 217):
push!(trace.nogood_count_trace, Int(nogood_count))
```
Apply this EXACT 5-site pattern for `socp_maxgap_trace::Vector{Float64}` (default
`NaN` — "not applicable this iteration", mirroring `gap_trace`'s own NaN-sentinel
convention documented at trace.jl lines 57-60: "a legitimate sentinel, NOT guarded away")
and `policy_action_trace::Vector{Symbol}` (default `:none`, mirroring `oracle_status`'s
own `:not_solved` default at trace.jl line 187). `trace_summary` (trace.jl lines 237-272)
should gain a `max_socp_maxgap`/similar summary field mirroring its own
`total_retries = sum(trace.retry_count_trace)` pattern (line 269).

---

### T=3–6 IEEE-13 aggregator population helper (new fixture code)

**Analog:** `test/fixtures_phase4.jl`'s `_house_aggregator` (lines ~110-150) and
`build_ieee13_ground_aggregators` (referenced at line 303) — but DO NOT reuse verbatim
(RESEARCH.md Anti-Pattern / Pitfall 5: hardcoded `T=24`, `Deferrable(bus, 8, 16, ...)`
window that throws `ArgumentError` at `T<16`).

**The verified-working T-parametrized replacement recipe** (RESEARCH.md Code Examples,
confirmed live this session):
```julia
function house_agg(bus; seed, φ=0.90, load_scale=0.01, pv_scale=0.03,
                    batt_pmax=0.02, batt_emax=0.1, batt_soc0=0.05)
    prof = generate_profiles(seed = seed + bus, T = T)   # NOT Phase4Fixtures (T=24-locked)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, fill(25.0, T))
    batt = PVBattery(bus, 0.95, 1.0, batt_pmax, 0.0, batt_emax, batt_soc0, 3.8, 6.2, 8.9, Ppv)
    return Aggregator(bus, φ, [therm, batt], Pdc)
end
```
Follow `fixtures_phase4.jl`'s OWN module-header docstring conventions (its `@testmodule`
header comment style: "Seam:", "CONTRACT (threat T-xx-xx)", "REPRODUCIBILITY", "UNITS")
and its own "define functions/consts only, no top-level solve call" contract (that file's
own header, line ~9-12) if this is placed in a new `@testmodule` (e.g.
`test/fixtures_phase30.jl`) rather than inline per-testitem.

**Battery price-triple convention to preserve** (fixtures_phase4.jl lines 33-36): keep
the STRICT `λ_min < λ_med < λ_max` ordering (`3.8 < 6.2 < 8.9`, same literals RESEARCH.md's
own probe used) — "the load-bearing no-binary guarantee."

---

### `test/test_planning_benders_ieee13.jl` (NEW — BILEV-03)

**Analog:** `test/test_planning_benders.jl` (converges end-to-end `@testitem`, lines
1-60+) for the happy-path convergence shape, and `test/test_planning_hardening.jl`'s T=8
item (lines ~240+) for the "document the measured iteration-count spread, don't pin a
fragile exact number" convention and the `[:slow]` tag precedent for a longer-running item.

**File-header convention to copy** (test_planning_benders.jl lines 1-30): a `# Seam:`
comment block naming the requirement ID, the toy/real fixture used, and an "EXPECTED
OPTIMUM — RE-DERIVED, NOT [copied from elsewhere]" style note — for BILEV-03 this becomes
"the monolithic cross-check is an INDEPENDENTLY solved model, not a reuse of the Benders
pieces" (CONTEXT.md's own explicit instruction).

**`@testitem` skeleton to copy** (test_planning_benders.jl lines 32-40):
```julia
@testitem "planning benders: converges end-to-end ..." tags = [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    feeder = Phase6Fixtures.two_bus_feeder()
    ...
    mktempdir() do dir
        result = solve_stackelberg!(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = 1,
                                     follower_kwargs = follower_kwargs, master_kwargs = master_kwargs,
                                     checkpoint_dir = dir)
        ...
    end
end
```
Swap `setup = [Phase6Fixtures, ToyDeviceFixture]` for the new IEEE-13 population
`@testmodule` (or inline builders), `LinDistFlow()` for `ConvexBranchFlow()`, and
`T = 1` for `T ∈ [3,6]` — the `mktempdir() do dir ... end` checkpoint-directory idiom is
reused unchanged (also used identically in `docs/literate/stackelberg_benders.jl` line 99
via plain `mktempdir()`).

**Monolithic cross-check pattern** — `build_joint_reference`
(`test/test_planning_certification_bilevel.jl` lines 187-230): builds an INDEPENDENT
single JuMP model via `contribute!(LinDistFlow(), ctx, feeder; T)` + its own investment/
coupling variables + `assert_solved!` directly — follow this EXACT "independent full
rebuild, not a reuse of Benders pieces" shape for BILEV-03's monolithic joint solve (swap
`LinDistFlow()` for `ConvexBranchFlow()` and extend to the full aggregator population
instead of the single `d[t]`/`agg_bus` device).

---

### `test/test_planning_feasibility_oracle.jl` (NEW — BILEV-04a)

**Analog:** `test/test_planning_master.jl`'s guard-`@testitem`s (lines 18-45) for the
`@test_throws`/assertion style, combined with RESEARCH.md's OWN verified ablation recipe
(Architecture Pattern 1) as the fixture-construction method:
```julia
function widen_smax(feeder; smax=90.0)
    branches2 = [TSODSO.Branch(br.from, br.to, br.r, br.x, smax) for br in feeder.branches]
    return TSODSO.Feeder(feeder.buses, branches2, feeder.root)
end
oracle0 = TSODSO.build_planning_oracle(feeder0, TSODSO.ConvexBranchFlow(), aggs; λ₀=λ0, T=4)
TSODSO.solve_planning_oracle!(oracle0, fill(0.0686, 4))   # THROWS: MOI.INFEASIBLE (thermal)
```
Use this ablation recipe to WRITE (not just verify) the fixture docstrings — RESEARCH.md's
own concrete numbers (`z≥0.0686` thermal, a thermally-widened `smax=90` + real voltage
bounds for the voltage-only case) are directly reusable as the fixture's pinned z values.

---

### `test/test_planning_inexact_policy.jl` (NEW — BILEV-04b)

**Analog:** `test/test_planning_oracle.jl`'s exactness-gate-exercising tests (which already
call `assert_socp_exact!` indirectly via `solve_planning_oracle!`) — mirror its
`@testitem ... tags = [:planning] ... begin using TSODSO ... end` skeleton, and
RESEARCH.md's own measured naturally-occurring inexact pin:
```julia
# z=0.06 on the T=4 IEEE-13 population: OK (feasible primal), SOCP INEXACT
# (maxgap≈1.9e-3, ratio≈4852× over tolerance) — the BILEV-04b fixture, per RESEARCH.md
```
Test each of `:strict`/`:reject`/`:certify_incumbent` as a SEPARATE `@testitem`, mirroring
`test_planning_master.jl`'s one-guard-per-`@testitem` granularity.

---

### `docs/literate/stackelberg_benders.jl` (EXTEND — optional T=24 run)

**Analog:** itself, verbatim — see the full file read above. The existing file already
establishes every convention needed for a T=24 IEEE-13 extension: `using TSODSO` only (no
test-only packages), `checkpoint_dir = mktempdir()`, a `result = solve_stackelberg!(...)`
call followed by narrated `result.gap`/`result.y`/`result.z`/`result.UB` cells, and a
CairoMakie convergence-figure section (lines 146-209) reading `result.trace` fields
directly (`trace.iter_trace`, `trace.UB_trace`, `trace.LB_trace`, `trace.gap_trace`) with
the `isfinite.(...)`/`.!isnan.(...)` masking idiom for the sentinel values. If BILEV-05 adds
new per-iteration trace columns, extend this figure's second panel analogously (e.g. an
`socp_maxgap` subplot) using the SAME `max.(..., eps())` log-axis-floor guard (line 197).

## Shared Patterns

### Build-once / Parameter re-solve (applies to feasibility_oracle.jl, alpha_bounds.jl's
relaxed oracle is the ONE exception — it is deliberately NOT re-solved, built once and
discarded)
**Source:** `src/planning/subproblem.jl` lines 115-225, `src/planning/follower.jl` lines
94-131, `src/planning/master.jl` lines 92-116 — ALL THREE existing build-once JuMP models
in this repo share the identical skeleton: boundary guards → `Model(select_optimizer(...))`
→ `contribute!`/`@variable`/`@constraint` assembly → return a struct holding `model` +
every handle a re-solve needs (`z`, named constraints, decision variables).
**Apply to:** `feasibility_oracle.jl` (new struct + builder).

### `solve_with_retry!` as the SOLE solve entry point (D-08)
**Source:** `src/planning/retry.jl` (whole file); consumed verbatim by `subproblem.jl` line
297, `master.jl` line 269. NEVER called around directly for any model whose duals will be
read and trusted.
**Apply to:** the feasibility oracle's solve function, the relaxed α-bound derivation solve
— NEVER the follower (which has its own documented `optimize!`-direct exception, PLAN-04)
and NEVER the AC re-check (which has its OWN documented bypass, `assert_solved!(...;
allow_local=true)` directly, per CONTEXT.md/RESEARCH.md's explicit instruction — this is
the ONE place in this phase that deliberately does NOT route through `solve_with_retry!`).

### Fail-loud boundary guards BEFORE any `@variable`/`@objective` assembly
**Source:** every `build_*` function read above (`subproblem.jl` 130-141, `follower.jl`
101-108, `master.jl` 93-96) — the universal convention: guard first, named `ArgumentError`
messages interpolating the offending value, before touching the model.
**Apply to:** every new `build_*` function this phase adds (`build_feasibility_oracle`,
the relaxed-oracle builder, `build_master`'s extended `:auto`/over-high-bound checks).

### Additive, backward-compatible keyword extension (never break an existing call site)
**Source:** `trace.jl`'s `nogood_count::Integer = 0` (line 189), `retry.jl`'s
`attempts_out::Union{Nothing,Ref{Int}} = nothing` (line 136), `benders.jl`'s `follower =
nothing`/`master = nothing`/`known_optimum = nothing` kwargs (lines 675-677) — EVERY
non-trivial API extension in this codebase defaults to a value that reproduces
byte-identical pre-existing behavior, documented explicitly as such in the docstring.
**Apply to:** `solve_stackelberg!`'s new `inexact_policy` kwarg (default `:strict` is
explicitly required by CONTEXT.md to reproduce "today's throw"), `build_master`'s
`α_op_lb`/`α_x_lb` becoming `Union{Symbol,Real}` with `:auto` as the NEW default (this one
IS a default-behavior CHANGE per BILEV-05's own spec — document it as such, unlike the
other additive examples).

### PVAL-04 builder-registry tripwire (mandatory for ANY new `build_*`)
**Source:** `test/test_planning_noninteger.jl` lines 24-100+ (`registry` Dict keyed by
function name, `EXEMPT` set for deliberately-non-binary-free builders, a trailing
source-scan that asserts the registry's keys equal every `build_\w+` definition under
`src/planning/`).
**Apply to:** `build_feasibility_oracle` (or whatever name the new builder in
`feasibility_oracle.jl` takes) and the relaxed α-bound builder in `alpha_bounds.jl` IF it
is named with a `build_` prefix — register BOTH in the SAME commit that introduces them,
in the exact Dict-entry style shown (`"build_x" => () -> build_x(...).model`).

### Checkpoint-once-per-iteration + BendersTrace push-once-per-iteration (never skip either)
**Source:** `benders.jl` lines 795-822 (feasibility branch) and 890-921 (optimality
branch) — both branches call `checkpoint_iteration!` and `push!(trace, ...)` EXACTLY once,
with `continue` immediately after on the feasibility branch (T-11-06: never update `UB`).
**Apply to:** the new oracle-feasibility-cut branch and the `inexact_policy` dispatch
branches — each must still checkpoint + trace-push exactly once per iteration, mirroring
the existing two branches' bookkeeping discipline.

## No Analog Found

None — every file this phase introduces or modifies has a strong, directly-applicable
in-repo analog (expected, since RESEARCH.md's own "Don't Hand-Roll" section concludes this
phase's new pieces are all "SMALL VARIANTS of an existing, already-validated
model-building pattern").

## Metadata

**Analog search scope:** `src/planning/*.jl` (all 5 files read in full), `src/data/ieee13.jl`
(read in full), `src/experiments/mpc_loop.jl` (targeted grep + read around
`_mpc_truth_import_acpf`, lines 1557-1650), `test/test_planning_noninteger.jl` (read in
full for the PVAL-04 registry), `test/test_planning_master.jl`, `test/test_planning_benders.jl`,
`test/test_planning_hardening.jl` (targeted reads for `@testitem`/fixture conventions),
`test/fixtures_phase4.jl`, `test/fixtures_planning.jl` (read in full for
`@testmodule`/fixture-helper conventions), `test/test_planning_certification_bilevel.jl`
(targeted read for `build_joint_reference`), `docs/literate/stackelberg_benders.jl` (read
in full).
**Files scanned:** 14 files read (5 full `src/planning/*.jl`, 1 full `src/data/ieee13.jl`,
1 full Literate experiment, 2 full test fixture modules, 5 targeted test-file reads).
**Pattern extraction date:** 2026-10-01
