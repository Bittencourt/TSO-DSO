# test/test_flex_market_ieee.jl
#
# Seam: the flexibility-market legs of `compare_tariffs` on the IEEE-13 ground fixture.
#
# The slow item runs the comparison with two flex legs (uniform and pay-as-bid, flat baseline)
# and asserts only status-set membership and finiteness: the flex outcome on this fixture is a
# measured result, so no welfare value and no "feasible" verdict is pinned here. The committed
# measurement itself lives in results/settlement_comparison/ (scripts/tariff_comparison.jl).

@testitem "flex market: IEEE-13 ground compare with flex legs" tags = [:flex_market, :slow] setup =
    [IEEE13Fixtures] begin
    using TSODSO
    using DataFrames: eachrow, nrow

    feeder = ieee13_modified()
    aggs = IEEE13Fixtures.build_ieee13_ground_aggregators(feeder)
    res = compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = IEEE13Fixtures.T,
        λ₀ = IEEE13Fixtures.mem_price_profile(),
        engine = :centralized,
        flex_market = [FlexMarket(), FlexMarket(payment_rule = :pay_as_bid)],
    )

    # Six rows in a fixed order: the four tariff legs, then the flex legs in input order.
    @test nrow(res.summary) == 6
    @test res.summary.tariff == ["dadp", "flat", "tou", "fit", "flex_uniform", "flex_pab"]
    row_of = Dict(r.tariff => r for r in eachrow(res.summary))

    allowed_status(s) =
        s in ("ok", "infeasible_redispatch", "inexact_redispatch") || startswith(s, "error:")
    allowed_feas = ("feasible", "infeasible", "solve_failed", "not_run")
    for name in ("flex_uniform", "flex_pab")
        fr = row_of[name]
        @test allowed_status(fr.status)
        @test fr.feasibility_status in allowed_feas
        if fr.status == "ok"
            @test isfinite(fr.welfare)
            @test isfinite(fr.welfare_gap_vs_dadp_lossless)
            @test fr.delivery_shortfall_total >= 0
        end
    end

    # The payment rule changes money only: both legs share one physics clear.
    fu = row_of["flex_uniform"]
    fp = row_of["flex_pab"]
    @test fu.status == fp.status
    @test isequal(fu.welfare, fp.welfare)
    @test fu.feasibility_status == fp.feasibility_status
end
