# test/test_agr.jl
#
# Seam: src/admm/AgrOpt.jl — the AGR-OPT per-node aggregator/device ADMM subproblem
# (ADMM-01 / ADMM-03, thesis eq. 3.46). Block 1 of the 2-block ADMM split.
#
# @testitem harness for the AGR-OPT subproblem. Every item name contains "agr" so
# `occursin("agr", ti.name)` selects them (06-VALIDATION filter substring); the build-once
# proof item additionally carries "resolve". Behavioral asserts sit BEHIND an `isdefined`
# guard so the runner never crashes while a symbol is still RED (mirrors test_admm.jl).
#
# CONTRACT pinned here (RESEARCH Pattern 4 / thesis 3.22/3.23/3.46):
#   build_agr_opt(agg::Aggregator, T; ρ) -> AgrOpt          # build-once per-node QP
#   solve_agr!(agr::AgrOpt, λ_j, c_j, ρ) -> (; pag, utility) # coefficient-update re-solve
# The subproblem reuses `Aggregator.contribute!` (and the device builders) VERBATIM — it is
# orchestration, not a re-implementation — and is built ONCE (num_variables/num_constraints
# invariant across re-solves; only `set_objective_coefficient` mutates it).

@testitem "agr: build_agr_opt builds per-node QP, solves OPTIMAL at zero price (agr)" setup = [
    Phase6Fixtures,
    Phase4Fixtures,
] tags = [:admm] begin
    using TSODSO
    using JuMP

    # RED until Task 1 (this plan) fills src/admm/AgrOpt.jl.
    @test isdefined(TSODSO, :build_agr_opt)
    @test isdefined(TSODSO, :AgrOpt)

    if isdefined(TSODSO, :build_agr_opt) && isdefined(TSODSO, :AgrOpt)
        feeder = Phase6Fixtures.two_bus_feeder()
        aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
        agg = aggs[1]
        Th = Phase6Fixtures.T
        ρ = Phase6Fixtures.RHO_2BUS

        agr = build_agr_opt(agg, Th; ρ = ρ)
        @test agr isa AgrOpt
        @test length(agr.pag) == Th
        @test agr.bus == agg.bus
        @test agr.T == Th

        # The objective is a QuadExpr carrying the FIXED −(ρ/2)·pag² penalty (built once).
        obj = objective_function(agr.model)
        @test obj isa QuadExpr

        # T coupling equalities `pag[t] == Σ p_inject − Pdc` (plus device equalities) ⇒ ≥ T.
        @test num_constraints(agr.model; count_variable_in_set_constraints = false) >= Th

        # A default zero-price model is a well-posed QP that solves OPTIMAL.
        assert_solved!(agr.model; dual = true)
        @test is_solved_and_feasible(agr.model; dual = true)
    end
end
