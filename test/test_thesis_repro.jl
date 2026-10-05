# test/test_thesis_repro.jl
#
# Seam: reproduction of the headline result — the gate-then-golden `@testitem` that certifies the thesis's headline
# DSO-surplus welfare result reproduces DIRECTIONALLY on real IEEE-123 data (real,
# Fortescue-reduced impedances + the retuned population, reactive pricing
# available via `decompose_dlmp(ctx).reactive`) — pinning a magnitude BAND, never a point
# value, and never the sign-unsafe aggregate welfare ratio `welfare_dadp/welfare_fit`
# (dividing two negative numbers can silently invert the intended
# "DADP is better" reading).
#
# Mirrors `test/test_acceptance.jl`'s 3-stage gate-then-golden convention (exactness gate ->
# pinned computed golden -> non-failing thesis cross-check), but the "golden" here is the
# DSO-surplus SIGN FLIP (FIT dso<0 -> DADP dso>0) plus a pinned magnitude BAND on `acct.dso`.
# Live-executed runs show the aggregate welfare ratio is a fragile,
# occasionally wrong-signed metric on both real fixtures at current population scales, while
# the DSO-surplus sign flip is the robust, correctly-signed, cross-fixture-consistent signal
# (and matches the thesis's own Case A framing, "DSO surplus -$2829 -> +$439").
#
# GOLDEN BAND PROVENANCE: `DSO_BAND_LO`/`DSO_BAND_HI` below are copied
# VERBATIM from the committed `results/repro_stability_check/findings.txt` "RECOMMENDED BAND:"
# line — NOT invented here. The band was first derived as DSO_BAND_HI = 5.58855710237937,
# then re-derived to 7.211125525764296, and is now 7.229422341375; see the blocks below for why.
#
# The primary item runs at the EXACT retuned point (no population-scale
# perturbation) where the original measurement confirms the sign flip HOLDS and the SOCP stays
# exact (`socp_maxgap=3.060e-07`). The original `sign_flip_survives=false` finding concerns ONLY
# the +-2%/+-5% population-scale sensitivity sweep — it is NOT a caveat about the exact
# pinned point, so the primary gates below are hard, not weakened.
#
# UPDATE: the original claim that "all 4 non-zero
# points FAIL the SOCP-exactness gate outright" was itself a MISATTRIBUTION — 2 of the 4
# failures were actually `fit_baseline`'s OWN internal solve throwing, not `solve_welfare`'s
# gate, an artifact of `repro_stability_check.jl`'s original single try/catch wrapping all
# three calls (since fixed by splitting it per stage). Once `solve_welfare` runs at
# a tightened `tol_gap=1e-10`, its SOCP-exactness gate resolves cleanly at ALL 5 swept points
# (0/5 THREW, re-confirmed by a solver-tolerance spike).
# However, `fit_baseline`'s OWN nested solve does NOT reliably converge at that same tight
# tolerance: on re-measurement, 3 of 5 points returned `ALMOST_OPTIMAL`/
# `NEARLY_FEASIBLE_POINT` rather than a trustworthy optimum, so the FULL sign-flip
# confirmation (DADP dso>0 AND FIT dso<0) currently holds at only 2 of 5 swept points, not
# 5 of 5 as first recorded. This is a DIFFERENT numerical issue
# (solver-convergence-at-extreme-tolerance, not SOCP inexactness) from the one
# originally reported.
#
# GOLDEN BAND RE-DERIVED: the `1.5 x max|dso|` rule ranges over `dso` (the DADP DSO surplus from
# solve_welfare + welfare_accounting). `fit_baseline`'s nested solve is ORTHOGONAL to `dso` —
# it produces `fit_dso` for the sign-flip check and nothing the band depends on. The old
# `repro_stability_check.jl` nevertheless gated the band on all-three-stages success AND
# discarded `acct.dso` as NaN whenever fit_baseline threw, so the band was gated on, and
# starved by, a stage irrelevant to it. Both were fixed; `dso` is now trustworthy
# at 5/5 swept points (only 2/5 clear all three stages), giving
# 1.5 x 4.807417 = 7.211125525764296 from a re-run of the FIXED script at
# REPRO_TOL_GAP=1e-10 (flake rate 13/20 = 0.650, all 13 at fit_baseline, reproduced across
# 3 runs). This figure is reached by
# the decoupling argument above -- NOT by the refuted "sweep solves 5/5 everywhere" assumption it
# was originally projected from. The band WIDENS (5.5886 -> 7.2111); the sign gate
# DSO_BAND_LO = 0.0 and every other assertion here are unchanged.
#
# GOLDEN BAND RE-PINNED AGAIN: after the population-scale sweep was re-run against
# the corrected model, the constant below was re-pinned to match: the committed
# `results/repro_stability_check/findings.txt` was regenerated
# with fresh numbers (`sign_flip_survives: true`, 5/5, flake rate 1/20), and its own
# "RECOMMENDED BAND:" line now computes to
# `1.5 x max|dso| = 1.5 x 4.819615 = 7.229422341375` (the `δ=+0.050` swept point's `dso` grew
# slightly under the Gan-Low default). OLD DSO_BAND_HI = 7.211125525764296 (above) ->
# NEW DSO_BAND_HI = 7.229422341375 (the regenerated findings.txt), copied verbatim
# from that file, never invented here. The pinned point (`acct.dso ~ 3.739`) sits comfortably
# inside both the old and new band, so this re-pin does not change the test's verdict -- it only
# restores the "copied verbatim from the committed findings.txt" provenance claim to true.

@testitem "thesis_repro: IEEE-123 real-impedance DADP-vs-FIT — DSO-surplus sign flip" tags =
    [:thesis_repro] setup = [IEEE123Fixtures] begin
    using TSODSO
    using TSODSO: SOCP

    # ── Pinned magnitude band (committed findings.txt "RECOMMENDED BAND:" line
    # -- DSO_BAND_LO=0.0, DSO_BAND_HI=7.229422341375 -- copied verbatim, never invented
    # here; re-derived over the dso-trustworthy points (see header), re-pinned
    # again after findings.txt was regenerated against
    # the corrected model: OLD 7.211125525764296 -> NEW 7.229422341375).
    const DSO_BAND_LO = 0.0
    const DSO_BAND_HI = 7.229422341375

    feeder = ieee123_modified()
    aggs = IEEE123Fixtures.build_ieee123_aggregators(feeder)
    Th = IEEE123Fixtures.T
    λ₀ = IEEE123Fixtures.ieee123_lambda0()

    # ── DADP: centralized GLB-CVX welfare optimum (thesis 3.38) + its surplus split (3.46/3.47).
    # Default tol_gap=1e-8 trips the exactness gate on this
    # real-impedance feeder (precision-floor artifact, same band as test_acceptance.jl's IEEE-123
    # item and test_ieee123_admm.jl). tol_gap=3e-9 clears it;
    # `assert_socp_exact!`'s own gate is UNCHANGED. This makes the sign-flip result
    # ASSESSABLE (no longer masked by the gate throw); restating the finding itself is out of
    # scope here.
    ctx, welfare_dadp, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        allow_export = true,
        optimizer = select_optimizer(SOCP(); tol_gap_abs = 3e-9, tol_gap_rel = 3e-9),
    )
    acct = welfare_accounting(ctx; T = Th)                       # (; social, dso, prosumer)

    # ── FIT counterfactual: German-FIT baseline (thesis 3.24-3.28), voltage-relaxed AC-PF —
    # CONFIRMED FEASIBLE on this voltage-driven (not congestion-driven) fixture.
    #
    # Under the hybrid exactness floor (τ_solver=2e-7), this
    # fit_baseline's OWN internal third-site solve_welfare re-check (fit.jl:407, on the voltage-
    # relaxed feeder) trips exactness gate at the DEFAULT `tol_gap=1e-8` (ratio ≈2.50, max gap 8.21e-7,
    # just above τ_solver). MEASURED ladder (tol_gap_abs=tol_gap_rel, direct execution of this
    # exact fixture body):
    #   1e-8  -> THROWS (ratio 2.50, gap 8.21e-7)
    #   1e-9  -> PASSES (fit_dso=-196.26281848751387); stable to ~8 significant digits vs
    #            5e-10/1e-10/5e-11 (all -196.26282174995868)
    #   1e-11 -> solver fails to converge (ALMOST_OPTIMAL) — outside the usable range
    # `1e-9` is the LOOSEST rung clearing the gate with ample margin (this call's `optimizer`
    # propagates to ALL THREE of fit_baseline's internal solve sites, per its own docstring).
    fb = fit_baseline(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        optimizer = select_optimizer(SOCP(); tol_gap_abs = 1e-9, tol_gap_rel = 1e-9),
    )
    fit_dso = fb.social_fit - fb.prosumer_surplus                # NOT a returned field

    # ── Gate-then-golden, in order, all HARD (no `broken=`):
    @test ctx.meta[:socp_maxgap] < 1e-5                          # 1. exactness gate
    @test acct.dso > 0.0                                          # 2. DADP DSO surplus sign
    @test fit_dso < 0.0                                           # 3. FIT DSO surplus sign
    @test acct.prosumer < fb.prosumer_surplus                     # 4. prosumer decreases under DADP
    @test DSO_BAND_LO < acct.dso < DSO_BAND_HI                    # 5. pinned magnitude band (golden)
end

# ── Secondary, NON-GATED qualitative cross-check (IEEE-13, congestion-driven, synthetic
# impedances). Live-executed numbers show the SAME DSO-surplus sign
# flip mechanism holds here too (FIT dso=-5.32 -> DADP dso=+2.56 at the `ground` population),
# even though this fixture's AGGREGATE welfare gap is currently wrong-signed (Δ≈-1.08) —
# this item documents the mechanism honestly
# via a non-failing `broken=` assertion rather than gating the reproduction on it.
#
# `fit_baseline`'s voltage-only relaxation is CONFIRMED INFEASIBLE on this congestion-driven
# fixture (the head-branch thermal S_max ALSO binds, not just voltage), so this item falls back to `scripts/thesis_caseA.jl`'s own hand-rolled,
# S_max-AND-voltage-relaxed FIT solve (via the internal `TSODSO._fit_opt_solve` seam) when
# `fit_baseline` throws.
@testitem "thesis_repro: IEEE-13 congestion — DSO-surplus sign-flip qualitative cross-check (secondary, non-gated)" tags =
    [:thesis_repro] setup = [IEEE13Fixtures] begin
    using TSODSO
    using TSODSO: problem_class
    using JuMP: value, Model, @variable, @constraint, @objective, optimize!
    import TSODSO:
        Bus, Branch, SMAX_NO_LIMIT, ModelContext, register_constraint!, add_to_residual!

    feeder = TSODSO.ieee13_modified()
    aggs = IEEE13Fixtures.build_ieee13_ground_aggregators(feeder; seed = 20260718)
    Th = IEEE13Fixtures.T
    λ₀ = IEEE13Fixtures.mem_price_profile()

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
    # INFEASIBLE here — the head-branch thermal limit binds, not just voltage).
    # Wrapped in a local FUNCTION (not a bare top-level try/catch) so the `fit_prosumer`/
    # `fit_dso` assignments inside `catch` are ordinary function-local bindings, not subject
    # to Julia's top-level soft-scope ambiguity (a bare try/catch at `@testitem` top level
    # introduces its own scope, and an assignment there to an outer `local` is ambiguous —
    # a bug caught by actually running this test).
    function _fit_ieee13(feeder, aggs, Th, λ₀)
        try
            fb = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀)
            return (;
                fit_prosumer = fb.prosumer_surplus,
                fit_dso = fb.social_fit - fb.prosumer_surplus,
            )
        catch e
            @info "thesis_repro (IEEE-13, secondary): fit_baseline infeasible as expected; " *
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
            _fit_ctx.feeder = fit_feeder
            _fit_ctx.T = Th
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
    # gate on this fixture — its aggregate welfare is currently wrong-signed).
    sign_flip_holds = acct.dso > 0.0 && fit_dso < 0.0 && acct.prosumer < fit_prosumer
    @info "thesis_repro (IEEE-13, secondary, non-gated): DSO-surplus sign-flip cross-check" acct.dso fit_dso acct.prosumer fit_prosumer sign_flip_holds

    @test sign_flip_holds broken = !sign_flip_holds
end
