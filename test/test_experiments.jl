# test/test_experiments.jl
#
# Seam: src/experiments/ — the Phase-8 experiment harness (EXP-01 declarative Scenario +
# swappable solve strategy, EXP-02 parameter sweep + diff-friendly storage, INFRA-04
# provenance + bit-for-bit reproducibility).
#
# RED @testitem harness (Wave 0 of Phase 8). Waves 2-4 (plans 08-02 Scenario/materialize,
# 08-03 run_scenario, 08-04 store/sweep) turn these green by IMPLEMENTING src/experiments/
# {Scenario,materialize,run,store,sweep}.jl — this file is NEVER edited to go green; the
# documented contract below (RESEARCH Patterns 1-3 + the 08-02/03/04 PLAN <verify> commands)
# IS the target API. Every item name is prefixed "EXP-01"/"EXP-02"/"INFRA-04" and contains an
# 08-VALIDATION filter substring (scenario, sweep, provenance/tagsave, repro/bitfor) so
# `occursin(<substring>, ti.name)` selects the right subset per task.
#
# GUARD (a missing symbol must fail cleanly, never crash the runner): every behavioral body
# sits behind an `isdefined(TSODSO, :symbol)` check — mirroring the Phase-6 test_admm.jl
# RED-then-green precedent. While RED the sole failing assertion is the isdefined check
# itself; the behavioral asserts go live automatically once the later wave lands the symbol.
#
# NOTE on the strategy guard: 08-02 validates feeder/strategy/price/population AT Scenario
# CONSTRUCTION (throws ArgumentError before a bad selector can ever reach run_scenario), so
# "EXP-01 scenario strategy guard" below exercises the Scenario-level guard directly; 08-03's
# own terminal `else` in run_scenario is defensive-in-depth and is exercised transitively
# (a Scenario with a bad strategy never constructs, so run_scenario is never reached with one).

@testitem "EXP-01 scenario centralized" setup = [Phase8Fixtures] begin
    using TSODSO

    # RED until plan 08-02 (Scenario) / 08-03 (run_scenario) land.
    @test isdefined(TSODSO, :Scenario)
    @test isdefined(TSODSO, :run_scenario)

    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_scenario)
        kw = Phase8Fixtures.minimal_scenario_kwargs()
        s = TSODSO.Scenario(; kw..., strategy = :centralized)
        r1 = TSODSO.run_scenario(s)
        r2 = TSODSO.run_scenario(s)   # same Scenario, same process

        @test r1.welfare isa Real
        @test r1.dadp isa AbstractMatrix
        @test r1.exact_maxgap isa Real
        @test ismissing(r1.iters)              # centralized has no ADMM iteration count

        # INFRA-04 bit-for-bit: same Scenario+seed -> identical through the full solve
        # (single-thread Clarabel, same process; timings are EXCLUDED, never compared).
        @test r1.welfare == r2.welfare
        @test r1.dadp == r2.dadp
        @test r1.exact_maxgap == r2.exact_maxgap
    end
end

@testitem "EXP-01 scenario admm" setup = [Phase8Fixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :Scenario)
    @test isdefined(TSODSO, :run_scenario)

    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_scenario)
        kw = Phase8Fixtures.minimal_scenario_kwargs()
        s = TSODSO.Scenario(; kw..., strategy = :admm)
        r = TSODSO.run_scenario(s)

        @test r.welfare isa Real
        @test r.dadp isa AbstractMatrix
        @test size(r.dadp, 2) == kw.T           # node×T, matching the :centralized shape
        @test r.iters isa Integer && r.iters >= 1
        @test !ismissing(r.final_r) && !ismissing(r.final_s)
    end
end

@testitem "EXP-01 scenario strategy guard" setup = [Phase8Fixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :Scenario)

    if isdefined(TSODSO, :Scenario)
        kw = Phase8Fixtures.minimal_scenario_kwargs()

        # A Scenario never silently underdetermines a run: every unknown selector throws
        # ArgumentError at construction (RESEARCH Pitfall 1 / 08-02 behavior).
        @test_throws ArgumentError TSODSO.Scenario(; kw..., feeder = :bogus)
        @test_throws ArgumentError TSODSO.Scenario(; kw..., strategy = :bogus)
        @test_throws ArgumentError TSODSO.Scenario(; kw..., price = :bogus)
        @test_throws ArgumentError TSODSO.Scenario(; kw..., population = :bogus)
    end
end

@testitem "EXP-02 sweep" setup = [Phase8Fixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :Scenario)
    @test isdefined(TSODSO, :run_sweep)

    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_sweep)
        Phase8Fixtures.with_tempdir() do dir
            kw = Phase8Fixtures.minimal_scenario_kwargs()
            params = Dict(pairs(kw)..., :seed => collect(1:2))   # Vector -> dict_list expands
            scns = TSODSO.run_sweep(params; dir = dir)

            @test length(scns) == 2
        end
    end
end

@testitem "EXP-02 sweep diff-friendly" setup = [Phase8Fixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :run_sweep)
    @test isdefined(TSODSO, :collate_summary)

    if isdefined(TSODSO, :run_sweep) && isdefined(TSODSO, :collate_summary)
        Phase8Fixtures.with_tempdir() do dir
            kw = Phase8Fixtures.minimal_scenario_kwargs()
            params = Dict(pairs(kw)..., :seed => collect(1:2))
            TSODSO.run_sweep(params; dir = dir)

            Phase8Fixtures.with_tempdir() do outdir
                c1 = joinpath(outdir, "s1.csv")
                c2 = joinpath(outdir, "s2.csv")
                TSODSO.collate_summary(dir, c1)
                TSODSO.collate_summary(dir, c2)

                # Diff-friendly (RESEARCH Pattern 3): fixed column order + deterministic sort
                # + NO absolute :path column -> two collations of the SAME runs are
                # byte-identical (no git churn); :gitcommit is kept.
                @test read(c1, String) == read(c2, String)
                header = first(split(read(c1, String), "\n"))
                @test !occursin("path", header)
            end
        end
    end
end

@testitem "INFRA-04 same-seed repro" setup = [Phase8Fixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :Scenario)
    @test isdefined(TSODSO, :run_scenario)

    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_scenario)
        kw = Phase8Fixtures.minimal_scenario_kwargs()
        s = TSODSO.Scenario(; kw..., strategy = :centralized)
        r1 = TSODSO.run_scenario(s)
        r2 = TSODSO.run_scenario(s)

        @test r1.welfare == r2.welfare
        @test r1.dadp == r2.dadp
        @test r1.exact_maxgap == r2.exact_maxgap
    end
end

@testitem "INFRA-04 seed sensitivity" setup = [Phase8Fixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :Scenario)
    @test isdefined(TSODSO, :run_scenario)

    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_scenario)
        kw = Phase8Fixtures.minimal_scenario_kwargs()
        r1 = TSODSO.run_scenario(TSODSO.Scenario(; kw..., strategy = :centralized, seed = 7))
        r2 = TSODSO.run_scenario(TSODSO.Scenario(; kw..., strategy = :centralized, seed = 8))

        @test r1.dadp != r2.dadp   # a DIFFERENT seed must change the profile-driven result
    end
end

@testitem "INFRA-04 provenance tagsave" setup = [Phase8Fixtures] begin
    using TSODSO
    using DrWatson: wload, savename

    @test isdefined(TSODSO, :Scenario)
    @test isdefined(TSODSO, :run_and_store)

    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_and_store)
        Phase8Fixtures.with_tempdir() do dir
            kw = Phase8Fixtures.minimal_scenario_kwargs()
            s = TSODSO.Scenario(; kw..., strategy = :centralized)
            TSODSO.run_and_store(s; dir = dir)

            f = joinpath(dir, savename(s, "jld2"))
            @test isfile(f)

            # NOTE (Rule 1 fix, 08-04): `wload` on a `.jld2` always round-trips through
            # JLD2's generic `FileIO.save`/`load`, which stores every dict key as a JLD2
            # variable NAME (a `String`) regardless of the in-memory key type passed to
            # `@tagsave` — verified live against DrWatson 2.19.1 / JLD2 0.6.5: a
            # `Dict{Symbol,Any}` tagsaved and reloaded comes back `Dict{String,Any}` with
            # string keys ("gitcommit", "julia_version", "seed"), never `Symbol` keys. The
            # original `haskey(dict, :gitcommit)`-style (Symbol) assertions here could never
            # pass against any real `wload` result. Assert String keys instead — the
            # provenance intent (gitcommit + julia_version + seed survive the tagsave/wload
            # round-trip) is unchanged.
            dict = wload(f)
            @test haskey(dict, "gitcommit")
            @test haskey(dict, "julia_version")
            @test dict["julia_version"] == string(VERSION)
            @test haskey(dict, "seed")
        end
    end
end
