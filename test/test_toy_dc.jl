# Seam: models/toy_dc.jl — the rung-0 end-to-end integration. RED until plan 01-04.
@testitem "toy: rung0 DC single-node solves OPTIMAL and returns objective + dual (INFRA-02/03, PF-01)" tags = [:rung0] begin
    using TSODSO

    # A trivial single-node feeder routed through the full keystone:
    #   per-unit data → immutable Feeder → factory → ModelContext residual → assert_solved!
    buses = [TSODSO.Bus(1, 0.95, 1.05, true)]
    branches = TSODSO.Branch{Float64}[]
    feeder = TSODSO.Feeder(buses, branches, 1)

    ctx, obj, λ = TSODSO.solve_toy_dc(feeder)

    @test is_solved_and_feasible(ctx.model; allow_local = false)
    @test isfinite(obj)
    @test isfinite(λ)                       # nodal-balance dual (future DADP)
    @test haskey(ctx.residuals, :nodal_balance)   # residual seam exercised (PF-01)
end

# Package-quality gate (Aqua). Named to avoid the seam filter substrings so it is
# only run by the full suite. May be RED until deps/exports settle in later plans.
@testitem "quality: Aqua package checks (no stale deps / ambiguities / export issues)" begin
    using TSODSO, Aqua

    Aqua.test_all(TSODSO)
end
