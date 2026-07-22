# ext/TSODSOMakieExt.jl
#
# Package extension for CairoMakie convergence diagnostics (ADMM-05, opt-in viz).
# OWNER: plan 07-01 SCAFFOLDS this module; plan 07-06 FILLS the method bodies.
#
# Loaded by Julia ONLY when both TSODSO and CairoMakie are present in the active
# environment (weakdep + [extensions] gating — the modern replacement for Requires.jl,
# mirroring ext/TSODSOGurobiExt.jl / ext/TSODSOMosekExt.jl). CairoMakie is NEVER a hard
# dependency and stays removable: it appears only under [weakdeps] in Project.toml, so
# the core `using TSODSO` and the headless CI test suite never import the heavy Makie
# viz stack (threat T-07-01).
#
# FILLED by plan 07-06 (RESEARCH Pattern 6): the CairoMakie-backed methods for
# `TSODSO.plot_convergence(res::TSODSO.AdmmResiduals; ...)` and
# `TSODSO.plot_price_convergence(res::TSODSO.AdmmResiduals; ...)`. Each builds and RETURNS a
# Makie `Figure` from the JuMP-free `AdmmResiduals` ledger ONLY — no JuMP, no solver, no
# reach into optimization state (threat T-07-18). The methods dispatch on the core generic
# functions declared in src/diagnostics/plots.jl, mirroring how ext/TSODSOGurobiExt.jl /
# ext/TSODSOMosekExt.jl add methods to the core solver-factory generic.
module TSODSOMakieExt

using TSODSO, CairoMakie

# Iterations axis for a recorded ledger (1 … res.iters). The traces are all equal length
# (`== iters`), so a single x-range serves every series.
_iters_axis(res::TSODSO.AdmmResiduals) = 1:(res.iters)

# log10-axis guard (IN-04): the residual / price-gap traces are stored `abs(...)` / `ρ·r_norm`,
# so a value of EXACTLY 0.0 (e.g. `price_gap = ρ·r_norm` when `r_norm` hits 0, or a residual that
# converges to exactly zero) maps to `log10(0) = -Inf`, which Makie rejects/drops — silently
# breaking the thesis-grade figure. Clamp each plotted series to a small positive floor (`eps()`)
# so a converged-to-zero trace degrades gracefully to the axis floor instead of crashing the plot.
_logsafe(trace) = max.(trace, eps())

"""
    TSODSO.plot_convergence(res::AdmmResiduals; filename = nothing) -> Makie.Figure

Plot the ADMM primal `‖r‖` and dual `‖s‖` residual traces versus iteration on a
log-scaled axis, overlaid with the per-unit `ε_pri` / `ε_dual` stopping-threshold lines
(dashed) so convergence is read as the residual curves crossing below their thresholds
(RESEARCH Pattern 6). Reads ONLY the JuMP-free `AdmmResiduals` traces. If `filename` is
given the figure is `save`d (vector PDF/SVG for thesis-grade output). Returns the `Figure`.
"""
function TSODSO.plot_convergence(res::TSODSO.AdmmResiduals; filename = nothing)
    xs = _iters_axis(res)
    fig = Figure()
    ax = Axis(
        fig[1, 1];
        xlabel = "ADMM iteration k",
        ylabel = "residual (per-unit)",
        yscale = log10,
        title = "ADMM convergence: primal ‖r‖ & dual ‖s‖ vs iteration",
    )
    lines!(ax, xs, _logsafe(res.primal_trace); label = "‖r‖ primal", color = :dodgerblue)
    lines!(ax, xs, _logsafe(res.dual_trace); label = "‖s‖ dual", color = :crimson)
    lines!(
        ax,
        xs,
        _logsafe(res.eps_pri_trace);
        label = "ε_pri",
        color = :dodgerblue,
        linestyle = :dash,
    )
    lines!(
        ax,
        xs,
        _logsafe(res.eps_dual_trace);
        label = "ε_dual",
        color = :crimson,
        linestyle = :dash,
    )
    axislegend(ax; position = :rt)
    filename === nothing || save(filename, fig)
    return fig
end

"""
    TSODSO.plot_price_convergence(res::AdmmResiduals; filename = nothing) -> Makie.Figure

Plot the DADP price-convergence trajectory — the price move `‖Δλ‖` (`price_gap_trace`) on a
log-scaled left axis — with the adaptive-ρ schedule (`rho_trace`) on a twin right axis, so
the price move decaying while ρ balances the residuals is read at a glance (RESEARCH
Pattern 6). Reads ONLY the JuMP-free `AdmmResiduals` traces. If `filename` is given the
figure is `save`d. Returns the `Figure`.
"""
function TSODSO.plot_price_convergence(res::TSODSO.AdmmResiduals; filename = nothing)
    xs = _iters_axis(res)
    fig = Figure()
    ax = Axis(
        fig[1, 1];
        xlabel = "ADMM iteration k",
        ylabel = "price move ‖Δλ‖ (per-unit)",
        yscale = log10,
        title = "DADP price convergence & adaptive-ρ schedule",
    )
    axρ = Axis(
        fig[1, 1];
        ylabel = "penalty ρ",
        yaxisposition = :right,
        ylabelcolor = :seagreen,
        yticklabelcolor = :seagreen,
    )
    # The twin axis shares x with the primary; hide its duplicate frame/x-decorations.
    hidespines!(axρ)
    hidexdecorations!(axρ)
    linkxaxes!(ax, axρ)

    lgap = lines!(ax, xs, _logsafe(res.price_gap_trace); color = :purple)
    lrho = lines!(axρ, xs, res.rho_trace; color = :seagreen, linestyle = :dot)
    axislegend(ax, [lgap, lrho], ["‖Δλ‖ price gap", "ρ (penalty)"]; position = :rt)
    filename === nothing || save(filename, fig)
    return fig
end

end # module TSODSOMakieExt
