# src/planning/coupling.jl
#
# SEAM: shared transmission-reinforcement corridor coupling N distributors
# (NASH-01).
# OWNER: plan 13-01.
#
# The ONE genuinely NEW shared JuMP model this phase introduces: a build-once
# transmission-reinforcement corridor whose delivered-flow rows are owned
# individually by each of N distributors (`x_op[i, t]`, `coupling[i, t]:
# x_op[i,t] == z[i,t]`, one row per distributor per hour, each independently
# dualizable — directly generalizing `follower.jl`'s single-distributor
# `coupling[t]` row to N rows), but whose CAPACITY is POOLED across all N
# distributors via one shared `capacity[t]` row — this pooled row is the
# single genuinely new coupling constraint NASH-01 exists for; without it
# there would be N independent corridors, not a shared one.
#
# DELIBERATE DEPARTURE FROM 13-RESEARCH.md's Pattern 1 sketch: CONTEXT.md
# (this phase's locked, post-research user decision) OVERRIDES
# 13-RESEARCH.md's tentative design of one shared scalar `x_inv` with an
# `[ASSUMED]` equal-split `cost_share` vector (13-RESEARCH.md Assumptions Log
# A1, Open Question 2). This file instead implements PER-DISTRIBUTOR
# INVESTMENT OWNERSHIP: each distributor `i` owns its own reinforcement
# investment `x_inv[i]` and pays its own `c_inv[i]*x_inv[i]`; the effective
# pooled corridor capacity is `corridor_cap * Σᵢ x_inv[i]`. This resolves the
# N-distributor cost-allocation ambiguity the single-distributor PSR source
# leaves open, in favor of the game-theoretically cleaner model where each
# distributor's best response prices only its own investment — the SHARED
# object is the aggregate capacity, not the cost split. Document this
# override here (not 13-RESEARCH.md's sketch) for thesis traceability.
#
# CUT-INVALIDATION MATH ARGUMENT (embedded verbatim from 13-RESEARCH.md
# Pattern 1, since it justifies why nash.jl (plan 13-02) must give every
# atomic best-response a fresh Benders cut store):
#
# > Within ONE atomic best-response (fixed `z_{-i}`), the follower's value
# > function `V_i(z_i; z_{-i})` is convex in `z_i` (it is the optimal value of
# > a parametric LP whose RHS is affine in `z_i` alone at fixed `z_{-i}`), so
# > Benders cuts computed at successive trial points `z_i^(1), z_i^(2), ...`
# > within that best-response remain valid supporting hyperplanes of
# > `V_i(·; z_{-i})` for every `z_i` — this is exactly why Phase 11/12's
# > persistent (never-rebuilt) cut store across BENDERS ITERATIONS is
# > correct, and it is unchanged here. However, `V_i(z_i; z_{-i})` is a
# > genuinely DIFFERENT function of `z_i` for a different `z_{-i}` — the
# > shared capacity constraint's RHS slack available to distributor `i`
# > shifts by exactly `Δ(Σ_{j≠i} z_j)` — so a cut computed at OLD `z_{-i}` is
# > not merely "less tight", it can be actively WRONG (non-supporting) for
# > the NEW `V_i(·; z_{-i}^{new})`: e.g., a feasibility cut derived from the
# > follower's infeasibility at old, tighter `z_{-i}` may incorrectly exclude
# > a `z_i` that is now perfectly feasible once neighbors freed up capacity.
# > Retaining stale cuts across a `z_{-i}` change therefore risks a master
# > that converges to a POINT THAT IS NOT THE TRUE BEST RESPONSE to the
# > current `z_{-i}` — silently wrong, not just slow. This is why every
# > atomic best-response in this phase starts its master's cut store EMPTY
# > (CONTEXT.md's locked "correctness-first" decision): validity is certain
# > by construction, at the cost of re-deriving cuts on every best-response
# > (instrumented in `NashTrace` as the rebuild-cost finding this phase is
# > asked to surface, not silently retain). A future phase MAY revisit
# > cut-reuse if it can prove `V_i` is monotonically non-decreasing (or
# > otherwise boundable) in `z_{-i}` on this specific corridor model — not
# > attempted here (Deferred Ideas).
#
# PVAL-04 continuous-only scope: no binary/integer variable exists anywhere
# in this file — every `@variable` call below is continuous, regression-
# tested directly in test/test_planning_coupling.jl.

using JuMP

"""
    SharedTransmission{Z,C}

The built-ONCE, N-distributor shared transmission-reinforcement corridor
(NASH-01): `N` individually-dualizable per-distributor coupling rows
(`coupling[i, t]: x_op[i,t] == z[i,t]`) plus ONE pooled capacity row
(`capacity[t]: Σᵢ x_op[i,t] <= corridor_cap * Σᵢ x_inv[i]`) — the single
genuinely new shared constraint this phase introduces. Generalizes
[`FollowerLP`](@ref) (`src/planning/follower.jl`) from 1 distributor to `N`,
with per-distributor investment ownership (CONTEXT.md's locked decision —
see this file's header for the departure from 13-RESEARCH.md's tentative
single-shared-`x_inv` sketch).

# Fields

  - `model::Model` — built ONCE via `Model(select_optimizer(LP()))`
    (INFRA-02 — never `Model(HiGHS.Optimizer)` directly); re-solved via
    `set_parameter_value.` only, never rebuilt.
  - `x_inv::Vector{VariableRef}` — length `N`, one continuous investment
    variable PER DISTRIBUTOR (PVAL-04: no binary/integer anywhere).
  - `x_op::Matrix{VariableRef}` — `N × T`, distributor `i`'s delivered flow
    at hour `t`.
  - `z::Z` — the `N × T` `Parameter`-typed coupling-flow array (the SAME
    `Parameter` idiom as `follower.jl`/`subproblem.jl`, generalized to two
    indices); only the ACTIVE distributor's row is driven by its own
    Benders trial each best-response, all other rows stay pinned at their
    last `write_back!`-committed value.
  - `coupling::C` — the named `N × T` `coupling[i,t]: x_op[i,t] == z[i,t]`
    constraint container, one independently-dualizable row per
    distributor per hour.
  - `N::Int` — number of distributors (`N >= 2`; a "shared" model with
    `N=1` has nothing to share, NASH-01's own success criterion).
  - `T::Int` — horizon.
  - `corridor_cap::Float64` — per-unit-investment pooled capacity
    coefficient.
  - `x_inv_max::Vector{Float64}` — length `N`, per-distributor investment
    upper bound.
  - `c_inv::Vector{Float64}` — length `N`, per-distributor investment
    unit cost (each distributor pays `c_inv[i]*x_inv[i]` — the
    per-distributor-ownership departure from RESEARCH.md's equal-split
    sketch).
  - `c_op::Vector{Vector{Float64}}` — length `N`, each length `T`,
    per-distributor operating cost.
"""
struct SharedTransmission{Z, C}
    model::Model
    x_inv::Vector{VariableRef}
    x_op::Matrix{VariableRef}
    z::Z
    coupling::C
    N::Int
    T::Int
    corridor_cap::Float64
    x_inv_max::Vector{Float64}
    c_inv::Vector{Float64}
    c_op::Vector{Vector{Float64}}
end

"""
    build_shared_transmission(; N::Int, T::Int, corridor_cap::Real,
                              x_inv_max::AbstractVector{<:Real},
                              c_inv::AbstractVector{<:Real},
                              c_op::AbstractVector{<:AbstractVector{<:Real}}) -> SharedTransmission

Build the shared transmission-reinforcement corridor EXACTLY ONCE:

 1. Boundary guards — `N >= 2` (a "shared" model with `N=1` has nothing to
    share), `T >= 1`, `corridor_cap > 0`, `length(x_inv_max) == N` and every
    entry `> 0`, `length(c_inv) == N`, `length(c_op) == N` and every
    `c_op[i]` with `length == T` — each throws a distinct `ArgumentError`
    naming the offending value/index, BEFORE any `@variable`/`@objective`
    assembly (mirrors `build_follower`'s discipline exactly).
 2. `model = Model(select_optimizer(LP()))` — INFRA-02, the sole
    solver-naming seam; never `Model(HiGHS.Optimizer)` directly.
 3. `0 <= x_inv[i] <= x_inv_max[i]` (continuous, per distributor) and
    `x_op[i,t] >= 0` — no binary/integer variable anywhere (PVAL-04).
 4. `z[i,t] in Parameter(0.0)` — the SAME `Parameter` idiom as
    `follower.jl`/`subproblem.jl`, generalized to two indices.
 5. `coupling[i,t]: x_op[i,t] == z[i,t]` — `N*T` individually-dualizable
    rows, one per distributor per hour (generalizes `follower.jl`'s single
    `coupling[t]` row).
 6. `capacity[t]: Σᵢ x_op[i,t] <= corridor_cap * Σᵢ x_inv[i]` — the ONE
    genuinely new pooled row NASH-01 exists for: every distributor's
    delivered flow competes for one shared, aggregate corridor capacity.
 7. `Min Σᵢ c_inv[i]*x_inv[i] + Σᵢ Σₜ c_op[i][t]*x_op[i,t]`.

Because every OTHER distributor `j`'s `z[j,:]` is a fixed `Parameter` and
`x_op[j,:]` is forced equal to it via `coupling[j,:]`, distributor `j`'s
operating-cost term `Σₜ c_op[j][t]*x_op[j,t]` is a CONSTANT during any other
distributor's best-response and does not distort the active distributor's
own optimization; `x_inv[j]` similarly must be BOUND-PINNED (see
[`write_back!`](@ref) below) for the same reason — otherwise a distributor
could use another distributor's uncosted-to-it investment headroom to relax
the pooled `capacity` row for free, silently subsidizing itself from a
neighbor's frozen decision. This is the correctness argument for the
bound-pinning mechanism `activate_distributor!`/`write_back!` implement.

Immediately after building, EVERY distributor's `x_inv[i]` is pinned at
exactly `0.0` (`set_upper_bound(x_inv[i], 0.0)`; the lower bound is already
`0.0` from the `@variable` declaration) — the build-time "nobody has taken a
turn yet" default state. `nash.jl` (plan 13-02) unpins the sweep's first
distributor via [`activate_distributor!`](@ref) before its first
best-response.

Returns a [`SharedTransmission`](@ref).
"""
function build_shared_transmission(;
    N::Int,
    T::Int,
    corridor_cap::Real,
    x_inv_max::AbstractVector{<:Real},
    c_inv::AbstractVector{<:Real},
    c_op::AbstractVector{<:AbstractVector{<:Real}},
)
    # Boundary guards FIRST — fail here, not deep in objective assembly.
    N >= 2 || throw(
        ArgumentError("build_shared_transmission needs N >= 2 (nothing to share), got N=$N"),
    )
    T >= 1 || throw(ArgumentError("build_shared_transmission needs T >= 1, got T=$T"))
    corridor_cap > 0 || throw(
        ArgumentError("build_shared_transmission needs corridor_cap > 0, got $corridor_cap"),
    )
    length(x_inv_max) == N || throw(
        ArgumentError(
            "x_inv_max has length $(length(x_inv_max)), expected N=$N",
        ),
    )
    for i in 1:N
        x_inv_max[i] > 0 || throw(
            ArgumentError("x_inv_max[$i] must be > 0, got $(x_inv_max[i])"),
        )
    end
    length(c_inv) == N ||
        throw(ArgumentError("c_inv has length $(length(c_inv)), expected N=$N"))
    length(c_op) == N ||
        throw(ArgumentError("c_op has length $(length(c_op)), expected N=$N"))
    for i in 1:N
        length(c_op[i]) == T || throw(
            ArgumentError(
                "c_op[$i] has length $(length(c_op[i])), expected T=$T",
            ),
        )
    end

    model = Model(select_optimizer(LP()))   # INFRA-02: never Model(HiGHS.Optimizer) directly

    @variable(model, 0 <= x_inv[i = 1:N] <= x_inv_max[i])
    @variable(model, x_op[i = 1:N, t = 1:T] >= 0)
    @variable(model, z[i = 1:N, t = 1:T] in Parameter(0.0))   # SAME Parameter idiom as follower.jl

    @constraint(model, coupling[i = 1:N, t = 1:T], x_op[i, t] == z[i, t])
    # The ONE genuinely new pooled row NASH-01 exists for:
    @constraint(
        model,
        capacity[t = 1:T],
        sum(x_op[i, t] for i in 1:N) <= corridor_cap * sum(x_inv[i] for i in 1:N)
    )

    @objective(
        model,
        Min,
        sum(c_inv[i] * x_inv[i] for i in 1:N) +
        sum(c_op[i][t] * x_op[i, t] for i in 1:N, t in 1:T)
    )

    # Build-time default: nobody has taken a turn yet — every distributor's
    # own investment is pinned at 0.0 until activate_distributor! unpins it.
    for i in 1:N
        set_upper_bound(x_inv[i], 0.0)
    end

    return SharedTransmission(
        model,
        [x_inv[i] for i in 1:N],
        [x_op[i, t] for i in 1:N, t in 1:T],
        z,
        coupling,
        N,
        T,
        Float64(corridor_cap),
        Float64.(x_inv_max),
        Float64.(c_inv),
        [Float64.(c_op[i]) for i in 1:N],
    )
end

"""
    activate_distributor!(shared::SharedTransmission, i::Int) -> SharedTransmission

Called ONCE by `nash.jl`, immediately BEFORE distributor `i`'s atomic
best-response starts: restores distributor `i`'s own investment freedom
(`set_lower_bound(x_inv[i], 0.0); set_upper_bound(x_inv[i], x_inv_max[i])`)
after a prior [`write_back!`](@ref) (or the build-time default) may have
pinned it. Never touches any OTHER distributor's row.

Throws `ArgumentError` when `i` is out of `1:shared.N`.
"""
function activate_distributor!(shared::SharedTransmission, i::Int)
    1 <= i <= shared.N ||
        throw(ArgumentError("activate_distributor!: i=$i out of range 1:$(shared.N)"))
    set_lower_bound(shared.x_inv[i], 0.0)
    set_upper_bound(shared.x_inv[i], shared.x_inv_max[i])
    return shared
end

"""
    update_coupling!(shared::SharedTransmission, i::Int,
                      z_i_trial::AbstractVector{<:Real}) -> SharedTransmission

Called from INSIDE distributor `i`'s Benders loop, once per inner iteration
(via [`solve_follower!`](@ref)`(::DistributorView, ...)`), while `x_inv[i]`
stays free throughout (already unpinned by [`activate_distributor!`](@ref)).
Sets ONLY `shared.z[i,:]` via `set_parameter_value.` — NEVER a rebuild,
NEVER touching `x_inv[i]`'s bounds or any other distributor's row `j != i`.

Throws `ArgumentError` when `i` is out of range or `length(z_i_trial) !=
shared.T`.
"""
function update_coupling!(shared::SharedTransmission, i::Int, z_i_trial::AbstractVector{<:Real})
    1 <= i <= shared.N ||
        throw(ArgumentError("update_coupling!: i=$i out of range 1:$(shared.N)"))
    length(z_i_trial) == shared.T || throw(
        ArgumentError(
            "update_coupling!: z_i_trial has length $(length(z_i_trial)), expected T=$(shared.T)",
        ),
    )
    set_parameter_value.(shared.z[i, :], z_i_trial)
    return shared
end

"""
    write_back!(shared::SharedTransmission, i::Int,
                z_i_converged::AbstractVector{<:Real},
                x_inv_i_converged::Real) -> SharedTransmission

Called ONCE by `nash.jl`, AFTER distributor `i`'s atomic best-response
converges: freezes BOTH distributor `i`'s converged flow
(`set_parameter_value.(shared.z[i,:], z_i_converged)`) AND its converged
investment (`set_lower_bound`/`set_upper_bound(shared.x_inv[i],
x_inv_i_converged)`) at a single point, so the NEXT distributor in the sweep
(or `i` itself, next sweep) reads the true committed state and cannot
silently move it — this is the correctness argument this file's header
(the objective-comment on `build_shared_transmission`) requires: without
this bound-pin, a later-activated distributor could use distributor `i`'s
uncosted-to-it, still-free `x_inv[i]` headroom to relax the pooled
`capacity` row for free.

Throws `ArgumentError` when `i` is out of range or `length(z_i_converged) !=
shared.T`.
"""
function write_back!(
    shared::SharedTransmission,
    i::Int,
    z_i_converged::AbstractVector{<:Real},
    x_inv_i_converged::Real,
)
    1 <= i <= shared.N ||
        throw(ArgumentError("write_back!: i=$i out of range 1:$(shared.N)"))
    length(z_i_converged) == shared.T || throw(
        ArgumentError(
            "write_back!: z_i_converged has length $(length(z_i_converged)), expected T=$(shared.T)",
        ),
    )
    set_parameter_value.(shared.z[i, :], z_i_converged)
    set_lower_bound(shared.x_inv[i], x_inv_i_converged)
    set_upper_bound(shared.x_inv[i], x_inv_i_converged)
    return shared
end

"""
    DistributorView

Thin per-distributor handle passed as `solve_stackelberg!`'s new `follower`
argument (plan 13-02): pairs the one shared model with the specific
distributor `i` whose own row [`solve_follower!`](@ref)`(::DistributorView,
...)` should drive and read.

# Fields

  - `shared::SharedTransmission` — the one shared, build-once model.
  - `i::Int` — this view's own distributor index.
"""
struct DistributorView
    shared::SharedTransmission
    i::Int
end

"""
    solve_follower!(view::DistributorView, z_trial::AbstractVector{<:Real}) -> NamedTuple

Re-solve the shared, build-ONCE model at distributor `view.i`'s Benders
trial `z_trial` (`update_coupling!` only, NEVER a rebuild) via `optimize!`
called DIRECTLY — NOT the escalating retry wrapper — mirroring
`follower.jl`'s `solve_follower!` three-way branch EXACTLY, scoped to
distributor `view.i`'s own row.

Two mutually exclusive, exhaustively-checked branches:

  - FEASIBLE (`is_solved_and_feasible(shared.model; dual = true)`): returns
    `(; feasible = true, cost, π_s)` where `cost` is distributor `view.i`'s
    OWN cost slice, `c_inv[i]*x_inv[i] + Σₜ c_op[i][t]*x_op[i,t]` —
    deliberately NOT `objective_value(shared.model)` (which would include
    every OTHER, currently-fixed distributor's constant cost contribution
    and pollute the hand-checkable per-distributor cost/incumbent tracking
    `solve_stackelberg!`'s CR-01 discipline depends on) — and `π_s =
    dual.(shared.coupling[i,:])` (length-T, restricted to distributor `i`'s
    own rows).
  - INFEASIBLE (`dual_status(shared.model) == MOI.INFEASIBILITY_CERTIFICATE`,
    a GENUINE HiGHS Farkas/dual ray): returns `(; feasible = false, v, u)`
    where `v = dual_objective_value(shared.model)` and `u =
    dual.(shared.coupling[i,:])` (restricted to distributor `i`'s own rows
    only) — both ENFORCED `isfinite` AND `v > 0` in production (WR-03/IN-06
    parity with `follower.jl`): a non-finite or non-positive certificate
    raises loudly here instead of poisoning a downstream Benders master's
    persistent cut set with a vacuous cut.

Any OTHER outcome raises loudly, naming `termination_status`/
`primal_status`/`dual_status`/`raw_status` (T-11-01 parity).

Throws `ArgumentError` when `length(z_trial) != view.shared.T`.
"""
function solve_follower!(view::DistributorView, z_trial::AbstractVector{<:Real})
    shared = view.shared
    i = view.i
    length(z_trial) == shared.T || throw(
        ArgumentError(
            "solve_follower!: z_trial has length $(length(z_trial)), expected T=$(shared.T)",
        ),
    )

    update_coupling!(shared, i, z_trial)

    # Deliberate departure from the escalating retry wrapper / strict solved
    # gate (same amendment as follower.jl): the infeasible branch below must
    # be OBSERVED on the UN-RETRIED solve, never retried away, or the Farkas
    # certificate is unreachable.
    optimize!(shared.model)

    if is_solved_and_feasible(shared.model; dual = true)
        cost =
            shared.c_inv[i] * value(shared.x_inv[i]) +
            sum(shared.c_op[i][t] * value(shared.x_op[i, t]) for t in 1:shared.T)
        π_s = dual.(shared.coupling[i, :])
        return (; feasible = true, cost = cost, π_s = π_s)
    elseif dual_status(shared.model) == MOI.INFEASIBILITY_CERTIFICATE
        # GENUINE HiGHS Farkas/dual ray — never a penalized-slack "always
        # feasible" shortcut (parity with follower.jl's own contract).
        v = dual_objective_value(shared.model)
        u = dual.(shared.coupling[i, :])
        # WR-03/IN-06 parity: ENFORCE the "both isfinite, v > 0" certificate
        # guarantee here, in production.
        isfinite(v) && v > 0 && all(isfinite, u) || error(
            "solve_follower!(::DistributorView): HiGHS returned a non-finite or " *
            "non-positive Farkas certificate (v=$v, u=$u) for distributor i=$i — " *
            "refusing to emit a feasibility cut that would fail to exclude z_k",
        )
        return (; feasible = false, v = v, u = u)
    else
        error(
            """
            solve_follower!(::DistributorView): neither a trusted solve nor a genuine infeasibility certificate for distributor i=$i — refusing to trust results:
              termination_status : $(termination_status(shared.model))
              primal_status      : $(primal_status(shared.model))
              dual_status        : $(dual_status(shared.model))
              raw_status         : $(raw_status(shared.model))
            """,
        )
    end
end

export SharedTransmission,
    build_shared_transmission,
    activate_distributor!,
    update_coupling!,
    write_back!,
    DistributorView,
    solve_follower!
