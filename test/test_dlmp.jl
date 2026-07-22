# Seam: pricing/dlmp.jl (PRICE-02). DLMP extraction + four-way decomposition.
#
# RED @testitem harness (Wave 1 of Phase 5). Plan 05-02 turns these green by defining
# `extract_dlmp` (read the λ_j[t] dual of the registered :balance_p) and `decompose_dlmp`
# (split into energy/loss/voltage/congestion using the :cone/:vdrop/:cpydrop/:smax duals
# registered in plan 05-01, with the sum-to-nodal-price identity as the net). Every item name
# contains "dlmp" so `occursin("dlmp", ti.name)` selects it. While RED the sole failing
# assertion is a missing-symbol `isdefined` check (never a runner crash); behavioral asserts
# sit behind the `isdefined` guard so they go live automatically once 05-02 lands.

@testitem "dlmp: extract_dlmp is defined and returns a per-hour price vector (PRICE-02)" tags =
    [:dlmp] begin
    using TSODSO

    # RED until plan 05-02 defines the DLMP extractor.
    @test isdefined(TSODSO, :extract_dlmp)

    if isdefined(TSODSO, :extract_dlmp)
        using TSODSO: Bus, Branch, Feeder
        using JuMP

        # A minimal lossy 2-bus radial feeder for a live SOCP welfare solve.
        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        T = 3
        batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
        agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
        ctx, _obj, _dadp = solve_welfare(
            feeder,
            ConvexBranchFlow(),
            [agg];
            T = T,
            λ₀ = fill(40.0, T),
            allow_export = true,
        )

        λ = extract_dlmp(ctx; bus = agg.bus, T = T)
        @test length(λ) == T
        @test all(isfinite, λ)
    end
end

@testitem "dlmp: decompose_dlmp components sum to the nodal price (PRICE-02)" tags = [:dlmp] begin
    using TSODSO

    # RED until plan 05-02 defines the four-way decomposition.
    @test isdefined(TSODSO, :decompose_dlmp)

    if isdefined(TSODSO, :decompose_dlmp) && isdefined(TSODSO, :extract_dlmp)
        using TSODSO: Bus, Branch, Feeder
        using JuMP

        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        T = 3
        batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
        agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
        ctx, _obj, _dadp = solve_welfare(
            feeder,
            ConvexBranchFlow(),
            [agg];
            T = T,
            λ₀ = fill(40.0, T),
            allow_export = true,
        )

        comps = decompose_dlmp(ctx; bus = agg.bus, T = T)
        λ = extract_dlmp(ctx; bus = agg.bus, T = T)
        # The four components (energy + loss + voltage + congestion) must sum to the DLMP.
        for t in 1:T
            total = comps.energy[t] + comps.loss[t] + comps.voltage[t] + comps.congestion[t]
            @test isapprox(total, λ[t]; atol = 1e-4)
        end
    end
end
