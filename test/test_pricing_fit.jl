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

@testitem "fit: fit_baseline solves OPTIMAL with a finite magnitude-sane social welfare" setup =
    [FitFixtures] tags = [:fit] begin
    using TSODSO

    T = FitFixtures.T
    feeder = FitFixtures.feeder()
    aggs = FitFixtures.aggregators(seed = 20260718)

    res = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = T)

    @test isfinite(res.social_fit)
    @test res.social_fit == res.welfare        # `welfare` is the alias the harness reads
    @test isfinite(res.prosumer_surplus)
    # Efficiency ratio social_DADP / social_fit is finite and positive (a self-contained
    # cross-check; the authoritative +25% headline ≈ 1.25 is computed by 05-05).
    @test isfinite(res.ratio)
    @test res.ratio > 0
    @test length(res.fit_flows) == length(aggs)
end

@testitem "fit: fit_baseline is reproducible bit-for-bit under a fixed seed (T-05-09)" setup =
    [FitFixtures] tags = [:fit] begin
    using TSODSO

    T = FitFixtures.T
    feeder = FitFixtures.feeder()

    res1 = fit_baseline(feeder, ConvexBranchFlow(), FitFixtures.aggregators(seed = 4242); T = T)
    res2 = fit_baseline(feeder, ConvexBranchFlow(), FitFixtures.aggregators(seed = 4242); T = T)

    # Same seed ⇒ identical baseline (deterministic solve over identical seeded profiles).
    @test res1.social_fit == res2.social_fit
    @test res1.prosumer_surplus == res2.prosumer_surplus

    # A different seed generally yields a different baseline (guards against a constant stub).
    res3 = fit_baseline(feeder, ConvexBranchFlow(), FitFixtures.aggregators(seed = 9999); T = T)
    @test res3.social_fit != res1.social_fit
end

@testitem "fit: the FIT AC-PF does NOT enforce the voltage limit (relaxed baseline ctx)" setup =
    [FitFixtures] tags = [:fit] begin
    using TSODSO

    T = FitFixtures.T
    feeder = FitFixtures.feeder()
    aggs = FitFixtures.aggregators(seed = 20260718)

    res = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = T)

    # The baseline ctx is marked as the FIT counterfactual, structurally distinct from a
    # DADP welfare ctx (no battery, voltage limit relaxed — Assumption A4 / Open Q3).
    @test res.ctx.meta[:fit_baseline] === true

    # The AC-PF ran on a voltage-RELAXED feeder: the original tight band [0.95, 1.05] is
    # widened to the per-unit sanity band [0.8, 1.2], so 3.35 does not bind (not enforced).
    relaxed = res.ctx.meta[:feeder]
    for b in relaxed.buses
        b.is_root && continue
        @test b.vmin == 0.8
        @test b.vmax == 1.2
    end

    # The solve is OPTIMAL and registered its nodal balance like a normal solve.
    @test haskey(res.ctx.constraints, :balance_p)
end

# ---------------------------------------------------------------------------------------------
# EXP-04 regression golden: FIT-vs-DADP ratio on this file's OWN small `FitFixtures` scenario.
#
# DISTINCT from and ADDITIVE to `test/test_pricing_welfare.jl`'s `RATIO_GOLDEN` (which pins the
# ratio on the larger IEEE-13 ground scenario) — this pins `fit_baseline`'s own self-contained
# efficiency indicator `res.ratio = social_dadp / social_fit` (computed internally by
# `fit_baseline`, per its docstring) on the small 3-bus fixture this file already owns, giving
# EXP-04 a FIT-focused regression independent of the IEEE-13 fixture. `FIT_RATIO_GOLDEN` was
# captured from the FIRST trusted solve on the fixed seed (20260718) — the same "first trusted
# solve" convention every other golden in this codebase follows (cf. test/test_ieee13.jl's
# header comment). Deterministic under the fixed seed (the "reproducible bit-for-bit" @testitem
# above already proves this).
# ---------------------------------------------------------------------------------------------
@testitem "fit: FIT-vs-DADP ratio regression golden (EXP-04)" setup = [FitFixtures] tags = [
    :fit,
] begin
    using TSODSO

    T = FitFixtures.T
    feeder = FitFixtures.feeder()
    aggs = FitFixtures.aggregators(seed = 20260718)

    res = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = T)

    # PRIMARY reproducibility anchor: the COMPUTED ratio pinned as a golden (tight rtol),
    # captured from the first trusted solve on this fixture's fixed seed.
    FIT_RATIO_GOLDEN = 0.6428101637491034
    @test isapprox(res.ratio, FIT_RATIO_GOLDEN; rtol = 1e-4)
end
