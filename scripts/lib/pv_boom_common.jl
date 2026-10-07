# scripts/lib/pv_boom_common.jl
#
# Shared helpers for the PV-boom case-study HTML report (`scripts/pv_boom_report.jl`):
# results loading, representative-bus selection, the three report figures, base64
# embedding, and the sweep / Nash / welfare-delta / exactness-gap HTML fragments.
# Every number is computed from the loaded results, never re-typed.
#
# This file is `include`d by the report script; it is not a script of its own.
#
using DrWatson
using TSODSO
using CairoMakie
using Base64
using Printf

"""
    pv_boom_load_results(path) -> NamedTuple

Load the case-study results file and return
`(; sweep, admm_crosscheck, nash_result, ac_stress, ok_rows)`, where `ok_rows` are the
sweep rows with `status == "ok"`. Errors if there is no successful sweep point.
"""
function pv_boom_load_results(path)
    results = DrWatson.wload(path)
    sweep = results["sweep"]
    ok_rows = [r for r in sweep if r.status == "ok"]
    isempty(ok_rows) && error(
        "pv_boom_report: no successful sweep points in data/pv_boom/results.jld2 — " *
        "nothing to report. Re-run scripts/pv_boom_case_study.jl.",
    )
    return (;
        sweep,
        admm_crosscheck = results["admm_crosscheck"],
        nash_result = results["nash_result"],
        ac_stress = results["ac_stress"],
        ok_rows,
    )
end

"""
    pv_boom_stressed_bus(ok_rows) -> Int

The representative "most-stressed" bus: the one with the largest total-price spread across
every successful `pv_mult` level (max over `pv_mult` and hour, minus min).
"""
function pv_boom_stressed_bus(ok_rows)
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
    println(
        "Representative stressed bus (largest total-price spread across pv_mult) = ",
        stressed_bus,
    )
    return stressed_bus
end

"""
    pv_boom_figures(results, stressed_bus) -> NamedTuple

Build the three report figures and return `(; fig1, fig2, fig3, highest_row)`:
price curves per `pv_mult` at the stressed bus, the 4-way DLMP decomposition at the
stressed bus for the highest successful `pv_mult`, and the ADMM convergence plot
(the generic `TSODSO.plot_convergence`, never reimplemented).
"""
function pv_boom_figures(results, stressed_bus)
    ok_rows = results.ok_rows
    T_full = size(first(ok_rows).dlmp, 2)
    hours = 1:T_full

    # Figure 1: price curves, one line per successful pv_mult, at the stressed bus.
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

    # Figure 2: 4-way stacked decomposition (energy/loss/congestion/voltage) at the
    # stressed bus, for the HIGHEST successful pv_mult.
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
    loss_v = decomp.cone[stressed_bus, :]
    congestion_v = decomp.congestion[stressed_bus, :]
    voltage_v = decomp.drop[stressed_bus, :]
    stack1 = energy_v
    stack2 = stack1 .+ loss_v
    stack3 = stack2 .+ congestion_v
    stack4 = stack3 .+ voltage_v
    band!(ax2, hours, zeros(T_full), stack1; color = (:steelblue, 0.7), label = "energy")
    band!(ax2, hours, stack1, stack2; color = (:orange, 0.7), label = "loss")
    band!(ax2, hours, stack2, stack3; color = (:firebrick, 0.7), label = "congestion")
    band!(ax2, hours, stack3, stack4; color = (:seagreen, 0.7), label = "voltage")
    lines!(
        ax2,
        hours,
        decomp.total[stressed_bus, :];
        color = :black,
        linestyle = :dash,
        label = "total (DADP)",
    )
    axislegend(ax2; position = :rt)

    # Figure 3: ADMM convergence.
    fig3 = TSODSO.plot_convergence(results.admm_crosscheck.residuals)

    return (; fig1, fig2, fig3, highest_row)
end

"""Embed a Makie figure as a base64 PNG data URI (no external image files)."""
function figure_to_data_uri(fig)
    path = joinpath(mktempdir(), "fig.png")
    CairoMakie.save(path, fig)
    bytes = read(path)
    return "data:image/png;base64," * Base64.base64encode(bytes)
end

"""HTML list of welfare deltas vs the `pv_mult = 0.0` baseline, computed from the sweep."""
function welfare_deltas_html(sweep, ok_rows; provenance = true)
    tag = provenance ? " <span class=\"provenance\">(computed from results.jld2)</span>" : ""
    baseline_idx = findfirst(r -> r.pv_mult == 0.0 && r.status == "ok", sweep)
    baseline_row = baseline_idx === nothing ? nothing : sweep[baseline_idx]
    io = IOBuffer()
    println(io, "<ul>")
    if baseline_row !== nothing
        for r in ok_rows
            r.pv_mult == 0.0 && continue
            δ = r.welfare - baseline_row.welfare
            @printf(
                io,
                "<li><code>pv_mult=%.1f</code>: welfare Δ = <b>+%.2f</b> vs the pv_mult=0.0 baseline (welfare=%.4f)%s</li>\n",
                r.pv_mult,
                δ,
                r.welfare,
                tag,
            )
        end
    end
    println(io, "</ul>")
    return String(take!(io))
end

"""HTML list of the per-`pv_mult` SOCP exactness gap (`exact_maxgap`)."""
function exact_maxgaps_html(ok_rows; provenance = true)
    tag = provenance ? " <span class=\"provenance\">(computed from results.jld2)</span>" : ""
    io = IOBuffer()
    println(io, "<ul>")
    for r in ok_rows
        @printf(
            io,
            "<li><code>pv_mult=%.1f</code>: exact_maxgap = %.3e%s</li>\n",
            r.pv_mult,
            r.exact_maxgap,
            tag,
        )
    end
    println(io, "</ul>")
    return String(take!(io))
end

"""HTML table of every sweep point (status, welfare, exactness gap or failure reason)."""
function sweep_table_html(rows)
    io = IOBuffer()
    println(io, "<table>")
    println(
        io,
        "<tr><th>pv_mult</th><th>status</th><th>welfare</th><th>exact_maxgap</th></tr>",
    )
    for r in rows
        if r.status == "ok"
            println(
                io,
                "<tr><td>$(r.pv_mult)</td><td>$(r.status)</td><td>$(round(r.welfare; digits=4))</td>" *
                "<td>$(round(r.exact_maxgap; sigdigits=4))</td></tr>",
            )
        else
            println(
                io,
                "<tr><td>$(r.pv_mult)</td><td>$(r.status)</td><td colspan=2>$(first(r.reason, 80))</td></tr>",
            )
        end
    end
    println(io, "</table>")
    return String(take!(io))
end

"""HTML table of the converged planning-game investment and mean frontier import."""
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
