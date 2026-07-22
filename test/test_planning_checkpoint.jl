# test/test_planning_checkpoint.jl
#
# Seam: src/planning/checkpoint.jl (D-10). Two @testitems (setup = [Phase8Fixtures] for
# `with_tempdir`, tagged [:planning]):
#   1. round-trip: checkpoint_iteration! writes a JLD2 file that resume_from_checkpoint
#      reads back, with `state` round-tripping through the wload/JLD2 contract;
#   2. highest-numbered-always-redo: writing iterations 1 then 2 to the same directory
#      makes resume_from_checkpoint report iteration 2 (the highest), never the first.

@testitem "planning checkpoint: round-trip through JLD2" tags = [:planning] setup =
    [Phase8Fixtures] begin
    using TSODSO

    Phase8Fixtures.with_tempdir() do dir
        path = TSODSO.checkpoint_iteration!((; z = [1.0, 2.0], cost = 3.5), 1; dir = dir)
        @test isfile(path)

        resumed = TSODSO.resume_from_checkpoint(dir)
        @test resumed.iteration == 1
        @test resumed.state.z == [1.0, 2.0]
        @test resumed.state.cost == 3.5
    end
end

@testitem "planning checkpoint: highest-numbered checkpoint always redone" tags = [
    :planning,
] setup = [Phase8Fixtures] begin
    using TSODSO

    Phase8Fixtures.with_tempdir() do dir
        TSODSO.checkpoint_iteration!((; z = [1.0], cost = 1.0), 1; dir = dir)
        TSODSO.checkpoint_iteration!((; z = [2.0], cost = 2.0), 2; dir = dir)

        resumed = TSODSO.resume_from_checkpoint(dir)
        @test resumed.iteration == 2   # highest-numbered, never the first/"last complete"
    end

    # An empty directory has no checkpoints to resume from.
    Phase8Fixtures.with_tempdir() do dir
        @test TSODSO.resume_from_checkpoint(dir) === nothing
    end
end
