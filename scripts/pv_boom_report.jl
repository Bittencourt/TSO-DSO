# scripts/pv_boom_report.jl
#
# Self-contained HTML report generator for the PV-boom case study (scripts/
# pv_boom_case_study.jl). Reads the raw run data `data/pv_boom/results.jld2` (gitignored
# — run `scripts/pv_boom_case_study.jl` first if it is absent), builds three CairoMakie
# figures, embeds them as base64 `data:image/png;base64,...` URIs (no external image
# files), and assembles ONE self-contained `results/pv_boom/report.html`: a rich,
# educational, guided walkthrough of the two-layer TSO-DSO framework, its equations
# (native `<math>` MathML, no CDN), the PV-boom experiment design, and the results — a
# power-systems reader with zero knowledge of this codebase can read it start to finish.
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

# ═════════════════════════════════════════════════════════════════════════════════════
# NEW EDUCATIONAL CONTENT (quick task 260807-7nz) — four narrative section bodies.
# Native <math> MathML only (no KaTeX/MathJax/CDN); every equation and parameter value
# below is transcribed VERBATIM from the source files/findings.txt cited inline — never
# invented, never re-derived. Not yet wired into `html_string` (Task 2 finishes
# `section5_repro_html`, rewrites the results-interpretation content, and assembles the
# final template).
# ═════════════════════════════════════════════════════════════════════════════════════

section1_framing_html = """
<h2 id="section1">1. Framing: what this report is about</h2>
<p>
This report showcases the <strong>TSO-DSO Integration Optimization Framework</strong>, a
Julia/JuMP research bench implementing the two-layer transactive-energy framework from
J.P. Palacios' PhD thesis (UNSJ/CONICET, 2022) and the associated PSR N1-N2 expansion note.
The framework has two layers:
</p>
<ul>
<li><strong>Operational layer</strong> — a single-level convex social-welfare maximization
over a 24-hour day-ahead horizon on a convex branch-flow (DistFlow/SOCP) distribution
network, solved centrally and (independently) by hand-rolled ADMM. The day-ahead dynamic
price (DADP/DLMP) emerges as the <em>dual</em> of the nodal active-power balance — prices
are never postulated, always recovered from duals.</li>
<li><strong>Planning layer</strong> — a Stackelberg-Nash TSO-DSO investment game:
distributor-leaders choose flexibility investment and import profiles against a
transmission-reinforcement follower, solved by hand-rolled Benders decomposition; multiple
distributors reach a Nash equilibrium via Gauss-Seidel diagonalization over a shared
transmission corridor.</li>
</ul>
<p>
The <strong>PV-boom case study</strong> (<code>scripts/pv_boom_case_study.jl</code>)
exercises both layers as PV penetration rises on the modified IEEE-13 feeder, asking three
questions:
</p>
<ol>
<li>How do distribution prices <em>reshape</em> as PV penetration rises at a stressed bus?</li>
<li>Does the SOCP relaxation of the branch-flow model stay <em>exact</em> as PV rises, or
does it break down under high reverse flow?</li>
<li>How does a Stackelberg-Nash investment game respond when two distributors face very
different PV levels?</li>
</ol>
<p>
Every number in this report traces to a real solve of the framework's code — nothing here
is illustrative or hand-drawn.
</p>
"""

section2_model_html = """
<h2 id="section2">2. The operational model, equation by equation</h2>
<p>The operational layer solves a single convex quadratic program: maximize the sum of every
prosumer's utility, minus the cost of power imported from the transmission grid, subject to
the distribution network's physical laws. Below is every equation this case study actually
solves, in the order a reader needs them, each tagged with its exact thesis equation number.</p>

<h3>2.1 The GLB-CVX welfare objective</h3>
<div class="eq-block">
<math display="block"><mrow>
  <munder><mo movablelimits="true">max</mo><mi>x</mi></munder>
  <munder><mo>&#x2211;</mo><mi>j</mi></munder>
  <msub><mi>U</mi><mi>j</mi></msub><mo>(</mo><mo>&#x22EF;</mo><mo>)</mo>
  <mo>&#x2212;</mo>
  <munder><mo>&#x2211;</mo><mi>t</mi></munder>
  <msub><mi>&#955;</mi><mn>0</mn></msub><mo>[</mo><mi>t</mi><mo>]</mo>
  <mo>&#x22C5;</mo>
  <msub><mi>p</mi><mtext>import</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo>
</mrow></math>
<span class="eqref">(eq. 3.38)</span>
</div>
<p>Implemented in <code>src/models/welfare_solve.jl</code>. The frontier
<code>p_import[t]</code> is the power bought (or, when <code>allow_export=true</code> — used
throughout this case study — sold) at the transmission root, priced at the wholesale/MEM
price λ₀[t]. Making the frontier free-sign rather than import-only is the
<strong>SOC-exactness enabler</strong> (finding PF-04): it makes the objective strictly
decreasing in the branch loss current <code>l</code>, which is what keeps the SOC relaxation
cone tight (exact) instead of slack in the over-voltage / reverse-flow regime a PV boom
produces.</p>

<h3>2.2 Prosumer device utilities</h3>
<p>Four convex device types roll up into each aggregator's utility term U_j above. Every one
of them has its additive thesis constant <code>c</code> deliberately dropped (see the callout
box below) — only the <em>curvature</em> and <em>slope</em> of each utility matter for the
optimum and its duals.</p>

<p><strong>Interruptible (curtailable) load</strong> — <code>src/devices/Interruptible.jl</code>:</p>
<div class="eq-block">
<math display="block"><mrow>
  <mi>U</mi><mo>(</mo><mi>p</mi><mo>)</mo><mo>=</mo>
  <munder><mo>&#x2211;</mo><mi>t</mi></munder>
  <mo>(</mo><mi>a</mi><mo>&#x22C5;</mo><mi>p</mi><mo>[</mo><mi>t</mi><mo>]</mo>
  <mo>&#x2212;</mo><mfrac><mi>b</mi><mn>2</mn></mfrac>
  <mo>&#x22C5;</mo><msup><mrow><mi>p</mi><mo>[</mo><mi>t</mi><mo>]</mo></mrow><mn>2</mn></msup>
  <mo>)</mo>
</mrow></math>
<span class="eqref">(eq. 3.10)</span>
</div>

<p><strong>Thermostatic (A/C) load</strong> — <code>src/devices/Thermostatic.jl</code> — a
comfort utility over an indoor-temperature state that evolves by an RC/ETP thermal
recursion:</p>
<div class="eq-block">
<math display="block"><mrow>
  <msub><mi>T</mi><mtext>in</mtext></msub><mo>[</mo><mi>t</mi><mo>+</mo><mn>1</mn><mo>]</mo>
  <mo>=</mo>
  <msub><mi>T</mi><mtext>in</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo>
  <mo>+</mo><mi>&#945;</mi><mo>&#x22C5;</mo>
  <mo>(</mo><msub><mi>T</mi><mtext>out</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo><mo>&#x2212;</mo><msub><mi>T</mi><mtext>in</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo><mo>)</mo>
  <mo>&#x2212;</mo><mi>&#946;</mi><mo>&#x22C5;</mo><mi>p</mi><mo>[</mo><mi>t</mi><mo>]</mo>
</mrow></math>
<span class="eqref">(eq. 3.2)</span>
</div>
<div class="eq-block">
<math display="block"><mrow>
  <msub><mi>T</mi><mtext>min</mtext></msub><mo>&#x2264;</mo>
  <msub><mi>T</mi><mtext>in</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo>
  <mo>&#x2264;</mo><msub><mi>T</mi><mtext>max</mtext></msub>
</mrow></math>
<span class="eqref">(eq. 3.3)</span>
</div>
<div class="eq-block">
<math display="block"><mrow>
  <mi>U</mi><mo>(</mo><msub><mi>T</mi><mtext>in</mtext></msub><mo>)</mo><mo>=</mo>
  <mo>&#x2212;</mo><mfrac><mi>b</mi><mn>2</mn></mfrac>
  <munder><mo>&#x2211;</mo><mi>t</mi></munder>
  <msup><mrow><mo>(</mo><msub><mi>T</mi><mtext>in</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo><mo>&#x2212;</mo><msub><mi>T</mi><mtext>min</mtext></msub><mo>)</mo></mrow><mn>2</mn></msup>
</mrow></math>
<span class="eqref">(eq. 3.11)</span>
</div>

<p><strong>Deferrable (shiftable) load</strong> — <code>src/devices/Deferrable.jl</code> — a
task (e.g. a washer or EV charge) whose total energy over a fixed window is softly targeted:</p>
<div class="eq-block">
<math display="block"><mrow>
  <msub><mi>E</mi><mtext>min</mtext></msub><mo>&#x2264;</mo>
  <munder><mo>&#x2211;</mo><mrow><mi>t</mi><mo>&#x2208;</mo><mtext>window</mtext></mrow></munder>
  <mi>p</mi><mo>[</mo><mi>t</mi><mo>]</mo><mo>&#x2264;</mo><mi>E</mi>
</mrow></math>
<span class="eqref">(eq. 3.4)</span>
</div>
<div class="eq-block">
<math display="block"><mrow>
  <mn>0</mn><mo>&#x2264;</mo><mi>p</mi><mo>[</mo><mi>t</mi><mo>]</mo><mo>&#x2264;</mo><msub><mi>P</mi><mtext>max</mtext></msub>
  <mtext>&#x2003;(t &#x2208; window),&#x2003;</mtext>
  <mi>p</mi><mo>[</mo><mi>t</mi><mo>]</mo><mo>=</mo><mn>0</mn><mtext>&#x2003;(otherwise)</mtext>
</mrow></math>
<span class="eqref">(eq. 3.5)</span>
</div>
<div class="eq-block">
<math display="block"><mrow>
  <mi>U</mi><mo>(</mo><mi>p</mi><mo>)</mo><mo>=</mo>
  <mo>&#x2212;</mo><mfrac><mi>b</mi><mn>2</mn></mfrac>
  <msup><mrow><mo>(</mo>
  <munder><mo>&#x2211;</mo><mrow><mi>t</mi><mo>&#x2208;</mo><mtext>window</mtext></mrow></munder>
  <mi>p</mi><mo>[</mo><mi>t</mi><mo>]</mo><mo>&#x2212;</mo><mi>E</mi>
  <mo>)</mo></mrow><mn>2</mn></msup>
</mrow></math>
<span class="eqref">(eq. 3.12)</span>
</div>

<p><strong>PV + battery (BESS)</strong> — <code>src/devices/PVBattery.jl</code> — a
co-located PV generator and battery with continuous state-of-charge dynamics:</p>
<div class="eq-block">
<math display="block"><mrow>
  <mtext>soc</mtext><mo>[</mo><mi>t</mi><mo>+</mo><mn>1</mn><mo>]</mo><mo>=</mo>
  <mtext>soc</mtext><mo>[</mo><mi>t</mi><mo>]</mo><mo>+</mo>
  <mo>(</mo><mi>&#951;</mi><mo>&#x22C5;</mo><msub><mi>p</mi><mtext>ch</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo>
  <mo>&#x2212;</mo><msub><mi>p</mi><mtext>dch</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo><mo>/</mo><mi>&#951;</mi>
  <mo>)</mo><mo>&#x22C5;</mo><mi>&#916;</mi><mi>t</mi>
</mrow></math>
<span class="eqref">(eq. 3.6)</span>
</div>
<div class="eq-block">
<math display="block"><mrow>
  <mn>0</mn><mo>&#x2264;</mo><msub><mi>p</mi><mtext>ch</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo>
  <mo>&#x2264;</mo><msub><mi>p</mi><mtext>v_used</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo>
  <mo>&#x2264;</mo><msub><mi>P</mi><mtext>pv</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo>
</mrow></math>
<span class="eqref">(eq. 3.7)</span>
</div>
<div class="eq-block">
<math display="block"><mrow>
  <mn>0</mn><mo>&#x2264;</mo><msub><mi>p</mi><mtext>ch</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo>
  <mo>,</mo><msub><mi>p</mi><mtext>dch</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo>
  <mo>&#x2264;</mo><msub><mi>P</mi><mtext>max</mtext></msub>
</mrow></math>
<span class="eqref">(eq. 3.8)</span>
</div>
<div class="eq-block">
<math display="block"><mrow>
  <msub><mi>E</mi><mtext>min</mtext></msub><mo>&#x2264;</mo><mtext>soc</mtext><mo>[</mo><mi>t</mi><mo>]</mo><mo>&#x2264;</mo><msub><mi>E</mi><mtext>max</mtext></msub>
  <mo>;</mo><mspace width="0.5em"></mspace>
  <mtext>soc</mtext><mo>[</mo><mn>1</mn><mo>]</mo><mo>=</mo><msub><mtext>soc</mtext><mn>0</mn></msub>
</mrow></math>
<span class="eqref">(eq. 3.9)</span>
</div>
<div class="eq-block">
<math display="block"><mrow>
  <mtext>utility</mtext><mo>=</mo>
  <munder><mo>&#x2211;</mo><mi>t</mi></munder>
  <mo>(</mo>
  <msub><mi>a</mi><mtext>ch</mtext></msub><mo>&#x22C5;</mo><msub><mi>p</mi><mtext>ch</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo>
  <mo>&#x2212;</mo><mfrac><msub><mi>b</mi><mtext>ch</mtext></msub><mn>2</mn></mfrac>
  <msup><mrow><msub><mi>p</mi><mtext>ch</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo></mrow><mn>2</mn></msup>
  <mo>&#x2212;</mo><msub><mi>a</mi><mtext>dch</mtext></msub><mo>&#x22C5;</mo><msub><mi>p</mi><mtext>dch</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo>
  <mo>&#x2212;</mo><mfrac><msub><mi>b</mi><mtext>dch</mtext></msub><mn>2</mn></mfrac>
  <msup><mrow><msub><mi>p</mi><mtext>dch</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo></mrow><mn>2</mn></msup>
  <mo>)</mo>
</mrow></math>
<math display="block"><mrow>
  <msub><mi>a</mi><mtext>ch</mtext></msub><mo>=</mo><msub><mi>a</mi><mtext>dch</mtext></msub><mo>=</mo><msub><mi>&#955;</mi><mtext>med</mtext></msub>
  <mo>,</mo><mspace width="0.5em"></mspace>
  <msub><mi>b</mi><mtext>ch</mtext></msub><mo>=</mo>
  <mfrac><mrow><mo>(</mo><msub><mi>&#955;</mi><mtext>med</mtext></msub><mo>&#x2212;</mo><msub><mi>&#955;</mi><mtext>min</mtext></msub><mo>)</mo></mrow><msub><mi>P</mi><mtext>max</mtext></msub></mfrac>
  <mo>,</mo><mspace width="0.5em"></mspace>
  <msub><mi>b</mi><mtext>dch</mtext></msub><mo>=</mo>
  <mfrac><mrow><mo>(</mo><msub><mi>&#955;</mi><mtext>max</mtext></msub><mo>&#x2212;</mo><msub><mi>&#955;</mi><mtext>med</mtext></msub><mo>)</mo></mrow><msub><mi>P</mi><mtext>max</mtext></msub></mfrac>
</mrow></math>
<span class="eqref">(eqs. 3.15-3.20)</span>
</div>
<p>The App. C no-binary argument: because the price triple is <em>strictly</em> ordered
λ_min &lt; λ_med &lt; λ_max, the marginal charge benefit never exceeds the marginal discharge
cost, so simultaneous charge and discharge is strictly dominated at the optimum — the model
needs <strong>no binary variable</strong> to enforce <code>p_ch[t]·p_dch[t] = 0</code>; it is
verified numerically after every solve instead.</p>

<div class="finding">
<strong>Educational caveat — every welfare LEVEL below is not economically meaningful on its
own.</strong> All four device utilities above have their additive thesis constant
<code>c</code> DELIBERATELY DROPPED (every device docstring in this codebase states this
explicitly as "RESEARCH A5"). Dropping an additive constant does not change the optimum, the
prices (duals), or any DELTA between scenarios — but it does mean the reported welfare LEVEL
is only approximately "(energy import bill) + (residual discomfort)", a large negative number
with no independent economic meaning. This is exactly why every welfare figure reported in
Section 4 below (e.g. <code>welfare ≈ -4830</code>) looks like a large negative number: only
the <em>differences between scenarios</em> and the <em>duals (prices)</em> carry meaning,
never the level in isolation.
</div>

<h3>2.3 The branch-flow network and its SOC relaxation</h3>
<p>The distribution network is a convex relaxation of the Baran-Wu / DistFlow branch-flow
model (<code>src/powerflow/ConvexBranchFlow.jl</code>). The true nonconvex power-flow
equality <code>l·v = P²+Q²</code> is relaxed to an inequality, written as a rotated
second-order cone:</p>
<div class="eq-block">
<math display="block"><mrow>
  <mi>l</mi><mo>&#x22C5;</mo><mi>v</mi><mo>&#x2265;</mo>
  <msup><mi>P</mi><mn>2</mn></msup><mo>+</mo><msup><mi>Q</mi><mn>2</mn></msup>
</mrow></math>
<span class="eqref">(eq. 3.39)</span>
</div>
<p>On its own this relaxation can be loose. The <strong>LinDistFlow exactness copy</strong>
— an auxiliary squared-voltage variable v̂ propagated by its own, slightly different
voltage-drop recursion, both bounded by the same voltage limits — is what drives the cone to
hold with EQUALITY (exact) on a radial feeder:</p>
<div class="eq-block">
<math display="block"><mrow>
  <mover><mi>v</mi><mo>^</mo></mover><mo>[</mo><mi>j</mi><mo>]</mo><mo>=</mo>
  <mover><mi>v</mi><mo>^</mo></mover><mo>[</mo><mi>i</mi><mo>]</mo><mo>&#x2212;</mo>
  <mn>2</mn><mo>{</mo><mi>r</mi><mo>(</mo><mi>P</mi><mo>+</mo><mi>r</mi><mi>l</mi><mo>)</mo>
  <mo>+</mo><mi>x</mi><mo>(</mo><mi>Q</mi><mo>+</mo><mi>x</mi><mi>l</mi><mo>)</mo><mo>}</mo>
</mrow></math>
<span class="eqref">(eq. 3.43)</span>
</div>
<div class="eq-block">
<math display="block"><mrow>
  <msubsup><mi>V</mi><mtext>min</mtext><mn>2</mn></msubsup><mo>&#x2264;</mo><mi>v</mi><mo>,</mo>
  <mover><mi>v</mi><mo>^</mo></mover><mo>&#x2264;</mo>
  <msubsup><mi>V</mi><mtext>max</mtext><mn>2</mn></msubsup>
</mrow></math>
<span class="eqref">(eq. 3.45)</span>
</div>
<p>What "exact" means in plain language: when the cone <code>l·v ≥ P²+Q²</code> holds with
EQUALITY at the optimum, the relaxed solution corresponds to a physically-achievable
branch-flow operating point. When it holds as a STRICT inequality, the relaxed solution is a
fictitious, physically-meaningless operating point — any prices (duals) recovered from it
would be economically meaningless, which is exactly why this framework REFUSES to price an
ungated, inexact SOCP solve (see <code>src/pricing/dlmp.jl</code>'s PF-04 gate).</p>

<h3>2.4 The day-ahead dynamic price (DADP/DLMP) and its 4-way decomposition</h3>
<p>The distribution price at every bus and hour is not postulated — it is the dual of the
nodal active-power balance constraint:</p>
<div class="eq-block">
<math display="block"><mrow>
  <msub><mi>&#955;</mi><mi>j</mi></msub><mo>[</mo><mi>t</mi><mo>]</mo><mo>=</mo>
  <mtext>dual</mtext><mo>(</mo><mtext>balance_p</mtext><mo>[</mo><mi>j</mi><mo>,</mo><mi>t</mi><mo>]</mo><mo>=</mo><mn>0</mn><mo>)</mo>
</mrow></math>
<span class="eqref">(eq. 3.31)</span>
</div>
<p><code>src/pricing/dlmp.jl</code>'s <code>decompose_dlmp</code> splits this single nodal
price into four INDEPENDENT components — energy, loss, congestion, voltage — each
reconstructed from its OWN distinct dual (never a leftover/residual split), following the
per-branch increment</p>
<div class="eq-block">
<math display="block"><mrow>
  <msub><mi>&#955;</mi><mi>j</mi></msub><mo>&#x2212;</mo><msub><mi>&#955;</mi><mi>i</mi></msub><mo>=</mo>
  <mo>&#x2212;</mo><mo>(</mo>
  <msub><mtext>cone_dual</mtext><mn>3</mn></msub><mo>+</mo>
  <mn>2</mn><mi>r</mi><mo>(</mo><mi>&#946;</mi><mo>+</mo><mi>&#947;</mi><mo>)</mo><mo>+</mo>
  <msub><mtext>smax_dual</mtext><mn>2</mn></msub>
  <mo>)</mo>
</mrow></math>
<span class="eqref">(derivation, dlmp.jl header)</span>
</div>
<p>summed along each node's unique radial root→node path. A hard assertion checks that the
four terms sum back to the total DADP at every bus/hour — a broken decomposition would show
up as a visible reconstruction gap, not silently pass.</p>

<h3>2.5 ADMM: the distributed cross-check</h3>
<p>The same welfare problem can also be solved in a fully distributed fashion by alternating
between a per-aggregator subproblem (AGR-OPT) and a whole-network subproblem (DSO-OPT):</p>
<div class="eq-block">
<math display="block"><mrow>
  <munder><mo movablelimits="true">max</mo><mtext>devices</mtext></munder>
  <msub><mi>U</mi><mtext>ag,j</mtext></msub>
  <mo>&#x2212;</mo><munder><mo>&#x2211;</mo><mi>t</mi></munder>
  <msub><mi>&#955;</mi><mi>j</mi></msub><mo>[</mo><mi>t</mi><mo>]</mo><mo>&#x22C5;</mo><msub><mi>p</mi><mtext>ag,j</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo>
  <mo>&#x2212;</mo><mfrac><mi>&#961;</mi><mn>2</mn></mfrac>
  <munder><mo>&#x2211;</mo><mi>t</mi></munder>
  <msup><mrow><mo>(</mo><msub><mi>c</mi><mi>j</mi></msub><mo>[</mo><mi>t</mi><mo>]</mo><mo>+</mo><msub><mi>p</mi><mtext>ag,j</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo><mo>)</mo></mrow><mn>2</mn></msup>
</mrow></math>
<span class="eqref">(eq. 3.46, AGR-OPT)</span>
</div>
<div class="eq-block">
<math display="block"><mrow>
  <munder><mo movablelimits="true">min</mo><mtext>P,Q,v,v&#770;,l,imports</mtext></munder>
  <munder><mo>&#x2211;</mo><mi>t</mi></munder>
  <msub><mi>&#955;</mi><mn>0</mn></msub><mo>[</mo><mi>t</mi><mo>]</mo><mo>&#x22C5;</mo><msub><mi>p</mi><mtext>import</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo>
  <mo>&#x2212;</mo>
  <munder><mo>&#x2211;</mo><mi>j</mi></munder><munder><mo>&#x2211;</mo><mi>t</mi></munder>
  <msub><mi>&#955;</mi><mi>j</mi></msub><mo>[</mo><mi>t</mi><mo>]</mo><mo>&#x22C5;</mo><msub><mi>p</mi><mtext>ag_dso,j</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo>
  <mo>+</mo><mfrac><mi>&#961;</mi><mn>2</mn></mfrac>
  <munder><mo>&#x2211;</mo><mi>j</mi></munder><munder><mo>&#x2211;</mo><mi>t</mi></munder>
  <msup><mrow><mo>(</mo><msub><mi>p</mi><mtext>ag_dso,j</mtext></msub><mo>[</mo><mi>t</mi><mo>]</mo><mo>&#x2212;</mo><msub><mi>a</mi><mi>j</mi></msub><mo>[</mo><mi>t</mi><mo>]</mo><mo>)</mo></mrow><mn>2</mn></msup>
</mrow></math>
<span class="eqref">(eq. 3.47, DSO-OPT)</span>
</div>
<p>Agreement between the centralized solve and this independently-coded ADMM solve path is a
meaningful cross-validation: the two paths share no code beyond the device/
<code>contribute!</code> builders, so a silent bug in either one would show up as a large
welfare or price gap between them, not a tiny one (see Section 4).</p>
"""

section3_experiment_html = """
<h2 id="section3">3. Experiment design and parameter choices</h2>
<p>Every parameter below is quoted verbatim from <code>scripts/pv_boom_case_study.jl</code> —
nothing here is re-derived or approximated.</p>

<h3>3.1 Feeder, horizon, and reproducibility</h3>
<p>The case study runs on the <strong>IEEE-13 feeder</strong> over a <strong>T=24</strong>-hour
day-ahead horizon. Every random draw (profiles, population) is seeded from a single
<code>BASE_SEED = 20260806</code> via a <code>sub_seed</code> derivation, so the entire
script is byte-reproducible end to end: re-running it from a clean checkout produces
bit-identical results.</p>

<h3>3.2 The PV-penetration sweep</h3>
<p>Six PV multiplier levels are swept: <code>PV_MULTS = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5]</code>.
Each <code>pv_mult</code> scales the per-bus PV magnitude
(<code>TSODSO._IEEE13_PV_SCALE * pv_mult</code>) via the <code>pv_boom_population</code>
wrapper. <code>pv_mult = 1.0</code> reproduces the existing documented
<code>:ieee13</code>/<code>:default</code> calibration bit-for-bit (confirmed by the
declarative <code>Scenario</code>/<code>run_scenario</code> cross-check reported in Section
4). <code>pv_mult = 0.0</code> is the pre-solar baseline; <code>pv_mult = 2.5</code> is the
"boom" scenario this case study is named for.</p>

<h3>3.3 The ADMM cross-check</h3>
<p>ADMM (<code>ρ = 100.0</code>) is run at exactly ONE point, <code>pv_mult = 1.0</code> —
the one point already documented and validated for the default <code>:ieee13</code>/
<code>:default</code> calibration (per <code>Scenario.jl</code>'s own docstring). This is
repo precedent, not a fresh tuning choice.</p>

<h3>3.4 The EXACT-04 stress fixture</h3>
<p>Every one of the 6 IEEE-13 sweep points above stayed SOCP-exact (<code>exact_maxgap</code>
on the order of 1e-8 to 1e-9 — see Section 4's sweep table). To reproduce the documented
knife-edge condition where the SOC relaxation genuinely loses tightness, a SEPARATE,
deliberately engineered 3-bus stress fixture is used instead of hoping the IEEE-13 sweep
itself goes inexact:</p>
<ul>
<li>3 buses, two branches with <code>r = x = 0.05</code> each, voltage cap
<code>vmax = 1.05</code>;</li>
<li>each house: PV scaled by <code>pv_scale = 1.2</code>, load scaled by
<code>load_scale = 0.2</code> — a deliberately PV-heavy, lightly-loaded configuration that
drives reverse flow and over-voltage;</li>
<li>solved with the documented diagnostic override <code>rtol_exact = 1.0</code> (loosens
only the internal SOCP-solve gate so the solve completes; the actual exactness VERDICT
reported in Section 4 comes from the independent AC-power-flow oracle's own standard
<code>rtol = 1e-4</code>, never from this loosened internal gate).</li>
</ul>

<h3>3.5 The planning-layer Nash game</h3>
<p>Two IEEE-13-scale distributors play a Stackelberg-Nash investment game over a shared
transmission-reinforcement corridor: a low-PV "baseline" and a "boom" distributor, over the
afternoon PV-peak sub-horizon hours 13-18 (<code>T_planning = 6</code>).</p>

<div class="finding">
<strong>Honest deviation, stated plainly:</strong> the originally-intended baseline
<code>pv_mult = 0.0</code> is STRUCTURALLY infeasible for this game.
<code>solve_stackelberg!</code>'s Benders master always proposes <code>z = 0</code> (zero
frontier import) as its unconditional FIRST trial — before any Benders cut exists — and a
zero-PV network has no way to self-balance zero frontier import, so the oracle raises a hard
infeasibility before any cut can even be attempted. This was verified directly:
<code>pv_mult ∈ {0.0, 0.3, 0.5}</code> all fail this way; <code>pv_mult ≥ 0.7</code> is
feasible (the feasibility floor). <code>pv_mult = 0.7</code> was substituted for the baseline
distributor to keep the "low PV vs PV boom" contrast playable — the "boom" distributor keeps
<code>pv_mult = 2.5</code>, reusing Section 3.2's own already-swept population.
</div>
"""

section5_repro_html = """
<h2 id="section5">5. Reproducibility</h2>
<p>PLACEHOLDER — finished in Task 2 with a live git commit stamp, the re-run commands, and
the BASE_SEED reproducibility note.</p>
"""

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
  math { font-size: 1.05rem; }
  .eq-block { background: #f7f9fb; border: 1px solid #dde3ea; border-radius: 6px; padding: 0.8rem 1.2rem; margin: 1rem 0; overflow-x: auto; }
  .eqref { float: right; font-size: 0.8rem; color: #888; font-style: italic; }
  nav.toc { position: sticky; top: 0; background: #fff; border-bottom: 2px solid #2c5f8a; padding: 0.6rem 0; margin-bottom: 1.5rem; font-size: 0.92rem; z-index: 10; }
  nav.toc a { margin-right: 1rem; color: #2c5f8a; text-decoration: none; font-weight: 600; }
  nav.toc a:hover { text-decoration: underline; }
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
