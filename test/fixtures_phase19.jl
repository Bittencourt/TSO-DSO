# test/fixtures_phase19.jl
#
# Seam: Phase-19 acceptance-gate fixture (MESH-04/MESH-05). A TestItems `@testmodule` that
# `test/test_admm_reactive.jl`'s NEW `:live` items consume via `setup = [Phase6Fixtures,
# Phase19Fixtures]` (Phase6Fixtures MUST be listed FIRST in every consuming testitem's `setup`
# array — TestItemRunner evaluates `option_setup` entries IN ORDER, so `Phase6Fixtures` is
# already a sibling submodule of the shared test-setup parent by the time this module's OWN
# `using ..Phase6Fixtures` runs; reversing the order would throw an `UndefVarError`).
#
# WHY THIS DEPARTS FROM THE PROJECT'S "self-contained @testmodule" CONVENTION (see
# fixtures_phase6.jl/fixtures_phase7.jl's own header comments): those modules avoid a
# cross-`@testmodule` load-time dependency by taking `feeder` as an ARGUMENT and duplicating
# any small shared helper locally. This module is EXPLICITLY instructed (plan 19-08, task 1) to
# reuse `Phase6Fixtures.two_bus_feeder()`/`SEED_2BUS`/`LOAD_SCALE_2BUS`/`PV_SCALE_2BUS`/
# `RHO_2BUS`/`BATT_λ_*`/`temperature_profile()` DIRECTLY rather than redefine them — the whole
# point is that the `:live` cross-validation runs on the IDENTICAL 2-bus fixture the project's
# existing ADMM cross-validation tests already anchor on, never a re-derived copy that could
# silently drift. `using ..Phase6Fixtures` (a relative import to the SIBLING submodule under
# the shared TestItemRunner setup-module parent) is the mechanism that makes this safe: verified
# directly against `TestItemRunner.jl`'s `ensure_evaled`/`run_testitem` source this session
# (`Core.eval(test_setup_module_set.setupmodule, :(module $(name) end))` — every `@testmodule`,
# including this one, is eval'd as a child of the SAME shared parent, so a sibling reference
# resolves once that sibling has ALREADY been `ensure_evaled`).
#
# CONE-NAME-COLLISION: RESOLVED AT SOURCE (WR-01, phase-19 code review; originally
# deferred-items.md / plan 19-07's finding). `FourQuadBESS.contribute!`'s device-level
# apparent-power cone is now ANONYMOUS (it claims no JuMP object-dictionary name), so a
# `FourQuadBESS`-bearing aggregator set composes directly with `ConvexBranchFlow`'s named
# network `:cone` in ONE shared model — the former test-only `JuMP.unregister(model, :cone)`
# workaround this file carried is retired. `centralized_welfare_4q` below is KEPT (unchanged
# in behavior): it reproduces `solve_welfare`'s exact step sequence (thesis eq. 3.38) using
# ONLY `solve_welfare`'s own PUBLIC seams (`contribute!`, `add_to_residual!`,
# `register_constraint!`, `assert_solved!`, `assert_socp_exact!`,
# `assert_battery_complementarity!`), and the phase's D-14 measured cross-validation
# tolerances below were pinned against THIS exact replica — swapping it for a direct
# `solve_welfare` call would invalidate that measurement provenance for zero test value.
#
# MEASUREMENT-BEFORE-GOLDEN (D-14, threat T-19-18): the welfare/λ/μ cross-validation tolerances
# Task 2 pins were MEASURED on this exact fixture (`build_two_bus_aggregators_4q` at its
# documented parameters below) across 5 seeds (`SEED_2BUS .. SEED_2BUS+4`), comparing
# `centralized_welfare_4q` against `solve_admm(...; reactive_consensus = :live)`:
#
#   seed        |Δwelfare|        |Δλ|₂ (T=24)      |Δμ|₂ (T=24)     |λ_c|₂    μ_c/μ_admm norms
#   20260719    2.191e-5          1.312e-5           1.338e-8         19.597   ~1.6e-8 / ~1.7e-8
#   20260720    2.368e-5          1.519e-5           1.028e-8         19.596   ~2.1e-8 / ~1.4e-8
#   20260721    2.188e-5          1.426e-5           6.943e-9         19.596   ~1.6e-8 / ~1.4e-8
#   20260722    1.586e-5          1.065e-5           1.242e-8         19.596   ~9.7e-9 / ~1.3e-8
#   20260723    2.003e-5          1.405e-5           1.610e-8         19.596   ~1.6e-8 / ~1.9e-8
#   max         2.368e-5          1.519e-5           1.610e-8
#
# (`obj_c ≈ -483.x` across seeds — the Thermostatic discomfort cost dominates, an expected
# feature of this fixture's own parametrization, not a Phase-19 concern.) Every entry converges
# in `iters = 2` — this near-lossless/interior/uncongested fixture (deliberately, per
# `Phase6Fixtures`'s own design) is warm-started essentially AT its converged point (RESEARCH
# Pattern: `λ` warm-starts at `-λ₀`), so a fast, small-iteration convergence is the EXPECTED,
# correct outcome here, not evidence of a trivial/degenerate solve — `solve_admm`'s own
# fail-loud maxiter cap (never silently returning early) is what makes a 2-iteration convergence
# trustworthy.
#
# D-03 DEGENERACY, CONFIRMED EMPIRICALLY (not merely cited): `|Δμ|` sits at ~1e-8, essentially
# AT Clarabel's own dual-accuracy noise floor — both the centralized `dual(:balance_q)` and the
# `:live` internal `μq`-derived `μ` converge to ≈0 on this near-lossless (`r=x=1e-3`),
# SMAX_NO_LIMIT branch: there is no genuine reactive network cost to price here (an HONEST
# feature of the near-lossless/uncongested 2-bus fixture, exactly as `solve_admm.jl`'s own D-03
# docstring note anticipates). The chosen tolerances below (Task 2) are each independently
# derived from THESE measured numbers, with a ≈3-6× safety margin over the observed max gap —
# NEVER one shared constant, and the μ tolerance is deliberately an ABSOLUTE (not relative) floor
# since μ itself is ≈0 (a relative comparison against ≈0 is meaningless):
#
#   welfare : atol = 1e-4   (measured max 2.368e-5, ≈4.2× margin)
#   λ       : atol = 5e-5   (measured max 1.519e-5, ≈3.3× margin)
#   μ       : atol = 1e-7   (measured max 1.610e-8, ≈6.2× margin; ABSOLUTE, μ is degenerate ≈0)
#
# FIXTURE SCALE (mirrors `LOAD_SCALE_2BUS = 0.02`/`PV_SCALE_2BUS = 0.005`'s own sizing
# discipline): `Pch_max = Pdch_max = 0.02` sits at the SAME magnitude as the fixture's inelastic
# demand (not `PVBattery`'s own `Pmax = 0.1`, which — empirically verified this session, an
# earlier 10×-larger candidate — let the 4Q-BESS's discharge occasionally FLIP bus 2 into a
# net-EXPORTER at a negative effective price, tripping the HONEST D-08 grid-charging boundary
# certificate (`assert_4q_complementarity!`) rather than staying comfortably interior). `Smax =
# 0.03` gives `√(Smax²−Pch_max²) ≈ 0.0224` of REACTIVE headroom at the ACTIVE bound — comfortably
# inside the apparent-power cone at every hour, keeping the 2-bus solve INTERIOR (never binding
# `Smax`, matching this fixture's own "interior, uncongested" design intent). `Emin/Emax/soc0 =
# 0/0.08/0.04` is a plain 4× headroom band around the `Pch_max`-scaled throughput, mirroring the
# existing `PVBattery`'s own `Emax ≈ 2×Pmax` discipline. `η = 0.95`, `Δt = 1.0` (hourly, matches
# `T = 24`) and the SAME strict `λ_min < λ_med < λ_max` triple (`Phase6Fixtures.BATT_λ_*`) as the
# fixture's own `PVBattery` — required by the constructor (D-05) and consistent with reusing one
# App. C price triple across every battery-like device in this fixture.

@testmodule Phase19Fixtures begin
    using TSODSO
    using JuMP
    using ..Phase6Fixtures

    # FourQuadBESS device-scale constants for the 2-bus + 4Q-BESS variant (see the file header's
    # "FIXTURE SCALE" note for the derivation of each value).
    const BESS_PCH_MAX = 0.02
    const BESS_PDCH_MAX = 0.02
    const BESS_SMAX = 0.03
    const BESS_EMIN = 0.0
    const BESS_EMAX = 0.08
    const BESS_SOC0 = 0.04

    """
        build_two_bus_aggregators_4q(feeder; seed=Phase6Fixtures.SEED_2BUS) -> Vector{<:Aggregator}

    Mirrors [`Phase6Fixtures.build_two_bus_aggregators`](@ref) EXACTLY (same
    Thermostatic/Deferrable/PVBattery triple, same seeded `generate_profiles` draw at
    `seed + bus`) PLUS one [`FourQuadBESS`](@ref) member at the SAME bus (MESH-04/05), on the
    SAME [`Phase6Fixtures.two_bus_feeder`](@ref). Seeded ⇒ reproducible; takes `feeder` as an
    argument (never calls `Phase6Fixtures.two_bus_feeder` at this module's load time).
    """
    function build_two_bus_aggregators_4q(feeder; seed::Integer = Phase6Fixtures.SEED_2BUS)
        bus = 2
        prof = generate_profiles(seed = seed + bus, T = Phase6Fixtures.T)
        Ppv = Float64[Phase6Fixtures.PV_SCALE_2BUS * p for p in prof.pv]
        Pdc = Float64[Phase6Fixtures.LOAD_SCALE_2BUS * d for d in prof.demand]

        therm = Thermostatic(
            bus,
            0.2,
            0.05,
            15.0,
            30.0,
            22.0,
            0.0,
            1.0,
            0.5,
            Phase6Fixtures.temperature_profile(),
        )
        defer = Deferrable(bus, 8, 16, 1.0, 0.5, 0.5)
        batt = PVBattery(
            bus,
            0.95,
            1.0,
            0.1,
            0.0,
            0.2,
            0.1,
            Phase6Fixtures.BATT_λ_MIN,
            Phase6Fixtures.BATT_λ_MED,
            Phase6Fixtures.BATT_λ_MAX,
            Ppv,
        )
        bess = FourQuadBESS(
            bus,
            0.95,
            1.0,
            BESS_PCH_MAX,
            BESS_PDCH_MAX,
            BESS_SMAX,
            BESS_EMIN,
            BESS_EMAX,
            BESS_SOC0,
            Phase6Fixtures.BATT_λ_MIN,
            Phase6Fixtures.BATT_λ_MED,
            Phase6Fixtures.BATT_λ_MAX,
        )
        return [Aggregator(bus, 0.90, AbstractDevice[therm, defer, batt, bess], Pdc)]
    end

    """
        centralized_welfare_4q(feeder, pf::ConvexBranchFlow, aggregators; T, λ₀,
                                allow_export=true, rtol_exact=1e-4, atol_exact=1e-5)
            -> (ctx, objective, balance_p, balance_q_or_nothing)

    A TEST-ONLY replica of [`solve_welfare`](@ref)'s exact step sequence (thesis eq. 3.38),
    written entirely against `solve_welfare`'s own PUBLIC seams. Originally required because a
    `FourQuadBESS`-bearing `aggregators` crashed `solve_welfare` on the `:cone` name collision;
    that collision is FIXED at source (WR-01 — the device cone is anonymous now), and this
    replica is KEPT because the phase's D-14 measured cross-validation tolerances were pinned
    against it (see this file's header comment). Every step mirrors `solve_welfare` verbatim:
    the free-sign frontier
    `p_import`/`q_import` (added ONLY when the formulation provides a reactive channel, WR-03),
    closing `:balance_p`/`:balance_q`, `assert_solved!` before any dual read, the PF-04
    `assert_socp_exact!` gate (data-driven on `:l`'s presence, BEFORE any dual read), and the
    mandatory App. C `assert_battery_complementarity!` post-solve check (`τ`
    PROBLEM-CLASS-AWARE, mirroring `solve_welfare`'s own default).

    Returns `(ctx, objective_value(model), balance_p, balance_q)` — `balance_q` is `nothing`
    when the formulation has no reactive channel (mirrors `solve_welfare`'s own `reactive`
    branching); the caller reads `dual.(balance_p[bus, :])` / `dual.(balance_q[bus, :])`
    directly, exactly as `solve_welfare`'s own callers do.
    """
    function centralized_welfare_4q(
        feeder,
        pf::ConvexBranchFlow,
        aggregators;
        T::Int,
        λ₀,
        allow_export::Bool = true,
        rtol_exact::Real = 1e-4,
        atol_exact::Real = 1e-5,
    )
        isempty(aggregators) &&
            throw(ArgumentError("centralized_welfare_4q needs at least one aggregator"))
        length(λ₀) == T ||
            throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))

        optimizer = select_optimizer(problem_class(pf))
        model = Model(optimizer)
        JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
        JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)

        ctx = ModelContext(model)
        ctx.meta[:feeder] = feeder
        ctx.meta[:T] = T

        Np = length(feeder.buses)
        for (k, agg) in enumerate(aggregators)
            1 <= agg.bus <= Np ||
                throw(ArgumentError("aggregator[$k] bus=$(agg.bus) is outside feeder buses 1:$Np"))
        end

        contribute!(pf, ctx, feeder; T = T)

        reactive = haskey(ctx.residuals, :Rq)

        for agg in aggregators
            contribute!(agg, ctx; T = T)
        end

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
            @variable(model, q_import[t = 1:T])
            for t in 1:T
                add_to_residual!(ctx, :Rq, feeder.root, t, q_import[t])
            end
            ctx.meta[:q_import] = q_import
        end

        @constraint(model, balance_p[j = 1:Np, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
        register_constraint!(ctx, :balance_p, balance_p)
        balance_q = nothing
        if reactive
            @constraint(model, balance_q_[j = 1:Np, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
            register_constraint!(ctx, :balance_q, balance_q_)
            balance_q = balance_q_
        end

        welfare = ctx.meta[:objective] - sum(λ₀[t] * p_import[t] for t in 1:T)
        @objective(model, Max, welfare)

        assert_solved!(model; dual = true, allow_local = false)

        if haskey(ctx.meta, :pf_vars) && haskey(ctx.meta[:pf_vars], :l)
            ctx.meta[:socp_maxgap] = assert_socp_exact!(ctx; rtol = rtol_exact, atol = atol_exact)
        end

        τ_batt = problem_class(pf) isa SOCP ? 1e-3 : 1e-6
        assert_battery_complementarity!(ctx; τ = τ_batt, T = T)

        return ctx, objective_value(model), balance_p, balance_q
    end

    export build_two_bus_aggregators_4q,
        centralized_welfare_4q,
        BESS_PCH_MAX,
        BESS_PDCH_MAX,
        BESS_SMAX,
        BESS_EMIN,
        BESS_EMAX,
        BESS_SOC0
end
