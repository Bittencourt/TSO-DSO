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
# therefore requests `tol_gap_abs/rel = 5e-10` via a new keyword-override method on
# `select_optimizer(::SOCP; attrs...)` (mirrors the pre-existing `NLP` method's own
# pattern) — a convergence-precision fix, not a weakening of the exactness GATE's own
# tolerance. `5e-10` (not a more aggressive `1e-10`) was chosen because `1e-10` measurably
# trips `ALMOST_OPTIMAL` on a SEPARATE, more-lossy fixture (Task 2's own D-06 test) —
# `5e-10` sits inside the measured common window `[3e-10, 9e-10]` that converges cleanly
# on BOTH fixtures. `select_optimizer(SOCP())` with no kwargs (every OTHER caller) is
# unaffected.
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
`p_ch_s[t] == p_ch_1[t]`, `p_dch_s[t] == p_dch_1[t]`, and — for a device carrying a
reactive dispatch (`FourQuadBESS`; WR-04 fix, phase-22 review) — `q_s[t] == q_1[t]`, for
`s = 2:S`, `t = 1:T`: the ENTIRE battery schedule, active AND reactive, is first-stage
under D-03, never a partial (active-only) tie. `soc` is DELIBERATELY NOT tied (WR-09
fix, phase-22 review): each scenario copy's own `soc[1] == soc0` initial condition plus
its SOC recursion, together with the `p_ch`/`p_dch` ties, already IMPLY
`soc_s[t] == soc_1[t]` for every `t` — the former explicit soc rows were exactly
linearly dependent, and (S−1)·T redundant equalities per battery are a needless
interior-point conditioning hazard. `Deferrable` is DELIBERATELY excluded from this tie
(not first-stage in this builder).

The objective is the probability-weighted sum
`Σ_s probabilities[s]·(ctx_s.meta[:objective] − Σ_t λ₀[t]·p_import_s[t])`. The solve is
routed through [`solve_with_retry!`](@ref)`(model; dual = true)` (WR-08 fix, phase-22
review: the escalating Clarabel-conditioning ladder — attributes-only, build-once
preserved, STRICT `assert_solved!` gate — because this solve is empirically known to sit
on a convergence knife-edge: a reasonable probability vector can trip `ALMOST_OPTIMAL`
under the default `tol_gap_abs/rel = 5e-10`); the deliberately-nonconvex cross-check
path (`allow_local = true`) keeps a direct `assert_solved!(...; allow_local = true)`
call. If a solve STILL fails `ALMOST_OPTIMAL` after the ladder, the caller's first knob
is `optimizer = select_optimizer(SOCP(); tol_gap_abs = ..., tol_gap_rel = ...)` (loosen
toward the factory's 1e-8 base). After the gated solve, the PF-04 exactness gate
`assert_socp_exact!` runs ONCE PER SCENARIO (D-06 — never aggregated, never a new
certificate) whenever that scenario stashed a squared-current `:l`, recording each
scenario's own `maxgap` into `socp_maxgap`. THEN `assert_battery_complementarity!` runs
once per scenario (App. C, applied identically to every scenario's tied battery copy by
construction). ONLY THEN are duals read: `dadp[s] = dual.(balance_p_s[priced, :]) ./ probabilities[s]` (D-05 de-scaling — no sign flip; `priced = scenario_aggs[1][1].bus`) is
the PRIMARY per-scenario price output; `expected_dadp = Σ_s probabilities[s]·dadp[s]` is
an explicitly-named DERIVED summary (D-07) — never a constraint-backed price primitive.

# Boundary guards (mirror `solve_welfare`'s ordering + `Scenario`'s own guard style)

Throws `ArgumentError` on: empty `scenario_aggs`; `length(probabilities) != S`; any
non-positive probability; `sum(probabilities)` not `≈ 1` (`atol = 1e-8`); `length(λ₀) != T`; a structural mismatch between `scenario_aggs[s]` and `scenario_aggs[1]` — differing
aggregator count, differing bus at any aggregator index, differing DEVICE COUNT within
any aggregator, or a differing DEVICE TYPE at any device index (WR-03 fix, phase-22
review: without the per-device check, a reordered/substituted device either crashed
confusingly mid-tie or — if scenario 1's device at that index is a non-battery while
scenario s's is a battery — silently left scenario s's battery UNTIED, i.e. clairvoyant
recourse); or any aggregator bus outside `1:length(feeder.buses)`.

Returns a `NamedTuple` `(; model, ctxs, probabilities, welfare, dadp, expected_dadp, socp_maxgap)` where `ctxs::Vector{ModelContext}`, `dadp::Vector{Vector{Float64}}` (one
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
    # at the SOCP() factory's base `tol_gap=1e-8`, this left a low-probability scenario's
    # cone residual measurably (though not structurally) short of tight on a near-lossless
    # 2-bus fixture (5.6e-6, ratio 5.6). `tol_gap_abs/rel = 5e-10` resolves it (→ 4.8e-8)
    # WITHOUT touching the PF-04 exactness GATE's own tolerance — a convergence-precision
    # fix, not a gate weakening. `5e-10` (not a more aggressive `1e-10`) was chosen after
    # SWEEPING candidates on BOTH this near-lossless fixture AND a separate, more-lossy
    # (`r=x=0.05`) 3-bus fixture (Task 2's own D-06 test): `1e-10` exactly trips
    # `ALMOST_OPTIMAL`/`NEARLY_FEASIBLE_POINT` on the lossier feeder (too tight for
    # Clarabel's interior-point to reach cleanly), while every value in `[3e-10, 9e-10]`
    # converges `OPTIMAL` on BOTH fixtures — `5e-10` sits comfortably inside that measured
    # common window. QP()/other classes are untouched (their `select_optimizer` methods
    # take no keyword overrides).
    optimizer = (
        problem_class(pf) isa SOCP ?
        select_optimizer(problem_class(pf); tol_gap_abs = 5e-10, tol_gap_rel = 5e-10) :
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
        ArgumentError("probabilities has length $(length(probabilities)), expected S=$S"),
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
            # WR-03 fix (phase-22 review): DEVICE-COMPOSITION congruence, per this
            # docstring's own promise. The tie walk below pairs
            # ctxs[s].meta[:agg_device_vars][bus][idx] blindly against scenario 1's idx,
            # so a composition mismatch either crashes confusingly (BoundsError /
            # 'no field p_ch') or — worst — SILENTLY skips a tie: if scenario 1's device
            # at idx is a non-battery while scenario s's is a battery, the
            # `haskey(v1, :soc0) || continue` marker never fires and scenario s's battery
            # becomes a scenario-specific (clairvoyant) recourse variable, quietly
            # corrupting the two-stage solution, its welfare, and every de-scaled DADP.
            devs1 = scenario_aggs[1][k].devices
            devss = scenario_aggs[s][k].devices
            length(devss) == length(devs1) || throw(
                ArgumentError(
                    "scenario_aggs[$s][$k] has $(length(devss)) devices, expected " *
                    "$(length(devs1)) (device-composition congruence with scenario 1, " *
                    "required so nonanticipativity ties are never mispaired or " *
                    "silently skipped)",
                ),
            )
            for i in 1:length(devs1)
                typeof(devss[i]).name === typeof(devs1[i]).name || throw(
                    ArgumentError(
                        "scenario_aggs[$s][$k].devices[$i] is a " *
                        "$(nameof(typeof(devss[i]))) but scenario_aggs[1][$k]." *
                        "devices[$i] is a $(nameof(typeof(devs1[i]))) — a " *
                        "device-composition mismatch (reordered or substituted device) " *
                        "would mispair the nonanticipativity walk, or silently leave " *
                        "a battery untied (clairvoyant recourse)",
                    ),
                )
            end
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
        balance_p_s =
            @constraint(model, [j = 1:Np, t = 1:T], ctx_s.residuals[:Rp][j, t] == 0)
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
                # WR-09 fix (phase-22 review): NO soc tie — it was EXACTLY linearly
                # dependent on constraints already in the model. Every scenario copy of
                # the same physical device shares the same η and the same soc0 Parameter
                # value, and each copy carries its own soc[1] == soc0 initial condition
                # plus the recursion soc[t+1] = soc[t] + η·p_ch[t] − p_dch[t]/η; given
                # the p_ch/p_dch ties above, soc_s[t] == soc_1[t] for every t is IMPLIED.
                # The former (S−1)·T·(#batteries) redundant equality rows made the
                # equality block rank-deficient — a classic interior-point KKT
                # conditioning hazard, and a plausible aggravating factor in this phase's
                # two convergence-precision battles (the tol_gap knife-edge and the
                # literate page's ALMOST_OPTIMAL probability-vector sensitivity).
                # Post-solve soc agreement across scenarios is pinned by a regression
                # testitem (test_stochastic_welfare.jl). NOTE: this implication assumes
                # what congruent-scenario input means physically — the SAME battery
                # (same η/soc0) with different exogenous DATA per scenario; the WR-03
                # guard enforces type congruence, and passing per-scenario batteries
                # with differing η/soc0 was never meaningful two-stage input (the old
                # soc tie made it infeasible; now soc would simply follow each copy's
                # own — still tied — schedule).
                # WR-04 fix (phase-22 review): a FourQuadBESS's reactive dispatch q is
                # part of the BATTERY's own day-ahead schedule and therefore first-stage
                # under D-03 ("battery schedule is first-stage, shared across scenarios")
                # — leaving it untied made the tie claim true only for the active-power
                # half of the device, an undocumented partial first-stage. WR-03's
                # device-TYPE congruence guard guarantees haskey(vs,:q) == haskey(v1,:q)
                # at every tied index. PVBattery carries no :q and is unaffected.
                if haskey(v1, :q)
                    @constraint(model, [t = 1:T], vs.q[t] == v1.q[t])
                end
            end
        end
    end

    # Probability-weighted extensive-form welfare objective.
    @objective(
        model,
        Max,
        sum(
            probabilities[s] * (
                ctxs[s].meta[:objective] -
                sum(λ₀[t] * ctxs[s].meta[:p_import][t] for t in 1:T)
            ) for s in 1:S
        )
    )

    # OPTIMAL gate: never read a dual (price) before a trusted solve. WR-08 fix
    # (phase-22 review): the extensive form is the ONE solve empirically known to sit on
    # the tol_gap knife-edge in both directions (5e-10 was fixture-tuned on two tiny
    # feeders, and the phase's own literate page then tripped ALMOST_OPTIMAL on a
    # perfectly reasonable probability vector at :ieee13/T=9), so it is routed through
    # solve_with_retry! — the escalating Clarabel-conditioning ladder (Phase 10) built
    # for exactly this failure shape. The ladder mutates ONLY optimizer attributes
    # (never a variable/constraint — build-once preserved) and its gate IS
    # assert_solved! (STRICT, dual = true), so nothing about the trust discipline
    # weakens. solve_with_retry! deliberately has no allow_local passthrough, so the
    # deliberately-nonconvex cross-check path (allow_local = true, e.g. an Ipopt
    # re-solve) keeps the direct assert_solved! call, byte-identical to before.
    if allow_local
        assert_solved!(model; dual = true, allow_local = true)
    else
        solve_with_retry!(model; dual = true)
    end

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
    dadp =
        [dual.(ctxs[s].constraints[:balance_p][priced, :]) ./ probabilities[s] for s in 1:S]

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

# D-09's out-of-sample harness (STOCH-03) — a SEPARATE, smaller build-once model than the
# S-scenario extensive form above.
#
# WHY A SEPARATE MODEL, NOT THE IN-SAMPLE ONE (RESEARCH.md Pattern 5): the extensive-form
# `build_stochastic_welfare` model above ties S in-sample scenarios' battery schedules
# together via nonanticipativity equality constraints and reads its own S-scenario
# objective/duals; re-slotting a held-out scenario INTO that same model would either
# require adding a genuinely (S+1)-th scenario block (rebuilding, defeating build-once) or
# mutating an existing scenario's data mid-tie (corrupting the in-sample optimum the
# held-out gap is measured AGAINST). Instead, `StochasticOosHarness` is a wholly separate,
# single-scenario, `solve_welfare`-shaped model: its network/device layer is built EXACTLY
# ONCE, and every held-out re-solve only re-targets Parameters (`Ppv_param`/`Pdc_param`/
# `Tout_param`) plus the caller-supplied in-sample optimum via anonymous per-step PIN
# Parameters on `p_ch`/`p_dch` — never `soc` itself (App. C dominance already forces
# `p_ch·p_dch = 0`; pinning `soc` directly would double-constrain the SAME recursion the
# device's own `soc[1] == soc0` IC + recursion already drives once `p_ch`/`p_dch` are
# pinned). This mirrors `build_mpc_window`'s own anonymous
# `@variable(model, base_name = ..., set = Parameter(...))` + `@constraint(model, v.soc[H]
# == term)` idiom (`src/models/mpc_window.jl`), generalized from a single terminal target
# to the FULL per-step `p_ch`/`p_dch` trajectory. `solve_stochastic_oos_step!` is a
# one-line `solve_with_retry!` delegation with `dual = false` — this harness never reports
# a per-scenario DADP (STOCH-03's scope is the realized welfare only, per this plan's own
# boundary against STOCH-02's in-sample pricing).

"""
    StochasticOosHarness{F}

The built-ONCE out-of-sample re-solve harness (STOCH-03, D-09): a SEPARATE, single-scenario,
`solve_welfare`-shaped model whose first-stage battery controls are Parameter-PINNED to a
caller-supplied in-sample optimum, and whose PV/demand/ambient inputs re-slide per held-out
scenario via `set_parameter_value`/`set_parameter_value.` — built EXACTLY ONCE, never
rebuilt across held-out re-solves.

# Fields

  - `model::Model` — the welfare-shaped harness model, built ONCE via
    `select_optimizer(problem_class(pf))` (formulation-generic, mirrors [`MpcWindow`](@ref));
    re-solved via `set_parameter_value`/`set_parameter_value.` + `optimize!` only, never
    rebuilt.
  - `ctx::ModelContext` — the shared, single-scenario context.
  - `agg_bus::Int` — the first aggregator's bus (`aggregators[1].bus`), mirroring
    `MpcWindow`'s DADP-reporting convention (unused here since `dual = false`, kept for
    introspection parity).
  - `feeder::F` — the network the harness is built on.
  - `p_import::Vector{VariableRef}` — the frontier active exchange `p_import[t]`, NEVER
    wrapped in a `Parameter` (Pitfall 2) — the objective's `λ₀` term is fixed at build time
    since this harness's `λ₀` never changes across held-out re-solves (unlike `MpcWindow`'s
    per-window slide).
  - `battery_pins::Vector{<:NamedTuple}` — one entry per battery-like device (any device
    whose returned `vars` carries `:soc0`): `(; bus::Int, pin_p_ch, pin_p_dch)`, the
    per-step PIN `Parameter`s tying that device's `p_ch[t]`/`p_dch[t]` to the caller-supplied
    in-sample optimum (`p_ch[t] == pin_p_ch[t]`, `p_dch[t] == pin_p_dch[t]`) — `soc` is
    NEVER pinned directly. For a device carrying a reactive dispatch (`FourQuadBESS`;
    WR-04 fix, phase-22 review) the entry additionally carries `pin_q` (`q[t] == pin_q[t]`): q is first-stage under D-03, so the held-out re-score pins the FULL
    committed schedule, active AND reactive.
  - `ppv_handles::Vector{<:NamedTuple}` — one entry per PV-CARRYING battery device
    (`PVBattery` — CR-01 fix: `FourQuadBESS` carries no `Ppv_param` and gets NO entry
    here, while still being pinned via `battery_pins`): `(; bus::Int, Ppv_param)`, the
    device's own PV-availability Parameter (re-slid per held-out scenario).
  - `tout_handles::Vector{<:NamedTuple}` — one entry per device carrying an ambient-
    temperature Parameter (`Thermostatic`, and generally any device with `:Tout_param`):
    `(; bus::Int, Tout_param)`.
  - `agg_pdc_handles::Vector{<:NamedTuple}` — one entry per aggregator: `(; bus::Int, Pdc_param)`, the per-step inelastic-demand forecast Parameter (re-slid per held-out
    scenario).
"""
struct StochasticOosHarness{F}
    model::Model
    ctx::ModelContext
    agg_bus::Int
    feeder::F
    p_import::Vector{VariableRef}
    battery_pins::Vector{<:NamedTuple}
    ppv_handles::Vector{<:NamedTuple}
    tout_handles::Vector{<:NamedTuple}
    agg_pdc_handles::Vector{<:NamedTuple}
end

"""
    build_stochastic_oos_harness(feeder, pf::AbstractPowerFlow,
        aggregators::AbstractVector{<:Aggregator};
        T::Int, λ₀::AbstractVector{<:Real},
        optimizer = select_optimizer(problem_class(pf)), allow_export::Bool = false)
        -> StochasticOosHarness

Build the fixed-horizon `[t=1:T]` out-of-sample re-solve harness EXACTLY ONCE (STOCH-03,
D-09), mirroring [`build_mpc_window`](@ref)'s build-once SHAPE:

 1. Boundary guards (mirror `build_mpc_window`): empty `aggregators`, `T < 1`,
    `length(λ₀) != T`, or an aggregator bus outside `1:length(feeder.buses)` each throw
    `ArgumentError` before any model assembly.
 2. `model = Model(select_optimizer(problem_class(pf)))` — formulation-generic, never
    hardcoding `SOCP()`. Registers the same SOC→nonconvex-quad cross-solver bridges as
    `solve_welfare`/`build_mpc_window`.
 3. `contribute!(pf, ctx, feeder; T)` — VERBATIM reuse of the validated power-flow
    builder, called EXACTLY ONCE (this harness never re-`contribute!`s, so it never needs
    `JuMP.unregister`, unlike the S-scenario loop in `build_stochastic_welfare`).
 4. A frontier `p_import[t=1:T]` (NAMED form — safe here, this model is built exactly
    once): free-sign when `allow_export = true`, import-only (`≥ 0`) otherwise; injected
    into `:Rp[feeder.root]`. `reactive = haskey(ctx.residuals, :Rq)` is captured
    IMMEDIATELY after step 3, before any aggregator write; when `true`, a free-sign
    `q_import[t=1:T]` is built the same way.
 5. Every aggregator `contribute!`s its own devices; each aggregator's `Pdc_param` handle
    is captured into `agg_pdc_handles`.
 6. The residuals are closed via the NAMED single-build form and registered under
    `:balance_p`/`:balance_q`.
 7. `ctx.meta[:agg_device_vars]` is walked: every battery-like device (`haskey(v, :soc0)` — `PVBattery`/`FourQuadBESS`) gets TWO anonymous per-step PIN `Parameter`s
    defaulting to the benign literal `0.0` for every `t` (mirrors `build_mpc_window`'s own
    "the caller ALWAYS calls `set_parameter_value` before the first solve" convention):
    `pin_p_ch`/`pin_p_dch`, tied via `p_ch[t] == pin_p_ch[t]`/`p_dch[t] == pin_p_dch[t]`
    (NEVER `soc` directly — Pattern 5's documented choice: App. C dominance already
    forces `p_ch·p_dch = 0` once `p_ch`/`p_dch` are pinned, so pinning `soc` too would
    double-constrain the same recursion). A device carrying a reactive dispatch `q`
    (`FourQuadBESS`) additionally gets a `pin_q` `Parameter` (`q[t] == pin_q[t]`) —
    WR-04 fix, phase-22 review: q is first-stage under D-03, so the committed schedule
    pinned here is the FULL one, active and reactive. Its `Ppv_param` — IF it carries one (CR-01
    fix: `PVBattery` does; `FourQuadBESS` has no PV Parameter and contributes no entry)
    — is captured into `ppv_handles`, and its `Tout_param` (if any) into `tout_handles`.
    Every OTHER device carrying a `Tout_param` (e.g. `Thermostatic`) also gets a
    `tout_handles` entry.
 8. The REAL objective `ctx.meta[:objective] - Σ_t λ₀[t]·p_import[t]` is built at construction
    time — `λ₀` never changes across held-out re-solves in this harness (unlike
    `MpcWindow`'s per-window `λ₀` slide), so it is NOT a placeholder.

Returns a [`StochasticOosHarness`](@ref). Re-solve via
[`solve_stochastic_oos_step!`](@ref) — never rebuild.
"""
function build_stochastic_oos_harness(
    feeder,
    pf::AbstractPowerFlow,
    aggregators::AbstractVector{<:Aggregator};
    T::Int,
    λ₀::AbstractVector{<:Real},
    optimizer = select_optimizer(problem_class(pf)),
    allow_export::Bool = false,
)
    # Boundary guards FIRST (mirrors build_mpc_window's own ordering).
    isempty(aggregators) &&
        throw(ArgumentError("build_stochastic_oos_harness needs at least one aggregator"))
    T >= 1 || throw(ArgumentError("build_stochastic_oos_harness requires T ≥ 1, got T=$T"))
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))

    N = length(feeder.buses)
    for (k, agg) in enumerate(aggregators)
        1 <= agg.bus <= N || throw(
            ArgumentError("aggregator[$k] bus=$(agg.bus) is outside feeder buses 1:$N"),
        )
    end

    # Formulation-generic factory routing (NEVER hardcode SOCP()).
    model = Model(optimizer)

    # Cross-solver enablement, dormant on the primary Clarabel path (mirrors
    # build_mpc_window/solve_welfare verbatim).
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)

    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder
    ctx.meta[:T] = T

    # VERBATIM power-flow builder reuse — called EXACTLY ONCE (no unregister needed).
    contribute!(pf, ctx, feeder; T = T)

    # WR-03 ordering: captured IMMEDIATELY after the formulation contributes, before any
    # aggregator write (mirrors build_mpc_window/solve_welfare).
    reactive = haskey(ctx.residuals, :Rq)

    # NAMED form is safe here — this model is built exactly once, unlike the anonymous
    # per-scenario frontier build_stochastic_welfare needs to avoid an S-way name collision.
    if allow_export
        @variable(model, p_import[t = 1:T])
    else
        @variable(model, p_import[t = 1:T] >= 0)
    end
    for t in 1:T
        add_to_residual!(ctx, :Rp, feeder.root, t, p_import[t])
    end
    ctx.meta[:p_import] = p_import

    if reactive
        @variable(model, q_import[t = 1:T])   # free-sign reactive frontier import
        for t in 1:T
            add_to_residual!(ctx, :Rq, feeder.root, t, q_import[t])
        end
        ctx.meta[:q_import] = q_import
    end

    # Aggregators: net active/reactive injections + utility. Capture each aggregator's
    # Pdc_param handle.
    agg_pdc_handles = NamedTuple[]
    for agg in aggregators
        res = contribute!(agg, ctx; T = T)
        push!(agg_pdc_handles, (; bus = agg.bus, Pdc_param = res.Pdc_param))
    end

    # Close :Rp always; :Rq only when the formulation provides a reactive channel — NAMED
    # single-build form (safe here, this model is built exactly once).
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

    # Walk ctx.meta[:agg_device_vars] to populate battery_pins/ppv_handles/tout_handles.
    battery_pins = NamedTuple[]
    ppv_handles = NamedTuple[]
    tout_handles = NamedTuple[]
    if haskey(ctx.meta, :agg_device_vars)
        for (bus, varlist) in ctx.meta[:agg_device_vars]
            for v in varlist
                if haskey(v, :soc0)
                    # Battery-like device (PVBattery/FourQuadBESS): TWO anonymous per-step
                    # PIN Parameters, defaulting to the benign literal 0.0 (mirrors
                    # build_mpc_window's own "always overridden before the first solve"
                    # convention). soc is NEVER pinned directly (Pattern 5).
                    pin_p_ch = @variable(model, [t = 1:T], set = Parameter(0.0))
                    pin_p_dch = @variable(model, [t = 1:T], set = Parameter(0.0))
                    @constraint(model, [t = 1:T], v.p_ch[t] == pin_p_ch[t])
                    @constraint(model, [t = 1:T], v.p_dch[t] == pin_p_dch[t])
                    if haskey(v, :q)
                        # WR-04 fix (phase-22 review): a FourQuadBESS's reactive dispatch
                        # q is first-stage under D-03 (tied across in-sample scenarios by
                        # build_stochastic_welfare), so an HONEST out-of-sample re-score
                        # of the committed schedule must pin q too — leaving it free
                        # would grant the held-out solve reactive recourse the in-sample
                        # commitment never had. The 0.0 default (q = 0) is always inside
                        # the device's own apparent-power cone.
                        pin_q = @variable(model, [t = 1:T], set = Parameter(0.0))
                        @constraint(model, [t = 1:T], v.q[t] == pin_q[t])
                        push!(battery_pins, (; bus, pin_p_ch, pin_p_dch, pin_q))
                    else
                        push!(battery_pins, (; bus, pin_p_ch, pin_p_dch))
                    end
                    # CR-01 fix (phase-22 review): only a PV-carrying battery (PVBattery)
                    # returns a `Ppv_param` handle — `FourQuadBESS.contribute!` returns
                    # `vars = (; p_ch, p_dch, soc, q, soc0)` with NO PV Parameter at all
                    # (it grid-charges; there is nothing to re-slide per held-out scenario).
                    # Reading `v.Ppv_param` unconditionally crashed the harness build with
                    # `type NamedTuple has no field Ppv_param` on a FourQuadBESS, a device
                    # this function's own contract names as supported. Guarded, a
                    # FourQuadBESS still gets its p_ch/p_dch PINNED above — it simply
                    # contributes no `ppv_handles` entry.
                    if haskey(v, :Ppv_param)
                        push!(ppv_handles, (; bus, Ppv_param = v.Ppv_param))
                    end
                    if haskey(v, :Tout_param)
                        push!(tout_handles, (; bus, Tout_param = v.Tout_param))
                    end
                elseif haskey(v, :Tout_param)
                    # Thermostatic case: no :soc0, but carries its own ambient Parameter.
                    push!(tout_handles, (; bus, Tout_param = v.Tout_param))
                end
            end
        end
    end

    # REAL objective (not a placeholder — λ₀ never changes across held-out re-solves in
    # this harness, unlike MpcWindow's per-window λ₀ slide).
    @objective(model, Max, ctx.meta[:objective] - sum(λ₀[t] * p_import[t] for t in 1:T))

    return StochasticOosHarness(
        model,
        ctx,
        aggregators[1].bus,
        feeder,
        p_import,
        battery_pins,
        ppv_handles,
        tout_handles,
        agg_pdc_handles,
    )
end

"""
    solve_stochastic_oos_step!(h::StochasticOosHarness; max_attempts::Int = 4) -> Model

Re-solve the built-ONCE [`StochasticOosHarness`](@ref) `h` via [`solve_with_retry!`](@ref)
— a ONE-LINE delegation that NEVER adds a variable or constraint to `h.model`. `dual = false`: this harness never reports a per-scenario DADP (STOCH-03's scope is the realized
welfare only). Callers mutate `h.battery_pins`/`h.ppv_handles`/`h.tout_handles`/
`h.agg_pdc_handles` via `set_parameter_value`/`set_parameter_value.` BEFORE calling this
function.
"""
function solve_stochastic_oos_step!(h::StochasticOosHarness; max_attempts::Int = 4)
    return solve_with_retry!(h.model; max_attempts = max_attempts, dual = false)
end

export StochasticOosHarness, build_stochastic_oos_harness, solve_stochastic_oos_step!
