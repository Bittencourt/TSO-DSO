# Seam: models/mesh_angle_certificate.jl (MESH-03). Driven green by plan 23-03.
@testitem "certify_angle_recoverable!: both fixture profiles, status/provenance/strict-mode (MESH-03/D-05/D-06/D-07)" setup = [
    Phase23Fixtures,
] begin
    using TSODSO, Test

    aggs = Phase23Fixtures.mesh_aggregators()
    λ₀ = Phase23Fixtures.mesh_lambda0()

    # (a) :uniform certifies -- angles returned, :angle_certified, never a throw.
    ctx_u, _, _ = solve_welfare(
        Phase23Fixtures.mesh_feeder(:uniform),
        MeshedFlow(),
        aggs;
        T = Phase23Fixtures.T_MESH,
        λ₀ = λ₀,
    )
    r_u = certify_angle_recoverable!(ctx_u; report = true)
    @test r_u.recoverable == true
    @test r_u.status == :angle_certified
    @test r_u.angles isa Matrix{ComplexF64}

    # (b) :heterogeneous reports :angle_unrecoverable under the DEFAULT report=true --
    # angles===nothing, NEVER throws.
    ctx_h, _, _ = solve_welfare(
        Phase23Fixtures.mesh_feeder(:heterogeneous),
        MeshedFlow(),
        aggs;
        T = Phase23Fixtures.T_MESH,
        λ₀ = λ₀,
    )
    r_h = certify_angle_recoverable!(ctx_h; report = true)
    @test r_h.recoverable == false
    @test r_h.status == :angle_unrecoverable
    @test r_h.angles === nothing

    # (c) The SAME :heterogeneous call with report=false THROWS -- D-05's documented opt-in
    # strict/throw mode, the one place this test directly exercises the divergence from the
    # certificate family's throw-by-default.
    ctx_h2, _, _ = solve_welfare(
        Phase23Fixtures.mesh_feeder(:heterogeneous),
        MeshedFlow(),
        aggs;
        T = Phase23Fixtures.T_MESH,
        λ₀ = λ₀,
    )
    @test_throws ErrorException certify_angle_recoverable!(ctx_h2; report = false)

    # (d) Provenance is READ, never fabricated: a plain ConvexBranchFlow context (which
    # never stashes :formulation) run through the SAME certificate reports :unknown --
    # mirrors restriction_exactness.jl's own "never fabricate provenance" test discipline.
    # A radial 2-bus feeder has NO chords, so the certificate degenerately (but honestly)
    # certifies -- worst_residual == 0.0, recoverable == true.
    plain_buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.90, 1.10, false)]
    plain_branches = [TSODSO.Branch(1, 2, 0.01, 0.02, TSODSO.SMAX_NO_LIMIT)]
    plain_feeder = TSODSO.Feeder(plain_buses, plain_branches, 1)
    plain_therm = TSODSO.Thermostatic(2, 0.0, 1.0, 20.0, 20.0, 20.0, 0.1, 0.1, 0.5, [20.0])
    plain_aggs = [TSODSO.Aggregator(2, 0.95, [plain_therm], [0.0])]
    ctx_plain, _, _ = solve_welfare(plain_feeder, ConvexBranchFlow(), plain_aggs; T = 1, λ₀ = [4.0])
    r_plain = certify_angle_recoverable!(ctx_plain; report = true)
    @test r_plain.recoverable == true
    @test r_plain.worst_residual == 0.0
    @test ctx_plain.meta[:price_provenance].formulation == :unknown
    @test ctx_plain.meta[:price_provenance].certificate == :certify_angle_recoverable!

    # (e) Residual ordering: :heterogeneous sits multiple orders-of-magnitude (measured
    # ~9.7x, D-08) above :uniform's -- the honest structural gap (D-10), never a knife-edge.
    @test r_h.worst_residual > 5 * r_u.worst_residual

    # ctx.meta[:price_provenance] correctly names the SOLVED formulation on the MeshedFlow
    # paths (never fabricated, T-23-06).
    @test ctx_u.meta[:price_provenance].formulation == :MeshedFlow
    @test ctx_h.meta[:price_provenance].formulation == :MeshedFlow
    @test ctx_u.meta[:price_provenance].certificate == :certify_angle_recoverable!
end
