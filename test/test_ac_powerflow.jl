# Seam: powerflow/ACPowerFlow.jl (EXACT-01). Independent nonconvex AC-OPF peer formulation.
#
# RED test-item harness (Wave 0). Plan 15-01 Task 2 turns these green by defining
# `ACPowerFlow <: AbstractPowerFlow` (the DistFlow branch-flow physics UNRELAXED: the true
# nonconvex equality `l·v = P²+Q²` instead of the rotated-SOC inequality, and no LinDistFlow
# exactness copy) and `problem_class(::ACPowerFlow) = NLP()`. Every item name contains
# "ac_powerflow" so `occursin("ac_powerflow", ti.name)` selects it. While RED the sole failing
# assertion is a missing-symbol `isdefined` check (never a runner crash); the behavioral
# asserts sit behind an `isdefined` guard so they go live automatically once 15-01 Task 2 lands.

@testitem "ac_powerflow: ACPowerFlow is a defined AbstractPowerFlow subtype (EXACT-01)" tags =
    [:ac_powerflow] begin
    using TSODSO

    # RED until plan 15-01 Task 2 defines the AC-OPF peer formulation.
    @test isdefined(TSODSO, :ACPowerFlow)

    if isdefined(TSODSO, :ACPowerFlow)
        @test TSODSO.ACPowerFlow() isa TSODSO.AbstractPowerFlow
    end
end

@testitem "ac_powerflow: ACPowerFlow routes to the NLP problem class (EXACT-01 / INFRA-02)" tags =
    [:ac_powerflow] begin
    using TSODSO

    # The generic trait returns QP() for DC/LinDistFlow (plan 04-01); ConvexBranchFlow adds
    # SOCP() (plan 04-02). Plan 15-01 adds the more-specific `problem_class(::ACPowerFlow) =
    # NLP()` so the true nonconvex equality cone routes to the Ipopt factory.
    @test isdefined(TSODSO, :ACPowerFlow)

    if isdefined(TSODSO, :ACPowerFlow)
        @test TSODSO.problem_class(TSODSO.ACPowerFlow()) isa TSODSO.NLP
    end
end

@testitem "ac_powerflow: contribute! stashes pf_vars WITHOUT the exactness copy v̂ (EXACT-01)" tags =
    [:ac_powerflow] begin
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
        @test ctx.pf_vars !== nothing
        pv = ctx.pf_vars
        @test keys(pv) == (:v, :P, :Q, :l)

        # AC branch flow is reactive-capable: it must populate BOTH :Rp and :Rq (like the SOCP
        # and LinDistFlow formulations).
        @test haskey(ctx.residuals, :Rp)
        @test haskey(ctx.residuals, :Rq)
    end
end

# PM-07 (26-15): PV back-feed fixture mirroring test_convex_branch_flow.jl's own FIX-03
# regression (26-05) — but on ACPowerFlow's UNRELAXED nonconvex formulation, solved by Ipopt
# rather than Clarabel. Under reverse flow (P < 0), the receiving-end power (P−r·l, Q−x·l) has
# LARGER magnitude than the sending-end power (P,Q) because the loss term `−r·l` REINFORCES
# rather than cancels the already-negative P (26-RESEARCH.md), so a branch limit sized to just
# admit the forward magnitude can still be violated on the receiving end under back-feed. The
# SAME `r=0.03, x=0.02, smax=0.3976601762564117` fixture Plan 26-05 validated is reused here —
# ACPowerFlow shares the identical branch-flow physics (just unrelaxed), so the same fixture
# drives the same qualitative binding/slack asymmetry. Since Ipopt (not a conic solver) is the
# backend, the raw dual MAGNITUDES differ from Plan 26-05's SOCP test; only the QUALITATIVE
# ratio (receiving-end dual dominates sending-end dual) is asserted, per the plan's own
# guidance.
@testitem "ac_powerflow: PV back-feed binds the receiving-end limit (:smax_rev) while the sending-end limit (:smax) stays slack (PM-07)" tags =
    [:ac_powerflow] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    r, x, smax = 0.03, 0.02, 0.3976601762564117
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.90, 1.05, false)],
        [Branch(1, 2, r, x, smax)],
        1,
    )

    model = Model(TSODSO.select_optimizer(TSODSO.NLP()))
    ctx = TSODSO.ModelContext(model)
    TSODSO.contribute!(TSODSO.ACPowerFlow(), ctx, feeder; T = 1)
    pv = ctx.pf_vars

    # Near-unity power factor (φ ≈ 0.999999), the same real-power back-feed isolation Plan
    # 26-05's ConvexBranchFlow test uses.
    φ = 0.999999
    tanφ = sqrt(1 - φ^2) / φ
    @constraint(model, pv.Q[1, 1] == pv.P[1, 1] * tanφ)

    # Warm start (Rule 3, blocking-issue auto-fix): Ipopt's default all-zero start sits at a
    # DEGENERATE KKT point of the `l·v = P²+Q²` equality (thesis 3.39 unrelaxed) — the
    # constraint's gradient in (P,Q) vanishes at P=Q=0, so the interior-point method reports
    # ALMOST_LOCALLY_SOLVED / NEARLY_FEASIBLE_POINT at the trivial P≈0 solution instead of
    # escaping toward the true back-feed optimum. A back-feed-directed starting point (nonzero
    # negative P, consistent Q/l/v) is a standard Ipopt remedy for a nonconvex equality with a
    # degenerate zero stationary point — NOT a change to the model's feasible set or physics.
    set_start_value(pv.P[1, 1], -0.3)
    set_start_value(pv.Q[1, 1], -0.3 * tanφ)
    set_start_value(pv.l[1, 1], 0.3^2)
    set_start_value(pv.v[1, 1], 1.0)
    set_start_value(pv.v[2, 1], 0.9)

    # Elastic PV/Aggregator idiom: maximize the export `−P` subject to BOTH apparent-power
    # limits (:smax forward, :smax_rev reverse) and the existing voltage/current bounds
    # ACPowerFlow already builds.
    @objective(model, Max, -pv.P[1, 1])
    optimize!(model)
    @test is_solved_and_feasible(model)

    # A scalar-quadratic inequality's dual is a plain scalar (not a vector, unlike the
    # SecondOrderCone dual in ConvexBranchFlow's peer test) — abs(...) gives the magnitude.
    mag_fwd = abs(dual(ctx.constraints[:smax][1, 1]))
    mag_rev = abs(dual(ctx.constraints[:smax_rev][1, 1]))
    @info "ACPowerFlow PV back-feed limit duals" mag_fwd mag_rev value(pv.P[1, 1]) value(
        pv.l[1, 1],
    )

    @test mag_rev > 100 * mag_fwd   # receiving-end limit dominates; sending-end stays slack
end
