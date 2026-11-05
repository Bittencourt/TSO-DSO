# test/test_flex_market.jl
#
# Seam: the coordination type hierarchy (`AbstractCoordination`, `PriceBased`, `FlexMarket`) and
# the flexibility-market legs built on it.
#
# Tolerances (julia 1.12.5; pinned at 3x the observed max over 3 seeds, or an exact `==` when the
# observed max is 0.0):
#
#   quantity                                              observed max   pinned
#   ledger: aggregator balance move vs independent        5.6e-15        1.67e-14
#     sum of price*quantity (seeded rows, 2-bus T = 3)
#   ledger: DSO balance move vs the negated sum           0.0            == (exact)
#   bids: |V0 - price-taker utility| (coupled, T = 24)     1.23e-8        3.68e-8
#   bids: secant vs analytic anchor (interruptible,        3.79e-10       1.14e-9
#     K in (1, 4))
#   bids: repair_max (coupled, T = 24, K = 4)              2.72e-6        8.18e-6
#   bids: repair_max (interruptible anchor)                0.0            == (exact)
#
# SOFT-SCOPE RULE: accumulators live inside functions, never bare in a top-level `for`.

@testmodule FlexMarketFixtures begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    const SEEDS = (20260719, 20260720, 20260721)

    # Measured tolerances (see the header table).
    const TOL_FLEX_AGG = 1.67e-14

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

    # ---- bid fixtures ----
    const TOL_V0 = 3.68e-8
    const TOL_ANCHOR = 1.14e-9
    const TOL_REPAIR = 8.18e-6

    const T_INT = 3
    const T_CPL = 24

    function feeder2(smax)
        return Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 1e-3, 1e-3, smax)],
            1,
        )
    end

    # One Interruptible at bus 2, φ = 1.0, with a seeded interior baseline: the tariff price
    # π₀[t] = a − b·p₀[t] makes p₀[t] the price-taker consumption, strictly inside [Pmin, Pmax].
    # `base` is the analytic baseline net injection −p₀ − Pdc.
    function interruptible_agg(seed; Pmin = 0.0, Pmax = 2.0, T = T_INT)
        prof = generate_profiles(seed = seed + 2, T = T)
        a = 6.0 + 2.0 * prof.demand[1]
        bc = 0.5 + prof.demand[2]
        p0 = Pmin == Pmax ? fill(Pmin, T) : Float64[0.4 + prof.demand[t] for t in 1:T]
        π0 = Float64[a - bc * p0[t] for t in 1:T]
        Pdc = Float64[0.1 * prof.demand[t] for t in 1:T]
        agg = Aggregator(2, 1.0, AbstractDevice[Interruptible(2, Pmin, Pmax, a, bc)], Pdc)
        base = Float64[-p0[t] - Pdc[t] for t in 1:T]
        return (; agg, a, bc, p0, π0, Pdc, base, Pmin, Pmax)
    end

    temp() = Float64[
        19,
        18,
        17,
        16,
        16,
        17,
        19,
        21,
        23,
        26,
        28,
        30,
        31,
        32,
        32,
        31,
        29,
        27,
        25,
        23,
        22,
        21,
        20,
        19,
    ]

    # Coupled aggregator (Thermostatic + Deferrable + PVBattery, T = 24) and a seeded tariff.
    function coupled_agg(seed; bus = 2, ls = 0.01, ps = 0.0025)
        prof = generate_profiles(seed = seed + bus, T = T_CPL)
        Ppv = Float64[ps * p for p in prof.pv]
        Pdc = Float64[ls * d for d in prof.demand]
        devs = AbstractDevice[
            Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, temp()),
            Deferrable(bus, 8, 16, 1.0, 0.5, 0.5),
            PVBattery(bus, 0.95, 1.0, 0.05, 0.0, 0.1, 0.05, 3.8, 6.2, 8.9, Ppv),
        ]
        agg = Aggregator(bus, 0.90, devs, Pdc)
        price = Float64[3.0 + 2.0 * prof.demand[t] for t in 1:T_CPL]
        return (; agg, price)
    end

    # The marginal curve of hour t in increasing injection order, offered blocks only.
    function marginal_curve(fb, t)
        K = size(fb.up_q, 2)
        c = Float64[]
        for k in K:-1:1
            fb.dn_q[t, k] > 0 && push!(c, fb.dn_g[t, k])
        end
        for k in 1:K
            fb.up_q[t, k] > 0 && push!(c, fb.up_m[t, k])
        end
        return c
    end
    curve_sorted(fb) = all(t -> issorted(marginal_curve(fb, t)), axes(fb.up_q, 1))

    # Hour-directions with at least one offered block.
    function offered_directions(fb)
        n = 0
        for t in axes(fb.up_q, 1)
            any(>(0), fb.up_q[t, :]) && (n += 1)
            any(>(0), fb.dn_q[t, :]) && (n += 1)
        end
        return n
    end
    expected_solves(fb) =
        1 + 2 * size(fb.up_q, 1) + size(fb.up_q, 2) * offered_directions(fb)

    # Largest deviation of the secant prices from the analytic anchor
    # m_k = π₀ + b(δ_{k−1}+δ_k)/2 (up) and g_k = π₀ − b(δ_{k−1}+δ_k)/2 (down).
    function anchor_error(f, fb)
        T, K = size(fb.up_q)
        e = 0.0
        for t in 1:T
            δu = (f.p0[t] - f.Pmin) / K
            δd = (f.Pmax - f.p0[t]) / K
            for k in 1:K
                mu = f.π0[t] + f.bc * ((k - 1) * δu + k * δu) / 2
                gd = f.π0[t] - f.bc * ((k - 1) * δd + k * δd) / 2
                e = max(e, abs(fb.up_m[t, k] - mu), abs(fb.dn_g[t, k] - gd))
            end
        end
        return e
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
    @test led.transfers[nb + 2] == (
        from = :dso,
        to = (:aggregator, 2),
        t = 1,
        price = 3.0,
        quantity = -0.5,
        amount = -1.5,
    )
    @test led.transfers[nb + 3].amount == -0.75 && led.transfers[nb + 4].amount == 0.75
    @test led.wholesale_payment == base.wholesale_payment
    @test led.merchandising_surplus == led.balances[:dso]
    paid = M.flex_total(rows)
    @test abs((led.balances[(:aggregator, 2)] - base.balances[(:aggregator, 2)]) - paid) <=
          M.TOL_FLEX_AGG
    @test abs((led.balances[:dso] - base.balances[:dso]) + paid) == 0.0

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
            d_agg = abs(
                (l.balances[(:aggregator, 2)] - base.balances[(:aggregator, 2)]) - tot,
            ),
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
        @test r.d_dso == 0.0
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

@testitem "flex market: bids match the interruptible anchor" setup = [FlexMarketFixtures] tags =
    [:flex_market] begin
    using TSODSO
    M = FlexMarketFixtures

    function check(seed, K)
        f = M.interruptible_agg(seed)
        fb = TSODSO.flex_bids(f.agg, f.base; T = M.T_INT, n_blocks = K)
        return (; f, fb, err = M.anchor_error(f, fb))
    end
    for seed in M.SEEDS, K in (1, 4)
        r = check(seed, K)
        @test r.fb isa TSODSO.FlexBids
        @test size(r.fb.up_q) == (M.T_INT, K)
        @test r.fb.n_failed == 0
        # every hour-direction is interior, so every block is offered
        @test all(>(0), r.fb.up_q) && all(>(0), r.fb.dn_q)
        @test r.fb.n_solves == 1 + 2 * M.T_INT + K * 2 * M.T_INT
        @test r.fb.n_solves == M.expected_solves(r.fb)
        @test r.err <= M.TOL_ANCHOR
        @test r.fb.repair_max == 0.0
        @test M.curve_sorted(r.fb)
        @test r.fb.min_bid_ask_gap > 0
        @test isfinite(r.fb.V0)
    end
end

@testitem "flex market: bids reproduce the baseline value on a coupled aggregator" setup =
    [FlexMarketFixtures] tags = [:flex_market] begin
    using TSODSO
    M = FlexMarketFixtures

    function check(seed)
        f = M.coupled_agg(seed)
        pt = price_taker_dispatch(f.agg, f.price; T = M.T_CPL)
        fb = TSODSO.flex_bids(f.agg, pt.net; T = M.T_CPL, n_blocks = 4)
        return (; pt, fb)
    end
    for seed in M.SEEDS
        r = check(seed)
        @test abs(r.fb.V0 - r.pt.utility) <= M.TOL_V0
        @test r.fb.n_failed == 0
        @test r.fb.n_solves == M.expected_solves(r.fb)
        @test r.fb.repair_max <= M.TOL_REPAIR
        @test M.curve_sorted(r.fb)
        @test r.fb.min_bid_ask_gap > 0
        # no offered block narrower than the floor's step, and absent blocks carry no price
        @test all(q -> q == 0.0 || q >= TSODSO.FLEX_RANGE_FLOOR / 4, r.fb.up_q)
        @test all(q -> q == 0.0 || q >= TSODSO.FLEX_RANGE_FLOOR / 4, r.fb.dn_q)
        @test all(r.fb.up_m[r.fb.up_q .== 0.0] .== 0.0)
        @test all(r.fb.dn_g[r.fb.dn_q .== 0.0] .== 0.0)
    end
end

@testitem "flex market: bids on a zero range offer nothing" setup = [FlexMarketFixtures] tags =
    [:flex_market] begin
    using TSODSO
    M = FlexMarketFixtures

    f = M.interruptible_agg(M.SEEDS[1]; Pmin = 1.0, Pmax = 1.0)
    for K in (1, 4)
        fb = TSODSO.flex_bids(f.agg, f.base; T = M.T_INT, n_blocks = K)
        @test all(==(0.0), fb.up_q) && all(==(0.0), fb.dn_q)
        @test all(==(0.0), fb.up_m) && all(==(0.0), fb.dn_g)
        @test fb.n_solves == 1 + 2 * M.T_INT
        @test fb.n_failed == 0
        @test fb.repair_max == 0.0
        @test fb.min_bid_ask_gap == Inf
        @test isfinite(fb.V0)
    end
end

@testitem "flex market: bids guards and monotone repair" setup = [FlexMarketFixtures] tags =
    [:flex_market] begin
    using TSODSO
    using TSODSO: _pav_nondecreasing
    M = FlexMarketFixtures

    # ---- weighted pool-adjacent-violators ----
    @test _pav_nondecreasing([1.0, 2.0, 3.0], [1.0, 1.0, 1.0]) == [1.0, 2.0, 3.0]
    @test _pav_nondecreasing([1.0, 3.0, 2.0], [1.0, 1.0, 1.0]) == [1.0, 2.5, 2.5]
    @test _pav_nondecreasing([3.0, 1.0], [1.0, 3.0]) == [1.5, 1.5]
    @test _pav_nondecreasing([4.0, 3.0, 2.0, 1.0], [1.0, 1.0, 1.0, 1.0]) == fill(2.5, 4)
    @test _pav_nondecreasing(Float64[], Float64[]) == Float64[]
    @test issorted(
        _pav_nondecreasing([0.5, 2.0, -1.0, 3.0, 2.9], [0.1, 1.0, 2.0, 0.5, 0.5]),
    )
    @test_throws ArgumentError _pav_nondecreasing([1.0, 2.0], [1.0])
    @test_throws ArgumentError _pav_nondecreasing([1.0, 2.0], [1.0, 0.0])
    @test_throws ArgumentError _pav_nondecreasing([1.0, NaN], [1.0, 1.0])

    # ---- argument guards ----
    f = M.interruptible_agg(M.SEEDS[1])
    @test_throws ArgumentError TSODSO.flex_bids(
        f.agg,
        f.base[1:2];
        T = M.T_INT,
        n_blocks = 4,
    )
    @test_throws ArgumentError TSODSO.flex_bids(
        f.agg,
        [f.base[1], NaN, f.base[3]];
        T = M.T_INT,
        n_blocks = 4,
    )
    @test_throws ArgumentError TSODSO.flex_bids(f.agg, f.base; T = M.T_INT, n_blocks = 0)
    @test_throws ArgumentError TSODSO.flex_bids(
        f.agg,
        f.base;
        T = M.T_INT,
        n_blocks = 4,
        range_floor = -1.0,
    )
    @test TSODSO.FLEX_RANGE_FLOOR == 1e-6
end
