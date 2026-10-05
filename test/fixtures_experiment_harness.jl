# test/fixtures_phase8.jl
#
# Shared Phase-8 (experiment harness & reproducibility) test fixture module (Wave 0). A
# TestItems `@testmodule` that the Phase-8 `@testitem`s consume via `setup=[Phase8Fixtures]`.
# Provides a minimal declarative Scenario-construction kwarg set (feeder = :ieee13, T = 24)
# and a `with_tempdir` helper wrapping `mktempdir` for hermetic storage/sweep tests (RESEARCH
# Pitfall 6).
#
# CONTRACT (mirrors the Phase6/7Fixtures "defines-only" discipline, threat T-06-01 lineage):
# this module DEFINES functions ONLY — it makes NO top-level call to `Scenario(...)` (the
# struct doesn't exist until plan 08-02 fills src/experiments/Scenario.jl). Returning a plain
# NamedTuple of primitive selector kwargs (not a constructed Scenario) keeps this module
# load-safe while RED — every @testitem splats it into `TSODSO.Scenario(; kw...)` once the
# struct exists, so a partial-wave state can never corrupt test discovery.
#
# WHY T=24 (not a shorter "small" horizon): every seeded profile/device fixture this harness
# orchestrates (temperature_profile, generate_profiles, the thesis MEM price shapes — RESEARCH
# §Pattern 1 / fixtures_phase4/7) is pinned to the 24-hour day-ahead horizon (thesis A1); a
# shorter T would silently truncate those fixed-length daily arrays. T=24 IS the minimal
# granularity this framework supports end-to-end, so it doubles as the "small T" a minimal
# fixture wants.

@testmodule Phase8Fixtures begin
    """
        minimal_scenario_kwargs() -> NamedTuple

    A minimal set of primitive Scenario selectors (RESEARCH §Pattern 1 defaults): the modified
    IEEE-13 feeder, the centralized strategy, seed 7, and the standard T=24 day-ahead horizon.
    Every @testitem splats this (overriding `strategy`/`seed` as needed) into
    `TSODSO.Scenario(; kw...)` — kept as a NamedTuple (not a constructed Scenario) so this
    module loads safely before Scenario exists (RED-compatible, Wave 0).
    """
    function minimal_scenario_kwargs()
        return (
            name = "phase8-fixture",
            feeder = :ieee13,
            strategy = :centralized,
            seed = 7,
            T = 24,
        )
    end

    """
        with_tempdir(f)

    Run `f(dir)` inside a fresh `mktempdir()`, auto-cleaned on exit — the hermetic storage-dir
    helper every Phase-8 storage/sweep test uses so runs never litter `test/` or the repo's own
    `data/`/`results/` (RESEARCH Pitfall 6: storage functions take an explicit `dir` keyword;
    tests must never rely on `datadir()` resolving under the test environment).
    """
    function with_tempdir(f)
        return mktempdir() do dir
            f(dir)
        end
    end

    export minimal_scenario_kwargs, with_tempdir
end
