# Seam: powerflow/ACPowerFlow.jl (EXACT-01). Independent nonconvex AC-OPF peer formulation.
#
# RED test-item harness (Wave 0). Plan 15-01 Task 2 turns these green by defining
# `ACPowerFlow <: AbstractPowerFlow` (the DistFlow branch-flow physics UNRELAXED: the true
# nonconvex equality `l·v = P²+Q²` instead of the rotated-SOC inequality, and no LinDistFlow
# exactness copy) and `problem_class(::ACPowerFlow) = NLP()`. Every item name contains
# "ac_powerflow" so `occursin("ac_powerflow", ti.name)` selects it. While RED the sole failing
# assertion is a missing-symbol `isdefined` check (never a runner crash); the behavioral
# asserts sit behind an `isdefined` guard so they go live automatically once 15-01 Task 2 lands.

@testitem "ac_powerflow: ACPowerFlow is a defined AbstractPowerFlow subtype (EXACT-01)" tags = [:ac_powerflow] begin
    using TSODSO

    # RED until plan 15-01 Task 2 defines the AC-OPF peer formulation.
    @test isdefined(TSODSO, :ACPowerFlow)

    if isdefined(TSODSO, :ACPowerFlow)
        @test TSODSO.ACPowerFlow() isa TSODSO.AbstractPowerFlow
    end
end

@testitem "ac_powerflow: ACPowerFlow routes to the NLP problem class (EXACT-01 / INFRA-02)" tags = [:ac_powerflow] begin
    using TSODSO

    # The generic trait returns QP() for DC/LinDistFlow (plan 04-01); ConvexBranchFlow adds
    # SOCP() (plan 04-02). Plan 15-01 adds the more-specific `problem_class(::ACPowerFlow) =
    # NLP()` so the true nonconvex equality cone routes to the Ipopt factory.
    @test isdefined(TSODSO, :ACPowerFlow)

    if isdefined(TSODSO, :ACPowerFlow)
        @test TSODSO.problem_class(TSODSO.ACPowerFlow()) isa TSODSO.NLP
    end
end

@testitem "ac_powerflow: contribute! stashes pf_vars WITHOUT the exactness copy v̂ (EXACT-01)" tags = [:ac_powerflow] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # A minimal lossy 2-bus radial feeder (r,x > 0 so the loss current l is meaningful).
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )

    @test isdefined(TSODSO, :ACPowerFlow)

    if isdefined(TSODSO, :ACPowerFlow)
        model = Model()
        ctx = TSODSO.ModelContext(model)
        TSODSO.contribute!(TSODSO.ACPowerFlow(), ctx, feeder; T = 1)

        # The AC peer stashes ONLY the true physical variables — the squared voltage v, the
        # branch flows P/Q, and the squared current l. There is NO exactness-copy v̂ (the
        # load-bearing difference from ConvexBranchFlow's own stash, which carries :v̂): the
        # copy exists solely to force the SOC relaxation tight, and this formulation is not a
        # relaxation.
        @test haskey(ctx.meta, :pf_vars)
        pv = ctx.meta[:pf_vars]
        @test keys(pv) == (:v, :P, :Q, :l)

        # AC branch flow is reactive-capable: it must populate BOTH :Rp and :Rq (like the SOCP
        # and LinDistFlow formulations).
        @test haskey(ctx.residuals, :Rp)
        @test haskey(ctx.residuals, :Rq)
    end
end
