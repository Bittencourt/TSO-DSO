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
#   julia --project=. scripts/tariff_comparison.jl --mode ieee13-ground --flex-market
#   julia --project=. scripts/tariff_comparison.jl --mode ieee123 [--flex-market]
#   julia --project=. scripts/tariff_comparison.jl --mode ieee123-default
#   julia --project=. scripts/tariff_comparison.jl --mode <mode> --record-timeout <S>
#
# Flags:
#
#   --flex-market     Boolean (no value). Adds the flexibility-market legs of
#                     `flex_markets_for(mode)` to the comparison (`compare_tariffs(...;
#                     flex_market)`). Allowed on ieee13-ground, ieee123 and ieee123-default;
#                     refused on case-a-784 (a houses run cannot carry flex legs).
#   --record-timeout S  Writes the mode's "(run)" row with status "timeout", run_wall_s = S
#                     and notes "stopped after S s wall", WITHOUT solving: the honest record
#                     of a run that was stopped or killed before it finished. The mode's
#                     earlier rows of the same seed and horizon are deleted first.
#                     On ieee13-ground the two runs are recorded separately:
#                       --record-timeout S               a stopped BASE run: every row of the
#                                                        mode is deleted, flex rows included.
#                       --record-timeout S --flex-market a stopped FLEX run: only the mode's
#                                                        flex rows are deleted and the status
#                                                        row is "flex_(run)"; the committed
#                                                        base rows (dadp, flat, tou, fit and
#                                                        their bill and breakout rows) stay.
#                                                        Refused when there is no committed
#                                                        dadp row to clear against.
#
# Modes (--mode):
#
#   ieee13-ground  DEFAULT. The fast smoke leg: `build_population(:default, ...)` — one
#                  aggregator per load bus on the modified IEEE-13 feeder, T = 24, the
#                  pinned :mem price profile, engine :centralized. Bills settle at BUS
#                  granularity (the one-aggregator-per-bus shape IS the household
#                  granularity here). Seconds-to-minutes wall time.
#                  With --flex-market (the flexibility-market measurement):
#                  the run also clears 8 flex legs (flat baseline x uniform/pay-as-bid x
#                  beta in {0, 0.05, 0.10}, plus the TOU baseline under both rules at beta
#                  0). Before ANY write, the in-run dadp row must reproduce the committed
#                  dadp row (welfare, aggregators_total, status, compared after a CSV round
#                  trip, so bitwise); on any difference the script errors and writes
#                  nothing. Only the rows whose tariff starts with "flex_" are upserted
#                  (summary, bills, rebound): the committed base rows stay as recorded.
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
#   ieee123        The modified IEEE-123 feeder with the certified test-fixture population
#                  (test/fixtures_ieee123.jl, copied below: 85 load nodes, one seeded
#                  Thermostatic + Deferrable + PVBattery house per node, seed 20260719),
#                  T = 24, the fixture's digitized price profile, engine :centralized.
#                  The welfare solves (DADP and every flex redispatch) use the documented
#                  conditioning select_optimizer(SOCP(); tol_gap_abs = 3e-9, tol_gap_rel =
#                  3e-9): the default tol_gap trips the exactness gate on this feeder at the
#                  precision floor (test/test_ieee123_admm.jl). The gates themselves (tau,
#                  epsilon, the hybrid floor) are untouched. All rows of this mode are
#                  written, and its rebound rows too. Several minutes of wall time.
#                  The committed ieee123 artifact is recorded WITH --flex-market: a run owns
#                  every row of the mode, so a base-only run deletes the committed flex rows,
#                  and the committed-CSV test (test/test_flex_market_ieee.jl) rejects a
#                  table that holds only the base legs.
#   ieee123-default  The same feeder with the DEFAULT generated population,
#                  build_population(:default, ..., :ieee123, ...) at seed 20260718, the :mem
#                  prices and the default SOCP optimizer, engine :centralized. Its DADP
#                  solve is expected to be REFUSED at the exactness certificate; whatever
#                  happens is written (a "(run)" status row on a refusal), never re-tuned.
#
# Wall time: the ieee13-ground flex path and both IEEE-123 modes stamp run_wall_s (the
# @elapsed of the mode's compare call, in s) on every summary row they write, "(run)"
# status rows included. The default ieee13-ground and case-a-784 paths are unchanged and
# do not stamp it.
#
# CSV contract (the case_a_scaling idiom): rows are UPSERTED keyed on their provenance
# identity (mode, tariff / unit_id / group, seed, t_horizon) with `cols = :union` —
# re-runs replace their own rows and never drop others'. A run OWNS its mode's rows of the
# same (seed, t_horizon) and deletes them from all four tables before writing (purge_rows),
# so no earlier "(run)" row, leg row or flex row survives beside the new outcome: the
# IEEE-123 modes, case-a-784 and --record-timeout (without --flex-market on ieee13-ground)
# own every row of the mode; the default
# ieee13-ground run owns the mode's non-flex rows on success (and its flex rows too when its
# dadp row no longer reproduces the committed one, or when the run is refused); the
# ieee13-ground --flex-market run, and its --record-timeout, own only the mode's flex rows
# ("flex_(run)" included). Every row stamps julia_version,
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
#   rebound_hourly.csv      — per-hour rebound rows (with delivery_shortfall on flex rows),
#                             written only by the --flex-market and IEEE-123 paths, keyed
#                             (mode, tariff, t, seed, t_horizon)
#
# Regenerate the committed artifacts:
#   julia --project=. scripts/tariff_comparison.jl --mode ieee13-ground
#   julia --project=. scripts/tariff_comparison.jl --mode case-a-784   # long-running
#   julia --project=. scripts/tariff_comparison.jl --mode ieee13-ground --flex-market
#   julia --project=. scripts/tariff_comparison.jl --mode ieee123 --flex-market   # minutes
#   julia --project=. scripts/tariff_comparison.jl --mode ieee123-default

using DrWatson
@quickactivate "TSODSO"
using TSODSO
using TSODSO:
    ADMM,
    Aggregator,
    CertificateError,
    ConvergenceError,
    ConvexBranchFlow,
    Deferrable,
    FlexMarket,
    PVBattery,
    SOCP,
    SolveFailedError,
    Thermostatic,
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
    ieee123_load_nodes,
    ieee123_modified,
    select_optimizer,
    sub_seed
using CSV
using DataFrames: DataFrame, eachrow, nrow
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
const REBOUND_CSV = joinpath(OUT_DIR, "rebound_hourly.csv")

# IEEE-123 seeds: the certified fixture population's seed (test/fixtures_ieee123.jl) and the
# seed of the default generated population whose DADP refusal the ieee123-default mode records.
const SEED_IEEE123 = 20260719
const SEED_IEEE123_DEFAULT = 20260718
const MODES = ("ieee13-ground", "case-a-784", "ieee123", "ieee123-default")

# ---- kv-flag parsing (case_a_scaling.jl conventions) -----------------------------------------

function parse_kv_flag(args, flag::String, default)
    idx = findfirst(==(flag), args)
    idx === nothing && return default
    idx == length(args) && throw(ArgumentError("$flag requires a value (none given)"))
    return args[idx + 1]
end

parse_args!(args) = (
    mode = let m = parse_kv_flag(args, "--mode", "ieee13-ground")
        (m in MODES) || throw(
            ArgumentError(
                "--mode must be one of $(join(repr.(MODES), ", ")) (got $(repr(m)))",
            ),
        )
        m
    end,
    # Boolean flag (no value): `parse_kv_flag` requires a value, so test membership.
    flex_market = ("--flex-market" in args),
    record_timeout = let s = parse_kv_flag(args, "--record-timeout", nothing)
        s === nothing ? nothing :
        let S = parse(Float64, s)
            (isfinite(S) && S >= 0) || throw(
                ArgumentError(
                    "--record-timeout must be a finite number of seconds ≥ 0 (got $S)",
                ),
            )
            S
        end
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
# (SEED_GROUND), the thesis-scale leg the LOCKED thesis seed (SEED_CASE_A), the IEEE-123
# modes SEED_IEEE123 / SEED_IEEE123_DEFAULT. A --seed override applies to any mode.
function mode_seed(mode::String, seed::Union{Nothing, Int})
    seed !== nothing && return seed
    mode == "ieee13-ground" && return SEED_GROUND
    mode == "ieee123" && return SEED_IEEE123
    mode == "ieee123-default" && return SEED_IEEE123_DEFAULT
    return SEED_CASE_A
end

"""
    flex_markets_for(mode) -> Vector{FlexMarket}

The flexibility-market legs a mode clears under `--flex-market`. Every mode gets the flat
baseline under both payment rules at baseline inflation beta in {0, 0.05, 0.10} (6 legs,
one physics clear, since the rule and beta change money only); ieee13-ground adds the TOU
baseline under both rules at beta 0 (8 legs, 2 clears). case-a-784 has none.
"""
function flex_markets_for(mode::String)
    flat = [
        FlexMarket(; payment_rule = r, baseline_inflation = β) for
        r in (:uniform, :pay_as_bid) for β in (0.0, 0.05, 0.10)
    ]
    mode == "ieee13-ground" && return vcat(
        flat,
        [
            FlexMarket(; baseline_tariff = :tou, payment_rule = r) for
            r in (:uniform, :pay_as_bid)
        ],
    )
    mode in ("ieee123", "ieee123-default") && return flat
    throw(
        ArgumentError(
            "flex_markets_for: no flexibility-market legs for mode $(repr(mode))",
        ),
    )
end

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

"""
    purge_rows(mode_name, seed, T_H; tariff = _ -> true) -> nothing

Delete, from each committed table that exists (summary, bills, breakouts, rebound), the rows of
`(mode, seed, t_horizon)` whose tariff satisfies the predicate `tariff` (called on the tariff
as a `String`). A run of a mode owns its rows: called before the mode writes, this keeps a
re-run from leaving rows of an earlier run beside the new ones, such as an old "(run)" status
row beside fresh legs, old legs beside a fresh refusal, or the flex rows of an older run beside
a base-only run. Rows of other modes, seeds and horizons are never touched, and a table with
nothing to delete is not rewritten.
"""
function purge_rows(mode_name::String, seed::Int, T_H::Int; tariff = _ -> true)
    for path in (SUMMARY_CSV, BILLS_CSV, BREAKOUTS_CSV, REBOUND_CSV)
        isfile(path) || continue
        old = CSV.read(path, DataFrame)
        nrow(old) == 0 && continue
        owned(r) =
            isequal(r.mode, mode_name) &&
            isequal(r.seed, seed) &&
            isequal(r.t_horizon, T_H) &&
            tariff(String(r.tariff))
        n = count(owned, eachrow(old))
        n == 0 && continue
        CSV.write(path, filter(r -> !owned(r), old))
        println("  purged $n stale row(s) of mode=$mode_name seed=$seed from $path")
    end
    flush(stdout)
    return nothing
end

isflex_tariff(t::AbstractString) = startswith(t, "flex_")

# The tariff of the status row of a stopped ieee13-ground --flex-market run. It is a flex row
# (`isflex_tariff`), so every path that owns the mode's flex rows also owns it.
const FLEX_RUN_TARIFF = "flex_(run)"

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

# Per-hour rebound rows: written only by the flexibility-market and IEEE-123 paths.
const REBOUND_COLS = Symbol[
    :mode,
    :tariff,
    :t,
    :baseline_net_load,
    :counterfactual_net_load,
    :delta,
    :classification,
    :delivery_shortfall,
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
    write_compare_results(res, mode_name, T_H, seed; run_wall_s = nothing,
                          only_flex = false, rebound = false) -> nothing

Upsert the runner's three committed tables row by row, each stamped with the script-side
provenance (`seed`, `mode`) beside the runner's own stamp (`julia_version`, `threads`,
`blas_threads`, `t_horizon`). The keywords are used only by the flexibility-market and
IEEE-123 paths (at their defaults the behaviour is the original one): `run_wall_s` stamps
that column on every summary row, `only_flex` restricts every table to the rows whose
tariff starts with "flex_", and `rebound` also upserts the per-hour rebound rows into
`rebound_hourly.csv`.
"""
function write_compare_results(
    res,
    mode_name::String,
    T_H::Int,
    seed::Int;
    run_wall_s::Union{Nothing, Float64} = nothing,
    only_flex::Bool = false,
    rebound::Bool = false,
)
    keep(r) = !only_flex || startswith(String(r.tariff), "flex_")
    wall = run_wall_s === nothing ? (;) : (run_wall_s = run_wall_s,)
    for r in eachrow(res.summary)
        keep(r) || continue
        row = NamedTuple(r)
        row = haskey(row, :notes) ? merge(row, (notes = flatten_note(row.notes),)) : row
        upsert_row(
            SUMMARY_CSV,
            merge(row, (mode = mode_name,), provenance_row(T_H, seed), wall);
            key = (:mode, :tariff, :seed, :t_horizon),
        )
    end
    for r in eachrow(res.household_bills)
        keep(r) || continue
        upsert_row(
            BILLS_CSV,
            merge(NamedTuple(r), (mode = mode_name,), provenance_row(T_H, seed));
            key = (:mode, :tariff, :unit_id, :seed, :t_horizon),
        )
    end
    for r in eachrow(res.equity_breakouts)
        keep(r) || continue
        upsert_row(
            BREAKOUTS_CSV,
            merge(NamedTuple(r), (mode = mode_name,), provenance_row(T_H, seed));
            key = (:mode, :tariff, :grouping, :group, :metric_kind, :seed, :t_horizon),
        )
    end
    if rebound
        ensure_schema(REBOUND_CSV, REBOUND_COLS)
        for r in eachrow(res.rebound)
            keep(r) || continue
            upsert_row(
                REBOUND_CSV,
                merge(NamedTuple(r), (mode = mode_name,), provenance_row(T_H, seed));
                key = (:mode, :tariff, :t, :seed, :t_horizon),
            )
        end
    end
    return nothing
end

"""
    write_run_status_row(outcome, mode_name, engine, T_H, seed; run_wall_s, tariff) -> nothing

The DADP-run-level honest status row (tariff = "(run)"): certified values missing, the
error type in `status`, the message truncated into `notes`, iterations carried when the
error has them. `tariff = FLEX_RUN_TARIFF` scopes the row to the flex legs of a mode instead
(the stopped ieee13-ground --flex-market run, whose base rows are the committed ones).
"""
function write_run_status_row(
    outcome,
    mode_name::String,
    engine::String,
    T_H::Int,
    seed::Int;
    run_wall_s::Union{Nothing, Float64} = nothing,
    tariff::String = "(run)",
)
    wall = run_wall_s === nothing ? (;) : (run_wall_s = run_wall_s,)
    row = merge(
        (
            mode = mode_name,
            tariff = tariff,
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
        wall,
    )
    upsert_row(SUMMARY_CSV, row; key = (:mode, :tariff, :seed, :t_horizon))
    return nothing
end

# ---- ieee13-ground mode ----------------------------------------------------------------------

# The ieee13-ground feeder, price and population (shared by the default and flex paths).
function ground_setup(T_H::Int, seed::Int)
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
    return feeder, λ₀, aggs
end

function ground_main(T_H::Int, seed::Int)
    # BLAS pinned to 1 for row-to-row comparability (the case_a_scaling discipline).
    BLAS.set_num_threads(1)
    feeder, λ₀, aggs = ground_setup(T_H, seed)

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
        # a refused run owns every row of the mode: no earlier leg (or flex) row survives it
        purge_rows("ieee13-ground", seed, T_H)
        write_run_status_row(outcome, "ieee13-ground", "centralized", T_H, seed)
        println(
            "  → DADP run RECORDED as $(outcome.status) (a measured outcome, never a dropped " *
            "leg) → $SUMMARY_CSV",
        )
        flush(stdout)
        return nothing
    end
    # The base run owns the mode's non-flex rows (its "(run)" row included). The flex rows were
    # written against the committed dadp row; they are kept only while this run reproduces it.
    chk = dadp_provenance(outcome, T_H, seed)
    stale_flex = !chk.ok
    stale_flex && println(
        "  the mode's flex rows, if any, are purged with the base rows (re-run " *
        "--flex-market to record them again), because the committed dadp row they were " *
        "cleared against is not reproduced: $(chk.reason)",
    )
    purge_rows("ieee13-ground", seed, T_H; tariff = t -> stale_flex || !isflex_tariff(t))
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

"""
    assert_dadp_reproduces(outcome, T_H, seed) -> nothing

Provenance guard of the ieee13-ground flex path, run BEFORE any write. The in-run dadp row
must reproduce the committed ieee13-ground dadp row of the same (seed, t_horizon) in
`welfare`, `aggregators_total` and `status`. The in-run values go through a CSV round trip
first: the CSV writer emits Float64 cells in shortest round-trip form, so on the pinned
environment a reproduction compares equal bit for bit, and the comparison is `isequal` with
no tolerance. On any difference (or a missing committed row, or a refused in-run DADP) this
throws with both values printed and nothing is written: the flex rows must never be mixed
with base rows of a different provenance. Re-recording the base rows is a separate,
explicit decision; this check is never bypassed with a tolerance.
"""
function assert_dadp_reproduces(outcome, T_H::Int, seed::Int)
    head = "ieee13-ground --flex-market: provenance check FAILED (seed=$seed, t_horizon=$T_H); NOTHING WRITTEN."
    chk = dadp_provenance(outcome, T_H, seed)
    chk.ok || error("$head $(chk.reason)$(chk.advice)")
    c = chk.committed
    println(
        "  provenance check passed: in-run dadp row == committed (welfare=$(repr(c.welfare)), " *
        "aggregators_total=$(repr(c.aggregators_total)), status=$(repr(c.status)))",
    )
    flush(stdout)
    return nothing
end

"""
    dadp_provenance(outcome, T_H, seed) -> (; ok, reason, advice, committed)

The comparison behind `assert_dadp_reproduces`, without throwing: `ok` is `true` when
the in-run ieee13-ground dadp row reproduces the committed one of the same (seed, t_horizon)
bit for bit (after a CSV round trip), `reason` says why not otherwise, `advice` is the
flex path's instruction on a value mismatch (empty otherwise; `assert_dadp_reproduces` appends
it, the default path does not), and `committed` is the
committed row (`nothing` when there is none). The default ieee13-ground path uses it to decide
whether the committed flex rows still belong to the base rows it is about to write.
"""
function dadp_provenance(outcome, T_H::Int, seed::Int)
    fail(reason, committed = nothing; advice = "") =
        (; ok = false, reason, advice, committed)
    isfile(SUMMARY_CSV) || return fail("No committed summary CSV at $SUMMARY_CSV.")
    old = CSV.read(SUMMARY_CSV, DataFrame)
    committed = filter(
        r ->
            isequal(r.mode, "ieee13-ground") &&
            isequal(r.tariff, "dadp") &&
            isequal(r.seed, seed) &&
            isequal(r.t_horizon, T_H),
        old,
    )
    nrow(committed) == 1 ||
        return fail("Expected exactly 1 committed dadp row, found $(nrow(committed)).")
    c = committed[1, :]
    outcome.ok || return fail(
        "The in-run DADP solve was refused: status=$(repr(outcome.status)) vs " *
        "committed status=$(repr(c.status)). Message: $(outcome.message)",
        c,
    )
    inrun = filter(r -> r.tariff == "dadp", outcome.res.summary)
    nrow(inrun) == 1 ||
        return fail("Expected exactly 1 in-run dadp row, found $(nrow(inrun)).", c)
    cols = [:welfare, :aggregators_total, :status]
    io = IOBuffer()
    CSV.write(io, inrun[:, cols])
    rt = CSV.read(IOBuffer(take!(io)), DataFrame)
    diffs = String[]
    for col in cols
        a = c[col]
        b = rt[1, col]
        isequal(a, b) || push!(
            diffs,
            "$col: committed=$(repr(a)) in-run=$(repr(b)) (in-run before the round trip: " *
            "$(repr(inrun[1, col])))",
        )
    end
    isempty(diffs) || return fail(
        "The in-run dadp row does not reproduce the committed one:\n  " *
        join(diffs, "\n  "),
        c;
        advice = "\nStop and investigate; re-recording the base rows is a separate, explicit decision.",
    )
    return (; ok = true, reason = "", advice = "", committed = c)
end

# Print one line per summary row of a finished run.
function print_summary_rows(summary; only_flex::Bool = false)
    for r in eachrow(summary)
        (only_flex && !startswith(String(r.tariff), "flex_")) && continue
        line =
            "  → $(r.tariff): welfare=$(r.welfare) payments=$(r.total_payments) " *
            "feas=$(r.feasibility_status) status=$(r.status)"
        if hasproperty(r, :welfare_gap_vs_dadp_lossless) &&
           startswith(String(r.tariff), "flex_")
            line *=
                " gap_lossless=$(r.welfare_gap_vs_dadp_lossless) " *
                "shortfall=$(r.delivery_shortfall_total) " *
                "overpay=$(r.baseline_overpayment) flex_wall_s=$(r.flex_wall_s)"
        end
        println(line)
    end
    flush(stdout)
    return nothing
end

# The ieee13-ground flexibility-market measurement: the 8 flex legs on the same run as the base
# legs. Only the flex rows are written, after the provenance guard: the committed base rows stay
# exactly as recorded and are never back-filled with the new columns' values.
function ground_flex_main(T_H::Int, seed::Int)
    BLAS.set_num_threads(1)
    feeder, λ₀, aggs = ground_setup(T_H, seed)
    markets = flex_markets_for("ieee13-ground")
    println(
        "tariff_comparison ieee13-ground --flex-market: T=$T_H, seed=$seed, " *
        "engine=:centralized, aggregators=$(length(aggs)), flex legs=$(length(markets)) " *
        "(BLAS pinned to 1) — comparing...",
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
            flex_market = markets,
        )
    end
    assert_dadp_reproduces(outcome, T_H, seed)
    ensure_all_schemas()
    # this run owns the mode's flex rows; the base rows stay as recorded
    purge_rows("ieee13-ground", seed, T_H; tariff = isflex_tariff)
    write_compare_results(
        outcome.res,
        "ieee13-ground",
        T_H,
        seed;
        run_wall_s = wall_s,
        only_flex = true,
        rebound = true,
    )
    print_summary_rows(outcome.res.summary; only_flex = true)
    println(
        "ieee13-ground --flex-market complete in $(round(wall_s; digits = 2)) s → " *
        "$SUMMARY_CSV, $BILLS_CSV, $REBOUND_CSV",
    )
    return nothing
end

# ---- IEEE-123 modes --------------------------------------------------------------------------

# IEEE-123 certified population, copied verbatim from test/fixtures_ieee123.jl (through its copy
# in scripts/actor_behaviour_sweep.jl). A script cannot include the fixture file: @testmodule is
# a no-op outside the test runner (see scripts/repro_stability_check.jl). The only change is
# that the seed and the horizon are arguments.
const BATT_λ_MIN = 3.8
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9
const LOAD_SCALE_IEEE123 = 0.05
const PV_SCALE_IEEE123 = 0.12
const DEV_SCALE_IEEE123 = 0.05 * (0.05 / 0.03)

temperature_profile() = Float64[
    19,
    18,
    17,
    16,
    16,
    17,
    19,
    21,
    23,
    26,
    28,
    30,
    31,
    32,
    32,
    31,
    29,
    27,
    25,
    23,
    22,
    21,
    20,
    19,
]

ieee123_lambda0() = Float64[
    3.8,
    3.7,
    3.6,
    3.6,
    3.7,
    4.0,
    4.8,
    5.8,
    6.5,
    6.2,
    5.9,
    5.7,
    5.6,
    5.8,
    6.0,
    6.8,
    8.2,
    9.0,
    8.6,
    7.4,
    6.2,
    5.2,
    4.4,
    4.0,
]

function house(
    bus;
    seed,
    T,
    φ,
    pv_scale = 1.0,
    load_scale = 1.0,
    dev_scale = 1.0,
    batt_pmax = 0.5,
    batt_emax = 2.0,
    batt_soc0 = 1.0,
)
    prof = generate_profiles(seed = seed + bus, T = T)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]
    therm = Thermostatic(
        bus,
        0.2,
        0.05,
        15.0,
        30.0,
        22.0,
        0.0,
        1.0 * dev_scale,
        0.5,
        temperature_profile(),
    )
    defer = Deferrable(bus, 8, 16, 1.0 * dev_scale, 0.5 * dev_scale, 0.5)
    batt = PVBattery(
        bus,
        0.95,
        1.0,
        batt_pmax,
        0.0,
        batt_emax,
        batt_soc0,
        BATT_λ_MIN,
        BATT_λ_MED,
        BATT_λ_MAX,
        Ppv,
    )
    return Aggregator(bus, φ, [therm, defer, batt], Pdc)
end

function ieee123_population(seed::Int, T::Int)
    return [
        house(
            bus;
            seed = seed,
            T = T,
            φ = 0.90,
            load_scale = LOAD_SCALE_IEEE123,
            pv_scale = PV_SCALE_IEEE123,
            dev_scale = DEV_SCALE_IEEE123,
            batt_pmax = 0.5 * LOAD_SCALE_IEEE123,
            batt_emax = 2.0 * LOAD_SCALE_IEEE123,
            batt_soc0 = 1.0 * LOAD_SCALE_IEEE123,
        ) for bus in ieee123_load_nodes()
    ]
end

# Record one IEEE-123 mode's outcome: a "(run)" status row on a refusal, otherwise every row
# (summary, bills, breakouts, rebound), with run_wall_s on every summary row either way. The
# mode's earlier rows of the same (seed, t_horizon) are purged first, so the tables hold this
# run's outcome only.
function write_mode_outcome(
    outcome,
    mode_name::String,
    T_H::Int,
    seed::Int,
    wall_s::Float64,
)
    ensure_all_schemas()
    # a run of an IEEE-123 mode owns all of that mode's rows, whatever its outcome
    purge_rows(mode_name, seed, T_H)
    if !outcome.ok
        write_run_status_row(
            outcome,
            mode_name,
            "centralized",
            T_H,
            seed;
            run_wall_s = wall_s,
        )
        println(
            "  → DADP run RECORDED as $(outcome.status) after $(round(wall_s; digits = 2)) s " *
            "(a measured outcome, never re-tuned) → $SUMMARY_CSV\n    $(outcome.message)",
        )
        flush(stdout)
        return nothing
    end
    write_compare_results(
        outcome.res,
        mode_name,
        T_H,
        seed;
        run_wall_s = wall_s,
        rebound = true,
    )
    print_summary_rows(outcome.res.summary)
    println(
        "$mode_name complete in $(round(wall_s; digits = 2)) s → " *
        "$SUMMARY_CSV, $BILLS_CSV, $BREAKOUTS_CSV, $REBOUND_CSV",
    )
    return nothing
end

function ieee123_horizon_check(mode_name::String, T_H::Int)
    T_H == 24 || throw(
        ArgumentError(
            "$mode_name: the IEEE-123 population and price profiles are 24-hour days " *
            "(got --t-horizon $T_H)",
        ),
    )
    return nothing
end

function ieee123_main(T_H::Int, seed::Int, flex::Bool)
    ieee123_horizon_check("ieee123", T_H)
    BLAS.set_num_threads(1)
    feeder = ieee123_modified()
    aggs = ieee123_population(seed, T_H)
    λ₀ = ieee123_lambda0()
    # Conditioning only (the documented tol_gap = 3e-9 of the IEEE-123 tests); the exactness
    # gate, tau and epsilon are unchanged.
    welfare_optimizer = select_optimizer(SOCP(); tol_gap_abs = 3e-9, tol_gap_rel = 3e-9)
    markets = flex ? flex_markets_for("ieee123") : nothing
    println(
        "tariff_comparison ieee123: T=$T_H, seed=$seed, engine=:centralized, " *
        "aggregators=$(length(aggs)), tol_gap=3e-9, flex legs=" *
        "$(markets === nothing ? 0 : length(markets)) (BLAS pinned to 1) — comparing...",
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
            welfare_optimizer = welfare_optimizer,
            flex_market = markets,
        )
    end
    write_mode_outcome(outcome, "ieee123", T_H, seed, wall_s)
    return nothing
end

function ieee123_default_main(T_H::Int, seed::Int, flex::Bool)
    ieee123_horizon_check("ieee123-default", T_H)
    BLAS.set_num_threads(1)
    feeder = ieee123_modified()
    profiles = generate_profiles(; seed = sub_seed(seed, :profiles), T = T_H)
    λ₀ = build_price(PRICE_SYM, T_H, nothing)
    aggs =
        build_population(:default, feeder, :ieee123, profiles, sub_seed(seed, :population))
    markets = flex ? flex_markets_for("ieee123-default") : nothing
    println(
        "tariff_comparison ieee123-default: T=$T_H, seed=$seed, engine=:centralized, " *
        "aggregators=$(length(aggs)), default SOCP optimizer, flex legs=" *
        "$(markets === nothing ? 0 : length(markets)) (BLAS pinned to 1) — comparing...",
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
            flex_market = markets,
        )
    end
    write_mode_outcome(outcome, "ieee123-default", T_H, seed, wall_s)
    return nothing
end

# --record-timeout: the honest record of a run that was stopped before it finished. No solve.
function record_timeout_main(mode::String, T_H::Int, seed::Int, S::Float64)
    ensure_all_schemas()
    # the stopped run owns the mode's rows: no earlier certified row survives beside it
    purge_rows(mode, seed, T_H)
    outcome = (; status = "timeout", message = "stopped after $S s wall", iters = missing)
    engine = mode == "case-a-784" ? "admm" : "centralized"
    write_run_status_row(outcome, mode, engine, T_H, seed; run_wall_s = S)
    println("  → $mode RECORDED as timeout (run_wall_s = $S) → $SUMMARY_CSV")
    return nothing
end

# --record-timeout --flex-market on ieee13-ground: the honest record of a stopped flex run. That
# run writes only flex rows beside the committed base rows, so its timeout owns only the mode's
# flex rows: they are deleted (an earlier flex status row included) and one FLEX_RUN_TARIFF
# status row is written. The base rows and their bill, breakout and rebound rows are never
# touched. The flex rows are cleared against the committed dadp row, so a flex timeout without
# one is refused before any write. No solve.
function record_flex_timeout_main(T_H::Int, seed::Int, S::Float64)
    committed_dadp(r) =
        isequal(r.mode, "ieee13-ground") &&
        isequal(r.tariff, "dadp") &&
        isequal(r.seed, seed) &&
        isequal(r.t_horizon, T_H)
    n_dadp =
        isfile(SUMMARY_CSV) ?
        count(committed_dadp, eachrow(CSV.read(SUMMARY_CSV, DataFrame))) : 0
    n_dadp == 1 || throw(
        ArgumentError(
            "--record-timeout --flex-market on ieee13-ground needs exactly 1 committed dadp " *
            "row of seed=$seed, t_horizon=$T_H (found $n_dadp): the flex legs are cleared " *
            "against it. Record the base run first (--mode ieee13-ground).",
        ),
    )
    ensure_all_schemas()
    purge_rows("ieee13-ground", seed, T_H; tariff = isflex_tariff)
    outcome = (;
        status = "timeout",
        message = "flex legs stopped after $S s wall (the base rows are the committed ones)",
        iters = missing,
    )
    write_run_status_row(
        outcome,
        "ieee13-ground",
        "centralized",
        T_H,
        seed;
        run_wall_s = S,
        tariff = FLEX_RUN_TARIFF,
    )
    println(
        "  → ieee13-ground --flex-market RECORDED as timeout (run_wall_s = $S, tariff " *
        "$FLEX_RUN_TARIFF; base rows kept) → $SUMMARY_CSV",
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
    # the run owns every row of the mode, whatever its outcome
    purge_rows("case-a-784", seed, T_H)
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
    (parsed.mode == "case-a-784" && parsed.flex_market) && throw(
        ArgumentError(
            "--flex-market is not available on case-a-784: a houses run cannot " *
            "carry flex legs (compare_tariffs refuses houses with flex_market)",
        ),
    )
    seed = mode_seed(parsed.mode, parsed.seed)
    println(
        "tariff_comparison: mode=$(parsed.mode) t_horizon=$(parsed.T_H) seed=$seed " *
        "time_limit_s=$(parsed.time_limit_s) flex_market=$(parsed.flex_market) " *
        "record_timeout=$(something(parsed.record_timeout, "-")) threads=$(Threads.nthreads()) " *
        "blas=$(BLAS.get_num_threads()) (pinning BLAS to 1)",
    )
    if parsed.record_timeout !== nothing
        if parsed.mode == "ieee13-ground" && parsed.flex_market
            # the stopped flex run owns only the flex rows; the base rows stay as recorded
            record_flex_timeout_main(parsed.T_H, seed, parsed.record_timeout)
        else
            record_timeout_main(parsed.mode, parsed.T_H, seed, parsed.record_timeout)
        end
    elseif parsed.mode == "ieee13-ground"
        parsed.flex_market ? ground_flex_main(parsed.T_H, seed) :
        ground_main(parsed.T_H, seed)
    elseif parsed.mode == "ieee123"
        ieee123_main(parsed.T_H, seed, parsed.flex_market)
    elseif parsed.mode == "ieee123-default"
        ieee123_default_main(parsed.T_H, seed, parsed.flex_market)
    else
        caseA_main(parsed.T_H, seed, parsed.time_limit_s)
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    comparison_main(ARGS)
end
