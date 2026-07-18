# Seam: data/topology.jl (DATA-02). RED until plan 01-02 fills the stub.
@testitem "topology: non-radial feeder raises a clear error; valid tree passes (DATA-02)" begin
    using TSODSO

    # Valid tree: 2 buses, 1 branch (edges == nodes - 1, connected, one root).
    ok_buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
    ok_branches = [TSODSO.Branch(1, 2, 0.01, 0.02, 10.0)]
    @test TSODSO.assert_radial(ok_buses, ok_branches, 1) !== nothing

    # Non-radial: 2 buses but 2 branches (a self-loop cycle) → must throw ArgumentError.
    bad_branches = [
        TSODSO.Branch(1, 2, 0.01, 0.02, 10.0),
        TSODSO.Branch(1, 2, 0.01, 0.02, 10.0),
    ]
    @test_throws ArgumentError TSODSO.assert_radial(ok_buses, bad_branches, 1)
end
