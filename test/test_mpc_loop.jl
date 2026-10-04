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
        strategy = MPC(H = 3, terminal_soc = true, forecast_error = 0.0),
    )
    r = run_mpc(s)

    @test r.trace.steps == r.steps
    @test r.steps == 9 - 3 + 1
    @test all(==(:certified_convex_dual), r.trace.cert_status_trace)
    @test all(isfinite, (r.day_ahead_welfare, r.realized_welfare, r.regret))
    @test isfinite(r.forecast_settled_welfare)
    @test all(isfinite, r.day_ahead_dadp)
    @test length(r.trace.dadp_trace) == r.steps

    # Phase 27 FIX-10 zero-forecast-error byte-identity invariant (permanent regression): no
    # clip ever engages (the window's own PV-limit constraint already bounds the solved p_ch
    # by the UNPERTURBED Ppv[abs_hour]), and the truth power-flow re-solve reproduces the
    # window's own solved dispatch exactly, since the fixed injections match what the window
    # itself balanced.
    @test isapprox(r.realized_welfare, r.forecast_settled_welfare; atol = 1e-6)
end

@testitem "mpc_loop: forced-PV-shortfall genuinely diverges realized_welfare from forecast_settled_welfare (FIX-10)" tags =
    [:mpc_loop] setup = [Phase21Fixtures] begin
    using TSODSO, Test

    # Phase 27 FIX-10: a nonzero mpc_forecast_error draw whose pv_factor inflates the
    # window's belief of available PV forces the solved p_ch above the device's TRUE
    # (unperturbed) Ppv[abs_hour] on at least one applied hour — the A6 clip then genuinely
    # changes both the settled welfare and the AC-settled frontier import versus the
    # forecast-consistent number.
    #
    # seed=1 (RESTORED — plan 27-09, USER DECISION 2026-09-29, reverting plan 27-08's own
    # seed-5 DEVIATION): plans 27-03/27-07 originally chose seed 5 to dodge a SOCP-relaxation
    # exactness knife-edge in the (now-superseded) SOCP truth-resolve; plan 27-08's AC
    # power-flow settlement removed that knife-edge but then MEASURED that the DEFAULT
    # seed=1 threw a GENUINE Ipopt `LOCALLY_INFEASIBLE` at abs_hour=5 under the LIMITED AC
    # settlement — confirmed (by re-solving with :smax/:smax_rev REMOVED) that a feasible AC
    # point EXISTS but exceeds the head branch's `smax=0.0686` rating at both ends. Plan
    # 27-09's "physics only" decision decouples the truth plant's AC-SOLVABILITY requirement
    # from the feeder's OPERATING limits: `_mpc_truth_import_acpf` no longer writes
    # :smax/:smax_rev at all (`ACPowerFlow(; limits = false)`), so this SAME seed=1 dispatch
    # now reaches `LOCALLY_SOLVED` cleanly — the genuine overload plan 27-08 found is
    # reported via `r.settlement_violations`, never thrown. See the new `@testitem` below
    # ("AC truth settlement REPORTS a genuine thermal overload, never throws (FIX-10, plan
    # 27-09)") for the citable regression.
    s = Scenario(;
        name = "mpc_loop_fix10_shortfall",
        feeder = :ieee13,
        T = 9,
        strategy = MPC(H = 3, step = 1, terminal_soc = true, forecast_error = 0.3),
        seed = 1,
    )
    r = run_mpc(s)

    @test isfinite(r.realized_welfare) && isfinite(r.forecast_settled_welfare)
    @test isfinite(r.regret)
    # The clip + loss-exact import genuinely changed the settlement — NOT a coincidental
    # floating-point tie.
    @test !isapprox(r.realized_welfare, r.forecast_settled_welfare; atol = 1e-9)
end

@testitem "mpc_loop: true-state propagation THROWS (never clamps) on a genuine out-of-band SOC/temperature event (FIX-10)" tags =
    [:mpc_loop] begin
    using TSODSO, Test

    # Phase 27 FIX-10's throw-not-clamp guard (`_mpc_assert_true_state_inband`, internal,
    # unexported) is exercised DIRECTLY here — mirroring this file's OWN established pattern
    # of testing `run_mpc`'s internal MPC helpers directly (`_mpc_certify_and_price`,
    # `_mpc_escalation_aggregators`, `_mpc_assert_state_keying`, above) rather than only
    # end-to-end. Claude's discretion (27-03-PLAN.md's "at Claude's discretion" fixture
    # latitude): an EXTENSIVE empirical search (>150 (T, mpc_H, seed, mpc_forecast_error)
    # combinations, T up to 24, mpc_forecast_error up to 0.99, mpc_terminal_soc both
    # settings — see 27-03-SUMMARY.md) found NO (seed, mpc_forecast_error) combination on
    # the default :ieee13/:default population that trips a genuine SOC/temperature
    # out-of-band event through `run_mpc` BEFORE also tripping the (separate, pre-existing)
    # SOCP exactness gate — the battery's own headroom (`Emax=2·load_scale`,
    # `Pmax=0.5·load_scale`, so a single hour's worst-case clip is well under half the SOC
    # band) makes a genuine violation require a multi-hour compounding drift that, on THIS
    # fixture, empirically co-occurs with the reverse-flow SOCP knife-edge far more often
    # than not. This item instead certifies the GUARD ITSELF fires correctly (throws,
    # names bus/hour/value, never clamps) on a synthetic out-of-band value — the exact
    # invariant `run_mpc`'s own accumulation loop depends on.
    @test isdefined(TSODSO, :_mpc_assert_true_state_inband)

    # In-band (including the documented `tol=1e-6` solver-precision slack): never throws.
    @test TSODSO._mpc_assert_true_state_inband(0.0, 0.01, 0.01, "SOC", 2, 5) === nothing
    @test TSODSO._mpc_assert_true_state_inband(0.0, 0.01 + 5e-7, 0.01, "SOC", 2, 5) === nothing
    @test TSODSO._mpc_assert_true_state_inband(15.0, 22.0, 30.0, "temperature", 3, 7) ===
          nothing

    # Genuinely out-of-band (well beyond the tolerance): throws, names bus/abs_hour/value.
    err = try
        TSODSO._mpc_assert_true_state_inband(0.0, 0.05, 0.01, "SOC", 2, 5)
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    msg = sprint(showerror, err)
    @test occursin("TRUE-plant", msg)
    @test occursin("SOC", msg)
    @test occursin("bus=2", msg)
    @test occursin("abs_hour=5", msg)
    @test_throws ErrorException TSODSO._mpc_assert_true_state_inband(
        15.0,
        50.0,
        30.0,
        "temperature",
        3,
        7,
    )
end

@testitem "mpc_loop: A6 truth-settlement clips BOTH p_ch and pv_used to true PV, never crediting phantom PV energy (CR-02, 27-REVIEW.md)" tags =
    [:mpc_loop] begin
    using TSODSO, Test

    # CR-02 regression (27-REVIEW.md, 2026-09-29): the PRE-FIX truth-settlement block
    # clipped only `p_ch` to the device's TRUE (unperturbed) PV availability, leaving
    # `pv_used` — which feeds `net_p`/`p_inject` and hence the AC truth-settled frontier
    # import — UNCLIPPED. Under a forecast draw with `fe.pv_factor > 1` (the window
    # believes MORE PV is available than truly exists — CONFIRMED to occur at several
    # hours of `test_mpc_loop.jl`'s own existing "forced-PV-shortfall" fixture,
    # `seed=1, mpc_forecast_error=0.3`: `draw_forecast_error(1, t, 0.3).pv_factor` measured
    # 2026-09-29 as 1.25/1.06/1.13/1.04/1.28/1.06 at t=1/2/3/6/7/9 respectively), this let
    # `realized_welfare`/`p_import_true` be credited with PV energy the true plant cannot
    # physically supply. Fixed by extracting the clip into `_mpc_pvbattery_true_clip`
    # (internal, unexported) and applying it to BOTH quantities identically — exercised
    # DIRECTLY here (mirroring this file's own established pattern of unit-testing
    # `run_mpc`'s internal helpers, e.g. `_mpc_assert_true_state_inband` immediately
    # above) with HAND-derived numbers, so the fix is checked exactly rather than only
    # qualitatively.
    #
    # PRE-FIX vs POST-FIX (confirmed BY HAND, 2026-09-29, via `git stash` on
    # `src/experiments/mpc_loop.jl` and re-running this exact body): pre-fix,
    # `_mpc_pvbattery_true_clip` does not exist (`UndefVarError`) — the semantic
    # equivalent, "PRE-FIX" `pv_used_true = pv_used` (no clip at all), is checked
    # explicitly below and FAILS the CR-02 invariant at this fixture's numbers.
    @test isdefined(TSODSO, :_mpc_pvbattery_true_clip)

    # A fe.pv_factor > 1 device-level scenario: the window solved p_ch=3.0, pv_used=4.0
    # believing more PV was available (e.g. a forecast-perturbed Ppv_param bounding
    # pv_used above the true value), but the TRUE (unperturbed) PV availability this hour
    # is only Ppv_true=2.0 — a forecast that overstated PV by 2x. Both p_ch and pv_used
    # exceed the TRUE availability.
    p_ch, pv_used, Ppv_true, p_dch = 3.0, 4.0, 2.0, 0.5
    clip = TSODSO._mpc_pvbattery_true_clip(p_ch, pv_used, Ppv_true)

    # The core CR-02 invariant (exactly what 27-REVIEW.md's Fix section asks for): NEITHER
    # realized quantity may exceed the TRUE PV availability, checked for BOTH p_ch_true
    # AND pv_used_true individually (the PRE-FIX bug was pv_used_true alone violating
    # this).
    @test clip.p_ch_true <= Ppv_true
    @test clip.pv_used_true <= Ppv_true
    # The PVBattery model's own p_ch <= pv_used invariant (src/devices/PVBattery.jl:308)
    # survives the clip — the returned pair is itself a valid operating point at the TRUE
    # PV availability, never just two independently-clamped numbers.
    @test clip.p_ch_true <= clip.pv_used_true

    # HAND-DERIVED exact values: both p_ch=3.0 and pv_used=4.0 exceed Ppv_true=2.0, so BOTH
    # clip to exactly 2.0.
    @test clip.p_ch_true == 2.0
    @test clip.pv_used_true == 2.0

    # Control: a device-hour where TRUE PV is NOT exceeded — the clip must be a no-op
    # (never distorts an already-truthful window solve, e.g. fe.pv_factor <= 1 hours).
    clip_noop = TSODSO._mpc_pvbattery_true_clip(0.5, 1.0, 2.0)
    @test clip_noop.p_ch_true == 0.5
    @test clip_noop.pv_used_true == 1.0

    # HAND-DERIVED realized welfare at the clipped point, using the SAME device utility
    # formula run_mpc itself calls (`_mpc_pvbattery_utility`), on a PVBattery with
    # λ_min=1.0, λ_med=4.0, λ_max=9.0, Pmax=5.0 (the SAME parametrization as the T>1
    # fixture in test_planning_certification_integer.jl):
    #   a_ch = λ_med = 4.0, b_ch = (λ_med-λ_min)/Pmax = 3.0/5.0 = 0.6
    #   a_dch = λ_med = 4.0, b_dch = (λ_max-λ_med)/Pmax = 5.0/5.0 = 1.0
    # at p_ch_true=2.0 (from the clip above), p_dch=0.5 (discharge is UNAFFECTED by the
    # PV clip):
    #   U = a_ch*p_ch_true - (b_ch/2)*p_ch_true^2 - a_dch*p_dch - (b_dch/2)*p_dch^2
    #     = 4.0*2.0 - 0.3*2.0^2 - 4.0*0.5 - 0.5*0.5^2
    #     = 8.0 - 1.2 - 2.0 - 0.125 = 4.675
    dev = TSODSO.PVBattery(
        2,
        0.95,
        1.0,
        5.0,
        0.0,
        10.0,
        2.0,
        1.0,
        4.0,
        9.0,
        [Ppv_true, Ppv_true],
    )
    U = TSODSO._mpc_pvbattery_utility(dev, clip.p_ch_true, p_dch)
    @test isapprox(U, 4.675; atol = 1e-12)

    # The realized NET PV contribution to settlement (`net_p`'s `pv_used_true - p_ch_true +
    # p_dch` term, mirroring run_mpc's own accumulation) under the FIX vs. the PRE-FIX
    # (unclipped pv_used) formula — demonstrating the actual bug CR-02 describes: the
    # device UTILITY term (above) was already correct pre-fix (it never reads pv_used
    # directly), but the NET INJECTION accounting was not.
    net_p_prefix_bug = pv_used - clip.p_ch_true + p_dch          # PRE-FIX: pv_used UNCLIPPED
    net_p_postfix = clip.pv_used_true - clip.p_ch_true + p_dch   # POST-FIX: pv_used CLIPPED
    @test net_p_prefix_bug == 2.5   # HAND-DERIVED: 4.0 - 2.0 + 0.5 -- overstates true PV
    @test net_p_postfix == 0.5      # HAND-DERIVED: 2.0 - 2.0 + 0.5 -- reflects TRUE PV
    @test net_p_postfix < net_p_prefix_bug
    # The PRE-FIX value physically implies MORE net PV injection than the true plant's
    # entire PV availability could support net of charging -- exactly the "phantom PV
    # energy" CR-02 describes. The POST-FIX value never can (by construction, since
    # pv_used_true <= Ppv_true always).
    @test net_p_prefix_bug > Ppv_true - clip.p_ch_true + p_dch
    @test net_p_postfix == Ppv_true - clip.p_ch_true + p_dch
end

@testitem "mpc_loop: A6 clip invariant holds at run_mpc's REAL PVBattery call site, not just the isolated helper (WR-04, 27-REVIEW.md iteration 2)" tags =
    [:mpc_loop] setup = [Phase21Fixtures] begin
    using TSODSO, Test

    # WR-04 (27-REVIEW.md, 2026-09-29, iteration 2): the CR-02 unit test above pins
    # `_mpc_pvbattery_true_clip`'s own correctness in isolation but never drives `run_mpc`'s
    # actual PVBattery truth-settlement call site (`src/experiments/mpc_loop.jl`, the
    # `net_p += pv_used_true - p_ch_true + p_dch1` line) — so a future edit silently
    # reverting THAT line back to the pre-CR-02 unclipped `pv_used1` would leave every
    # then-committed test green. This item closes that gap by driving `run_mpc`'s PUBLIC
    # path directly and reading `r.pvbattery_truth_trace` — a per-applied-hour,
    # per-PVBattery-device diagnostic added SOLELY for this test (`net_p_delta` is captured
    # as `net_p_after - net_p_before` AROUND the real accumulation line, never a
    # re-derivation) — so the assertion below is provably sensitive to a revert of that
    # exact line.
    #
    # SAME "forced-PV-shortfall" fixture as the existing FIX-10/CR-02 items above
    # (seed=1, mpc_forecast_error=0.3): `draw_forecast_error(1, t, 0.3).pv_factor` was
    # measured (see the CR-02 item's own comment) to exceed 1 at several resolves
    # (t=1/2/3/6/7/9), i.e. the window's belief genuinely overstates true PV availability —
    # the exact regime CR-02/WR-04 concern.
    #
    # CONFIRMED BY HAND (2026-09-29): reverting ONLY the accumulation line
    # `net_p += pv_used_true - p_ch_true + p_dch1` back to
    # `net_p += pv_used1 - p_ch_true + p_dch1` (a temporary in-place edit, restored
    # immediately after, never committed — no `git stash` used) makes the invariant
    # assertion below FAIL (`pv_used_actually_summed > Ppv_true` at abs_hour=3, bus=2,
    # `0.003531... > 0.003126...`); against the current (fixed) source, it passes.
    s = Scenario(;
        name = "mpc_loop_fix10_shortfall",
        feeder = :ieee13,
        T = 9,
        strategy = MPC(H = 3, step = 1, terminal_soc = true, forecast_error = 0.3),
        seed = 1,
    )
    r = run_mpc(s)

    # Precondition: the fixture genuinely exercises the PVBattery truth-settlement call site
    # (never a vacuously-empty pass).
    @test !isempty(r.pvbattery_truth_trace)

    tol = 1e-9
    for entry in r.pvbattery_truth_trace
        # Recover the quantity ACTUALLY summed into net_p this hour from the measured delta
        # (`net_p_delta = pv_used_ACTUALLY_USED - p_ch_true + p_dch`, whatever
        # `pv_used_ACTUALLY_USED` the real call site used) — never re-deriving it from the
        # clip helper's own output, so this is genuinely a check of the CALL SITE, not the
        # helper in isolation.
        pv_used_actually_summed = entry.net_p_delta + entry.p_ch_true - entry.p_dch
        # The exact CR-02/WR-04 invariant: the self-consumption/export value actually fed
        # into the settled net PV-battery injection can never exceed the device's TRUE
        # (unperturbed) PV availability this hour — this is what FAILS if the real call site
        # reverts to the unclipped `pv_used1` under `fe.pv_factor > 1`.
        @test pv_used_actually_summed <= entry.Ppv_true + tol
        # Cross-check against the clip helper's own verbatim outputs (both individually
        # bounded by the true PV, and p_ch_true <= pv_used_true, per
        # `_mpc_pvbattery_true_clip`'s own documented invariant).
        @test entry.p_ch_true <= entry.Ppv_true + tol
        @test entry.pv_used_true <= entry.Ppv_true + tol
        @test entry.p_ch_true <= entry.pv_used_true + tol
    end
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

    # PM-01 (phase 26-18): the DEFAULT ConvexBranchFlow() is now EXACT on this fixture (it is
    # Gan-Low's modified OPF, a restriction on the UPPER voltage band — see
    # ConvexBranchFlow.jl's PM-01 docstring addendum), so it no longer forces the inexactness
    # this escalation-ladder test needs; thesis_literal=true (the OLD, lower-band-restricting
    # copy) is re-forced here as the explicit opt-in that reproduces the original trigger.
    o = build_mpc_window(
        feeder,
        ConvexBranchFlow(; thesis_literal = true),
        aggs;
        H = H,
        terminal_soc = false,
    )
    for agg in aggs
        varlist = o.ctx.agg_device_vars[agg.bus]
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
    result =
        TSODSO._mpc_certify_and_price(feeder, aggs, o, λ₀, 1; measured_state = ms, fe = fe)

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
    # PM-01 (phase 26-18): re-forced with thesis_literal=true — see the identical rationale
    # comment in the testitem above (the default is now exact on this fixture).
    o = build_mpc_window(
        feeder,
        ConvexBranchFlow(; thesis_literal = true),
        aggs;
        H = H,
        terminal_soc = false,
    )
    prices = Dict{Int, Vector{Float64}}()
    for t in (1, 4)
        for agg in aggs
            varlist = o.ctx.agg_device_vars[agg.bus]
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
            set_parameter_value.(handle.Pdc_param, Float64[agg.Pdc[t + τ - 1] for τ in 1:H])
        end
        for τ in 1:H
            set_objective_coefficient(o.model, o.p_import[τ], -λ₀[t + τ - 1])
        end
        solve_mpc_window!(o)
        r = TSODSO._mpc_certify_and_price(
            feeder,
            aggs,
            o,
            λ₀,
            t;
            measured_state = ms,
            fe = fe,
        )
        @test r.cone_maxratio > 1                              # pre-condition at THIS t
        @test r.cert_status in (:certified_convex_dual_restricted, :local_ac_dual)
        @test all(isfinite, r.price_vec)
        prices[t] = r.price_vec
    end
    @test prices[1] != prices[4]   # the CR-01 regression: t-window-distinct escalation price
end

@testitem "mpc_loop: (bus, kind) state-keying invariant is asserted LOUDLY — duplicate buses / two same-kind stateful devices per bus throw (WR-05)" tags =
    [:mpc_loop] setup = [Phase21Fixtures] begin
    using TSODSO, Test

    feeder = Phase21Fixtures.mpc_feeder()
    aggs = Phase21Fixtures.build_mpc_aggregators(feeder)

    # The valid fixture population passes (one aggregator per bus, one device per state kind).
    @test TSODSO._mpc_assert_state_keying(aggs) === nothing

    # (a) two aggregators sharing a bus — contribute! APPENDS their varlists into ONE per-bus
    # vector, so zip(agg.devices, varlist) would mispair devices with variables.
    dup_bus = [aggs[1], Aggregator(aggs[1].bus, 0.9, aggs[1].devices, aggs[1].Pdc)]
    @test_throws ArgumentError TSODSO._mpc_assert_state_keying(dup_bus)

    # (b) two SOC-stateful devices on one bus (a PVBattery AND a FourQuadBESS both carry
    # :soc0) — the (bus, :soc) measured-state key would silently overwrite, and the
    # `only(vv -> haskey(vv, :soc0))` pairing in the apply loop would throw mid-loop instead
    # of up front.
    batt = only(d for d in aggs[1].devices if d isa PVBattery)
    bess4q = FourQuadBESS(
        aggs[1].bus,
        0.95,
        1.0,
        0.002,
        0.002,
        0.003,
        0.0,
        0.008,
        0.004,
        3.8,
        6.2,
        8.9,
    )
    two_soc = [Aggregator(aggs[1].bus, 0.9, [batt, bess4q], aggs[1].Pdc)]
    @test_throws ArgumentError TSODSO._mpc_assert_state_keying(two_soc)
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

    # PM-01 (phase 26-18): re-forced with thesis_literal=true — see the identical rationale
    # comment in the first escalation-ladder testitem above (the default is now exact on this
    # fixture, so the terminal :cert_failed tier's own pre-condition needs the explicit opt-in).
    o = build_mpc_window(
        feeder,
        ConvexBranchFlow(; thesis_literal = true),
        aggs;
        H = H,
        terminal_soc = false,
    )
    for agg in aggs
        varlist = o.ctx.agg_device_vars[agg.bus]
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

    # seed=1 (RESTORED — plan 27-09, USER DECISION 2026-09-29, reverting plan 27-08's own
    # seed-5 DEVIATION). History: plan 27-07 originally chose seed 5 here because the
    # DEFAULT `seed=1` tripped the (now-superseded) SOCP truth-resolve's `assert_socp_exact!`
    # gate — a structural SOCP relaxation inexactness under compounding forecast-error-driven
    # state drift, head branch loading measured ≈98% of its `smax=0.0686` thermal limit. Plan
    # 27-08's AC power-flow settlement removed that SOCP knife-edge but then MEASURED that
    # `seed=1, mpc_step=2` threw a GENUINE Ipopt `LOCALLY_INFEASIBLE` at abs_hour=4 under the
    # LIMITED AC settlement (confirmed by re-solving with :smax/:smax_rev REMOVED: a feasible
    # AC point exists but exceeds the head branch's thermal rating). Plan 27-09's "physics
    # only" decision decouples the truth plant's AC-SOLVABILITY requirement from the feeder's
    # OPERATING limits: `_mpc_truth_import_acpf` no longer writes :smax/:smax_rev at all
    # (`ACPowerFlow(; limits = false)`), so this SAME seed=1 dispatch now reaches
    # `LOCALLY_SOLVED` cleanly — the genuine overload is reported via
    # `r.settlement_violations`, never thrown (see the new `@testitem` below).
    base = (;
        name = "mpc_loop_stride",
        feeder = :ieee13,
        T = 9,
        seed = 1,
    )
    mpc_base = (H = 3, terminal_soc = true, forecast_error = 0.05)
    s_step1 = Scenario(; base..., strategy = MPC(; mpc_base..., step = 1))
    s_step2 = Scenario(; base..., strategy = MPC(; mpc_base..., step = 2))

    r_step1 = run_mpc(s_step1)
    r_step2 = run_mpc(s_step2)

    @test r_step1.steps == 9 - 3 + 1
    @test r_step2.steps == r_step1.steps
    @test r_step1.trace.steps == r_step1.steps
    @test r_step2.trace.steps == r_step1.steps

    s_bad = Scenario(; base..., strategy = MPC(; mpc_base..., H = 3, step = 5))
    @test_throws ArgumentError run_mpc(s_bad)

    # WR-02: with stateful devices (every :default population), mpc_step == mpc_H would
    # apply the window's dynamics-UNCOVERED H-th control (the recursions cover τ ≤ H−1),
    # which can drive the propagated measured state out of bounds and crash the NEXT
    # resolve — rejected loudly up front: mpc_step must be ≤ mpc_H − 1.
    s_free_lunch = Scenario(; base..., strategy = MPC(; mpc_base..., H = 3, step = 3))
    @test_throws ArgumentError run_mpc(s_free_lunch)

    # WR-07: the window cannot exceed the day-ahead horizon — a Scenario-level
    # misconfiguration must throw HERE, not as a cryptic device-level "profile too short"
    # deep inside build_mpc_window (or a silent zero-resolve run).
    s_long_window = Scenario(; base..., strategy = MPC(; mpc_base..., H = 12))   # T = 9 < mpc_H = 12
    @test_throws ArgumentError run_mpc(s_long_window)

    @info "mpc_loop mpc_step stride measured difference" r_step1.realized_welfare r_step2.realized_welfare r_step1.regret r_step2.regret r_step1.trace.dadp_trace r_step2.trace.dadp_trace

    # LOAD-BEARING assertion (D-03, checker revision 1): mpc_step must produce a genuinely
    # different closed-loop trajectory, not merely a different `steps` bookkeeping value.
    # Measured directly (never assumed): at mpc_forecast_error=0.05 on this fixture, the two
    # runs' realized_welfare AND dadp_trace both differ (see @info above for the measured
    # values) — no need to widen the fixture further.
    @test r_step1.realized_welfare != r_step2.realized_welfare
    @test r_step1.trace.dadp_trace != r_step2.trace.dadp_trace
end

@testitem "mpc_loop: AC truth settlement REPORTS a genuine thermal overload, never throws (FIX-10, plan 27-09)" tags =
    [:mpc_loop] setup = [Phase21Fixtures] begin
    using TSODSO, Test

    # Plan 27-08's own escalated finding (see the forced-PV-shortfall item above and
    # 27-08-SUMMARY.md "Findings"): the DEFAULT `seed=1` on the forced-PV-shortfall fixture
    # (T=9, mpc_H=3, mpc_forecast_error=0.3) drives the realized/clipped dispatch at
    # abs_hour=5 into a point that GENUINELY exceeds the head branch's `smax=0.0686` thermal
    # rating once served by the TRUE (unrelaxed) AC equality. Under plan 27-08's LIMITED AC
    # settlement, Ipopt correctly reported `LOCALLY_INFEASIBLE` there and
    # `_mpc_truth_import_acpf` threw. Plan 27-09 (USER DECISION 2026-09-29) decouples the
    # truth plant's AC-SOLVABILITY requirement from the feeder's OPERATING limits
    # (`ACPowerFlow(; limits = false)`): the SAME seed=1 dispatch now reaches
    # `LOCALLY_SOLVED` cleanly (confirming plan 27-08's own diagnosis — it was the
    # `:smax` constraint refusing it, not a genuine AC non-solvability), and the overload is
    # surfaced as a `settlement_violations` diagnostic instead of a thrown exception. This is
    # a REAL fixture, not a synthetic stand-in: it doubles as the citable regression for "the
    # settlement never refuses on a limit violation" AND documents the genuine head-branch
    # overload the OLD SOCP relaxation was silently absorbing (27-07/27-08's own finding).
    s = Scenario(;
        name = "mpc_loop_fix10_shortfall",
        feeder = :ieee13,
        T = 9,
        strategy = MPC(H = 3, step = 1, terminal_soc = true, forecast_error = 0.3),
        seed = 1,
    )

    r = run_mpc(s)   # NEVER throws under plan 27-09's physics-only settlement
    @test isfinite(r.realized_welfare)
    @test length(r.settlement_violations) == r.steps

    # abs_hour=5 is τ_apply=1 of the resolve starting at t=5 (mpc_step=1, so abs_hour==k for
    # k>=1 here) — locate it by its own `abs_hour` field rather than assuming a k index.
    v5 = only(filter(v -> v.abs_hour == 5, r.settlement_violations))
    @test v5.n_thermal_violations >= 1
    @test v5.max_overload_ratio > 1.0   # the genuine head-branch overload, now REPORTED
end
