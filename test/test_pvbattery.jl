# Seam: devices/PVBattery.jl. PV + battery (BESS), no binaries.
#
# The headline correctness risk of the seam: the
# no-binary battery. App. C (pp. 166-168) proves that with λ_min ≤ λ_med ≤ λ_max the
# concave charge utility + convex discharge cost make simultaneous charge/discharge
# strictly dominated, so p_ch·p_dch = 0 at the optimum WITHOUT any complementarity
# constraint or binary. Because NO constraint forbids it, correctness rests entirely on
# the parametrization — so the mandatory post-solve numeric assertion
# `value(p_ch[t])·value(p_dch[t]) < τ` is exercised here on a
# standalone convex-QP solve. Every item name contains "battery" so
# `occursin("battery", ti.name)` selects it.

@testitem "battery: PVBattery device type exists over the T=24 fixture" tags = [:battery] setup =
    [SmallRadialFixtures] begin
    using TSODSO

    # The shared fixture is healthy (exercises setup wiring): a valid 3-bus feeder + T=24 PV profile.
    feeder = SmallRadialFixtures.small_radial_feeder()
    @test length(feeder.buses) == 3
    @test length(SmallRadialFixtures.Ppv) == SmallRadialFixtures.T == 24

    # The no-binary PV+battery device (SOC 3.6-3.9, utility 3.15-3.20) exists.
    @test isdefined(TSODSO, :PVBattery)
end

@testitem "battery: PVBattery constructor guards reject the App. C / physics violations" tags =
    [:battery] begin
    using TSODSO

    # A valid parameterization with a STRICT λ ordering (so the App. C dominance is strict).
    Ppv = fill(5.0, 4)
    good() = TSODSO.PVBattery(2, 0.95, 1.0, 5.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0, Ppv)
    @test good() isa TSODSO.AbstractDevice
    @test good() isa TSODSO.PVBattery{Float64}

    # λ_med OUTSIDE [λ_min, λ_max] — the load-bearing App. C guard.
    @test_throws ArgumentError TSODSO.PVBattery(
        2,
        0.95,
        1.0,
        5.0,
        0.0,
        10.0,
        2.0,
        1.0,
        10.0,
        9.0,
        Ppv,
    ) # λ_med > λ_max
    @test_throws ArgumentError TSODSO.PVBattery(
        2,
        0.95,
        1.0,
        5.0,
        0.0,
        10.0,
        2.0,
        1.0,
        0.5,
        9.0,
        Ppv,
    )  # λ_med < λ_min

    # A NON-STRICT ordering (any equality) is rejected — equality zeroes a utility
    # curvature and admits SOC-draining p_ch·p_dch > 0 co-optima, breaking the App. C
    # no-binary guarantee. Only STRICT λ_min < λ_med < λ_max is admissible.
    @test_throws ArgumentError TSODSO.PVBattery(
        2,
        0.95,
        1.0,
        5.0,
        0.0,
        10.0,
        2.0,
        4.0,
        4.0,
        9.0,
        Ppv,
    )  # λ_min == λ_med
    @test_throws ArgumentError TSODSO.PVBattery(
        2,
        0.95,
        1.0,
        5.0,
        0.0,
        10.0,
        2.0,
        1.0,
        9.0,
        9.0,
        Ppv,
    )  # λ_med == λ_max
    @test_throws ArgumentError TSODSO.PVBattery(
        2,
        0.95,
        1.0,
        5.0,
        0.0,
        10.0,
        2.0,
        4.0,
        4.0,
        4.0,
        Ppv,
    )  # all equal

    # η OUTSIDE (0, 1] — a physical round-trip efficiency (eq. 3.6).
    @test_throws ArgumentError TSODSO.PVBattery(
        2,
        1.5,
        1.0,
        5.0,
        0.0,
        10.0,
        2.0,
        1.0,
        4.0,
        9.0,
        Ppv,
    )  # η > 1
    @test_throws ArgumentError TSODSO.PVBattery(
        2,
        0.0,
        1.0,
        5.0,
        0.0,
        10.0,
        2.0,
        1.0,
        4.0,
        9.0,
        Ppv,
    )  # η ≤ 0

    # soc0 OUTSIDE [Emin, Emax] — the SOC-band IC (eq. 3.9).
    @test_throws ArgumentError TSODSO.PVBattery(
        2,
        0.95,
        1.0,
        5.0,
        0.0,
        10.0,
        100.0,
        1.0,
        4.0,
        9.0,
        Ppv,
    ) # soc0 > Emax
    @test_throws ArgumentError TSODSO.PVBattery(
        2,
        0.95,
        1.0,
        5.0,
        0.0,
        10.0,
        -1.0,
        1.0,
        4.0,
        9.0,
        Ppv,
    )  # soc0 < Emin

    # Pmax must be > 0 (eq. 3.8; it also divides the utility curvatures 3.17-3.20).
    @test_throws ArgumentError TSODSO.PVBattery(
        2,
        0.95,
        1.0,
        0.0,
        0.0,
        10.0,
        2.0,
        1.0,
        4.0,
        9.0,
        Ppv,
    )

    # A mixed-type call (a Float64 η among integer args, Int-eltype Ppv) promotes
    # to a common Float64 rather than MethodError.
    mixed = TSODSO.PVBattery(2, 0.95, 1, 5, 0, 10, 2, 1, 4, 9, [5, 5, 5, 5])
    @test mixed isa TSODSO.PVBattery{Float64}
    @test mixed.Pmax === 5.0
end

@testitem "battery: standalone convex-QP solve holds p_ch·p_dch < τ with ZERO binaries (App. C)" tags =
    [:battery] begin
    using TSODSO, JuMP

    # --- A bare battery-only convex QP, NO feeder anywhere (device is network-agnostic) ---
    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx = TSODSO.ModelContext(model)
    @test ctx.feeder === nothing

    # STRICT λ ordering (thesis-typical 1/4/9 ¢$/kWh) so the App. C dominance is strict.
    T = 4
    Ppv = [5.0, 5.0, 0.0, 0.0]                     # PV available early, none late
    bat = TSODSO.PVBattery(2, 0.95, 1.0, 5.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0, Ppv)

    res = TSODSO.contribute!(bat, ctx; T = T)

    # Aggregatable contract: the device wrote NOTHING to the residual/objective seams.
    @test isempty(ctx.residuals)
    @test isempty(ctx.objective.terms) && iszero(ctx.objective.aff)
    @test res.utility isa QuadExpr                 # concave charge utility − convex discharge cost
    @test length(res.p_inject) == T
    @test all(x -> x isa AffExpr, res.p_inject)    # p_inject = Ppv − p_ch + p_dch (affine)

    # A time-varying export price closes the QP AND creates genuine charge/discharge tension:
    # cheap early (charging beats exporting PV), expensive late (discharging pays off). The
    # App. C claim is that the schedule STILL never charges and discharges in the same hour.
    price = [2.0, 2.0, 20.0, 20.0]
    @objective(model, Max, res.utility + sum(price[t] * res.p_inject[t] for t in 1:T))

    # Solve gate: trust results only on OPTIMAL + feasible primal AND dual (prices are duals).
    TSODSO.assert_solved!(model; dual = true, allow_local = false)

    p_ch, p_dch, soc = res.vars.p_ch, res.vars.p_dch, res.vars.soc

    # === App. C mandatory numeric verification ===
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

    # === Zero-binary / zero-integer invariant ===
    # Adding a binary or complementarity constraint would break QP convexity + the
    # downstream pricing (duals) — assert it never happened.
    vars = all_variables(model)
    # p_ch, p_dch, pv_used = 3T, PLUS soc which is now T+1 long (the horizon-closing
    # fix: this golden MOVED from 5T + 1 to 5T + 2 — soc grew by one variable to close the SOC
    # recursion over the whole horizon), PLUS the Parameter widening: soc0 (1
    # Parameter) + Ppv_param (T Parameters) — Parameters ARE VariableRefs in JuMP, counted
    # here too: 3T + (T+1) + 1 + T = 5T + 2, even though their DEFAULT solved behavior is
    # bit-for-bit identical.
    @test length(vars) == 5T + 2
    @test count(is_binary, vars) == 0
    @test count(is_integer, vars) == 0

    # The curtailment variable exists and is available for surplus PV to be dumped.
    @test haskey(res.vars, :pv_used)
    @test length(res.vars.pv_used) == T
end

@testitem "battery: contribute! widens soc0/Ppv_param to a genuine Parameter, bit-for-bit identical default" tags =
    [:battery] begin
    using TSODSO, JuMP

    # Reuse the SAME literal parameters as the "constructor guards" item's `good()` fixture.
    Ppv = fill(5.0, 4)
    model = Model()
    ctx = TSODSO.ModelContext(model)
    T = 4
    bat = TSODSO.PVBattery(2, 0.95, 1.0, 5.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0, Ppv)
    res = TSODSO.contribute!(bat, ctx; T = T)

    # (a) bit-for-bit identical default: every new Parameter's value equals the ORIGINAL literal.
    @test parameter_value(res.vars.soc0) == 2.0
    @test all(parameter_value.(res.vars.Ppv_param) .== Ppv)

    # (b) set_parameter_value changes the value with NO new variable/constraint added
    # (count_variable_in_set_constraints = true — test_planning_oracle.jl's idiom).
    nv0 = num_variables(model)
    nc0 = num_constraints(model; count_variable_in_set_constraints = true)
    set_parameter_value(res.vars.soc0, 0.5)
    set_parameter_value.(res.vars.Ppv_param, fill(1.0, T))
    @test parameter_value(res.vars.soc0) == 0.5
    @test all(parameter_value.(res.vars.Ppv_param) .== 1.0)
    @test num_variables(model) == nv0
    @test num_constraints(model; count_variable_in_set_constraints = true) == nc0

    # (c) The old literal-bound code path is genuinely gone: pv_used carries NO upper
    # bound anymore (the PV limit moved to a Ppv_param-backed constraint).
    @test has_upper_bound(res.vars.pv_used[1]) == false
end

@testitem "battery: soc0=Emin + hour-T discharge incentive drives p_dch[T] to zero" tags =
    [:battery] begin
    using TSODSO, JuMP

    # Regression: soc is now T+1 long with the recursion closing over the
    # WHOLE horizon (t = 1:T), so p_dch[T] always appears in a constraint. Starting at
    # soc0 = Emin with zero PV availability (no charging headroom, physically enforced by
    # Ppv ≡ 0 — charge from PV only) and a heavy hour-T discharge incentive,
    # the optimal p_dch[T] must be driven to (numerically) zero — the bound
    # soc[T+1] >= Emin makes any further discharge infeasible.
    T = 3
    bat = TSODSO.PVBattery(2, 0.95, 1.0, 5.0, 0.0, 10.0, 0.0, 1.0, 4.0, 9.0, fill(0.0, T))
    model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
    ctx = TSODSO.ModelContext(model)
    res = TSODSO.contribute!(bat, ctx; T = T)

    price = [0.0, 0.0, 100.0]
    @objective(model, Max, res.utility + sum(price[t] * res.p_inject[t] for t in 1:T))
    TSODSO.assert_solved!(model; dual = false, allow_local = false)

    @test value(res.vars.p_dch[T]) < 1e-6
end
