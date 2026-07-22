# Seam: models/toy_dc.jl — the rung-0 end-to-end integration. RED until plan 01-04.
@testitem "toy: rung0 DC single-node solves OPTIMAL and returns objective + dual (INFRA-02/03, PF-01)" tags =
    [:rung0] begin
    using TSODSO, JuMP   # JuMP for `is_solved_and_feasible` (matches test_factory.jl / test_status.jl)

    # A trivial single-node feeder routed through the full keystone:
    #   per-unit data → immutable Feeder → factory → ModelContext residual → assert_solved!
    buses = [TSODSO.Bus(1, 0.95, 1.05, true)]
    branches = TSODSO.Branch{Float64}[]
    feeder = TSODSO.Feeder(buses, branches, 1)

    ctx, obj, λ = TSODSO.solve_toy_dc(feeder)

    @test is_solved_and_feasible(ctx.model; allow_local = false)

    # Pin the KNOWN closed-form optimum, not just finiteness (WR-04): welfare is
    # `3·p_load - 1·p_import` with `p_load` capped at 1.0 and the nodal balance
    # forcing `p_import == p_load`, so the optimum is p_load = p_import = 1.0,
    # giving obj = 3·1 - 1·1 = 2.0 and dual(balance) = +1.0 (marginal import
    # cost). This catches a regression in the objective coefficients, the
    # balance-residual sign, or the dual extraction — all of which would still
    # return finite numbers and pass a bare `isfinite` check.
    @test obj ≈ 2.0 atol = 1e-8            # welfare at p_load = p_import = 1.0
    @test λ ≈ 1.0 atol = 1e-8              # nodal-balance dual (future DADP)
    @test haskey(ctx.residuals, :nodal_balance)   # residual seam exercised (PF-01)
end

# Package-quality gate (Aqua). Named to avoid the seam filter substrings so it is
# only run by the full suite. May be RED until deps/exports settle in later plans.
@testitem "quality: Aqua package checks (no stale deps / ambiguities / export issues)" begin
    using TSODSO, Aqua

    # StableRNGs is now genuinely loaded by src/data/profiles.jl (plan 03-02), so the
    # Wave-0 stale-deps ignore is no longer needed.
    Aqua.test_all(TSODSO)
end
