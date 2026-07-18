# Seam: data/Feeder.jl (DATA-01). Driven green by plan 01-02.
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

    # Structs are immutable: the types are non-mutable and field assignment errors.
    @test !ismutabletype(TSODSO.Feeder{Float64})
    @test !ismutabletype(TSODSO.Bus{Float64})
    @test !ismutabletype(TSODSO.Branch{Float64})
    @test_throws ErrorException setfield!(feeder, :root, 2)

    # Construction rejects a non-tree feeder (wrong branch count) with ArgumentError,
    # so `Feeder(...)` is itself the validation gate (not only `assert_radial`).
    bad_branches = [branches[1], TSODSO.Branch(1, 2, 0.01, 0.02, 10.0)]
    @test_throws ArgumentError TSODSO.Feeder(buses, bad_branches, 1)

    # Construction rejects an out-of-band MAGNITUDE feeder on the LIVE path:
    # topology is valid, but bus voltage 1.5 pu is outside [0.8, 1.2], so the
    # `assert_magnitudes` tripwire fires during `Feeder(...)` (INFRA-05).
    bad_mag_buses = [
        TSODSO.Bus(1, 0.95, 1.5, true),    # vmax 1.5 pu is implausible
        TSODSO.Bus(2, 0.95, 1.05, false),
    ]
    @test_throws AssertionError TSODSO.Feeder(bad_mag_buses, branches, 1)
end
