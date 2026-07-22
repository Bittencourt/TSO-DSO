# test/test_dso.jl
#
# Seam: src/admm/DsoOpt.jl — the whole-network DSO-OPT SOCP ADMM subproblem (ADMM-01/03,
# thesis eq. 3.47). Plan 06-03 (Wave 2) turns these GREEN by implementing `build_dso_opt` /
# `solve_dso!`. Every item name contains "dso" so `occursin("dso", ti.name)` selects them; the
# build-once item carries "resolve" (06-VALIDATION filter substring).
#
# CONTRACT pinned here:
#   build_dso_opt(feeder, aggregators, T; ρ, λ₀) -> DsoOpt
#     reuses ConvexBranchFlow.contribute! VERBATIM (:l present), a free-sign priced frontier
#     p_import/q_import, a per-load-node ACTIVE coupling `pag`, and the CONSTANT reactive draw
#     closing :balance_q at every bus (proven by an IEEE-13 OPTIMAL solve — an active-only
#     closure would be infeasible at φ = 0.90).
#   solve_dso!(dso, λ, a, ρ; check_exact) -> (; pag_dso, p_import, exact_maxgap)
#     updates ONLY the linear coefficient of each `pag[j,t]` (set_objective_coefficient) and,
#     on convergence (check_exact=true), runs the PF-04 exactness gate.

@testitem "dso: build_dso_opt builds whole-network SOCP, reuses ConvexBranchFlow (2-bus)" setup =
    [Phase6Fixtures, Phase4Fixtures] tags = [:dso] begin
    using TSODSO
    using JuMP

    @test isdefined(TSODSO, :build_dso_opt)
    @test isdefined(TSODSO, :DsoOpt)

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    Th = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()
    ρ = Phase6Fixtures.RHO_2BUS

    dso = build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀)
    @test dso isa TSODSO.DsoOpt

    # VERBATIM ConvexBranchFlow reuse: the SOC squared-current :l is stashed in pf_vars.
    @test haskey(dso.ctx.meta, :pf_vars)
    @test haskey(dso.ctx.meta[:pf_vars], :l)

    # feeder / T stashed for the PF-04 exactness gate.
    @test dso.ctx.meta[:feeder] === feeder
    @test dso.ctx.meta[:T] == Th

    # Load nodes = the single non-root bus 2; the coupling container is bus × time.
    @test dso.load_nodes == [2]
    @test size(dso.pag) == (1, Th)   # not yet solved — just the container shape

    # A free-sign frontier p_import + q_import at the root, and BOTH balances registered.
    @test haskey(dso.ctx.meta, :p_import)
    @test haskey(dso.ctx.meta, :q_import)
    @test haskey(dso.ctx.constraints, :balance_p)
    @test haskey(dso.ctx.constraints, :balance_q)

    # The built model solves OPTIMAL with the default (zero) coupling price — feasible network.
    assert_solved!(dso.model; dual = true)
    @test isfinite(objective_value(dso.model))
end

@testitem "dso: build_dso_opt on IEEE-13 solves OPTIMAL — reactive closure feasible (ieee13)" setup =
    [Phase6Fixtures, Phase4Fixtures] tags = [:dso] begin
    using TSODSO
    using JuMP

    # The reactive closure is MANDATORY (ConvexBranchFlow sets reactive=true): each load node's
    # constant draw −Pdc·tan(acos φ) (φ=0.90) is injected into :Rq and served by a free-sign
    # q_import at the root. An ACTIVE-ONLY closure would pin :Rq to zero at every load bus and
    # be INFEASIBLE — so a clean OPTIMAL solve here proves the reactive path is right.
    feeder = ieee13_modified()
    aggs = Phase4Fixtures.build_ieee13_ground_aggregators(feeder)
    Th = Phase4Fixtures.T
    λ₀ = Phase4Fixtures.mem_price_profile()
    ρ = Phase6Fixtures.RHO_2BUS

    dso = build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀)

    # Every non-root bus is a load node (transit-node guard passed).
    @test dso.load_nodes == collect(2:length(feeder.buses))

    assert_solved!(dso.model; dual = true)
    @test isfinite(objective_value(dso.model))

    # The reactive frontier actually carries power (the constant draw is served, not zeroed):
    # a regression that dropped the reactive closure would leave q_import ≡ 0.
    q_import = dso.ctx.meta[:q_import]
    @test any(t -> abs(value(q_import[t])) > 1e-8, 1:Th)
end

@testitem "dso: build_dso_opt guards — empty aggs, λ₀ shape, root aggregator, out-of-range" setup =
    [Phase7Fixtures, Phase6Fixtures, Phase4Fixtures] tags = [:dso] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    Th = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()
    ρ = Phase6Fixtures.RHO_2BUS

    # Empty aggregators.
    @test_throws ArgumentError build_dso_opt(feeder, typeof(aggs)(), Th; ρ = ρ, λ₀ = λ₀)
    # λ₀ shape mismatch.
    @test_throws ArgumentError build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀[1:(Th - 1)])

    # GENUINELY-invalid buses STILL fail loud — the transit relaxation (plan 07-03 / Pitfall 5)
    # only admits VALID zero-injection nodes, never a mislocated aggregator.
    buses3 =
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false), Bus(3, 0.95, 1.05, false)]
    branches3 =
        [Branch(1, 2, 1e-3, 1e-3, SMAX_NO_LIMIT), Branch(2, 3, 1e-3, 1e-3, SMAX_NO_LIMIT)]
    feeder3 = Feeder(buses3, branches3, 1)

    # Aggregator ON the root bus — the frontier carries no aggregator (thesis 3.47) → fail loud.
    root_agg = Phase7Fixtures.build_ieee123_aggregators(feeder3; load_buses = [1])
    @test_throws ArgumentError build_dso_opt(feeder3, root_agg, Th; ρ = ρ, λ₀ = λ₀)

    # Aggregator on a bus OUTSIDE 1:N (bus 3 fed to the 2-bus feeder, N=2) → fail loud.
    oob_agg = Phase7Fixtures.build_ieee123_aggregators(feeder3; load_buses = [3])
    @test_throws ArgumentError build_dso_opt(feeder, oob_agg, Th; ρ = ρ, λ₀ = λ₀)

    # A genuine TRANSIT bus (aggregator only on bus 2, bus 3 zero-injection) is now ADMITTED
    # (Pitfall 5 relaxation) — build succeeds and the coupling axis excludes the transit node.
    dso3 = build_dso_opt(feeder3, aggs, Th; ρ = ρ, λ₀ = λ₀)
    @test dso3.load_nodes == [2]                       # coupling axis = aggregator buses only
    @test haskey(dso3.ctx.constraints, :balance_p)     # balance still closed at all N buses
    @test haskey(dso3.ctx.constraints, :balance_q)
end

@testitem "dso: transit zero-injection bus admitted, balance closes, solves OPTIMAL (transit, dso)" setup =
    [Phase7Fixtures, Phase6Fixtures, Phase4Fixtures] tags = [:dso, :phase7] begin
    using TSODSO
    using JuMP

    # SMALL SYNTHETIC feeder (NOT ieee123_modified — that is a parallel-wave stub at 07-03 time):
    # root(1) → transit(2, NO aggregator) → load(3, aggregator). Bus 2 is a genuine zero-injection
    # junction the Phase-6 guard rejected; plan 07-03 admits it (RESEARCH Pitfall 5).
    buses = [Bus(1, 0.95, 1.05, true), Bus(2, 0.9, 1.1, false), Bus(3, 0.9, 1.1, false)]
    branches =
        [Branch(1, 2, 0.02, 0.02, SMAX_NO_LIMIT), Branch(2, 3, 0.02, 0.02, SMAX_NO_LIMIT)]
    feeder = Feeder(buses, branches, 1)

    aggs = Phase7Fixtures.build_ieee123_aggregators(feeder; load_buses = [3])   # ONLY bus 3
    Th = Phase7Fixtures.T
    λ₀ = Phase7Fixtures.ieee123_lambda0()
    ρ = Phase7Fixtures.RHO0

    dso = build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀)

    # Coupling axis DECOUPLED from the balance-closure axis: only the aggregator bus 3 is a load
    # node; bus 2 is a transit node absent from the coupling.
    @test dso.load_nodes == [3]
    @test size(dso.pag) == (1, Th)

    # Balance registered at ALL N buses (root + transit + load), so the SOCP is well-determined.
    @test haskey(dso.ctx.constraints, :balance_p)
    @test haskey(dso.ctx.constraints, :balance_q)
    @test size(dso.ctx.residuals[:Rp]) == (length(feeder.buses), Th)

    # The zero-injection transit closure is NOT under-determined: a clean OPTIMAL solve proves it.
    assert_solved!(dso.model; dual = true)
    @test isfinite(objective_value(dso.model))
end

@testitem "dso: solve_dso! zero-price OPTIMAL returns pag_dso/p_import of right shape" setup =
    [Phase6Fixtures, Phase4Fixtures] tags = [:dso] begin
    using TSODSO
    using JuMP

    @test isdefined(TSODSO, :solve_dso!)

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    Th = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()
    ρ = Phase6Fixtures.RHO_2BUS

    dso = build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀)

    # Zero coupling price + zero AGR target ⇒ the fixed ρ/2 penalty pins pag_dso near 0.
    λ = Dict(j => zeros(Th) for j in dso.load_nodes)
    a = Dict(j => zeros(Th) for j in dso.load_nodes)

    res = solve_dso!(dso, λ, a, ρ)   # check_exact defaults to false (mid-loop)

    @test size(res.pag_dso) == (length(dso.load_nodes), Th)
    @test length(res.p_import) == Th
    @test all(isfinite, res.pag_dso)
    @test all(isfinite, res.p_import)
    @test res.exact_maxgap === nothing   # gate not run mid-loop
end

@testitem "dso: solve_dso! check_exact passes PF-04 gate on 2-bus and IEEE-13 (exact)" setup =
    [Phase6Fixtures, Phase4Fixtures] tags = [:dso] begin
    using TSODSO
    using JuMP

    # --- 2-bus dual-sign anchor ---
    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    Th = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()
    ρ = Phase6Fixtures.RHO_2BUS

    dso = build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀)
    λ = Dict(j => zeros(Th) for j in dso.load_nodes)
    a = Dict(j => zeros(Th) for j in dso.load_nodes)

    res = solve_dso!(dso, λ, a, ρ; check_exact = true)   # convergence call
    @test res.exact_maxgap !== nothing
    @test res.exact_maxgap < 1e-3                          # PF-04: SOC cone tight (exact)
    @test haskey(dso.ctx.meta, :socp_maxgap)

    # --- IEEE-13 ground fixture (allow_export semantics; reactive closure exercised) ---
    feeder13 = ieee13_modified()
    aggs13 = Phase4Fixtures.build_ieee13_ground_aggregators(feeder13)
    T13 = Phase4Fixtures.T
    λ₀13 = Phase4Fixtures.mem_price_profile()

    dso13 = build_dso_opt(feeder13, aggs13, T13; ρ = ρ, λ₀ = λ₀13)
    λ13 = Dict(j => zeros(T13) for j in dso13.load_nodes)
    a13 = Dict(j => zeros(T13) for j in dso13.load_nodes)

    res13 = solve_dso!(dso13, λ13, a13, ρ; check_exact = true)
    @test res13.exact_maxgap < 1e-3                        # PF-04 exact on the radial feeder
end

@testitem "dso: build-once — num_variables/num_constraints unchanged across re-solves (resolve)" setup =
    [Phase6Fixtures, Phase4Fixtures] tags = [:dso] begin
    using TSODSO
    using JuMP: num_variables, num_constraints

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    Th = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()
    ρ = Phase6Fixtures.RHO_2BUS

    dso = build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀)

    nv0 = num_variables(dso.model)
    nc0 = num_constraints(dso.model; count_variable_in_set_constraints = true)

    # Two re-solves with DIFFERENT coupling prices/targets — only coefficients mutate.
    λ1 = Dict(j => fill(0.10, Th) for j in dso.load_nodes)
    a1 = Dict(j => fill(0.02, Th) for j in dso.load_nodes)
    solve_dso!(dso, λ1, a1, ρ)

    λ2 = Dict(j => fill(-0.05, Th) for j in dso.load_nodes)
    a2 = Dict(j => fill(0.03, Th) for j in dso.load_nodes)
    solve_dso!(dso, λ2, a2, ρ)

    # ADMM-03: the model shape is INVARIANT across re-solves (no rebuild).
    @test num_variables(dso.model) == nv0
    @test num_constraints(dso.model; count_variable_in_set_constraints = true) == nc0
end

@testitem "dso: set_rho! mutate-then-solve equals fresh build at ρ, build-once (rho, adaptive)" setup =
    [Phase6Fixtures, Phase4Fixtures] tags = [:dso, :phase7] begin
    using TSODSO
    using JuMP: num_variables, num_constraints

    # RED until Task 1 (this plan) adds set_rho!.
    @test isdefined(TSODSO, :set_rho!)

    if isdefined(TSODSO, :set_rho!)
        feeder = Phase6Fixtures.two_bus_feeder()
        aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
        Th = Phase6Fixtures.T
        λ₀ = Phase6Fixtures.two_bus_lambda0()
        ρ0 = Phase6Fixtures.RHO_2BUS
        ρ1 = 2.5 * ρ0                       # a genuine ρ change

        # MUTATE path: build at ρ0, set_rho!(dso, ρ1) — NO rebuild — then solve at ρ1.
        dso_mut = build_dso_opt(feeder, aggs, Th; ρ = ρ0, λ₀ = λ₀)
        ln = dso_mut.load_nodes
        λ = Dict(j => fill(0.05, Th) for j in ln)
        a = Dict(j => fill(0.02, Th) for j in ln)

        nv0 = num_variables(dso_mut.model)
        nc0 = num_constraints(dso_mut.model; count_variable_in_set_constraints = true)
        set_rho!(dso_mut, ρ1)
        # Build-once (ADMM-04): a ρ change mutates ONLY objective coefficients — shape invariant.
        @test num_variables(dso_mut.model) == nv0
        @test num_constraints(dso_mut.model; count_variable_in_set_constraints = true) ==
              nc0
        res_mut = solve_dso!(dso_mut, λ, a, ρ1)

        # FRESH path: build directly at ρ1, solve the SAME coupling price/target.
        dso_fresh = build_dso_opt(feeder, aggs, Th; ρ = ρ1, λ₀ = λ₀)
        res_fresh = solve_dso!(dso_fresh, λ, a, ρ1)

        # Equivalence proof: the in-place quadratic mutation reproduces a fresh build at ρ1.
        # (pag_dso is a Vector-axis DenseAxisArray — index over its axes rather than `collect`.)
        pag_mut = Float64[res_mut.pag_dso[j, t] for j in ln, t in 1:Th]
        pag_fresh = Float64[res_fresh.pag_dso[j, t] for j in ln, t in 1:Th]
        @test isapprox(pag_mut, pag_fresh; atol = 1e-6, rtol = 1e-5)
        @test isapprox(
            collect(res_mut.p_import),
            collect(res_fresh.p_import);
            atol = 1e-6,
            rtol = 1e-5,
        )
    end
end
