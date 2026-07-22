# test/test_planning_follower.jl
#
# Seam: src/planning/follower.jl (PLAN-04). `FollowerLP` + `build_follower` (Task 1)
# build the transmission-reinforcement follower LP EXACTLY ONCE; `solve_follower!`
# returns a feasible cost+dual for a deliverable z and a GENUINE HiGHS Farkas
# certificate for an infeasible z (never a penalized-slack shortcut). Items tagged
# `[:planning]`, names contain "planning" and "follower" (occursin filter
# convention, mirrors test_planning_retry.jl / test_planning_oracle.jl).
#
# Toy fixture (11-01-PLAN.md's own <toy_fixture> block, reused verbatim in plans
# 11-02/11-03): T=1, corridor_cap=2.0, x_inv_max=2.0 (max deliverable = 4.0),
# c_inv=1.0, c_op=[0.5]. The follower's marginal cost of delivering one more unit
# of z is the CONSTANT m_f = c_inv/corridor_cap + c_op[1] = 1.0 for any feasible
# z ∈ [0, 4.0] (the LP always invests exactly x_inv = z/corridor_cap — no slack).

@testitem "planning follower: build_follower guards (T, corridor_cap, x_inv_max, c_op length)" tags =
    [:planning] begin
    using TSODSO

    @test_throws ArgumentError build_follower(;
        T = 0,
        corridor_cap = 2.0,
        x_inv_max = 2.0,
        c_inv = 1.0,
        c_op = [0.5],
    )
    @test_throws ArgumentError build_follower(;
        T = 1,
        corridor_cap = 0.0,
        x_inv_max = 2.0,
        c_inv = 1.0,
        c_op = [0.5],
    )
    @test_throws ArgumentError build_follower(;
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = 0.0,
        c_inv = 1.0,
        c_op = [0.5],
    )
    @test_throws ArgumentError build_follower(;
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = 2.0,
        c_inv = 1.0,
        c_op = [0.5, 0.3],
    )
end

@testitem "planning follower: build_follower is build-once (num_variables/num_constraints invariant across re-solves)" tags =
    [:planning] begin
    using TSODSO
    using JuMP: num_variables, num_constraints, set_parameter_value, optimize!

    f = build_follower(;
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = 2.0,
        c_inv = 1.0,
        c_op = [0.5],
    )
    @test f isa TSODSO.FollowerLP

    nv0 = num_variables(f.model)
    nc0 = num_constraints(f.model; count_variable_in_set_constraints = true)

    solve_follower!(f, [1.0])
    solve_follower!(f, [2.0])

    @test num_variables(f.model) == nv0
    @test num_constraints(f.model; count_variable_in_set_constraints = true) == nc0
end

@testitem "planning follower: feasible branch — cost/shape at z=[1.0]" tags = [:planning] begin
    using TSODSO

    f = build_follower(;
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = 2.0,
        c_inv = 1.0,
        c_op = [0.5],
    )
    res = solve_follower!(f, [1.0])

    @test res.feasible == true
    # Hand-computed: c_inv*(1/corridor_cap) + c_op[1]*1 = 1*0.5 + 0.5*1 = 1.0
    @test res.cost ≈ 1.0 atol = 1e-6
    @test length(res.π_s) == 1
end

@testitem "planning follower: Farkas-certificate regression — negative z (corridor cannot deliver reverse flow)" tags =
    [:planning] begin
    using TSODSO

    f = build_follower(;
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = 2.0,
        c_inv = 1.0,
        c_op = [0.5],
    )
    res = solve_follower!(f, [-1.0])

    @test res.feasible == false
    @test isfinite(res.v)
    @test all(isfinite, res.u)
end

@testitem "planning follower: Farkas-certificate regression — z exceeds max capacity (corridor_cap*x_inv_max=4.0)" tags =
    [:planning] begin
    using TSODSO

    f = build_follower(;
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = 2.0,
        c_inv = 1.0,
        c_op = [0.5],
    )
    res = solve_follower!(f, [10.0])

    @test res.feasible == false
    @test isfinite(res.v)
    @test all(isfinite, res.u)
end

@testitem "planning follower: dual-sign/slope regression — m_f=1.0 slope, sign pinned by direct measurement" tags =
    [:planning] begin
    using TSODSO

    f = build_follower(;
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = 2.0,
        c_inv = 1.0,
        c_op = [0.5],
    )

    res1 = solve_follower!(f, [1.0])
    res2 = solve_follower!(f, [1.5])

    # Known constant marginal cost m_f = c_inv/corridor_cap + c_op[1] = 1.0.
    @test res2.cost - res1.cost ≈ 0.5 atol = 1e-6

    @test isapprox(abs(res1.π_s[1]), 1.0; atol = 1e-6)

    # Sign pinned by DIRECT MEASUREMENT (10-RESEARCH.md Pitfall 1's own "measure,
    # don't guess" methodology, run once this session): dual.(f.coupling)[1] was
    # OBSERVED to be +1.0 (POSITIVE) at both z=[1.0] and z=[1.5] — increasing
    # z[t] increases the follower's Min-sense marginal cost at rate m_f=1.0, and
    # JuMP reports the coupling[t]: x_op[t] == z[t] equality's dual with that
    # SAME positive sign under this project's Min-sense LP convention.
    @test isapprox(res1.π_s[1], 1.0 * 1.0; atol = 1e-6)
end
