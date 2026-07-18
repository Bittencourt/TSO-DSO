# Seam: data/Feeder.jl (DATA-01). RED until plan 01-02 fills the stub.
@testitem "feeder: immutable JuMP-free feeder constructs from valid radial data (DATA-01)" begin
    using TSODSO

    # A trivial two-bus radial feeder: one root (frontier) bus, one leaf, one branch.
    buses = [
        TSODSO.Bus(1, 0.95, 1.05, true),   # id, vmin, vmax, is_root
        TSODSO.Bus(2, 0.95, 1.05, false),
    ]
    branches = [TSODSO.Branch(1, 2, 0.01, 0.02, 10.0)]  # from, to, r, x, smax
    feeder = TSODSO.Feeder(buses, branches, 1)

    @test length(feeder.buses) == 2
    @test length(feeder.branches) == 1
    @test feeder.root == 1
end
