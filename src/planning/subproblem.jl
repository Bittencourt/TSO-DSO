# src/planning/subproblem.jl
#
# SEAM: build-once planning-layer oracle subproblem.
#
# A live, build-once JuMP subproblem: `build_planning_oracle` constructs
# the welfare-shaped model EXACTLY ONCE with `z[t]` as a genuine JuMP `Parameter` and
# `p_import[t] == z[t]` as a named `pin[t]` constraint, reusing
# `contribute!(pf, ctx, feeder; T)` / `contribute!(agg, ctx; T)` verbatim (the SAME
# builders `solve_welfare`/`build_dso_opt` already use). `solve_planning_oracle!`
# re-solves it via `solve_with_retry!` — the retry wrapper is the SOLE
# solve entry point, never called around directly — and returns the pin's dual `π` (the
# length-T Benders-cut gradient)
# plus its duration-weighted reconciliation `π_s`, a reporting-only scalar never
# fed back into the optimization. The raw-dual sign convention is pinned by a
# hand-derived toy-case monotonicity invariant, NOT assumed from the docstring
# formula — the raw `dual(pin)` was empirically found to be NEGATED
# relative to the naive `∂(objective)/∂z` under this project's `Max`-sense welfare
# objective.
#
# `welfare_solve.jl`/`oracle.jl` are bit-for-bit UNMODIFIED by this file:
# this module mirrors their SHAPE (frontier/reactive-closure/objective) but lives in a
# NEW module, formulation-generic like `solve_welfare` (never hardcodes `SOCP()`, unlike
# `DsoOpt`).

using JuMP

"""
    PlanningOracle{Z,PC,PI,F}

The built-ONCE planning-layer oracle subproblem: the welfare-shaped
model (mirrors [`solve_welfare`](@ref)'s frontier/reactive-closure/objective SHAPE,
without modifying that file) with a genuine JuMP `Parameter`-typed coupling-flow
setpoint `z[t]` and a named pin constraint `p_import[t] == z[t]`.

# Fields

  - `model::Model` — the welfare-shaped model, built ONCE via
    `select_optimizer(problem_class(pf))` (formulation-generic — NEVER hardcodes
    `SOCP()`, unlike [`DsoOpt`](@ref)); re-solved via `set_parameter_value.(z, ...)` +
    `optimize!` only, never rebuilt.
  - `ctx::ModelContext` — the shared context; `ctx.constraints[:balance_p]` (and
    `:balance_q` when the formulation provides a reactive channel) carries the DADP
    duals, mirroring `solve_welfare`.
  - `z` — the length-T `Parameter`-typed coupling-flow setpoint; re-settable via
    `set_parameter_value.(o.z, z_trial)` with NO rebuild.
  - `pin` — the named `pin[t]: p_import[t] == z[t]` constraint; its dual (read
    by [`solve_planning_oracle!`](@ref)) is the length-T Benders-cut gradient.
  - `p_import` — the FREE-SIGN frontier active exchange `p_import[t]` at `feeder.root`
    (no lower bound — the safer default).
  - `agg_bus::Int` — the first aggregator's bus (`aggregators[1].bus`), the DADP
    reporting convention mirroring `solve_welfare`'s `priced = aggregators[1].bus`.
  - `T::Int` — the day-ahead horizon (thesis A1).
  - `feeder` — the network the oracle is built on.
  - `λ₀::Vector{Float64}` — the MEM / wholesale price profile pricing `p_import`.
"""
struct PlanningOracle{Z, PC, PI, F <: AbstractFeeder}
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
                          λ₀, T::Int = 24,
                          optimizer = select_optimizer(problem_class(pf))) -> PlanningOracle

Build the planning-layer oracle subproblem (thesis-welfare-shaped, mirrors
[`solve_welfare`](@ref) WITHOUT modifying it) EXACTLY ONCE, with a genuine
`Parameter`-typed coupling-flow setpoint `z[t]` and a named pin constraint
`p_import[t] == z[t]`:

 1. Boundary guards (mirror `solve_welfare`/`build_dso_opt`): empty `aggregators`, a
    `λ₀` length mismatch, or an aggregator bus outside `1:length(feeder.buses)` each
    throw `ArgumentError` before any objective assembly.
 2. `model = Model(optimizer)`, `optimizer` DEFAULTING to `select_optimizer(problem_class(pf))`
    — FORMULATION-GENERIC routing (QP for DC/LinDistFlow, SOCP for `ConvexBranchFlow`), never
    hardcoding `SOCP()` (unlike [`DsoOpt`](@ref), this oracle mirrors `solve_welfare`'s
    formulation-agnostic factory choice). The `optimizer` kwarg
    lets a caller pass a differently-conditioned factory (e.g. a tighter Clarabel `tol_gap`)
    when the default sits at the solver's own achievable precision floor on a specific
    fixture — the DEFAULT expression is bit-for-bit identical to every call site that predates the kwarg. Registers
    the same SOC→nonconvex-quad cross-solver bridges as `solve_welfare`/`DsoOpt` (dormant on
    the primary Clarabel path).
 3. `contribute!(pf, ctx, feeder; T)` — VERBATIM reuse of the validated power-flow
    builder.
 4. FREE-SIGN frontier `p_import[t]` at `feeder.root` (no lower bound — the safer default),
    injected into `:Rp[root]`. `reactive = haskey(ctx.residuals, :Rq)` is
    captured IMMEDIATELY after step 3, before any aggregator writes (mirrors
    `solve_welfare`'s ordering); if `reactive`, a FREE-SIGN `q_import[t]` is added
    at the root too.
 5. Each aggregator `contribute!`s its net injection + utility (discarding the return —
    no stash is needed).
 6. Residuals are closed with the same defensive `size(...) == (N, T)` guard as
    `DsoOpt`/`solve_welfare` before each `@constraint`; `:balance_p` is always
    registered, `:balance_q` only when `reactive`.
 7. THE NEW SEAM: `z[t] in Parameter(0.0)` and the named pin `p_import[t] == z[t]`
    — the live coupling constraint of the pinned form.
 8. `@objective(model, Max, ctx.objective - Σ_t λ₀[t]*p_import[t])` — identical
    shape to `solve_welfare`'s welfare objective (thesis eq. 3.38).

Returns a [`PlanningOracle`](@ref). `welfare_solve.jl`/`oracle.jl` are NOT modified by
this function — it is a wholly NEW module reusing their builders verbatim.
"""
function build_planning_oracle(
    feeder::AbstractFeeder,
    pf::AbstractPowerFlow,
    aggregators::AbstractVector{<:Aggregator};
    λ₀,
    T::Int = 24,
    # A NEW optimizer seam, defaulting to the EXACT SAME factory
    # expression this call site always used, so the default path is bit-for-bit identical for every
    # pre-existing caller. Added so a test/call site can pass a tighter Clarabel `tol_gap`
    # (e.g. `select_optimizer(SOCP(); tol_gap_abs=…, tol_gap_rel=…)`) when the DEFAULT
    # `tol_gap=1e-8` sits at Clarabel's own achievable cone-residual precision floor for a
    # specific fixture (measured, per-fixture — never a blanket relaxation of the exactness
    # gate itself) — see `test/test_planning_oracle.jl`'s own measured ladder comment.
    optimizer = select_optimizer(problem_class(pf)),
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
    # oracle mirrors solve_welfare's formulation-agnostic choice). `optimizer` defaults to
    # this SAME expression (bit-for-bit identical default path, see the kwarg's own docstring note).
    model = Model(optimizer)

    # Cross-solver enablement, dormant on the primary Clarabel path (mirrors
    # solve_welfare/build_dso_opt verbatim).
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)

    ctx = ModelContext(model)
    ctx.feeder = feeder
    ctx.T = T
    # Stash the formulation's problem class so solve_planning_oracle! can default
    # its battery-complementarity τ PROBLEM-CLASS-AWARE (looser 1e-3 on the interior-point
    # SOCP path, tighter 1e-6 on the QP path) — mirroring solve_welfare's τ default —
    # without carrying `pf` itself in the struct.
    ctx.meta[:problem_class] = problem_class(pf)

    # VERBATIM power-flow builder reuse.
    contribute!(pf, ctx, feeder; T = T)

    # FREE-SIGN frontier active exchange at the root (no lower bound — the safer default).
    @variable(model, p_import[t = 1:T])
    for t in 1:T
        add_to_residual!(ctx, :Rp, feeder.root, t, p_import[t])
    end
    ctx.meta[:p_import] = p_import

    # Ordering: capture `reactive` IMMEDIATELY after the formulation contributes,
    # BEFORE any aggregator writes (mirrors solve_welfare).
    reactive = haskey(ctx.residuals, :Rq)

    if reactive
        @variable(model, q_import[t = 1:T])   # free-sign reactive frontier import
        for t in 1:T
            add_to_residual!(ctx, :Rq, feeder.root, t, q_import[t])
        end
        ctx.meta[:q_import] = q_import
    end

    # Aggregators: net active/reactive injections + utility. Return discarded
    # (no per-aggregator stash is needed here).
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

    # THE NEW SEAM: z as a genuine JuMP Parameter, and the named pin
    # p_import[t] == z[t]. Its dual (read by solve_planning_oracle!) is the Benders-cut
    # gradient.
    @variable(model, z[t = 1:T] in Parameter(0.0))
    @constraint(model, pin[t = 1:T], p_import[t] == z[t])

    # GLB-CVX welfare (thesis eq. 3.38), identical shape to solve_welfare's objective.
    @objective(model, Max, ctx.objective - sum(λ₀[t] * p_import[t] for t in 1:T))

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
                          attempts_out::Union{Nothing,Ref{Int}} = nothing,
                          on_inexact::Symbol = :throw)
        -> (; cost, π, π_s, dadp, ctx, exactness, socp_maxgap)

Re-solve the built-ONCE [`PlanningOracle`](@ref) `o` at the coupling-flow trial
`z_trial` (`set_parameter_value.` only, NEVER a rebuild) via
[`solve_with_retry!`](@ref) — the SOLE solve entry point — then run
the SAME two mandatory post-solve trust gates as [`solve_welfare`](@ref), the model this
oracle mirrors, strictly BEFORE any dual is read:

 1. the EXACTNESS GATE [`assert_socp_exact!`](@ref)`(o.ctx; rtol = rtol_exact)` —
    DATA-DRIVEN on the squared-current `:l` stash in `o.ctx.pf_vars` (only
    `ConvexBranchFlow` stashes `:l`; DC/LinDistFlow skip untouched). The pin
    `p_import[t] == z[t]` REMOVES the priced-export degree of freedom that
    `solve_welfare` identifies as the SOC-exactness ENABLER, so an off-optimal `z_trial`
    is exactly the regime where the cone can go slack — a physically-meaningless `π`
    (the Benders-cut gradient) from an inexact relaxation is REFUSED (thrown), never
    returned. `maxgap` is stashed under
    `o.ctx.meta[:socp_maxgap]`;
 2. the App. C MANDATORY battery complementarity check
    [`assert_battery_complementarity!`](@ref)`(o.ctx; τ, T = o.T)` — degenerate
    `p_ch·p_dch` co-activation is MORE likely at a pinned off-optimal `z` than at the
    free welfare optimum. `τ` defaults PROBLEM-CLASS-AWARE from the
    `problem_class(pf)` stashed at build time (`1e-3` on the SOCP path, `1e-6` on the
    QP path), mirroring `solve_welfare`'s default; it is a DISTINCT quantity from
    `rtol_exact` — never conflated.

Returns a `NamedTuple`:

  - `cost` — the welfare optimum at this trial (`objective_value(o.model)`);
  - `π`    — the length-T dual of the pin `p_import[t] == z[t]` (`dual.(o.pin)`), the
    EXACT Benders-cut gradient; its raw-dual sign convention is pinned by a
    hand-derived toy-case monotonicity invariant, not
    an assumed docstring formula: `π` is monotonically NON-DECREASING in `z_trial`,
    crossing zero at the network's own unconstrained free-import optimum;
  - `π_s`  — the DURATION-WEIGHTED reconciliation `Σ_t Δt·π[t]` (default
    `Δt = 1.0`, matching the framework's hourly rate today and correct-by-construction
    for a future non-uniform `Δt`). REPORTING-ONLY: never fed back into the
    optimization, computed purely for interpretation;
  - `dadp` — the distribution price at the first aggregator's bus
    (`dual.(o.ctx.constraints[:balance_p][o.agg_bus, :])`), mirroring
    `solve_welfare`'s `priced = aggregators[1].bus` convention;
  - `ctx`  — the solved [`ModelContext`](@ref), so a caller can read any other dual;
  - `exactness` — the exactness gate's EXPLICIT verdict: `:exact` (the gate ran and passed), `:inexact` (the gate ran and failed —
    only ever returned under `on_inexact = :report`), or `:not_applicable` (no `:l`
    stash — DC/LinDistFlow — so the gate never ran);
  - `socp_maxgap` — the measured absolute cone residual `max |l·v − (P²+Q²)|` whenever
    the gate ran (exact or inexact), `NaN` when `exactness === :not_applicable`.

`on_inexact`: `:throw` (the default — bit-for-bit identical
to every call site that predates `on_inexact`) rethrows the exactness gate's own `CertificateError`;
`:report` returns the inexact result instead, with `exactness = :inexact`. In BOTH modes
the battery-complementarity gate runs on every result that is returned — an inexact
`:report` result is never exempted from it (a complementarity violation always throws).
`:report` exists for `solve_stackelberg!`'s `inexact_policy` dispatch, so the caller
learns the verdict from an explicit return field rather than inferring it from which
side effects a throw left behind.

Throws `ArgumentError` when `length(z_trial) != o.T` (a shape mismatch must
fail loudly before `set_parameter_value.` — never silently truncate/pad the trial).

`attempts_out` is forwarded UNCHANGED to `solve_with_retry!` (additive —
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
    on_inexact::Symbol = :throw,
)
    length(z_trial) == o.T ||
        throw(ArgumentError("z_trial has length $(length(z_trial)), expected T=$(o.T)"))
    on_inexact in (:throw, :report) || throw(
        ArgumentError(
            "solve_planning_oracle!: on_inexact must be :throw or :report, got $(repr(on_inexact))",
        ),
    )

    set_parameter_value.(o.z, z_trial)   # mutate the Parameter, no rebuild
    # Drop any `:socp_maxgap` certificate left by a PRIOR
    # solve of this build-once model, so a stashed key always describes THIS solve.
    delete!(o.ctx.meta, :socp_maxgap)

    # solve_with_retry! is the SOLE solve entry point (its internal STRICT gate,
    # dual = true, ensures π is read only after a trusted solve).
    solve_with_retry!(
        o.model;
        max_attempts = max_attempts,
        dual = true,
        attempts_out = attempts_out,
    )

    # EXACTNESS GATE (mirrors solve_welfare): MUST
    # run AFTER the trusted solve and BEFORE any dual is read, so a physically-meaningless
    # π from a STRICT (inexact) SOC relaxation is REFUSED (thrown) rather than returned as
    # a Benders-cut gradient into the entire planning loop. DATA-DRIVEN on the
    # `:l` stash: only ConvexBranchFlow stashes `:l`, so DC/LinDistFlow skip untouched.
    # The pin removes the priced-export SOC-exactness enabler, making this gate MORE
    # load-bearing at an off-optimal z_trial than in the free welfare solve, not less.
    #
    # The gate's verdict is captured EXPLICITLY here,
    # at the one call site that can produce it, instead of being inferred later by a
    # caller from whether `:socp_maxgap` happens to be stashed. `assert_socp_exact!`'s ONLY
    # exactness verdict is `CertificateError(kind = :socp_exact)` (its malformed-feeder guard is an
    # `ArgumentError`, a missing stash a `KeyError` — both propagate untouched below).
    # Under `on_inexact = :throw` (the default) that verdict is rethrown unchanged — the
    # bit-for-bit identical behavior every other caller relies on. Under
    # `on_inexact = :report` the verdict is RETURNED (`exactness = :inexact`, the raw cone
    # residual in `socp_maxgap`) instead of thrown — and, crucially, execution still falls
    # through to the battery-complementarity gate below, which is NEVER skipped.
    # `:socp_maxgap` is stashed ONLY on an exact verdict: its presence is the
    # certificate other consumers check (e.g. `extract_dlmp`), so it must never be set on
    # an inexact solve.
    exactness = :not_applicable
    socp_maxgap = NaN
    if has_branch_current(o.ctx)
        try
            socp_maxgap = assert_socp_exact!(o.ctx; rtol = rtol_exact)
            o.ctx.meta[:socp_maxgap] = socp_maxgap
            exactness = :exact
        catch e
            (e isa CertificateError && e.kind === :socp_exact && on_inexact === :report) ||
                rethrow()
            exactness = :inexact
            socp_maxgap = socp_relaxation_gap(o.ctx)
        end
    end

    # App. C MANDATORY battery complementarity at the PINNED point (mirrors
    # solve_welfare): degenerate p_ch·p_dch co-activation is MORE likely
    # at a pinned off-optimal z than at the free optimum. Data-driven no-op when no
    # batteries were registered under ctx.agg_device_vars. Runs on EVERY returned
    # result, including an `on_inexact = :report` inexact one.
    assert_battery_complementarity!(o.ctx; τ = τ, T = o.T)

    π = dual.(o.pin)                                    # length-T pin dual
    π_s = sum(Δt * π[t] for t in 1:o.T)                 # duration-weighted, reporting-only
    dadp = dual.(o.ctx.constraints[:balance_p][o.agg_bus, :])
    cost = objective_value(o.model)

    return (; cost, π, π_s, dadp, ctx = o.ctx, exactness, socp_maxgap)
end

