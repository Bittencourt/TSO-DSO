# test/test_population_case_a.jl
#
# Seam: src/experiments/materialize.jl — the `:case_a_784` thesis population (POP-01/02/03)
# and the `case_a_household_map` pure accessor.
#
# FAST items only (tags = [:population]): the full-population build is 784 per-house hash
# draws + device structs (no solves), measured cheap — every item here stays in the fast
# lane. The heavy centralized-vs-ADMM agreement check (POP-04) is a separate `:slow` item
# owned by a later plan of this phase; numeric identity of `:default` is owned by the
# existing goldens (test_ieee8500.jl) and the ADMM knife-edge canary.
#
# GUARD (a missing symbol must fail cleanly, never crash the runner): the first assertion in
# each item is the `isdefined(TSODSO, :symbol)` check, mirroring the test_admm.jl precedent;
# the behavioral asserts sit behind it.
#
# SOFT-SCOPE RULE (runtests.jl header — Pitfall 9): every loop accumulator lives in a `let`
# block (a hard scope) whose value is destructured back at item top level; `all(...)`/
# closures are used where no accumulation is needed. Never a bare assignment inside a
# top-level `for`.
#
# Fixtures are built in-item (no new testsetup module): feeder `build_feeder(:ieee13)`,
# profiles `generate_profiles(; seed = sub_seed(42, :profiles), T = 24)`, population seed
# `sub_seed(42, :population)` — the scripts/thesis_caseA.jl constants.
#
# Equality-semantics note for the rebuild item: the device structs and `Aggregator` are
# immutable but carry Vector fields (`Tout`/`Ppv`/`Pdc`/`devices`), so Julia's default
# `==`/`===` compares those fields by REFERENCE — two independently built populations are
# `==`-false even when bit-identical. Rebuild reproducibility is therefore asserted
# STRUCTURALLY (field-wise `isequal`, which on the bit-reproducible profile vectors is
# bitwise identity) — this is the honest reading of the locked "rebuilding reproduces the
# population exactly" criterion.

@testitem "population: case_a_784 counts and roll-up shape" tags = [:population] begin
    using TSODSO
    using TSODSO:
        _case_a_house_counts,
        build_feeder,
        build_population,
        case_a_household_map,
        generate_profiles,
        sub_seed

    @test isdefined(TSODSO, :build_population)
    @test isdefined(TSODSO, :case_a_household_map)

    feeder = build_feeder(:ieee13)
    profiles = generate_profiles(; seed = sub_seed(42, :profiles), T = 24)
    S_pop = sub_seed(42, :population)
    aggs = build_population(:case_a_784, feeder, :ieee13, profiles, S_pop)
    counts = _case_a_house_counts(collect(2:11), 784)
    map_rows = case_a_household_map(feeder, :ieee13, S_pop)

    # 10 bus-level aggregators over the 10 IEEE-13 load buses, strictly ascending, unique.
    @test length(aggs) == 10
    @test [a.bus for a in aggs] == collect(2:11)

    # 784 houses == 3 devices each == 2352 devices total; per-bus device counts are
    # 3 x the counts dict (79 houses on buses 2-5, 78 on buses 6-11).
    @test sum(length, [a.devices for a in aggs]) == 3 * 784
    @test all(a -> length(a.devices) == 3 * counts[a.bus], aggs)

    # The roll-up keeps the horizon: every aggregator's Pdc has length T.
    @test all(a -> length(a.Pdc) == 24, aggs)

    # The household map describes the SAME population: 784 rows, per-bus counts equal.
    @test length(map_rows) == 784
    per_bus_map = let
        c = Dict{Int, Int}()
        for row in map_rows
            c[row.bus] = get(c, row.bus, 0) + 1
        end
        c
    end
    @test per_bus_map == Dict(bus => n for (bus, n) in counts)
end

@testitem "population: case_a_784 seed derivation distinct + deterministic" tags =
    [:population] begin
    using TSODSO
    using TSODSO: _case_a_house_counts, _case_a_house_seed, sub_seed

    @test isdefined(TSODSO, :_case_a_house_seed)

    counts = _case_a_house_counts(collect(2:11), 784)
    buses = sort(collect(keys(counts)))
    S_pop = sub_seed(42, :population)

    # Distinctness is asserted on the SET (a collision would shrink it below 784 even
    # though a vector of draws would still have length 784).
    n_seeds = let
        seeds = Set{Int}()
        for bus in buses, h in 1:counts[bus]
            push!(seeds, _case_a_house_seed(S_pop, bus, h))
        end
        length(seeds)
    end
    @test n_seeds == 784

    # Deterministic: the same (seed, bus, house_index) tuple evaluates identically.
    @test _case_a_house_seed(S_pop, 2, 1) == _case_a_house_seed(S_pop, 2, 1)
    @test _case_a_house_seed(S_pop, 11, 78) == _case_a_house_seed(S_pop, 11, 78)

    # Sensitivity: a different master seed changes at least one house seed.
    n_changed = let
        c = 0
        for bus in buses, h in 1:counts[bus]
            if _case_a_house_seed(S_pop, bus, h) != _case_a_house_seed(S_pop + 1, bus, h)
                c += 1
            end
        end
        c
    end
    @test n_changed >= 1
end

@testitem "population: case_a_784 rebuild is == and same-bus houses differ" tags =
    [:population] begin
    using TSODSO
    using TSODSO:
        _case_a_house_counts,
        _case_a_house_seed,
        build_feeder,
        build_population,
        generate_profiles,
        sub_seed

    @test isdefined(TSODSO, :build_population)

    # Structural field-wise equality (see the file-header equality-semantics note: default
    # `==` is reference-true on the devices'/aggregator's Vector fields, so rebuild identity
    # is asserted structurally). At DEVICE level every field is a scalar or a Vector, so
    # `isequal` is exact; the AGGREGATOR's `devices` Vector needs element-wise structural
    # comparison (isequal on whole-device structs would compare the wrapped Vectors by
    # reference).
    function struct_eq(a, b)
        typeof(a) === typeof(b) || return false
        for n in propertynames(a)
            isequal(getproperty(a, n), getproperty(b, n)) || return false
        end
        return true
    end
    agg_eq(x, y) =
        x.bus == y.bus &&
        isequal(x.φ, y.φ) &&
        isequal(x.Pdc, y.Pdc) &&
        length(x.devices) == length(y.devices) &&
        all(i -> struct_eq(x.devices[i], y.devices[i]), eachindex(x.devices))

    feeder = build_feeder(:ieee13)
    profiles = generate_profiles(; seed = sub_seed(42, :profiles), T = 24)
    S_pop = sub_seed(42, :population)
    counts = _case_a_house_counts(collect(2:11), 784)
    aggs1 = build_population(:case_a_784, feeder, :ieee13, profiles, S_pop)
    aggs2 = build_population(:case_a_784, feeder, :ieee13, profiles, S_pop)

    # Rebuild at the same seed reproduces the population exactly (structurally ==).
    @test length(aggs1) == length(aggs2)
    @test all(i -> agg_eq(aggs1[i], aggs2[i]), eachindex(aggs1))

    # ANTI-PITFALL-2 (`seed + bus` duplication): the bus-2 aggregator's PVBattery devices
    # (one per house — devices 3, 6, 9, ... of the concatenated list) must carry distinct
    # per-house profile draws. Under the `seed + bus` idiom ALL 79 houses would share ONE
    # draw, so the distinct-count would collapse to 1.
    #
    # THRESHOLD, not strict pairwise distinctness (measured entropy of the profile
    # generator): the pv vector only encodes the 12 daylight hours of a 3-state Markov
    # path (the diurnal envelope zeroes the rest), so two DISTINCT seeds have a small but
    # real chance of coinciding on the same pv path — at this population's S_pop exactly
    # one bus-2 pair collides (78 distinct pv vectors of 79; their demand draws differ and
    # their seeds are distinct — verified when pinning this threshold). The full (pv,
    # demand) draw is unique for every one of the 784 houses (asserted below), which is
    # the load-bearing no-collision statement.
    bus2_batts = let
        agg = aggs1[1]   # ascending bus order: aggs1[1] is bus 2
        collect(Iterators.filter(d -> d isa PVBattery, agg.devices))
    end
    @test length(bus2_batts) == 79   # one battery per bus-2 house
    n_distinct_pv_bus2 = let
        pvs = [b.Ppv for b in bus2_batts]
        length(Set(pvs))
    end
    @test n_distinct_pv_bus2 >= 70   # would be 1 under `seed + bus`

    # Full-draw uniqueness: re-deriving every house's (pv, demand) draw from its
    # `_case_a_house_seed` yields 784 DISTINCT draws — no two houses of the population
    # share a profile (would be 10 draws under `seed + bus`).
    n_distinct_draws = let
        draws = Set{Tuple{Vector{Float64}, Vector{Float64}}}()
        for bus in 2:11, h in 1:counts[bus]
            prof = generate_profiles(; seed = _case_a_house_seed(S_pop, bus, h), T = 24)
            push!(draws, (prof.pv, prof.demand))
        end
        length(draws)
    end
    @test n_distinct_draws == 784
end

@testitem "population: household map consistency + purity" tags = [:population] begin
    using TSODSO
    using TSODSO: _case_a_house_counts, build_feeder, case_a_household_map

    @test isdefined(TSODSO, :case_a_household_map)

    feeder = build_feeder(:ieee13)
    m1 = case_a_household_map(feeder, :ieee13, 42)
    m2 = case_a_household_map(feeder, :ieee13, 42)

    # Purity: two calls with equal arguments return == vectors.
    @test m1 == m2
    @test length(m1) == 784

    # Seed-independence (documented contract): the map encodes ONLY assignment structure
    # (bus / house_index / pv_group), never profile draws — per-house seeding happens
    # exclusively in build_population's profile draws. Two calls differing ONLY in the
    # seed positional return == vectors.
    @test m1 == case_a_household_map(feeder, :ieee13, 999)

    # Exactly the locked fields, in order; aggregator is keyed by bus; fixed device set;
    # global 1..784 index in bus-major then house-index order.
    @test all(
        row ->
            propertynames(row) ==
            (:house, :bus, :aggregator, :device_set, :pv_group, :house_index),
        m1,
    )
    @test all(row -> row.aggregator == row.bus, m1)
    @test all(row -> row.device_set === :thermostatic_deferrable_pvbattery, m1)
    @test [row.house for row in m1] == collect(1:784)
    @test m1[1].bus == 2 && m1[1].house_index == 1

    # Per-bus row counts match the counts dict; house_index stays in 1..n_bus.
    counts = _case_a_house_counts(collect(2:11), 784)
    per_bus = let
        c = Dict{Int, Int}()
        for row in m1
            c[row.bus] = get(c, row.bus, 0) + 1
        end
        c
    end
    @test per_bus == Dict(bus => n for (bus, n) in counts)
    @test all(row -> 1 <= row.house_index <= counts[row.bus], m1)

    # Default pv_fraction (1.0): every house is :pv — the honest reading of the locked
    # "keep the :default fractions" decision (:default is 100%-PV).
    @test all(row -> row.pv_group === :pv, m1)

    # Generic-field behavior (Phase-41 seam, asserted WITHOUT changing the default): at
    # pv_fraction = 0.5 the :pv houses are exactly those with
    # house_index <= ceil(0.5 * n_bus); the rest are :non_pv.
    m_half = case_a_household_map(feeder, :ieee13, 42; pv_fraction = 0.5)
    @test length(m_half) == 784
    @test all(
        row ->
            row.pv_group ==
            (row.house_index <= ceil(0.5 * counts[row.bus]) ? :pv : :non_pv),
        m_half,
    )
    n_pv_half = let
        c = 0
        for row in m_half
            row.pv_group === :pv && (c += 1)
        end
        c
    end
    @test n_pv_half == sum(bus -> Int(ceil(0.5 * counts[bus])), collect(2:11))

    # The default map is untouched by the keyword call above (no shared mutable state).
    @test m1 == case_a_household_map(feeder, :ieee13, 42)
end

@testitem "population: :default regression + selector guards" tags = [:population] begin
    using TSODSO
    using TSODSO: build_feeder, build_population, generate_profiles, sub_seed

    @test isdefined(TSODSO, :build_population)
    @test isdefined(TSODSO, :Scenario)

    feeder = build_feeder(:ieee13)
    profiles = generate_profiles(; seed = sub_seed(42, :profiles), T = 24)
    S_pop = sub_seed(42, :population)

    # :default STRUCTURAL regression (numeric identity is owned by the existing goldens and
    # the ADMM knife-edge canary): still 10 aggregators on ieee13, buses [2..11], 3 devices
    # each, Pdc over the full horizon.
    def = build_population(:default, feeder, :ieee13, profiles, S_pop)
    @test length(def) == 10
    @test [a.bus for a in def] == collect(2:11)
    @test all(a -> length(a.devices) == 3, def)
    @test all(a -> length(a.Pdc) == 24, def)

    # Selector guards: unknown population selector, and :case_a_784 over a non-:ieee13
    # feeder, both throw ArgumentError (fail-loud, never a silent fallback).
    @test_throws ArgumentError build_population(:nope, feeder, :ieee13, profiles, S_pop)
    @test_throws ArgumentError build_population(
        :case_a_784,
        feeder,
        :ieee123,
        profiles,
        S_pop,
    )

    # Scenario accepts the new selector and still rejects unknown ones (SCENARIO_VALID_
    # POPULATIONS widened; the guard auto-lists the tuple in its message). `name` is a
    # REQUIRED keyword, not positional.
    s = Scenario(; name = "population: case_a_784 selector", population = :case_a_784)
    @test s.population == :case_a_784
    @test_throws ArgumentError Scenario(;
        name = "population: bad selector",
        population = :not_a_selector,
    )
end

@testitem "population: case_a_household_map stays unexported" tags = [:population] begin
    using TSODSO

    # The materializer group stays out of the namespace (test_exports.jl precedent): the
    # accessor is reachable ONLY through qualification.
    @test isdefined(TSODSO, :case_a_household_map)
    @test !(:case_a_household_map in names(TSODSO))
    @test TSODSO.case_a_household_map isa Function
end
