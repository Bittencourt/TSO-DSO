# scripts/pv_boom_report.jl
#
# Self-contained HTML report generator for the PV-boom case study (scripts/
# pv_boom_case_study.jl). Reads the raw run data `data/pv_boom/results.jld2` (gitignored
# — run `scripts/pv_boom_case_study.jl` first if it is absent), builds three CairoMakie
# figures, embeds them as base64 PNG `data:image/png;base64,...` URIs (no external image
# files), and assembles ONE self-contained `results/pv_boom/report.html` a collaborator
# without Julia can open offline — zero network requests, no external CSS/JS/CDN.
#
#   julia --project=. scripts/pv_boom_report.jl
#
using DrWatson
@quickactivate "TSODSO"

using TSODSO
using CairoMakie
using Base64

results = DrWatson.wload(datadir("pv_boom", "results.jld2"))
sweep = results["sweep"]
admm_crosscheck = results["admm_crosscheck"]
nash_result = results["nash_result"]
ac_stress = results["ac_stress"]

ok_rows = [r for r in sweep if r.status == "ok"]
isempty(ok_rows) && error(
    "pv_boom_report: no successful sweep points in data/pv_boom/results.jld2 — nothing " *
    "to report. Re-run scripts/pv_boom_case_study.jl.",
)

# ── Pick the representative "most-stressed" bus: the one with the largest total-price
# spread across every successful pv_mult level (max over pv_mult/hour minus min). ────────
N_buses = size(first(ok_rows).dlmp, 1)
bus_range = zeros(N_buses)
for bus in 1:N_buses
    vals = Float64[]
    for r in ok_rows
        append!(vals, r.dlmp[bus, :])
    end
    bus_range[bus] = maximum(vals) - minimum(vals)
end
stressed_bus = argmax(bus_range)
println("Representative stressed bus (largest total-price spread across pv_mult) = ", stressed_bus)

T_full = size(first(ok_rows).dlmp, 2)
hours = 1:T_full

# ── Figure 1: price curves, one line per successful pv_mult, at the stressed bus ────────
fig1 = Figure(; size = (900, 500))
ax1 = Axis(
    fig1[1, 1];
    xlabel = "hour",
    ylabel = "total DADP (per-unit)",
    title = "Price reshaping at bus $stressed_bus across PV penetration (IEEE-13)",
)
palette1 = Makie.wong_colors()
for (idx, r) in enumerate(ok_rows)
    lines!(
        ax1,
        hours,
        r.dlmp[stressed_bus, :];
        label = "pv_mult=$(r.pv_mult)",
        color = palette1[mod1(idx, length(palette1))],
    )
end
axislegend(ax1; position = :rt)

# ── Figure 2: 4-way stacked decomposition (energy/loss/congestion/voltage) at the
# stressed bus, for the HIGHEST successful pv_mult. ──────────────────────────────────────
highest_row = ok_rows[argmax([r.pv_mult for r in ok_rows])]
decomp = highest_row.decomp
fig2 = Figure(; size = (900, 500))
ax2 = Axis(
    fig2[1, 1];
    xlabel = "hour",
    ylabel = "price component (per-unit)",
    title = "4-way DLMP decomposition at bus $stressed_bus, pv_mult=$(highest_row.pv_mult)",
)
energy_v = decomp.energy[stressed_bus, :]
loss_v = decomp.loss[stressed_bus, :]
congestion_v = decomp.congestion[stressed_bus, :]
voltage_v = decomp.voltage[stressed_bus, :]
stack1 = energy_v
stack2 = stack1 .+ loss_v
stack3 = stack2 .+ congestion_v
stack4 = stack3 .+ voltage_v
band!(ax2, hours, zeros(T_full), stack1; color = (:steelblue, 0.7), label = "energy")
band!(ax2, hours, stack1, stack2; color = (:orange, 0.7), label = "loss")
band!(ax2, hours, stack2, stack3; color = (:firebrick, 0.7), label = "congestion")
band!(ax2, hours, stack3, stack4; color = (:seagreen, 0.7), label = "voltage")
lines!(ax2, hours, decomp.total[stressed_bus, :]; color = :black, linestyle = :dash, label = "total (DADP)")
axislegend(ax2; position = :rt)

# ── Figure 3: ADMM convergence (reuses the generic TSODSO.plot_convergence — never
# reimplemented). ─────────────────────────────────────────────────────────────────────
fig3 = TSODSO.plot_convergence(admm_crosscheck.residuals)

# ── Embed each Figure as a base64 PNG data URI (no external image files). ───────────────
function figure_to_data_uri(fig)
    path = joinpath(mktempdir(), "fig.png")
    CairoMakie.save(path, fig)
    bytes = read(path)
    return "data:image/png;base64," * Base64.base64encode(bytes)
end

uri1 = figure_to_data_uri(fig1)
uri2 = figure_to_data_uri(fig2)
uri3 = figure_to_data_uri(fig3)

# ── Captions drawn from findings.txt's own text (never re-derived independently). ───────
findings_path = projectdir("results", "pv_boom", "findings.txt")
findings_text = isfile(findings_path) ? read(findings_path, String) : ""

function extract_section(text::AbstractString, header::AbstractString)
    idx = findfirst(header, text)
    idx === nothing && return "(findings.txt section '$header' not found — run " *
                              "scripts/pv_boom_case_study.jl to regenerate it.)"
    rest = text[first(idx):end]
    # Cut at the next blank-line-preceded section header (a line of dashes/equals or a
    # double newline), keeping the caption short.
    lines_ = split(rest, '\n')
    out = String[]
    for (i, l) in enumerate(lines_)
        i == 1 && continue   # skip the header line itself
        (isempty(strip(l)) || all(c -> c in "-=", strip(l))) && break
        push!(out, l)
    end
    return join(out, " ")
end

caption1 = "Price reshaping: " * extract_section(findings_text, "Part A — PV-penetration operational sweep")
caption2 = "The documented EXACT-04 exactness boundary: " * extract_section(findings_text, "Part A2 — the documented EXACT-04 finding, reproduced")
caption3 = "ADMM-vs-centralized cross-check: " * extract_section(findings_text, "ADMM cross-check @ pv_mult=1.0")

# ── Tables (plain HTML string interpolation — no templating library). ───────────────────
function sweep_table_html(rows)
    io = IOBuffer()
    println(io, "<table>")
    println(io, "<tr><th>pv_mult</th><th>status</th><th>welfare</th><th>exact_maxgap</th></tr>")
    for r in rows
        if r.status == "ok"
            println(
                io,
                "<tr><td>$(r.pv_mult)</td><td>$(r.status)</td><td>$(round(r.welfare; digits=4))</td>" *
                "<td>$(round(r.exact_maxgap; sigdigits=4))</td></tr>",
            )
        else
            println(io, "<tr><td>$(r.pv_mult)</td><td>$(r.status)</td><td colspan=2>$(first(r.reason, 80))</td></tr>")
        end
    end
    println(io, "</table>")
    return String(take!(io))
end

function nash_table_html(nash_result)
    io = IOBuffer()
    println(io, "<table>")
    println(io, "<tr><th>distributor</th><th>x_inv</th><th>final z (mean)</th></tr>")
    labels = ["baseline", "boom"]
    for i in 1:length(nash_result.x_inv)
        println(
            io,
            "<tr><td>$(labels[min(i, length(labels))])</td><td>$(round(nash_result.x_inv[i]; sigdigits=4))</td>" *
            "<td>$(round(sum(nash_result.z[i, :]) / size(nash_result.z, 2); sigdigits=4))</td></tr>",
        )
    end
    println(io, "</table>")
    return String(take!(io))
end

sweep_table = sweep_table_html(sweep)
nash_table = nash_table_html(nash_result)

# ── Assemble ONE self-contained HTML string — inline <style>, no external CSS/JS/CDN. ───
html_string = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>PV-Boom Case Study — TSO-DSO Integration Optimization Framework</title>
<style>
  body { font-family: Georgia, 'Times New Roman', serif; max-width: 960px; margin: 2rem auto; padding: 0 1rem; color: #222; line-height: 1.5; }
  h1 { border-bottom: 3px solid #2c5f8a; padding-bottom: 0.3rem; }
  h2 { color: #2c5f8a; margin-top: 2.5rem; }
  figure { margin: 1.5rem 0; text-align: center; }
  figcaption { font-size: 0.92rem; color: #444; margin-top: 0.5rem; text-align: left; }
  img { max-width: 100%; border: 1px solid #ccc; }
  table { border-collapse: collapse; width: 100%; margin: 1rem 0; }
  th, td { border: 1px solid #999; padding: 0.4rem 0.6rem; text-align: right; font-size: 0.9rem; }
  th { background: #eef3f7; }
  td:first-child, th:first-child { text-align: left; }
  .finding { background: #fff8e1; border-left: 4px solid #e0a800; padding: 0.6rem 1rem; margin: 1rem 0; }
</style>
</head>
<body>
<h1>PV-Boom Case Study</h1>
<p>A showcase of the TSO-DSO Integration Optimization Framework's operational and
planning layers across rising PV penetration on the modified IEEE-13 feeder. Generated by
<code>scripts/pv_boom_case_study.jl</code> + <code>scripts/pv_boom_report.jl</code>. Every
number below traces to a real solve — no placeholders.</p>

<h2>1. Price reshaping under rising PV penetration</h2>
<figure>
  <img src="$uri1" alt="Price curves across PV penetration">
  <figcaption>$caption1</figcaption>
</figure>

<h2>2. Four-way DLMP decomposition (highest PV penetration)</h2>
<figure>
  <img src="$uri2" alt="4-way DLMP decomposition">
  <figcaption>$caption2</figcaption>
</figure>

<h2>3. Centralized-vs-ADMM cross-check</h2>
<figure>
  <img src="$uri3" alt="ADMM convergence">
  <figcaption>$caption3</figcaption>
</figure>

<h2>4. PV-penetration sweep summary</h2>
$sweep_table

<h2>5. Planning-layer Stackelberg-Nash investment response</h2>
<p>Converged: <b>$(nash_result.converged)</b> (sweeps=$(nash_result.sweeps))</p>
$nash_table

<div class="finding">
<b>The documented EXACT-04 finding, reproduced:</b> on the certified 3-bus high-PV stress
fixture, the SOC branch-flow relaxation is genuinely INEXACT at
$(ac_stress.n_inexact_hours) hour(s) (obj_gap = $(round(ac_stress.obj_gap; sigdigits=4)),
socp_maxgap = $(round(ac_stress.socp_maxgap; sigdigits=4))) — never re-derived or
re-tuned from the certified fixture.
</div>

<p style="margin-top:3rem;color:#777;font-size:0.85rem;">Generated offline from
<code>data/pv_boom/results.jld2</code> — zero network requests, no external CSS/JS/CDN.</p>
</body>
</html>
"""

OUT = mkpath(projectdir("results", "pv_boom"))
write(joinpath(OUT, "report.html"), html_string)
println("wrote ", joinpath(OUT, "report.html"))
