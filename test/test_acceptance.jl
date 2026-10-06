# test/test_acceptance.jl
#
# Seam: the v1 acceptance gate — the single consolidated end-to-end proof that
# BOTH headline cases (IEEE-13 congestion, IEEE-123 voltage) reproduce exact SOC relaxation,
# recovered DADP, and ADMM ≈ centralized welfare, in one place. This file does NOT introduce
# any new solve path, fixture, or tolerance: it calls the SAME real entrypoints
# (`operational_oracle`, `solve_welfare`, `solve_admm`, `extract_dlmp`) already exercised by
# `test/test_ieee13.jl` (IEEE-13 "ground" @testitems) and
# `test/test_ieee123_admm.jl`, and it REUSES their already-pinned goldens and
# tolerances verbatim (never invent new/looser acceptance-specific
# thresholds). Item names are tagged `:acceptance` for organizational/documentation purposes
# (NOTE: `test/runtests.jl`'s `@run_package_tests` call passes no `filter`
# keyword, so `Pkg.test(; test_args=["acceptance"])` does NOT select a subset today — it
# runs the entire suite, including these two testitems; tags are metadata only, not yet an
# active runtime filter).
#
# Consolidates (without duplicating):
#   - test/test_ieee13.jl  — "ieee13 ground: pinned computed golden regression" @testitem
#     (GOLDEN_WELFARE / GOLDEN_DADP16 / GOLDEN_SUM_DADP / GOLDEN_V9_16 / THESIS_V9_16).
#   - test/test_ieee123_admm.jl — the ADMM end-to-end convergence + DADP cross-validation
#     contract (res.iters, res.welfare, res.exact_maxgap, res.λ vs centralized DLMP).

@testitem "acceptance: IEEE-13 congestion — exact relaxation + DADP + ADMM≈centralized (SC3)" tags =
    [:acceptance, :slow] setup = [IEEE13Fixtures] begin
    using TSODSO
    using JuMP

    # ── PINNED COMPUTED GOLDEN (reused verbatim from test/test_ieee13.jl's "ieee13 ground:
    # pinned computed golden regression + thesis v₉[16] cross-check" @testitem — NOT
    # re-derived here). See that file's header for the ground-truth calibration rationale
    # (IEEE13Fixtures.build_ieee13_ground_aggregators rescales the seeded shapes to a
    # residential magnitude so the head-branch-congested GLB-CVX solve is feasible and lands
    # in the thesis congestion-driven over-voltage regime).
    # Re-pin after the later model corrections — kept bit-for-bit identical to test_ieee13.jl's
    # re-pin (battery soc[T+1] dominant, flexible-load reactive draw and the
    # :smax_rev back-feed limit also contribute), per this file's own
    # reused-verbatim convention. OLD -4823.1598620624 -> NEW -4823.496124912337.
    GOLDEN_WELFARE = -4823.496124912337 # GLB-CVX welfare optimum (computed; test_ieee13.jl)
    # Re-pin after the later model corrections — kept bit-for-bit identical to test_ieee13.jl's
    # re-pin (same causes as GOLDEN_WELFARE above).
    # OLD 1.0436080536 -> NEW 1.03604426055989.
    GOLDEN_V9_16 = 1.03604426055989   # |V₉[16]| computed golden (test_ieee13.jl); HARD regression anchor
    THESIS_V9_16 = 1.0493             # thesis Fig 4.4 magnitude — non-failing cross-check only

    feeder = TSODSO.ieee13_modified()
    aggs = IEEE13Fixtures.build_ieee13_ground_aggregators(feeder; seed = 20260718)
    λ₀ = IEEE13Fixtures.mem_price_profile()

    # ── Centralized GLB-CVX SOCP solve through the oracle (exact relaxation + recovered DADP).
    res = operational_oracle(
        feeder,
        ConvexBranchFlow(),
        aggs;
        λ₀ = λ₀,
        T = 24,
        allow_export = true,
    )
    ctx = res.ctx

    @test ctx.meta[:socp_maxgap] < 1e-5                          # exact relaxation
    @test isapprox(res.cost, GOLDEN_WELFARE; rtol = 1e-4)        # existing golden (test_ieee13.jl)

    # ── ADMM on the SAME feeder/aggregators/λ₀ must match the centralized optimum
    # and recover the SAME DADP. `res.dadp` (from `operational_oracle`/`solve_welfare`) is only
    # the FIRST aggregator's bus DADP (length-T vector), while `admm.λ` is the full
    # `(n_load_nodes, T)` converged DADP matrix (one row per load node, ascending bus order —
    # see `solve_admm`'s own docstring: "matching `extract_dlmp(centralized)[load_buses, :]`").
    # Build the SAME-shape centralized cross-check via `extract_dlmp` (identical pattern to
    # test_ieee123_admm.jl / the IEEE-123 acceptance item below) rather than the dimensionally
    # mismatched single-bus `res.dadp` — reusing the SAME tolerances (atol/rtol), never new ones.
    # Once ADMM's DsoOpt correctly engages LIVE reactive coupling
    # (this fixture carries Thermostatic/Deferrable flexible loads), the joint active+reactive
    # dual-ascent converges more slowly than this fixture's earlier budget (ρ=100, maxiter=200,
    # default ε_abs=1e-4/ε_rel=1e-3 → 103 iters, norm(Δλ)=0.697 vs bound=0.072 — FAILS). Re-tuned
    # (measured sweep, not guessed): ε_abs=1e-5/ε_rel=1e-4/maxiter=400 converges in 377 iters to
    # norm(Δλ)=0.0050, a ~14x margin under the SAME bound=0.072 — a genuine convergence-budget
    # fix, not a loosened assertion (the isapprox atol/rtol below are UNCHANGED).
    admm = solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = 24,
        λ₀ = λ₀,
        ρ = 100.0,
        maxiter = 400,
        ε_abs = 1e-5,
        ε_rel = 1e-4,
        allow_export = true,
    )
    load_buses = sort([a.bus for a in aggs])
    dlmp_c = reduce(vcat, (extract_dlmp(ctx; bus = b, T = 24)' for b in load_buses))
    @test admm.exact_maxgap < 1e-3                                # exact on the ADMM-converged DSO-OPT
    @test isapprox(admm.welfare, res.cost; rtol = 1e-4)          # ADMM ≈ centralized welfare
    # NOTE: `isapprox` on `AbstractArray` args is norm-based
    # (`norm(x-y) <= max(atol, rtol*max(norm(x),norm(y)))`), NOT elementwise — this is an
    # AGGREGATE bound over all (bus, hour) entries, not a per-entry `atol = 1e-2` guarantee.
    # A single bus/hour DADP can differ by more than `atol` and this assertion would still pass
    # (re-tune: at the re-tuned convergence budget above, the
    # observed max elementwise |Δ| ≈ 0.0020 and norm(Δ) ≈ 0.0050 both now comfortably clear
    # atol = 1e-2, but the check is still norm-based, not elementwise, in general).
    @test isapprox(admm.λ, dlmp_c; atol = 1e-2, rtol = 1e-3)     # recovered DADP match (aggregate, not per-entry)

    # ── HARD regression assertion on the COMPUTED golden (restores the
    # per-node voltage golden that test_ieee13.jl hard-asserts, so THIS file also catches a
    # voltage-drop/sign regression that welfare + ADMM cross-validation alone would not).
    # A1: `v` is the SQUARED voltage ⇒ |V₉[16]| = sqrt(v[10,16]); node 9 → struct index 10.
    v9_16 = sqrt(value(ctx.pf_vars.v[10, 16]))
    @test isapprox(v9_16, GOLDEN_V9_16; atol = 1e-4)             # existing golden (test_ieee13.jl)

    # ── NON-FAILING thesis cross-check (never a hard failure — mirrors test_ieee13.jl).
    gap = abs(v9_16 - THESIS_V9_16)
    @info "acceptance ieee13: thesis v₉[16] cross-check (Assumption A1)" v9_16 = v9_16 thesis =
        THESIS_V9_16 gap = gap note = "gap is expected & documented (inputs are figure-bound)"
    @test gap < 1e-2 broken = (gap >= 1e-2)
end

@testitem "acceptance: IEEE-123 voltage — exact relaxation + DADP + ADMM≈centralized (SC3)" tags =
    [:acceptance, :slow] setup = [IEEE123Fixtures] begin
    using TSODSO
    using TSODSO: SOCP

    feeder = ieee123_modified()
    aggs = IEEE123Fixtures.build_ieee123_aggregators(feeder)
    load_buses = [a.bus for a in aggs]
    Th = IEEE123Fixtures.T
    λ₀ = IEEE123Fixtures.ieee123_lambda0()

    # ── Centralized ground truth: monolithic SOCP welfare + its DADP duals (the ADMM oracle),
    # identical to test_ieee123_admm.jl's cross-validation path.
    # The real-impedance IEEE-123 feeder trips the exactness
    # gate at Clarabel's default tol_gap=1e-8 (ratio 3.94, precision-floor artifact, NOT
    # a genuine inexactness — the true optimum IS cone-tight; see the
    # v2.1 IEEE-123 noise-floor precedent). Calibrated tol_gap=3e-9 clears it (ratio ~0.084);
    # 1e-10 with tol_feas tightened FAILED on this same feeder in a prior measurement, so this is
    # not over-tightened. `assert_socp_exact!`'s own gate (atol/rtol) is UNCHANGED.
    ctx_c, obj_c, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        allow_export = true,
        optimizer = select_optimizer(SOCP(); tol_gap_abs = 3e-9, tol_gap_rel = 3e-9),
    )
    dlmp_c = reduce(vcat, (extract_dlmp(ctx_c; bus = b, T = Th)' for b in load_buses))

    # ── ADMM with the SAME per-unit adaptive-ρ config as the smaller feeders (scale-invariant,
    # scale-invariant) — REUSING the identical IEEE123Fixtures config constants, never retuned.
    res = solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        ρ = IEEE123Fixtures.RHO0,
        ε_abs = IEEE123Fixtures.EPS_ABS,
        ε_rel = IEEE123Fixtures.EPS_REL,
        τ = IEEE123Fixtures.TAU,
        μ = IEEE123Fixtures.MU,
        ρ_min = IEEE123Fixtures.RHO_MIN,
        ρ_max = IEEE123Fixtures.RHO_MAX,
        maxiter = 300,
        allow_export = true,
    )

    # ── Five contract lines reused verbatim from test_ieee123_admm.jl (no new/looser tolerance).
    @test res.iters < 300                                   # converged before the fail-loud cap
    @test res.iters <= 100                                  # ~tens of iters (loose bound)
    @test isapprox(res.welfare, obj_c; rtol = 1e-4)         # welfare match
    @test res.exact_maxgap < 1e-3                           # exact on the converged DSO-OPT
    # NOTE: norm-based `isapprox` over the whole matrix, NOT a per-entry
    # bound — see the IEEE-13 item above for the elementwise-vs-aggregate caveat.
    @test isapprox(res.λ, dlmp_c; atol = 1e-2, rtol = 1e-3) # DADP → centralized price (λ_j → DADP), aggregate
end
