# test/test_population_case_a_scaling.jl
#
# Seam: the POP-05 scaling-measurement path — `_case_a_rung_counts`
# (src/experiments/materialize.jl) plus the nested-prefix → roll-up → solve_admm
# construction path scripts/case_a_scaling.jl drives for the population ladder.
#
# FAST structural smoke (tags = [:population]): item 1 is pure hash-free arithmetic on the
# counts dict; item 2 exercises the SCRIPT'S OWN construction path IN-PROCESS (the exact
# helpers + scales + roll-up idiom the `:case_a_784` branch and the script use) for two
# rungs, with a small serial solve per rung under a time_limit_s honesty cap (a
# `:budget_exceeded` is an accepted recorded status — the assertion is structural, never a
# performance claim). The FULL-scale measurement itself is the long-running script run
# owned by the committed CSVs (results/case_a_population/*.csv), not a suite item.
#
# Horizon note: item 2 runs at T = 10, NOT T = 2 — the `_case_a_house` device guards make
# this house shape UNCONSTRUCTABLE below T = 9 (the `Deferrable` window collapses:
# `min(16,T) - min(8,T)` gives `E ≤ Pmax·window_length` infeasible; the measured precedent
# is `T_HORIZON_FLOOR = T_QUICK = 10` in scripts/benchmark_ieee8500.jl, which documents
# exactly this ArgumentError). T = 10 is the smallest horizon that exercises the same
# construction path.
#
# GUARD (a missing symbol must fail cleanly, never crash the runner): the first assertion
# in each item is the `isdefined(TSODSO, :symbol)` check (test_admm.jl precedent).
#
# SOFT-SCOPE RULE (runtests.jl header — Pitfall 9): loop accumulators live in `let` blocks
# (hard scopes); `all(...)`/closures where no accumulation is needed.
#
# ρ provenance: solve_admm's `ρ` is a REQUIRED kwarg, so the micro-ladder passes the
# executor's own default `ADMM().ρ` — exactly what the script passes (the locked
# no-re-tuning configuration).

@testitem "population: scaling ladder rung counts nested + bounded + deterministic" tags =
    [:population] begin
    using TSODSO
    using TSODSO: _case_a_house_counts, _case_a_rung_counts

    @test isdefined(TSODSO, :_case_a_rung_counts)

    buses = collect(2:11)
    full = _case_a_house_counts(buses, 784)   # {2:79, 3:79, 4:79, 5:79, 6..11:78}

    # fraction 1.0 is EXACTLY the full population.
    @test _case_a_rung_counts(full, 1.0) == full

    # Deterministic: same inputs → identical output dict.
    @test _case_a_rung_counts(full, 0.25) == _case_a_rung_counts(full, 0.25)

    # Bounded + nested: 1 ≤ m_b ≤ n_b at every fraction, and m_b is monotone
    # non-decreasing in fraction for EVERY bus (a smaller rung is a prefix of a larger).
    fractions = [1 / 78, 0.125, 0.25, 0.5, 0.75, 0.999, 1.0]
    nested_ok = let ok = true
        for (i, f) in enumerate(fractions)
            rung = _case_a_rung_counts(full, f)
            for bus in buses
                n = full[bus]
                m = rung[bus]
                ok &= (1 <= m <= n)
                if i > 1
                    ok &= (m >= _case_a_rung_counts(full, fractions[i - 1])[bus])
                end
            end
        end
        ok
    end
    @test nested_ok

    # The 1/78 rung selects exactly 1 house per bus (10 houses total — the smallest
    # non-empty prefix).
    tiny = _case_a_rung_counts(full, 1 / 78)
    @test all(v -> v == 1, values(tiny))

    # Sub-1.0 fractions select strictly fewer houses than the full bus (floor behavior).
    @test _case_a_rung_counts(full, 0.5)[2] == div(79, 2)
    @test _case_a_rung_counts(full, 0.5)[11] == div(78, 2)

    # fraction ≤ 0 throws (rungs are nested prefixes; a non-positive fraction selects
    # nothing).
    @test_throws ArgumentError _case_a_rung_counts(full, 0.0)
    @test_throws ArgumentError _case_a_rung_counts(full, -0.25)
end

@testitem "population: T=10 micro-ladder through the script's construction path" tags =
    [:population] begin
    using TSODSO
    using TSODSO:
        ADMM,
        ConvexBranchFlow,
        _CASE_A_PV_FRACTION,
        _CASE_A_TOTAL_HOUSES,
        _IEEE13_DEV_SCALE,
        _IEEE13_LOAD_SCALE,
        _IEEE13_PV_SCALE,
        _case_a_house,
        _case_a_house_counts,
        _case_a_rung_counts,
        _load_buses,
        build_feeder,
        build_price,
        generate_profiles,
        solve_admm,
        sub_seed

    @test isdefined(TSODSO, :_case_a_rung_counts)
    @test isdefined(TSODSO, :solve_admm)

    # ---- the script's own construction path (case_a_houses_by_bus + roll-up) at T=10 ----
    # T = 10 (NOT 2): the Deferrable guard makes `_case_a_house` unconstructable below
    # T = 9 (T_HORIZON_FLOOR precedent, scripts/benchmark_ieee8500.jl).
    T = 10
    feeder = build_feeder(:ieee13)
    s_pop = sub_seed(42, :population)
    buses = _load_buses(feeder, :ieee13)
    counts = _case_a_house_counts(buses, _CASE_A_TOTAL_HOUSES)
    houses_by_bus = Dict{Int, Vector{Aggregator}}(
        bus => Aggregator[
            _case_a_house(
                bus,
                h,
                counts[bus],
                s_pop,
                T;
                load_scale = _IEEE13_LOAD_SCALE,
                pv_scale = _IEEE13_PV_SCALE,
                dev_scale = _IEEE13_DEV_SCALE,
                pv_fraction = _CASE_A_PV_FRACTION,
            ) for h in 1:counts[bus]
        ] for bus in buses
    )

    rollup(bus, hs) =
        Aggregator(
            bus,
            0.90,
            reduce(vcat, [h.devices for h in hs]),
            reduce(+, [h.Pdc for h in hs]),
        )

    λ₀ = build_price(:mem, T, nothing)
    ρ = ADMM().ρ                      # executor default — the script's own ρ provenance
    PF = ConvexBranchFlow()

    # Two nested rungs (0.5, 1.0): each solved serially with executor defaults; a
    # :budget_exceeded under the honesty cap is an ACCEPTED recorded status.
    statuses = Symbol[]
    iters_all = Int[]
    let
        for fraction in (0.5, 1.0)
            rung_counts = _case_a_rung_counts(counts, fraction)
            aggs = Aggregator[
                rollup(bus, houses_by_bus[bus][1:rung_counts[bus]]) for bus in buses
            ]
            # Roll-up shape: exactly 10 bus-level aggregators (solve_admm's 1:1 guard).
            @test length(aggs) == 10
            @test [a.bus for a in aggs] == buses
            @test sum(length(a.devices) for a in aggs) ==
                  3 * sum(values(rung_counts))
            r = solve_admm(
                feeder,
                PF,
                aggs;
                T = T,
                λ₀ = λ₀,
                ρ = ρ,
                time_limit_s = 120.0,
            )
            @test r.iters >= 1
            @test r.status in (:converged, :budget_exceeded)
            push!(statuses, r.status)
            push!(iters_all, Int(r.iters))
        end
    end
    @test length(statuses) == 2
    @test length(iters_all) == 2
    # Nestedness at the solve level: the 1.0 rung carries every device the 0.5 rung has,
    # plus its second half (same construction, same seeds).
    @test sum(values(_case_a_rung_counts(counts, 0.5))) <
          sum(values(_case_a_rung_counts(counts, 1.0)))
end
