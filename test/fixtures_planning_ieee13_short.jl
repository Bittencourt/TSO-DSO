# test/fixtures_planning_ieee13_short.jl
#
# Seam: bilevel convergence test — the ONE piece of fixture infrastructure the
# convergence test needs: a fresh, short-horizon (`T ∈ [3,6]`)
# `ieee13_modified()` aggregator population where the Benders loop's own natural trial
# range stays mostly inside the feasible-and-exact region,
# PLUS an independently-built monolithic joint-reference solver (a single-shot JuMP
# model representing the SAME integrated problem `solve_stackelberg!` Benders-decomposes,
# built from scratch — never a reuse of `PlanningOracle`/`FollowerLP`/`BendersMaster`,
# as an independent model is required).
#
# CONTRACT (mirrors test/fixtures_ieee13.jl's own convention): this module DEFINES
# functions/constants ONLY — it makes NO top-level solve call. The feeder-consuming
# builders take a `feeder` argument, so nothing here evaluates a not-yet-built network at
# module-load time.
#
# --- TUNING EVIDENCE (measured with JULIA_LOAD_PATH="test:.:@stdlib" julia
# script.jl against the UNMODIFIED `ieee13_modified()`; the raw
# probe transcripts were not kept) ---
#
# Chosen horizon: T = 4 (within the required T ∈ [3,6] range; the
# exact value is a free choice).
#
# Population: PVBattery + Thermostatic ONLY (NEVER `Deferrable` —
# its hardcoded `[8,16]` window does not fit T<16), one aggregator per non-root bus
# (`bus in 2:N`), built from `generate_profiles(seed = 20260718 + bus, T = 4)`. Magnitudes:
# `load_scale=0.01`, `pv_scale=0.03`, `batt_pmax=0.02`, `batt_emax=0.1`, `batt_soc0=0.05`.
# Battery price triple `λ_min=3.8 < λ_med=6.2 < λ_max=8.9` (STRICT — the no-binary
# guarantee, PVBattery's own inner-constructor guard).
#
# NOTE on an earlier exploratory population: an earlier live session
# (conducted against an EARLIER codebase state) measured THIS SAME recipe's
# `z=0` as `MOI.INFEASIBLE` and recommended "retuning" (more PV/battery capacity) to fix
# it. Re-probing THIS SAME recipe against the current codebase state (after the
# exactness/complementarity fixes), `z=zeros(4)` is ALREADY oracle-feasible — no
# magnitude change was needed. This is reported here as a found discrepancy (the
# project's own exactness-gate/complementarity-gate fixes landed between that
# probe and this fixture), not silently reconciled: the CONFIRMATION below is
# a freshly re-run probe, not an assumption carried over from the earlier session.
#
# Direct probe (`solve_planning_oracle!(oracle, zeros(4))`):
#     cost = -609.0471557105552, maxgap = 2.2407826061415185e-10  (SOCP EXACT)
# ⇒ z = zeros(T) is CONFIRMED oracle-feasible (and exact) on the UNMODIFIED
# `ieee13_modified()` with this population.
#
# Sweep map (uniform `z` pin over all T=4 hours, same population; head branch
# `smax=0.0686` pu is the feeder's single thermal limit, `src/data/ieee13.jl`):
#
# | z (pu/hr)        | Outcome                                                          |
# |------------------|-------------------------------------------------------------------|
# | -0.10, -0.08      | `MOI.INFEASIBLE` (export capacity-limited — battery/PV magnitude, NOT network) |
# | -0.05 .. 0.05     | OK, SOCP EXACT (`maxgap` ≈ `1.4e-9`–`3.3e-8`)                      |
# | 0.06              | OK (feasible primal), SOCP **INEXACT** (`maxgap` ratio ≈ 4852× over tolerance — matches the earlier session's measured ratio on this exact recipe) |
# | 0.0686, 0.07      | `MOI.INFEASIBLE` (thermal — the feeder's head-branch `smax` limit)  |
#
# This is the AUTHORITATIVE reference the convergence test's own expectations
# must be checked against (its own `y_max`/`corridor_cap` should keep the master's
# natural box mostly inside the `[-0.05, 0.05]` feasible-and-exact window above).

@testmodule IEEE13ShortHorizonFixtures begin
    using TSODSO: SOCP, solve_with_retry!
    using JuMP, TSODSO

    # Day-ahead short horizon for this fixture (T ∈ [3,6] is required).
    # Exported so items/other fixtures reference
    # `IEEE13ShortHorizonFixtures.T`.
    const T = 4

    # The standard λ₀ (MEM/wholesale price) profile used by every probe/testitem in this
    # module (length T=4, ¢$/kWh-consistent — same convention as fixtures_ieee13.jl's own
    # mem_price_profile, just a 4-hour slice of a similar morning-shoulder magnitude).
    const LAMBDA0 = Float64[6.5, 6.2, 5.9, 5.7]

    """
        house_agg(bus; seed, φ=0.90, load_scale=0.01, pv_scale=0.03,
                  batt_pmax=0.02, batt_emax=0.1, batt_soc0=0.05) -> Aggregator

    One T=4 aggregator (PVBattery + Thermostatic only, never `Deferrable` —
    see the population note in the file header) at `bus`, fed by a seeded `generate_profiles` draw (T=4,
    NOT `IEEE13Fixtures`'s T=24-locked helpers). The battery holds the STRICT App. C
    price triple `λ_min=3.8 < λ_med=6.2 < λ_max=8.9` (the load-bearing no-binary
    guarantee).
    """
    function house_agg(
        bus;
        seed::Integer,
        φ::Real = 0.90,
        load_scale::Real = 0.01,
        pv_scale::Real = 0.03,
        batt_pmax::Real = 0.02,
        batt_emax::Real = 0.1,
        batt_soc0::Real = 0.05,
    )
        prof = generate_profiles(seed = seed + bus, T = T)
        Ppv = Float64[pv_scale * p for p in prof.pv]
        Pdc = Float64[load_scale * d for d in prof.demand]
        therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, fill(25.0, T))
        batt = PVBattery(bus, 0.95, 1.0, batt_pmax, 0.0, batt_emax, batt_soc0, 3.8, 6.2, 8.9, Ppv)
        return Aggregator(bus, φ, [therm, batt], Pdc)
    end

    """
        population(feeder; seed=20260718) -> Vector{<:Aggregator}

    One [`house_agg`](@ref) per non-root bus (`bus in 2:N`) on `feeder` — the
    T=4, tuned-feasible-at-z=0 IEEE-13 population documented in this file's own header
    comment. Takes `feeder` as an argument (never calls `ieee13_modified` at module-load
    time, mirroring `fixtures_ieee13.jl`'s own CONTRACT).
    """
    function population(feeder; seed::Integer = 20260718)
        N = length(feeder.buses)
        return [house_agg(bus; seed = seed) for bus in 2:N]
    end

    """
        solve_joint_reference(feeder, aggregators; λ₀, T, c_y, y_max, corridor_cap,
                              x_inv_max, c_inv, c_op) -> NamedTuple

    The INDEPENDENTLY-BUILT monolithic joint-reference solver for the bilevel convergence
    cross-check (NEVER a reuse of `PlanningOracle`/`FollowerLP`/`BendersMaster` —
    independence requirement: "must be an independently built model, not a
    re-use of the Benders subproblems"). Represents the IDENTICAL integrated problem
    `solve_stackelberg!` Benders-decomposes as a SINGLE, non-decomposed JuMP model: builds
    the SAME network (`contribute!(ConvexBranchFlow(), ctx, feeder; T)`) and the SAME
    aggregator population (`contribute!(agg, ctx; T)` loop) `build_planning_oracle`
    (`src/planning/subproblem.jl`) uses, but adds the planning-layer investment/corridor
    variables (`y_inv`, `x_inv`, `z`) and their coupling constraints DIRECTLY, instead of
    splitting them across an oracle/follower/master Benders decomposition.

    `z[t]` is reused directly as BOTH the oracle's frontier import AND the follower's
    delivered flow — they are the SAME physical quantity in the non-decomposed,
    single-planner problem; the `invest_op` constraint (`z[t] <= corridor_cap*x_inv`)
    folds in the follower's own capacity limit (no separate `p_import`/`x_op`).

    # Sign convention (documented here so the convergence test does not have to re-derive it)

    `solve_stackelberg!`'s returned `UB` is a MIN-sense total cost
    `c_y*y + c_inv*x_inv + Σc_op[t]*z[t] - oracle_welfare(z)` (`src/planning/benders.jl`'s
    own docstring). This function's `welfare_total` is the MAX-sense NEGATIVE of that SAME
    quantity at the joint (non-decomposed) optimum:
    `welfare_total = oracle_welfare(z) - c_y*y_inv - c_inv*x_inv - Σc_op[t]*z[t]`.
    The convergence test must therefore compare
    `result.UB ≈ -joint.welfare_total`.

    Also returns `gap = |objective_value − dual_objective_value|` (the joint solve's OWN
    certified duality gap) and `socp_maxgap` (its own cone residual — the solve THROWS via
    `assert_socp_exact!` if the joint relaxation is inexact, so a returned value is an
    exactness-certified optimum; found in review).

    Independence scope (stated plainly): the joint model shares NO
    oracle/follower/master object with the decomposition, but it is assembled from the
    SAME `contribute!` network/device builders, so it validates the DECOMPOSITION
    (cuts, bounds, incumbent tracking), not the formulation itself.
    """
    function solve_joint_reference(
        feeder,
        aggregators;
        λ₀,
        T::Int,
        c_y::Real,
        y_max::Real,
        corridor_cap::Real,
        x_inv_max::Real,
        c_inv::Real,
        c_op::AbstractVector{<:Real},
    )
        length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
        length(c_op) == T ||
            throw(ArgumentError("c_op has length $(length(c_op)), expected T=$T"))
        isempty(aggregators) &&
            throw(ArgumentError("solve_joint_reference needs at least one aggregator"))

        model = Model(select_optimizer(SOCP()))
        ctx = ModelContext(model)
        ctx.feeder = feeder
        ctx.T = T
        ctx.meta[:problem_class] = SOCP()
        contribute!(ConvexBranchFlow(), ctx, feeder; T = T)

        @variable(model, 0 <= y_inv <= y_max)
        @variable(model, 0 <= x_inv <= x_inv_max)
        @variable(model, z[t = 1:T])
        @constraint(model, box_lo[t = 1:T], z[t] >= 0)
        @constraint(model, box_hi[t = 1:T], z[t] <= y_inv)
        @constraint(model, invest_op[t = 1:T], z[t] <= corridor_cap * x_inv)
        for t in 1:T
            add_to_residual!(ctx, :Rp, feeder.root, t, z[t])
        end

    # Ordering note (mirrors build_planning_oracle): capture `reactive` immediately
        # after the formulation contributes, before any aggregator writes.
        reactive = haskey(ctx.residuals, :Rq)
        if reactive
            @variable(model, zq[t = 1:T])
            for t in 1:T
                add_to_residual!(ctx, :Rq, feeder.root, t, zq[t])
            end
        end

        for agg in aggregators
            contribute!(agg, ctx; T = T)
        end

        N = length(feeder.buses)
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

        @objective(
            model,
            Max,
            ctx.objective - sum(λ₀[t] * z[t] for t in 1:T) - c_y * y_inv -
            c_inv * x_inv - sum(c_op[t] * z[t] for t in 1:T)
        )

    # Review finding: `dual = true` so the solver's OWN duality gap is
        # certified and readable, and the joint model checks its OWN cone exactness —
        # otherwise the cross-check would compare one relaxation against another.
        solve_with_retry!(model; dual = true)
        socp_maxgap = assert_socp_exact!(ctx)   # throws if the joint relaxation is inexact

        return (;
            y = value(y_inv),
            x_inv = value(x_inv),
            z = value.(z),
            welfare_total = objective_value(model),
            gap = abs(objective_value(model) - dual_objective_value(model)),
            socp_maxgap,
        )
    end

    export T, LAMBDA0, house_agg, population, solve_joint_reference
end
