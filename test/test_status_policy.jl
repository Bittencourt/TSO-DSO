# test/test_status_policy.jl
#
# Seam: status-vs-throw policy. `STATUS_VOCABULARY` is the single
# source of the per-entry-point `status::Symbol` vocabulary; every entry point's returned status
# must lie inside its documented vocabulary. Also pins (WITHOUT a throw) the DC + reactive
# aggregators behaviour behind the `has_reactive` guard deferral.

@testitem "status policy: STATUS_VOCABULARY table and pure status helpers" tags =
    [:status_policy] begin
    using TSODSO

    V = TSODSO.STATUS_VOCABULARY
    @test V.solve_admm == (:converged, :budget_exceeded)
    @test V.solve_stackelberg == (:converged, :converged_relaxation_only)
    @test V.run_nash == (:converged, :converged_relaxation_only)
    @test V.run_mpc == (:certified, :degraded, :cert_failed)
    @test V.run_stochastic == (:solved, :oos_infeasible_skipped)

    @test TSODSO._mpc_status([:certified_convex_dual, :certified_convex_dual]) == :certified
    @test TSODSO._mpc_status([:certified_convex_dual, :certified_convex_dual_restricted]) ==
          :degraded
    @test TSODSO._mpc_status([:certified_convex_dual, :local_ac_dual]) == :degraded
    @test TSODSO._mpc_status([:local_ac_dual, :cert_failed]) == :cert_failed
    @test TSODSO._mpc_status([:certified_convex_dual, :cert_failed]) == :cert_failed

    @test TSODSO._stochastic_status([false, false]) == :solved
    @test TSODSO._stochastic_status([false, true]) == :oos_infeasible_skipped
end

@testitem "status policy: solve_stackelberg! and run_nash! status within vocabulary" tags =
    [:status_policy, :planning] setup = [TwoBusFixtures, ToyDeviceFixture] begin
    using TSODSO

    V = TSODSO.STATUS_VOCABULARY
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)

    function run_stackelberg()
        mktempdir() do dir
            return solve_stackelberg!(
                TwoBusFixtures.two_bus_feeder(),
                LinDistFlow(),
                [agg];
                λ₀ = [4.0],
                T = 1,
                follower_kwargs = (;
                    corridor_cap = 2.0,
                    x_inv_max = 2.0,
                    c_inv = 1.0,
                    c_op = [0.5],
                ),
                master_kwargs = master_kwargs,
                tol = 1e-6,
                max_iter = 100,
                checkpoint_dir = dir,
            )
        end
    end
    r = run_stackelberg()
    @test r.status in V.solve_stackelberg
    @test r.status == (r.ub_relaxation_only ? :converged_relaxation_only : :converged)

    function run_nash_small()
        shared = build_shared_transmission(;
            N = 2,
            T = 1,
            corridor_cap = 2.0,
            x_inv_max = [0.3, 0.3],
            c_inv = [1.0, 1.0],
            c_op = [[0.5], [0.5]],
        )
        spec = (;
            feeder = TwoBusFixtures.two_bus_feeder(),
            pf = LinDistFlow(),
            aggregators = [agg],
            λ₀ = [4.0],
            master_kwargs = master_kwargs,
        )
        return run_nash!(
            [spec, spec],
            shared;
            z0 = zeros(2, 1),
            tol_outer = 1e-4,
            max_sweeps = 50,
            checkpoint_dir = mktempdir(),
        )
    end
    n = run_nash_small()
    @test n.converged
    @test n.status in V.run_nash
    @test n.status == (n.any_relaxation_only ? :converged_relaxation_only : :converged)
end

@testitem "status policy: run_mpc and run_stochastic status within vocabulary" tags =
    [:status_policy, :mpc_loop] begin
    using TSODSO

    V = TSODSO.STATUS_VOCABULARY
    m = run_mpc(
        Scenario(;
            name = "status_mpc",
            feeder = :ieee13,
            T = 9,
            strategy = MPC(H = 3, terminal_soc = true, forecast_error = 0.0),
        ),
    )
    @test m.status in V.run_mpc
    @test m.status == :certified   # happy path: every step first tier

    st = run_stochastic(
        Scenario(
            name = "status_stoch",
            feeder = :ieee13,
            T = 9,
            strategy = Stochastic(S = 3, H_oos = 5),
        ),
    )
    @test st.status in V.run_stochastic
    @test st.status == (any(st.oos.infeasible_h) ? :oos_infeasible_skipped : :solved)
end

@testitem "status policy: DC + reactive aggregators pinned as documented degradation (no throw)" tags =
    [:status_policy] setup = [ExperimentHarnessFixtures] begin
    using TSODSO, JuMP

    # Aggregators write reactive terms unconditionally; DCPowerFlow is active-only by design,
    # so the unclosed `:Rq` residual is a documented degradation, NOT a bug — no throw, no
    # status (the has_reactive guard deferral is decided as "pin, don't throw").
    function solve_dc()
        s = TSODSO.Scenario(;
            ExperimentHarnessFixtures.minimal_scenario_kwargs()...,
            strategy = :admm,
        )
        feeder, λ₀, aggs = TSODSO._materialize(s)
        return solve_welfare(
            feeder,
            DCPowerFlow(),
            aggs;
            T = 24,
            λ₀ = λ₀,
            allow_export = true,
        )
    end
    ctx, obj, _ = solve_dc()
    @test termination_status(ctx.model) == MOI.OPTIMAL
    @test isapprox(obj, -4819.9377763808125; rtol = 1e-12)
    @test !TSODSO.has_reactive(DCPowerFlow())
    @test haskey(ctx.residuals, :Rq)
    @test !haskey(ctx.constraints, :balance_q)
end
