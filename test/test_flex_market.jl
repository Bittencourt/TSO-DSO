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
#   stage 2: |bus_nets - (b + Δ)| (tight 2-bus, K = 4)     2.22e-16       6.67e-16
#   stage 2: max_wash min(Σu, Σw) (tight and no-limit)     7.02e-9        2.11e-8
#   stage 2: Δ with all-zero bid widths                    0.0            == (exact)
#   delivery: Σ shortfall, separable (tight, K = 4)        3.06e-12       9.17e-12
#   delivery: over-reach |shortfall[2] - R↑[2]|            6.97e-10       2.09e-9
#   delivery: over-reach, other hours' shortfall           3.18e-9        9.53e-9
#   delivery: |net(w) - net(10w)| (over-reach, coupled)    1.26e-10       3.79e-10
#   market: |Σ ledger balances| (both rules, β in         4.55e-15       1.37e-14
#     (0, 0.05, 0.10), peaked market fixture, K = 4)
#   market: Σ row price*quantity vs payments + overpay    0.0            == (exact)
#   market: tariff_on_activation vs independent sum       0.0            == (exact)
#   market: overpayment(0.10) - 2*overpayment(0.05)       0.0            == (exact)
#   market: pay-as-bid |Σ row quantity_t - Δ_t| /        2.11e-16       6.33e-16
#     Σ |row quantity_t| (peaked market fixture, K = 4,
#     per hour; the absolute maximum is 2.78e-17)
#   market: pay-as-bid payments vs Σ m·u - Σ g·w,         0.0            == (exact, by
#     summed in booking order                                            construction)
#   market: PAB minus uniform aggregator total            -7.1e-3        < 0 (strict; no
#     (largest value; held with no violation)                            slack)
#   liveness: Σ shortfall, K in (1, 2, 4, 8, 16)          9.03e-11       2.71e-10
#     (tight fixture, flat baseline; the K = 1 clear is
#     the largest, K >= 2 stay below 4.8e-12)
#   liveness: gap_16 = W* - welfare_socp_import           2.64e-4        7.92e-4
#   liveness: gap_{K'} - gap_K for K' > K (monotone        -3.74e-4       < 0 (strict; no
#     noise; largest value, held with no violation)                      slack)
#   liveness: welfare_socp_import - W* (upper bound        -1.55e-4       <= 0 (no slack)
#     noise; largest value, held with no violation)
#   price band: |π - λ| at activated (bus, hour), K = 16  3.06e-2        9.18e-2
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

    # ---- stage-2 fixtures ----
    const TOL_BUSNET = 6.67e-16
    const TOL_WASH = 2.11e-8

    # One Interruptible at bus 2 (φ = 1.0, so the stage-2 reactive draw is zero) whose seeded
    # interior baseline peaks in hour 2: p₀ = SHAPE + 0.1·demand, priced at π₀ = a − b·p₀.
    # `smax` puts the head branch 0.4·p₀[2] below the hour-2 consumption and well above the
    # other hours', so exactly hour 2 binds. `pdc_add` raises the inelastic demand (with
    # Pmin = 0 no bid can then bring the flow under a small smax).
    const SHAPE = (0.4, 1.6, 0.5)
    function tight_agg(seed; pdc_add = 0.0, T = T_INT)
        prof = generate_profiles(seed = seed + 2, T = T)
        a = 6.0 + 2.0 * prof.demand[1]
        bc = 0.5 + prof.demand[2]
        p0 = Float64[SHAPE[t] + 0.1 * prof.demand[t] for t in 1:T]
        π0 = Float64[a - bc * p0[t] for t in 1:T]
        Pdc = Float64[0.1 * prof.demand[t] + pdc_add for t in 1:T]
        agg = Aggregator(2, 1.0, AbstractDevice[Interruptible(2, 0.0, 2.0, a, bc)], Pdc)
        base = Float64[-p0[t] - Pdc[t] for t in 1:T]
        smax = (p0[2] + Pdc[2]) - 0.4 * p0[2]
        return (; agg, a, bc, p0, π0, Pdc, base, smax)
    end

    # Stage 2 on the tight fixture with K blocks over `feeder2(smax)`.
    function stage2(f, smax; K = 4, bids = nothing)
        fb =
            bids === nothing ? TSODSO.flex_bids(f.agg, f.base; T = T_INT, n_blocks = K) :
            bids
        s2 = TSODSO._stage2_aggregators([f.agg], [f.base], [fb]; T = T_INT)
        r = TSODSO._redispatch(feeder2(smax), ConvexBranchFlow(), s2; T = T_INT, λ₀ = f.π0)
        return (; fb, s2, r)
    end

    # An all-zero bid of K blocks over T hours.
    zero_bids(T, K) = TSODSO.FlexBids(
        zeros(T, K),
        zeros(T, K),
        zeros(T, K),
        zeros(T, K),
        0.0,
        0.0,
        Inf,
        0,
        0,
    )

    # ---- delivery fixtures ----
    const TOL_SEP = 9.17e-12
    const TOL_OVER = 2.09e-9
    const TOL_OVER_OTHER = 9.53e-9
    const TOL_WSENS = 3.79e-10

    # The physics pipeline on the tight fixture (baseline priced at π₀, λ₀ = π₀).
    tight_physics(f, smax; K = 4) = TSODSO._flex_physics(
        feeder2(smax),
        ConvexBranchFlow(),
        [f.agg],
        f.π0;
        T = T_INT,
        λ₀ = f.π0,
        n_blocks = K,
    )

    # ---- failure seam ----
    # A test-only device that wraps `inner` and counts its `contribute!` calls in `calls`. On
    # the call numbered `fail_at` it throws the `SolveFailedError` that `assert_solved!` throws
    # on a failed solve, instead of contributing, so a chosen solve fails deterministically
    # whatever the solver would do; every other call contributes `inner` unchanged.
    # `fail_at = 0` never fails (a counting dry run).
    struct FailAtCall{D <: AbstractDevice} <: AbstractDevice
        inner::D
        fail_at::Int
        calls::Base.RefValue{Int}
    end
    function TSODSO.contribute!(d::FailAtCall, ctx::TSODSO.ModelContext; T::Int, kwargs...)
        d.calls[] += 1
        d.calls[] == d.fail_at &&
            throw(SolveFailedError("injected failure at contribute! call $(d.fail_at)"))
        return TSODSO.contribute!(d.inner, ctx; T = T, kwargs...)
    end
    TSODSO.is_flexible_load(d::FailAtCall) = TSODSO.is_flexible_load(d.inner)

    # The Interruptible aggregator of the tight or market fixture `f` with its device wrapped in
    # `FailAtCall(fail_at)`; returns the aggregator and the wrapper (to read its call count).
    function failing_agg(f, fail_at)
        dev = FailAtCall(Interruptible(2, 0.0, 2.0, f.a, f.bc), Int(fail_at), Ref(0))
        return Aggregator(2, 1.0, AbstractDevice[dev], f.Pdc), dev
    end

    # ---- market fixtures ----
    const TOL_MKT_BAL = 1.37e-14

    # ---- liveness fixtures ----
    const LIVE_K = (1, 2, 4, 8, 16)
    const TOL_LIVE_SF = 2.71e-10
    const TOL_GAP16 = 7.92e-4
    const TOL_BAND = 9.18e-2

    # The market fixture: the tight Interruptible at bus 2 (φ = 1.0) with an inelastic peak of
    # `peak` pu in hour 2 and a head branch `head·p₀[2]` above that peak. Under the DADP run
    # (λ₀ = π₀) only hour 2 binds. The revenue-neutral flat baseline consumes about the same
    # flexible amount in every hour, so in hour 2 it overloads the branch and stage 2 must buy
    # UP-flex (less consumption) there: the congested hour has up-activation of a consuming
    # aggregator, which is what the β phantom needs. (On the plain tight fixture the flat
    # baseline sits below the hour-2 limit and stage 2 buys down-flex, so the phantom is 0.)
    function market_agg(seed; peak = 0.5, head = 0.15, pdc_add = 0.0, T = T_INT)
        prof = generate_profiles(seed = seed + 2, T = T)
        a = 6.0 + 2.0 * prof.demand[1]
        bc = 0.5 + prof.demand[2]
        p0 = Float64[SHAPE[t] + 0.1 * prof.demand[t] for t in 1:T]
        π0 = Float64[a - bc * p0[t] for t in 1:T]
        Pdc = Float64[0.1 * prof.demand[t] + (t == 2 ? peak : 0.0) + pdc_add for t in 1:T]
        agg = Aggregator(2, 1.0, AbstractDevice[Interruptible(2, 0.0, 2.0, a, bc)], Pdc)
        smax = Pdc[2] + head * p0[2]
        return (; agg, a, bc, p0, π0, Pdc, smax)
    end

    # The centralized welfare solve at a tight solver tolerance, used as the DADP run.
    cent_opt() =
        TSODSO.select_optimizer(TSODSO.SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)

    # The DADP run on `feeder2(smax)` and its packed settlement input.
    function market_dadp(f; smax = f.smax, optimizer = cent_opt())
        ctx, _, _ = solve_welfare(
            feeder2(smax),
            ConvexBranchFlow(),
            [f.agg];
            T = T_INT,
            λ₀ = f.π0,
            allow_export = true,
            optimizer = optimizer,
        )
        return (; ctx, input = settlement_input(ctx; T = T_INT, λ₀ = f.π0))
    end

    # One market clear on the fixture's own network.
    market_clear(f, input, fm; smax = f.smax, kw...) = clear_flex_market(
        feeder2(smax),
        ConvexBranchFlow(),
        [f.agg],
        input,
        fm;
        T = T_INT,
        λ₀ = f.π0,
        kw...,
    )

    # Independent Σ price·quantity of payment rows (any iterable of rows).
    function row_total(rows)
        s = 0.0
        for r in rows
            s += r.price * r.quantity
        end
        return s
    end

    # The pay-as-bid payment rows rebuilt from the accepted blocks, as (bus, t, price,
    # quantity) tuples: per hour, the non-zero up blocks (m_k, +u_k) then the non-zero down
    # blocks (g_k, −w_k).
    function pab_rows(fb, u, w, bus)
        out = Tuple{Int, Int, Float64, Float64}[]
        for t in axes(u, 1)
            for k in axes(u, 2)
                u[t, k] != 0 && push!(out, (bus, t, fb.up_m[t, k], u[t, k]))
            end
            for k in axes(w, 2)
                w[t, k] != 0 && push!(out, (bus, t, fb.dn_g[t, k], -w[t, k]))
            end
        end
        return out
    end

    # Largest relative |Σ_{rows of hour t} quantity − Δ[t]| over the hours, scaled by
    # Σ_{rows of hour t} |quantity| (the magnitude a floating-point sum's rounding error grows
    # with, so the bound does not depend on the size of the activation); an hour whose gap is
    # exactly 0 contributes 0, and a non-zero gap with no rows is Inf.
    function pab_quantity_relgap(rows, Δ)
        g = 0.0
        for t in eachindex(Δ)
            q = sum(r.quantity for r in rows if r.t == t; init = 0.0)
            gap = abs(q - Δ[t])
            gap == 0 && continue
            g = max(g, gap / sum(abs(r.quantity) for r in rows if r.t == t; init = 0.0))
        end
        return g
    end
    const TOL_PAB_QREL = 6.33e-16

    # Σ price·quantity over (bus, t, price, quantity) tuples, accumulated one row at a time in
    # their order, which is the order the settlement books and sums the payment rows.
    function tuple_money(rows)
        s = 0.0
        for (_, _, price, quantity) in rows
            s += price * quantity
        end
        return s
    end

    # Independent Σ_k Σ_t p_t·Δ_{k,t}.
    function activation_value(p, Δ)
        s = 0.0
        for d in Δ, t in eachindex(p)
            s += p[t] * d[t]
        end
        return s
    end

    # Calls `f()` and returns the exception it throws, or `nothing`.
    function caught(f)
        try
            f()
        catch err
            return err
        end
        return nothing
    end

    # Every number reachable from `x` is finite (records, vectors, bids).
    allfinite(x::Number) = isfinite(x)
    allfinite(x::Union{Symbol, AbstractString, Bool}) = true
    allfinite(x::AbstractArray) = all(allfinite, x)
    allfinite(x::NamedTuple) = all(allfinite, values(x))
    allfinite(x::TSODSO.FlexBids) =
        all(isfinite, x.up_q) &&
        all(isfinite, x.up_m) &&
        all(isfinite, x.dn_q) &&
        all(isfinite, x.dn_g) &&
        isfinite(x.V0)

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

@testitem "flex market: stage-2 pseudo-device validates its bids" setup =
    [FlexMarketFixtures] tags = [:flex_market] begin
    using TSODSO
    using TSODSO: FlexBidDevice
    M = FlexMarketFixtures

    g = [1.0, 2.0, 3.0]
    q = fill(0.5, 3, 2)
    p = fill(4.0, 3, 2)
    d = FlexBidDevice(g, q, p, q, p)
    @test d isa AbstractDevice
    @test d.gross == g && d.up_q == q && d.dn_g == p
    @test !TSODSO.is_flexible_load(d)
    @test TSODSO.storage_kind(d) === :none
    # sizes, finiteness, widths and the gross length are all guarded
    @test_throws ArgumentError FlexBidDevice(g, q, fill(4.0, 3, 3), q, p)
    @test_throws ArgumentError FlexBidDevice(g, q, p, fill(0.5, 2, 2), p)
    @test_throws ArgumentError FlexBidDevice([1.0, 2.0], q, p, q, p)
    @test_throws ArgumentError FlexBidDevice([1.0, NaN, 3.0], q, p, q, p)
    pn = copy(p)
    pn[2, 1] = Inf
    @test_throws ArgumentError FlexBidDevice(g, q, pn, q, p)
    qn = copy(q)
    qn[3, 2] = -1e-3
    @test_throws ArgumentError FlexBidDevice(g, q, p, qn, p)
    # the FlexBids convenience constructor copies the four matrices
    fb = M.zero_bids(3, 2)
    @test FlexBidDevice(g, fb).up_q == zeros(3, 2)

    # the pseudo-aggregators keep order, bus, φ and Pdc, and refuse what they cannot carry
    f = M.tight_agg(M.SEEDS[1])
    s2 = TSODSO._stage2_aggregators([f.agg], [f.base], [fb]; T = M.T_INT)
    @test length(s2) == 1
    @test s2[1].bus == f.agg.bus && s2[1].φ == f.agg.φ && s2[1].Pdc == f.agg.Pdc
    @test only(s2[1].devices).gross ≈ f.base .+ f.Pdc
    @test_throws ArgumentError TSODSO._stage2_aggregators(
        [f.agg],
        [f.base[1:2]],
        [fb];
        T = M.T_INT,
    )
    @test_throws ArgumentError TSODSO._stage2_aggregators(
        [f.agg],
        [f.base, f.base],
        [fb];
        T = M.T_INT,
    )
    cap = Aggregator(
        2,
        0.95,
        AbstractDevice[Interruptible(2, 0.0, 2.0, 6.0, 1.0), FixedCapacitor(2, 0.1)],
        f.Pdc,
    )
    @test_throws ArgumentError TSODSO._stage2_aggregators(
        [cap],
        [f.base],
        [fb];
        T = M.T_INT,
    )
    a3 = Aggregator(3, 1.0, AbstractDevice[Interruptible(3, 0.0, 2.0, 6.0, 1.0)], f.Pdc)
    @test_throws ArgumentError TSODSO._stage2_aggregators(
        [a3, f.agg],
        [f.base, f.base],
        [fb, fb];
        T = M.T_INT,
    )
end

@testitem "flex market: stage-2 redispatch clears the tight fixture" setup =
    [FlexMarketFixtures] tags = [:flex_market] begin
    using TSODSO
    M = FlexMarketFixtures

    function check(seed)
        f = M.tight_agg(seed)
        (; fb, r) = M.stage2(f, f.smax)
        r.status == "ok" || return (; ok = false, status = r.status)
        target = f.base .+ r.Δ[1]
        ch = TSODSO._congested_hours(r.ctx2, f.π0; T = M.T_INT)
        # the accepted quantities stay inside the offered widths
        inside =
            all(r.u[1] .>= -M.TOL_WASH) &&
            all(r.u[1] .<= fb.up_q .+ M.TOL_WASH) &&
            all(r.w[1] .>= -M.TOL_WASH) &&
            all(r.w[1] .<= fb.dn_q .+ M.TOL_WASH)
        return (;
            ok = true,
            r,
            ch,
            inside,
            dnet = maximum(abs.(r.input2.bus_nets[2] .- target)),
        )
    end
    for seed in M.SEEDS
        c = check(seed)
        @test c.ok
        c.ok || continue
        r = c.r
        @test r.notes == ""
        @test isfinite(r.maxgap) && r.maxgap >= 0
        @test r.input2 isa TSODSO.SettlementInput
        @test all(isfinite, r.input2.prices)
        @test size(r.input2.prices) == (1, M.T_INT)
        @test c.dnet <= M.TOL_BUSNET
        @test c.inside
        # the binding hour is relieved by accepted up-flex (less consumption)
        @test r.Δ[1][2] > 0.1
        @test r.max_wash <= M.TOL_WASH
        # exactly the binding hour is congested, robustly so
        @test c.ch.congested == [false, true, false]
        @test c.ch.kappa_lo < TSODSO.FLEX_CONGESTION_KAPPA < c.ch.kappa_hi
        @test length(c.ch.scores) == M.T_INT
    end

    # no thermal limit: nothing is congested and the upper end of the interval is open
    function check_free(seed)
        f = M.tight_agg(seed)
        (; r) = M.stage2(f, TSODSO.SMAX_NO_LIMIT)
        ch = r.status == "ok" ? TSODSO._congested_hours(r.ctx2, f.π0; T = M.T_INT) : nothing
        return (; r, ch)
    end
    for seed in M.SEEDS
        c = check_free(seed)
        @test c.r.status == "ok"
        c.r.status == "ok" || continue
        @test c.ch.congested == falses(M.T_INT)
        @test c.ch.kappa_hi == Inf
        @test c.ch.kappa_lo < TSODSO.FLEX_CONGESTION_KAPPA
        @test c.r.max_wash <= M.TOL_WASH
    end

    # an explicit optimizer reproduces the default call
    f = M.tight_agg(M.SEEDS[1])
    fb = TSODSO.flex_bids(f.agg, f.base; T = M.T_INT, n_blocks = 4)
    s2 = TSODSO._stage2_aggregators([f.agg], [f.base], [fb]; T = M.T_INT)
    r0 = TSODSO._redispatch(
        M.feeder2(f.smax),
        ConvexBranchFlow(),
        s2;
        T = M.T_INT,
        λ₀ = f.π0,
    )
    r1 = TSODSO._redispatch(
        M.feeder2(f.smax),
        ConvexBranchFlow(),
        s2;
        T = M.T_INT,
        λ₀ = f.π0,
        optimizer = TSODSO.select_optimizer(TSODSO.problem_class(ConvexBranchFlow())),
    )
    @test r1.status == "ok"
    @test r1.Δ == r0.Δ
    @test r1.input2.prices == r0.input2.prices
    @test_throws ArgumentError TSODSO._congested_hours(r0.ctx2, f.π0[1:2]; T = M.T_INT)
    @test_throws ArgumentError TSODSO._congested_hours(r0.ctx2, -f.π0; T = M.T_INT)
end

@testitem "flex market: stage-2 failures are statuses" setup = [FlexMarketFixtures] tags =
    [:flex_market] begin
    using TSODSO
    using TSODSO: SolveFailedError, CertificateError, ConvergenceError
    import JuMP
    M = FlexMarketFixtures

    # all-zero widths on a feasible network: nothing moves, exactly
    f = M.tight_agg(M.SEEDS[1])
    zb = M.zero_bids(M.T_INT, 4)
    z = M.stage2(f, TSODSO.SMAX_NO_LIMIT; bids = zb).r
    @test z.status == "ok"
    @test z.Δ[1] == zeros(M.T_INT)
    @test z.u[1] == zeros(M.T_INT, 4) && z.w[1] == zeros(M.T_INT, 4)
    @test z.max_wash == 0.0
    # ... and on the tight network the unrelieved baseline is infeasible
    zt = M.stage2(f, f.smax; bids = zb).r
    @test zt.status == "infeasible_redispatch"

    # an offer that cannot restore the limit: inelastic demand alone exceeds smax
    function infeasible(seed)
        g = M.tight_agg(seed; pdc_add = 2.0)
        return M.stage2(g, 1.0).r
    end
    for seed in M.SEEDS
        r = infeasible(seed)
        @test r.status == "infeasible_redispatch"
        @test !isempty(r.notes) && length(r.notes) <= 400
        @test r.ctx2 === nothing && r.input2 === nothing && r.Δ === nothing
    end

    # the mapping itself
    MOI = JuMP.MOI
    sfe(ts) = SolveFailedError("x", ts, MOI.NO_SOLUTION, MOI.NO_SOLUTION, "")
    @test TSODSO._redispatch_status(sfe(MOI.INFEASIBLE))[1] == "infeasible_redispatch"
    @test TSODSO._redispatch_status(sfe(MOI.INFEASIBLE_OR_UNBOUNDED))[1] ==
          "infeasible_redispatch"
    @test TSODSO._redispatch_status(sfe(MOI.NUMERICAL_ERROR))[1] == "error:SolveFailedError"
    @test TSODSO._redispatch_status(CertificateError("gap"; kind = :socp_exact))[1] ==
          "inexact_redispatch"
    @test TSODSO._redispatch_status(CertificateError("batt"; kind = :battery))[1] ==
          "error:CertificateError"
    @test TSODSO._redispatch_status(ConvergenceError("admm"))[1] == "error:ConvergenceError"
    @test TSODSO._redispatch_status(ArgumentError("bad input")) === nothing
    long = TSODSO._redispatch_status(CertificateError(repeat("a", 900); kind = :socp_exact))
    @test length(long[2]) == 400
end

@testitem "flex market: delivery tracks targets and reports shortfall" setup =
    [FlexMarketFixtures] tags = [:flex_market] begin
    using TSODSO
    M = FlexMarketFixtures

    function check(seed)
        f = M.tight_agg(seed)
        ph = M.tight_physics(f, f.smax)
        ph.status == "ok" || return (; ok = false)
        fb = ph.bids[1]
        # over-reach: ask hour 2 for twice its whole up range
        R = sum(fb.up_q[2, :])
        tgt = copy(ph.baseline.net[1])
        tgt[2] += 2R
        d1 = TSODSO._deliver(f.agg, f.π0, tgt; T = M.T_INT, weight = ph.weight)
        d10 = TSODSO._deliver(f.agg, f.π0, tgt; T = M.T_INT, weight = 10 * ph.weight)
        return (; ok = true, f, ph, R, d1, d10)
    end
    for seed in M.SEEDS
        c = check(seed)
        @test c.ok
        c.ok || continue
        # separable targets are met
        @test c.ph.shortfall_total <= M.TOL_SEP
        @test sum(c.ph.shortfall[1]) == c.ph.shortfall_total
        @test isfinite(c.ph.shortfall_10w_total) && c.ph.shortfall_10w_total >= 0
        # an unreachable target: the shortfall is exactly the part beyond the range
        @test c.R > 0.5
        @test abs(c.d1.shortfall[2] - c.R) <= M.TOL_OVER
        @test c.d1.shortfall[1] <= M.TOL_OVER_OTHER && c.d1.shortfall[3] <= M.TOL_OVER_OTHER
        @test maximum(abs.(c.d1.net .- c.d10.net)) <= M.TOL_WSENS
        # the delivery result speaks the price-taker vocabulary
        @test keys(c.d1) ==
              (:net, :utility, :battery_certificate, :battery_message, :shortfall)
        @test c.d1.battery_certificate === :not_checked
        @test c.d1.shortfall == abs.(c.d1.net .- (c.ph.baseline.net[1] .+ [0, 2c.R, 0]))
    end

    # guards
    f = M.tight_agg(M.SEEDS[1])
    p = f.π0
    @test_throws ArgumentError TSODSO._deliver(
        f.agg,
        p[1:2],
        f.base;
        T = M.T_INT,
        weight = 1.0,
    )
    @test_throws ArgumentError TSODSO._deliver(
        f.agg,
        p,
        f.base[1:2];
        T = M.T_INT,
        weight = 1.0,
    )
    @test_throws ArgumentError TSODSO._deliver(
        f.agg,
        p,
        [NaN, 0.0, 0.0];
        T = M.T_INT,
        weight = 1.0,
    )
    @test_throws ArgumentError TSODSO._deliver(f.agg, p, f.base; T = M.T_INT, weight = 0.0)
    @test_throws ArgumentError TSODSO._deliver(f.agg, p, f.base; T = M.T_INT, weight = Inf)
end

@testitem "flex market: delivery on a coupled aggregator" setup = [FlexMarketFixtures] tags =
    [:flex_market] begin
    using TSODSO
    M = FlexMarketFixtures

    function check(seed)
        c = M.coupled_agg(seed)
        pt = price_taker_dispatch(c.agg, c.price; T = M.T_CPL)
        smax = 0.9 * maximum(-pt.net)
        ph = TSODSO._flex_physics(
            M.feeder2(smax),
            ConvexBranchFlow(),
            [c.agg],
            c.price;
            T = M.T_CPL,
            λ₀ = c.price,
            n_blocks = 4,
        )
        ph.status == "ok" || return (; ph, wsens = NaN)
        d1 = TSODSO._deliver(c.agg, c.price, ph.targets[1]; T = M.T_CPL, weight = ph.weight)
        d10 = TSODSO._deliver(
            c.agg,
            c.price,
            ph.targets[1];
            T = M.T_CPL,
            weight = 10 * ph.weight,
        )
        return (; ph, wsens = maximum(abs.(d1.net .- d10.net)))
    end
    for seed in M.SEEDS
        r = check(seed)
        @test r.ph.status == "ok"
        r.ph.status == "ok" || continue
        @test any(r.ph.congested)
        @test r.ph.delivered.battery_certificate[1] in (:ok, :refused, :not_checked)
        @test r.ph.baseline.battery_certificate[1] in (:ok, :refused, :not_checked)
        @test r.ph.delivered.n_battery_ok +
              r.ph.delivered.n_battery_refused +
              r.ph.delivered.n_battery_not_checked == 1
        @test isfinite(r.ph.shortfall_total) && isfinite(r.ph.shortfall_10w_total)
        @test r.wsens <= M.TOL_WSENS
        @test r.ph.n_probe_solves == r.ph.bids[1].n_solves
    end
end

@testitem "flex market: physics pipeline statuses and fields" setup = [FlexMarketFixtures] tags =
    [:flex_market] begin
    using TSODSO
    using TSODSO: SolveFailedError, CertificateError
    M = FlexMarketFixtures

    fields = (
        :status,
        :notes,
        :price,
        :baseline,
        :bids,
        :u,
        :w,
        :Δ,
        :π,
        :congested,
        :congestion_scores,
        :kappa_lo,
        :kappa_hi,
        :targets,
        :delivered,
        :shortfall,
        :shortfall_total,
        :shortfall_10w_total,
        :weight,
        :maxgap,
        :p_import_stage2,
        :max_wash,
        :n_probe_solves,
        :n_probe_failed,
        :bid_repair_max,
        :min_bid_ask_gap,
        :wall_s,
    )

    function check(seed)
        f = M.tight_agg(seed)
        return (; f, ph = M.tight_physics(f, f.smax))
    end
    for seed in M.SEEDS
        c = check(seed)
        q = c.ph
        @test q.status == "ok"
        q.status == "ok" || continue
        @test keys(q) == fields
        @test all(k -> getfield(q, k) !== nothing, fields)
        @test M.allfinite(q)
        @test q.notes == ""
        @test q.price == c.f.π0
        @test q.n_probe_solves == sum(fb.n_solves for fb in q.bids)
        @test q.n_probe_failed == 0
        @test q.congested == [false, true, false]
        @test q.kappa_lo < TSODSO.FLEX_CONGESTION_KAPPA < q.kappa_hi
        @test q.targets[1] == q.baseline.net[1] .+ q.Δ[1]
        @test length(q.π[1]) == M.T_INT && length(q.p_import_stage2) == M.T_INT
        @test q.weight ==
              10 * max(maximum(abs, q.π[1]), maximum(c.f.π0), maximum(abs, c.f.π0))
        @test q.wall_s > 0
        @test q.max_wash <= M.TOL_WASH
    end

    # the 10w sensitivity diagnostic reproduces the record's total, and its own solver outcome
    # is (missing, note), never a throw; a malformed input still throws. The solver outcome is
    # injected by the FailAtCall seam (its first solve throws SolveFailedError), so no solver
    # behaviour on extreme data is assumed.
    f1 = M.tight_agg(M.SEEDS[1])
    ph1 = M.tight_physics(f1, f1.smax)
    redeliver(aggs, tg) = TSODSO._shortfall_diagnostic(
        aggs,
        ph1.price,
        tg;
        T = M.T_INT,
        weight = 10 * ph1.weight,
        τ_batt = 1e-3,
    )
    @test redeliver([f1.agg], ph1.targets) == (ph1.shortfall_10w_total, "")
    bad = redeliver([first(M.failing_agg(f1, 1))], ph1.targets)
    @test bad[1] === missing
    @test startswith(bad[2], "delivery at 10w (sensitivity diagnostic only")
    @test occursin("injected failure", bad[2])
    @test_throws ArgumentError redeliver([f1.agg], [ph1.targets[1][1:2]])

    # the same outcome inside a whole clear. A counting dry run gives the number of device
    # solves of the clear; the last one is the 10w diagnostic. Failing exactly that solve keeps
    # the clear "ok" with the primary delivery, puts the note in `notes` and leaves
    # `shortfall_10w_total` missing; failing the solve before it (the primary delivery) is a
    # "delivery: " status with no delivery.
    function injected(f, fail_at)
        agg, dev = M.failing_agg(f, fail_at)
        ph = TSODSO._flex_physics(
            M.feeder2(f.smax),
            ConvexBranchFlow(),
            [agg],
            f.π0;
            T = M.T_INT,
            λ₀ = f.π0,
            n_blocks = 4,
        )
        return (; ph, calls = dev.calls[])
    end
    dry = injected(f1, 0)
    @test dry.ph.status == "ok" && dry.ph.notes == ""
    # the wrapper is transparent: the dry run reproduces the plain clear
    @test dry.ph.delivered.net == ph1.delivered.net
    @test dry.ph.shortfall_total == ph1.shortfall_total
    @test dry.ph.shortfall_10w_total == ph1.shortfall_10w_total
    diag = injected(f1, dry.calls).ph
    @test diag.status == "ok"
    @test startswith(diag.notes, "delivery at 10w (sensitivity diagnostic only")
    @test occursin("injected failure", diag.notes)
    @test diag.shortfall_10w_total === missing
    @test diag.delivered.net == dry.ph.delivered.net
    @test diag.shortfall_total == dry.ph.shortfall_total
    @test diag.Δ == dry.ph.Δ && diag.weight == dry.ph.weight
    prim = injected(f1, dry.calls - 1).ph
    @test prim.status == "error:SolveFailedError"
    @test startswith(prim.notes, "delivery: injected failure")
    @test prim.delivered === nothing && prim.shortfall_10w_total === nothing

    # an offer that cannot restore the limit: a status, the bids known, no delivery
    function infeasible(seed)
        g = M.tight_agg(seed; pdc_add = 2.0)
        return M.tight_physics(g, 1.0)
    end
    for seed in M.SEEDS
        ph = infeasible(seed)
        @test ph.status == "infeasible_redispatch"
        @test !isempty(ph.notes)
        @test keys(ph) == fields
        @test ph.delivered === nothing && ph.shortfall === nothing && ph.Δ === nothing
        @test ph.π === nothing && ph.congested === nothing
        @test ph.baseline !== nothing && ph.bids !== nothing
        @test ph.n_probe_solves == sum(fb.n_solves for fb in ph.bids)
    end

    # guards, all before any solve
    f = M.tight_agg(M.SEEDS[1])
    fd = M.feeder2(f.smax)
    pf = ConvexBranchFlow()
    phys(aggs, p; kw...) =
        TSODSO._flex_physics(fd, pf, aggs, p; T = M.T_INT, λ₀ = f.π0, n_blocks = 4, kw...)
    @test_throws ArgumentError phys([f.agg], f.π0[1:2])
    @test_throws ArgumentError phys([f.agg], [f.π0[1], NaN, f.π0[3]])
    @test_throws ArgumentError phys([f.agg], f.π0; n_blocks = 0)
    @test_throws ArgumentError phys([f.agg], f.π0; λ₀ = f.π0[1:2])
    @test_throws ArgumentError phys(Aggregator[], f.π0)
    cap = Aggregator(
        2,
        0.95,
        AbstractDevice[Interruptible(2, 0.0, 2.0, 6.0, 1.0), FixedCapacitor(2, 0.1)],
        f.Pdc,
    )
    @test_throws ArgumentError phys([cap], f.π0)
    # the congested-hour split needs the SOCP handles and a positive λ₀: refused up front
    e_pf = M.caught(
        () -> TSODSO._flex_physics(
            fd,
            TSODSO.LinDistFlow(),
            [f.agg],
            f.π0;
            T = M.T_INT,
            λ₀ = f.π0,
            n_blocks = 4,
        ),
    )
    @test e_pf isa ArgumentError && occursin("ConvexBranchFlow", e_pf.msg)
    e_λ0 = M.caught(() -> phys([f.agg], f.π0; λ₀ = [f.π0[1], 0.0, f.π0[3]]))
    @test e_λ0 isa ArgumentError && occursin("positive", e_λ0.msg)
    e_λneg = M.caught(() -> phys([f.agg], f.π0; λ₀ = [f.π0[1], -1.0, f.π0[3]]))
    @test e_λneg isa ArgumentError && occursin("positive", e_λneg.msg)

    # a split reconstruction failure after stage 2 maps to a status; other errors do not. The
    # failure is raised by the real `decompose_dlmp` on a real gated stage-2 context: a
    # negative atol (a forcing seam, not a tolerance) makes its sum-to-price check fail, so a
    # reworded message in dlmp.jl that the mapper no longer accepts fails here.
    ctx2 = M.stage2(f, f.smax).r.ctx2
    e_split = M.caught(() -> TSODSO.decompose_dlmp(ctx2; atol = -1.0, rtol = 0.0))
    @test e_split isa ErrorException
    @test startswith(e_split.msg, TSODSO._DLMP_RECON_FAIL)
    s = TSODSO._congestion_status(e_split)
    @test s !== nothing && s[1] == "error:dlmp_split"
    @test s !== nothing && startswith(s[2], "congestion: " * TSODSO._DLMP_RECON_FAIL)
    # a malformed tree raises the split's own path-walk error, which is never mapped
    e_tree = M.caught(
        () -> TSODSO._path_branches((root = 1, branches = [(from = 1, to = 2)]), 3),
    )
    @test e_tree isa ErrorException && occursin("no parent branch", e_tree.msg)
    @test TSODSO._congestion_status(e_tree) === nothing
    @test TSODSO._congestion_status(SolveFailedError("no point")) ==
          ("error:SolveFailedError", "congestion: no point")
    @test TSODSO._congestion_status(ErrorException("unrelated")) === nothing
    @test TSODSO._congestion_status(ErrorException("decompose_dlmp: other")) === nothing
    @test TSODSO._congestion_status(ArgumentError(TSODSO._DLMP_RECON_FAIL)) === nothing

    # stage-1 and delivery outcomes map to prefixed statuses; anything else is not mapped
    s = TSODSO._physics_error_status(SolveFailedError("no point"), "baseline: ")
    @test s == ("error:SolveFailedError", "baseline: no point")
    s = TSODSO._physics_error_status(CertificateError("refused"; kind = :x), "delivery: ")
    @test s == ("error:CertificateError", "delivery: refused")
    @test TSODSO._physics_error_status(ArgumentError("bad"), "delivery: ") === nothing
end

@testitem "flex market: settlement record conserves for both rules and every β" setup =
    [FlexMarketFixtures] tags = [:flex_market] begin
    using TSODSO
    M = FlexMarketFixtures

    record_keys = (
        :status,
        :notes,
        :market,
        :baseline_price,
        :physics,
        :ledger,
        :feasibility,
        :payment_rows,
        :flex_payments_total,
        :baseline_overpayment,
        :tariff_on_activation,
        :flex_payment_on_delivered,
        :p_import_lossless,
        :bills,
        :surplus,
        :welfare_lossless,
        :welfare_socp_import,
    )

    function check(seed)
        f = M.market_agg(seed)
        input = M.market_dadp(f).input
        out = NamedTuple[]
        for rule in (:uniform, :pay_as_bid), β in (0.0, 0.05, 0.10)
            fm = FlexMarket(; payment_rule = rule, baseline_inflation = β)
            r = M.market_clear(f, input, fm)
            push!(out, (; rule, β, r, input))
        end
        return out
    end
    for seed in M.SEEDS, c in check(seed)
        r = c.r
        @test r.status == "ok"
        r.status == "ok" || continue
        @test keys(r) == record_keys
        @test r.market === FlexMarket(; payment_rule = c.rule, baseline_inflation = c.β)
        @test r.baseline_price == flat_prices(c.input)
        @test r.physics.price == r.baseline_price
        led = r.ledger
        @test led isa SettlementLedger
        @test ledger_residual(led) == 0.0
        @test abs(sum(values(led.balances))) <= M.TOL_MKT_BAL
        @test led.metadata.source === :flex_market
        # every payment row is a ledger flow: Σ price·quantity = payments + overpayment
        @test M.row_total(r.payment_rows) == r.flex_payments_total + r.baseline_overpayment
        # the ledger books the delivered nets at the baseline tariff and the lossless import
        n = r.physics.delivered.net[1]
        @test r.p_import_lossless == Float64[-n[t] for t in 1:M.T_INT]
        @test led.wholesale_payment ==
              sum(c.input.λ₀[t] * r.p_import_lossless[t] for t in 1:M.T_INT)
        # bills and surplus at bus granularity, from the ledger
        @test r.bills[2] == -led.balances[(:aggregator, 2)]
        @test r.surplus[2] ==
              r.physics.delivered.utility[1] + led.balances[(:aggregator, 2)]
        # welfare: utilities of the delivered dispatch minus wholesale on the import
        U = r.physics.delivered.utility[1]
        @test r.welfare_lossless ==
              U - sum(c.input.λ₀[t] * r.p_import_lossless[t] for t in 1:M.T_INT)
        @test r.welfare_socp_import ==
              U - sum(c.input.λ₀[t] * r.physics.p_import_stage2[t] for t in 1:M.T_INT)
        # the tariff-on-activation overlap is reported, independently recomputed
        @test r.tariff_on_activation == M.activation_value(r.baseline_price, r.physics.Δ)
        # the AC check is recorded, never a gate
        @test r.feasibility isa FeasibilityStatus
        @test r.feasibility.status in (:feasible, :infeasible, :solve_failed)
        # the uniform rule also reports the payment on the delivered deviation
        if c.rule === :uniform
            @test r.flex_payment_on_delivered isa Float64
            @test isfinite(r.flex_payment_on_delivered)
        else
            @test r.flex_payment_on_delivered === missing
        end
    end
end

@testitem "flex market: payment rules differ only in money" setup = [FlexMarketFixtures] tags =
    [:flex_market] begin
    using TSODSO
    M = FlexMarketFixtures

    function check(seed)
        f = M.market_agg(seed)
        input = M.market_dadp(f).input
        uni = M.market_clear(f, input, FlexMarket(; payment_rule = :uniform))
        pab = M.market_clear(f, input, FlexMarket(; payment_rule = :pay_as_bid))
        return (; uni, pab)
    end
    for seed in M.SEEDS
        c = check(seed)
        u, p = c.uni, c.pab
        @test u.status == "ok" && p.status == "ok"
        (u.status == "ok" && p.status == "ok") || continue
        # identical physics, computed independently
        @test u.physics.delivered.net == p.physics.delivered.net
        @test u.physics.Δ == p.physics.Δ
        @test u.welfare_lossless == p.welfare_lossless
        @test u.welfare_socp_import == p.welfare_socp_import
        @test u.feasibility.status == p.feasibility.status
        @test u.tariff_on_activation == p.tariff_on_activation
        # uniform: one row per activated (bus, hour) at the clearing price
        Δ = u.physics.Δ[1]
        @test [(r.bus, r.t) for r in u.payment_rows] == [(2, t) for t in 1:M.T_INT if Δ[t] != 0]
        @test all(r -> r.price == u.physics.π[1][r.t], u.payment_rows)
        @test all(r -> r.quantity == Δ[r.t], u.payment_rows)
        # pay-as-bid: every block with a non-zero accepted quantity at its own price (rejected
        # blocks carry interior-point noise of either sign, so the sign of a row does not tell
        # its direction; the quantities still sum to Δ)
        fb = p.physics.bids[1]
        pu, pw = p.physics.u[1], p.physics.w[1]
        @test all(r -> r.bus == 2, p.payment_rows)
        @test length(p.payment_rows) == count(!=(0.0), pu) + count(!=(0.0), pw)
        # each row is its own block at that block's price: up blocks (m_k, +u_k), then down
        # blocks (g_k, −w_k), hour by hour, so a row priced at another block or at the other
        # direction's price fails
        expect_rows = M.pab_rows(fb, pu, pw, 2)
        @test length(p.payment_rows) == length(expect_rows)
        @test all(
            ((r, e),) -> (r.bus, r.t, r.price, r.quantity) == e,
            zip(p.payment_rows, expect_rows),
        )
        # the row quantities of each hour add up to its activated deviation Δ, up to the
        # rounding of two different summation orders, relative to the summed magnitude
        @test M.pab_quantity_relgap(p.payment_rows, p.physics.Δ[1]) <= M.TOL_PAB_QREL
        # the money is Σ_k m_k·u_k − Σ_k g_k·w_k over the accepted blocks, accumulated in the
        # order the rows are booked (hour by hour, up blocks then down blocks), the order the
        # settlement sums them, so the equality is exact by construction
        @test p.flex_payments_total == M.tuple_money(expect_rows)
        # pay-as-bid moves money from aggregators to the DSO (held strictly on every seed)
        agg_total(r) = r.ledger.balances[(:aggregator, 2)]
        @test agg_total(p) < agg_total(u)
        @test p.flex_payments_total < u.flex_payments_total
        @test ledger_residual(p.ledger) == 0.0 && ledger_residual(u.ledger) == 0.0
    end

    # an offer that cannot restore the limit: a status record, never a throw
    function infeasible(seed)
        f = M.market_agg(seed)
        input = M.market_dadp(f; smax = TSODSO.SMAX_NO_LIMIT).input
        g = M.market_agg(seed; pdc_add = 2.0)
        return M.market_clear(g, input, FlexMarket(); smax = 1.0)
    end
    for seed in M.SEEDS
        r = infeasible(seed)
        @test r.status == "infeasible_redispatch"
        @test !isempty(r.notes)
        @test r.ledger === nothing && r.feasibility === nothing
        @test r.payment_rows === nothing
        @test r.flex_payments_total === missing && r.baseline_overpayment === missing
        @test r.welfare_lossless === missing && r.welfare_socp_import === missing
        @test r.physics.status == "infeasible_redispatch"
        @test r.baseline_price isa Vector{Float64}
    end

    # baseline-tariff resolution: TOU bins resolve only on the TOU path, before any solve
    f = M.market_agg(M.SEEDS[1])
    input = M.market_dadp(f).input
    tou =
        M.market_clear(f, input, FlexMarket(; baseline_tariff = :tou); bins = [[1, 2], [3]])
    @test tou.status == "ok"
    @test tou.baseline_price == tou_prices(input; bins = [[1, 2], [3]])
    @test ledger_residual(tou.ledger) == 0.0
    e_default = M.caught(() -> default_tou_bins(M.T_INT))
    # a NaN λ₀ would throw a different ArgumentError inside the physics: the bins message
    # proves the bins were resolved first
    e_clear = M.caught(
        () -> clear_flex_market(
            M.feeder2(f.smax),
            ConvexBranchFlow(),
            [f.agg],
            input,
            FlexMarket(; baseline_tariff = :tou);
            T = M.T_INT,
            λ₀ = [NaN, NaN, NaN],
        ),
    )
    @test e_default isa ArgumentError && e_clear isa ArgumentError
    @test e_clear.msg == e_default.msg
    # a flat clear ignores bins
    flat = M.market_clear(f, input, FlexMarket(); bins = [[1, 2], [3]])
    @test flat.baseline_price == flat_prices(input)

    # input guards, before any solve
    @test_throws ArgumentError clear_flex_market(
        M.feeder2(f.smax),
        ConvexBranchFlow(),
        [f.agg],
        input,
        FlexMarket();
        T = 2,
        λ₀ = f.π0[1:2],
    )
    other = Aggregator(3, 1.0, AbstractDevice[Interruptible(3, 0.0, 2.0, 6.0, 1.0)], f.Pdc)
    @test_throws ArgumentError clear_flex_market(
        M.feeder2(f.smax),
        ConvexBranchFlow(),
        [other],
        input,
        FlexMarket();
        T = M.T_INT,
        λ₀ = f.π0,
    )
    # every bus present but in descending order: refused by the entry guard, which names the
    # order (the stage-2 builder's own check would only fire after stage 1 and the probes)
    lo = Aggregator(1, 1.0, AbstractDevice[Interruptible(1, 0.0, 2.0, 6.0, 1.0)], f.Pdc)
    two = merge(
        input,
        (;
            buses = [1, 2],
            prices = vcat(input.prices, input.prices),
            bus_nets = Dict(1 => input.bus_nets[2], 2 => input.bus_nets[2]),
            bus_utilities = Dict(1 => input.bus_utilities[2], 2 => input.bus_utilities[2]),
        ),
    )
    e_ord = M.caught(
        () -> clear_flex_market(
            M.feeder2(f.smax),
            ConvexBranchFlow(),
            [f.agg, lo],
            two,
            FlexMarket();
            T = M.T_INT,
            λ₀ = f.π0,
        ),
    )
    @test e_ord isa ArgumentError
    @test e_ord isa ArgumentError && startswith(e_ord.msg, "clear_flex_market:")
    @test e_ord isa ArgumentError && occursin("ascending bus order", e_ord.msg)
    e_phys = M.caught(
        () -> TSODSO._flex_physics(
            M.feeder2(f.smax),
            ConvexBranchFlow(),
            [f.agg, lo],
            f.π0;
            T = M.T_INT,
            λ₀ = f.π0,
            n_blocks = 4,
        ),
    )
    @test e_phys isa ArgumentError && startswith(e_phys.msg, "_flex_physics:")
    @test e_phys isa ArgumentError && occursin("not ascending", e_phys.msg)
end

@testitem "flex market: baseline inflation changes money only" setup = [FlexMarketFixtures] tags =
    [:flex_market] begin
    using TSODSO
    M = FlexMarketFixtures

    function check(seed, rule)
        f = M.market_agg(seed)
        input = M.market_dadp(f).input
        rs = [
            M.market_clear(
                f,
                input,
                FlexMarket(; payment_rule = rule, baseline_inflation = β),
            ) for β in (0.0, 0.05, 0.10)
        ]
        return (; f, rs)
    end
    for seed in M.SEEDS, rule in (:uniform, :pay_as_bid)
        c = check(seed, rule)
        r0, r5, r10 = c.rs
        @test all(r -> r.status == "ok", c.rs)
        all(r -> r.status == "ok", c.rs) || continue
        # the congested hour is up-activated for a consuming aggregator
        ph = r0.physics
        @test ph.congested == [false, true, false]
        @test ph.Δ[1][2] > TSODSO.FLEX_RANGE_FLOOR
        @test ph.baseline.net[1][2] < 0
        # truthful: no phantom; inflated: a positive overpayment, linear in β
        @test r0.baseline_overpayment == 0.0
        @test r5.baseline_overpayment > 0
        @test r10.baseline_overpayment == 2 * r5.baseline_overpayment
        # the phantom rows are real ledger rows: one per congested up-activated hour
        @test length(r5.payment_rows) == length(r0.payment_rows) + 1
        @test r5.payment_rows[1:length(r0.payment_rows)] == r0.payment_rows
        extra = r5.payment_rows[end]
        @test extra.bus == 2 && extra.t == 2
        @test extra.quantity == 0.05 * (-ph.baseline.net[1][2])
        if rule === :uniform
            @test extra.price == ph.π[1][2]
        else
            fb = ph.bids[1]
            k = findlast(>(TSODSO.FLEX_RANGE_FLOOR), ph.u[1][2, :])
            @test extra.price == fb.up_m[2, k]
        end
        @test r5.flex_payments_total == r0.flex_payments_total
        @test ledger_residual(r5.ledger) == 0.0 && ledger_residual(r10.ledger) == 0.0
        @test r5.ledger.balances[(:aggregator, 2)] >= r0.ledger.balances[(:aggregator, 2)]
        # physics columns are identical across β
        for r in (r5, r10)
            @test r.physics.delivered.net == r0.physics.delivered.net
            @test r.welfare_lossless == r0.welfare_lossless
            @test r.welfare_socp_import == r0.welfare_socp_import
            @test r.feasibility.status == r0.feasibility.status
            @test r.feasibility.max_overload_ratio == r0.feasibility.max_overload_ratio
            @test r.tariff_on_activation == r0.tariff_on_activation
        end
    end
end

# The liveness fixture is the tight Interruptible (exactly hour-separable utility
# Σ_t a·p − b/2·p², φ = 1.0 so no reactive draw), with the DADP run as the centralized welfare
# solve at a tight solver tolerance and the flat baseline derived from it. Under the flat
# baseline every hour is activated (hours 1 and 3 by the energy-value correction, hour 2, the
# binding hour, by congestion relief), so the bid discretisation bites in every hour and the
# gap falls at every refinement. (On the peaked market fixture the gap plateaus over
# K = 1, 2, 4 because one hour only clears once its first block is narrow enough.)
@testitem "flex market: liveness against the centralized optimum (hour-separable)" setup =
    [FlexMarketFixtures] tags = [:flex_market] begin
    using TSODSO
    M = FlexMarketFixtures

    # The gap is the bid-discretisation gap: Interruptible is exactly hour-separable, so this
    # fixture has no hour-separability gap, and the truthful piecewise-linear bids converge to
    # the device's own value function as K grows. W* is SOCIAL WELFARE from utilities of the
    # centralized run (Σ bus utilities − λ₀ᵀ p_import through settlement_input), the same
    # convention as welfare_socp_import, never an objective value.
    function sweep(seed)
        f = M.tight_agg(seed)
        inC = M.market_dadp(f).input
        W =
            sum(values(inC.bus_utilities)) -
            sum(f.π0[t] * inC.p_import[t] for t in 1:M.T_INT)
        rs = [
            M.market_clear(f, inC, FlexMarket(; n_blocks = K); optimizer = M.cent_opt()) for K in M.LIVE_K
        ]
        ok = all(r -> r.status == "ok", rs)
        gaps = ok ? Float64[W - r.welfare_socp_import for r in rs] : Float64[]
        shortfall = ok ? Float64[r.physics.shortfall_total for r in rs] : Float64[]
        return (; W, rs, ok, gaps, shortfall)
    end
    for seed in M.SEEDS
        c = sweep(seed)
        @test c.ok
        c.ok || continue
        @test all(<=(M.TOL_LIVE_SF), c.shortfall)
        # the centralized optimum bounds the market from above
        @test all(>=(0.0), c.gaps)
        @test all(r -> r.welfare_socp_import <= c.W, c.rs)
        # the discretisation gap shrinks at every refinement and ends small
        @test all(i -> c.gaps[i + 1] < c.gaps[i], 1:(length(c.gaps) - 1))
        @test c.gaps[end] <= M.TOL_GAP16
        # liveness: the market is not vacuous, refining the bids actually closes the gap
        @test c.gaps[1] - c.gaps[end] > 0
        @test all(r -> r.market.n_blocks == size(r.physics.u[1], 2), c.rs)
    end
end

@testitem "flex market: clearing prices sit in a band around the DADP prices" setup =
    [FlexMarketFixtures] tags = [:flex_market] begin
    using TSODSO
    M = FlexMarketFixtures

    # At K = 16 the uniform clearing price π of each activated (bus, hour) is compared with the
    # DADP price λ of the same bus and hour. They are not the same object (π is the dual of the
    # stage-2 balance over piecewise-linear bids; λ is the DADP price of the device model), so
    # the check is a measured band, not an identity. Non-activated pairs are excluded: there π
    # is not unique inside the bid–ask gap.
    function band(seed)
        f = M.tight_agg(seed)
        inC = M.market_dadp(f).input
        r = M.market_clear(f, inC, FlexMarket(; n_blocks = 16); optimizer = M.cent_opt())
        r.status == "ok" || return (; ok = false)
        Δ = r.physics.Δ[1]
        act = [t for t in 1:M.T_INT if abs(Δ[t]) > TSODSO.FLEX_RANGE_FLOOR]
        row = findfirst(==(2), inC.buses)
        gap =
            isempty(act) ? NaN :
            maximum(abs(r.physics.π[1][t] - inC.prices[row, t]) for t in act)
        return (; ok = true, act, gap)
    end
    for seed in M.SEEDS
        c = band(seed)
        @test c.ok
        c.ok || continue
        @test !isempty(c.act)
        @test c.gap <= M.TOL_BAND
    end
end

# The comparison-table integration runs on the peaked market fixture (congested hour 2 is
# up-activated, so the β row has a phantom) with the default solver everywhere. Measured over
# the three seeds (julia 1.12.5): every flex row is ok; the pay-as-bid minus uniform aggregator
# total is −8.21e-3, −1.13e-2 and −7.05e-3 (strict, no slack); the per-bus bill and per-hour
# rebound delivery_shortfall columns sum to the summary total with a difference of exactly 0.0
# (asserted with ==).
@testitem "flex market: compare_tariffs appends flex rows" setup =
    [FlexMarketFixtures, FlexFenceFixtures] tags = [:flex_market, :settlement] begin
    using TSODSO
    using DataFrames
    M = FlexMarketFixtures
    F = FlexFenceFixtures

    fms = [
        FlexMarket(),
        FlexMarket(; payment_rule = :pay_as_bid),
        FlexMarket(; baseline_inflation = 0.05),
    ]
    flex_names = ["flex_uniform", "flex_pab", "flex_uniform_beta0.05"]
    extra = String[string(k) for k in TSODSO.FLEX_EXTRA_COLUMNS]
    @test keys(TSODSO._flex_extras()) == TSODSO.FLEX_EXTRA_COLUMNS
    @test all(ismissing, values(TSODSO._flex_extras()))
    @test length(extra) == 34

    function run_case(seed)
        f = M.market_agg(seed)
        cmp(; kw...) = compare_tariffs(
            M.feeder2(f.smax),
            ConvexBranchFlow(),
            [f.agg];
            T = M.T_INT,
            λ₀ = f.π0,
            bins = F.BINS,
            kw...,
        )
        r0 = cmp()
        r = cmp(; flex_market = fms)
        # the DADP run's settlement input, solved independently with the default optimizer
        input = M.market_dadp(f; optimizer = TSODSO.select_optimizer(TSODSO.SOCP())).input
        n = input.bus_nets[2]
        w_dadp = input.bus_utilities[2] - sum(f.π0[t] * (-n[t]) for t in 1:M.T_INT)
        return (; r0, r, w_dadp)
    end

    for seed in M.SEEDS
        c = run_case(seed)
        s, s0 = c.r.summary, c.r0.summary
        # schema: base rows untouched, flex rows appended with the additive columns
        @test nrow(s) == 7
        @test s.tariff == vcat(["dadp", "flat", "tou", "fit"], flex_names)
        @test names(s) == vcat(F.SUMMARY_COLUMNS, extra)
        @test isequal(s[1:4, F.SUMMARY_COLUMNS], s0)
        @test all(ismissing, s[1:4, :coordination])
        @test isequal(c.r.equity_breakouts, c.r0.equity_breakouts)

        fx = s[5:7, :]
        @test all(
            st ->
                st in ("ok", "infeasible_redispatch", "inexact_redispatch") ||
                startswith(st, "error:"),
            fx.status,
        )
        @test all(
            in(("feasible", "infeasible", "solve_failed", "not_run")),
            fx.feasibility_status,
        )
        @test all(==("ok"), fx.status)
        all(==("ok"), fx.status) || continue
        @test all(isfinite, fx.welfare)
        @test all(isfinite, fx.welfare_gap_vs_dadp_lossless)
        @test all(isfinite, fx.tariff_on_activation)
        # field mapping
        @test all(==("centralized"), fx.engine)
        @test all(==("flex_market"), fx.coordination)
        @test fx.payment_rule == ["uniform", "pay_as_bid", "uniform"]
        @test fx.baseline_inflation == [0.0, 0.0, 0.05]
        @test all(==("bus"), fx.bills_granularity)
        @test all(ismissing, fx.fairness_total)
        @test fx.total_payments == -fx.aggregators_total
        @test fx.merchandising_surplus == fx.dso_total
        @test fx.welfare_dadp_lossless == fill(c.w_dadp, 3)
        @test fx.welfare_gap_vs_dadp_lossless == fx.welfare .- fx.welfare_dadp_lossless
        @test fx.energy_merchandising_surplus ==
              fx.dso_total .+ fx.flex_payments_total .+ fx.baseline_overpayment
        @test fx.congestion_kappa == fill(TSODSO.FLEX_CONGESTION_KAPPA, 3)
        # uniform and pay-as-bid share the physics; pay-as-bid pays the aggregators less
        u, p, b = 1, 2, 3
        @test fx.welfare[u] == fx.welfare[p]
        @test fx.feasibility_status[u] == fx.feasibility_status[p]
        @test fx.aggregators_total[p] < fx.aggregators_total[u]
        # β changes money only: every physics column equals the uniform row's
        for col in (
            :welfare,
            :feasibility_status,
            :max_overload_ratio,
            :n_thermal_violations,
            :n_voltage_violations,
            :delivery_shortfall_total,
            :delivery_shortfall_max,
            :flex_up_total,
            :flex_down_total,
            :n_congested_hours,
            :welfare_socp_import,
            :redispatch_socp_maxgap,
            :redispatch_p_import_total,
            :tariff_on_activation,
            :flex_wall_s,
            :rebound_amount,
        )
            @test isequal(fx[b, col], fx[u, col])
        end
        @test fx.baseline_overpayment[u] == 0.0
        @test fx.baseline_overpayment[b] > 0

        # household bills: one bus row per flex tariff, with the additive shortfall column
        hb = c.r.household_bills
        n0 = nrow(c.r0.household_bills)
        @test isequal(hb[1:n0, names(c.r0.household_bills)], c.r0.household_bills)
        @test names(hb) == vcat(names(c.r0.household_bills), ["delivery_shortfall"])
        @test all(ismissing, hb.delivery_shortfall[1:n0])
        # rebound: T rows per flex tariff
        rbd = c.r.rebound
        m0 = nrow(c.r0.rebound)
        @test isequal(rbd[1:m0, names(c.r0.rebound)], c.r0.rebound)
        @test all(ismissing, rbd.delivery_shortfall[1:m0])
        for (k, nm) in enumerate(flex_names)
            bills_k = hb[hb.tariff .== nm, :]
            @test nrow(bills_k) == 1
            @test all(==("bus"), bills_k.granularity)
            @test sum(bills_k.bill) == fx.total_payments[k]
            @test sum(bills_k.delivery_shortfall) == fx.delivery_shortfall_total[k]
            reb_k = rbd[rbd.tariff .== nm, :]
            @test reb_k.t == collect(1:M.T_INT)
            @test sum(reb_k.delivery_shortfall) == fx.delivery_shortfall_total[k]
        end
    end

    # a failed redispatch is a status row with the identical field set and no bill or
    # rebound rows; appending it never changes the schema
    function status_case(seed)
        f = M.market_agg(seed)
        input = M.market_dadp(f; smax = TSODSO.SMAX_NO_LIMIT).input
        g = M.market_agg(seed; pdc_add = 2.0)
        return TSODSO._flex_tables(
            M.feeder2(1.0),
            ConvexBranchFlow(),
            [g.agg],
            input,
            FlexMarket[FlexMarket(), FlexMarket(; payment_rule = :pay_as_bid)];
            T = M.T_INT,
            λ₀vec = f.π0,
            bins = F.BINS,
            engine_str = "centralized",
            τ_batt = 1e-3,
        )
    end
    st = status_case(M.SEEDS[1])
    @test st.summary.status == ["infeasible_redispatch", "infeasible_redispatch"]
    @test st.summary.tariff == ["flex_uniform", "flex_pab"]
    @test names(st.summary) == vcat(F.SUMMARY_COLUMNS, extra)
    @test all(ismissing, st.summary.welfare)
    @test all(==("not_run"), st.summary.feasibility_status)
    @test all(!isempty, st.summary.notes)
    @test st.summary.payment_rule == ["uniform", "pay_as_bid"]
    @test nrow(st.household_bills) == 0 && nrow(st.rebound) == 0
    @test "delivery_shortfall" in names(st.household_bills)
    @test "delivery_shortfall" in names(st.rebound)

    # a failed 10w diagnostic reaches the table as an ok row, with the note and a missing
    # delivery_shortfall_total_10w: the FailAtCall seam fails the last device solve of the
    # clear (the diagnostic), located by a counting dry run of the same call
    function diag_tables(seed, fail_at)
        f = M.market_agg(seed)
        input = M.market_dadp(f).input
        agg, dev = M.failing_agg(f, fail_at)
        t = TSODSO._flex_tables(
            M.feeder2(f.smax),
            ConvexBranchFlow(),
            [agg],
            input,
            FlexMarket[FlexMarket()];
            T = M.T_INT,
            λ₀vec = f.π0,
            bins = F.BINS,
            engine_str = "centralized",
            τ_batt = 1e-3,
        )
        return (; s = t.summary, calls = dev.calls[])
    end
    dry_t = diag_tables(M.SEEDS[1], 0)
    @test dry_t.s.status == ["ok"] && dry_t.s.notes == [""]
    @test !ismissing(dry_t.s.delivery_shortfall_total_10w[1])
    dg = diag_tables(M.SEEDS[1], dry_t.calls).s
    @test dg.status == ["ok"]
    @test startswith(dg.notes[1], "delivery at 10w (sensitivity diagnostic only")
    @test ismissing(dg.delivery_shortfall_total_10w[1])
    @test dg.delivery_shortfall_total == dry_t.s.delivery_shortfall_total
    @test isequal(dg.welfare, dry_t.s.welfare)
    @test dg.feasibility_status == dry_t.s.feasibility_status
    ok = run_case(M.SEEDS[1]).r.summary
    @test names(vcat(ok, st.summary; cols = :union)) == names(ok)
    # the status-row builder and an ok row share one field set
    phys = (;
        status = "error:SolveFailedError",
        notes = "baseline: no point",
        bid_repair_max = nothing,
        min_bid_ask_gap = nothing,
        n_probe_solves = 0,
        n_probe_failed = 0,
        baseline = nothing,
        wall_s = 0.0,
    )
    row = TSODSO._flex_status_row(
        FlexMarket(),
        phys;
        engine_str = "centralized",
        T = M.T_INT,
        nb = 1,
        welfare_dadp_lossless = 0.0,
    )
    @test String[string(k) for k in propertynames(row)] == names(ok)
    @test row.status == "error:SolveFailedError" && row.baseline_batt_refused === missing
end
