# scripts/repro_stability_check.jl
#
# Phase 18 (directional thesis reproduction) — the REPRO-02-mandated stability/sensitivity
# measurement, run and its findings committed BEFORE any golden band is pinned in
# `test/test_thesis_repro.jl` (Plan 18-02). Mirrors `scripts/reactive_flake_rate.jl`'s
# DrWatson scaffold / try-catch flake-counter / committed-findings shape exactly (18-RESEARCH.md
# Validation Architecture, Wave 0 Gaps).
#
# Two measurements, NEITHER previously done anywhere in the repo (18-RESEARCH.md Pitfall 5):
#
# (a) Discrete Clarabel flake rate at the EXACT Phase-17-retuned IEEE-123 population point
#     (`LOAD_SCALE_IEEE123=0.05`, `PV_SCALE_IEEE123=0.12`) — does the solve occasionally THROW
#     rather than return a slightly different number (mirrors `reactive_flake_rate.jl`'s
#     `count_failures`, N>=20 repeats, tiny λ₀ jitter).
# (b) A NEW population-scale sensitivity sweep (±2-5% on `LOAD_SCALE_IEEE123`/`PV_SCALE_IEEE123`,
#     `DEV_SCALE_IEEE123` ratio held fixed) probing whether the DSO-surplus sign flip discovered
#     by 18-RESEARCH.md (FIT dso < 0 -> DADP dso > 0, on the real-impedance, Phase-17-retuned
#     IEEE-123 fixture) survives near the exactness boundary Phase 17 documented (18-RESEARCH.md
#     Pitfall 4 / Open Question 1).
#
# FIXTURE CONSTRUCTION NOTE (mirrors `reactive_flake_rate.jl`'s own header): `Phase7Fixtures` is
# a `TestItems.@testmodule` block. The standalone `TestItems.jl` package expands `@testmodule` to
# a no-op outside `TestItemRunner`'s AST-introspection path, so `include("test/fixtures_phase7.jl")`
# from a plain script does NOT actually define `Phase7Fixtures`. The population construction is
# therefore RE-IMPLEMENTED INLINE below, copied verbatim from `test/fixtures_phase7.jl` (lines
# 92-95, 178-264: `temperature_profile`, `ieee123_lambda0`, `_house_aggregator`,
# `build_ieee123_aggregators`, and the retuned scale constants), so the population here is
# bit-for-bit identical to the one `test_ieee123_admm.jl`/18-RESEARCH.md's live probes exercise.
#
# HONEST-MEASUREMENT MANDATE (threat T-18-02): if the DSO-surplus sign flip does NOT survive
# every swept point, this script reports `sign_flip_survives: false` honestly — it never narrows
# the sweep range, drops the failing point, or otherwise edits itself to force a passing
# appearance. A negative result is a legitimate, documented outcome.
#
# PER-STAGE ATTRIBUTION + `optimizer` KWARG (quick task 260823-gea): the original version of this
# script wrapped `solve_welfare` -> `welfare_accounting` -> `fit_baseline` in ONE `try/catch` per
# point, in both `count_failures` and `sweep_population_scale`. Spike 003 found this misattributed
# 2 of 4 sweep "failures" — they were actually `assert_socp_exact!` throwing inside `solve_welfare`
# at the default `tol_gap = 1e-8`, not failures of the later stages the single catch-all made them
# look like. Each function now runs three SEQUENTIAL per-stage `try/catch` blocks (short-circuiting
# to skip later stages once one fails), so a failure is attributable to exactly one of
# `solve_welfare`/`welfare_accounting`/`fit_baseline`. Both functions also accept an `optimizer`
# keyword (mirroring `fit_baseline`/`solve_welfare`'s own "only compute/pass the override when the
# caller actually gave one" discipline, INFRA-02), driven at the top level by an optional
# `REPRO_TOL_GAP` environment variable: unset means the script's numeric behavior is BYTE-FOR-BYTE
# unchanged from before this fix (no `optimizer` kwarg is ever passed downstream); set, it builds a
# `Clarabel.Optimizer` with `tol_gap_abs`/`tol_gap_rel` pinned to that value (same attribute pair as
# `.planning/spikes/003-phase18-fragility-tolerance/check.jl`), letting the sweep be re-run at a
# tightened tolerance (e.g. `REPRO_TOL_GAP=1e-10`) without editing source.

using DrWatson
@quickactivate "TSODSO"
using TSODSO
using JuMP
using Clarabel
using Printf
using Dates

const OUT = projectdir("results", "repro_stability_check")
mkpath(OUT)

# ---- Shared config (verbatim from test/fixtures_phase7.jl) ------------------------------------
const T = 24

const BATT_λ_MIN = 3.8
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9

# IEEE-123 population scaling, Phase-17-retuned point (verbatim from test/fixtures_phase7.jl:92-95).
const SEED_IEEE123 = 20260719
const LOAD_SCALE_IEEE123 = 0.05
const PV_SCALE_IEEE123 = 0.12
const DEV_SCALE_IEEE123 = 0.05 * (0.05 / 0.03)   # ratio to LOAD_SCALE held fixed

# Optional solver-tolerance override (quick task 260823-gea): unset REPRO_TOL_GAP => `nothing` =>
# every downstream call keeps its own default `optimizer` factory (byte-for-byte unchanged path).
# Set REPRO_TOL_GAP=<tol> => a Clarabel optimizer pinned to that tol_gap_abs/tol_gap_rel, same
# attribute pair as spike 003's `check.jl`, threaded into `count_failures`/`sweep_population_scale`.
const REPRO_OPTIMIZER = let tol_str = get(ENV, "REPRO_TOL_GAP", nothing)
    if tol_str === nothing
        nothing
    else
        tol = parse(Float64, tol_str)
        optimizer_with_attributes(
            Clarabel.Optimizer,
            "verbose" => false,
            "tol_gap_abs" => tol,
            "tol_gap_rel" => tol,
        )
    end
end

"""
    temperature_profile() -> Vector{Float64}

Digitized 24h exterior-temperature profile (°C), verbatim copy of
`test/fixtures_phase7.jl`'s `temperature_profile` (thesis Fig 4.2 shape).
"""
function temperature_profile()
    return Float64[
        19,
        18,
        17,
        16,
        16,
        17,   # 00–05 cooling to a dawn minimum
        19,
        21,
        23,
        26,
        28,
        30,   # 06–11 morning warm-up
        31,
        32,
        32,
        31,
        29,
        27,   # 12–17 afternoon peak → decline
        25,
        23,
        22,
        21,
        20,
        19,   # 18–23 evening cool-down
    ]
end

"""
    ieee123_lambda0() -> Vector{Float64}

Digitized 24h MEM/wholesale price λ₀, verbatim copy of `test/fixtures_phase7.jl`'s
`ieee123_lambda0`.
"""
function ieee123_lambda0()
    return Float64[
        3.8,
        3.7,
        3.6,
        3.6,
        3.7,
        4.0,   # 00–05 overnight trough
        4.8,
        5.8,
        6.5,
        6.2,
        5.9,
        5.7,   # 06–11 morning ramp → midday shoulder
        5.6,
        5.8,
        6.0,
        6.8,
        8.2,
        9.0,   # 12–17 afternoon rise → evening peak
        8.6,
        7.4,
        6.2,
        5.2,
        4.4,
        4.0,   # 18–23 evening decline
    ]
end

"""
    _house_aggregator(feeder, bus; seed, φ, pv_scale=1.0, load_scale=1.0, dev_scale=1.0,
                      batt_pmax=0.5, batt_emax=2.0, batt_soc0=1.0) -> Aggregator

Verbatim copy of `test/fixtures_phase7.jl`'s `_house_aggregator` (Thermostatic + Deferrable +
PVBattery, seeded `generate_profiles` draw).
"""
function _house_aggregator(
    feeder,
    bus;
    seed::Integer,
    φ::Real,
    pv_scale::Real = 1.0,
    load_scale::Real = 1.0,
    dev_scale::Real = 1.0,
    batt_pmax::Real = 0.5,
    batt_emax::Real = 2.0,
    batt_soc0::Real = 1.0,
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

"""
    build_ieee123_aggregators(feeder; seed=SEED_IEEE123, load_buses=nothing,
                              load_scale=LOAD_SCALE_IEEE123, pv_scale=PV_SCALE_IEEE123,
                              dev_scale=DEV_SCALE_IEEE123) -> Vector{<:Aggregator}

Verbatim SHAPE of `test/fixtures_phase7.jl`'s `build_ieee123_aggregators`, extended with
explicit `load_scale`/`pv_scale`/`dev_scale` keyword overrides (defaulting to the Phase-17-
retuned point) so the population-scale sweep below can rebuild the SAME population at a
perturbed scale without touching the module constants.
"""
function build_ieee123_aggregators(
    feeder;
    seed::Integer = SEED_IEEE123,
    load_buses = nothing,
    load_scale::Real = LOAD_SCALE_IEEE123,
    pv_scale::Real = PV_SCALE_IEEE123,
    dev_scale::Real = DEV_SCALE_IEEE123,
)
    buses = load_buses === nothing ? ieee123_load_nodes() : load_buses
    return [
        _house_aggregator(
            feeder,
            bus;
            seed = seed,
            φ = 0.90,
            load_scale = load_scale,
            pv_scale = pv_scale,
            dev_scale = dev_scale,
            batt_pmax = 0.5 * load_scale,
            batt_emax = 2.0 * load_scale,
            batt_soc0 = 1.0 * load_scale,
        ) for bus in buses
    ]
end

# ---- Part (a): discrete flake-rate measurement -------------------------------------------------

"""
    count_failures(feeder, aggs, λ₀; n_repeats=20, seed_offset=0, optimizer=nothing)
        -> (; failures::Int, by_stage::Dict{Symbol,Int})

Calls `solve_welfare` -> `welfare_accounting` -> `fit_baseline` `n_repeats` times, each stage in
its OWN `try/catch` (quick task 260823-gea — the original single catch-all misattributed which
stage actually threw, per spike 003 Finding 1), short-circuiting to skip later stages once one
fails since they consume the previous stage's output. `by_stage` is zero-initialized for all three
stage keys so the caller can always report a full breakdown, even when a stage never failed.
Mirrors `reactive_flake_rate.jl:273-310`'s `count_failures`, adapted to the DADP/FIT/DSO-split
seam this phase measures instead of `solve_admm`. Each repeat perturbs λ₀ by a tiny (`1e-9`-scale)
numerical jitter — enough to perturb the interior-point solver's exact iterate path without
changing the economically-meaningful problem data. `optimizer`, when given, is threaded into every
`solve_welfare`/`fit_baseline` call (not `welfare_accounting`, which takes no optimizer); when
`nothing` (the default), no `optimizer` kwarg is passed and the byte-for-byte prior default path
is preserved.
"""
function count_failures(
    feeder,
    aggs,
    λ₀;
    n_repeats::Int = 20,
    seed_offset::Int = 0,
    optimizer = nothing,
)
    opt_kwargs = optimizer === nothing ? NamedTuple() : (; optimizer)
    failures = 0
    by_stage = Dict{Symbol,Int}(
        :solve_welfare => 0,
        :welfare_accounting => 0,
        :fit_baseline => 0,
    )
    for i in 1:n_repeats
        jitter = 1e-9 * (i + seed_offset)
        λ₀_i = λ₀ .+ jitter

        ctx = nothing
        stage1_ok = true
        try
            ctx, _, _ = solve_welfare(
                feeder,
                ConvexBranchFlow(),
                aggs;
                T = T,
                λ₀ = λ₀_i,
                allow_export = true,
                opt_kwargs...,
            )
        catch e
            stage1_ok = false
            failures += 1
            by_stage[:solve_welfare] += 1
            @warn "stability measurement failed" repeat = i stage = :solve_welfare exception =
                (e, catch_backtrace())
        end
        stage1_ok || continue

        stage2_ok = true
        try
            welfare_accounting(ctx; T = T)
        catch e
            stage2_ok = false
            failures += 1
            by_stage[:welfare_accounting] += 1
            @warn "stability measurement failed" repeat = i stage = :welfare_accounting exception =
                (e, catch_backtrace())
        end
        stage2_ok || continue

        try
            fit_baseline(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ₀_i, opt_kwargs...)
        catch e
            failures += 1
            by_stage[:fit_baseline] += 1
            @warn "stability measurement failed" repeat = i stage = :fit_baseline exception =
                (e, catch_backtrace())
        end
    end
    return (; failures, by_stage)
end

# ---- Part (b): population-scale sensitivity sweep (NEW measurement) ---------------------------

"""
    sweep_population_scale(feeder; deltas=(-0.05, -0.02, 0.0, 0.02, 0.05), optimizer=nothing)
        -> Vector{NamedTuple}

For each `δ`, rebuilds the IEEE-123 population at `load_scale = LOAD_SCALE_IEEE123*(1+δ)`,
`pv_scale = PV_SCALE_IEEE123*(1+δ)`, `dev_scale = DEV_SCALE_IEEE123*(1+δ)` (the ratio to
`LOAD_SCALE_IEEE123` held fixed, per `fixtures_phase7.jl`'s own convention), solves
`solve_welfare` + `welfare_accounting` + `fit_baseline` UNMODIFIED, and records the DADP/FIT
DSO-surplus split. This is a genuinely NEW measurement (18-RESEARCH.md Pitfall 4 / Open
Question 1) — not previously run anywhere in the repo.

Each point runs the three stages SEQUENTIALLY, each in its OWN `try/catch` (quick task
260823-gea — Rule-1 fix, discovered live: at `δ=-0.05` the SOCP relaxation genuinely goes
INEXACT — `assert_socp_exact!` throws inside `solve_welfare` — exactly the near-boundary risk
18-RESEARCH.md's Pitfall 4 documented as a live possibility, not a hypothetical; the original
single catch-all could not distinguish this from a `welfare_accounting`/`fit_baseline` failure,
per spike 003 Finding 1). A failing point is recorded as `(; δ, failed_stage, error_msg)` —
`failed_stage = :none` on full success, else the symbol of the stage that threw — rather than
crashing the whole sweep; an uncaught exception here would silently produce ZERO findings, which
is a worse honesty failure than reporting the point as failed. `sign_flip_survives` (computed by
the caller) treats any `failed_stage != :none` point as a non-survival, per the honest-measurement
mandate. `optimizer`, when given, is threaded into every `solve_welfare`/`fit_baseline` call (not
`welfare_accounting`); `nothing` (the default) preserves the byte-for-byte prior default path.
"""
function sweep_population_scale(
    feeder;
    deltas = (-0.05, -0.02, 0.0, 0.02, 0.05),
    optimizer = nothing,
)
    opt_kwargs = optimizer === nothing ? NamedTuple() : (; optimizer)
    λ0 = ieee123_lambda0()
    results = NamedTuple[]
    for δ in deltas
        load_scale = LOAD_SCALE_IEEE123 * (1 + δ)
        pv_scale = PV_SCALE_IEEE123 * (1 + δ)
        dev_scale = DEV_SCALE_IEEE123 * (1 + δ)
        println(
            "  δ=$δ: load_scale=$load_scale, pv_scale=$pv_scale, dev_scale=$dev_scale ...",
        )
        aggs = build_ieee123_aggregators(
            feeder;
            load_scale = load_scale,
            pv_scale = pv_scale,
            dev_scale = dev_scale,
        )

        ctx = nothing
        acct = nothing
        failed_stage = :none
        error_msg = ""

        try
            ctx, welfare_dadp, _ = solve_welfare(
                feeder,
                ConvexBranchFlow(),
                aggs;
                T = T,
                λ₀ = λ0,
                allow_export = true,
                opt_kwargs...,
            )
        catch e
            failed_stage = :solve_welfare
            error_msg = sprint(showerror, e)
            @warn "sweep point failed" δ stage = failed_stage exception =
                (e, catch_backtrace())
        end

        if failed_stage == :none
            try
                acct = welfare_accounting(ctx; T = T)
            catch e
                failed_stage = :welfare_accounting
                error_msg = sprint(showerror, e)
                @warn "sweep point failed" δ stage = failed_stage exception =
                    (e, catch_backtrace())
            end
        end

        fb = nothing
        if failed_stage == :none
            try
                fb = fit_baseline(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ0, opt_kwargs...)
            catch e
                failed_stage = :fit_baseline
                error_msg = sprint(showerror, e)
                @warn "sweep point failed" δ stage = failed_stage exception =
                    (e, catch_backtrace())
            end
        end

        if failed_stage == :none
            fit_dso = fb.social_fit - fb.prosumer_surplus
            push!(
                results,
                (;
                    δ = δ,
                    failed_stage = failed_stage,
                    dso = acct.dso,
                    fit_dso = fit_dso,
                    prosumer = acct.prosumer,
                    fit_prosumer = fb.prosumer_surplus,
                    socp_maxgap = ctx.meta[:socp_maxgap],
                    error_msg = error_msg,
                ),
            )
        else
            push!(
                results,
                (;
                    δ = δ,
                    failed_stage = failed_stage,
                    dso = NaN,
                    fit_dso = NaN,
                    prosumer = NaN,
                    fit_prosumer = NaN,
                    socp_maxgap = NaN,
                    error_msg = error_msg,
                ),
            )
        end
    end
    return results
end

# ---- Run ----------------------------------------------------------------------------------------

const N_REPEATS = 20

println(
    "Building IEEE-123 population at the Phase-17-retuned point (seed=$SEED_IEEE123)...",
)
feeder = ieee123_modified()
aggs = build_ieee123_aggregators(feeder)
λ0 = ieee123_lambda0()

println(
    "Running discrete flake-rate measurement ($N_REPEATS repeats) at the retuned point...",
)
cf = count_failures(feeder, aggs, λ0; n_repeats = N_REPEATS, optimizer = REPRO_OPTIMIZER)
failures = cf.failures
flake_rate = failures / N_REPEATS

println("Running population-scale sensitivity sweep (5 points)...")
results = sweep_population_scale(feeder; optimizer = REPRO_OPTIMIZER)

any_failed = any(r -> r.failed_stage != :none, results)
sign_flip_survives =
    !any_failed &&
    all(r -> r.dso > 0 && r.fit_dso < 0 && r.prosumer < r.fit_prosumer, results)

dso_band_lo = 0.0
successful = filter(r -> r.failed_stage == :none, results)
dso_band_hi = isempty(successful) ? NaN : 1.5 * maximum(abs(r.dso) for r in successful)

@printf("\nFlake rate: %d/%d = %.3f\n", failures, N_REPEATS, flake_rate)
println("failures_by_stage = ", cf.by_stage)
println("sign_flip_survives: ", sign_flip_survives)
@printf("RECOMMENDED BAND: DSO_BAND_LO=%.6f, DSO_BAND_HI=%.6f\n", dso_band_lo, dso_band_hi)

# ---- Committed findings artifact ---------------------------------------------------------------

report_path = joinpath(OUT, "findings.txt")
open(report_path, "w") do io
    println(
        io,
        "Phase 18 (directional thesis reproduction) — Repro Stability Check (REPRO-02)",
    )
    println(io, "Measured: ", Dates.format(now(), "yyyy-mm-dd HH:MM:SS"), " UTC-local")
    println(
        io,
        "Fixture: ieee123_modified() (real Phase-17 impedances), seed=$SEED_IEEE123",
    )
    println(
        io,
        "Retuned point: LOAD_SCALE_IEEE123=$LOAD_SCALE_IEEE123, PV_SCALE_IEEE123=$PV_SCALE_IEEE123, ",
        "DEV_SCALE_IEEE123=$DEV_SCALE_IEEE123",
    )
    println(io)
    println(io, "=== Flake rate ===")
    println(io, "N_REPEATS = $N_REPEATS")
    @printf(io, "failures = %d\n", failures)
    @printf(io, "rate = %.4f\n", flake_rate)
    println(io, "failures_by_stage = ", cf.by_stage)
    println(
        io,
        "This is a citable phase finding, not a pass/fail gate (mirrors ",
        "scripts/reactive_flake_rate.jl's own framing) — the number itself is the deliverable, ",
        "reported here neither silently accepted nor silently \"fixed.\" The per-stage breakdown ",
        "(quick task 260823-gea) makes any future misattribution of WHICH call failed structurally ",
        "impossible to reintroduce.",
    )
    println(io)
    println(io, "=== Population-scale sensitivity sweep ===")
    @printf(
        io,
        "%-8s %14s %14s %14s %14s %14s\n",
        "delta",
        "dso",
        "fit_dso",
        "prosumer",
        "fit_prosumer",
        "socp_maxgap"
    )
    for r in results
        if r.failed_stage != :none
            failed_cell = "FAILED($(r.failed_stage))"
            @printf(
                io,
                "%-8.3f %14s %14s %14s %14s %14s\n",
                r.δ,
                failed_cell,
                failed_cell,
                failed_cell,
                failed_cell,
                failed_cell
            )
        else
            @printf(
                io,
                "%-8.3f %14.6f %14.6f %14.6f %14.6f %14.3e\n",
                r.δ,
                r.dso,
                r.fit_dso,
                r.prosumer,
                r.fit_prosumer,
                r.socp_maxgap
            )
        end
    end
    if any_failed
        println(io)
        println(io, "Failed-point error detail:")
        for r in results
            r.failed_stage != :none &&
                println(io, "  δ=$(r.δ) [$(r.failed_stage)]: ", r.error_msg)
        end
    end
    println(io)
    println(io, "sign_flip_survives: ", sign_flip_survives)
    if sign_flip_survives
        swept_deltas = join([@sprintf("%.3f", r.δ) for r in results], ", ")
        println(
            io,
            "The DSO-surplus sign flip (FIT dso < 0 -> DADP dso > 0) AND the prosumer-surplus ",
            "decrease (DADP prosumer < FIT prosumer) hold at EVERY swept point (delta in ",
            "[$swept_deltas]). This is the robustness evidence 18-RESEARCH.md's Open ",
            "Question 1 / Pitfall 4 required before pinning a golden magnitude band.",
        )
    elseif any_failed
        failed_deltas =
            join([@sprintf("%.3f", r.δ) for r in results if r.failed_stage != :none], ", ")
        println(
            io,
            "HONEST NEGATIVE RESULT: the sweep point(s) delta=[$failed_deltas] FAILED OUTRIGHT — ",
            "solve_welfare's SOCP-exactness gate (assert_socp_exact!) THREW rather than returning ",
            "a comparable welfare/surplus split, exactly the near-boundary risk 18-RESEARCH.md's ",
            "Pitfall 4 documented (Phase 17's own finding: this population regime sits on a genuine ",
            "asymmetric exactness knife-edge). Per this script's own mandate (threat T-18-02), this ",
            "is reported as-is — the sweep range was NOT narrowed and the failing point was NOT ",
            "omitted to force a passing appearance. Plan 18-03 must carry this forward as an ",
            "assumption-page caveat: the DSO-surplus sign-flip finding is NOT population-scale-",
            "robust in the direction(s) that go inexact; the golden band below is derived ONLY from ",
            "the points that solved successfully and should be read with that caveat attached.",
        )
    else
        println(
            io,
            "HONEST NEGATIVE RESULT: the DSO-surplus sign flip and/or the prosumer-surplus ",
            "decrease did NOT survive at every swept point (see the table above for the failing ",
            "delta(s)). Per this script's own mandate (threat T-18-02), this is reported as-is — ",
            "the sweep range was NOT narrowed and no failing point was omitted to force a ",
            "passing appearance. Plan 18-03 must carry this forward as an assumption-page caveat ",
            "on the reproduction's population-scale robustness.",
        )
    end
    println(io)
    println(io, "=== RECOMMENDED BAND ===")
    if any_failed
        println(
            io,
            "NOTE: at least one sweep point FAILED (see above) — the band below is derived ONLY ",
            "from the $(length(successful))/$(length(results)) points that solved successfully ",
            "(the exact retuned point delta=0.0 is one of them); it does NOT certify robustness ",
            "across the failed direction(s).",
        )
    end
    println(
        io,
        "Derivation: DSO_BAND_LO = 0.0 (the DADP DSO surplus must be strictly positive per the ",
        "sign gate); DSO_BAND_HI = 1.5 * max(|dso|) over the SUCCESSFULLY-SOLVED swept points — ",
        "a 50% safety-margin multiplier above the largest observed magnitude among the points that ",
        "actually solved, so the pinned golden band tolerates ordinary Clarabel/Julia-patch-level ",
        "numerical drift without being so wide it stops meaning anything.",
    )
    @printf(io, "DSO_BAND_LO = %.6f\n", dso_band_lo)
    @printf(io, "DSO_BAND_HI = %.6f\n", dso_band_hi)
    println(io, "RECOMMENDED BAND: DSO_BAND_LO=$(dso_band_lo), DSO_BAND_HI=$(dso_band_hi)")
end

println("\nWrote findings to: ", report_path)
