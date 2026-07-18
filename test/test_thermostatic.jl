# Seam: devices/Thermostatic.jl (DEV-01). Thermostatic (A/C) flexible load.
#
# Plan 03-03 turns these green. The `Thermostatic` device is the AGGREGATABLE variant of
# the device contract (aggregator-as-writer, DEV-05): `contribute!` builds its own
# variables + temporal-coupling constraints on `ctx.model` and RETURNS
# `(; vars, p_inject, utility)` — it writes NOTHING to `ctx.residuals` and calls NO
# `add_to_objective!`. Every @testitem name contains "thermostatic" so
# `occursin("thermostatic", ti.name)` selects them.

@testitem "thermostatic: device type exists (DEV-01)" tags = [:thermostatic] begin
    using TSODSO

    # Recursion 3.2-3.3, comfort band, concave utility 3.11.
    @test isdefined(TSODSO, :Thermostatic)
    @test TSODSO.Thermostatic <: TSODSO.AbstractDevice
end

@testitem "thermostatic: rejects non-concave utility and inconsistent bounds (DEV-01)" tags = [
    :thermostatic,
] begin
    using TSODSO

    Tout = fill(30.0, 24)

    # A valid device is an AbstractDevice.
    d = TSODSO.Thermostatic(3, 0.2, 0.5, 20.0, 24.0, 22.0, 0.0, 5.0, 1.0, Tout)
    @test d isa TSODSO.AbstractDevice
    @test d isa TSODSO.Thermostatic{Float64}

    # Concavity guard (thesis 3.11/3.14): b ≤ 0 flips curvature → rejected loudly.
    @test_throws ArgumentError TSODSO.Thermostatic(3, 0.2, 0.5, 20.0, 24.0, 22.0, 0.0, 5.0, 0.0, Tout)
    @test_throws ArgumentError TSODSO.Thermostatic(3, 0.2, 0.5, 20.0, 24.0, 22.0, 0.0, 5.0, -1.0, Tout)

    # Comfort band inconsistency (Tmax < Tmin) rejected.
    @test_throws ArgumentError TSODSO.Thermostatic(3, 0.2, 0.5, 24.0, 20.0, 22.0, 0.0, 5.0, 1.0, Tout)

    # Power-bound inconsistency (Pmax < Pmin) rejected.
    @test_throws ArgumentError TSODSO.Thermostatic(3, 0.2, 0.5, 20.0, 24.0, 22.0, 5.0, 0.0, 1.0, Tout)

    # IN-01 promotion: a mixed-type call (integer among Float64s) promotes rather than MethodError.
    mixed = TSODSO.Thermostatic(3, 0, 0.5, 20.0, 24.0, 22.0, 0, 5.0, 1.0, Tout)
    @test mixed isa TSODSO.Thermostatic{Float64}
    @test mixed.Pmin === 0.0
end

@testitem "thermostatic: aggregatable contribute! returns terms, writes NOTHING, holds no feeder (DEV-01)" tags = [
    :thermostatic,
] begin
    using TSODSO, JuMP

    # A bare context: NO feeder anywhere — the device is network-agnostic.
    model = Model()
    ctx = TSODSO.ModelContext(model)
    @test !haskey(ctx.meta, :feeder)

    T = 4
    Tout = fill(30.0, T)
    Pmin, Pmax, Tmin, Tmax = 0.0, 5.0, 20.0, 24.0
    d = TSODSO.Thermostatic(3, 0.2, 0.5, Tmin, Tmax, 22.0, Pmin, Pmax, 1.0, Tout)

    out = TSODSO.contribute!(d, ctx; T = T)

    # AGGREGATABLE-DEVICE CONTRACT: returns (; vars, p_inject, utility).
    @test out isa NamedTuple
    @test haskey(out, :vars) && haskey(out, :p_inject) && haskey(out, :utility)

    # p_inject is length T and NEGATIVE-signed (a load draw = negative injection −p).
    @test length(out.p_inject) == T
    for t in 1:T
        @test out.p_inject[t] isa AffExpr
        @test all(c -> c < 0, values(out.p_inject[t].terms))
    end

    # utility is a concave QuadExpr (curvature −b/2 ≤ 0, thesis 3.11).
    @test out.utility isa QuadExpr
    @test !isempty(out.utility.terms)
    @test all(c -> c <= 0, values(out.utility.terms))

    # vars: bounded power p ∈ [Pmin,Pmax] and temperature Tin ∈ [Tmin,Tmax] (comfort band 3.3).
    @test length(out.vars.p) == T
    @test length(out.vars.Tin) == T
    for t in 1:T
        @test lower_bound(out.vars.p[t]) == Pmin && upper_bound(out.vars.p[t]) == Pmax
        @test lower_bound(out.vars.Tin[t]) == Tmin && upper_bound(out.vars.Tin[t]) == Tmax
    end

    # Temporal coupling: T-1 affine equality recursions (3.2) are present on the model.
    @test num_constraints(model, AffExpr, MOI.EqualTo{Float64}) == T - 1
    # State IC Tin[1] == Tin0 is a single-variable EqualTo constraint.
    @test num_constraints(model, VariableRef, MOI.EqualTo{Float64}) == 1

    # Aggregator-as-writer: the device wrote NOTHING to the residual or the objective.
    @test isempty(ctx.residuals)
    @test !haskey(ctx.meta, :objective)
end

@testitem "thermostatic: recursion 3.2 and IC hold at the solved optimum (DEV-01)" tags = [
    :thermostatic,
] begin
    using TSODSO, JuMP

    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx = TSODSO.ModelContext(model)

    T = 4
    α, β = 0.2, 0.5
    Tin0 = 22.0
    Tout = fill(30.0, T)
    d = TSODSO.Thermostatic(3, α, β, 20.0, 24.0, Tin0, 0.0, 5.0, 1.0, Tout)

    out = TSODSO.contribute!(d, ctx; T = T)
    # The device set NO objective; the assembly would — here we maximize its own utility.
    @objective(model, Max, out.utility)
    TSODSO.assert_solved!(model; dual = false)

    Tin, p = out.vars.Tin, out.vars.p
    # IC: Tin[1] == Tin0.
    @test isapprox(value(Tin[1]), Tin0; atol = 1e-6)
    # Recursion (3.2): Tin[t+1] == Tin[t] + α(Tout[t] − Tin[t]) − β·p[t].
    for t in 1:T-1
        expected = value(Tin[t]) + α * (Tout[t] - value(Tin[t])) - β * value(p[t])
        @test isapprox(value(Tin[t+1]), expected; atol = 1e-5)
    end
end

@testitem "thermostatic: contribute! validates the ambient profile length (DEV-01)" tags = [
    :thermostatic,
] begin
    using TSODSO, JuMP

    ctx = TSODSO.ModelContext(Model())
    # Tout shorter than the requested horizon → reject at contribute! (temporal infeasibility guard).
    d = TSODSO.Thermostatic(3, 0.2, 0.5, 20.0, 24.0, 22.0, 0.0, 5.0, 1.0, fill(30.0, 3))
    @test_throws ArgumentError TSODSO.contribute!(d, ctx; T = 8)
end
