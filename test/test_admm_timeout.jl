# test/test_admm_timeout.jl
#
# `solve_admm`'s `time_limit_s` wall-clock exit: an effectively-zero budget returns a
# `:budget_exceeded` result with every price field `nothing` (a caller cannot mistake a
# mid-loop iterate for a certified price), the `maxiter` cap still throws a typed
# `ConvergenceError`, and an unbudgeted run converges with `:converged`.
#
# Uses `ieee13_modified()` + `build_population(:default, feeder, :ieee13, profiles, seed)` +
# `ConvexBranchFlow()` + `build_price(:mem, T, nothing)` (the SAME building blocks
# `scripts/thesis_caseA.jl` uses) — this exercises the wall-clock EXIT MECHANICS, not
# economic pricing accuracy, but it still needs the REAL digitized MEM price shape (not a
# flat constant): the congestion-driven IEEE-13 fixture only converges after ~dozens of
# iterations at ρ = 100 (mirrors test/test_admm.jl's own ieee13 crossval fixture), which is
# what gives the wall-clock check something genuine to interrupt. A flat λ₀ = 1 was tried
# first and converged in ITERATION 1 (no congestion to resolve), so the budget check never
# fired before the final consolidation pass — which then hit an UNRELATED pre-existing
# battery-complementarity gate on that off-nominal price.
#
# Seed 20260718 matches test/fixtures_ieee13.jl's `build_ieee13_ground_aggregators` default
# seed EXACTLY — the "ground" congestion-driven per-bus profile draw. A different seed (42,
# tried first) drew a materially less-congested population that converged trivially on
# ITERATION 1 — before the wall-clock check ever got a chance to fire.
#
# ρ = 100.0 is small enough that a maxiter = 1 budget cannot reach consensus and large enough
# that a single AGR-OPT/DSO-OPT solve pair takes measurably more than 1e-9 s.
#
# Self-contained via `src/` builders only (no `@testmodule` fixtures); each item builds the
# fixture inline.

@testitem "admm_timeout: time_limit_s returns :budget_exceeded with no price fields, and the maxiter cap still throws ConvergenceError" tags =
    [:admm] begin
    using TSODSO, Test
    using TSODSO: build_population, build_price

    seed = 20260718
    T = 24
    feeder = ieee13_modified()
    profiles = generate_profiles(; seed = seed, T = T)
    aggs = build_population(:default, feeder, :ieee13, profiles, seed)
    pf = ConvexBranchFlow()
    λ₀ = build_price(:mem, T, nothing)   # digitized thesis Fig 4.5 MEM price (see header)
    rho = 100.0

    # Without a time limit the fail-loud cap still throws on a budget too small to reach
    # consensus, exactly as test/test_admm.jl's "fails loud on the cap" item pins.
    @test_throws ConvergenceError solve_admm(
        feeder,
        pf,
        aggs;
        T = T,
        λ₀ = λ₀,
        ρ = rho,
        maxiter = 1,
        tol = 1e-12,
        allow_export = true,
    )

    # An effectively-zero time_limit_s returns (does NOT throw) a NamedTuple with
    # status == :budget_exceeded, iters < maxiter, and dadp/λ === nothing.
    res_budget = solve_admm(
        feeder,
        pf,
        aggs;
        T = T,
        λ₀ = λ₀,
        ρ = rho,
        maxiter = 200,
        allow_export = true,
        time_limit_s = 1e-9,
    )
    @test res_budget.status == :budget_exceeded
    @test res_budget.status in TSODSO.STATUS_VOCABULARY.solve_admm
    @test res_budget.iters < 200
    @test res_budget.dadp === nothing
    @test res_budget.λ === nothing
    @test res_budget.welfare === nothing
    @test res_budget.exact_maxgap === nothing
    @test res_budget.mu_q === nothing
    @test res_budget.q_devices == Dict{Int, Vector{Float64}}()
    @test hasproperty(res_budget.dso_ctx, :model)   # dso_ctx still returned (build-once model)
    @test res_budget.residuals isa TSODSO.AdmmResiduals
end

@testitem "admm_timeout: an unbudgeted run converges with :converged and populated fields" tags =
    [:admm] begin
    using TSODSO, Test
    using TSODSO: build_population, build_price

    seed = 20260718
    T = 24
    feeder = ieee13_modified()
    profiles = generate_profiles(; seed = seed, T = T)
    aggs = build_population(:default, feeder, :ieee13, profiles, seed)
    pf = ConvexBranchFlow()
    λ₀ = build_price(:mem, T, nothing)
    rho = 100.0

    # Normal convergence (no time limit) carries status == :converged with every price
    # field populated.
    res_ok = solve_admm(
        feeder,
        pf,
        aggs;
        T = T,
        λ₀ = λ₀,
        ρ = rho,
        maxiter = 200,
        allow_export = true,
    )
    @test res_ok.status == :converged
    @test res_ok.status in TSODSO.STATUS_VOCABULARY.solve_admm
    @test res_ok.iters < 200
    @test res_ok.dadp !== nothing
    @test res_ok.λ === res_ok.dadp
    @test isfinite(res_ok.welfare)
    @test res_ok.exact_maxgap < 1e-3
end
