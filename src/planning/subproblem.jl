# src/planning/subproblem.jl
#
# SEAM: build-once planning-layer oracle subproblem (PLAN-01/PLAN-02, D-01/D-02/D-04
# through D-07/D-11).
# OWNER: plan 10-02.
#
# Turns the SEAM-01 `z`-pin stub (`src/models/oracle.jl`'s `_coupling_dual` — UNMODIFIED
# here, D-03) into a live, build-once JuMP subproblem: `build_planning_oracle` constructs
# the welfare-shaped model EXACTLY ONCE with `z[t]` as a genuine JuMP `Parameter` and
# `p_import[t] == z[t]` as a named `pin[t]` constraint (D-01), reusing
# `contribute!(pf, ctx, feeder; T)` / `contribute!(agg, ctx; T)` verbatim (the SAME
# builders `solve_welfare`/`build_dso_opt` already use). `solve_planning_oracle!`
# re-solves it via `solve_with_retry!` (plan 10-01, D-08) — the retry wrapper is the SOLE
# solve entry point, never called around directly — and returns the pin's dual `π` (the
# length-T Benders-cut gradient, D-05)
# plus its duration-weighted reconciliation `π_s` (D-07), a reporting-only scalar never
# fed back into the optimization (D-04). The raw-dual sign convention is pinned by a
# hand-derived toy-case monotonicity invariant (D-06), NOT assumed from the docstring
# formula — 10-RESEARCH.md Pitfall 1 empirically found the raw `dual(pin)` is NEGATED
# relative to the naive `∂(objective)/∂z` under this project's `Max`-sense welfare
# objective.
#
# `welfare_solve.jl`/`oracle.jl` are byte-for-byte UNMODIFIED by this file (D-03/D-11):
# this module mirrors their SHAPE (frontier/reactive-closure/objective) but lives in a
# NEW module, formulation-generic like `solve_welfare` (never hardcodes `SOCP()`, unlike
# `DsoOpt`).

using JuMP

"""
    PlanningOracle{Z,PC,PI,F}

The built-ONCE planning-layer oracle subproblem (PLAN-01/PLAN-02): the welfare-shaped
model (mirrors [`solve_welfare`](@ref)'s frontier/reactive-closure/objective SHAPE,
without modifying that file) with a genuine JuMP `Parameter`-typed coupling-flow
setpoint `z[t]` and a named pin constraint `p_import[t] == z[t]` (D-01).

# Fields

  - `model::Model` — the welfare-shaped model, built ONCE via
    `select_optimizer(problem_class(pf))` (formulation-generic — NEVER hardcodes
    `SOCP()`, unlike [`DsoOpt`](@ref)); re-solved via `set_parameter_value.(z, ...)` +
    `optimize!` only, never rebuilt (D-11).
  - `ctx::ModelContext` — the shared context; `ctx.constraints[:balance_p]` (and
    `:balance_q` when the formulation provides a reactive channel) carries the DADP
    duals, mirroring `solve_welfare`.
  - `z` — the length-T `Parameter`-typed coupling-flow setpoint (D-01); re-settable via
    `set_parameter_value.(o.z, z_trial)` with NO rebuild.
  - `pin` — the named `pin[t]: p_import[t] == z[t]` constraint (D-01); its dual (read
    by [`solve_planning_oracle!`](@ref)) is the length-T Benders-cut gradient (D-05).
  - `p_import` — the FREE-SIGN frontier active exchange `p_import[t]` at `feeder.root`
    (no lower bound — the safer default per 10-RESEARCH.md Open Question 1).
  - `agg_bus::Int` — the first aggregator's bus (`aggregators[1].bus`), the DADP
    reporting convention mirroring `solve_welfare`'s `priced = aggregators[1].bus`.
  - `T::Int` — the day-ahead horizon (thesis A1).
  - `feeder` — the network the oracle is built on.
  - `λ₀::Vector{Float64}` — the MEM / wholesale price profile pricing `p_import`.
"""
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

"""
    build_planning_oracle(feeder, pf::AbstractPowerFlow,
                          aggregators::AbstractVector{<:Aggregator};
                          λ₀, T::Int = 24) -> PlanningOracle

Build the planning-layer oracle subproblem (thesis-welfare-shaped, mirrors
[`solve_welfare`](@ref) WITHOUT modifying it) EXACTLY ONCE (D-11), with a genuine
`Parameter`-typed coupling-flow setpoint `z[t]` and a named pin constraint
`p_import[t] == z[t]` (D-01):

 1. Boundary guards (mirror `solve_welfare`/`build_dso_opt`): empty `aggregators`, a
    `λ₀` length mismatch, or an aggregator bus outside `1:length(feeder.buses)` each
    throw `ArgumentError` before any objective assembly.
 2. `model = Model(select_optimizer(problem_class(pf)))` — FORMULATION-GENERIC routing
    (QP for DC/LinDistFlow, SOCP for `ConvexBranchFlow`), never hardcoding `SOCP()`
    (unlike [`DsoOpt`](@ref), this oracle mirrors `solve_welfare`'s formulation-agnostic
    factory choice). Registers the same SOC→nonconvex-quad cross-solver bridges as
    `solve_welfare`/`DsoOpt` (dormant on the primary Clarabel path).
 3. `contribute!(pf, ctx, feeder; T)` — VERBATIM reuse of the validated power-flow
    builder.
 4. FREE-SIGN frontier `p_import[t]` at `feeder.root` (no lower bound — Open Question 1
    resolution), injected into `:Rp[root]`. `reactive = haskey(ctx.residuals, :Rq)` is
    captured IMMEDIATELY after step 3, before any aggregator writes (mirrors
    `solve_welfare`'s WR-03 ordering); if `reactive`, a FREE-SIGN `q_import[t]` is added
    at the root too.
 5. Each aggregator `contribute!`s its net injection + utility (discarding the return —
    Phase 10 needs no PRICE-03-style stash).
 6. Residuals are closed with the same defensive `size(...) == (N, T)` guard as
    `DsoOpt`/`solve_welfare` before each `@constraint`; `:balance_p` is always
    registered, `:balance_q` only when `reactive`.
 7. THE NEW SEAM: `z[t] in Parameter(0.0)` and the named pin `p_import[t] == z[t]`
    (D-01/D-11) — the live coupling constraint superseding the SEAM-01 `ArgumentError`
    stub in `_coupling_dual`.
 8. `@objective(model, Max, ctx.meta[:objective] - Σ_t λ₀[t]*p_import[t])` — identical
    shape to `solve_welfare`'s welfare objective (thesis eq. 3.38).

Returns a [`PlanningOracle`](@ref). `welfare_solve.jl`/`oracle.jl` are NOT modified by
this function (D-03/D-11) — it is a wholly NEW module reusing their builders verbatim.
"""
function build_planning_oracle(
    feeder,
    pf::AbstractPowerFlow,
    aggregators::AbstractVector{<:Aggregator};
    λ₀,
    T::Int = 24,
)
    # Boundary guards (mirror solve_welfare/build_dso_opt): fail here, not deep in
    # objective assembly.
    isempty(aggregators) &&
        throw(ArgumentError("build_planning_oracle needs at least one aggregator"))
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))

    N = length(feeder.buses)
    for (k, agg) in enumerate(aggregators)
        1 <= agg.bus <= N || throw(
            ArgumentError("aggregator[$k] bus=$(agg.bus) is outside feeder buses 1:$N"),
        )
    end

    # Formulation-generic factory routing (NEVER hardcode SOCP() — unlike DsoOpt; this
    # oracle mirrors solve_welfare's formulation-agnostic choice).
    model = Model(select_optimizer(problem_class(pf)))

    # Cross-solver enablement, dormant on the primary Clarabel path (mirrors
    # solve_welfare/build_dso_opt verbatim).
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)

    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder
    ctx.meta[:T] = T
    # CR-03: stash the formulation's problem class so solve_planning_oracle! can default
    # its battery-complementarity τ PROBLEM-CLASS-AWARE (looser 1e-3 on the interior-point
    # SOCP path, tighter 1e-6 on the QP path) — mirroring solve_welfare's τ default —
    # without carrying `pf` itself in the struct.
    ctx.meta[:problem_class] = problem_class(pf)

    # VERBATIM power-flow builder reuse.
    contribute!(pf, ctx, feeder; T = T)

    # FREE-SIGN frontier active exchange at the root (no lower bound — Open Question 1).
    @variable(model, p_import[t = 1:T])
    for t in 1:T
        add_to_residual!(ctx, :Rp, feeder.root, t, p_import[t])
    end
    ctx.meta[:p_import] = p_import

    # WR-03 ordering: capture `reactive` IMMEDIATELY after the formulation contributes,
    # BEFORE any aggregator writes (mirrors solve_welfare).
    reactive = haskey(ctx.residuals, :Rq)

    if reactive
        @variable(model, q_import[t = 1:T])   # free-sign reactive frontier import
        for t in 1:T
            add_to_residual!(ctx, :Rq, feeder.root, t, q_import[t])
        end
        ctx.meta[:q_import] = q_import
    end

    # Aggregators: net active/reactive injections + utility. Return discarded (Phase 10
    # needs no PRICE-03-style per-aggregator stash).
    for agg in aggregators
        contribute!(agg, ctx; T = T)
    end

    # Close :Rp always; :Rq only when the formulation provides a reactive channel.
    size(ctx.residuals[:Rp]) == (N, T) || error(
        "residual :Rp is $(size(ctx.residuals[:Rp])), expected ($N, $T) — an index escaped the feeder",
    )
    @constraint(model, balance_p[j = 1:N, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
    register_constraint!(ctx, :balance_p, balance_p)          # dual = λ_j (DADP)

    if reactive
        size(ctx.residuals[:Rq]) == (N, T) || error(
            "residual :Rq is $(size(ctx.residuals[:Rq])), expected ($N, $T) — an index escaped the feeder",
        )
        @constraint(model, balance_q[j = 1:N, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
        register_constraint!(ctx, :balance_q, balance_q)
    end

    # THE NEW SEAM (D-01/D-11): z as a genuine JuMP Parameter, and the named pin
    # p_import[t] == z[t]. Its dual (read by solve_planning_oracle!) is the Benders-cut
    # gradient (D-05).
    @variable(model, z[t = 1:T] in Parameter(0.0))
    @constraint(model, pin[t = 1:T], p_import[t] == z[t])

    # GLB-CVX welfare (thesis eq. 3.38), identical shape to solve_welfare's objective.
    @objective(model, Max, ctx.meta[:objective] - sum(λ₀[t] * p_import[t] for t in 1:T))

    return PlanningOracle(
        model,
        ctx,
        z,
        pin,
        p_import,
        aggregators[1].bus,
        T,
        feeder,
        Vector{Float64}(λ₀),
    )
end

"""
    solve_planning_oracle!(o::PlanningOracle, z_trial::AbstractVector{<:Real};
                          max_attempts::Int = 4, Δt::Real = 1.0,
                          rtol_exact::Real = 1e-4,
                          τ::Real = (SOCP path ? 1e-3 : 1e-6),
                          attempts_out::Union{Nothing,Ref{Int}} = nothing)
        -> (; cost, π, π_s, dadp, ctx)

Re-solve the built-ONCE [`PlanningOracle`](@ref) `o` at the coupling-flow trial
`z_trial` (D-01/D-11: `set_parameter_value.` only, NEVER a rebuild) via
[`solve_with_retry!`](@ref) (plan 10-01, D-08) — the SOLE solve entry point — then run
the SAME two mandatory post-solve trust gates as [`solve_welfare`](@ref), the model this
oracle mirrors, strictly BEFORE any dual is read (CR-03):

 1. the PF-04 EXACTNESS GATE [`assert_socp_exact!`](@ref)`(o.ctx; rtol = rtol_exact)` —
    DATA-DRIVEN on the squared-current `:l` stash in `o.ctx.meta[:pf_vars]` (only
    `ConvexBranchFlow` stashes `:l`; DC/LinDistFlow skip untouched). The pin
    `p_import[t] == z[t]` REMOVES the priced-export degree of freedom that
    `solve_welfare` identifies as the SOC-exactness ENABLER, so an off-optimal `z_trial`
    is exactly the regime where the cone can go slack — a physically-meaningless `π`
    (the Benders-cut gradient) from an inexact relaxation is REFUSED (thrown), never
    returned (threats T-04-01/T-04-03). `maxgap` is stashed under
    `o.ctx.meta[:socp_maxgap]`;
 2. the App. C MANDATORY battery complementarity check
    [`assert_battery_complementarity!`](@ref)`(o.ctx; τ, T = o.T)` — degenerate
    `p_ch·p_dch` co-activation is MORE likely at a pinned off-optimal `z` than at the
    free welfare optimum (threat T-03-13). `τ` defaults PROBLEM-CLASS-AWARE from the
    `problem_class(pf)` stashed at build time (`1e-3` on the SOCP path, `1e-6` on the
    QP path), mirroring `solve_welfare`'s default; it is a DISTINCT quantity from
    `rtol_exact` — never conflated.

Returns a `NamedTuple`:

  - `cost` — the welfare optimum at this trial (`objective_value(o.model)`);
  - `π`    — the length-T dual of the pin `p_import[t] == z[t]` (`dual.(o.pin)`), the
    EXACT Benders-cut gradient (D-05); its raw-dual sign convention is pinned by a
    hand-derived toy-case monotonicity invariant (D-06; 10-RESEARCH.md Pitfall 1), not
    an assumed docstring formula: `π` is monotonically NON-DECREASING in `z_trial`,
    crossing zero at the network's own unconstrained free-import optimum;
  - `π_s`  — the DURATION-WEIGHTED reconciliation `Σ_t Δt·π[t]` (D-07, default
    `Δt = 1.0`, matching the framework's hourly rate today and correct-by-construction
    for a future non-uniform `Δt`). REPORTING-ONLY (D-04): never fed back into the
    optimization, computed purely for interpretation;
  - `dadp` — the distribution price at the first aggregator's bus
    (`dual.(o.ctx.constraints[:balance_p][o.agg_bus, :])`), mirroring
    `solve_welfare`'s `priced = aggregators[1].bus` convention;
  - `ctx`  — the solved [`ModelContext`](@ref), so a caller can read any other dual.

Throws `ArgumentError` when `length(z_trial) != o.T` (T-10-06: a shape mismatch must
fail loudly before `set_parameter_value.` — never silently truncate/pad the trial).

`attempts_out` is forwarded UNCHANGED to `solve_with_retry!` (plan 12-01, additive —
defaults to `nothing`, a pure no-op for every pre-existing call site).
"""
function solve_planning_oracle!(
    o::PlanningOracle,
    z_trial::AbstractVector{<:Real};
    max_attempts::Int = 4,
    Δt::Real = 1.0,
    rtol_exact::Real = 1e-4,
    τ::Real = (get(o.ctx.meta, :problem_class, nothing) isa SOCP ? 1e-3 : 1e-6),
    attempts_out::Union{Nothing, Ref{Int}} = nothing,
)
    length(z_trial) == o.T ||
        throw(ArgumentError("z_trial has length $(length(z_trial)), expected T=$(o.T)"))

    set_parameter_value.(o.z, z_trial)   # D-01/D-11: mutate the Parameter, no rebuild

    # D-08: solve_with_retry! is the SOLE solve entry point (its internal STRICT gate,
    # dual = true, ensures π is read only after a trusted solve — T-10-05).
    solve_with_retry!(
        o.model;
        max_attempts = max_attempts,
        dual = true,
        attempts_out = attempts_out,
    )

    # CR-03 / PF-04 EXACTNESS GATE (mirrors solve_welfare, threats T-04-01/T-04-03): MUST
    # run AFTER the trusted solve and BEFORE any dual is read, so a physically-meaningless
    # π from a STRICT (inexact) SOC relaxation is REFUSED (thrown) rather than returned as
    # a Benders-cut gradient into the entire Phase-11 planning loop. DATA-DRIVEN on the
    # `:l` stash: only ConvexBranchFlow stashes `:l`, so DC/LinDistFlow skip untouched.
    # The pin removes the priced-export SOC-exactness enabler, making this gate MORE
    # load-bearing at an off-optimal z_trial than in the free welfare solve, not less.
    if haskey(o.ctx.meta, :pf_vars) && haskey(o.ctx.meta[:pf_vars], :l)
        o.ctx.meta[:socp_maxgap] = assert_socp_exact!(o.ctx; rtol = rtol_exact)
    end

    # CR-03 / App. C MANDATORY battery complementarity at the PINNED point (mirrors
    # solve_welfare, threat T-03-13): degenerate p_ch·p_dch co-activation is MORE likely
    # at a pinned off-optimal z than at the free optimum. Data-driven no-op when no
    # batteries were registered under ctx.meta[:agg_device_vars].
    assert_battery_complementarity!(o.ctx; τ = τ, T = o.T)

    π = dual.(o.pin)                                    # length-T pin dual (D-01/D-05)
    π_s = sum(Δt * π[t] for t in 1:o.T)                 # D-07 duration-weighted, reporting-only (D-04)
    dadp = dual.(o.ctx.constraints[:balance_p][o.agg_bus, :])
    cost = objective_value(o.model)

    return (; cost, π, π_s, dadp, ctx = o.ctx)
end

export PlanningOracle, build_planning_oracle, solve_planning_oracle!
