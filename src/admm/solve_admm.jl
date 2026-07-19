# src/admm/solve_admm.jl
#
# SEAM: solve_admm — the hand-rolled dual-ascent ADMM loop (ADMM-01 / ADMM-03 / ADMM-04).
# OWNER: plan 06-04 (Wave 3). This file is a COMMENT-ONLY stub here in Wave 1; plan
# 06-04 fills it and declares its own `export`s per the include-graph convention.
#
# WHAT IT WILL BE (RESEARCH Pattern 2 / thesis eq. 3.31 dual update):
#   The outer orchestrator that BUILDS AGR-OPT[j] (plan 06-02) and DSO-OPT (plan 06-03)
#   ONCE, then alternates their solves and takes one gradient-ascent step on the coupling
#   price each iteration (hand-rolled per CLAUDE.md — no Coluna/StructJuMP):
#
#       R_{p,j}[t] = value(pag_j[t]) − value(pag_dso_j[t])   (consensus violation → 0)
#       λ_j[t]  ←  λ_j[t]  +  ρ · R_{p,j}[t]                 (thesis: λ ← λ + ρ·R_{p,j})
#       R_{q,j}[t] = value(qag_j[t]) − value(qag_dso_j[t])
#       μ_j[t]  ←  μ_j[t]  +  ρ · R_{q,j}[t]                 (thesis: μ ← μ + ρ·R_{q,j})
#
#   STOP on the primal residual max_{j,t}|R_{p,j}| ≤ ε OR a maxiter cap that FAILS LOUD
#   (RESEARCH Pitfall 2). Residual traces recorded in `AdmmResiduals` (residuals.jl). At
#   convergence: `assert_socp_exact!(dso_ctx)` (PF-04), welfare recomputed from PRIMAL values
#   (Σ U_ag − λ₀ᵀp_import — NOT the penalized subproblem objective), and returns
#   `(; welfare, dadp, λ, iters, residuals, dso_ctx, exact_maxgap)`.
#
#   CORRECTNESS GATE (ADMM-04): the returned welfare AND λ_j must match the centralized
#   `solve_welfare` optimum + `extract_dlmp` duals to tolerance on every small fixture
#   (2-bus, IEEE-13 ground) — the false-convergence net (RESEARCH Pattern 5). This is the
#   whole value of the phase; the loop consumes AGR-OPT, DSO-OPT, and AdmmResiduals.
#
# No code / no exports yet — Wave 3 owns this seam.
