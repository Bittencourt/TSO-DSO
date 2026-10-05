# test/test_experiments.jl
#
# Seam: src/experiments/ — the experiment harness (declarative Scenario +
# swappable solve strategy, parameter sweep + diff-friendly storage, provenance +
# bit-for-bit reproducibility).
#
# The documented contract below is the target API of src/experiments/
# {Scenario,materialize,run,store,sweep}.jl. Every item name is prefixed "experiments:"
# and contains a filter substring (scenario, sweep, provenance/tagsave, repro/bitfor) so
# `occursin(<substring>, ti.name)` selects the right subset.
#
# GUARD (a missing symbol must fail cleanly, never crash the runner): every behavioral body
# sits behind an `isdefined(TSODSO, :symbol)` check, mirroring the test_admm.jl
# precedent. If a symbol is missing the sole failing assertion is the isdefined check
# itself; the behavioral asserts go live automatically once the symbol exists.
#
# NOTE on the strategy guard: Scenario validates feeder/strategy/price/population AT Scenario
# CONSTRUCTION (throws ArgumentError before a bad selector can ever reach run_scenario), so
# "experiments: scenario strategy guard" below exercises the Scenario-level guard directly; the
# terminal `else` in run_scenario is defensive-in-depth and is exercised transitively
# (a Scenario with a bad strategy never constructs, so run_scenario is never reached with one).

@testitem "experiments: scenario centralized" setup = [ExperimentHarnessFixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :Scenario)
    @test isdefined(TSODSO, :run_scenario)

    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_scenario)
        kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
        s = TSODSO.Scenario(; kw..., strategy = :centralized)
        r1 = TSODSO.run_scenario(s)
        r2 = TSODSO.run_scenario(s)   # same Scenario, same process

        @test r1.welfare isa Real
        @test r1.dadp isa AbstractMatrix
        @test r1.exact_maxgap isa Real
        @test ismissing(r1.iters)              # centralized has no ADMM iteration count

        # :centralized has no ADMM reactive-consensus
        # concept, so the provenance field must stay `missing` here (regression guard for
        # src/experiments/run.jl's `reactive_consensus_mode = missing` centralized branch).
        @test ismissing(r1.reactive_consensus_mode)

        # Bit-for-bit: same Scenario+seed -> identical through the full solve
        # (single-thread Clarabel, same process; timings are EXCLUDED, never compared).
        @test r1.welfare == r2.welfare
        @test r1.dadp == r2.dadp
        @test r1.exact_maxgap == r2.exact_maxgap
    end
end

@testitem "experiments: scenario admm" setup = [ExperimentHarnessFixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :Scenario)
    @test isdefined(TSODSO, :run_scenario)

    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_scenario)
        kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
        s = TSODSO.Scenario(; kw..., strategy = :admm)
        r = TSODSO.run_scenario(s)

        @test r.welfare isa Real
        @test r.dadp isa AbstractMatrix
        @test size(r.dadp, 2) == kw.T           # node×T, matching the :centralized shape
        @test r.iters isa Integer && r.iters >= 1
        @test !ismissing(r.final_r) && !ismissing(r.final_s)

        # The provenance field threads solve_admm's RESOLVED
        # reactive_consensus mode out to ScenarioResult; guard that it stays populated (not
        # `missing`, not silently dropped/renamed by a future refactor of solve_admm's return
        # tuple or ScenarioResult's field list).
        @test r.reactive_consensus_mode isa TSODSO.ReactiveMode.T
    end
end

@testitem "experiments: scenario strategy guard" setup = [ExperimentHarnessFixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :Scenario)

    if isdefined(TSODSO, :Scenario)
        kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()

        # A Scenario never silently underdetermines a run: every unknown selector throws
        # ArgumentError at construction.
        @test_throws ArgumentError TSODSO.Scenario(; kw..., feeder = :bogus)
        @test_throws ArgumentError TSODSO.Scenario(; kw..., strategy = :bogus)
        @test_throws ArgumentError TSODSO.Scenario(; kw..., price = :bogus)
        @test_throws ArgumentError TSODSO.Scenario(; kw..., population = :bogus)
    end
end

@testitem "experiments: sweep" setup = [ExperimentHarnessFixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :Scenario)
    @test isdefined(TSODSO, :run_sweep)

    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_sweep)
        ExperimentHarnessFixtures.with_tempdir() do dir
            kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
            params = Dict(pairs(kw)..., :seed => collect(1:2))   # Vector -> dict_list expands
            scns = TSODSO.run_sweep(params; dir = dir)

            @test length(scns) == 2
        end
    end
end

@testitem "experiments: sweep diff-friendly" setup = [ExperimentHarnessFixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :run_sweep)
    @test isdefined(TSODSO, :collate_summary)

    if isdefined(TSODSO, :run_sweep) && isdefined(TSODSO, :collate_summary)
        ExperimentHarnessFixtures.with_tempdir() do dir
            kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
            params = Dict(pairs(kw)..., :seed => collect(1:2))
            TSODSO.run_sweep(params; dir = dir)

            ExperimentHarnessFixtures.with_tempdir() do outdir
                c1 = joinpath(outdir, "s1.csv")
                c2 = joinpath(outdir, "s2.csv")
                TSODSO.collate_summary(dir, c1)
                TSODSO.collate_summary(dir, c2)

                # Diff-friendly: fixed column order + deterministic sort
                # + NO absolute :path column -> two collations of the SAME runs are
                # bit-for-bit identical (no git churn); :gitcommit is kept.
                @test read(c1, String) == read(c2, String)
                header = first(split(read(c1, String), "\n"))
                @test !occursin("path", header)
            end
        end
    end
end

@testitem "experiments: same-seed repro" setup = [ExperimentHarnessFixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :Scenario)
    @test isdefined(TSODSO, :run_scenario)

    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_scenario)
        kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
        s = TSODSO.Scenario(; kw..., strategy = :centralized)
        r1 = TSODSO.run_scenario(s)
        r2 = TSODSO.run_scenario(s)

        @test r1.welfare == r2.welfare
        @test r1.dadp == r2.dadp
        @test r1.exact_maxgap == r2.exact_maxgap
    end
end

@testitem "experiments: seed sensitivity" setup = [ExperimentHarnessFixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :Scenario)
    @test isdefined(TSODSO, :run_scenario)

    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_scenario)
        kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
        r1 =
            TSODSO.run_scenario(TSODSO.Scenario(; kw..., strategy = :centralized, seed = 7))
        r2 =
            TSODSO.run_scenario(TSODSO.Scenario(; kw..., strategy = :centralized, seed = 8))

        @test r1.dadp != r2.dadp   # a DIFFERENT seed must change the profile-driven result
    end
end

# The same-seed/seed-sensitivity gates above only ever exercised the
# :centralized strategy; :admm is the iterative, floating-point-order-sensitive path
# (adaptive-ρ residual comparisons, iteration-count-dependent convergence checks) and is
# exactly where non-determinism is most likely to leak in. run.jl's own docstring asserts
# bit-for-bit identity holds for :admm too, but nothing verified it. Mirror both gates here.
@testitem "experiments: same-seed repro admm" setup = [ExperimentHarnessFixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :Scenario)
    @test isdefined(TSODSO, :run_scenario)

    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_scenario)
        kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
        s = TSODSO.Scenario(; kw..., strategy = :admm)
        r1 = TSODSO.run_scenario(s)
        r2 = TSODSO.run_scenario(s)

        @test r1.welfare == r2.welfare
        @test r1.dadp == r2.dadp
        @test r1.exact_maxgap == r2.exact_maxgap
        @test r1.iters == r2.iters
        @test r1.final_r == r2.final_r
        @test r1.final_s == r2.final_s
    end
end

@testitem "experiments: seed sensitivity admm" setup = [ExperimentHarnessFixtures] begin
    using TSODSO

    @test isdefined(TSODSO, :Scenario)
    @test isdefined(TSODSO, :run_scenario)

    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_scenario)
        kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
        r1 = TSODSO.run_scenario(TSODSO.Scenario(; kw..., strategy = :admm, seed = 7))
        r2 = TSODSO.run_scenario(TSODSO.Scenario(; kw..., strategy = :admm, seed = 8))

        @test r1.dadp != r2.dadp   # a DIFFERENT seed must change the profile-driven result
    end
end

@testitem "experiments: Scenario copies stoch_probabilities — caller mutation cannot bypass validation" begin
    using TSODSO

    # The inner constructor validated stoch_probabilities then passed the SAME
    # array to new(...) — an aliasing hole through which a caller could mutate the
    # validated vector after construction (p[1] = 99.0 ⇒ sum 99.8, every invariant
    # silently gone while savename/hash/reproducibility stay keyed to the stale check).
    # The fix copies on construction; this item pins it.
    p = [0.2, 0.3, 0.5]
    s = Scenario(name = "wr01-alias", strategy = Stochastic(probabilities = p))   # S defaults to 3
    p[1] = 99.0
    @test s.strategy.probabilities == [0.2, 0.3, 0.5]
    @test isapprox(sum(s.strategy.probabilities), 1; atol = 1e-8)
    @test s.strategy.probabilities !== p
end

@testitem "experiments: scenario_filename identifies the probability vector" begin
    using TSODSO

    # stoch_probabilities::Vector{Float64} is outside DrWatson's default_allowed
    # filter and is silently DROPPED from the bare savename, so two Scenarios differing
    # ONLY in their weighting (the uniform-vs-non-uniform comparison)
    # previously rendered the IDENTICAL filename. scenario_filename now folds a stable
    # digest of a NON-uniform vector into the name; the uniform case stays bit-for-bit identical
    # to the pre-fix name (uniform is fully determined by the stoch_S field the name
    # already carries).
    s_uniform = Scenario(name = "wr02", strategy = Stochastic())             # default uniform
    s_uniform_explicit = Scenario(name = "wr02", strategy = Stochastic(probabilities = fill(1 / 3, 3)))
    s_a = Scenario(name = "wr02", strategy = Stochastic(probabilities = [0.2, 0.3, 0.5]))
    s_b = Scenario(name = "wr02", strategy = Stochastic(probabilities = [0.5, 0.3, 0.2]))

    fu = TSODSO.scenario_filename(s_uniform)
    fa = TSODSO.scenario_filename(s_a)
    fb = TSODSO.scenario_filename(s_b)

    # Non-uniform vectors resolve to filenames DISTINCT from uniform and from each other
    # (same multiset of probabilities, different order ⇒ different draws-to-weights map).
    @test fa != fu
    @test fb != fu
    @test fa != fb

    # An explicitly-passed uniform vector is the SAME Scenario as the default sentinel
    # resolution — identical filename, no spurious digest churn.
    @test TSODSO.scenario_filename(s_uniform_explicit) == fu

    # Determinism + the NAME_MAX guard still holds AFTER the digest is folded in.
    @test TSODSO.scenario_filename(s_a) == fa
    for f in (fu, fa, fb)
        @test sizeof(f) <= 255
        @test endswith(f, ".jld2")
    end
end

@testitem "experiments: provenance tagsave" setup = [ExperimentHarnessFixtures] begin
    using TSODSO
    using DrWatson: wload

    @test isdefined(TSODSO, :Scenario)
    @test isdefined(TSODSO, :run_and_store)

    if isdefined(TSODSO, :Scenario) && isdefined(TSODSO, :run_and_store)
        ExperimentHarnessFixtures.with_tempdir() do dir
            kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
            s = TSODSO.Scenario(; kw..., strategy = :centralized)
            TSODSO.run_and_store(s; dir = dir)

            # `run_and_store` saves under `TSODSO.scenario_filename(s)`
            # (lossless float formatting, avoids DrWatson's lossy default sigdigits=3
            # rounding colliding two distinguishable ADMM-knob Scenarios onto one filename).
            #
            # This item must not re-derive `savename(s, "jld2"; digits = 10)` directly
            # instead of calling `scenario_filename` — EXACTLY the "second,
            # independently-maintained call site" `scenario_filename`'s own docstring warns
            # is how divergence happens: once `scenario_filename` grew its
            # own NAME_MAX-safety fallback, a re-derived
            # bare `savename` string no longer matched the ACTUAL
            # filename `run_and_store` used, throwing `ENAMETOOLONG`. Calling the single source of truth
            # directly (as `run_and_store` itself does) fixes it for good.
            f = joinpath(dir, TSODSO.scenario_filename(s))
            @test isfile(f)

            # NOTE: `wload` on a `.jld2` always round-trips through
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

@testitem "experiments: filename identity" begin
    using TSODSO

    base = (name = "id", seed = 1, T = 24)
    four = [
        Scenario(; base..., strategy = Centralized()),
        Scenario(; base..., strategy = ADMM(ρ = 50.0)),
        Scenario(; base..., strategy = MPC()),
        Scenario(; base..., strategy = Stochastic()),
    ]
    names = TSODSO.scenario_filename.(four)
    @test allunique(names)
    @test occursin("strategy=ADMM", names[2])
    @test occursin("admm_ρ=", names[2])
    @test !any(occursin(r"admm_|mpc_|stoch_", names[1]))
    @test all(f -> sizeof(f) <= 255, names)

    function variants()
        v = Scenario[Scenario(; base...)]
        push!(v, Scenario(; base..., name = "id2"))
        push!(v, Scenario(; base..., seed = 2))
        push!(v, Scenario(; base..., T = 48))
        push!(v, Scenario(; base..., allow_export = false))
        push!(v, Scenario(; base..., pf = :lindistflow))
        push!(v, Scenario(; base..., pf_thesis_literal = true))
        push!(v, Scenario(; base..., pf = :restricted_branch_flow, pf_ε = 1e-3))
        push!(v, Scenario(; base..., pf = :restricted_branch_flow, pf_ε = 2e-3))
        for kw in (
            (ρ = 7.0,), (ε_abs = 2e-4,), (ε_rel = 2e-3,), (maxiter = 150,), (τ_ratio = 3.0,), (μ = 5.0,),
        )
            push!(v, Scenario(; base..., strategy = ADMM(; kw...)))
        end
        push!(v, Scenario(; base..., strategy = ADMM()))
        for kw in (
            (H = 8,), (step = 2,), (terminal_soc = false,), (forecast_error = 0.1,),
        )
            push!(v, Scenario(; base..., strategy = MPC(; kw...)))
        end
        push!(v, Scenario(; base..., strategy = MPC()))
        push!(v, Scenario(; base..., strategy = Stochastic(S = 4)))
        push!(v, Scenario(; base..., strategy = Stochastic(H_oos = 6)))
        push!(v, Scenario(; base..., strategy = Stochastic(probabilities = [0.2, 0.3, 0.5])))
        return v
    end
    vs = variants()
    fs = TSODSO.scenario_filename.(vs)
    @test allunique(fs)
    @test fs == TSODSO.scenario_filename.(variants())   # deterministic
    @test all(f -> sizeof(f) <= 255, fs)

    f_u = TSODSO.scenario_filename(Scenario(; base..., strategy = Stochastic()))
    f_n = TSODSO.scenario_filename(Scenario(; base..., strategy = Stochastic(probabilities = [0.2, 0.3, 0.5])))
    @test !occursin("_p", replace(f_u, "_population" => "", "_price" => "", "_pf" => ""))
    @test occursin(r"_p[0-9a-f]{16}\.jld2$", f_n)
end

@testitem "experiments: result_to_dict flat primitives" setup = [ExperimentHarnessFixtures] begin
    using TSODSO

    kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
    rc = TSODSO.run_scenario(TSODSO.Scenario(; kw..., strategy = :centralized))
    d = TSODSO.result_to_dict(rc)
    @test d[:strategy] == :centralized
    @test d[:pf] == :convex_branch_flow
    @test ismissing(d[:iters])
    @test !haskey(d, :ρ)
    @test all(v -> !(v isa TSODSO.AbstractStrategy), values(d))

    ra = TSODSO.run_scenario(TSODSO.Scenario(; kw..., strategy = :admm))
    da = TSODSO.result_to_dict(ra)
    @test da[:strategy] == :admm
    @test haskey(da, :ρ)
    @test da[:iters] isa Int
    @test all(v -> !(v isa TSODSO.AbstractStrategy), values(da))
end

@testitem "experiments: run_and_store round-trip" setup = [ExperimentHarnessFixtures] begin
    using TSODSO
    using DrWatson: wload

    function roundtrip(dir, strat)
        kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
        s = TSODSO.Scenario(; kw..., strategy = strat)
        TSODSO.run_and_store(s; dir = dir)
        return wload(joinpath(dir, TSODSO.scenario_filename(s)))
    end

    ExperimentHarnessFixtures.with_tempdir() do dir
        for (strat, lab) in ((:centralized, :centralized), (:admm, :admm))
            dict = roundtrip(dir, strat)
            for k in ("strategy", "pf", "welfare", "gitcommit", "julia_version")
                @test haskey(dict, k)
            end
            @test dict["strategy"] == lab
        end
    end
end

@testitem "experiments: mixed-strategy sweep collate" setup = [ExperimentHarnessFixtures] begin
    using TSODSO
    using DataFrames: DataFrame, nrow
    using CSV: CSV

    ExperimentHarnessFixtures.with_tempdir() do dir
        params = Dict(
            :name => "mix", :feeder => :ieee13, :strategy => [:centralized, :admm],
            :seed => 1, :T => 24,
        )
        TSODSO.run_sweep(params; dir = dir)
        ExperimentHarnessFixtures.with_tempdir() do outdir
            c1 = joinpath(outdir, "a.csv")
            c2 = joinpath(outdir, "b.csv")
            df = TSODSO.collate_summary(dir, c1)
            TSODSO.collate_summary(dir, c2)
            @test read(c1, String) == read(c2, String)
            @test nrow(df) == 2
            @test "pf" in names(df)
            @test !("path" in names(df))
            cen = df[df.strategy .== :centralized, :]
            @test all(ismissing, cen.ρ)
        end
    end
end

@testitem "experiments: over-length filename fallback uses the stable FNV digest" begin
    using TSODSO, Test
    s = Scenario(name = "w5-" * repeat("x", 400), feeder = :ieee13)
    f = TSODSO.scenario_filename(s)
    @test sizeof(f) <= 245
    m = match(r"_h([0-9a-f]{16})\.jld2$", f)
    @test m !== nothing
    @test f == TSODSO.scenario_filename(s)
end
