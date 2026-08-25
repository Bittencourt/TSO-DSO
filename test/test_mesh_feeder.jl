# Seam: data/mesh_topology.jl + data/MeshedFeeder.jl (MESH-01). Driven green by plan 23-01.
@testitem "mesh_topology: assert_connected accepts a cyclic feeder; MeshedFeeder mirrors Feeder's shape (MESH-01/D-09)" begin
    using TSODSO

    # Valid tree (for the checks assert_connected shares with assert_radial):
    # 2 buses, 1 branch, one root, connected.
    ok_buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
    ok_branches = [TSODSO.Branch(1, 2, 0.01, 0.02, 10.0)]
    A = TSODSO.assert_connected(ok_buses, ok_branches, 1)
    @test A !== nothing
    @test size(A) == (2, 1)   # node-branch incidence: N buses × B branches

    # NEW cyclic-accept case: a 3-bus triangle, nB = 3 > N - 1 = 2 -- this is
    # exactly the topology `assert_radial` rejects on the edge-count check
    # alone, but `assert_connected` MUST accept it (MESH-01, no tree
    # requirement).
    cyc_buses = [
        TSODSO.Bus(1, 0.95, 1.05, true),
        TSODSO.Bus(2, 0.95, 1.05, false),
        TSODSO.Bus(3, 0.95, 1.05, false),
    ]
    cyc_branches = [
        TSODSO.Branch(1, 2, 0.01, 0.02, TSODSO.SMAX_NO_LIMIT),
        TSODSO.Branch(2, 3, 0.01, 0.02, TSODSO.SMAX_NO_LIMIT),
        TSODSO.Branch(3, 1, 0.01, 0.02, TSODSO.SMAX_NO_LIMIT),
    ]
    Acyc = TSODSO.assert_connected(cyc_buses, cyc_branches, 1)
    @test size(Acyc) == (3, 3)

    # (1) Disconnected: 3 buses but bus 3 is unreachable from the root --
    #     parallel edge between 1 and 2 wastes a branch (edge-count check is
    #     dropped, so this must fail on connectivity alone, not edge count).
    disc_branches =
        [TSODSO.Branch(1, 2, 0.01, 0.02, 10.0), TSODSO.Branch(1, 2, 0.01, 0.02, 10.0)]
    @test_throws ArgumentError TSODSO.assert_connected(cyc_buses, disc_branches, 1)

    # (2a) Zero roots: a connected topology but no bus flagged is_root.
    noroot_buses = [TSODSO.Bus(1, 0.95, 1.05, false), TSODSO.Bus(2, 0.95, 1.05, false)]
    @test_throws ArgumentError TSODSO.assert_connected(noroot_buses, ok_branches, 1)

    # (2b) Two roots: a connected topology but two buses flagged is_root.
    tworoot_buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, true)]
    @test_throws ArgumentError TSODSO.assert_connected(tworoot_buses, ok_branches, 1)

    # (3) Root index / is_root flag DISAGREE: exactly one root bus, connected,
    #     but the `root` argument points at the non-flagged bus (WR-01).
    mismatch_buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
    @test_throws ArgumentError TSODSO.assert_connected(mismatch_buses, ok_branches, 2)

    # (4) Positional convention violated (WR-03): connected + one root, but the
    #     bus ids do not equal their 1-based positions.
    mislabeled_buses = [TSODSO.Bus(2, 0.95, 1.05, true), TSODSO.Bus(3, 0.95, 1.05, false)]
    @test_throws ArgumentError TSODSO.assert_connected(mislabeled_buses, ok_branches, 1)

    # (5) Branch endpoint out of range.
    outofrange_branches = [TSODSO.Branch(1, 9, 0.01, 0.02, 10.0)]
    @test_throws ArgumentError TSODSO.assert_connected(ok_buses, outofrange_branches, 1)

    # (6) Root out of range.
    @test_throws ArgumentError TSODSO.assert_connected(cyc_buses, cyc_branches, 9)

    # D-09 regression: the IDENTICAL 3-branch triangle edge list makes
    # `Feeder` throw `ArgumentError` (the radial gate was never weakened)
    # while `MeshedFeeder` succeeds on the same input.
    @test_throws ArgumentError TSODSO.Feeder(cyc_buses, cyc_branches, 1)
    mf = TSODSO.MeshedFeeder(cyc_buses, cyc_branches, 1)

    # Duck-typing check: MeshedFeeder exposes the exact same field shape
    # Feeder does, so solve_welfare's duck-typed feeder access works
    # unmodified (RESEARCH Assumption A4).
    @test hasproperty(mf, :buses) && hasproperty(mf, :branches) && hasproperty(mf, :root)
    @test mf.root == 1
    @test length(mf.buses) == 3
    @test length(mf.branches) == 3
end
