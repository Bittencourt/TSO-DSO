# test/test_ieee123.jl
#
# Seam: the modified IEEE 123-node feeder fixture (DATA-03 scale target, RESEARCH Pitfall 4).
#
# RED @testitem harness (Wave 0 of Phase 7). Plan 07-02 turns these green by IMPLEMENTING
# `ieee123_modified()` (thesis App. E, per-unit, radial, relabeled to contiguous ids). The tests
# are NEVER edited to go green. Every item name contains "ieee123" so `occursin("ieee123", ti.name)`
# selects them.
#
# RED SIGNAL (never a runner crash): the sole failing assertion is
# `isdefined(TSODSO, :ieee123_modified)`; every structural assert sits BEHIND that guard.
#
# CONTRACT pinned here (the Feeder invariants `assert_radial` / `assert_magnitudes` enforce):
#   - radial: `length(branches) == length(buses) − 1` (tie switches open, RESEARCH Pitfall 4).
#   - contiguous ids: `bus.id == position` for every bus (the framework relabel convention).
#   - a single root at the substation/frontier terminal (thesis 150), all other buses non-root.
#   - voltage-constrained band V ∈ [0.9, 1.1] (thesis Case B, looser than IEEE-13).

@testitem "ieee123: fixture is radial, contiguous, single-root (ieee123)" tags = [:phase7] begin
    using TSODSO

    # RED until Wave 2 (plan 07-02 fills the ieee123_modified fixture).
    @test isdefined(TSODSO, :ieee123_modified)

    if isdefined(TSODSO, :ieee123_modified)
        feeder = ieee123_modified()
        N = length(feeder.buses)

        # radial: a tree on N buses has exactly N−1 edges (tie switches open).
        @test length(feeder.branches) == N - 1

        # contiguous 1-based ids (bus.id == position) — the relabel convention.
        @test all(i -> feeder.buses[i].id == i, 1:N)

        # exactly one root, at the declared root index; every other bus non-root.
        @test count(b -> b.is_root, feeder.buses) == 1
        @test feeder.buses[feeder.root].is_root
    end
end

@testitem "ieee123: voltage band + per-unit magnitude sanity (ieee123)" tags = [:phase7] begin
    using TSODSO

    # RED until Wave 2 (plan 07-02).
    @test isdefined(TSODSO, :ieee123_modified)

    if isdefined(TSODSO, :ieee123_modified)
        feeder = ieee123_modified()

        # thesis Case B voltage band V ∈ [0.9, 1.1] on the non-root buses.
        for b in feeder.buses
            b.is_root && continue
            @test b.vmin <= 0.9 + 1e-9
            @test b.vmax >= 1.1 - 1e-9
        end

        # branch r/x are strictly positive per-unit; smax honours the strict 0 < smax < 100 band.
        for br in feeder.branches
            @test br.r > 0
            @test br.x > 0
            @test 0 < br.smax < 100
        end
    end
end

@testitem "ieee123: relabel map + substation root spot-check (ieee123)" tags = [:phase7] begin
    using TSODSO

    # RED until Wave 2 (plan 07-02 fills the fixture + its documented relabel map).
    @test isdefined(TSODSO, :ieee123_modified)
    @test isdefined(TSODSO, :ieee123_relabel_map)

    if isdefined(TSODSO, :ieee123_modified) && isdefined(TSODSO, :ieee123_relabel_map)
        feeder = ieee123_modified()
        N = length(feeder.buses)
        remap = ieee123_relabel_map()

        # the map is a bijection thesis_terminal -> 1..N (one struct index per terminal).
        @test length(remap) == N
        @test sort(collect(values(remap))) == collect(1:N)

        # the substation/frontier terminal 150 is struct index 1, and IS feeder.root (Open-Q1).
        @test remap[TSODSO.IEEE123_ROOT_TERMINAL] == 1
        @test feeder.root == remap[TSODSO.IEEE123_ROOT_TERMINAL]

        # documented spot-checks: smallest non-root terminal -> 2; a known high terminal -> N.
        @test remap[1] == 2
        @test remap[450] == N
    end
end

@testitem "ieee123: transit (zero-injection) bus count (ieee123)" tags = [:phase7] begin
    using TSODSO

    # RED until Wave 2 (plan 07-02 exposes the load/transit split).
    @test isdefined(TSODSO, :ieee123_modified)
    @test isdefined(TSODSO, :ieee123_load_nodes)

    if isdefined(TSODSO, :ieee123_modified) && isdefined(TSODSO, :ieee123_load_nodes)
        feeder = ieee123_modified()
        N = length(feeder.buses)
        load_nodes = ieee123_load_nodes()

        # load nodes are distinct, non-root, in range (the aggregator-coupling axis).
        @test allunique(load_nodes)
        @test all(j -> 2 <= j <= N, load_nodes)
        @test !(feeder.root in load_nodes)

        # thesis Case B ships 85 spot-load nodes; the rest of the non-root buses are TRANSIT.
        @test length(load_nodes) == 85

        # the fixture genuinely exercises the transit path plan 07-03 relaxes: > 0 transit buses.
        transit = N - 1 - length(load_nodes)
        @test transit > 0
    end
end

@testitem "ieee123: pinned real-impedance spot-check on branch (149,1) (ieee123)" tags = [:phase7] begin
    using TSODSO

    # Real per-segment Ω→pu impedance ingestion (plan 17-02, IMPED-02): branch (149,1)
    # (LineCode=1, Length=0.4) must convert via to_pu_impedance on IEEE123_BASE, not the
    # retired uniform synthetic scalar.
    @test isdefined(TSODSO, :ieee123_modified)

    if isdefined(TSODSO, :ieee123_modified)
        feeder = ieee123_modified()
        remap = ieee123_relabel_map()

        from_idx = remap[149]
        to_idx = remap[1]
        br = only(filter(b -> b.from == from_idx && b.to == to_idx, feeder.branches))

        expected_r = TSODSO.to_pu_impedance(0.057967 * 0.4, TSODSO.IEEE123_BASE)
        expected_x = TSODSO.to_pu_impedance(0.118756 * 0.4, TSODSO.IEEE123_BASE)

        @test isapprox(br.r, expected_r; atol = 1e-6)
        @test isapprox(br.x, expected_x; atol = 1e-6)
    end
end
