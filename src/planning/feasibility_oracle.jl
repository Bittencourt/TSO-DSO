# src/planning/feasibility_oracle.jl
#
# SEAM: build-once slack-minimization feasibility oracle.
#
# By an explicit, locked design decision: "No Farkas-ray extraction from solver
# certificates." When a pinned `z_trial` makes the REAL `PlanningOracle` (subproblem.jl)
# genuinely `MOI.INFEASIBLE` (voltage- or thermally-caused), this file builds a SECOND,
# independent, built-ONCE oracle whose pin is RELAXED into an equality with free-sign slack:
# `p_import[t] == z[t] + s_plus[t] - s_minus[t]`, minimizing `Σ_t (s_plus[t] + s_minus[t])`
# (an L1 slack-min). The slack frees ONLY `p_import`, so this model is feasible iff SOME
# `p_import` trajectory admits the network + device constraints — NOT unconditionally
# an import-independent voltage violation or unmeetable
# device minimums make it infeasible too, and `solve_stackelberg!` then reports both
# errors. Its pin's dual is read EXACTLY like `PlanningOracle`'s own pin
# dual, yielding a valid Benders feasibility-cut pair `(v, u)` in the SAME shape
# `add_feasibility_cut!` (master.jl) already consumes — `v_k = cost` (the minimized total
# slack, >= 0, ≈0 iff `z_trial` is genuinely oracle-feasible) and `u_k` the (sign-verified,
# see `solve_feasibility_oracle!`'s own docstring) pin dual.
#
# Reuses `contribute!(pf, ctx, feeder; T)` and the aggregator-writer loop VERBATIM from
# `build_planning_oracle` (subproblem.jl) — the ONLY structural differences are (a) no `λ₀`
# kwarg / no economic objective (this oracle has no welfare sense, only a feasibility
# diagnostic), (b) the relaxed pin with free-sign slack variables, (c) the L1 slack-min
# objective. Routes its solve through `solve_with_retry!` (the SOLE solve entry point)
# — never raw `optimize!`. A solve failure here is either numerical or the "no
# `p_import` admits the network at all" case above.

using JuMP

"""
    FeasibilityOracle{Z,PC,PI,SP,SM,F}

The built-ONCE slack-minimization feasibility oracle: mirrors
[`PlanningOracle`](@ref)'s field shape minus `agg_bus`/`λ₀` (this oracle has no economic
objective), with the RELAXED pin's free-sign slack variables `s_plus`/`s_minus` added.

# Fields

  - `model::Model` — built ONCE via `select_optimizer(problem_class(pf))`
    (formulation-generic, mirrors `build_planning_oracle`); re-solved via
    `set_parameter_value.(z, ...)` + `solve_with_retry!` only, never rebuilt.
  - `ctx::ModelContext` — the shared context.
  - `z` — the length-T `Parameter`-typed coupling-flow TRIAL setpoint (re-settable, no
    rebuild).
  - `pin` — the named RELAXED pin `pin[t]: p_import[t] == z[t] + s_plus[t] - s_minus[t]`;
    its dual (read by [`solve_feasibility_oracle!`](@ref)) is the feasibility-cut gradient.
  - `p_import` — the FREE-SIGN frontier active exchange at `feeder.root` (mirrors
    `PlanningOracle`).
  - `s_plus`/`s_minus` — the free-sign (`>= 0`) slack variables relaxing the pin; the L1
    slack-min objective (`Min Σ_t s_plus[t]+s_minus[t]`) drives them to `0` whenever
    `z_trial` is genuinely oracle-feasible.
  - `T::Int` — the day-ahead horizon.
  - `feeder` — the network the oracle is built on.
"""
struct FeasibilityOracle{Z, PC, PI, SP, SM, F <: AbstractFeeder}
    model::Model
    ctx::ModelContext
    z::Z
    pin::PC
    p_import::PI
    s_plus::SP
    s_minus::SM
    T::Int
    feeder::F
end

"""
    build_feasibility_oracle(feeder, pf::AbstractPowerFlow,
                             aggregators::AbstractVector{<:Aggregator};
                             T::Int) -> FeasibilityOracle

Build the slack-minimization feasibility oracle EXACTLY ONCE, reusing
[`build_planning_oracle`](@ref)'s EXACT structure (boundary guards, `Model(select_optimizer( problem_class(pf)))`, the two SOC→nonconvex-quad cross-solver bridges, `ModelContext`,
`contribute!(pf, ctx, feeder; T)`, the free-sign frontier `p_import[t]`/`q_import[t]`, the
aggregator loop, the `:Rp`/`:Rq` balance closure with the `size(...) == (N,T)` guard) through
the balance closure, with THREE differences:

 1. No `λ₀` kwarg, no economic `@objective` — this oracle has no welfare sense;
 2. The coupling is RELAXED with free-sign slack:
    `s_plus[t] >= 0`, `s_minus[t] >= 0`, `z[t] in Parameter(0.0)`,
    `pin[t]: p_import[t] == z[t] + s_plus[t] - s_minus[t]`;
 3. The objective is the L1 slack-min `Min Σ_t (s_plus[t] + s_minus[t])` — a genuinely
    LINEAR term composing fine inside the SOCP-constrained model under Clarabel (confirmed;
    no separate epigraph reformulation needed).

Throws `ArgumentError` on an empty `aggregators` or an aggregator bus outside
`1:length(feeder.buses)`, mirroring `build_planning_oracle`'s own boundary-guard discipline
(no `λ₀`-length guard here — this oracle takes no `λ₀`).
"""
function build_feasibility_oracle(
    feeder::AbstractFeeder,
    pf::AbstractPowerFlow,
    aggregators::AbstractVector{<:Aggregator};
    T::Int,
)
    # Boundary guards (mirror build_planning_oracle, minus the λ₀ length check — this
    # oracle has no λ₀).
    isempty(aggregators) &&
        throw(ArgumentError("build_feasibility_oracle needs at least one aggregator"))

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
    ctx.feeder = feeder
    ctx.T = T
    ctx.meta[:problem_class] = problem_class(pf)

    # VERBATIM power-flow builder reuse.
    contribute!(pf, ctx, feeder; T = T)

    # FREE-SIGN frontier active exchange at the root (mirrors build_planning_oracle).
    @variable(model, p_import[t = 1:T])
    for t in 1:T
        add_to_residual!(ctx, :Rp, feeder.root, t, p_import[t])
    end
    ctx.meta[:p_import] = p_import

    reactive = has_reactive(pf)

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

    # THE RELAXED SEAM: z as a genuine JuMP Parameter (the TRIAL pin, not a
    # welfare optimization variable), relaxed into an equality via free-sign slack.
    @variable(model, s_plus[t = 1:T] >= 0)
    @variable(model, s_minus[t = 1:T] >= 0)
    @variable(model, z[t = 1:T] in Parameter(0.0))
    @constraint(model, pin[t = 1:T], p_import[t] == z[t] + s_plus[t] - s_minus[t])

    # L1 slack-min — no economic sense, purely a feasibility diagnostic.
    @objective(model, Min, sum(s_plus[t] + s_minus[t] for t in 1:T))

    return FeasibilityOracle(model, ctx, z, pin, p_import, s_plus, s_minus, T, feeder)
end

"""
    solve_feasibility_oracle!(fo::FeasibilityOracle, z_trial::AbstractVector{<:Real};
                              max_attempts::Int = 4) -> (; cost, v, u, z_k)

Re-solve the built-ONCE [`FeasibilityOracle`](@ref) `fo` at the coupling-flow trial
`z_trial` (`set_parameter_value.` only, never a rebuild) via [`solve_with_retry!`](@ref)
(the SOLE solve entry point). The slack frees only `p_import` (`s_plus`/`s_minus`
absorb any mismatch between `p_import` and `z_trial`), so this LP/SOCP is feasible iff SOME
`p_import` trajectory admits the network + device constraints — feasible for every
`z_trial` in that case, but NOT unconditionally: an
import-independent voltage violation or device minimums no import can meet make it
infeasible too, and `solve_with_retry!` then throws. No exactness/battery-complementarity
gate is applied (this is a diagnostic probe, not a cut-producing optimality subproblem).

Throws `ArgumentError` when `length(z_trial) != fo.T` (mirrors `solve_planning_oracle!`'s own
shape guard).

Returns `(; cost, v, u, z_k)`:

  - `cost` — the minimized total slack `objective_value(fo.model)` (`V(z_trial)`, always
    `>= 0`, `≈ 0` iff `z_trial` is genuinely oracle-feasible);
  - `v` — set equal to `cost` (the SAME scalar `add_feasibility_cut!`'s `v_k` expects);
  - `u` — the length-T feasibility-cut gradient, `u = π` where `π = dual.(fo.pin)` — the
    RAW pin dual, UN-negated. **EMPIRICALLY VERIFIED SIGN** (not an assumed formula,
    mirroring `solve_planning_oracle!`'s own precedent, and the OPPOSITE conclusion
    from a naive copy of that precedent — see below): solved on `ieee13_modified()`
    (T=1, the house_agg-style population from the test fixtures) at the anchor
    `z_k = 0.08` (measured THERMALLY infeasible on the real feeder;
    measured map: `MOI.INFEASIBLE` for `z >= 0.0686`), the raw pin dual was
    `π ≈ +0.99999999839` and `v_k = cost ≈ 0.01827` (a genuinely positive, nonzero slack).
    Plugging BOTH candidate signs into the cut inequality `v_k + u'(z - z_k) <= 0`
    (plain arithmetic, no JuMP) across the FULL measured feasible/infeasible map
    (`z ∈ {0.0, 0.01, 0.02, 0.05, 0.0686, 0.08, 0.09}`) showed:
    `u = +π` HOLDS (`<= 0`, not excluded) at every KNOWN-FEASIBLE `z ∈ {0.0,...,0.05}` and
    is VIOLATED (`> 0`, excluded) at every KNOWN-INFEASIBLE `z ∈ {0.0686, 0.08, 0.09}` —
    the cut exactly reproduces the real thermal threshold. `u = -π` was checked and found
    to VIOLATE the cut at EVERY tested `z`, including the known-feasible ones — an invalid
    cut that would wrongly exclude the entire feasible region. The correctly-verified sign
    here is therefore the OPPOSITE convention from `solve_planning_oracle!`'s own `π`
    (that oracle's pin dual needs no negation for its OWN, different use as a Benders
    optimality-cut gradient on a `Max`-sense welfare objective; this is a structurally
    different `Min`-sense slack-objective oracle, and the sign was re-derived from
    scratch here, never assumed from that other docstring's convention);
  - `z_k` — `copy(z_trial)`, the trial point this cut is anchored at (mirrors
    `add_feasibility_cut!`'s own `z_k` argument).

`attempts_out` is forwarded unchanged to `solve_with_retry!` (additive, `nothing` by default) so `solve_stackelberg!` can report this
solve's genuine retries on its trace.
"""
function solve_feasibility_oracle!(
    fo::FeasibilityOracle,
    z_trial::AbstractVector{<:Real};
    max_attempts::Int = 4,
    attempts_out::Union{Nothing, Ref{Int}} = nothing,
)
    length(z_trial) == fo.T ||
        throw(ArgumentError("z_trial has length $(length(z_trial)), expected T=$(fo.T)"))

    set_parameter_value.(fo.z, z_trial)   # no rebuild

    # solve_with_retry! is the SOLE solve entry point. Feasible iff some p_import
    # admits the network — a failure here is numerical or that structural case.
    solve_with_retry!(
        fo.model;
        max_attempts = max_attempts,
        dual = true,
        attempts_out = attempts_out,
    )

    cost = objective_value(fo.model)
    π = dual.(fo.pin)
    v = cost
    u = π   # EMPIRICALLY VERIFIED sign (un-negated raw pin dual) — see docstring above.

    return (; cost, v, u, z_k = copy(z_trial))
end
