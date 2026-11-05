# test/test_flex_market.jl
#
# Seam: the coordination type hierarchy (`AbstractCoordination`, `PriceBased`, `FlexMarket`) and
# the flexibility-market legs built on it.
#
# Tolerances (julia 1.12.5; pinned at 3x the observed max over 3 seeds, or an exact `==` when the
# observed max is 0.0):
#
#   quantity                                              observed max   pinned
#
# SOFT-SCOPE RULE: accumulators live inside functions, never bare in a top-level `for`.

@testitem "flex market: coordination types and row naming" tags = [:flex_market] begin
    using TSODSO
    using TSODSO: _flex_row_name, coordination_label

    # ---- defaults and the type hierarchy ----
    fm = FlexMarket()
    @test fm isa AbstractCoordination
    @test PriceBased() isa AbstractCoordination
    @test fm.baseline_tariff === :flat
    @test fm.payment_rule === :uniform
    @test fm.n_blocks === 4
    @test fm.baseline_inflation === 0.0
    @test FlexMarket(; baseline_inflation = 0).baseline_inflation === 0.0
    @test FlexMarket(; baseline_tariff = :tou, payment_rule = :pay_as_bid).payment_rule ===
          :pay_as_bid
    @test coordination_label(PriceBased()) == "price_based"
    @test coordination_label(fm) == "flex_market"

    # ---- keyword validation: every bad value is an ArgumentError ----
    @test_throws ArgumentError FlexMarket(; payment_rule = :vickrey)
    @test_throws ArgumentError FlexMarket(; baseline_tariff = :fit)
    @test_throws ArgumentError FlexMarket(; n_blocks = 0)
    @test_throws ArgumentError FlexMarket(; n_blocks = -3)
    @test_throws ArgumentError FlexMarket(; baseline_inflation = -0.01)
    @test_throws ArgumentError FlexMarket(; baseline_inflation = NaN)
    @test_throws ArgumentError FlexMarket(; baseline_inflation = Inf)

    # ---- row naming ----
    @test _flex_row_name(FlexMarket()) == "flex_uniform"
    @test _flex_row_name(FlexMarket(; payment_rule = :pay_as_bid)) == "flex_pab"
    @test _flex_row_name(FlexMarket(; baseline_inflation = 0.05)) == "flex_uniform_beta0.05"
    @test _flex_row_name(FlexMarket(; baseline_tariff = :tou)) == "flex_uniform_tou"
    @test _flex_row_name(FlexMarket(; n_blocks = 8)) == "flex_uniform_k8"

    # ---- injectivity over the full keyword grid ----
    function grid_names()
        out = String[]
        for rule in (:uniform, :pay_as_bid),
            tariff in (:flat, :tou),
            k in (1, 4, 8),
            β in (0.0, 0.05, 0.10)

            m = FlexMarket(;
                baseline_tariff = tariff,
                payment_rule = rule,
                n_blocks = k,
                baseline_inflation = β,
            )
            push!(out, _flex_row_name(m))
        end
        return out
    end
    row_names = grid_names()
    @test length(row_names) == 2 * 2 * 3 * 3
    @test allunique(row_names)
end
