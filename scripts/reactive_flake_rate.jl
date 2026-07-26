# scripts/reactive_flake_rate.jl
#
# Phase 16 (reactive-power consensus) — the phase's two REQUIRED empirical measurements
# (16-RESEARCH.md Pitfall 5 / Open Questions 1-2), run as a re-runnable DrWatson-convention
# script, NOT a `@testitem` (long-running, N>=20 repeats x 2 fixtures x 2 modes = 80+ solves).
#
# (a) Measures the Clarabel `NUMERICAL_ERROR`-class flake rate of `solve_admm` under
#     `reactive_consensus ∈ (false, true)` on BOTH IEEE-13 and IEEE-123 (N>=20 repeats each,
#     80+ solves total), comparing the Q-consensus path against a same-session baseline on
#     the IDENTICAL fixtures/seeds — never assuming v1.0's (or the Phase-12 toy fixture's)
#     rate transfers (STATE.md's explicit flag).
# (b) Records the Open-Question-1 (rho vs rho_q) finding directly from Plan 16-02's ACTUAL
#     shipped mechanism: `qag_dso[j,t]` is pinned via a hard equality (`:qag_pin`,
#     `qag_dso[j,t] == q_draw[j][t]`) with NO quadratic ρ-penalty term of its own (16-RESEARCH
#     Assumption A1/A3 — the pinned target `b_j = agr.qag[j][t]` never moves, so there is no
#     live dual-ascent target to tune a ρ_q against). This is recorded as the finding, not
#     re-derived from scratch.
#
# FIXTURE CONSTRUCTION NOTE: `Phase4Fixtures`/`Phase7Fixtures` are `TestItems.@testmodule`
# blocks. The standalone `TestItems.jl` package (as opposed to the `TestItemRunner`
# introspection machinery) expands `@testmodule` to a no-op (`return nothing`) — so
# `include("test/fixtures_phase7.jl")` from a plain script does NOT actually define
# `Phase7Fixtures` outside the test-runner's special AST-introspection path. Per this plan's
# own instruction, the population construction is therefore RE-IMPLEMENTED INLINE below,
# copied verbatim from `test/fixtures_phase4.jl` (`build_ieee13_ground_aggregators`,
# `mem_price_profile`) and `test/fixtures_phase7.jl` (`build_ieee123_aggregators`,
# `ieee123_lambda0`, and the shared adaptive-ρ config constants `RHO0`/`EPS_ABS`/`EPS_REL`/
# `TAU`/`MU`/`RHO_MIN`/`RHO_MAX`), using the SAME underlying builders (`Aggregator`,
# `Thermostatic`, `Deferrable`, `PVBattery`, `generate_profiles`) with the SAME seeds/scales,
# so the populations here are bit-for-bit identical to the ones `test_admm_adaptive.jl`/
# `test_ieee123_admm.jl` already exercise.

using DrWatson
@quickactivate "TSODSO"
using TSODSO
using Printf
using Dates

const OUT = projectdir("results", "reactive_flake_rate")
mkpath(OUT)

# ---- Shared adaptive-ρ / per-unit-tolerance config (verbatim from test/fixtures_phase7.jl) ----
const T = 24
const EPS_ABS = 1e-5
const EPS_REL = 1e-4
const TAU = 2.0
const MU = 10.0
const RHO_MIN = 1e-2
const RHO_MAX = 1e4
const RHO0 = 5.0

const BATT_λ_MIN = 3.8
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9

# IEEE-13 ground-truth calibration (verbatim from test/fixtures_phase4.jl)
const GROUND_LOAD_SCALE = 0.005
const GROUND_PV_SCALE = 0.03
const SEED_IEEE13 = 20260718

# IEEE-123 population scaling (verbatim from test/fixtures_phase7.jl)
const SEED_IEEE123 = 20260719
const LOAD_SCALE_IEEE123 = 0.03
const PV_SCALE_IEEE123 = 0.06
const DEV_SCALE_IEEE123 = 0.05

"""
    temperature_profile() -> Vector{Float64}

Digitized 24h exterior-temperature profile (°C), verbatim copy shared by
`test/fixtures_phase4.jl`/`test/fixtures_phase6.jl`/`test/fixtures_phase7.jl`.
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
    mem_price_profile() -> Vector{Float64}

Digitized 24h MEM/wholesale price λ₀ for IEEE-13, verbatim copy of
`test/fixtures_phase4.jl`'s `mem_price_profile`.
"""
function mem_price_profile()
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
    ieee123_lambda0() -> Vector{Float64}

Digitized 24h MEM/wholesale price λ₀ for IEEE-123, verbatim copy of
`test/fixtures_phase7.jl`'s `ieee123_lambda0`.
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
    _house_aggregator(bus; seed, φ, pv_scale=1.0, load_scale=1.0, dev_scale=1.0,
                       batt_pmax=0.5, batt_emax=2.0, batt_soc0=1.0) -> Aggregator

One seeded Thermostatic + Deferrable + PVBattery aggregator, verbatim SHAPE of the
`_house_aggregator` helper shared by `test/fixtures_phase4.jl`/`test/fixtures_phase7.jl`.
"""
function _house_aggregator(
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

    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0 * dev_scale, 0.5, temperature_profile())
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
    build_ieee13_ground_aggregators(feeder; seed=SEED_IEEE13) -> Vector{<:Aggregator}

One aggregator per non-root bus, residential-scale (`GROUND_LOAD_SCALE`/`GROUND_PV_SCALE`),
verbatim copy of `test/fixtures_phase4.jl`'s `build_ieee13_ground_aggregators` — the SAME
population `test_admm_adaptive.jl`'s IEEE-13 leg exercises.
"""
function build_ieee13_ground_aggregators(feeder; seed::Integer = SEED_IEEE13)
    N = length(feeder.buses)
    return [
        _house_aggregator(
            bus;
            seed = seed,
            φ = 0.90,
            load_scale = GROUND_LOAD_SCALE,
            pv_scale = GROUND_PV_SCALE,
            batt_pmax = 0.5 * GROUND_LOAD_SCALE,
            batt_emax = 2.0 * GROUND_LOAD_SCALE,
            batt_soc0 = 1.0 * GROUND_LOAD_SCALE,
        ) for bus in 2:N
    ]
end

"""
    build_ieee123_aggregators(feeder; seed=SEED_IEEE123) -> Vector{<:Aggregator}

One seeded aggregator per LOAD node of the modified IEEE-123 feeder, verbatim copy of
`test/fixtures_phase7.jl`'s `build_ieee123_aggregators` — the SAME population
`test_ieee123_admm.jl` exercises.
"""
function build_ieee123_aggregators(feeder; seed::Integer = SEED_IEEE123)
    buses = ieee123_load_nodes()
    return [
        _house_aggregator(
            bus;
            seed = seed,
            φ = 0.90,
            load_scale = LOAD_SCALE_IEEE123,
            pv_scale = PV_SCALE_IEEE123,
            dev_scale = DEV_SCALE_IEEE123,
            batt_pmax = 0.5 * LOAD_SCALE_IEEE123,
            batt_emax = 2.0 * LOAD_SCALE_IEEE123,
            batt_soc0 = 1.0 * LOAD_SCALE_IEEE123,
        ) for bus in buses
    ]
end

# ---- Flake-rate measurement -------------------------------------------------------------------

"""
    count_failures(feeder, aggs, λ₀; reactive_consensus, n_repeats=20, seed_offset=0) -> Int

Calls `solve_admm(feeder, ConvexBranchFlow(), aggs; T, λ₀, ρ=RHO0, ..., reactive_consensus)`
`n_repeats` times inside a `try/catch`, incrementing a failure counter on any caught exception
and `@warn`-logging it. The seeded fixtures (`build_ieee13_ground_aggregators`/
`build_ieee123_aggregators`) are fully deterministic given a fixed seed, so each repeat instead
varies a tiny (`1e-9`-scale) numerical jitter on λ₀ — enough to perturb the interior-point
solver's exact iterate path (and thus exercise any conditioning-dependent flake) without
changing the economically-meaningful problem data. Returns the number of caught failures
(0 <= failures <= n_repeats).
"""
function count_failures(
    feeder,
    aggs,
    λ₀;
    reactive_consensus::Bool,
    n_repeats::Int = 20,
    seed_offset::Int = 0,
)
    failures = 0
    for i in 1:n_repeats
        jitter = 1e-9 * (i + seed_offset)
        λ₀_i = λ₀ .+ jitter
        try
            solve_admm(
                feeder,
                ConvexBranchFlow(),
                aggs;
                T = T,
                λ₀ = λ₀_i,
                ρ = RHO0,
                ε_abs = EPS_ABS,
                ε_rel = EPS_REL,
                τ = TAU,
                μ = MU,
                ρ_min = RHO_MIN,
                ρ_max = RHO_MAX,
                maxiter = 500,
                allow_export = true,
                reactive_consensus = reactive_consensus,
            )
        catch e
            failures += 1
            @warn "solve_admm failed during reactive-flake-rate measurement" repeat = i reactive_consensus exception =
                (e, catch_backtrace())
        end
    end
    return failures
end

# ---- Run the four measurements (2 fixtures x 2 modes, N=20 repeats each = 80 solves) -----------

const N_REPEATS = 20

println("Building IEEE-13 population (ground-truth calibration, seed=$SEED_IEEE13)...")
feeder13 = ieee13_modified()
aggs13 = build_ieee13_ground_aggregators(feeder13)
λ0_13 = mem_price_profile()

println("Building IEEE-123 population (seed=$SEED_IEEE123)...")
feeder123 = ieee123_modified()
aggs123 = build_ieee123_aggregators(feeder123)
λ0_123 = ieee123_lambda0()

println("Running IEEE-13, reactive_consensus=false ($N_REPEATS repeats)...")
fail_13_false = count_failures(feeder13, aggs13, λ0_13; reactive_consensus = false, n_repeats = N_REPEATS)

println("Running IEEE-13, reactive_consensus=true ($N_REPEATS repeats)...")
fail_13_true = count_failures(feeder13, aggs13, λ0_13; reactive_consensus = true, n_repeats = N_REPEATS)

println("Running IEEE-123, reactive_consensus=false ($N_REPEATS repeats)...")
fail_123_false =
    count_failures(feeder123, aggs123, λ0_123; reactive_consensus = false, n_repeats = N_REPEATS)

println("Running IEEE-123, reactive_consensus=true ($N_REPEATS repeats)...")
fail_123_true =
    count_failures(feeder123, aggs123, λ0_123; reactive_consensus = true, n_repeats = N_REPEATS)

rate_13_false = fail_13_false / N_REPEATS
rate_13_true = fail_13_true / N_REPEATS
rate_123_false = fail_123_false / N_REPEATS
rate_123_true = fail_123_true / N_REPEATS

# ---- Report ------------------------------------------------------------------------------------

@printf(
    "\n%-12s %-22s %8s %8s %8s\n",
    "Fixture",
    "reactive_consensus",
    "N",
    "fails",
    "rate"
)
@printf("%-12s %-22s %8d %8d %8.3f\n", "IEEE-13", "false", N_REPEATS, fail_13_false, rate_13_false)
@printf("%-12s %-22s %8d %8d %8.3f\n", "IEEE-13", "true", N_REPEATS, fail_13_true, rate_13_true)
@printf(
    "%-12s %-22s %8d %8d %8.3f\n",
    "IEEE-123",
    "false",
    N_REPEATS,
    fail_123_false,
    rate_123_false
)
@printf(
    "%-12s %-22s %8d %8d %8.3f\n",
    "IEEE-123",
    "true",
    N_REPEATS,
    fail_123_true,
    rate_123_true
)

report_path = joinpath(OUT, "flake_rate_findings.txt")
open(report_path, "w") do io
    println(io, "Phase 16 Reactive-Power Consensus — Clarabel Flake-Rate Measurement")
    println(io, "Measured: ", Dates.format(now(), "yyyy-mm-dd HH:MM:SS"), " UTC-local")
    println(io, "Repeats per cell: N = $N_REPEATS (80 solves total)")
    println(io)
    println(io, "=== Measured NUMERICAL_ERROR-class flake rates ===")
    @printf(io, "%-12s %-22s %8s %8s %8s\n", "Fixture", "reactive_consensus", "N", "fails", "rate")
    @printf(io, "%-12s %-22s %8d %8d %8.3f\n", "IEEE-13", "false", N_REPEATS, fail_13_false, rate_13_false)
    @printf(io, "%-12s %-22s %8d %8d %8.3f\n", "IEEE-13", "true", N_REPEATS, fail_13_true, rate_13_true)
    @printf(
        io,
        "%-12s %-22s %8d %8d %8.3f\n",
        "IEEE-123",
        "false",
        N_REPEATS,
        fail_123_false,
        rate_123_false
    )
    @printf(
        io,
        "%-12s %-22s %8d %8d %8.3f\n",
        "IEEE-123",
        "true",
        N_REPEATS,
        fail_123_true,
        rate_123_true
    )
    println(io)
    println(io, "=== Finding 1: Clarabel flake rate under reactive_consensus=true ===")
    println(
        io,
        "IEEE-13:  baseline (reactive_consensus=false) rate = $(rate_13_false) ($(fail_13_false)/$N_REPEATS); ",
        "Q-consensus (reactive_consensus=true) rate = $(rate_13_true) ($(fail_13_true)/$N_REPEATS).",
    )
    println(
        io,
        "IEEE-123: baseline (reactive_consensus=false) rate = $(rate_123_false) ($(fail_123_false)/$N_REPEATS); ",
        "Q-consensus (reactive_consensus=true) rate = $(rate_123_true) ($(fail_123_true)/$N_REPEATS).",
    )
    delta13 = rate_13_true - rate_13_false
    delta123 = rate_123_true - rate_123_false
    println(
        io,
        "Delta (true - false): IEEE-13 = $(delta13); IEEE-123 = $(delta123). ",
        "This is a citable phase finding, not a pass/fail gate (16-RESEARCH.md Pitfall 5 / ",
        "Open Question 2) — the number itself is the deliverable, reported here neither ",
        "silently accepted nor silently \"fixed.\"",
    )
    println(io)
    println(io, "=== Finding 2: rho vs rho_q (Open Question 1) ===")
    println(
        io,
        "Plan 16-02's shipped mechanism pins `qag_dso[j,t]` via a HARD EQUALITY (`:qag_pin`, ",
        "`qag_dso[j,t] == q_draw[j][t]`) with NO quadratic rho-penalty term of its own ",
        "(16-RESEARCH Assumption A1/A3: the pinned target `b_j = agr.qag[j][t]` never moves — ",
        "AgrOpt.qag is a fixed constant, per thesis A3 DERs-are-active-only, so there is no ",
        "genuine reactive DER decision to iterate on). Consequently the question \"shared rho ",
        "vs a distinct rho_q\" DOES NOT APPLY to the actual shipped mechanism: there is no ",
        "rho-penalty weight of any kind on the reactive coupling constraint to tune, shared or ",
        "distinct. This is recorded as the finding rather than re-derived from scratch, per ",
        "16-RESEARCH.md's own resolution of Open Question 1 against the Plan 16-02 SUMMARY.",
    )
    if delta13 > 0.05 || delta123 > 0.05
        println(
            io,
            "NOTE: the measured reactive_consensus=true flake rate is materially worse than the ",
            "reactive_consensus=false baseline on at least one fixture (delta > 0.05). Per ",
            "16-RESEARCH.md's Pattern 1 (\"unconstrained\" alternative) / Pattern 3 (\"only ",
            "escalate if the empirical experiment shows the degenerate-target assumption ",
            "doesn't hold\"), a soft rho_q-penalized alternative to the current hard-pin ",
            "mechanism would be the natural follow-up — explicitly OUT OF SCOPE for this phase.",
        )
    else
        println(
            io,
            "The measured deltas are small (<= 0.05) on both fixtures — no evidence the ",
            "degenerate-target assumption (A1/A3) fails to hold at this scale. No follow-up ",
            "rho_q escalation (16-RESEARCH.md Pattern 3) is warranted from this measurement.",
        )
    end
end

println("\nWrote findings to: ", report_path)
