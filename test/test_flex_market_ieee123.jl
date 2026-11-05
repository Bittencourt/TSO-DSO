# test/test_flex_market_ieee123.jl
#
# Seam: the flexibility-market leg of `compare_tariffs` on the modified IEEE-123 feeder, with the
# certified fixture population and the documented tol_gap = 3e-9 welfare conditioning
# (test/test_ieee123_admm.jl explains why the default tolerance trips the exactness gate on this
# feeder at the precision floor; the gate itself is unchanged).
#
# Smoke contract: the outcome is RECORDED, never a crash. On the ok path the flex_uniform row
# exists exactly once and carries statuses from the documented sets. A DADP refusal is accepted
# only as one of the two documented refusal classes (SolveFailedError, CertificateError); any
# other error propagates. No welfare number is pinned and "feasible" is never asserted.

@testitem "flex market: IEEE-123 smoke (outcome recorded)" tags =
    [:flex_market, :slow, :ieee123] setup = [IEEE123Fixtures] begin
    using TSODSO
    using TSODSO: SOCP, CertificateError, SolveFailedError

    feeder = ieee123_modified()
    aggs = IEEE123Fixtures.build_ieee123_aggregators(feeder)
    outcome = try
        (;
            ok = true,
            res = compare_tariffs(
                feeder,
                ConvexBranchFlow(),
                aggs;
                T = 24,
                λ₀ = IEEE123Fixtures.ieee123_lambda0(),
                engine = :centralized,
                welfare_optimizer = select_optimizer(
                    SOCP();
                    tol_gap_abs = 3e-9,
                    tol_gap_rel = 3e-9,
                ),
                flex_market = FlexMarket(),
            ),
            err = nothing,
        )
    catch err
        (err isa SolveFailedError || err isa CertificateError) || rethrow()
        (; ok = false, res = nothing, err = err)
    end

    if outcome.ok
        tariffs = outcome.res.summary.tariff
        # Non-vacuous ok path: the flex row must exist exactly once.
        @test count(==("flex_uniform"), tariffs) == 1
        k = findfirst(==("flex_uniform"), tariffs)
        st = outcome.res.summary.status[k]
        fs = outcome.res.summary.feasibility_status[k]
        @test st in ("ok", "infeasible_redispatch", "inexact_redispatch") ||
              startswith(st, "error:")
        @test fs in ("feasible", "infeasible", "solve_failed", "not_run")
        @info "IEEE-123 flex smoke: flex_uniform recorded" status = st feasibility = fs
    else
        @test outcome.err isa SolveFailedError || outcome.err isa CertificateError
        @info "IEEE-123 flex smoke: DADP refused (a recorded outcome)" error =
            sprint(showerror, outcome.err)
    end
end
