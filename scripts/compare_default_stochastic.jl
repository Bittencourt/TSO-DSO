# scripts/compare_default_stochastic.jl
#
# Side-by-side: DEFAULT (deterministic, single-forecast welfare solve via run_scenario's
# :centralized strategy) vs STOCHASTIC (two-stage S-scenario extensive form + out-of-sample
# evaluation via run_stochastic) on the SAME network (:ieee13), same master seed, same
# horizon T = 9 (the :default population floor; also the T at which the demo probability
# vector is known to converge cleanly).
#
# Run:  julia --project=. scripts/compare_default_stochastic.jl
#
# NOTE on comparability: run_scenario materializes its single profile draw from
# sub_seed(seed, :profiles) while run_stochastic materializes its S in-sample draws from a
# DISJOINT tag family (sub_seed(seed, :stoch_insample_profiles_k)) — by design, so no
# stochastic draw replays the deterministic one. The welfare numbers are therefore on
# different exogenous draws; the meaningful comparison is the SHAPE of the outputs:
# one price path vs S scenario-conditioned price paths + one shared battery schedule.
using DrWatson
@quickactivate "TSODSO"
using TSODSO
using CairoMakie
using Statistics

# Figures (PDF + PNG into results/compare_default_stochastic/), mirroring
# scripts/demo_mpc_plots.jl's own output convention:
#   1. dadp_comparison    — default single-forecast DADP vs the 5 per-scenario stochastic
#                           DADPs + expected DADP; right panel: deviations from E[DADP].
#   2. scenario_fan       — the 5 in-sample PV/demand draws the extensive form hedges over
#                           (regenerated via the SAME exported seeding seams run_stochastic
#                           uses, so bit-identical to what each scenario saw in the solve).
#   3. welfare_robustness — the committed first-stage schedule re-scored on the 10 held-out
#                           draws vs the in-sample optimum; right panel: per-hour scenario
#                           price spread (the "how scenario-conditioned is the price" view).
#   4. price_envelope     — min–max scenario price band with the two summary paths overlaid;
#                           right panel: signed default − E[DADP] bars.
# Machine-readable artifacts (cf. results/pv_boom): summary.csv (scalars), dadp_tidy.csv
# (tidy source×hour price table), oos_draws.csv (per-held-out-draw realized welfare).
const OUT = projectdir("results", "compare_default_stochastic")
mkpath(OUT)

saveboth(name, fig) =
    (save(joinpath(OUT, "$name.pdf"), fig); save(joinpath(OUT, "$name.png"), fig))

const T = 9
const SEED = 42

# --- 1. DEFAULT run: one forecast in, one schedule + one price path out ------------------
s_default = Scenario(;
    name = "compare-default",
    feeder = :ieee13,
    strategy = :centralized,
    seed = SEED,
    T = T,
)

println("="^72)
println("DEFAULT (deterministic, :centralized) — feeder :ieee13, T = $T, seed = $SEED")
println("="^72)
t_def = @elapsed r_def = run_scenario(s_default)

println("welfare            = ", round(r_def.welfare; digits = 6))
println("SOCP exact maxgap  = ", r_def.exact_maxgap)
println("DADP (first load bus, $T hours):")
println("  ", round.(r_def.dadp[1, :]; digits = 4))
println("solve time         = ", round(t_def; digits = 2), " s")

# --- 2. STOCHASTIC run: S futures in, one hedged battery schedule + S price paths out ----
s_stoch = Scenario(;
    name = "compare-stochastic",
    feeder = :ieee13,
    seed = SEED,
    T = T,
    stoch_S = 5,
    stoch_probabilities = [0.05, 0.15, 0.30, 0.30, 0.20],
    stoch_H_oos = 10,
)

println()
println("="^72)
println("STOCHASTIC (S = 5 extensive form + 10 held-out) — feeder :ieee13, T = $T, seed = $SEED")
println("="^72)
t_stoch = @elapsed r_stoch = run_stochastic(s_stoch)

inS = r_stoch.in_sample
println("probabilities      = ", inS.probabilities)
println("in-sample welfare  = ", round(inS.welfare; digits = 6), "  (probability-weighted)")
println("SOCP exact maxgap  = ", round(maximum(inS.socp_maxgap); digits = 6),
    "  (max over scenarios; each gated independently)")
println()
println("Per-scenario DADP at the priced bus (PRIMARY output):")
for k in eachindex(inS.dadp)
    println("  scenario $k (p = ", inS.probabilities[k], "): ",
        round.(inS.dadp[k]; digits = 4))
end
println()
println("Expected DADP (DERIVED summary, not a real price):")
println("  ", round.(inS.expected_dadp; digits = 4))
println()
println("Out-of-sample (committed battery schedule vs 10 unseen draws):")
oos = r_stoch.oos
println("  realized welfare  = ", round(oos.realized_welfare; digits = 6),
    "  (mean over feasible held-out draws)")
println("  welfare gap       = ", round(oos.welfare_gap; digits = 6),
    "  (realized − in-sample)")
println("  infeasible draws  = ", count(oos.infeasible_h), " / ", length(oos.infeasible_h))
println("solve time         = ", round(t_stoch; digits = 2), " s")

# --- 3. Side-by-side price summary --------------------------------------------------------
println()
println("="^72)
println("SIDE BY SIDE — DADP at the priced bus")
println("="^72)
println("default     : ", round.(r_def.dadp[1, :]; digits = 4))
println("stoch E[·]  : ", round.(inS.expected_dadp; digits = 4))
spread = [
    maximum(inS.dadp[k][t] for k in eachindex(inS.dadp)) -
    minimum(inS.dadp[k][t] for k in eachindex(inS.dadp)) for t in 1:T
]
println("per-hour scenario spread (max−min across the 5 DADPs):")
println("  ", round.(spread; digits = 4))
println("max scenario spread at any hour: ", round(maximum(spread); digits = 4))

# --- 4. FIGURES ---------------------------------------------------------------------------
# Fixed color per scenario, reused across ALL figures (identity follows the entity across
# figures — same idiom as docs/literate/stochastic_pv_demand.jl).
const S = s_stoch.stoch_S
const H_OOS = s_stoch.stoch_H_oos
scen_colors = [:dodgerblue, :crimson, :seagreen, :orange, :purple]

# Figure 1 — DADP comparison: default vs the 5 scenario DADPs + expectation; deviations.
fig1 = Figure(size = (1080, 420))
ax1 = Axis(
    fig1[1, 1];
    xlabel = "hour t",
    ylabel = "DADP",
    xticks = 1:T,
    title = "Default (one forecast) vs stochastic per-scenario DADP",
)
for k in 1:S
    lines!(
        ax1,
        1:T,
        inS.dadp[k];
        color = (scen_colors[k], 0.65),
        linewidth = 1.6,
        label = "scenario $k (p = $(inS.probabilities[k]))",
    )
end
lines!(
    ax1,
    1:T,
    inS.expected_dadp;
    color = :black,
    linestyle = :dash,
    linewidth = 2,
    label = "stochastic E[DADP] (derived)",
)
lines!(
    ax1,
    1:T,
    r_def.dadp[1, :];
    color = :black,
    linewidth = 3,
    label = "default (single forecast)",
)
scatter!(ax1, 1:T, r_def.dadp[1, :]; color = :black, markersize = 7)
ax2 = Axis(
    fig1[1, 2];
    xlabel = "hour t",
    ylabel = "λ − E[λ]",
    xticks = 1:T,
    title = "Deviation from E[DADP] (scenario spread)",
)
for k in 1:S
    lines!(ax2, 1:T, inS.dadp[k] .- inS.expected_dadp; color = scen_colors[k], linewidth = 1.6)
end
lines!(
    ax2,
    1:T,
    r_def.dadp[1, :] .- inS.expected_dadp;
    color = :black,
    linestyle = :dot,
    linewidth = 2,
    label = "default − E[λ]",
)
hlines!(ax2, 0; color = :gray, linewidth = 0.8)
axislegend(ax2; position = :rb, framevisible = false, labelsize = 9)
Legend(fig1[1, 3], ax1; framevisible = false, labelsize = 10)
saveboth("dadp_comparison", fig1)
println("saved dadp_comparison.{pdf,png}")

# Figure 2 — in-sample PV/demand scenario fan, regenerated via the SAME exported seeding
# seams run_stochastic itself uses (bit-identical replay of what each scenario saw).
scen_profiles = [
    generate_profiles(;
        seed = sub_seed(s_stoch.seed, Symbol(:stoch_insample_profiles_, k)),
        T = T,
    ) for k in 1:S
]
fig2 = Figure(size = (980, 400))
axpv = Axis(
    fig2[1, 1];
    xlabel = "hour t",
    ylabel = "PV availability (p.u.)",
    xticks = 1:T,
    title = "In-sample PV fan ($S seeded Markov draws)",
)
axdem = Axis(
    fig2[1, 2];
    xlabel = "hour t",
    ylabel = "baseline demand (p.u.)",
    xticks = 1:T,
    title = "In-sample demand fan",
)
for k in 1:S
    lab = "scenario $k (p = $(inS.probabilities[k]))"
    scatterlines!(axpv, 1:T, scen_profiles[k].pv; color = scen_colors[k], label = lab, markersize = 5)
    scatterlines!(axdem, 1:T, scen_profiles[k].demand; color = scen_colors[k], markersize = 5)
end
Legend(fig2[1, 3], axpv; framevisible = false, labelsize = 11)
saveboth("scenario_fan", fig2)
println("saved scenario_fan.{pdf,png}")

# Figure 3 — robustness: committed schedule re-scored on held-out draws; per-hour spread.
fig3 = Figure(size = (1000, 400))
gap_str = round(oos.welfare_gap; digits = 4)
ninf_str = count(oos.infeasible_h)
ax3 = Axis(
    fig3[1, 1];
    xlabel = "held-out draw h",
    ylabel = "realized welfare",
    xticks = 1:H_OOS,
    title = "Committed schedule vs $H_OOS unseen futures (gap = $gap_str, $ninf_str infeasible)",
)
scatter!(
    ax3,
    (1:H_OOS)[.!oos.infeasible_h],
    oos.welfare_h[.!oos.infeasible_h];
    color = :dodgerblue,
    markersize = 10,
    label = "held-out draw",
)
if any(oos.infeasible_h)
    scatter!(
        ax3,
        (1:H_OOS)[oos.infeasible_h],
        fill(oos.realized_welfare, count(oos.infeasible_h));
        color = :red,
        marker = :xtick,
        markersize = 12,
        label = "infeasible (skipped)",
    )
end
hlines!(
    ax3,
    inS.welfare;
    color = :crimson,
    linestyle = :dash,
    linewidth = 2,
    label = "in-sample expected welfare",
)
hlines!(
    ax3,
    oos.realized_welfare;
    color = :black,
    linewidth = 2,
    label = "realized mean (feasible draws)",
)
axislegend(ax3; position = :rb, framevisible = false, labelsize = 9)
ax4 = Axis(
    fig3[1, 2];
    xlabel = "hour t",
    ylabel = "max − min across scenarios",
    xticks = 1:T,
    title = "Per-hour scenario price spread",
)
barplot!(ax4, 1:T, spread; color = :seagreen)
saveboth("welfare_robustness", fig3)
println("saved welfare_robustness.{pdf,png}")

# Figure 4 — price envelope: the one-number default view vs the distribution view. The
# min–max band across the 5 scenario DADPs IS the "price risk" the extensive form hedges;
# the signed bars show where the single-forecast price departs from the hedged expectation
# (same disjoint-draws caveat as the header: this is a SHAPE comparison).
lo_t = [minimum(inS.dadp[k][t] for k in 1:S) for t in 1:T]
hi_t = [maximum(inS.dadp[k][t] for k in 1:S) for t in 1:T]
fig4 = Figure(size = (1000, 400))
ax5 = Axis(
    fig4[1, 1];
    xlabel = "hour t",
    ylabel = "DADP",
    xticks = 1:T,
    title = "Scenario price envelope (min–max over the $S DADPs)",
)
band!(ax5, 1:T, lo_t, hi_t; color = (:steelblue, 0.18), label = "scenario min–max envelope")
lines!(
    ax5,
    1:T,
    inS.expected_dadp;
    color = :black,
    linestyle = :dash,
    linewidth = 2,
    label = "stochastic E[DADP] (derived)",
)
lines!(
    ax5,
    1:T,
    r_def.dadp[1, :];
    color = :crimson,
    linewidth = 2.5,
    label = "default (single forecast)",
)
axislegend(ax5; position = :rt, framevisible = false, labelsize = 9)
ax6 = Axis(
    fig4[1, 2];
    xlabel = "hour t",
    ylabel = "default − E[DADP]",
    xticks = 1:T,
    title = "Single-forecast price minus hedged expectation",
)
barplot!(ax6, 1:T, r_def.dadp[1, :] .- inS.expected_dadp; color = :orange)
hlines!(ax6, [0.0]; color = :gray, linewidth = 0.8)
saveboth("price_envelope", fig4)
println("saved price_envelope.{pdf,png}")

# --- 5. MACHINE-READABLE ARTIFACTS (results-folder convention, cf. results/pv_boom) --------
# summary.csv   — scalar key/value table (welfares, gaps, exactness, timings).
# dadp_tidy.csv — tidy long-format DADP table (source × hour), diff-friendly.
# oos_draws.csv — per-held-out-draw realized welfare + infeasibility mask.
using DataFrames, CSV

summary_df = DataFrame(
    key = [
        "T",
        "seed",
        "default_welfare",
        "default_exact_maxgap",
        "default_solve_s",
        "stoch_S",
        "stoch_insample_welfare",
        "stoch_exact_maxgap_max",
        "stoch_expected_dadp_mean",
        "oos_realized_welfare",
        "oos_welfare_gap",
        "oos_n_infeasible",
        "oos_H",
        "stoch_solve_s",
        "dadp_spread_max",
    ],
    value = [
        T,
        SEED,
        r_def.welfare,
        r_def.exact_maxgap,
        t_def,
        S,
        inS.welfare,
        maximum(inS.socp_maxgap),
        mean(inS.expected_dadp),
        oos.realized_welfare,
        oos.welfare_gap,
        count(oos.infeasible_h),
        H_OOS,
        t_stoch,
        maximum(spread),
    ],
    note = [
        "horizon (hours)",
        "master seed (both runs)",
        "deterministic :centralized run (own disjoint profile draw)",
        "PF-04 certificate, default run",
        "wall time, default run",
        "in-sample scenario count",
        "probability-weighted extensive-form objective",
        "max over per-scenario PF-04 certificates (gated independently, D-06)",
        "mean of the derived E[DADP] summary (not a constraint-backed price, D-07)",
        "uniform mean over FEASIBLE held-out draws",
        "realized − in-sample (D-09)",
        "held-out draws infeasible vs committed schedule (WR-05)",
        "held-out draw count",
        "wall time, stochastic run (extensive form + 10 held-out re-solves)",
        "max over hours of (max−min scenario DADP)",
    ],
)
CSV.write(joinpath(OUT, "summary.csv"), summary_df)

dadp_tidy = DataFrame(
    source = String[],
    probability = Float64[],
    hour = Int[],
    dadp = Float64[],
)
for t in 1:T
    push!(dadp_tidy, ("default", NaN, t, r_def.dadp[1, t]))
end
for k in 1:S, t in 1:T
    push!(dadp_tidy, ("stoch_$k", inS.probabilities[k], t, inS.dadp[k][t]))
end
for t in 1:T
    push!(dadp_tidy, ("expected", NaN, t, inS.expected_dadp[t]))
end
CSV.write(joinpath(OUT, "dadp_tidy.csv"), dadp_tidy)

oos_draws = DataFrame(
    draw = collect(1:H_OOS),
    welfare = oos.welfare_h,
    infeasible = oos.infeasible_h,
)
CSV.write(joinpath(OUT, "oos_draws.csv"), oos_draws)
println("wrote summary.csv, dadp_tidy.csv, oos_draws.csv")

println()
println("All figures written to $OUT")
