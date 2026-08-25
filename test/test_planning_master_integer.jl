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
    follower = build_follower(;
        corridor_cap = 2.0,
        x_inv_max = 2.0,
        c_inv = 1.0,
        c_op = [0.5],
        T = 1,
    )

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

@testitem "planning master_integer: add_ll_cut! exhaustive K=4 16x16-corner tightness/slackness (24-RESEARCH.md Priority Finding 1)" tags =
    [:planning] begin
    using TSODSO
    using JuMP: fix, optimize!, value, unfix

    K = 4
    Q_nu = -0.3
    build_fixture() = build_master_integer(;
        T = 1,
        K = K,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )

    corner(i) = Float64[(i >> k) & 1 for k in 0:(K - 1)]

    # THE CUT MUST BE WRITTEN OVER THE RAW b_k (Pitfall 1) -- exhaustively proven here by
    # re-deriving D(b') independently of add_ll_cut!'s own internals (closed-form
    # arithmetic on the SAME algebra the function implements), for every one of the
    # 2^K = 16 incumbents x every one of the 15 OTHER corners: 16x16 = 256 pairs total.
    for i in 0:(2 ^ K - 1)
        b_nu = corner(i)
        master = build_fixture()
        L = master.L
        @test master.L == -5.0   # A1 (24-01), reused, not re-derived here

        add_ll_cut!(master, b_nu, Q_nu, L)
        @test length(master.cuts) == 1
        @test master.cuts[1].kind == :ll
        @test master.cuts[1].b_trial == round.(Int, b_nu)

        S = findall(==(1.0), b_nu)
        Sc = setdiff(1:K, S)

        for j in 0:(2 ^ K - 1)
            b_p = corner(j)
            D = sum(b_p[S]; init = 0.0) - sum(b_p[Sc]; init = 0.0) - length(S) + 1
            rhs = (Q_nu - L) * D + L
            if b_p == b_nu
                # TIGHT at the incumbent.
                @test isapprox(rhs, Q_nu; atol = 1e-9)
            else
                # IMPLIED elsewhere -- adds ZERO new information beyond theta >= L.
                @test rhs <= L + 1e-9
            end
        end

        # Genuine JuMP-level reinforcement (not just closed-form arithmetic): fixing b
        # to the incumbent b^nu and re-optimizing the ACTUAL model must realize
        # alpha_op + alpha_x == Q_nu exactly -- the cut is load-bearing in the solver,
        # not merely correct on paper.
        fix.(master.b, b_nu; force = true)
        optimize!(master.model)
        @test isapprox(value(master.α_op) + value(master.α_x), Q_nu; atol = 1e-6)
        unfix.(master.b)
    end
end

@testitem "planning master_integer: add_nogood_cut! forbids exact re-visitation, leaves other corners feasible" tags =
    [:planning] begin
    using TSODSO
    using JuMP: fix, optimize!, termination_status, MOI, unfix

    master = build_master_integer(;
        T = 1,
        K = 4,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )

    banned = [1.0, 0.0, 1.0, 0.0]
    add_nogood_cut!(master, banned)
    @test length(master.cuts) == 1
    @test master.cuts[1].kind == :nogood
    @test master.cuts[1].b_trial == round.(Int, banned)

    # Forbidden EXACTLY at the banned corner.
    fix.(master.b, banned; force = true)
    optimize!(master.model)
    @test termination_status(master.model) == MOI.INFEASIBLE
    unfix.(master.b)

    # Feasible at any OTHER corner.
    other = [0.0, 0.0, 1.0, 0.0]
    fix.(master.b, other; force = true)
    optimize!(master.model)
    @test termination_status(master.model) == MOI.OPTIMAL
    unfix.(master.b)
end
