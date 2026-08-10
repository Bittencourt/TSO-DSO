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

# Review 23 CR-01/WR-03 regression: the certificate's verdict and recovered phasor field
# must be invariant to branch STORAGE orientation (physically meaningless, unconstrained by
# assert_connected) -- the Phase-20 CR-01 discipline (ac_oracle.jl's "Branch orientation"
# note, enforced for the radial shadow voltage in test/test_restricted_branch_flow.jl),
# applied to the new signed-orientation traversal.
#
# DEVIATION from the review's literal suggestion (flip branch 3 alone): a SINGLE flipped
# branch is NOT solver-equivalent on this diamond. ConvexBranchFlow's exactness-copy
# machinery forces the cycle identity sum(eps_b*(r_b^2+x_b^2)*l_b) = 0, where eps_b is the
# branch's STORED orientation relative to the cycle traversal; one flip turns the diamond's
# even 2-2 eps split into 3-1, producing a structural cone gap (~4e-2, empirically measured)
# that solve_welfare's assert_socp_exact! refuses -- the same mechanism fixtures_phase23.jl's
# header documents for the flipped triangle. The one physically-identical re-encoding that
# PRESERVES the identity is the FULL root-inward reversal (every branch stored child->parent,
# a global eps sign flip). That reversal also exercises CR-01 maximally: ALL THREE tree
# edges are traversed backwards (bsigned < 0), so the -(S_b - z*l_b) receiving-end
# correction carries the whole phasor recovery; branch 3 stays the chord (anchored at bus 4
# instead of bus 2).
@testitem "certify_angle_recoverable!: reversed-orientation re-encoding -- verdicts and phasors invariant (review CR-01/WR-03)" setup = [
    Phase23Fixtures,
] begin
    using TSODSO, Test

    # Full root-inward re-encoding of Phase23Fixtures.mesh_feeder (same buses, same (r,x)
    # literals, every branch stored child->parent).
    function reversed_mesh_feeder(profile::Symbol)
        rx =
            profile == :uniform ? Phase23Fixtures.UNIFORM_RX :
            Phase23Fixtures.HETEROGENEOUS_RX
        buses = [
            TSODSO.Bus(1, 0.95, 1.05, true),
            TSODSO.Bus(2, 0.90, 1.10, false),
            TSODSO.Bus(3, 0.90, 1.10, false),
            TSODSO.Bus(4, 0.90, 1.10, false),
        ]
        branches = [
            TSODSO.Branch(2, 1, rx[1]..., TSODSO.SMAX_NO_LIMIT),
            TSODSO.Branch(3, 1, rx[2]..., TSODSO.SMAX_NO_LIMIT),
            TSODSO.Branch(4, 2, rx[3]..., TSODSO.SMAX_NO_LIMIT),
            TSODSO.Branch(4, 3, rx[4]..., TSODSO.SMAX_NO_LIMIT),
        ]
        return TSODSO.MeshedFeeder(buses, branches, 1)
    end

    λ₀ = Phase23Fixtures.mesh_lambda0()
    for profile in (:uniform, :heterogeneous)
        ctx_c, _, _ = solve_welfare(
            Phase23Fixtures.mesh_feeder(profile),
            MeshedFlow(),
            Phase23Fixtures.mesh_aggregators();
            T = Phase23Fixtures.T_MESH,
            λ₀ = λ₀,
        )
        r_c = certify_angle_recoverable!(ctx_c; report = true)
        ctx_r, _, _ = solve_welfare(
            reversed_mesh_feeder(profile),
            MeshedFlow(),
            Phase23Fixtures.mesh_aggregators();
            T = Phase23Fixtures.T_MESH,
            λ₀ = λ₀,
        )
        r_r = certify_angle_recoverable!(ctx_r; report = true)

        # Verdicts must match exactly.
        @test r_r.status == r_c.status
        @test r_r.recoverable == r_c.recoverable

        # Residuals: the reversal necessarily flips the chord's anchor endpoint (its own
        # defining equation is evaluated from bus 4 instead of bus 2), a second-order
        # anchor effect measured at ~6e-4 relative (:uniform) and ~2.0e-2 relative
        # (:heterogeneous, 8x impedances) AFTER the CR-01 fix -- so exact equality is not
        # achievable; the bounds below hold with margin post-fix and would NOT catch the
        # bare-flip bug through the residual alone (the exactness-copy identity makes the
        # per-edge |z|^2*l errors telescope to ~zero around the cycle). The sharp
        # discriminator is the PHASOR-field assertion below.
        rtol_resid = profile == :uniform ? 0.01 : 0.05
        @test isapprox(r_r.worst_residual, r_c.worst_residual; rtol = rtol_resid)

        # The recovered phasor field itself must be storage-invariant (measured agreement
        # ~2e-10 post-fix; the pre-fix bare flip is off by |z|^2*l per backward edge,
        # ~2.5e-5 even on :uniform -- 4+ orders above this bound). Only available on the
        # certified path (angles === nothing when unrecoverable).
        if r_c.recoverable
            @test maximum(abs, r_r.angles .- r_c.angles) < 1.0e-8
        end
    end

    # Radial big-impedance probe -- the strongest backward-edge discriminator: a 2-bus
    # feeder with the :heterogeneous branch-1 impedance (r=0.32, x=0.08) stored REVERSED
    # (child->parent). No chord exists, so the certificate certifies trivially and returns
    # the recovered angles; those angles are computed ENTIRELY through the backward-edge
    # recursion. Pre-fix, the bare flip is off by |z|^2*l ~ 5.6e-3 here (measured);
    # post-fix agreement with the forward encoding is ~2.5e-10.
    rbuses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.80, 1.20, false)]
    rtherm = TSODSO.Thermostatic(2, 0.0, 1.0, 20.0, 20.0, 20.0, 0.30, 0.30, 0.5, [20.0])
    raggs = [TSODSO.Aggregator(2, 0.95, [rtherm], [0.0])]
    fwd = TSODSO.Feeder(rbuses, [TSODSO.Branch(1, 2, 0.32, 0.08, TSODSO.SMAX_NO_LIMIT)], 1)
    rev = TSODSO.Feeder(rbuses, [TSODSO.Branch(2, 1, 0.32, 0.08, TSODSO.SMAX_NO_LIMIT)], 1)
    ctx_f, _, _ = solve_welfare(fwd, ConvexBranchFlow(), raggs; T = 1, λ₀ = [4.0])
    ctx_v, _, _ = solve_welfare(rev, ConvexBranchFlow(), raggs; T = 1, λ₀ = [4.0])
    r_f = certify_angle_recoverable!(ctx_f; report = true)
    r_v = certify_angle_recoverable!(ctx_v; report = true)
    @test r_f.status == :angle_certified
    @test r_v.status == :angle_certified
    @test maximum(abs, r_v.angles .- r_f.angles) < 1.0e-8
end
