# scripts/case_a_agreement.jl
#
# POP-04 (Phase 40): the centralized-vs-ADMM AGREEMENT MEASUREMENT on the FULL 784-house
# `:case_a_784` population at the thesis Case A point — MEASUREMENT FIRST (gate-then-golden):
# this script runs BOTH engines on the SAME 10-aggregator roll-up, records the OBSERVED
# welfare and price deltas in `results/case_a_population/agreement.csv`, and derives the
# RECOMMENDED band constants from that measurement (10× the observed delta, floored at
# solver noise). The `:slow` agreement test (`test/test_population_case_a_agreement.jl`)
# pins its band FROM this measurement — never pre-loosened, never hand-picked (locked
# CONTEXT decision "Centralized vs ADMM Agreement").
#
# usage:
#   julia --project=. scripts/case_a_agreement.jl
#   julia --project=. scripts/case_a_agreement.jl --seed 42 --t-horizon 24   # the defaults
#
# Both engines, ONE population (built once, shared):
#   Leg 1 (centralized) — `solve_welfare(feeder, PF, aggs; T, λ₀, allow_export = true)` with
#       the DEFAULT optimizer. On a `CertificateError` the leg is RE-RUN with the SOLVER
#       tightened — `select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)` —
#       and the path that produced the row is recorded in the `centralized_optimizer` column
#       (`default` / `tol_gap_1e-10`). THE EXACTNESS GATE IS NEVER MODIFIED: no
#       `assert_socp_exact!` tolerance, no battery `τ`, no `rtol_exact`/`atol_exact` is
#       touched by this script — tightening the SOLVER's own convergence precision in answer
#       to a gate refusal is the established precedent (test/test_admm.jl:42-50 and the
#       `stochastic_welfare.jl` tol-gap note; research Pitfall 4: a first full-scale refusal
#       is a solver-precision artifact, not model inexactness). If the tightened leg is ALSO
#       refused, the refusal is RECORDED (missing welfare/deltas + the certificate kind in
#       the row) per the honesty policy — a refusal at full scale is a measured finding and
#       the phase-level escalation signal, never something to tune away.
#   Leg 2 (ADMM) — `solve_admm(feeder, PF, aggs; T, λ₀, ρ = ADMM().ρ)` SERIAL with executor
#       defaults everywhere (ρ is a REQUIRED kwarg sourced from the strategy's own default —
#       the locked A5 resolution / no-re-tuning configuration; maxiter/tolerances untouched).
#       `iters`, `status`, `welfare` and `exact_maxgap` are recorded whatever their values;
#       a maxiter stall (`ConvergenceError`), a certificate refusal (`CertificateError` at
#       the final consolidation) or a solver failure (`SolveFailedError`) is RECORDED as its
#       own status row (iters from the error, welfare/exact_maxgap missing) — the same
#       honest-recording contract as `scripts/case_a_scaling.jl`.
#
# CSV contract: ONE row per (julia_version, seed, t_horizon), UPSERTED with `cols = :union`
# — re-runs replace their own row and never drop others. The recommended-band columns are
# `max(10 × the observed delta, stated floor)` (floors: welfare rtol 1e-8, price atol/rtol
# 1e-6 — solver noise); they are REPRODUCIBLE from the row's own delta columns. When no
# agreement is measurable (a refused leg), the delta/band columns are missing and the
# console carries the honest reason — no band is invented.
#
# Case A constants (scripts/thesis_caseA.jl): T = 24, SEED = 42, :ieee13, :mem prices,
# profiles seed = sub_seed(SEED, :profiles), population seed = sub_seed(SEED, :population).
#
# Regenerate the committed artifact:
#   julia --project=. scripts/case_a_agreement.jl

using DrWatson
@quickactivate "TSODSO"
using TSODSO
using TSODSO:
    ADMM,
    CertificateError,
    ConvergenceError,
    ConvexBranchFlow,
    SOCP,
    SolveFailedError,
    _CASE_A_TOTAL_HOUSES,
    build_feeder,
    build_population,
    build_price,
    extract_dlmp,
    generate_profiles,
    select_optimizer,
    solve_admm,
    solve_welfare,
    sub_seed
using CSV
using DataFrames
using LinearAlgebra: BLAS

const FEEDER_SYM = :ieee13
const PRICE_SYM = :mem
# NOTE: `:tol_gap_1e-10` would PARSE AS SUBTRACTION (`:tol_gap_1e - 10`); the path tag is
# therefore built with an explicit Symbol() call.
const TOL_GAP_PATH = Symbol("tol_gap_1e-10")
const OUT_DIR = joinpath(projectdir(), "results", "case_a_population")
const AGREEMENT_CSV = joinpath(OUT_DIR, "agreement.csv")

# ---- kv-flag parsing (benchmark_ieee8500.jl / case_a_scaling.jl conventions) -----------------

function parse_kv_flag(args, flag::String, default)
    idx = findfirst(==(flag), args)
    idx === nothing && return default
    idx == length(args) && throw(ArgumentError("$flag requires a value (none given)"))
    return args[idx + 1]
end

parse_args!(args) = (
    SEED = let s = parse(Int, parse_kv_flag(args, "--seed", "42"))
        s >= 0 || throw(ArgumentError("--seed must be ≥ 0 (got $s)"))
        s
    end,
    T_H = let T = parse(Int, parse_kv_flag(args, "--t-horizon", "24"))
        T >= 1 || throw(ArgumentError("--t-horizon must be ≥ 1 (got $T)"))
        T
    end,
)

# ---- provenance + CSV upsert (case_a_scaling.jl conventions) ---------------------------------

num_or_missing(x) = x === nothing ? missing : x

"""
    upsert_row(path, row::NamedTuple; key) -> nothing

Append-or-replace `row` in the CSV at `path`, keyed on `key` (a tuple of column names):
existing rows whose key matches the new row's are REPLACED, all other rows are kept
(`cols = :union` merges column sets across schema evolution). Header is written on create.
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

# ---- Leg 1: centralized ----------------------------------------------------------------------

"""
    run_centralized(feeder, pf, aggs; T, λ₀) -> (; ctx, welfare, path, refused_kind)

Run the centralized `solve_welfare` leg. First with the DEFAULT optimizer; on a
`CertificateError` re-run with the SOLVER tightened (`tol_gap_abs/rel = 1e-10`) — the
gate is NEVER touched (test_admm.jl:42-50 precedent; see the file header). Returns the
winning `(; ctx, welfare, path)` with `path ∈ (:default, :tol_gap_1e-10)`, or — when BOTH
paths are refused — `(; ctx = nothing, welfare = missing, path = nothing, refused_kind)`
with the certificate kind of the final refusal (honest recorded outcome, never tuned away).
"""
function run_centralized(feeder, pf, aggs; T::Int, λ₀)
    try
        ctx, welfare, _ =
            solve_welfare(feeder, pf, aggs; T = T, λ₀ = λ₀, allow_export = true)
        return (; ctx = ctx, welfare = welfare, path = :default, refused_kind = nothing)
    catch err
        err isa CertificateError || rethrow()
        println(
            "centralized leg: CertificateError (kind=$(err.kind)) at the DEFAULT optimizer — " *
            "tightening the SOLVER (tol_gap_abs/rel = 1e-10), NEVER the gate " *
            "(test_admm.jl:42-50 precedent)...",
        )
        flush(stdout)
    end
    try
        ctx, welfare, _ = solve_welfare(
            feeder,
            pf,
            aggs;
            T = T,
            λ₀ = λ₀,
            allow_export = true,
            optimizer = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10),
        )
        return (; ctx = ctx, welfare = welfare, path = TOL_GAP_PATH, refused_kind = nothing)
    catch err
        err isa CertificateError || rethrow()
        println(
            "centralized leg: CertificateError (kind=$(err.kind)) ALSO at the tightened " *
            "solver — recorded honestly (full-scale refusal = the escalation signal; the " *
            "gate was never touched).",
        )
        flush(stdout)
        return (;
            ctx = nothing,
            welfare = missing,
            path = nothing,
            refused_kind = Symbol(err.kind),
        )
    end
end

# ---- Leg 2: ADMM -----------------------------------------------------------------------------

"""
    run_admm(feeder, pf, aggs; T, λ₀) -> (; status, iters, welfare, exact_maxgap, λ)

Run the ADMM leg with executor defaults (ρ = `ADMM().ρ`, the strategy's own default — a
REQUIRED kwarg; maxiter/tolerances untouched) and return its HONEST outcome. Solver-outcome
exceptions are RECORDED OUTCOMES per the honesty policy — a maxiter stall
(`ConvergenceError`), a certificate refusal (`CertificateError` at the final consolidation)
and a solver failure (`SolveFailedError`) each become a status row (iterations from the
error's own field, -1 sentinel when it carries none; welfare/exact_maxgap/λ missing — no
certified values exist). Anything else (argument misuse, a genuine bug) PROPAGATES.
"""
function run_admm(feeder, pf, aggs; T::Int, λ₀)
    try
        r = solve_admm(feeder, pf, aggs; T = T, λ₀ = λ₀, ρ = ADMM().ρ)
        return (;
            status = string(r.status),
            iters = Int(r.iters),
            welfare = num_or_missing(r.welfare),
            exact_maxgap = num_or_missing(r.exact_maxgap),
            λ = r.λ,
        )
    catch err
        err isa ConvergenceError ||
            err isa CertificateError ||
            err isa SolveFailedError ||
            rethrow()
        iters = err.iterations === nothing ? -1 : Int(err.iterations)
        kind = err isa CertificateError ? " (kind=$(err.kind))" : ""
        println(
            "ADMM leg: ",
            nameof(typeof(err)),
            kind,
            " after iters=",
            iters,
            " — recorded honestly (a full-scale non-convergence/refusal is the A5 " *
            "escalation signal, never tuned away).",
        )
        flush(stdout)
        return (;
            status = "error:" * string(nameof(typeof(err))),
            iters = iters,
            welfare = missing,
            exact_maxgap = missing,
            λ = nothing,
        )
    end
end

# ---- measurement -----------------------------------------------------------------------------

function agreement_main(SEED::Int, T_H::Int)
    # BLAS pinned to 1 for row-to-row comparability (both legs solve on the same footing).
    BLAS.set_num_threads(1)
    feeder = build_feeder(FEEDER_SYM)
    profiles = generate_profiles(; seed = sub_seed(SEED, :profiles), T = T_H)
    λ₀ = build_price(PRICE_SYM, T_H, nothing)
    pf = ConvexBranchFlow()
    # ONE population, shared by BOTH engines (the same 10-aggregator roll-up — the
    # 1:1 node↔aggregator guard's satisfied shape).
    aggs = build_population(
        :case_a_784,
        feeder,
        FEEDER_SYM,
        profiles,
        sub_seed(SEED, :population),
    )
    aggregators = length(aggs)
    # Each house contributes exactly 3 devices (Thermostatic, Deferrable, PVBattery) rolled
    # into its bus aggregator — the measured house count must equal the selector's total.
    houses = div(sum(length(a.devices) for a in aggs), 3)
    houses == _CASE_A_TOTAL_HOUSES || error(
        "case_a_agreement: the built population carries $houses houses (3 devices each) " *
        "but the selector's total is $_CASE_A_TOTAL_HOUSES — the population shape changed; " *
        "re-measure deliberately.",
    )
    load_buses = sort!([a.bus for a in aggs])

    println(
        "case_a_agreement: T=$T_H, seed=$SEED, houses=$houses, aggregators=$aggregators, " *
        "ρ=$(ADMM().ρ) (executor default) — measuring centralized-vs-ADMM agreement " *
        "(gate-then-golden)...",
    )
    flush(stdout)

    # ---- Leg 1: centralized ------------------------------------------------------------------
    centralized = run_centralized(feeder, pf, aggs; T = T_H, λ₀ = λ₀)
    welfare_c = centralized.welfare
    dlmp_c =
        centralized.ctx === nothing ? nothing : extract_dlmp(centralized.ctx)[load_buses, :]

    # ---- Leg 2: ADMM -------------------------------------------------------------------------
    admm = run_admm(feeder, pf, aggs; T = T_H, λ₀ = λ₀)

    # ---- Deltas + recommended band (only when BOTH legs certified a comparable point) --------
    measurable =
        welfare_c isa Real &&
        admm.welfare isa Real &&
        dlmp_c !== nothing &&
        admm.λ !== nothing
    if measurable
        welfare_abs = abs(admm.welfare - welfare_c)
        welfare_rel = welfare_abs / abs(welfare_c)
        price_abs = maximum(abs.(admm.λ .- dlmp_c))
        price_rel = maximum(abs.(admm.λ .- dlmp_c) ./ max.(abs.(dlmp_c), 1.0))
        # Headroom rule — 10× the observed delta, floored at solver noise.
        rec_rtol_welfare = max(10 * welfare_rel, 1e-8)
        rec_atol_price = max(10 * price_abs, 1e-6)
        rec_rtol_price = max(10 * price_rel, 1e-6)
        println(
            "MEASURED: welfare_abs_delta=$welfare_abs welfare_rel_delta=$welfare_rel " *
            "price_max_abs_delta=$price_abs price_max_rel_delta=$price_rel",
        )
        println(
            "RECOMMENDED BAND: rtol_welfare=$(rec_rtol_welfare) atol_price=$(rec_atol_price) " *
            "rtol_price=$(rec_rtol_price) — rule = 10× the observed delta, floored at " *
            "solver noise (welfare rtol floor 1e-8, price atol/rtol floor 1e-6); " *
            "derived from this run's own deltas, never pre-loosened.",
        )
    else
        welfare_abs = welfare_rel = price_abs = price_rel = missing
        rec_rtol_welfare = rec_atol_price = rec_rtol_price = missing
        println(
            "RECOMMENDED BAND: NOT DERIVABLE — no certified agreement point exists " *
            "(centralized welfare = $(repr(welfare_c)), ADMM status = $(admm.status)). " *
            "The band is pinned only from a MEASUREMENT (gate-then-golden); no constants " *
            "are invented here. This is the recorded full-scale escalation signal.",
        )
    end
    flush(stdout)

    centralized_optimizer =
        centralized.path === :default ? "default" :
        centralized.path === TOL_GAP_PATH ? "tol_gap_1e-10" :
        "refused:default+tol_gap_1e-10 kind=:$(centralized.refused_kind)"

    row = (
        julia_version = string(VERSION),
        seed = SEED,
        t_horizon = T_H,
        houses = houses,
        aggregators = aggregators,
        centralized_optimizer = centralized_optimizer,
        welfare_centralized = welfare_c isa Real ? welfare_c : missing,
        welfare_admm = admm.welfare,
        welfare_abs_delta = welfare_abs,
        welfare_rel_delta = welfare_rel,
        price_max_abs_delta = price_abs,
        price_max_rel_delta = price_rel,
        admm_iters = admm.iters,
        admm_status = admm.status,
        admm_exact_maxgap = admm.exact_maxgap,
        recommended_rtol_welfare = rec_rtol_welfare,
        recommended_atol_price = rec_atol_price,
        recommended_rtol_price = rec_rtol_price,
    )
    upsert_row(AGREEMENT_CSV, row; key = (:julia_version, :seed, :t_horizon))
    println(
        "recorded → $AGREEMENT_CSV (centralized_optimizer=$centralized_optimizer, " *
        "admm_status=$(admm.status), admm_iters=$(admm.iters))",
    )
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    parsed = parse_args!(ARGS)
    agreement_main(parsed.SEED, parsed.T_H)
end
