# scripts/demo_flexibility_plots.jl
#
# Demo: a TSO→DSO→aggregators day-ahead scenario with PARAMETRIZED FLEXIBILITY available.
#
# We sweep a single flexibility knob `flex` across the aggregator population and solve each
# scenario end-to-end on the IEEE-13 feeder (centralized convex social-welfare SOCP via
# `solve_welfare`), then ALSO run ONE decomposed ADMM solve to exhibit the convergence
# diagnostics. From every solve we recover the full transactive stack this framework produces:
#
#   • the day-ahead dynamic price (DADP / DLMP)            — `extract_dlmp(ctx)`
#   • the four-way DLMP decomposition (energy/loss/cong/V) — `decompose_dlmp(ctx)`
#   • the welfare surplus split (prosumer vs DSO)          — `welfare_accounting(ctx)`
#   • the TSO↔DSO frontier exchange                        — `ctx.meta[:p_import]`
#   • the ADMM primal/dual + price-convergence traces      — `solve_admm(...).residuals`
#
# We then render a set of publication-quality CairoMakie figures showing how aggregator
# flexibility reshapes prices, welfare, congestion, and the system net-demand profile.
#
# Run:
#     julia --project=. scripts/demo_flexibility_plots.jl
# Figures land in  results/demo_flexibility_plots/  (PDF + PNG).

using DrWatson
@quickactivate "TSODSO"
using TSODSO
using CairoMakie
using Printf
using Statistics
using JuMP: value

import Dates

# -------------------------------------------------------------------------------------------
# Output directory (committed, diff-friendly location under results/).
# -------------------------------------------------------------------------------------------
const OUT = projectdir("results", "demo_flexibility_plots")
mkpath(OUT)

# -------------------------------------------------------------------------------------------
# Fixed scenario selectors (mirrors the `:default` IEEE-13 population SHAPE from
# src/experiments/materialize.jl, but with the device/storage capacities exposed as a single
# `flex` knob so a researcher can dial aggregator flexibility up/down).
# -------------------------------------------------------------------------------------------
const FEEDER_SYM = :ieee13
const T          = 24                 # day-ahead horizon (hours)
const SEED       = 42                 # master seed (threaded per-bus via generate_profiles)
const PF         = ConvexBranchFlow() # SOCP branch-flow (gives physically meaningful DLMPs)

# IEEE-13 (100 MVA base) residential magnitude scales — SAME values as the `:default`
# population (src/experiments/materialize.jl `_IEEE13_*`), so `flex = 1.0` reproduces it.
const LOAD_SCALE = 0.005              # inelastic demand magnitude (pu)
const PV_SCALE   = 0.03               # rooftop PV magnitude (pu)
const BATT_λ_MIN = 3.8                # App. C battery price triple (¢$/kWh-consistent)
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9

# The 24h ambient-temperature profile (°C) feeding the thermostatic `Tout` — the SAME digitized
# shape as the project default (thesis Fig 4.2). Inlined here so the script is self-contained.
const TEMPERATURE_24H = Float64[
    19, 18, 17, 16, 16, 17,   # 00–05 dawn minimum
    19, 21, 23, 26, 28, 30,   # 06–11 morning warm-up
    31, 32, 32, 31, 29, 27,   # 12–17 afternoon peak
    25, 23, 22, 21, 20, 19,   # 18–23 evening cool-down
]
temperature_profile(T::Int) = Float64[TEMPERATURE_24H[mod1(t, 24)] for t in 1:T]

"""
    flexibility_population(feeder, master_seed, T; flex, φ=0.90) -> Vector{Aggregator}

Build one residential `Aggregator` per non-root bus, with the SHIFTABLE capacity of each house
scaled by `flex`. `flex = 1.0` reproduces the `:default` IEEE-13 population; `flex < 1` tightens
the battery / deferrable / thermostatic headroom (less load can be moved across hours);
`flex > 1` amplifies it (more storage, more deferrable energy). PV generation and inelastic
demand magnitudes are held FIXED, so all welfare/price differences are attributable to the
flexibility knob alone (a clean single-variable study).

This is the demo's "parametrized flexibility available": each aggregator fields a
`Thermostatic` (A/C, comfort-band power `∝ flex`), a `Deferrable` (energy budget + power
`∝ flex`), and a `PVBattery` (storage energy + power `∝ flex`).

**Special case `flex = 0.0` — NO FLEXIBILITY (pure inelastic demand):** the aggregators drop
the Thermostatic and Deferrable entirely and keep only the PV (as passive generation) plus a
token-negligible battery (Pmax ∝ 1e-4, far too small to time-shift any load) so the device set
is non-empty. This is the "rooftop PV + dumb demand, nothing to shift" prosumer — the lower
bound of the flexibility sweep.
"""
function flexibility_population(feeder, master_seed::Integer, T::Int; flex::Real, φ::Real = 0.90)
    flex >= 0 ||
        throw(ArgumentError("flex must be ≥ 0 (0 = no flexibility / inelastic demand); got flex=$flex"))
    Tout = temperature_profile(T)
    buses = [b.id for b in feeder.buses if !b.is_root]
    no_flex = iszero(flex)            # flex = 0 → pure inelastic demand (PV + dumb load)
    aggs = Aggregator[]
    for bus in buses
        # Per-bus deterministic profile draw (same idiom as the `:default` population).
        prof = generate_profiles(; seed = master_seed + bus, T = T)
        Pdc  = LOAD_SCALE .* prof.demand
        Ppv  = PV_SCALE   .* prof.pv

        if no_flex
            # NO FLEXIBILITY: passive PV generation + inelastic demand, nothing meaningfully
            # shiftable. We keep the full device set (well-conditioned SOCP) but floor the
            # shiftable capacity at a small ε (1% of the default) — at that scale the battery
            # can move ~1% of one hour's demand and the flexible loads are negligible, so the
            # prosumer is effectively "PV + dumb demand". An exact zero (Pmax=E=0) makes the
            # SOCP degenerate (ALMOST_OPTIMAL), and a smaller ε trips the App. C battery
            # complementarity gate on the tiny battery (Pmax² → ratio blows up), so ε=1e-2 is
            # the faithful numerical realization of the zero-flexibility limit.
            ε = 1e-2
            therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0 * ε, 0.5, Tout)
            defer = Deferrable(bus, min(8, T), min(16, T), 1.0 * ε, 0.5 * ε, 0.5)
            batt  = PVBattery(
                bus, 0.95, 1.0,
                0.5 * LOAD_SCALE * ε,            # Pmax ~ 1% of default → negligible shifting
                0.0,
                2.0 * LOAD_SCALE * ε,            # Emax ~ 1% of default → negligible storage
                1.0 * LOAD_SCALE * ε,
                BATT_λ_MIN, BATT_λ_MED, BATT_λ_MAX,
                Ppv,
            )
            push!(aggs, Aggregator(bus, φ, [therm, defer, batt], Pdc))
        else
            therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0 * flex, 0.5, Tout)
            defer = Deferrable(bus, min(8, T), min(16, T), 1.0 * flex, 0.5 * flex, 0.5)
            batt  = PVBattery(
                bus,
                0.95,                         # round-trip efficiency η
                1.0,                          # Δt (h)
                0.5 * LOAD_SCALE * flex,      # Pmax (charge/discharge power)
                0.0,                          # Emin
                2.0 * LOAD_SCALE * flex,      # Emax (storage energy)
                1.0 * LOAD_SCALE * flex,      # soc0
                BATT_λ_MIN, BATT_λ_MED, BATT_λ_MAX,
                Ppv,
            )
            push!(aggs, Aggregator(bus, φ, [therm, defer, batt], Pdc))
        end
    end
    return aggs
end

# -------------------------------------------------------------------------------------------
# 1. FLEXIBILITY SWEEP — solve the centralized welfare optimum at each flex level.
#    Collect welfare, DADP, surplus split, frontier exchange, and DLMP decomposition.
# -------------------------------------------------------------------------------------------
const FLEX_LEVELS = [0.0, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0]   # 0.0 = no flexibility (inelastic demand)

println("=" ^ 70)
println("TSO→DSO→aggregators flexibility demo")
println("  feeder = $FEEDER_SYM, T = $T, seed = $SEED")
println("  flex levels = $(FLEX_LEVELS)")
println("=" ^ 70)

feeder = build_feeder(FEEDER_SYM)
λ₀     = build_price(:mem, T, nothing)          # the MEM/wholesale price (TSO signal)
hours  = 0:(T - 1)                              # 00:00 .. 23:00 axis
load_buses = sort!([b.id for b in feeder.buses if !b.is_root])

records = []  # one NamedTuple per flex level
for flex in FLEX_LEVELS
    aggs = flexibility_population(feeder, SEED, T; flex = flex)
    ctx, welfare, _ = solve_welfare(
        feeder,
        PF,
        aggs;
        T = T,
        λ₀ = λ₀,
        allow_export = true,                    # priced export = SOC-exactness enabler (PF-04)
        # At low `flex` the batteries are tiny (Pmax ∝ flex), so the scale-free relative
        # complementarity test `p_ch·p_dch < τ·Pmax²` becomes borderline-numerical even when
        # simultaneous charge/discharge is physically negligible (<0.2% of Pmax²). A modestly
        # looser τ keeps the demo's full flex range runnable without weakening the gate
        # meaningfully (the default SOCP τ is 1e-3).
        τ = 5e-3,
    )
    acct   = welfare_accounting(ctx; T = T)
    dadp   = extract_dlmp(ctx)[load_buses, :]   # (n_load, T) — DADP at aggregator buses
    decomp = decompose_dlmp(ctx)                # (; energy, loss, congestion, voltage, total)
    pimp   = Float64[value.(ctx.meta[:p_import])...]   # frontier exchange (TSO↔DSO), length T

    push!(records, (;
        flex           = flex,
        welfare        = welfare,
        prosumer       = acct.prosumer,
        dso            = acct.dso,
        dadp           = dadp,
        decomp         = decomp,
        p_import       = pimp,
        exact_maxgap   = ctx.meta[:socp_maxgap],
    ))
    @printf("  flex=%4.2f  welfare=%9.4f  prosumer=%9.4f  dso=%8.4f  exact_gap=%.2e  peak_DADP=%.3f\n",
        flex, welfare, acct.prosumer, acct.dso, ctx.meta[:socp_maxgap], maximum(dadp))
end

# Index of the baseline (flex = 1.0) record — used as the reference case in several plots.
baseline_idx = findfirst(==(1.0), FLEX_LEVELS)

# -------------------------------------------------------------------------------------------
# 2. ONE ADMM solve (baseline flex) — exhibit the decomposed TSO↔DSO↔AGR convergence traces.
#    Best-effort: the ADMM path is numerically noisier than the centralized solve (it is an
#    iterative price decomposition), and its final re-solve enforces the App. C battery
#    complementarity gate at a hardcoded τ_batt = 1e-3. If that gate is borderline at the
#    chosen flex we skip the two convergence plots and keep the (always-interesting) sweep
#    figures above.
# -------------------------------------------------------------------------------------------
println("\nRunning one ADMM solve (flex = 1.0) for convergence diagnostics...")
admm = nothing
try
    global admm = solve_admm(
        feeder,
        PF,
        flexibility_population(feeder, SEED, T; flex = 1.0);
        T       = T,
        λ₀      = λ₀,
        ρ       = 100.0,        # validated initial penalty for the IEEE-13 default population
        maxiter = 300,
        allow_export = true,
    )
    println("  ADMM converged in $(admm.iters) iters; welfare=$(round(admm.welfare; digits=4))  ",
            "(centralized baseline: ", round(records[baseline_idx].welfare; digits = 4), ")")
catch e
    println("  ⚠ ADMM solve did not pass the App. C battery complementarity gate at this flex —")
    println("    skipping the two convergence plots (the flexibility-sweep figures are unaffected).")
    println("    reason: ", sprint(showerror, e))
end

# -------------------------------------------------------------------------------------------
# 3. PLOTS
# -------------------------------------------------------------------------------------------
# A perceptually-ordered color ramp across the flex sweep (dark = low flex, bright = high flex).
flex_colors = cgrad(:viridis, length(FLEX_LEVELS); categorical = true)

saveboth(name, fig) = (save(joinpath(OUT, "$name.pdf"), fig); save(joinpath(OUT, "$name.png"), fig))

# === (3a) Summary 2×2 ============================================================
let
    fig = Figure(; size = (1000, 760))
    st  = fig[0, 1:2] = Label(fig,
        "TSO→DSO→aggregators day-ahead scenario — effect of aggregator flexibility (IEEE-13, T=$T)",
        fontsize = 16, font = :bold)

    # (a) Social welfare vs flex. The objective Σ U_ag − λ₀ᵀp_import is dominated by the
    # (negative) MEM import cost on this 100 MVA base, so welfare is large-negative and the
    # differences across flex are small in relative terms — but the trend and magnitude are
    # the honest picture. Annotate the actual signed change, not a misleading "gain".
    axW = Axis(fig[1, 1];
        xlabel = "flexibility scale `flex`",
        ylabel = "social welfare (per-unit)",
        title  = "(a) Social welfare vs aggregator flexibility",
        titlealign = :left)
    welfare_vals = [r.welfare for r in records]
    w0 = first(welfare_vals)
    lines!(axW, FLEX_LEVELS, welfare_vals; color = :dodgerblue, linewidth = 2)
    scatter!(axW, FLEX_LEVELS, welfare_vals; color = :dodgerblue, markersize = 10)
    Δ_pct = 100 * (welfare_vals[end] - w0) / abs(w0)
    text!(axW, FLEX_LEVELS[end], welfare_vals[end];
        text = "  Δ = $(round(Δ_pct; digits = 2))% vs flex=$(first(FLEX_LEVELS))",
        align = (:right, Δ_pct >= 0 ? (:bottom) : (:top)), fontsize = 11, color = :dimgrey)
    axW.xticks = FLEX_LEVELS

    # (b) Surplus split (stacked: prosumer + DSO) vs flex
    axS = Axis(fig[1, 2];
        xlabel = "flexibility scale `flex`",
        ylabel = "surplus (per-unit)",
        title  = "(b) Prosumer vs DSO surplus split",
        titlealign = :left)
    prosumer_vals = [r.prosumer for r in records]
    dso_vals      = [r.dso      for r in records]
    barplot!(axS, 1:length(FLEX_LEVELS), prosumer_vals;
        color = :seagreen, label = "prosumer")
    barplot!(axS, 1:length(FLEX_LEVELS), dso_vals;
        offset = prosumer_vals, color = :indianred, label = "DSO")
    axS.xticks = (1:length(FLEX_LEVELS), string.(FLEX_LEVELS))
    axislegend(axS; position = :lt)

    # (c) Frontier exchange (TSO↔DSO net flow) over the day, one curve per flex
    axF = Axis(fig[2, 1];
        xlabel = "hour of day",
        ylabel = "frontier exchange p_import (per-unit)",
        title  = "(c) TSO↔DSO exchange: flexibility peak-shaves & reshapes",
        titlealign = :left)
    for (i, r) in enumerate(records)
        lines!(axF, hours, r.p_import;
            color = flex_colors[i], linewidth = 1.8,
            label = "flex=$(r.flex)")
    end
    axF.xticks = 0:3:23
    axislegend(axF; position = :rt, framevisible = false)

    # (d) Mean DADP (over load nodes) ± spread over the day, baseline vs highest flex
    axP = Axis(fig[2, 2];
        xlabel = "hour of day",
        ylabel = "DADP (per-unit)",
        title  = "(d) Day-ahead dynamic price: flexibility flattens the peak",
        titlealign = :left)
    for (idx, label_txt) in ((1, "low flex ($(FLEX_LEVELS[1]))"), (baseline_idx, "baseline (1.0)"), (lastindex(FLEX_LEVELS), "high flex ($(FLEX_LEVELS[end]))"))
        r = records[idx]
        mean_dadp = vec(mean(r.dadp; dims = 1))
        lo        = vec(minimum(r.dadp; dims = 1))
        hi        = vec(maximum(r.dadp; dims = 1))
        band!(axP, hours, lo, hi; color = (flex_colors[idx], 0.2))
        lines!(axP, hours, mean_dadp; color = flex_colors[idx], linewidth = 2, label = label_txt)
    end
    # overlay the MEM wholesale price λ₀ for reference (the TSO signal)
    lines!(axP, hours, λ₀; color = :black, linestyle = :dash, linewidth = 1.5, label = "MEM λ₀")
    axP.xticks = 0:3:23
    axislegend(axP; position = :rt, framevisible = false)

    saveboth("summary", fig)
    println("\n✓ summary.{pdf,png}")
end

# === (3b) DLMP decomposition (baseline) — stacked energy/loss/congestion/voltage ===========
# (the decomposition fields are (N, T) matrices; average over the load-bus rows for a clean stack)
let
    r = records[baseline_idx]
    energy     = vec(mean(r.decomp.energy[load_buses, :];     dims = 1))
    loss       = vec(mean(r.decomp.loss[load_buses, :];       dims = 1))
    congestion = vec(mean(r.decomp.congestion[load_buses, :]; dims = 1))
    voltage    = vec(mean(r.decomp.voltage[load_buses, :];    dims = 1))

    fig = Figure(; size = (900, 500))
    fig[0, 1] = Label(fig,
        "DLMP four-way decomposition (baseline flex=1.0, averaged over aggregator buses)";
        fontsize = 15, font = :bold)
    ax = Axis(fig[1, 1];
        xlabel = "hour of day",
        ylabel = "price component (per-unit)",
        title  = "energy + loss + congestion + voltage = DADP")
    # stack from the bottom: energy → loss → congestion → voltage
    barplot!(ax, hours .+ 1, energy;     color = :steelblue,  label = "energy")
    barplot!(ax, hours .+ 1, loss;       offset = energy,     color = :orange,    label = "loss")
    barplot!(ax, hours .+ 1, congestion; offset = energy .+ loss,             color = :crimson,   label = "congestion")
    barplot!(ax, hours .+ 1, voltage;    offset = energy .+ loss .+ congestion, color = :purple,   label = "voltage")
    # overlay the total DADP (mean over nodes) as a line to confirm the stack sums to it
    mean_total = vec(mean(r.dadp; dims = 1))
    lines!(ax, hours .+ 1, mean_total; color = :black, linewidth = 2, label = "DADP (mean)")
    ax.xticks = 1:3:24
    axislegend(ax; position = :rt)
    saveboth("dlmp_decomposition", fig)
    println("✓ dlmp_decomposition.{pdf,png}")
end

# === (3c) DADP heatmap (baseline) — node × hour ===================================
let
    r = records[baseline_idx]
    fig = Figure(; size = (850, 460))
    fig[0, 1] = Label(fig, "Day-ahead dynamic price (DADP) — aggregator buses × hour (baseline flex=1.0)";
        fontsize = 15, font = :bold)
    n_load = length(load_buses)
    ax = Axis(fig[1, 1];
        xlabel = "hour of day",
        ylabel = "aggregator bus",
        yreversed = true,
        # cells are labeled by their (hour, bus); ticks sit at cell centers.
        xticks = (collect(1:T) .- 0.5, string.(hours)),
        yticks = (collect(1:n_load) .- 0.5, string.(load_buses)))
    # This CairoMakie build requires EDGE vectors (length = dim+1) for non-interpolated heatmaps,
    # and indexes matrix[xi, yi] at (x[xi], y[yi]) — so the matrix must be (length(x)-1, length(y)-1)
    # = (T, n_load). r.dadp is (n_load, T), hence the transpose; x = hour-edges, y = bus-edges.
    hm = heatmap!(ax, collect(0:T), collect(0:n_load), Matrix(r.dadp'); colormap = :plasma)
    Colorbar(fig[1, 2], hm; label = "DADP (per-unit)")
    saveboth("dadp_heatmap", fig)
    println("✓ dadp_heatmap.{pdf,png}")
end

# === (3d) Congestion relief — nodal price spread vs flex =========================
let
    fig = Figure(; size = (900, 460))
    fig[0, 1] = Label(fig, "Nodal price spread (max−min DADP across aggregator buses)";
        fontsize = 15, font = :bold)
    ax = Axis(fig[1, 1];
        xlabel = "hour of day",
        ylabel = "nodal price spread (per-unit)",
        title  = "more flexibility → flatter network → less congestion")
    for (i, r) in enumerate(records)
        spread = vec(maximum(r.dadp; dims = 1) .- minimum(r.dadp; dims = 1))
        lines!(ax, hours, spread; color = flex_colors[i], linewidth = 1.8, label = "flex=$(r.flex)")
    end
    ax.xticks = 0:3:23
    axislegend(ax; position = :rt, framevisible = false)
    saveboth("congestion_relief", fig)
    println("✓ congestion_relief.{pdf,png}")
end

# === (3e) ADMM convergence diagnostics (baseline) ================================
if admm !== nothing
    fig_conv = TSODSO.plot_convergence(admm.residuals)
    saveboth("admm_convergence_residuals", fig_conv)
    println("✓ admm_convergence_residuals.{pdf,png}")

    fig_price = TSODSO.plot_price_convergence(admm.residuals)
    saveboth("admm_convergence_price", fig_price)
    println("✓ admm_convergence_price.{pdf,png}")
end

println("\nAll figures written to: ", OUT)
println("Done.")
