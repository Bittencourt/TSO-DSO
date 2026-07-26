# scripts/thesis_case123_repro.jl
#
# Phase 18 (directional thesis reproduction) — the REPRO-01 promotion-source script: the
# IEEE-123 real-impedance DADP-vs-FIT reproduction of the thesis's headline DSO-surplus welfare
# result, on Phase 17's real, Fortescue-reduced impedances + the Phase-17-retuned population,
# with reactive pricing available via `decompose_dlmp(ctx).reactive` (Phase 16). Mirrors
# `scripts/thesis_caseA.jl`'s DrWatson scaffold and figure conventions on this new fixture.
#
# WHAT THIS DOES NOT CLAIM (18-RESEARCH.md's central honesty finding, carried forward here):
# the thesis's headline +25% AGGREGATE-WELFARE-RATIO MAGNITUDE does NOT reproduce on real public
# IEEE-123 data — the aggregate welfare gap here is small (≈+0.045% on this fixture) and reported
# below ONLY as an explicitly-labeled fragile SECONDARY number, never the primary claim (Pitfall
# 1: `welfare_dadp / welfare_fit` sign-inverts on negative welfare and must never be the headline
# metric). What DOES reproduce, robustly and correctly-signed, is the DSO-SURPLUS SIGN FLIP: the
# FIT baseline's DSO surplus is negative, the DADP optimum's DSO surplus is positive — the same
# directional finding as the thesis's own Case A ("DSO surplus -$2829 -> +$439"), on a real,
# public-data feeder rather than a thesis-figure-calibrated one. Every cited number below carries
# the fixed "directional, public-data" qualifier so a reader never mistakes this directional
# reproduction for an exact-figure claim (18-PATTERNS.md).
#
# Plan 18-01 additionally measured (scripts/repro_stability_check.jl,
# results/repro_stability_check/findings.txt) that this sign flip is confirmed ONLY at the exact
# Phase-17-retuned population point (delta=0.0) — a +/-2-5% population-scale perturbation makes
# the SOCP relaxation go genuinely inexact (`assert_socp_exact!` throws) before the sign flip can
# even be evaluated (`sign_flip_survives: false`). This script runs ONLY at that exact pinned
# point; it does not re-run the sweep (see `scripts/repro_stability_check.jl` for that
# measurement, and `docs/literate/thesis_reproduction_assumptions.jl` for the full caveat).
#
# Run:
#     julia --project=. scripts/thesis_case123_repro.jl
# Figures land in  results/thesis_case123_repro/  (PDF + PNG).

using DrWatson
@quickactivate "TSODSO"
using TSODSO
using CairoMakie
using Printf
using Statistics
using JuMP: value

# -------------------------------------------------------------------------------------------
# Output directory (mirrors thesis_caseA.jl's scaffold, new OUT dir per the plan interfaces).
# -------------------------------------------------------------------------------------------
const OUT = projectdir("results", "thesis_case123_repro")
mkpath(OUT)

saveboth(name, fig) = (save(joinpath(OUT, "$name.pdf"), fig); save(joinpath(OUT, "$name.png"), fig))

# -------------------------------------------------------------------------------------------
# The "directional, public-data" qualifier — the ONE new convention this phase introduces.
# Apply to every printed/cited reproduction number below (18-PATTERNS.md).
# -------------------------------------------------------------------------------------------
const REPRO_QUALIFIER = "directional, public-data"
cite_repro(x) = "$x ($REPRO_QUALIFIER)"

# -------------------------------------------------------------------------------------------
# IEEE-123 population — re-implemented inline, verbatim from test/fixtures_phase7.jl (lines
# 92-95, 178-264) and scripts/repro_stability_check.jl's own inline copy, since
# `Phase7Fixtures` is a `TestItems.@testmodule` and expands to a no-op outside
# `TestItemRunner`'s AST-introspection path (a plain script `include` would not define it).
# -------------------------------------------------------------------------------------------
const T = 24

const BATT_λ_MIN = 3.8
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9

# Phase-17-retuned population point (verbatim from test/fixtures_phase7.jl:92-95).
const SEED_IEEE123 = 20260719
const LOAD_SCALE_IEEE123 = 0.05
const PV_SCALE_IEEE123 = 0.12
const DEV_SCALE_IEEE123 = 0.05 * (0.05 / 0.03)   # ratio to LOAD_SCALE held fixed

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

function build_ieee123_aggregators(
    feeder;
    seed::Integer = SEED_IEEE123,
    load_buses = nothing,
)
    buses = load_buses === nothing ? ieee123_load_nodes() : load_buses
    return [
        _house_aggregator(
            feeder,
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

# -------------------------------------------------------------------------------------------
# Case 123 scenario — real-impedance modified IEEE-123, Phase-17-retuned population, 24h.
# -------------------------------------------------------------------------------------------
const FEEDER = ieee123_modified()
const PF = ConvexBranchFlow()
const λ₀ = ieee123_lambda0()
const hours = 0:(T - 1)
const aggs = build_ieee123_aggregators(FEEDER)

println("=" ^ 72)
println("Thesis Case A reproduction — real-impedance IEEE-123 feeder ($REPRO_QUALIFIER)")
println("  $(length(aggs)) aggregator buses, T=$T, seed=$SEED_IEEE123, digitized MEM λ₀")
println("=" ^ 72)

# -------------------------------------------------------------------------------------------
# 1. DADP solve (centralized GLB-CVX welfare optimum, eq 3.38) + FIT baseline (eqs 3.24-3.28).
#    `fit_baseline` is the plain seam (confirmed feasible on IEEE-123, unlike IEEE-13's
#    congestion-driven infeasibility — no manual S_max-relaxed FIT solve needed here).
# -------------------------------------------------------------------------------------------
println("\n[1/2] Solving the DADP welfare optimum (GLB-CVX SOCP, eq 3.38)...")
ctx, welfare_dadp, _ = solve_welfare(FEEDER, PF, aggs; T = T, λ₀ = λ₀, allow_export = true)
acct = welfare_accounting(ctx; T = T)          # (; social, dso, prosumer)
maxgap = ctx.meta[:socp_maxgap]                # PF-04 SOC-exactness certificate

println("\n[2/2] Solving the FIT baseline (German feed-in tariff, eqs 3.24-3.28)...")
fb = fit_baseline(FEEDER, PF, aggs; T = T, λ₀ = λ₀)
fit_dso = fb.social_fit - fb.prosumer_surplus

# ── Reactive DLMP (Phase 16, decompose_dlmp(ctx).reactive) — a plain solve_welfare ctx already
# carries the reactive channel; NO ADMM-only reactive-consensus dual-ascent kwarg is needed or
# accepted here (Pitfall 3 — that mechanism belongs solely to the ADMM decomposition path, never
# threaded into this centralized solve_welfare seam).
d = decompose_dlmp(ctx)

println("  SOCP exactness   = ", cite_repro(round(maxgap; sigdigits = 2)), " (certified exact)")
println(
    "  DADP DSO surplus = ",
    cite_repro(round(acct.dso; digits = 6)),
    "   FIT DSO surplus = ",
    cite_repro(round(fit_dso; digits = 6)),
)
println(
    "  DADP prosumer    = ",
    cite_repro(round(acct.prosumer; digits = 4)),
    "   FIT prosumer    = ",
    cite_repro(round(fb.prosumer_surplus; digits = 4)),
)
println(
    "  reactive DLMP    = ",
    cite_repro(round(mean(d.reactive); digits = 6)),
    " pu (mean over node × hour; range [",
    round(minimum(d.reactive); digits = 6),
    ", ",
    round(maximum(d.reactive); digits = 6),
    "])",
)

# -------------------------------------------------------------------------------------------
# HEADLINE (primary): the DSO-surplus sign flip. NEVER the aggregate welfare ratio (Pitfall 1 —
# dividing the DADP welfare by the FIT welfare sign-inverts silently on negative welfare and is
# never printed here as the primary metric).
# -------------------------------------------------------------------------------------------
println("\n" * "=" ^ 72)
println("PRIMARY FINDING — DSO-surplus sign flip ", cite_repro(""))
@printf(
    "  FIT DSO surplus  = %.6f  ->  DADP DSO surplus = %.6f  (sign flip: %s)\n",
    fit_dso,
    acct.dso,
    cite_repro(fit_dso < 0.0 && acct.dso > 0.0 ? "confirmed" : "NOT confirmed"),
)
@printf(
    "  FIT prosumer     = %.6f  ->  DADP prosumer     = %.6f  (decrease: %s)\n",
    fb.prosumer_surplus,
    acct.prosumer,
    cite_repro(acct.prosumer < fb.prosumer_surplus ? "confirmed" : "NOT confirmed"),
)
println(
    "  This mirrors the thesis's own Case A framing (\"DSO surplus -\$2829 -> +\$439\") — the ",
    "sign of the redistribution, not its magnitude, is the reproducible claim on this real, ",
    "public-data feeder (see docs/literate/thesis_reproduction_assumptions.jl for the full ",
    "caveat chain, including 18-01's honest sign_flip_survives=false population-scale-",
    "sensitivity finding).",
)

# SECONDARY, fragile: the aggregate welfare delta (never the ratio — Pitfall 1). Reported thin,
# explicitly labeled fragile, and never used to drive any assertion below.
welfare_delta_pct = 100 * (welfare_dadp - fb.social_fit) / abs(fb.social_fit)
println(
    "\n  (secondary, fragile, ",
    cite_repro("not the primary claim"),
    "): aggregate welfare delta = ",
    cite_repro(@sprintf("%.4f%%", welfare_delta_pct)),
    " — small and comparatively fragile at this population scale; do NOT read this the way the ",
    "thesis's own +25% headline ratio is read.",
)
println("=" ^ 72)

# -------------------------------------------------------------------------------------------
# PLOT — "DSO surplus sign flip" bar chart (mirrors thesis_caseA.jl Fig D's axS surplus-split
# bar-pair layout), into results/thesis_case123_repro/.
# -------------------------------------------------------------------------------------------
let
    fig = Figure(; size = (950, 520))
    fig[0, 1] = Label(
        fig,
        "Thesis Case A reproduction — IEEE-123 real impedances: DSO-surplus sign flip ($REPRO_QUALIFIER)";
        fontsize = 14,
        font = :bold,
    )
    axS = Axis(
        fig[1, 1];
        xlabel = "pricing scheme",
        ylabel = "surplus (per-unit)",
        xticks = (1:2, ["FIT", "DADP"]),
        title = "prosumer vs DSO surplus split",
    )
    barplot!(axS, [1], [fb.prosumer_surplus]; color = :dodgerblue, label = "prosumer")
    barplot!(axS, [1], [fit_dso]; offset = [fb.prosumer_surplus], color = :orange, label = "DSO")
    barplot!(axS, [2], [acct.prosumer]; color = :dodgerblue)
    barplot!(axS, [2], [acct.dso]; offset = [acct.prosumer], color = :orange)
    hlines!(axS, [0]; color = :grey, linewidth = 0.5)
    axislegend(axS; position = :lt)

    axD = Axis(
        fig[1, 2];
        xlabel = "pricing scheme",
        ylabel = "DSO surplus alone (per-unit)",
        xticks = (1:2, ["FIT", "DADP"]),
        title = "DSO surplus — the sign flip",
    )
    barplot!(axD, [1, 2], [fit_dso, acct.dso]; color = [:indianred, :seagreen])
    hlines!(axD, [0]; color = :grey, linewidth = 0.5)
    text!(
        axD,
        2,
        acct.dso;
        text = " sign flip $(cite_repro(""))",
        align = (:left, :bottom),
        fontsize = 11,
        font = :bold,
        color = :seagreen,
    )
    saveboth("fig_dso_surplus_sign_flip", fig)
    println("\n✓ fig_dso_surplus_sign_flip.{pdf,png}")
end

println("All figures written to: ", OUT)

# -------------------------------------------------------------------------------------------
# Self-asserting finding: the script fails loudly if the sign flip stops holding at this exact
# pinned population point (never silently reported as passing).
# -------------------------------------------------------------------------------------------
@assert acct.dso > 0.0 && fit_dso < 0.0 "DSO-surplus sign flip did not hold ($(cite_repro("")))"
@assert acct.prosumer < fb.prosumer_surplus "prosumer-surplus decrease did not hold ($(cite_repro("")))"

println("\nRESULT: DSO-surplus sign flip + prosumer-surplus decrease both confirmed ", cite_repro(""), ".")
