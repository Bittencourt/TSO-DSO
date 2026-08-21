# test/test_admm_timeout.jl
#
# Plain Test.jl script (NOT `@testitem`) for `solve_admm`'s `time_limit_s` wall-clock exit
# (D-18, Phase 25). Run directly: `julia --project=. test/test_admm_timeout.jl`.
#
# Deliberately NOT a TestItemRunner `@testitem`: this project's recorded trap is that
# TestItemRunner invoked via `julia --project=. -e '... @run_package_tests ...'` (a `-e`
# string with no real `__source__.file`) resolves the test root via cwd and can pick up
# SIBLING WORKTREE test copies, producing spurious failures. A plain script with a real
# entrypoint file sidesteps that entirely — it never goes through the runner at all.
#
# Uses `ieee13_modified()` + `build_population(:default, feeder, :ieee13, profiles, seed)` +
# `ConvexBranchFlow()` + `build_price(:mem, T, nothing)` (the SAME building blocks
# `scripts/thesis_caseA.jl` uses) — this test exercises the wall-clock EXIT MECHANICS, not
# economic pricing accuracy, but it still needs the REAL digitized MEM price shape (not a
# flat constant): the congestion-driven IEEE-13 fixture only converges after ~dozens of
# iterations at ρ=100 (mirrors test/test_admm.jl's own ieee13 crossval fixture), which is
# what gives the wall-clock check in Test 2 something genuine to interrupt. A flat λ₀ = 1
# was tried first and converged in ITERATION 1 (no congestion to resolve), so the budget
# check never fired before the final consolidation pass — which then hit an UNRELATED
# pre-existing battery-complementarity gate on that off-nominal price. Never a dependency on
# TestItemRunner-only `@testmodule` fixtures — self-contained via the exported `src/`
# builders only.

using Test
using TSODSO

# SEED = 20260718 matches test/fixtures_phase4.jl's `build_ieee13_ground_aggregators`
# default seed EXACTLY — the "ground" congestion-driven per-bus profile draw that needs
# ~dozens of ADMM iterations to converge at ρ=100 (test/test_admm.jl's own ieee13 crossval
# precedent). A different seed (42, tried first) drew a materially less-congested
# population that converged trivially on ITERATION 1 — before the wall-clock check ever
# got a chance to fire.
const SEED = 20260718
const T = 24

feeder = ieee13_modified()
profiles = generate_profiles(; seed = SEED, T = T)
aggs = build_population(:default, feeder, :ieee13, profiles, SEED)
pf = ConvexBranchFlow()
λ₀ = build_price(:mem, T, nothing)   # digitized thesis Fig 4.5 MEM price (see header note)

# ρ = 100.0 mirrors test/test_admm.jl's own IEEE-13 crossval fixture (congestion-driven,
# converges only after ~dozens of iterations at this penalty) — small enough that a
# maxiter = 1 budget cannot possibly reach consensus (Test 1) and large enough that a
# single AGR-OPT/DSO-OPT solve pair takes measurably more than 1e-9s (Test 2).
const RHO = 100.0

@testset "solve_admm time_limit_s (D-18)" begin
    # Test 1: the PRE-EXISTING behavior (time_limit_s absent/nothing) is BYTE-IDENTICAL —
    # the fail-loud cap still throws on a budget too small to reach consensus, exactly as
    # test/test_admm.jl's "fails loud on the cap" testitem pins.
    @test_throws Exception solve_admm(
        feeder,
        pf,
        aggs;
        T = T,
        λ₀ = λ₀,
        ρ = RHO,
        maxiter = 1,
        tol = 1e-12,
        allow_export = true,
    )

    # Test 2: an effectively-zero time_limit_s returns (does NOT throw) a NamedTuple with
    # status == :budget_exceeded, iters < maxiter, and dadp/λ === nothing — a caller cannot
    # silently mistake a mid-loop iterate for a certified price.
    res_budget = solve_admm(
        feeder,
        pf,
        aggs;
        T = T,
        λ₀ = λ₀,
        ρ = RHO,
        maxiter = 200,
        allow_export = true,
        time_limit_s = 1e-9,
    )
    @test res_budget.status == :budget_exceeded
    @test res_budget.iters < 200
    @test res_budget.dadp === nothing
    @test res_budget.λ === nothing
    @test res_budget.welfare === nothing
    @test res_budget.exact_maxgap === nothing
    @test res_budget.mu_q === nothing
    @test res_budget.q_devices == Dict{Int, Vector{Float64}}()
    @test hasproperty(res_budget.dso_ctx, :model)   # dso_ctx still returned (build-once model)
    @test res_budget.residuals isa TSODSO.AdmmResiduals

    # Test 3: normal convergence (no time limit) now ALSO carries status == :converged, with
    # every OTHER field unchanged from today (byte-identical additive field).
    res_ok = solve_admm(
        feeder,
        pf,
        aggs;
        T = T,
        λ₀ = λ₀,
        ρ = RHO,
        maxiter = 200,
        allow_export = true,
    )
    @test res_ok.status == :converged
    @test res_ok.iters < 200
    @test res_ok.dadp !== nothing
    @test res_ok.λ === res_ok.dadp
    @test isfinite(res_ok.welfare)
    @test res_ok.exact_maxgap < 1e-3
end

println("test_admm_timeout.jl: ALL TESTS PASSED")
