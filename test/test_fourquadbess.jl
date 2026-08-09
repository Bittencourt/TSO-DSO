# Seam: devices/FourQuadBESS.jl (MESH-04). Standalone 4Q battery + inverter, no binaries.
#
# Plan 19-02 turns these green. The headline correctness risk of the phase: the App. C
# no-binary argument (`PVBattery.jl:42-57`) is a PURE ACTIVE-POWER, 1-D argument and does
# NOT automatically transfer once a genuine P-Q apparent-power cone and asymmetric
# grid-charging caps are introduced (RESEARCH.md's "Complementarity Derivation Skeleton").
# Task 1 covers construction + guard-rejection only; Task 2 (this same file, extended)
# covers `contribute!`'s variable/cone/return shape. The post-solve numeric certificate
# itself is plan 19-05's `assert_4q_complementarity!` and is NOT tested here. Every item
# name contains "fourquadbess" so `occursin("fourquadbess", ti.name)` selects it.

@testitem "fourquadbess: FourQuadBESS device type exists (MESH-04)" tags = [:fourquadbess] begin
    using TSODSO

    @test isdefined(TSODSO, :FourQuadBESS)
end

@testitem "fourquadbess: construction succeeds with valid, distinct caps + strict λ ordering (D-01/D-02)" tags =
    [:fourquadbess] begin
    using TSODSO

    # bus, η, Δt, Pch_max, Pdch_max, Smax, Emin, Emax, soc0, λ_min, λ_med, λ_max
    good() = TSODSO.FourQuadBESS(2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0)
    @test good() isa TSODSO.AbstractDevice
    @test good() isa TSODSO.FourQuadBESS{Float64}

    # IN-01: a mixed-type call promotes to a common Float64 rather than MethodError.
    mixed = TSODSO.FourQuadBESS(2, 0.95, 1, 4, 5, 6, 0, 10, 2, 1, 4, 9)
    @test mixed isa TSODSO.FourQuadBESS{Float64}
    @test mixed.Pch_max === 4.0
    @test mixed.Pdch_max === 5.0
end

@testitem "fourquadbess: constructor rejects non-positive Pch_max/Pdch_max independently (D-04)" tags =
    [:fourquadbess] begin
    using TSODSO

    # Pch_max <= 0 must throw INDEPENDENTLY of Pdch_max's value (asymmetric caps, D-04).
    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 0.95, 1.0, 0.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0,
    )
    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 0.95, 1.0, -1.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0,
    )
    # Pdch_max <= 0 must throw INDEPENDENTLY of Pch_max's value.
    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 0.95, 1.0, 4.0, 0.0, 6.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0,
    )
    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 0.95, 1.0, 4.0, -1.0, 6.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0,
    )
end

@testitem "fourquadbess: constructor rejects Smax <= 0 (apparent-power cone bound)" tags =
    [:fourquadbess] begin
    using TSODSO

    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 0.95, 1.0, 4.0, 5.0, 0.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0,
    )
    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 0.95, 1.0, 4.0, 5.0, -1.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0,
    )
end

@testitem "fourquadbess: constructor rejects η outside (0,1] (eq. 3.6 analog)" tags =
    [:fourquadbess] begin
    using TSODSO

    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 1.5, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0,
    )  # η > 1
    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 0.0, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0,
    )  # η <= 0
end

@testitem "fourquadbess: constructor rejects soc0 outside [Emin, Emax] (SOC-band IC)" tags =
    [:fourquadbess] begin
    using TSODSO

    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 100.0, 1.0, 4.0, 9.0,
    )  # soc0 > Emax
    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, -1.0, 1.0, 4.0, 9.0,
    )  # soc0 < Emin
end

@testitem "fourquadbess: constructor rejects non-strict λ_min < λ_med < λ_max (internal 1-D dominance premise)" tags =
    [:fourquadbess] begin
    using TSODSO

    # λ_med OUTSIDE [λ_min, λ_max].
    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 10.0, 9.0,
    )  # λ_med > λ_max
    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 0.5, 9.0,
    )  # λ_med < λ_min

    # CR-01: a NON-STRICT ordering (any equality) is rejected — same rationale as
    # `PVBattery` (the INTERNAL 1-D dominance argument still needs it for a fixed net p;
    # see Task 2's re-derivation docstring for why this is still load-bearing here).
    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 4.0, 4.0, 9.0,
    )  # λ_min == λ_med
    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 9.0, 9.0,
    )  # λ_med == λ_max
    @test_throws ArgumentError TSODSO.FourQuadBESS(
        2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 4.0, 4.0, 4.0,
    )  # all equal
end

@testitem "fourquadbess: contribute! creates the expected variables + bounds (D-01/D-02/D-04)" tags =
    [:fourquadbess] begin
    using TSODSO, JuMP

    model = Model()
    ctx = TSODSO.ModelContext(model)
    T = 3
    d = TSODSO.FourQuadBESS(2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0)

    res = TSODSO.contribute!(d, ctx; T = T)

    p_ch, p_dch, soc, q = res.vars.p_ch, res.vars.p_dch, res.vars.soc, res.vars.q
    @test length(p_ch) == T
    @test length(p_dch) == T
    @test length(soc) == T
    @test length(q) == T
    for t in 1:T
        @test lower_bound(p_ch[t]) == 0.0
        @test upper_bound(p_ch[t]) == d.Pch_max
        @test lower_bound(p_dch[t]) == 0.0
        @test upper_bound(p_dch[t]) == d.Pdch_max
        @test lower_bound(soc[t]) == d.Emin
        @test upper_bound(soc[t]) == d.Emax
        # q is FREE inside the cone (D-03): no explicit variable bound.
        @test !has_lower_bound(q[t])
        @test !has_upper_bound(q[t])
    end
end

@testitem "fourquadbess: contribute! has NO pv_used/Ppv coupling anywhere (D-01/D-02)" tags =
    [:fourquadbess] begin
    using TSODSO

    # D-01/D-02: no PV coupling anywhere in the source file (grep-verified, mirrors the
    # plan's acceptance criterion — checked here so it is a live regression, not just a
    # one-time human grep).
    src_path = joinpath(dirname(dirname(pathof(TSODSO))), "src", "devices", "FourQuadBESS.jl")
    src = read(src_path, String)
    @test !occursin("pv_used", src)
    @test !occursin("Ppv", src)
end

@testitem "fourquadbess: contribute! ties Smax/net-p/q into a SecondOrderCone (D-03/D-04)" tags =
    [:fourquadbess] begin
    using TSODSO, JuMP

    model = Model()
    ctx = TSODSO.ModelContext(model)
    T = 2
    d = TSODSO.FourQuadBESS(2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0)
    res = TSODSO.contribute!(d, ctx; T = T)

    cone_constraints = [
        c for c in all_constraints(model; include_variable_in_set_constraints = false) if
        constraint_object(c).set isa MOI.SecondOrderCone
    ]
    @test length(cone_constraints) == T
end

@testitem "fourquadbess: contribute! SOC recursion + IC hold (mirrors PVBattery 3.6/3.9)" tags =
    [:fourquadbess] begin
    using TSODSO, JuMP

    model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
    ctx = TSODSO.ModelContext(model)
    T = 3
    d = TSODSO.FourQuadBESS(2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0)
    res = TSODSO.contribute!(d, ctx; T = T)

    @objective(model, Max, res.utility)
    TSODSO.assert_solved!(model; dual = false, allow_local = false)

    soc = res.vars.soc
    @test isapprox(value(soc[1]), d.soc0; atol = 1e-6)
end

@testitem "fourquadbess: contribute! returns the widened contract with q_inject (D-09)" tags =
    [:fourquadbess] begin
    using TSODSO, JuMP

    model = Model()
    ctx = TSODSO.ModelContext(model)
    T = 2
    d = TSODSO.FourQuadBESS(2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0)
    res = TSODSO.contribute!(d, ctx; T = T)

    @test isempty(ctx.residuals)
    @test !haskey(ctx.meta, :objective)
    @test res.utility isa QuadExpr
    @test length(res.p_inject) == T
    @test all(x -> x isa AffExpr, res.p_inject)
    @test res.q_inject === res.vars.q               # same object, D-09
    @test propertynames(res) == (:vars, :p_inject, :q_inject, :utility)
end

@testitem "fourquadbess: contribute! widens soc0 to a genuine Parameter, byte-identical default (MPC-01 seam)" tags =
    [:fourquadbess] begin
    using TSODSO, JuMP

    # Reuse the SAME literal parameters as the "contribute! creates the expected
    # variables + bounds" item's fixture.
    model = Model()
    ctx = TSODSO.ModelContext(model)
    T = 3
    d = TSODSO.FourQuadBESS(2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0)
    res = TSODSO.contribute!(d, ctx; T = T)

    # (a) Byte-identical default: soc0's Parameter value equals the ORIGINAL literal.
    @test parameter_value(res.vars.soc0) == 2.0

    # (b) set_parameter_value changes the value with NO new variable/constraint added.
    nv0 = num_variables(model)
    nc0 = num_constraints(model; count_variable_in_set_constraints = true)
    set_parameter_value(res.vars.soc0, 0.5)
    @test parameter_value(res.vars.soc0) == 0.5
    @test num_variables(model) == nv0
    @test num_constraints(model; count_variable_in_set_constraints = true) == nc0
end

# Plan 19-05: assert_4q_complementarity! (MESH-04 clause 2) + the OLD
# assert_battery_complementarity!'s tightened mutual-exclusivity guard. The shared
# harness below mirrors the plan's standalone-solve pattern: one FourQuadBESS, its OWN
# ModelContext, SOCP()/Clarabel, and a manually-populated ctx.meta[:agg_device_vars]
# stash (this fixture bypasses Aggregator on purpose, to isolate the certificate).

@testitem "fourquadbess: assert_4q_complementarity! exists, is exported, callable with only ctx (D-07)" tags =
    [:fourquadbess, :complementarity] begin
    using TSODSO, JuMP

    @test isdefined(TSODSO, :assert_4q_complementarity!)

    # Benign, strictly App.-C-dominated fixture: one FourQuadBESS, a POSITIVE in-band
    # price (no grid-charging incentive) -- App. C dominance clearly holds.
    d = TSODSO.FourQuadBESS(2, 0.95, 1.0, 4.0, 5.0, 6.0, 0.0, 10.0, 2.0, 1.0, 4.0, 9.0)
    model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
    ctx = TSODSO.ModelContext(model)
    ctx.meta[:T] = 3
    res = TSODSO.contribute!(d, ctx; T = 3)
    λ_test = 2.5
    @objective(model, Max, res.utility - λ_test * sum(res.p_inject[t] for t in 1:3))
    TSODSO.assert_solved!(model; dual = false, allow_local = false)

    store = get!(ctx.meta, :agg_device_vars, Dict{Int, Vector{Any}}())
    append!(get!(store, d.bus, Vector{Any}()), [res.vars])

    # Callable with only ctx (defaults present) -- must NOT throw on this benign solve.
    ratio = TSODSO.assert_4q_complementarity!(ctx)
    @test ratio isa Float64
    @test ratio <= 1.0

    # No-op (returns 0.0) when ctx.meta[:agg_device_vars] is absent entirely.
    model2 = Model()
    ctx2 = TSODSO.ModelContext(model2)
    ctx2.meta[:T] = 3
    @test TSODSO.assert_4q_complementarity!(ctx2) == 0.0
end

@testitem "fourquadbess: assert_battery_complementarity! silently skips a FourQuadBESS-only stash (T-19-11)" tags =
    [:fourquadbess, :complementarity] begin
    using TSODSO, JuMP

    # A DELIBERATELY-violating FourQuadBESS fixture (see the honest-boundary item below
    # for the mechanism) -- the OLD, PVBattery-shaped check must skip it REGARDLESS of
    # how badly p_ch/p_dch co-activate, because its tightened loop condition
    # (!haskey(v,:q)) never even LOOKS at a device carrying a reactive decision.
    d = TSODSO.FourQuadBESS(2, 0.5, 1.0, 8.0, 8.0, 12.0, 0.0, 1.5, 1.3, 1.0, 4.0, 9.0)
    model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
    ctx = TSODSO.ModelContext(model)
    ctx.meta[:T] = 2
    res = TSODSO.contribute!(d, ctx; T = 2)
    λ_test = 9.0
    @objective(model, Max, res.utility - λ_test * sum(res.p_inject[t] for t in 1:2))
    TSODSO.assert_solved!(model; dual = false, allow_local = false)

    store = get!(ctx.meta, :agg_device_vars, Dict{Int, Vector{Any}}())
    append!(get!(store, d.bus, Vector{Any}()), [res.vars])

    # Confirm this fixture DOES co-activate (p_ch, p_dch both meaningfully positive) --
    # otherwise skipping it would prove nothing.
    @test value(res.vars.p_ch[1]) > 1.0
    @test value(res.vars.p_dch[1]) > 1.0

    # The OLD check must return nothing (never throw) -- it never even inspects this
    # device's vars, since haskey(v,:q) makes the tightened loop condition false.
    @test TSODSO.assert_battery_complementarity!(ctx; τ = 1e-9) === nothing
end

@testitem "fourquadbess: assert_4q_complementarity! defaults are scale-aware at per-unit device scale (CR-01)" tags =
    [:fourquadbess, :complementarity] begin
    using TSODSO, JuMP

    # CR-01 regression (phase-19 code review): the ORIGINAL flat `atol = 1e-6` floor dominated
    # the `atol + rtol·scale²` tolerance at the committed per-unit fixture scales (scale² = 4e-4
    # on the 2-bus fixture, 6.25e-6 on the IEEE-13 one), so simultaneous legs of up to ~40% of
    # an IEEE-13-scale device's rating slid under the certificate. The re-measured defaults
    # (rtol = 1e-4, atol = 1e-8 — see the certificate's tolerance-provenance docstring) must
    # FLAG exactly those escapes while still clearing the measured production noise floor.
    #
    # Harness: pin p_ch/p_dch at a chosen leg magnitude via EQUALITY CONSTRAINTS — never
    # `fix(...; force = true)`, which DELETES the variable bounds the certificate recovers the
    # device scale from (`upper_bound(v.p_ch[1])`).
    function pinned_ctx(pmax, leg)
        model = Model(TSODSO.select_optimizer(TSODSO.QP()))
        ctx = TSODSO.ModelContext(model)
        T = 2
        ctx.meta[:T] = T
        p_ch = @variable(model, [t = 1:T], lower_bound = 0.0, upper_bound = pmax)
        p_dch = @variable(model, [t = 1:T], lower_bound = 0.0, upper_bound = pmax)
        q = @variable(model, [t = 1:T])
        @constraint(model, [t = 1:T], p_ch[t] == leg)
        @constraint(model, [t = 1:T], p_dch[t] == leg)
        @constraint(model, [t = 1:T], q[t] == 0.0)
        @objective(model, Max, 0.0)
        TSODSO.assert_solved!(model; dual = false, allow_local = false)
        store = get!(ctx.meta, :agg_device_vars, Dict{Int, Vector{Any}}())
        append!(get!(store, 2, Vector{Any}()), [(; p_ch, p_dch, q)])
        return ctx
    end

    # (a) IEEE-13 device scale (Pch_max = 0.0025), legs at 40% of rating — the review's cited
    #     escape (product 1e-6 vs old tol ≈ 1e-6, ratio ≈ 1): now ratio ≈ 94, must THROW.
    @test_throws ErrorException TSODSO.assert_4q_complementarity!(pinned_ctx(0.0025, 1e-3))
    # (b) 2-bus device scale (Pch_max = 0.02), legs at 5% of rating — the review's other cited
    #     escape: now ratio ≈ 20, must THROW.
    @test_throws ErrorException TSODSO.assert_4q_complementarity!(pinned_ctx(0.02, 1e-3))
    # (c) the measured production noise-floor magnitude still PASSES: per-leg ~1e-5 at the
    #     2-bus scale (product ~1e-10, below the atol = 1e-8 machine-noise guard).
    @test TSODSO.assert_4q_complementarity!(pinned_ctx(0.02, 1e-5)) <= 1.0
end

@testitem "fourquadbess: assert_4q_complementarity! throws on the honest D-08 boundary; report=true neutralizes it" tags =
    [:fourquadbess, :complementarity] begin
    using TSODSO, JuMP

    # Deliberately-constructed negative-effective-price + grid-charging fixture (D-08):
    # a large, in-band-exceeding frontier price rewards grid-charging up to Pch_max
    # (D-02: no PV-availability limit on charge) while a TIGHT upper SOC band (Emax
    # only 0.2 above soc0) cannot accommodate that charge without a compensating
    # discharge -- since η<1 makes VENTING a large charge via a SMALL discharge cheap
    # (asymmetric round-trip efficiency, the derivation's step 3), the solved optimum
    # co-activates p_ch AND p_dch at t=1 far beyond any plausible solver noise. Per the
    # harness's own sign convention (objective = utility - λ_test*Σp_inject, so a unit
    # of DISCHARGE/injection nets an EFFECTIVE price of -λ_test at the device), the
    # large positive λ_test here means discharging faces a genuinely NEGATIVE effective
    # per-unit price at the binding period -- exactly the regime D-08 predicts the
    # certificate legitimately (not buggily) refuses.
    d = TSODSO.FourQuadBESS(2, 0.5, 1.0, 8.0, 8.0, 12.0, 0.0, 1.5, 1.3, 1.0, 4.0, 9.0)
    model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
    ctx = TSODSO.ModelContext(model)
    ctx.meta[:T] = 2
    res = TSODSO.contribute!(d, ctx; T = 2)
    λ_test = 9.0
    @objective(model, Max, res.utility - λ_test * sum(res.p_inject[t] for t in 1:2))
    TSODSO.assert_solved!(model; dual = false, allow_local = false)

    store = get!(ctx.meta, :agg_device_vars, Dict{Int, Vector{Any}}())
    append!(get!(store, d.bus, Vector{Any}()), [res.vars])

    prod1 = value(res.vars.p_ch[1]) * value(res.vars.p_dch[1])
    @test prod1 > 1.0   # genuine, large co-activation -- not solver noise

    # (b) throws by default (Task 1's measured rtol/atol defaults).
    @test_throws ErrorException TSODSO.assert_4q_complementarity!(ctx)

    # (c) report = true neutralizes the SAME violating fixture -- no exception, and the
    # returned diagnostic still names the violation's magnitude (worst ratio > 1).
    ratio = TSODSO.assert_4q_complementarity!(ctx; report = true)
    @test ratio > 1.0
end

