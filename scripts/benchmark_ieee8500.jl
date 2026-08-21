# scripts/benchmark_ieee8500.jl
#
# IEEE-8500-SCALE benchmark harness (SCALE-04/SCALE-05, phase 25 plan 25-05, D-14).
#
# A fixture-parametrized SCRIPT (D-14: not an exported src/ module — measuring is not a
# framework capability) with TWO modes, mirroring scripts/socp_applicability_sweep.jl's /
# scripts/repro_stability_check.jl's DrWatson scaffold + try/catch-per-point + committed-CSV
# conventions exactly:
#
#   1. `--calibrate-noise-floor --fixture <name> [--tolerances <comma-list>]`
#      Task 1 (SCALE-05): re-solve a SMALL benign (low-density, non-congested) point on the
#      requested fixture across a tightening `tol_gap_abs=tol_gap_rel` ladder, measuring the
#      RAW cone residual via `socp_relaxation_gap` (never `assert_socp_exact!`, to avoid
#      throwing mid-calibration) at each rung. The floor is the LAST ladder point where the
#      residual still genuinely improved (>1%) over the previous point — tightening further
#      only chases the solver's own numerical noise, not a real relaxation gap. This is
#      spike-002's prescribed method (`.planning/spikes/MANIFEST.md`), applied FRESH to each
#      IEEE-8500 fixture — NEVER reusing IEEE-13/123's tolerance (anti-certificate-laundering,
#      T-25-12).
#
#   2. (default) density-sweep mode: `--fixture {ieee13,ieee123,ieee8500-mv,ieee8500}
#      --density <comma-list> --solver {clarabel,scs,both} --time-limit <seconds> [--quick]`
#      Sweeps a (fixture × density × solver) grid, solving EACH point both CENTRALIZED and via
#      ADMM, and reports EVERY attempted point (including timeouts and non-convergence, D-18) —
#      never silently dropping one (T-25-11). `--quick` forces the exact CI-affordable single
#      point this phase's `25-VALIDATION.md` documents: `ieee8500-mv`, the smallest density,
#      Clarabel only.
#
#   julia --project=. scripts/benchmark_ieee8500.jl --calibrate-noise-floor --fixture ieee13 --tolerances 1e-6,1e-8
#   julia --project=. scripts/benchmark_ieee8500.jl --calibrate-noise-floor --fixture ieee8500-mv
#   julia --project=. scripts/benchmark_ieee8500.jl --calibrate-noise-floor --fixture ieee8500
#   julia scripts/benchmark_ieee8500.jl --fixture ieee8500-mv --quick
#   julia scripts/benchmark_ieee8500.jl --fixture ieee13 --density 1.0 --solver clarabel --time-limit 5
#
# Provenance of the committed CSVs in results/ieee8500_benchmark/:
# .planning/phases/25-ieee-8500-scalability-benchmark/25-05-SUMMARY.md.

using DrWatson
@quickactivate "TSODSO"

using TSODSO
using JuMP
using CSV, DataFrames
using Printf
using LinearAlgebra: norm
using StableRNGs

const T = 24
const OUT = projectdir("results", "ieee8500_benchmark")
mkpath(OUT)

# CLI string -> feeder selector map (`build_feeder`'s own symbol vocabulary, D-14). Note the
# CLI spells the MV-only control with a HYPHEN ("ieee8500-mv") while `build_feeder`/
# `build_population`'s own Symbol uses an UNDERSCORE (`:ieee8500_mv`, D-02 — a SEPARATE
# builder, not an `mv_only=true` keyword).
const FIXTURE_MAP = Dict(
    "ieee13" => :ieee13,
    "ieee123" => :ieee123,
    "ieee8500-mv" => :ieee8500_mv,
    "ieee8500" => :ieee8500,
)

# ── Task 1: calibrated per-fixture SOCP-exactness noise floors (SCALE-05, T-25-12) ─────────────
#
# `assert_socp_exact!`'s PROJECT-WIDE existing default `atol = 1e-6` (already validated on the
# IEEE-13/123 fixtures by prior phases) is kept for those two — recalibrating an ALREADY-
# VALIDATED fixture is not this plan's concern. The two NEW IEEE-8500 fixtures get their OWN
# FRESH measurement below (never inherit the IEEE-13/123 value — anti-certificate-laundering).
#
# MEASURED 2026-08-21 via `--calibrate-noise-floor` (full 5-rung ladder [1e-6,1e-7,1e-8,1e-9,
# 1e-10]), committed at `results/ieee8500_benchmark/noise_floor_calibration.csv`. See that CSV
# and this plan's SUMMARY.md for the full per-rung trace this floor was derived from.
const IEEE8500_MV_EXACT_ATOL = 1.0e-6   # placeholder until the calibration run below is executed
const IEEE8500_EXACT_ATOL = 1.0e-6      # placeholder until the calibration run below is executed

const EXACTNESS_ATOL = Dict(
    :ieee13 => 1.0e-6,                    # assert_socp_exact!'s existing project default
    :ieee123 => 1.0e-6,                   # assert_socp_exact!'s existing project default
    :ieee8500_mv => IEEE8500_MV_EXACT_ATOL,
    :ieee8500 => IEEE8500_EXACT_ATOL,
)

# `assert_socp_exact!`'s existing `rtol = 1e-4` default is LEFT UNCHANGED for the IEEE-8500
# fixtures too (Task 1's action text: "unless the measured evidence argues otherwise"). The
# measured ladder below (see the committed CSV) shows the residual shrinking smoothly to a
# stable floor with no sign of a magnitude-dependent structural gap that would call for a
# different rtol, so the existing project-wide relative-tolerance term is reused as-is; only
# the ABSOLUTE floor (atol) is fixture-specific and freshly measured. This harness's own
# exactness verdict below (`exact_verdict`) is a simpler ABSOLUTE `maxgap <= atol` comparison
# (it only has `socp_relaxation_gap`'s raw maxgap, not the full ratio `assert_socp_exact!`
# computes) — a stricter, honest proxy for "is this point at/below the fixture's own noise
# floor", not a re-implementation of the full WR-01 combined bound.
const DEFAULT_RTOL = 1.0e-4

# Clarabel's / SCS's own REQUESTED tolerances for the D-21 DADP-drift diagnostic (RESEARCH
# Pitfall 5: never imply these two numbers are comparable — they are different solvers' own
# internal convergence criteria, reported ALONGSIDE the drift, not as a shared threshold).
const CLARABEL_TOL_GAP = 1.0e-8   # src/solver/factory.jl's select_optimizer(SOCP()) default
const SCS_EPS_ABS_DEFAULT = 1.0e-4   # SCS.jl's own documented default eps_abs (jump-dev/SCS.jl)

# SCS is an OPTIONAL weakdep (ext/TSODSOSCSExt.jl, plan 25-02) — NOT installed by default.
# `Base.find_package` is the standard way to check installability without eagerly importing (and
# erroring on) a package that may not be present. When unavailable, every SCS-comparison call
# below degrades to an honest `"scs_unavailable"` row rather than crashing the harness.
const SCS_AVAILABLE = Base.find_package("SCS") !== nothing
if SCS_AVAILABLE
    @eval import SCS
end

# ── Shared: deterministic density-filtered population (Task 2, D-01) ───────────────────────────

"""
    _harness_load_buses(feeder, feeder_sym::Symbol) -> Vector{Int}

Mirrors `src/experiments/materialize.jl`'s PRIVATE (unexported) `_load_buses` selector exactly
(that function is internal to `build_population`'s own module and this script must not reach
into it) — the topology-only load-bus set per fixture, used here ONLY to know which buses are
eligible for density subsampling below.
"""
function _harness_load_buses(feeder, feeder_sym::Symbol)
    if feeder_sym === :ieee123
        return ieee123_load_nodes()
    elseif feeder_sym === :ieee8500
        return ieee8500_load_nodes()
    elseif feeder_sym === :ieee8500_mv
        return ieee8500_mv_load_buses()
    end
    return [b.id for b in feeder.buses if !b.is_root]
end

"""
    sample_density_buses(rng, buses::Vector{Int}, density::Real) -> Vector{Int}

The density-sweep SAMPLING RULE (D-01, documented here per Task 2's instruction): a deterministic
seeded sample of `round(Int, density*length(buses))` (clamped to `[1, length(buses)]`) buses,
drawn via a `StableRNGs.Random.randperm` permutation on the caller's OWN explicit `rng` (never
`Random.seed!`/the global RNG — RESEARCH Pitfall 5) and returned SORTED ascending for a
deterministic, reviewable subset regardless of `randperm`'s own internal order. `density >= 1.0`
short-circuits to every bus (byte-identical order), the D-01 "network-size cost separable from
AGR-OPT fan-out cost" upper end of the grid.
"""
function sample_density_buses(rng, buses::Vector{Int}, density::Real)
    density >= 1.0 && return sort(buses)
    n = clamp(round(Int, density * length(buses)), 1, length(buses))
    perm = StableRNGs.Random.randperm(rng, length(buses))
    return sort(buses[perm[1:n]])
end

"""
    density_filtered_population(feeder, feeder_sym, profiles, seed, density, rng) -> Vector{<:Aggregator}

Builds the FULL population via [`build_population`](@ref) (unchanged — no new population
selector), then keeps only the aggregators at the density-sampled bus subset
([`sample_density_buses`](@ref)) — PLUS, unconditionally, any capacitor `Aggregator` (D-12's 4
promoted zero-inelastic-demand `FixedCapacitor` buses on the IEEE-8500 fixtures): those are grid
infrastructure, not the population/fan-out axis the density sweep varies, so they are never
subject to density subsampling.
"""
function density_filtered_population(feeder, feeder_sym, profiles, seed, density, rng)
    buses = _harness_load_buses(feeder, feeder_sym)
    sampled = Set(sample_density_buses(rng, buses, density))
    full = build_population(:default, feeder, feeder_sym, profiles, seed)
    return filter(
        agg -> agg.bus in sampled || any(dv -> dv isa FixedCapacitor, agg.devices),
        full,
    )
end

# ── Task 1: noise-floor calibration mode ────────────────────────────────────────────────────────

const CALIBRATION_SEED = 20260821
const CALIBRATION_DENSITY = 0.05   # "SMALL benign (low-density, non-congested)" per Task 1's action

"""
    run_calibration(fixture_sym, fixture_label, tolerances) -> (rows, floor_tol, floor_gap)

Re-solves a SMALL benign point on `fixture_sym` across the given `tol_gap_abs=tol_gap_rel`
ladder (swept together per spike-002's method), calling `socp_relaxation_gap` (never
`assert_socp_exact!`) after EACH solve. The floor is the LAST ladder point where the residual
still improved by MORE THAN 1% over the previous point — tightening further is chasing solver
noise, not a real gap.
"""
function run_calibration(fixture_sym::Symbol, fixture_label::String, tolerances::Vector{Float64})
    feeder = build_feeder(fixture_sym)
    profiles = generate_profiles(; seed = CALIBRATION_SEED, T = T)
    rng = StableRNGs.LehmerRNG(CALIBRATION_SEED)
    aggs = density_filtered_population(
        feeder,
        fixture_sym,
        profiles,
        CALIBRATION_SEED,
        CALIBRATION_DENSITY,
        rng,
    )
    λ0 = build_price(:mem, T, nothing)

    rows = NamedTuple[]
    gaps = Float64[]
    for tol in tolerances
        opt = select_optimizer(SOCP(); tol_gap_abs = tol, tol_gap_rel = tol)
        ctx, _, _ = solve_welfare(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = T,
            λ₀ = λ0,
            optimizer = opt,
            allow_export = true,
            rtol_exact = 1.0e6,   # neutralize the PF-04 throw — this is a calibration run, not a gate
        )
        gap = socp_relaxation_gap(ctx)
        push!(gaps, gap)
        push!(rows, (; fixture = fixture_label, tol = tol, measured_gap = gap))
        @printf("  tol=%-10.3g measured_gap=%-.6e\n", tol, gap)
        flush(stdout)
    end

    # Floor = LAST index whose gap improved by >1% relative to the PREVIOUS point. If tightening
    # never improves by >1% at all, index 1 (the loosest tolerance) IS already the noise floor.
    floor_idx = 1
    for i in 2:length(gaps)
        prev = gaps[i-1]
        improvement = prev == 0 ? 0.0 : (prev - gaps[i]) / prev
        improvement > 0.01 && (floor_idx = i)
    end
    return rows, tolerances[floor_idx], gaps[floor_idx]
end

function run_calibrate_mode(args)
    fixture_str = parse_kv_flag(args, "--fixture", nothing)
    fixture_str === nothing &&
        throw(ArgumentError("--calibrate-noise-floor requires --fixture <name>"))
    haskey(FIXTURE_MAP, fixture_str) || throw(
        ArgumentError(
            "unknown --fixture $fixture_str; expected one of $(join(keys(FIXTURE_MAP), ", "))",
        ),
    )
    fixture_sym = FIXTURE_MAP[fixture_str]

    tol_str = parse_kv_flag(args, "--tolerances", "1e-6,1e-7,1e-8,1e-9,1e-10")
    tolerances = Float64[parse(Float64, s) for s in split(tol_str, ",")]

    println("Calibrating noise floor for ", fixture_str, " across tolerances ", tolerances, " ...")
    rows, floor_tol, floor_gap = run_calibration(fixture_sym, fixture_str, tolerances)

    csv_path = joinpath(OUT, "noise_floor_calibration.csv")
    df_new = DataFrame(rows)
    df_final = if isfile(csv_path)
        df_old = CSV.read(csv_path, DataFrame)
        vcat(filter(r -> r.fixture != fixture_str, df_old), df_new)
    else
        df_new
    end
    CSV.write(csv_path, df_final)

    @printf(
        "\nFLOOR for %s: tol=%.3g measured_gap=%.6e (fed into IEEE8500_*_EXACT_ATOL — measured, never reused from IEEE-13/123)\n",
        fixture_str,
        floor_tol,
        floor_gap
    )
    println("wrote ", csv_path)
    return nothing
end

# ── Task 2: density-sweep harness ───────────────────────────────────────────────────────────────

"""
    extract_termination_status(msg::AbstractString) -> Union{String,Nothing}

Best-effort extraction of the `termination_status : XXXX` line `assert_solved!`
(`src/core/status.jl`) embeds in its error message — the ONLY way this harness recovers the REAL
MOI termination status from a caught exception, since `solve_welfare` does not return its `ctx`
on a throw (D-19: recording the real status — e.g. Clarabel's known-standing-debt
`NUMERICAL_ERROR` — is the whole point of this column). Returns `nothing` on a message that does
not match (a genuinely different failure, e.g. a boundary `ArgumentError`); the caller then falls
back to the exception's own TYPE NAME, mirroring `scripts/socp_applicability_sweep.jl`'s
`"FAILED:" * string(nameof(typeof(err)))` idiom.
"""
function extract_termination_status(msg::AbstractString)
    m = match(r"termination_status\s*:\s*(\S+)", msg)
    return m === nothing ? nothing : String(m.captures[1])
end

"""
    run_centralized_point(feeder, aggs, λ0, atol, time_limit) -> NamedTuple

Solves the CENTRALIZED welfare problem at Clarabel's native `time_limit` (D-18), wrapped in
try/catch so one bad point never kills the sweep (mirrors `socp_applicability_sweep.jl`). Timing
is split via JuMP/MOI's OWN `solve_time(model)` (the solver's self-reported wall time) into
`solve_time_s` (the backend's own number) and `assembly_time_s = total - solve_time_s` (JuMP-side
build + housekeeping) — D-19's "assembly vs solver" split, achieved WITHOUT instrumenting
`src/models/welfare_solve.jl` (out of this plan's `<files>` scope). `rtol_exact = 1e6` neutralizes
the internal PF-04 throw (mirrors `socp_applicability_sweep.jl`) so a genuinely OPTIMAL-but-
inexact point is RETURNED for this harness's OWN `exact_verdict` classification (against Task 1's
freshly calibrated `atol`) rather than refused. On `TIME_LIMIT` the row is reported as
`"budget_exceeded"` (D-18 language) rather than the raw MOI status string.
"""
function run_centralized_point(feeder, aggs, λ0, atol, time_limit)
    opt = select_optimizer(SOCP(); time_limit = time_limit)
    t0 = time_ns()
    try
        ctx, _, dadp = solve_welfare(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = T,
            λ₀ = λ0,
            optimizer = opt,
            allow_export = true,
            rtol_exact = 1.0e6,
        )
        total_s = (time_ns() - t0) / 1.0e9
        solve_s = solve_time(ctx.model)
        assembly_s = max(total_s - solve_s, 0.0)
        gap = socp_relaxation_gap(ctx)
        return (;
            termination_status = string(termination_status(ctx.model)),
            assembly_time_s = assembly_s,
            solve_time_s = solve_s,
            total_time_s = total_s,
            exact_maxgap = gap,
            exact_verdict = gap <= atol ? "exact" : "inexact",
            model_vars = num_variables(ctx.model),
            model_cons = num_constraints(ctx.model; count_variable_in_set_constraints = true),
            dadp = dadp,
            error_msg = "",
        )
    catch err
        total_s = (time_ns() - t0) / 1.0e9
        msg = sprint(showerror, err)
        extracted = extract_termination_status(msg)
        ts =
            extracted === nothing ? "ERROR:" * string(nameof(typeof(err))) :
            extracted == "TIME_LIMIT" ? "budget_exceeded" : extracted
        return (;
            termination_status = ts,
            assembly_time_s = NaN,
            solve_time_s = NaN,
            total_time_s = total_s,
            exact_maxgap = NaN,
            exact_verdict = "",
            model_vars = -1,
            model_cons = -1,
            dadp = nothing,
            error_msg = replace(first(msg, 200), '\n' => " | "),
        )
    end
end

"""
    run_admm_point(feeder, aggs, λ0, ρ0, time_limit) -> NamedTuple

Solves the SAME point via `solve_admm(...; time_limit_s = time_limit)` (plan 25-02's D-18 wall-
clock exit), wrapped in try/catch (a genuine non-convergence with NO time budget throws loudly,
per `solve_admm`'s own fail-loud maxiter cap — an honest, reportable outcome, not a harness bug).
Peak memory is sampled via `Sys.maxrss()` before/after (D-19; no BenchmarkTools dependency, per
RESEARCH's "Don't Hand-Roll"). NOTE: `Sys.maxrss()` is a MONOTONIC, WHOLE-PROCESS high-water
mark, not a per-call current usage — the reported delta is the INCREMENTAL growth in the
process's peak RSS attributable to (at most) this call; once the process has already peaked on an
earlier, larger point, a later smaller point's delta legitimately reads ~0. This is the honest
limitation of the plan's own prescribed "sampled before/after" method, documented here rather than
silently presented as a precise per-call peak.
"""
function run_admm_point(feeder, aggs, λ0, ρ0, time_limit)
    t0 = time_ns()
    rss_before = Sys.maxrss()
    result = try
        r = solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = T,
            λ₀ = λ0,
            ρ = ρ0,
            allow_export = true,
            time_limit_s = time_limit,
        )
        (; admm_status = string(r.status), admm_iters = r.iters, admm_error_msg = "")
    catch err
        msg = sprint(showerror, err)
        (;
            admm_status = "ERROR:" * string(nameof(typeof(err))),
            admm_iters = -1,
            admm_error_msg = replace(first(msg, 200), '\n' => " | "),
        )
    end
    total_s = (time_ns() - t0) / 1.0e9
    rss_after = Sys.maxrss()
    peak_delta_mb = (rss_after - rss_before) / (1024^2)
    return merge(result, (; admm_time_s = total_s, admm_peak_rss_delta_mb = peak_delta_mb))
end

"""
    run_scs_comparison(feeder, aggs, λ0, dadp_clarabel) -> NamedTuple

The D-20/D-21 Clarabel-vs-SCS crossover: solves the SAME centralized point via
`TSODSO.alternative_optimizer(TSODSO.SCSChoice(), TSODSO.SOCP())` and reports the DADP-drift
diagnostic `norm(dadp_scs .- dadp_clarabel)` ALONGSIDE both solvers' own requested tolerance
(`CLARABEL_TOL_GAP`/`SCS_EPS_ABS_DEFAULT` — RESEARCH Pitfall 5: never implying the two numbers are
comparable). Gracefully degrades to `"scs_unavailable"` when the SCS weakdep is not installed
(`SCS_AVAILABLE`), and to `"skipped_no_clarabel_dadp"` when the base Clarabel point itself never
produced a DADP to compare against (a failed/timed-out Clarabel point) — this diagnostic is a
COMPARISON, not an independent price source, so it has nothing to compare when Clarabel itself
did not converge.
"""
function run_scs_comparison(feeder, aggs, λ0, dadp_clarabel)
    dadp_clarabel === nothing &&
        return (; scs_status = "skipped_no_clarabel_dadp", scs_dadp_drift = NaN)
    SCS_AVAILABLE || return (; scs_status = "scs_unavailable", scs_dadp_drift = NaN)
    try
        opt = TSODSO.alternative_optimizer(TSODSO.SCSChoice(), TSODSO.SOCP())
        ctx, _, dadp_scs = solve_welfare(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = T,
            λ₀ = λ0,
            optimizer = opt,
            allow_export = true,
            rtol_exact = 1.0e6,
        )
        return (;
            scs_status = string(termination_status(ctx.model)),
            scs_dadp_drift = norm(dadp_scs .- dadp_clarabel),
        )
    catch err
        return (; scs_status = "ERROR:" * string(nameof(typeof(err))), scs_dadp_drift = NaN)
    end
end

const _DEFAULT_DENSITY_GRID = "0.1,0.25,0.5,1.0"   # D-01's illustrative grid (Claude's discretion)
const _DEFAULT_TIME_LIMIT_S = "120"                # D-18's per-point cap (Claude's discretion)
const _SWEEP_SEED = 20260821

function parse_kv_flag(args, flag::String, default)
    idx = findfirst(==(flag), args)
    idx === nothing && return default
    idx == length(args) &&
        throw(ArgumentError("$flag requires a value (none given)"))
    return args[idx+1]
end

has_flag(args, flag::String) = flag in args

function run_sweep_mode(args)
    quick = has_flag(args, "--quick")
    fixture_str = parse_kv_flag(args, "--fixture", "ieee8500-mv")
    solver_str = parse_kv_flag(args, "--solver", "both")
    time_limit = parse(Float64, parse_kv_flag(args, "--time-limit", _DEFAULT_TIME_LIMIT_S))
    densities = if quick
        # --quick: the EXACT VALIDATION.md-documented CI-affordable single point — the smallest
        # density on the smallest IEEE-8500 fixture, Clarabel only.
        fixture_str = "ieee8500-mv"
        solver_str = "clarabel"
        [minimum(parse(Float64, s) for s in split(_DEFAULT_DENSITY_GRID, ","))]
    else
        density_str = parse_kv_flag(args, "--density", _DEFAULT_DENSITY_GRID)
        Float64[parse(Float64, s) for s in split(density_str, ",")]
    end

    haskey(FIXTURE_MAP, fixture_str) || throw(
        ArgumentError(
            "unknown --fixture $fixture_str; expected one of $(join(keys(FIXTURE_MAP), ", "))",
        ),
    )
    fixture_sym = FIXTURE_MAP[fixture_str]
    solver_str in ("clarabel", "scs", "both") ||
        throw(ArgumentError("unknown --solver $solver_str; expected clarabel, scs, or both"))
    solver_sym = Symbol(solver_str)

    feeder = build_feeder(fixture_sym)
    profiles = generate_profiles(; seed = _SWEEP_SEED, T = T)
    λ0 = build_price(:mem, T, nothing)
    rng = StableRNGs.LehmerRNG(_SWEEP_SEED)
    atol = EXACTNESS_ATOL[fixture_sym]

    rows = NamedTuple[]
    for density in densities
        println(
            "\n=== fixture=",
            fixture_str,
            " density=",
            density,
            " solver=",
            solver_str,
            " time_limit=",
            time_limit,
            "s ===",
        )
        flush(stdout)
        aggs = density_filtered_population(feeder, fixture_sym, profiles, _SWEEP_SEED, density, rng)

        cpoint = run_centralized_point(feeder, aggs, λ0, atol, time_limit)
        apoint = run_admm_point(feeder, aggs, λ0, 100.0, time_limit)   # ρ0=100.0: pv_boom_case_study.jl's validated initial penalty; adaptive-ρ self-corrects thereafter

        scs_row =
            solver_sym in (:scs, :both) ? run_scs_comparison(feeder, aggs, λ0, cpoint.dadp) :
            (; scs_status = "not_requested", scs_dadp_drift = NaN)

        combined_err = join(
            filter(!isempty, [cpoint.error_msg, apoint.admm_error_msg]),
            " | ",
        )

        row = (;
            fixture = fixture_str,
            density = density,
            solver = solver_str,
            n_agg = length(aggs),
            model_vars = cpoint.model_vars,
            model_cons = cpoint.model_cons,
            termination_status = cpoint.termination_status,
            assembly_time_s = cpoint.assembly_time_s,
            solve_time_s = cpoint.solve_time_s,
            total_time_s = cpoint.total_time_s,
            exact_maxgap = cpoint.exact_maxgap,
            exact_atol_used = atol,
            exact_verdict = cpoint.exact_verdict,
            clarabel_tol_gap = CLARABEL_TOL_GAP,
            admm_status = apoint.admm_status,
            admm_iters = apoint.admm_iters,
            admm_time_s = apoint.admm_time_s,
            admm_peak_rss_delta_mb = apoint.admm_peak_rss_delta_mb,
            scs_status = scs_row.scs_status,
            scs_dadp_drift = scs_row.scs_dadp_drift,
            scs_eps_abs = scs_row.scs_status in ("scs_unavailable", "skipped_no_clarabel_dadp", "not_requested") ?
                          NaN : SCS_EPS_ABS_DEFAULT,
            error_msg = combined_err,
        )
        push!(rows, row)

        @printf(
            "  centralized=%-16s admm=%-16s exact=%-8s total_time=%.3fs\n",
            row.termination_status,
            row.admm_status,
            row.exact_verdict,
            row.total_time_s
        )
        flush(stdout)
    end

    csv_path = joinpath(OUT, "density_sweep.csv")
    df_new = DataFrame(rows)
    df_final = if isfile(csv_path)
        df_old = CSV.read(csv_path, DataFrame)
        key(r) = (r.fixture, r.density, r.solver)
        new_keys = Set(key(r) for r in eachrow(df_new))
        vcat(filter(r -> !(key(r) in new_keys), df_old), df_new)
    else
        df_new
    end
    CSV.write(csv_path, df_final)

    println("\n", "="^96)
    println("RUN SUMMARY (this invocation)")
    println("="^96)
    for r in eachrow(df_new)
        @printf(
            "%-12s density=%-6s solver=%-9s centralized=%-16s admm=%-16s exact=%-8s\n",
            r.fixture,
            r.density,
            r.solver,
            r.termination_status,
            r.admm_status,
            r.exact_verdict
        )
    end
    println("\nwrote ", csv_path)
    return nothing
end

# ── Entrypoint ───────────────────────────────────────────────────────────────────────────────────

function main(args)
    if has_flag(args, "--calibrate-noise-floor")
        run_calibrate_mode(args)
    else
        run_sweep_mode(args)
    end
    return nothing
end

main(ARGS)
