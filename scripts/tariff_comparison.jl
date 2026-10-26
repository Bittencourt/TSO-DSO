# scripts/tariff_comparison.jl
#
# SETL-02/05 (Phase 41): the committed tariff-comparison measurement — ONE DADP run per
# mode, settled and re-dispatched per tariff (`:dadp` / `:flat` / `:tou` / `:fit`) on the
# SAME feeder + population via `TSODSO.compare_tariffs`, with per-leg welfare, ledger
# totals, AC feasibility statuses, equity metrics on bills/surplus, and rebound.
#
# usage:
#   julia --project=. scripts/tariff_comparison.jl --mode ieee13-ground
#   julia --project=. scripts/tariff_comparison.jl --mode case-a-784 [--time-limit-s 3600]
#
# Modes (--mode):
#
#   ieee13-ground  DEFAULT. The fast smoke leg: `build_population(:default, ...)` — one
#                  aggregator per load bus on the modified IEEE-13 feeder, T = 24, the
#                  pinned :mem price profile, engine :centralized. Bills settle at BUS
#                  granularity (the one-aggregator-per-bus shape IS the household
#                  granularity here). Seconds-to-minutes wall time.
#   case-a-784     THE deliverable: the thesis-scale 784-house population. Thesis
#                  constants exactly as `scripts/thesis_caseA.jl` / the
#                  `scripts/case_a_scaling.jl` header restate them: T = 24, SEED = 42,
#                  profiles seed = sub_seed(42, :profiles), population seed =
#                  sub_seed(42, :population), :mem prices; engine :admm with
#                  ρ = ADMM().ρ — the LOCKED no-re-tuning configuration (the executor
#                  default; tolerances/gates untouched). The 784 houses are rebuilt with
#                  the exact `_case_a_house` primitives in `case_a_household_map` order
#                  (bus-major, house-index ascending — the alignment is asserted) so the
#                  per-house attribution cannot drift from the population. LONG-RUNNING:
#                  the ADMM leg alone is ~10+ min per the Phase-40 measurement.
#
# CSV contract (the case_a_scaling idiom): rows are UPSERTED keyed on their provenance
# identity (mode, tariff / unit_id / group, seed, t_horizon) with `cols = :union` —
# re-runs replace their own rows and never drop others'. Every row stamps julia_version,
# threads, blas_threads, seed and t_horizon (the runner stamps the same provenance; the
# script adds `seed` and `mode`). A kill mid-run leaves the rows already captured — a
# kill is a MEASURED OUTCOME, not a missing run (honesty policy).
#
# Honesty policy for per-leg statuses: `compare_tariffs` records every leg as a row,
# never dropped. A solver-outcome failure of the DADP run itself (a maxiter stall
# `ConvergenceError`, a certificate refusal `CertificateError` — the EXPECTED full-
# population outcome at executor defaults per the Phase-40 measurement — a solver
# failure `SolveFailedError`, or the ADMM non-`:converged` typed guard
# `UnconvergedAdmmError` a budget stop produces) is RECORDED by this script as its own
# status row (tariff = "(run)", certified values missing, iterations from the error
# where carried) — never retried into a pass, never re-tuned (ρ = ADMM().ρ, no tol
# changes; a refusal is answered upstream by the bounded solver-precision ladder, not
# by this artifact). Misuse errors (bad args, shape guards) still propagate and exit
# nonzero.
#
# Case A constants (scripts/thesis_caseA.jl): T = 24, SEED = 42, :ieee13, :mem prices,
# profiles seed = sub_seed(SEED, :profiles), population seed = sub_seed(SEED, :population).
#
# Outputs (results/settlement_comparison/):
#   tariff_comparison.csv   — one row per tariff per mode (+ "(run)" status rows)
#   household_bills.csv     — per-household (or per-bus) bill/surplus rows
#   equity_breakouts.csv    — per-group equity rows (pv_group / bus / load tercile)
#
# Regenerate the committed artifacts:
#   julia --project=. scripts/tariff_comparison.jl --mode ieee13-ground
#   julia --project=. scripts/tariff_comparison.jl --mode case-a-784   # long-running

using DrWatson
@quickactivate "TSODSO"
using TSODSO
using TSODSO:
    ADMM,
    CertificateError,
    ConvergenceError,
    ConvexBranchFlow,
    SolveFailedError,
    UnconvergedAdmmError,
    _CASE_A_PV_FRACTION,
    _CASE_A_TOTAL_HOUSES,
    _IEEE13_DEV_SCALE,
    _IEEE13_LOAD_SCALE,
    _IEEE13_PV_SCALE,
    _case_a_house,
    _case_a_house_counts,
    _load_buses,
    build_feeder,
    build_population,
    build_price,
    case_a_household_map,
    compare_tariffs,
    generate_profiles,
    sub_seed
using CSV
using DataFrames: DataFrame, eachrow
using LinearAlgebra: BLAS

const SEED_GROUND = 20260718   # the ground-fixture regression seed (IEEE13Fixtures') — the
# smoke mode's measurement configuration. NOT the thesis seed: the seed-42 default
# population's centralized run is REFUSED at the battery-complementarity certificate on
# this runtime (bus 5, t=16 — recorded as its own honest "(run)" status row in the CSV,
# the Phase-40 refusal class at executor defaults); the smoke leg exists to exercise the
# comparison pipeline, and 20260718 is the seed the ground fixture was calibrated and
# validated with. The case-a-784 mode keeps the LOCKED thesis seed below.
const SEED_CASE_A = 42
const FEEDER_SYM = :ieee13
const PRICE_SYM = :mem
const OUT_DIR = joinpath(projectdir(), "results", "settlement_comparison")
const SUMMARY_CSV = joinpath(OUT_DIR, "tariff_comparison.csv")
const BILLS_CSV = joinpath(OUT_DIR, "household_bills.csv")
const BREAKOUTS_CSV = joinpath(OUT_DIR, "equity_breakouts.csv")

# ---- kv-flag parsing (case_a_scaling.jl conventions) -----------------------------------------

function parse_kv_flag(args, flag::String, default)
    idx = findfirst(==(flag), args)
    idx === nothing && return default
    idx == length(args) && throw(ArgumentError("$flag requires a value (none given)"))
    return args[idx + 1]
end

parse_args!(args) = (
    mode = let m = parse_kv_flag(args, "--mode", "ieee13-ground")
        (m in ("ieee13-ground", "case-a-784")) || throw(
            ArgumentError(
                "--mode must be \"ieee13-ground\" or \"case-a-784\" (got $(repr(m)))",
            ),
        )
        m
    end,
    T_H = let T = parse(Int, parse_kv_flag(args, "--t-horizon", "24"))
        T >= 1 || throw(ArgumentError("--t-horizon must be ≥ 1 (got $T)"))
        T
    end,
    time_limit_s = let tl =
            parse(Float64, parse_kv_flag(args, "--time-limit-s", "3600.0"))
        tl > 0 || throw(
            ArgumentError(
                "--time-limit-s must be > 0 (got $tl) — the honest " *
                "unconverged-stop path needs a finite positive budget",
            ),
        )
        tl
    end,
    seed = let s = parse_kv_flag(args, "--seed", nothing)
        s === nothing ? nothing : parse(Int, s)   # nothing ⇒ per-mode default (mode_seed)
    end,
)

# Per-mode seed defaults: the smoke leg uses the ground-fixture regression seed
# (SEED_GROUND), the thesis-scale leg the LOCKED thesis seed (SEED_CASE_A). A --seed
# override applies to either.
mode_seed(mode::String, seed::Union{Nothing, Int}) =
    seed !== nothing ? seed : (mode == "ieee13-ground" ? SEED_GROUND : SEED_CASE_A)

# ---- provenance + CSV upsert (case_a_scaling.jl idiom) ---------------------------------------

"""
    run_compare_outcome(compare) -> (; ok, res, status, message, iters)

Run ONE `compare_tariffs` call (as a thunk) and return its HONEST outcome. Solver-outcome
failures of the DADP run are RECORDED OUTCOMES per the honesty policy — a maxiter stall
(`ConvergenceError`), a certificate refusal (`CertificateError`), a solver failure
(`SolveFailedError`) and the ADMM non-`:converged` guard (the typed
`UnconvergedAdmmError` `settlement_input` throws — what a wall-clock budget stop
produces) each become a status row (iterations from the error's own field, -1 sentinel
when it carries none; certified values missing). Anything else (argument misuse, a
genuine bug) PROPAGATES and exits nonzero.
"""
function run_compare_outcome(compare::Function)
    local res
    local status::String
    local message::String
    local iters
    try
        res = compare()
        return (; ok = true, res, status = "ok", message = "", iters = missing)
    catch err
        if err isa ConvergenceError || err isa CertificateError || err isa SolveFailedError
            status = "error:" * string(nameof(typeof(err)))
            message = first(string(err.msg), 400)
            iters = err.iterations === nothing ? -1 : Int(err.iterations)
        elseif err isa UnconvergedAdmmError
            # the ADMM adapter's typed non-`:converged` refusal — the recorded shape of
            # a wall-clock budget stop (a budget stop carries NO certified price).
            # Caught BY TYPE: an unrelated ArgumentError that merely mentions
            # ":converged" propagates and exits nonzero (the WR-05 discipline).
            status = "error:unconverged_admm"
            message = first(string(err.msg), 400)
            iters = missing
        else
            rethrow()
        end
        return (;
            ok = false,
            res = nothing,
            status = status,
            message = message,
            iters = iters,
        )
    end
end

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

provenance_row(T_H::Int, seed::Int) = (
    julia_version = string(VERSION),
    threads = Threads.nthreads(),
    blas_threads = BLAS.get_num_threads(),
    seed = seed,
    t_horizon = T_H,
)

# Committed-CSV hygiene: the status `notes` carry solver messages that legitimately
# contain newlines; the artifact CSVs are LINE-ORIENTED by repo convention (the docs
# pages' minimal readers split per line), so embedded newlines are flattened to "; "
# and double quotes to single — the message CONTENT is preserved verbatim otherwise.
flatten_note(s) = replace(replace(String(s), '\n' => "; ", '\r' => ""), '"' => "'")

"""
    ensure_schema(path, cols) -> nothing

Guarantee the CSV exists (header-only when no row was ever captured): an empty table is
the HONEST content of a mode whose run-level failure left zero certified rows (a missing
FILE would read as "the measurement never ran"; a header-only table reads as "it ran and
certified nothing").
"""
function ensure_schema(path::String, cols::Vector{Symbol})
    mkpath(OUT_DIR)
    isfile(path) || CSV.write(path, DataFrame([Any[] for _ in cols], cols))
    return nothing
end

const SUMMARY_COLS = Symbol[
    :mode,
    :tariff,
    :engine,
    :status,
    :notes,
    :welfare,
    :total_payments,
    :fairness_total,
    :merchandising_surplus,
    :dso_total,
    :aggregators_total,
    :wholesale_total,
    :feasibility_status,
    :n_thermal_violations,
    :n_voltage_violations,
    :max_overload_ratio,
    :batt_ok,
    :batt_refused,
    :batt_not_checked,
    :gini_bills,
    :theil_bills,
    :theil_n_excluded_bills,
    :atkinson_bills,
    :atkinson_n_excluded_bills,
    :palma_bills,
    :gini_surplus,
    :theil_surplus,
    :theil_n_excluded_surplus,
    :atkinson_surplus,
    :atkinson_n_excluded_surplus,
    :palma_surplus,
    :rebound_amount,
    :rebound_ratio,
    :bills_granularity,
    :julia_version,
    :threads,
    :blas_threads,
    :seed,
    :t_horizon,
]
const BILLS_COLS = Symbol[
    :mode,
    :tariff,
    :unit_id,
    :bus,
    :granularity,
    :bill,
    :surplus,
    :pv_group,
    :load_tercile,
    :julia_version,
    :threads,
    :blas_threads,
    :seed,
    :t_horizon,
]
const BREAKOUTS_COLS = Symbol[
    :mode,
    :tariff,
    :grouping,
    :group,
    :metric_kind,
    :n,
    :gini,
    :theil,
    :theil_n_excluded,
    :atkinson,
    :atkinson_n_excluded,
    :palma,
    :julia_version,
    :threads,
    :blas_threads,
    :seed,
    :t_horizon,
]

# All three artifacts EXIST regardless of outcome (header-only = certified nothing).
# Called BEFORE the run-failure branch in both modes: a "(run)" status row must never
# ship without its sibling header-only tables (the docs readers open all three
# unconditionally; a missing FILE would read as "the measurement never ran" — WR-04).
function ensure_all_schemas()
    ensure_schema(SUMMARY_CSV, SUMMARY_COLS)
    ensure_schema(BILLS_CSV, BILLS_COLS)
    ensure_schema(BREAKOUTS_CSV, BREAKOUTS_COLS)
    return nothing
end

"""
    write_compare_results(res, mode_name, T_H, seed) -> nothing

Upsert the runner's three committed tables row by row, each stamped with the script-side
provenance (`seed`, `mode`) beside the runner's own stamp (`julia_version`, `threads`,
`blas_threads`, `t_horizon`).
"""
function write_compare_results(res, mode_name::String, T_H::Int, seed::Int)
    for r in eachrow(res.summary)
        row = NamedTuple(r)
        row = haskey(row, :notes) ? merge(row, (notes = flatten_note(row.notes),)) : row
        upsert_row(
            SUMMARY_CSV,
            merge(row, (mode = mode_name,), provenance_row(T_H, seed));
            key = (:mode, :tariff, :seed, :t_horizon),
        )
    end
    for r in eachrow(res.household_bills)
        upsert_row(
            BILLS_CSV,
            merge(NamedTuple(r), (mode = mode_name,), provenance_row(T_H, seed));
            key = (:mode, :tariff, :unit_id, :seed, :t_horizon),
        )
    end
    for r in eachrow(res.equity_breakouts)
        upsert_row(
            BREAKOUTS_CSV,
            merge(NamedTuple(r), (mode = mode_name,), provenance_row(T_H, seed));
            key = (:mode, :tariff, :grouping, :group, :metric_kind, :seed, :t_horizon),
        )
    end
    return nothing
end

"""
    write_run_status_row(outcome, mode_name, engine, T_H, seed) -> nothing

The DADP-run-level honest status row (tariff = "(run)"): certified values missing, the
error type in `status`, the message truncated into `notes`, iterations carried when the
error has them.
"""
function write_run_status_row(
    outcome,
    mode_name::String,
    engine::String,
    T_H::Int,
    seed::Int,
)
    row = merge(
        (
            mode = mode_name,
            tariff = "(run)",
            engine = engine,
            status = outcome.status,
            notes = flatten_note(outcome.message),
            welfare = missing,
            total_payments = missing,
            merchandising_surplus = missing,
            feasibility_status = "not_run",
            iters = outcome.iters,
        ),
        provenance_row(T_H, seed),
    )
    upsert_row(SUMMARY_CSV, row; key = (:mode, :tariff, :seed, :t_horizon))
    return nothing
end

# ---- ieee13-ground mode ----------------------------------------------------------------------

function ground_main(T_H::Int, seed::Int)
    # BLAS pinned to 1 for row-to-row comparability (the case_a_scaling discipline).
    BLAS.set_num_threads(1)
    feeder = build_feeder(FEEDER_SYM)
    profiles = generate_profiles(; seed = sub_seed(seed, :profiles), T = T_H)
    λ₀ = build_price(PRICE_SYM, T_H, nothing)
    aggs = build_population(
        :default,
        feeder,
        FEEDER_SYM,
        profiles,
        sub_seed(seed, :population),
    )

    println(
        "tariff_comparison ieee13-ground: T=$T_H, seed=$seed, engine=:centralized, " *
        "aggregators=$(length(aggs)) (BLAS pinned to 1) — comparing...",
    )
    flush(stdout)
    wall_s = @elapsed outcome = run_compare_outcome() do
        compare_tariffs(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = T_H,
            λ₀ = λ₀,
            engine = :centralized,
        )
    end
    ensure_all_schemas()
    if !outcome.ok
        write_run_status_row(outcome, "ieee13-ground", "centralized", T_H, seed)
        println(
            "  → DADP run RECORDED as $(outcome.status) (a measured outcome, never a dropped " *
            "leg) → $SUMMARY_CSV",
        )
        flush(stdout)
        return nothing
    end
    write_compare_results(outcome.res, "ieee13-ground", T_H, seed)
    for r in eachrow(outcome.res.summary)
        println(
            "  → $(r.tariff): welfare=$(r.welfare) payments=$(r.total_payments) " *
            "feas=$(r.feasibility_status) status=$(r.status)",
        )
    end
    println(
        "ieee13-ground complete in $(round(wall_s; digits = 2)) s → " *
        "$SUMMARY_CSV, $BILLS_CSV, $BREAKOUTS_CSV",
    )
    return nothing
end

# ---- case-a-784 mode -------------------------------------------------------------------------

"""
    case_a_houses_flat(feeder, T, seed) -> Vector{Aggregator}

The FULL 784-house population's per-house `Aggregator`s, built with the EXACT
`_case_a_house` primitives the `:case_a_784` branch of `build_population` uses, in
`case_a_household_map` order (bus-major, house-index ascending) — so `houses[k]`
corresponds to `map_rows[k]` 1:1 and the per-house attribution cannot drift from the
population (the alignment is asserted against the map before any solve).
"""
function case_a_houses_flat(feeder, T::Int, seed::Int)
    buses = _load_buses(feeder, FEEDER_SYM)
    counts = _case_a_house_counts(buses, _CASE_A_TOTAL_HOUSES)
    s_pop = sub_seed(seed, :population)
    houses = Aggregator[]
    for bus in buses, h in 1:counts[bus]
        push!(
            houses,
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
            ),
        )
    end
    return houses
end

function caseA_main(T_H::Int, seed::Int, time_limit_s::Real)
    BLAS.set_num_threads(1)
    feeder = build_feeder(FEEDER_SYM)
    profiles = generate_profiles(; seed = sub_seed(seed, :profiles), T = T_H)
    λ₀ = build_price(PRICE_SYM, T_H, nothing)
    ρ = ADMM().ρ   # the executor default — the locked no-re-tuning configuration
    aggs = build_population(
        :case_a_784,
        feeder,
        FEEDER_SYM,
        profiles,
        sub_seed(seed, :population),
    )
    map_rows = case_a_household_map(feeder, FEEDER_SYM, seed)
    houses = case_a_houses_flat(feeder, T_H, seed)
    # Drift tripwire: the per-house reconstruction must match the pure map exactly.
    length(houses) == length(map_rows) || error(
        "case-a-784: $(length(houses)) reconstructed houses vs $(length(map_rows)) map rows " *
        "— the reconstruction drifted from case_a_household_map (aborting loudly)",
    )
    all(houses[k].bus == map_rows[k].bus for k in eachindex(houses)) || error(
        "case-a-784: house/map bus assignment mismatch — the reconstruction drifted " *
        "from case_a_household_map (aborting loudly)",
    )

    println(
        "tariff_comparison case-a-784: T=$T_H, seed=$seed, engine=:admm, ρ=$ρ (executor " *
        "default, NO re-tuning), houses=$(length(houses)), aggregators=$(length(aggs)), " *
        "time_limit_s=$time_limit_s (BLAS pinned to 1) — comparing (LONG-RUNNING)...",
    )
    flush(stdout)
    wall_s = @elapsed outcome = run_compare_outcome() do
        compare_tariffs(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = T_H,
            λ₀ = λ₀,
            engine = :admm,
            ρ = ρ,
            houses = houses,
            map_rows = map_rows,
            time_limit_s = time_limit_s,
        )
    end
    ensure_all_schemas()
    if !outcome.ok
        write_run_status_row(outcome, "case-a-784", "admm", T_H, seed)
        println(
            "  → ADMM run RECORDED as $(outcome.status) iters=$(outcome.iters) — the expected " *
            "executor-default outcome at the full population (Phase-40 precedent: the final " *
            "battery-complementarity certificate refuses; a status row IS the artifact, " *
            "never re-tuned) → $SUMMARY_CSV",
        )
        flush(stdout)
        return nothing
    end
    write_compare_results(outcome.res, "case-a-784", T_H, seed)
    for r in eachrow(outcome.res.summary)
        println(
            "  → $(r.tariff): welfare=$(r.welfare) payments=$(r.total_payments) " *
            "feas=$(r.feasibility_status) status=$(r.status) granularity=$(r.bills_granularity)",
        )
    end
    println(
        "case-a-784 complete in $(round(wall_s; digits = 2)) s → " *
        "$SUMMARY_CSV, $BILLS_CSV, $BREAKOUTS_CSV",
    )
    return nothing
end

# ---- entry -----------------------------------------------------------------------------------

function comparison_main(args)
    parsed = parse_args!(args)
    seed = mode_seed(parsed.mode, parsed.seed)
    println(
        "tariff_comparison: mode=$(parsed.mode) t_horizon=$(parsed.T_H) seed=$seed " *
        "time_limit_s=$(parsed.time_limit_s) threads=$(Threads.nthreads()) " *
        "blas=$(BLAS.get_num_threads()) (pinning BLAS to 1)",
    )
    if parsed.mode == "ieee13-ground"
        ground_main(parsed.T_H, seed)
    else
        caseA_main(parsed.T_H, seed, parsed.time_limit_s)
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    comparison_main(ARGS)
end
