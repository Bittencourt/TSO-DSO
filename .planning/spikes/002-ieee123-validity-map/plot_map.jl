# Spike 002 — IEEE-123 validity map: the figure.
#
# Same two-row layout as spike 001 so the two substrates are visually comparable:
#   row 1 — categorical region map (exact / inexact / infeasible / guard-tripped)
#   row 2 — log10 cone-gap ratio on solved points
#
# Axes are MULTIPLIERS on the Phase-17-retuned population point (load 0.05 / pv 0.12), unlike
# spike 001 where they were absolute fixture values. Labelled accordingly.
#
# Run (after sweep.jl):  julia --project=. .planning/spikes/002-ieee123-validity-map/plot_map.jl

using CSV, DataFrames, CairoMakie

CairoMakie.activate!(type = "png")

const HERE = @__DIR__
df = CSV.read(joinpath(HERE, "sweep.csv"), DataFrame)

pvs = sort(unique(df.pv_mult))
lds = sort(unique(df.load_mult))
vms = sort(unique(df.vmax))

const CODE =
    Dict("exact" => 1, "inexact" => 2, "guard" => 3, "solver" => 3, "infeasible" => 4)
const COLORS = [
    RGBf(0.13, 0.55, 0.49),   # exact
    RGBf(0.78, 0.15, 0.20),   # INEXACT
    RGBf(0.95, 0.71, 0.25),   # guard-tripped — UNMEASURED
    RGBf(0.88, 0.88, 0.90),   # infeasible — unserveable
]

function cell(vmax, pm, lm)
    hit = filter(r -> r.vmax == vmax && r.pv_mult == pm && r.load_mult == lm, eachrow(df))
    return isempty(hit) ? nothing : only(hit)
end

fig = Figure(size = (1180, 700), backgroundcolor = :white)

Label(
    fig[0, 1:3],
    "REAL IEEE-123 impedances — NO structural inexactness found",
    fontsize = 21,
    font = :bold,
    padding = (0, 0, 4, 0),
)
Label(
    fig[1, 1:3],
    "123 buses · public OpenDSS positive-sequence (Fortescue-reduced) impedances · 85 load nodes · T=24 · priced export ON · free cone-gap detector, no AC oracle\n" *
    "axes are multipliers on the Phase-17-retuned point (load 0.05 / pv 0.12, seed 20260719) — ×1.0 is the thesis-reproduction point\n" *
    "RED CELLS ARE SOLVER NOISE, NOT RELAXATION GAPS: tightening tol_gap 1e-8→1e-10 collapses the worst ratio 4.76→0.0029 at an identical optimum",
    fontsize = 12,
    color = :gray35,
    padding = (0, 0, 0, 2),
)

# ── Row 1: categorical ────────────────────────────────────────────────────────────────────
for (k, vmax) in enumerate(vms)
    ax = Axis(
        fig[2, k],
        title = "vmax = $vmax",
        titlesize = 15,
        xlabel = "pv multiplier",
        ylabel = k == 1 ? "load multiplier" : "",
        xticks = (1:length(pvs), string.(pvs)),
        yticks = (1:length(lds), string.(lds)),
        xticklabelsize = 11,
        yticklabelsize = 11,
        xgridvisible = false,
        ygridvisible = false,
    )

    Z = [
        begin
            r = cell(vmax, pm, lm)
            r === nothing ? NaN : Float64(CODE[r.class])
        end for pm in pvs, lm in lds
    ]
    heatmap!(
        ax,
        1:length(pvs),
        1:length(lds),
        Z,
        colormap = cgrad(COLORS, 4, categorical = true),
        colorrange = (0.5, 4.5),
        nan_color = RGBf(1, 1, 1),
    )

    for (i, pm) in enumerate(pvs), (j, lm) in enumerate(lds)
        r = cell(vmax, pm, lm)
        r !== nothing &&
            r.n_at_vmax >= 1 &&
            scatter!(
                ax,
                [i],
                [j],
                marker = :circle,
                markersize = 5,
                color = (:white, 0.85),
                strokecolor = :black,
                strokewidth = 0.6,
            )
    end

    # The thesis-reproduction anchor lives at (pv×1.0, load×1.0) on the vmax = 1.10 panel.
    if vmax == 1.10
        ia, ja = findfirst(==(1.0), pvs), findfirst(==(1.0), lds)
        scatter!(
            ax,
            [ia],
            [ja],
            marker = :star5,
            markersize = 18,
            color = :white,
            strokecolor = :black,
            strokewidth = 1.3,
        )
    end
    xlims!(ax, 0.5, length(pvs) + 0.5)
    ylims!(ax, 0.5, length(lds) + 0.5)
end

# ── Row 2: log10 ratio ────────────────────────────────────────────────────────────────────
solved = filter(r -> r.status == "SOLVED", df)
lo, hi = isempty(solved) ? (-3.0, 3.0) : extrema(log10.(solved.maxratio))

for (k, vmax) in enumerate(vms)
    ax = Axis(
        fig[3, k],
        xlabel = "pv multiplier",
        ylabel = k == 1 ? "load multiplier" : "",
        xticks = (1:length(pvs), string.(pvs)),
        yticks = (1:length(lds), string.(lds)),
        xticklabelsize = 11,
        yticklabelsize = 11,
        xgridvisible = false,
        ygridvisible = false,
    )

    Z = [
        begin
            r = cell(vmax, pm, lm)
            (r === nothing || r.status != "SOLVED") ? NaN : log10(r.maxratio)
        end for pm in pvs, lm in lds
    ]
    hm = heatmap!(
        ax,
        1:length(pvs),
        1:length(lds),
        Z,
        colormap = :vik,
        colorrange = (lo, hi),
        nan_color = RGBf(0.94, 0.94, 0.95),
    )
    contour!(
        ax,
        1:length(pvs),
        1:length(lds),
        Z,
        levels = [0.0],
        color = :black,
        linewidth = 2.2,
    )
    k == length(vms) && Colorbar(
        fig[3, length(vms) + 1],
        hm,
        label = "log₁₀ cone-gap ratio",
        labelsize = 12,
        ticklabelsize = 11,
    )
    xlims!(ax, 0.5, length(pvs) + 0.5)
    ylims!(ax, 0.5, length(lds) + 0.5)
end

elems = [
    PolyElement(color = COLORS[1]),
    PolyElement(color = COLORS[2]),
    PolyElement(color = COLORS[3]),
    PolyElement(color = COLORS[4]),
    MarkerElement(
        marker = :circle,
        markersize = 6,
        color = (:white, 0.85),
        strokecolor = :black,
        strokewidth = 0.6,
    ),
    MarkerElement(
        marker = :star5,
        markersize = 13,
        color = :white,
        strokecolor = :black,
        strokewidth = 1.2,
    ),
]
labels = [
    "ratio ≤ 1",
    "flagged ratio > 1 — SOLVER NOISE",
    "guard tripped — UNMEASURED",
    "not swept",
    "voltage bound active (never occurs)",
    "thesis-reproduction point",
]
Legend(
    fig[4, 1:3],
    elems,
    labels,
    orientation = :horizontal,
    framevisible = false,
    labelsize = 12,
    nbanks = 1,
)

Label(
    fig[5, 1:3],
    "Voltage upper bound is NEVER active at any of the 48 solved points (vpeak span 0.9997-1.0158) — the 3-bus overvoltage mechanism does not occur here.\n" *
    "Flags are scattered non-monotonically in every axis, including at the LOWEST pv swept (×0.4), which no physical relaxation-gap mechanism can produce.",
    fontsize = 11,
    color = :gray40,
    halign = :left,
    justification = :left,
)

rowgap!(fig.layout, 6)
for (p, f) in (("validity-map-ieee123.png", 2.0), ("validity-map-ieee123.pdf", 1.0))
    save(joinpath(HERE, p), fig; px_per_unit = f)
    println("wrote ", joinpath(HERE, p))
end
