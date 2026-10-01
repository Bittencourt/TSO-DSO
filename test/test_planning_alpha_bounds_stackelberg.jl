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
    end
end

@testitem "planning alpha bounds stackelberg: a pre-built follower with no sound α_x_lb derivation (DistributorView) is accepted, not rejected — α_op_lb is still validated" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

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
