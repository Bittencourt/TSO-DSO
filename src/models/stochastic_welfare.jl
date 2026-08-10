# src/models/stochastic_welfare.jl
#
# SEAM: two-stage extensive-form stochastic welfare builder (STOCH-01/STOCH-02).
# OWNER: plan 22-02.
#
# `welfare_solve.jl`, `oracle.jl`, every `src/devices/*.jl` file, and
# `src/powerflow/ConvexBranchFlow.jl` are BYTE-FOR-BYTE UNMODIFIED by this file — it is
# PURE ADDITIVE ORCHESTRATION over already-validated building blocks (`contribute!`,
# `ModelContext`, `assert_solved!`, `assert_socp_exact!`, `assert_battery_complementarity!`).
#
# D-02's honest SEAM-01 resolution note: `models/oracle.jl`'s `objective_hook` stub (inert
# since Phase 4) is INSUFFICIENT for this axis — it only transforms `ctx.meta[:objective]`
# on ONE already-built `ctx`, and has no argument through which to express per-scenario
# DUPLICATION of the network + device layer. Building S independently-`contribute!`d
# scenario blocks needs a genuinely new orchestration entry point, hence this sibling
# module rather than a `objective_hook` wiring.
#
# The genuinely new mechanical fact this file's construction depends on (RESEARCH.md
# Pattern 1, empirically verified): `contribute!(::ConvexBranchFlow, ctx, feeder; T)`
# registers NINE named JuMP containers (`:v, :v̂, :P, :Q, :l, :cone, :vdrop, :cpydrop,
# :smax`). Calling it a second time on the SAME `Model` throws
# `"An object of name v is already attached to this model"` unless `JuMP.unregister(model,
# name)` is called for each of those nine names between scenario blocks. `unregister` frees
# only the NAME (the model's object-dictionary lookup) — the underlying `VariableRef`/
# `ConstraintRef` handles already captured in a scenario's own `ctx_s.meta[:pf_vars]` /
# `ctx_s.constraints` remain independently usable afterward. `unregister` is never called
# after the LAST scenario (nothing follows it).
#
# Nonanticipativity (D-03): the battery-like devices (any device whose returned `vars`
# NamedTuple carries `:soc0` — currently `PVBattery`/`FourQuadBESS`) are first-stage,
# SHARED across scenarios; network flows, imports, and thermostatic response stay
# per-scenario recourse. Rather than threading one literally-shared JuMP variable through
# S scenario blocks (impossible without restructuring a device's own `contribute!`, which
# bundles controls and per-scenario DATA Parameters into one call), each scenario builds
# its OWN independent battery copy (seeing its own scenario's `Ppv_param`), and explicit
# equality constraints tie scenario s's schedule to scenario 1's — the standard
# extensive-form nonanticipativity idiom (Birge & Louveaux, 2011).
#
# Per-scenario DADP de-scaling (D-05, empirically verified against `solve_welfare`'s own
# baseline this phase's RESEARCH.md session): in a `Max`-sense objective
# `Σ_s p_s·(utility_s − λ₀ᵀp_import_s)`, scenario s's `:balance_p` dual is scaled by `p_s`
# relative to the deterministic (single-scenario) case — dividing the raw dual by `p_s`
# restores the standard per-scenario price interpretation, with NO sign flip (this
# constraint shape is structurally identical to `solve_welfare`'s own `:balance_p`).
#
# PF-04 gating (D-06): `assert_socp_exact!` runs ONCE PER SCENARIO in a plain loop, never
# aggregated — one scenario's exactness can never mask another's inexactness.
#
# Plan 22-02 deviation (Rule 1 — auto-fixed bug; see `src/solver/factory.jl`): a
# probability-weighted extensive form genuinely WEAKENS a low-probability scenario's own
# loss-cost gradient (scaled by its `probabilities[s]`), which — empirically verified this
# plan, on a near-lossless branch — can leave Clarabel's SOCP-factory base `tol_gap=1e-8`
# short of that scenario's true (unique, gradient-driven) cone-tight point, tripping PF-04
# on a genuinely tiny, non-structural residual. This builder's DEFAULT `optimizer`
# therefore requests `tol_gap_abs/rel = 1e-10` via a new keyword-override method on
# `select_optimizer(::SOCP; attrs...)` (mirrors the pre-existing `NLP` method's own
# pattern) — a convergence-precision fix, not a weakening of the exactness GATE's own
# tolerance. `select_optimizer(SOCP())` with no kwargs (every OTHER caller) is unaffected.
#
# The probability-weighted expectation (D-07) is a DERIVED summary field
# (`expected_dadp`) — never itself a constraint-backed price primitive; only the
# per-scenario `dadp[s]` are.

using JuMP

"""
    build_stochastic_welfare(feeder, pf::AbstractPowerFlow,
        scenario_aggs::AbstractVector{<:AbstractVector{<:Aggregator}};
        probabilities::AbstractVector{<:Real} = fill(1/length(scenario_aggs), length(scenario_aggs)),
        T::Int, λ₀::AbstractVector{<:Real},
        optimizer = select_optimizer(problem_class(pf)), allow_local::Bool = false,
        allow_export::Bool = false, rtol_exact::Real = 1e-4,
        τ::Real = (problem_class(pf) isa SOCP ? 1e-3 : 1e-6))
        -> (; model, ctxs, probabilities, welfare, dadp, expected_dadp, socp_maxgap)

Build and solve the S-scenario two-stage extensive-form welfare problem (STOCH-01):
`length(scenario_aggs)` independently-`contribute!`d, `JuMP.unregister`-decoupled network
blocks on ONE shared `Model`, with battery-like first-stage devices tied across scenarios
by explicit nonanticipativity equality constraints (D-03) and network flows/imports/
thermostatic response left as per-scenario recourse.

# Construction (mirrors [`solve_welfare`](@ref)'s shape S times)

For each scenario `s in 1:S`:
 1. a FRESH `ModelContext(model)` is built on the SAME shared `model`;
 2. `contribute!(pf, ctx_s, feeder; T)` writes that scenario's OWN network copy — the
    `ConvexBranchFlow` named-container collision (RESEARCH.md Pattern 1) is avoided by
    `JuMP.unregister`-ing the nine formulation container names between scenario blocks
    (never after the last one);
 3. every aggregator in `scenario_aggs[s]` `contribute!`s its own scenario's devices
    (`ctx_s.meta[:agg_device_vars]` records each device's returned vars, keyed by bus);
 4. an ANONYMOUS per-scenario frontier `p_import_s` (free-sign under `allow_export`, else
    `≥ 0`) and, when the formulation provides a reactive channel (WR-03,
    `haskey(ctx_s.residuals, :Rq)`, captured right after step 2, before step 3's
    aggregator writes), a free-sign `q_import_s`, are injected at `feeder.root` — AFTER
    the aggregators, mirroring `solve_welfare`'s own construction order exactly (Rule 1
    fix: building the frontier before the aggregators is mathematically equivalent but
    shifts Clarabel's internal variable/constraint ordering enough to move a
    near-zero-flow branch's cone residual across the PF-04 threshold at small per-unit
    magnitudes — the S=1 degenerate case must mirror `solve_welfare`'s own numerical path
    to satisfy D-08 reliably);
 5. the residuals are closed via the ANONYMOUS array-constraint form (never the named
    macro, which would collide across scenarios exactly like `ConvexBranchFlow`'s own
    containers) and registered under `:balance_p`/`:balance_q` in `ctx_s.constraints` — a
    fresh per-`ModelContext` `Dict`, so S scenarios never collide on the SAME key.

AFTER every scenario block is built, nonanticipativity equality constraints tie every
battery-like device (any device whose `contribute!`-returned `vars` carries `:soc0` — a
`PVBattery` or `FourQuadBESS`) at bus/index `(bus, idx)` across scenarios:
`p_ch_s[t] == p_ch_1[t]`, `p_dch_s[t] == p_dch_1[t]`, `soc_s[t] == soc_1[t]` for
`s = 2:S`, `t = 1:T` — `Deferrable` is DELIBERATELY excluded from this tie (not
first-stage in this builder).

The objective is the probability-weighted sum
`Σ_s probabilities[s]·(ctx_s.meta[:objective] − Σ_t λ₀[t]·p_import_s[t])`. After
`assert_solved!(model; dual = true, allow_local)`, the PF-04 exactness gate
`assert_socp_exact!` runs ONCE PER SCENARIO (D-06 — never aggregated, never a new
certificate) whenever that scenario stashed a squared-current `:l`, recording each
scenario's own `maxgap` into `socp_maxgap`. THEN `assert_battery_complementarity!` runs
once per scenario (App. C, applied identically to every scenario's tied battery copy by
construction). ONLY THEN are duals read: `dadp[s] = dual.(balance_p_s[priced, :]) ./
probabilities[s]` (D-05 de-scaling — no sign flip; `priced = scenario_aggs[1][1].bus`) is
the PRIMARY per-scenario price output; `expected_dadp = Σ_s probabilities[s]·dadp[s]` is
an explicitly-named DERIVED summary (D-07) — never a constraint-backed price primitive.

# Boundary guards (mirror `solve_welfare`'s ordering + `Scenario`'s own guard style)

Throws `ArgumentError` on: empty `scenario_aggs`; `length(probabilities) != S`; any
non-positive probability; `sum(probabilities)` not `≈ 1` (`atol = 1e-8`); `length(λ₀) !=
T`; a structural mismatch between `scenario_aggs[s]` and `scenario_aggs[1]` (differing
device count or differing bus order at any aggregator index — nonanticipativity ties
would otherwise be mispaired across scenarios); or any aggregator bus outside
`1:length(feeder.buses)`.

Returns a `NamedTuple` `(; model, ctxs, probabilities, welfare, dadp, expected_dadp,
socp_maxgap)` where `ctxs::Vector{ModelContext}`, `dadp::Vector{Vector{Float64}}` (one
per scenario), `expected_dadp::Vector{Float64}`, and `socp_maxgap::Vector{Float64}` (one
per scenario whose formulation carries an SOC cone).
"""
function build_stochastic_welfare(
    feeder,
    pf::AbstractPowerFlow,
    scenario_aggs::AbstractVector{<:AbstractVector{<:Aggregator}};
    probabilities::AbstractVector{<:Real} = fill(
        1 / length(scenario_aggs),
        length(scenario_aggs),
    ),
    T::Int,
    λ₀::AbstractVector{<:Real},
    # Plan 22-02 (STOCH-01) deviation (Rule 1 — auto-fixed bug, see factory.jl): the
    # probability-weighted extensive-form objective scales each scenario's own loss-cost
    # gradient by that scenario's `probabilities[s]`, genuinely weakening the pressure
    # driving a LOW-probability scenario's SOC cone tight relative to `solve_welfare`'s own
    # (implicitly probability-1) single-scenario gradient. Empirically verified this plan:
    # at the SOCP() factory's base `tol_gap=1e-8`, this can leave a low-probability
    # scenario's cone residual measurably (though not structurally) short of tight on a
    # near-lossless branch; `tol_gap_abs/rel = 1e-10` resolves it (5.6e-6 → 5.7e-10)
    # without touching the PF-04 exactness GATE's own tolerance. QP()/other classes are
    # untouched (their `select_optimizer` methods take no keyword overrides).
    optimizer = (
        problem_class(pf) isa SOCP ?
        select_optimizer(problem_class(pf); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10) :
        select_optimizer(problem_class(pf))
    ),
    allow_local::Bool = false,
    allow_export::Bool = false,
    rtol_exact::Real = 1e-4,
    τ::Real = (problem_class(pf) isa SOCP ? 1e-3 : 1e-6),
)
    # Boundary guards FIRST (mirrors solve_welfare's own ordering).
    isempty(scenario_aggs) &&
        throw(ArgumentError("build_stochastic_welfare needs at least one scenario"))

    S = length(scenario_aggs)

    length(probabilities) == S || throw(
        ArgumentError(
            "probabilities has length $(length(probabilities)), expected S=$S",
        ),
    )
    any(<=(0), probabilities) && throw(
        ArgumentError("probabilities must all be strictly positive; got $probabilities"),
    )
    isapprox(sum(probabilities), 1; atol = 1e-8) ||
        throw(ArgumentError("probabilities must sum to 1 (got sum=$(sum(probabilities)))"))
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))

    # Structural congruence (D-03): nonanticipativity ties every scenario's device k
    # against scenario 1's device k, so scenario_aggs[s] must have the SAME device count
    # and the SAME bus at each index as scenario_aggs[1].
    for s in 2:S
        length(scenario_aggs[s]) == length(scenario_aggs[1]) || throw(
            ArgumentError(
                "scenario_aggs[$s] has $(length(scenario_aggs[s])) aggregators, " *
                "expected $(length(scenario_aggs[1])) (structural congruence with " *
                "scenario 1, required so nonanticipativity ties are never mispaired)",
            ),
        )
        for k in 1:length(scenario_aggs[1])
            scenario_aggs[s][k].bus == scenario_aggs[1][k].bus || throw(
                ArgumentError(
                    "scenario_aggs[$s][$k].bus=$(scenario_aggs[s][k].bus) != " *
                    "scenario_aggs[1][$k].bus=$(scenario_aggs[1][k].bus) — structural " *
                    "mismatch would mispair nonanticipativity ties across scenarios",
                ),
            )
        end
    end

    Np = length(feeder.buses)
    for s in 1:S, (k, agg) in enumerate(scenario_aggs[s])
        1 <= agg.bus <= Np || throw(
            ArgumentError(
                "scenario_aggs[$s][$k] bus=$(agg.bus) is outside feeder buses 1:$Np",
            ),
        )
    end

    model = Model(optimizer)   # SOCP()/QP() factory by default; never names a solver

    # Cross-solver enablement (mirrors solve_welfare verbatim) — dormant on the primary
    # Clarabel path, only activates for a deliberately nonconvex NLP cross-check.
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)

    ctxs = ModelContext[]

    for s in 1:S
        ctx_s = ModelContext(model)
        ctx_s.meta[:feeder] = feeder
        ctx_s.meta[:T] = T

        # Formulation: branch/voltage terms into ctx_s.residuals[:Rp] (and :Rq).
        contribute!(pf, ctx_s, feeder; T = T)

        # RESEARCH.md Pattern 1: ConvexBranchFlow registers NAMED containers on `model`;
        # free the NAMES (not the already-captured handles in ctx_s.meta[:pf_vars]) so the
        # NEXT scenario's contribute! call does not collide. Never after the last scenario.
        if s < S
            for name in (:v, :v̂, :P, :Q, :l, :cone, :vdrop, :cpydrop, :smax)
                JuMP.unregister(model, name)
            end
        end

        # WR-03: captured right after the formulation contributes, before any aggregator
        # write — reflects the FORMULATION's own reactive capability, not the devices'.
        reactive_s = haskey(ctx_s.residuals, :Rq)

        # Each scenario's own aggregators (and hence its own device copies, each seeing its
        # own scenario's data Parameters) contribute their net injections + utility.
        for agg in scenario_aggs[s]
            contribute!(agg, ctx_s; T = T)
        end

        # Anonymous per-scenario frontier (never the NAMED macro form — it would collide
        # across scenarios exactly like ConvexBranchFlow's own named containers), injected
        # AFTER the aggregators — mirrors solve_welfare's own construction order exactly
        # (RULE 1 fix: building the frontier BEFORE the aggregators is mathematically
        # equivalent but shifts Clarabel's internal variable/constraint ordering enough to
        # move a near-zero-flow branch's SOCP cone residual across the PF-04 exactness
        # threshold at this fixture's tiny per-unit magnitudes — verified empirically: the
        # S=1 degenerate case must byte-for-byte mirror solve_welfare's own numerical path
        # to satisfy D-08 reliably).
        p_import_s =
            allow_export ? @variable(model, [t = 1:T]) :
            @variable(model, [t = 1:T], lower_bound = 0.0)
        for t in 1:T
            add_to_residual!(ctx_s, :Rp, feeder.root, t, p_import_s[t])
        end
        ctx_s.meta[:p_import] = p_import_s

        if reactive_s
            q_import_s = @variable(model, [t = 1:T])   # free-sign reactive frontier import
            for t in 1:T
                add_to_residual!(ctx_s, :Rq, feeder.root, t, q_import_s[t])
            end
            ctx_s.meta[:q_import] = q_import_s
        end

        # Close the residuals via the ANONYMOUS array-constraint form (no name), then
        # register into ctx_s.constraints — a fresh per-ModelContext Dict, so S scenarios
        # never collide on the same :balance_p/:balance_q key.
        size(ctx_s.residuals[:Rp]) == (Np, T) || error(
            "scenario $s residual :Rp is $(size(ctx_s.residuals[:Rp])), expected " *
            "($Np, $T) — an index escaped the feeder",
        )
        balance_p_s = @constraint(model, [j = 1:Np, t = 1:T], ctx_s.residuals[:Rp][j, t] == 0)
        register_constraint!(ctx_s, :balance_p, balance_p_s)   # dual = de-scaled DADP (D-05)

        if reactive_s
            size(ctx_s.residuals[:Rq]) == (Np, T) || error(
                "scenario $s residual :Rq is $(size(ctx_s.residuals[:Rq])), expected " *
                "($Np, $T) — an index escaped the feeder",
            )
            balance_q_s =
                @constraint(model, [j = 1:Np, t = 1:T], ctx_s.residuals[:Rq][j, t] == 0)
            register_constraint!(ctx_s, :balance_q, balance_q_s)
        end

        push!(ctxs, ctx_s)
    end

    # Nonanticipativity (D-03): tie every battery-like device (haskey(vars, :soc0) —
    # PVBattery or FourQuadBESS) at bus/index (bus, idx) across scenarios s = 2:S to
    # scenario 1's own copy. Runs AFTER the full scenario loop so every scenario's device
    # vars already exist. Deferrable is deliberately excluded from this tie.
    for (bus, varlist1) in ctxs[1].meta[:agg_device_vars]
        for (idx, v1) in enumerate(varlist1)
            haskey(v1, :soc0) || continue   # battery-like device marker
            for s in 2:S
                vs = ctxs[s].meta[:agg_device_vars][bus][idx]
                @constraint(model, [t = 1:T], vs.p_ch[t] == v1.p_ch[t])
                @constraint(model, [t = 1:T], vs.p_dch[t] == v1.p_dch[t])
                @constraint(model, [t = 1:T], vs.soc[t] == v1.soc[t])
            end
        end
    end

    # Probability-weighted extensive-form welfare objective.
    @objective(
        model,
        Max,
        sum(
            probabilities[s] *
            (ctxs[s].meta[:objective] - sum(λ₀[t] * ctxs[s].meta[:p_import][t] for t in 1:T))
            for s in 1:S
        )
    )

    # OPTIMAL gate: never read a dual (price) before a trusted solve.
    assert_solved!(model; dual = true, allow_local = allow_local)

    # PF-04 EXACTNESS GATE (D-06): run ONCE PER SCENARIO, never aggregated — one scenario's
    # exactness can never mask another's inexactness. Skips a scenario whose formulation
    # stashed no squared-current :l (DC/LinDistFlow paths), exactly like solve_welfare.
    socp_maxgap = Float64[]
    for s in 1:S
        if haskey(ctxs[s].meta, :pf_vars) && haskey(ctxs[s].meta[:pf_vars], :l)
            push!(socp_maxgap, assert_socp_exact!(ctxs[s]; rtol = rtol_exact))
        end
    end

    # App. C MANDATORY post-solve battery complementarity, applied per scenario — every
    # scenario's tied battery vars satisfy it identically by construction, but the check
    # itself stays per-ctx per project convention.
    for s in 1:S
        assert_battery_complementarity!(ctxs[s]; τ = τ, T = T)
    end

    # ONLY THEN read duals. De-scaled per-scenario DADP (D-05) — PRIMARY output: the dual
    # of scenario s's OWN nodal balance, divided by its OWN probability. No sign flip: this
    # constraint shape is structurally identical to solve_welfare's own :balance_p.
    priced = scenario_aggs[1][1].bus
    dadp = [dual.(ctxs[s].constraints[:balance_p][priced, :]) ./ probabilities[s] for s in 1:S]

    # Probability-weighted expectation (D-07) — an explicitly-named DERIVED summary field,
    # never itself a constraint-backed price primitive.
    expected_dadp = sum(probabilities[s] .* dadp[s] for s in 1:S)

    return (;
        model,
        ctxs,
        probabilities = collect(Float64, probabilities),
        welfare = Float64(objective_value(model)),
        dadp = Vector{Vector{Float64}}(dadp),
        expected_dadp = Vector{Float64}(expected_dadp),
        socp_maxgap,
    )
end

export build_stochastic_welfare
