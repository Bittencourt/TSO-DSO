# Seam: pricing/welfare.jl (PRICE-03). Welfare accounting — social = prosumer + DSO surplus.
#
# RED @testitem harness (Wave 1 of Phase 5). Plan 05-05 turns these green by defining
# `welfare_accounting` (split the social welfare into prosumer surplus and DSO surplus from a
# solved ctx, using the additive `ctx.meta[:agg_net]` stash + the registered :balance_p dual,
# with the surplus-identity prosumer + DSO == social as the net). Item names contain "welfare"
# and "surplus" so either `occursin` filter selects them. DISTINCT file from the Phase-3
# test_welfare_solve.jl (that tests the OPTIMIZATION; this tests the post-solve ACCOUNTING).
# While RED the sole failing assertion is a missing-symbol `isdefined` check; behavioral
# asserts sit behind the `isdefined` guard so they go live once 05-05 lands.

@testitem "welfare surplus accounting: welfare_accounting is defined (PRICE-03)" tags = [
    :welfare,
    :surplus,
] begin
    using TSODSO

    # RED until plan 05-05 defines the surplus split.
    @test isdefined(TSODSO, :welfare_accounting)
end

@testitem "welfare surplus accounting: prosumer + DSO surplus sums to social welfare (PRICE-03)" tags = [
    :welfare,
    :surplus,
] begin
    using TSODSO

    # RED until plan 05-05 defines the accounting; the surplus-identity assertion goes live once
    # `welfare_accounting` exists and consumes the ctx.meta[:agg_net] stash from plan 05-01.
    @test isdefined(TSODSO, :welfare_accounting)

    if isdefined(TSODSO, :welfare_accounting)
        using TSODSO: Bus, Branch, Feeder

        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        T = 3
        batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
        agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
        ctx, obj, _dadp =
            solve_welfare(feeder, ConvexBranchFlow(), [agg]; T = T, λ₀ = fill(40.0, T), allow_export = true)

        acct = welfare_accounting(ctx; T = T)
        # Surplus identity: prosumer + DSO surplus == social welfare (the optimization optimum).
        @test isapprox(acct.prosumer + acct.dso, obj; rtol = 1e-4, atol = 1e-4)
    end
end
