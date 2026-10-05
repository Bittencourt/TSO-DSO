# test/test_planning_benders.jl
#
# Seam: src/planning/benders.jl. `solve_stackelberg!` wires the
# reused operational oracle (PlanningOracle), the transmission-
# reinforcement follower (FollowerLP), and the Benders master
# (BendersMaster) into a single hand-rolled Benders loop, converging
# end-to-end on the toy fixture within a documented relative UB/LB gap
# tolerance, checkpointing every iteration, and raising loudly on iteration-cap
# exhaustion. Items tagged `[:planning]`, names contain "planning" and "benders"
# (occursin filter convention, mirrors test_planning_follower.jl/test_planning_master.jl).
#
# Toy fixture (reused verbatim): T=1,
# feeder=TwoBusFixtures.two_bus_feeder(), λ₀=[4.0],
# dev=ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0),
# agg=TSODSO.Aggregator(2, 0.9, [dev], [0.0]); follower corridor_cap=2.0,
# x_inv_max=2.0, c_inv=1.0, c_op=[0.5]; master c_y=0.3, y_max=8.0, α_op_lb=-5.0,
# α_x_lb=0.0.
#
# `ToyDeviceFixture` is the `@testmodule` defined in test_planning_oracle.jl (the
# SAME toy elastic device the oracle's own dual-sign/monotonicity regression uses)
# — reused here via `setup = [TwoBusFixtures, ToyDeviceFixture]`, never redefined.
#
# EXPECTED OPTIMUM — RE-DERIVED, NOT the originally stated y*=1.0/z*=1.0/cost=-0.2
# (if the converged values are qualitatively wrong ... that is a genuine bug ...
# [otherwise] widen atol and document why; do NOT force a
# match by changing benders.jl's cut-sign logic). On THIS exact fixture, the
# leader's total minimization (with y == z at the minimal-investment optimum, since
# c_y > 0 and the box is z <= y_inv with no benefit to slack) is the UNCONSTRAINED
# convex quadratic `total(z) = c_y*z + m_f*z - welfare(z)` with
# `welfare(z) = (a-λ₀)*z - (b/2)*z^2 = 2z - 0.5z^2` (closed
# form) and `m_f = 1.0` (the follower marginal cost): substituting,
# `total(z) = 0.5*z^2 - 0.7*z`, whose first-order condition `z - 0.7 = 0` gives
# `z* = (a - λ₀ - c_y - m_f)/b = (6 - 4 - 0.3 - 1.0)/1.0 = 0.7`, NOT `1.0`
# (verified: `total(0.7) = -0.245 < total(1.0) = -0.2`, i.e. z*=1.0
# is not even a local minimizer of this fixture — an arithmetic
# slip in the originally stated optimum, not a defect in
# `solve_stackelberg!`). This test asserts against the RE-DERIVED, verified
# `y* = z* = 0.7`; the BilevelJuMP certification gate should
# independently re-derive (not blindly reuse) the originally stated numbers.

@testitem "planning benders: converges end-to-end with documented UB/LB gap, matches the re-derived analytic optimum (z*=0.7)" tags =
    [:planning] setup = [TwoBusFixtures, ToyDeviceFixture] begin
    using TSODSO
    using TSODSO: solve_follower!, solve_planning_oracle!

    feeder = TwoBusFixtures.two_bus_feeder()
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
        # Re-derived analytic optimum z* = 0.7 (see file header) — NOT the originally
        # stated z*=1.0, which is not a stationary point of this fixture's own cost
        # function.
        @test isapprox(result.y, 0.7; atol = 1e-3)
        @test isapprox(result.z[1], 0.7; atol = 1e-3)

        # Incumbent regression: the RETURNED (y, z) must be the point CERTIFIED by
        # UB — its true cost c_y*y + φ_x(z) - W(z), recomputed by re-solving both
        # subproblems at the returned z, equals result.UB. Returning the last master
        # iterate instead of the incumbent breaks this identity by an amount NOT bounded
        # by tol.
        f_res = solve_follower!(result.follower, result.z)
        @test f_res.feasible
        o_res = solve_planning_oracle!(result.oracle, result.z)
        true_cost = result.master.c_y * result.y + f_res.cost - o_res.cost
        @test isapprox(true_cost, result.UB; atol = 1e-6)

        checkpoint_files = filter(
            f -> occursin(r"^iter_\d{5}\.jld2$", basename(f)),
            readdir(dir; join = true),
        )
        @test length(checkpoint_files) == result.iters

        # BendersTrace assertions — structurally distinct from
        # AdmmResiduals (single relative-gap scalar), including the GENUINE
        # per-iteration retry_count and both retry-gated subproblems' statuses.
        @test result.trace isa TSODSO.BendersTrace
        @test result.trace.iters == result.iters
        @test length(result.trace.gap_trace) == result.iters
        @test result.trace.cut_type_trace[end] == :optimality
        @test TSODSO.is_converged(result.trace, 1e-6)
        @test result.trace.n_cuts_trace[end] == length(result.master.cuts)
        @test length(result.trace.retry_count_trace) == result.iters
        @test all(result.trace.retry_count_trace .>= 0)
        # The LAST row is :optimality (per the assertion above), so the oracle was
        # solved and its status recorded, never the sentinel.
        @test result.trace.oracle_status_trace[end] != :not_solved
        # Regression: master_status_trace must record
        # the GENUINE post-solve termination status, captured BEFORE any add_*_cut!
        # dirties the CACHING-mode master model — a dirty model short-circuits
        # termination_status to :OPTIMIZE_NOT_CALLED, turning the ledger column into
        # a constant sentinel. On this clean converging run every master solve (and
        # the final oracle solve) is genuinely :OPTIMAL.
        @test all(==(:OPTIMAL), result.trace.master_status_trace)
        @test result.trace.oracle_status_trace[end] == :OPTIMAL
    end
end

@testitem "planning benders: feasibility-cut branch — an undeliverable master trial routes to a Farkas cut and the loop still converges" tags =
    [:planning] setup = [TwoBusFixtures, ToyDeviceFixture] begin
    using TSODSO

    feeder = TwoBusFixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]
    # Deliverable capacity SHRUNK to corridor_cap * x_inv_max = 2.0 * 0.25 = 0.5 —
    # BELOW both the unconstrained optimum z* = 0.7 (see file header) and the master's
    # early cut-driven trials, so the Benders loop MUST pass through at least one
    # follower-infeasible trial z_k > 0.5 and recover via the production feasibility-cut
    # branch (previously structurally unreachable in every end-to-end test).
    follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 0.25, c_inv = 1.0, c_op = [0.5])
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

        # The production feasibility-cut branch actually ran: at least one appended cut
        # is a Farkas feasibility cut (not merely the unit-tested appender in isolation).
        @test any(c -> c.kind == :feasibility, result.master.cuts)

        # The loop still converges, to the BOUNDARY optimum: total(z) = 0.5z^2 - 0.7z is
        # decreasing on [0, 0.7], so the deliverable cap z = 0.5 binds and y* = z* = 0.5.
        @test result.gap <= 1e-6
        @test isapprox(result.y, 0.5; atol = 1e-3)
        @test isapprox(result.z[1], 0.5; atol = 1e-3)

        # Checkpoint invariant holds ACROSS feasibility iterations too:
        # checkpoint_iteration! fires exactly once per iteration on BOTH branches.
        checkpoint_files = filter(
            f -> occursin(r"^iter_\d{5}\.jld2$", basename(f)),
            readdir(dir; join = true),
        )
        @test length(checkpoint_files) == result.iters

        # BendersTrace assertions on the feasibility-branch fixture —
        # matching the existing production feasibility-cut assertion above.
        @test count(==(:feasibility), result.trace.cut_type_trace) >= 1
        # Cut-store growth is monotone non-decreasing, never shrinks.
        @test all(diff(result.trace.n_cuts_trace) .>= 0)
        # A feasibility-branch row's oracle_status is exactly the sentinel — the
        # oracle was never reached on that iteration.
        k_feas = findfirst(==(:feasibility), result.trace.cut_type_trace)
        @test result.trace.oracle_status_trace[k_feas] == :not_solved
        @test all(result.trace.retry_count_trace .>= 0)
    end
end

@testitem "planning benders: tol/max_iter boundary guards reject NaN/negative tol and max_iter > 99_999 before any build call" tags =
    [:planning] setup = [TwoBusFixtures, ToyDeviceFixture] begin
    using TSODSO

    feeder = TwoBusFixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]
    follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])
    master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)

    # Cheap: the guards fire before any build_* call, so no solver is ever invoked.
    @test_throws ArgumentError solve_stackelberg!(
        feeder,
        LinDistFlow(),
        [agg];
        λ₀ = λ₀,
        T = 1,
        follower_kwargs = follower_kwargs,
        master_kwargs = master_kwargs,
        tol = NaN,
        max_iter = 100,
    )
    @test_throws ArgumentError solve_stackelberg!(
        feeder,
        LinDistFlow(),
        [agg];
        λ₀ = λ₀,
        T = 1,
        follower_kwargs = follower_kwargs,
        master_kwargs = master_kwargs,
        tol = -1.0,
        max_iter = 100,
    )
    @test_throws ArgumentError solve_stackelberg!(
        feeder,
        LinDistFlow(),
        [agg];
        λ₀ = λ₀,
        T = 1,
        follower_kwargs = follower_kwargs,
        master_kwargs = master_kwargs,
        tol = 1e-6,
        max_iter = 100_000,
    )
end

@testitem "planning benders: max_iter=1 raises loudly (ConvergenceError, 'exhausted'), never returns a non-converged result" tags =
    [:planning] setup = [TwoBusFixtures, ToyDeviceFixture] begin
    using TSODSO

    feeder = TwoBusFixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]
    follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])
    master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)

    mktempdir() do dir
        err = nothing
        try
            solve_stackelberg!(
                feeder,
                LinDistFlow(),
                [agg];
                λ₀ = λ₀,
                T = 1,
                follower_kwargs = follower_kwargs,
                master_kwargs = master_kwargs,
                tol = 1e-6,
                max_iter = 1,
                checkpoint_dir = dir,
            )
        catch e
            err = e
        end
        @test err isa ConvergenceError
        @test occursin("exhausted", err.msg)
        # The message now sources from the trace, not a stale
        # loop-local gap.
        @test occursin("last recorded LB", err.msg)
    end
end
