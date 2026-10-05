# Seam: pricing/fit.jl. Flat feed-in-tariff (FIT) baseline counterfactual.
#
# @testitems for
# `fit_baseline` (re-solve the operational welfare under a flat feed-in tariff and return the
# baseline welfare / prices + the DLMP-vs-FIT efficiency ratio). Every item name contains
# "fit" so `occursin("fit", ti.name)` selects it. The behavioral asserts sit behind an
# `isdefined` guard so a missing symbol fails cleanly.

@testitem "fit: fit_baseline is defined and returns a finite baseline welfare" tags = [:fit] begin
    using TSODSO

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

@testitem "fit: the DLMP-vs-FIT efficiency ratio is a finite positive scalar" tags = [:fit] begin
    using TSODSO

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

# `fit_baseline`'s FIT AC-PF step (SITE 2) previously
# called ONLY `assert_solved!` — never `assert_socp_exact!` — so a genuinely inexact SOC
# relaxation there silently returned an uncertified `social_fit`/`ratio`.
#
# SEMANTICS: SITE 2 is no longer a fixed-
# dispatch SOC relaxation gated by `assert_socp_exact!` — it is a genuine AC power flow,
# PHYSICS ONLY (`ACPowerFlow(; limits = false)`), because the OLD fixed-dispatch SOC re-solve
# was found STRUCTURALLY inexact on a real fixture (IEEE-123, gap≈211) — fixing every injection leaves the loss current free with nothing to
# pin it. There is no longer a "cone slack" for `on_inexact` to certify; it now gates a
# genuine Ipopt NON-CONVERGENCE instead. Rather than searching for a fixture that happens to
# make the physics-only AC power flow genuinely non-solvable (fragile, feeder-specific), this
# item FORCES the failure deterministically via the internal test seam
# `_site2_ac_optimizer` (mirrors `run_mpc`'s own `_truth_settlement` idiom) — a crippled
# `max_iter=1` Ipopt cannot converge in one iteration on ANY fixture, giving a reproducible
# `ITERATION_LIMIT` regardless of the feeder.
@testitem "fit: SITE 2 (FIT AC-PF) on_inexact=:error throws on a forced AC non-convergence, :report returns the diagnostic" tags =
    [:fit] setup = [IEEE13Fixtures] begin
    using TSODSO, JuMP

    @test isdefined(TSODSO, :fit_baseline)

    if isdefined(TSODSO, :fit_baseline)
        feeder = IEEE13Fixtures.high_pv_feeder()
        aggs = IEEE13Fixtures.build_high_pv_aggregators(feeder; pv_scale = 2.0)
        λ₀ = IEEE13Fixtures.mem_price_profile()
        crippled = TSODSO.select_optimizer(TSODSO.NLP(); max_iter = 1)

        err = try
            fit_baseline(
                feeder,
                ConvexBranchFlow(),
                aggs;
                T = IEEE13Fixtures.T,
                λ₀ = λ₀,
                on_inexact = :error,
                _site2_ac_optimizer = crippled,
            )
            nothing
        catch e
            e
        end
        @test err isa SolveFailedError
        msg = sprint(showerror, err)
        @test occursin("FIT AC-PF (SITE 2)", msg)
        @test_throws SolveFailedError fit_baseline(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = IEEE13Fixtures.T,
            λ₀ = λ₀,
            on_inexact = :error,
            _site2_ac_optimizer = crippled,
        )

        res = fit_baseline(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = IEEE13Fixtures.T,
            λ₀ = λ₀,
            on_inexact = :report,
            _site2_ac_optimizer = crippled,
        )
        @test res.ac_status !== nothing
        @test res.ac_status != MOI.LOCALLY_SOLVED   # ITERATION_LIMIT (or similar), never a pass
        @test isnan(res.social_fit)   # :report never reads a value off a non-converged model
        @test isnan(res.ratio)

        # A NORMAL (uncrippled) solve on the SAME fixture converges cleanly (the forced failure
        # above is an ARTIFACT of the crippled optimizer, not a genuine property of this
        # fixture's AC physics) and reports a violations diagnostic instead.
        ok = fit_baseline(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = IEEE13Fixtures.T,
            λ₀ = λ₀,
            on_inexact = :error,
        )
        @test isfinite(ok.social_fit)
        @test ok.ac_status == MOI.LOCALLY_SOLVED
        @test length(ok.ac_violations) == IEEE13Fixtures.T

        @test_throws ArgumentError fit_baseline(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = IEEE13Fixtures.T,
            λ₀ = λ₀,
            on_inexact = :bogus,
        )
    end
end
