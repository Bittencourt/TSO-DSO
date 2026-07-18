# Seam: models/oracle.jl (OPT-03 / SEAM-01). operational_oracle + extension-interface stubs.
#
# RED @testitem harness (Wave 1). Plan 04-04 turns these green by defining
# `operational_oracle(feeder, pf, aggregators; λ₀, T, z, role, objective_hook,
# horizon_state) -> (; cost, π, dadp, ctx)` — a thin wrapper over `solve_welfare` exposing
# the frontier coupling dual plus the SEAM-01 stub kwargs. Item names contain "oracle" so
# `occursin("oracle", ti.name)` selects them. The body uses the already-existing
# LinDistFlow formulation (not the SOCP cone), so it depends ONLY on 04-04 landing — it
# builds its feeder/aggregator inline (no Phase4Fixtures / SOCP coupling) for a clean RED.

@testitem "oracle: operational_oracle returns (cost, π, dadp) and accepts the SEAM-01 stub kwargs (OPT-03/SEAM-01)" tags = [
    :oracle,
] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    # RED until plan 04-04 defines the oracle wrapper.
    @test isdefined(TSODSO, :operational_oracle)

    if isdefined(TSODSO, :operational_oracle)
        T = 24
        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        defer = Deferrable(2, 1, T, 1.0, 0.5, 0.5)          # one flexible task over the window
        agg = Aggregator(2, 0.9, [defer], fill(0.1, T))     # a single minimal aggregator
        λ₀ = fill(2.0, T)

        # Exercise EVERY SEAM-01 stub kwarg (z coupling flow, leader/follower role,
        # multi-scenario objective hook, rolling-horizon initial state).
        res = TSODSO.operational_oracle(
            feeder, LinDistFlow(), [agg];
            λ₀ = λ₀, T = T,
            z = nothing,
            role = :follower,
            objective_hook = identity,
            horizon_state = nothing,
        )

        @test res isa NamedTuple
        for k in (:cost, :π, :dadp)                          # (cost, coupling dual π, DADP)
            @test k in keys(res)
        end
        @test isfinite(res.cost)
        @test all(isfinite, res.dadp)
    end
end
