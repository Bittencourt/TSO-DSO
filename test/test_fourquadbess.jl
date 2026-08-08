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

