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
    @test_throws ArgumentError build_population(:default_10pct, feeder13, :ieee13, profiles, 1)
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
            agg -> agg.bus in sampled || any(dv -> dv isa TSODSO.FixedCapacitor, agg.devices),
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
