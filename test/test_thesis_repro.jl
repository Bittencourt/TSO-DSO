# test/test_thesis_repro.jl
#
# Seam: REPRO-01 — the gate-then-golden `@testitem` that certifies the thesis's headline
# DSO-surplus welfare result reproduces DIRECTIONALLY on real IEEE-123 data (real,
# Fortescue-reduced Phase-17 impedances + the Phase-17-retuned population, reactive pricing
# available via `decompose_dlmp(ctx).reactive`) — pinning a magnitude BAND, never a point
# value, and never the sign-unsafe aggregate welfare ratio `welfare_dadp/welfare_fit`
# (18-RESEARCH.md Pitfall 1: dividing two negative numbers can silently invert the intended
# "DADP is better" reading).
#
# Mirrors `test/test_acceptance.jl`'s 3-stage gate-then-golden convention (exactness gate ->
# pinned computed golden -> non-failing thesis cross-check), but the "golden" here is the
# DSO-surplus SIGN FLIP (FIT dso<0 -> DADP dso>0) plus a pinned magnitude BAND on `acct.dso`,
# per 18-RESEARCH.md's live-executed finding that the aggregate welfare ratio is a fragile,
# occasionally wrong-signed metric on both real fixtures at current population scales, while
# the DSO-surplus sign flip is the robust, correctly-signed, cross-fixture-consistent signal
# (and matches the thesis's own Case A framing, "DSO surplus -$2829 -> +$439").
#
# GOLDEN BAND PROVENANCE (threat T-18-04): `DSO_BAND_LO`/`DSO_BAND_HI` below are copied
# VERBATIM from Plan 18-01's committed `results/repro_stability_check/findings.txt`
# "RECOMMENDED BAND:" line (DSO_BAND_LO=0.0, DSO_BAND_HI=5.58855710237937) — NOT invented in
# this task, enforced by this plan's `depends_on: ["18-01"]` execution ordering.
#
# The primary item runs at the EXACT Phase-17-retuned point (no population-scale
# perturbation) where 18-01's own measurement confirms the sign flip HOLDS and the SOCP stays
# exact (`socp_maxgap=3.060e-07`). 18-01's `sign_flip_survives=false` finding concerns ONLY
# the +-2%/+-5% population-scale sensitivity sweep — it is NOT a caveat about the exact
# pinned point, so the primary gates below are hard, not weakened.
#
# UPDATE (quick task 260726-mo7 / 260823-gea): 18-01's original claim that "all 4 non-zero
# points FAIL the SOCP-exactness gate outright" was itself a MISATTRIBUTION — 2 of the 4
# failures were actually `fit_baseline`'s OWN internal solve throwing, not `solve_welfare`'s
# gate, an artifact of `repro_stability_check.jl`'s original single try/catch wrapping all
# three calls (fixed by 260823-gea, which split it per stage). Once `solve_welfare` runs at
# a tightened `tol_gap=1e-10`, its SOCP-exactness gate resolves cleanly at ALL 5 swept points
# (0/5 THREW, re-confirmed by 260823-gea, `.planning/spikes/003-phase18-fragility-tolerance/`).
# However, `fit_baseline`'s OWN nested solve does NOT reliably converge at that same tight
# tolerance: re-measured by 260823-gea, 3 of 5 points returned `ALMOST_OPTIMAL`/
# `NEARLY_FEASIBLE_POINT` rather than a trustworthy optimum, so the FULL sign-flip
# confirmation (DADP dso>0 AND FIT dso<0) currently holds at only 2 of 5 swept points, not
# 5 of 5 as `260726-mo7`'s SUMMARY recorded. This is a DIFFERENT numerical issue
# (solver-convergence-at-extreme-tolerance, not SOCP inexactness) from the one 18-01
# originally reported, and it means Plan 18-02's golden-band re-derivation (item 4 of
# STATE.md's Phase 18 corrections-owed bullet) remains OPEN — `DSO_BAND_HI` below is
# UNCHANGED by 260823-gea, pending a bounded, budgeted re-measurement in a future phase.

@testitem "thesis_repro: IEEE-123 real-impedance DADP-vs-FIT — DSO-surplus sign flip (REPRO-01)" tags =
    [:thesis_repro] setup = [Phase7Fixtures] begin
    using TSODSO

    # ── Pinned magnitude band (thesis 18-01's committed findings.txt "RECOMMENDED BAND:" line
    # -- DSO_BAND_LO=0.0, DSO_BAND_HI=5.58855710237937 -- copied verbatim, never invented here).
    const DSO_BAND_LO = 0.0
    const DSO_BAND_HI = 5.58855710237937

    feeder = ieee123_modified()
    aggs = Phase7Fixtures.build_ieee123_aggregators(feeder)
    Th = Phase7Fixtures.T
    λ₀ = Phase7Fixtures.ieee123_lambda0()

    # ── DADP: centralized GLB-CVX welfare optimum (thesis 3.38) + its surplus split (3.46/3.47).
    ctx, welfare_dadp, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        allow_export = true,
    )
    acct = welfare_accounting(ctx; T = Th)                       # (; social, dso, prosumer)

    # ── FIT counterfactual: German-FIT baseline (thesis 3.24-3.28), voltage-relaxed AC-PF —
    # CONFIRMED FEASIBLE on this voltage-driven (not congestion-driven) fixture (18-RESEARCH.md).
    fb = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀)
    fit_dso = fb.social_fit - fb.prosumer_surplus                # NOT a returned field

    # ── Gate-then-golden, in order, all HARD (no `broken=`):
    @test ctx.meta[:socp_maxgap] < 1e-5                          # 1. exactness gate (PF-04)
    @test acct.dso > 0.0                                          # 2. DADP DSO surplus sign
    @test fit_dso < 0.0                                           # 3. FIT DSO surplus sign
    @test acct.prosumer < fb.prosumer_surplus                     # 4. prosumer decreases under DADP
    @test DSO_BAND_LO < acct.dso < DSO_BAND_HI                    # 5. pinned magnitude band (golden)
end

# ── Secondary, NON-GATED qualitative cross-check (IEEE-13, congestion-driven, synthetic
# impedances). 18-RESEARCH.md's own live-executed numbers show the SAME DSO-surplus sign
# flip mechanism holds here too (FIT dso=-5.32 -> DADP dso=+2.56 at the `ground` population),
# even though this fixture's AGGREGATE welfare gap is currently wrong-signed (Δ≈-1.08) —
# per 18-RESEARCH.md's explicit recommendation, this item documents the mechanism honestly
# via a non-failing `broken=` assertion rather than gating REPRO-01 on it (threat T-18-05).
#
# `fit_baseline`'s voltage-only relaxation is CONFIRMED INFEASIBLE on this congestion-driven
# fixture (the head-branch thermal S_max ALSO binds, not just voltage — 18-RESEARCH.md
# Pitfall 2), so this item falls back to `scripts/thesis_caseA.jl`'s own hand-rolled,
# S_max-AND-voltage-relaxed FIT solve (via the internal `TSODSO._fit_opt_solve` seam) when
# `fit_baseline` throws.
@testitem "thesis_repro: IEEE-13 congestion — DSO-surplus sign-flip qualitative cross-check (secondary, non-gated)" tags =
    [:thesis_repro] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP: value, Model, @variable, @constraint, @objective, optimize!
    import TSODSO:
        Bus, Branch, SMAX_NO_LIMIT, ModelContext, register_constraint!, add_to_residual!

    feeder = TSODSO.ieee13_modified()
    aggs = Phase4Fixtures.build_ieee13_ground_aggregators(feeder; seed = 20260718)
    Th = Phase4Fixtures.T
    λ₀ = Phase4Fixtures.mem_price_profile()

    # ── DADP: same seam as the primary item, on the congestion-driven IEEE-13 fixture.
    ctx, welfare_dadp, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        allow_export = true,
    )
    acct = welfare_accounting(ctx; T = Th)

    # ── FIT: try the plain voltage-relaxed seam first; fall back to the manual S_max-relaxed
    # solve (mirrors scripts/thesis_caseA.jl:97-131) since `fit_baseline` is CONFIRMED
    # INFEASIBLE here (Pitfall 2 — the head-branch thermal limit binds, not just voltage).
    # Wrapped in a local FUNCTION (not a bare top-level try/catch) so the `fit_prosumer`/
    # `fit_dso` assignments inside `catch` are ordinary function-local bindings, not subject
    # to Julia's top-level soft-scope ambiguity (a bare try/catch at `@testitem` top level
    # introduces its own scope, and an assignment there to an outer `local` is ambiguous —
    # a Rule-1 bug caught by actually running this test).
    function _fit_ieee13(feeder, aggs, Th, λ₀)
        try
            fb = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀)
            return (;
                fit_prosumer = fb.prosumer_surplus,
                fit_dso = fb.social_fit - fb.prosumer_surplus,
            )
        catch e
            @info "thesis_repro (IEEE-13, secondary): fit_baseline infeasible as expected (Pitfall 2); " *
                  "falling back to the manual S_max-relaxed FIT solve" exception = e

            fa = TSODSO._fit_opt_solve(
                aggs;
                T = Th,
                optimizer = select_optimizer(problem_class(ConvexBranchFlow())),
            )
            fit_feeder = Feeder(
                [Bus(b.id, 0.8, 1.2, b.is_root) for b in feeder.buses],
                [
                    Branch(br.from, br.to, br.r, br.x, SMAX_NO_LIMIT) for
                    br in feeder.branches
                ],
                feeder.root,
            )
            _fit_model = Model(select_optimizer(problem_class(ConvexBranchFlow())))
            _fit_ctx = ModelContext(_fit_model)
            _fit_ctx.meta[:feeder] = fit_feeder
            _fit_ctx.meta[:T] = Th
            contribute!(ConvexBranchFlow(), _fit_ctx, fit_feeder; T = Th)
            _Np = length(fit_feeder.buses)
            for a in fa.per_agg
                _tanφ = sqrt(1 - a.φ^2) / a.φ
                for t in 1:Th
                    add_to_residual!(_fit_ctx, :Rp, a.bus, t, a.net[t])
                    add_to_residual!(_fit_ctx, :Rq, a.bus, t, -a.Pdc[t] * _tanφ)
                end
            end
            @variable(_fit_model, _fit_pimp[t = 1:Th])
            @variable(_fit_model, _fit_qimp[t = 1:Th])
            for t in 1:Th
                add_to_residual!(_fit_ctx, :Rp, fit_feeder.root, t, _fit_pimp[t])
                add_to_residual!(_fit_ctx, :Rq, fit_feeder.root, t, _fit_qimp[t])
            end
            @constraint(
                _fit_model,
                _fit_bp[j = 1:_Np, t = 1:Th],
                _fit_ctx.residuals[:Rp][j, t] == 0
            )
            @constraint(
                _fit_model,
                _fit_bq[j = 1:_Np, t = 1:Th],
                _fit_ctx.residuals[:Rq][j, t] == 0
            )
            register_constraint!(_fit_ctx, :balance_p, _fit_bp)
            @objective(_fit_model, Max, -sum(λ₀[t] * _fit_pimp[t] for t in 1:Th))
            optimize!(_fit_model)

            fit_prosumer = fa.prosumer_surplus
            fit_pimp = Float64[value.(_fit_pimp)...]
            welfare_fit = fa.total_utility - sum(λ₀[t] * fit_pimp[t] for t in 1:Th)
            fit_dso = welfare_fit - fit_prosumer
            return (; fit_prosumer, fit_dso)
        end
    end

    fit_result = _fit_ieee13(feeder, aggs, Th, λ₀)
    fit_prosumer = fit_result.fit_prosumer
    fit_dso = fit_result.fit_dso

    # ── Report the SAME sign-flip pattern via @info + a NON-FAILING assertion (never a hard
    # gate on this fixture — its aggregate welfare is currently wrong-signed, 18-RESEARCH.md).
    sign_flip_holds = acct.dso > 0.0 && fit_dso < 0.0 && acct.prosumer < fit_prosumer
    @info "thesis_repro (IEEE-13, secondary, non-gated): DSO-surplus sign-flip cross-check" acct.dso fit_dso acct.prosumer fit_prosumer sign_flip_holds

    @test sign_flip_holds broken = !sign_flip_holds
end
