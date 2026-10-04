# test/test_exactness_verdict.jl
#
# Seam: FIX-01/02 verdict regression (phase 26-02). Every item name contains
# "exactness_verdict" so `occursin("exactness_verdict", ti.name)` selects the whole file.
#
# This is the FIX-01 acceptance regression: a 3-bus radial, heavy-load, low-voltage feeder
# that is (a) AC-feasible (Ipopt, ACPowerFlow), (b) feasible under the CORRECTED default
# ConvexBranchFlow() SOCP (v̂ ≥ v, the Gan-Low direction), and (c) INFEASIBLE under the
# LITERAL, defective thesis-transcribed ConvexBranchFlow(; thesis_literal=true) variant —
# demonstrating that the literal formula's `v̂ ≥ V²min` acts as a genuine RESTRICTION (it
# rejects an AC-feasible operating point), not merely a relaxation.
#
# Fixture provenance (per 26-02-PLAN.md Task 3): VALIDATED during plan revision against the
# CURRENT pre-fix code and an independent raw-JuMP replica of the corrected default. 3-bus
# radial Feeder, Bus(j, 0.90, 1.05, ...) at every bus, Branch(1,2,0.08,0.03,SMAX_NO_LIMIT)
# and Branch(2,3,0.08,0.03,SMAX_NO_LIMIT), a dummy Deferrable(3,1,1,0.0,1.0,1.0) device
# (draws nothing itself — present only to satisfy Aggregator's "at least one device" guard)
# plus Aggregator(3, 0.999999, [dummy], [0.53]) (near-unity power factor isolates the
# real-power mechanism this test targets, avoiding a reactive-power confound); T=1, λ₀=[1.0].

@testmodule ExactnessVerdictFixtures begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder, Aggregator, Deferrable

    const R = 0.08
    const X = 0.03
    const VMIN = 0.90
    const VMAX = 1.05
    const E = 0.53   # heavy inelastic load at the far bus (tuned per 26-02-PLAN.md Task 3)

    function feeder()
        return Feeder(
            [Bus(1, VMIN, VMAX, true), Bus(2, VMIN, VMAX, false), Bus(3, VMIN, VMAX, false)],
            [Branch(1, 2, R, X, 10.0), Branch(2, 3, R, X, 10.0)],
            1,
        )
    end

    function aggregators()
        dummy = Deferrable(3, 1, 1, 0.0, 1.0, 1.0)
        return [Aggregator(3, 0.999999, [dummy], [E])]
    end
end

@testitem "exactness_verdict: AC-feasible, default-SOCP-feasible, thesis-literal-infeasible 3-way regression (FIX-01)" tags =
    [:exactness_verdict] setup = [ExactnessVerdictFixtures] begin
    using TSODSO
    using TSODSO: ConvexBranchFlow, ACPowerFlow, solve_welfare
    using JuMP

    feeder = ExactnessVerdictFixtures.feeder()
    aggs = ExactnessVerdictFixtures.aggregators()

    # (a) AC-feasible ground truth (Ipopt).
    ctx_ac, _, _ =
        solve_welfare(feeder, ACPowerFlow(), aggs; T = 1, λ₀ = [1.0], allow_local = true, allow_export = true)
    @test ctx_ac isa TSODSO.ModelContext

    # (b) DEFAULT ConvexBranchFlow() (corrected, Gan-Low direction) must remain feasible on
    # the SAME data, and satisfy v̂ ≥ v at the solution. rtol_exact = 1.0 is the SAME
    # diagnostic override test_ac_oracle.jl/test_restricted_branch_flow.jl's EXACT-04 items
    # use, so an inexact/tight SOCP solution surfaces for inspection instead of being
    # refused by solve_welfare's own internal PF-04 gate.
    ctx_cv, _, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = 1,
        λ₀ = [1.0],
        allow_export = true,
        rtol_exact = 1.0,
    )
    gap = value(ctx_cv.pf_vars.v̂[3, 1]) - value(ctx_cv.pf_vars.v[3, 1])
    @info "default ConvexBranchFlow() v̂-v gap at bus 3" gap
    @test gap >= -1e-9   # v̂ ≥ v (Gan-Low direction), FIX-01/02

    # (c) The LITERAL, defective thesis-transcribed variant must be INFEASIBLE on the SAME
    # data (this is the "restriction" finding: v̂ ≥ V²min binds as a genuine restriction that
    # rejects an AC-feasible operating point under the literal, un-corrected sign).
    literal_infeasible = try
        solve_welfare(
            feeder,
            ConvexBranchFlow(; thesis_literal = true),
            aggs;
            T = 1,
            λ₀ = [1.0],
            allow_export = true,
            rtol_exact = 1.0,
        )
        false
    catch e
        true
    end
    @test literal_infeasible
end
