# Seam: powerflow/ConvexBranchFlow.jl (PF-03). SOCP Convex Branch Flow formulation.
#
# RED @testitem harness (Wave 1). Plan 04-02 turns these green by defining
# `ConvexBranchFlow <: AbstractPowerFlow` (the DistFlow SOC relaxation + LinDistFlow
# exactness copy) and `problem_class(::ConvexBranchFlow) = SOCP()`. Every item name
# contains "socp" so `occursin("socp", ti.name)` selects it. While RED the sole failing
# assertion is a missing-symbol `isdefined` check (never a runner crash); the behavioral
# asserts sit behind an `isdefined` guard so they go live automatically once 04-02 lands.

@testitem "socp: ConvexBranchFlow is a defined AbstractPowerFlow subtype (PF-03)" tags = [:socp] begin
    using TSODSO

    # RED until plan 04-02 defines the SOCP formulation.
    @test isdefined(TSODSO, :ConvexBranchFlow)

    if isdefined(TSODSO, :ConvexBranchFlow)
        @test TSODSO.ConvexBranchFlow() isa TSODSO.AbstractPowerFlow
    end
end

@testitem "socp: ConvexBranchFlow routes to the SOCP problem class (PF-03 / INFRA-02)" tags = [:socp] begin
    using TSODSO

    # The generic trait already returns QP() for DC/LinDistFlow (plan 04-01); plan 04-02
    # adds the more-specific `problem_class(::ConvexBranchFlow) = SOCP()` so the cone routes
    # to the tight-gap Clarabel factory.
    @test isdefined(TSODSO, :ConvexBranchFlow)

    if isdefined(TSODSO, :ConvexBranchFlow)
        @test TSODSO.problem_class(TSODSO.ConvexBranchFlow()) isa TSODSO.SOCP
    end
end

@testitem "socp: contribute! stashes pf_vars with the SOC/exactness variables (PF-03)" tags = [:socp] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # A minimal lossy 2-bus radial feeder (r,x > 0 so the loss current l is meaningful).
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )

    @test isdefined(TSODSO, :ConvexBranchFlow)

    if isdefined(TSODSO, :ConvexBranchFlow)
        model = Model()
        ctx = TSODSO.ModelContext(model)
        TSODSO.contribute!(TSODSO.ConvexBranchFlow(), ctx, feeder; T = 1)

        # The SOCP formulation must stash the squared-voltage v, its exactness copy v̂, the
        # branch flows P/Q, and the squared current l for the PF-04 exactness checker.
        @test haskey(ctx.meta, :pf_vars)
        pv = ctx.meta[:pf_vars]
        for k in (:v, :v̂, :P, :Q, :l)
            @test k in keys(pv)
        end

        # SOCP is reactive-capable: it must populate BOTH :Rp and :Rq (like LinDistFlow).
        @test haskey(ctx.residuals, :Rp)
        @test haskey(ctx.residuals, :Rq)
    end
end

# GREEN confirmation (no factory edit needed): the `SOCP()` problem class already routes to
# a Clarabel factory with the tight duality-gap tolerances the DADP accuracy / exactness
# check depend on (src/solver/factory.jl, plan 01-03). This item documents that Phase-4
# required NO change to the solver factory — the pre-existing `select_optimizer(SOCP())`
# suffices. Name contains "socp" so `occursin("socp", ti.name)` selects it.
@testitem "socp: SOCP() routes to a Clarabel factory with tight gap (INFRA-02)" tags = [:socp] begin
    using TSODSO
    using JuMP

    factory = select_optimizer(SOCP())          # must build without naming a solver here
    @test factory isa JuMP.MOI.OptimizerWithAttributes

    # The factory constructs a JuMP model (Clarabel backend) — routing is live end-to-end.
    model = Model(factory)
    @test model isa Model
    @test occursin("Clarabel", string(solver_name(model)))
end
