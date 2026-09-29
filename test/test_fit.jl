# Seam: pricing/fit.jl (PRICE-04). Flat feed-in-tariff (FIT) baseline counterfactual.
#
# RED @testitem harness (Wave 1 of Phase 5). Plan 05-03 turns these green by defining
# `fit_baseline` (re-solve the operational welfare under a flat feed-in tariff and return the
# baseline welfare / prices + the DLMP-vs-FIT efficiency ratio). Every item name contains
# "fit" so `occursin("fit", ti.name)` selects it. While RED the sole failing assertion is a
# missing-symbol `isdefined` check; the behavioral asserts sit behind the `isdefined` guard.

@testitem "fit: fit_baseline is defined and returns a finite baseline welfare (PRICE-04)" tags =
    [:fit] begin
    using TSODSO

    # RED until plan 05-03 defines the FIT baseline.
    @test isdefined(TSODSO, :fit_baseline)

    if isdefined(TSODSO, :fit_baseline)
        using TSODSO: Bus, Branch, Feeder

        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        T = 3
        batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
        agg = Aggregator(2, 0.9, [batt], fill(0.1, T))

        res = fit_baseline(feeder, ConvexBranchFlow(), [agg]; λ_fit = 40.0, T = T)
        @test isfinite(res.welfare)
    end
end

@testitem "fit: the DLMP-vs-FIT efficiency ratio is a finite positive scalar (PRICE-04)" tags =
    [:fit] begin
    using TSODSO

    # RED until plan 05-03 exposes the efficiency ratio.
    @test isdefined(TSODSO, :fit_baseline)

    if isdefined(TSODSO, :fit_baseline)
        using TSODSO: Bus, Branch, Feeder

        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        T = 3
        batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
        agg = Aggregator(2, 0.9, [batt], fill(0.1, T))

        res = fit_baseline(feeder, ConvexBranchFlow(), [agg]; λ_fit = 40.0, T = T)
        @test res.ratio > 0
        @test isfinite(res.ratio)
    end
end

# FIX-09 (Phase 27, plan 27-05; T-27-12): `fit_baseline`'s FIT AC-PF step (SITE 2) previously
# called ONLY `assert_solved!` — never `assert_socp_exact!` — so a genuinely inexact SOC
# relaxation there silently returned an uncertified `social_fit`/`ratio`. This item is RED
# until the `on_inexact::Symbol` kwarg is wired in (`src/pricing/fit.jl`).
@testitem "fit: SITE 2 (FIT AC-PF) on_inexact=:error refuses an inexact cone, :report returns a finite certificate (FIX-09)" tags =
    [:fit] setup = [Phase4Fixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :fit_baseline)

    if isdefined(TSODSO, :fit_baseline)
        # pv_scale=2.0 on Phase4Fixtures' high-PV stress fixture (EXACT-04's own substrate)
        # drives `fit_baseline`'s SITE 2 (the FIT AC-PF, on its OWN voltage-relaxed [0.8,1.2]
        # feeder copy) genuinely INEXACT — measured directly at ≈6.1 (an O(1) cone slack, not
        # borderline solver noise) — while the OTHER two internal solves (the FIT-OPT, the
        # nested solve_welfare cross-check) both succeed. EXACT-04's own pv_scale=1.2 (tuned
        # against the TIGHT [0.95,1.05] band) stays EXACT here: SITE 2's wider relaxed band
        # needs a LARGER back-feed to pin its own, higher voltage cap.
        feeder = Phase4Fixtures.high_pv_feeder()
        aggs = Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 2.0)
        λ₀ = Phase4Fixtures.mem_price_profile()

        @test_throws Exception fit_baseline(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Phase4Fixtures.T,
            λ₀ = λ₀,
            on_inexact = :error,
        )

        res = fit_baseline(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Phase4Fixtures.T,
            λ₀ = λ₀,
            on_inexact = :report,
        )
        @test isfinite(res.socp_maxgap)
        @test res.socp_maxgap > 0   # a genuine, non-trivial cone slack was measured, not 0

        @test_throws ArgumentError fit_baseline(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Phase4Fixtures.T,
            λ₀ = λ₀,
            on_inexact = :bogus,
        )
    end
end
