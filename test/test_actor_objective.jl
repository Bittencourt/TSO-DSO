# test/test_actor_objective.jl
#
# Seam: src/actors/{actor_objective,Portfolio}.jl and the AgrOpt hook (Phase 44 plan 01).
# Every item name contains "actor objective". Accumulators live in functions/`let`.

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
