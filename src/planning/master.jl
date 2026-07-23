# src/planning/master.jl
#
# SEAM: build-once Benders master with persistent optimality/feasibility cut rows
# (PLAN-05).
# OWNER: plan 11-01.
#
# PERSISTENT ROWS, NEVER REBUILT (CONTEXT.md locked decision): `build_master`
# constructs the leader's own LP (continuous investment `y_inv` + coupling flow
# `z[t]` + TWO epigraph variables `α_op`/`α_x`, one per Benders-cutting subproblem
# — the oracle's welfare-as-cost contribution and the follower's transmission
# cost, respectively, per 11-RESEARCH.md's resolved multi-cut structure)
# EXACTLY ONCE. `add_optimality_cut!`/`add_feasibility_cut!` append NEW
# `@constraint` rows to the EXISTING model handle — mirroring `DsoOpt`'s own
# mutate-without-rebuild idiom (`set_rho!`), though here rows are ADDED rather
# than coefficients mutated. `solve_master!` routes through `solve_with_retry!`
# (plan 10-01) — NEVER the SOLE INFRA-03 choke point directly — so every
# cut-producing solve on the master is gated by that choke point's own strict
# solved-and-feasible contract (never `allow_almost=true`), D-08, mirroring the
# oracle's own discipline.
#
# THE ONE GENUINELY NEW PIECE (11-RESEARCH.md Pitfall M1, no in-repo analog): the
# epigraph variables carry a DOCUMENTED, DERIVED finite lower bound
# (`α_op >= α_op_lb`, `α_x >= α_x_lb`) declared AT BUILD TIME, before any cut
# exists. Without this, the master's very first solve (zero cuts) has a free `α`
# in a `Min` objective and is `MOI.DUAL_INFEASIBLE` — not a modeling bug, but a
# well-known first-iteration Benders footgun this file avoids by construction.

using JuMP

"""
    BendersMaster{Y,Z,AOP,AX}

The built-ONCE Benders master (PLAN-05): the leader's own LP — continuous
investment `y_inv`, coupling flow `z[t]`, and TWO epigraph variables `α_op`
(the oracle's welfare-as-cost cut) and `α_x` (the follower's transmission-cost
cut) — with cuts appended as persistent `@constraint` rows, never rebuilt.

# Fields

  - `model::Model` — the master LP, built ONCE via `Model(select_optimizer(LP()))`
    (INFRA-02); mutated ONLY by appending new `@constraint` rows (cuts), never
    rebuilt.
  - `y_inv::Y` — the leader's flexibility-investment variable
    (`0 <= y_inv <= y_max`).
  - `z::Z` — the length-T coupling flow (`0 <= z[t] <= y_inv`, per
    11-RESEARCH.md Pitfall O1 — the box is `[0, y_inv]`, not `[-y_inv, y_inv]`,
    since `z` represents a physically nonnegative delivered import flow on this
    fixture's corridor).
  - `α_op::AOP` — the oracle's own epigraph variable (`α_op >= α_op_lb`).
  - `α_x::AX` — the follower's own epigraph variable (`α_x >= α_x_lb`).
  - `T::Int` — the horizon.
  - `c_y::Float64` — the leader's flexibility-investment unit cost.
  - `cuts::Vector{Any}` — a bookkeeping log of every cut appended (NamedTuples
    tagged `kind = :optimality`/`:feasibility`), for cut-validity testing in
    plan 11-02; not consumed by `solve_master!` itself.
"""
struct BendersMaster{Y, Z, AOP, AX}
    model::Model
    y_inv::Y
    z::Z
    α_op::AOP
    α_x::AX
    T::Int
    c_y::Float64
    cuts::Vector{Any}
end

"""
    build_master(; T::Int, c_y::Real, y_max::Real, α_op_lb::Real,
                 α_x_lb::Real) -> BendersMaster

Build the Benders master LP EXACTLY ONCE:

 1. Boundary guards — `T >= 1`, `y_max > 0`, `c_y >= 0` — each throws
    `ArgumentError` naming the offending value, BEFORE any `@variable`/
    `@objective` assembly.
 2. `model = Model(select_optimizer(LP()))` — INFRA-02, the sole solver-naming
    seam.
 3. `0 <= y_inv <= y_max` (continuous investment) and unconstrained `z[1:T]`
    (boxed below) — no binary/integer variable anywhere.
 4. `α_op >= α_op_lb` and `α_x >= α_x_lb` — the DOCUMENTED, DERIVED finite
    epigraph lower bounds (11-RESEARCH.md Pitfall M1) declared HERE, at build
    time, never added "later".
 5. `box_lo[t]: z[t] >= 0`, `box_hi[t]: z[t] <= y_inv` — `z` is a physically
    nonnegative delivered import flow bounded by the leader's own investment
    (11-RESEARCH.md Pitfall O1).
 6. `Min c_y*y_inv + α_op + α_x` — the leader's own objective: investment cost
    plus both epigraph cost-to-go terms.

Returns a [`BendersMaster`](@ref) with an empty `cuts` log.
"""
function build_master(; T::Int, c_y::Real, y_max::Real, α_op_lb::Real, α_x_lb::Real)
    # Boundary guards FIRST — fail here, not deep in objective assembly.
    T >= 1 || throw(ArgumentError("build_master needs T >= 1, got T=$T"))
    y_max > 0 || throw(ArgumentError("build_master needs y_max > 0, got $y_max"))
    c_y >= 0 || throw(ArgumentError("build_master needs c_y >= 0, got $c_y"))

    model = Model(select_optimizer(LP()))   # INFRA-02: never Model(HiGHS.Optimizer) directly

    @variable(model, 0 <= y_inv <= y_max)
    @variable(model, z[t = 1:T])
    # Pitfall M1: FINITE epigraph lower bounds declared AT BUILD TIME — the very
    # first (zero-cut) solve depends on this, not an edge case to defer.
    @variable(model, α_op >= α_op_lb)
    @variable(model, α_x >= α_x_lb)

    # Pitfall O1: z is a physically nonnegative delivered import flow on this
    # fixture's corridor, bounded above by the leader's own investment — the box
    # is [0, y_inv], not [-y_inv, y_inv].
    @constraint(model, box_lo[t = 1:T], z[t] >= 0)
    @constraint(model, box_hi[t = 1:T], z[t] <= y_inv)

    @objective(model, Min, c_y * y_inv + α_op + α_x)

    return BendersMaster(model, y_inv, z, α_op, α_x, T, Float64(c_y), Any[])
end

"""
    add_optimality_cut!(master::BendersMaster, epigraph::Symbol, cost_k::Real,
                        grad_k::AbstractVector{<:Real},
                        z_k::AbstractVector{<:Real}) -> BendersMaster

Append ONE new persistent optimality-cut row to `master.model` — NEVER a
rebuild — of the Phase-10 D-05 form:

```
α >= cost_k + Σ_t grad_k[t] * (z[t] - z_k[t])
```

where `α` is `master.α_op` if `epigraph === :op` or `master.α_x` if
`epigraph === :x`. This function is sign-agnostic: it takes whatever
`cost_k`/`grad_k` the caller supplies (plan 11-02's `benders.jl` is responsible
for the oracle's own `cost_k = -oracle_res.cost`, `grad_k = oracle_res.π` sign
convention documented in this plan's `<sign_convention>` block; the follower's
`cost_k = follower_res.cost`, `grad_k = follower_res.π_s` is used as-is).

Throws `ArgumentError` if `epigraph` is anything other than `:op`/`:x`, if
`length(grad_k) != master.T` or `length(z_k) != master.T`, or if `cost_k`,
any `grad_k[t]`, or any `z_k[t]` is non-finite (NaN/Inf) — a malformed cut
triple must fail loudly BEFORE corrupting the master's persistent constraint
set (T-11-03/WR-03: a NaN/Inf row appended to the build-once model is
unremovable and silently poisons every later solve).

Logs `(; kind = :optimality, epigraph, cost_k, grad_k, z_k)` to `master.cuts` and
returns `master`.
"""
function add_optimality_cut!(
    master::BendersMaster,
    epigraph::Symbol,
    cost_k::Real,
    grad_k::AbstractVector{<:Real},
    z_k::AbstractVector{<:Real},
)
    epigraph in (:op, :x) || throw(
        ArgumentError("add_optimality_cut!: epigraph must be :op or :x, got $epigraph"),
    )
    length(grad_k) == master.T ||
        throw(ArgumentError("grad_k has length $(length(grad_k)), expected T=$(master.T)"))
    length(z_k) == master.T ||
        throw(ArgumentError("z_k has length $(length(z_k)), expected T=$(master.T)"))
    # WR-03: finiteness guard — a NaN/Inf cut row would permanently poison the
    # build-once master (rows are never removed); fail loudly BEFORE @constraint.
    isfinite(cost_k) ||
        throw(ArgumentError("add_optimality_cut!: cost_k must be finite, got $cost_k"))
    all(isfinite, grad_k) || throw(
        ArgumentError("add_optimality_cut!: grad_k contains a non-finite entry: $grad_k"),
    )
    all(isfinite, z_k) ||
        throw(ArgumentError("add_optimality_cut!: z_k contains a non-finite entry: $z_k"))

    α = epigraph === :op ? master.α_op : master.α_x
    @constraint(
        master.model,
        α >= cost_k + sum(grad_k[t] * (master.z[t] - z_k[t]) for t in 1:(master.T))
    )
    push!(
        master.cuts,
        (;
            kind = :optimality,
            epigraph,
            cost_k,
            grad_k = Vector{Float64}(grad_k),
            z_k = Vector{Float64}(z_k),
        ),
    )
    return master
end

"""
    add_feasibility_cut!(master::BendersMaster, v_k::Real,
                         u_k::AbstractVector{<:Real},
                         z_k::AbstractVector{<:Real}) -> BendersMaster

Append ONE new persistent feasibility-cut row to `master.model` — NEVER a
rebuild — from the follower's own genuine HiGHS Farkas certificate
`(v_k, u_k)` (see [`solve_follower!`](@ref)):

```
v_k + Σ_t u_k[t] * (z[t] - z_k[t]) <= 0
```

Throws `ArgumentError` if `length(u_k) != master.T` or `length(z_k) != master.T`,
or if `v_k`, any `u_k[t]`, or any `z_k[t]` is non-finite (NaN/Inf)
(T-11-03/WR-03).

Logs `(; kind = :feasibility, v_k, u_k, z_k)` to `master.cuts` and returns
`master`.
"""
function add_feasibility_cut!(
    master::BendersMaster,
    v_k::Real,
    u_k::AbstractVector{<:Real},
    z_k::AbstractVector{<:Real},
)
    length(u_k) == master.T ||
        throw(ArgumentError("u_k has length $(length(u_k)), expected T=$(master.T)"))
    length(z_k) == master.T ||
        throw(ArgumentError("z_k has length $(length(z_k)), expected T=$(master.T)"))
    # WR-03: finiteness guard — mirror add_optimality_cut!'s own discipline; a
    # NaN/Inf feasibility row is just as unremovable and just as poisonous.
    isfinite(v_k) ||
        throw(ArgumentError("add_feasibility_cut!: v_k must be finite, got $v_k"))
    all(isfinite, u_k) ||
        throw(ArgumentError("add_feasibility_cut!: u_k contains a non-finite entry: $u_k"))
    all(isfinite, z_k) ||
        throw(ArgumentError("add_feasibility_cut!: z_k contains a non-finite entry: $z_k"))

    @constraint(
        master.model,
        v_k + sum(u_k[t] * (master.z[t] - z_k[t]) for t in 1:(master.T)) <= 0
    )
    push!(
        master.cuts,
        (;
            kind = :feasibility,
            v_k,
            u_k = Vector{Float64}(u_k),
            z_k = Vector{Float64}(z_k),
        ),
    )
    return master
end

"""
    solve_master!(master::BendersMaster; max_attempts::Int = 4,
                 attempts_out::Union{Nothing,Ref{Int}} = nothing) -> NamedTuple

Re-solve the built-ONCE [`BendersMaster`](@ref) via `solve_with_retry!` (D-08) —
NEVER the SOLE INFRA-03 choke point directly — so every cut-producing solve on
the master is gated by that choke point's own strict solved-and-feasible
contract (never `allow_almost=true`). The very first (zero-cut) solve returns
`MOI.OPTIMAL`, never `MOI.DUAL_INFEASIBLE`, because `build_master` already
declared finite epigraph lower bounds (Pitfall M1).

`attempts_out` is forwarded UNCHANGED to `solve_with_retry!` (plan 12-01, additive —
defaults to `nothing`, a pure no-op for every pre-existing call site).

Returns `(; y, z, LB)` where `y = value(master.y_inv)`, `z = value.(master.z)`,
and `LB = objective_value(master.model)` (the Benders lower bound at this
iteration).
"""
function solve_master!(
    master::BendersMaster;
    max_attempts::Int = 4,
    attempts_out::Union{Nothing, Ref{Int}} = nothing,
)
    # D-08: solve_with_retry! is the SOLE solve entry point on the master, mirroring
    # the oracle's own discipline — NEVER the INFRA-03 choke point called directly.
    solve_with_retry!(
        master.model;
        max_attempts = max_attempts,
        dual = true,
        attempts_out = attempts_out,
    )

    return (;
        y = value(master.y_inv),
        z = value.(master.z),
        LB = objective_value(master.model),
    )
end

export BendersMaster, build_master, add_optimality_cut!, add_feasibility_cut!, solve_master!
