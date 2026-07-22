# test/test_planning_benders.jl
#
# Seam: src/planning/benders.jl (PLAN-06). `solve_stackelberg!` (Task 1) wires the
# reused operational oracle (PlanningOracle, Phase 10), the new transmission-
# reinforcement follower (FollowerLP, plan 11-01), and the new Benders master
# (BendersMaster, plan 11-01) into a single hand-rolled Benders loop, converging
# end-to-end on the Phase-11 toy fixture within a documented relative UB/LB gap
# tolerance, checkpointing every iteration, and raising loudly on iteration-cap
# exhaustion. Items tagged `[:planning]`, names contain "planning" and "benders"
# (occursin filter convention, mirrors test_planning_follower.jl/test_planning_master.jl).
#
# Toy fixture (11-01-PLAN.md's own <toy_fixture> block, reused verbatim): T=1,
# feeder=Phase6Fixtures.two_bus_feeder(), λ₀=[4.0],
# dev=ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0),
# agg=TSODSO.Aggregator(2, 0.9, [dev], [0.0]); follower corridor_cap=2.0,
# x_inv_max=2.0, c_inv=1.0, c_op=[0.5]; master c_y=0.3, y_max=8.0, α_op_lb=-5.0,
# α_x_lb=0.0.
#
# `ToyDeviceFixture` is the `@testmodule` defined in test_planning_oracle.jl (the
# SAME toy elastic device the oracle's own dual-sign/monotonicity regression uses)
# — reused here via `setup = [Phase6Fixtures, ToyDeviceFixture]`, never redefined.
#
# EXPECTED OPTIMUM — RE-DERIVED, NOT 11-01-PLAN.md's STATED y*=1.0/z*=1.0/cost=-0.2
# (Task 2's own escape hatch: "if the converged values are qualitatively wrong ...
# that is a genuine bug ... [otherwise] widen atol and document why", NOT force a
# match by changing benders.jl's cut-sign logic). On THIS exact fixture, the
# leader's total minimization (with y == z at the minimal-investment optimum, since
# c_y > 0 and the box is z <= y_inv with no benefit to slack) is the UNCONSTRAINED
# convex quadratic `total(z) = c_y*z + m_f*z - welfare(z)` with
# `welfare(z) = (a-λ₀)*z - (b/2)*z^2 = 2z - 0.5z^2` (11-01-PLAN.md's own closed
# form) and `m_f = 1.0` (11-01-PLAN.md's own follower marginal cost): substituting,
# `total(z) = 0.5*z^2 - 0.7*z`, whose first-order condition `z - 0.7 = 0` gives
# `z* = (a - λ₀ - c_y - m_f)/b = (6 - 4 - 0.3 - 1.0)/1.0 = 0.7`, NOT `1.0`
# (verified: `total(0.7) = -0.245 < total(1.0) = -0.2`, i.e. 11-01-PLAN.md's stated
# z*=1.0 is not even a local minimizer of the fixture IT defines — an arithmetic
# slip in that plan's own <toy_fixture> block, not a defect in this plan's
# `solve_stackelberg!`). This test asserts against the RE-DERIVED, verified
# `y* = z* = 0.7`; plan 11-03's BilevelJuMP certification gate should
# independently re-derive (not blindly reuse) 11-01-PLAN.md's stated numbers —
# flagged in this plan's own SUMMARY.md as a deviation for the next plan to see.

@testitem "planning benders: converges end-to-end with documented UB/LB gap, matches the re-derived analytic optimum (z*=0.7)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

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
        # Re-derived analytic optimum z* = 0.7 (see file header) — NOT 11-01-PLAN.md's
        # stated z*=1.0, which is not a stationary point of this fixture's own cost
        # function.
        @test isapprox(result.y, 0.7; atol = 1e-3)
        @test isapprox(result.z[1], 0.7; atol = 1e-3)

        # CR-01 incumbent regression: the RETURNED (y, z) must be the point CERTIFIED by
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
    end
end

@testitem "planning benders: max_iter=1 raises loudly (ErrorException, 'exhausted'), never returns a non-converged result" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
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
        @test err isa ErrorException
        @test occursin("exhausted", err.msg)
    end
end
