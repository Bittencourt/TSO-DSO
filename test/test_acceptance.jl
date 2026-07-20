# test/test_acceptance.jl
#
# Seam: the SC3 v1 acceptance gate (EXP-04) — the single consolidated end-to-end proof that
# BOTH headline cases (IEEE-13 congestion, IEEE-123 voltage) reproduce exact SOC relaxation,
# recovered DADP, and ADMM ≈ centralized welfare, in one place. This file does NOT introduce
# any new solve path, fixture, or tolerance: it calls the SAME real entrypoints
# (`operational_oracle`, `solve_welfare`, `solve_admm`, `extract_dlmp`) already exercised by
# `test/test_ieee13.jl` (IEEE-13 "ground" @testitems, plan 04-06) and
# `test/test_ieee123_admm.jl` (plan 07-05), and it REUSES their already-pinned goldens and
# tolerances verbatim (CONTEXT.md lock: never invent new/looser acceptance-specific
# thresholds). Item names are tagged `:acceptance` for organizational/documentation purposes
# (NOTE 09-REVIEW WR-02: `test/runtests.jl`'s `@run_package_tests` call passes no `filter`
# keyword, so `Pkg.test(; test_args=["acceptance"])` does NOT select a subset today — it
# runs the entire suite, including these two testitems; tags are metadata only, not yet an
# active runtime filter).
#
# Consolidates (without duplicating):
#   - test/test_ieee13.jl  — "ieee13 ground: pinned computed golden regression" @testitem
#     (GOLDEN_WELFARE / GOLDEN_DADP16 / GOLDEN_SUM_DADP / GOLDEN_V9_16 / THESIS_V9_16).
#   - test/test_ieee123_admm.jl — the ADMM end-to-end convergence + DADP cross-validation
#     contract (res.iters, res.welfare, res.exact_maxgap, res.λ vs centralized DLMP).

@testitem "acceptance: IEEE-13 congestion — exact relaxation + DADP + ADMM≈centralized (SC3)" tags = [
    :acceptance,
] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    # ── PINNED COMPUTED GOLDEN (reused verbatim from test/test_ieee13.jl's "ieee13 ground:
    # pinned computed golden regression + thesis v₉[16] cross-check" @testitem — NOT
    # re-derived here). See that file's header for the ground-truth calibration rationale
    # (Phase4Fixtures.build_ieee13_ground_aggregators rescales the seeded shapes to a
    # residential magnitude so the head-branch-congested GLB-CVX solve is feasible and lands
    # in the thesis congestion-driven over-voltage regime).
    GOLDEN_WELFARE = -4823.1598620624 # GLB-CVX welfare optimum (computed; test_ieee13.jl)
    GOLDEN_V9_16 = 1.0436080536       # |V₉[16]| computed golden (test_ieee13.jl); HARD regression anchor
    THESIS_V9_16 = 1.0493             # thesis Fig 4.4 magnitude — non-failing cross-check only

    feeder = TSODSO.ieee13_modified()
    aggs = Phase4Fixtures.build_ieee13_ground_aggregators(feeder; seed = 20260718)
    λ₀ = Phase4Fixtures.mem_price_profile()

    # ── Centralized GLB-CVX SOCP solve through the oracle (exact relaxation + recovered DADP).
    res = operational_oracle(
        feeder, ConvexBranchFlow(), aggs; λ₀ = λ₀, T = 24, allow_export = true,
    )
    ctx = res.ctx

    @test ctx.meta[:socp_maxgap] < 1e-5                          # PF-04 exact relaxation
    @test isapprox(res.cost, GOLDEN_WELFARE; rtol = 1e-4)        # existing golden (test_ieee13.jl)

    # ── ADMM on the SAME feeder/aggregators/λ₀ must match the centralized optimum (ADMM-03/04)
    # and recover the SAME DADP. `res.dadp` (from `operational_oracle`/`solve_welfare`) is only
    # the FIRST aggregator's bus DADP (length-T vector), while `admm.λ` is the full
    # `(n_load_nodes, T)` converged DADP matrix (one row per load node, ascending bus order —
    # see `solve_admm`'s own docstring: "matching `extract_dlmp(centralized)[load_buses, :]`").
    # Build the SAME-shape centralized cross-check via `extract_dlmp` (identical pattern to
    # test_ieee123_admm.jl / the IEEE-123 acceptance item below) rather than the dimensionally
    # mismatched single-bus `res.dadp` — reusing the SAME tolerances (atol/rtol), never new ones.
    admm = solve_admm(
        feeder, ConvexBranchFlow(), aggs;
        T = 24, λ₀ = λ₀, ρ = 100.0, allow_export = true,
    )
    load_buses = sort([a.bus for a in aggs])
    dlmp_c = reduce(vcat, (extract_dlmp(ctx; bus = b, T = 24)' for b in load_buses))
    @test admm.exact_maxgap < 1e-3                                # PF-04 exact on the ADMM-converged DSO-OPT
    @test isapprox(admm.welfare, res.cost; rtol = 1e-4)          # ADMM ≈ centralized welfare
    # NOTE (09-REVIEW WR-01): `isapprox` on `AbstractArray` args is norm-based
    # (`norm(x-y) <= max(atol, rtol*max(norm(x),norm(y)))`), NOT elementwise — this is an
    # AGGREGATE bound over all (bus, hour) entries, not a per-entry `atol = 1e-2` guarantee.
    # A single bus/hour DADP can differ by more than `atol` and this assertion still passes
    # (observed: max |Δ| ≈ 0.0166 > atol = 1e-2 here, while the norm-based check still holds).
    @test isapprox(admm.λ, dlmp_c; atol = 1e-2, rtol = 1e-3)     # recovered DADP match (aggregate, not per-entry)

    # ── HARD regression assertion on the COMPUTED golden (09-REVIEW WR-03: restores the
    # per-node voltage golden that test_ieee13.jl hard-asserts, so THIS file also catches a
    # voltage-drop/sign regression that welfare + ADMM cross-validation alone would not).
    # A1: `v` is the SQUARED voltage ⇒ |V₉[16]| = sqrt(v[10,16]); node 9 → struct index 10.
    v9_16 = sqrt(value(ctx.meta[:pf_vars].v[10, 16]))
    @test isapprox(v9_16, GOLDEN_V9_16; atol = 1e-4)             # existing golden (test_ieee13.jl)

    # ── NON-FAILING thesis cross-check (never a hard failure — mirrors test_ieee13.jl).
    gap = abs(v9_16 - THESIS_V9_16)
    @info "acceptance ieee13: thesis v₉[16] cross-check (Assumption A1)" v9_16 = v9_16 thesis =
        THESIS_V9_16 gap = gap note = "gap is expected & documented (Open Q1: inputs figure-bound)"
    @test gap < 1e-2 broken = (gap >= 1e-2)
end

@testitem "acceptance: IEEE-123 voltage — exact relaxation + DADP + ADMM≈centralized (SC3)" tags = [
    :acceptance,
] setup = [Phase7Fixtures] begin
    using TSODSO

    feeder = ieee123_modified()
    aggs = Phase7Fixtures.build_ieee123_aggregators(feeder)
    load_buses = [a.bus for a in aggs]
    Th = Phase7Fixtures.T
    λ₀ = Phase7Fixtures.ieee123_lambda0()

    # ── Centralized ground truth: monolithic SOCP welfare + its DADP duals (ADMM-03 oracle),
    # identical to test_ieee123_admm.jl's cross-validation path.
    ctx_c, obj_c, _ = solve_welfare(
        feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀, allow_export = true,
    )
    dlmp_c = reduce(vcat, (extract_dlmp(ctx_c; bus = b, T = Th)' for b in load_buses))

    # ── ADMM with the SAME per-unit adaptive-ρ config as the smaller feeders (scale-invariant,
    # ADMM-02) — REUSING the identical Phase7Fixtures config constants, never retuned.
    res = solve_admm(
        feeder, ConvexBranchFlow(), aggs;
        T = Th, λ₀ = λ₀, ρ = Phase7Fixtures.RHO0,
        ε_abs = Phase7Fixtures.EPS_ABS, ε_rel = Phase7Fixtures.EPS_REL,
        τ = Phase7Fixtures.TAU, μ = Phase7Fixtures.MU,
        ρ_min = Phase7Fixtures.RHO_MIN, ρ_max = Phase7Fixtures.RHO_MAX,
        maxiter = 300, allow_export = true,
    )

    # ── Five contract lines reused verbatim from test_ieee123_admm.jl (no new/looser tolerance).
    @test res.iters < 300                                   # converged before the fail-loud cap
    @test res.iters <= 100                                  # ~tens of iters (loose bound)
    @test isapprox(res.welfare, obj_c; rtol = 1e-4)         # welfare match (ADMM-04)
    @test res.exact_maxgap < 1e-3                           # PF-04 exact on the converged DSO-OPT
    # NOTE (09-REVIEW WR-01): norm-based `isapprox` over the whole matrix, NOT a per-entry
    # bound — see the IEEE-13 item above for the elementwise-vs-aggregate caveat.
    @test isapprox(res.λ, dlmp_c; atol = 1e-2, rtol = 1e-3) # DADP → centralized price (λ_j → DADP), aggregate
end
