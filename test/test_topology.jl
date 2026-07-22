# Seam: data/topology.jl (DATA-02). Driven green by plan 01-02.
@testitem "topology: non-radial feeder raises a clear error; valid tree passes (DATA-02)" begin
    using TSODSO

    # Valid tree: 2 buses, 1 branch (edges == nodes - 1, connected, one root).
    ok_buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
    ok_branches = [TSODSO.Branch(1, 2, 0.01, 0.02, 10.0)]
    A = TSODSO.assert_radial(ok_buses, ok_branches, 1)
    @test A !== nothing
    @test size(A) == (2, 1)   # node-branch incidence: N buses × B branches

    # (1) Wrong branch count: 2 buses but 2 branches → must throw ArgumentError.
    bad_count =
        [TSODSO.Branch(1, 2, 0.01, 0.02, 10.0), TSODSO.Branch(1, 2, 0.01, 0.02, 10.0)]
    @test_throws ArgumentError TSODSO.assert_radial(ok_buses, bad_count, 1)

    # (2) Disconnected: 3 buses, 2 branches (correct edge count) but bus 3 is
    #     unreachable from the root — parallel edge between 1 and 2 wastes a branch.
    disc_buses = [
        TSODSO.Bus(1, 0.95, 1.05, true),
        TSODSO.Bus(2, 0.95, 1.05, false),
        TSODSO.Bus(3, 0.95, 1.05, false),
    ]
    disc_branches =
        [TSODSO.Branch(1, 2, 0.01, 0.02, 10.0), TSODSO.Branch(1, 2, 0.01, 0.02, 10.0)]
    @test_throws ArgumentError TSODSO.assert_radial(disc_buses, disc_branches, 1)

    # (3a) Zero roots: a valid tree topology but no bus flagged is_root.
    noroot_buses = [TSODSO.Bus(1, 0.95, 1.05, false), TSODSO.Bus(2, 0.95, 1.05, false)]
    @test_throws ArgumentError TSODSO.assert_radial(noroot_buses, ok_branches, 1)

    # (3b) Two roots: a valid tree topology but two buses flagged is_root.
    tworoot_buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, true)]
    @test_throws ArgumentError TSODSO.assert_radial(tworoot_buses, ok_branches, 1)

    # (4) Root index / is_root flag DISAGREE: exactly one root bus, valid tree,
    #     but the `root` argument points at the non-flagged bus (WR-01). The
    #     stored frontier index and the frontier flag must never silently differ.
    mismatch_buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
    @test_throws ArgumentError TSODSO.assert_radial(mismatch_buses, ok_branches, 2)

    # (5) Positional convention violated (WR-03): valid tree + one root, but the
    #     bus ids do not equal their 1-based positions. Incidence/adjacency index
    #     by position, so this must be rejected loudly rather than silently
    #     indexing inconsistently with `bus.id`.
    mislabeled_buses = [TSODSO.Bus(2, 0.95, 1.05, true), TSODSO.Bus(3, 0.95, 1.05, false)]
    @test_throws ArgumentError TSODSO.assert_radial(mislabeled_buses, ok_branches, 1)
end
