# test/test_actor_objective.jl
#
# Seam: src/actors/{actor_objective,Portfolio,efficiency}.jl, the AgrOpt hook (plan 44-01) and the
# solve_welfare / solve_admm `actors` wiring (plan 44-02). Every item name contains
# "actor objective". Accumulators live in functions/`let`.
#
# MEASURED TOLERANCES (plan 44-02; every band = 3x the observed max, never picked).
# Observed over seeds {20260719,20260720,20260721} (two-bus, wedge m = 5.0) and
# {20260718,20260719,20260720} (IEEE-13 ground fixture, 2 portfolios x 5 buses, m = 0.5 on
# portfolio 1), julia 1.12.5:
#
#   quantity                                   observed max / min              pinned band
#   ---------------------------------------    ----------------------------    ---------------
#   central |W(Profit(0)) - W(default)|         3.09e-11 (both fixtures)        9.3e-11  (tol_cen_pass)
#   central dadp Profit(0) vs default          0.0 (bitwise)                   ==
#   ADMM Profit(0) vs default (W,dadp,iters)   bitwise equal                   ==
#   welfare gap ADMM vs central, relative      4.12e-8 (IEEE-13), 7.7e-9 (2b)  1.24e-7
#   dadp gap ADMM vs central, abs (IEEE-13)    4.09e-3                         1.23e-2
#   dadp gap ADMM vs central, abs (two-bus)    1.35e-5                         4.1e-5
#   central DeltaW = W_opt - W_soc             min 1.96e-3 (IEEE), 0.248 (2b)  > min/3 (liveness)
#   negative DeltaW excursion (any path)       none observed                   slack = tol_cen_pass
#                                                                              (ADMM: 1.24e-7 * |W|)
#   ADMM net-injection shift, m != 0           min 1.42e-2 (IEEE), 6.8e-3 (2b) > min/3 (liveness)
#
# Note: on the two-bus fixture the wedge is dormant for |m| <~ 2 (dispatch kink: shift 7e-8 at
# m = 2, 6.8e-3 at m = 5); m = 5.0 is therefore the measured live operating point.

@testitem "actor objective: hierarchy hooks and default predicate" tags = [:actors] begin
    using TSODSO
    using TSODSO:
        agr_objective, agr_linear_offset, wedge_term, is_default_objective, _wedge_vec

    U = 3.0
    @test agr_objective(WelfareObjective(), U, nothing, 3) === U
    @test agr_objective(ProfitObjective(0.5), U, nothing, 3) === U
    @test agr_linear_offset(WelfareObjective(), 3) === nothing
    @test agr_linear_offset(ProfitObjective(0.5), 3) == [0.5, 0.5, 0.5]
    v = agr_linear_offset(ProfitObjective([1, 2, 3]), 3)
    @test v isa Vector{Float64} && v == [1.0, 2.0, 3.0]
    @test is_default_objective(WelfareObjective())
    @test !is_default_objective(ProfitObjective(0.0))
    @test wedge_term(WelfareObjective(), [1.0], 1) === nothing
    m = [0.1, 0.2, 0.3]
    net = [1.0, -2.0, 4.0]
    @test wedge_term(ProfitObjective(m), net, 3) == sum(m[t] * net[t] for t in 1:3)
    @test wedge_term(ProfitObjective(2.0), net, 3) == 2.0 * sum(net)
end

@testitem "actor objective: wedge guards throw ArgumentError" tags = [:actors] begin
    using TSODSO
    using TSODSO: agr_linear_offset, wedge_term

    @test_throws ArgumentError ProfitObjective(NaN)
    @test_throws ArgumentError ProfitObjective(Inf)
    @test_throws ArgumentError ProfitObjective([0.1, NaN])
    @test_throws ArgumentError agr_linear_offset(ProfitObjective([1.0, 2.0]), 3)
    @test_throws ArgumentError wedge_term(ProfitObjective([1.0, 2.0]), [1.0, 2.0, 3.0], 3)
    @test_throws ArgumentError wedge_term(ProfitObjective(1.0), [1.0, 2.0], 3)
end

@testitem "actor objective: Portfolio guards and _expand_actors" tags = [:actors] begin
    using TSODSO
    using TSODSO: _expand_actors

    mk(bus) = Aggregator(bus, 1.0, [Deferrable(bus, 1, 3, 1.0, 0.5, 0.5)], zeros(3))
    a, b, c = mk(2), mk(3), mk(4)

    @test_throws ArgumentError Portfolio(Aggregator[])
    @test_throws ArgumentError Portfolio(a, a)

    p1 = Portfolio(a, b; name = :p1)
    p2 = Portfolio(c; objective = ProfitObjective(0.5), name = :p2)
    @test p1.objective isa WelfareObjective

    # positional order of `aggregators` is what the maps align with
    ex = _expand_actors([p1, p2], [c, a, b])
    @test ex.site_actor == [2, 1, 1]
    @test ex.site_objective[1] isa ProfitObjective
    @test ex.site_objective[2] isa WelfareObjective

    @test_throws ArgumentError _expand_actors([p1, Portfolio(a)], [a, b])   # site in two portfolios
    @test_throws ArgumentError _expand_actors([p1], [a])                    # site missing from aggregators
    @test_throws ArgumentError _expand_actors([p1], [a, b, c])              # aggregator in no portfolio
end

@testitem "actor objective: AgrOpt default build is bit-identical, margin rides linear_offset" setup =
    [TwoBusFixtures] tags = [:actors, :admm] begin
    using TSODSO
    using JuMP

    feeder = TwoBusFixtures.two_bus_feeder()
    agg = TwoBusFixtures.build_two_bus_aggregators(feeder)[1]
    Th = TwoBusFixtures.T
    ρ = TwoBusFixtures.RHO_2BUS

    a0 = build_agr_opt(agg, Th; ρ = ρ)
    a1 = build_agr_opt(agg, Th; ρ = ρ, objective = WelfareObjective())
    @test a0.linear_offset === nothing && a1.linear_offset === nothing
    @test num_variables(a0.model) == num_variables(a1.model)
    @test num_constraints(a0.model; count_variable_in_set_constraints = true) ==
          num_constraints(a1.model; count_variable_in_set_constraints = true)
    @test string(objective_function(a0.model)) == string(objective_function(a1.model))

    # Test 2: the pag coefficient after solve_agr! is -λ - ρc + m (read, not inferred).
    m = collect(range(0.1, 0.5; length = Th))
    ap = build_agr_opt(agg, Th; ρ = ρ, objective = ProfitObjective(m))
    @test ap.linear_offset == m
    λ = fill(4.0, Th)
    c = fill(0.01, Th)
    solve_agr!(ap, λ, c, ρ)
    aff = objective_function(ap.model).aff
    coefs = [aff.terms[ap.pag[t]] for t in 1:Th]
    @test coefs ≈ -λ .- ρ .* c .+ m
    # re-solve: the margin survives a second coefficient overwrite
    solve_agr!(ap, λ .+ 1, c, ρ)
    aff2 = objective_function(ap.model).aff
    @test [aff2.terms[ap.pag[t]] for t in 1:Th] ≈ -(λ .+ 1) .- ρ .* c .+ m
end

@testitem "actor objective: margin is live in the AGR optimum; zero wedge matches default bitwise" setup =
    [TwoBusFixtures] tags = [:actors, :admm] begin
    using TSODSO

    feeder = TwoBusFixtures.two_bus_feeder()
    agg = TwoBusFixtures.build_two_bus_aggregators(feeder)[1]
    Th = TwoBusFixtures.T
    ρ = TwoBusFixtures.RHO_2BUS
    λ = fill(4.0, Th)
    c = zeros(Th)

    pag_of(obj) = begin
        a = build_agr_opt(agg, Th; ρ = ρ, objective = obj)
        solve_agr!(a, λ, c, ρ).pag
    end
    p_def = pag_of(WelfareObjective())
    p_zero = pag_of(ProfitObjective(0.0))
    p_m = pag_of(ProfitObjective(2.0))
    @test p_zero == p_def                 # x + 0.0 == x, bitwise
    @test maximum(abs.(p_m .- p_def)) > 1e-6
end


# ---------------------------------------------------------------------------------------------
# Plan 44-02: solve paths
# ---------------------------------------------------------------------------------------------

@testitem "actor objective: solve_welfare default path untouched and efficiency helper" setup =
    [TwoBusFixtures] tags = [:actors] begin
    using TSODSO
    using TSODSO: SOCP

    function run_case()
        feeder = TwoBusFixtures.two_bus_feeder()
        aggs = TwoBusFixtures.build_two_bus_aggregators(feeder)
        Th = TwoBusFixtures.T
        λ₀ = TwoBusFixtures.two_bus_lambda0()
        opt = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)
        solve(act) = solve_welfare(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, allow_export = true, optimizer = opt, actors = act,
        )
        c0 = solve(nothing)
        cw = solve([Portfolio(aggs[1])])               # all-WelfareObjective
        return (c0, cw)
    end
    c0, cw = run_case()
    @test !haskey(c0[1].meta, :actor) && !haskey(cw[1].meta, :actor)
    @test c0[2] == cw[2] && c0[3] == cw[3]

    # efficiency helper
    e = actor_efficiency(10.0, 9.5)
    @test e.delta_abs == 0.5 && e.delta_rel == 0.05
    @test_throws ArgumentError actor_efficiency(NaN, 1.0)
    @test_throws ArgumentError actor_efficiency(1.0, Inf)
    @test_throws ArgumentError actor_efficiency(0.0, 1.0)
end

@testitem "actor objective: centralized wedge pass-through, liveness, social welfare (two-bus)" setup =
    [TwoBusFixtures] tags = [:actors] begin
    using TSODSO
    using JuMP
    using TSODSO: SOCP

    tol_cen_pass = 9.3e-11
    live_dW = 0.248 / 3
    function run_case(seed, m)
        feeder = TwoBusFixtures.two_bus_feeder()
        aggs = TwoBusFixtures.build_two_bus_aggregators(feeder; seed = seed)
        Th = TwoBusFixtures.T
        λ₀ = TwoBusFixtures.two_bus_lambda0()
        opt = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)
        solve(act) = solve_welfare(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, allow_export = true, optimizer = opt, actors = act,
        )
        c0 = solve(nothing)
        cz = solve([Portfolio(aggs[1]; objective = ProfitObjective(0.0))])
        cm = solve([Portfolio(aggs[1]; objective = ProfitObjective(m))])
        # wedge length mismatch surfaces as ArgumentError at the boundary
        bad = try
            solve([Portfolio(aggs[1]; objective = ProfitObjective(fill(0.1, Th - 1)))])
            false
        catch err
            err isa ArgumentError
        end
        net(c) = [value(x) for x in c[1].meta[:agg_net][1].net]
        return (; c0, cz, cm, bad, λ₀, Th, dnet = maximum(abs.(net(cm) .- net(c0))))
    end

    for seed in (20260719, 20260720, 20260721)
        r = run_case(seed, 5.0)
        @test haskey(r.cz[1].meta, :actor)            # zero wedge is routed, not short-circuited
        @test abs(r.cz[2] - r.c0[2]) <= tol_cen_pass
        @test r.cz[3] == r.c0[3]
        @test r.bad
        # liveness: nonzero wedge moves dispatch and costs social welfare (DeltaW > 0)
        a = r.cm[1].meta[:actor]
        @test r.dnet > 1e-3
        dW = r.c0[2] - r.cm[2]
        @test dW > live_dW
        @test dW >= -tol_cen_pass                      # W_soc <= W_opt + slack
        @test actor_efficiency(r.c0[2], r.cm[2]).delta_rel > 0
        # welfare honesty: returned welfare is SOCIAL, distinct from the actor objective
        p_imp = r.cm[1].meta[:p_import]
        social = value(r.cm[1].objective) - sum(r.λ₀[t] * value(p_imp[t]) for t in 1:r.Th)
        @test r.cm[2] == social == a.social_welfare
        @test a.actor_objective_value != r.cm[2]
        @test r.cm[2] != JuMP.objective_value(r.cm[1].model)
    end
end

@testitem "actor objective: centralized wedge on IEEE-13 portfolios" setup = [IEEE13Fixtures] tags =
    [:actors] begin
    using TSODSO
    using TSODSO: SOCP

    tol_cen_pass = 9.3e-11
    live_dW = 1.96e-3 / 3
    function run_case()
        feeder = ieee13_modified()
        aggs = IEEE13Fixtures.build_ieee13_ground_aggregators(feeder)
        Th = IEEE13Fixtures.T
        λ₀ = IEEE13Fixtures.mem_price_profile()
        h = length(aggs) ÷ 2
        P(o) = [Portfolio(aggs[1:h]; objective = o, name = :a), Portfolio(aggs[(h + 1):end]; name = :b)]
        solve(act) = solve_welfare(
            feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀, allow_export = true, actors = act,
        )
        return (solve(nothing), solve(P(ProfitObjective(0.0))), solve(P(ProfitObjective(0.5))))
    end
    c0, cz, cm = run_case()
    @test abs(cz[2] - c0[2]) <= tol_cen_pass
    @test cz[3] == c0[3]
    dW = c0[2] - cm[2]
    @test dW > live_dW
    @test dW >= -tol_cen_pass
    a = cm[1].meta[:actor]
    @test a.social_welfare == cm[2]
    @test a.actor_objective_value != cm[2]
    @test length(a.profit_by_actor) == 2 && a.profit_by_actor[2] == 0.0
    @test a.retail_wedge[1] == fill(0.5, 24) && a.retail_wedge[2] === nothing
end

@testitem "actor objective: solve_admm pass-through, liveness, crossval, guards (two-bus)" setup =
    [TwoBusFixtures] tags = [:actors, :admm] begin
    using TSODSO
    using TSODSO: SOCP

    live_net = 6.8e-3 / 3
    gap_w_rel = 1.24e-7
    gap_dadp = 4.1e-5
    slack_rel = 1.24e-7
    function run_case(seed, m)
        feeder = TwoBusFixtures.two_bus_feeder()
        aggs = TwoBusFixtures.build_two_bus_aggregators(feeder; seed = seed)
        Th = TwoBusFixtures.T
        λ₀ = TwoBusFixtures.two_bus_lambda0()
        opt = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)
        P(o) = [Portfolio(aggs[1]; objective = o)]
        ad(act) = solve_admm(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, ρ = TwoBusFixtures.RHO_2BUS, allow_export = true, actors = act,
        )
        cm = solve_welfare(
            feeder, ConvexBranchFlow(), aggs;
            T = Th, λ₀ = λ₀, allow_export = true, optimizer = opt, actors = P(ProfitObjective(m)),
        )
        return (; a0 = ad(nothing), aw = ad(P(WelfareObjective())), az = ad(P(ProfitObjective(0.0))),
            am = ad(P(ProfitObjective(m))), cm, feeder, aggs, λ₀, Th)
    end

    for seed in (20260719, 20260720, 20260721)
        r = run_case(seed, 5.0)
        # default fence on the ADMM side: all-welfare actors change nothing, no `actor` key
        @test r.aw.welfare == r.a0.welfare && r.aw.dadp == r.a0.dadp && r.aw.iters == r.a0.iters
        @test keys(r.aw) == keys(r.a0)
        # bitwise pass-through at zero wedge (== not isapprox)
        @test r.az.welfare == r.a0.welfare
        @test r.az.dadp == r.a0.dadp
        @test r.az.iters == r.a0.iters
        @test r.az.residuals.primal_trace == r.a0.residuals.primal_trace
        # liveness + actor report
        @test haskey(r.am, :actor)
        @test maximum(abs.(r.am.agr_dispatch[2] .- r.a0.agr_dispatch[2])) > live_net
        @test r.am.actor.social_welfare == r.am.welfare
        @test r.am.actor.actor_objective_value != r.am.welfare
        @test length(r.am.actor.profit_by_actor) == 1
        # DEV-10 crossval: centralized vs ADMM under the same wedge
        @test abs(r.am.welfare - r.cm[2]) / abs(r.cm[2]) <= gap_w_rel
        @test maximum(abs.(vec(r.am.dadp) .- r.cm[3])) <= gap_dadp
        @test maximum(abs.((vec(r.am.dadp) .+ 5.0) .- (r.cm[3] .+ 5.0))) <= gap_dadp   # retail price
        # DeltaW >= 0 within the measured slack, and strictly positive for m != 0
        e = actor_efficiency(r.a0.welfare, r.am.welfare)
        @test e.delta_abs >= -slack_rel * abs(r.a0.welfare)
        @test e.delta_abs > 0 && e.delta_rel > 0
    end

    # guards: ArgumentError before any model build
    feeder = TwoBusFixtures.two_bus_feeder()
    aggs = TwoBusFixtures.build_two_bus_aggregators(feeder)
    other = TwoBusFixtures.build_two_bus_aggregators(feeder; seed = 1)
    Th = TwoBusFixtures.T
    λ₀ = TwoBusFixtures.two_bus_lambda0()
    admm(act) = solve_admm(
        feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀, ρ = TwoBusFixtures.RHO_2BUS, actors = act,
    )
    welf(act) = solve_welfare(feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀, actors = act)
    for f in (admm, welf)
        @test_throws ArgumentError f([Portfolio(aggs[1]; objective = ProfitObjective(fill(0.1, Th - 1)))])
        @test_throws ArgumentError f([Portfolio(other[1])])                    # unknown site
        @test_throws ArgumentError f([Portfolio(aggs[1]), Portfolio(aggs[1])]) # duplicate site
        @test_throws ArgumentError f(Portfolio[])                              # partition mismatch
    end
    @test_throws ArgumentError ProfitObjective([0.1, NaN])
end

@testitem "actor objective: solve_admm IEEE-13 portfolios crossval and legacy equality" setup =
    [IEEE13Fixtures] tags = [:actors, :admm, :slow] begin
    using TSODSO

    gap_w_rel = 1.24e-7
    gap_dadp = 1.23e-2
    live_net = 1.42e-2 / 3
    function run_case()
        feeder = ieee13_modified()
        aggs = IEEE13Fixtures.build_ieee13_ground_aggregators(feeder)
        Th = IEEE13Fixtures.T
        λ₀ = IEEE13Fixtures.mem_price_profile()
        h = length(aggs) ÷ 2
        P(o) = [Portfolio(aggs[1:h]; objective = o, name = :a), Portfolio(aggs[(h + 1):end]; name = :b)]
        kw = (T = Th, λ₀ = λ₀, ρ = 100.0, tol = 1e-6, maxiter = 700, ε_abs = 1e-6, ε_rel = 1e-7, allow_export = true)
        cm = solve_welfare(
            feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀, allow_export = true,
            actors = P(ProfitObjective(0.5)),
        )
        return (;
            a0 = solve_admm(feeder, ConvexBranchFlow(), aggs; kw...),
            aw = solve_admm(feeder, ConvexBranchFlow(), aggs; kw..., actors = P(WelfareObjective())),
            az = solve_admm(feeder, ConvexBranchFlow(), aggs; kw..., actors = P(ProfitObjective(0.0))),
            am = solve_admm(feeder, ConvexBranchFlow(), aggs; kw..., actors = P(ProfitObjective(0.5))),
            cm,
        )
    end
    r = run_case()
    # multi-bus portfolios on distinct buses == legacy (bitwise), including a zero wedge
    @test r.aw.welfare == r.a0.welfare && r.aw.dadp == r.a0.dadp && r.aw.iters == r.a0.iters
    @test r.az.welfare == r.a0.welfare && r.az.dadp == r.a0.dadp && r.az.iters == r.a0.iters
    @test maximum(
        abs(r.am.agr_dispatch[b][t] - r.a0.agr_dispatch[b][t]) for b in keys(r.a0.agr_dispatch), t in 1:24
    ) > live_net
    @test r.am.actor.social_welfare == r.am.welfare
    @test r.am.actor.actor_objective_value != r.am.welfare
    @test abs(r.am.welfare - r.cm[2]) / abs(r.cm[2]) <= gap_w_rel
    @test maximum(abs.(r.am.dadp[1, :] .- r.cm[3])) <= gap_dadp
    e = actor_efficiency(r.a0.welfare, r.am.welfare)
    @test e.delta_abs >= -1.24e-7 * abs(r.a0.welfare) && e.delta_abs > 0
end

@testitem "actor objective: MPC, stochastic and FIT entries expose no actors keyword" setup =
    [TwoBusFixtures] tags = [:actors] begin
    using TSODSO

    feeder = TwoBusFixtures.two_bus_feeder()
    aggs = TwoBusFixtures.build_two_bus_aggregators(feeder)
    act = [Portfolio(aggs[1]; objective = ProfitObjective(1.0))]
    scen = Scenario(; name = "actor-guard", feeder = :ieee13, strategy = :centralized, seed = 7, T = 24)
    # valid positional arguments in every call: the MethodError can only come from the keyword
    f_fit() = fit_baseline(feeder, ConvexBranchFlow(), aggs; actors = act)
    f_mpc() = run_mpc(scen; actors = act)
    f_sto() = run_stochastic(scen; actors = act)
    @test_throws MethodError f_fit()
    @test_throws MethodError f_mpc()
    @test_throws MethodError f_sto()
    # the rejection names the keyword (not an unrelated missing method)
    msg(f) = try
        f()
        ""
    catch e
        sprint(showerror, e)
    end
    @test occursin("actors", msg(f_fit)) && occursin("actors", msg(f_mpc)) && occursin("actors", msg(f_sto))
end
