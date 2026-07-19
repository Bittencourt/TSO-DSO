# src/admm/residuals.jl
#
# SEAM: AdmmResiduals — the ADMM primal/dual residual ledger (ADMM-01 diagnostics).
# OWNER: plan 06-01 (this plan, Task 2). Filled in-place below; declares its own `export`s
# per the include-graph convention.
#
# A pure data / bookkeeping type — NO JuMP, NO solves — so both Phase 6 (primal-only
# stopping) and Phase 7 (dual-residual stop + adaptive-ρ) reuse it. It records, per ADMM
# iteration, the worst-magnitude primal and dual residuals of RESEARCH Pattern 2:
#
#     R_{p,j}[t] = value(pag_j[t]) − value(pag_dso_j[t])   (primal / consensus violation)
#     dual residual ≈ ρ · Δ(coupling) across iterations    (the dual-ascent step size)
#
# so `solve_admm` (plan 06-04) can drive convergence, plot the residual traces (CairoMakie),
# and fail loud at the maxiter cap (RESEARCH Pitfall 2).

# NOTE: filled by Task 2 of this plan (see below).
