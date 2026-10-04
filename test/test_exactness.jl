# Seam: models/exactness.jl (PF-04). The SOCP relaxation exactness price-refusal gate.
#
# RED @testitem harness (Wave 1). Plan 04-05 turns these green by defining
# `assert_socp_exact!(ctx; τ)` — the post-solve invariant `max|l·v − (P²+Q²)| < τ` that
# THROWS (refusing prices) when the relaxation is inexact. Every item name contains
# "exact" so `occursin("exact", ti.name)` selects it. The self-contained items build a
# fixed-value model directly (no dependence on the SOCP formulation), so they go live the
# moment `assert_socp_exact!` lands; the high-PV item additionally needs ConvexBranchFlow
# (04-02) and the shared Phase4Fixtures high-PV feeder.

@testitem "exact: assert_socp_exact! throws on an inexact relaxation, refusing prices (PF-04)" tags =
    [:exact] begin
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
        @variable(model, v[1:N, 1:T])
        @variable(model, v̂[1:N, 1:T])
        @variable(model, P[1:B, 1:T])
        @variable(model, Q[1:B, 1:T])
        @variable(model, l[1:B, 1:T])
        # A GROSSLY inexact point: l·v_from = 1·1 = 1 ≫ P²+Q² = 0  ⇒  gap = 1, and the
        # RELATIVE cone slack gap/max(|lhs|,|rhs|) ≈ 1 ≫ rtol (WR-01: scale-free gate).
        fix.(v, 1.0; force = true)
        fix.(v̂, 1.0; force = true)
        fix.(P, 0.0; force = true)
        fix.(Q, 0.0; force = true)
        fix.(l, 1.0; force = true)
        @objective(model, Max, 0)
        optimize!(model)

        ctx = TSODSO.ModelContext(model)
        ctx.feeder = feeder
        ctx.T = T
        ctx.pf_vars = (; v, v̂, P, Q, l)

        @test_throws Exception TSODSO.assert_socp_exact!(ctx; rtol = 1e-4)
    end
end

@testitem "exact: assert_socp_exact! passes and reports maxgap on an exact point (PF-04)" tags =
    [:exact] begin
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
        @variable(model, v[1:N, 1:T])
        @variable(model, v̂[1:N, 1:T])
        @variable(model, P[1:B, 1:T])
        @variable(model, Q[1:B, 1:T])
        @variable(model, l[1:B, 1:T])
        # An EXACT point: l = 0, P = Q = 0, v = 1 ⇒ gap = 0·1 − 0 = 0 < τ (no throw).
        fix.(v, 1.0; force = true)
        fix.(v̂, 1.0; force = true)
        fix.(P, 0.0; force = true)
        fix.(Q, 0.0; force = true)
        fix.(l, 0.0; force = true)
        @objective(model, Max, 0)
        optimize!(model)

        ctx = TSODSO.ModelContext(model)
        ctx.feeder = feeder
        ctx.T = T
        ctx.pf_vars = (; v, v̂, P, Q, l)

        maxgap = TSODSO.assert_socp_exact!(ctx; rtol = 1e-4)   # returns the abs gap; must not throw
        @test maxgap < 1e-5
    end
end

@testitem "exact: relative gate refuses a base-shrunk cone slack an absolute τ would accept (WR-01)" tags =
    [:exact] begin
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
        @variable(model, v[1:N, 1:T])
        @variable(model, v̂[1:N, 1:T])
        @variable(model, P[1:B, 1:T])
        @variable(model, Q[1:B, 1:T])
        @variable(model, l[1:B, 1:T])
        # A SMALL-MAGNITUDE strict cone: l·v_from = 5e-6·1 = 5e-6 ≫ P²+Q² = 0. The ABSOLUTE
        # cone residual is 5e-6 — BELOW the legacy absolute τ = 1e-5, so the old gate would
        # have SILENTLY ACCEPTED this fictitious over-current (the scale-dependence hazard on a
        # large per-unit base). The RELATIVE slack, however, is ≈ 1 (the cone is fully strict),
        # so the WR-01 gate correctly REFUSES prices regardless of the magnitude.
        fix.(v, 1.0; force = true)
        fix.(v̂, 1.0; force = true)
        fix.(P, 0.0; force = true)
        fix.(Q, 0.0; force = true)
        fix.(l, 5.0e-6; force = true)
        @objective(model, Max, 0)
        optimize!(model)

        ctx = TSODSO.ModelContext(model)
        ctx.feeder = feeder
        ctx.T = T
        ctx.pf_vars = (; v, v̂, P, Q, l)

        # The absolute residual is tiny (would slip past a 1e-5 ABSOLUTE gate)...
        @test 5.0e-6 < 1e-5
        # ...yet the RELATIVE gate refuses it: the cone is strict, not merely small.
        @test_throws Exception TSODSO.assert_socp_exact!(ctx; rtol = 1e-4)
    end
end

@testitem "exact: per-branch floor flags a slack cone on a small-smax branch the old flat atol missed (FIX-08)" tags =
    [:exact] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 0.01)],   # SMALL smax=0.01 ⇒ ref_b = smax^2 = 1e-4
        1,
    )
    T, N, B = 1, 2, 1
    model = Model(select_optimizer(SOCP()))
    @variable(model, v[1:N, 1:T])
    @variable(model, v̂[1:N, 1:T])
    @variable(model, P[1:B, 1:T])
    @variable(model, Q[1:B, 1:T])
    @variable(model, l[1:B, 1:T])
    # An injected gap of 5e-7 — BELOW the OLD flat atol=1e-6 (the legacy gate would have
    # silently PASSED this), but LARGE relative to this branch's own ref_b = smax^2 = 1e-4
    # (relative slack 5e-7 / 1e-4 = 5e-3): exactly the scale-blind-floor regression FIX-08
    # closes (a fine-grained lateral's slack cone silently accepted because the flat atol was
    # calibrated against head-branch-scale fixtures, not this branch's own thermal scale).
    fix.(v, 1.0; force = true)
    fix.(v̂, 1.0; force = true)
    fix.(P, 0.0; force = true)
    fix.(Q, 0.0; force = true)
    fix.(l, 5.0e-7; force = true)
    @objective(model, Max, 0)
    optimize!(model)

    ctx = TSODSO.ModelContext(model)
    ctx.feeder = feeder
    ctx.T = T
    ctx.pf_vars = (; v, v̂, P, Q, l)

    # Documents the regression this task closes: the OLD flat atol=1e-6 (still reachable via
    # the explicit-override backward-compat path) PASSES this exact point...
    maxgap_old_style = TSODSO.assert_socp_exact!(ctx; rtol = 1e-4, atol = 1e-6)
    @test maxgap_old_style < 1e-6

    # ...but the NEW per-branch default floor (ε * ref_b, ref_b = smax^2 = 1e-4) correctly
    # THROWS: the cone is slack by ~5x the branch's own scale-relative floor.
    @test_throws Exception TSODSO.assert_socp_exact!(ctx; rtol = 1e-4)
end

@testitem "exact: head-branch lookup is orientation-agnostic — ref_b matches forward vs reversed root branch (FIX-08, plan 27-07)" tags =
    [:exact] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # A 3-bus radial chain, root=1: branch A (the HEAD branch, SMAX_NO_LIMIT) connects the
    # root to bus 2; branch B (interior, ALSO SMAX_NO_LIMIT) connects bus 2 to bus 3. Since
    # BOTH branches are unlimited, `ref_b` for BOTH falls back to the head branch's OWN flow
    # magnitude squared (`head_flow_mag2`) — this item checks that value is IDENTICAL whether
    # the head branch is stored `br.from==root` (forward) or `br.to==root` (reversed, the
    # `test_mesh_angle_certificate.jl` CR-01/WR-03 "reversed-orientation" convention).
    #
    # `ref_b = 20^2 + 10^2 = 500` is chosen LARGE enough that `ε*ref_b = 1e-9*500 = 5e-7`
    # STRICTLY EXCEEDS the absolute floor `τ_solver = 2e-7` (2.5x) — i.e. the relative term
    # actually GOVERNS the gate here, so a wrong/zero `ref_b` (e.g. a broken head-branch
    # lookup silently defaulting to 0) would measurably change the verdict, not just its
    # margin. The interior branch's injected gap `3.5e-7` sits strictly BETWEEN the two
    # floors (`τ_solver=2e-7 < 3.5e-7 < ε*ref_b=5e-7`): it PASSES only when `ref_b` correctly
    # resolves to 500 in EITHER orientation.
    function build_ctx(head_branch_forward::Bool)
        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.90, 1.10, false), Bus(3, 0.90, 1.10, false)],
            head_branch_forward ?
            [
                Branch(1, 2, 0.01, 0.02, TSODSO.SMAX_NO_LIMIT),
                Branch(2, 3, 0.01, 0.02, TSODSO.SMAX_NO_LIMIT),
            ] :
            [
                Branch(2, 1, 0.01, 0.02, TSODSO.SMAX_NO_LIMIT),   # head branch, REVERSED storage
                Branch(2, 3, 0.01, 0.02, TSODSO.SMAX_NO_LIMIT),
            ],
            1,
        )
        T, N, B = 1, 3, 2
        model = Model(select_optimizer(SOCP()))
        @variable(model, v[1:N, 1:T])
        @variable(model, v̂[1:N, 1:T])
        @variable(model, P[1:B, 1:T])
        @variable(model, Q[1:B, 1:T])
        @variable(model, l[1:B, 1:T])
        fix.(v, 1.0; force = true)
        fix.(v̂, 1.0; force = true)
        # Head branch (index 1): P=20, Q=10 (ref_b = 500), l set EXACT (l*v = P²+Q²) so the
        # head branch's OWN cone (evaluated against its own ref_b too) never throws — this
        # item isolates the INTERIOR branch's use of the head-derived ref_b, not the head
        # branch's own exactness.
        fix(P[1, 1], 20.0; force = true)
        fix(Q[1, 1], 10.0; force = true)
        fix(l[1, 1], 500.0; force = true)
        # Interior branch (index 2): P=Q=0, l = 3.5e-7 — strictly between τ_solver and
        # ε*ref_b (see header comment above).
        fix(P[2, 1], 0.0; force = true)
        fix(Q[2, 1], 0.0; force = true)
        fix(l[2, 1], 3.5e-7; force = true)
        @objective(model, Max, 0)
        optimize!(model)

        ctx = TSODSO.ModelContext(model)
        ctx.feeder = feeder
        ctx.T = T
        ctx.pf_vars = (; v, v̂, P, Q, l)
        return ctx
    end

    ctx_fwd = build_ctx(true)
    ctx_rev = build_ctx(false)

    # Neither orientation throws `ArgumentError` (the malformed-feeder guard) NOR the
    # inexactness `error(...)` — both correctly resolve `ref_b=500` via the orientation-
    # agnostic head-branch lookup (`br.from==root || br.to==root`).
    maxgap_fwd = TSODSO.assert_socp_exact!(ctx_fwd; rtol = 1e-4)
    maxgap_rev = TSODSO.assert_socp_exact!(ctx_rev; rtol = 1e-4)

    # The gate's verdict (and the reported absolute residual) is IDENTICAL regardless of
    # the head branch's storage orientation — the direct regression this item pins.
    @test maxgap_fwd == maxgap_rev
    @test isapprox(maxgap_fwd, 3.5e-7; rtol = 1e-6)
end

@testitem "exact: high-PV / over-voltage SOCP solve stays exact, prices NOT refused (PF-04)" tags =
    [:exact] setup = [Phase4Fixtures] begin
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
            feeder,
            pf,
            aggs;
            T = Phase4Fixtures.T,
            λ₀ = λ₀,
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
        pv = ctx.pf_vars
        N = length(feeder.buses)
        B = length(feeder.branches)
        @test any(value(pv.v[j, t]) > 1.0 + 1e-4 for j in 1:N, t in 1:Phase4Fixtures.T)
        @test any(value(pv.P[b, t]) < -1e-3 for b in 1:B, t in 1:Phase4Fixtures.T)
        # ...and every bus stays within the squared-voltage cap (over-voltage, not a violation).
        vmax2 = maximum(feeder.buses[j].vmax^2 for j in 1:N)
        @test all(value(pv.v[j, t]) <= vmax2 + 1e-6 for j in 1:N, t in 1:Phase4Fixtures.T)
    end
end
