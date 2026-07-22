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
    # no rebuild (D-11).
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

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    T = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()

    o = build_planning_oracle(feeder, LinDistFlow(), aggs; λ₀ = λ₀, T = T)
    res = solve_planning_oracle!(o, zeros(T))

    @test res isa NamedTuple
    @test keys(res) == (:cost, :π, :π_s, :dadp, :ctx)
    @test length(res.π) == T
    @test all(isfinite, res.π)
    @test res.π_s ≈ sum(res.π)
    @test length(res.dadp) == T
    @test all(isfinite, res.dadp)
end

@testitem "planning oracle: dual-sign toy-case regression — π monotonically non-decreasing in z, zero at the unconstrained optimum (D-06)" tags =
    [:planning] setup = [Phase6Fixtures] begin
    using TSODSO
    using JuMP: value

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    T = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()

    # The network's OWN unconstrained free-import optimum, via the UNMODIFIED free path
    # (z = nothing, allow_export = true — the same free-sign frontier shape
    # build_planning_oracle builds). This is the toy-case anchor, NOT an assumed docstring
    # formula (10-RESEARCH.md Pitfall 1).
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

    res_star = solve_planning_oracle!(o, zstar)
    @test all(abs.(res_star.π) .< 1e-4)

    res_minus = solve_planning_oracle!(o, zstar .- 0.01)
    @test all(res_minus.π .<= 1e-6)

    res_plus = solve_planning_oracle!(o, zstar .+ 0.01)
    @test all(res_plus.π .>= -1e-6)

    # Elementwise monotonicity: π(z) is NON-DECREASING in z (the empirically-verified
    # negated-Max-dual convention, D-06) — this operationalizes 10-RESEARCH.md Pitfall 1 on
    # the REAL 2-bus fixture, not an assumed docstring formula.
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
    using JuMP: num_variables, num_constraints

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    T = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()

    o = build_planning_oracle(feeder, LinDistFlow(), aggs; λ₀ = λ₀, T = T)
    nv0 = num_variables(o.model)
    nc0 = num_constraints(o.model; count_variable_in_set_constraints = true)

    solve_planning_oracle!(o, fill(0.01, T))
    solve_planning_oracle!(o, fill(-0.02, T))

    @test num_variables(o.model) == nv0
    @test num_constraints(o.model; count_variable_in_set_constraints = true) == nc0
end
