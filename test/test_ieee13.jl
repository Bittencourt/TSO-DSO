# Seam: data/ieee13.jl (DATA-03) — the modified IEEE 13-node built-in fixture.
#
# Fixture-level @testitems (driven GREEN by plan 04-03). They assert that
# `ieee13_modified()` constructs as a radial, magnitude-valid, per-unit `Feeder`
# and that its topology matches thesis Table 4.1 under the node `k` → struct
# index `k+1` shift. Item names contain "ieee13" so the `occursin(...)` filter
# selects them.
#
# The GLB-CVX SOCP solve on this feeder (OPT-02) and the thesis-number ground-truth
# regression (OPT-02/OPT-03) are NOT exercised here — they depend on the SOCP
# formulation (04-02) and the pinned golden, and are added by plan 04-06's
# "ground" items. Keeping this file solve-free keeps the fixture check fast and
# independent of the formulation wave.

@testitem "ieee13: ieee13_modified constructs radial — 11 buses, 10 branches, root at index 1 (DATA-03)" tags = [
    :ieee13,
] begin
    using TSODSO

    @test isdefined(TSODSO, :ieee13_modified)

    feeder = TSODSO.ieee13_modified()               # runs assert_radial + assert_magnitudes
    @test length(feeder.buses) == 11                 # thesis node 0 + nodes 1..10
    @test length(feeder.branches) == 10              # radial tree ⇒ buses − 1
    @test feeder.root == 1                            # index 1 = thesis MEM frontier (node 0)
    @test feeder.buses[1].is_root                     # root bus carries the is_root flag
    @test count(b -> b.is_root, feeder.buses) == 1    # exactly one frontier bus
    @test eltype(feeder.branches) == TSODSO.Branch{Float64}   # per-unit Float64 fixture
end

@testitem "ieee13: fixture magnitudes & topology match thesis Table 4.1 (DATA-03)" tags = [
    :ieee13,
] begin
    using TSODSO

    feeder = TSODSO.ieee13_modified()

    # Voltage band: every bus 0.95 / 1.05 pu (Table 4.1).
    @test all(b -> b.vmin == 0.95, feeder.buses)
    @test all(b -> b.vmax == 1.05, feeder.buses)

    # Head branch (thesis 0→1 ⇒ struct index 1→2) carries the single binding limit:
    # S_max = 6.86 MVA ⇒ 0.0686 pu on the 100 MVA base.
    head = feeder.branches[1]
    @test head.from == 1 && head.to == 2
    @test head.smax ≈ 0.0686

    # Interior branches are effectively unconstrained but STRICTLY inside the
    # 0 < smax < 100 magnitude band (99.0 sentinel, Open Q2 / Assumption A4).
    interior = feeder.branches[2:end]
    @test all(br -> br.smax == 99.0, interior)
    @test all(br -> 0 < br.smax < 100.0, feeder.branches)

    # Topology spot-checks under the node k → struct index k+1 shift:
    #   branch 1: thesis (0,1) → index (1,2), r 0.310
    @test (feeder.branches[1].from, feeder.branches[1].to) == (1, 2)
    @test feeder.branches[1].r ≈ 0.310 && feeder.branches[1].x ≈ 0.155
    #   branch 9: thesis (3,9) → index (4,10), r 0.600 (the long lateral)
    @test (feeder.branches[9].from, feeder.branches[9].to) == (4, 10)
    @test feeder.branches[9].r ≈ 0.600 && feeder.branches[9].x ≈ 0.300
    #   branch 10: thesis (2,10) → index (3,11), r 0.300
    @test (feeder.branches[10].from, feeder.branches[10].to) == (3, 11)

    # Impedances stay well inside the per-unit sanity band (0 ≤ r,x < 5).
    @test all(br -> 0 ≤ br.r < 5.0 && 0 ≤ br.x < 5.0, feeder.branches)
end
