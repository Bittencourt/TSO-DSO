# test/test_planning_alpha_bounds_stackelberg.jl
#
# Seam: src/planning/benders.jl's `solve_stackelberg!` (BILEV-05, plan 30-04 Task 2) —
# the UNCONDITIONAL `bounds_ctx` wiring. Covers the three acceptance-criteria items this
# plan's own PLAN.md Task 2 specifies: (1) an absurdly-high explicit `α_op_lb` is
# REJECTED at build time, BEFORE any Benders iteration runs; (2) a pre-existing valid
# explicit bound still converges with zero regression; (3) a pre-built `follower` with NO
# sound `α_x_lb` derivation (`DistributorView`, `run_nash!`'s own production path) is
# ACCEPTED, not rejected, while `α_op_lb` remains validated regardless of follower type.
# Items tagged `[:planning]`, names contain "planning" and "alpha" (occursin filter
# convention, mirrors test_planning_master.jl's own BILEV-05 items).

@testitem "planning alpha bounds stackelberg: bounds_ctx validation rejects an over-high explicit α_op_lb at build time" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]
    follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])
    # α_op_lb = 1e9 is absurdly high relative to ANY derived minimum on this fixture
    # (test_planning_master.jl's own probe gives a derived minimum on the order of a few
    # units at this scale) — build_master's bounds_ctx rejection must fire BEFORE any
    # Benders iteration.
    master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = 1.0e9, α_x_lb = 0.0)

    mktempdir() do dir
        @test_throws ArgumentError solve_stackelberg!(
            feeder,
            LinDistFlow(),
            [agg];
            λ₀ = λ₀,
            T = 1,
            follower_kwargs = follower_kwargs,
            master_kwargs = master_kwargs,
            tol = 1e-6,
            max_iter = 100,
            checkpoint_dir = dir,
        )
        # The throw happens at build time (inside build_master, BEFORE the
        # `for k in 1:max_iter` loop) — no checkpoint file is ever written.
        @test isempty(readdir(dir))
    end
end

@testitem "planning alpha bounds stackelberg: a valid explicit bound converges with zero regression" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    # test_planning_benders.jl's own T=1 toy fixture literal, reused VERBATIM — this is
    # the SAME call site 30-02-SUMMARY.md's own audit already confirmed valid
    # (α_op_lb=-5.0 accepted at T=1 by the new derivation formula).
    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]
    follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])
    master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)

    mktempdir() do dir
        result = solve_stackelberg!(
            feeder,
            LinDistFlow(),
            [agg];
            λ₀ = λ₀,
            T = 1,
            follower_kwargs = follower_kwargs,
            master_kwargs = master_kwargs,
            tol = 1e-6,
            max_iter = 100,
            checkpoint_dir = dir,
        )

        @test result.gap <= 1e-6
        # LinDistFlow never stashes :l, so solve_planning_oracle! never throws from
        # exactness there — the AC-recheck-at-convergence hook (BILEV-04b) must find the
        # incumbent genuinely exact and report ac_report = nothing.
        @test result.ac_report === nothing
        # CR-02/IN-04: on LinDistFlow the exactness gate never runs — "not checked",
        # reported as such, never as "certified exact".
        @test result.incumbent_exactness === :not_applicable
        @test !result.ub_relaxation_only
    end
end

@testitem "planning alpha bounds stackelberg: a pre-built follower with no sound α_x_lb derivation (DistributorView) is accepted, not rejected — α_op_lb is still validated" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    using TSODSO: activate_distributor!

    # Mirrors test_planning_nash.jl's own N=2, T=1 toy fixture shape: distributor 1 is
    # the one actually solved against (activate_distributor!), distributor 2 stays
    # pinned at the build-time default x_inv=0 — matching this plan's own <interfaces>
    # item (3) recipe (`build_shared_transmission(; N=2, T=1, ...)`,
    # `follower = DistributorView(shared, 1)`).
    shared = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [2.0, 2.0],
        c_inv = [1.0, 1.0],
        c_op = [[0.5], [0.5]],
    )
    activate_distributor!(shared, 1)

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]

    mktempdir() do dir
        # A valid explicit bound, pre-built DistributorView follower: must NOT throw —
        # checker BLOCKER 2's fix (solve_stackelberg! never rejects a pre-built follower)
        # — and must still converge.
        result = solve_stackelberg!(
            feeder,
            LinDistFlow(),
            [agg];
            λ₀ = λ₀,
            T = 1,
            follower_kwargs = NamedTuple(),
            master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
            tol = 1e-6,
            max_iter = 100,
            checkpoint_dir = dir,
            follower = DistributorView(shared, 1),
        )
        @test result.gap <= 1e-6
    end

    # SAME pre-built-follower call, but an absurdly-high α_op_lb: α_op_lb's build-time
    # validation is UNCONDITIONAL regardless of the follower type (checker BLOCKER 1) —
    # this must STILL throw ArgumentError, confirming α_x_lb's honest skip for
    # DistributorView does NOT also silently skip α_op_lb's own check.
    @test_throws ArgumentError solve_stackelberg!(
        feeder,
        LinDistFlow(),
        [agg];
        λ₀ = λ₀,
        T = 1,
        follower_kwargs = NamedTuple(),
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = 1.0e9, α_x_lb = 0.0),
        tol = 1e-6,
        max_iter = 100,
        follower = DistributorView(shared, 1),
    )
end

@testitem "planning alpha bounds stackelberg: an explicit bound accepted inside the build-time slack is CLAMPED and never trips the runtime floor at the box argmax (Option A, Phase 31 WR-05/WR-03, Plan 31-07)" tags =
    [:planning] setup = [IEEE13ShortHorizonFixtures] begin
    using TSODSO
    using TSODSO: build_master
    using JuMP: value, lower_bound

    # Phase 30 code review iteration 2 (WR-05). Build time accepts an explicit α_op_lb up
    # to optimum + S; the runtime floor used to test only against the pinned solve's own
    # tolerance tol_k, which is far smaller than S. MEASURED 2026-10-01 (scratchpad
    # fix2/probe_wr05.jl), IEEE13ShortHorizonFixtures T=4, ConvexBranchFlow, y_max=0.05:
    #   derivation: optimum = 609.0096500784123, gap = 1.525e-6, S = 1.525e-5;
    #   pinned oracle at the box argmax (z ≈ [0.00544, 0, 0, 0.05], SOCP-exact):
    #   cost_k = optimum − 1.68e-7, gap_k = 1.94e-7, tol_k = 6.09e-6.
    # With α = optimum + S/2 (accepted), cost_k < α − tol_k: the old runtime rule fired a
    # "modeling bug" on a bound build_master had just accepted.
    feeder = TSODSO.ieee13_modified()
    aggs = IEEE13ShortHorizonFixtures.population(feeder)
    λ₀ = IEEE13ShortHorizonFixtures.LAMBDA0
    T = IEEE13ShortHorizonFixtures.T
    y_max = 0.05
    pf = ConvexBranchFlow()

    d = TSODSO.alpha_op_lb_derivation(feeder, pf, aggs; λ₀ = λ₀, T = T, y_max = y_max)
    S = TSODSO.alpha_lb_margin(d.optimum, d.gap; floor = TSODSO.ALPHA_LB_REJECTION_TOL)
    α = d.optimum + S / 2

    fk = (; corridor_cap = 1.0, x_inv_max = 0.05, c_inv = 0.01, c_op = fill(0.01, T))
    bounds_ctx = (; feeder, pf, aggregators = aggs, λ₀, follower_kwargs = fk)
    m = build_master(; T = T, c_y = 0.01, y_max = y_max, α_op_lb = α, α_x_lb = 0.0, bounds_ctx)
    # Option A (Phase 31 WR-03, Plan 31-07): the accepted-but-in-slack bound is CLAMPED
    # down to the certified minimum d.bound, NEVER installed at the raw requested α.
    @test lower_bound(m.α_op) == d.bound
    @test m.lb_clamped.op ≈ α - d.bound
    @test m.lb_clamped.op > 0.0
    # lb_slack is now ALWAYS zero — no residual runtime floor slack is ever needed again.
    @test m.lb_slack == (; op = 0.0, x = 0.0)

    # The box argmax, and the pinned oracle's own value there.
    rm = TSODSO.make_relaxed_oracle_model(feeder, pf, aggs; λ₀ = λ₀, T = T, y_max = y_max)
    TSODSO.solve_with_retry!(rm; dual = true)
    zstar = value.(rm[:p_import])
    o = TSODSO.build_planning_oracle(feeder, pf, aggs; λ₀ = λ₀, T = T)
    r = TSODSO.solve_planning_oracle!(o, zstar; on_inexact = :report)
    gk = TSODSO._measured_duality_gap(o.model)
    cost_k = -r.cost
    tol_k = TSODSO.alpha_lb_margin(cost_k, gk; floor = TSODSO.ALPHA_LB_REJECTION_TOL)
    # The regime of the finding: the accepted bound sits above cost_k by more than tol_k.
    @test cost_k < α - tol_k
    # Old rule (no accepted slack), raw unclamped α: a false "modeling bug" — this proof
    # that the finding is genuine and demonstrable is KEPT UNCHANGED (the raw, unclamped α
    # is passed directly, never lower_bound(m.α_op)).
    @test_throws ErrorException TSODSO._assert_epigraph_floor(cost_k, α, :op; gap = gk)
    # Option A (Phase 31 WR-03, Plan 31-07): the PRODUCTION path uses the INSTALLED
    # (clamped) bound lower_bound(m.α_op), never the raw α — with accepted_slack = 0.0
    # (the default, since _accepted_lb_slack now always returns 0.0), no error fires.
    @test TSODSO._assert_epigraph_floor(
        cost_k,
        lower_bound(m.α_op),
        :op;
        gap = gk,
        accepted_slack = TSODSO._accepted_lb_slack(m, :op),
    ) === nothing
    # A value clearly below the derivation's own certified lower bound still fires.
    @test_throws ErrorException TSODSO._assert_epigraph_floor(
        d.optimum - 10 * (S + abs(d.gap)),
        lower_bound(m.α_op),
        :op;
        gap = gk,
        accepted_slack = TSODSO._accepted_lb_slack(m, :op),
    )
    # :auto bounds carry no slack (they already sit below the optimum).
    m_auto = build_master(; T = T, c_y = 0.01, y_max = y_max, bounds_ctx)
    @test m_auto.lb_slack == (; op = 0.0, x = 0.0)
end
