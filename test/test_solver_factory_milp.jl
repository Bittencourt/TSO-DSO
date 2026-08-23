# test/test_solver_factory_milp.jl
#
# Seam: src/solver/factory.jl (INFRA-02), `select_optimizer(::MILP())`. Phase 24
# (24-RESEARCH.md Priority Finding 4) requires `mip_rel_gap => 0.0` so the planning
# layer's later "exact lattice termination" claim (D-13) is not silently undermined by
# a loose INNER MILP gap. This file lives at the solver-factory seam but is tagged
# `[:planning]` because MILP exactness is the planning layer's own solver dependency —
# no other tier in this project currently consumes `MILP()`.
#
# Pure factory-level smoke test: a tiny standalone binary-knapsack MILP, NOT reusing
# any planning fixture (24-01-PLAN.md Task 1).

@testitem "solver factory: select_optimizer(::MILP()) sets mip_rel_gap=>0.0 and solves a tiny knapsack exactly (INT-01)" tags =
    [:planning] begin
    using TSODSO
    using JuMP
    using JuMP: MOI

    # Tiny binary-knapsack smoke test: capacity 2, 3 items with values [3, 2, 1] and unit
    # weights. Known-by-hand optimum: pick items 1 and 2 (value 5), capacity binds at 2.
    model = Model(TSODSO.select_optimizer(TSODSO.MILP()))
    @variable(model, x[1:3], Bin)
    @constraint(model, x[1] + x[2] + x[3] <= 2)
    @objective(model, Max, 3x[1] + 2x[2] + x[3])
    optimize!(model)

    # (a) solves to MOI.OPTIMAL with the exact known-by-hand integer optimum.
    @test termination_status(model) == MOI.OPTIMAL
    @test isapprox(objective_value(model), 5.0; atol = 1e-6)
    @test isapprox(value(x[1]), 1.0; atol = 1e-6)
    @test isapprox(value(x[2]), 1.0; atol = 1e-6)
    @test isapprox(value(x[3]), 0.0; atol = 1e-6)

    # (b) RESEARCH.md Common Pitfall 2 / Assumption A2's "quick empirical check": mip_rel_gap
    # => 0.0 must NOT stall branch-and-bound on this tiny instance. If it ever does (a
    # non-OPTIMAL status), that would be a finding to document plainly in factory.jl's own
    # comment (fall back to a small positive mip_rel_gap, e.g. 1e-9) — not something to
    # silently paper over. Empirically: it does not stall.
    @test termination_status(model) != MOI.OTHER_LIMIT
end
