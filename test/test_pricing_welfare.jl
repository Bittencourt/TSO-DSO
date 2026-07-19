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

# ---------------------------------------------------------------------------------------------
# Task 1 (05-05): the surplus-identity correctness gate (thesis 3.38/3.46/3.47).
#
# The load-bearing check is `social ≈ prosumer + dso ≈ objective_value(ctx.model)` — the
# `Σ_j λ_j·p_agⱼ` price-transfer cancels between the AGR-OPT (3.46) and DSO-OPT (3.47)
# settlements, so any mis-signed / dropped term in ONE settlement (a broken cancellation)
# makes `welfare_accounting` THROW. Verified on a (near-)lossless 2-bus first (Open Q2: is
# there a loss remainder?) and then on the lossy IEEE-13 ground solve.
# ---------------------------------------------------------------------------------------------

@testitem "welfare surplus accounting: near-lossless 2-bus identity + finite magnitude-sane surpluses (PRICE-03)" tags = [
    :welfare,
    :surplus,
] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # Near-lossless (tiny r) 2-bus radial: isolates Open Q2 — with essentially no `−r·l` loss
    # term the surplus identity must hold to machine precision (no loss remainder).
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 1.0e-6, 0.02, 10.0)],
        1,
    )
    T = 3
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
    ctx, obj, _dadp = solve_welfare(
        feeder, ConvexBranchFlow(), [agg]; T = T, λ₀ = fill(40.0, T), allow_export = true,
    )

    acct = welfare_accounting(ctx; T = T)

    # social == GLB-CVX objective (3.38); the two surpluses sum back to it (transfer cancels).
    @test acct.social ≈ obj rtol = 1e-4 atol = 1e-4
    @test isapprox(acct.prosumer + acct.dso, obj; rtol = 1e-4, atol = 1e-4)
    # On a near-lossless feeder the identity is TIGHT — no loss remainder (Open Q2 resolved).
    @test isapprox(acct.prosumer + acct.dso, acct.social; rtol = 1e-6, atol = 1e-6)
    # Magnitude-sane and finite (Pitfall 5).
    @test isfinite(acct.prosumer)
    @test isfinite(acct.dso)
    @test isfinite(acct.social)
end

@testitem "welfare surplus accounting: sign-flipped price-transfer makes the identity THROW — non-vacuous (PRICE-03)" tags = [
    :welfare,
    :surplus,
] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T = 3
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
    ctx, _obj, _dadp = solve_welfare(
        feeder, ConvexBranchFlow(), [agg]; T = T, λ₀ = fill(40.0, T), allow_export = true,
    )

    # Correct input: the identity holds and welfare_accounting returns cleanly.
    acct = welfare_accounting(ctx; T = T)
    @test isfinite(acct.social)

    # Load-bearing proof: flipping the price-transfer sign in the DSO settlement ONLY (a broken
    # cancellation — the exact bug class the identity guards) makes the assertion THROW. If the
    # identity were vacuous this would silently pass (threat T-05-03).
    @test_throws ErrorException welfare_accounting(ctx; T = T, _transfer_flip = true)
end

@testitem "welfare surplus accounting: IEEE-13 ground solve — social == prosumer + dso == objective (PRICE-03)" tags = [
    :welfare,
    :surplus,
] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = ieee13_modified()
    aggs = Phase4Fixtures.build_ieee13_ground_aggregators(feeder)
    λ₀ = Phase4Fixtures.mem_price_profile()

    ctx, obj, _dadp = solve_welfare(
        feeder, ConvexBranchFlow(), aggs;
        T = Phase4Fixtures.T, λ₀ = λ₀, allow_export = true,
    )

    acct = welfare_accounting(ctx; T = Phase4Fixtures.T)

    # The lossy IEEE-13 case: the identity still holds within rtol (transfer cancels; the loss
    # sits inside objective_value on both sides — Open Q2 resolved, no separate loss term needed).
    @test acct.social ≈ obj rtol = 1e-4 atol = 1e-4
    @test isapprox(acct.prosumer + acct.dso, acct.social; rtol = 1e-4, atol = 1e-4)
    @test isfinite(acct.prosumer)
    @test isfinite(acct.dso)

    # Passing the true MEM price λ₀ (rather than recovering it from the root DADP) yields the
    # same split — the root DADP equals λ₀ at the priced-frontier optimum (KKT).
    acct2 = welfare_accounting(ctx; T = Phase4Fixtures.T, λ₀ = λ₀)
    @test acct2.prosumer ≈ acct.prosumer rtol = 1e-4 atol = 1e-4
    @test acct2.dso ≈ acct.dso rtol = 1e-4 atol = 1e-4
end
