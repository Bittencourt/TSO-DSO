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
