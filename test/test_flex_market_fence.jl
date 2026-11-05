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
        ctx, _obj, _dadp =
            solve_welfare(f.feeder, ConvexBranchFlow(), f.aggs; T = T, λ₀ = f.λ₀, allow_export = true)
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

@testitem "flex market: default fence (digests)" setup = [ActorFenceDigest, FlexFenceFixtures] tags =
    [:settlement, :flex_market, :fence] begin
    using TSODSO
    F = FlexFenceFixtures
    fold = ActorFenceDigest.fold

    res = F.default_compare()
    d_summary = F.df_digest(fold, res.summary)
    d_bills = F.df_digest(fold, res.household_bills)
    d_breakouts = F.df_digest(fold, res.equity_breakouts)
    d_rebound = F.df_digest(fold, res.rebound)
    d_ledger = F.ledger_digest(fold, build_settlement_ledger(F.default_input()))
    @info "flex market fence digests" repr((d_summary, d_bills, d_breakouts, d_rebound, d_ledger))

    # One digest assertion for the whole fence (single version-gate skip record).
    if VERSION == v"1.12.5"
        @test (d_summary, d_bills, d_breakouts, d_rebound, d_ledger) == (0x51a1ed4c3c66413e, 0xf4e1569ddabc1b5f, 0x082f2207b4e88cc4, 0x5515555ce78f74e5, 0xe386f1abc04d04c8)
    else
        @test_skip (d_summary, d_bills, d_breakouts, d_rebound, d_ledger) == (0x51a1ed4c3c66413e, 0xf4e1569ddabc1b5f, 0x082f2207b4e88cc4, 0x5515555ce78f74e5, 0xe386f1abc04d04c8)
    end
end
