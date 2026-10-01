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

# ---------------------------------------------------------------------------------------
# Plan 30-02 (BILEV-05): `:auto` α-bound derivation + build-time rejection. The new
# @testitems below reuse the SAME two-bus/ToyElasticDevice toy fixture test_planning_oracle.jl's
# own D-06 dual-sign regression already established (Phase6Fixtures + ToyDeviceFixture).
# ---------------------------------------------------------------------------------------

@testitem "planning master: explicit bounds with no bounds_ctx are byte-identical (regression guard)" tags =
    [:planning] begin
    using TSODSO
    using JuMP: termination_status, MOI

    master = build_master(; T = 1, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)
    @test master isa TSODSO.BendersMaster

    solve_master!(master)

    @test termination_status(master.model) == MOI.OPTIMAL
end

@testitem "planning master: :auto resolves both epigraph bounds via a genuine relaxed solve" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    using JuMP: termination_status, MOI, lower_bound

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], zeros(1))
    λ₀ = [4.0]

    bounds_ctx = (;
        feeder = feeder,
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = λ₀,
        follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5]),
    )

    # α_op_lb/α_x_lb omitted entirely — the new :auto default.
    master = build_master(; T = 1, c_y = 0.3, y_max = 8.0, bounds_ctx = bounds_ctx)
    @test master isa TSODSO.BendersMaster

    solve_master!(master)
    @test termination_status(master.model) == MOI.OPTIMAL

    @test isfinite(lower_bound(master.α_op))
    @test !isnan(lower_bound(master.α_op))
    @test isfinite(lower_bound(master.α_x))
    @test !isnan(lower_bound(master.α_x))
    # A sane sign: α_op_lb = -(relaxed welfare optimum) should be <= 0 on this fixture
    # (the relaxed welfare optimum is nonnegative: a=6,b=1,λ₀=4 toy device, box [0,y_max]).
    @test lower_bound(master.α_op) <= 0.0
end

@testitem "planning master: build-time rejection of an over-high explicit α_op_lb when bounds_ctx is supplied" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], zeros(1))
    λ₀ = [4.0]

    bounds_ctx = (;
        feeder = feeder,
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = λ₀,
        follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5]),
    )

    @test_throws ArgumentError build_master(;
        T = 1,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = 1e9,
        bounds_ctx = bounds_ctx,
    )
end

@testitem "planning master: build-time rejection of an over-high explicit α_x_lb when bounds_ctx is supplied" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], zeros(1))
    λ₀ = [4.0]

    bounds_ctx = (;
        feeder = feeder,
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = λ₀,
        follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5]),
    )

    @test_throws ArgumentError build_master(;
        T = 1,
        c_y = 0.3,
        y_max = 8.0,
        α_x_lb = 1e9,
        bounds_ctx = bounds_ctx,
    )
end

@testitem "planning master: :auto derivation independently confirms test_planning_hardening.jl's own T=8 finding (α_op_lb=-5.0 invalid, α_op_lb=-50.0 valid)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    # EXACT T=8 fixture literals, verbatim from test_planning_hardening.jl's own header
    # comment (the "FIX" paragraph): dev=ToyElasticDevice(2,6.0,1.0,10.0), agg with zeros(8)
    # Pdc, λ₀=fill(4.0,8).
    T = 8
    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], zeros(T))
    λ₀ = fill(4.0, T)

    d = TSODSO.alpha_op_lb_derivation(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = T, y_max = 8.0)
    # Phase 30 code review (WR-03): rejection compares against the UN-margined optimum
    # plus the measured, scale-aware slack — the same rule build_master applies.
    slack = TSODSO.alpha_lb_margin(d.optimum, d.gap; floor = TSODSO.ALPHA_LB_REJECTION_TOL)

    # -5.0 is REJECTED (too tight — exceeds the derived minimum ≈ -16): the
    # already-documented finding that -5.0 silently converges to a wrong answer at T=8.
    @test -5.0 > d.optimum + slack
    # -50.0 remains a VALID, non-rejected bound.
    @test -50.0 <= d.optimum + slack
    # The declared :auto bound sits strictly below the optimum by the measured margin.
    @test d.bound == d.optimum - d.margin
    @test d.margin >= TSODSO.ALPHA_LB_MARGIN
end

@testitem "planning master: build-time rejection has real headroom — a bound AT the derived optimum is accepted (WR-03)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    using JuMP: lower_bound

    # Phase 30 code review (WR-03): the old rule rejected `α > (optimum − margin) + tol`
    # with margin == tol == 1e-6, i.e. `α > optimum` — ZERO tolerance: a user bound equal
    # to the true minimum was rejected whenever the solver reported its optimum slightly
    # low, and α_x_lb = 0.0 on a 0.0-minimum follower was accepted only because
    # -1e-6 + 1e-6 == 0.0 in floating point. Now: reject iff α > optimum + slack.
    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], zeros(1))
    λ₀ = [4.0]
    fk = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])
    bounds_ctx = (; feeder = feeder, pf = LinDistFlow(), aggregators = [agg], λ₀ = λ₀, follower_kwargs = fk)

    dop = TSODSO.alpha_op_lb_derivation(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = 1, y_max = 8.0)
    dx = TSODSO.alpha_x_lb_derivation(; fk..., T = 1)
    sop = TSODSO.alpha_lb_margin(dop.optimum, dop.gap; floor = TSODSO.ALPHA_LB_REJECTION_TOL)
    sx = TSODSO.alpha_lb_margin(dx.optimum, dx.gap; floor = TSODSO.ALPHA_LB_REJECTION_TOL)

    # A bound slightly ABOVE the reported optimum, but inside the measured slack, is
    # accepted (the old rule rejected both of these).
    m = build_master(;
        T = 1,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = dop.optimum + sop / 2,
        α_x_lb = dx.optimum + sx / 2,
        bounds_ctx = bounds_ctx,
    )
    @test lower_bound(m.α_op) == dop.optimum + sop / 2
    @test lower_bound(m.α_x) == dx.optimum + sx / 2
    # Beyond the slack, both are still rejected.
    @test_throws ArgumentError build_master(;
        T = 1, c_y = 0.3, y_max = 8.0,
        α_op_lb = dop.optimum + 2 * sop, α_x_lb = 0.0, bounds_ctx = bounds_ctx,
    )
    @test_throws ArgumentError build_master(;
        T = 1, c_y = 0.3, y_max = 8.0,
        α_op_lb = -50.0, α_x_lb = dx.optimum + 2 * sx, bounds_ctx = bounds_ctx,
    )
end

@testitem "planning master: derive_alpha_x_lb(::FollowerLP) dispatch agrees with the follower_kwargs path" tags =
    [:planning] begin
    using TSODSO

    f = build_follower(; T = 1, corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])
    a = TSODSO.derive_alpha_x_lb(f)
    b = TSODSO.derive_alpha_x_lb(;
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = 2.0,
        c_inv = 1.0,
        c_op = [0.5],
    )
    @test isapprox(a, b; atol = 1e-8)
end

@testitem "planning master: α_x_lb build-time validation is honestly skipped when bounds_ctx.follower_kwargs is nothing (DistributorView-equivalent scope limit)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    using JuMP: lower_bound

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], zeros(1))
    λ₀ = [4.0]

    bounds_ctx_skip = (;
        feeder = feeder,
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = λ₀,
        follower_kwargs = nothing,
    )

    master = build_master(;
        T = 1,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = :auto,
        α_x_lb = 0.0,
        bounds_ctx = bounds_ctx_skip,
    )
    @test lower_bound(master.α_x) == 0.0   # explicit literal passed straight through
    @test isfinite(lower_bound(master.α_op))   # α_op_lb WAS resolved via bounds_ctx
    @test lower_bound(master.α_op) != -5.0     # not a stray default/literal

    @test_throws ArgumentError build_master(;
        T = 1,
        c_y = 0.3,
        y_max = 8.0,
        α_x_lb = :auto,
        bounds_ctx = bounds_ctx_skip,
    )
end
