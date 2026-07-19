# test/test_pricing_fit.jl
#
# Seam: pricing/fit.jl (PRICE-03, the FIT baseline half). The thesis-faithful FIT-OPT
# (3.24-3.28) + plain AC-PF counterfactual `fit_baseline`, driven GREEN by plan 05-03.
#
# Every @testitem name contains "fit" so `occursin("fit", ti.name)` selects it. These
# items are the plan's own richer contract (the flow-split identities, the FIT social
# welfare, seeded reproducibility, and the "voltage limit NOT enforced" structural
# distinction) — complementary to the coarse Wave-1 RED harness in test/test_fit.jl.

# A small seeded fixture: a 3-bus radial feeder (root + two load buses), each load bus
# holding an aggregator with a Deferrable flexible load + a PVBattery (whose PV the FIT-OPT
# keeps and whose battery it drops). Built purely from `generate_profiles(seed=…)`, so two
# builds with the same seed are bit-for-bit identical (INFRA-04).
@testmodule FitFixtures begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    const T = 4

    function feeder()
        buses = [
            Bus(1, 0.95, 1.05, true),     # root / MEM frontier
            Bus(2, 0.95, 1.05, false),
            Bus(3, 0.95, 1.05, false),
        ]
        branches = [
            Branch(1, 2, 0.02, 0.03, 10.0),
            Branch(2, 3, 0.02, 0.03, 10.0),
        ]
        return Feeder(buses, branches, 1)
    end

    "Aggregators built deterministically from a seed (PV + a deferrable load + a battery)."
    function aggregators(; seed::Integer)
        aggs = TSODSO.Aggregator[]
        for bus in 2:3
            prof = generate_profiles(seed = seed + bus, T = T)
            defer = Deferrable(bus, 1, T, 0.4, 0.3, 1.0)
            batt = PVBattery(bus, 0.95, 1.0, 0.3, 0.0, 1.0, 0.5, 1.0, 2.0, 3.0, prof.pv)
            push!(aggs, Aggregator(bus, 0.9, [defer, batt], prof.demand))
        end
        return aggs
    end
end

@testitem "fit: FIT-OPT flows satisfy the import/self-consume/export split (3.25-3.27)" setup =
    [FitFixtures] tags = [:fit] begin
    using TSODSO
    using TSODSO: select_optimizer, problem_class

    T = FitFixtures.T
    aggs = FitFixtures.aggregators(seed = 20260718)

    fa = TSODSO._fit_opt_solve(
        aggs;
        T = T,
        optimizer = select_optimizer(problem_class(ConvexBranchFlow())),
    )

    @test isfinite(fa.prosumer_surplus)
    @test length(fa.per_agg) == length(aggs)

    for a in fa.per_agg
        for t in 1:T
            # Flow-split identities (thesis 3.25-3.27): exact structural equalities.
            @test a.self[t] + a.imp[t] ≈ a.p_h[t] atol = 1e-6
            @test a.self[t] + a.exp[t] ≈ a.Ppv[t] atol = 1e-6
            # Non-negativity ⇒ self ≤ min(Ppv, p_h) (the max/min split without a nonconvex min).
            @test a.self[t] >= -1e-6
            @test a.imp[t] >= -1e-6
            @test a.exp[t] >= -1e-6
            # Net grid injection identity: net = exp − imp = Ppv − p_h (thesis 3.22).
            @test a.net[t] ≈ a.Ppv[t] - a.p_h[t] atol = 1e-6
        end
    end
end

@testitem "fit: FIT baseline uses the German-FIT price triple as documented constants" tags =
    [:fit] begin
    using TSODSO

    # Named module constants (thesis page 93), in the SAME ¢$/kWh unit as λ₀ (Pitfall 5).
    @test TSODSO.FIT_λ_IMPORT == 6.6
    @test TSODSO.FIT_λ_EXPORT == 9.6
    @test TSODSO.FIT_λ_SELF == 5.6
    # Import cost strictly below export revenue below … the thesis German-FIT calibration.
    @test TSODSO.FIT_λ_SELF < TSODSO.FIT_λ_IMPORT < TSODSO.FIT_λ_EXPORT
end
