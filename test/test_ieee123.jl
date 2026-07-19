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
