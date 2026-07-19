# Seam: pricing/checks.jl (PRICE-05). Economic-direction price checks.
#
# GREEN @testitems (Wave 2 of Phase 5, plan 05-04). `economic_direction_checks` asserts the
# DADP (the dual of the registered `:balance_p` active nodal balance) moves in the
# economically-correct direction: it falls BELOW wholesale λ₀ in a PV-glut / reverse-flow /
# over-voltage window and rises ABOVE λ₀ in a head-branch congestion window (thesis Fig 4.5 /
# 4.6, node 9). The checker reads `ctx.constraints[:balance_p]` DIRECTLY (the same primitive
# `extract_dlmp` uses) so this suite stays independent of `dlmp.jl` (parallel plan 05-02).
#
# Every item name contains "econ" AND "direction" so either `occursin("econ", ti.name)` or
# `occursin("direction", ti.name)` selects it. The fixtures come from the shared Phase-4
# `Phase4Fixtures` @testmodule (high-PV over-generation + IEEE-13 head-branch congestion).

@testitem "econ direction: economic_direction_checks is defined and exported (PRICE-05)" tags = [
    :econ,
    :direction,
] begin
    using TSODSO

    @test isdefined(TSODSO, :economic_direction_checks)
    @test :economic_direction_checks in names(TSODSO)
end

@testitem "econ direction: PV-glut window drives the DADP below wholesale λ₀ (PRICE-05)" tags = [
    :econ,
    :direction,
] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = Phase4Fixtures.high_pv_feeder()
    aggs = Phase4Fixtures.build_high_pv_aggregators(feeder)
    λ₀ = Phase4Fixtures.mem_price_profile()

    # allow_export = true: the reverse-flow PV surplus is SOLD to the MEM (the SOC-exactness
    # enabler, PF-04). solve_welfare gates on the exactness certificate BEFORE any dual read,
    # so reaching this line means the DADP is trustworthy.
    ctx, _obj, _dadp = solve_welfare(
        feeder, ConvexBranchFlow(), aggs;
        T = Phase4Fixtures.T, λ₀ = λ₀, allow_export = true,
    )

    res = economic_direction_checks(ctx; λ₀ = λ₀, regime = :pv_glut)
    @test res.pv_glut_ok

    # Non-vacuous, explicit: the DADP genuinely dips STRICTLY below λ₀ at some node/hour
    # (thesis Fig 4.5, node 9 @ 15:00 < MEM). Read balance_p directly here too.
    Λ = dual.(ctx.constraints[:balance_p])
    Np = size(Λ, 1)
    below = Inf
    for j in 1:Np, t in 1:Phase4Fixtures.T
        j == feeder.root && continue
        below = min(below, Λ[j, t] - λ₀[t])
    end
    @test below < -1e-6
end

@testitem "econ direction: head-branch congestion drives the DADP above wholesale λ₀ (PRICE-05)" tags = [
    :econ,
    :direction,
] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = ieee13_modified()
    aggs = Phase4Fixtures.build_ieee13_ground_aggregators(feeder)
    λ₀ = Phase4Fixtures.mem_price_profile()

    ctx, _obj, _dadp = solve_welfare(
        feeder, ConvexBranchFlow(), aggs;
        T = Phase4Fixtures.T, λ₀ = λ₀, allow_export = true,
    )

    res = economic_direction_checks(ctx; λ₀ = λ₀, regime = :congestion)
    @test res.congestion_ok

    # Non-vacuous, explicit: the DADP genuinely rises STRICTLY above λ₀ at some node/hour
    # (thesis Fig 4.6, node 9 @ 22:00 > MEM — the evening head-branch import congestion window).
    Λ = dual.(ctx.constraints[:balance_p])
    Np = size(Λ, 1)
    above = -Inf
    for j in 1:Np, t in 1:Phase4Fixtures.T
        j == feeder.root && continue
        above = max(above, Λ[j, t] - λ₀[t])
    end
    @test above > 1e-6
end

@testitem "econ direction: a backwards (sign-flipped) price signal makes the check THROW — non-vacuous (PRICE-05)" tags = [
    :econ,
    :direction,
] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    λ₀ = Phase4Fixtures.mem_price_profile()

    # --- PV glut: negating λ₀ inverts the expected below-wholesale relation ⇒ throw ---
    fg = Phase4Fixtures.high_pv_feeder()
    ctxg, _, _ = solve_welfare(
        fg, ConvexBranchFlow(), Phase4Fixtures.build_high_pv_aggregators(fg);
        T = Phase4Fixtures.T, λ₀ = λ₀, allow_export = true,
    )
    @test economic_direction_checks(ctxg; λ₀ = λ₀, regime = :pv_glut).pv_glut_ok   # sane baseline
    @test_throws ArgumentError economic_direction_checks(ctxg; λ₀ = -λ₀, regime = :pv_glut)

    # Shape guard (T-05-11): a λ₀ horizon mismatch throws a loud error, never @assert.
    @test_throws ArgumentError economic_direction_checks(ctxg; λ₀ = λ₀[1:end-1], regime = :pv_glut)

    # --- Congestion: a negated DADP inverts the expected above-wholesale relation ⇒ throw ---
    # (negating λ₀ would only strengthen an above-wholesale signal, so the non-vacuity probe
    # for the congestion direction flips the DADP instead — the plan's "sign-flipped … DADP").
    fc = ieee13_modified()
    ctxc, _, _ = solve_welfare(
        fc, ConvexBranchFlow(), Phase4Fixtures.build_ieee13_ground_aggregators(fc);
        T = Phase4Fixtures.T, λ₀ = λ₀, allow_export = true,
    )
    @test economic_direction_checks(ctxc; λ₀ = λ₀, regime = :congestion).congestion_ok  # sane baseline
    Λc = dual.(ctxc.constraints[:balance_p])
    @test_throws ArgumentError economic_direction_checks(ctxc; λ₀ = λ₀, regime = :congestion, dadp = -Λc)
end
