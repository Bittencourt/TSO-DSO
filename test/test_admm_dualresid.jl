# test/test_admm_dualresid.jl
#
# Seam: the Boyd-correct two-residual ADMM stop.
#
# @testitem harness for the
# corrected dual residual `s = ρ·Δ(pag_dso)` (the z-block, superseding the earlier ρ·Δa
# diagnostic) and the primal+dual 2-norm per-unit STOP inside `solve_admm` — the tests are
# NEVER edited to go green. Every item name contains "dualresid" and "admm" so the test-name
# filters `occursin("dualresid", ti.name)` / `occursin("admm", ti.name)` select them.
#
# GATE (never a runner crash): the sole failing assertion is `isdefined(TSODSO, :set_rho!)`
# — the adaptive-ρ seam that lands together with the dual-residual correction.
# Every behavioral assert sits BEHIND that guard, so it goes live automatically once
# the seam exists (mirrors test_admm.jl's `isdefined(:solve_admm)` precedent).
#
# CONTRACT pinned here:
#   - `res.residuals.dual_trace` stores ‖s‖ = ρ·‖Δ(pag_dso)‖₂ (a REAL number, NOT the NaN the
#     earlier 4-arg `record!` pads — proving the extended 8-arg `record!` is now the call site).
#   - the loop stops iff BOTH ‖r‖ ≤ ε_pri AND ‖s‖ ≤ ε_dual (two-residual `converged`), so the
#     converged ledger satisfies the two-residual predicate at its final iterate.

@testitem "admm dualresid: z-block dual residual + two-residual stop (dualresid, admm)" setup =
    [IEEE123Fixtures, TwoBusFixtures] tags = [:admm, :adaptive] begin
    using TSODSO
    using TSODSO: converged

    # The dual-residual correction lands with the set_rho! seam.
    @test isdefined(TSODSO, :set_rho!)

    if isdefined(TSODSO, :set_rho!)
        feeder = TwoBusFixtures.two_bus_feeder()
        aggs = TwoBusFixtures.build_two_bus_aggregators(feeder)
        Th = TwoBusFixtures.T
        λ₀ = TwoBusFixtures.two_bus_lambda0()

        res = solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            ρ = IEEE123Fixtures.RHO0,
            ε_abs = IEEE123Fixtures.EPS_ABS,
            ε_rel = IEEE123Fixtures.EPS_REL,
            allow_export = true,
        )
        led = res.residuals

        # (a) the dual trace holds a REAL Boyd z-block residual (extended record! is now used —
        # NOT the NaN sentinel the earlier 4-arg overload pads).
        @test led.iters >= 1
        @test all(isfinite, led.dual_trace)
        @test all(isfinite, led.eps_pri_trace)
        @test all(isfinite, led.eps_dual_trace)

        # (b) the converged ledger satisfies the TWO-residual predicate at its final iterate
        # (primal AND dual below their per-unit thresholds) — the false-convergence net.
        @test converged(led, last(led.eps_pri_trace), last(led.eps_dual_trace))
        @test last(led.primal_trace) <= last(led.eps_pri_trace)
        @test last(led.dual_trace) <= last(led.eps_dual_trace)
    end
end

@testitem "admm dualresid: ledger two-residual converged predicate (dualresid, resid)" setup =
    [IEEE123Fixtures] tags = [:admm, :adaptive] begin
    using TSODSO
    using TSODSO: converged, record!

    # This item exercises the JuMP-free ledger contract directly (extended AdmmResiduals)
    # — it does NOT depend on solve_admm, so it pins the
    # two-residual `converged` semantics the dual-residual stop relies on.
    res = AdmmResiduals(2, IEEE123Fixtures.T)
    record!(res, 1, 1e-2, 1e-2, IEEE123Fixtures.RHO0, 1e-4, 1e-4, 0.5)   # both above ε
    @test converged(res, 1e-4, 1e-4) == false
    record!(res, 2, 1e-5, 5e-5, IEEE123Fixtures.RHO0, 1e-4, 1e-4, 1e-3)  # both below ε
    @test converged(res, 1e-4, 1e-4) == true
    @test converged(res, 1e-4, 1e-6) == false                          # dual above ⇒ not converged
end
