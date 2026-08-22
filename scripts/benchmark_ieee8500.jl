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
#      --density <comma-list> --solver {clarabel,scs,both} --time-limit <seconds>
#      [--t-horizon <int>] [--clarabel-tol <float>] [--quick]`
#      Sweeps a (fixture × density × solver) grid, solving EACH point both CENTRALIZED and via
#      ADMM, and reports EVERY attempted point (including timeouts and non-convergence, D-18) —
#      never silently dropping one (T-25-11). `--quick` forces the exact CI-affordable single
#      point this phase's `25-VALIDATION.md` documents: `ieee8500-mv`, the smallest density,
#      Clarabel only. `--t-horizon <int>` (gap-closure task) overrides the horizon used for
#      BOTH the centralized and ADMM points (recorded in the committed CSV's `T_horizon`
#      column); absent, behaviour is unchanged (`quick ? T_QUICK : T`). Rejects values below
#      the floor of 10 (see `T_HORIZON_FLOOR`'s own comment) rather than silently clamping.
#      `--clarabel-tol <float>` (2026-08-22 follow-up, quick task 260822-f0b) overrides
#      Clarabel's `tol_gap_abs`/`tol_gap_rel` for the CENTRALIZED point only; absent, behaviour
#      is `DEFAULT_CLARABEL_TOL_GAP[fixture_sym]` — `1e-7` (a MEASURED, achievable floor) for
#      `:ieee8500` only, `1e-8` (today's unconditional value, byte-identical) for every other
#      fixture. The value actually used is always recorded in the CSV's `clarabel_tol_gap`
#      column.
#      (2026-08-22 round-2 follow-up, quick task 260822-hld) The SAME per-fixture
#      `EXACTNESS_ATOL[fixture_sym]` used for the centralized `exact_verdict` is now ALSO
#      threaded into `run_admm_point`'s `solve_admm(...; atol_exact = ...)` call (the additive
#      gate-override seam quick task 260822-f0b built) — recorded in the CSV's
#      `admm_atol_used` column. This is anti-certificate-laundering-SAFE threading (T-25-12):
#      the value is always a FRESHLY MEASURED noise floor, never a literal chosen to pass a
#      specific point, and a converged point whose cone gap genuinely exceeds its fixture's
#      own floor still throws exactly as before.
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
# RE-MEASURED 2026-08-21 (phase-25 gap-closure task, after `scripts/reduce_ieee8500_impedances.jl`
# applied the D-13 near-ideal treatment to the degenerate `HVMV_Sub_48332 -> _HVMV_Sub_LSB` MV
# busbar-tie connector) via `--calibrate-noise-floor` (full 5-rung ladder [1e-6,1e-7,1e-8,1e-9,
# 1e-10]), committed at `results/ieee8500_benchmark/noise_floor_calibration.csv`. See that CSV,
# `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` item 1 (RESOLVED), and
# this gap-closure task's own `25-07-SUMMARY.md` for the full per-rung trace and before/after.
#
# WHAT CHANGED FROM THE ORIGINAL (plan 25-05) MEASUREMENT: `HVMV_Sub_48332 -> _HVMV_Sub_LSB`
# (`IEEE8500_MV_BRANCH_RX_OHMS[("HVMV_Sub_48332", "_HVMV_Sub_LSB")]`) used to carry a literal
# near-zero Ω value (`1e-6 Ω`/`1e-5 Ω`, `r≈3.2e-9 pu`) that structurally broke the LinDistFlow
# SOC-exactness gradient — the residual PLATEAUED instead of shrinking as `tol_gap` tightened.
# `reduce_ieee8500_impedances.jl`'s `reshape_near_zero_mv_edges!` now reassigns that ONE edge's
# r/x VALUES (same bus pair, same table) to the D-13 near-ideal Ω-equivalent of
# `IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` at this fixture's own MV base (`r=0.09330 Ω`,
# `x=0.04665 Ω`). The re-measured floor now GENUINELY SHRINKS as `tol_gap` tightens (both
# fixtures improve rung-over-rung before failing `ALMOST_OPTIMAL` at the tightest rungs) —
# behaving like real numerical noise rather than a structural relaxation failure. `ieee8500-mv`'s
# floor dropped from `0.1796` (tol=1e-8, plateaued) to `0.0011460` (tol=1e-8, shrinking 27x
# tighter than the tol=1e-6 rung) — a 157x improvement. `ieee8500`'s floor dropped from `0.5653`
# (tol=1e-6, EVERY tighter rung failed) to `0.0049691` (tol=1e-7).
#
# HONEST CAVEAT (still true after this fix — do NOT read this as "ADMM consolidation now
# works"): both re-measured floors are still `~1e-3` scale, which STILL exceeds `solve_admm`'s
# hardcoded final-consolidation `assert_socp_exact!` call's PROJECT DEFAULT `atol=1e-6` (no
# override parameter exists on `solve_admm` — see deferred-items.md item 3, still OPEN). A
# genuinely CONVERGED, CONSOLIDATED ADMM point on either IEEE-8500 fixture can still throw at
# that gate. This fix closes the STRUCTURAL relaxation failure; it does NOT close the numerical
# gap between the noise floor and the project's existing `1e-6` default gate.
const IEEE8500_MV_EXACT_ATOL = 0.0011460285861373265   # re-measured 2026-08-21 (post D-13 fix), ladder floor at tol=1e-8 (rungs 1e-9/1e-10 failed ALMOST_OPTIMAL)
const IEEE8500_EXACT_ATOL = 0.004969145122458496       # re-measured 2026-08-21 (post D-13 fix), ladder floor at tol=1e-7 (rungs 1e-8/1e-9/1e-10 failed ALMOST_OPTIMAL)

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

# 2026-08-22 follow-up (quick task 260822-f0b, `25-VERIFICATION.md`): the sweep's ONE completed
# row on the true headline fixture (`:ieee8500`) came back `ALMOST_OPTIMAL` because it solved at
# the unconditional `CLARABEL_TOL_GAP = 1e-8` above — a tolerance
# `results/ieee8500_benchmark/noise_floor_calibration.csv` ALREADY measured to fail on `:ieee8500`
# (`ieee8500, 1e-8 -> NaN`; `ieee8500, 1e-7 -> 0.0049691451`, the last rung that still resolved).
# `IEEE8500_CLARABEL_TOL_GAP` below is that MEASURED, achievable value — never a guess. The other
# three fixtures keep reusing `CLARABEL_TOL_GAP` unchanged (byte-identical to today; their own
# noise-floor ladders never showed a comparable failure at 1e-8).
const IEEE8500_CLARABEL_TOL_GAP = 1.0e-7   # MEASURED floor (see noise_floor_calibration.csv, ieee8500 row)

const DEFAULT_CLARABEL_TOL_GAP = Dict{Symbol,Float64}(
    :ieee13 => CLARABEL_TOL_GAP,
    :ieee123 => CLARABEL_TOL_GAP,
    :ieee8500_mv => CLARABEL_TOL_GAP,
    :ieee8500 => IEEE8500_CLARABEL_TOL_GAP,
)

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
    good_tols = Float64[]
    good_gaps = Float64[]
    for tol in tolerances
        opt = select_optimizer(SOCP(); tol_gap_abs = tol, tol_gap_rel = tol)
        # Rule 1 (own-script bug fix, discovered live): at a large IEEE-8500 scale a benign point
        # can carry a genuinely near-zero-impedance real branch (see the comment on
        # IEEE8500_MV_EXACT_ATOL/IEEE8500_EXACT_ATOL below) that makes the interior-point solve
        # numerically ILL-CONDITIONED at the tightest ladder rungs — Clarabel legitimately reports
        # ALMOST_OPTIMAL (assert_solved! then throws, since solve_welfare has no allow_almost
        # pass-through) rather than a bug in this harness. A single failed rung must NOT kill the
        # whole ladder (mirrors socp_applicability_sweep.jl's own per-point try/catch) — it is
        # itself informative: the solver's OWN achievable precision on this fixture sits at/above
        # that rung, which is exactly the "floor" this calibration exists to find.
        gap = try
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
            socp_relaxation_gap(ctx)
        catch err
            @warn "calibration rung failed to reach a trustworthy solve — recording as a failed rung, not crashing the ladder" fixture =
                fixture_label tol = tol exception = (err, catch_backtrace())
            NaN
        end
        push!(rows, (; fixture = fixture_label, tol = tol, measured_gap = gap))
        if isfinite(gap)
            push!(good_tols, tol)
            push!(good_gaps, gap)
        end
        @printf("  tol=%-10.3g measured_gap=%-.6e\n", tol, gap)
        flush(stdout)
    end

    isempty(good_gaps) && error(
        "run_calibration($fixture_label): NO ladder rung reached a trustworthy solve — cannot " *
        "determine a noise floor; inspect the per-rung failures above",
    )

    # Floor = LAST index (among the rungs that actually solved) whose gap improved by >1% relative
    # to the PREVIOUS successful point. If tightening never improves by >1% at all, index 1 (the
    # loosest successful tolerance) IS already the noise floor.
    floor_idx = 1
    for i in 2:length(good_gaps)
        prev = good_gaps[i-1]
        improvement = prev == 0 ? 0.0 : (prev - good_gaps[i]) / prev
        improvement > 0.01 && (floor_idx = i)
    end
    return rows, good_tols[floor_idx], good_gaps[floor_idx]
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
        "\nFLOOR for %s: tol=%.3g measured_gap=%.6e (fed into IEEE8500_*_EXACT_ATOL — a genuinely fresh, fixture-own measurement)\n",
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
    run_centralized_point(feeder, aggs, λ0, atol, time_limit, T_horizon; clarabel_tol) -> NamedTuple

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

`clarabel_tol` (2026-08-22 follow-up, quick task 260822-f0b) sets Clarabel's own
`tol_gap_abs`/`tol_gap_rel` for this centralized solve — caller passes
`DEFAULT_CLARABEL_TOL_GAP[fixture_sym]` absent an explicit `--clarabel-tol` override (mirrors
`run_calibrate_mode`'s own `select_optimizer(SOCP(); tol_gap_abs = tol, tol_gap_rel = tol)`
precedent at line ~230 exactly).
"""
function run_centralized_point(feeder, aggs, λ0, atol, time_limit, T_horizon::Int, clarabel_tol::Float64)
    opt = select_optimizer(SOCP(); time_limit = time_limit, tol_gap_abs = clarabel_tol, tol_gap_rel = clarabel_tol)
    t0 = time_ns()
    try
        ctx, _, dadp = solve_welfare(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = T_horizon,
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
    run_admm_point(feeder, aggs, λ0, ρ0, time_limit, T_horizon, atol_exact) -> NamedTuple

Solves the SAME point via `solve_admm(...; time_limit_s = time_limit)` (plan 25-02's D-18 wall-
clock exit), wrapped in try/catch (a genuine non-convergence with NO time budget throws loudly,
per `solve_admm`'s own fail-loud maxiter cap — an honest, reportable outcome, not a harness bug).
Peak memory is sampled via `Sys.maxrss()` before/after (D-19; no new micro-benchmarking
package dependency added for this, per RESEARCH's "Don't Hand-Roll"). NOTE: `Sys.maxrss()` is a MONOTONIC, WHOLE-PROCESS high-water
mark, not a per-call current usage — the reported delta is the INCREMENTAL growth in the
process's peak RSS attributable to (at most) this call; once the process has already peaked on an
earlier, larger point, a later smaller point's delta legitimately reads ~0. This is the honest
limitation of the plan's own prescribed "sampled before/after" method, documented here rather than
silently presented as a precise per-call peak.

`atol_exact` (2026-08-22 round-2 follow-up, quick task 260822-hld) is threaded straight through to
`solve_admm`'s own `atol_exact` kwarg (the additive override seam quick task 260822-f0b built onto
the FINAL consolidation `assert_socp_exact!` gate only — the mid-loop `check_exact = false` call is
untouched). The caller ALWAYS passes `EXACTNESS_ATOL[fixture_sym]` — the SAME freshly-measured,
per-fixture noise floor already used for the centralized point's own `exact_verdict` above — NEVER
a literal chosen to make a point pass (T-25-12, anti-certificate-laundering): a point whose
converged cone gap genuinely EXCEEDS its fixture's own measured floor still throws here exactly as
it does today.
"""
function run_admm_point(feeder, aggs, λ0, ρ0, time_limit, T_horizon::Int, atol_exact::Real)
    t0 = time_ns()
    rss_before = Sys.maxrss()
    result = try
        r = solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = T_horizon,
            λ₀ = λ0,
            ρ = ρ0,
            allow_export = true,
            time_limit_s = time_limit,
            atol_exact = atol_exact,
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
    run_scs_comparison(feeder, aggs, λ0, dadp_clarabel, T_horizon) -> NamedTuple

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
function run_scs_comparison(feeder, aggs, λ0, dadp_clarabel, T_horizon::Int)
    dadp_clarabel === nothing &&
        return (; scs_status = "skipped_no_clarabel_dadp", scs_dadp_drift = NaN)
    SCS_AVAILABLE || return (; scs_status = "scs_unavailable", scs_dadp_drift = NaN)
    try
        opt = TSODSO.alternative_optimizer(TSODSO.SCSChoice(), TSODSO.SOCP())
        ctx, _, dadp_scs = solve_welfare(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = T_horizon,
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
# 2026-08-22 follow-up (quick task 260822-f0b, `25-VERIFICATION.md`): raised from the original
# "120" (D-18's original per-point cap). The headline T=10 point hit `budget_exceeded` after
# only 6 ADMM iterations at ~20s/iteration under the OLD 120s cap — far too short to observe
# convergence. ADMM elsewhere in this project has been observed converging anywhere from ~4
# iterations (near-lossless 2-bus/low-density cases) up to the ~55-99 iteration range on
# congestion-driven fixtures (e.g. the IEEE-13 ground crossval in `test/test_admm.jl`, ~99
# iterations at ρ=100). At ~20s/iteration, 1200s (20 minutes) covers ~60 iterations of pure
# solve time with margin left for JuMP assembly/build-once overhead, comfortably spanning the
# observed range without being open-ended. This ONLY affects invocations that don't pass an
# explicit `--time-limit`; `_QUICK_TIME_LIMIT_S` below (and everything `--quick`/the D-16
# goldens depend on) is UNTOUCHED — `run_sweep_mode`'s own `quick ? _QUICK_TIME_LIMIT_S :
# _DEFAULT_TIME_LIMIT_S` never consults this constant under `--quick`.
const _DEFAULT_TIME_LIMIT_S = "1200"               # D-18's per-point cap (Claude's discretion)
# --quick's OWN tighter cap (Claude's discretion, measured 2026-08-21 on a quiet 4-core machine).
# At the FULL T=24 horizon, ieee8500-mv/density=0.1's CENTRALIZED point alone costs ~76s wall
# (43s JuMP assembly + 33s solve — assembly is NOT solver-time-limit-bounded, so a smaller
# `--time-limit` cannot shrink it) and `solve_admm`'s BUILD-ONCE phase (before the wall-clock
# loop even starts checking `time_limit_s`) alone costs ~13s — together already eating most of
# the 120s `25-VALIDATION.md` feedback-latency budget before ANY solver iteration, on top of
# Julia's own package-import/JIT overhead (measured ~40-45s for this harness's dependency set,
# fixed regardless of problem size). Combined with `T_QUICK` below (which shrinks the DOMINANT
# network-size cost), a 5s ADMM cap keeps the WHOLE --quick invocation's total WALL time
# (imports + centralized + ADMM) comfortably under 120s (measured ≈70-80s) while still being
# long enough to distinguish "hit the cap mid-loop" from "never even reached the loop" (D-18's
# honest `budget_exceeded` early exit).
const _QUICK_TIME_LIMIT_S = "5"
# --quick's OWN tighter horizon (Claude's discretion, measured 2026-08-21 on a quiet 4-core
# machine): the JuMP model-assembly cost (branch/voltage vars+constraints, `T*n_branches`) and
# `solve_admm`'s BUILD-ONCE phase (BEFORE the wall-clock loop even starts checking
# `_QUICK_TIME_LIMIT_S`) are both dominated by NETWORK size at the full `T=24` horizon — NEITHER
# shrinks by lowering `--time-limit` alone (D-01: network-size cost is separable from AGR-OPT
# fan-out cost, and neither is separable from T). At `T=24` the centralized point alone measured
# ~76s wall (43s assembly + 33s solve) on ieee8500-mv/density=0.1, and `solve_admm`'s build phase
# alone measured ~42s — together already exceeding VALIDATION.md's 120s max-feedback-latency
# budget BEFORE any solver time. `--quick` uses a SHORTER `T_QUICK`-hour horizon (still passed
# through the SAME code path as the general sweep — no separate quick-only logic branch) to keep
# the WHOLE invocation comfortably under 120s; the general (non-quick) sweep keeps the full T=24.
# T_QUICK=10 (not smaller): _ieee8500_house's Deferrable window is `Deferrable(bus, min(8,T),
# min(16,T), 1.0, 0.5, 0.5)` (src/experiments/materialize.jl, plan 25-04 — out of THIS plan's
# <files> scope to change), whose energy-budget guard requires `E=1.0 <= Pmax*window_length =
# 0.5*(min(16,T)-min(8,T)+1)`. At `T<9` this collapses to `window_length=1` (E=1.0 > 0.5*1,
# infeasible — discovered live: T_QUICK=4 threw `ArgumentError` at population-construction
# time, a Rule-1 bug in THIS choice, not in materialize.jl). `T_QUICK=10` gives
# `window_length=3` (capacity 1.5 ≥ 1.0), the smallest horizon that keeps every :ieee13/:ieee123/
# :ieee8500/:ieee8500_mv population buildable while still cutting T=24's assembly/build cost.
const T_QUICK = 10
const _SWEEP_SEED = 20260821

# Floor for the general (non-quick) sweep's own `--t-horizon` override (gap-closure task,
# deferred-items.md item 4: "plan 25-05's T_QUICK precedent could be generalized beyond
# --quick"). REUSES T_QUICK's own already-measured floor rather than re-deriving a separate
# constant: `_ieee8500_house`'s fixed `Deferrable(bus, min(8,T), min(16,T), 1.0, 0.5, 0.5)`
# energy-budget guard (`src/experiments/materialize.jl`, plan 25-04 — out of this task's
# `<files>` scope) requires `E=1.0 <= Pmax*window_length = 0.5*(min(16,T)-min(8,T)+1)`, which
# collapses to `window_length=1` (infeasible, `E=1.0 > 0.5`) below `T=9` — `T_QUICK=4` threw
# `ArgumentError` at population-construction time when this was first discovered (25-05-SUMMARY).
# `T_HORIZON_FLOOR=10` (not 9) matches `T_QUICK`'s own already-validated value exactly, so a
# `--t-horizon 10` invocation is byte-identical in horizon to `--quick`'s own T_horizon.
const T_HORIZON_FLOOR = T_QUICK

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
    time_limit = parse(
        Float64,
        parse_kv_flag(args, "--time-limit", quick ? _QUICK_TIME_LIMIT_S : _DEFAULT_TIME_LIMIT_S),
    )
    densities = if quick
        # --quick: the EXACT VALIDATION.md-documented CI-affordable single point — the smallest
        # density on the smallest IEEE-8500 fixture, Clarabel only, with the tighter
        # _QUICK_TIME_LIMIT_S cap above (an explicit --time-limit still overrides it).
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

    # `--t-horizon` (gap-closure task, deferred-items.md item 4): an explicit CLI override of
    # the horizon, ABSENT of which behaviour is EXACTLY today's `quick ? T_QUICK : T` (no
    # existing invocation changes). Rejects (never silently clamps) anything below
    # `T_HORIZON_FLOOR` — see that constant's own comment for why T=10 is the smallest safe
    # horizon on these fixtures' `Deferrable` population.
    t_horizon_str = parse_kv_flag(args, "--t-horizon", nothing)
    T_horizon = if t_horizon_str === nothing
        quick ? T_QUICK : T
    else
        v = parse(Int, t_horizon_str)
        v < T_HORIZON_FLOOR && throw(
            ArgumentError(
                "--t-horizon=$v is below the safe floor of $T_HORIZON_FLOOR: " *
                "_ieee8500_house's Deferrable(bus, min(8,T), min(16,T), 1.0, 0.5, 0.5) energy " *
                "budget requires window_length = min(16,T)-min(8,T)+1 >= 2 (i.e. T >= 9), and " *
                "T_QUICK=10 is this harness's own already-measured smallest safe value across " *
                "every fixture — refusing rather than silently clamping",
            ),
        )
        v
    end
    # `--clarabel-tol` (2026-08-22 follow-up, quick task 260822-f0b): an explicit CLI override of
    # Clarabel's `tol_gap_abs`/`tol_gap_rel` for the centralized point, ABSENT of which behaviour
    # is `DEFAULT_CLARABEL_TOL_GAP[fixture_sym]` — see that Dict's own comment for provenance.
    clarabel_tol_str = parse_kv_flag(args, "--clarabel-tol", nothing)
    clarabel_tol =
        clarabel_tol_str === nothing ? DEFAULT_CLARABEL_TOL_GAP[fixture_sym] :
        parse(Float64, clarabel_tol_str)

    feeder = build_feeder(fixture_sym)
    profiles = generate_profiles(; seed = _SWEEP_SEED, T = T_horizon)
    λ0 = build_price(:mem, T_horizon, nothing)
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

        cpoint = run_centralized_point(feeder, aggs, λ0, atol, time_limit, T_horizon, clarabel_tol)
        apoint = run_admm_point(feeder, aggs, λ0, 100.0, time_limit, T_horizon, atol)   # ρ0=100.0: pv_boom_case_study.jl's validated initial penalty; adaptive-ρ self-corrects thereafter; atol: EXACTNESS_ATOL[fixture_sym], see run_admm_point's own docstring (T-25-12)

        scs_row =
            solver_sym in (:scs, :both) ?
            run_scs_comparison(feeder, aggs, λ0, cpoint.dadp, T_horizon) :
            (; scs_status = "not_requested", scs_dadp_drift = NaN)

        combined_err = join(
            filter(!isempty, [cpoint.error_msg, apoint.admm_error_msg]),
            " | ",
        )

        row = (;
            fixture = fixture_str,
            density = density,
            solver = solver_str,
            T_horizon = T_horizon,
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
            clarabel_tol_gap = clarabel_tol,
            admm_atol_used = atol,
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
