# scripts/case_a_magnitude.jl
#
# REPRO-03/04/05 (Phase 42): the pre-registered welfare-gain MAGNITUDE measurement —
# DADP vs FIT on the thesis Case A configuration, under the committed pre-registration
# protocol `.planning/phases/42-thesis-case-a-magnitude/42-CASE-A-PROTOCOL.md` (the guard
# below REFUSES to run anything unless that file exists AND is committed).
#
# usage:
#   julia --project=. scripts/case_a_magnitude.jl --mode headline [--seed 42] [--time-limit-s S]
#   julia --project=. scripts/case_a_magnitude.jl --mode proxy
#
# Modes (--mode):
#
#   headline  DEFAULT. ONE registered master seed per invocation (default 42, the
#             continuity anchor; 43–46 are the pre-registered spread). The FROZEN
#             registered configuration (protocol §2) — `:case_a_784` over `:ieee13`,
#             ConvexBranchFlow, T = 24, λ₀ = :mem, allow_export = true, ρ = ADMM().ρ
#             (locked, no re-tuning) — runs the PRE-REGISTERED AGR solver-precision
#             ladder (`AGR_TOL_RUNGS`, stop-on-first-certified, hard stop after the last
#             rung) over `solve_admm` (the published-price engine), then the UNCHANGED
#             `fit_baseline` FIT leg (batteryless by design, thesis Assumption A4), then
#             the SIGN-SAFE registered gain. LONG-RUNNING (the 784-house measurement is
#             plan 42-05's payload; certify machinery on the proxy mode first).
#   proxy     The SAME code path (`_measure_point`) on the small protocol-pinned
#             fixtures: IEEE-123 `:default` (seed 20260719 — the ≈+0.263% provenance
#             fixture, `thesis_case123_repro.jl` SEED_IEEE123) first, then IEEE-13
#             `:default` (seed 20260718 — the ground-fixture regression seed). Minutes
#             scale. Expected honest outcomes: ieee123 certifies with a FIT leg;
#             ieee13 records the KNOWN FIT INFEASIBLE (`error:SolveFailedError`,
#             the committed `tariff_comparison.csv` precedent) — recorded, never
#             re-tuned. `--seed` is rejected: the fixtures pin their own seeds.
#
# Honesty policy (protocol §4/§5, v5.0 policies): every solver refusal is a RECORDED
# outcome — `error:<TypeName>` status rows (iters from the typed error, −1 sentinel when
# the error carries none), the typed `:budget_exceeded` wall-clock early exit, and
# `fit_inexact`/retry outcomes. The ONLY sanctioned answers are the pre-registered AGR
# ladder (via `solve_admm`'s documented `agr_optimizer` seam) and the ONE pinned FIT
# retry (the SOLVER tightened to `tol_gap 1e-10` — never a gate, never ρ, never battery
# τ). A kill mid-run leaves the rows already captured (upsert contract) — a kill is a
# measured outcome.
#
# The gain is computed ONLY by `welfare_gain` from `scripts/lib/case_a_common.jl` — the
# registered SIGN-SAFE form `Δ% = 100·(W_DADP − W_FIT)/|W_FIT|`. The naive ratio W_DADP/W_FIT
# is BANNED (it sign-inverts on negative welfare: welfare ≈ −3.78e5 at 784 houses, so a
# welfare LOSS would read as a positive-looking ratio > 1 — PROJECT.md Key Decision;
# protocol §1). It appears nowhere in this script, and the source-contract test asserts
# that absence.
#
# CSV contract (the `tariff_comparison.jl` idiom): rows are UPSERTED with `cols = :union`
# keyed on their provenance identity PLUS the row-granularity columns (kind, rung) —
# re-runs replace their own rows and never drop siblings; every row stamps
# `protocol_sha` + full provenance (julia_version / threads / blas_threads / seed /
# t_horizon). Every rung attempt is its own row (refusals included). One measurement
# process at a time.
#
# Outputs (results/thesis_case_a_magnitude/):
#   magnitude.csv  — headline rows: one per rung attempt + one gain row per seed
#   proxy.csv      — proxy rows: same shapes, with a `fixture` identity column
#
# Regenerate the committed proxy artifact (minutes-scale):
#   julia --project=. scripts/case_a_magnitude.jl --mode proxy

using DrWatson
@quickactivate "TSODSO"
using TSODSO
using TSODSO:
    ADMM,
    CertificateError,
    ConvergenceError,
    ConvexBranchFlow,
    QP,
    SOCP,
    SolveFailedError,
    UnconvergedAdmmError,
    _CASE_A_TOTAL_HOUSES,
    build_feeder,
    build_population,
    build_price,
    fit_baseline,
    generate_profiles,
    select_optimizer,
    solve_admm,
    sub_seed
using CSV
using DataFrames: DataFrame, eachrow
using LinearAlgebra: BLAS

include(joinpath(@__DIR__, "lib", "case_a_common.jl"))   # the 42-01 helpers: the guard,
# welfare_gain, provenance_row, flatten_note — ONE shared definition, never re-derived here.

# ---- the pre-planned values (the protocol, restated as runnable identity) ---------------------

# The protocol seed set (42-CASE-A-PROTOCOL.md §3): 42 = primary/registered anchor with
# every prior Case A artifact, 43–46 = the pre-registered spread. Adding a seed is a
# protocol amendment + a script edit (this tuple is pinned by the source-contract test).
const SEEDS = (42, 43, 44, 45, 46)
const REGISTERED_SEED = first(SEEDS)

# The mode whitelist. EXTENDABLE by later waves (crosscheck/lenses/ablation-* modes are
# planned) — never shrink or rename a registered mode: the source-contract test pins the
# registered members with contains-semantics on purpose.
const MODES = ("headline", "proxy")

# The PRE-PLANNED AGR solver-precision ladder (verbatim from
# `scripts/case_a_agreement.jl:116-126`; protocol §4). The Dict IS the entire permitted
# ladder — the rungs tighten Clarabel's OWN convergence precision via the documented
# `agr_optimizer` seam; the exactness gate, the battery τ and ρ are NEVER touched. Rung
# keys are plain STRINGS (`:gap_1e-10` would parse as subtraction). Adding a rung
# requires editing this Dict + a protocol amendment (the deliberate-act friction).
const AGR_TOL_RUNGS = Dict{String, Union{Nothing, NamedTuple}}(
    "default"       => nothing,
    "gap_1e-10"     => (tol_gap_abs = 1e-10, tol_gap_rel = 1e-10),
    "gap_1e-12"     => (tol_gap_abs = 1e-12, tol_gap_rel = 1e-12),
    "gapfeas_1e-12" => (
        tol_gap_abs = 1e-12,
        tol_gap_rel = 1e-12,
        tol_feas_abs = 1e-12,
        tol_feas_rel = 1e-12,
    ),
)
# The declared run order (Julia Dicts are unordered): step 0 → 3 of the protocol §4
# table. Guarded below against drift from the Dict.
const AGR_RUNG_ORDER = ("default", "gap_1e-10", "gap_1e-12", "gapfeas_1e-12")
sort(collect(keys(AGR_TOL_RUNGS))) == sort(collect(AGR_RUNG_ORDER)) || error(
    "case_a_magnitude: AGR_RUNG_ORDER $(AGR_RUNG_ORDER) does not exactly cover " *
    "AGR_TOL_RUNGS keys $(sort(collect(keys(AGR_TOL_RUNGS)))) — the ladder Dict and its " *
    "declared run order drifted (aborting loudly)",
)

# The protocol-pinned proxy fixtures (42-CASE-A-PROTOCOL.md §7c/§8): the ≈+0.263%
# provenance fixture FIRST (the restatement point), then the same-feeder regression
# fixture whose known honest statuses are EXPECTED rows.
const PROXY_FIXTURES = (
    (fixture = "ieee123-default", feeder_sym = :ieee123, pop_sym = :default, seed = 20260719),
    (fixture = "ieee13-default", feeder_sym = :ieee13, pop_sym = :default, seed = 20260718),
)

const FEEDER_SYM = :ieee13   # the registered headline feeder (protocol §2)
const PRICE_SYM = :mem       # the registered price signal (protocol §2)
const T_H = 24               # the registered horizon (protocol §2)
const OUT_DIR = joinpath(projectdir(), "results", "thesis_case_a_magnitude")
const MAGNITUDE_CSV = joinpath(OUT_DIR, "magnitude.csv")
const PROXY_CSV = joinpath(OUT_DIR, "proxy.csv")

# The per-run protocol SHA — filled by `main` from the guard, stamped on EVERY row
# (tampering mitigations T-42-03-1/T-42-03-3: each row is auditable to the exact
# protocol version that produced it).
const PROTOCOL_SHA = Ref("")

# ---- kv-flag parsing (tariff_comparison.jl / case_a_agreement.jl conventions) -----------------

function parse_kv_flag(args, flag::String, default)
    idx = findfirst(==(flag), args)
    idx === nothing && return default
    idx == length(args) && throw(ArgumentError("$flag requires a value (none given)"))
    return args[idx + 1]
end

parse_args!(args) = (
    mode = let m = parse_kv_flag(args, "--mode", "headline")
        m in MODES || throw(
            ArgumentError(
                "--mode must be one of the registered modes ($(join(MODES, ", ")); the " *
                "whitelist is extendable by later protocol amendments, never shrinkable) " *
                "— got $(repr(m))",
            ),
        )
        m
    end,
    seed = let s = parse_kv_flag(args, "--seed", nothing)
        s === nothing ? nothing :
        let v = parse(Int, s)
            v in SEEDS || throw(
                ArgumentError(
                    "--seed $(v) is not a pre-registered seed — the protocol seed set " *
                    "(42-CASE-A-PROTOCOL.md §3) is: $(join(SEEDS, ", ")) (42 = primary/" *
                    "registered anchor). A new seed requires a protocol amendment first.",
                ),
            )
            v
        end
    end,
    time_limit_s = let tl = parse_kv_flag(args, "--time-limit-s", nothing)
        tl === nothing ? nothing :
        let v = parse(Float64, tl)
            v > 0 || throw(
                ArgumentError(
                    "--time-limit-s must be > 0 (got $v) — a budget stop is the honest " *
                    "recorded `:budget_exceeded` outcome, never a silent truncation",
                ),
            )
            v
        end
    end,
)

# ---- honest solver-outcome recording ----------------------------------------------------------

"""
    run_rung_outcome(feeder, pf, aggs; T, λ₀, rung_attrs, time_limit_s)
        -> (; status, welfare, iters, message)

ONE ladder rung: `solve_admm` at executor defaults (ρ = `ADMM().ρ` — the locked
no-re-tuning configuration; maxiter/tolerances untouched) with the rung's conditional
splat — the `default` rung adds NOTHING (byte-identical call); a tightened rung threads
`agr_optimizer = select_optimizer(QP(); rung_attrs...)` (the documented seam). A rung is
CERTIFIED iff it returns `:converged` with a finite Real welfare (the function's own
converged contract). Solver-outcome failures are RECORDED OUTCOMES per the honesty
policy: a maxiter stall (`ConvergenceError`), a certificate refusal (`CertificateError`)
and a solver failure (`SolveFailedError`) become `error:<TypeName>` rows (iters from the
error, −1 sentinel when it carries none); the typed `UnconvergedAdmmError` non-`:converged`
guard becomes `error:unconverged_admm`; the wall-clock budget exit is the honest
`:budget_exceeded` row (NO certified welfare BY DESIGN). Anything else (misuse, a bug)
PROPAGATES and exits nonzero.
"""
function run_rung_outcome(feeder, pf, aggs; T::Int, λ₀, rung_attrs, time_limit_s)
    try
        r = solve_admm(
            feeder,
            pf,
            aggs;
            T = T,
            λ₀ = λ₀,
            ρ = ADMM().ρ,
            allow_export = true,
            (
                rung_attrs === nothing ? NamedTuple() :
                (; agr_optimizer = select_optimizer(QP(); rung_attrs...))
            )...,
            time_limit_s = time_limit_s,
        )
        if r.status === :converged && r.welfare isa Real && isfinite(r.welfare)
            return (;
                status = "converged",
                welfare = Float64(r.welfare),
                iters = Int(r.iters),
                message = "",
            )
        else
            # the honest wall-clock early exit: `:budget_exceeded` carries no welfare
            # BY DESIGN (never a plausible-but-uncertified price) — a recorded outcome.
            return (;
                status = ":budget_exceeded",
                welfare = missing,
                iters = Int(r.iters),
                message = "solve_admm returned status=:budget_exceeded (time_limit_s " *
                          "budget) — no certified welfare (honest early exit)",
            )
        end
    catch err
        if err isa ConvergenceError || err isa CertificateError || err isa SolveFailedError
            return (;
                status = "error:" * string(nameof(typeof(err))),
                welfare = missing,
                iters = err.iterations === nothing ? -1 : Int(err.iterations),
                message = first(string(err.msg), 400),
            )
        elseif err isa UnconvergedAdmmError
            return (;
                status = "error:unconverged_admm",
                welfare = missing,
                iters = -1,
                message = first(string(err.msg), 400),
            )
        else
            rethrow()
        end
    end
end

"""
    run_ladder_outcome(feeder, pf, aggs; T, λ₀, time_limit_s)
        -> (; rows, certified)

The PRE-REGISTERED AGR ladder (protocol §4): run `AGR_TOL_RUNGS` in declared order,
STOP-ON-FIRST-CERTIFIED, HARD STOP after the last rung. Every rung attempt is one row
(refusals included); if every executed rung refuses, the terminal state is the recorded
`error:ladder_exhausted` row — the DOCUMENTED NON-CLOSURE, never an out-of-Dict
tolerance. `certified` is the winning rung row (with its Real `welfare_dadp`) or
`nothing`.
"""
function run_ladder_outcome(feeder, pf, aggs; T::Int, λ₀, time_limit_s)
    rows = NamedTuple[]
    certified = nothing
    for rung in AGR_RUNG_ORDER
        rung_attrs = AGR_TOL_RUNGS[rung]
        println(
            "  ladder rung '",
            rung,
            "': ",
            rung_attrs === nothing ? "plain QP factory (executor default)" :
            string(rung_attrs),
            " — solving...",
        )
        flush(stdout)
        wall_s = @elapsed outcome = run_rung_outcome(
            feeder,
            pf,
            aggs;
            T = T,
            λ₀ = λ₀,
            rung_attrs = rung_attrs,
            time_limit_s = time_limit_s,
        )
        row = (
            kind = "rung",
            rung = rung,
            status = outcome.status,
            welfare_dadp = outcome.welfare,
            welfare_fit = missing,
            delta_w = missing,
            delta_pct = missing,
            iters = outcome.iters,
            wall_s = wall_s,
            note = flatten_note(outcome.message),
        )
        push!(rows, row)
        println(
            "  ladder rung '",
            rung,
            "': ",
            outcome.status,
            " iters=",
            outcome.iters,
            " (",
            round(wall_s; digits = 1),
            " s)",
        )
        flush(stdout)
        if outcome.welfare isa Real
            certified = row
            break   # STOP-ON-FIRST-CERTIFIED (protocol §4)
        end
    end
    if certified === nothing
        # HARD STOP after the last rung — the honest terminal state is the DOCUMENTED
        # NON-CLOSURE, recorded as its own row (never an out-of-Dict tolerance).
        push!(
            rows,
            (
                kind = "rung",
                rung = "(ladder)",
                status = "error:ladder_exhausted",
                welfare_dadp = missing,
                welfare_fit = missing,
                delta_w = missing,
                delta_pct = missing,
                iters = missing,
                wall_s = missing,
                note = "every pre-registered AGR rung refused — the documented " *
                       "non-closure (protocol §4); no tolerance outside the Dict was tried",
            ),
        )
        println(
            "  ladder EXHAUSTED: all pre-registered rungs refused — recorded as " *
            "error:ladder_exhausted (hard stop; no out-of-Dict tolerance)",
        )
        flush(stdout)
    end
    return (; rows = rows, certified = certified)
end

# ---- the FIT leg (unchanged fit_baseline + the ONE pinned retry) ------------------------------

function _fit_result(fb; note::String, retry::String)
    if fb.welfare isa Real && isfinite(fb.welfare)
        return (;
            status = "ok",
            welfare_fit = Float64(fb.welfare),
            message = note,
            retry = retry,
        )
    else
        return (;
            status = "fit_inexact",
            welfare_fit = missing,
            message = note * " — fit_baseline reported a non-certified outcome " *
                      "(on_inexact = :report; social_fit = $(fb.social_fit))",
            retry = retry,
        )
    end
end

"""
    run_fit_outcome(feeder, pf, aggs; T, λ₀) -> (; status, welfare_fit, message, retry)

The FIT leg: `fit_baseline` UNCHANGED (batteryless by design, thesis Assumption A4) with
`on_inexact = :report` (protocol §5's registered call). On a typed solver failure
(`SolveFailedError`/`CertificateError`/`ConvergenceError` — the committed ieee13-ground
FIT INFEASIBLE precedent is exactly this class) the protocol-pinned ONE retry runs with
the SOLVER tightened (`select_optimizer(QP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)`)
— a SOLVER change, never a gate change. BOTH the attempt and the retry outcomes are
recorded in the returned status/note; a still-refused leg after the single retry is a
recorded outcome. Anything else PROPAGATES.
"""
function run_fit_outcome(feeder, pf, aggs; T::Int, λ₀)
    local fb
    try
        fb = fit_baseline(feeder, pf, aggs; T = T, λ₀ = λ₀, on_inexact = :report)
    catch err
        (err isa ConvergenceError) || (err isa CertificateError) ||
            (err isa SolveFailedError) || rethrow()
        status = "error:" * string(nameof(typeof(err)))
        message = first(string(err.msg), 400)
        println(
            "  FIT leg: ",
            status,
            " at the registered call — the protocol-pinned ONE retry (SOLVER tightened " *
            "to tol_gap 1e-10; never a gate, never ρ, never battery τ)...",
        )
        flush(stdout)
        try
            fb = fit_baseline(
                feeder,
                pf,
                aggs;
                T = T,
                λ₀ = λ₀,
                on_inexact = :report,
                optimizer = select_optimizer(QP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10),
            )
        catch err2
            (err2 isa ConvergenceError) || (err2 isa CertificateError) ||
                (err2 isa SolveFailedError) || rethrow()
            return (;
                status = "error:" * string(nameof(typeof(err2))),
                welfare_fit = missing,
                message = "attempt: " * status * " (" * first(message, 200) * "); " *
                          "pinned retry also refused: " * first(string(err2.msg), 200),
                retry = "tol_gap_1e-10",
            )
        end
        return _fit_result(
            fb;
            note = "attempt: " * status * "; pinned retry (tol_gap_1e-10) certified",
            retry = "tol_gap_1e-10",
        )
    end
    return _fit_result(fb; note = "registered call (on_inexact = :report)", retry = "none")
end

# ---- the SHARED measurement point (the "same code path" claim, made structural) ---------------

"""
    _measure_point(feeder_sym, pop_sym, seed; T, time_limit_s) -> Vector{NamedTuple}

ONE measurement point — the ladder, the FIT leg, and the gain — SHARED by the headline
and proxy modes (the protocol §8 "same code path" claim is this function, not a
description). Returns the point's rows: one per rung attempt (+ the terminal
`error:ladder_exhausted` row when the ladder closes empty) and one gain row.
"""
function _measure_point(
    feeder_sym::Symbol,
    pop_sym::Symbol,
    seed::Int;
    T::Int = T_H,
    time_limit_s = nothing,
)
    # The FROZEN REGISTERED CONFIGURATION (42-CASE-A-PROTOCOL.md §2), spelled out:
    #     feeder   = build_feeder(:ieee13)
    #     profiles = generate_profiles(; seed = sub_seed(SEED, :profiles), T = 24)
    #     λ₀       = build_price(:mem, 24, nothing)
    #     pf       = ConvexBranchFlow()
    #     aggs     = build_population(:case_a_784, feeder, :ieee13, profiles, sub_seed(SEED, :population))
    # The generic calls below ARE that configuration with (feeder_sym, pop_sym, seed)
    # bound; the headline binds (:ieee13, :case_a_784, seed) — byte-for-byte the
    # registered point. NO value here is a free constant beyond what the seams require.
    feeder = build_feeder(feeder_sym)
    profiles = generate_profiles(; seed = sub_seed(seed, :profiles), T = T)
    λ₀ = build_price(PRICE_SYM, T, nothing)
    pf = ConvexBranchFlow()
    aggs = build_population(pop_sym, feeder, feeder_sym, profiles, sub_seed(seed, :population))
    if pop_sym === :case_a_784
        # Fail-loud population-shape tripwire (the case_a_agreement idiom): each house
        # contributes exactly 3 devices rolled into its bus aggregator.
        houses = div(sum(length(a.devices) for a in aggs), 3)
        houses == _CASE_A_TOTAL_HOUSES || error(
            "case_a_magnitude: the built :case_a_784 population carries $houses houses " *
            "(3 devices each) but the selector's total is $_CASE_A_TOTAL_HOUSES — the " *
            "population shape changed; re-measure deliberately (aborting loudly)",
        )
    end
    println(
        "  point :",
        pop_sym,
        " @ :",
        feeder_sym,
        " seed=",
        seed,
        ": ",
        length(aggs),
        " aggregators — AGR ladder (stop-on-first-certified)...",
    )
    flush(stdout)
    ladder = run_ladder_outcome(feeder, pf, aggs; T = T, λ₀ = λ₀, time_limit_s = time_limit_s)

    println("  FIT leg (fit_baseline unchanged; on_inexact = :report)...")
    flush(stdout)
    fit_out = run_fit_outcome(feeder, pf, aggs; T = T, λ₀ = λ₀)
    println("  → FIT leg: ", fit_out.status)
    flush(stdout)

    rows = NamedTuple[]
    append!(rows, ladder.rows)
    if ladder.certified !== nothing &&
       fit_out.welfare_fit isa Real &&
       isfinite(fit_out.welfare_fit)
        # The ONLY gain computation in this script — the registered SIGN-SAFE definition
        # from the shared lib (protocol §1). The banned naive ratio appears nowhere.
        g = welfare_gain(ladder.certified.welfare_dadp, fit_out.welfare_fit)
        push!(
            rows,
            (
                kind = "gain",
                rung = ladder.certified.rung,
                status = "ok",
                welfare_dadp = ladder.certified.welfare_dadp,
                welfare_fit = fit_out.welfare_fit,
                delta_w = g.Δ,
                delta_pct = g.Δpct,
                iters = missing,
                wall_s = missing,
                note = "SIGN-SAFE registered gain (protocol §1): DADP ladder rung " *
                       "'$(ladder.certified.rung)' vs FIT leg ($(fit_out.retry)); " *
                       "the naive W_DADP/W_FIT ratio is banned",
            ),
        )
    else
        why = ladder.certified === nothing ?
              "no AGR ladder rung certified (ladder exhausted — documented non-closure)" :
              "DADP certified at rung '$(ladder.certified.rung)' but the FIT leg did not certify"
        push!(
            rows,
            (
                kind = "gain",
                rung = ladder.certified === nothing ? "(none)" : ladder.certified.rung,
                status = fit_out.status,
                welfare_dadp = ladder.certified === nothing ? missing :
                               ladder.certified.welfare_dadp,
                welfare_fit = fit_out.welfare_fit isa Real ? fit_out.welfare_fit : missing,
                delta_w = missing,
                delta_pct = missing,
                iters = missing,
                wall_s = missing,
                note = flatten_note(
                    "no certified pair — " *
                    why *
                    "; FIT: " *
                    (isempty(fit_out.message) ? "no certified welfare" : fit_out.message),
                ),
            ),
        )
    end
    return rows
end

# ---- CSV upsert machinery (the tariff_comparison.jl idiom) ------------------------------------

"""
    upsert_row(path, row::NamedTuple; key) -> nothing

Append-or-replace `row` in the CSV at `path`, keyed on `key` (a tuple of column names):
existing rows whose key matches the new row's are REPLACED, all other rows are kept
(`cols = :union` merges column sets across schema evolution). Header is written on
create. Re-runs replace their own rows and never drop siblings' rows; a kill mid-run
leaves the rows already captured (honesty policy — a kill is a measured outcome).
"""
function upsert_row(path::String, row::NamedTuple; key::NTuple{N, Symbol} where {N})
    mkpath(dirname(path))
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
    ensure_schema(path, cols) -> nothing

Guarantee the CSV exists (header-only when no row was ever captured): an empty table is
the HONEST content of a mode whose run-level failure left zero certified rows (a missing
FILE would read as "the measurement never ran"; a header-only table reads as "it ran and
certified nothing").
"""
function ensure_schema(path::String, cols::Vector{Symbol})
    mkpath(dirname(path))
    isfile(path) || CSV.write(path, DataFrame([Any[] for _ in cols], cols))
    return nothing
end

const MEASURE_COLS = Symbol[
    :kind,
    :rung,
    :status,
    :welfare_dadp,
    :welfare_fit,
    :delta_w,
    :delta_pct,
    :iters,
    :wall_s,
    :note,
    :protocol_sha,
    :julia_version,
    :threads,
    :blas_threads,
    :seed,
    :t_horizon,
]
const MAGNITUDE_COLS = Symbol[:mode; MEASURE_COLS]
const PROXY_COLS = Symbol[:fixture; MEASURE_COLS]

# WR-04 discipline: the ACTIVE mode's artifact EXISTS (header-only when nothing was
# captured) BEFORE any failure branch — a run-level failure must ship its honest empty
# table, never a missing FILE. Per-mode by design: each mode writes exactly its own
# artifact, so the guarantee covers that mode's every exit path.
function ensure_all_schemas(mode::String)
    if mode == "headline"
        ensure_schema(MAGNITUDE_CSV, MAGNITUDE_COLS)
    else
        ensure_schema(PROXY_CSV, PROXY_COLS)
    end
    return nothing
end

"""
    write_point_rows(path, cols, identity, rows, T_H, seed; key) -> nothing

Upsert one CSV row per measurement row: identity columns (mode/fixture + the row's own
kind/rung), then the measured columns, then `protocol_sha`, then the provenance stamp —
the plan's row merge order. The upsert key carries the row-granularity columns (kind,
rung) so sibling rows of the same run replace only themselves.
"""
function write_point_rows(
    path::String,
    cols::Vector{Symbol},
    identity::NamedTuple,
    rows::Vector{<:NamedTuple},
    T_H::Int,
    seed::Int;
    key::NTuple{N, Symbol} where {N},
)
    for r in rows
        row = merge(
            identity,
            r,
            (protocol_sha = PROTOCOL_SHA[],),
            provenance_row(T_H, seed),
        )
        # Guard the MERGED row: the raw measurement rows carry the measured columns;
        # identity + protocol_sha + provenance are merged here (the plan's row merge
        # order) — the WRITTEN row must carry every declared column.
        all(c in keys(row) for c in cols) || error(
            "case_a_magnitude: row is missing a declared column — merged row has " *
            "$(keys(row)), declared $cols",
        )
        upsert_row(path, row; key = key)
    end
    return nothing
end

# ---- modes ------------------------------------------------------------------------------------

function headline_main(seed::Int, time_limit_s)
    assert_protocol_registered()   # the guard is the mains' first statement too — the
    # CLI path inherits it from main; a direct call is gated independently (T-42-03-1).
    BLAS.set_num_threads(1)
    ensure_all_schemas("headline")
    println(
        "case_a_magnitude headline: seed=",
        seed,
        " (protocol §3), T=",
        T_H,
        ", ρ=",
        ADMM().ρ,
        " (executor default, NO re-tuning), time_limit_s=",
        repr(time_limit_s),
        " — measuring the registered 784-house point (LONG-RUNNING)...",
    )
    flush(stdout)
    wall_s = @elapsed rows = _measure_point(FEEDER_SYM, :case_a_784, seed; time_limit_s)
    write_point_rows(
        MAGNITUDE_CSV,
        MAGNITUDE_COLS,
        (mode = "headline",),
        rows,
        T_H,
        seed;
        key = (:mode, :seed, :t_horizon, :kind, :rung),
    )
    for r in rows
        println(
            "  → [",
            r.kind,
            "] rung=",
            r.rung,
            " status=",
            r.status,
            " welfare_dadp=",
            repr(r.welfare_dadp),
            " welfare_fit=",
            repr(r.welfare_fit),
            " delta_pct=",
            repr(r.delta_pct),
        )
    end
    flush(stdout)
    println(
        "case_a_magnitude headline seed=",
        seed,
        " complete in ",
        round(wall_s; digits = 1),
        " s → ",
        MAGNITUDE_CSV,
    )
    flush(stdout)
    return nothing
end

function proxy_main(time_limit_s)
    assert_protocol_registered()   # the guard is the mains' first statement too (T-42-03-1)
    BLAS.set_num_threads(1)
    ensure_all_schemas("proxy")
    println(
        "case_a_magnitude proxy: ",
        length(PROXY_FIXTURES),
        " protocol-pinned fixtures (ieee123/20260719 → ieee13/20260718), T=",
        T_H,
        ", time_limit_s=",
        repr(time_limit_s),
        " — certifying the measurement machinery at proxy scale...",
    )
    flush(stdout)
    wall_s = @elapsed for fx in PROXY_FIXTURES
        rows = _measure_point(fx.feeder_sym, fx.pop_sym, fx.seed; time_limit_s)
        write_point_rows(
            PROXY_CSV,
            PROXY_COLS,
            (fixture = fx.fixture,),
            rows,
            T_H,
            fx.seed;
            key = (:fixture, :seed, :t_horizon, :kind, :rung),
        )
        println("  → $(fx.fixture): $(length(rows)) rows recorded")
        flush(stdout)
    end
    println(
        "case_a_magnitude proxy complete in ",
        round(wall_s; digits = 1),
        " s → ",
        PROXY_CSV,
    )
    flush(stdout)
    return nothing
end

# ---- entry ------------------------------------------------------------------------------------

function main(args)
    # THE PRE-REGISTRATION GATE — the FIRST executed code path (T-42-03-1): no protocol
    # file → no run; an uncommitted protocol → no run. Everything below exists only to
    # serve a measurement under the committed protocol version stamped on every row.
    PROTOCOL_SHA[] = assert_protocol_registered()
    parsed = parse_args!(args)
    if parsed.mode == "proxy" && parsed.seed !== nothing
        throw(
            ArgumentError(
                "--seed is not valid with --mode proxy — the proxy fixtures pin their " *
                "own protocol seeds (ieee123-default → 20260719, the ≈+0.263% provenance " *
                "fixture; ieee13-default → 20260718, the ground-fixture regression seed)",
            ),
        )
    end
    println(
        "case_a_magnitude: mode=",
        parsed.mode,
        " protocol_sha=",
        PROTOCOL_SHA[],
        " threads=",
        Threads.nthreads(),
        " blas=",
        BLAS.get_num_threads(),
        " (pinning BLAS to 1)",
    )
    flush(stdout)
    if parsed.mode == "headline"
        headline_main(parsed.seed === nothing ? REGISTERED_SEED : parsed.seed, parsed.time_limit_s)
    else
        proxy_main(parsed.time_limit_s)
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
