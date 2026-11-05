# test/test_ieee8500_scenario.jl
#
# Seam: src/experiments/Scenario.jl (the widened feeder selector tuple, the `:default_10pct`
# population selector and the construction guards for the IEEE-8500 family) and
# src/experiments/materialize.jl (the `:default_10pct` branch of the population builder).
#
# Every item name contains "ieee8500 scenario" so a substring selector picks them up.
#
# COST RULE: nothing in this file solves an IEEE-8500 point. Items construct a `Scenario`, or
# materialize an IEEE-8500 population (about 3 s each), and nothing more.
#
# SOFT-SCOPE RULE: accumulators live inside functions / `let` blocks, never bare in a top-level
# `for` of a @testitem body.

@testitem "ieee8500 scenario: widened feeder selector constructs" begin
    using TSODSO

    @test TSODSO.SCENARIO_VALID_FEEDERS == (:ieee13, :ieee123, :ieee8500, :ieee8500_mv)

    s85 = Scenario(; name = "x", feeder = :ieee8500)
    @test s85.feeder === :ieee8500
    @test s85.population === :default
    @test s85.strategy == Centralized()

    s85mv = Scenario(; name = "x", feeder = :ieee8500_mv, strategy = ADMM())
    @test s85mv.feeder === :ieee8500_mv
    @test s85mv.strategy isa ADMM

    # The default Scenario is unchanged by the widening.
    s13 = Scenario(; name = "x")
    @test s13.feeder === :ieee13
    @test s13.seed == 1
    @test s13.T == 24
    @test s13.population === :default
    @test s13.price === :mem
    @test s13.allow_export
    @test s13.pf === :convex_branch_flow
    @test !s13.pf_thesis_literal
    @test s13.pf_ε == 0.0
    @test s13.strategy == Centralized()

    # Unknown feeders still fail loudly.
    @test_throws ArgumentError Scenario(; name = "x", feeder = :bogus)
    @test_throws ArgumentError Scenario(; name = "x", feeder = :ieee14)
end

@testitem "ieee8500 scenario: construction guards for unsupported combinations" begin
    using TSODSO
    using TSODSO: build_feeder, build_population, generate_profiles

    # The message of every new guard starts with "Scenario: " like its neighbours.
    function guard_message(kw)
        err = try
            Scenario(; name = "x", kw...)
            nothing
        catch e
            e
        end
        return err
    end
    # `needle` pins the specific guard (not the generic "unknown selector" message).
    function check_guard(kw, needle)
        err = guard_message(kw)
        @test err isa ArgumentError
        msg = err isa ArgumentError ? err.msg : ""
        @test startswith(msg, "Scenario: ")
        @test occursin(needle, msg)
        @test !occursin("unknown", msg)
        return nothing
    end

    @test TSODSO.SCENARIO_VALID_POPULATIONS == (:default, :case_a_784, :default_10pct)

    # :default_10pct is defined on the two IEEE-8500 feeders only.
    check_guard((feeder = :ieee13, population = :default_10pct), ":default_10pct")
    check_guard((feeder = :ieee123, population = :default_10pct), ":default_10pct")
    # :case_a_784 is an IEEE-13 population: rejected at construction on the 8500 family.
    check_guard((feeder = :ieee8500, population = :case_a_784), ":case_a_784")
    check_guard((feeder = :ieee8500_mv, population = :case_a_784), ":case_a_784")
    # Never measured at IEEE-8500 scale: AC power flow, MPC and Stochastic strategies.
    check_guard((feeder = :ieee8500, pf = :ac), "pf = :ac")
    check_guard((feeder = :ieee8500_mv, pf = :ac), "pf = :ac")
    check_guard((feeder = :ieee8500, strategy = MPC()), "MPC")
    check_guard((feeder = :ieee8500_mv, strategy = MPC()), "MPC")
    check_guard((feeder = :ieee8500, strategy = Stochastic()), "Stochastic")
    check_guard((feeder = :ieee8500_mv, strategy = Stochastic()), "Stochastic")

    # Still allowed: the density-1.0 default population on 8500, and the legacy
    # :ieee123 + :case_a_784 construction (which fails only at materialization, as before).
    s = Scenario(; name = "x", feeder = :ieee8500, population = :default, strategy = ADMM())
    @test s.population === :default
    @test Scenario(; name = "x", feeder = :ieee123, population = :case_a_784).population ===
          :case_a_784
    s10 = Scenario(;
        name = "x",
        feeder = :ieee8500,
        population = :default_10pct,
        strategy = ADMM(),
        T = 10,
    )
    @test s10.population === :default_10pct
    @test Scenario(; name = "x", feeder = :ieee8500, pf = :lindistflow).pf === :lindistflow

    # The builder itself rejects :default_10pct off the 8500 family.
    feeder13 = build_feeder(:ieee13)
    profiles = generate_profiles(; seed = 1, T = 10)
    @test_throws ArgumentError build_population(
        :default_10pct,
        feeder13,
        :ieee13,
        profiles,
        1,
    )
    # The unknown-selector message names all three selectors.
    err = try
        build_population(:bogus, feeder13, :ieee13, profiles, 1)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    msg = err isa ArgumentError ? err.msg : ""
    @test occursin(":default", msg)
    @test occursin(":default_10pct", msg)
    @test occursin(":case_a_784", msg)
end

@testitem "ieee8500 scenario: :default_10pct materializes 122 and 118 aggregators" begin
    using TSODSO

    is_cap(a) = any(d -> d isa TSODSO.FixedCapacitor, a.devices)
    scen(feeder, seed) = Scenario(;
        name = "x",
        feeder = feeder,
        population = :default_10pct,
        strategy = ADMM(),
        T = 10,
        seed = seed,
    )
    buses_of(aggs) = [a.bus for a in aggs]
    pdc_of(aggs) = [a.Pdc for a in aggs]

    # Full MV + LV feeder: 118 sampled houses + the 4 capacitor aggregators.
    feeder, λ₀, aggs = TSODSO._materialize(scen(:ieee8500, 1))
    @test length(feeder.buses) == 4866
    @test length(feeder.branches) == 4865
    @test length(λ₀) == 10
    @test length(aggs) == 122
    @test count(is_cap, aggs) == 4
    @test all(a -> is_cap(a) || length(a.devices) == 3, aggs)
    @test all(a -> length(a.Pdc) == 10, aggs)
    house_buses = [a.bus for a in aggs if !is_cap(a)]
    @test allunique(house_buses)
    @test issubset(house_buses, TSODSO.ieee8500_load_nodes())

    # Deterministic: an equal Scenario gives the same buses and the same Pdc.
    _, _, aggs_again = TSODSO._materialize(scen(:ieee8500, 1))
    @test buses_of(aggs_again) == buses_of(aggs)
    @test pdc_of(aggs_again) == pdc_of(aggs)

    # A different master seed changes the bus sample (same size).
    _, _, aggs_seed2 = TSODSO._materialize(scen(:ieee8500, 2))
    @test length(aggs_seed2) == 122
    @test count(is_cap, aggs_seed2) == 4
    @test Set(buses_of(aggs_seed2)) != Set(buses_of(aggs))

    # MV-only reduction: 114 sampled houses + the 4 capacitor aggregators.
    feeder_mv, _, aggs_mv = TSODSO._materialize(scen(:ieee8500_mv, 1))
    @test length(feeder_mv.buses) == 2512
    @test length(aggs_mv) == 118
    @test count(is_cap, aggs_mv) == 4
    @test issubset([a.bus for a in aggs_mv if !is_cap(a)], TSODSO.ieee8500_mv_load_buses())
end

@testitem "ieee8500 scenario: :default_10pct equals the harness density rule at an equal seed" begin
    using TSODSO
    using TSODSO: build_feeder, build_population, generate_profiles
    using StableRNGs

    # The harness rule, copied inline from scripts/benchmark_ieee8500.jl
    # (`sample_density_buses` + `density_filtered_population`); the script is not included.
    function harness_sample(rng, buses::Vector{Int}, density::Real)
        density >= 1.0 && return sort(buses)
        n = clamp(round(Int, density * length(buses)), 1, length(buses))
        perm = StableRNGs.Random.randperm(rng, length(buses))
        return sort(buses[perm[1:n]])
    end
    function harness_population(feeder, feeder_sym, profiles, seed, density, rng)
        buses = TSODSO._load_buses(feeder, feeder_sym)
        sampled = Set(harness_sample(rng, buses, density))
        full = build_population(:default, feeder, feeder_sym, profiles, seed)
        return filter(
            agg ->
                agg.bus in sampled || any(dv -> dv isa TSODSO.FixedCapacitor, agg.devices),
            full,
        )
    end

    S = 20260821   # the harness's literal sweep seed
    feeder = build_feeder(:ieee8500)
    profiles = generate_profiles(; seed = 1, T = 10)
    sel = build_population(:default_10pct, feeder, :ieee8500, profiles, S)
    ref = harness_population(feeder, :ieee8500, profiles, S, 0.1, StableRNGs.LehmerRNG(S))
    @test length(sel) == length(ref) == 122
    @test [a.bus for a in sel] == [a.bus for a in ref]
    @test [a.Pdc for a in sel] == [a.Pdc for a in ref]
    @test [length(a.devices) for a in sel] == [length(a.devices) for a in ref]
end

@testitem "ieee8500 scenario: default population fence on ieee13 and ieee123" begin
    using TSODSO
    using TSODSO: build_feeder, build_population, generate_profiles, sub_seed

    # Structural facts only (the bit-level fence lives in test_flex_population.jl): one
    # 3-device residential aggregator per load bus, ascending bus order, deterministic in seed.
    function check_default(feeder_sym)
        feeder = build_feeder(feeder_sym)
        profiles = generate_profiles(; seed = sub_seed(42, :profiles), T = 24)
        s_pop = sub_seed(42, :population)
        aggs = build_population(:default, feeder, feeder_sym, profiles, s_pop)
        load_buses = TSODSO._load_buses(feeder, feeder_sym)
        @test [a.bus for a in aggs] == load_buses
        @test all(a -> length(a.devices) == 3, aggs)
        @test all(a -> count(d -> d isa TSODSO.Thermostatic, a.devices) == 1, aggs)
        @test all(a -> count(d -> d isa TSODSO.Deferrable, a.devices) == 1, aggs)
        @test all(a -> count(d -> d isa TSODSO.PVBattery, a.devices) == 1, aggs)
        @test !any(a -> any(d -> d isa TSODSO.FixedCapacitor, a.devices), aggs)
        again = build_population(:default, feeder, feeder_sym, profiles, s_pop)
        @test [a.Pdc for a in again] == [a.Pdc for a in aggs]
        return length(aggs)
    end

    @test check_default(:ieee13) == 10
    @test check_default(:ieee123) == length(TSODSO.ieee123_load_nodes())
end

# ---------------------------------------------------------------------------- measurement script
#
# The items below include scripts/ieee8500_scenario_point.jl inside their own body (its `main`
# runs only when the file is the program, so the include defines the helpers and nothing more).
# None of them solves an IEEE-8500 point: the NO-GO record is derived from the committed CSVs, and
# the phase composition is checked on IEEE-13 only.

@testitem "ieee8500 scenario: NO-GO record derived from the committed CSVs" begin
    using TSODSO
    include(joinpath(@__DIR__, "..", "scripts", "ieee8500_scenario_point.jl"))

    # Binary GiB: 1 GiB = 1,048,576 kB.
    @test kb_to_gib(1_048_576) == 1.0

    dir = joinpath(pkgdir(TSODSO), "results", "ieee8500_benchmark")
    # MemTotal of the host the earlier runs used, passed explicitly so B2 does not depend on the
    # machine running the test.
    host_kb = 15_765_568
    row = derive_nogo_row(;
        attribution_csv = joinpath(dir, "memory_attribution.csv"),
        resources_csv = joinpath(dir, "point_resources.csv"),
        host_total_kb = host_kb,
    )
    @test keys(row) == SCENARIO_TABLE_COLUMNS
    @test row.row_kind == "recorded_no_go"
    @test row.status == "memory_infeasible"
    @test row.feeder == "ieee8500"
    @test row.T == 24
    @test row.strategy == "ADMM"
    # Raw counters, pinned by value.
    @test row.vmhwm_kb == 11_753_716
    @test row.p35_maxrss_kb == 12_079_316
    @test row.vmhwm_gib == 11_753_716 / 1024^2
    @test round(row.vmhwm_gib; digits = 3) == 11.209
    @test row.p35_maxrss_gib == 12_079_316 / 1024^2
    # B1: the larger measured peak; B2: an estimate above it.
    @test row.b1_gib == 12_079_316 / 1024^2
    @test round(row.b1_gib; digits = 3) == 11.520
    @test row.b2_gib_estimate == row.b1_gib + 0.12 * host_kb / 1024^2
    @test row.b2_gib_estimate > row.b1_gib
    @test row.threshold_gib == 10.0
    @test row.b1_gib > row.threshold_gib
    # The attribution anchor.
    @test row.anchor_iters == 7
    @test row.iters == 7
    @test round(row.anchor_delta_gib; digits = 4) == 9.2955
    @test round(row.gap_ratio; digits = 2) == 223.68
    # The note labels B2 as an estimate and states the counter-fact.
    @test occursin("is an estimate, not a bound", row.note)
    @test occursin("measured lower bound", row.note)
    @test occursin("Counter-fact", row.note)
    @test !occursin('\n', row.note)

    # The verdict is refused (not recorded) when the threshold is above the measured peaks.
    @test_throws ArgumentError derive_nogo_row(;
        attribution_csv = joinpath(dir, "memory_attribution.csv"),
        resources_csv = joinpath(dir, "point_resources.csv"),
        host_total_kb = host_kb,
        threshold_gib = 12.0,
    )
end

@testitem "ieee8500 scenario: memory pre-flight reads MemAvailable" begin
    using TSODSO
    include(joinpath(@__DIR__, "..", "scripts", "ieee8500_scenario_point.jl"))

    dir = mktempdir()
    path = joinpath(dir, "meminfo")
    write(
        path,
        "MemTotal:       15765568 kB\nMemFree:          812344 kB\n" *
        "MemAvailable:    4324172 kB\nBuffers:          123456 kB\n",
    )
    kb = mem_available_kb(path)
    @test kb == 4_324_172
    @test !preflight_ok(kb, 8)
    @test preflight_ok(kb, 0)
    @test preflight_ok(9_000_000, 8)
    @test preflight_ok(8 * 1_048_576, 8)
    @test !preflight_ok(8 * 1_048_576 - 1, 8)

    nomem = joinpath(dir, "meminfo_without_available")
    write(nomem, "MemTotal:       15765568 kB\nMemFree:          812344 kB\n")
    @test mem_available_kb(nomem) == -1
    @test !preflight_ok(mem_available_kb(nomem), 8)
end

@testitem "ieee8500 scenario: keyed upsert and gap-ratio parse" begin
    using TSODSO
    using CSV, DataFrames
    include(joinpath(@__DIR__, "..", "scripts", "ieee8500_scenario_point.jl"))

    # Row schema: every column, in order, `note` last; an unknown column is refused.
    r0 = scenario_row(; row_kind = "measured", feeder = "ieee13", status = "ok")
    @test keys(r0) == SCENARIO_TABLE_COLUMNS
    @test last(SCENARIO_TABLE_COLUMNS) === :note
    @test ismissing(r0.iters)
    @test_throws ArgumentError scenario_row(; not_a_column = 1)
    @test scenario_row(; note = "a\nb\r\nc").note == "a b c"

    path = joinpath(mktempdir(), "sub", "scenario_table.csv")
    key = (; row_kind = "measured", feeder = "ieee13", population = "default", T = 10)
    started = scenario_row(; key..., strategy = "ADMM", status = "started", note = "x")
    other = scenario_row(; key..., T = 24, strategy = "ADMM", status = "memory_infeasible")
    upsert_rows!(path, [started, other])
    d1 = CSV.read(path, DataFrame)
    @test nrow(d1) == 2

    # The final row replaces the started row with the same key; the other key survives.
    final = scenario_row(; key..., strategy = "ADMM", status = "ok", iters = 43, note = "y")
    upsert_rows!(path, [final])
    d2 = CSV.read(path, DataFrame)
    @test nrow(d2) == 2
    @test count(==(10), d2.T) == 1
    @test d2.status[findfirst(==(10), d2.T)] == "ok"
    @test d2.iters[findfirst(==(10), d2.T)] == 43
    @test d2.status[findfirst(==(24), d2.T)] == "memory_infeasible"

    # An added column is tolerated, and `note` stays last.
    extra = merge(
        scenario_row(; key..., feeder = "ieee123", strategy = "ADMM"),
        (; extra_col = 7),
    )
    upsert_rows!(path, [extra])
    d3 = CSV.read(path, DataFrame)
    @test nrow(d3) == 3
    @test :extra_col in propertynames(d3)
    @test last(propertynames(d3)) === :note
    @test d3.extra_col[findfirst(==("ieee123"), string.(d3.feeder))] == 7

    # The ratio quoted in the production SOC-exactness refusal message.
    msg =
        "SOC exactness refused: worst gap/(atol_b+rtol·|cone|)=568.9541645248668 > 1 " *
        "(rtol=0.0001, atol_b floor)"
    @test parse_gap_ratio(msg) == 568.9541645248668
    @test isnan(parse_gap_ratio("CertificateError without a ratio"))
    @test isnan(parse_gap_ratio(""))
end

@testitem "ieee8500 scenario: ieee13 phase composition parity" begin
    using TSODSO
    include(joinpath(@__DIR__, "..", "scripts", "ieee8500_scenario_point.jl"))

    # The script composes the solve_admm plumbing phase by phase; on the same Scenario it must give
    # what the library path gives. Both paths are deterministic and run the same calls, and the
    # observed differences are exactly 0, so the comparison is `==`.
    s = Scenario(;
        name = "phase-parity",
        feeder = :ieee13,
        strategy = ADMM(),
        T = 10,
        seed = 3,
    )
    # No wall-clock cap, as on the library path (solve_admm defaults to `nothing`).
    ph = scenario_admm_phases(s; time_limit_s = nothing, sample_mem = false)
    @test ph.status == "ok"
    @test ph.result !== nothing
    lib = TSODSO.run_scenario(s)
    @test ph.iters == lib.iters
    @test ph.result.iters == lib.iters
    @test ph.result.welfare == lib.welfare
    @test ph.result.exact_maxgap == lib.exact_maxgap
    @test ph.result.dadp == lib.dadp
    @test ph.result.welfare isa Float64
    @test ph.result.dadp isa Matrix{Float64}
    @test ph.n_buses == 11
    @test ph.n_aggregators == 10
end
