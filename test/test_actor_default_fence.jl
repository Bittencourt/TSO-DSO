# test/test_actor_default_fence.jl
#
# Seam: default (no-actor) paths of `solve_admm` and centralized `solve_welfare`
# (Phase 44 plan 01, ACTOR-01 foundation).
#
# BYTE-IDENTITY FENCE. The golden FNV-1a digests below were captured BEFORE any src/ edit of
# phase 44 (`git diff -- src` empty at capture time) and are never re-pinned. They fold EVERY
# data field of the default `solve_admm` result and the default `solve_welfare` outputs, plus
# the key set of `ctx.meta` (so a stray `ctx.meta[:actor]` on the default path is caught).
#
# Captured: 2026-11-02, Julia 1.12.5, git HEAD 1506ef5 (src tree clean).
# The digests are valid only on Julia 1.12.5 (1.12.7 drifts numerically): digest assertions are
# gated on `VERSION == v"1.12.5"` and `@test_skip` elsewhere. This is a DELIBERATE plan decision
# (Phase 44 review WR-03): re-pinning per Julia version would defeat a never-re-pinned fence.
# The fence is therefore NOT inert on other versions: the VERSION-INDEPENDENT assertions below run
# on every Julia (structural `!haskey(ctx.meta, :actor)`, the knife-edge canary, and a same-process
# BITWISE `==` comparison of the default `solve_admm` / `solve_welfare` against the same call
# routed through the actor machinery with all-welfare portfolios, i.e. whatever this version
# computes, the default path and the actor path must agree to the last bit).
#
# SOFT-SCOPE RULE: accumulators live inside functions, never bare in a top-level `for`.

@testmodule ActorFenceDigest begin
    using TSODSO
    using JuMP: AbstractModel
    using JuMP.Containers: SparseAxisArray

    const GOLDEN_VERSION = v"1.12.5"

    # FNV-1a over bit patterns; deterministic, no Base.hash.
    function fold(h::UInt64, x)::UInt64
        if x isa AbstractFloat
            return (h ⊻ reinterpret(UInt64, Float64(x))) * 0x100000001b3
        elseif x isa Bool || x isa Integer
            return (h ⊻ (Int(x) % UInt64)) * 0x100000001b3
        elseif x isa Symbol || x isa AbstractString
            for c in codeunits(string(x))
                h = (h ⊻ c) * 0x100000001b3
            end
            return (h ⊻ 0xff) * 0x100000001b3
        elseif x isa SparseAxisArray
            return fold(h, x.data)
        elseif x isa AbstractArray
            h = fold(h, size(x))
            for e in x
                h = fold(h, e)
            end
            return h
        elseif x isa Tuple
            h = fold(h, length(x))
            for e in x
                h = fold(h, e)
            end
            return h
        elseif x isa AbstractDict
            ks = sort!(collect(keys(x)); by = string)
            for k in ks
                h = fold(fold(h, k), x[k])
            end
            return h
        elseif x isa NamedTuple
            for k in keys(x)
                h = fold(fold(h, k), x[k])
            end
            return h
        elseif x === nothing || x === missing
            return h * 0x100000001b3
        elseif x isa AbstractModel || x isa Function || x isa Module
            return h
        elseif isstructtype(typeof(x))
            h = fold(h, string(nameof(typeof(x))))
            for f in fieldnames(typeof(x))
                h = fold(h, getfield(x, f))
            end
            return h
        else
            return fold(h, string(x))
        end
    end

    digest(x) = fold(0xcbf29ce484222325, x)

    # solve_admm result: key order + every field.
    admm_digest(r) = fold(fold(0xcbf29ce484222325, collect(keys(r))), r)

    # solve_welfare: objective, dadp, and the SORTED key set of ctx.meta (not its values).
    function welfare_digest(ctx, obj, dadp)
        h = fold(0xcbf29ce484222325, obj)
        h = fold(h, dadp)
        return fold(h, sort!(string.(collect(keys(ctx.meta)))))
    end
end

@testitem "actor objective: default fence (admm + welfare + canary, byte-identity)" setup =
    [ActorFenceDigest, TwoBusFixtures, IEEE13Fixtures, ExperimentHarnessFixtures] tags =
    [:actors, :fence] begin
    using TSODSO
    using TSODSO: SOCP

    # ---- two-bus ----

    feeder2 = TwoBusFixtures.two_bus_feeder()
    aggs2 = TwoBusFixtures.build_two_bus_aggregators(feeder2)
    λ2 = TwoBusFixtures.two_bus_lambda0()
    T2 = TwoBusFixtures.T

    res2 = solve_admm(
        feeder2,
        ConvexBranchFlow(),
        aggs2;
        T = T2,
        λ₀ = λ2,
        ρ = TwoBusFixtures.RHO_2BUS,
        allow_export = true,
    )
    # near-lossless fixture: tighten the centralized SOCP gap exactly as test_admm_generic_pf.jl
    ctx2, obj2, dadp2 = solve_welfare(
        feeder2,
        ConvexBranchFlow(),
        aggs2;
        T = T2,
        λ₀ = λ2,
        allow_export = true,
        optimizer = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10),
    )
    da2 = ActorFenceDigest.admm_digest(res2)
    dw2 = ActorFenceDigest.welfare_digest(ctx2, obj2, dadp2)
    @info "fence digests two-bus" admm = repr(da2) welfare = repr(dw2)

    @test !haskey(ctx2.meta, :actor)

    # ---- IEEE-13 ----
    feeder = ieee13_modified()
    aggs = IEEE13Fixtures.build_ieee13_ground_aggregators(feeder)
    λ₀ = IEEE13Fixtures.mem_price_profile()
    Th = IEEE13Fixtures.T

    res = solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        ρ = 100.0,
        maxiter = 300,
        allow_export = true,
    )
    ctx, obj, dadp = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        allow_export = true,
    )
    da = ActorFenceDigest.admm_digest(res)
    dw = ActorFenceDigest.welfare_digest(ctx, obj, dadp)
    @info "fence digests ieee13" admm = repr(da) welfare = repr(dw)

    @test !haskey(ctx.meta, :actor)

    # Version-independent same-process fence (WR-03): the default result equals, bit for bit, the
    # all-welfare actor/slot routing computed on THIS Julia version.
    acts = [Portfolio(a; name = Symbol("site", i)) for (i, a) in enumerate(aggs)]
    res_slot = solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        ρ = 100.0,
        maxiter = 300,
        allow_export = true,
        actors = acts,
        _force_slot_path = true,
    )
    @test res_slot.welfare == res.welfare
    @test res_slot.dadp == res.dadp
    @test res_slot.iters == res.iters
    same_fields(a, b) = all(f -> getfield(a, f) == getfield(b, f), fieldnames(typeof(a)))
    @test same_fields(res_slot.residuals, res.residuals)
    @test keys(res_slot) == keys(res)
    ctx_a, obj_a, dadp_a = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        allow_export = true,
        actors = acts,
    )
    @test obj_a == obj
    @test dadp_a == dadp

    # Knife-edge canary (same pins as test_admm_knifeedge_canary.jl; never re-pinned here).
    kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
    s = TSODSO.Scenario(; kw..., strategy = :admm)
    r = TSODSO.run_scenario(s)
    @test r.iters == 56
    @test isapprox(r.welfare, -4823.66604824162; rtol = 1e-6, atol = 1e-3)

    # One digest assertion for the whole fence (single version-gate skip record).
    if VERSION == ActorFenceDigest.GOLDEN_VERSION
        @test (da2, dw2, da, dw) == (0xc1791cfe86ef6538, 0xd3ba3a3fbb317158, 0x27a82704e86fbdd9, 0x3b8e36e55565b99c)
    else
        @test_skip (da2, dw2, da, dw) == (0xc1791cfe86ef6538, 0xd3ba3a3fbb317158, 0x27a82704e86fbdd9, 0x3b8e36e55565b99c)
    end
end
