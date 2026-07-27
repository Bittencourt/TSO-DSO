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

@testitem "dlmp: extract_dlmp on a lossless 2-bus is positive and ≈ λ₀ (energy-only, PRICE-01)" tags =
    [:dlmp] begin
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
    ctx, _obj, _dadp = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        allow_export = true,
    )

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

@testitem "dlmp: extract_dlmp REFUSES an ungated SOCP ctx (PF-04 gate, PRICE-01)" tags =
    [:dlmp] begin
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

@testitem "dlmp: extract_dlmp returns the (N,T) DADP matrix on the IEEE-13 ground solve (PRICE-01)" tags =
    [:dlmp] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = ieee13_modified()
    aggs = Phase4Fixtures.build_ieee13_ground_aggregators(feeder)
    λ₀ = Phase4Fixtures.mem_price_profile()
    ctx, _obj, _dadp = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
    )

    M = extract_dlmp(ctx)
    @test size(M) == (length(feeder.buses), Phase4Fixtures.T)
    @test all(isfinite, M)
    # The root row is the MEM price λ₀ (energy component); every entry is a real dual.
    for t in 1:Phase4Fixtures.T
        @test isapprox(M[feeder.root, t], λ₀[t]; atol = 1e-3)
    end
end

@testitem "dlmp: decompose_dlmp four components SUM to the DADP on IEEE-13 (congestion binds, PRICE-02)" tags =
    [:dlmp] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = ieee13_modified()
    aggs = Phase4Fixtures.build_ieee13_ground_aggregators(feeder)
    λ₀ = Phase4Fixtures.mem_price_profile()
    ctx, _obj, _dadp = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
    )

    d = decompose_dlmp(ctx)
    total = extract_dlmp(ctx)
    N, T = size(total)

    # Every field is an (N, T) matrix.
    for f in (d.energy, d.loss, d.congestion, d.voltage, d.total)
        @test size(f) == (N, T)
    end

    # THE HARD sum-to-nodal-price net (Success Criterion #2): the four INDEPENDENTLY
    # reconstructed components sum to the DADP elementwise, and `total` IS the DADP.
    @test all(
        isapprox(
            d.energy[j, t] + d.loss[j, t] + d.congestion[j, t] + d.voltage[j, t],
            total[j, t];
            atol = 1e-6,
            rtol = 1e-6,
        ) for j in 1:N, t in 1:T
    )
    @test d.total ≈ total

    # PARALLEL, non-summed finite-check on `d.reactive` (REACT-02): a SEPARATE price signal
    # from the 4-term active reconstruction above — checked for finiteness only, deliberately
    # NOT folded into the sum-to-nodal-price assertion (which stays exactly 4-term).
    for f in (d.energy, d.loss, d.congestion, d.voltage, d.reactive)
        @test all(isfinite, f)
    end

    # The energy component is the root MEM price at EVERY node (≈ λ₀), same across space.
    for j in 1:N, t in 1:T
        @test isapprox(d.energy[j, t], λ₀[t]; atol = 1e-3)
    end

    # The modified IEEE-13 is congestion-driven at the head branch: the congestion component is
    # genuinely NONZERO at the PV-peak hours where S_max,(0,1) binds (not a spurious zero).
    @test any(abs(d.congestion[j, t]) > 1e-2 for j in 1:N, t in 1:T)
end

@testitem "dlmp: decompose_dlmp SUM holds and voltage is engaged on the high-PV over-voltage solve (PRICE-02)" tags =
    [:dlmp] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = Phase4Fixtures.high_pv_feeder()
    aggs = Phase4Fixtures.build_high_pv_aggregators(feeder)
    λ₀ = Phase4Fixtures.mem_price_profile()
    ctx, _obj, _dadp = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
    )

    d = decompose_dlmp(ctx)
    total = extract_dlmp(ctx)
    N, T = size(total)

    # Sum-to-nodal-price holds in the over-voltage / reverse-flow regime too.
    @test all(
        isapprox(
            d.energy[j, t] + d.loss[j, t] + d.congestion[j, t] + d.voltage[j, t],
            total[j, t];
            atol = 1e-6,
            rtol = 1e-6,
        ) for j in 1:N, t in 1:T
    )
    @test d.total ≈ total

    # No thermal limit exists on this fixture (99.0 sentinel), so congestion is identically 0 …
    @test all(iszero, d.congestion)
    # … while the voltage-drop component is ENGAGED (nonzero) as the back-feed lifts voltage.
    @test any(abs(d.voltage[j, t]) > 1e-8 for j in 1:N, t in 1:T)
end

@testitem "dlmp: decompose_dlmp has ≈0 congestion/voltage on an uncongested in-bound 2-bus (PRICE-02)" tags =
    [:dlmp] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # Lossless, uncongested (smax ≫ flow), in-bound (voltage un-binding) 2-bus: only the ENERGY
    # component survives — congestion ≈ 0, voltage ≈ 0, and the total ≈ energy ≈ λ₀.
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 1e-6, 1e-6, 10.0)],
        1,
    )
    T = 3
    λ₀ = fill(40.0, T)
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
    ctx, _obj, _dadp = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        allow_export = true,
    )

    d = decompose_dlmp(ctx)
    total = extract_dlmp(ctx)
    N, _ = size(total)

    @test all(
        isapprox(
            d.energy[j, t] + d.loss[j, t] + d.congestion[j, t] + d.voltage[j, t],
            total[j, t];
            atol = 1e-6,
            rtol = 1e-6,
        ) for j in 1:N, t in 1:T
    )
    for t in 1:T
        @test isapprox(d.congestion[2, t], 0.0; atol = 1e-4)   # uncongested ⇒ ≈ 0
        @test isapprox(d.voltage[2, t], 0.0; atol = 1e-4)      # in-bound ⇒ ≈ 0
        @test isapprox(d.energy[2, t], λ₀[t]; atol = 1e-6)     # energy = root MEM price
        @test isapprox(d.total[2, t], λ₀[t]; atol = 1e-2)      # total ≈ energy (energy-only)
        @test d.total[2, t] > 0                                # positive marginal cost
    end

    # The per-bus keyword form returns length-T component vectors (module-API harness contract).
    dv = decompose_dlmp(ctx; bus = 2, T = T)
    @test dv.energy isa Vector{Float64}
    @test length(dv.total) == T
    for t in 1:T
        @test dv.energy[t] + dv.loss[t] + dv.voltage[t] + dv.congestion[t] ≈ dv.total[t]
    end
end

@testitem "dlmp: reactive price is degenerate at the root and finite/economically-consistent at a load bus on a lossy 2-bus (REACT-02)" tags =
    [:dlmp] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # Lossy 2-bus radial fixture (r=0.01, x=0.02), the SAME shape used by
    # test_ac_oracle.jl's angle-recovery validation gate — a genuinely lossy branch is what
    # makes the load-bus reactive price analytically non-trivial (unlike the near-lossless
    # r=x=1e-6 fixture used by this file's other 2-bus items).
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T = 3
    λ₀ = fill(40.0, T)
    Pdc = fill(0.1, T)
    φ0 = 0.9   # non-degenerate power factor: reactive_factor(0.9) > 0, so tanφ > 0
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, φ0, [batt], Pdc)

    ctx, obj0, _dadp = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        allow_export = true,
    )
    d = decompose_dlmp(ctx)

    # (a) The root's reactive price is DEGENERATE (≈0): the free-sign, zero-objective-
    # coefficient `q_import`'s own KKT stationarity forces its dual to exactly zero (RESEARCH
    # "Free slack, precisely located").
    for t in 1:T
        @test isapprox(d.reactive[1, t], 0.0; atol = 1e-6)
    end

    # (b) The load bus's reactive price is a FINITE, non-degenerate, reproducible number.
    for t in 1:T
        @test isfinite(d.reactive[2, t])
    end

    # Finite-difference economic-consistency pin (RESEARCH Pitfall 6/7 discipline — a
    # hand-computed sanity check, not a further closed-form KKT re-derivation of the reactive
    # price itself, per Assumption A1's minimal one-shot-price scope): perturb the SAME
    # aggregator's power factor by a small δ, re-solve, and confirm the welfare objective's
    # change matches Σ_t d.reactive[2, t] * (q1[t] - q0[t]) to first order, where q0/q1 are the
    # aggregator's reactive-demand values before/after the perturbation computed via the SAME
    # `reactive_factor` formula the production code path uses (src/devices/Aggregator.jl).
    δ = 1e-4
    agg_perturbed = Aggregator(2, φ0 + δ, [batt], Pdc)
    _ctx1, obj1, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        [agg_perturbed];
        T = T,
        λ₀ = λ₀,
        allow_export = true,
    )

    q0 = -Pdc .* reactive_factor(φ0)
    q1 = -Pdc .* reactive_factor(φ0 + δ)
    predicted_Δobj = sum(d.reactive[2, t] * (q1[t] - q0[t]) for t in 1:T)
    actual_Δobj = obj1 - obj0

    @test isapprox(predicted_Δobj, actual_Δobj; atol = 1e-8, rtol = 5e-2)
end
