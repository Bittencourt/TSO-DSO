# Seam: models/welfare_solve.jl (OPT-01, DEV-04). GLB-CVX centralized social-welfare solve.
#
# Plan 03-05 turns this green: the end-to-end multi-device GLB-CVX solve — aggregators
# rolling Thermostatic/Deferrable/PVBattery devices onto a LinDistFlow feeder with
# seeded T=24 profiles — to a global optimum, plus the WR-03 reactive-root fix and the
# App. C battery-complementarity check (p_ch·p_dch < τ). The name contains "welfare" so
# `occursin("welfare", ti.name)` selects it.

@testitem "welfare: solve_welfare + fixture health exist (OPT-01)" tags = [:welfare] setup = [Phase3Fixtures] begin
    using TSODSO

    # The shared fixture is healthy (exercises setup wiring): valid feeder + T=24 data.
    feeder = Phase3Fixtures.small_radial_feeder()
    @test feeder.root == 1
    @test length(Phase3Fixtures.λ₀) == length(Phase3Fixtures.Pdc) == Phase3Fixtures.T == 24

    @test isdefined(TSODSO, :solve_welfare)
end

@testitem "welfare: end-to-end GLB-CVX optimum, reactive balance, battery complementarity (OPT-01, DEV-04)" tags = [:welfare] setup = [Phase3Fixtures] begin
    using TSODSO
    using JuMP

    T = Phase3Fixtures.T                       # 24
    feeder = Phase3Fixtures.small_radial_feeder()
    Tout = Phase3Fixtures.Tout
    Pdc = Phase3Fixtures.Pdc
    λ₀ = Phase3Fixtures.λ₀
    φ = 0.9                                     # nonzero power factor ⇒ reactive load present

    # Seeded, reproducible PV profile (DATA-04) feeds the battery availability limit.
    prof = generate_profiles(seed = 20260718, T = T)

    # An aggregator holding a Thermostatic + a Deferrable + a PV-battery at one bus.
    function make_agg(bus)
        therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, Tout)
        defer = Deferrable(bus, 8, 16, 1.0, 0.5, 0.5)
        batt = PVBattery(bus, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, prof.pv)
        return Aggregator(bus, φ, [therm, defer, batt], Pdc)
    end
    aggs = [make_agg(2), make_agg(3)]           # ≥2 aggregators on the non-root load buses

    # --- GLB-CVX solve over LinDistFlow at T=24 (convex QP ⇒ global optimum) ---
    ctx, obj, dadp = solve_welfare(feeder, LinDistFlow(), aggs; T = T, λ₀ = λ₀)

    # OPTIMAL: solve_welfare passed assert_solved! (else it would have thrown). Welfare is
    # finite; a magnitude sanity bound catches a unit/scale blowup (RESEARCH Pitfall 3).
    @test isfinite(obj)
    @test abs(obj) < 1e6
    @test length(dadp) == T
    @test all(isfinite, dadp)

    # WR-03 fix works: the free-sign q_import unblocked :Rq, so the reactive load is
    # actually served (a regression here would be INFEASIBLE or an all-zero reactive draw).
    q_import = ctx.meta[:q_import]
    @test any(t -> abs(value(q_import[t])) > 1e-6, 1:T)

    # App. C: every battery honors p_ch·p_dch < τ at the FULL welfare optimum.
    @test haskey(ctx.meta, :agg_device_vars)
    batteries = [
        v for (_bus, varlist) in ctx.meta[:agg_device_vars] for v in varlist if
        haskey(v, :p_ch) && haskey(v, :p_dch)
    ]
    @test length(batteries) == 2                # both aggregators' batteries are checked
    for v in batteries, t in 1:T
        @test value(v.p_ch[t]) * value(v.p_dch[t]) < 1e-6
    end

    # --- Cross-solver sanity: Clarabel-QP vs Ipopt-NLP objective agree (Pitfall 4) ---
    # Re-solve the SAME assembly through the NLP factory (allow_local for Ipopt's
    # LOCALLY_SOLVED status on this convex problem) and check the welfare matches.
    _ctx2, obj2, _dadp2 = solve_welfare(
        feeder, LinDistFlow(), aggs;
        T = T, λ₀ = λ₀,
        optimizer = select_optimizer(NLP()),
        allow_local = true,
    )
    @test isapprox(obj, obj2; rtol = 1e-4, atol = 1e-4)
end

@testitem "welfare: DC + reactive aggregator solves active-only (WR-03, DEV-05)" tags = [:welfare] setup = [Phase3Fixtures] begin
    using TSODSO
    using JuMP

    T = Phase3Fixtures.T
    feeder = Phase3Fixtures.small_radial_feeder()
    Tout = Phase3Fixtures.Tout
    Pdc = Phase3Fixtures.Pdc
    λ₀ = Phase3Fixtures.λ₀
    φ = 0.9                                    # φ < 1 ⇒ the aggregator emits a reactive term

    prof = generate_profiles(seed = 20260718, T = T)
    function make_agg(bus)
        therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, Tout)
        defer = Deferrable(bus, 8, 16, 1.0, 0.5, 0.5)
        batt = PVBattery(bus, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, prof.pv)
        return Aggregator(bus, φ, [therm, defer, batt], Pdc)
    end
    aggs = [make_agg(2), make_agg(3)]          # reactive aggregators on NON-root load buses

    # WR-03: DCPowerFlow provides NO reactive channel, yet the aggregators still emit their
    # reactive term into :Rq. Previously balance_q was pinned to zero at every non-root
    # reactive bus ⇒ INFEASIBLE. Now the reactive channel is keyed off the FORMULATION, so a
    # DC study models active power only and SOLVES (the DC↔LinDistFlow interchange holds).
    ctx, obj, dadp = solve_welfare(feeder, DCPowerFlow(), aggs; T = T, λ₀ = λ₀)

    @test isfinite(obj)
    @test abs(obj) < 1e6
    @test length(dadp) == T
    @test all(isfinite, dadp)

    # Active-only: no reactive frontier import created and no reactive balance registered,
    # while the active balance IS closed and priced.
    @test !haskey(ctx.meta, :q_import)
    @test !haskey(ctx.constraints, :balance_q)
    @test haskey(ctx.constraints, :balance_p)

    # App. C battery complementarity still enforced under the DC formulation.
    @test haskey(ctx.meta, :agg_device_vars)
    batteries = [
        v for (_bus, varlist) in ctx.meta[:agg_device_vars] for v in varlist if
        haskey(v, :p_ch) && haskey(v, :p_dch)
    ]
    @test length(batteries) == 2
    for v in batteries, t in 1:T
        @test value(v.p_ch[t]) * value(v.p_dch[t]) < 1e-6
    end
end

@testitem "welfare: high-PV surplus is curtailed rather than infeasible (WR-04, DEV-04)" tags = [
    :welfare,
    :battery,
] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    T = 3
    # A 2-bus radial feeder: root/MEM frontier (bus 1) + one load bus (bus 2).
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )

    Pdc = fill(0.1, T)          # small inelastic load
    λ₀ = fill(40.0, T)
    Ppv = fill(100.0, T)        # MASSIVE PV — far beyond load or battery/storage capacity

    # STRICT λ ordering (CR-01) for the no-binary guarantee; tiny Pmax/SOC so the battery
    # cannot soak up the surplus — the ONLY recourse is PV curtailment.
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, Ppv)
    agg = Aggregator(2, 0.9, [batt], Pdc)

    # WR-04: PV is curtailable, so the surplus is dumped rather than forcing the
    # (export-less, p_import ≥ 0) root balance INFEASIBLE. Without pv_used this solve had no
    # recourse for the surplus and failed.
    ctx, obj, _dadp = solve_welfare(feeder, LinDistFlow(), [agg]; T = T, λ₀ = λ₀)
    @test isfinite(obj)

    # The curtailment variable exists and BINDS: used PV is well below the available Ppv.
    battery_vars = ctx.meta[:agg_device_vars][2][1]
    @test haskey(battery_vars, :pv_used)
    @test all(t -> value(battery_vars.pv_used[t]) <= Ppv[t] + 1e-6, 1:T)
    @test any(t -> value(battery_vars.pv_used[t]) < Ppv[t] - 1e-3, 1:T)
end

@testitem "welfare: battery complementarity is a base-free relative test (WR-02)" tags = [
    :welfare,
    :battery,
] begin
    using TSODSO, JuMP

    @test isdefined(TSODSO, :assert_battery_complementarity!)

    # Build a solved ModelContext holding ONE battery whose p_ch/p_dch are fixed to chosen
    # values, so the complementarity gate can be exercised in isolation (no full welfare solve).
    function ctx_with_battery(pmax, pch, pdch)
        T = length(pch)
        model = Model(TSODSO.select_optimizer(TSODSO.QP()))
        # Keep the upper_bound = Pmax intact (the gate recovers the rated power from it, as in
        # the real PVBattery where p_ch/p_dch are UNFIXED decision variables): pin the values
        # with equality constraints rather than `fix`, which would delete the bound.
        p_ch = @variable(model, [t = 1:T], lower_bound = 0.0, upper_bound = pmax)
        p_dch = @variable(model, [t = 1:T], lower_bound = 0.0, upper_bound = pmax)
        @constraint(model, [t = 1:T], p_ch[t] == pch[t])
        @constraint(model, [t = 1:T], p_dch[t] == pdch[t])
        @objective(model, Max, 0)
        optimize!(model)
        ctx = TSODSO.ModelContext(model)
        ctx.meta[:T] = T
        store = get!(ctx.meta, :agg_device_vars, Dict{Int,Vector{Any}}())
        store[2] = Any[(; p_ch, p_dch)]
        return ctx
    end

    # --- Base-independence: a genuine simultaneous charge/discharge is caught even when its
    # ABSOLUTE product is tiny. On a small-Pmax (≈large-base) battery, p_ch = p_dch = 5e-4
    # gives product 2.5e-7 — comfortably under the OLD absolute τ = 1e-4 (silently accepted) —
    # yet both legs are 50% of the 1e-3 rated power, so the RELATIVE gate REFUSES it.
    ctx_small = ctx_with_battery(1.0e-3, fill(5.0e-4, 3), fill(5.0e-4, 3))
    @test 5.0e-4 * 5.0e-4 < 1e-4                     # the old absolute gate would have passed it
    @test_throws Exception assert_battery_complementarity!(ctx_small; τ = 1e-3)

    # --- A genuinely large co-activation (10% of a 0.5 pu rating on each leg) is caught.
    ctx_big = ctx_with_battery(0.5, fill(0.05, 3), fill(0.05, 3))
    @test_throws Exception assert_battery_complementarity!(ctx_big; τ = 1e-3)

    # --- Solver-noise co-activation passes: one leg genuinely charges, the other carries only
    # a tiny numerical residual, so the product is negligible relative to Pmax².
    ctx_noise = ctx_with_battery(0.1, fill(1.0e-3, 3), fill(8.0e-6, 3))
    @test assert_battery_complementarity!(ctx_noise; τ = 1e-3) === nothing

    # --- Clean complementarity (one leg exactly zero) always passes.
    ctx_clean = ctx_with_battery(0.5, [0.3, 0.0, 0.2], [0.0, 0.25, 0.0])
    @test assert_battery_complementarity!(ctx_clean; τ = 1e-3) === nothing
end
