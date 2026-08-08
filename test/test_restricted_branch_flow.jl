# test/test_restricted_branch_flow.jl
#
# Seam: overvoltage-capable relaxation restriction mechanism (OVR-01..04). Every item name
# contains "restricted_branch_flow" so `occursin("restricted_branch_flow", ti.name)` selects
# the whole file.
#
# The FIRST @testitem below is the BLOCKING analytic spot-check RESEARCH.md requires BEFORE any
# `RestrictedBranchFlow` code exists: it numerically confirms (or falsifies) RESEARCH.md
# Assumption A1 — that the EXISTING thesis exactness copy (`v̂`, thesis 3.43/3.45, already coded
# in `ConvexBranchFlow.jl`) is a LOWER-bound shadow on the true voltage (`v ≥ v̂` everywhere),
# the OPPOSITE sign relationship from Gan–Low's UPPER-bound shadow `v ≤ v̂_GL(s)`. If this
# assertion ever fails, STOP: the derivation in 20-RESEARCH.md has an error and every downstream
# plan (20-02..05) needs re-deriving before proceeding.
#
# The SECOND @testitem measures the Gan–Low "modification gap" ε (Definition 3, eq. 18) on a
# genuine AC-feasible operating point via the new `recover_lossfree_shadow_voltage` helper
# (src/models/ac_oracle.jl) — a MEASURED, never-searched default for plan 20-02's
# `RestrictedBranchFlow` shrink kwarg (D-03/D-04).

@testitem "restricted_branch_flow: v ≥ v̂ sign-relationship spot-check on the EXACT-04 fixture (RESEARCH Assumption A1)" tags =
    [:restricted_branch_flow] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = Phase4Fixtures.high_pv_feeder()
    aggs = Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = Phase4Fixtures.mem_price_profile()

    # rtol_exact = 1.0: the SAME diagnostic override test_ac_oracle.jl's EXACT-04 item uses, so
    # the inexact SOCP solution is returned for inspection instead of refused by solve_welfare's
    # own internal PF-04 gate. This is a read of v/v̂, not a claim about exactness.
    ctx, cost, dadp = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
        rtol_exact = 1.0,
    )
    pv = ctx.meta[:pf_vars]
    N = length(feeder.buses)

    mingap = minimum(
        value(pv.v[j, t]) - value(pv.v̂[j, t]) for j in 1:N, t in 1:Phase4Fixtures.T
    )
    @info "v-v̂ min gap" mingap

    # RESEARCH.md Assumption A1: the existing thesis exactness copy is a LOWER-bound shadow
    # (v ≥ v̂), opposite Gan-Low's UPPER-bound shadow — this is the reason Phase 20 needs a
    # genuinely new mechanism, not an adjustment of the existing v̂ bound. If this assertion ever
    # fails, STOP: the derivation in 20-RESEARCH.md has an error and every downstream plan
    # (20-02..05) needs re-deriving before proceeding.
    @test mingap >= -1e-9
end

@testitem "restricted_branch_flow: measured Gan-Low modification gap ε on the EXACT-04 fixture (D-03)" tags =
    [:restricted_branch_flow] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = Phase4Fixtures.high_pv_feeder()
    aggs = Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = Phase4Fixtures.mem_price_profile()

    # A genuine AC-feasible operating point (RESEARCH.md "Measuring ε" recipe step 1).
    ctx_ac, cost_ac, _ = solve_welfare(
        feeder,
        ACPowerFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_local = true,
        allow_export = true,
    )

    v̂_GL = TSODSO.recover_lossfree_shadow_voltage(ctx_ac)
    pv_ac = ctx_ac.meta[:pf_vars]
    N = length(feeder.buses)

    # Lemma 1 sanity check: Gan-Low's v ≤ v̂(s) always holds — the OPPOSITE sign from the first
    # @testitem's v ≥ v̂, confirming the two shadows are genuinely distinct mechanisms.
    @test minimum(
        v̂_GL[j, t] - value(pv_ac.v[j, t]) for j in 1:N, t in 1:Phase4Fixtures.T
    ) >= -1e-9

    ε_measured = maximum(
        v̂_GL[j, t] - value(pv_ac.v[j, t]) for j in 1:N, t in 1:Phase4Fixtures.T
    )
    @info "measured Gan-Low modification gap (before safety multiplier)" ε_measured

    # A nonzero, sensible modification gap. This exact printed value is what plan 20-02's
    # RestrictedBranchFlow default kwarg will hardcode (times a documented safety multiplier per
    # D-03's "measured, not searched" requirement), with a citation back to this test item.
    @test ε_measured > 0.0
end
