# src/planning/follower.jl
#
# SEAM: transmission-reinforcement follower LP with genuine Farkas certificates
# (PLAN-04).
# OWNER: plan 11-01.
#
# A genuinely NEW, small, declarative transmission-corridor LP — distinct from the
# reused operational `PlanningOracle` (subproblem.jl, Phase 10, unmodified). Built
# EXACTLY ONCE via `build_follower`; `solve_follower!` re-solves it at a Benders
# trial `z_trial` via `set_parameter_value.` only (never a rebuild), mirroring
# `subproblem.jl`'s build-once/`Parameter` idiom.
#
# NO PENALIZED-SLACK SHORTCUT (CONTEXT.md locked decision, PLAN-04 success
# criterion 1): an infeasible `z_trial` must return a GENUINE HiGHS Farkas/dual-ray
# certificate (`dual_status(model) == MOI.INFEASIBILITY_CERTIFICATE`), never a
# hand-rolled "always feasible" heuristic.
#
# CONTEXT.md's Amendment (revision 1) — scoped exclusion: `solve_follower!` calls
# `optimize!` DIRECTLY, never the escalating retry wrapper (`src/planning/retry.jl`).
# That wrapper's `RETRYABLE_STATUSES` deliberately never includes `MOI.INFEASIBLE`/
# `MOI.INFEASIBILITY_CERTIFICATE` — retrying a genuine infeasibility would silently
# discard the Farkas certificate this file's own success criterion requires. The
# certificate only exists on the UN-RETRIED, directly-observed infeasible solve.
# The master's and the oracle's own cut-producing solves remain fully gated by the
# retry wrapper's strict solved-and-feasible check (never `allow_almost`) — this
# amendment narrows scope to the follower's infeasible branch only.

using JuMP

"""
    FollowerLP{Z,C}

The built-ONCE transmission-reinforcement follower LP (PLAN-04): a minimal
PSR-note-faithful LP that invests in corridor capacity (`x_inv`) and delivers an
operating flow (`x_op[t]`) equal to the Benders trial `z[t]` via a named coupling
constraint, whose dual is the follower's own coupling-dual `π_s` (feasible branch)
or whose Farkas ray is the feasibility-cut coefficient (infeasible branch).

# Fields

  - `model::Model` — the follower LP, built ONCE via `Model(select_optimizer(LP()))`
    (INFRA-02 — never `Model(HiGHS.Optimizer)` directly); re-solved via
    `set_parameter_value.(f.z, ...)` + `optimize!` only, never rebuilt.
  - `x_inv::VariableRef` — the corridor-reinforcement investment (continuous, no
    binary/integer variable anywhere in this file, per PVAL-04's continuous-only
    scope).
  - `x_op::Vector{VariableRef}` — the length-T operating flow delivered by the
    corridor.
  - `z` — the length-T `Parameter`-typed coupling-flow setpoint; re-settable via
    `set_parameter_value.(f.z, z_trial)` with NO rebuild.
  - `coupling` — the named `coupling[t]: x_op[t] == z[t]` constraint; its dual
    (feasible branch) or its restriction of the Farkas ray (infeasible branch) is
    read by [`solve_follower!`](@ref).
  - `T::Int` — the horizon.
  - `corridor_cap::Float64` — the corridor's per-unit-investment capacity
    coefficient (`x_op[t] <= corridor_cap * x_inv`).
  - `x_inv_max::Float64` — the investment upper bound.
"""
struct FollowerLP{Z, C}
    model::Model
    x_inv::VariableRef
    x_op::Vector{VariableRef}
    z::Z
    coupling::C
    T::Int
    corridor_cap::Float64
    x_inv_max::Float64
end

"""
    build_follower(; T::Int, corridor_cap::Real, x_inv_max::Real, c_inv::Real,
                   c_op::AbstractVector{<:Real}) -> FollowerLP

Build the transmission-reinforcement follower LP EXACTLY ONCE:

 1. Boundary guards — `T >= 1`, `corridor_cap > 0`, `x_inv_max > 0`,
    `length(c_op) == T` — each throws `ArgumentError` naming the offending value,
    BEFORE any `@variable`/`@objective` assembly (mirrors `subproblem.jl`'s
    boundary-guard-before-objective-assembly discipline).
 2. `model = Model(select_optimizer(LP()))` — INFRA-02, the sole solver-naming
    seam; never `Model(HiGHS.Optimizer)` directly.
 3. `0 <= x_inv <= x_inv_max` (continuous investment) and `x_op[t] >= 0`
    (continuous operation) — no binary/integer variable anywhere.
 4. `z[t] in Parameter(0.0)` — the SAME `Parameter` idiom as
    [`PlanningOracle`](@ref)'s `z`.
 5. `invest_op[t]: x_op[t] <= corridor_cap * x_inv` — the corridor's own capacity
    constraint.
 6. `coupling[t]: x_op[t] == z[t]` — the named coupling constraint whose dual
    (feasible branch) is the follower's own `π_s`, PLAN-04's literal scope.
 7. `Min c_inv*x_inv + Σ_t c_op[t]*x_op[t]` — the follower's own cost objective.

Returns a [`FollowerLP`](@ref).
"""
function build_follower(;
    T::Int,
    corridor_cap::Real,
    x_inv_max::Real,
    c_inv::Real,
    c_op::AbstractVector{<:Real},
)
    # Boundary guards FIRST — fail here, not deep in objective assembly.
    T >= 1 || throw(ArgumentError("build_follower needs T >= 1, got T=$T"))
    corridor_cap > 0 ||
        throw(ArgumentError("build_follower needs corridor_cap > 0, got $corridor_cap"))
    x_inv_max > 0 ||
        throw(ArgumentError("build_follower needs x_inv_max > 0, got $x_inv_max"))
    length(c_op) == T ||
        throw(ArgumentError("c_op has length $(length(c_op)), expected T=$T"))

    model = Model(select_optimizer(LP()))   # INFRA-02: never Model(HiGHS.Optimizer) directly

    @variable(model, 0 <= x_inv <= x_inv_max)
    @variable(model, x_op[t = 1:T] >= 0)
    @variable(model, z[t = 1:T] in Parameter(0.0))   # SAME Parameter idiom as subproblem.jl

    @constraint(model, invest_op[t = 1:T], x_op[t] <= corridor_cap * x_inv)
    @constraint(model, coupling[t = 1:T], x_op[t] == z[t])   # dual = π_s (feasible branch)

    @objective(model, Min, c_inv * x_inv + sum(c_op[t] * x_op[t] for t in 1:T))

    return FollowerLP(
        model,
        x_inv,
        x_op,
        z,
        coupling,
        T,
        Float64(corridor_cap),
        Float64(x_inv_max),
    )
end

"""
    solve_follower!(f::FollowerLP, z_trial::AbstractVector{<:Real}) -> NamedTuple

Re-solve the built-ONCE [`FollowerLP`](@ref) `f` at the Benders trial `z_trial`
(`set_parameter_value.` only, NEVER a rebuild) via `optimize!` called DIRECTLY —
NOT the escalating retry wrapper / strict solved-and-feasible gate (`src/planning/retry.jl`) —
because `RETRYABLE_STATUSES` deliberately excludes `MOI.INFEASIBLE`/
`MOI.INFEASIBILITY_CERTIFICATE`; retrying a genuine infeasibility would silently
discard the Farkas certificate this function's infeasible branch must return
(CONTEXT.md's Amendment (revision 1)).

Two mutually exclusive, exhaustively-checked branches:

  - FEASIBLE (`is_solved_and_feasible(f.model; dual = true)`): returns
    `(; feasible = true, cost, π_s)` where `cost = objective_value(f.model)` and
    `π_s = dual.(f.coupling)` (length-T).
  - INFEASIBLE (`dual_status(f.model) == MOI.INFEASIBILITY_CERTIFICATE`, a
    GENUINE HiGHS Farkas/dual ray, never a penalized-slack heuristic): returns
    `(; feasible = false, v, u)` where `v = dual_objective_value(f.model)` and
    `u = dual.(f.coupling)` (the certificate vector, restricted to the coupling
    rows) — both `isfinite`.

Any OTHER outcome (neither a trusted solve nor a genuine certificate) raises
loudly, naming `termination_status`/`dual_status` — this function refuses to
silently default an ambiguous outcome to either feasible or infeasible (T-11-01).

Throws `ArgumentError` when `length(z_trial) != f.T` (a shape mismatch must fail
loudly before `set_parameter_value.` — never silently truncate/pad).
"""
function solve_follower!(f::FollowerLP, z_trial::AbstractVector{<:Real})
    length(z_trial) == f.T ||
        throw(ArgumentError("z_trial has length $(length(z_trial)), expected T=$(f.T)"))

    set_parameter_value.(f.z, z_trial)   # mutate the Parameter, no rebuild

    # Deliberate departure from the escalating retry wrapper / strict solved gate
    # (CONTEXT.md Amendment (revision 1)): the infeasible branch below must be
    # OBSERVED on the UN-RETRIED solve, never retried away, or the Farkas
    # certificate is unreachable. RETRYABLE_STATUSES excludes
    # INFEASIBLE/INFEASIBILITY_CERTIFICATE by design (retry.jl).
    optimize!(f.model)

    if is_solved_and_feasible(f.model; dual = true)
        return (; feasible = true, cost = objective_value(f.model), π_s = dual.(f.coupling))
    elseif dual_status(f.model) == MOI.INFEASIBILITY_CERTIFICATE
        # GENUINE HiGHS Farkas/dual ray — never a penalized-slack "always feasible"
        # shortcut (PLAN-04 success criterion 1, T-11-01).
        return (;
            feasible = false,
            v = dual_objective_value(f.model),
            u = dual.(f.coupling),
        )
    else
        error(
            """
            solve_follower!: neither a trusted solve nor a genuine infeasibility certificate — refusing to trust results:
              termination_status : $(termination_status(f.model))
              primal_status      : $(primal_status(f.model))
              dual_status        : $(dual_status(f.model))
              raw_status         : $(raw_status(f.model))
            """,
        )
    end
end

export FollowerLP, build_follower, solve_follower!
