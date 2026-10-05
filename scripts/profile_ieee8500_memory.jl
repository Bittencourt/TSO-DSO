using TSODSO: build_feeder, build_price
# scripts/profile_ieee8500_memory.jl
#
# Staged memory profile of ONE IEEE-8500 point (staged peak-memory measurement). One stage-set per process,
# ideally under scripts/run_ieee8500_point.sh (SCRIPT=scripts/profile_ieee8500_memory.jl).
#
#   julia --project=. scripts/profile_ieee8500_memory.jl --density 0.1 --t-horizon 10 --stage 2
#
# Prints one TSV line per stage: `stage  name  VmRSS_kB  VmHWM_kB  gc_live_MB`, and upserts the rows
# into results/ieee8500_benchmark/memory_profile.csv keyed by (fixture, density, T, stage, name).
# `--fixture` defaults to `ieee8500-mv`; pass `--fixture ieee8500` to profile the full 4,875-bus feeder.
# Rows written before the `fixture` column existed were all `ieee8500-mv` runs and are backfilled as such.
# Stages: 0 after `using`; 1 feeder + population; 2 build_dso_opt (no solve); 3 first optimize! of
# the DSO model (T <= 10 ONLY); 4 after GC.gc() and again after malloc_trim; 5 after building AgrOpts.
# Read-only with respect to src/.

using DrWatson
@quickactivate "TSODSO"
using TSODSO, JuMP, CSV, DataFrames, StableRNGs

# Safe to include: the harness only runs `main` when it is the program entry point.
include(joinpath(@__DIR__, "benchmark_ieee8500.jl"))

function proc_status_kb(key::String)
    for line in eachline("/proc/self/status")
        startswith(line, key * ":") && return parse(Int, split(line)[2])
    end
    return -1
end

const ROWS = NamedTuple[]
DENSITY = 0.1
T_H = 10
FIXTURE = "ieee8500-mv"

function report(stage::Int, name::String)
    rss, hwm = proc_status_kb("VmRSS"), proc_status_kb("VmHWM")
    live = Base.gc_live_bytes() / 2^20
    println(stage, "\t", name, "\t", rss, "\t", hwm, "\t", round(live; digits = 1))
    flush(stdout)
    push!(ROWS, (; fixture = FIXTURE, density = DENSITY, T = T_H, stage = stage, name = name, VmRSS_kB = rss, VmHWM_kB = hwm, gc_live_MB = live))
    return nothing
end

function profile_main(args)
    global DENSITY = parse(Float64, parse_kv_flag(args, "--density", "0.1"))
    global T_H = parse(Int, parse_kv_flag(args, "--t-horizon", "10"))
    max_stage = parse(Int, parse_kv_flag(args, "--stage", "2"))
    fixture_str = parse_kv_flag(args, "--fixture", "ieee8500-mv")
    haskey(FIXTURE_MAP, fixture_str) || throw(ArgumentError("unknown --fixture $fixture_str"))
    global FIXTURE = fixture_str
    max_stage >= 3 && T_H > 10 &&
        throw(ArgumentError("stage >= 3 (optimize!) is only allowed with --t-horizon <= 10"))
    T_H < T_HORIZON_FLOOR && throw(ArgumentError("--t-horizon below floor $T_HORIZON_FLOOR"))
    fixture_sym = FIXTURE_MAP[fixture_str]

    println("stage\tname\tVmRSS_kB\tVmHWM_kB\tgc_live_MB")
    report(0, "after_using")
    feeder = build_feeder(fixture_sym)
    profiles = generate_profiles(; seed = _SWEEP_SEED, T = T_H)
    λ0 = build_price(:mem, T_H, nothing)
    rng = StableRNGs.LehmerRNG(_SWEEP_SEED)
    aggs = density_filtered_population(feeder, fixture_sym, profiles, _SWEEP_SEED, DENSITY, rng)
    report(1, "feeder_population")
    dso = nothing
    if max_stage >= 2
        dso = TSODSO.build_dso_opt(feeder, aggs, T_H; ρ = 100.0, λ₀ = λ0)
        report(2, "build_dso_opt")
    end
    if max_stage >= 3
        optimize!(dso.ctx.model)
        report(3, "first_optimize")
    end
    if max_stage >= 4
        GC.gc()
        report(4, "after_gc")
        ccall(:malloc_trim, Cint, (Cint,), 0)
        report(4, "after_malloc_trim")
    end
    if max_stage >= 5
        agrs = [TSODSO.build_agr_opt(a, T_H; ρ = 100.0) for a in aggs]
        report(5, "after_agr_opts")
    end

    path = joinpath(out_dir(), "memory_profile.csv")
    mkpath(out_dir())
    df = DataFrame(ROWS)
    if isfile(path)
        old = CSV.read(path, DataFrame)
        # pre-fixture-column rows were all `ieee8500-mv` (the default).
        hasproperty(old, :fixture) || (old.fixture = fill("ieee8500-mv", nrow(old)))
        k(r) = (string(r.fixture), r.density, r.T, r.stage, r.name)
        nk = Set(k(r) for r in eachrow(df))
        df = vcat(filter(r -> !(k(r) in nk), old), df; cols = :union)
    end
    select!(df, :fixture, Not(:fixture))
    CSV.write(path, df)
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    profile_main(ARGS)
end
