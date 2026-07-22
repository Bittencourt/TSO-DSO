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
