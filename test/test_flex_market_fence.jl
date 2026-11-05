# test/test_flex_market_fence.jl
#
# Seam: the default (no flexibility market) output of `compare_tariffs` and the default
# `build_settlement_ledger` on the hermetic 2-bus T = 3 settlement fixture.
#
# DEFAULT-PATH FENCE. The golden FNV-1a digests below were captured BEFORE any src/ edit for the
# flexibility-market legs (`git diff -- src` empty at capture time) and are never re-pinned. They
# fold every column name and every cell of the four `compare_tariffs` tables (summary,
# household_bills, equity_breakouts, rebound), except the environment-dependent provenance
# columns `threads` and `blas_threads`, plus every field of every ledger transfer, the ledger
# balances (keys sorted by `string(key)`), `merchandising_surplus` and `wholesale_payment`.
#
# Captured: 2026-11-04, Julia 1.12.5, git HEAD ea30313 (src tree clean).
# The digests are valid only on Julia 1.12.5 (other patch releases drift numerically in the last
# bits), so the single digest assertion is gated on `VERSION == v"1.12.5"` and is a `@test_skip`
# elsewhere (one allowlisted record in expected_broken.txt). Re-pinning per Julia version would
# defeat a never-re-pinned fence. The fence is therefore NOT inert on other versions: the
# VERSION-INDEPENDENT assertions run on every Julia: the pinned 37-column summary list, the
# tariff row order dadp/flat/tou/fit, same-process `isequal` determinism of all four tables
# across two calls, and the default ledger's exact conservation and row count.
#
# The digest fold is the `ActorFenceDigest` testmodule of test_actor_default_fence.jl (reused,
# not copied; testmodules are global to the run). DataFrames are folded by the explicit
# column-wise helper below, never by the struct fallback (which would fold internal fields).
#
# SOFT-SCOPE RULE: accumulators live inside functions, never bare in a top-level `for`.

@testmodule FlexFenceFixtures begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    const T = 3
    const BINS = [[1, 2], [3]]

    # The pinned `_summary_row` field order (37 names).
    const SUMMARY_COLUMNS = [
        "tariff",
        "engine",
        "status",
        "notes",
        "welfare",
        "total_payments",
        "fairness_total",
        "merchandising_surplus",
        "dso_total",
        "aggregators_total",
        "wholesale_total",
        "feasibility_status",
        "n_thermal_violations",
        "n_voltage_violations",
        "max_overload_ratio",
        "batt_ok",
        "batt_refused",
        "batt_not_checked",
        "gini_bills",
        "theil_bills",
        "theil_n_excluded_bills",
        "atkinson_bills",
        "atkinson_n_excluded_bills",
        "palma_bills",
        "gini_surplus",
        "theil_surplus",
        "theil_n_excluded_surplus",
        "atkinson_surplus",
        "atkinson_n_excluded_surplus",
        "palma_surplus",
        "rebound_amount",
        "rebound_ratio",
        "bills_granularity",
        "julia_version",
        "threads",
        "blas_threads",
        "t_horizon",
    ]

    # Hermetic 2-bus T = 3 fixture (the compare_tariffs settlement fixture).
    function two_bus()
        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
        agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
        λ₀ = fill(40.0, T)
        return (; feeder, aggs = [agg], λ₀)
    end

    # The default four-leg comparison (no opt-in keyword).
    function default_compare()
        f = two_bus()
        return compare_tariffs(
            f.feeder,
            ConvexBranchFlow(),
            f.aggs;
            T = T,
            λ₀ = f.λ₀,
            engine = :centralized,
            bins = BINS,
        )
    end

    # The default DADP settlement input (same solve as the comparison's centralized leg).
    function default_input()
        f = two_bus()
        ctx, _obj, _dadp = solve_welfare(
            f.feeder,
            ConvexBranchFlow(),
            f.aggs;
            T = T,
            λ₀ = f.λ₀,
            allow_export = true,
        )
        return settlement_input(ctx; T = T, λ₀ = f.λ₀)
    end

    const EXCLUDED_COLUMNS = ("threads", "blas_threads")

    # Column-wise DataFrame digest: kept column names, then each kept column's cells in order.
    function df_digest(fold, df)
        kept = [c for c in names(df) if !(c in EXCLUDED_COLUMNS)]
        h = fold(0xcbf29ce484222325, kept)
        for c in kept
            h = fold(h, df[!, c])
        end
        return h
    end

    # Ledger digest: transfers field by field, balances by sorted key, then the two named lines.
    function ledger_digest(fold, led)
        h = 0xcbf29ce484222325
        for tr in led.transfers
            for f in fieldnames(TSODSO.Transfer)
                h = fold(h, getfield(tr, f))
            end
        end
        for k in sort!(collect(keys(led.balances)); by = string)
            h = fold(fold(h, k), led.balances[k])
        end
        h = fold(h, led.merchandising_surplus)
        return fold(h, led.wholesale_payment)
    end
end

@testitem "flex market: default fence (schema and determinism)" setup = [FlexFenceFixtures] tags =
    [:settlement, :flex_market, :fence] begin
    using TSODSO
    F = FlexFenceFixtures

    r1 = F.default_compare()
    r2 = F.default_compare()

    @test names(r1.summary) == F.SUMMARY_COLUMNS
    @test length(F.SUMMARY_COLUMNS) == 37
    @test r1.summary.tariff == ["dadp", "flat", "tou", "fit"]
    # isequal, not ==: the dadp row's rebound_ratio is NaN by construction, and cells may be missing.
    @test isequal(r1.summary, r2.summary)
    @test isequal(r1.household_bills, r2.household_bills)
    @test isequal(r1.equity_breakouts, r2.equity_breakouts)
    @test isequal(r1.rebound, r2.rebound)

    input = F.default_input()
    l1 = build_settlement_ledger(input)
    l2 = build_settlement_ledger(input)
    @test l1.transfers == l2.transfers
    @test l1.balances == l2.balances
    @test l1.merchandising_surplus == l2.merchandising_surplus
    @test l1.wholesale_payment == l2.wholesale_payment
    @test ledger_residual(l1) == 0.0
    @test length(l1.transfers) == 2 * (length(input.buses) * F.T + F.T)
end

@testitem "flex market: default fence (digests)" setup =
    [ActorFenceDigest, FlexFenceFixtures] tags = [:settlement, :flex_market, :fence] begin
    using TSODSO
    F = FlexFenceFixtures
    fold = ActorFenceDigest.fold

    res = F.default_compare()
    d_summary = F.df_digest(fold, res.summary)
    d_bills = F.df_digest(fold, res.household_bills)
    d_breakouts = F.df_digest(fold, res.equity_breakouts)
    d_rebound = F.df_digest(fold, res.rebound)
    d_ledger = F.ledger_digest(fold, build_settlement_ledger(F.default_input()))
    @info "flex market fence digests" repr((
        d_summary,
        d_bills,
        d_breakouts,
        d_rebound,
        d_ledger,
    ))

    # One digest assertion for the whole fence (single version-gate skip record).
    if VERSION == v"1.12.5"
        @test (d_summary, d_bills, d_breakouts, d_rebound, d_ledger) == (
            0x51a1ed4c3c66413e,
            0xf4e1569ddabc1b5f,
            0x082f2207b4e88cc4,
            0x5515555ce78f74e5,
            0xe386f1abc04d04c8,
        )
    else
        @test_skip (d_summary, d_bills, d_breakouts, d_rebound, d_ledger) == (
            0x51a1ed4c3c66413e,
            0xf4e1569ddabc1b5f,
            0x082f2207b4e88cc4,
            0x5515555ce78f74e5,
            0xe386f1abc04d04c8,
        )
    end
end

@testitem "flex market: ledger default unchanged" setup = [FlexFenceFixtures] tags =
    [:settlement, :flex_market, :fence] begin
    using TSODSO
    F = FlexFenceFixtures

    input = F.default_input()
    l0 = build_settlement_ledger(input)
    l1 = build_settlement_ledger(input; flex_payments = nothing)
    @test l1.transfers == l0.transfers
    @test l1.balances == l0.balances
    @test l1.merchandising_surplus == l0.merchandising_surplus
    @test l1.wholesale_payment == l0.wholesale_payment
    @test length(l1.transfers) == 2 * (length(input.buses) * F.T + F.T)
    # the same through the primitive entry point
    l2 = build_settlement_ledger(
        input.prices,
        input.bus_nets,
        input.bus_utilities,
        input.p_import,
        input.λ₀,
        input.buses;
        T = input.T,
        source = input.source,
        flex_payments = nothing,
    )
    @test l2.transfers == l0.transfers
    @test l2.balances == l0.balances
    @test l2.merchandising_surplus == l0.merchandising_surplus
    @test l2.wholesale_payment == l0.wholesale_payment
end

@testitem "flex market: comparison keywords default unchanged" setup = [FlexFenceFixtures] tags =
    [:settlement, :flex_market, :fence] begin
    using TSODSO
    F = FlexFenceFixtures

    f = F.two_bus()
    compare(; kw...) = compare_tariffs(
        f.feeder,
        ConvexBranchFlow(),
        f.aggs;
        T = F.T,
        λ₀ = f.λ₀,
        engine = :centralized,
        bins = F.BINS,
        kw...,
    )
    r0 = compare()
    r_fm = compare(; flex_market = nothing)
    r_wo = compare(; welfare_optimizer = nothing)
    r_both = compare(; flex_market = nothing, welfare_optimizer = nothing)
    for r in (r_fm, r_wo, r_both)
        @test names(r.summary) == F.SUMMARY_COLUMNS
        @test isequal(r.summary, r0.summary)
        @test isequal(r.household_bills, r0.household_bills)
        @test isequal(r.equity_breakouts, r0.equity_breakouts)
        @test isequal(r.rebound, r0.rebound)
    end
end

@testitem "flex market: welfare_optimizer contract and guards" setup =
    [FlexFenceFixtures, FlexMarketFixtures] tags = [:settlement, :flex_market, :fence] begin
    using TSODSO
    using JuMP
    F = FlexFenceFixtures
    M = FlexMarketFixtures

    # A factory that counts how many optimizers it built (one per model solve).
    function counting()
        n = Ref(0)
        factory = function ()
            n[] += 1
            return JuMP.MOI.instantiate(TSODSO.select_optimizer(TSODSO.SOCP()))
        end
        return (; n, factory)
    end

    # an explicit factory equal to the default reproduces the default DADP row
    f = F.two_bus()
    compare(; kw...) = compare_tariffs(
        f.feeder,
        ConvexBranchFlow(),
        f.aggs;
        T = F.T,
        λ₀ = f.λ₀,
        bins = F.BINS,
        kw...,
    )
    r0 = compare()
    r1 = compare(; welfare_optimizer = TSODSO.select_optimizer(TSODSO.SOCP()))
    @test r1.summary.status[1] == "ok"
    @test r1.summary.tariff[1] == "dadp"
    @test r1.summary.welfare[1] == r0.summary.welfare[1]

    # reach: the factory conditions the DADP solve and the one redispatch solve
    t = M.tight_agg(M.SEEDS[1])
    tight(aggs; kw...) = compare_tariffs(
        M.feeder2(t.smax),
        ConvexBranchFlow(),
        aggs;
        T = M.T_INT,
        λ₀ = t.π0,
        bins = F.BINS,
        kw...,
    )
    c = counting()
    rt = tight([t.agg]; welfare_optimizer = c.factory)
    @test c.n[] == 1
    @test rt.summary.tariff == ["dadp", "flat", "tou", "fit"]
    c2 = counting()
    rf = tight([t.agg]; flex_market = FlexMarket(), welfare_optimizer = c2.factory)
    @test c2.n[] == 2
    @test rf.summary.tariff == ["dadp", "flat", "tou", "fit", "flex_uniform"]

    # every guard fires before any solve: the counting factory is never called
    err(g) = M.caught(g)
    function refused(g)
        c0 = counting()
        e = err(() -> g(c0.factory))
        return (; e, n = c0.n[])
    end
    cap = Aggregator(
        2,
        1.0,
        AbstractDevice[Interruptible(2, 0.0, 2.0, t.a, t.bc), FixedCapacitor(2, 0.1)],
        t.Pdc,
    )
    cases = [
        ("admm", g -> tight([t.agg]; engine = :admm, welfare_optimizer = g)),
        (
            "houses",
            g -> tight(
                [t.agg];
                houses = [t.agg],
                map_rows = [(; pv_group = :none)],
                flex_market = FlexMarket(),
                welfare_optimizer = g,
            ),
        ),
        (
            "duplicate",
            g -> tight(
                [t.agg];
                flex_market = [FlexMarket(), FlexMarket()],
                welfare_optimizer = g,
            ),
        ),
        ("scalar", g -> tight([t.agg]; flex_market = 3, welfare_optimizer = g)),
        (
            "mixed",
            g -> tight([t.agg]; flex_market = [FlexMarket(), 3], welfare_optimizer = g),
        ),
        ("empty", g -> tight([t.agg]; flex_market = FlexMarket[], welfare_optimizer = g)),
        ("capacitor", g -> tight([cap]; flex_market = FlexMarket(), welfare_optimizer = g)),
        (
            "lindistflow",
            g -> compare_tariffs(
                M.feeder2(t.smax),
                TSODSO.LinDistFlow(),
                [t.agg];
                T = M.T_INT,
                λ₀ = t.π0,
                bins = F.BINS,
                flex_market = FlexMarket(),
                welfare_optimizer = g,
            ),
        ),
        (
            "zero_lambda0",
            g -> compare_tariffs(
                M.feeder2(t.smax),
                ConvexBranchFlow(),
                [t.agg];
                T = M.T_INT,
                λ₀ = [t.π0[1], 0.0, t.π0[3]],
                bins = F.BINS,
                flex_market = FlexMarket(),
                welfare_optimizer = g,
            ),
        ),
        (
            "negative_lambda0",
            g -> compare_tariffs(
                M.feeder2(t.smax),
                ConvexBranchFlow(),
                [t.agg];
                T = M.T_INT,
                λ₀ = [t.π0[1], -1.0, t.π0[3]],
                bins = F.BINS,
                flex_market = FlexMarket(),
                welfare_optimizer = g,
            ),
        ),
    ]
    for (label, g) in cases
        rr = refused(g)
        @test rr.e isa ArgumentError
        @test rr.n == 0
        rr.e isa ArgumentError && @test occursin("compare_tariffs", rr.e.msg)
    end
    # the admm refusal names its reason
    e_admm = refused(g -> tight([t.agg]; engine = :admm, welfare_optimizer = g)).e
    @test e_admm isa ArgumentError && occursin("solve_admm takes no optimizer", e_admm.msg)
    # the capacitor refusal comes from the comparison guard, not from the physics
    e_cap = refused(g -> tight([cap]; flex_market = FlexMarket(), welfare_optimizer = g)).e
    @test e_cap isa ArgumentError && occursin("FixedCapacitor", e_cap.msg)
    # a complete but descending aggregator order is refused before the DADP run
    lo = Aggregator(1, 1.0, AbstractDevice[Interruptible(1, 0.0, 2.0, t.a, t.bc)], t.Pdc)
    e_ord =
        refused(g -> tight([t.agg, lo]; flex_market = FlexMarket(), welfare_optimizer = g))
    @test e_ord.e isa ArgumentError && e_ord.n == 0
    @test e_ord.e isa ArgumentError && occursin("ascending bus order", e_ord.e.msg)
    @test e_ord.e isa ArgumentError && occursin("compare_tariffs", e_ord.e.msg)
    # the formulation and λ₀ refusals name their reasons
    e_pf = refused(g -> cases[end - 2][2](g)).e
    @test e_pf isa ArgumentError && occursin("ConvexBranchFlow", e_pf.msg)
    e_λ = refused(g -> cases[end - 1][2](g)).e
    @test e_λ isa ArgumentError && occursin("positive", e_λ.msg)
    # the same inputs without flex_market keep the default path (no new guard there)
    r_pf = compare_tariffs(
        M.feeder2(t.smax),
        TSODSO.LinDistFlow(),
        [t.agg];
        T = M.T_INT,
        λ₀ = t.π0,
        bins = F.BINS,
    )
    @test r_pf.summary.tariff == ["dadp", "flat", "tou", "fit"]
end
