# test/test_pricing_fit.jl
#
# Seam: pricing/fit.jl (the FIT baseline half). The thesis-faithful FIT-OPT
# (3.24-3.28) + plain AC-PF counterfactual `fit_baseline`.
#
# Every @testitem name contains "fit" (this is documentation/
# organizational metadata only — `test/runtests.jl`'s `@run_package_tests` passes no
# `filter` keyword, so there is no active `occursin("fit", ti.name)`-based selection
# mechanism wired up today; running `Pkg.test()` always runs the entire suite). These
# items are the richer contract (the flow-split identities, the FIT social
# welfare, seeded reproducibility, and the "voltage limit NOT enforced" structural
# distinction) — complementary to the coarse harness in test/test_fit.jl.

# A small seeded fixture: a 3-bus radial feeder (root + two load buses), each load bus
# holding an aggregator with a Deferrable flexible load + a PVBattery (whose PV the FIT-OPT
# keeps and whose battery it drops). Built purely from `generate_profiles(seed=…)`, so two
# builds with the same seed are bit-for-bit identical.
@testmodule FitFixtures begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    const T = 4

    function feeder()
        buses = [
            Bus(1, 0.95, 1.05, true),     # root / MEM frontier
            Bus(2, 0.95, 1.05, false),
            Bus(3, 0.95, 1.05, false),
        ]
        branches = [Branch(1, 2, 0.02, 0.03, 10.0), Branch(2, 3, 0.02, 0.03, 10.0)]
        return Feeder(buses, branches, 1)
    end

    """
    Aggregators built deterministically from a seed (PV + a deferrable load + a battery).
    """
    function aggregators(; seed::Integer)
        aggs = TSODSO.Aggregator[]
        for bus in 2:3
            prof = generate_profiles(seed = seed + bus, T = T)
            defer = Deferrable(bus, 1, T, 0.4, 0.3, 1.0)
            batt = PVBattery(bus, 0.95, 1.0, 0.3, 0.0, 1.0, 0.5, 1.0, 2.0, 3.0, prof.pv)
            push!(aggs, Aggregator(bus, 0.9, [defer, batt], prof.demand))
        end
        return aggs
    end
end

@testitem "fit: FIT-OPT flows satisfy the import/self-consume/export split (3.25-3.27)" setup =
    [FitFixtures] tags = [:fit] begin
    using TSODSO
    using TSODSO: select_optimizer, problem_class

    T = FitFixtures.T
    aggs = FitFixtures.aggregators(seed = 20260718)

    fa = TSODSO._fit_opt_solve(
        aggs;
        T = T,
        optimizer = select_optimizer(problem_class(ConvexBranchFlow())),
    )

    @test isfinite(fa.prosumer_surplus)
    @test length(fa.per_agg) == length(aggs)

    for a in fa.per_agg
        for t in 1:T
            # Flow-split identities (thesis 3.25-3.27): exact structural equalities.
            @test a.self[t] + a.imp[t] ≈ a.p_h[t] atol = 1e-6
            @test a.self[t] + a.exp[t] ≈ a.Ppv[t] atol = 1e-6
            # Non-negativity ⇒ self ≤ min(Ppv, p_h) (the max/min split without a nonconvex min).
            @test a.self[t] >= -1e-6
            @test a.imp[t] >= -1e-6
            @test a.exp[t] >= -1e-6
            # Net grid injection identity: net = exp − imp = Ppv − p_h (thesis 3.22).
            @test a.net[t] ≈ a.Ppv[t] - a.p_h[t] atol = 1e-6
        end
    end
end

@testitem "fit: FIT baseline uses the German-FIT price triple as documented constants" tags =
    [:fit] begin
    using TSODSO

    # Named module constants (thesis page 93), in the SAME ¢$/kWh unit as λ₀.
    @test TSODSO.FIT_λ_IMPORT == 6.6
    @test TSODSO.FIT_λ_EXPORT == 9.6
    @test TSODSO.FIT_λ_SELF == 5.6
    # Import cost strictly below export revenue below … the thesis German-FIT calibration.
    @test TSODSO.FIT_λ_SELF < TSODSO.FIT_λ_IMPORT < TSODSO.FIT_λ_EXPORT
end

@testitem "fit: fit_baseline solves OPTIMAL with a finite magnitude-sane social welfare" setup =
    [FitFixtures] tags = [:fit] begin
    using TSODSO

    T = FitFixtures.T
    feeder = FitFixtures.feeder()
    aggs = FitFixtures.aggregators(seed = 20260718)

    res = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = T)

    @test isfinite(res.social_fit)
    @test res.social_fit == res.welfare        # `welfare` is the alias the harness reads
    @test isfinite(res.prosumer_surplus)
    # Efficiency ratio social_DADP / social_fit is finite and positive (a self-contained
    # cross-check; the authoritative +25% headline ≈ 1.25 is computed in test_pricing_welfare.jl).
    @test isfinite(res.ratio)
    @test res.ratio > 0
    @test length(res.fit_flows) == length(aggs)
end

@testitem "fit: fit_baseline is reproducible bit-for-bit under a fixed seed" setup =
    [FitFixtures] tags = [:fit] begin
    using TSODSO

    T = FitFixtures.T
    feeder = FitFixtures.feeder()

    res1 = fit_baseline(
        feeder,
        ConvexBranchFlow(),
        FitFixtures.aggregators(seed = 4242);
        T = T,
    )
    res2 = fit_baseline(
        feeder,
        ConvexBranchFlow(),
        FitFixtures.aggregators(seed = 4242);
        T = T,
    )

    # Same seed ⇒ identical baseline (deterministic solve over identical seeded profiles).
    @test res1.social_fit == res2.social_fit
    @test res1.prosumer_surplus == res2.prosumer_surplus

    # A different seed generally yields a different baseline (guards against a constant stub).
    res3 = fit_baseline(
        feeder,
        ConvexBranchFlow(),
        FitFixtures.aggregators(seed = 9999);
        T = T,
    )
    @test res3.social_fit != res1.social_fit
end

@testitem "fit: the FIT AC-PF does NOT enforce the voltage limit (relaxed baseline ctx)" setup =
    [FitFixtures] tags = [:fit] begin
    using TSODSO

    T = FitFixtures.T
    feeder = FitFixtures.feeder()
    aggs = FitFixtures.aggregators(seed = 20260718)

    res = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = T)

    # The baseline ctx is marked as the FIT counterfactual, structurally distinct from a
    # DADP welfare ctx (no battery, voltage limit relaxed).
    @test res.ctx.meta[:fit_baseline] === true

    # The AC-PF ran on a voltage-RELAXED feeder: the original tight band [0.95, 1.05] is
    # widened to the per-unit sanity band [0.8, 1.2], so 3.35 does not bind (not enforced).
    relaxed = res.ctx.feeder
    for b in relaxed.buses
        b.is_root && continue
        @test b.vmin == 0.8
        @test b.vmax == 1.2
    end

    # The solve is OPTIMAL and registered its nodal balance like a normal solve.
    @test haskey(res.ctx.constraints, :balance_p)
end

# ---------------------------------------------------------------------------------------------
# Regression golden: FIT-vs-DADP ratio on this file's OWN small `FitFixtures` scenario.
#
# DISTINCT from and ADDITIVE to `test/test_pricing_welfare.jl`'s `RATIO_GOLDEN` (which pins the
# ratio on the larger IEEE-13 ground scenario) — this pins `fit_baseline`'s own self-contained
# efficiency indicator `res.ratio = social_dadp / social_fit` (computed internally by
# `fit_baseline`, per its docstring) on the small 3-bus fixture this file already owns, giving
# the FIT baseline a FIT-focused regression independent of the IEEE-13 fixture. `FIT_RATIO_GOLDEN` was
# captured from the FIRST trusted solve on the fixed seed (20260718) — the same "first trusted
# solve" convention every other golden in this codebase follows (cf. test/test_ieee13.jl's
# header comment). Deterministic under the fixed seed (the "reproducible bit-for-bit" @testitem
# above already proves this).
# ---------------------------------------------------------------------------------------------
@testitem "fit: FIT-vs-DADP ratio regression golden" setup = [FitFixtures] tags = [:fit] begin
    using TSODSO

    T = FitFixtures.T
    feeder = FitFixtures.feeder()
    aggs = FitFixtures.aggregators(seed = 20260718)

    res = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = T)

    # PRIMARY reproducibility anchor: the COMPUTED ratio pinned as a golden (tight rtol),
    # captured from the first trusted solve on this fixture's fixed seed.
    # Re-pinned after PVBattery's free hour-T discharge was closed
    # on this T=4 fixture. OLD 0.6428101637491034 -> NEW 0.772018581825438.
    FIT_RATIO_GOLDEN = 0.772018581825438
    @test isapprox(res.ratio, FIT_RATIO_GOLDEN; rtol = 1e-4)
end

# ---------------------------------------------------------------------------------------------
# The `optimizer` kwarg.
#
# `fit_baseline` runs THREE internal solves: the per-prosumer FIT-OPT, the FIT AC-PF, and the
# nested `solve_welfare` that forms the efficiency ratio. Before this kwarg each hardcoded
# `select_optimizer(problem_class(pf))`, so a caller could not condition the solver — and the
# nested solve_welfare's exactness gate (assert_socp_exact!) could refuse prices for purely numerical
# reasons with no recourse (atol=1e-6 sits at Clarabel's cone residual on a large
# feeder at the default tol_gap=1e-8).
# ---------------------------------------------------------------------------------------------
@testitem "fit: the optimizer kwarg defaults bit-for-bit identically to the problem-class factory" setup =
    [FitFixtures] tags = [:fit] begin
    using TSODSO

    T = FitFixtures.T
    feeder = FitFixtures.feeder()
    pf = ConvexBranchFlow()

    implicit = fit_baseline(feeder, pf, FitFixtures.aggregators(seed = 20260718); T = T)
    explicit = fit_baseline(
        feeder,
        pf,
        FitFixtures.aggregators(seed = 20260718);
        T = T,
        optimizer = TSODSO.select_optimizer(TSODSO.problem_class(pf)),
    )

    # The default expression IS the factory call every site used before the kwarg existed, so
    # omitting it must be indistinguishable from passing it (no behaviour change for any caller).
    @test implicit.social_fit == explicit.social_fit
    @test implicit.ratio == explicit.ratio
    @test implicit.prosumer_surplus == explicit.prosumer_surplus
end

@testitem "fit: a caller-supplied optimizer is actually consumed by the internal solves" setup =
    [FitFixtures] tags = [:fit] begin
    using TSODSO
    using JuMP

    T = FitFixtures.T
    feeder = FitFixtures.feeder()
    pf = ConvexBranchFlow()

    # NO solver is named here: the constructor is taken from the project's own factory and only
    # re-parameterized, so this test keeps working if the factory ever swaps backends.
    base = TSODSO.select_optimizer(TSODSO.problem_class(pf))
    # One interior-point iteration cannot reach optimality, so `assert_solved!` must refuse. Were
    # the kwarg silently ignored, this would SOLVE — the throw is what proves the caller's
    # optimizer reaches a real solve rather than being dropped on the floor.
    crippled = optimizer_with_attributes(
        base.optimizer_constructor,
        base.params...,
        "max_iter" => 1,
    )

    @test_throws Exception fit_baseline(
        feeder,
        pf,
        FitFixtures.aggregators(seed = 20260718);
        T = T,
        optimizer = crippled,
    )
end

@testitem "fit: tightening solver tolerance preserves the optimum (use case)" setup =
    [FitFixtures] tags = [:fit] begin
    using TSODSO
    using JuMP

    T = FitFixtures.T
    feeder = FitFixtures.feeder()
    pf = ConvexBranchFlow()

    # Attribute names mirror src/solver/factory.jl's own SOCP tolerances — no NEW solver coupling
    # is introduced, and the constructor still comes from the factory rather than being named.
    base = TSODSO.select_optimizer(TSODSO.problem_class(pf))

    loose = fit_baseline(feeder, pf, FitFixtures.aggregators(seed = 20260718); T = T)
    tight = fit_baseline(
        feeder,
        pf,
        FitFixtures.aggregators(seed = 20260718);
        T = T,
        optimizer = optimizer_with_attributes(
            base.optimizer_constructor,
            base.params...,
            "tol_gap_abs" => 1e-10,
            "tol_gap_rel" => 1e-10,
        ),
    )

    # Tightening convergence must NOT move the optimum — it only shrinks residuals. This is the
    # property used to show the earlier exactness failures were numerical.
    @test isapprox(tight.social_fit, loose.social_fit; rtol = 1e-6)
    @test isapprox(tight.ratio, loose.ratio; rtol = 1e-6)
end

@testitem "fit: source tripwire — no solver factory is hardcoded inside fit_baseline's BODY" tags =
    [:fit] begin
    using TSODSO

    src = read(joinpath(dirname(pathof(TSODSO)), "pricing", "fit.jl"), String)
    idx = findfirst("function fit_baseline(", src)
    @test idx !== nothing
    full = src[first(idx):end]

    # The second site's AC-PF is a DIFFERENT problem class (NLP)
    # from the `optimizer` kwarg's SOCP/QP factory, so it needs its OWN kwarg default
    # (`_site2_ac_optimizer`) — a SECOND, LEGITIMATE `select_optimizer(` call, not a regression.
    # The tripwire's real invariant is narrower than "exactly one call anywhere": no
    # `select_optimizer(` may appear in the EXECUTABLE BODY (bypassing BOTH kwargs) — split at
    # the first executable statement (the boundary-guard `isempty(aggregators)`) to check the
    # kwarg-defaults header and the body separately.
    split_idx = findfirst("isempty(aggregators)", full)
    @test split_idx !== nothing
    header = full[1:(first(split_idx) - 1)]
    body = full[first(split_idx):end]

    @test count(_ -> true, eachmatch(r"select_optimizer\(", header)) == 2
    @test count(_ -> true, eachmatch(r"select_optimizer\(", body)) == 0
    @test occursin("optimizer = select_optimizer(problem_class(pf))", header)
    @test occursin(
        "_site2_ac_optimizer = select_optimizer(problem_class(ACPowerFlow()))",
        header,
    )
end
