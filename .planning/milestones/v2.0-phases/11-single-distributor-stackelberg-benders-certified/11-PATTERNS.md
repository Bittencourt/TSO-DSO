# Phase 11: Single-Distributor Stackelberg-Benders (Certified) - Pattern Map

**Mapped:** 2026-07-22
**Files analyzed:** 9 (3 src modules, 1 include-block edit, 4 test files, 1 test manifest edit)
**Analogs found:** 9 / 9 (all have a strong or partial match; none are fully greenfield —
the project's build-once/re-solve idiom and TestItems conventions cover every file)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/planning/follower.jl` | model/service (build-once JuMP LP) | request-response (build-once, re-solve at trial `z`) | `src/planning/subproblem.jl` (`PlanningOracle`/`build_planning_oracle`/`solve_planning_oracle!`) | exact (same build-once/`Parameter`/re-solve shape; different problem class LP vs SOCP) |
| `src/planning/master.jl` | model/service (build-once JuMP LP, persistent row growth) | CRUD-like (append-only cut rows) + request-response (re-solve) | `src/admm/DsoOpt.jl` (`build_dso_opt`/`solve_dso!`/`set_rho!`) for build-once/mutate-coefficient idiom; JuMP official Benders tutorial pattern (cited in RESEARCH.md) for the cut-accumulation shape itself | role-match (DsoOpt shows build-once + post-build mutation; no existing file grows persistent constraint ROWS — that part is genuinely new, guided by RESEARCH.md Pattern 1/Code Examples) |
| `src/planning/benders.jl` | orchestration/service (plain-Julia outer loop, no JuMP model of its own) | event-driven/iterative (loop: solve → cut → checkpoint → converge?) | `src/admm/solve_admm.jl` (`solve_admm`) — hand-rolled outer loop over build-once subproblems, fail-loud maxiter cap, per-iteration diagnostics | role-match (same orchestration shape: guards → build subproblems once → loop → fail-loud cap → final gate); convergence criterion is DIFFERENT (UB/LB gap, not residual — do not copy `AdmmResiduals`) |
| `src/TSODSO.jl` (include block edit) | config/wiring | — | `src/TSODSO.jl` itself — the existing `planning/` include block (lines 111-113) | exact (append 3 lines in the same block, same ordering discipline) |
| `test/test_planning_follower.jl` | test | request-response (feasible + Farkas-certificate branches) | `test/test_planning_oracle.jl` (build-once invariance, NamedTuple-shape assertions) + `test/test_planning_retry.jl` (deliberately-provoked failure-branch pattern, `TSODSO.select_optimizer(...)` never a bare solver) | exact |
| `test/test_planning_master.jl` | test | CRUD (cut accumulation) + request-response | `test/test_planning_oracle.jl` (build-once `num_variables`/`num_constraints` invariance idiom — but INVERTED: master rows are EXPECTED to grow, so assert monotonic growth instead of invariance) | role-match |
| `test/test_planning_benders.jl` | test | event-driven (integration, end-to-end loop) | `test/test_admm.jl` (full end-to-end convergence integration test over a small fixture) — not read line-by-line this pass (large), but is the established analog for "run the whole hand-rolled loop on a small fixture and assert convergence + gap" | role-match |
| `test/test_bilevel_certification.jl` (RESEARCH.md/CONTEXT.md call it `test_planning_certification.jl` — same file, planner should pick ONE name; see Metadata note) | test | request-response (independent MPEC cross-check, permanent regression) | `test/test_planning_retry.jl` (deliberate, documented INFRA-02 exception header pattern) + BilevelJuMP official docs (Code Examples in RESEARCH.md) | partial (no existing BilevelJuMP usage in repo; test-file conventions carry over, MPEC content is genuinely new) |
| `test/Project.toml` | config | — | `test/Project.toml` itself (existing `[deps]` block) | exact (add `BilevelJuMP` to `[deps]` + a `[compat]` block; no existing `[compat]` block today — see below) |

## Pattern Assignments

### `src/planning/follower.jl` (model, request-response, build-once LP)

**Analog:** `src/planning/subproblem.jl` (`PlanningOracle`)

**Header/seam-comment convention** (subproblem.jl lines 1-27): every planning module opens
with a `# SEAM:` / `# OWNER:` comment block naming the plan and design decisions (D-xx) it
implements, then a prose paragraph explaining what it reuses/does NOT reuse. `follower.jl`
should open the same way, citing PLAN-04 and the "no penalized-slack shortcut" decision.

**Struct + build pattern** (subproblem.jl lines 59-69, 110-211):
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

function build_planning_oracle(feeder, pf::AbstractPowerFlow, aggregators; λ₀, T::Int = 24)
    isempty(aggregators) && throw(ArgumentError("build_planning_oracle needs at least one aggregator"))
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
    model = Model(select_optimizer(problem_class(pf)))   # INFRA-02 — never Model(HiGHS.Optimizer)
    ...
    @variable(model, z[t = 1:T] in Parameter(0.0))
    @constraint(model, pin[t = 1:T], p_import[t] == z[t])
    @objective(model, Max, ...)
    return PlanningOracle(model, ctx, z, pin, p_import, aggregators[1].bus, T, feeder, Vector{Float64}(λ₀))
end
```
Copy the shape exactly for `FollowerLP`/`build_follower`, but route through
`select_optimizer(LP())` (never a formulation-generic dispatch — the follower is always LP
per CONTEXT.md), and use RESEARCH.md's own Pattern 3 code example (already project-shaped):
```julia
function build_follower(; T::Int, corridor_cap::Real, c_inv::Real, c_op::Vector{<:Real})
    model = Model(select_optimizer(LP()))             # INFRA-02
    @variable(model, x_inv >= 0)
    @variable(model, x_op[1:T] >= 0)
    @variable(model, z[t = 1:T] in Parameter(0.0))     # SAME Parameter idiom as subproblem.jl
    @constraint(model, invest_op[t = 1:T], x_op[t] <= corridor_cap * x_inv)
    @constraint(model, coupling[t = 1:T], x_op[t] == z[t])   # dual = π_s / Farkas ray
    @objective(model, Min, c_inv * x_inv + sum(c_op[t] * x_op[t] for t in 1:T))
    return (; model, x_inv, x_op, z, coupling)
end
```

**Re-solve + Farkas-branch pattern** (RESEARCH.md Pattern 3, mirrors subproblem.jl's
`set_parameter_value.`/gate discipline at lines 274-303, but DIVERGES on retry — see below):
```julia
function solve_follower!(f, z_trial; max_attempts = 4)
    set_parameter_value.(f.z, z_trial)
    optimize!(f.model)     # NOT solve_with_retry! — infeasibility must be OBSERVED, not retried away
    if is_solved_and_feasible(f.model; dual = true)
        return (; feasible = true, cost = objective_value(f.model), π_s = dual.(f.coupling))
    elseif dual_status(f.model) == MOI.INFEASIBILITY_CERTIFICATE
        return (; feasible = false, v = dual_objective_value(f.model), u = dual.(f.coupling))
    else
        error("follower LP neither solved nor produced an infeasibility certificate — refusing to trust: " *
              "termination_status=$(termination_status(f.model)) dual_status=$(dual_status(f.model))")
    end
end
```
**Divergence from the analog (document explicitly in the module header):**
`subproblem.jl`'s `solve_planning_oracle!` calls `solve_with_retry!` as the SOLE solve entry
point (line 278). The follower must NOT do this for the infeasible branch — `RETRYABLE_STATUSES`
(retry.jl line 33) excludes `INFEASIBLE`/`INFEASIBILITY_CERTIFICATE` by design, so routing
through it would either mask the certificate or throw before the Farkas ray is ever read. Call
`optimize!` directly and branch on `is_solved_and_feasible`/`dual_status`, per RESEARCH.md
Pattern 3 and Anti-Patterns.

**Farkas certificate reading** (RESEARCH.md "Code Examples" section, MOI's own machinery —
do not hand-roll):
```julia
optimize!(follower.model)
if dual_status(follower.model) == MOI.INFEASIBILITY_CERTIFICATE
    v = dual_objective_value(follower.model)
    u = dual.(follower.coupling)
end
```

**Boundary guards** (mirrors subproblem.jl lines 117-128 and DsoOpt.jl lines 128-147):
`ArgumentError` on `T < 1`, `corridor_cap <= 0`, `length(c_op) != T`, before any `@variable`/
`@objective` — same "fail here, not deep in objective assembly" discipline.

**Pitfall F1 handling** (RESEARCH.md): if the Farkas certificate is not reliably returned on
the actual fixture, `set_attribute(model, "presolve", "off")` locally on the follower model
only — mirrors how `retry.jl`'s escalation ladder scopes attribute changes to one model at a
time (retry.jl lines 94-108), never a global solver-default change.

---

### `src/planning/master.jl` (model, CRUD-like cut accumulation + request-response)

**Analog (build-once/mutate idiom):** `src/admm/DsoOpt.jl`

**Build-once model + persistent handles pattern** (DsoOpt.jl lines 69-79, 180-265):
```julia
struct DsoOpt{P, PI, F}
    model::Model
    ctx::ModelContext
    pag::P          # the coupling container the loop mutates
    p_import::PI
    load_nodes::Vector{Int}
    T::Int
    feeder::F
    ρ::Float64
    λ₀::Vector{Float64}
end

model = Model(select_optimizer(SOCP()))   # INFRA-02 — never names a solver
...
@objective(model, Min, sum(λ₀[t] * p_import[t] for t in 1:T) + 0.5 * ρ * sum(pag_dso[j, t]^2 for j in load_nodes, t in 1:T))
```
For `master.jl`, the analogous `BendersMaster` struct holds `model`, investment vars, `z`,
epigraph `α`, and vectors/dicts of accumulated cut metadata (for the S1 cut-validity test).
Mutation-without-rebuild is the SAME discipline as `set_objective_coefficient`
(DsoOpt.jl lines 296-335) — but for the master, mutation is `@constraint(model, ...)` ADDING a
new row each iteration (persistent growth is EXPECTED here, unlike DsoOpt's fixed shape).

**Epigraph lower bound — the one place this diverges from every existing build-once model**
(RESEARCH.md Pattern 1 / Pitfall M1, no in-repo analog — this is the genuinely new piece):
```julia
α_lb = -(worst_case_follower_cost(follower_fixture) + worst_case_oracle_cost(oracle_fixture))
@variable(master.model, α >= α_lb)     # NEVER an unbounded epigraph — iteration 1 has zero cuts
@objective(master.model, Min, <investment cost> + α)
```

**Persistent cut-row accumulation** (RESEARCH.md Code Examples, CONTEXT.md-locked D-05 form):
```julia
# Optimality cut (oracle or follower), appended as a NEW row — never replacing an old one:
@constraint(master.model, α >= cost_k + sum(π[t] * (master.z[t] - z_k[t]) for t in 1:T))

# Feasibility cut (follower Farkas ray only):
@constraint(master.model, v_k + sum(u[t] * (master.z[t] - z_k[t]) for t in 1:T) <= 0)
```

**Boundary guards + solve gate:** mirror `build_dso_opt`'s guards (DsoOpt.jl lines 128-147:
empty investment set, `T` mismatch) and `solve_dso!`'s STRICT `assert_solved!` call
(DsoOpt.jl lines 296-321) — master solves are ALWAYS `strict = true` (never
`allow_almost = true`; CONTEXT.md locks `assert_solved!(...; allow_almost=false)` on every
cut-producing solve, including the master's own solve).

**Anti-pattern to flag in the module header (per CLAUDE.md/RESEARCH.md):** never rebuild the
JuMP model to add a cut — `@constraint` on the existing `model` handle only, exactly as
`solve_dso!`/`set_rho!` never call `Model(...)` again after `build_dso_opt`.

---

### `src/planning/benders.jl` (orchestration, event-driven outer loop)

**Analog:** `src/admm/solve_admm.jl` (`solve_admm`)

**Boundary-guard-then-build-once-then-loop shape** (solve_admm.jl lines 116-181):
```julia
function solve_admm(feeder, pf::ConvexBranchFlow, aggregators; T::Int = 24, λ₀, ρ::Real,
                     maxiter::Int = 200, tol::Real = 1e-5, ...)
    isempty(aggregators) && throw(ArgumentError("solve_admm needs at least one aggregator"))
    T >= 1 || throw(ArgumentError("solve_admm needs T ≥ 1 (got T=$T)"))
    length(λ₀) == T || throw(ArgumentError(...))
    maxiter >= 1 || throw(ArgumentError("solve_admm needs maxiter ≥ 1 (got maxiter=$maxiter)"))

    # ---- BUILD ONCE: the subproblem models are constructed OUTSIDE the loop ----
    dso = build_dso_opt(feeder, aggregators, T; ρ = ρf, λ₀ = λ₀)
    ...
    for iter in 1:maxiter
        ... solve subproblems, update state ...
        converged_flag && break
    end
    converged_flag || throw(ErrorException("solve_admm FAILED to converge: hit maxiter=$maxiter ... "))
    return (; welfare, dadp, λ, iters, residuals, dso_ctx, exact_maxgap)
end
```
For `solve_stackelberg!`/`benders.jl`: same shape — guards, then `build_master`/
`build_planning_oracle`/`build_follower` OUTSIDE the loop (never inside), then the
iterate-and-cut loop, then a fail-loud `error(...)` on `MAX_ITER` exhaustion (never silent).

**Fail-loud maxiter cap** (solve_admm.jl lines 342-352) — copy the DIAGNOSTIC-RICH style
(name the last-known residual/gap values, name the tunable knobs, cite the thesis/RESEARCH
pitfall) for the Benders loop's own exhaustion error, per CONTEXT.md's D-10 requirement and
RESEARCH.md Pattern 2:
```julia
k == MAX_ITER && error("Benders loop exhausted $MAX_ITER iterations without converging (gap=$gap) — refusing to silently return a non-converged result")
```

**UB/LB gap convergence loop body** (RESEARCH.md Pattern 2, CONTEXT.md-locked formula —
structurally DIFFERENT from `solve_admm`'s two-residual stop; do not reuse `AdmmResiduals`,
per Pitfall 7 / Don't-Hand-Roll table):
```julia
for k in 1:MAX_ITER
    optimize_master!(master)                                  # solve_with_retry! + assert_solved!(allow_almost=false)
    LB = objective_value(master.model)
    z_k = value.(master.z)
    oracle_res   = solve_planning_oracle!(oracle, z_k)
    follower_res = solve_follower!(follower, z_k)
    if !follower_res.feasible
        add_feasibility_cut!(master, follower_res.v, follower_res.u, z_k)
        continue                                               # a feasibility cut does not update UB
    end
    add_optimality_cut!(master, oracle_res.cost, oracle_res.π, z_k)
    add_optimality_cut!(master, follower_res.cost, follower_res.π_s, z_k)
    UB = min(UB, <leader_investment_cost>(value.(master.y)) + oracle_res.cost + follower_res.cost)
    gap = (UB - LB) / max(1, abs(UB))
    checkpoint_iteration!((; k, LB, UB, gap, z_k), k)          # D-10, per Benders iteration exactly
    gap <= TOL && break
end
```

**Checkpointing integration:** call `checkpoint_iteration!` (checkpoint.jl lines 41-64)
exactly once per Benders iteration, with the SAME `iter_%05d` filename contract — reuse
verbatim, no wrapper needed.

**Solve entry points:** every cut-producing solve routes through `solve_with_retry!`
(retry.jl) for the master and oracle, but the follower's infeasible branch bypasses it
(see follower.jl section above) — `benders.jl`'s loop body must call `solve_follower!`
directly, never wrap it in `solve_with_retry!`.

---

### `src/TSODSO.jl` (include-block edit)

**Analog:** the file's own existing planning include block

**Exact insertion point** (TSODSO.jl lines 111-113):
```julia
include("planning/retry.jl")        # solve_with_retry! wraps assert_solved! (plan 10-01, D-08/D-09)
include("planning/checkpoint.jl")   # checkpoint_iteration!/resume_from_checkpoint (plan 10-01, D-10)
include("planning/subproblem.jl")   # PlanningOracle build-once z-pin oracle (plan 10-02, PLAN-01/02)
```
Append three new lines directly after `subproblem.jl` (ordering matters: `follower.jl` has
no cross-dependency on `subproblem.jl` but should still load after it for a stable diff;
`master.jl` and `benders.jl` must load AFTER both `subproblem.jl` and `follower.jl`, since
`benders.jl` calls `solve_planning_oracle!`/`solve_follower!`/master functions at call time,
not include time — Julia's include order only needs definitions to exist before first USE at
runtime, but the project's own convention, per the existing comment block's dependency-order
discipline, is to state WHY each file is positioned where it is):
```julia
include("planning/follower.jl")     # FollowerLP build-once transmission LP (plan 11-0x, PLAN-04)
include("planning/master.jl")       # BendersMaster build-once cut-accumulating LP (plan 11-0x, PLAN-05)
include("planning/benders.jl")      # solve_stackelberg! outer loop (plan 11-0x, PLAN-06)
```
Follow the file's own top-of-block convention: a comment above the three new lines explaining
what plan/requirement wired them and why they are positioned after `subproblem.jl` (mirrors
the existing prose at lines 101-110 for the retry/checkpoint/subproblem block).

---

### `test/test_planning_follower.jl` (test)

**Analog:** `test/test_planning_oracle.jl` (build-once invariance + NamedTuple-shape idiom)
and `test/test_planning_retry.jl` (deliberately-provoked-failure branch + solver-factory-only
convention)

**File header convention** (test_planning_oracle.jl lines 1-19): a `# Seam:` comment block
naming the src file, the plan/requirement, and any fixture-feasibility caveat (mirrors the
oracle file's own z_trial feasibility note) — `test_planning_follower.jl` should document its
own corridor-capacity infeasibility design (which `z` values are deliberately over-capacity
to trigger the Farkas branch).

**Build-once invariance test shape** (test_planning_oracle.jl lines 59-88):
```julia
@testitem "..." tags = [:planning] setup = [Phase6Fixtures] begin
    using TSODSO
    using JuMP: num_variables, num_constraints, set_parameter_value, optimize!
    f = build_follower(...)
    nv0 = num_variables(f.model)
    nc0 = num_constraints(f.model; count_variable_in_set_constraints = true)
    solve_follower!(f, z_trial_1)
    solve_follower!(f, z_trial_2)
    @test num_variables(f.model) == nv0
    @test num_constraints(f.model; count_variable_in_set_constraints = true) == nc0
end
```

**Farkas-certificate regression** (RESEARCH.md Pitfall F1's own recommended test):
```julia
@testitem "planning follower: infeasible z_trial yields a genuine Farkas certificate" tags = [:planning] begin
    using TSODSO, JuMP
    f = build_follower(; T = ..., corridor_cap = ..., c_inv = ..., c_op = ...)
    res = solve_follower!(f, z_over_capacity)
    @test res.feasible == false
    @test all(isfinite, res.u)
    @test isfinite(res.v)
end
```

**Deliberately-provoked-failure + solver-factory-only convention** (test_planning_retry.jl
lines 8-31, 87-94): build the model via `TSODSO.select_optimizer(TSODSO.LP())`, never
`import HiGHS` directly in this file (INFRA-02 discipline holds for this test file, unlike
the certification test which has a documented, scoped exception).

---

### `test/test_planning_master.jl` (test)

**Analog:** `test/test_planning_oracle.jl`'s build-once idiom, INVERTED for expected growth

Where the oracle test asserts `num_constraints` is INVARIANT across re-solves
(test_planning_oracle.jl lines 86-87), the master test must assert it is MONOTONICALLY
NON-DECREASING as cuts are added, and that `num_variables` stays invariant (investment vars +
`z` + `α` never change count — only constraint ROWS grow):
```julia
nc0 = num_constraints(master.model; count_variable_in_set_constraints = true)
add_optimality_cut!(master, cost1, π1, z1)
nc1 = num_constraints(master.model; count_variable_in_set_constraints = true)
@test nc1 == nc0 + 1
```

**Epigraph lower-bound regression** (RESEARCH.md Pitfall M1 — the test this pitfall
explicitly calls for): assert the FIRST master solve (zero cuts) returns `OPTIMAL`, not
`DUAL_INFEASIBLE`:
```julia
master = build_master(...)
solve_master!(master)   # zero cuts yet
@test termination_status(master.model) == MOI.OPTIMAL
```

**Cut-validity invariant** (RESEARCH.md Pitfall S1, `test_planning_master.jl`'s own assigned
location): for a later-evaluated `z'`, assert the recorded cut never gets violated by the true
re-evaluated cost — mirrors the strict `assert_solved!` gate discipline used everywhere else
in the planning/ directory (status.jl lines 38-66).

---

### `test/test_planning_benders.jl` (test, integration)

**Analog:** `test/test_admm.jl`'s end-to-end convergence pattern (large file, not read
line-by-line this pass — Grep confirms it exists and is the established "run the full
hand-rolled loop on a small fixture, assert convergence" pattern; `solve_admm.jl`'s own
docstring return-shape and fail-loud-maxiter tests are the concrete API-shape analog already
read above)

**End-to-end shape:**
```julia
@testitem "planning benders: converges end-to-end with documented UB/LB gap" tags = [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    result = solve_stackelberg!(oracle_fixture, follower_fixture; tol = 1e-6, max_iter = ...)
    @test result.gap <= 1e-6
end
```

**Iteration-cap loud-failure regression** (mirrors test_planning_retry.jl's
`@test_throws ErrorException` + `occursin("exhausted", ...)` idiom, retry.jl lines 152-160,
and solve_admm.jl lines 342-352's message style):
```julia
@test_throws ErrorException solve_stackelberg!(...; max_iter = 1)   # too few to converge
```

---

### `test/test_bilevel_certification.jl` / `test/test_planning_certification.jl` (test)

**Analog:** `test/test_planning_retry.jl`'s documented-exception header convention
(lines 1-31: a file-header explaining exactly WHY this file deviates from the project's
standard solver-abstraction discipline) + BilevelJuMP's own official docs (RESEARCH.md Code
Examples, Pattern 4)

**Sanctioned INFRA-02 exception header** (RESEARCH.md Pitfall B3 — write this into the file
header explicitly, mirroring how `ext/TSODSOGurobiExt.jl` is the one other sanctioned place a
concrete solver is named):
```julia
# NOTE (INFRA-02 exception, Pitfall B3): BilevelModel's own constructor contract requires a
# bare zero-arg solver constructor (HiGHS.Optimizer / Ipopt.Optimizer), not an
# OptimizerWithAttributes from select_optimizer(...). This file — and ONLY this file —
# imports HiGHS/Ipopt directly, because BilevelJuMP is a validation-oracle-only, test-only
# dependency (never imported by src/), per CLAUDE.md's "validation oracle only" rule.
using BilevelJuMP, HiGHS, Ipopt
```

**BigMMode + StrongDualityMode dual-certification pattern** (RESEARCH.md Pattern 4, from
`joaquimg.github.io/BilevelJuMP.jl`):
```julia
model_bigm = BilevelModel(HiGHS.Optimizer, mode = BilevelJuMP.BigMMode(primal_big_M = 100, dual_big_M = 100))
@variable(Upper(model_bigm), y_inv >= 0)
@variable(Lower(model_bigm), x_op[1:T] >= 0)
@objective(Upper(model_bigm), Min, c_y_inv * y_inv + ...)
@objective(Lower(model_bigm), Min, sum(c_x_op[t] * x_op[t] for t in 1:T))
@constraint(Lower(model_bigm), coupling[t = 1:T], x_op[t] == ...)
optimize!(model_bigm)

model_sd = BilevelModel(Ipopt.Optimizer, mode = BilevelJuMP.StrongDualityMode())
# ... same Upper()/Lower() blocks ...
optimize!(model_sd)

@assert isapprox(value(y_inv, model_bigm), value(y_inv, model_sd); rtol = 1e-4)
@assert isapprox(objective_value(model_bigm), objective_value(model_sd); rtol = 1e-4)
@assert isapprox(value(y_inv, model_bigm), y_inv_hand_enumerated; rtol = 1e-4)
```

**Permanent-regression tagging convention** (mirrors every other `test_planning_*.jl` file):
`tags = [:planning]`, part of the default full-suite run — NOT a throwaway script, per
CONTEXT.md's explicit "retained forever" instruction.

---

### `test/Project.toml` (config)

**Analog:** the file itself (current `[deps]` block, no existing `[compat]` block)

Current file (read in full):
```toml
[deps]
Aqua = "4c88cf16-eb10-579e-8560-4a9242c79595"
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
DrWatson = "634d3b9d-ee7a-5ddf-bec9-22491ea816e1"
JET = "c3a54625-cd67-489e-a8e7-0a5a0ff4e31b"
JuMP = "4076af6c-e467-56ae-b986-b466b2749572"
StableRNGs = "860ef19b-820b-49d6-a774-d7a799459cd3"
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
TestItemRunner = "f8b46487-2199-4994-9208-9a1283c18c0a"
TestItems = "1c621080-faea-4a02-84b6-bbd5e436b8fe"
```
Add `BilevelJuMP` (UUID `485130c0-...`, per RESEARCH.md's Package Legitimacy Audit — confirm
exact UUID via `julia --project=test -e 'import Pkg; Pkg.add("BilevelJuMP")'` rather than
hand-typing it) to `[deps]` in the SAME alphabetically-sorted style as the existing block.
RESEARCH.md's Installation section notes there is currently NO `[compat]` block in this file
at all — CONTEXT.md's instruction to add one is aspirational; either (a) add a NEW
`[compat]` section pinning `BilevelJuMP = "0.6.3"` (introducing the section), or (b) follow
whatever convention the existing file lacks and match it (no compat pins at all). Prefer (a)
per CONTEXT.md's explicit "pin an exact `[compat]` version, never a floating range" security
guidance (RESEARCH.md Known Threat Patterns table) — this is a deviation FROM the current
file's own (compat-less) convention, made deliberately for supply-chain-integrity reasons the
existing file simply never needed before (its other deps are all long-established, unpinned
test-only tools).

## Shared Patterns

### Solver-factory routing (INFRA-02)
**Source:** `src/solver/factory.jl` (`select_optimizer(::LP)`, line 42) and
`src/solver/ProblemClass.jl` (`LP` singleton, line 26)
**Apply to:** `follower.jl`, `master.jl` — both call `Model(select_optimizer(LP()))`,
never `Model(HiGHS.Optimizer)` directly.
```julia
select_optimizer(::LP) = optimizer_with_attributes(HiGHS.Optimizer, "presolve" => "on")
```

### Solve-status trust gate (INFRA-03)
**Source:** `src/core/status.jl` (`assert_solved!`, lines 38-66)
**Apply to:** every cut-producing solve in `master.jl`/`benders.jl` (oracle solves already
gated inside `solve_planning_oracle!`). STRICT gate only (`allow_almost=false`) — never the
ADMM-style `allow_almost=true` intermediate tolerance, since Benders cuts must be built from
a genuinely optimal, dual-feasible point.
```julia
function assert_solved!(model::Model; dual::Bool = true, allow_local::Bool = false, allow_almost::Bool = false)
    optimize!(model)
    ok = is_solved_and_feasible(model; dual = dual, allow_local = allow_local)
    ...
    ok || error("Solve failed — refusing to trust results: ...")
    return model
end
```

### Escalating retry wrapper (D-08/D-09)
**Source:** `src/planning/retry.jl` (`solve_with_retry!`, `RETRYABLE_STATUSES`, lines 33, 85-163)
**Apply to:** `master.jl`'s and the oracle's cut-producing solves ONLY — explicitly NOT
`follower.jl`'s solve (its infeasible branch must be read directly, per the follower section
above and RESEARCH.md's Anti-Patterns).

### Checkpointing (D-10)
**Source:** `src/planning/checkpoint.jl` (`checkpoint_iteration!`, lines 41-64)
**Apply to:** `benders.jl`'s outer loop — call once per Benders iteration exactly, same
`iter_%05d` contract, no wrapper.

### Build-once / never-rebuild discipline
**Source:** `src/admm/DsoOpt.jl` (`solve_dso!`, `set_rho!`, lines 267-370) and
`src/planning/subproblem.jl` (`solve_planning_oracle!`, lines 263-303)
**Apply to:** all three new src files — `num_variables`/`num_constraints` (or, for the
master, `num_variables` alone) must stay invariant across re-solves except for the master's
deliberate constraint-row growth via new `@constraint` calls (never `Model(...)` again).

### Boundary-guard-before-objective-assembly
**Source:** `src/planning/subproblem.jl` lines 117-128, `src/admm/DsoOpt.jl` lines 128-147,
`src/admm/solve_admm.jl` lines 134-151
**Apply to:** every `build_*`/`solve_stackelberg!` entry point — `ArgumentError` for empty
collections, `T`/length mismatches, out-of-range indices, non-positive `maxiter`/`T`, BEFORE
any `@variable`/`@objective`/loop iteration.

### TestItems `[:planning]` tag + fixture-module convention
**Source:** every `test_planning_*.jl` file (headers), `test/fixtures_phase6.jl`
(`@testmodule Phase6Fixtures`, `ToyElasticDevice` pattern in `test_planning_oracle.jl` lines
144-164)
**Apply to:** all four new test files — `tags = [:planning]`, `setup = [Phase6Fixtures, ...]`
where a fixture is needed, and (per RESEARCH.md Pitfall O1 / Wave-0-Gaps) prefer the
DEV-05-conformant `ToyElasticDevice` pattern for the oracle side of the Phase-11 fixture over
`Phase6Fixtures`'s real aggregator, to keep the follower's corridor capacity as the sole
designed infeasibility surface.

## No Analog Found

None — every file has at least a role-match analog in the existing codebase (see table
above). The genuinely novel pieces with NO direct in-repo precedent are:

| Aspect | File | Why no direct analog | What guides it instead |
|---|---|---|---|
| Persistent, ever-growing constraint rows on a build-once model | `master.jl` | Every existing build-once model (`DsoOpt`, `AgrOpt`, `PlanningOracle`) has a FIXED row count across re-solves — none grows rows | RESEARCH.md Pattern 1/Architecture Patterns + the official JuMP Benders tutorial (cited) |
| Genuine HiGHS Farkas-ray reading | `follower.jl` | No existing file reads `MOI.INFEASIBILITY_CERTIFICATE`/`dual_objective_value` | RESEARCH.md "Don't Hand-Roll" table, JuMP/MOI infeasibility-certificates background docs |
| BilevelJuMP MPEC construction | `test_bilevel_certification.jl` | No BilevelJuMP usage anywhere in the repo today | RESEARCH.md Pattern 4/Code Examples, official BilevelJuMP tutorials (fetched directly this session per RESEARCH.md) |

## Metadata

**Analog search scope:** `src/planning/`, `src/admm/`, `src/solver/`, `src/core/`, `test/`
(all `test_planning_*.jl`, `test_admm.jl`, `fixtures_phase6.jl`, `runtests.jl`, `Project.toml`)
**Files scanned:** `src/planning/subproblem.jl`, `src/planning/retry.jl`,
`src/planning/checkpoint.jl`, `src/admm/DsoOpt.jl`, `src/admm/solve_admm.jl` (partial,
targeted sections), `src/admm/residuals.jl` (header only), `src/solver/factory.jl`,
`src/solver/ProblemClass.jl`, `src/core/status.jl`, `src/TSODSO.jl`,
`test/test_planning_oracle.jl`, `test/test_planning_retry.jl`,
`test/test_planning_checkpoint.jl`, `test/fixtures_phase6.jl`, `test/runtests.jl`,
`test/Project.toml`
**Pattern extraction date:** 2026-07-22

**Naming discrepancy flagged for the planner:** the orchestrator's expected file list
(pattern-mapping-context) names the certification test `test/test_bilevel_certification.jl`;
RESEARCH.md's own "Recommended Project Structure" and "Wave 0 Gaps" tables both name it
`test/test_planning_certification.jl`. These are the SAME file under two different proposed
names — the planner should pick one (recommend `test_planning_certification.jl` for
consistency with the `test_planning_*.jl` naming convention every other new test file in
this phase follows) and use it consistently across all PLAN-07/PVAL-01 tasks.
