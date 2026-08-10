# test/test_stochastic_oos_harness.jl
#
# Seam: src/models/stochastic_welfare.jl (STOCH-03, D-09). `StochasticOosHarness` +
# `build_stochastic_oos_harness` generalize `MpcWindow`'s build-once/`Parameter`-pin shape
# (`src/models/mpc_window.jl`'s anonymous `soc[H] == terminal_param` idiom) from a single
# terminal target to the FULL `p_ch`/`p_dch` trajectory, pinning a caller-supplied in-sample
# battery schedule while leaving PV/demand/ambient Parameters free to re-slide per held-out
# scenario. `solve_stochastic_oos_step!` is a one-line `solve_with_retry!` delegation
# (`dual = false` — STOCH-03's scope is the realized welfare only). Items tagged
# `[:stochastic_oos_harness]`, `setup = [Phase22Fixtures]`, mirroring
# `test_mpc_window.jl`'s own build-once-invariance test convention (lines 75-131).
#
# Deviations (Rule 1 — verify-script feasibility fixes, discovered executing this task and
# Task 1 before it):
#
# 1. PLAN.md's own Task 1 `<verify>` script pins `p_ch` at `0.0005 * trial` for `trial in
#    1:3` while NEVER resetting the battery's own `soc0` Parameter (this harness exposes no
#    handle for it — Pattern 5's documented "pin only p_ch/p_dch, never soc" choice, and
#    `soc0` is deliberately NOT one of `battery_pins`' fields). On THIS fixture (`Pmax=0.002,
#    Emin=0.0, Emax=0.008, soc0=0.004`, `η=0.95`, `T=6` ⇒ 5 recursion steps), a CONSTANT
#    pinned `p_ch=0.001` (`trial=2`) alone drives `soc[6] = soc0 + 5·η·p_ch = 0.004 + 0.00475
#    = 0.00875 > Emax=0.008` WITHIN THAT SINGLE SOLVE — a genuine `PRIMAL_INFEASIBLE`,
#    verified directly (not guessed): trial=1 (`p_ch=0.0005`) solves `OPTIMAL`; trial=2
#    (`p_ch=0.001`) throws `PRIMAL_INFEASIBLE` from `solve_with_retry!`'s own exhaustion
#    path. This file's own heterogeneous cycles below use SMALLER pinned magnitudes
#    (respecting the same `soc0 + 5·η·p_ch(max) ≤ Emax` reachability envelope
#    `test_mpc_window.jl`'s own cycle design already documents this discipline for), while
#    still genuinely exercising charge-only, discharge-only, and mixed charge+discharge pins
#    across the three cycles.
# 2. Item 2 (pin correctness) additionally overrides `Ppv_param` to a flat, sufficiently
#    large value BEFORE pinning `p_ch`: the device's own DEFAULT `Ppv_param` is a seeded
#    daily profile that is genuinely ZERO at night hours, so a constant nonzero `p_ch` pin
#    across every `t` (this test's whole point) is infeasible at any night hour unless
#    `Ppv_param` is also raised (`p_ch[t] ≤ pv_used[t] ≤ Ppv_param[t]`, eq. 3.7) — verified
#    directly: the SAME pin without the `Ppv_param` override throws `PRIMAL_INFEASIBLE`.

@testitem "stochastic_oos_harness: build-once — num_variables/num_constraints invariant across heterogeneous re-solves (D-09)" tags =
    [:stochastic_oos_harness] setup = [Phase22Fixtures] begin
    using TSODSO
    using JuMP: num_variables, num_constraints, set_parameter_value

    feeder = Phase22Fixtures.stoch_feeder()
    T = Phase22Fixtures.T
    λ0 = Phase22Fixtures.stoch_lambda0()
    aggs = Phase22Fixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(Phase22Fixtures.SEED_STOCH, :oos_1),
    )

    h = build_stochastic_oos_harness(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ0)
    @test h isa TSODSO.StochasticOosHarness

    nv0 = num_variables(h.model)
    nc0 = num_constraints(h.model; count_variable_in_set_constraints = true)

    pin = only(h.battery_pins)
    ppv = only(h.ppv_handles)
    pdc = only(h.agg_pdc_handles)
    tout = only(h.tout_handles)

    # THREE heterogeneous re-solve cycles — different pinned p_ch/p_dch (charge-only,
    # discharge-only, mixed charge+discharge), different Ppv_param/Pdc_param/Tout_param
    # slices — all within the battery's own per-solve SOC-band reachability envelope
    # (soc0=0.004, Emax=0.008, η=0.95, T-1=5 recursion steps ⇒ a constant pinned p_ch up to
    # ≈0.00084 stays feasible; well clear at the magnitudes used below) so every cycle
    # genuinely solves.
    cycles = [
        (p_ch = 0.0003, p_dch = 0.0000, Ppv = 0.006, Pdc = 0.015, Tout = 18.0),
        (p_ch = 0.0000, p_dch = 0.0003, Ppv = 0.004, Pdc = 0.020, Tout = 24.0),
        (p_ch = 0.0004, p_dch = 0.0001, Ppv = 0.008, Pdc = 0.010, Tout = 20.0),
    ]

    for c in cycles
        set_parameter_value.(pin.pin_p_ch, fill(c.p_ch, T))
        set_parameter_value.(pin.pin_p_dch, fill(c.p_dch, T))
        set_parameter_value.(ppv.Ppv_param, fill(c.Ppv, T))
        set_parameter_value.(pdc.Pdc_param, fill(c.Pdc, T))
        set_parameter_value.(tout.Tout_param, fill(c.Tout, length(tout.Tout_param)))
        solve_stochastic_oos_step!(h)
    end

    @test num_variables(h.model) == nv0
    @test num_constraints(h.model; count_variable_in_set_constraints = true) == nc0
end

@testitem "stochastic_oos_harness: pin is genuinely binding, not vacuous (T-22-05)" tags =
    [:stochastic_oos_harness] setup = [Phase22Fixtures] begin
    using TSODSO
    using JuMP: value, set_parameter_value

    feeder = Phase22Fixtures.stoch_feeder()
    T = Phase22Fixtures.T
    λ0 = Phase22Fixtures.stoch_lambda0()
    aggs = Phase22Fixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(Phase22Fixtures.SEED_STOCH, :oos_2),
    )

    h = build_stochastic_oos_harness(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ0)

    pin = only(h.battery_pins)
    ppv = only(h.ppv_handles)
    vbatt = only(
        vv for (bus, varlist) in h.ctx.meta[:agg_device_vars] for vv in varlist if
        haskey(vv, :p_ch)
    )

    # The device's own DEFAULT Ppv_param is a seeded daily profile (zero at night hours),
    # so a CONSTANT nonzero p_ch pin across every t needs Ppv_param overridden to a flat
    # value ≥ the largest pin used below (p_ch ≤ pv_used ≤ Ppv_param, thesis eq. 3.7) —
    # otherwise the pin itself would be infeasible at a night hour regardless of the pin
    # mechanism's own correctness.
    set_parameter_value.(ppv.Ppv_param, fill(0.01, T))

    # valsA/valsB stay within the fixture's own reachability envelope (see file header) —
    # a constant p_ch up to ≈0.00084 is feasible at T=6 from soc0=0.004.
    valsA = fill(0.0003, T)
    set_parameter_value.(pin.pin_p_ch, valsA)
    set_parameter_value.(pin.pin_p_dch, zeros(T))
    solve_stochastic_oos_step!(h)
    @test all(isapprox.(value.(vbatt.p_ch), valsA; atol = 1e-6))

    # A DIFFERENT pin, re-solved on the SAME (never-rebuilt) model, genuinely moves the
    # solved value — the pin is load-bearing, not overridden by the optimizer.
    valsB = fill(0.0006, T)
    set_parameter_value.(pin.pin_p_ch, valsB)
    solve_stochastic_oos_step!(h)
    @test all(isapprox.(value.(vbatt.p_ch), valsB; atol = 1e-6))
    @test !all(isapprox.(value.(vbatt.p_ch), valsA; atol = 1e-6))
end

@testitem "stochastic_oos_harness: build_stochastic_oos_harness boundary guards" tags =
    [:stochastic_oos_harness] setup = [Phase22Fixtures] begin
    using TSODSO

    feeder = Phase22Fixtures.stoch_feeder()
    T = Phase22Fixtures.T
    λ0 = Phase22Fixtures.stoch_lambda0()
    aggs = Phase22Fixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(Phase22Fixtures.SEED_STOCH, :oos_3),
    )

    # Empty aggregators: no priced load / no objective.
    @test_throws ArgumentError build_stochastic_oos_harness(
        feeder,
        ConvexBranchFlow(),
        typeof(aggs)();
        T = T,
        λ₀ = λ0,
    )

    # T < 1.
    @test_throws ArgumentError build_stochastic_oos_harness(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = 0,
        λ₀ = Float64[],
    )

    # length(λ₀) != T.
    @test_throws ArgumentError build_stochastic_oos_harness(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = T,
        λ₀ = fill(4.0, T + 1),
    )

    # Aggregator bus outside 1:length(feeder.buses).
    out_of_range = [TSODSO.Aggregator(99, 0.9, aggs[1].devices, aggs[1].Pdc)]
    @test_throws ArgumentError build_stochastic_oos_harness(
        feeder,
        ConvexBranchFlow(),
        out_of_range;
        T = T,
        λ₀ = λ0,
    )
end
