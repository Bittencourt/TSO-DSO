# test/test_admm.jl
#
# Seam: src/admm/ — the ADMM decomposition core (ADMM-01 / ADMM-03 / ADMM-04).
#
# RED @testitem harness (Wave 0 of Phase 6). Waves 2–3 turn these green by IMPLEMENTING the
# code (the AGR-OPT / DSO-OPT subproblem builders and the `solve_admm` dual-ascent loop) — the
# tests are NEVER edited to go green; the documented contract below is the target API. Every
# item name contains "admm" so `occursin("admm", ti.name)` selects them; the cross-validation
# items also carry "crossval" (one "ieee13"), the build-once item carries "resolve"
# (06-VALIDATION filter substrings).
#
# While RED the sole failing assertion is a missing-symbol `isdefined(TSODSO, :solve_admm)`
# check (never a runner crash — the behavioral asserts sit BEHIND the `isdefined` guard, so
# they go live automatically once Wave 3 lands `solve_admm`). This mirrors the Phase-5
# `test_dlmp.jl` RED-then-green precedent.
#
# CONTRACT pinned here (RESEARCH Pattern 5 / System Architecture Diagram):
#   solve_admm(feeder, ConvexBranchFlow(), aggregators;
#              T, λ₀, ρ, maxiter, tol, allow_export)
#     -> (; welfare, dadp, λ, iters, residuals, dso_ctx, exact_maxgap)
#   where `welfare ≈ objective_value(centralized)` and `λ ≈ extract_dlmp(centralized_ctx)` at
#   the load buses (the load-bearing DADP cross-validation, ADMM-04), and the subproblem JuMP
#   models are built ONCE (ADMM-03 — model shape is iteration-count-independent).

@testitem "admm: cross-validation 2-bus welfare + DADP sign (crossval)" setup = [
    Phase6Fixtures,
    Phase4Fixtures,
] tags = [:admm] begin
    using TSODSO

    # RED until Wave 3 (plan 06-04) fills the ADMM dual-ascent loop.
    @test isdefined(TSODSO, :solve_admm)

    if isdefined(TSODSO, :solve_admm)
        feeder = Phase6Fixtures.two_bus_feeder()
        aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
        Th = Phase6Fixtures.T
        λ₀ = Phase6Fixtures.two_bus_lambda0()
        load_bus = 2

        # Centralized ground truth (Phase 4/5): the monolithic SOCP welfare + its DADP duals.
        ctx_c, obj_c, _ = solve_welfare(
            feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀, allow_export = true,
        )
        dlmp_c = extract_dlmp(ctx_c; bus = load_bus, T = Th)

        # ADMM must recover the SAME welfare AND the SAME duals to tolerance.
        res = solve_admm(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, ρ = Phase6Fixtures.RHO_2BUS, allow_export = true,
        )

        @test isapprox(res.welfare, obj_c; rtol = 1e-4)          # welfare match (ADMM-04)
        @test all(>(0), dlmp_c)                                  # dual-SIGN anchor: positive price
        @test isapprox(vec(res.λ), vec(dlmp_c); atol = 1e-2, rtol = 1e-3)   # DADP match (load-bearing)
    end
end

@testitem "admm: cross-validation ieee13 welfare + DADP (crossval, ieee13)" setup = [
    Phase6Fixtures,
    Phase4Fixtures,
] tags = [:admm] begin
    using TSODSO

    # RED until Wave 3 (plan 06-04) fills the ADMM dual-ascent loop.
    @test isdefined(TSODSO, :solve_admm)

    if isdefined(TSODSO, :solve_admm)
        # Reuse the Phase-4 IEEE-13 GROUND fixture + the exported modified feeder (allow_export
        # is mandatory — the priced frontier keeps the SOC relaxation exact, PF-04).
        feeder = ieee13_modified()
        aggs = Phase4Fixtures.build_ieee13_ground_aggregators(feeder)
        Th = Phase4Fixtures.T
        λ₀ = Phase4Fixtures.mem_price_profile()
        load_buses = 2:length(feeder.buses)

        # ρ_ieee13 / tol_ieee13 — the IEEE-13 penalty/dual-step + primal-stop, DISTINCT from the
        # 2-bus RHO_2BUS = 5.0 (RESEARCH Open Q1: ρ is fixture-empirical; adaptive-ρ is Phase 7).
        # Unlike the near-lossless 2-bus (DADP ≈ λ₀, converges in ~4 iters at ANY ρ), the ground
        # fixture is CONGESTION-driven (the head branch binds at the PV peak → an over-voltage on
        # node 9), so the DADP at the binding node carries a congestion+voltage component whose
        # dual-ascent tail converges only linearly. Swept empirically: ρ = 100 with a primal stop
        # tol = 1e-6 lands the load-bus DADP within ~0.005 of `extract_dlmp` (a ~4× margin on the
        # cross-validation tolerance) in ~99 iterations. A larger ρ speeds the primal but SLOWS the
        # dual (the price) tail; ρ = 100 balances both. (The `solve_admm` −λ₀ multiplier warm start
        # is what keeps this to ~100 rather than ~1000 iterations.) Pinned inline per the plan.
        ρ_ieee13 = 100.0
        tol_ieee13 = 1e-6

        ctx_c, obj_c, _ = solve_welfare(
            feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀, allow_export = true,
        )
        dlmp_c = reduce(vcat, (extract_dlmp(ctx_c; bus = b, T = Th)' for b in load_buses))

        res = solve_admm(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, ρ = ρ_ieee13, maxiter = 200, tol = tol_ieee13, allow_export = true,
        )

        @test res.iters < 200                                    # converged before the fail-loud cap
        @test isapprox(res.welfare, obj_c; rtol = 1e-4)          # welfare match (ADMM-04)
        @test res.exact_maxgap < 1e-3                            # PF-04 on the converged DSO-OPT
        @test isapprox(res.λ, dlmp_c; atol = 1e-2, rtol = 1e-3)  # DADP match on every load node
    end
end

@testitem "admm: dual-ascent loop converges + fails loud on the cap (loop)" setup = [
    Phase6Fixtures,
    Phase4Fixtures,
] tags = [:admm] begin
    using TSODSO

    # RED until Wave 3 (plan 06-04) fills the ADMM dual-ascent loop.
    @test isdefined(TSODSO, :solve_admm)

    if isdefined(TSODSO, :solve_admm)
        feeder = Phase6Fixtures.two_bus_feeder()
        aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
        Th = Phase6Fixtures.T
        λ₀ = Phase6Fixtures.two_bus_lambda0()
        ρ = Phase6Fixtures.RHO_2BUS
        maxiter = 200
        tol = 1e-5

        # (a) The hand-rolled dual-ascent loop CONVERGES on the 2-bus (primal residual ≤ tol) in
        # well under maxiter iterations, recording each iteration in the returned AdmmResiduals.
        res = solve_admm(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, ρ = ρ, maxiter = maxiter, tol = tol, allow_export = true,
        )

        @test res.iters >= 1
        @test res.iters < maxiter                                   # converged before the cap
        @test res.residuals isa TSODSO.AdmmResiduals
        @test res.residuals.iters == res.iters                      # every iteration recorded
        @test last(res.residuals.primal_trace) <= tol               # primal-residual stop (Pitfall 2)

        # (b) The full return tuple is present and well-typed (RESEARCH System Architecture Diagram).
        @test res.λ === res.dadp                                    # dadp == λ (converged price)
        @test size(res.λ, 2) == Th                                  # one column per hour
        @test isfinite(res.welfare)                                 # welfare recomputed from primals
        @test res.exact_maxgap < 1e-3                               # converged DSO-OPT is PF-04 exact
        @test hasproperty(res.dso_ctx, :model)                      # converged DSO-OPT context

        # (c) Welfare is recomputed from PRIMAL values (Σ U_ag − λ₀ᵀp_import), NOT a penalized
        # subproblem objective — so it MATCHES the centralized welfare, which the penalized
        # objectives (carrying the ρ-penalty + dual terms) never would (RESEARCH Pattern 5).
        _, obj_c, _ = solve_welfare(
            feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀, allow_export = true,
        )
        @test isapprox(res.welfare, obj_c; rtol = 1e-4)

        # (d) FAIL-LOUD cap (RESEARCH Pitfall 2, threat T-06-03): a budget too small to reach a
        # consensus THROWS rather than silently returning the last (non-consensus) iterate. The
        # 2-bus needs several iterations, so maxiter = 1 with a tight tol cannot converge.
        @test_throws Exception solve_admm(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, ρ = ρ, maxiter = 1, tol = 1e-12, allow_export = true,
        )

        # (e) A non-positive maxiter is an INVALID budget: the loop never runs, so the residual
        # trace stays empty. This must throw a CLEAR boundary ArgumentError (WR-01), NOT the opaque
        # BoundsError the fail-loud cap's `last(residuals.primal_trace)` would raise on an empty
        # trace (the guard failing itself). maxiter = 0 AND a negative maxiter both reject up front.
        @test_throws ArgumentError solve_admm(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, ρ = ρ, maxiter = 0, tol = tol, allow_export = true,
        )
        @test_throws ArgumentError solve_admm(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, ρ = ρ, maxiter = -3, tol = tol, allow_export = true,
        )

        # (f) A DEGENERATE horizon T = 0 (with a length-0 λ₀ that would otherwise pass the shape
        # guard) is an INVALID problem: the coupling-entry count p = length(load_nodes)·T == 0, so
        # ε_pri = ε_dual = 0 and every residual sum is 0, making `converged` trivially true on
        # iteration 1 — a NONSENSICAL "converged" result for an empty problem. This must throw a
        # CLEAR boundary ArgumentError up front (IN-03), NOT silently report a degenerate optimum.
        @test_throws ArgumentError solve_admm(
            feeder, ConvexBranchFlow(), aggs;
            T = 0, λ₀ = Float64[], ρ = ρ, maxiter = maxiter, tol = tol, allow_export = true,
        )
    end
end

@testitem "admm: build-once subproblems, no per-iteration rebuild (resolve)" setup = [
    Phase6Fixtures,
    Phase4Fixtures,
] tags = [:admm] begin
    using TSODSO
    using JuMP: num_variables, num_constraints

    # RED until Wave 3 (plan 06-04) fills the ADMM loop; AGR-OPT / DSO-OPT builders are Wave 2.
    @test isdefined(TSODSO, :solve_admm)

    if isdefined(TSODSO, :solve_admm) &&
       isdefined(TSODSO, :AgrOpt) &&
       isdefined(TSODSO, :DsoOpt)
        feeder = Phase6Fixtures.two_bus_feeder()
        aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
        Th = Phase6Fixtures.T
        λ₀ = Phase6Fixtures.two_bus_lambda0()
        ρ = Phase6Fixtures.RHO_2BUS

        # ADMM-03 (RESEARCH Pattern 3 / Pitfall 6): the subproblem JuMP models are built ONCE
        # outside the loop and only re-solved via `set_objective_coefficient` — NO variable or
        # constraint is added per iteration. The observable no-rebuild signal: the CONVERGED
        # DSO-OPT model (after `res.iters` re-solves) has EXACTLY the same variable/constraint
        # counts as a FRESHLY-built DSO-OPT — a per-iteration rebuild or leaked state would grow
        # the model. `count_variable_in_set_constraints = true` also pins the SOC cones.
        dso_ref = build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀)
        nv_ref = num_variables(dso_ref.model)
        nc_ref = num_constraints(dso_ref.model; count_variable_in_set_constraints = true)

        res = solve_admm(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, ρ = ρ, maxiter = 200, allow_export = true,
        )

        @test res.iters < 200                                       # converged (loop actually ran)
        @test num_variables(res.dso_ctx.model) == nv_ref            # no per-iteration variable growth
        @test num_constraints(res.dso_ctx.model; count_variable_in_set_constraints = true) ==
              nc_ref                                                # no per-iteration constraint growth

        # AGR-OPT[j] is likewise built once: a freshly-built AGR-OPT and the loop's per-node model
        # share the same shape (the loop mutates only the coupling coefficient, never rebuilds).
        agr_ref = build_agr_opt(aggs[1], Th; ρ = ρ)
        @test num_variables(agr_ref.model) >= 1                     # a real per-node QP was built once
    end
end

@testitem "admm: final published primal certified — active-balance no hidden slack (crossval)" setup = [
    Phase6Fixtures,
    Phase4Fixtures,
] tags = [:admm] begin
    using TSODSO
    using JuMP: value

    # WR-01 / INFRA-03: the FINAL consolidation DSO-OPT solve tolerates the conic backend's BENIGN
    # ALMOST_OPTIMAL / NEARLY_FEASIBLE LABEL (an interior-point gap artefact under the ρ-penalty),
    # but its PRIMAL is PUBLISHED (it feeds the reported `welfare` and the PF-04 exactness gate). So
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
        feeder = Phase6Fixtures.two_bus_feeder()
        aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
        Th = Phase6Fixtures.T
        λ₀ = Phase6Fixtures.two_bus_lambda0()

        res = solve_admm(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, ρ = Phase6Fixtures.RHO_2BUS, maxiter = 200, allow_export = true,
        )

        # The active nodal balance of the PUBLISHED converged primal is satisfied with no hidden
        # slack — the WR-01 runtime certificate. `assert_no_slack` (the same gate solve_admm runs)
        # recomputes each residual from the solved variables and returns `lhs − rhs`; RE-running it
        # here on the returned context must not throw and must be ≈ 0.
        balance_p = res.dso_ctx.constraints[:balance_p]
        max_slack = maximum(
            abs(assert_no_slack(res.dso_ctx.model, balance_p[j, t]; atol = 1e-6))
            for j in 1:size(balance_p, 1), t in 1:size(balance_p, 2)
        )
        @test max_slack <= 1e-6                    # active balance is machine-exact at the optimum
        @test isfinite(res.welfare)               # welfare derived from the certified primal
        @test res.exact_maxgap < 1e-3             # PF-04 certificate from the certified primal
    end
end
