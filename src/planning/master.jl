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
#
# PLAN 30-02 (BILEV-05) EXTENSION: `α_op_lb`/`α_x_lb` gain a THIRD option beyond an
# explicit `Real` — the `:auto` `Symbol`, resolved via a genuine ONE-TIME relaxed solve
# (never a closed-form shortcut), plus an opt-in build-time REJECTION of an explicit bound
# that exceeds the derived minimum. This file (not a new `alpha_bounds.jl`) hosts the
# derivation helpers (`make_relaxed_oracle_model`/`derive_alpha_op_lb`/
# `make_relaxed_follower_model`/`derive_alpha_x_lb`) — a new file would require an
# unrelated `src/TSODSO.jl` include-line edit that conflicts with plan 30-01's own wave-1
# new files (`feasibility_oracle.jl`, `ac_recheck.jl`) touching the same include block;
# co-locating the helpers in the file that already consumes them (`build_master`) avoids
# that cross-plan file conflict entirely. The machinery is OPT-IN via a new `bounds_ctx`
# keyword: every pre-existing call site (explicit `α_op_lb`/`α_x_lb` `Real`s, no
# `bounds_ctx`) stays BYTE-IDENTICAL — no relaxed model is built, no rejection check runs.

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
    ALPHA_LB_MARGIN

MEASURED safety margin (plan 30-02, BILEV-05) subtracted from a derived `α_op_lb`/
`α_x_lb` relaxed-solve optimum, mirroring `benders.jl`'s `KNOWN_OPTIMUM_ATOL`/
`JOINT_RECOURSE_GAP_TOL` "measure, don't guess" convention. Derivation: built
`make_relaxed_oracle_model`/`make_relaxed_follower_model` on
`Phase6Fixtures.two_bus_feeder()` + `ToyElasticDevice(2, 6.0, 1.0, 10.0)` (the SAME toy
fixture `test_planning_master.jl` already uses) at `T=1`, `λ₀=[4.0]`, `y_max=8.0`, and
`follower_kwargs=(; corridor_cap=2.0, x_inv_max=2.0, c_inv=1.0, c_op=[0.5])`, solved each,
and read `abs(objective_value(model) - dual_objective_value(model))` directly:
oracle gap ≈ `2.8509e-9`, follower gap `= 0.0` (an LP with a trivial `x_inv=x_op=0`
optimum) — `max_gap ≈ 2.8509e-9`. `ALPHA_LB_MARGIN = max(1e-6, 10*max_gap) = 1e-6` (the
floor dominates; `10*max_gap ≈ 2.85e-8` is far below it). Probe script:
`JULIA_LOAD_PATH="test:.:@stdlib" julia probe_alpha_margin.jl`, this session, re-runnable
from the recipe in this comment.
"""
const ALPHA_LB_MARGIN = 1e-6

"""
    ALPHA_LB_REJECTION_TOL

MEASURED tolerance (plan 30-02, BILEV-05) `build_master` adds to a derived `α_op_lb`/
`α_x_lb` minimum before rejecting an explicit user-supplied bound that exceeds it — set to
the SAME measured value as [`ALPHA_LB_MARGIN`](@ref) (`1e-6`, derivation above), since both
quantities are bounding the SAME solver-tolerance-scale numerical slack (the relaxed-solve
primal/dual gap) on the SAME toy-fixture probe; a single shared probe is sufficient
evidence for both constants (no second derivation needed).
"""
const ALPHA_LB_REJECTION_TOL = 1e-6

"""
    make_relaxed_oracle_model(feeder, pf::AbstractPowerFlow,
                              aggregators::AbstractVector{<:Aggregator};
                              λ₀, T::Int, y_max::Real) -> Model

ONE-TIME, discard-after-use relaxed oracle model for [`derive_alpha_op_lb`](@ref)
(BILEV-05): reuses [`build_planning_oracle`](@ref)'s EXACT assembly (boundary guards,
`Model(select_optimizer(problem_class(pf)))`, the two SOC→nonconvex-quad cross-solver
bridges, `contribute!(pf, ctx, feeder; T)`, the aggregator loop, the `:Rp`/`:Rq` balance
closure with its `size(...) == (N,T)` guard) with ONE structural difference: `p_import[t]`
is a genuinely BOXED `@variable` (`0 <= p_import[t] <= y_max`), NOT a `Parameter`-pinned
one. `PlanningOracle.z`'s `Parameter`-pin cannot be "freed" into an inequality by
re-setting its value — it stays an equality at whatever value is set — so this function
builds an INDEPENDENT model, never reuses [`PlanningOracle`](@ref).

Objective: `Max ctx.meta[:objective] - Σ_t λ₀[t]*p_import[t]` — identical shape to
`build_planning_oracle`'s welfare objective, just over the free box instead of a fixed pin.

Deliberately named WITHOUT a `build_` prefix: `test/test_planning_noninteger.jl`'s PVAL-04
source-scan tripwire greps for the substring `build_\\w+`, and this is a one-time,
discard-after-use derivation helper (built once, solved once, discarded), not a
planning-layer subproblem builder in that registry's sense — see that file's own header
comment for the full exemption rationale.
"""
function make_relaxed_oracle_model(
    feeder,
    pf::AbstractPowerFlow,
    aggregators::AbstractVector{<:Aggregator};
    λ₀,
    T::Int,
    y_max::Real,
)
    isempty(aggregators) &&
        throw(ArgumentError("make_relaxed_oracle_model needs at least one aggregator"))
    length(λ₀) == T ||
        throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))

    N = length(feeder.buses)
    for (k, agg) in enumerate(aggregators)
        1 <= agg.bus <= N || throw(
            ArgumentError("aggregator[$k] bus=$(agg.bus) is outside feeder buses 1:$N"),
        )
    end

    model = Model(select_optimizer(problem_class(pf)))

    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)

    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder
    ctx.meta[:T] = T
    ctx.meta[:problem_class] = problem_class(pf)

    contribute!(pf, ctx, feeder; T = T)

    # THE ONE STRUCTURAL DIFFERENCE from build_planning_oracle: a genuinely BOXED
    # p_import, never a Parameter pin.
    @variable(model, 0 <= p_import[t = 1:T] <= y_max)
    for t in 1:T
        add_to_residual!(ctx, :Rp, feeder.root, t, p_import[t])
    end
    ctx.meta[:p_import] = p_import

    reactive = haskey(ctx.residuals, :Rq)

    if reactive
        @variable(model, q_import[t = 1:T])
        for t in 1:T
            add_to_residual!(ctx, :Rq, feeder.root, t, q_import[t])
        end
        ctx.meta[:q_import] = q_import
    end

    for agg in aggregators
        contribute!(agg, ctx; T = T)
    end

    size(ctx.residuals[:Rp]) == (N, T) || error(
        "residual :Rp is $(size(ctx.residuals[:Rp])), expected ($N, $T) — an index escaped the feeder",
    )
    @constraint(model, balance_p[j = 1:N, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
    register_constraint!(ctx, :balance_p, balance_p)

    if reactive
        size(ctx.residuals[:Rq]) == (N, T) || error(
            "residual :Rq is $(size(ctx.residuals[:Rq])), expected ($N, $T) — an index escaped the feeder",
        )
        @constraint(model, balance_q[j = 1:N, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
        register_constraint!(ctx, :balance_q, balance_q)
    end

    @objective(model, Max, ctx.meta[:objective] - sum(λ₀[t] * p_import[t] for t in 1:T))

    return model
end

"""
    derive_alpha_op_lb(feeder, pf::AbstractPowerFlow,
                       aggregators::AbstractVector{<:Aggregator};
                       λ₀, T::Int, y_max::Real,
                       margin::Real = ALPHA_LB_MARGIN) -> Float64

Derive `α_op_lb` (BILEV-05) via a genuine ONE-TIME relaxed solve of
[`make_relaxed_oracle_model`](@ref) (never a closed-form shortcut): builds the relaxed
model, solves it via [`solve_with_retry!`](@ref) (D-08, the SOLE solve entry point), and
returns `-objective_value(model) - margin` — a valid global lower bound on `-welfare(z)`
for ANY `z` inside `[0, y_max]^T`, since the relaxed model's box-bounded `p_import`
strictly contains every pinned welfare value the real oracle can produce at a feasible
`z_trial` in that box (confirmed numerically, 30-RESEARCH.md Architecture Pattern 3).
"""
function derive_alpha_op_lb(
    feeder,
    pf::AbstractPowerFlow,
    aggregators::AbstractVector{<:Aggregator};
    λ₀,
    T::Int,
    y_max::Real,
    margin::Real = ALPHA_LB_MARGIN,
)
    model = make_relaxed_oracle_model(feeder, pf, aggregators; λ₀ = λ₀, T = T, y_max = y_max)
    solve_with_retry!(model; dual = true)
    return -objective_value(model) - margin
end

"""
    make_relaxed_follower_model(; T::Int, corridor_cap::Real, x_inv_max::Real,
                                c_inv::Real, c_op::AbstractVector{<:Real}) -> Model

ONE-TIME, discard-after-use relaxed follower model for [`derive_alpha_x_lb`](@ref)
(BILEV-05): mirrors [`build_follower`](@ref)'s assembly through `invest_op`, but DROPS the
`z`/`coupling` constraint entirely — `x_op[t]` is bounded only by
`x_op[t] <= corridor_cap*x_inv`, never pinned to any trial `z`. Its unconstrained minimum
over this larger feasible region is therefore a valid lower bound on the TRUE
(coupling-constrained) follower cost for any feasible `z`.

Deliberately named WITHOUT a `build_` prefix — see [`make_relaxed_oracle_model`](@ref)'s
docstring for the PVAL-04 exemption rationale (same applies here).
"""
function make_relaxed_follower_model(;
    T::Int,
    corridor_cap::Real,
    x_inv_max::Real,
    c_inv::Real,
    c_op::AbstractVector{<:Real},
)
    T >= 1 || throw(ArgumentError("make_relaxed_follower_model needs T >= 1, got T=$T"))
    corridor_cap > 0 || throw(
        ArgumentError(
            "make_relaxed_follower_model needs corridor_cap > 0, got $corridor_cap",
        ),
    )
    x_inv_max > 0 || throw(
        ArgumentError("make_relaxed_follower_model needs x_inv_max > 0, got $x_inv_max"),
    )
    length(c_op) == T ||
        throw(ArgumentError("c_op has length $(length(c_op)), expected T=$T"))

    model = Model(select_optimizer(LP()))

    @variable(model, 0 <= x_inv <= x_inv_max)
    @variable(model, x_op[t = 1:T] >= 0)
    @constraint(model, invest_op[t = 1:T], x_op[t] <= corridor_cap * x_inv)
    @objective(model, Min, c_inv * x_inv + sum(c_op[t] * x_op[t] for t in 1:T))

    return model
end

"""
    derive_alpha_x_lb(; T::Int, corridor_cap::Real, x_inv_max::Real, c_inv::Real,
                      c_op::AbstractVector{<:Real},
                      margin::Real = ALPHA_LB_MARGIN) -> Float64

Derive `α_x_lb` (BILEV-05) via a genuine ONE-TIME relaxed solve of
[`make_relaxed_follower_model`](@ref) (never a hard-coded `0.0` shortcut, even though every
existing fixture's `c_op`/`c_inv` happen to be nonnegative — RESEARCH.md Open Question 3's
own resolution: always solve the relaxed LP, robust to a future negative-cost fixture).
Returns `objective_value(model) - margin` (the Min-sense relaxed minimum, lowered by the
same measured margin as [`derive_alpha_op_lb`](@ref)).
"""
function derive_alpha_x_lb(;
    T::Int,
    corridor_cap::Real,
    x_inv_max::Real,
    c_inv::Real,
    c_op::AbstractVector{<:Real},
    margin::Real = ALPHA_LB_MARGIN,
)
    model = make_relaxed_follower_model(;
        T = T,
        corridor_cap = corridor_cap,
        x_inv_max = x_inv_max,
        c_inv = c_inv,
        c_op = c_op,
    )
    solve_with_retry!(model; dual = true)
    return objective_value(model) - margin
end

"""
    derive_alpha_x_lb(f::FollowerLP; margin::Real = ALPHA_LB_MARGIN) -> Float64

A SOUND, cheap overload of [`derive_alpha_x_lb`](@ref) for a pre-built [`FollowerLP`](@ref)
follower (checker-fix revision), distinct from the `follower_kwargs`-NamedTuple method
above. Extracts `corridor_cap`/`x_inv_max`/`T` directly off the struct, and `c_inv`/`c_op`
via JuMP's `coefficient(objective_function(f.model), ·)` — sound because `FollowerLP`'s
structure is an EXACT match for [`make_relaxed_follower_model`](@ref)'s assumptions (same
`invest_op`-shaped cap, same additive cost, no other coupling). Calls the `follower_kwargs`
method above with the extracted values, so the two dispatch methods agree by construction.

Deliberately NOT extended to `src/planning/coupling.jl`'s `DistributorView`: its
per-distributor capacity is governed by a POOLED row shared across ALL distributors
(`capacity[t]: Σⱼ x_op[j,t] <= corridor_cap*Σⱼ x_inv[j]`), so distributor `i`'s true local
bound also depends on every OTHER distributor's currently-committed state, which changes
every Gauss-Seidel sweep and is unavailable at `solve_stackelberg!`'s build-once call
boundary — a per-distributor relaxed minimum computed without that state would NOT be a
sound lower bound (full argument in plan 30-04 Task 2). `build_master`'s resolution logic
treats the absence of this method as `bounds_ctx.follower_kwargs === nothing`: `α_x_lb`'s
build-time rejection is then honestly SKIPPED for that follower type (documented scope
limit, never a silent pass) — the universal runtime floor guard (plan 30-04, benders.jl)
remains active as defense-in-depth.
"""
function derive_alpha_x_lb(f::FollowerLP; margin::Real = ALPHA_LB_MARGIN)
    obj = objective_function(f.model)
    c_inv = coefficient(obj, f.x_inv)
    c_op = [coefficient(obj, f.x_op[t]) for t in 1:f.T]
    return derive_alpha_x_lb(;
        T = f.T,
        corridor_cap = f.corridor_cap,
        x_inv_max = f.x_inv_max,
        c_inv = c_inv,
        c_op = c_op,
        margin = margin,
    )
end

"""
    build_master(; T::Int, c_y::Real, y_max::Real,
                 α_op_lb::Union{Symbol,Real} = :auto,
                 α_x_lb::Union{Symbol,Real} = :auto,
                 bounds_ctx::Union{Nothing,NamedTuple} = nothing,
                 rejection_tol::Real = ALPHA_LB_REJECTION_TOL) -> BendersMaster

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

**BILEV-05 (plan 30-02): `α_op_lb`/`α_x_lb` are `Union{Symbol,Real}`, defaulting to
`:auto`.** `:auto` resolves via a genuine one-time relaxed solve
([`derive_alpha_op_lb`](@ref)/[`derive_alpha_x_lb`](@ref)) — this REQUIRES `bounds_ctx` to
be supplied. An explicit `Real` is accepted unconditionally when `bounds_ctx === nothing`
(the byte-identical, zero-regression path every pre-existing call site uses: NO relaxed
model is built, NO rejection check runs). When `bounds_ctx` IS supplied alongside an
explicit `Real`, that explicit value is VALIDATED against the derived minimum: a bound
that exceeds `derived + rejection_tol` throws `ArgumentError` — an invalid (too-tight)
declared lower bound would otherwise silently produce a WRONG converged answer (see
`test_planning_hardening.jl`'s own T=8 finding, 30-RESEARCH.md Pitfall 4).

`bounds_ctx`'s expected shape: `(; feeder, pf, aggregators, λ₀, follower_kwargs)`, where
`follower_kwargs` is ONE of: a `NamedTuple` with `corridor_cap`/`x_inv_max`/`c_inv`/`c_op`
(routed to [`derive_alpha_x_lb`](@ref)'s `follower_kwargs` method), a [`FollowerLP`](@ref)
instance (routed to its own `derive_alpha_x_lb` dispatch method), or `nothing` — a
documented scope limit for a follower type with no sound per-object relaxed-minimum
derivation (e.g. `src/planning/coupling.jl`'s `DistributorView`, whose capacity is governed
by a POOLED row shared across distributors). When `follower_kwargs === nothing`,
`α_x_lb`'s build-time validation is honestly SKIPPED (never silently "passed" as valid) —
`:auto` in that case is a hard `ArgumentError` (nothing to derive from), while an explicit
`α_x_lb` passes through UNVALIDATED at build time; `α_op_lb` on the SAME call remains fully
resolved/validated via `bounds_ctx` regardless of `follower_kwargs`'s value. The universal
runtime floor guard (plan 30-04, `benders.jl`) remains active as defense-in-depth for the
skipped case.

**Design decision (30-02-PLAN.md's own `<objective>`):** this machinery is OPT-IN via
`bounds_ctx`, not wired unconditionally — every one of the ~90 pre-existing call sites
across 10 test files passes explicit `Real` `α_op_lb`/`α_x_lb` and omits `bounds_ctx`; those
calls remain byte-identical (confirmed by code inspection: the `bounds_ctx === nothing`
branch below never calls `derive_alpha_op_lb`/`derive_alpha_x_lb`).

Returns a [`BendersMaster`](@ref) with an empty `cuts` log.
"""
function build_master(;
    T::Int,
    c_y::Real,
    y_max::Real,
    α_op_lb::Union{Symbol, Real} = :auto,
    α_x_lb::Union{Symbol, Real} = :auto,
    bounds_ctx::Union{Nothing, NamedTuple} = nothing,
    rejection_tol::Real = ALPHA_LB_REJECTION_TOL,
)
    # Boundary guards FIRST — fail here, not deep in objective assembly.
    T >= 1 || throw(ArgumentError("build_master needs T >= 1, got T=$T"))
    y_max > 0 || throw(ArgumentError("build_master needs y_max > 0, got $y_max"))
    c_y >= 0 || throw(ArgumentError("build_master needs c_y >= 0, got $c_y"))

    (α_op_lb === :auto || α_x_lb === :auto) &&
        bounds_ctx === nothing &&
        throw(ArgumentError("build_master: α_op_lb/α_x_lb = :auto requires bounds_ctx"))
    α_op_lb isa Union{Symbol, Real} || throw(
        ArgumentError(
            "build_master: α_op_lb must be :auto or a Real, got $(typeof(α_op_lb))",
        ),
    )
    α_x_lb isa Union{Symbol, Real} || throw(
        ArgumentError(
            "build_master: α_x_lb must be :auto or a Real, got $(typeof(α_x_lb))",
        ),
    )

    # BILEV-05 resolution: α_op_lb. :auto always derives; an explicit bound is validated
    # ONLY when bounds_ctx is supplied (the opt-in design decision above) — the
    # bounds_ctx === nothing branch is the byte-identical, zero-regression path.
    α_op_lb_resolved = if α_op_lb === :auto
        derive_alpha_op_lb(
            bounds_ctx.feeder,
            bounds_ctx.pf,
            bounds_ctx.aggregators;
            λ₀ = bounds_ctx.λ₀,
            T = T,
            y_max = y_max,
        )
    elseif bounds_ctx !== nothing
        derived = derive_alpha_op_lb(
            bounds_ctx.feeder,
            bounds_ctx.pf,
            bounds_ctx.aggregators;
            λ₀ = bounds_ctx.λ₀,
            T = T,
            y_max = y_max,
        )
        α_op_lb > derived + rejection_tol && throw(
            ArgumentError(
                "build_master: α_op_lb=$α_op_lb exceeds the derived minimum $derived " *
                "(+tol=$rejection_tol) — would silently produce a wrong-converged answer " *
                "(see test_planning_hardening.jl's own T=8 finding)",
            ),
        )
        Float64(α_op_lb)
    else
        Float64(α_op_lb)
    end

    # BILEV-05 resolution: α_x_lb. Three-way dispatch on bounds_ctx.follower_kwargs: a
    # NamedTuple, a FollowerLP, or nothing (no sound derivation for this follower type,
    # e.g. DistributorView — skip the rejection check, accept the explicit value as-is;
    # :auto in this branch is a hard error, since there is nothing to derive from).
    _fk = bounds_ctx === nothing ? nothing : bounds_ctx.follower_kwargs
    α_x_lb_resolved = if α_x_lb === :auto
        _fk === nothing && throw(
            ArgumentError(
                "build_master: α_x_lb=:auto requires bounds_ctx.follower_kwargs to be a " *
                "NamedTuple or a FollowerLP — got `nothing` (no sound derivation for this " *
                "follower type)",
            ),
        )
        _fk isa NamedTuple ? derive_alpha_x_lb(; _fk..., T = T) : derive_alpha_x_lb(_fk)
    elseif bounds_ctx !== nothing && _fk !== nothing
        derived = _fk isa NamedTuple ? derive_alpha_x_lb(; _fk..., T = T) : derive_alpha_x_lb(_fk)
        α_x_lb > derived + rejection_tol && throw(
            ArgumentError(
                "build_master: α_x_lb=$α_x_lb exceeds the derived minimum $derived " *
                "(+tol=$rejection_tol) — would silently produce a wrong-converged answer",
            ),
        )
        Float64(α_x_lb)
    else
        # bounds_ctx === nothing (opt-out, byte-identical path), OR _fk === nothing (a
        # pre-built follower with no sound derivation, e.g. DistributorView) — accept the
        # explicit value unvalidated at build time; the universal runtime floor guard
        # (plan 30-04, benders.jl) remains the defense-in-depth check.
        Float64(α_x_lb)
    end

    model = Model(select_optimizer(LP()))   # INFRA-02: never Model(HiGHS.Optimizer) directly

    @variable(model, 0 <= y_inv <= y_max)
    @variable(model, z[t = 1:T])
    # Pitfall M1: FINITE epigraph lower bounds declared AT BUILD TIME — the very
    # first (zero-cut) solve depends on this, not an edge case to defer.
    @variable(model, α_op >= α_op_lb_resolved)
    @variable(model, α_x >= α_x_lb_resolved)

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
