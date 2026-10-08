# test/test_stochastic_oos_harness.jl
#
# Seam: src/models/stochastic_welfare.jl. `StochasticOosHarness` +
# `build_stochastic_oos_harness` generalize `MpcWindow`'s build-once/`Parameter`-pin shape
# (`src/models/mpc_window.jl`'s anonymous `soc[H + 1] == terminal_param` idiom; it was
# retargeted from `soc[H]` once the device's own `soc` vector grew to `1:(H+1)`)
# from a single terminal target to the FULL `p_ch`/`p_dch` trajectory, pinning a caller-supplied in-sample
# battery schedule while leaving PV/demand/ambient Parameters free to re-slide per held-out
# scenario. `solve_stochastic_oos_step!` re-solves via `solve_with_retry!` (`dual = false` —
# the scope is the realized welfare only) and then runs the shared SOCP exactness gate,
# refusing an inexact held-out solve with a `CertificateError`. Items tagged
# `[:stochastic_oos_harness]`, `setup = [StochasticFixtures]`, mirroring
# `test_mpc_window.jl`'s own build-once-invariance test convention (lines 75-131).
#
# Design notes (feasibility fixes found while building this file):
#
# 1. A naive verification script that pins `p_ch` at `0.0005 * trial` for `trial in
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
# 3. The mechanics items below (build-once, pin-binding, FourQuadBESS q pin) build the harness
#    with an explicitly tightened optimizer, `select_optimizer(SOCP(); tol_gap_abs = 5e-10,
#    tol_gap_rel = 5e-10)`. On this near-lossless 2-bus fixture the default `tol_gap = 1e-8`
#    leaves cone residuals that the held-out exactness gate refuses (measured worst
#    gap/(atol_b + rtol·|cone|) ratios up to ≈ 51 on the pin-binding solves); at 5e-10 every
#    one of these solves measures ≤ 0.5. This is the same tolerance and the same rationale as
#    the in-sample builder `build_stochastic_welfare` (a convergence-precision fix, not a gate
#    weakening: the gate's own τ/ε are untouched). The harness DEFAULT optimizer is unchanged;
#    the refusal item below exercises it on purpose.

@testitem "stochastic_oos_harness: build-once — num_variables/num_constraints invariant across heterogeneous re-solves" tags =
    [:stochastic_oos_harness] setup = [StochasticFixtures] begin
    using TSODSO
    using TSODSO: build_stochastic_oos_harness, solve_stochastic_oos_step!, sub_seed
    using JuMP: num_variables, num_constraints, set_parameter_value

    feeder = StochasticFixtures.stoch_feeder()
    T = StochasticFixtures.T
    λ0 = StochasticFixtures.stoch_lambda0()
    aggs = StochasticFixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(StochasticFixtures.SEED_STOCH, :oos_1),
    )

    # Tightened optimizer: see file header note 3 (mechanics item, not an accuracy test).
    oos_opt =
        TSODSO.select_optimizer(TSODSO.SOCP(); tol_gap_abs = 5e-10, tol_gap_rel = 5e-10)
    h = build_stochastic_oos_harness(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = T,
        λ₀ = λ0,
        optimizer = oos_opt,
    )
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

@testitem "stochastic_oos_harness: pin is genuinely binding, not vacuous" tags =
    [:stochastic_oos_harness] setup = [StochasticFixtures] begin
    using TSODSO
    using TSODSO: build_stochastic_oos_harness, solve_stochastic_oos_step!, sub_seed
    using JuMP: value, set_parameter_value

    feeder = StochasticFixtures.stoch_feeder()
    T = StochasticFixtures.T
    λ0 = StochasticFixtures.stoch_lambda0()
    aggs = StochasticFixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(StochasticFixtures.SEED_STOCH, :oos_2),
    )

    # Tightened optimizer: see file header note 3 (mechanics item, not an accuracy test).
    oos_opt =
        TSODSO.select_optimizer(TSODSO.SOCP(); tol_gap_abs = 5e-10, tol_gap_rel = 5e-10)
    h = build_stochastic_oos_harness(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = T,
        λ₀ = λ0,
        optimizer = oos_opt,
    )

    pin = only(h.battery_pins)
    ppv = only(h.ppv_handles)
    vbatt = only(
        vv for (bus, varlist) in h.ctx.agg_device_vars for
        vv in varlist if haskey(vv, :p_ch)
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

@testitem "stochastic_oos_harness: an inexact held-out re-solve is refused and skipped-and-reported, never silently averaged" tags =
    [:stochastic_oos_harness] setup = [StochasticFixtures] begin
    using TSODSO
    using TSODSO: build_stochastic_oos_harness, solve_stochastic_oos_step!, sub_seed
    using JuMP: set_parameter_value

    # The pin-binding fixture above, but with the harness DEFAULT optimizer (tol_gap = 1e-8).
    # Measured: its held-out solve leaves a cone residual whose worst
    # gap/(atol_b + rtol·|cone|) ratio is ≈ 51 (the shared exactness gate refuses > 1). The
    # step must throw the typed certificate refusal, and the orchestrator helper must turn
    # exactly that refusal into a reported, excluded draw — not an aborted run and not a
    # silently averaged number.
    feeder = StochasticFixtures.stoch_feeder()
    T = StochasticFixtures.T
    λ0 = StochasticFixtures.stoch_lambda0()
    aggs = StochasticFixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(StochasticFixtures.SEED_STOCH, :oos_2),
    )

    h = build_stochastic_oos_harness(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ0)

    pin = only(h.battery_pins)
    ppv = only(h.ppv_handles)
    set_parameter_value.(ppv.Ppv_param, fill(0.01, T))
    set_parameter_value.(pin.pin_p_ch, fill(0.0003, T))
    set_parameter_value.(pin.pin_p_dch, zeros(T))

    err = @test_throws CertificateError solve_stochastic_oos_step!(h)
    @test err.value.kind === :socp_exact
    @test h.ctx.meta[:socp_maxratio] > 1
    @test h.ctx.meta[:socp_maxgap] > 0

    # Orchestrator conversion: (welfare, infeasible = false, inexact = true), welfare finite
    # (reported per draw, excluded from the realized average by the caller).
    w, infeas, inexact = TSODSO._stoch_solve_held_out!(h, 1)
    @test inexact === true
    @test infeas === false
    @test isfinite(w)
end

@testitem "stochastic_oos_harness: regression — a FourQuadBESS (no Ppv_param) builds, pins, and solves" tags =
    [:stochastic_oos_harness] setup = [StochasticFixtures] begin
    using TSODSO
    using TSODSO: build_stochastic_oos_harness, solve_stochastic_oos_step!, sub_seed
    using JuMP: objective_value

    # The harness's battery-pin walk selected battery-like
    # devices by `haskey(v, :soc0)` and then read `v.Ppv_param` UNCONDITIONALLY —
    # crashing (`type NamedTuple has no field Ppv_param`) on a FourQuadBESS, whose
    # `contribute!` returns `vars = (; p_ch, p_dch, soc, q, soc0)` with no PV Parameter,
    # despite the docstring naming FourQuadBESS as supported. This item pins the fix:
    # a mixed PVBattery + FourQuadBESS aggregator must build, expose ONE pin entry PER
    # battery-like device but a `ppv_handles` entry ONLY for the PV-carrying PVBattery,
    # and re-solve cleanly with both batteries pinned at the benign 0.0 default.
    feeder = StochasticFixtures.stoch_feeder()
    T = StochasticFixtures.T
    λ0 = StochasticFixtures.stoch_lambda0()
    aggs = StochasticFixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(StochasticFixtures.SEED_STOCH, :cr01_fourquad),
    )

    # Same scale family as the fixture's own PVBattery (LOAD_SCALE_STOCH-relative), so
    # the near-lossless 2-bus solve stays feasible and interior.
    L = StochasticFixtures.LOAD_SCALE_STOCH
    bess = FourQuadBESS(
        2,                              # bus (the fixture's single load bus)
        0.95,                           # η
        1.0,                            # Δt
        0.1 * L,                        # Pch_max
        0.1 * L,                        # Pdch_max
        0.2 * L,                        # Smax
        0.0,                            # Emin
        0.4 * L,                        # Emax
        0.2 * L,                        # soc0
        StochasticFixtures.BATT_λ_MIN,
        StochasticFixtures.BATT_λ_MED,
        StochasticFixtures.BATT_λ_MAX,
    )
    agg = TSODSO.Aggregator(
        2,
        aggs[1].φ,
        AbstractDevice[aggs[1].devices..., bess],
        aggs[1].Pdc,
    )

    h = build_stochastic_oos_harness(feeder, ConvexBranchFlow(), [agg]; T = T, λ₀ = λ0)

    # BOTH battery-like devices are pinned; ONLY the PVBattery carries a PV handle.
    @test length(h.battery_pins) == 2
    @test length(h.ppv_handles) == 1

    # End-to-end: the mixed-battery harness genuinely re-solves (pins at the 0.0
    # default = both batteries idle — always inside the SOC band from any soc0).
    solve_stochastic_oos_step!(h)
    @test isfinite(objective_value(h.model))
end

@testitem "stochastic_oos_harness: FourQuadBESS q is pinned first-stage, never free held-out recourse" tags =
    [:stochastic_oos_harness] setup = [StochasticFixtures] begin
    using TSODSO
    using TSODSO: build_stochastic_oos_harness, solve_stochastic_oos_step!, sub_seed
    using JuMP: value, set_parameter_value

    # build_stochastic_welfare ties q across in-sample scenarios (q is part
    # of the first-stage battery schedule), so the held-out re-score must PIN
    # the committed q too — a free q would grant the held-out solve reactive recourse
    # the in-sample commitment never had. This item pins the harness half of the fix.
    feeder = StochasticFixtures.stoch_feeder()
    T = StochasticFixtures.T
    λ0 = StochasticFixtures.stoch_lambda0()
    L = StochasticFixtures.LOAD_SCALE_STOCH
    aggs = StochasticFixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(StochasticFixtures.SEED_STOCH, :wr04_oos),
    )
    bess = FourQuadBESS(
        2,
        0.95,
        1.0,
        0.1 * L,
        0.1 * L,
        0.2 * L,
        0.0,
        0.4 * L,
        0.2 * L,
        StochasticFixtures.BATT_λ_MIN,
        StochasticFixtures.BATT_λ_MED,
        StochasticFixtures.BATT_λ_MAX,
    )
    agg = TSODSO.Aggregator(
        2,
        aggs[1].φ,
        AbstractDevice[aggs[1].devices..., bess],
        aggs[1].Pdc,
    )

    # Tightened optimizer: see file header note 3 (mechanics item, not an accuracy test).
    oos_opt =
        TSODSO.select_optimizer(TSODSO.SOCP(); tol_gap_abs = 5e-10, tol_gap_rel = 5e-10)
    h = build_stochastic_oos_harness(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ0,
        optimizer = oos_opt,
    )

    # Exactly the FourQuadBESS pin carries pin_q; the PVBattery pin does not.
    @test count(p -> haskey(p, :pin_q), h.battery_pins) == 1
    pin = only(p for p in h.battery_pins if haskey(p, :pin_q))

    # Pin a nonzero committed q (inside the device's own cone: |q| ≤ Smax with p = 0)
    # and assert the solved q reproduces it — the pin is load-bearing, not vacuous.
    qvals = fill(0.05 * L, T)
    set_parameter_value.(pin.pin_q, qvals)
    solve_stochastic_oos_step!(h)
    vbess = only(v for (bus, vl) in h.ctx.agg_device_vars for v in vl if haskey(v, :q))
    @test all(isapprox.(value.(vbess.q), qvals; atol = 1e-6))
end

@testitem "stochastic_oos_harness: build_stochastic_oos_harness boundary guards" tags =
    [:stochastic_oos_harness] setup = [StochasticFixtures] begin
    using TSODSO
    using TSODSO: build_stochastic_oos_harness, sub_seed

    feeder = StochasticFixtures.stoch_feeder()
    T = StochasticFixtures.T
    λ0 = StochasticFixtures.stoch_lambda0()
    aggs = StochasticFixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(StochasticFixtures.SEED_STOCH, :oos_3),
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
