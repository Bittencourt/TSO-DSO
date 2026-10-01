# test/test_planning_bilevel.jl
#
# Seam: src/planning/bilevel_kkt.jl (BILEV-01, Phase 29 plan 29-01). Unit and
# boundary-guard `@testitem`s for `build_bilevel_kkt`/`solve_bilevel!` — a ONE-SHOT
# MILP solve, not an iterative Benders loop (no `BendersTrace`/checkpoint assertions
# needed, mirrors test_planning_benders.jl's own unit-level shape).
#
# Verified via a direct Julia/Test.jl script under `--project=.` BEFORE relying on
# TestItemRunner (memory: `gsd-plan-verify-testitemrunner-trap` — TestItemRunner does
# NOT resolve under `--project=.`).

@testitem "bilevel: build_bilevel_kkt + solve_bilevel! reproduce the hand-derived corner (y*=0, z*=0, total=0)" tags =
    [:planning] setup = [PlanningFixtures] begin
    using TSODSO

    f = PlanningFixtures.bilevel_toy_fixture()

    kkt = build_bilevel_kkt(
        f.feeder,
        LinDistFlow();
        T = f.T,
        agg_bus = f.agg_bus,
        corridor_cap = f.corridor_cap,
        x_inv_max = f.x_inv_max,
        c_inv = f.c_inv,
        c_op = f.c_op,
        pi_tariff = f.pi_tariff,
        q_op = f.q_op,
        c_y = f.c_y,
        y_max = f.y_max,
        v_d = f.v_d,
        d_max = f.d_max,
    )
    result = solve_bilevel!(kkt)

    # Measured, not hand-picked: HiGHS's own achieved precision on this fixture (see
    # fixtures_planning.jl's bilevel_toy_fixture derivation comment for the hand-derived
    # corner y*=0, z*=0, total*=0.0). 1e-6 is comfortably above the fixture's own
    # measured residual (see this plan's SUMMARY for the measured value).
    atol = 1e-6
    @test isapprox(result.y, 0.0; atol = atol)
    @test isapprox(result.x_inv, 0.0; atol = atol)
    @test isapprox(result.z[1], 0.0; atol = atol)
    @test isapprox(result.total_cost, 0.0; atol = atol)
end

@testitem "bilevel: build_bilevel_kkt boundary guards" tags = [:planning] setup =
    [PlanningFixtures] begin
    using TSODSO

    f = PlanningFixtures.bilevel_toy_fixture()
    base = (;
        agg_bus = f.agg_bus,
        corridor_cap = f.corridor_cap,
        x_inv_max = f.x_inv_max,
        c_inv = f.c_inv,
        c_op = f.c_op,
        pi_tariff = f.pi_tariff,
        q_op = f.q_op,
        c_y = f.c_y,
        y_max = f.y_max,
        v_d = f.v_d,
        d_max = f.d_max,
    )

    # T=0
    @test_throws ArgumentError build_bilevel_kkt(
        f.feeder,
        LinDistFlow();
        base...,
        T = 0,
    )

    # mismatched length(c_op)
    @test_throws ArgumentError build_bilevel_kkt(
        f.feeder,
        LinDistFlow();
        base...,
        T = f.T,
        c_op = [0.5, 0.5],
    )

    # agg_bus == feeder.root
    @test_throws ArgumentError build_bilevel_kkt(
        f.feeder,
        LinDistFlow();
        base...,
        T = f.T,
        agg_bus = f.feeder.root,
    )

    # agg_bus outside 1:length(feeder.buses)
    @test_throws ArgumentError build_bilevel_kkt(
        f.feeder,
        LinDistFlow();
        base...,
        T = f.T,
        agg_bus = length(f.feeder.buses) + 1,
    )

    # pf = ConvexBranchFlow() (SOCP-class network, unsupported)
    @test_throws ArgumentError build_bilevel_kkt(
        f.feeder,
        ConvexBranchFlow();
        base...,
        T = f.T,
    )

    # pf = ACPowerFlow() (NLP-class network — WR-02: must be rejected by the allowlist
    # guard as an ArgumentError, not fail later inside JuMP with an ErrorException)
    @test_throws ArgumentError build_bilevel_kkt(
        f.feeder,
        ACPowerFlow();
        base...,
        T = f.T,
    )

    # pf = DCPowerFlow() (affine but untested here — WR-02 allowlist rejects it)
    @test_throws ArgumentError build_bilevel_kkt(
        f.feeder,
        DCPowerFlow();
        base...,
        T = f.T,
    )

    # follower_integer = true (unsupported)
    @test_throws ArgumentError build_bilevel_kkt(
        f.feeder,
        LinDistFlow();
        base...,
        T = f.T,
        follower_integer = true,
    )

    # q_op = [-1.0] (BLOCKER-1 revision — negative curvature, must throw)
    @test_throws ArgumentError build_bilevel_kkt(
        f.feeder,
        LinDistFlow();
        base...,
        T = f.T,
        q_op = [-1.0],
    )
end

@testitem "bilevel: solve_bilevel! validity check rejects a genuinely too-tight SOS1 bound" tags =
    [:planning] begin
    using TSODSO, JuMP

    # DELIBERATE stress test of the Pitfall-3 at-bound check itself (never a claim
    # about the production default). 29-REVIEW.md WR-06: the earlier version used
    # safety = 1e-9, which made the MILP INFEASIBLE, so assert_solved! threw
    # "Solve failed" first and the at-bound branch was never reached.
    #
    # Here the model stays FEASIBLE but a dual binds. Interior-fixture data with the
    # leader fixed at y_inv = 0.05 (below the 0.148 kink) forces the follower's
    # coupling dual to rho_y = 14.8 - 100*0.05 = 9.8 exactly. The closed-form bound
    # before `safety` is 14.8, so safety = 9.8/14.8 gives m_ub = 9.8: rho_y must sit
    # AT the bound, and solve_bilevel! must reject it.
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 1e-3, 1e-3, 99.0)],
        1,
    )
    kwargs = (;
        T = 1,
        agg_bus = 2,
        corridor_cap = 10.0,
        x_inv_max = 10.0,
        c_inv = 0.2,
        c_op = [0.5],
        pi_tariff = [2.0],
        q_op = [1.0],
        c_y = 0.05,
        y_max = 5.0,
        v_d = [3.0],
        d_max = 10.0,
    )

    tight = build_bilevel_kkt(feeder, LinDistFlow(); kwargs..., safety = 9.8 / 14.8)
    @test isapprox(tight.m_ub, 9.8; atol = 1e-12)
    fix(tight.y_inv, 0.05; force = true)
    err = try
        solve_bilevel!(tight)
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    @test err !== nothing && occursin("rho_y sits at (or within", sprint(showerror, err))

    # Positive control: the SAME fixed-y solve with safety = 1 (m_ub = 14.8, still
    # strictly above rho_y = 9.8) passes the check and reports the forced dual.
    loose = build_bilevel_kkt(feeder, LinDistFlow(); kwargs..., safety = 1.0)
    fix(loose.y_inv, 0.05; force = true)
    r = solve_bilevel!(loose)
    @test isapprox(r.rho_y, 9.8; atol = 1e-6)
end

@testitem "bilevel: follower's own x_inv <= x_inv_max carries a KKT multiplier (WR-01)" tags =
    [:planning] begin
    using TSODSO, JuMP

    # Interior-fixture data (test_planning_certification_bilevel_interior.jl) with the
    # follower's own investment ceiling shrunk to x_inv_max = 0.1, BELOW its
    # unconstrained optimum x_inv_F = 0.148. Fix the leader at y_inv = 1.0 > x_inv_max.
    # The true follower response is x_inv = 0.1, z = corridor_cap*x_inv = 1.0.
    # Hand-derived multipliers: slack_y = 0.9 > 0, so rho_y = 0;
    # mu_cap = (pi_tariff - c_op) - q_op*z = 1.5 - 1.0 = 0.5;
    # rho_max = corridor_cap*mu_cap - c_inv = 10*0.5 - 0.2 = 4.8.
    # Before the WR-01 fix (no rho_max in statio_x) this model was INFEASIBLE.
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 1e-3, 1e-3, 99.0)],
        1,
    )
    kkt = build_bilevel_kkt(
        feeder,
        LinDistFlow();
        T = 1,
        agg_bus = 2,
        corridor_cap = 10.0,
        x_inv_max = 0.1,
        c_inv = 0.2,
        c_op = [0.5],
        pi_tariff = [2.0],
        q_op = [1.0],
        c_y = 0.05,
        y_max = 5.0,
        v_d = [3.0],
        d_max = 10.0,
    )
    fix(kkt.y_inv, 1.0; force = true)
    r = solve_bilevel!(kkt)

    atol = 1e-6
    @test isapprox(r.x_inv, 0.1; atol = atol)
    @test isapprox(r.z[1], 1.0; atol = atol)
    @test isapprox(r.mu_cap[1], 0.5; atol = atol)
    @test isapprox(r.rho_y, 0.0; atol = atol)
    @test isapprox(r.rho_max, 4.8; atol = atol)
end

@testitem "bilevel: m_ub is the closed-form dual bound, pinned on both fixtures (WR-03)" tags =
    [:planning] setup = [PlanningFixtures] begin
    using TSODSO, JuMP

    # 29-REVIEW.md WR-03: the old solver-probe bound depended on Clarabel's arbitrary
    # point on an unbounded dual face (m_ub = 9544.4 on the interior fixture). The
    # closed-form bound (_follower_kkt_dual_bound) is pinned EXACTLY here, so any
    # drift is visible. Hand values (safety = 10):
    #   corner:   max(mu_cap 0, mu_lo 0.3, rho_y (2*0-1)^+ = 0, rho_lo 1.0) = 1.0  -> 10.0
    #   interior: max(mu_cap 1.5, mu_lo 0, rho_y 10*1.5-0.2 = 14.8, rho_lo 0.2) = 14.8
    #             -> 148.0 (14.8 is exactly the tight rho_y at y_inv = 0)
    f = PlanningFixtures.bilevel_toy_fixture()
    corner = build_bilevel_kkt(
        f.feeder,
        LinDistFlow();
        T = f.T,
        agg_bus = f.agg_bus,
        corridor_cap = f.corridor_cap,
        x_inv_max = f.x_inv_max,
        c_inv = f.c_inv,
        c_op = f.c_op,
        pi_tariff = f.pi_tariff,
        q_op = f.q_op,
        c_y = f.c_y,
        y_max = f.y_max,
        v_d = f.v_d,
        d_max = f.d_max,
    )
    @test corner.m_ub == 10.0

    interior_kwargs = (;
        T = 1,
        agg_bus = 2,
        corridor_cap = 10.0,
        x_inv_max = 10.0,
        c_inv = 0.2,
        c_op = [0.5],
        pi_tariff = [2.0],
        q_op = [1.0],
        c_y = 0.05,
        y_max = 5.0,
        v_d = [3.0],
        d_max = 10.0,
    )
    interior = build_bilevel_kkt(f.feeder, LinDistFlow(); interior_kwargs...)
    @test isapprox(interior.m_ub, 148.0; rtol = 1e-12)

    # Complementarity is enforced to within the bridge's big-M times HiGHS's
    # integrality tolerance (~ m_ub * 1e-9 ≈ 1.5e-7 here). Measured products on the
    # interior optimum are checked against 1e-6.
    r = solve_bilevel!(interior)
    slack_cap = 10.0 * r.x_inv - r.z[1]
    slack_y = r.y - r.x_inv
    @test abs(slack_cap * r.mu_cap[1]) < 1e-6
    @test abs(r.z[1] * r.mu_lo[1]) < 1e-6
    @test abs(slack_y * r.rho_y) < 1e-6
    @test abs(r.x_inv * r.rho_lo) < 1e-6
    @test abs((10.0 - r.x_inv) * r.rho_max) < 1e-6
end

@testitem "bilevel: at-bound check accepts correct x_inv*=0 optima on a degenerate multiplier face (iteration-2 CR-01)" tags =
    [:planning] begin
    using TSODSO, JuMP

    # 29-REVIEW.md iteration-2 CR-01. Interior-fixture data (a = pi_tariff - c_op = 1.5,
    # so the follower is profitable), in three variants where the leader prefers NO
    # delivery and the follower therefore cannot invest (y* = x_inv* = z* = 0):
    #   v_d = [1.0]   : the leader pays pi_tariff = 2.0 for a unit it values at 1.0;
    #   c_y = 20.0    : investment is too expensive for the leader;
    #   y_inv fixed 0 : a caller's sensitivity sweep at y = 0.
    # Leader objective at the optimum: 0. At x_inv = y_inv = 0 the follower's
    # multiplier face is degenerate and unbounded (rho_y - rho_lo = 10*mu_cap - 0.2,
    # mu_cap - mu_lo = 1.5). HiGHS returned box-face vertices such as rho_y = m_ub = 148
    # and the old raw-value check threw "rho_y sits at ...". The smallest valid
    # certificate is mu_cap = 1.5, mu_lo = 0, rho_y = 14.8, rho_lo = 0 — exactly the
    # proven bound, so the check must also pass at safety = 1 (m_ub = 14.8).
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 1e-3, 1e-3, 99.0)],
        1,
    )
    base = (;
        T = 1,
        agg_bus = 2,
        corridor_cap = 10.0,
        x_inv_max = 10.0,
        c_inv = 0.2,
        c_op = [0.5],
        pi_tariff = [2.0],
        q_op = [1.0],
        c_y = 0.05,
        y_max = 5.0,
        v_d = [3.0],
        d_max = 10.0,
    )
    cases = [
        ("v_d = [1.0]", merge(base, (; v_d = [1.0])), false),
        ("c_y = 20", merge(base, (; c_y = 20.0)), false),
        ("y_inv fixed at 0", base, true),
    ]

    # Wrapped in a function: @testitem bodies run as top-level code (soft scope).
    function run_case(kw, fix_y0, safety)
        kkt = build_bilevel_kkt(feeder, LinDistFlow(); kw..., safety = safety)
        fix_y0 && fix(kkt.y_inv, 0.0; force = true)
        err = nothing
        r = try
            solve_bilevel!(kkt)
        catch e
            err = e
            nothing
        end
        return r, err
    end

    atol = 1e-6
    for (label, kw, fix_y0) in cases, safety in (10.0, 1.0)
        r, err = run_case(kw, fix_y0, safety)
        @test err === nothing
        r === nothing && (@info "CR-01 regression threw" label safety err; continue)
        @test isapprox(r.y, 0.0; atol = atol)
        @test isapprox(r.x_inv, 0.0; atol = atol)
        @test isapprox(r.z[1], 0.0; atol = atol)
        @test isapprox(r.total_cost, 0.0; atol = atol)
    end
end
