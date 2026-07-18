# Seam: models/oracle.jl (OPT-03 / SEAM-01). operational_oracle + extension-interface stubs.
#
# Plan 04-04 turns these green by defining
# `operational_oracle(feeder, pf, aggregators; λ₀, T, z, role, objective_hook,
# horizon_state) -> (; cost, π, dadp, ctx)` — a thin wrapper over `solve_welfare` exposing
# the frontier coupling dual plus the SEAM-01 stub kwargs. Item names contain "oracle" so
# `occursin("oracle", ti.name)` selects them. The bodies use the already-existing
# LinDistFlow formulation (NOT the SOCP cone), so each depends ONLY on 04-04 landing — they
# build their feeder/aggregator inline (no Phase4Fixtures / SOCP coupling), keeping this
# Wave-2 test independent of 04-02/04-03. Ground-truth numbers are 04-06's job, not here.

@testitem "oracle: operational_oracle returns (cost, π, dadp, ctx) with finite prices (OPT-03/SEAM-01)" tags = [
    :oracle,
] begin
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

    # Exercise EVERY SEAM-01 stub kwarg (z coupling flow, leader/follower role,
    # multi-scenario objective hook, rolling-horizon initial state) on a LinDistFlow solve.
    res = operational_oracle(
        feeder, LinDistFlow(), [agg];
        λ₀ = λ₀, T = T,
        z = nothing,
        role = :follower,
        objective_hook = identity,
        horizon_state = nothing,
    )

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

@testitem "oracle: SEAM-01 stub kwargs are inert — :leader role returns the same shape (SEAM-01)" tags = [
    :oracle,
] begin
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

    # Passing the explicit Stackelberg :leader role (PSR: distributor = leader) plus the
    # other three SEAM-01 stubs must SUCCEED and return the identical (; cost, π, dadp, ctx)
    # shape — the stubs are inert in Phase 4 (no partial planning behavior, threat T-04-13).
    res = operational_oracle(
        feeder, LinDistFlow(), [agg];
        λ₀ = λ₀, T = T,
        z = nothing,
        role = :leader,
        objective_hook = identity,
        horizon_state = nothing,
    )

    @test res isa NamedTuple
    @test keys(res) == (:cost, :π, :dadp, :ctx)
    @test isfinite(res.cost)
    @test length(res.π) == T
    @test all(isfinite, res.π)
    @test length(res.dadp) == T

    # An unknown role is rejected loudly (fail-fast; the role is a real, typed seam).
    @test_throws ArgumentError operational_oracle(
        feeder, LinDistFlow(), [agg];
        λ₀ = λ₀, T = T, role = :bystander,
    )
end
