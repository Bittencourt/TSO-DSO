# src/models/mpc_window.jl
#
# SEAM: build-once receding-horizon window model (MPC-01/MPC-02).
# OWNER: plan 21-03.
#
# `welfare_solve.jl`/`oracle.jl` are byte-for-byte UNMODIFIED by this file (D-01/D-03): this
# module mirrors `PlanningOracle`'s build-once/`Parameter`-re-solve SHAPE
# (`src/planning/subproblem.jl`, the ONLY existing build-once model in this codebase) —
# generalized from a single `z`-pin to the full set of per-step-varying inputs plan 21-01
# widened: battery/thermostatic initial conditions (`soc0`/`Tin0`), PV/ambient/demand forecast
# slices (`Ppv_param`/`Tout_param`/`Pdc_param`), and an optional hard terminal-SOC target
# (MPC-02, D-06). D-02's "each window solves the centralized `solve_welfare` problem" is read
# here as describing the MATH shape (centralized welfare, not ADMM decomposition) — this
# builder NEVER calls `solve_welfare` itself, exactly as `PlanningOracle` already mirrors that
# shape one level up in the planning layer rather than literally calling the function.
#
# `build_mpc_window` builds the fixed-length `[τ=1:H]` window model EXACTLY ONCE; a caller
# re-solves it many times via `set_parameter_value!`/`set_parameter_value.` on the returned
# `ic_handles`/`agg_pdc_handles` Parameter handles plus `set_objective_coefficient` on
# `p_import` (the frontier price `λ₀`, NEVER a Parameter — Pitfall 2), with
# `num_variables`/`num_constraints` provably UNCHANGED across every re-solve. `solve_mpc_window!`
# is a one-line delegation to `solve_with_retry!` (plan 10-01) — the SOLE solve entry point —
# and never adds a variable or constraint.

using JuMP

"""
    MpcWindow{F}

The built-ONCE receding-horizon window model (MPC-01/MPC-02): the welfare-shaped model
(mirrors [`PlanningOracle`](@ref)'s build-once SHAPE, generalized from a single `z`-pin to the
full set of per-step device Parameters plan 21-01 widened) over a FIXED window length `H`.

# Fields

  - `model::Model` — the welfare-shaped window model, built ONCE via
    `select_optimizer(problem_class(pf))` (formulation-generic — NEVER hardcodes `SOCP()`);
    re-solved via `set_parameter_value`/`set_objective_coefficient` + `optimize!` only, never
    rebuilt.
  - `ctx::ModelContext` — the shared context; `ctx.constraints[:balance_p]` (and `:balance_q`
    when the formulation provides a reactive channel) carries the DADP duals.
  - `H::Int` — the FIXED window length `[τ=1:H]` (Pitfall 5: never shrinks across re-solves).
  - `agg_bus::Int` — the first aggregator's bus (`aggregators[1].bus`), mirroring
    `PlanningOracle`'s DADP reporting convention.
  - `feeder::F` — the network the window is built on.
  - `p_import::Vector{VariableRef}` — the FREE-SIGN frontier active exchange `p_import[τ]` (no
    lower bound — export stays ALLOWED, D-04); NEVER wrapped in a `Parameter` (Pitfall 2). A
    caller slides the frontier price `λ₀` via
    `set_objective_coefficient(o.model, o.p_import[τ], -λ0_window[τ])`.
  - `ic_handles::Vector{<:NamedTuple}` — one entry per stateful device:
    `(; bus::Int, kind::Symbol, ic_param, terminal_param)`, `kind ∈ (:soc, :Tin)`.
    `terminal_param` is `nothing` unless `kind == :soc && terminal_soc` (D-07: Thermostatic's
    `:Tin` entries NEVER carry a terminal target).
  - `agg_pdc_handles::Vector{<:NamedTuple}` — one entry per aggregator: `(; bus::Int,
    Pdc_param)`, the per-step inelastic-demand forecast Parameter.
  - `terminal_soc::Bool` — the build-time toggle recorded for introspection; `true` means every
    `:soc`-kind `ic_handles` entry carries a live hard equality `soc[H] == terminal_param`.
"""
struct MpcWindow{F}
    model::Model
    ctx::ModelContext
    H::Int
    agg_bus::Int
    feeder::F
    p_import::Vector{VariableRef}
    ic_handles::Vector{<:NamedTuple}
    agg_pdc_handles::Vector{<:NamedTuple}
    terminal_soc::Bool
end

"""
    build_mpc_window(feeder, pf::AbstractPowerFlow,
                     aggregators::AbstractVector{<:Aggregator};
                     H::Int, terminal_soc::Bool = true) -> MpcWindow

Build the fixed-length `[τ=1:H]` welfare-shaped receding-horizon window model EXACTLY ONCE
(MPC-01), mirroring [`build_planning_oracle`](@ref)'s build-once SHAPE:

 1. Boundary guards (mirror `build_planning_oracle`): empty `aggregators`, `H < 1`, or an
    aggregator bus outside `1:length(feeder.buses)` each throw `ArgumentError` before any
    model assembly.
 2. `model = Model(select_optimizer(problem_class(pf)))` — FORMULATION-GENERIC routing, never
    hardcoding `SOCP()`. Registers the same SOC→nonconvex-quad cross-solver bridges as
    `solve_welfare`/`build_planning_oracle` (dormant on the primary Clarabel path).
 3. `contribute!(pf, ctx, feeder; T = H)` — VERBATIM reuse of the validated power-flow builder.
 4. A FREE-SIGN frontier `p_import[τ = 1:H]` at `feeder.root` (no lower bound — export stays
    ALLOWED, D-04, mirroring `PlanningOracle`'s Open-Question-1 resolution), injected into
    `:Rp[root]`. `reactive = haskey(ctx.residuals, :Rq)` is captured IMMEDIATELY after, BEFORE
    any aggregator write (WR-03 ordering); if `reactive`, a FREE-SIGN `q_import[τ=1:H]` too.
 5. Each aggregator `contribute!`s its net injection + utility; its returned `Pdc_param`
    (returned at the Aggregator's OWN top level, not nested inside `res.vars`) is captured into
    `agg_pdc_handles`. `ctx.meta[:agg_device_vars]` is populated as a SIDE EFFECT of this SAME
    `contribute!` call (plan 21-01's widened `soc0`/`Tin0`/`Ppv_param`/`Tout_param` Parameters).
 6. Residuals are closed with the same defensive `size(...) == (N, H)` guard as
    `build_planning_oracle` before each `@constraint`; `:balance_p` is always registered,
    `:balance_q` only when `reactive`.
 7. `ctx.meta[:agg_device_vars]` is walked to populate `ic_handles`: every device carrying a
    `soc0` Parameter (PVBattery, FourQuadBESS) gets a `:soc`-kind entry; every device carrying
    a `Tin0` Parameter (Thermostatic) gets a `:Tin`-kind entry with `terminal_param = nothing`
    ALWAYS (D-07: no terminal condition on thermostatic temperature, ever). When
    `terminal_soc = true`, every `:soc`-kind entry ALSO gets a hard equality
    `soc[H] == terminal_param` against a NEW anonymous Parameter defaulting to the device's own
    IC value (a benign, always-overridden default) — the ONE build-time toggle this plan
    permits (MPC-02, D-06). When `terminal_soc = false`, no such constraint exists in the model
    at all — a genuinely different model, never a silent no-op.
 8. `p_import`'s objective coefficient is set to a PLACEHOLDER `0.0` at build time — the caller
    (Wave 4) ALWAYS calls `set_objective_coefficient` before the first solve. `p_import`/`λ₀`
    is NEVER wrapped in a `Parameter` here (Pitfall 2: a `Parameter`-times-variable bilinear
    term is not representable in this convex QP/SOCP shape).

Returns an [`MpcWindow`](@ref). `welfare_solve.jl`/`oracle.jl` are NOT modified by this
function (D-01/D-03) — it is a wholly NEW module reusing their builders verbatim, and it NEVER
calls `solve_welfare` internally.
"""
function build_mpc_window(
    feeder,
    pf::AbstractPowerFlow,
    aggregators::AbstractVector{<:Aggregator};
    H::Int,
    terminal_soc::Bool = true,
)
    # Boundary guards (mirror build_planning_oracle): fail here, not deep in model assembly.
    isempty(aggregators) &&
        throw(ArgumentError("build_mpc_window needs at least one aggregator"))
    H >= 1 || throw(ArgumentError("build_mpc_window requires H ≥ 1, got H=$H"))

    N = length(feeder.buses)
    for (k, agg) in enumerate(aggregators)
        1 <= agg.bus <= N || throw(
            ArgumentError("aggregator[$k] bus=$(agg.bus) is outside feeder buses 1:$N"),
        )
    end

    # Formulation-generic factory routing (NEVER hardcode SOCP() — mirrors
    # build_planning_oracle/solve_welfare's formulation-agnostic choice).
    model = Model(select_optimizer(problem_class(pf)))

    # Cross-solver enablement, dormant on the primary Clarabel path (mirrors
    # build_planning_oracle/solve_welfare verbatim).
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)

    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder
    ctx.meta[:T] = H
    ctx.meta[:problem_class] = problem_class(pf)

    # VERBATIM power-flow builder reuse.
    contribute!(pf, ctx, feeder; T = H)

    # FREE-SIGN frontier active exchange at the root (no lower bound — export stays ALLOWED,
    # D-04, mirroring PlanningOracle's Open-Question-1 resolution).
    @variable(model, p_import[τ = 1:H])
    for τ in 1:H
        add_to_residual!(ctx, :Rp, feeder.root, τ, p_import[τ])
    end
    ctx.meta[:p_import] = p_import

    # WR-03 ordering: capture `reactive` IMMEDIATELY after the formulation contributes, BEFORE
    # any aggregator writes (mirrors build_planning_oracle/solve_welfare).
    reactive = haskey(ctx.residuals, :Rq)

    if reactive
        @variable(model, q_import[τ = 1:H])   # free-sign reactive frontier import
        for τ in 1:H
            add_to_residual!(ctx, :Rq, feeder.root, τ, q_import[τ])
        end
        ctx.meta[:q_import] = q_import
    end

    # Aggregators: net active/reactive injections + utility. Capture each aggregator's
    # top-level Pdc_param handle (plan 21-01's widened per-step inelastic-demand Parameter) —
    # ctx.meta[:agg_device_vars] is populated as a SIDE EFFECT of this SAME contribute! call.
    agg_pdc_handles = NamedTuple[]
    for agg in aggregators
        res = contribute!(agg, ctx; T = H)
        push!(agg_pdc_handles, (; bus = agg.bus, Pdc_param = res.Pdc_param))
    end

    # Close :Rp always; :Rq only when the formulation provides a reactive channel.
    size(ctx.residuals[:Rp]) == (N, H) || error(
        "residual :Rp is $(size(ctx.residuals[:Rp])), expected ($N, $H) — an index escaped the feeder",
    )
    @constraint(model, balance_p[j = 1:N, τ = 1:H], ctx.residuals[:Rp][j, τ] == 0)
    register_constraint!(ctx, :balance_p, balance_p)          # dual = λ_j (DADP)

    if reactive
        size(ctx.residuals[:Rq]) == (N, H) || error(
            "residual :Rq is $(size(ctx.residuals[:Rq])), expected ($N, $H) — an index escaped the feeder",
        )
        @constraint(model, balance_q[j = 1:N, τ = 1:H], ctx.residuals[:Rq][j, τ] == 0)
        register_constraint!(ctx, :balance_q, balance_q)
    end

    # Walk ctx.meta[:agg_device_vars] to populate ic_handles (MPC-01 seam consumption): every
    # device carrying a soc0 Parameter (PVBattery, FourQuadBESS) gets a :soc-kind entry, every
    # device carrying a Tin0 Parameter (Thermostatic) gets a :Tin-kind entry. terminal_param
    # stays `nothing` for :Tin ALWAYS (D-07). Anonymous per-device Parameter/constraint (unique
    # `base_name`, never a shared object-dictionary symbol) so multiple battery-like devices
    # compose in one window without a name collision — the same discipline FourQuadBESS's
    # anonymous apparent-power cone already establishes in this codebase.
    ic_handles = NamedTuple[]
    if haskey(ctx.meta, :agg_device_vars)
        for (bus, varlist) in ctx.meta[:agg_device_vars]
            for v in varlist
                if haskey(v, :soc0)
                    if terminal_soc
                        term = @variable(
                            model,
                            base_name = "soc_terminal_bus$(bus)",
                            set = Parameter(parameter_value(v.soc0)),
                        )
                        @constraint(model, v.soc[H] == term)
                        push!(
                            ic_handles,
                            (; bus, kind = :soc, ic_param = v.soc0, terminal_param = term),
                        )
                    else
                        push!(
                            ic_handles,
                            (;
                                bus,
                                kind = :soc,
                                ic_param = v.soc0,
                                terminal_param = nothing,
                            ),
                        )
                    end
                end
                if haskey(v, :Tin0)
                    push!(
                        ic_handles,
                        (; bus, kind = :Tin, ic_param = v.Tin0, terminal_param = nothing),
                    )
                end
            end
        end
    end

    # PLACEHOLDER objective coefficient on p_import (Pitfall 2: λ₀ is NEVER a Parameter — it
    # slides via set_objective_coefficient, mirroring AgrOpt.jl's own documented avoidance of
    # the Parameter-times-variable bilinear failure). The caller (Wave 4) ALWAYS calls
    # set_objective_coefficient before the first solve; 0.0 is never itself a modeling claim.
    @objective(model, Max, ctx.meta[:objective] - sum(0.0 * p_import[τ] for τ in 1:H))

    return MpcWindow(
        model,
        ctx,
        H,
        aggregators[1].bus,
        feeder,
        p_import,
        ic_handles,
        agg_pdc_handles,
        terminal_soc,
    )
end

"""
    solve_mpc_window!(o::MpcWindow; max_attempts::Int = 4,
                      attempts_out::Union{Nothing,Ref{Int}} = nothing) -> Model

Re-solve the built-ONCE [`MpcWindow`](@ref) `o` via [`solve_with_retry!`](@ref) (plan 10-01) —
the SOLE solve entry point — a ONE-LINE delegation that NEVER adds a variable or constraint to
`o.model`. Callers mutate `o.ic_handles`/`o.agg_pdc_handles` via
`set_parameter_value`/`set_parameter_value.` and `o.p_import` via `set_objective_coefficient`
BEFORE calling this function.
"""
function solve_mpc_window!(
    o::MpcWindow;
    max_attempts::Int = 4,
    attempts_out::Union{Nothing, Ref{Int}} = nothing,
)
    return solve_with_retry!(
        o.model;
        max_attempts = max_attempts,
        dual = true,
        attempts_out = attempts_out,
    )
end

export MpcWindow, build_mpc_window, solve_mpc_window!
