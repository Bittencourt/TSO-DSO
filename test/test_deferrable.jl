# Seam: devices/Deferrable.jl (DEV-02). Deferrable (shiftable) flexible load.
#
# Plan 03-03 turns these green. The `Deferrable` device is the AGGREGATABLE variant of
# the device contract (aggregator-as-writer, DEV-05): `contribute!` builds its own
# per-hour power variables + the energy-within-window budget constraint on `ctx.model`
# and RETURNS `(; vars, p_inject, utility)` — it writes NOTHING to `ctx.residuals` and
# calls NO `add_to_objective!`. Every @testitem name contains "deferrable" so
# `occursin("deferrable", ti.name)` selects them.

@testitem "deferrable: device type exists (DEV-02)" tags = [:deferrable] begin
    using TSODSO

    # Energy-window coupling 3.4-3.5, concave utility 3.12.
    @test isdefined(TSODSO, :Deferrable)
    @test TSODSO.Deferrable <: TSODSO.AbstractDevice
end

@testitem "deferrable: rejects non-concave utility and infeasible/inconsistent window (DEV-02)" tags = [
    :deferrable,
] begin
    using TSODSO

    # A valid device (window t=2..4, budget E=6 ≤ Pmax·3 = 15) is an AbstractDevice.
    d = TSODSO.Deferrable(3, 2, 4, 6.0, 5.0, 1.0)
    @test d isa TSODSO.AbstractDevice
    @test d isa TSODSO.Deferrable{Float64}

    # Concavity guard (thesis 3.12): b ≤ 0 rejected loudly.
    @test_throws ArgumentError TSODSO.Deferrable(3, 2, 4, 6.0, 5.0, 0.0)
    @test_throws ArgumentError TSODSO.Deferrable(3, 2, 4, 6.0, 5.0, -1.0)

    # Inconsistent window (t_start > t_end) rejected.
    @test_throws ArgumentError TSODSO.Deferrable(3, 4, 2, 6.0, 5.0, 1.0)
    # Window start before the first hour rejected.
    @test_throws ArgumentError TSODSO.Deferrable(3, 0, 4, 6.0, 5.0, 1.0)

    # Infeasible energy budget: E cannot fit the window at Pmax (E=20 > 5·3 = 15).
    @test_throws ArgumentError TSODSO.Deferrable(3, 2, 4, 20.0, 5.0, 1.0)
    # Negative budget rejected.
    @test_throws ArgumentError TSODSO.Deferrable(3, 2, 4, -1.0, 5.0, 1.0)

    # IN-01 promotion: a mixed-type call (integer budget among Float64s) promotes.
    mixed = TSODSO.Deferrable(3, 2, 4, 6, 5.0, 1.0)
    @test mixed isa TSODSO.Deferrable{Float64}
    @test mixed.E === 6.0
end

@testitem "deferrable: aggregatable contribute! returns terms, writes NOTHING, holds no feeder (DEV-02)" tags = [
    :deferrable,
] begin
    using TSODSO, JuMP

    # A bare context: NO feeder anywhere — the device is network-agnostic.
    model = Model()
    ctx = TSODSO.ModelContext(model)
    @test !haskey(ctx.meta, :feeder)

    T = 5
    t_start, t_end, E, Pmax = 2, 4, 6.0, 5.0
    d = TSODSO.Deferrable(3, t_start, t_end, E, Pmax, 1.0)

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

    # utility is a concave QuadExpr (thesis 3.12).
    @test out.utility isa QuadExpr
    @test !isempty(out.utility.terms)
    @test all(c -> c <= 0, values(out.utility.terms))

    # vars: per-hour power p, length T. Inside window p ∈ [0,Pmax]; outside window pinned to 0.
    @test length(out.vars.p) == T
    for t in 1:T
        @test lower_bound(out.vars.p[t]) == 0.0
        if t_start <= t <= t_end
            @test upper_bound(out.vars.p[t]) == Pmax
        else
            @test upper_bound(out.vars.p[t]) == 0.0
        end
    end

    # Energy-window budget (3.4-3.5): exactly one equality constraint beyond bounds.
    n_eq =
        num_constraints(model, AffExpr, MOI.EqualTo{Float64}) +
        num_constraints(model, VariableRef, MOI.EqualTo{Float64})
    @test n_eq == 1

    # Aggregator-as-writer: the device wrote NOTHING to the residual or the objective.
    @test isempty(ctx.residuals)
    @test !haskey(ctx.meta, :objective)
end

@testitem "deferrable: energy-window budget 3.4 binds at the solved optimum (DEV-02)" tags = [
    :deferrable,
] begin
    using TSODSO, JuMP

    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx = TSODSO.ModelContext(model)

    T = 5
    t_start, t_end, E, Pmax = 2, 4, 6.0, 5.0
    d = TSODSO.Deferrable(3, t_start, t_end, E, Pmax, 1.0)

    out = TSODSO.contribute!(d, ctx; T = T)
    @objective(model, Max, out.utility)
    TSODSO.assert_solved!(model; dual = false)

    p = out.vars.p
    # Energy budget (3.4): Σ over the window == E.
    @test isapprox(sum(value(p[t]) for t in t_start:t_end), E; atol = 1e-5)
    # Outside the window: zero draw (3.5, p = 0 outside T_{h,d}).
    @test isapprox(value(p[1]), 0.0; atol = 1e-6)
    @test isapprox(value(p[T]), 0.0; atol = 1e-6)
end

@testitem "deferrable: contribute! validates the window fits the horizon (DEV-02)" tags = [
    :deferrable,
] begin
    using TSODSO, JuMP

    ctx = TSODSO.ModelContext(Model())
    # Window end beyond the requested horizon → reject at contribute!.
    d = TSODSO.Deferrable(3, 2, 6, 6.0, 5.0, 1.0)
    @test_throws ArgumentError TSODSO.contribute!(d, ctx; T = 4)
end
