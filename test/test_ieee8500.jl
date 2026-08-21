# test/test_ieee8500.jl
#
# Seam: the IEEE-8500 scale-benchmark feeder fixtures (SCALE-01/02, plan 25-03). Construction/
# invariant tests for BOTH committed fixtures (headline `ieee8500_modified`, MV-only control
# `ieee8500_mv_modified`, D-02), plus the pinned corrected-transformer regression trap (T-25-07)
# and the D-06 measured-impedance-spread reporting requirement.
#
# HYBRID FILE (repo-established pattern, VALIDATION.md): `@testitem` blocks for TestItemRunner
# discovery under `Pkg.test()`, PLUS a standalone `if abspath(PROGRAM_FILE) == @__FILE__ ... end`
# block at the bottom replicating the core assertions as plain `Test.jl` so
# `julia --project=. test/test_ieee8500.jl` (VALIDATION.md's documented quick command) runs
# WITHOUT TestItemRunner (this project's recorded sibling-worktree-contamination trap:
# `julia --project=. -e '... @run_package_tests ...'` resolves the test root via cwd).
#
# `@testitem` is only defined once `TestItemRunner`/`TestItems` (test-only deps) are loaded —
# NOT in the plain `--project=.` environment `julia --project=. test/test_ieee8500.jl` runs
# under. The guard below defines a no-op stub `@testitem` macro ONLY if one isn't already bound
# (i.e., only when running standalone, never under the real runner), so the `@testitem` blocks
# below macro-expand to a no-op instead of throwing `UndefVarError` when run directly.
if !isdefined(Main, Symbol("@testitem"))
    macro testitem(args...)
        return nothing
    end
end

# Hoisted to file scope (NOT nested inside the standalone `if` block at the bottom): a single
# top-level `if ... end` block is macro-expanded IN FULL before any part of it executes, so a
# `using Test` nested earlier IN THE SAME block would not yet be in effect for a `@testset`
# nested later in that same block. `Test` is a stdlib, always loadable regardless of environment.
using Test
using TSODSO
using JuMP

@testitem "ieee8500: headline fixture is radial, contiguous, single-root (ieee8500)" tags =
    [:phase25] begin
    using TSODSO

    feeder = TSODSO.ieee8500_modified()
    N = length(feeder.buses)

    # radial: a tree on N buses has exactly N-1 edges.
    @test length(feeder.branches) == N - 1

    # contiguous 1-based ids (bus.id == position) — the relabel convention.
    @test all(i -> feeder.buses[i].id == i, 1:N)

    # exactly one root, at the declared root index; every other bus non-root.
    @test count(b -> b.is_root, feeder.buses) == 1
    @test feeder.buses[feeder.root].is_root
end

@testitem "ieee8500: MV-only control fixture is radial, contiguous, single-root (ieee8500)" tags =
    [:phase25] begin
    using TSODSO

    feeder = TSODSO.ieee8500_mv_modified()
    N = length(feeder.buses)

    @test length(feeder.branches) == N - 1
    @test all(i -> feeder.buses[i].id == i, 1:N)
    @test count(b -> b.is_root, feeder.buses) == 1
    @test feeder.buses[feeder.root].is_root
end

@testitem "ieee8500: per-unit magnitude sanity, both fixtures (ieee8500)" tags = [:phase25] begin
    using TSODSO

    for feeder in (TSODSO.ieee8500_modified(), TSODSO.ieee8500_mv_modified())
        for br in feeder.branches
            @test 0 <= br.r < TSODSO.IMPEDANCE_PU_MAX
            @test 0 <= br.x < TSODSO.IMPEDANCE_PU_MAX
            @test 0 < br.smax < TSODSO.SMAX_PU_MAX
        end
        head = only(
            b for b in feeder.branches if
            b.from == feeder.root || b.to == feeder.root
        )
        @test isapprox(head.smax, 55.0; atol = 1e-6)
    end
end

@testitem "ieee8500: pinned corrected-transformer spot-check on a CT5 branch (ieee8500)" tags =
    [:phase25] begin
    using TSODSO

    # Regression trap (T-25-07): a future accidental revert to the superseded 2-winding
    # placeholder formula (%Rs[1]+%Rs[2], bare Xhl) would give r_pct=1.8/x_pct=2.04, which at
    # S_base=0.5 MVA and CT5's kva=5 (ratio 500/5=100) yields r=1.80/x=2.04 pu — NOT 3.00/2.72 —
    # so this assertion fails loudly on a regression.
    feeder = TSODSO.ieee8500_modified()
    remap = TSODSO.ieee8500_relabel_map()

    ct5_pair = first(k for (k, v) in TSODSO.IEEE8500_XFMR_EDGES if v.code == "CT5")
    from_idx, to_idx = remap[ct5_pair[1]], remap[ct5_pair[2]]
    br = only(
        b for b in feeder.branches if
        (b.from == from_idx && b.to == to_idx) || (b.from == to_idx && b.to == from_idx)
    )

    @test isapprox(br.r, 3.00; atol = 1e-2)
    @test isapprox(br.x, 2.72; atol = 1e-2)
end

@testitem "ieee8500: capacitor/load/mv-load bus-role helpers (ieee8500)" tags = [:phase25] begin
    using TSODSO

    full_feeder = TSODSO.ieee8500_modified()
    mv_feeder = TSODSO.ieee8500_mv_modified()

    cap = TSODSO.ieee8500_capacitor_buses()
    @test length(cap) == 4
    @test allunique(cap)
    @test all(1 <= c <= length(full_feeder.buses) for c in cap)
    @test all(1 <= c <= length(mv_feeder.buses) for c in cap)

    loads = TSODSO.ieee8500_load_nodes()
    @test length(loads) == 1177
    @test allunique(loads)
    @test all(1 <= l <= length(full_feeder.buses) for l in loads)

    mv_loads = TSODSO.ieee8500_mv_load_buses()
    @test length(mv_loads) <= 1177
    @test issorted(mv_loads)
    @test allunique(mv_loads)
    @test all(1 <= m <= length(mv_feeder.buses) for m in mv_loads)
end

@testitem "ieee8500: D-06 measured per-unit impedance spread is reported (ieee8500)" tags =
    [:phase25] begin
    using TSODSO

    feeder = TSODSO.ieee8500_modified()
    vals = [v for br in feeder.branches for v in (br.r, br.x) if v > 0]
    measured_min_pu = minimum(vals)
    measured_max_pu = maximum(vals)
    spread_orders = log10(measured_max_pu / measured_min_pu)

    println(
        "D-06 measured per-unit impedance spread: min=$(measured_min_pu) pu, " *
        "max=$(measured_max_pu) pu, spread=$(spread_orders) orders of magnitude",
    )

    # Loose, on-purpose sanity floor (D-06: report the measured spread, never engineer it
    # away) — NOT a pinned regression value.
    @test spread_orders > 3.0
end

@testitem "ieee8500: build_population(:ieee8500) house/capacitor roll-up (plan 25-04)" tags =
    [:phase25] begin
    using TSODSO

    profiles = generate_profiles(; seed = 1, T = 24)
    feeder = TSODSO.ieee8500_modified()
    pop = build_population(:default, feeder, :ieee8500, profiles, 7)

    @test length(pop) == length(TSODSO.ieee8500_load_nodes()) + 4

    houses = pop[1:(end - 4)]
    caps = pop[(end - 3):end]

    # Every house aggregator has exactly 3 devices (D-04: Thermostatic + Deferrable +
    # PVBattery, no device-count axis introduced alongside the density sweep).
    for h in houses
        @test length(h.devices) == 3
        @test count(d -> d isa TSODSO.Thermostatic, h.devices) == 1
        @test count(d -> d isa TSODSO.Deferrable, h.devices) == 1
        @test count(d -> d isa TSODSO.PVBattery, h.devices) == 1
    end

    # The 4 capacitor aggregators (D-12): Pdc == zeros(T), exactly one FixedCapacitor each.
    T = length(profiles.demand)
    for c in caps
        @test c.Pdc == zeros(T)
        @test length(c.devices) == 1
        @test c.devices[1] isa TSODSO.FixedCapacitor
    end
end

@testitem "ieee8500: FixedCapacitor contribute! + DEV-05 sole-:Rq-writer invariant (plan 25-04)" tags =
    [:phase25] begin
    using TSODSO, JuMP

    # Direct unit call: a bare context, no feeder anywhere (network-agnostic device).
    model = Model()
    ctx = TSODSO.ModelContext(model)
    T = 4
    q_nom = 0.75
    d = TSODSO.FixedCapacitor(11, q_nom)
    out = TSODSO.contribute!(d, ctx; T = T)

    @test out isa NamedTuple
    @test haskey(out, :vars) && haskey(out, :p_inject) && haskey(out, :q_inject) &&
          haskey(out, :utility)
    @test out.vars == NamedTuple()
    @test length(out.q_inject) == T
    for t in 1:T
        @test JuMP.constant(out.q_inject[t]) == q_nom
        @test isempty(JuMP.linear_terms(out.q_inject[t]))   # a pure constant, no variables
        @test JuMP.constant(out.p_inject[t]) == 0.0
        @test isempty(JuMP.linear_terms(out.p_inject[t]))
    end

    # DEV-05 structural regression (T-25-10): Aggregator must remain the SOLE :Rq writer —
    # no `add_to_residual!(..., :Rq, ...)` call may exist outside Aggregator.jl.
    devices_dir = joinpath(dirname(pathof(TSODSO)), "devices")
    offenders = String[]
    for f in readdir(devices_dir; join = true)
        endswith(f, "Aggregator.jl") && continue
        isfile(f) || continue
        for line in eachline(f)
            occursin(r"add_to_residual!.*:Rq", line) && push!(offenders, "$f: $line")
        end
    end
    @test isempty(offenders)
end

@testitem "ieee8500: build_population(:ieee13) is byte-identical to its pre-plan-25-04 golden (plan 25-04)" tags =
    [:phase25] begin
    using TSODSO

    profiles = generate_profiles(; seed = 1, T = 24)
    pop = build_population(:default, ieee13_modified(), :ieee13, profiles, 42)

    # Golden snapshot measured ONCE against the pre-plan-25-04 build_population output
    # (before the :ieee8500/:ieee8500_mv branches were added to materialize.jl) — a
    # regression trap for the must-not-break invariant, not just "still runs without error."
    golden_bus_phi = [(agg.bus, agg.φ) for agg in pop]
    @test golden_bus_phi == [(b, 0.90) for b in TSODSO._load_buses(ieee13_modified(), :ieee13)]

    expected_load_scale = 0.005
    for agg in pop
        prof = generate_profiles(; seed = 42 + agg.bus, T = 24)
        expected_pdc = Float64[expected_load_scale * dd for dd in prof.demand]
        @test agg.Pdc == expected_pdc
    end
end

@testitem "ieee8500: build_population(:ieee8500_mv) total-load conservation (plan 25-04)" tags =
    [:phase25] begin
    using TSODSO

    profiles = generate_profiles(; seed = 1, T = 24)
    seed = 7
    T = 24

    f8500 = TSODSO.ieee8500_modified()
    pop8500 = build_population(:default, f8500, :ieee8500, profiles, seed)
    houses8500 = pop8500[1:(end - 4)]

    f8500mv = TSODSO.ieee8500_mv_modified()
    pop8500mv = build_population(:default, f8500mv, :ieee8500_mv, profiles, seed)
    housesmv = pop8500mv[1:(end - 4)]

    @test length(pop8500mv) == length(TSODSO.ieee8500_mv_load_buses()) + 4

    # Recovered per-bus kW magnitude: Pdc[t]/prof.demand[t] is constant across t by
    # construction, so t=1 suffices to recover the fixed real-kW magnitude.
    recovered(h) = h.Pdc[1] / generate_profiles(; seed = seed + h.bus, T = T).demand[1]

    sum8500 = sum(recovered, houses8500)
    summv = sum(recovered, housesmv)
    @test isapprox(sum8500, summv; rtol = 1e-9)
end

# ─────────────────────────────────────────────────────────────────────────────────────────
# Standalone plain-script block (VALIDATION.md quick command): replicates assertions
# (1)-(4) and (6) above as plain @test calls, runnable via `julia --project=. test/test_ieee8500.jl`
# WITHOUT TestItemRunner.
# ─────────────────────────────────────────────────────────────────────────────────────────
if abspath(PROGRAM_FILE) == @__FILE__
    @testset "ieee8500 standalone (quick command)" begin
        @testset "(1) headline fixture is radial, contiguous, single-root" begin
            feeder = TSODSO.ieee8500_modified()
            N = length(feeder.buses)
            @test length(feeder.branches) == N - 1
            @test all(i -> feeder.buses[i].id == i, 1:N)
            @test count(b -> b.is_root, feeder.buses) == 1
            @test feeder.buses[feeder.root].is_root
        end

        @testset "(2) MV-only control fixture is radial, contiguous, single-root" begin
            feeder = TSODSO.ieee8500_mv_modified()
            N = length(feeder.buses)
            @test length(feeder.branches) == N - 1
            @test all(i -> feeder.buses[i].id == i, 1:N)
            @test count(b -> b.is_root, feeder.buses) == 1
            @test feeder.buses[feeder.root].is_root
        end

        @testset "(3) per-unit magnitude sanity, both fixtures" begin
            for feeder in (TSODSO.ieee8500_modified(), TSODSO.ieee8500_mv_modified())
                for br in feeder.branches
                    @test 0 <= br.r < TSODSO.IMPEDANCE_PU_MAX
                    @test 0 <= br.x < TSODSO.IMPEDANCE_PU_MAX
                    @test 0 < br.smax < TSODSO.SMAX_PU_MAX
                end
                head = only(
                    b for b in feeder.branches if
                    b.from == feeder.root || b.to == feeder.root
                )
                @test isapprox(head.smax, 55.0; atol = 1e-6)
            end
        end

        @testset "(4) pinned corrected-transformer spot-check on a CT5 branch" begin
            feeder = TSODSO.ieee8500_modified()
            remap = TSODSO.ieee8500_relabel_map()
            ct5_pair = first(k for (k, v) in TSODSO.IEEE8500_XFMR_EDGES if v.code == "CT5")
            from_idx, to_idx = remap[ct5_pair[1]], remap[ct5_pair[2]]
            br = only(
                b for b in feeder.branches if
                (b.from == from_idx && b.to == to_idx) ||
                (b.from == to_idx && b.to == from_idx)
            )
            @test isapprox(br.r, 3.00; atol = 1e-2)
            @test isapprox(br.x, 2.72; atol = 1e-2)
        end

        @testset "(6) D-06 measured per-unit impedance spread is reported" begin
            feeder = TSODSO.ieee8500_modified()
            vals = [v for br in feeder.branches for v in (br.r, br.x) if v > 0]
            measured_min_pu = minimum(vals)
            measured_max_pu = maximum(vals)
            spread_orders = log10(measured_max_pu / measured_min_pu)
            println(
                "D-06 measured per-unit impedance spread: min=$(measured_min_pu) pu, " *
                "max=$(measured_max_pu) pu, spread=$(spread_orders) orders of magnitude",
            )
            @test spread_orders > 3.0
        end

        @testset "(7) build_population(:ieee8500) house/capacitor roll-up (plan 25-04)" begin
            profiles = generate_profiles(; seed = 1, T = 24)
            feeder = TSODSO.ieee8500_modified()
            pop = build_population(:default, feeder, :ieee8500, profiles, 7)

            @test length(pop) == length(TSODSO.ieee8500_load_nodes()) + 4

            houses = pop[1:(end - 4)]
            caps = pop[(end - 3):end]

            for h in houses
                @test length(h.devices) == 3
                @test count(d -> d isa TSODSO.Thermostatic, h.devices) == 1
                @test count(d -> d isa TSODSO.Deferrable, h.devices) == 1
                @test count(d -> d isa TSODSO.PVBattery, h.devices) == 1
            end

            T = length(profiles.demand)
            for c in caps
                @test c.Pdc == zeros(T)
                @test length(c.devices) == 1
                @test c.devices[1] isa TSODSO.FixedCapacitor
            end
        end

        @testset "(8) FixedCapacitor contribute! + DEV-05 sole-:Rq-writer invariant (plan 25-04)" begin
            model = JuMP.Model()
            ctx = TSODSO.ModelContext(model)
            T = 4
            q_nom = 0.75
            d = TSODSO.FixedCapacitor(11, q_nom)
            out = TSODSO.contribute!(d, ctx; T = T)

            @test out isa NamedTuple
            @test haskey(out, :vars) &&
                  haskey(out, :p_inject) &&
                  haskey(out, :q_inject) &&
                  haskey(out, :utility)
            @test out.vars == NamedTuple()
            @test length(out.q_inject) == T
            for t in 1:T
                @test JuMP.constant(out.q_inject[t]) == q_nom
                @test isempty(JuMP.linear_terms(out.q_inject[t]))
                @test JuMP.constant(out.p_inject[t]) == 0.0
                @test isempty(JuMP.linear_terms(out.p_inject[t]))
            end

            devices_dir = joinpath(dirname(pathof(TSODSO)), "devices")
            offenders = String[]
            for f in readdir(devices_dir; join = true)
                endswith(f, "Aggregator.jl") && continue
                isfile(f) || continue
                for line in eachline(f)
                    occursin(r"add_to_residual!.*:Rq", line) && push!(offenders, "$f: $line")
                end
            end
            @test isempty(offenders)
        end

        @testset "(9) build_population(:ieee13) byte-identical golden (plan 25-04)" begin
            profiles = generate_profiles(; seed = 1, T = 24)
            pop = build_population(:default, ieee13_modified(), :ieee13, profiles, 42)

            golden_bus_phi = [(agg.bus, agg.φ) for agg in pop]
            @test golden_bus_phi ==
                  [(b, 0.90) for b in TSODSO._load_buses(ieee13_modified(), :ieee13)]

            expected_load_scale = 0.005
            for agg in pop
                prof = generate_profiles(; seed = 42 + agg.bus, T = 24)
                expected_pdc = Float64[expected_load_scale * dd for dd in prof.demand]
                @test agg.Pdc == expected_pdc
            end
        end

        @testset "(10) build_population(:ieee8500_mv) total-load conservation (plan 25-04)" begin
            profiles = generate_profiles(; seed = 1, T = 24)
            seed = 7
            T = 24

            f8500 = TSODSO.ieee8500_modified()
            pop8500 = build_population(:default, f8500, :ieee8500, profiles, seed)
            houses8500 = pop8500[1:(end - 4)]

            f8500mv = TSODSO.ieee8500_mv_modified()
            pop8500mv = build_population(:default, f8500mv, :ieee8500_mv, profiles, seed)
            housesmv = pop8500mv[1:(end - 4)]

            @test length(pop8500mv) == length(TSODSO.ieee8500_mv_load_buses()) + 4

            recovered(h) = h.Pdc[1] / generate_profiles(; seed = seed + h.bus, T = T).demand[1]

            sum8500 = sum(recovered, houses8500)
            summv = sum(recovered, housesmv)
            @test isapprox(sum8500, summv; rtol = 1e-9)
        end
    end
end
