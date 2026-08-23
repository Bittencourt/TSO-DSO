# test/test_planning_master_integer.jl
#
# Seam: src/planning/master_integer.jl (Phase 24, INT-01). `BendersMasterInteger` +
# `build_master_integer` build the leader's binary-expansion MILP master EXACTLY ONCE —
# a completely separate sibling of the continuous `BendersMaster`/`build_master`
# (master.jl, D-05), never touching it. Items tagged `[:planning]`, names contain
# "planning" and "master" (occursin filter convention, mirrors test_planning_master.jl).
#
# Toy fixture (same D-12 canonical instance as test_planning_master.jl / the N=1 golden):
# T=1, c_y=0.3, y_max=8.0, K=4, α_op_lb=-5.0, α_x_lb=0.0.

@testitem "planning master_integer: build_master_integer guards (T, K, y_max, c_y)" tags =
    [:planning] begin
    using TSODSO

    @test_throws ArgumentError build_master_integer(;
        T = 0,
        K = 4,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )
    @test_throws ArgumentError build_master_integer(;
        T = 1,
        K = 0,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )
    @test_throws ArgumentError build_master_integer(;
        T = 1,
        K = 4,
        c_y = 0.3,
        y_max = 0.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )
    @test_throws ArgumentError build_master_integer(;
        T = 1,
        K = 4,
        c_y = -1.0,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )
end

@testitem "planning master_integer: zero-cut first solve is OPTIMAL (MILP analog of Pitfall M1)" tags =
    [:planning] begin
    using TSODSO
    using JuMP: termination_status, MOI

    master = build_master_integer(;
        T = 1,
        K = 4,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )
    @test master isa TSODSO.BendersMasterInteger

    r = solve_master!(master)

    @test termination_status(master.model) == MOI.OPTIMAL
    @test length(r.b) == 4
end

@testitem "planning master_integer: D-02 lattice reachability — all-ones corner reaches y_max*(1-2^-K), never y_max" tags =
    [:planning] begin
    using TSODSO
    using JuMP: fix, optimize!, value

    master = build_master_integer(;
        T = 1,
        K = 4,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )
    solve_master!(master)   # establish a first solve before mutating fixings

    fix.(master.b, 1.0)
    optimize!(master.model)

    @test isapprox(value(master.y_inv), 8.0 * 15 / 16; atol = 1e-6)
    @test !isapprox(value(master.y_inv), 8.0; atol = 1e-6)
end

@testitem "planning master_integer: L-validity (Assumption A1) — L=α_op_lb+α_x_lb bounds the REAL oracle/follower across [0,y_max]" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]

    oracle = build_planning_oracle(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = 1)
    follower = build_follower(; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5], T = 1)

    master = build_master_integer(;
        T = 1,
        K = 4,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )

    # Sweep z spanning the full [0, y_max=8.0] domain against the REAL oracle/follower
    # entrypoints (not the archived closed form) — Assumption A1 closed by measurement.
    #
    # MEASURED FINDING (not assumed): at z=8.0 the follower is INFEASIBLE on this exact
    # D-12 fixture — its own corridor capacity `corridor_cap * x_inv_max = 2.0 * 2.0 = 4.0`
    # caps deliverable flow INDEPENDENTLY of the master's y_inv/y_max. This is not a bug:
    # 24-RESEARCH.md's Priority Finding 1 documents this exact mechanism as "orthogonal to
    # LL-cut applicability" — the master's own trial z (bounded by y_inv, not by the
    # follower's own capacity) can propose a z the follower cannot deliver, firing the
    # EXISTING feasibility-cut branch (untouched by this phase). Q(z) — and hence L's bound
    # on it — is only defined/required at z where the follower IS feasible (where an
    # optimality cut, not a feasibility cut, would be generated); z=0 is always feasible by
    # construction (complete recourse), which is what LL-cut applicability actually needs.
    for z in (0.0, 1.0, 2.0, 4.0, 8.0)
        oracle_res = solve_planning_oracle!(oracle, [z])
        follower_res = solve_follower!(follower, [z])

        # α_op_lb must bound the MIN-sense quantity -oracle_res.cost (oracle_res.cost is
        # MAX-sense welfare) — the oracle has no box tied to the follower's own capacity,
        # so this holds at every sampled z regardless of follower feasibility.
        @test -oracle_res.cost >= -5.0

        if follower_res.feasible
            # α_x_lb=0.0 bounds the follower's MIN-sense cost.
            @test follower_res.cost >= 0.0
            # L = α_op_lb + α_x_lb must bound the combined recourse Q(z) at every FEASIBLE
            # sampled z (the only points at which Q(z) is even defined).
            @test master.L <= -oracle_res.cost + follower_res.cost
        else
            # solve_follower!'s own contract (T-11-01/WR-03) already enforces isfinite(v) &&
            # v > 0 for a genuine Farkas certificate before returning — reaching this branch
            # at all confirms a VALID feasibility cut would be generated here, exactly the
            # mechanism RESEARCH.md documents as orthogonal to A1/LL-cut validity.
            @test isfinite(follower_res.v) && follower_res.v > 0
        end
    end

    # complete recourse (RESEARCH.md Priority Finding 1): z=0 is ALWAYS feasible for the
    # follower, independent of y_inv — the concrete anchor A1's LL-cut applicability needs.
    @test solve_follower!(follower, [0.0]).feasible
end

@testitem "planning master_integer: persistent cut-row growth — reused continuous cuts append rows, never columns (RESEARCH.md Finding 2)" tags =
    [:planning] begin
    using TSODSO
    using JuMP: num_variables, num_constraints

    # Mirrors test_planning_master.jl's own "persistent cut-row growth" pattern — the
    # MILP analog of the continuous regression, exercising the SAME add_optimality_cut!/
    # add_feasibility_cut! algebra now overloaded for BendersMasterInteger (plan 24-02
    # Task 1).
    master = build_master_integer(;
        T = 1,
        K = 4,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )

    nv0 = num_variables(master.model)
    nc0 = num_constraints(master.model; count_variable_in_set_constraints = true)

    add_optimality_cut!(master, :op, 5.0, [2.0], [1.0])
    nv1 = num_variables(master.model)
    nc1 = num_constraints(master.model; count_variable_in_set_constraints = true)
    @test nc1 == nc0 + 1
    @test nv1 == nv0

    add_feasibility_cut!(master, 3.0, [1.0], [1.0])
    nv2 = num_variables(master.model)
    nc2 = num_constraints(master.model; count_variable_in_set_constraints = true)
    @test nc2 == nc1 + 1
    @test nv2 == nv0

    @test length(master.cuts) == 2
    @test master.cuts[1].kind == :optimality
    @test master.cuts[2].kind == :feasibility
end
