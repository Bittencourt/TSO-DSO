# Seam: models/exactness.jl (PF-04). The SOCP relaxation exactness price-refusal gate.
#
# RED @testitem harness (Wave 1). Plan 04-05 turns these green by defining
# `assert_socp_exact!(ctx; τ)` — the post-solve invariant `max|l·v − (P²+Q²)| < τ` that
# THROWS (refusing prices) when the relaxation is inexact. Every item name contains
# "exact" so `occursin("exact", ti.name)` selects it. The self-contained items build a
# fixed-value model directly (no dependence on the SOCP formulation), so they go live the
# moment `assert_socp_exact!` lands; the high-PV item additionally needs ConvexBranchFlow
# (04-02) and the shared Phase4Fixtures high-PV feeder.

@testitem "exact: assert_socp_exact! throws on an inexact relaxation, refusing prices (PF-04)" tags = [:exact] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # RED until plan 04-05 defines the checker.
    @test isdefined(TSODSO, :assert_socp_exact!)

    if isdefined(TSODSO, :assert_socp_exact!)
        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        T, N, B = 1, 2, 1
        model = Model(select_optimizer(SOCP()))
        @variable(model, v[1:N, 1:T]);  @variable(model, v̂[1:N, 1:T])
        @variable(model, P[1:B, 1:T]);  @variable(model, Q[1:B, 1:T]);  @variable(model, l[1:B, 1:T])
        # A GROSSLY inexact point: l·v_from = 1·1 = 1 ≫ P²+Q² = 0  ⇒  gap = 1, and the
        # RELATIVE cone slack gap/max(|lhs|,|rhs|) ≈ 1 ≫ rtol (WR-01: scale-free gate).
        fix.(v, 1.0; force = true);  fix.(v̂, 1.0; force = true)
        fix.(P, 0.0; force = true);  fix.(Q, 0.0; force = true);  fix.(l, 1.0; force = true)
        @objective(model, Max, 0)
        optimize!(model)

        ctx = TSODSO.ModelContext(model)
        ctx.meta[:feeder] = feeder
        ctx.meta[:T] = T
        ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)

        @test_throws Exception TSODSO.assert_socp_exact!(ctx; rtol = 1e-4)
    end
end

@testitem "exact: assert_socp_exact! passes and reports maxgap on an exact point (PF-04)" tags = [:exact] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    @test isdefined(TSODSO, :assert_socp_exact!)

    if isdefined(TSODSO, :assert_socp_exact!)
        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        T, N, B = 1, 2, 1
        model = Model(select_optimizer(SOCP()))
        @variable(model, v[1:N, 1:T]);  @variable(model, v̂[1:N, 1:T])
        @variable(model, P[1:B, 1:T]);  @variable(model, Q[1:B, 1:T]);  @variable(model, l[1:B, 1:T])
        # An EXACT point: l = 0, P = Q = 0, v = 1 ⇒ gap = 0·1 − 0 = 0 < τ (no throw).
        fix.(v, 1.0; force = true);  fix.(v̂, 1.0; force = true)
        fix.(P, 0.0; force = true);  fix.(Q, 0.0; force = true);  fix.(l, 0.0; force = true)
        @objective(model, Max, 0)
        optimize!(model)

        ctx = TSODSO.ModelContext(model)
        ctx.meta[:feeder] = feeder
        ctx.meta[:T] = T
        ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)

        maxgap = TSODSO.assert_socp_exact!(ctx; rtol = 1e-4)   # returns the abs gap; must not throw
        @test maxgap < 1e-5
    end
end

@testitem "exact: relative gate refuses a base-shrunk cone slack an absolute τ would accept (WR-01)" tags = [
    :exact,
] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    @test isdefined(TSODSO, :assert_socp_exact!)

    if isdefined(TSODSO, :assert_socp_exact!)
        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        T, N, B = 1, 2, 1
        model = Model(select_optimizer(SOCP()))
        @variable(model, v[1:N, 1:T]);  @variable(model, v̂[1:N, 1:T])
        @variable(model, P[1:B, 1:T]);  @variable(model, Q[1:B, 1:T]);  @variable(model, l[1:B, 1:T])
        # A SMALL-MAGNITUDE strict cone: l·v_from = 5e-6·1 = 5e-6 ≫ P²+Q² = 0. The ABSOLUTE
        # cone residual is 5e-6 — BELOW the legacy absolute τ = 1e-5, so the old gate would
        # have SILENTLY ACCEPTED this fictitious over-current (the scale-dependence hazard on a
        # large per-unit base). The RELATIVE slack, however, is ≈ 1 (the cone is fully strict),
        # so the WR-01 gate correctly REFUSES prices regardless of the magnitude.
        fix.(v, 1.0; force = true);  fix.(v̂, 1.0; force = true)
        fix.(P, 0.0; force = true);  fix.(Q, 0.0; force = true);  fix.(l, 5.0e-6; force = true)
        @objective(model, Max, 0)
        optimize!(model)

        ctx = TSODSO.ModelContext(model)
        ctx.meta[:feeder] = feeder
        ctx.meta[:T] = T
        ctx.meta[:pf_vars] = (; v, v̂, P, Q, l)

        # The absolute residual is tiny (would slip past a 1e-5 ABSOLUTE gate)...
        @test 5.0e-6 < 1e-5
        # ...yet the RELATIVE gate refuses it: the cone is strict, not merely small.
        @test_throws Exception TSODSO.assert_socp_exact!(ctx; rtol = 1e-4)
    end
end

@testitem "exact: high-PV / over-voltage SOCP solve stays exact, prices NOT refused (PF-04)" tags = [
    :exact,
] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    # RED until BOTH the SOCP formulation (04-02) and the exactness gate (04-05) land.
    @test isdefined(TSODSO, :ConvexBranchFlow)
    @test isdefined(TSODSO, :assert_socp_exact!)

    if isdefined(TSODSO, :ConvexBranchFlow) && isdefined(TSODSO, :assert_socp_exact!)
        feeder = Phase4Fixtures.high_pv_feeder()
        aggs = Phase4Fixtures.build_high_pv_aggregators(feeder)
        λ₀ = Phase4Fixtures.mem_price_profile()

        pf = TSODSO.ConvexBranchFlow()
        # `allow_export = true`: a real feeder SELLS its reverse-flow PV surplus to the MEM at
        # λ₀. That priced export sink is the SOC-exactness enabler — it makes welfare strictly
        # decreasing in the loss current `l`, so the cone stays tight in the over-voltage
        # regime (import-only would leave losses-vs-curtailment welfare-equivalent → slack
        # cone → refused prices). solve_welfare runs the PF-04 gate internally BEFORE the dual
        # read; reaching this line at all means prices were NOT refused.
        ctx, obj, dadp = solve_welfare(
            feeder, pf, aggs;
            T = Phase4Fixtures.T, λ₀ = λ₀,
            optimizer = select_optimizer(problem_class(pf)),
            allow_export = true,
        )

        # The over-voltage / reverse-flow regime is exactly where the SOC relaxation can go
        # strict; the exactness copy (3.43/3.45) keeps it exact so prices are trustworthy.
        # solve_welfare already gated on this and stashed the gap; re-assert externally too.
        @test haskey(ctx.meta, :socp_maxgap)
        maxgap = TSODSO.assert_socp_exact!(ctx; rtol = 1e-4)
        @test maxgap < 1e-5
        @test ctx.meta[:socp_maxgap] < 1e-5
        @test all(isfinite, dadp)

        # This is a GENUINE over-voltage / reverse-flow regime, not a trivial no-flow case:
        # at least one bus voltage exceeds nominal (v > 1.0² ⇒ over-voltage) and at least one
        # branch carries reverse power flow (P < 0 ⇒ PV back-feed toward the root).
        pv = ctx.meta[:pf_vars]
        N = length(feeder.buses)
        B = length(feeder.branches)
        @test any(value(pv.v[j, t]) > 1.0 + 1e-4 for j in 1:N, t in 1:Phase4Fixtures.T)
        @test any(value(pv.P[b, t]) < -1e-3 for b in 1:B, t in 1:Phase4Fixtures.T)
        # ...and every bus stays within the squared-voltage cap (over-voltage, not a violation).
        vmax2 = maximum(feeder.buses[j].vmax^2 for j in 1:N)
        @test all(value(pv.v[j, t]) <= vmax2 + 1e-6 for j in 1:N, t in 1:Phase4Fixtures.T)
    end
end
