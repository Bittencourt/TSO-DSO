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

@testmodule FlexMarketFixtures begin
    using TSODSO

    const SEEDS = (20260719, 20260720, 20260721)

    # Measured tolerances (see the header table).
    const TOL_FLEX_AGG = NaN
    const TOL_FLEX_DSO = NaN

    # Seeded flexibility-payment rows on bus 2 for every hour of a T-hour horizon: price and
    # quantity derive from `generate_profiles(seed = seed + bus)`, signs alternate.
    function flex_rows(seed; T = 3, bus = 2)
        prof = generate_profiles(seed = seed + bus, T = T)
        return [
            (
                bus = bus,
                t = t,
                price = 1.7 + 3.1 * prof.demand[t],
                quantity = (isodd(t) ? 1.0 : -1.0) * (0.37 * prof.demand[t] + 0.013 * t),
            ) for t in 1:T
        ]
    end

    # Independent sum of price * quantity over the rows (the aggregator's flexibility income).
    function flex_total(rows)
        s = 0.0
        for r in rows
            s += r.price * r.quantity
        end
        return s
    end
end

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

@testitem "flex market: ledger flex payments conserve and validate" setup =
    [FlexFenceFixtures, FlexMarketFixtures] tags = [:settlement, :flex_market] begin
    using TSODSO
    F = FlexFenceFixtures
    M = FlexMarketFixtures

    input = F.default_input()
    base = build_settlement_ledger(input)
    nb = length(base.transfers)

    # ---- two hand-written rows: up-flex earns, down-flex pays ----
    rows = [
        (bus = 2, t = 1, price = 3.0, quantity = 0.5),
        (bus = 2, t = 2, price = 3.0, quantity = -0.25),
    ]
    led = build_settlement_ledger(input; flex_payments = rows)
    @test ledger_residual(led) == 0.0
    @test length(led.transfers) == nb + 2 * length(rows)
    # the base flows are an unchanged prefix; the flexibility rows are appended after them
    @test led.transfers[1:nb] == base.transfers
    @test led.transfers[nb + 1] == (
        from = (:aggregator, 2),
        to = :dso,
        t = 1,
        price = 3.0,
        quantity = 0.5,
        amount = 1.5,
    )
    @test led.transfers[nb + 2] ==
          (from = :dso, to = (:aggregator, 2), t = 1, price = 3.0, quantity = -0.5, amount = -1.5)
    @test led.transfers[nb + 3].amount == -0.75 && led.transfers[nb + 4].amount == 0.75
    @test led.wholesale_payment == base.wholesale_payment
    @test led.merchandising_surplus == led.balances[:dso]
    paid = M.flex_total(rows)
    @test abs((led.balances[(:aggregator, 2)] - base.balances[(:aggregator, 2)]) - paid) <=
          M.TOL_FLEX_AGG
    @test abs((led.balances[:dso] - base.balances[:dso]) + paid) <= M.TOL_FLEX_DSO

    # ---- the SettlementInput overload forwards the keyword to the primitive ----
    led_p = build_settlement_ledger(
        input.prices,
        input.bus_nets,
        input.bus_utilities,
        input.p_import,
        input.λ₀,
        input.buses;
        T = input.T,
        source = input.source,
        flex_payments = rows,
    )
    @test led_p.transfers == led.transfers
    @test led_p.balances == led.balances
    @test led_p.merchandising_surplus == led.merchandising_surplus

    # ---- seeded rows on every hour: exact conservation, mirror moves ----
    function check(seed)
        rs = M.flex_rows(seed; T = F.T)
        l = build_settlement_ledger(input; flex_payments = rs)
        tot = M.flex_total(rs)
        return (;
            residual = ledger_residual(l),
            prefix = l.transfers[1:nb] == base.transfers,
            n = length(l.transfers),
            d_agg = abs((l.balances[(:aggregator, 2)] - base.balances[(:aggregator, 2)]) - tot),
            d_dso = abs((l.balances[:dso] - base.balances[:dso]) + tot),
            wholesale = l.wholesale_payment == base.wholesale_payment,
        )
    end
    for seed in M.SEEDS
        r = check(seed)
        @test r.residual == 0.0
        @test r.prefix
        @test r.n == nb + 2 * F.T
        @test r.d_agg <= M.TOL_FLEX_AGG
        @test r.d_dso <= M.TOL_FLEX_DSO
        @test r.wholesale
    end

    # ---- V5 guards: every malformed row is an ArgumentError before any transfer ----
    build(rs) = build_settlement_ledger(input; flex_payments = rs)
    r1 = rows[1]
    @test_throws ArgumentError build([(bus = 2, t = 1, quantity = 0.5)])
    @test_throws ArgumentError build([(; r1..., bus = 99)])
    @test_throws ArgumentError build([(; r1..., t = 0)])
    @test_throws ArgumentError build([(; r1..., t = F.T + 1)])
    @test_throws ArgumentError build([(; r1..., t = 1.5)])
    @test_throws ArgumentError build([(; r1..., price = NaN)])
    @test_throws ArgumentError build([(; r1..., quantity = Inf)])
    @test_throws ArgumentError build([(; r1..., price = "3.0")])
    # an empty row list adds nothing
    l0 = build([])
    @test l0.transfers == base.transfers && l0.balances == base.balances
end
