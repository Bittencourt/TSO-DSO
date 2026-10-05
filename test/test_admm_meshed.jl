# Seam: admm/solve_admm.jl x MeshedFeeder/MeshedFlow x live reactive consensus (ARCH-06,
# Plan 34-10). Meshed ADMM with LIVE reactive pricing cross-validated against the centralized
# meshed `solve_welfare` (`dual(:balance_p)` / `dual(:balance_q)`); closes the v3.0 MESH-06 advisory.
#
# MEASURED TOLERANCES (memory `highs-exactness-defaults`: measure, never pick). Fixture: Phase-23
# diamond, `:heterogeneous` profile, Thermostatic phi = 0.95 (centralized reactive price
# 0.2511 / 0.1354 at buses 2/3), eps = (eps_abs 1e-6, eps_rel 1e-5), T = 1, lambda0 = 4.0.
# Observed (max over buses 2,3; max|dP| active price, max|dQ| reactive price, |dW| welfare):
#   rho0 =   1 : 37 iters, dP 5.40e-5, dQ 5.27e-5, dW 4.11e-7
#   rho0 =  10 : 16 iters, dP 3.16e-5, dQ 4.10e-5, dW 5.81e-6
#   rho0 = 100 :  6 iters, dP 5.48e-5, dQ 6.10e-5, dW 7.52e-6
# Angle composition (uniform/hetero, phi = 1 + FourQuadBESS): worst residual central vs ADMM
#   0.0071986 vs 0.0071997 (certified); 0.0712824 vs 0.0712808 (unrecoverable).
# Asserted: price atol = 5e-4 (headroom factor 8.2x = 5e-4/6.10e-5 over the worst observed price gap),
# welfare rtol = 1e-4. Research-table worst price gap across rho0 was 6.1e-5; the gap tracks the
# ADMM dual tolerance and floors at ~1e-5 (interior-point dual accuracy) -- never assert below that.

@testitem "admm meshed: LIVE reactive ADMM matches centralized meshed prices + welfare (ARCH-06)" setup =
    [MeshFixtures] tags = [:admm, :mesh, :reactive] begin
    using TSODSO, Test
    using JuMP: dual

    feeder = MeshFixtures.mesh_feeder(:heterogeneous)
    aggs = MeshFixtures.mesh_aggregators_phi(0.95)
    λ₀ = MeshFixtures.mesh_lambda0()
    T = MeshFixtures.T_MESH

    ctx_c, obj_c, _ = solve_welfare(feeder, MeshedFlow(), aggs; T = T, λ₀ = λ₀)
    p_c = [dual(ctx_c.constraints[:balance_p][j, 1]) for j in (2, 3)]
    q_c = [dual(ctx_c.constraints[:balance_q][j, 1]) for j in (2, 3)]
    # Non-vacuity (T-34-32): the reactive reference is clearly nonzero.
    @test all(>(0.05), q_c)

    worst = Float64[]
    for ρ₀ in (10.0, 1.0, 100.0)
        r = solve_admm(
            feeder,
            MeshedFlow(),
            aggs;
            T = T,
            λ₀ = λ₀,
            ρ = ρ₀,
            ε_abs = 1e-6,
            ε_rel = 1e-5,
            reactive_consensus = ReactiveMode.LIVE,
            maxiter = 500,
        )
        dP = maximum(abs.(vec(r.λ) .- p_c))
        dQ = maximum(abs.(vec(r.mu_q) .- q_c))
        dW = abs(r.welfare - obj_c)
        @info "ARCH-06 measured" ρ₀ iters = r.iters dP dQ dW
        push!(worst, max(dP, dQ))
        @test r.status == :converged
        @test r.reactive_consensus_mode == ReactiveMode.LIVE
        @test r.exact_maxgap < 1e-6
        @test isapprox(vec(r.λ), p_c; atol = 5e-4)
        @test isapprox(vec(r.mu_q), q_c; atol = 5e-4)
        @test isapprox(r.welfare, obj_c; rtol = 1e-4)
    end
    @info "ARCH-06 worst price gap" worst_gap = maximum(worst) headroom = 5e-4 / maximum(worst)
end

@testitem "admm meshed: ADMM dso_ctx certifies the angle verdict like the centralized ctx (ARCH-06)" setup =
    [MeshFixtures] tags = [:admm, :mesh] begin
    using TSODSO, Test

    λ₀ = MeshFixtures.mesh_lambda0()
    T = MeshFixtures.T_MESH

    function verdicts(profile)
        feeder = MeshFixtures.mesh_feeder(profile)
        aggs = MeshFixtures.mesh_aggregators_phi(1.0; bess = true)
        ctx_c, _, _ = solve_welfare(feeder, MeshedFlow(), aggs; T = T, λ₀ = λ₀)
        r = solve_admm(
            feeder,
            MeshedFlow(),
            aggs;
            T = T,
            λ₀ = λ₀,
            ρ = 10.0,
            ε_abs = 1e-6,
            ε_rel = 1e-5,
            reactive_consensus = ReactiveMode.LIVE,
            maxiter = 500,
        )
        return (
            certify_angle_recoverable!(ctx_c; report = true),
            certify_angle_recoverable!(r.dso_ctx; report = true),
        )
    end

    cu, au = verdicts(:uniform)
    @info "ARCH-06 angle uniform" central = cu.worst_residual admm = au.worst_residual
    @test cu.status == :angle_certified
    @test au.status == cu.status
    @test isapprox(au.worst_residual, cu.worst_residual; atol = 1e-4)

    ch, ah = verdicts(:heterogeneous)
    @info "ARCH-06 angle heterogeneous" central = ch.worst_residual admm = ah.worst_residual
    @test ch.status == :angle_unrecoverable
    @test ah.status == ch.status
    @test isapprox(ah.worst_residual, ch.worst_residual; atol = 1e-4)
end

@testitem "admm meshed: radial formulations x MeshedFeeder throw; MeshedFlow runs (ARCH-06, T-34-33)" setup =
    [MeshFixtures] tags = [:admm, :mesh] begin
    using TSODSO, Test

    feeder = MeshFixtures.mesh_feeder(:heterogeneous)
    aggs = MeshFixtures.mesh_aggregators_phi(0.95)
    λ₀ = MeshFixtures.mesh_lambda0()
    kw = (; T = MeshFixtures.T_MESH, λ₀ = λ₀, ρ = 10.0)

    for pf in (ConvexBranchFlow(), LinDistFlow())
        err = try
            solve_admm(feeder, pf, aggs; kw...)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("MeshedFeeder", err.msg)
    end

    r = solve_admm(feeder, MeshedFlow(), aggs; kw..., ε_abs = 1e-6, ε_rel = 1e-5)
    @test r.status == :converged
end
