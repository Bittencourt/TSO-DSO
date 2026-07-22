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

@testitem "planning checkpoint: iter outside 0:99999 raises ArgumentError (WR-03 filename contract)" tags = [
    :planning,
] setup = [Phase8Fixtures] begin
    using TSODSO

    Phase8Fixtures.with_tempdir() do dir
        # Negative: lpad(-3, 5, '0') pads the STRING "-3" into a malformed, nonsensically
        # sorting name. Over the width: iter_100000.jld2 sorts lexicographically BEFORE
        # iter_99999.jld2, silently resuming the wrong (lower) iteration.
        @test_throws ArgumentError TSODSO.checkpoint_iteration!((; z = [1.0]), -3; dir = dir)
        @test_throws ArgumentError TSODSO.checkpoint_iteration!((; z = [1.0]), 100000; dir = dir)

        # The boundary values themselves are valid.
        TSODSO.checkpoint_iteration!((; z = [0.0]), 0; dir = dir)
        TSODSO.checkpoint_iteration!((; z = [1.0]), 99999; dir = dir)
        resumed = TSODSO.resume_from_checkpoint(dir)
        @test resumed.iteration == 99999
    end
end

@testitem "planning checkpoint: re-saving the same iteration resumes the FRESH state, never the safesave backup (CR-02)" tags = [
    :planning,
] setup = [Phase8Fixtures] begin
    using TSODSO

    # The exact crash-redo workflow this primitive exists for: crash during iteration 2,
    # resume, REDO iteration 2, checkpoint it again. `safe = true` routes through
    # DrWatson's safesave: the FIRST save is renamed to iter_00002_#1.jld2 and the NEW
    # state is written to the canonical iter_00002.jld2. Because '_' (0x5F) sorts after
    # '.' (0x2E), a naive all-.jld2 lexicographic sort put the STALE backup last — the
    # second resume then silently loaded the pre-redo state while reporting the correct
    # iteration number.
    Phase8Fixtures.with_tempdir() do dir
        TSODSO.checkpoint_iteration!((; z = [1.0], cost = 1.0), 2; dir = dir)
        TSODSO.checkpoint_iteration!((; z = [9.0], cost = 9.0), 2; dir = dir)

        # safesave preserved the first save as a backup (T-10-02: never silently
        # overwrite) ...
        @test isfile(joinpath(dir, "iter_00002_#1.jld2"))

        # ... but resume must return the SECOND (fresh) state from the canonical file.
        resumed = TSODSO.resume_from_checkpoint(dir)
        @test resumed.iteration == 2
        @test resumed.state.z == [9.0]
        @test resumed.state.cost == 9.0
    end

    # Three saves of the same iteration: _#2 (the OLDEST state) sorts after _#1 — the
    # canonical file must still win.
    Phase8Fixtures.with_tempdir() do dir
        TSODSO.checkpoint_iteration!((; z = [1.0], cost = 1.0), 3; dir = dir)
        TSODSO.checkpoint_iteration!((; z = [2.0], cost = 2.0), 3; dir = dir)
        TSODSO.checkpoint_iteration!((; z = [3.0], cost = 3.0), 3; dir = dir)

        resumed = TSODSO.resume_from_checkpoint(dir)
        @test resumed.state.z == [3.0]
        @test resumed.state.cost == 3.0
    end

    # A foreign .jld2 file that sorts last must be IGNORED (previously it was wloaded and
    # raised KeyError("iteration") — an undiagnosable crash instead of a resume).
    Phase8Fixtures.with_tempdir() do dir
        TSODSO.checkpoint_iteration!((; z = [1.0], cost = 1.0), 1; dir = dir)
        touch(joinpath(dir, "zzz_foreign.jld2"))

        resumed = TSODSO.resume_from_checkpoint(dir)
        @test resumed.iteration == 1
        @test resumed.state.z == [1.0]
    end
end
