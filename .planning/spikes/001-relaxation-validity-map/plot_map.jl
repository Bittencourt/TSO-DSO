# Spike 001 — relaxation validity map: the figure.
#
# Reads sweep.csv and renders the parameter-space map. Two rows:
#   row 1 — categorical region map (exact / inexact / infeasible / guard-tripped)
#   row 2 — log10 of the cone-gap ratio on solved points, showing that the transition is a CLIFF
#           (there are no points between ratio 0.024 and 8.45) rather than a gradient
#
# Run (after sweep.jl):  julia --project=. .planning/spikes/001-relaxation-validity-map/plot_map.jl

using CSV, DataFrames, CairoMakie

CairoMakie.activate!(type = "png")

const HERE = @__DIR__
df = CSV.read(joinpath(HERE, "sweep.csv"), DataFrame)

pvs = sort(unique(df.pv_scale))
lds = sort(unique(df.load_scale))
vms = sort(unique(df.vmax))

# 1 = exact, 2 = inexact, 3 = guard-tripped (UNMEASURED), 4 = infeasible (unserveable)
const CODE =
    Dict("exact" => 1, "inexact" => 2, "guard" => 3, "solver" => 3, "infeasible" => 4)
const COLORS = [
    RGBf(0.13, 0.55, 0.49),   # exact — teal
    RGBf(0.78, 0.15, 0.20),   # inexact — crimson
    RGBf(0.95, 0.71, 0.25),   # guard-tripped — amber (NOT a verdict: unmeasured)
    RGBf(0.88, 0.88, 0.90),   # infeasible — light grey (legitimate white space)
]

cell(vmax, ps, ld) =
    only(filter(r -> r.vmax == vmax && r.pv_scale == ps && r.load_scale == ld, eachrow(df)))

fig = Figure(size = (1180, 720), backgroundcolor = :white)

Label(
    fig[0, 1:3],
    "Where the SOC branch-flow relaxation is EXACT",
    fontsize = 21,
    font = :bold,
    padding = (0, 0, 4, 0),
)
Label(
    fig[1, 1:3],
    "3-bus high-PV fixture (r=x=0.05, vmin=0.95) · T=24 · priced export ON · free cone-gap detector, no AC oracle",
    fontsize = 12.5,
    color = :gray35,
    padding = (0, 0, 0, 2),
)

# ── Row 1: categorical region map ─────────────────────────────────────────────────────────
for (k, vmax) in enumerate(vms)
    ax = Axis(
        fig[2, k],
        title = "vmax = $vmax",
        titlesize = 15,
        xlabel = "pv_scale",
        ylabel = k == 1 ? "load_scale" : "",
        xticks = (1:length(pvs), string.(pvs)),
        yticks = (1:length(lds), string.(lds)),
        xticklabelsize = 11,
        yticklabelsize = 11,
        xgridvisible = false,
        ygridvisible = false,
    )

    Z = [CODE[cell(vmax, ps, ld).class] for ps in pvs, ld in lds]
    heatmap!(
        ax,
        1:length(pvs),
        1:length(lds),
        Z,
        colormap = cgrad(COLORS, 4, categorical = true),
        colorrange = (0.5, 4.5),
    )

    # Mark the voltage-bound binding set — the free interpretive diagnostic. A dot means the
    # upper voltage bound is ACTIVE at >=1 (bus,hour) in that solve.
    for (i, ps) in enumerate(pvs), (j, ld) in enumerate(lds)
        r = cell(vmax, ps, ld)
        r.n_at_vmax >= 1 && scatter!(
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

    # The two EXACT-04 control points, only on the vmax = 1.05 panel where they were measured.
    if vmax == 1.05
        ie, je = findfirst(==(0.5), pvs), findfirst(==(0.20), lds)
        ii, ji = findfirst(==(1.2), pvs), findfirst(==(0.20), lds)
        scatter!(
            ax,
            [ie, ii],
            [je, ji],
            marker = :star5,
            markersize = 17,
            color = :white,
            strokecolor = :black,
            strokewidth = 1.3,
        )
    end
    xlims!(ax, 0.5, length(pvs) + 0.5)
    ylims!(ax, 0.5, length(lds) + 0.5)
end

# ── Row 2: the cliff ──────────────────────────────────────────────────────────────────────
solved = filter(r -> r.status == "SOLVED", df)
lo, hi = extrema(log10.(solved.maxratio))

for (k, vmax) in enumerate(vms)
    ax = Axis(
        fig[3, k],
        xlabel = "pv_scale",
        ylabel = k == 1 ? "load_scale" : "",
        xticks = (1:length(pvs), string.(pvs)),
        yticks = (1:length(lds), string.(lds)),
        xticklabelsize = 11,
        yticklabelsize = 11,
        xgridvisible = false,
        ygridvisible = false,
    )

    Z = [
        begin
            r = cell(vmax, ps, ld)
            r.status == "SOLVED" ? log10(r.maxratio) : NaN
        end for ps in pvs, ld in lds
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
    # The classification threshold sits at ratio = 1, i.e. log10 = 0.
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

# ── Legend ────────────────────────────────────────────────────────────────────────────────
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
    "exact (ratio ≤ 1)",
    "INEXACT (ratio > 1)",
    "guard tripped — UNMEASURED",
    "infeasible — unserveable",
    "voltage bound active",
    "EXACT-04 control point",
]
Legend(
    fig[4, 1:3],
    elems,
    labels,
    orientation = :horizontal,
    framevisible = false,
    labelsize = 12,
    nbanks = 1,
    padding = (0, 0, 0, 0),
)

Label(
    fig[5, 1:3],
    "Row 2 black line = classification threshold (ratio = 1). Solved points are bimodal: max exact ratio 0.024, min inexact ratio 8.45 —\n" *
    "a ~350× empty band, so the boundary's position does not depend on where the threshold is placed.",
    fontsize = 11,
    color = :gray40,
    halign = :left,
    justification = :left,
)

rowgap!(fig.layout, 6)
for (p, f) in (("validity-map.png", 2.0), ("validity-map.pdf", 1.0))
    save(joinpath(HERE, p), fig; px_per_unit = f)
    println("wrote ", joinpath(HERE, p))
end
