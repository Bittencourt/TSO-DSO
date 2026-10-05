# Seam: pricing/dlmp.jl. DLMP extraction + four-way decomposition.
#
# @testitem harness for
# `extract_dlmp` (read the λ_j[t] dual of the registered :balance_p) and `decompose_dlmp`
# (split into energy/loss/voltage/congestion using the :cone/:vdrop/:cpydrop/:smax duals
# registered by the convex branch flow, with the sum-to-nodal-price identity as the net). Every item name
# contains "dlmp" so `occursin("dlmp", ti.name)` selects it. The first
# assertion is a missing-symbol `isdefined` check (never a runner crash); behavioral asserts
# sit behind the `isdefined` guard so they go live automatically once the functions exist.

@testitem "dlmp: extract_dlmp is defined and returns a per-hour price vector" tags = [:dlmp] begin
    using TSODSO

    # The DLMP extractor must be defined.
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

@testitem "dlmp: decompose_dlmp components sum to the nodal price" tags = [:dlmp] begin
    using TSODSO

    # The four-way decomposition must be defined.
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
            total = comps.energy[t] + comps.cone[t] + comps.drop[t] + comps.congestion[t]
            @test isapprox(total, λ[t]; atol = 1e-4)
        end
    end
end
