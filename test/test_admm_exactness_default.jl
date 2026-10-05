# Phase 35 (ARCH-10): ADMM consolidation exactness gate defaults to the hybrid floor.

@testmodule ExactDefaultHelpers begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    function fixed_ctx(br, vval, lval)
        feeder = Feeder([Bus(1, 0.95, 1.1, true), Bus(2, 0.95, 1.1, false)], [br], 1)
        model = Model(select_optimizer(SOCP()))
        @variable(model, v[1:2, 1:1])
        @variable(model, v̂[1:2, 1:1])
        @variable(model, P[1:1, 1:1])
        @variable(model, Q[1:1, 1:1])
        @variable(model, l[1:1, 1:1])
        fix.(v, vval; force = true)
        fix.(v̂, vval; force = true)
        fix.(P, 0.0; force = true)
        fix.(Q, 0.0; force = true)
        fix.(l, lval; force = true)
        @objective(model, Max, 0)
        optimize!(model)
        ctx = TSODSO.ModelContext(model)
        ctx.feeder = feeder
        ctx.T = 1
        ctx.pf_vars = (; v, v̂, P, Q, l)
        return ctx
    end

    ctx_A() = fixed_ctx(Branch(1, 2, 0.01, 0.02, 90.0), 1.0, 5.0e-6)
    ctx_N() = fixed_ctx(Branch(1, 2, 2.4e-6, 5.6e-6, TSODSO.SMAX_NO_LIMIT), 1.06, 1.7e-3)
end

@testitem "admm exactness default: hybrid floor accepts smax=90 gap 5e-6, flat 1e-6 refuses (A)" setup =
    [ExactDefaultHelpers] tags = [:exact, :admm] begin
    using TSODSO
    ctx = ExactDefaultHelpers.ctx_A()
    @test_throws CertificateError TSODSO.assert_socp_exact!(ctx; atol = 1e-6)
    mg = TSODSO.assert_socp_exact!(ctx)
    @test isapprox(mg, 5e-6; rtol = 1e-3)
end

@testitem "admm exactness default: near-zero-r inexact point still throws (N)" setup =
    [ExactDefaultHelpers] tags = [:exact, :admm] begin
    using TSODSO
    ctx = ExactDefaultHelpers.ctx_N()
    @test_throws CertificateError TSODSO.assert_socp_exact!(ctx)
end

@testitem "admm exactness default: solve_admm default == atol_exact=nothing, overrides work (B)" setup =
    [Phase6Fixtures, Phase4Fixtures] tags = [:exact, :admm] begin
    using TSODSO
    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
    kw = (;
        T = Phase6Fixtures.T,
        λ₀ = Phase6Fixtures.two_bus_lambda0(),
        ρ = Phase6Fixtures.RHO_2BUS,
        allow_export = true,
    )
    r1 = solve_admm(feeder, ConvexBranchFlow(), aggs; kw...)
    r2 = solve_admm(feeder, ConvexBranchFlow(), aggs; kw..., atol_exact = nothing)
    @test r1.iters == r2.iters
    @test r1.welfare == r2.welfare
    @test r1.exact_maxgap == r2.exact_maxgap
    # The throw assertion below is only meaningful because the consolidation gap is > 0.
    @test r1.exact_maxgap > 0
    @test_throws CertificateError solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs;
        kw...,
        atol_exact = 1e-30,
        rtol_exact = 0.0,
    )
    r3 = solve_admm(feeder, ConvexBranchFlow(), aggs; kw..., atol_exact = Inf)
    @test r3.iters == r1.iters
end

@testitem "admm exactness default: hybrid_ratios diagnostic" setup = [ExactDefaultHelpers] tags =
    [:exact, :admm] begin
    using TSODSO
    rA = TSODSO.hybrid_ratios(ExactDefaultHelpers.ctx_A())
    @test length(rA) == 1
    @test isapprox(rA[1].gap, 5e-6; rtol = 1e-3)
    @test isapprox(rA[1].atol_b, 8.1e-6; rtol = 1e-3)
    @test rA[1].ratio < 1
    rN = TSODSO.hybrid_ratios(ExactDefaultHelpers.ctx_N())
    @test rN[1].ratio > 1e3
    @test rN[1].r_pu == 2.4e-6
    @test isapprox(rN[1].loss_impact, 4e-9; rtol = 0.5)
    @test issorted([r.ratio for r in rN]; rev = true)
    # WR-02 (35-REVIEW): hybrid_ratios takes the gate's own kwargs and agrees with its verdict
    # for the SAME kwargs (both compute rows through the shared `_cone_row` helper).
    ctxA = ExactDefaultHelpers.ctx_A()
    rA_flat = TSODSO.hybrid_ratios(ctxA; atol = 1e-6)
    @test rA_flat[1].atol_b == 1e-6
    @test rA_flat[1].ratio > 1                     # gate with atol = 1e-6 refuses ctx_A ...
    @test_throws CertificateError TSODSO.assert_socp_exact!(ctxA; atol = 1e-6)
    rA_eps = TSODSO.hybrid_ratios(ctxA; ε = 1e-11)  # ... and a smaller ε drops the floor to τ
    @test rA_eps[1].atol_b == TSODSO.TAU_SOLVER_FIX08
    @test rA_eps[1].ratio > 1
    @test_throws CertificateError TSODSO.assert_socp_exact!(ctxA; ε = 1e-11)
    @test TSODSO.hybrid_ratios(ctxA; τ_solver = 1e-5)[1].atol_b == 1e-5
end
