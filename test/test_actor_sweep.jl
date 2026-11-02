# test/test_actor_sweep.jl
#
# Seam: the committed measurement artifact results/actor_behaviour/actor_behaviour_sweep.csv
# produced by scripts/actor_behaviour_sweep.jl (plan 44-07, ACTOR-04 report). Slow tests (the
# reference-point reproduction re-solves an IEEE-13 ADMM wedge point, about 1 minute). Item
# names contain "actor sweep".
#
# Bands (never picked): the identity anchor (wedge 0 on IEEE-13) is bitwise equal to the
# unwrapped solve (44-02: ADMM Profit(0) == default, bitwise), so dW_abs is exactly 0; the
# reproduction band is the measured ADMM-vs-centralized relative welfare gap 1.24e-7
# (test_actor_objective.jl), the loosest quantity this artifact is compared at.

@testmodule ActorSweepCsv begin
    function read_csv(path)
        lines = readlines(path)
        header = String.(split(first(lines), ','))
        idx = Dict(h => i for (i, h) in enumerate(header))
        rows = [
            (f = split(ln, ','); Dict(h => String(strip(f[idx[h]])) for h in header)) for
            ln in lines[2:end]
        ]
        return header, rows
    end
    num(s) = (v = tryparse(Float64, s); v === nothing ? NaN : v)
    const REQUIRED = [
        "fixture", "wedge", "xi", "opt_out", "r", "seed", "verdict", "welfare",
        "actor_objective", "dW_abs", "dW_rel", "dadp_mean", "dadp_max", "ledger_total_aggregators",
        "ledger_residual", "rebound_amount", "rebound_ratio", "iters", "runtime_s",
    ]
    const REL_BAND = 1.24e-7
end

@testitem "actor sweep: committed CSV schema and verdicts" setup = [ActorSweepCsv] tags = [
    :actors, :slow
] begin
    using TSODSO
    path = joinpath(pkgdir(TSODSO), "results", "actor_behaviour", "actor_behaviour_sweep.csv")
    @test isfile(path)
    header, rows = ActorSweepCsv.read_csv(path)
    @test all(c -> c in header, ActorSweepCsv.REQUIRED)
    @test length(rows) >= 8
    @test all(r -> r["verdict"] == "ok" || startswith(r["verdict"], "refused:"), rows)
    @test all(r -> r["fixture"] in ("ieee123_behaviour", "ieee13_wedge"), rows)
    # both blocks present; key unique
    @test any(r -> r["fixture"] == "ieee123_behaviour", rows)
    @test count(r -> r["fixture"] == "ieee13_wedge", rows) >= 3
    keys_ = [join((r[k] for k in ("fixture", "wedge", "xi", "opt_out", "r", "seed")), "|") for r in rows]
    @test length(unique(keys_)) == length(rows)
    # finite welfare and exactly conserving ledger on every ok row
    for r in filter(r -> r["verdict"] == "ok", rows)
        @test isfinite(ActorSweepCsv.num(r["welfare"]))
        @test ActorSweepCsv.num(r["ledger_residual"]) == 0.0
        @test isfinite(ActorSweepCsv.num(r["dadp_mean"]))
        # rebound ratio is NaN exactly when there is no reduction hour
        nred = ActorSweepCsv.num(r["n_reduction_hours"])
        @test isnan(ActorSweepCsv.num(r["rebound_ratio"])) == (nred == 0)
    end
    # identity anchors: the IEEE-13 zero wedge and the unwrapped IEEE-123 point have dW = 0
    zero_wedge = filter(r -> r["fixture"] == "ieee13_wedge" && ActorSweepCsv.num(r["wedge"]) == 0.0, rows)
    @test length(zero_wedge) == 1
    @test ActorSweepCsv.num(zero_wedge[1]["dW_abs"]) == 0.0
    # a positive wedge never beats the welfare optimum beyond the measured slack
    for r in filter(r -> r["fixture"] == "ieee13_wedge" && r["verdict"] == "ok", rows)
        W = ActorSweepCsv.num(r["welfare"])
        @test ActorSweepCsv.num(r["dW_abs"]) >= -ActorSweepCsv.REL_BAND * abs(W)
    end
    # xi = 0 is the pure opt-out population: every xi = 0 row reports the same welfare
    xi0 = [ActorSweepCsv.num(r["welfare"]) for r in rows if r["fixture"] == "ieee123_behaviour" && ActorSweepCsv.num(r["xi"]) == 0.0 && r["verdict"] == "ok"]
    @test length(xi0) >= 2
    @test all(==(xi0[1]), xi0)
end

@testitem "actor sweep: reference wedge point reproduces by re-solving" setup =
    [ActorSweepCsv, IEEE13Fixtures] tags = [:actors, :slow] begin
    using TSODSO
    path = joinpath(pkgdir(TSODSO), "results", "actor_behaviour", "actor_behaviour_sweep.csv")
    _, rows = ActorSweepCsv.read_csv(path)
    ref = only(filter(r -> r["fixture"] == "ieee13_wedge" && ActorSweepCsv.num(r["wedge"]) == 0.5, rows))
    @test ref["verdict"] == "ok"

    function resolve_point()
        feeder = ieee13_modified()
        aggs = IEEE13Fixtures.build_ieee13_ground_aggregators(feeder)
        Th = IEEE13Fixtures.T
        λ₀ = IEEE13Fixtures.mem_price_profile()
        h = length(aggs) ÷ 2
        ports = [
            Portfolio(aggs[1:h]; objective = ProfitObjective(0.5), name = :a),
            Portfolio(aggs[(h + 1):end]; name = :b),
        ]
        kw = (T = Th, λ₀ = λ₀, ρ = 100.0, tol = 1e-6, maxiter = 700, ε_abs = 1e-6, ε_rel = 1e-7, allow_export = true)
        res = solve_admm(feeder, ConvexBranchFlow(), aggs; kw..., actors = ports)
        wrows = TSODSO.actor_wedge_rows(res, ports; T = Th)
        led = build_settlement_ledger(settlement_input(res; λ₀ = λ₀); actor_wedges = wrows)
        return (; res, led)
    end
    out = resolve_point()
    W = ActorSweepCsv.num(ref["welfare"])
    @test abs(out.res.welfare - W) <= ActorSweepCsv.REL_BAND * abs(W)
    @test out.res.iters == parse(Int, ref["iters"])
    @test isapprox(
        sum(out.res.dadp) / length(out.res.dadp), ActorSweepCsv.num(ref["dadp_mean"]);
        rtol = ActorSweepCsv.REL_BAND, atol = 0,
    )
    @test isapprox(
        out.led.balances[(:actor, 1)], ActorSweepCsv.num(ref["ledger_total_actor_1"]);
        atol = ActorSweepCsv.REL_BAND, rtol = 0,
    )
    @test ledger_residual(out.led) == 0.0
end
