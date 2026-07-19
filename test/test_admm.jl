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

        ctx_c, obj_c, _ = solve_welfare(
            feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀, allow_export = true,
        )
        dlmp_c = reduce(vcat, (extract_dlmp(ctx_c; bus = b, T = Th)' for b in load_buses))

        res = solve_admm(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, ρ = Phase6Fixtures.RHO_2BUS, allow_export = true,
        )

        @test isapprox(res.welfare, obj_c; rtol = 1e-4)          # welfare match (ADMM-04)
        @test res.exact_maxgap < 1e-3                            # PF-04 on the converged DSO-OPT
        @test isapprox(res.λ, dlmp_c; atol = 1e-2, rtol = 1e-3)  # DADP match on every load node
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

        # ADMM-03: the subproblem JuMP models are built ONCE and only re-solved via coefficient
        # updates — so the returned DSO-OPT model shape is INDEPENDENT of the iteration count
        # (a per-iteration rebuild would still be built-once-per-run, but the model-shape
        # invariant across differing maxiter is the observable no-growth signal, RESEARCH
        # Pattern 3 / Pitfall 6).
        res1 = solve_admm(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, ρ = ρ, maxiter = 1, allow_export = true,
        )
        res3 = solve_admm(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, ρ = ρ, maxiter = 3, allow_export = true,
        )

        m1, m3 = res1.dso_ctx.model, res3.dso_ctx.model
        @test num_variables(m1) == num_variables(m3)
        @test num_constraints(m1; count_variable_in_set_constraints = true) ==
              num_constraints(m3; count_variable_in_set_constraints = true)
        @test res3.iters >= res1.iters                          # more budget ⇒ no fewer iterations
    end
end
