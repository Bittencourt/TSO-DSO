# Seam: devices/PVBattery.jl (DEV-04). PV + battery (BESS), no binaries.
#
# Plan 03-04 turns these green. The headline correctness risk of the phase: the
# no-binary battery. App. C (pp. 166-168) proves that with λ_min ≤ λ_med ≤ λ_max the
# concave charge utility + convex discharge cost make simultaneous charge/discharge
# strictly dominated, so p_ch·p_dch = 0 at the optimum WITHOUT any complementarity
# constraint or binary. Because NO constraint forbids it, correctness rests entirely on
# the parametrization — so the mandatory post-solve numeric assertion
# `value(p_ch[t])·value(p_dch[t]) < τ` (RESEARCH Pitfall 1) is exercised here on a
# standalone convex-QP solve. Every item name contains "battery" so
# `occursin("battery", ti.name)` selects it.

@testitem "battery: PVBattery device type exists over the T=24 fixture (DEV-04)" tags = [:battery] setup = [Phase3Fixtures] begin
    using TSODSO

    # The shared fixture is healthy (exercises setup wiring): a valid 3-bus feeder + T=24 PV profile.
    feeder = Phase3Fixtures.small_radial_feeder()
    @test length(feeder.buses) == 3
    @test length(Phase3Fixtures.Ppv) == Phase3Fixtures.T == 24

    # The no-binary PV+battery device (SOC 3.6-3.9, utility 3.15-3.20) exists (DEV-04).
    @test isdefined(TSODSO, :PVBattery)
end

@testitem "battery: PVBattery constructor guards reject the App. C / physics violations (DEV-04)" tags = [:battery] begin
    using TSODSO

    # A valid parameterization with a STRICT λ ordering (so the App. C dominance is strict).
    Ppv = fill(5.0, 4)
    good() = TSODSO.PVBattery(2, 0.95, 1.0, 5.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0, Ppv)
    @test good() isa TSODSO.AbstractDevice
    @test good() isa TSODSO.PVBattery{Float64}

    # λ_med OUTSIDE [λ_min, λ_max] — the load-bearing App. C guard (threat T-03-09).
    @test_throws ArgumentError TSODSO.PVBattery(2, 0.95, 1.0, 5.0, 0.0, 10.0, 2.0, 1.0, 10.0, 9.0, Ppv) # λ_med > λ_max
    @test_throws ArgumentError TSODSO.PVBattery(2, 0.95, 1.0, 5.0, 0.0, 10.0, 2.0, 1.0, 0.5, 9.0, Ppv)  # λ_med < λ_min

    # CR-01: a NON-STRICT ordering (any equality) is rejected — equality zeroes a utility
    # curvature and admits SOC-draining p_ch·p_dch > 0 co-optima, breaking the App. C
    # no-binary guarantee. Only STRICT λ_min < λ_med < λ_max is admissible.
    @test_throws ArgumentError TSODSO.PVBattery(2, 0.95, 1.0, 5.0, 0.0, 10.0, 2.0, 4.0, 4.0, 9.0, Ppv)  # λ_min == λ_med
    @test_throws ArgumentError TSODSO.PVBattery(2, 0.95, 1.0, 5.0, 0.0, 10.0, 2.0, 1.0, 9.0, 9.0, Ppv)  # λ_med == λ_max
    @test_throws ArgumentError TSODSO.PVBattery(2, 0.95, 1.0, 5.0, 0.0, 10.0, 2.0, 4.0, 4.0, 4.0, Ppv)  # all equal

    # η OUTSIDE (0, 1] — a physical round-trip efficiency (eq. 3.6).
    @test_throws ArgumentError TSODSO.PVBattery(2, 1.5, 1.0, 5.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0, Ppv)  # η > 1
    @test_throws ArgumentError TSODSO.PVBattery(2, 0.0, 1.0, 5.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0, Ppv)  # η ≤ 0

    # soc0 OUTSIDE [Emin, Emax] — the SOC-band IC (eq. 3.9).
    @test_throws ArgumentError TSODSO.PVBattery(2, 0.95, 1.0, 5.0, 0.0, 10.0, 100.0, 1.0, 4.0, 9.0, Ppv) # soc0 > Emax
    @test_throws ArgumentError TSODSO.PVBattery(2, 0.95, 1.0, 5.0, 0.0, 10.0, -1.0, 1.0, 4.0, 9.0, Ppv)  # soc0 < Emin

    # Pmax must be > 0 (eq. 3.8; it also divides the utility curvatures 3.17-3.20).
    @test_throws ArgumentError TSODSO.PVBattery(2, 0.95, 1.0, 0.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0, Ppv)

    # IN-01: a mixed-type call (a Float64 η among integer args, Int-eltype Ppv) promotes
    # to a common Float64 rather than MethodError.
    mixed = TSODSO.PVBattery(2, 0.95, 1, 5, 0, 10, 2, 1, 4, 9, [5, 5, 5, 5])
    @test mixed isa TSODSO.PVBattery{Float64}
    @test mixed.Pmax === 5.0
end

@testitem "battery: standalone convex-QP solve holds p_ch·p_dch < τ with ZERO binaries (App. C, DEV-04)" tags = [:battery] begin
    using TSODSO, JuMP

    # --- A bare battery-only convex QP, NO feeder anywhere (device is network-agnostic) ---
    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx = TSODSO.ModelContext(model)
    @test !haskey(ctx.meta, :feeder)

    # STRICT λ ordering (thesis-typical 1/4/9 ¢$/kWh) so the App. C dominance is strict.
    T = 4
    Ppv = [5.0, 5.0, 0.0, 0.0]                     # PV available early, none late
    bat = TSODSO.PVBattery(2, 0.95, 1.0, 5.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0, Ppv)

    res = TSODSO.contribute!(bat, ctx; T = T)

    # Aggregatable contract: the device wrote NOTHING to the residual/objective seams.
    @test isempty(ctx.residuals)
    @test !haskey(ctx.meta, :objective)
    @test res.utility isa QuadExpr                 # concave charge utility − convex discharge cost
    @test length(res.p_inject) == T
    @test all(x -> x isa AffExpr, res.p_inject)    # p_inject = Ppv − p_ch + p_dch (affine)

    # A time-varying export price closes the QP AND creates genuine charge/discharge tension:
    # cheap early (charging beats exporting PV), expensive late (discharging pays off). The
    # App. C claim is that the schedule STILL never charges and discharges in the same hour.
    price = [2.0, 2.0, 20.0, 20.0]
    @objective(model, Max, res.utility + sum(price[t] * res.p_inject[t] for t in 1:T))

    # INFRA-03 gate: trust results only on OPTIMAL + feasible primal AND dual (prices are duals).
    TSODSO.assert_solved!(model; dual = true, allow_local = false)

    p_ch, p_dch, soc = res.vars.p_ch, res.vars.p_dch, res.vars.soc

    # === App. C mandatory numeric verification (RESEARCH Pitfall 1) ===
    # No constraint forbids p_ch·p_dch > 0; the parametrization alone must drive it to 0.
    τ = 1e-6
    for t in 1:T
        @test value(p_ch[t]) * value(p_dch[t]) < τ
    end

    # The scenario is NON-trivial: it actually charges early and discharges late, so the
    # complementarity above is meaningful (not vacuously p_dch ≡ 0).
    @test sum(value(p_ch[t]) for t in 1:T) > 1e-3
    @test sum(value(p_dch[t]) for t in 1:T) > 1e-3

    # SOC initial condition (3.9 IC) holds at the solution.
    @test isapprox(value(soc[1]), 2.0; atol = 1e-6)

    # === Zero-binary / zero-integer invariant (threat T-03-10) ===
    # Adding a binary or complementarity constraint would break QP convexity + Phase-5
    # pricing. RESEARCH §Anti-Patterns forbids it — assert it never happened.
    vars = all_variables(model)
    @test length(vars) == 3T                        # p_ch, p_dch, soc only
    @test count(is_binary, vars) == 0
    @test count(is_integer, vars) == 0
end
