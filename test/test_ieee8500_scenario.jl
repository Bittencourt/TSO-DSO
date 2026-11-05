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
