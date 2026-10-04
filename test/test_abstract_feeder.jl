# Seam: AbstractFeeder supertype, formulation x feeder validity, formulation traits (ARCH-03/ARCH-07).
# Plan 33-02 appends ADMM-on-meshed assertions to this file.

@testitem "abstract feeder: both feeders subtype AbstractFeeder; constructors still gate" tags =
    [:feeder] begin
    using TSODSO

    radial = TSODSO.Feeder(
        [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)],
        [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0)],
        1,
    )
    @test radial isa TSODSO.AbstractFeeder{Float64}
    @test TSODSO.Feeder{Float64} <: TSODSO.AbstractFeeder{Float64}
    @test TSODSO.MeshedFeeder{Float64} <: TSODSO.AbstractFeeder{Float64}

    bus3 = [
        TSODSO.Bus(1, 0.95, 1.05, true),
        TSODSO.Bus(2, 0.95, 1.05, false),
        TSODSO.Bus(3, 0.95, 1.05, false),
    ]
    loop = [
        TSODSO.Branch(1, 2, 0.01, 0.02, 10.0),
        TSODSO.Branch(2, 3, 0.01, 0.02, 10.0),
        TSODSO.Branch(3, 1, 0.01, 0.02, 10.0),
    ]
    @test_throws ArgumentError TSODSO.Feeder(bus3, loop, 1)
    mesh = TSODSO.MeshedFeeder(bus3, loop, 1)
    @test mesh isa TSODSO.AbstractFeeder{Float64}
    # disconnected: bus 3 unreachable
    @test_throws ArgumentError TSODSO.MeshedFeeder(bus3, [TSODSO.Branch(1, 2, 0.01, 0.02, 10.0)], 1)
end

@testitem "abstract feeder: invalid formulation x MeshedFeeder pairs throw; valid pairs build" tags =
    [:feeder] begin
    using TSODSO, JuMP

    bus3 = [
        TSODSO.Bus(1, 0.95, 1.05, true),
        TSODSO.Bus(2, 0.95, 1.05, false),
        TSODSO.Bus(3, 0.95, 1.05, false),
    ]
    loop = [
        TSODSO.Branch(1, 2, 0.01, 0.02, 10.0),
        TSODSO.Branch(2, 3, 0.01, 0.02, 10.0),
        TSODSO.Branch(3, 1, 0.01, 0.02, 10.0),
    ]
    mesh = TSODSO.MeshedFeeder(bus3, loop, 1)
    radial = TSODSO.Feeder(bus3, loop[1:2], 1)

    freshctx() = TSODSO.ModelContext(Model())

    function check_throw(pf, name)
        err = try
            TSODSO.contribute!(pf, freshctx(), mesh; T = 1)
            nothing
        catch e
            e
        end
        return err isa ArgumentError &&
               occursin(name, err.msg) &&
               occursin("MeshedFeeder", err.msg)
    end
    @test_throws ArgumentError TSODSO.contribute!(TSODSO.RestrictedBranchFlow(0.0), freshctx(), mesh; T = 1)
    @test_throws ArgumentError TSODSO.contribute!(TSODSO.ConvexBranchFlow(), freshctx(), mesh; T = 1)
    @test_throws ArgumentError TSODSO.contribute!(TSODSO.LinDistFlow(), freshctx(), mesh; T = 1)
    @test check_throw(TSODSO.RestrictedBranchFlow(0.0), "RestrictedBranchFlow")
    @test check_throw(TSODSO.ConvexBranchFlow(), "ConvexBranchFlow")
    @test check_throw(TSODSO.LinDistFlow(), "LinDistFlow")

    # valid on meshed
    for pf in (TSODSO.DCPowerFlow(), TSODSO.ACPowerFlow(), TSODSO.MeshedFlow())
        @test TSODSO.contribute!(pf, freshctx(), mesh; T = 1) isa TSODSO.ModelContext
    end
    # valid on radial
    for pf in (
        TSODSO.MeshedFlow(),
        TSODSO.RestrictedBranchFlow(0.0),
        TSODSO.ConvexBranchFlow(),
        TSODSO.LinDistFlow(),
        TSODSO.DCPowerFlow(),
    )
        @test TSODSO.contribute!(pf, freshctx(), radial; T = 1) isa TSODSO.ModelContext
    end
end

@testitem "abstract feeder: has_reactive / has_branch_current truth tables" tags = [:feeder] begin
    using TSODSO, JuMP

    radial = TSODSO.Feeder(
        [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)],
        [TSODSO.Branch(1, 2, 0.01, 0.01, 10.0)],
        1,
    )
    table = [
        (TSODSO.ConvexBranchFlow(), true, true),
        (TSODSO.RestrictedBranchFlow(0.0), true, true),
        (TSODSO.MeshedFlow(), true, true),
        (TSODSO.ACPowerFlow(), true, true),
        (TSODSO.LinDistFlow(), true, false),
        (TSODSO.DCPowerFlow(), false, false),
    ]
    function check(pf, reactive, bc)
        ctx = TSODSO.contribute!(pf, TSODSO.ModelContext(Model()), radial; T = 1)
        return TSODSO.has_reactive(pf) == reactive &&
               TSODSO.has_reactive(pf) == haskey(ctx.residuals, :Rq) &&
               TSODSO.has_branch_current(pf) == bc
    end
    for (pf, r, b) in table
        @test check(pf, r, b)
    end
    @test TSODSO.has_branch_current(nothing) == false
end

@testitem "abstract feeder: radial-only ADMM entry points reject a MeshedFeeder" tags = [:feeder] begin
    using TSODSO

    function _check()
        bus3 = [
            TSODSO.Bus(1, 0.95, 1.05, true),
            TSODSO.Bus(2, 0.95, 1.05, false),
            TSODSO.Bus(3, 0.95, 1.05, false),
        ]
        loop = [
            TSODSO.Branch(1, 2, 0.01, 0.02, 10.0),
            TSODSO.Branch(2, 3, 0.01, 0.02, 10.0),
            TSODSO.Branch(3, 1, 0.01, 0.02, 10.0),
        ]
        mesh = TSODSO.MeshedFeeder(bus3, loop, 1)
        for (f, name) in ((TSODSO.solve_admm, "solve_admm"), (TSODSO.build_dso_opt, "build_dso_opt"))
            err = try
                f(mesh, TSODSO.ConvexBranchFlow(), TSODSO.Aggregator[]; T = 2)
                nothing
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin(name, err.msg) && occursin("MeshedFeeder", err.msg)
        end
        @test hasmethod(TSODSO.solve_admm, Tuple{TSODSO.Feeder,TSODSO.ConvexBranchFlow,Vector{TSODSO.Aggregator}})
        @test hasmethod(TSODSO.build_dso_opt, Tuple{TSODSO.Feeder,Vector{TSODSO.Aggregator},Int})
    end
    _check()
end
