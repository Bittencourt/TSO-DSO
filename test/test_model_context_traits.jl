# Seam: typed ModelContext fill by the six formulations + trait agreement (ARCH-07).

@testitem "model context: ctx.pf records the real formulation for all six" tags = [:context] begin
    using TSODSO, JuMP

    feeder = TSODSO.Feeder(
        [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)],
        [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0)],
        1,
    )
    pfs = (
        TSODSO.DCPowerFlow(),
        TSODSO.LinDistFlow(),
        TSODSO.ConvexBranchFlow(),
        TSODSO.RestrictedBranchFlow(0.0),
        TSODSO.MeshedFlow(),
        TSODSO.ACPowerFlow(),
    )
    function run_all(pfs, feeder)
        out = Any[]
        for pf in pfs
            ctx = TSODSO.ModelContext(Model())
            TSODSO.contribute!(pf, ctx, feeder; T = 1)
            push!(out, (pf, ctx))
        end
        return out
    end
    for (pf, ctx) in run_all(pfs, feeder)
        @test typeof(ctx.pf) == typeof(pf)
    end
end

@testitem "model context: traits agree with pf_vars and residuals" tags = [:context] begin
    using TSODSO, JuMP

    feeder = TSODSO.Feeder(
        [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)],
        [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0)],
        1,
    )
    pfs = (
        TSODSO.DCPowerFlow(),
        TSODSO.LinDistFlow(),
        TSODSO.ConvexBranchFlow(),
        TSODSO.RestrictedBranchFlow(0.0),
        TSODSO.MeshedFlow(),
        TSODSO.ACPowerFlow(),
    )
    function check(pf, feeder)
        ctx = TSODSO.ModelContext(Model())
        TSODSO.contribute!(pf, ctx, feeder; T = 1)
        bc = TSODSO.has_branch_current(pf) == (ctx.pf_vars !== nothing && haskey(ctx.pf_vars, :l))
        rq = TSODSO.has_reactive(pf) == haskey(ctx.residuals, :Rq)
        dc = pf isa TSODSO.DCPowerFlow ? ctx.pf_vars === nothing : ctx.pf_vars !== nothing
        return bc, rq, dc
    end
    for pf in pfs
        bc, rq, dc = check(pf, feeder)
        @test bc
        @test rq
        @test dc
    end
    @test TSODSO.has_branch_current(TSODSO.ACPowerFlow())
end

@testitem "model context: fresh ctx trait and aggregator typed fill" tags = [:context] begin
    using TSODSO, JuMP

    ctx0 = TSODSO.ModelContext(Model())
    @test !TSODSO.has_branch_current(ctx0.pf)

    T = 3
    bus = 2
    Tout = fill(25.0, T)
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, Tout)
    agg = Aggregator(bus, 0.9, [therm], fill(0.3, T))
    ctx = ModelContext(Model())
    res = contribute!(agg, ctx; T = T)
    @test haskey(ctx.agg_device_vars, bus)
    @test ctx.agg_device_vars[bus] == res.vars
    @test !(isempty(ctx.objective.terms) && iszero(ctx.objective.aff))
end
