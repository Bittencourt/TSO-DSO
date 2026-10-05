# operational_oracle: `operational_oracle(feeder, pf, aggregators; λ₀, T, role,
# allow_export) -> (; cost, π, dadp, ctx)` is a thin wrapper over `solve_welfare` exposing
# the frontier coupling dual. Item names contain "oracle" so `occursin("oracle", ti.name)`
# selects them. The bodies use the LinDistFlow formulation and build their
# feeder/aggregator inline.

@testitem "oracle: operational_oracle returns (cost, π, dadp, ctx) with finite prices" tags =
    [:oracle] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    @test isdefined(TSODSO, :operational_oracle)

    T = 24
    # 2-bus radial feeder: root/MEM frontier (bus 1) + one load bus (bus 2).
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    defer = Deferrable(2, 1, T, 1.0, 0.5, 0.5)          # one flexible task over the window
    agg = Aggregator(2, 0.9, [defer], fill(0.1, T))     # a single minimal aggregator
    λ₀ = fill(2.0, T)

    # Exercise the role kwarg on a LinDistFlow solve.
    res = operational_oracle(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = T, role = :follower)

    # Shape: a NamedTuple carrying (cost, π, dadp, ctx).
    @test res isa NamedTuple
    for k in (:cost, :π, :dadp, :ctx)
        @test k in keys(res)
    end

    # Prices are finite: the welfare optimum, the frontier coupling dual π (length-T, since
    # π is the dual of the ROOT active balance over the horizon — distinct from the DADP at
    # the first aggregator's bus), and the length-T DADP.
    @test isfinite(res.cost)
    @test length(res.π) == T
    @test all(isfinite, res.π)
    @test length(res.dadp) == T
    @test all(isfinite, res.dadp)
end

@testitem "oracle: the :leader role returns the same shape" tags = [:oracle] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    T = 24
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    defer = Deferrable(2, 1, T, 1.0, 0.5, 0.5)
    agg = Aggregator(2, 0.9, [defer], fill(0.1, T))
    λ₀ = fill(2.0, T)

    # The explicit Stackelberg :leader role (distributor = leader) must succeed and return
    # the identical (; cost, π, dadp, ctx) shape.
    res = operational_oracle(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = T, role = :leader)

    @test res isa NamedTuple
    @test keys(res) == (:cost, :π, :dadp, :ctx)
    @test isfinite(res.cost)
    @test length(res.π) == T
    @test all(isfinite, res.π)
    @test length(res.dadp) == T

    # An unknown role is rejected loudly (fail-fast; the role is a real, typed seam).
    @test_throws ArgumentError operational_oracle(
        feeder,
        LinDistFlow(),
        [agg];
        λ₀ = λ₀,
        T = T,
        role = :bystander,
    )
end

@testitem "oracle: removed keyword arguments raise MethodError" tags = [:oracle] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    T = 24
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    defer = Deferrable(2, 1, T, 1.0, 0.5, 0.5)
    agg = Aggregator(2, 0.9, [defer], fill(0.1, T))
    λ₀ = fill(2.0, T)

    @test_throws MethodError operational_oracle(
        feeder,
        LinDistFlow(),
        [agg];
        λ₀ = λ₀,
        T = T,
        objective_hook = nothing,
    )
    @test_throws MethodError operational_oracle(
        feeder,
        LinDistFlow(),
        [agg];
        λ₀ = λ₀,
        T = T,
        horizon_state = nothing,
    )
    @test_throws MethodError operational_oracle(
        feeder,
        LinDistFlow(),
        [agg];
        λ₀ = λ₀,
        T = T,
        z = nothing,
    )

    # The free-coupling path still returns a finite frontier coupling dual.
    res = operational_oracle(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = T)
    @test length(res.π) == T
    @test all(isfinite, res.π)
end
