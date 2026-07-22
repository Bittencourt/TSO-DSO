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

@testitem "agr: build_agr_opt builds per-node QP, solves OPTIMAL at zero price (agr)" setup =
    [Phase6Fixtures, Phase4Fixtures] tags = [:admm] begin
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

@testitem "agr: solve_agr! coefficient-update re-solve returns pag + utility (agr)" setup =
    [Phase6Fixtures, Phase4Fixtures] tags = [:admm] begin
    using TSODSO
    using JuMP

    # RED until Task 2 (this plan) adds solve_agr!.
    @test isdefined(TSODSO, :solve_agr!)

    if isdefined(TSODSO, :solve_agr!)
        feeder = Phase6Fixtures.two_bus_feeder()
        aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
        agg = aggs[1]
        Th = Phase6Fixtures.T
        ρ = Phase6Fixtures.RHO_2BUS

        agr = build_agr_opt(agg, Th; ρ = ρ)

        # Zero price + zero penalty target ⇒ OPTIMAL; returns a length-T pag and a utility value.
        # The App. C battery-complementarity gate runs INSIDE solve_agr! (must not throw).
        out = solve_agr!(agr, zeros(Th), zeros(Th), ρ)
        @test length(out.pag) == Th
        @test out.pag isa AbstractVector{<:Real}
        @test out.utility isa Real
        @test isfinite(out.utility)
    end
end

@testitem "agr: build-once — num_variables/num_constraints stable across re-solves (resolve)" setup =
    [Phase6Fixtures, Phase4Fixtures] tags = [:admm] begin
    using TSODSO
    using JuMP: num_variables, num_constraints

    # RED until Task 2 adds solve_agr!.
    @test isdefined(TSODSO, :solve_agr!)

    if isdefined(TSODSO, :solve_agr!) && isdefined(TSODSO, :build_agr_opt)
        feeder = Phase6Fixtures.two_bus_feeder()
        aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
        agg = aggs[1]
        Th = Phase6Fixtures.T
        ρ = Phase6Fixtures.RHO_2BUS

        agr = build_agr_opt(agg, Th; ρ = ρ)

        # ADMM-03 build-once proof: only `set_objective_coefficient` mutates the model, so
        # re-solving with DIFFERENT (λ_j, c_j) never changes its variable/constraint count.
        nv0 = num_variables(agr.model)
        nc0 = num_constraints(agr.model; count_variable_in_set_constraints = true)

        solve_agr!(agr, fill(1.0, Th), fill(0.2, Th), ρ)
        nv1 = num_variables(agr.model)
        nc1 = num_constraints(agr.model; count_variable_in_set_constraints = true)

        solve_agr!(agr, fill(-0.5, Th), fill(0.7, Th), ρ)
        nv2 = num_variables(agr.model)
        nc2 = num_constraints(agr.model; count_variable_in_set_constraints = true)

        @test nv0 == nv1 == nv2          # no variable added across re-solves (no rebuild)
        @test nc0 == nc1 == nc2          # no constraint added across re-solves (no rebuild)
    end
end

@testitem "agr: price coefficient actually shifts the net injection (agr)" setup =
    [Phase6Fixtures, Phase4Fixtures] tags = [:admm] begin
    using TSODSO

    # RED until Task 2 adds solve_agr!.
    @test isdefined(TSODSO, :solve_agr!)

    if isdefined(TSODSO, :solve_agr!)
        feeder = Phase6Fixtures.two_bus_feeder()
        aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
        agg = aggs[1]
        Th = Phase6Fixtures.T
        ρ = Phase6Fixtures.RHO_2BUS

        agr = build_agr_opt(agg, Th; ρ = ρ)

        # A high consumption price must measurably move the flexible schedule (the price truly
        # enters the QP via the pag[t] linear coefficient — RESEARCH Pattern 3).
        lo = solve_agr!(agr, zeros(Th), zeros(Th), ρ)
        hi = solve_agr!(agr, fill(20.0, Th), zeros(Th), ρ)
        @test !isapprox(collect(lo.pag), collect(hi.pag); atol = 1e-6)
    end
end

@testitem "agr: set_rho! mutate-then-solve equals fresh build at ρ, build-once (rho, adaptive)" setup =
    [Phase6Fixtures, Phase4Fixtures] tags = [:admm, :phase7] begin
    using TSODSO
    using JuMP: num_variables, num_constraints

    # RED until Task 1 (this plan) adds set_rho!.
    @test isdefined(TSODSO, :set_rho!)

    if isdefined(TSODSO, :set_rho!)
        feeder = Phase6Fixtures.two_bus_feeder()
        aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
        agg = aggs[1]
        Th = Phase6Fixtures.T
        ρ0 = Phase6Fixtures.RHO_2BUS
        ρ1 = 3.7 * ρ0                       # a genuine ρ change (τ-like ratchet)

        # A FIXED (λ_j, c_j) exercised on both paths so any difference is the ρ mutation alone.
        λj = fill(0.8, Th)
        cj = fill(0.15, Th)

        # MUTATE path: build at ρ0, set_rho!(agr, ρ1) — NO rebuild — then solve at ρ1.
        agr_mut = build_agr_opt(agg, Th; ρ = ρ0)
        nv0 = num_variables(agr_mut.model)
        nc0 = num_constraints(agr_mut.model; count_variable_in_set_constraints = true)
        set_rho!(agr_mut, ρ1)
        # Build-once (ADMM-04): a ρ change mutates ONLY objective coefficients — shape invariant.
        @test num_variables(agr_mut.model) == nv0
        @test num_constraints(agr_mut.model; count_variable_in_set_constraints = true) ==
              nc0
        out_mut = solve_agr!(agr_mut, λj, cj, ρ1; check_battery = false, strict = false)

        # FRESH path: build directly at ρ1, solve the SAME coefficients.
        agr_fresh = build_agr_opt(agg, Th; ρ = ρ1)
        out_fresh = solve_agr!(agr_fresh, λj, cj, ρ1; check_battery = false, strict = false)

        # Equivalence proof: the in-place quadratic mutation reproduces a fresh build at ρ1.
        @test isapprox(
            collect(out_mut.pag),
            collect(out_fresh.pag);
            atol = 1e-6,
            rtol = 1e-5,
        )
        @test isapprox(out_mut.utility, out_fresh.utility; atol = 1e-6, rtol = 1e-5)
    end
end
