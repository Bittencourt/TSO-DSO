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
# SCAFFOLD ONLY (this plan): the CairoMakie-backed methods for
# `TSODSO.plot_convergence(res::TSODSO.AdmmResiduals; ...)` and
# `TSODSO.plot_price_convergence(res::TSODSO.AdmmResiduals; ...)` are added by plan
# 07-06 (RESEARCH Pattern 6). Until then this module only establishes the extension
# wiring so the weakdep/[extensions] declaration in Project.toml is complete and the
# symbols the ext extends are always exported by the core.
module TSODSOMakieExt

using TSODSO, CairoMakie

# --- plan 07-06 fills the plotting methods here (RESEARCH Pattern 6) ---
#
# function TSODSO.plot_convergence(res::TSODSO.AdmmResiduals; filename = nothing)
#     ...  # Figure / Axis(yscale = log10) / lines! over res.primal_trace, res.dual_trace,
#          #      res.eps_pri_trace, res.eps_dual_trace ; save(filename, f)
# end
#
# function TSODSO.plot_price_convergence(res::TSODSO.AdmmResiduals; filename = nothing)
#     ...  # res.price_gap_trace, res.rho_trace on a twin axis, per-node λ
# end

end # module TSODSOMakieExt
