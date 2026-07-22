# test/test_planning_master.jl
#
# Seam: src/planning/master.jl (PLAN-05). `BendersMaster` + `build_master` (Task 2)
# build the leader's own LP (investment + coupling flow + TWO epigraph terms
# α_op/α_x) EXACTLY ONCE, with a DOCUMENTED, DERIVED finite epigraph lower bound
# declared at build time (11-RESEARCH.md Pitfall M1). `add_optimality_cut!`/
# `add_feasibility_cut!` append persistent constraint rows — never rebuilt.
# `solve_master!` routes through `solve_with_retry!` (never `assert_solved!`
# directly). Items tagged `[:planning]`, names contain "planning" and "master"
# (occursin filter convention, mirrors test_planning_follower.jl).
#
# Toy fixture (11-01-PLAN.md's own <toy_fixture> block): T=1, c_y=0.3, y_max=8.0,
# α_op_lb=-5.0 (conservative margin below the oracle's own analytic max welfare
# of 2.0 on this fixture), α_x_lb=0.0 (the follower's cost is a sum of
# nonnegative coefficients times nonnegative variables, trivially bounded below
# by zero).

@testitem "planning master: build_master guards (T, y_max, c_y)" tags = [:planning] begin
    using TSODSO

    @test_throws ArgumentError build_master(;
        T = 0,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )
    @test_throws ArgumentError build_master(;
        T = 1,
        c_y = 0.3,
        y_max = 0.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )
    @test_throws ArgumentError build_master(;
        T = 1,
        c_y = -1.0,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )
end

@testitem "planning master: epigraph lower-bound regression — zero-cut first solve is OPTIMAL, never DUAL_INFEASIBLE" tags =
    [:planning] begin
    using TSODSO
    using JuMP: termination_status, MOI

    master = build_master(; T = 1, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)
    @test master isa TSODSO.BendersMaster

    solve_master!(master)

    @test termination_status(master.model) == MOI.OPTIMAL
end

@testitem "planning master: persistent cut-row growth — num_constraints grows by exactly 1 per cut, num_variables never changes" tags =
    [:planning] begin
    using TSODSO
    using JuMP: num_variables, num_constraints

    master = build_master(; T = 1, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)

    nv0 = num_variables(master.model)
    nc0 = num_constraints(master.model; count_variable_in_set_constraints = true)

    add_optimality_cut!(master, :op, 5.0, [2.0], [1.0])
    nv1 = num_variables(master.model)
    nc1 = num_constraints(master.model; count_variable_in_set_constraints = true)
    @test nc1 == nc0 + 1
    @test nv1 == nv0

    add_optimality_cut!(master, :x, 1.0, [1.0], [1.0])
    nv2 = num_variables(master.model)
    nc2 = num_constraints(master.model; count_variable_in_set_constraints = true)
    @test nc2 == nc1 + 1
    @test nv2 == nv0

    add_feasibility_cut!(master, 3.0, [1.0], [1.0])
    nv3 = num_variables(master.model)
    nc3 = num_constraints(master.model; count_variable_in_set_constraints = true)
    @test nc3 == nc2 + 1
    @test nv3 == nv0

    @test length(master.cuts) == 3
end

@testitem "planning master: bogus-epigraph guard — add_optimality_cut! rejects any symbol other than :op/:x" tags =
    [:planning] begin
    using TSODSO

    master = build_master(; T = 1, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)

    @test_throws ArgumentError add_optimality_cut!(master, :bogus, 1.0, [1.0], [1.0])
end

@testitem "planning master: shape-mismatch guards — grad_k/z_k/u_k length must equal T (T-11-03)" tags =
    [:planning] begin
    using TSODSO

    master = build_master(; T = 1, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)

    @test_throws ArgumentError add_optimality_cut!(master, :op, 5.0, [2.0, 1.0], [1.0])
    @test_throws ArgumentError add_optimality_cut!(master, :op, 5.0, [2.0], [1.0, 1.0])
    @test_throws ArgumentError add_feasibility_cut!(master, 3.0, [1.0, 1.0], [1.0])
    @test_throws ArgumentError add_feasibility_cut!(master, 3.0, [1.0], [1.0, 1.0])
end

@testitem "planning master: finiteness guards — NaN/Inf cut inputs are rejected loudly BEFORE touching the model (WR-03)" tags =
    [:planning] begin
    using TSODSO
    using JuMP: num_constraints

    master = build_master(; T = 1, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)
    nc0 = num_constraints(master.model; count_variable_in_set_constraints = true)

    @test_throws ArgumentError add_optimality_cut!(master, :op, NaN, [2.0], [1.0])
    @test_throws ArgumentError add_optimality_cut!(master, :op, 5.0, [Inf], [1.0])
    @test_throws ArgumentError add_optimality_cut!(master, :op, 5.0, [2.0], [NaN])
    @test_throws ArgumentError add_feasibility_cut!(master, Inf, [1.0], [1.0])
    @test_throws ArgumentError add_feasibility_cut!(master, 3.0, [NaN], [1.0])
    @test_throws ArgumentError add_feasibility_cut!(master, 3.0, [1.0], [-Inf])

    # The persistent master must be UNTOUCHED — no row appended, no cut logged.
    @test num_constraints(master.model; count_variable_in_set_constraints = true) == nc0
    @test isempty(master.cuts)
end

@testitem "planning master: cut-validity structural check — the solved point never violates a known cut" tags =
    [:planning] begin
    using TSODSO
    using JuMP: value

    master = build_master(; T = 1, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)
    add_optimality_cut!(master, :op, 5.0, [2.0], [1.0])

    solve_master!(master)

    @test value(master.α_op) >= 5.0 + 2.0 * (value(master.z[1]) - 1.0) - 1e-6
end
