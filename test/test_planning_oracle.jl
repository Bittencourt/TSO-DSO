# test/test_planning_oracle.jl
#
# Seam: src/planning/subproblem.jl (PLAN-01/PLAN-02, D-01/D-02/D-04/D-05/D-06/D-07/D-11).
# `PlanningOracle` + `build_planning_oracle` (Task 1) turn the SEAM-01 `z`-pin stub into a
# live, build-once JuMP subproblem carrying a genuine `Parameter`-typed `z[t]` and a named
# `pin[t]: p_import[t] == z[t]` constraint. `solve_planning_oracle!` (Task 2) re-solves it
# via the plan 10-01 retry wrapper and returns the pin's dual `π` (length-T) plus its
# duration-weighted reconciliation `π_s`. Items tagged `[:planning]`, names contain
# "planning" and "oracle" (occursin filter convention, mirrors test_planning_retry.jl /
# test_planning_checkpoint.jl).
#
# z_trial FEASIBILITY NOTE: Phase6Fixtures's real 2-bus aggregator (Thermostatic +
# Deferrable + PVBattery) has only a NARROW feasible import band around its own
# unconstrained free-import optimum (its inelastic demand + bounded device flexibility do
# not tolerate an arbitrary z, e.g. z=0 is INFEASIBLE for this fixture — empirically
# verified this session). Every test below therefore derives its z_trial from the
# network's OWN unconstrained free-import optimum (via the unmodified free path,
# `operational_oracle(...; z = nothing, allow_export = true)`), which is feasible by
# construction, rather than an arbitrary fixed vector.

@testitem "planning oracle: build_planning_oracle guards (empty aggregators, λ₀ length, bus range)" tags =
    [:planning] setup = [Phase6Fixtures] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    T = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()

    # Empty aggregators: no priced load / no objective.
    @test_throws ArgumentError build_planning_oracle(
        feeder,
        LinDistFlow(),
        typeof(aggs)();
        λ₀ = λ₀,
        T = T,
    )

    # λ₀ length mismatch.
    @test_throws ArgumentError build_planning_oracle(
        feeder,
        LinDistFlow(),
        aggs;
        λ₀ = λ₀[1:(end - 1)],
        T = T,
    )

    # Aggregator bus outside 1:length(feeder.buses) (feeder has 2 buses; 99 is out of range).
    out_of_range = [TSODSO.Aggregator(99, 0.9, aggs[1].devices, aggs[1].Pdc)]
    @test_throws ArgumentError build_planning_oracle(
        feeder,
        LinDistFlow(),
        out_of_range;
        λ₀ = λ₀,
        T = T,
    )
end

@testitem "planning oracle: build_planning_oracle is build-once (num_variables/num_constraints invariant across re-solves)" tags =
    [:planning] setup = [Phase6Fixtures] begin
    using TSODSO
    using JuMP: num_variables, num_constraints, set_parameter_value, optimize!

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    T = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()

    o = build_planning_oracle(feeder, LinDistFlow(), aggs; λ₀ = λ₀, T = T)
    @test o isa TSODSO.PlanningOracle

    nv0 = num_variables(o.model)
    nc0 = num_constraints(o.model; count_variable_in_set_constraints = true)

    # Two set_parameter_value + optimize! cycles at DIFFERENT z_trial vectors — build-once,
    # no rebuild (D-11). This task's own acceptance criterion checks ONLY the model SHAPE
    # (num_variables/num_constraints), not solve feasibility, so raw optimize! (no
    # assert_solved! gate) is used directly, exactly mirroring test_dso.jl's build-once
    # invariance shape.
    set_parameter_value.(o.z, fill(0.01, T))
    optimize!(o.model)

    set_parameter_value.(o.z, fill(-0.02, T))
    optimize!(o.model)

    @test num_variables(o.model) == nv0
    @test num_constraints(o.model; count_variable_in_set_constraints = true) == nc0
end

@testitem "planning oracle: solve_planning_oracle! returns (cost, π, π_s, dadp, ctx) NamedTuple shape" tags =
    [:planning] setup = [Phase6Fixtures] begin
    using TSODSO
    using JuMP: value

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    T = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()

    # z_trial must be FEASIBLE for the pinned network (see file-header note: z=0 is
    # infeasible for this fixture). The network's own unconstrained free-import optimum
    # (via the UNMODIFIED free path) is always feasible by construction — use it.
    free = operational_oracle(
        feeder,
        LinDistFlow(),
        aggs;
        λ₀ = λ₀,
        T = T,
        z = nothing,
        allow_export = true,
    )
    zstar = value.(free.ctx.meta[:p_import])

    o = build_planning_oracle(feeder, LinDistFlow(), aggs; λ₀ = λ₀, T = T)
    res = solve_planning_oracle!(o, zstar)

    @test res isa NamedTuple
    @test keys(res) == (:cost, :π, :π_s, :dadp, :ctx)
    @test length(res.π) == T
    @test all(isfinite, res.π)
    @test res.π_s ≈ sum(res.π)
    @test length(res.dadp) == T
    @test all(isfinite, res.dadp)
end

# A minimal AGGREGATABLE toy device (DEV-05 contract: contribute! returns
# `(; vars, p_inject, utility)`, writes NOTHING to ctx itself) with a SEPARABLE
# concave-quadratic utility `U(p) = a*p - (b/2)*p^2` (mirrors `Interruptible`'s eq. 3.10
# shape, but DEV-05-conformant so it can sit under an `Aggregator`, unlike `Interruptible`
# itself, which self-injects and predates DEV-05). Deliberately loose bounds keep its
# price-responsive optimum STRICTLY INTERIOR at every hour — unlike Phase6Fixtures's real
# aggregator (Thermostatic/Deferrable/PVBattery), whose comfort-band and battery-SOC
# bounds actively BIND at the network's free-import optimum (empirically confirmed this
# session: the real fixture's dual-sign test at z=zstar gives |π| up to ~1.5, not ≈0,
# because TWO structurally-redundant equality constraints touch p_import[t]
# — `balance_p[root,t]` and `pin[t]` — and their dual SPLIT is uniquely pinned only when
# every OTHER coupled variable's own KKT stationarity is non-degenerate, i.e. no active
# device bound anywhere in the loop). This toy device guarantees that non-degeneracy,
# giving a clean, low-noise regression for the D-06 sign/monotonicity invariant — exactly
# 10-RESEARCH.md Pitfall 1's own guidance: reuse the toy-case PATTERN (tiny feeder + one
# aggregator + a known-analytic optimum, mirroring Phase6Fixtures's 2-bus dual-sign-anchor
# shape), NOT a re-derivation of the document's specific numeric toy, and NOT
# Phase6Fixtures's own aggregator.
@testmodule ToyDeviceFixture begin
    using TSODSO
    using JuMP

    struct ToyElasticDevice <: AbstractDevice
        bus::Int
        a::Float64
        b::Float64
        Pmax::Float64
    end

    function TSODSO.contribute!(d::ToyElasticDevice, ctx::ModelContext; T::Int)
        m = ctx.model
        p = @variable(m, [t = 1:T], lower_bound = 0.0, upper_bound = d.Pmax)
        p_inject = AffExpr[-p[t] for t in 1:T]                        # a load: NEGATIVE injection
        utility = sum(d.a * p[t] - (d.b / 2) * p[t]^2 for t in 1:T)   # thesis eq. 3.10 shape
        return (; vars = (; p), p_inject, utility)
    end

    export ToyElasticDevice
end

@testitem "planning oracle: dual-sign toy-case regression — π monotonically non-decreasing in z, zero at the unconstrained optimum (D-06)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    using JuMP: value

    feeder = Phase6Fixtures.two_bus_feeder()   # reuse the near-lossless 2-bus anchor shape
    T = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()

    # a=6, b=1, λ₀=4 (flat) ⇒ unconstrained FOC a - b*p = λ₀ ⇒ p* = 2, strictly interior to
    # [0, Pmax=10] at every hour — no device bound ever binds (hand-derived, verified).
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], zeros(T))

    # The network's OWN unconstrained free-import optimum, via the UNMODIFIED free path
    # (z = nothing, allow_export = true — the same free-sign frontier shape
    # build_planning_oracle builds). This is the toy-case anchor, NOT an assumed docstring
    # formula (10-RESEARCH.md Pitfall 1).
    free = operational_oracle(
        feeder,
        LinDistFlow(),
        [agg];
        λ₀ = λ₀,
        T = T,
        z = nothing,
        allow_export = true,
    )
    zstar = value.(free.ctx.meta[:p_import])
    @test all(z -> isapprox(z, 2.0; atol = 1e-6), zstar)   # hand-derived p* = 2 anchor

    o = build_planning_oracle(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = T)

    res_star = solve_planning_oracle!(o, zstar)
    @test all(abs.(res_star.π) .< 1e-4)

    res_minus = solve_planning_oracle!(o, zstar .- 0.01)
    @test all(res_minus.π .<= 1e-6)

    res_plus = solve_planning_oracle!(o, zstar .+ 0.01)
    @test all(res_plus.π .>= -1e-6)

    # Elementwise monotonicity: π(z) is NON-DECREASING in z (the empirically-verified
    # negated-Max-dual convention, D-06) — this operationalizes 10-RESEARCH.md Pitfall 1's
    # toy-case PATTERN on a real PlanningOracle solve, not an assumed docstring formula.
    @test all(res_plus.π .>= res_star.π .- 1e-6) && all(res_star.π .>= res_minus.π .- 1e-6)
end

@testitem "planning oracle: free-path parity — operational_oracle's z !== nothing guard is untouched (D-03)" tags =
    [:planning] setup = [Phase6Fixtures] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    T = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()

    @test_throws ArgumentError operational_oracle(
        feeder,
        LinDistFlow(),
        aggs;
        λ₀ = λ₀,
        T = T,
        z = fill(0.05, T),
    )
end

@testitem "planning oracle: solve_planning_oracle! re-solve is build-once (num_variables/num_constraints invariant)" tags =
    [:planning] setup = [Phase6Fixtures] begin
    using TSODSO
    using JuMP: num_variables, num_constraints, value

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    T = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()

    # FEASIBLE z_trial values (see file-header note): the network's own unconstrained
    # free-import optimum, and a small positive perturbation of it (both empirically
    # verified feasible for this fixture; an arbitrary fixed offset like -0.02 is not).
    free = operational_oracle(
        feeder,
        LinDistFlow(),
        aggs;
        λ₀ = λ₀,
        T = T,
        z = nothing,
        allow_export = true,
    )
    zstar = value.(free.ctx.meta[:p_import])

    o = build_planning_oracle(feeder, LinDistFlow(), aggs; λ₀ = λ₀, T = T)
    nv0 = num_variables(o.model)
    nc0 = num_constraints(o.model; count_variable_in_set_constraints = true)

    solve_planning_oracle!(o, zstar)
    solve_planning_oracle!(o, zstar .+ 0.005)

    @test num_variables(o.model) == nv0
    @test num_constraints(o.model; count_variable_in_set_constraints = true) == nc0
end
