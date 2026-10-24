# scripts/case_a_scaling.jl
#
# POP-05 (Phase 40): the measured scaling report of the `:case_a_784` thesis population —
# a deterministic nested-prefix population LADDER (ADMM iterations + wall time per rung)
# and a subprocess-driven THREADS SWEEP of the full-population ADMM solve.
#
# usage:
#   julia --project=. -t 1 scripts/case_a_scaling.jl --mode ladder
#   julia --project=. -t 1 scripts/case_a_scaling.jl --mode threads-sweep
#   julia --project=. -t 4 scripts/case_a_scaling.jl --mode threads-sweep --threads 4
#
# Both modes are normally driven through `scripts/run_case_a_scaling.sh`, which runs ONE
# `julia -t N` PROCESS PER LEG (Threads.nthreads() is fixed at process start, so a threads
# sweep cannot run in-process) and propagates nonzero exits.
#
# Modes (--mode):
#
#   ladder        — DEFAULT_LADDER_FRACTIONS nested-prefix rungs of the SAME seeded
#                   784-house population (per-bus house prefixes via `_case_a_rung_counts`,
#                   built with the exact `_case_a_house` helpers the `:case_a_784` branch
#                   uses), each solved SERIALLY with executor-default ADMM settings
#                   (ρ = ADMM().ρ — a REQUIRED solve_admm kwarg sourced from the strategy's
#                   own default; maxiter/tolerances untouched). NO per-rung re-tuning
#                   (locked). The 1.0 rung is asserted against
#                   `build_population(:case_a_784, ...)` (prefix-construction consistency
#                   tripwire; aborts loudly on drift). One row per rung →
#                   results/case_a_population/scaling_ladder.csv
#   threads-sweep — ONE full-population solve with the executor chosen by the process's
#                   own thread count: `parallel = Threads.nthreads() > 1` (the Phase-39
#                   opt-in, kwarg-only — NO Scenario seam, scenario identity stays
#                   executor-blind per PAR-04). With `parallel = true` on a 1-thread
#                   runtime solve_admm THROWS (fail-loud) — this script surfaces the error
#                   and exits nonzero; it NEVER degrades to serial. The `executor` column
#                   records which executor actually ran (serial when the `parallel` kwarg
#                   was false, parallel when true) so rows are self-describing. One row →
#                   results/case_a_population/threads_sweep.csv
#
# CSV contract: rows are UPSERTED keyed on their provenance identity (mode, threads,
# rung/fraction, seed, t_horizon) with `cols = :union` — re-runs replace their own rows and
# never drop others. Every row stamps julia_version, threads, blas_threads, seed and
# t_horizon. A kill mid-run leaves the rows already captured — a kill is a MEASURED
# OUTCOME, not a missing run (honesty policy). A `:budget_exceeded` status (the
# --time-limit-s wall-clock budget) is likewise a RECORDED outcome: welfare/exact_maxgap
# land as missing cells per the solve_admm contract (a budget stop carries NO certified
# price), never dropped and never retried into a pass.
#
# Case A constants (scripts/thesis_caseA.jl): T = 24, SEED = 42, :ieee13, :mem prices,
# profiles seed = sub_seed(SEED, :profiles), population seed = sub_seed(SEED, :population).
#
# Regenerate the committed artifacts:
#   scripts/run_case_a_scaling.sh

using DrWatson
@quickactivate "TSODSO"
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
    build_population,
    build_price,
    generate_profiles,
    solve_admm,
    sub_seed
using CSV
using DataFrames
using LinearAlgebra: BLAS

const SEED = 42
const FEEDER_SYM = :ieee13
const PRICE_SYM = :mem
const OUT_DIR = joinpath(projectdir(), "results", "case_a_population")
const LADDER_CSV = joinpath(OUT_DIR, "scaling_ladder.csv")
const SWEEP_CSV = joinpath(OUT_DIR, "threads_sweep.csv")

# The population ladder's rungs (agent's discretion per CONTEXT; ~6 rungs from small to
# 784). NESTED prefixes of the same seeded population — fraction 1.0 is exactly the full
# 784-house population. 1/78 selects 1 house per bus (the smallest non-empty rung).
const DEFAULT_LADDER_FRACTIONS = (1 / 78, 0.125, 0.25, 0.5, 0.75, 1.0)

# solve_admm's `ρ` is a REQUIRED kwarg (no default in the signature), so the script passes
# the executor's own default — `ADMM().ρ` (strategies.jl: ρ = 100.0) — IDENTICALLY at every
# rung and leg. This is the locked no-re-tuning configuration, not a per-rung choice.
rho_executor_default() = ADMM().ρ

# ---- kv-flag parsing (benchmark_ieee8500.jl conventions) ------------------------------------

function parse_kv_flag(args, flag::String, default)
    idx = findfirst(==(flag), args)
    idx === nothing && return default
    idx == length(args) && throw(ArgumentError("$flag requires a value (none given)"))
    return args[idx + 1]
end

parse_args!(args) = (
    mode = let m = parse_kv_flag(args, "--mode", "ladder")
        (m in ("ladder", "threads-sweep")) || throw(
            ArgumentError(
                "--mode must be \"ladder\" or \"threads-sweep\" (got $(repr(m)))",
            ),
        )
        m
    end,
    T_H = let T = parse(Int, parse_kv_flag(args, "--t-horizon", "24"))
        T >= 1 || throw(ArgumentError("--t-horizon must be ≥ 1 (got $T)"))
        T
    end,
    time_limit_s = let tl = parse(Float64, parse_kv_flag(args, "--time-limit-s", "1800.0"))
        tl > 0 ||
            throw(ArgumentError("--time-limit-s must be > 0 (got $tl) — the honest " *
                                ":budget_exceeded path needs a finite positive budget"))
        tl
    end,
    threads_declared = let s = parse_kv_flag(args, "--threads", nothing)
        s === nothing ? nothing : parse(Int, s)
    end,
)

# ---- provenance + CSV upsert ----------------------------------------------------------------

num_or_missing(x) = x === nothing ? missing : x

"""
    upsert_row(path, row::NamedTuple; key) -> nothing

Append-or-replace `row` in the CSV at `path`, keyed on `key` (a tuple of column names):
existing rows whose key matches the new row's are REPLACED, all other rows are kept
(`cols = :union` merges column sets across schema evolution). Header is written on create.
Re-runs replace their own rows and never drop others' rows; a kill mid-run leaves the rows
already captured (honesty policy).
"""
function upsert_row(path::String, row::NamedTuple; key::NTuple{N, Symbol} where {N})
    mkpath(OUT_DIR)
    new = DataFrame([row])
    df = if isfile(path)
        old = CSV.read(path, DataFrame)
        keyof(r) = Tuple(r[c] for c in key)
        new_keys = Set(keyof(r) for r in eachrow(new))
        keep = filter(r -> !(keyof(r) in new_keys), old)
        vcat(keep, new; cols = :union)
    else
        new
    end
    CSV.write(path, df)
    return nothing
end

# ---- ladder mode ----------------------------------------------------------------------------

"""
    case_a_houses_by_bus(feeder, T) -> Dict{Int, Vector{Aggregator}}

The FULL population's per-bus house structure at horizon `T`, built with the EXACT helpers
the `:case_a_784` branch of `build_population` uses (`_load_buses`, `_case_a_house_counts`,
`_case_a_house` with the module's `_IEEE13_*` scales and `_CASE_A_PV_FRACTION`), so a
nested prefix of these houses rolls up into a genuine prefix of the built population.
"""
function case_a_houses_by_bus(feeder, T::Int)
    buses = _load_buses(feeder, FEEDER_SYM)
    counts = _case_a_house_counts(buses, _CASE_A_TOTAL_HOUSES)
    s_pop = sub_seed(SEED, :population)
    return Dict{Int, Vector{Aggregator}}(
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
end

# `Aggregator` (and the device structs) are immutable with Vector fields, so the default
# `==` compares those fields by REFERENCE — two independently built but bit-identical
# populations are `==`-false (documented in test/test_population_case_a.jl's header). The
# 1.0-rung tripwire therefore asserts STRUCTURAL equality: field-wise equality on every
# device (Vector fields compare element-wise under `==`) and element-wise equality on
# `Pdc` — the honest reading of the plan's "compare == against build_population output".
function struct_fieldwise_equal(x, y)
    typeof(x) === typeof(y) || return false
    for n in fieldnames(typeof(x))
        getfield(x, n) == getfield(y, n) || return false
    end
    return true
end

function aggregators_structurally_equal(x, y)
    x.bus == y.bus || return false
    x.φ == y.φ || return false
    x.Pdc == y.Pdc || return false
    length(x.devices) == length(y.devices) || return false
    return all(struct_fieldwise_equal(dx, dy) for (dx, dy) in zip(x.devices, y.devices))
end

function ladder_main(T_H::Int, time_limit_s::Real)
    # BLAS pinned to 1 for row-to-row comparability (the threaded executor of the sweep
    # re-pins/restores BLAS itself; the ladder is serial-only).
    BLAS.set_num_threads(1)
    feeder = build_feeder(FEEDER_SYM)
    profiles = generate_profiles(; seed = sub_seed(SEED, :profiles), T = T_H)
    λ₀ = build_price(PRICE_SYM, T_H, nothing)
    pf = ConvexBranchFlow()
    ρ = rho_executor_default()
    houses_by_bus = case_a_houses_by_bus(feeder, T_H)
    buses = sort!(collect(keys(houses_by_bus)))
    counts = _case_a_house_counts(buses, _CASE_A_TOTAL_HOUSES)

    println(
        "case_a_scaling ladder: T=$T_H, seed=$SEED, ρ=$ρ (executor default), " *
        "time_limit_s=$time_limit_s, $(length(DEFAULT_LADDER_FRACTIONS)) rungs",
    )
    for (i, fraction) in enumerate(DEFAULT_LADDER_FRACTIONS)
        rung_counts = _case_a_rung_counts(counts, fraction)
        # Nested prefix per bus (house_index ≤ m_b), rolled up EXACTLY as the
        # `:case_a_784` branch does: devices concatenated, Pdc summed.
        aggs_rung = Aggregator[
            let hs = houses_by_bus[bus][1:rung_counts[bus]]
                Aggregator(
                    bus,
                    0.90,
                    reduce(vcat, [h.devices for h in hs]),
                    reduce(+, [h.Pdc for h in hs]),
                )
            end for bus in buses
        ]
        houses_actual = sum(values(rung_counts))
        if fraction >= 1
            full_ref = build_population(
                :case_a_784,
                feeder,
                FEEDER_SYM,
                profiles,
                sub_seed(SEED, :population),
            )
            length(aggs_rung) == length(full_ref) &&
                all(
                    aggregators_structurally_equal(r, f) for
                    (r, f) in zip(aggs_rung, full_ref)
                ) || error(
                    "ladder 1.0-fraction rung does NOT match build_population(:case_a_784, ...) " *
                    "— the prefix construction drifted from the builder (aborting loudly)",
                )
            println(
                "  ✓ 1.0-fraction rung matches the build_population roll-up " *
                "(structural check, $houses_actual houses)",
            )
        end

        println(
            "rung $i: fraction=$fraction, houses=$houses_actual, " *
            "aggregators=$(length(aggs_rung)) — solving (serial, executor defaults)...",
        )
        flush(stdout)
        wall_s = @elapsed r = solve_admm(
            feeder,
            pf,
            aggs_rung;
            T = T_H,
            λ₀ = λ₀,
            ρ = ρ,
            time_limit_s = time_limit_s,
        )
        row = (
            mode = "ladder",
            rung_label = "rung$i",
            fraction = Float64(fraction),
            julia_version = string(VERSION),
            threads = Threads.nthreads(),
            blas_threads = BLAS.get_num_threads(),
            seed = SEED,
            t_horizon = T_H,
            houses_actual = houses_actual,
            aggregators = length(aggs_rung),
            iters = Int(r.iters),
            status = string(r.status),
            welfare = num_or_missing(r.welfare),
            exact_maxgap = num_or_missing(r.exact_maxgap),
            wall_s = wall_s,
        )
        upsert_row(
            LADDER_CSV,
            row;
            key = (:mode, :threads, :fraction, :seed, :t_horizon),
        )
        println(
            "  → iters=$(row.iters) status=$(row.status) wall_s=$(round(wall_s; digits = 2)) " *
            "recorded (budget_exceeded rows carry missing welfare/exact_maxgap by contract)",
        )
        flush(stdout)
    end
    println("ladder complete → $LADDER_CSV")
    return nothing
end

# ---- threads-sweep mode ---------------------------------------------------------------------

function sweep_main(T_H::Int, time_limit_s::Real, threads_declared::Union{Nothing, Int})
    nthreads_proc = Threads.nthreads()
    # Fail loud on a driver/leg mismatch: thread count is fixed at PROCESS start, so a
    # --threads N claim that disagrees with the running process is a misuse, not a knob.
    if threads_declared !== nothing && threads_declared != nthreads_proc
        throw(
            ArgumentError(
                "--threads $threads_declared does not match this process's " *
                "Threads.nthreads() = $nthreads_proc (thread count is fixed at process " *
                "start; run the leg as `julia --project=. -t $threads_declared ...`)",
            ),
        )
    end
    parallel = nthreads_proc > 1
    executor = parallel ? "parallel" : "serial"
    # BLAS pinned to 1 before the solve for row-to-row comparability; the threaded executor
    # itself pins/restores BLAS on every exit path, so the restored value is this pin (1).
    BLAS.set_num_threads(1)
    feeder = build_feeder(FEEDER_SYM)
    profiles = generate_profiles(; seed = sub_seed(SEED, :profiles), T = T_H)
    λ₀ = build_price(PRICE_SYM, T_H, nothing)
    aggs = build_population(
        :case_a_784,
        feeder,
        FEEDER_SYM,
        profiles,
        sub_seed(SEED, :population),
    )
    println(
        "case_a_scaling threads-sweep: T=$T_H, seed=$SEED, julia threads=$nthreads_proc, " *
        "executor=$executor, houses=$_CASE_A_TOTAL_HOUSES, time_limit_s=$time_limit_s — solving...",
    )
    flush(stdout)
    # Kwarg-only direct call (NO Scenario seam — locked); `parallel = true` on a 1-thread
    # runtime THROWS (solve_admm fail-loud guard) and this script lets it propagate — the
    # process exits nonzero, never degrading to serial.
    wall_s = @elapsed r = solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = T_H,
        λ₀ = λ₀,
        ρ = rho_executor_default(),
        time_limit_s = time_limit_s,
        parallel = parallel,
    )
    row = (
        mode = "threads-sweep",
        julia_version = string(VERSION),
        threads = nthreads_proc,
        blas_threads = BLAS.get_num_threads(),
        executor = executor,
        seed = SEED,
        t_horizon = T_H,
        houses = _CASE_A_TOTAL_HOUSES,
        iters = Int(r.iters),
        status = string(r.status),
        welfare = num_or_missing(r.welfare),
        exact_maxgap = num_or_missing(r.exact_maxgap),
        wall_s = wall_s,
    )
    upsert_row(SWEEP_CSV, row; key = (:mode, :threads, :seed, :t_horizon))
    println(
        "  → iters=$(row.iters) status=$(row.status) wall_s=$(round(wall_s; digits = 2)) " *
        "executor=$executor recorded → $SWEEP_CSV",
    )
    return nothing
end

# ---- entry -----------------------------------------------------------------------------------

function scaling_main(args)
    parsed = parse_args!(args)
    println(
        "case_a_scaling: mode=$(parsed.mode) t_horizon=$(parsed.T_H) " *
        "time_limit_s=$(parsed.time_limit_s) threads=$(Threads.nthreads()) " *
        "blas=$(BLAS.get_num_threads()) (pinning BLAS to 1)",
    )
    if parsed.mode == "ladder"
        ladder_main(parsed.T_H, parsed.time_limit_s)
    else
        sweep_main(parsed.T_H, parsed.time_limit_s, parsed.threads_declared)
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    scaling_main(ARGS)
end
