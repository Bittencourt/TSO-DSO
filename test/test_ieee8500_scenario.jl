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

    # Without `host_total_kb`, B2's host total is the measurement host's evidence (the `free -m`
    # snapshot of the attribution run), never the machine running the derivation.
    @test free_total_kb(joinpath(dir, "runs", "p39-attr-d0.1-T24.free_before")) == 15_396 * 1024
    dflt = derive_nogo_row(;
        attribution_csv = joinpath(dir, "memory_attribution.csv"),
        resources_csv = joinpath(dir, "point_resources.csv"),
    )
    @test dflt.b2_gib_estimate == dflt.b1_gib + 0.12 * (15_396 * 1024) / 1024^2
    @test occursin("free -m total in runs/p39-attr-d0.1-T24.free_before", dflt.note)
    nofree = joinpath(mktempdir(), "free_before")
    write(nofree, "              total        used\nSwap:   10239   1553\n")
    @test_throws ArgumentError free_total_kb(nofree)

    # The counter-fact is derived from the rows: both runs completed, with the head run's
    # launch-time MemAvailable below B1, and the mechanism is not asserted as measured.
    @test occursin("completed on this host twice", row.note)
    @test occursin("10334 MiB", row.note)
    @test occursin("which the wrapper did not measure", row.note)
    @test occursin("rc 143, oom_source earlyoom", row.note)

    # A head run that did not end with rc 0 is not claimed as completed; a missing killed row is
    # an error, not a silent omission.
    res_lines = readlines(joinpath(dir, "point_resources.csv"))
    tmpd = mktempdir()
    failed = joinpath(tmpd, "head_failed.csv")
    write(
        failed,
        join(
            map(
                l -> replace(l, r"^p35-head-d0\.1-T24,0," => "p35-head-d0.1-T24,143,"),
                res_lines,
            ),
            "\n",
        ) * "\n",
    )
    fr = derive_nogo_row(;
        attribution_csv = joinpath(dir, "memory_attribution.csv"),
        resources_csv = failed,
        host_total_kb = host_kb,
    )
    @test fr.status == "memory_infeasible"
    @test occursin("completed on this host once", fr.note)
    @test occursin("ended with rc 143, so no completed run is claimed from it", fr.note)
    nokill = joinpath(tmpd, "no_kill.csv")
    write(nokill, join(filter(l -> !startswith(l, "p35-head-d0.25-T24,"), res_lines), "\n") * "\n")
    @test_throws ArgumentError derive_nogo_row(;
        attribution_csv = joinpath(dir, "memory_attribution.csv"),
        resources_csv = nokill,
        host_total_kb = host_kb,
    )

    # The verdict uses the LARGER peak: a threshold between the two peaks (11.209 and 11.520 GiB)
    # is still a NO-GO.
    between = derive_nogo_row(;
        attribution_csv = joinpath(dir, "memory_attribution.csv"),
        resources_csv = joinpath(dir, "point_resources.csv"),
        host_total_kb = host_kb,
        threshold_gib = 11.3,
    )
    @test between.status == "memory_infeasible"
    @test between.threshold_gib == 11.3

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
    @test ph.n_load_buses == 10   # the feeder's load-bus count, on every feeder
    # Every phase time includes compilation; the recorded compile part fits inside it.
    for k in (:materialize, :build, :solve, :certify)
        c = getproperty(ph, Symbol(k, "_compile_s"))
        w = getproperty(ph, Symbol(k, "_s"))
        @test 0 <= c <= w + 1e-3
    end
end

@testitem "ieee8500 scenario: provenance records the effective heap-size hint" begin
    using TSODSO
    include(joinpath(@__DIR__, "..", "scripts", "ieee8500_scenario_point.jl"))

    # Julia reads no environment variable for its heap-size hint, so the recorded value must be
    # the process's own `Base.JLOptions().heap_size_hint` (bytes, 0 = none), whatever the
    # environment says.
    eff = Int(Base.JLOptions().heap_size_hint)
    @test effective_heap_size_hint() === eff
    @test eff >= 0
    p = withenv("JULIA_HEAP_SIZE_HINT" => "8G") do
        _provenance_fields((; run_label = "hint-check"))
    end
    @test p.heap_size_hint === eff
    @test p.run_label == "hint-check"
end

@testitem "ieee8500 scenario: a transient row never displaces a completed measurement" begin
    using TSODSO
    using CSV, DataFrames
    include(joinpath(@__DIR__, "..", "scripts", "ieee8500_scenario_point.jl"))

    @test ROW_KEY == (:row_kind, :feeder, :population, :T, :strategy, :seed, :run_label)
    @test is_transient_status("started")
    @test is_transient_status("preflight_refused")
    @test !is_transient_status("refused_certificate")
    @test !is_transient_status("ok")

    path = joinpath(mktempdir(), "scenario_table.csv")
    key = (;
        row_kind = "measured",
        feeder = "ieee8500",
        population = "default_10pct",
        T = 10,
        strategy = "ADMM",
        seed = 1,
        run_label = "p-a",
    )
    statuses(p) = sort(string.(CSV.read(p, DataFrame).status))

    upsert_rows!(path, [scenario_row(; key..., status = "refused_certificate", iters = 5)])
    # A pre-flight refusal of a later attempt under the same key keeps the completed row.
    upsert_rows!(path, [scenario_row(; key..., status = "preflight_refused")])
    @test statuses(path) == ["preflight_refused", "refused_certificate"]
    # A `started` row replaces the older transient row, never the completed one.
    upsert_rows!(path, [scenario_row(; key..., status = "started")])
    @test statuses(path) == ["refused_certificate", "started"]
    d = CSV.read(path, DataFrame)
    @test d.iters[findfirst(==("refused_certificate"), d.status)] == 5
    # The attempt's final row replaces both rows of its key.
    upsert_rows!(path, [scenario_row(; key..., status = "ok", iters = 7)])
    d = CSV.read(path, DataFrame)
    @test nrow(d) == 1
    @test d.status[1] == "ok"
    @test d.iters[1] == 7

    # Another seed or another run label is another row.
    upsert_rows!(path, [scenario_row(; key..., seed = 2, status = "started")])
    upsert_rows!(path, [scenario_row(; key..., run_label = "p-b", status = "preflight_refused")])
    d = CSV.read(path, DataFrame)
    @test nrow(d) == 3
    @test count(==("ok"), d.status) == 1

    # A table written before seed and run_label joined the key stays readable: its rows key on
    # missing seed and label, and the schema grows by union.
    old = joinpath(mktempdir(), "scenario_table.csv")
    write(
        old,
        "row_kind,feeder,population,T,strategy,status,note\n" *
        "recorded_no_go,ieee8500,harness_density_0.1,24,ADMM,memory_infeasible,\"a, b\"\n" *
        "measured,ieee8500,default_10pct,10,ADMM,refused_certificate,x\n",
    )
    upsert_rows!(old, [scenario_row(; key..., status = "started")])
    d = CSV.read(old, DataFrame)
    @test nrow(d) == 3
    @test :seed in propertynames(d) && :run_label in propertynames(d)
    @test last(propertynames(d)) === :note
    @test count(==("refused_certificate"), d.status) == 1
    # The NO-GO record (missing seed and label) is replaced in place by a re-derivation.
    upsert_rows!(
        old,
        [
            scenario_row(;
                row_kind = "recorded_no_go",
                feeder = "ieee8500",
                population = "harness_density_0.1",
                T = 24,
                strategy = "ADMM",
                status = "memory_infeasible",
                note = "re-derived",
            ),
        ],
    )
    d = CSV.read(old, DataFrame)
    @test nrow(d) == 3
    @test only(d.note[d.row_kind .== "recorded_no_go"]) == "re-derived"
end

@testitem "ieee8500 scenario: the table is rewritten atomically" begin
    using TSODSO
    using CSV, DataFrames
    include(joinpath(@__DIR__, "..", "scripts", "ieee8500_scenario_point.jl"))

    dir = mktempdir()
    path = joinpath(dir, "scenario_table.csv")
    upsert_rows!(path, [scenario_row(; row_kind = "measured", feeder = "ieee13", status = "ok")])
    upsert_rows!(path, [scenario_row(; row_kind = "measured", feeder = "ieee123", status = "ok")])
    # Only the table remains: the temporary file was renamed over it, not left beside it.
    @test readdir(dir) == ["scenario_table.csv"]
    @test nrow(CSV.read(path, DataFrame)) == 2

    # A failed write leaves the previous table intact and no temporary file behind.
    before = read(path, String)
    @test_throws Exception write_table_atomic(path, :not_a_table)
    @test read(path, String) == before
    @test readdir(dir) == ["scenario_table.csv"]
end

@testitem "ieee8500 scenario: in-process failures are recorded, then propagate" begin
    using TSODSO
    using CSV, DataFrames
    include(joinpath(@__DIR__, "..", "scripts", "ieee8500_scenario_point.jl"))

    # A stub phase runner stands in for the solve, so nothing is materialized or solved.
    dir = mktempdir()
    path = joinpath(dir, "scenario_table.csv")
    opts = (;
        feeder = :ieee13,
        T = 10,
        seed = 3,
        time_limit = 1200.0,
        min_gib = 0.0,
        run_label = "stub",
        results_dir = dir,
    )
    oom_phases(s; kw...) = throw(OutOfMemoryError())
    bug_phases(s; kw...) = throw(ArgumentError("stub misuse"))
    row_status(p) = string.(CSV.read(p, DataFrame).status)

    @test_throws OutOfMemoryError run_measured_point(opts; phases = oom_phases)
    @test row_status(path) == ["memory_infeasible_inprocess"]
    @test !is_transient_status("memory_infeasible_inprocess")

    # A crash is transient: recorded, but it never displaces the final row of its key.
    @test_throws ArgumentError run_measured_point(opts; phases = bug_phases)
    @test sort(row_status(path)) == ["crashed:ArgumentError", "memory_infeasible_inprocess"]
    d = CSV.read(path, DataFrame)
    @test occursin("stub misuse", only(d.note[d.status .== "crashed:ArgumentError"]))

    # On a fresh key the crash row replaces the `started` row (no misleading "process died").
    opts2 = merge(opts, (; run_label = "stub2"))
    @test_throws ArgumentError run_measured_point(opts2; phases = bug_phases)
    d = CSV.read(path, DataFrame)
    @test only(d.status[d.run_label .== "stub2"]) == "crashed:ArgumentError"
end

@testitem "ieee8500 scenario: ieee13 status branches (refusal, maxiter, budget)" begin
    using TSODSO
    include(joinpath(@__DIR__, "..", "scripts", "ieee8500_scenario_point.jl"))

    # IEEE-13 only. The production outcome at 8500 scale is `refused_certificate`; here it is
    # forced with a flat floor far below any solver residual, passed ONLY in this test (the
    # library defaults and the command line are unchanged).
    s = Scenario(; name = "status-branches", feeder = :ieee13, strategy = ADMM(), T = 10, seed = 3)
    atol_force, rtol_force = 1e-300, 0.0
    ph = scenario_admm_phases(
        s;
        time_limit_s = nothing,
        sample_mem = false,
        atol_exact = atol_force,
        rtol_exact = rtol_force,
    )
    @test ph.status == "refused_certificate"
    @test ph.result === nothing
    @test ph.iters > 0
    @test isfinite(ph.gap_ratio) && ph.gap_ratio > 1
    @test !ismissing(ph.certify_s)
    @test occursin("kind=socp_exact", ph.message)

    # The library path refuses the same point after the same number of iterations, with the same
    # ratio (solve_admm called with run(::ADMM)'s arguments plus the same forcing floor).
    function library_refusal(s, atol, rtol)
        feeder, λ₀, aggs = TSODSO._materialize(s)
        pf = TSODSO.build_powerflow(s)
        A = s.strategy
        try
            TSODSO.solve_admm(
                feeder,
                pf,
                aggs;
                T = s.T,
                λ₀ = λ₀,
                ρ = A.ρ,
                maxiter = A.maxiter,
                ε_abs = A.ε_abs,
                ε_rel = A.ε_rel,
                τ = A.τ_ratio,
                μ = A.μ,
                allow_export = s.allow_export,
                atol_exact = atol,
                rtol_exact = rtol,
            )
        catch e
            return e
        end
        return nothing
    end
    lib = library_refusal(s, atol_force, rtol_force)
    @test lib isa CertificateError
    @test lib.kind === :socp_exact
    @test lib.iterations == ph.iters
    @test parse_gap_ratio(lib.msg) == ph.gap_ratio

    # convergence_error: maxiter reached, iters = maxiter, no certificate, as run_scenario's
    # ConvergenceError reports.
    s3 = Scenario(;
        name = "status-maxiter",
        feeder = :ieee13,
        strategy = ADMM(; maxiter = 3),
        T = 10,
        seed = 3,
    )
    ph3 = scenario_admm_phases(s3; time_limit_s = nothing, sample_mem = false)
    @test ph3.status == "convergence_error"
    @test ph3.iters == 3
    @test ph3.result === nothing
    @test ismissing(ph3.certify_s)
    err3 = try
        TSODSO.run_scenario(s3)
        nothing
    catch e
        e
    end
    @test err3 isa ConvergenceError
    @test err3.iterations == ph3.iters

    # budget_exceeded: a wall-clock cap that is already spent after the first iteration.
    phb = scenario_admm_phases(s; time_limit_s = 1e-6, sample_mem = false)
    @test phb.status == "budget_exceeded"
    @test phb.result === nothing
    @test ismissing(phb.certify_s)
    @test phb.iters >= 1
end

@testitem "ieee8500 scenario: the pre-flight judges the reading taken before package load" begin
    using TSODSO
    using CSV, DataFrames
    include(joinpath(@__DIR__, "..", "scripts", "ieee8500_scenario_point.jl"))

    # Read on the script's first lines (Base only); -1 only without /proc/meminfo.
    @test MEMAVAIL_AT_START_KB isa Int
    @test isfile("/proc/meminfo") ? MEMAVAIL_AT_START_KB > 0 : MEMAVAIL_AT_START_KB == -1

    # A refused pre-flight writes one row and runs nothing (the stub would throw if called).
    dir = mktempdir()
    opts = (;
        feeder = :ieee13,
        T = 10,
        seed = 3,
        time_limit = 1200.0,
        min_gib = 8.0,
        run_label = "preflight",
        results_dir = dir,
    )
    never(s; kw...) = error("phases must not run after a refused pre-flight")
    row = run_measured_point(opts; phases = never, avail_kb = 1024)
    @test row.status == "preflight_refused"
    @test row.mem_avail_before_kb == 1024
    @test occursin("before any package load", row.note)
    d = CSV.read(joinpath(dir, "scenario_table.csv"), DataFrame)
    @test nrow(d) == 1
    @test d.status[1] == "preflight_refused"
end

@testitem "ieee8500 scenario: text columns survive a rewrite" begin
    using TSODSO
    using CSV, DataFrames
    include(joinpath(@__DIR__, "..", "scripts", "ieee8500_scenario_point.jl"))

    # An all-digit git hash and run label keep their leading zeros across upserts.
    path = joinpath(mktempdir(), "scenario_table.csv")
    r = scenario_row(;
        row_kind = "measured",
        feeder = "ieee13",
        status = "ok",
        git_head = "0123456",
        run_label = "007",
    )
    upsert_rows!(path, [r])
    upsert_rows!(path, [scenario_row(; row_kind = "measured", feeder = "ieee123", status = "ok")])
    txt = read(path, String)
    @test occursin(",0123456,", txt)
    @test occursin(",007,", txt)
end
