# test/test_admm.jl
#
# Seam: src/admm/ — the ADMM decomposition core (build-once subproblems and DADP cross-validation).
#
# @testitem harness for the ADMM core. The items verify the
# code (the AGR-OPT / DSO-OPT subproblem builders and the `solve_admm` dual-ascent loop) — the
# tests are NEVER edited to go green; the documented contract below is the target API. Every
# item name contains "admm" so `occursin("admm", ti.name)` selects them; the cross-validation
# items also carry "crossval" (one "ieee13"), the build-once item carries "resolve"
# (test filter substrings).
#
# The first assertion in each item is a missing-symbol `isdefined(TSODSO, :solve_admm)`
# check (never a runner crash — the behavioral asserts sit BEHIND the `isdefined` guard, so
# they go live automatically once `solve_admm` exists). This mirrors the `test_dlmp.jl`
# precedent.
#
# CONTRACT pinned here:
#   solve_admm(feeder, ConvexBranchFlow(), aggregators;
#              T, λ₀, ρ, maxiter, tol, allow_export)
#     -> (; welfare, dadp, λ, iters, residuals, dso_ctx, exact_maxgap)
#   where `welfare ≈ objective_value(centralized)` and `λ ≈ extract_dlmp(centralized_ctx)` at
#   the load buses (the load-bearing DADP cross-validation), and the subproblem JuMP
#   models are built ONCE (model shape is iteration-count-independent).

@testitem "admm: cross-validation 2-bus welfare + DADP sign (crossval)" setup =
    [TwoBusFixtures, IEEE13Fixtures] tags = [:admm] begin
    using TSODSO
    using TSODSO: SOCP

    # solve_admm must be defined (the ADMM dual-ascent loop).
    @test isdefined(TSODSO, :solve_admm)

    if isdefined(TSODSO, :solve_admm)
        feeder = TwoBusFixtures.two_bus_feeder()
        aggs = TwoBusFixtures.build_two_bus_aggregators(feeder)
        Th = TwoBusFixtures.T
        λ₀ = TwoBusFixtures.two_bus_lambda0()
        load_bus = 2

        # Centralized ground truth: the monolithic SOCP welfare + its DADP duals.
        #
        # Precision-floor note: this near-lossless (r=x=1e-3) two-bus fixture's TRUE
        # optimum is exact, but Clarabel's default `tol_gap=1e-8` interior-point stopping point
        # trips the exactness gate at ratio ~4.00. A tol_gap
        # ladder measurement confirms ratio 1.4e-3 at `1e-10` — a ~3000x margin
        # below the gate — with the objective value UNCHANGED to >=6 significant digits
        # (-483.819124 either way). The exactness gate itself (`assert_socp_exact!`'s atol/rtol) is
        # NEVER touched; only the SOLVER's own convergence precision is tightened for this
        # genuinely-degenerate fixture (established precedent: src/models/stochastic_welfare.jl
        # L187-190).
        ctx_c, obj_c, _ = solve_welfare(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            allow_export = true,
            optimizer = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10),
        )
        dlmp_c = extract_dlmp(ctx_c; bus = load_bus, T = Th)

        # ADMM must recover the SAME welfare AND the SAME duals to tolerance.
        res = solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            ρ = TwoBusFixtures.RHO_2BUS,
            allow_export = true,
        )

        @test isapprox(res.welfare, obj_c; rtol = 1e-4)          # welfare match
        @test all(>(0), dlmp_c)                                  # dual-SIGN anchor: positive price
        @test isapprox(vec(res.λ), vec(dlmp_c); atol = 1e-2, rtol = 1e-3)   # DADP match (load-bearing)
    end
end

@testitem "admm: cross-validation ieee13 welfare + DADP (crossval, ieee13)" setup =
    [TwoBusFixtures, IEEE13Fixtures] tags = [:admm] begin
    using TSODSO

    # solve_admm must be defined (the ADMM dual-ascent loop).
    @test isdefined(TSODSO, :solve_admm)

    if isdefined(TSODSO, :solve_admm)
        # Reuse the IEEE-13 GROUND fixture + the exported modified feeder (allow_export
        # is mandatory — the priced frontier keeps the SOC relaxation exact).
        feeder = ieee13_modified()
        aggs = IEEE13Fixtures.build_ieee13_ground_aggregators(feeder)
        Th = IEEE13Fixtures.T
        λ₀ = IEEE13Fixtures.mem_price_profile()
        load_buses = 2:length(feeder.buses)

        # ρ_ieee13 / tol_ieee13 — the IEEE-13 penalty/dual-step + primal-stop, DISTINCT from the
        # 2-bus RHO_2BUS = 5.0 (ρ is fixture-empirical; adaptive-ρ is handled separately).
        # Unlike the near-lossless 2-bus (DADP ≈ λ₀, converges in ~4 iters at ANY ρ), the ground
        # fixture is CONGESTION-driven (the head branch binds at the PV peak → an over-voltage on
        # node 9), so the DADP at the binding node carries a congestion+voltage component whose
        # dual-ascent tail converges only linearly. Swept empirically: ρ = 100 with a primal stop
        # tol = 1e-6 lands the load-bus DADP within ~0.005 of `extract_dlmp` (a ~4× margin on the
        # cross-validation tolerance) in ~99 iterations. A larger ρ speeds the primal but SLOWS the
        # dual (the price) tail; ρ = 100 balances both. (The `solve_admm` −λ₀ multiplier warm start
        # is what keeps this to ~100 rather than ~1000 iterations.) Pinned inline.
        #
        # Re-tuned after the reactive-consensus default changed: the
        # reactive_consensus smart default now correctly engages `LIVE` reactive coupling on
        # this Thermostatic/Deferrable/PVBattery IEEE-13 ground population (it was silently OFF
        # before, since the earlier guard only inspected `FourQuadBESS`), so this item's
        # earlier (ρ=100, maxiter=200, default ε_abs=1e-4/ε_rel=1e-3) budget — swept when the
        # reactive channel was never actually engaged — is too tight for the now-JOINTLY-driven
        # active+reactive stopping rule: it still terminates at iters=103 (< 200, so it does NOT
        # hit the fail-loud cap) but the recovered DADP misses the norm-based
        # `isapprox(...; atol=1e-2, rtol=1e-3)` check (max elementwise |Δ| = 0.139, concentrated
        # at the PV back-feed hours 9/16). OLD: `maxiter = 200` with
        # `ε_abs`/`ε_rel` left at solve_admm's own defaults (1e-4/1e-3). NEW: `maxiter_ieee13 =
        # 700`, `ε_abs_ieee13 = 1e-6`, `ε_rel_ieee13 = 1e-7` — re-measured (a direct
        # budget sweep: ρ=100 unchanged, maxiter/ε_abs/ε_rel swept jointly) converges in
        # `iters = 535` (comfortably under the new 700 cap) to max elementwise |Δ| = 4.24e-3, a
        # ~2.4× margin under the pinned `atol=1e-2` — genuinely re-tuned to a TIGHTER stopping
        # rule that the reactive channel needs to jointly converge, never a loosened assertion.
        # `exact_maxgap` stays at 1.9e-9 (well inside the unchanged `< 1e-3` exactness gate).
        ρ_ieee13 = 100.0
        tol_ieee13 = 1e-6
        maxiter_ieee13 = 700
        ε_abs_ieee13 = 1e-6
        ε_rel_ieee13 = 1e-7

        ctx_c, obj_c, _ = solve_welfare(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            allow_export = true,
        )
        dlmp_c = reduce(vcat, (extract_dlmp(ctx_c; bus = b, T = Th)' for b in load_buses))

        res = solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            ρ = ρ_ieee13,
            maxiter = maxiter_ieee13,
            tol = tol_ieee13,
            ε_abs = ε_abs_ieee13,
            ε_rel = ε_rel_ieee13,
            allow_export = true,
        )

        @test res.iters < maxiter_ieee13                         # converged before the fail-loud cap
        @test isapprox(res.welfare, obj_c; rtol = 1e-4)          # welfare match
        @test res.exact_maxgap < 1e-3                            # exactness on the converged DSO-OPT
        @test isapprox(res.λ, dlmp_c; atol = 1e-2, rtol = 1e-3)  # DADP match on every load node
    end
end

@testitem "admm: dual-ascent loop converges + fails loud on the cap (loop)" setup =
    [TwoBusFixtures, IEEE13Fixtures] tags = [:admm] begin
    using TSODSO
    using TSODSO: SOCP

    # solve_admm must be defined (the ADMM dual-ascent loop).
    @test isdefined(TSODSO, :solve_admm)

    if isdefined(TSODSO, :solve_admm)
        feeder = TwoBusFixtures.two_bus_feeder()
        aggs = TwoBusFixtures.build_two_bus_aggregators(feeder)
        Th = TwoBusFixtures.T
        λ₀ = TwoBusFixtures.two_bus_lambda0()
        ρ = TwoBusFixtures.RHO_2BUS
        maxiter = 200
        tol = 1e-5

        # (a) The hand-rolled dual-ascent loop CONVERGES on the 2-bus (primal residual ≤ tol) in
        # well under maxiter iterations, recording each iteration in the returned AdmmResiduals.
        res = solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            ρ = ρ,
            maxiter = maxiter,
            tol = tol,
            allow_export = true,
        )

        @test res.iters >= 1
        @test res.iters < maxiter                                   # converged before the cap
        @test res.residuals isa TSODSO.AdmmResiduals
        @test res.residuals.iters == res.iters                      # every iteration recorded
        @test last(res.residuals.primal_trace) <= tol               # primal-residual stop

        # (b) The full return tuple is present and well-typed.
        @test res.λ === res.dadp                                    # dadp == λ (converged price)
        @test size(res.λ, 2) == Th                                  # one column per hour
        @test isfinite(res.welfare)                                 # welfare recomputed from primals
        @test res.exact_maxgap < 1e-3                               # converged DSO-OPT is exact
        @test hasproperty(res.dso_ctx, :model)                      # converged DSO-OPT context

        # (c) Welfare is recomputed from PRIMAL values (Σ U_ag − λ₀ᵀp_import), NOT a penalized
        # subproblem objective — so it MATCHES the centralized welfare, which the penalized
        # objectives (carrying the ρ-penalty + dual terms) never would.
        #
        # Precision-floor note: SAME two-bus precision-floor fixture as the `crossval`
        # item above — tightened tol_gap for the SAME reason (see that item's comment).
        _, obj_c, _ = solve_welfare(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            allow_export = true,
            optimizer = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10),
        )
        @test isapprox(res.welfare, obj_c; rtol = 1e-4)

        # (d) FAIL-LOUD cap: a budget too small to reach a
        # consensus THROWS rather than silently returning the last (non-consensus) iterate. The
        # 2-bus needs several iterations, so maxiter = 1 with a tight tol cannot converge.
        @test_throws ConvergenceError solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            ρ = ρ,
            maxiter = 1,
            tol = 1e-12,
            allow_export = true,
        )

        # (e) A non-positive maxiter is an INVALID budget: the loop never runs, so the residual
        # trace stays empty. This must throw a CLEAR boundary ArgumentError, NOT the opaque
        # BoundsError the fail-loud cap's `last(residuals.primal_trace)` would raise on an empty
        # trace (the guard failing itself). maxiter = 0 AND a negative maxiter both reject up front.
        @test_throws ArgumentError solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            ρ = ρ,
            maxiter = 0,
            tol = tol,
            allow_export = true,
        )
        @test_throws ArgumentError solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            ρ = ρ,
            maxiter = -3,
            tol = tol,
            allow_export = true,
        )

        # (f) A DEGENERATE horizon T = 0 (with a length-0 λ₀ that would otherwise pass the shape
        # guard) is an INVALID problem: the coupling-entry count p = length(load_nodes)·T == 0, so
        # ε_pri = ε_dual = 0 and every residual sum is 0, making `converged` trivially true on
        # iteration 1 — a NONSENSICAL "converged" result for an empty problem. This must throw a
        # CLEAR boundary ArgumentError up front, NOT silently report a degenerate optimum.
        @test_throws ArgumentError solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = 0,
            λ₀ = Float64[],
            ρ = ρ,
            maxiter = maxiter,
            tol = tol,
            allow_export = true,
        )
    end
end

@testitem "admm: build-once subproblems, no per-iteration rebuild (resolve)" setup =
    [TwoBusFixtures, IEEE13Fixtures] tags = [:admm] begin
    using TSODSO
    using JuMP: num_variables, num_constraints

    # solve_admm must be defined; the AGR-OPT / DSO-OPT builders are checked below.
    @test isdefined(TSODSO, :solve_admm)

    if isdefined(TSODSO, :solve_admm) &&
       isdefined(TSODSO, :AgrOpt) &&
       isdefined(TSODSO, :DsoOpt)
        feeder = TwoBusFixtures.two_bus_feeder()
        aggs = TwoBusFixtures.build_two_bus_aggregators(feeder)
        Th = TwoBusFixtures.T
        λ₀ = TwoBusFixtures.two_bus_lambda0()
        ρ = TwoBusFixtures.RHO_2BUS

        # Build-once: the subproblem JuMP models are built ONCE
        # outside the loop and only re-solved via `set_objective_coefficient` — NO variable or
        # constraint is added per iteration. The observable no-rebuild signal: the CONVERGED
        # DSO-OPT model (after `res.iters` re-solves) has EXACTLY the same variable/constraint
        # counts as a FRESHLY-built DSO-OPT — a per-iteration rebuild or leaked state would grow
        # the model. `count_variable_in_set_constraints = true` also pins the SOC cones.
        dso_ref = build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀)
        nv_ref = num_variables(dso_ref.model)
        nc_ref = num_constraints(dso_ref.model; count_variable_in_set_constraints = true)

        res = solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            ρ = ρ,
            maxiter = 200,
            allow_export = true,
        )

        @test res.iters < 200                                       # converged (loop actually ran)
        @test num_variables(res.dso_ctx.model) == nv_ref            # no per-iteration variable growth
        @test num_constraints(
            res.dso_ctx.model;
            count_variable_in_set_constraints = true,
        ) == nc_ref                                                # no per-iteration constraint growth

        # AGR-OPT[j] is likewise built once: a freshly-built AGR-OPT and the loop's per-node model
        # share the same shape (the loop mutates only the coupling coefficient, never rebuilds).
        agr_ref = build_agr_opt(aggs[1], Th; ρ = ρ)
        @test num_variables(agr_ref.model) >= 1                     # a real per-node QP was built once
    end
end

@testitem "admm: final published primal certified — active-balance no hidden slack (crossval)" setup =
    [TwoBusFixtures, IEEE13Fixtures] tags = [:admm] begin
    using TSODSO
    using JuMP: value

    # The FINAL consolidation DSO-OPT solve tolerates the conic backend's BENIGN
    # ALMOST_OPTIMAL / NEARLY_FEASIBLE LABEL (an interior-point gap artefact under the ρ-penalty),
    # but its PRIMAL is PUBLISHED (it feeds the reported `welfare` and the exactness gate). So
    # `solve_admm` guards that primal with a runtime PHYSICAL certificate INDEPENDENT of the solver
    # label: the ACTIVE nodal balance (`:balance_p`, thesis 3.31 — the constraint feeding
    # `p_import`→`welfare` and whose dual is the DADP) must carry NO hidden slack. A genuinely
    # near-INFEASIBLE final primal would show active-balance slack and be REFUSED loudly. The
    # observable signal here: after a converged `solve_admm`, recomputing the active-balance residual
    # of the returned DSO-OPT context from the solved variables is ≈ 0 to tight tolerance — the exact
    # quantity `assert_no_slack` gates inside the loop. (`:balance_q`, the inelastic constant
    # reactive-draw closure, legitimately carries the conic solver's NEARLY_FEASIBLE slack and is NOT
    # published/load-bearing, so it is intentionally NOT asserted — see solve_admm's final block.)
    @test isdefined(TSODSO, :solve_admm)

    if isdefined(TSODSO, :solve_admm)
        feeder = TwoBusFixtures.two_bus_feeder()
        aggs = TwoBusFixtures.build_two_bus_aggregators(feeder)
        Th = TwoBusFixtures.T
        λ₀ = TwoBusFixtures.two_bus_lambda0()

        res = solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            ρ = TwoBusFixtures.RHO_2BUS,
            maxiter = 200,
            allow_export = true,
        )

        # The active nodal balance of the PUBLISHED converged primal is satisfied with no hidden
    # slack — the runtime certificate. `assert_no_slack` (the same gate solve_admm runs)
        # recomputes each residual from the solved variables and returns `lhs − rhs`; RE-running it
        # here on the returned context must not throw and must be ≈ 0.
        balance_p = res.dso_ctx.constraints[:balance_p]
        max_slack = maximum(
            abs(assert_no_slack(res.dso_ctx.model, balance_p[j, t]; atol = 1e-6)) for
            j in 1:size(balance_p, 1), t in 1:size(balance_p, 2)
        )
        @test max_slack <= 1e-6                    # active balance is machine-exact at the optimum
        @test isfinite(res.welfare)               # welfare derived from the certified primal
        @test res.exact_maxgap < 1e-3             # exactness certificate from the certified primal
    end
end
