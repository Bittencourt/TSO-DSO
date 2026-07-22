# test/test_admm_dualresid.jl
#
# Seam: the Boyd-correct two-residual ADMM stop (ADMM-02, RESEARCH Pattern 2 & 3).
#
# RED @testitem harness (Wave 0 of Phase 7). Plan 07-04 turns these green by IMPLEMENTING the
# corrected dual residual `s = ρ·Δ(pag_dso)` (the z-block, superseding the Phase-6 ρ·Δa
# diagnostic) and the primal+dual 2-norm per-unit STOP inside `solve_admm` — the tests are
# NEVER edited to go green. Every item name contains "dualresid" and "admm" so the VALIDATION
# filters `occursin("dualresid", ti.name)` / `occursin("admm", ti.name)` select them.
#
# RED SIGNAL (never a runner crash): the sole failing assertion is `isdefined(TSODSO, :set_rho!)`
# — the Wave-2/3 adaptive-ρ seam (07-03) that lands together with the dual-residual correction
# (07-04). Every behavioral assert sits BEHIND that guard, so it goes live automatically once
# the seam exists (mirrors test_admm.jl's `isdefined(:solve_admm)` precedent).
#
# CONTRACT pinned here (RESEARCH Pattern 2/3):
#   - `res.residuals.dual_trace` stores ‖s‖ = ρ·‖Δ(pag_dso)‖₂ (a REAL number, NOT the NaN the
#     Phase-6 4-arg `record!` pads — proving the extended 8-arg `record!` is now the call site).
#   - the loop stops iff BOTH ‖r‖ ≤ ε_pri AND ‖s‖ ≤ ε_dual (two-residual `converged`), so the
#     converged ledger satisfies the two-residual predicate at its final iterate.

@testitem "admm dualresid: z-block dual residual + two-residual stop (dualresid, admm)" setup =
    [Phase7Fixtures, Phase6Fixtures] tags = [:admm, :phase7] begin
    using TSODSO

    # RED until Wave 3 (plan 07-04 dual-residual correction lands with the 07-03 set_rho! seam).
    @test isdefined(TSODSO, :set_rho!)

    if isdefined(TSODSO, :set_rho!)
        feeder = Phase6Fixtures.two_bus_feeder()
        aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
        Th = Phase6Fixtures.T
        λ₀ = Phase6Fixtures.two_bus_lambda0()

        res = solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            ρ = Phase7Fixtures.RHO0,
            ε_abs = Phase7Fixtures.EPS_ABS,
            ε_rel = Phase7Fixtures.EPS_REL,
            allow_export = true,
        )
        led = res.residuals

        # (a) the dual trace holds a REAL Boyd z-block residual (extended record! is now used —
        # NOT the NaN sentinel the Phase-6 4-arg overload pads).
        @test led.iters >= 1
        @test all(isfinite, led.dual_trace)
        @test all(isfinite, led.eps_pri_trace)
        @test all(isfinite, led.eps_dual_trace)

        # (b) the converged ledger satisfies the TWO-residual predicate at its final iterate
        # (primal AND dual below their per-unit thresholds) — the false-convergence net (Pitfall 2).
        @test converged(led, last(led.eps_pri_trace), last(led.eps_dual_trace))
        @test last(led.primal_trace) <= last(led.eps_pri_trace)
        @test last(led.dual_trace) <= last(led.eps_dual_trace)
    end
end

@testitem "admm dualresid: ledger two-residual converged predicate (dualresid, resid)" setup =
    [Phase7Fixtures] tags = [:admm, :phase7] begin
    using TSODSO

    # This item exercises the JuMP-free ledger contract directly (GREEN once plan 07-01 Task 2
    # lands the extended AdmmResiduals) — it does NOT depend on solve_admm, so it pins the
    # two-residual `converged` semantics the dual-residual stop relies on.
    res = AdmmResiduals(2, Phase7Fixtures.T)
    record!(res, 1, 1e-2, 1e-2, Phase7Fixtures.RHO0, 1e-4, 1e-4, 0.5)   # both above ε
    @test converged(res, 1e-4, 1e-4) == false
    record!(res, 2, 1e-5, 5e-5, Phase7Fixtures.RHO0, 1e-4, 1e-4, 1e-3)  # both below ε
    @test converged(res, 1e-4, 1e-4) == true
    @test converged(res, 1e-4, 1e-6) == false                          # dual above ⇒ not converged
end
