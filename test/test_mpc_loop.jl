# test/test_mpc_loop.jl
#
# Seam: MPC-03/MPC-04 — end-to-end regression for run_mpc(scenario), the receding-horizon
# closed-loop orchestrator (plan 21-05). Every item name contains "mpc_loop", tagged
# [:mpc_loop], setup = [Phase21Fixtures]. Covers: (1) the happy-path CI fixture never
# escalating, a populated trace, and a finite regret; (2) the forced-inexact high-PV fixture
# genuinely tripping the inline cone check and escalating through Phase-20's ladder WITHOUT
# throwing (D-04); (3) s.mpc_step genuinely striding the resolve cadence — a measured
# behavioral difference, never a silently-inert kwarg (D-03, checker revision 1).
#
# Per this project's mandatory testing constraint, this file's bodies were each verified as
# standalone plain Test.jl scripts under --project=. before being committed here — TestItemRunner
# discovery/execution is deferred to the phase-closing plan 21-06.

@testitem "mpc_loop: end-to-end closed loop on the happy-path CI fixture — trace populated, regret finite, never escalates (MPC-03)" tags =
    [:mpc_loop] setup = [Phase21Fixtures] begin
    using TSODSO, Test

    # SCENARIO_VALID_FEEDERS only covers :ieee13/:ieee123 — Phase21Fixtures' own 2-bus
    # fixture is not addressable via Scenario. The default :ieee13/:default population at a
    # short T (T=9, the smallest value at which materialize.jl's :default population's
    # Deferrable device remains constructible — see mpc_loop.jl's own header deviation note)
    # and mpc_H=3 genuinely reproduces a comparably small, fast CI-scale closed loop, so this
    # item drives run_mpc directly (the plan's preferred path) rather than duplicating the
    # loop mechanics by hand.
    s = Scenario(;
        name = "mpc_loop_happy",
        feeder = :ieee13,
        T = 9,
        mpc_H = 3,
        mpc_terminal_soc = true,
        mpc_forecast_error = 0.0,
    )
    r = run_mpc(s)

    @test r.trace.steps == r.steps
    @test r.steps == 9 - 3 + 1
    @test all(==(:certified_convex_dual), r.trace.cert_status_trace)
    @test all(isfinite, (r.day_ahead_welfare, r.realized_welfare, r.regret))
    @test all(isfinite, r.day_ahead_dadp)
    @test length(r.trace.dadp_trace) == r.steps
end

@testitem "mpc_loop: forced-inexact window escalates through Phase-20's ladder WITHOUT throwing (MPC-04, D-04)" tags =
    [:mpc_loop] setup = [Phase21Fixtures] begin
    using TSODSO, Test
    using JuMP: set_parameter_value, set_objective_coefficient

    # Drive the SAME per-resolve certificate/escalation logic run_mpc's own loop calls
    # (_mpc_certify_and_price, factored out in plan 21-05 Task 2 for exactly this purpose)
    # directly against Phase21Fixtures' high-PV fixture at the MEASURED pv_scale — this
    # fixture's custom 3-bus feeder is not addressable via Scenario, so run_mpc itself cannot
    # be called here; build_mpc_window/solve_mpc_window! are driven by hand, mirroring
    # test_mpc_terminal.jl's own driving pattern.
    feeder = Phase21Fixtures.mpc_high_pv_feeder()
    aggs = Phase21Fixtures.build_mpc_high_pv_aggregators(
        feeder;
        pv_scale = Phase21Fixtures.MPC_HIGH_PV_SCALE_MEASURED,
    )
    H = Phase21Fixtures.H
    λ₀ = Phase21Fixtures.mpc_lambda0()

    o = build_mpc_window(feeder, ConvexBranchFlow(), aggs; H = H, terminal_soc = false)
    for agg in aggs
        varlist = o.ctx.meta[:agg_device_vars][agg.bus]
        for (d, v) in zip(agg.devices, varlist)
            haskey(v, :Ppv_param) && set_parameter_value.(v.Ppv_param, d.Ppv[1:H])
            haskey(v, :Tout_param) && set_parameter_value.(v.Tout_param, d.Tout[1:(H - 1)])
        end
    end
    for handle in o.agg_pdc_handles
        agg = only(a for a in aggs if a.bus == handle.bus)
        set_parameter_value.(handle.Pdc_param, agg.Pdc[1:H])
    end
    for τ in 1:H
        set_objective_coefficient(o.model, o.p_import[τ], -λ₀[τ])
    end
    solve_mpc_window!(o)

    # Pre-condition check (reusing Task 2's own verify-script methodology, not just trusting
    # the constant): the measured pv_scale genuinely trips the inline check on THIS solve.
    result = TSODSO._mpc_certify_and_price(feeder, aggs, o, λ₀, 1)

    @test result.cone_maxratio > 1     # the pre-condition: this call's inline check DID fail
    @test result.cert_status in (:certified_convex_dual, :local_ac_dual)   # escalation resolved it
    @test length(result.price_vec) == H
    @test all(isfinite, result.price_vec)
    # The call above completing (no exception propagated to this point) IS the D-04 assertion
    # — a bare @test wrapping a call that throws would itself error out of this test item, so
    # simply reaching this line already demonstrates the never-throw contract; the explicit
    # `@test true` below documents that intent for a human reader.
    @test true   # never threw
end

@testitem "mpc_loop: mpc_step genuinely strides the resolve cadence — NOT a silently-inert kwarg (D-03, checker revision 1)" tags =
    [:mpc_loop] setup = [Phase21Fixtures] begin
    using TSODSO, Test

    base = (;
        name = "mpc_loop_stride",
        feeder = :ieee13,
        T = 9,
        mpc_H = 3,
        mpc_terminal_soc = true,
        mpc_forecast_error = 0.05,
    )
    s_step1 = Scenario(; base..., mpc_step = 1)
    s_step2 = Scenario(; base..., mpc_step = 2)

    r_step1 = run_mpc(s_step1)
    r_step2 = run_mpc(s_step2)

    @test r_step1.steps == 9 - 3 + 1
    @test r_step2.steps == r_step1.steps
    @test r_step1.trace.steps == r_step1.steps
    @test r_step2.trace.steps == r_step1.steps

    s_bad = Scenario(; base..., mpc_H = 3, mpc_step = 5)
    @test_throws ArgumentError run_mpc(s_bad)

    @info "mpc_loop mpc_step stride measured difference" r_step1.realized_welfare r_step2.realized_welfare r_step1.regret r_step2.regret r_step1.trace.dadp_trace r_step2.trace.dadp_trace

    # LOAD-BEARING assertion (D-03, checker revision 1): mpc_step must produce a genuinely
    # different closed-loop trajectory, not merely a different `steps` bookkeeping value.
    # Measured directly (never assumed): at mpc_forecast_error=0.05 on this fixture, the two
    # runs' realized_welfare AND dadp_trace both differ (see @info above for the measured
    # values) — no need to widen the fixture further.
    @test r_step1.realized_welfare != r_step2.realized_welfare
    @test r_step1.trace.dadp_trace != r_step2.trace.dadp_trace
end
