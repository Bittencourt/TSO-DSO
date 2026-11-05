# test/test_flex_market_ieee.jl
#
# Seam: the flexibility-market legs of `compare_tariffs` on the IEEE-13 ground fixture.
#
# The slow item runs the comparison with two flex legs (uniform and pay-as-bid, flat baseline)
# and asserts only status-set membership and finiteness: the flex outcome on this fixture is a
# measured result, so no welfare value and no "feasible" verdict is pinned here. The committed
# measurement itself lives in results/settlement_comparison/ (scripts/tariff_comparison.jl).
#
# The fast item reads that committed measurement and checks its invariants: the expected rows
# exist, the statuses are in the documented sets, the base rows were not back-filled (the FIT
# error row in particular), beta changes money only, and the per-bus and per-hour shortfall
# columns add up to the summary total.
#
# Measured tolerances (committed CSVs, Julia 1.12.5):
#   - per-bus bill shortfall sum vs delivery_shortfall_total: 0.0 on every flex row (exact,
#     asserted with ==);
#   - per-hour rebound shortfall sum vs delivery_shortfall_total: at most 1.87e-16 relative
#     (summation order: buses within an hour, then hours), so the pinned rtol is 6e-16, three
#     times the observed maximum.

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
        s in ("ok", "infeasible_redispatch", "inexact_redispatch") ||
        startswith(s, "error:")
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

@testitem "flex market: committed comparison CSV rows" tags = [:flex_market] begin
    using TSODSO
    using CSV
    using DataFrames: DataFrame, eachrow, nrow

    dir = joinpath(pkgdir(TSODSO), "results", "settlement_comparison")
    summ = DataFrame(CSV.File(joinpath(dir, "tariff_comparison.csv")))
    bills = DataFrame(CSV.File(joinpath(dir, "household_bills.csv")))
    reb = DataFrame(CSV.File(joinpath(dir, "rebound_hourly.csv")))
    rows(df, mode) = filter(r -> isequal(r.mode, mode), df)
    isflex(r) = startswith(String(r.tariff), "flex_")

    # The ieee13-ground flex rows: all 8 legs, or ONLY the flex-scoped status row "flex_(run)"
    # of a stopped flex run (`--record-timeout S --flex-market`), never a mix.
    g = rows(summ, "ieee13-ground")
    g13flex = Set(String(t) for t in g.tariff if startswith(String(t), "flex_"))
    g13legs = Set([
        "flex_uniform",
        "flex_uniform_beta0.05",
        "flex_uniform_beta0.1",
        "flex_pab",
        "flex_pab_beta0.05",
        "flex_pab_beta0.1",
        "flex_uniform_tou",
        "flex_pab_tou",
    ])
    @test g13flex == g13legs || g13flex == Set(["flex_(run)"])

    # ieee123: the base legs plus the 6 flex legs, or ONLY a run-level status row (a run owns
    # its mode's rows, so the two outcomes never mix).
    t123 = Set(String.(rows(summ, "ieee123").tariff))
    @test (
        t123 == Set([
            "dadp",
            "flat",
            "tou",
            "fit",
            "flex_uniform",
            "flex_uniform_beta0.05",
            "flex_uniform_beta0.1",
            "flex_pab",
            "flex_pab_beta0.05",
            "flex_pab_beta0.1",
        ])
    ) || (t123 == Set(["(run)"]))
    @test nrow(rows(summ, "ieee123-default")) >= 1

    # No stale rows: within one (mode, seed, t_horizon), a "(run)" row is the only summary row
    # and has no bill, breakout or rebound rows beside it; a "flex_(run)" row (a stopped flex
    # run) excludes the flex rows only: no flex leg row and no flex bill, breakout or rebound
    # row sits beside it, while the base rows stay; a mode with flex rows also has the dadp row
    # they were cleared against.
    brk = DataFrame(CSV.File(joinpath(dir, "equity_breakouts.csv")))
    function no_stale_rows(summ, others)
        ok = true
        n_run = 0
        n_flex_run = 0
        isflex_t(t) = startswith(String(t), "flex_")
        for k in unique((r.mode, r.seed, r.t_horizon) for r in eachrow(summ))
            own(df) = filter(r -> (r.mode, r.seed, r.t_horizon) == k, df)
            ts = String.(own(summ).tariff)
            if "(run)" in ts
                n_run += 1
                ok &= ts == ["(run)"]
                ok &= all(nrow(own(df)) == 0 for df in others)
            end
            if "flex_(run)" in ts
                n_flex_run += 1
                ok &= count(isflex_t, ts) == 1
                ok &= all(!any(isflex_t, own(df).tariff) for df in others)
            end
            any(isflex_t, ts) && (ok &= "dadp" in ts)
        end
        return ok, n_run, n_flex_run
    end
    stale_ok, n_run, _ = no_stale_rows(summ, (bills, brk, reb))
    @test stale_ok
    @test n_run >= 1   # the committed ieee123-default refusal row is checked, not skipped
    # the "flex_(run)" rule on synthetic tables (the committed tables need not hold one)
    syn(ts) = DataFrame(
        mode = fill("m", length(ts)),
        seed = fill(1, length(ts)),
        t_horizon = fill(24, length(ts)),
        tariff = String[ts...],
    )
    base = ["dadp", "flat", "tou", "fit"]
    @test no_stale_rows(syn(vcat(base, "flex_(run)")), (syn(base), syn(String[]))) ==
          (true, 0, 1)
    @test !first(no_stale_rows(syn(vcat(base, "flex_(run)", "flex_pab")), (syn(base),)))
    @test !first(no_stale_rows(syn(vcat(base, "flex_(run)")), (syn(["dadp", "flex_pab"]),)))
    @test !first(no_stale_rows(syn(["flex_(run)"]), (syn(String[]),)))

    # Statuses of every flex leg row are in the documented sets; ok rows have a finite
    # welfare. A "flex_(run)" row is the timeout record of a stopped flex run.
    flex = filter(r -> isflex(r) && String(r.tariff) != "flex_(run)", summ)
    flex_run = filter(r -> String(r.tariff) == "flex_(run)", summ)
    @test all(==("timeout"), flex_run.status)
    allowed_status(s) =
        s in ("ok", "infeasible_redispatch", "inexact_redispatch") ||
        startswith(s, "error:")
    @test all(allowed_status(String(s)) for s in flex.status)
    @test all(
        f in ("feasible", "infeasible", "solve_failed", "not_run") for
        f in flex.feasibility_status
    )
    @test all(isfinite(r.welfare) for r in eachrow(flex) if r.status == "ok")

    # The base rows are never back-filled: FIT's committed error row is unchanged and the
    # ieee13-ground base rows carry no run_wall_s.
    fit = filter(r -> r.tariff == "fit", g)
    @test nrow(fit) == 1
    @test fit.status[1] == "error:SolveFailedError"
    @test all(ismissing(r.run_wall_s) for r in eachrow(g) if !isflex(r))

    # Every row written by the new paths carries a finite, non-negative run_wall_s.
    new_rows = vcat(filter(isflex, g), rows(summ, "ieee123"), rows(summ, "ieee123-default"))
    @test nrow(new_rows) >= 9
    @test all(!ismissing(w) && isfinite(w) && w >= 0 for w in new_rows.run_wall_s)

    # Beta changes money only: within one (mode, payment_rule, baseline_tariff) group, the
    # welfare and the AC verdict are identical, and the overpayment does not decrease in beta.
    function beta_groups_ok(flex)
        gkeys = unique((r.mode, r.payment_rule, r.baseline_tariff) for r in eachrow(flex))
        ok = true
        for k in gkeys
            grp = filter(r -> (r.mode, r.payment_rule, r.baseline_tariff) == k, flex)
            grp = grp[sortperm(grp.baseline_inflation), :]
            ok &= all(isequal(w, grp.welfare[1]) for w in grp.welfare)
            ok &= all(f == grp.feasibility_status[1] for f in grp.feasibility_status)
            over = grp.baseline_overpayment
            if all(!ismissing, over)
                ok &= all(over[i + 1] >= over[i] for i in 1:(length(over) - 1))
            end
        end
        return ok, length(gkeys)
    end
    beta_ok, n_groups = beta_groups_ok(flex)
    @test beta_ok
    # ieee13-ground flat/tou x 2 rules (unless its flex run is a recorded timeout), ieee123
    # flat x 2 rules
    @test n_groups >= (g13flex == g13legs ? 4 : 2)

    # Shortfall persistence: per-bus bill rows and per-hour rebound rows carry
    # delivery_shortfall, and both add up to the summary total of the same (mode, tariff).
    @test hasproperty(bills, :delivery_shortfall)
    @test hasproperty(reb, :delivery_shortfall)
    function shortfall_sums_ok(flex, bills, reb)
        ok = true
        n = 0
        for r in eachrow(flex)
            r.status == "ok" || continue
            sel(df) =
                filter(x -> isequal(x.mode, r.mode) && isequal(x.tariff, r.tariff), df)
            b = sel(bills)
            h = sel(reb)
            ok &= nrow(b) > 0 && nrow(h) > 0
            ok &=
                all(!ismissing, b.delivery_shortfall) &&
                all(!ismissing, h.delivery_shortfall)
            tot = r.delivery_shortfall_total
            ok &= sum(b.delivery_shortfall) == tot
            ok &= isapprox(sum(h.delivery_shortfall), tot; rtol = 6e-16)
            n += 1
        end
        return ok, n
    end
    sums_ok, n_ok = shortfall_sums_ok(flex, bills, reb)
    @test sums_ok
    @test n_ok >= 1
    # The new bill and rebound rows belong to the flex legs or the IEEE-123 modes only.
    @test all(
        isflex(r) || startswith(String(r.mode), "ieee123") for
        r in eachrow(bills) if !ismissing(r.delivery_shortfall)
    )
    @test all(isflex(r) || startswith(String(r.mode), "ieee123") for r in eachrow(reb))
end
