# Seam: powerflow/ConvexBranchFlow.jl (PF-03). SOCP Convex Branch Flow formulation.
#
# RED @testitem harness (Wave 1). Plan 04-02 turns these green by defining
# `ConvexBranchFlow <: AbstractPowerFlow` (the DistFlow SOC relaxation + LinDistFlow
# exactness copy) and `problem_class(::ConvexBranchFlow) = SOCP()`. Every item name
# contains "socp" so `occursin("socp", ti.name)` selects it. While RED the sole failing
# assertion is a missing-symbol `isdefined` check (never a runner crash); the behavioral
# asserts sit behind an `isdefined` guard so they go live automatically once 04-02 lands.

@testitem "socp: ConvexBranchFlow is a defined AbstractPowerFlow subtype (PF-03)" tags =
    [:socp] begin
    using TSODSO

    # RED until plan 04-02 defines the SOCP formulation.
    @test isdefined(TSODSO, :ConvexBranchFlow)

    if isdefined(TSODSO, :ConvexBranchFlow)
        @test TSODSO.ConvexBranchFlow() isa TSODSO.AbstractPowerFlow
    end
end

@testitem "socp: ConvexBranchFlow routes to the SOCP problem class (PF-03 / INFRA-02)" tags =
    [:socp] begin
    using TSODSO

    # The generic trait already returns QP() for DC/LinDistFlow (plan 04-01); plan 04-02
    # adds the more-specific `problem_class(::ConvexBranchFlow) = SOCP()` so the cone routes
    # to the tight-gap Clarabel factory.
    @test isdefined(TSODSO, :ConvexBranchFlow)

    if isdefined(TSODSO, :ConvexBranchFlow)
        @test TSODSO.problem_class(TSODSO.ConvexBranchFlow()) isa TSODSO.SOCP
    end
end

@testitem "socp: contribute! stashes pf_vars with the SOC/exactness variables (PF-03)" tags =
    [:socp] begin
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
        @test ctx.pf_vars !== nothing
        pv = ctx.pf_vars
        for k in (:v, :v̂, :P, :Q, :l)
            @test k in keys(pv)
        end

        # SOCP is reactive-capable: it must populate BOTH :Rp and :Rq (like LinDistFlow).
        @test haskey(ctx.residuals, :Rp)
        @test haskey(ctx.residuals, :Rq)
    end
end

# FIX-01/02 (phase 26-02): ConvexBranchFlow()'s DEFAULT (thesis_literal=false) exactness copy
# must satisfy v̂ ≥ v (the Gan-Low direction) at the solution.
@testitem "socp: default ConvexBranchFlow() satisfies v̂ ≥ v (FIX-01/02)" tags = [:socp] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )

    model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
    ctx = TSODSO.ModelContext(model)
    TSODSO.contribute!(TSODSO.ConvexBranchFlow(), ctx, feeder; T = 2)
    pv = ctx.pf_vars

    fix.(pv.P[1, :], 0.3; force = true)
    fix.(pv.Q[1, :], 0.1; force = true)
    @objective(model, Min, 0.0)
    optimize!(model)
    @test is_solved_and_feasible(model)

    N = length(feeder.buses)
    mingap = minimum(value(pv.v̂[j, t]) - value(pv.v[j, t]) for j in 1:N, t in 1:2)
    @info "v̂-v min gap (default ConvexBranchFlow)" mingap
    @test mingap >= -1e-9   # v̂ ≥ v everywhere (Gan-Low direction)
end

# FIX-02 load-bearing/redundant bound check: under the CORRECTED direction, `v̂ ≤ V²max` is
# the LOAD-BEARING (exactness-driving) bound and `v ≤ V²max` is redundant (implied by
# `v ≤ v̂ ≤ V²max`) — matching ConvexBranchFlow's corrected docstring claim. Demonstrated by
# maximizing the squared branch current `l` (which increases `v̂` TWICE as fast as `v` per
# unit `l`, since both start from the SAME root value and `v̂`'s copy-drop coefficient on `l`
# is `2(r²+x²)` vs `v`'s true-drop coefficient `(r²+x²)`): the solve must hit `v̂`'s own
# upper bound strictly BEFORE `v`'s, leaving `v`'s bound slack.
@testitem "socp: default ConvexBranchFlow() has v̂ ≤ V²max load-bearing, v ≤ V²max redundant (FIX-02)" tags =
    [:socp] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )

    model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
    ctx = TSODSO.ModelContext(model)
    TSODSO.contribute!(TSODSO.ConvexBranchFlow(), ctx, feeder; T = 1)
    pv = ctx.pf_vars

    fix.(pv.P[1, :], 0.05; force = true)
    fix.(pv.Q[1, :], 0.02; force = true)
    @objective(model, Max, pv.l[1, 1])   # push l up until a bus-voltage bound binds
    optimize!(model)
    @test is_solved_and_feasible(model)

    vmax2 = feeder.buses[2].vmax^2
    v2 = value(pv.v[2, 1])
    v̂2 = value(pv.v̂[2, 1])
    @info "load-bearing check" v2 v̂2 vmax2

    @test isapprox(v̂2, vmax2; atol = 1e-6)   # v̂ ≤ V²max binds (load-bearing)
    @test v2 < vmax2 - 1e-3                  # v ≤ V²max is SLACK (redundant)
end

# GREEN confirmation (no factory edit needed): the `SOCP()` problem class already routes to
# a Clarabel factory with the tight duality-gap tolerances the DADP accuracy / exactness
# check depend on (src/solver/factory.jl, plan 01-03). This item documents that Phase-4
# required NO change to the solver factory — the pre-existing `select_optimizer(SOCP())`
# suffices. Name contains "socp" so `occursin("socp", ti.name)` selects it.
@testitem "socp: SOCP() routes to a Clarabel factory with tight gap (INFRA-02)" tags =
    [:socp] begin
    using TSODSO
    using JuMP

    factory = select_optimizer(SOCP())          # must build without naming a solver here
    @test factory isa JuMP.MOI.OptimizerWithAttributes

    # The factory constructs a JuMP model (Clarabel backend) — routing is live end-to-end.
    model = Model(factory)
    @test model isa Model
    @test occursin("Clarabel", string(solver_name(model)))
end

# PRICE-02 (05-01): the four branch-flow constraint duals the DLMP decomposition consumes
# (voltage-drop 3.33, copy-drop 3.43, rotated cone 3.39, apparent-power limit 3.36) must be
# recoverable BY NAME from a solved ctx. This item builds `contribute!` on a lossy radial
# feeder and asserts each handle is registered under ctx.constraints. The `:smax` container is
# BRANCH-INDEXED (keyed by branch index b, time t) with the SAME `smax < _SMAX_NO_LIMIT` filter
# as before, so only genuinely-limited branches carry a cone (feasible set byte-identical).
@testitem "socp: contribute! registers the branch-flow duals for DLMP (:vdrop/:cpydrop/:cone/:smax) (PRICE-02)" tags =
    [:socp] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # A 3-bus radial feeder: branch 1 carries a genuine apparent-power limit (smax=0.05, so
    # `smax < _SMAX_NO_LIMIT`) so the `:smax` container is non-empty; branch 2 is at the
    # no-limit sentinel so it gets NO apparent-power cone (byte-identical to the prior loop).
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false), Bus(3, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 0.05), Branch(2, 3, 0.01, 0.02, TSODSO._SMAX_NO_LIMIT)],
        1,
    )

    @test isdefined(TSODSO, :ConvexBranchFlow)

    if isdefined(TSODSO, :ConvexBranchFlow)
        model = Model()
        ctx = TSODSO.ModelContext(model)
        TSODSO.contribute!(TSODSO.ConvexBranchFlow(), ctx, feeder; T = 2)

        for k in (:vdrop, :cpydrop, :cone, :smax)
            @test haskey(ctx.constraints, k)
        end

        # `:smax` is a sparse branch-indexed container: only the genuinely-limited branch 1
        # has entries (branch 2 is at the sentinel), keyed by (branch index, t).
        smax = ctx.constraints[:smax]
        @test length(smax) == 2                    # branch 1 at t=1,2 only
        @test haskey(smax.data, (1, 1))
        @test haskey(smax.data, (1, 2))
        @test !haskey(smax.data, (2, 1))           # sentinel branch gets NO apparent-power cone
    end
end

# FIX-03 (26-05): PV back-feed fixture — the receiving-end apparent-power cone (:smax_rev,
# thesis 3.37) must bind while the sending-end cone (:smax, thesis 3.36) stays slack. Under
# reverse flow (P < 0, power flowing from the load bus back toward the root), the
# receiving-end power (P−r·l, Q−x·l) has LARGER magnitude than the sending-end power (P,Q)
# because the loss term `−r·l` REINFORCES (adds to) rather than cancels the already-negative
# P — i.e. `|P − r·l| = |P| + r·l > |P|` when `P < 0` and `l ≥ 0` — so a branch limit sized to
# just admit the forward magnitude can still be violated on the receiving end under back-feed
# (26-RESEARCH.md). Exercises ConvexBranchFlow's OWN registered `:smax`/`:smax_rev` constraint
# containers directly (mirrors this file's existing direct-fix/direct-objective @testitem
# convention above, e.g. the FIX-01/02 items), maximizing the export `−P[1,1]` at near-unity
# power factor — the elastic PV/Aggregator idiom (an unconstrained-by-price generator that
# wants to export as much as the network allows) an independent standalone raw-JuMP replica
# of this exact fixture (this plan's own `<verify>` script) validates the fixture's `smax`
# choice against.
@testitem "socp: PV back-feed binds the receiving-end cone (:smax_rev) while the sending-end cone (:smax) stays slack (FIX-03)" tags =
    [:socp] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # 2-bus radial feeder; `smax` sits strictly between the natural forward apparent-power
    # magnitude (~0.393) and the natural reverse magnitude (~0.400) at the chosen export
    # level (validated fixture; see 26-05-PLAN.md Task 2's independent derivation).
    r, x, smax = 0.03, 0.02, 0.3976601762564117
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.90, 1.05, false)],
        [Branch(1, 2, r, x, smax)],
        1,
    )

    model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
    ctx = TSODSO.ModelContext(model)
    TSODSO.contribute!(TSODSO.ConvexBranchFlow(), ctx, feeder; T = 1)
    pv = ctx.pf_vars

    # Near-unity power factor (φ ≈ 0.999999) isolates the real-power back-feed mechanism:
    # Q tracks P via the same tanφ throughout.
    φ = 0.999999
    tanφ = sqrt(1 - φ^2) / φ
    @constraint(model, pv.Q[1, 1] == pv.P[1, 1] * tanφ)

    # Elastic PV/Aggregator idiom: maximize the export `−P` (a generator that wants to
    # export as much as the network allows) subject to BOTH apparent-power cones (:smax
    # forward, :smax_rev reverse) and the existing voltage/current bounds ConvexBranchFlow
    # already builds — no artificial upper bound on the export itself.
    @objective(model, Max, -pv.P[1, 1])
    optimize!(model)
    @test is_solved_and_feasible(model)

    d_fwd = dual(ctx.constraints[:smax][1, 1])
    d_rev = dual(ctx.constraints[:smax_rev][1, 1])
    mag_fwd = sqrt(sum(abs2, d_fwd))
    mag_rev = sqrt(sum(abs2, d_rev))
    @info "PV back-feed cone duals" mag_fwd mag_rev value(pv.P[1, 1]) value(pv.l[1, 1])

    @test mag_rev > 1e-3            # receiving-end cone BINDS under back-feed
    @test mag_fwd < 1e-6            # sending-end cone stays SLACK
    @test mag_rev > 100 * mag_fwd   # materially larger, not just numerically nonzero
end
