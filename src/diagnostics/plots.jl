# src/diagnostics/plots.jl
#
# SEAM: convergence-diagnostics plotting API (ADMM-05).
# OWNER: plan 07-01 (this plan, Task 1) — declares the exported generic functions;
# the CairoMakie-backed METHODS are filled by plan 07-06 in ext/TSODSOMakieExt.jl.
#
# CORE STAYS PLOT-FREE (threat T-07-01): this file declares ONLY method-less generic
# functions + their `export`s and imports NO CairoMakie — so `using TSODSO` and the
# headless CI test suite never pull the heavy Makie viz stack. The plotting backend is a
# WEAKDEP package extension (RESEARCH Pattern 6, mirroring ext/TSODSOGurobiExt.jl): Julia
# lights up the methods ONLY when CairoMakie is present in the active environment.
#
# The functions consume the JuMP-free `AdmmResiduals` ledger (src/admm/residuals.jl) —
# hence this file is included AFTER the admm/ seams in TSODSO.jl.

"""
    plot_convergence(res::AdmmResiduals; filename=nothing)

Plot the ADMM primal + dual residual traces (and the ε_pri / ε_dual threshold lines)
versus iteration on a log-scaled axis. **Requires CairoMakie to be loaded** — the
method lives in the `TSODSOMakieExt` package extension (plan 07-06); with only the core
package loaded this generic function has NO applicable method (a deliberate MethodError,
keeping the core solve + headless CI plot-free, threat T-07-01).
"""
function plot_convergence end

"""
    plot_price_convergence(res::AdmmResiduals; filename=nothing)

Plot the DADP / price-convergence trajectory (the `price_gap_trace`, optionally with the
adaptive-ρ schedule on a twin axis) versus iteration. **Requires CairoMakie to be
loaded** — the method lives in the `TSODSOMakieExt` package extension (plan 07-06); with
only the core package loaded this generic function has NO applicable method.
"""
function plot_price_convergence end

export plot_convergence, plot_price_convergence
