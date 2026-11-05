# test/test_flex_market_ieee123.jl
#
# Seam: the flexibility-market leg of `compare_tariffs` on the modified IEEE-123 feeder, with the
# certified fixture population and the documented tol_gap = 3e-9 welfare conditioning
# (test/test_ieee123_admm.jl explains why the default tolerance trips the exactness gate on this
# feeder at the precision floor; the gate itself is unchanged).
#
# Smoke contract: the outcome is RECORDED, never a crash. The DADP solve runs first, on its own,
# with the same optimizer as the comparison. Only that solve may end in a refusal, and only in
# one of the two documented refusal classes (SolveFailedError, or a CertificateError from the
# SOCP exactness gate); any other error propagates. When the DADP solve is certified, the
# comparison runs OUTSIDE any try, so an error from any other leg (flat, TOU, FIT, or the flex
# leg itself) fails the item instead of passing as a refusal, and the flex row must exist
# exactly once with statuses from the documented sets. No welfare number is pinned and
# "feasible" is never asserted.

@testitem "flex market: IEEE-123 smoke (outcome recorded)" tags =
    [:flex_market, :slow, :ieee123] setup = [IEEE123Fixtures] begin
    using TSODSO
    using TSODSO: SOCP, CertificateError, SolveFailedError

    feeder = ieee123_modified()
    aggs = IEEE123Fixtures.build_ieee123_aggregators(feeder)
    λ₀ = IEEE123Fixtures.ieee123_lambda0()
    opt() = select_optimizer(SOCP(); tol_gap_abs = 3e-9, tol_gap_rel = 3e-9)

    # The DADP solve alone: the only place a refusal is accepted.
    dadp_refusal(err) =
        err isa SolveFailedError || (err isa CertificateError && err.kind === :socp_exact)
    function dadp_outcome()
        try
            solve_welfare(
                feeder,
                ConvexBranchFlow(),
                aggs;
                T = 24,
                λ₀ = λ₀,
                allow_export = true,
                optimizer = opt(),
            )
        catch err
            dadp_refusal(err) || rethrow()
            return err
        end
        return nothing
    end
    refusal = dadp_outcome()

    if refusal === nothing
        res = compare_tariffs(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = 24,
            λ₀ = λ₀,
            engine = :centralized,
            welfare_optimizer = opt(),
            flex_market = FlexMarket(),
        )
        tariffs = res.summary.tariff
        @test tariffs == ["dadp", "flat", "tou", "fit", "flex_uniform"]
        @test res.summary.status[1] == "ok"
        k = findfirst(==("flex_uniform"), tariffs)
        st = res.summary.status[k]
        fs = res.summary.feasibility_status[k]
        @test st in ("ok", "infeasible_redispatch", "inexact_redispatch") ||
              startswith(st, "error:")
        @test fs in ("feasible", "infeasible", "solve_failed", "not_run")
        @test isfinite(res.summary.flex_wall_s[k]) && res.summary.flex_wall_s[k] > 0
        if st == "ok"
            @test res.summary.n_probe_solves[k] > 0
            @test isfinite(res.summary.welfare[k])
            @test res.summary.delivery_shortfall_total[k] >= 0
        end
        @info "IEEE-123 flex smoke: flex_uniform recorded" status = st feasibility = fs
    else
        # A refusal of the DADP solve itself: the comparison's first solve is that same
        # DADP solve, so it must refuse with the same error type before any other leg runs.
        @test_throws typeof(refusal) compare_tariffs(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = 24,
            λ₀ = λ₀,
            engine = :centralized,
            welfare_optimizer = opt(),
            flex_market = FlexMarket(),
        )
        @info "IEEE-123 flex smoke: DADP refused (a recorded outcome)" error =
            sprint(showerror, refusal)
    end
end
