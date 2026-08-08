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

@testitem "restricted_branch_flow: RestrictedBranchFlow solves EXACT-04 through solve_welfare at PF-04's DEFAULT tolerance (OVR-01, free validation signal)" tags =
    [:restricted_branch_flow] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = Phase4Fixtures.high_pv_feeder()
    aggs = Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = Phase4Fixtures.mem_price_profile()

    # Deliberately WITHOUT any rtol_exact override — the DEFAULT 1e-4 is what
    # assert_socp_exact! uses internally. This call must NOT throw — if it does, the
    # restriction did not close the gap and the plan has failed at the most basic level.
    #
    # ESCALATION NOTE (see 20-02-SUMMARY.md): the SIMPLER OPF-ε special case (shrink v's own
    # bound by a single measured scalar ε) was tried FIRST and empirically found NOT to close
    # this gap at any feasible ε on this fixture (reverse-flow-driven residual, not
    # voltage-pinning-driven). RestrictedBranchFlow now implements the FULLER Gan-Low OPF-m
    # mechanism (direct v̂_GL(s) ≤ v̄ constraint, Theorem 2) by default (ε=0.0), which DOES
    # close the gap here — see the measured socp_maxgap below.
    ctx, cost, dadp = solve_welfare(
        feeder,
        RestrictedBranchFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
    )

    # RESEARCH.md's prediction: the residual should collapse from EXACT-04's documented
    # ≈10.4 to the benign-feeder scale ~1e-7; 1e-5 is a safe order-of-magnitude gate, not a
    # tight pin. Measured (OPF-m): ≈2.08e-8.
    @info "RestrictedBranchFlow socp_maxgap on EXACT-04" ctx.meta[:socp_maxgap]
    @test ctx.meta[:socp_maxgap] < 1e-5

    # D-08 provenance stash from Task 1.
    @test ctx.meta[:formulation] == :RestrictedBranchFlow
    @test ctx.meta[:restriction_ε] >= 0.0
end

@testitem "restricted_branch_flow: plain ConvexBranchFlow on EXACT-04 is UNCHANGED by RestrictedBranchFlow's existence (default-path regression)" tags =
    [:restricted_branch_flow] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP
    import Ipopt

    # Deliberate duplication (not a call into test_ac_oracle.jl) so that a future accidental
    # edit to ConvexBranchFlow.jl's bound-setting loop — the one Task 1's anti-pattern warning
    # protects — is caught by TWO independent test files, not one.
    feeder = Phase4Fixtures.high_pv_feeder()
    aggs = Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = Phase4Fixtures.mem_price_profile()

    ctx_socp, cost_socp, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
        rtol_exact = 1.0,
    )

    ctx_ac, cost_ac, _ = solve_welfare(
        feeder,
        ACPowerFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_local = true,
        allow_export = true,
    )
    ctx_ac2, cost_ac2, _ = solve_welfare(
        feeder,
        ACPowerFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_local = true,
        allow_export = true,
        optimizer = optimizer_with_attributes(
            Ipopt.Optimizer,
            "print_level" => 0,
            "mu_strategy" => "adaptive",
        ),
    )
    @test isapprox(cost_ac, cost_ac2; rtol = 1e-3, atol = 1e-3)

    report = TSODSO.assert_ac_exact!(ctx_socp, ctx_ac; rtol = 1e-4, atol = 1e-6)
    inexact_hours = [row.t for row in report.hours if !row.exact]
    @test !isempty(inexact_hours)

    pv_socp = ctx_socp.meta[:pf_vars]
    N = length(feeder.buses)
    B = length(feeder.branches)
    diagnosed = any(inexact_hours) do t★
        voltage_bound_hit =
            any(value(pv_socp.v[j, t★]) >= feeder.buses[j].vmax^2 - 1e-3 for j in 1:N)
        reverse_flow = any(value(pv_socp.P[b, t★]) < 0 for b in 1:B)
        voltage_bound_hit || reverse_flow
    end
    @test diagnosed
end
