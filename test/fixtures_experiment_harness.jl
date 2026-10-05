# test/fixtures_experiment_harness.jl
#
# Shared test fixture module for the experiment harness & reproducibility tests. A
# TestItems `@testmodule` that the experiment-harness `@testitem`s consume via `setup=[ExperimentHarnessFixtures]`.
# Provides a minimal declarative Scenario-construction kwarg set (feeder = :ieee13, T = 24)
# and a `with_tempdir` helper wrapping `mktempdir` for hermetic storage/sweep tests (storage
# functions take an explicit `dir`, see `with_tempdir`).
#
# CONTRACT (mirrors the other fixture modules' "defines-only" discipline):
# this module DEFINES functions ONLY — it makes NO top-level call to `Scenario(...)` (the
# struct is defined in src/experiments/Scenario.jl). Returning a plain
# NamedTuple of primitive selector kwargs (not a constructed Scenario) keeps this module
# load-safe before it exists — every @testitem splats it into `TSODSO.Scenario(; kw...)` once the
# struct exists, so a partially-implemented state can never corrupt test discovery.
#
# WHY T=24 (not a shorter "small" horizon): every seeded profile/device fixture this harness
# orchestrates (temperature_profile, generate_profiles, the thesis MEM price shapes;
# fixtures_ieee13/7) is pinned to the 24-hour day-ahead horizon (thesis A1); a
# shorter T would silently truncate those fixed-length daily arrays. T=24 IS the minimal
# granularity this framework supports end-to-end, so it doubles as the "small T" a minimal
# fixture wants.

@testmodule ExperimentHarnessFixtures begin
    """
        minimal_scenario_kwargs() -> NamedTuple

    A minimal set of primitive Scenario selectors (the defaults): the modified
    IEEE-13 feeder, the centralized strategy, seed 7, and the standard T=24 day-ahead horizon.
    Every @testitem splats this (overriding `strategy`/`seed` as needed) into
    `TSODSO.Scenario(; kw...)` — kept as a NamedTuple (not a constructed Scenario) so this
    module loads safely before Scenario exists.
    """
    function minimal_scenario_kwargs()
        return (
            name = "harness-fixture",
            feeder = :ieee13,
            strategy = :centralized,
            seed = 7,
            T = 24,
        )
    end

    """
        with_tempdir(f)

    Run `f(dir)` inside a fresh `mktempdir()`, auto-cleaned on exit — the hermetic storage-dir
    helper every experiment-harness storage/sweep test uses so runs never litter `test/` or the repo's own
    `data/`/`results/` (storage functions take an explicit `dir` keyword;
    tests must never rely on `datadir()` resolving under the test environment).
    """
    function with_tempdir(f)
        return mktempdir() do dir
            f(dir)
        end
    end

    export minimal_scenario_kwargs, with_tempdir
end
