# scripts/pv_boom_report_v2.jl
#
# Review-hardened v2 of the PV-boom case study HTML report (quick task 260807-bv8).
# Starts from scripts/pv_boom_report.jl's mechanics (data loading, figures, tables,
# live-computed Section-4 numbers) — copied verbatim in substance, never `include()`d —
# and layers on six review-hardening additions: source-file/line citations next to every
# equation, a notation/symbols glossary, an inline SVG architecture diagram, a dedicated
# honest-limitations section, semantic HTML5 structure + accessibility + print/dark-mode
# CSS, and a battery of self-verifying gates. v1's `scripts/pv_boom_report.jl` and
# `results/pv_boom/report.html` are READ-ONLY inputs and are NEVER modified by this file.
#
#   julia --project=. scripts/pv_boom_report_v2.jl
#
using DrWatson
@quickactivate "TSODSO"

using TSODSO
using CairoMakie
using Base64
using Printf

results = DrWatson.wload(datadir("pv_boom", "results.jld2"))
sweep = results["sweep"]
admm_crosscheck = results["admm_crosscheck"]
nash_result = results["nash_result"]
ac_stress = results["ac_stress"]

ok_rows = [r for r in sweep if r.status == "ok"]
isempty(ok_rows) && error(
    "pv_boom_report_v2: no successful sweep points in data/pv_boom/results.jld2 — " *
    "nothing to report. Re-run scripts/pv_boom_case_study.jl.",
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

# ── Section 4 richly-interpreted numbers — computed directly from the loaded results
# dict / sweep rows (never hardcoded/re-typed from findings.txt, so they can never drift
# from the actual data this run loaded). Every number below carries a `.provenance` span
# in the final assembly (Task 2) reading "computed from results.jld2". ──────────────────
baseline_idx = findfirst(r -> r.pv_mult == 0.0 && r.status == "ok", sweep)
baseline_row = baseline_idx === nothing ? nothing : sweep[baseline_idx]

welfare_deltas_html = let io = IOBuffer()
    println(io, "<ul>")
    if baseline_row !== nothing
        for r in ok_rows
            r.pv_mult == 0.0 && continue
            δ = r.welfare - baseline_row.welfare
            @printf(
                io,
                "<li><code>pv_mult=%.1f</code>: welfare Δ = <b>+%.2f</b> vs the pv_mult=0.0 baseline (welfare=%.4f) <span class=\"provenance\">(computed from results.jld2)</span></li>\n",
                r.pv_mult,
                δ,
                r.welfare,
            )
        end
    end
    println(io, "</ul>")
    String(take!(io))
end

exact_maxgaps_html = let io = IOBuffer()
    println(io, "<ul>")
    for r in ok_rows
        @printf(
            io,
            "<li><code>pv_mult=%.1f</code>: exact_maxgap = %.3e <span class=\"provenance\">(computed from results.jld2)</span></li>\n",
            r.pv_mult,
            r.exact_maxgap,
        )
    end
    println(io, "</ul>")
    String(take!(io))
end

admm_relative_gap =
    abs(admm_crosscheck.welfare_admm - admm_crosscheck.welfare_centralized) /
    abs(admm_crosscheck.welfare_centralized)
admm_iters = admm_crosscheck.residuals.iters

nash_differentiated =
    isapprox(nash_result.x_inv[1], nash_result.x_inv[2]; rtol = 1e-3) ? false : true

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
# NEW REVIEW-HARDENING CONTENT (quick task 260807-bv8) — four additions not present in
# v1: a notation/symbols glossary, an inline SVG architecture diagram, a consolidated
# honest-limitations section, and a CSS fragment (source-citation/provenance spans,
# semantic-landmark spacing, print, dark mode). Not yet wired into a final `html_string`
# — Task 2 ports v1's five narrative sections (with source-citation + provenance spans
# added), wires all of this together, and writes `results/pv_boom/report_v2.html`.
# ═════════════════════════════════════════════════════════════════════════════════════

notation_table_html = """
<section id="notation">
<h2 id="notation-h">Notation and symbols</h2>
<p>Every symbol used in the equations below, defined once here before it is first used.</p>
<table>
<tr><th>Symbol</th><th>Meaning</th><th>Units / convention</th></tr>
<tr><td><code>p_import[t]</code></td><td>Active power exchange with the transmission grid (MEM) at the feeder root</td><td>pu power; <code>&gt;0</code> = buy, <code>&lt;0</code> = sell (only when <code>allow_export=true</code>)</td></tr>
<tr><td><code>λ₀[t]</code></td><td>Wholesale/MEM price at the transmission root (the price <code>p_import</code> is settled at)</td><td>pu price / pu power</td></tr>
<tr><td><code>λ_j[t]</code> (DADP)</td><td>Day-ahead dynamic price at bus <code>j</code>, hour <code>t</code> — the dual of the nodal active-balance constraint <code>balance_p[j,t]</code></td><td>pu price / pu power</td></tr>
<tr><td><code>v[j,t]</code>, <code>v̂[j,t]</code></td><td>Squared voltage magnitude at bus <code>j</code> (the SOCP relaxed variable <code>v</code>, and <code>v̂</code> the LinDistFlow "exactness copy" auxiliary variable that drives the cone to hold with equality)</td><td>pu²</td></tr>
<tr><td><code>l[b,t]</code></td><td>Squared current magnitude on branch <code>b</code> — the loss/current variable in the SOC cone <code>l·v ≥ P²+Q²</code></td><td>pu²</td></tr>
<tr><td><code>P[b,t]</code>, <code>Q[b,t]</code></td><td>Active / reactive power flow on branch <code>b</code>, hour <code>t</code></td><td>pu</td></tr>
<tr><td><code>ρ</code></td><td>ADMM quadratic penalty weight (AGR-OPT / DSO-OPT)</td><td>pu⁻¹ (scales a squared-power term)</td></tr>
<tr><td><code>z[i,t]</code></td><td>Distributor <code>i</code>'s frontier import/export at the shared transmission corridor — the planning-layer coupling variable (<code>p_import == z</code>)</td><td>pu power</td></tr>
<tr><td><code>x_inv[i]</code></td><td>Distributor <code>i</code>'s converged flexibility-investment level (planning-layer decision)</td><td>pu</td></tr>
<tr><td><code>π_s</code></td><td>Dual of the planning-layer coupling constraint <code>p_import == z</code>; the Benders cut gradient — a "linking price" conceptually analogous to a DLMP (per README's own language)</td><td>pu price / pu power</td></tr>
<tr><td><code>pv_mult</code></td><td>PV-penetration multiplier scaling per-bus PV magnitude — a parameter of THIS case study only (<code>pv_boom_case_study.jl</code>), not a framework-wide symbol</td><td>dimensionless</td></tr>
</table>
</section>
"""

architecture_diagram_html = """
<section id="architecture">
<h2 id="architecture-h">Architecture: operational and planning layers</h2>
<svg viewBox="0 0 900 480" role="img" aria-labelledby="arch-svg-title arch-svg-desc" xmlns="http://www.w3.org/2000/svg">
<title id="arch-svg-title">Two-layer architecture diagram</title>
<desc id="arch-svg-desc">Operational layer on the left (prosumer devices to aggregator to DSO network, emitting DADP prices); planning layer on the right (two distributor-leaders to a shared transmission corridor to a transmission-reinforcement follower); a thin cross-layer arrow shows the PV-boom case study's own local_price to c_op calibration link.</desc>
<defs>
<marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
<path d="M 0 0 L 10 5 L 0 10 z" fill="#2c5f8a"></path>
</marker>
</defs>
<text x="20" y="20" font-size="14" font-weight="bold" fill="#2c5f8a">Operational layer</text>
<rect x="20" y="30" width="220" height="55" rx="6" fill="#f7f9fb" stroke="#2c5f8a"></rect>
<text x="130" y="53" font-size="12" text-anchor="middle">Prosumer devices</text>
<text x="130" y="70" font-size="11" text-anchor="middle">(Interruptible / Thermostatic /</text>
<text x="130" y="82" font-size="11" text-anchor="middle">Deferrable / PVBattery)</text>
<line x1="130" y1="85" x2="130" y2="120" stroke="#2c5f8a" stroke-width="2" marker-end="url(#arrow)"></line>
<rect x="20" y="122" width="220" height="45" rx="6" fill="#f7f9fb" stroke="#2c5f8a"></rect>
<text x="130" y="150" font-size="12" text-anchor="middle">Aggregator (per bus)</text>
<line x1="130" y1="167" x2="130" y2="202" stroke="#2c5f8a" stroke-width="2" marker-end="url(#arrow)"></line>
<rect x="20" y="204" width="220" height="55" rx="6" fill="#f7f9fb" stroke="#2c5f8a"></rect>
<text x="130" y="227" font-size="12" text-anchor="middle">DSO network</text>
<text x="130" y="243" font-size="11" text-anchor="middle">(ConvexBranchFlow SOCP)</text>
<line x1="130" y1="259" x2="130" y2="294" stroke="#2c5f8a" stroke-width="2" marker-end="url(#arrow)"></line>
<text x="130" y="312" font-size="11" text-anchor="middle" fill="#333">λ_j[t] = dual(balance_p[j,t])</text>
<text x="130" y="326" font-size="11" text-anchor="middle" fill="#333">(DADP)</text>

<text x="480" y="20" font-size="14" font-weight="bold" fill="#2c5f8a">Planning layer</text>
<rect x="460" y="30" width="220" height="50" rx="6" fill="#f7f9fb" stroke="#2c5f8a"></rect>
<text x="570" y="50" font-size="12" text-anchor="middle">Distributor-leader (baseline)</text>
<text x="570" y="66" font-size="11" text-anchor="middle">Benders master + subproblem</text>
<line x1="570" y1="80" x2="570" y2="112" stroke="#2c5f8a" stroke-width="2" marker-end="url(#arrow)"></line>
<rect x="460" y="114" width="220" height="50" rx="6" fill="#f7f9fb" stroke="#2c5f8a"></rect>
<text x="570" y="134" font-size="12" text-anchor="middle">Distributor-leader (boom)</text>
<text x="570" y="150" font-size="11" text-anchor="middle">Benders master + subproblem</text>
<text x="570" y="182" font-size="10" text-anchor="middle" fill="#555">decision vars x_inv[i], z[i,t]</text>
<line x1="570" y1="164" x2="570" y2="198" stroke="#2c5f8a" stroke-width="2" marker-end="url(#arrow)"></line>
<rect x="460" y="200" width="220" height="55" rx="6" fill="#f7f9fb" stroke="#2c5f8a"></rect>
<text x="570" y="223" font-size="12" text-anchor="middle">Shared transmission corridor</text>
<text x="570" y="239" font-size="11" text-anchor="middle">p_import == z, dual π_s</text>
<line x1="570" y1="255" x2="570" y2="290" stroke="#2c5f8a" stroke-width="2" marker-end="url(#arrow)"></line>
<text x="570" y="270" font-size="10" text-anchor="middle" fill="#555">Gauss-Seidel diagonalization across</text>
<text x="570" y="282" font-size="10" text-anchor="middle" fill="#555">distributors -&gt; Nash equilibrium (run_nash!)</text>
<rect x="460" y="292" width="220" height="55" rx="6" fill="#f7f9fb" stroke="#2c5f8a"></rect>
<text x="570" y="315" font-size="12" text-anchor="middle">Transmission-reinforcement</text>
<text x="570" y="331" font-size="12" text-anchor="middle">follower</text>

<line x1="240" y1="300" x2="455" y2="215" stroke="#888" stroke-width="1.5" stroke-dasharray="4 3" marker-end="url(#arrow)"></line>
<text x="345" y="360" font-size="10" text-anchor="middle" fill="#555">this case study only: local_price -&gt; c_op cost coefficient</text>
<text x="345" y="373" font-size="10" text-anchor="middle" fill="#555">(scripts/pv_boom_case_study.jl:515-527, distributor_calibration)</text>
</svg>
<p>The diagram shows the operational layer (prosumer devices aggregated per bus, cleared
on a convex branch-flow DSO network, emitting per-bus DADP prices as duals) alongside the
planning layer (two distributor-leaders reaching a Nash equilibrium by Gauss-Seidel
diagonalization over a shared transmission corridor against a transmission-reinforcement
follower); the dashed cross-layer arrow marks the ONE data flow this specific case study
wires between the two layers — it is not a general framework feature.</p>
</section>
"""

limitations_html = """
<section id="limitations">
<h2 id="limitations-h">Honest limitations</h2>
<p>Every genuinely negative or caveated finding already documented in this report,
gathered here in one place — none softened, none new.</p>
<ol>
<li><strong>Welfare-level meaninglessness.</strong> Every device utility has its additive
thesis constant <code>c</code> deliberately dropped (RESEARCH A5, stated in every device
docstring); only welfare DELTAS between scenarios and DUALS (prices) are economically
meaningful, never the reported level in isolation.</li>
<li><strong>EXACT-04 SOC inexactness under high-PV reverse flow.</strong> The certified
3-bus stress fixture (<code>pv_scale=1.2</code>, <code>load_scale=0.2</code>,
<code>vmax=1.05</code>) shows the SOC relaxation genuinely INEXACT at
<b>$(ac_stress.n_inexact_hours) of 24 hours</b>
<span class="provenance">(computed from results.jld2)</span>
(<code>obj_gap=$(round(ac_stress.obj_gap; sigdigits=4))</code>,
<code>socp_maxgap=$(round(ac_stress.socp_maxgap; sigdigits=4))</code>
<span class="provenance">(computed from results.jld2)</span> under the documented
<code>rtol_exact=1.0</code> diagnostic override) — the IEEE-13 sweep itself never exhibits
this (all 6 <code>pv_mult</code> points stay exact to O(1e-8)-O(1e-9)).</li>
<li><strong>The <code>pv_mult&gt;=0.7</code> Benders feasibility floor deviation.</strong>
<code>solve_stackelberg!</code>'s Benders master's unconditional first trial is
<code>z=0</code>; a zero-PV network cannot self-balance zero frontier import, so
<code>pv_mult ∈ {0.0, 0.3, 0.5}</code> all raise a hard <code>INFEASIBLE</code> before any
cut is attempted; <code>pv_mult &gt;= 0.7</code> is the feasibility floor.
<code>pv_mult=0.7</code> was substituted for the intended <code>0.0</code> baseline.</li>
<li><strong>Nash non-differentiation.</strong> The converged planning game gives
<code>x_inv = $(nash_result.x_inv)</code>
<span class="provenance">(computed from results.jld2)</span> for both distributors at
this calibration: a genuine, reported-as-is finding, never forced apart.</li>
<li><strong>"Directional, public-data" thesis-reproduction qualifier.</strong> Quoting
<code>README.md</code> (lines 77-81): "the thesis's DSO-surplus sign flip reproduces on
real public data; the +25% welfare-ratio magnitude does not — stated plainly, always with
the 'directional, public-data' qualifier, pinned only on sign-safe quantities." This is a
repo-wide reproduction-honesty convention, not something specific to the PV-boom study.</li>
</ol>
</section>
"""

extra_style_html = """
  .src { display: block; font-family: 'Courier New', monospace; font-size: 0.78rem; color: #777; margin-top: 0.2rem; }
  .provenance { font-style: italic; font-size: 0.85rem; color: #666; }
  main { display: block; }
  nav.toc { }
  section { margin-bottom: 1rem; }
  svg { max-width: 100%; height: auto; background: #fff; }
  @media print {
    nav.toc { display: none; }
    figure, .eq-block { break-inside: avoid; page-break-inside: avoid; }
  }
  @media (prefers-color-scheme: dark) {
    body { background: #1b1e22; color: #dcdcdc; }
    .eq-block { background: #24282e; border-color: #3a3f47; }
    table { color: #dcdcdc; }
    th { background: #2a2f36; }
    th, td { border-color: #444; }
    .finding { background: #33301a; border-left-color: #e0a800; color: #dcdcdc; }
    nav.toc { background: #1b1e22; border-bottom-color: #6fa8d8; }
    nav.toc a { color: #6fa8d8; }
    a { color: #6fa8d8; }
    .src, .provenance { color: #9aa0a6; }
  }
"""

println("scripts/pv_boom_report_v2.jl: Task-1 scaffold loaded OK (notation/architecture/limitations/style defined, not yet assembled).")
