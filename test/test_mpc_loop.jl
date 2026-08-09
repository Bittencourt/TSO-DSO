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

    # CR-01: _mpc_certify_and_price now REQUIRES the resolve's measured state + forecast
    # draw so an escalation prices the SAME window the failed resolve solved. At t = 1 with
    # the initial device state and no forecast error, these are the devices' own literals.
    ms = Dict{Tuple{Int, Symbol}, Float64}()
    for agg in aggs, d in agg.devices
        hasproperty(d, :soc0) && (ms[(agg.bus, :soc)] = Float64(d.soc0))
        hasproperty(d, :Tin0) && (ms[(agg.bus, :Tin)] = Float64(d.Tin0))
    end
    fe = (; pv_factor = 1.0, demand_factor = 1.0)

    # Pre-condition check (reusing Task 2's own verify-script methodology, not just trusting
    # the constant): the measured pv_scale genuinely trips the inline check on THIS solve.
    result = TSODSO._mpc_certify_and_price(feeder, aggs, o, λ₀, 1; measured_state = ms, fe = fe)

    @test result.cone_maxratio > 1     # the pre-condition: this call's inline check DID fail
    # escalation resolved it — WR-04: the restricted-tier rescue carries its OWN symbol,
    # DISTINCT from a first-tier :certified_convex_dual certification.
    @test result.cert_status in (:certified_convex_dual_restricted, :local_ac_dual)
    @test length(result.price_vec) == H
    @test all(isfinite, result.price_vec)
    # The call above completing (no exception propagated to this point) IS the D-04 assertion
    # — a bare @test wrapping a call that throws would itself error out of this test item, so
    # simply reaching this line already demonstrates the never-throw contract; the explicit
    # `@test true` below documents that intent for a human reader.
    @test true   # never threw
end

@testitem "mpc_loop: escalation at t > 1 prices the CURRENT window — same t-sliced profiles, same measured state, never hours 1..H (CR-01)" tags =
    [:mpc_loop] setup = [Phase21Fixtures] begin
    using TSODSO, Test
    using JuMP: set_parameter_value, set_objective_coefficient

    feeder = Phase21Fixtures.mpc_high_pv_feeder()
    aggs = Phase21Fixtures.build_mpc_high_pv_aggregators(
        feeder;
        pv_scale = Phase21Fixtures.MPC_HIGH_PV_SCALE_MEASURED,
    )
    H = Phase21Fixtures.H
    λ₀ = Phase21Fixtures.mpc_lambda0()   # FLAT λ₀ — load-bearing for the regression below

    ms = Dict{Tuple{Int, Symbol}, Float64}()
    for agg in aggs, d in agg.devices
        hasproperty(d, :soc0) && (ms[(agg.bus, :soc)] = Float64(d.soc0))
        hasproperty(d, :Tin0) && (ms[(agg.bus, :Tin)] = Float64(d.Tin0))
    end
    fe = (; pv_factor = 1.0, demand_factor = 1.0)

    # 1. UNIT regression on the window-slicing helper itself: the escalation aggregators must
    # carry the t-sliced, forecast-perturbed profiles and the measured state as their plain
    # struct fields (which the fresh escalation model's Parameters DEFAULT to, plan 21-01).
    fe2 = (; pv_factor = 1.1, demand_factor = 0.9)
    ms2 = Dict{Tuple{Int, Symbol}, Float64}()
    for agg in aggs
        ms2[(agg.bus, :soc)] = 0.001
        ms2[(agg.bus, :Tin)] = 24.0
    end
    esc = TSODSO._mpc_escalation_aggregators(aggs, 3, H, fe2, ms2)
    batt0 = only(d for d in aggs[1].devices if d isa PVBattery)
    batt = only(d for d in esc[1].devices if d isa PVBattery)
    @test batt.Ppv == Float64[batt0.Ppv[3 + τ - 1] * 1.1 for τ in 1:H]   # t-sliced + perturbed
    @test batt.soc0 == 0.001                                            # measured, not d.soc0
    therm0 = only(d for d in aggs[1].devices if d isa Thermostatic)
    therm = only(d for d in esc[1].devices if d isa Thermostatic)
    @test therm.Tout == Float64[therm0.Tout[3 + τ - 1] for τ in 1:H]    # t-sliced, UNPERTURBED (D-05)
    @test therm.Tin0 == 24.0                                            # measured, not d.Tin0
    @test esc[1].Pdc == Float64[aggs[1].Pdc[3 + τ - 1] * 0.9 for τ in 1:H]

    # 2. END-TO-END regression at t > 1: drive the SAME slide-the-window mechanics run_mpc
    # uses at t = 1 and t = 4 (both MEASURED to trip the inline cone check on this fixture at
    # pv_scale = 3.0 — ratios ≈ 9432 at both). Under the pre-fix code the escalation ALWAYS
    # solved hours 1..H with construction-time ICs, so with this FLAT λ₀ its published price
    # was IDENTICAL at every t; the fixed escalation prices the t-window, so the two prices
    # MUST differ (the PV slices differ across the two windows).
    o = build_mpc_window(feeder, ConvexBranchFlow(), aggs; H = H, terminal_soc = false)
    prices = Dict{Int, Vector{Float64}}()
    for t in (1, 4)
        for agg in aggs
            varlist = o.ctx.meta[:agg_device_vars][agg.bus]
            for (d, v) in zip(agg.devices, varlist)
                haskey(v, :Ppv_param) && set_parameter_value.(
                    v.Ppv_param,
                    Float64[d.Ppv[t + τ - 1] for τ in 1:H],
                )
                haskey(v, :Tout_param) && set_parameter_value.(
                    v.Tout_param,
                    Float64[d.Tout[t + τ - 1] for τ in 1:(H - 1)],
                )
            end
        end
        for handle in o.agg_pdc_handles
            agg = only(a for a in aggs if a.bus == handle.bus)
            set_parameter_value.(
                handle.Pdc_param,
                Float64[agg.Pdc[t + τ - 1] for τ in 1:H],
            )
        end
        for τ in 1:H
            set_objective_coefficient(o.model, o.p_import[τ], -λ₀[t + τ - 1])
        end
        solve_mpc_window!(o)
        r = TSODSO._mpc_certify_and_price(feeder, aggs, o, λ₀, t; measured_state = ms, fe = fe)
        @test r.cone_maxratio > 1                              # pre-condition at THIS t
        @test r.cert_status in (:certified_convex_dual_restricted, :local_ac_dual)
        @test all(isfinite, r.price_vec)
        prices[t] = r.price_vec
    end
    @test prices[1] != prices[4]   # the CR-01 regression: t-window-distinct escalation price
end

@testitem "mpc_loop: ladder terminal failure publishes :cert_failed with the reference fallback price — NEVER throws (CR-02, D-04, WR-04)" tags =
    [:mpc_loop] setup = [Phase21Fixtures] begin
    using TSODSO, Test
    using JuMP: set_parameter_value, set_objective_coefficient

    # The terminal :cert_failed tier is unreachable on any cheap CI fixture by construction
    # (a fixture where BOTH the restricted SOCP and the multi-start NLP genuinely fail is not
    # economically buildable in CI), so this item drives _mpc_certify_and_price's DOCUMENTED
    # internal test seams (_solve_welfare/_ac_dual_fallback_price) with throwing stand-ins —
    # deterministically exercising the SAME catch/ledger code paths a genuine tier failure
    # (assert_solved! retry exhaustion, assert_battery_complementarity!'s legitimate
    # negative-price throw) takes in production.
    feeder = Phase21Fixtures.mpc_high_pv_feeder()
    aggs = Phase21Fixtures.build_mpc_high_pv_aggregators(
        feeder;
        pv_scale = Phase21Fixtures.MPC_HIGH_PV_SCALE_MEASURED,
    )
    H = Phase21Fixtures.H
    λ₀ = Phase21Fixtures.mpc_lambda0()

    ms = Dict{Tuple{Int, Symbol}, Float64}()
    for agg in aggs, d in agg.devices
        hasproperty(d, :soc0) && (ms[(agg.bus, :soc)] = Float64(d.soc0))
        hasproperty(d, :Tin0) && (ms[(agg.bus, :Tin)] = Float64(d.Tin0))
    end
    fe = (; pv_factor = 1.0, demand_factor = 1.0)

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

    boom = (args...; kwargs...) -> error("forced tier failure (test seam)")
    fallback_ref = Float64[2.0 + 0.1 * t for t in eachindex(λ₀)]   # distinguishable slice

    # BOTH tiers fail → the terminal :cert_failed with the fallback_price window slice —
    # reaching this line at all (no exception propagated) IS the D-04 assertion.
    result = TSODSO._mpc_certify_and_price(
        feeder,
        aggs,
        o,
        λ₀,
        2;
        measured_state = ms,
        fe = fe,
        fallback_price = fallback_ref,
        _solve_welfare = boom,
        _ac_dual_fallback_price = boom,
    )
    @test result.cone_maxratio > 1                       # pre-condition: escalation triggered
    @test result.cert_status == :cert_failed
    @test result.price_vec == fallback_ref[2:(2 + H - 1)]   # the t-sliced reference policy

    # The terminal failure must SURFACE in the ledger: any_cert_failed is no longer
    # structurally vacuous (WR-04).
    trace = MpcTrace()
    record!(trace, 1, result.price_vec[1], 4.0, result.cert_status)
    @test any_cert_failed(trace)

    # Tier-2 failure alone still lands on the genuine tier-3 pricer (:local_ac_dual): only
    # the restricted-tier seam throws; ac_dual_fallback_price runs for real.
    result_t3 = TSODSO._mpc_certify_and_price(
        feeder,
        aggs,
        o,
        λ₀,
        2;
        measured_state = ms,
        fe = fe,
        _solve_welfare = boom,
    )
    @test result_t3.cert_status == :local_ac_dual
    @test length(result_t3.price_vec) == H
    @test all(isfinite, result_t3.price_vec)
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

    # WR-02: with stateful devices (every :default population), mpc_step == mpc_H would
    # apply the window's dynamics-UNCOVERED H-th control (the recursions cover τ ≤ H−1),
    # which can drive the propagated measured state out of bounds and crash the NEXT
    # resolve — rejected loudly up front: mpc_step must be ≤ mpc_H − 1.
    s_free_lunch = Scenario(; base..., mpc_H = 3, mpc_step = 3)
    @test_throws ArgumentError run_mpc(s_free_lunch)

    @info "mpc_loop mpc_step stride measured difference" r_step1.realized_welfare r_step2.realized_welfare r_step1.regret r_step2.regret r_step1.trace.dadp_trace r_step2.trace.dadp_trace

    # LOAD-BEARING assertion (D-03, checker revision 1): mpc_step must produce a genuinely
    # different closed-loop trajectory, not merely a different `steps` bookkeeping value.
    # Measured directly (never assumed): at mpc_forecast_error=0.05 on this fixture, the two
    # runs' realized_welfare AND dadp_trace both differ (see @info above for the measured
    # values) — no need to widen the fixture further.
    @test r_step1.realized_welfare != r_step2.realized_welfare
    @test r_step1.trace.dadp_trace != r_step2.trace.dadp_trace
end
