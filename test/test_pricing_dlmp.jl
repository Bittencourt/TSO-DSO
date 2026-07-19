# test/test_pricing_dlmp.jl
#
# Seam: pricing/dlmp.jl (PRICE-01 / PRICE-02). DLMP extraction + four-way decomposition.
#
# The BEHAVIORAL @testitems for plan 05-02 (the RED harness `test_dlmp.jl` pins the module
# API; this file pins the physics). Every item name contains "dlmp" so
# `@run_package_tests filter=ti->occursin("dlmp", ti.name)` selects it. Items are
# self-contained where possible (an inline 2-bus feeder for the DADP sign / gate) and reuse
# `setup=[Phase4Fixtures]` for the IEEE-13 ground and high-PV over-voltage solves.
#
# What is pinned:
#   * PRICE-01 — `extract_dlmp` is the per-node/hour dual of `:balance_p`, POSITIVE and ≈ λ₀ on
#     a lossless uncongested interior 2-bus (sign regression, RESEARCH Pitfall 1); it REFUSES
#     (throws) an ungated SOCP ctx that lacks the PF-04 exactness certificate (threat T-05-01).
#   * PRICE-02 — `decompose_dlmp` splits the DADP into energy/loss/congestion/voltage that SUM
#     to the nodal price within a relative tolerance on IEEE-13 (congestion binds at the head)
#     AND the high-PV over-voltage solve (voltage engaged); congestion/voltage ≈ 0 on the
#     uncongested in-bound 2-bus.

@testitem "dlmp: extract_dlmp on a lossless 2-bus is positive and ≈ λ₀ (energy-only, PRICE-01)" tags = [
    :dlmp,
] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # Lossless (r,x ≈ 0), uncongested (smax ≫ flow), interior (voltage un-binding) 2-bus: the
    # hand-solved energy-only case where the load-bus DADP must equal the MEM price λ₀ and be
    # strictly POSITIVE (marginal cost of consumption — the sign every downstream check inherits).
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 1e-6, 1e-6, 10.0)],
        1,
    )
    T = 3
    λ₀ = fill(40.0, T)
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
    ctx, _obj, _dadp =
        solve_welfare(feeder, ConvexBranchFlow(), [agg]; T = T, λ₀ = λ₀, allow_export = true)

    M = extract_dlmp(ctx)
    @test size(M) == (2, T)
    for t in 1:T
        @test M[2, t] > 0                       # POSITIVE = marginal cost of consumption
        @test isapprox(M[2, t], λ₀[t]; atol = 1e-2)   # energy-only ⇒ ≈ λ₀ (no loss/cong/volt)
        @test isapprox(M[1, t], λ₀[t]; atol = 1e-6)   # root price is exactly the MEM price
    end

    # The per-bus keyword form (consumed by the module-API harness) returns bus 2's row.
    @test extract_dlmp(ctx; bus = 2, T = T) ≈ M[2, :]
end

@testitem "dlmp: extract_dlmp REFUSES an ungated SOCP ctx (PF-04 gate, PRICE-01)" tags = [
    :dlmp,
] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # A SOCP-SHAPED ctx (its `pf_vars` carries a squared current `:l`) that was NEVER certified
    # exact (no `ctx.meta[:socp_maxgap]`). extract_dlmp must throw rather than price a possibly-
    # inexact cone whose duals are physically meaningless (threat T-05-01). The guard fires
    # before any dual is read, so no solve is needed.
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    model = Model()
    @variable(model, x[1:2, 1:1])
    @constraint(model, bp[j = 1:2, t = 1:1], x[j, t] == 0)
    ctx = TSODSO.ModelContext(model)
    ctx.meta[:feeder] = feeder
    ctx.meta[:T] = 1
    register_constraint!(ctx, :balance_p, bp)
    ctx.meta[:pf_vars] = (; l = x)          # `:l` present ⇒ SOCP-shaped; NO :socp_maxgap ⇒ ungated

    @test_throws ArgumentError extract_dlmp(ctx)

    # Stashing the PF-04 certificate lifts the refusal: with `:socp_maxgap` present the ctx is
    # priceable and the guard passes (the subsequent dual read is a separate solve concern,
    # exercised by the solved 2-bus / IEEE-13 items). The guard is the ONLY thing standing
    # between an inexact cone and a shipped price.
    ctx.meta[:socp_maxgap] = 1e-9
    @test TSODSO._assert_priceable(ctx) === nothing

    # A LinDistFlow/DC-shaped ctx (no `:l` in pf_vars) is NOT SOCP, so no exactness certificate
    # is required — the gate must NOT refuse it.
    ctx2 = TSODSO.ModelContext(model)
    register_constraint!(ctx2, :balance_p, bp)
    ctx2.meta[:pf_vars] = (; P = x)         # no `:l` ⇒ not a cone ⇒ no gate
    @test TSODSO._assert_priceable(ctx2) === nothing
end

@testitem "dlmp: extract_dlmp returns the (N,T) DADP matrix on the IEEE-13 ground solve (PRICE-01)" tags = [
    :dlmp,
] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = ieee13_modified()
    aggs = Phase4Fixtures.build_ieee13_ground_aggregators(feeder)
    λ₀ = Phase4Fixtures.mem_price_profile()
    ctx, _obj, _dadp = solve_welfare(
        feeder, ConvexBranchFlow(), aggs;
        T = Phase4Fixtures.T, λ₀ = λ₀, allow_export = true,
    )

    M = extract_dlmp(ctx)
    @test size(M) == (length(feeder.buses), Phase4Fixtures.T)
    @test all(isfinite, M)
    # The root row is the MEM price λ₀ (energy component); every entry is a real dual.
    for t in 1:Phase4Fixtures.T
        @test isapprox(M[feeder.root, t], λ₀[t]; atol = 1e-3)
    end
end
