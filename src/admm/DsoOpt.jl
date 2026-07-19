# src/admm/DsoOpt.jl
#
# SEAM: DSO-OPT — the whole-network SOCP ADMM subproblem (ADMM-01).
# OWNER: plan 06-03 (Wave 2). This file is a COMMENT-ONLY stub here in Wave 1; plan
# 06-03 fills it and declares its own `export`s per the include-graph convention.
#
# WHAT IT WILL BE (RESEARCH Pattern 4 / thesis eq. 3.47):
#   The network subproblem that REUSES `ConvexBranchFlow.contribute!` verbatim (P, Q, v, v̂,
#   l, cone, vdrop, cpydrop, smax, :Rp/:Rq) plus the priced free-sign frontier export — the
#   SOC-exactness enabler (PF-04). Block 2 of the 2-block split derived from the single
#   augmented Lagrangian (RESEARCH Pattern 1):
#
#       min_{P,Q,v,v̂,l,p_import}  λ₀ᵀ p_import
#                                 − Σ_j Σ_t λ_j[t]·pag_dso_j[t]         (linear price term)
#                                 + (ρ/2) Σ_j Σ_t ( a_j[t] − pag_dso_j[t] )²  (ρ-penalty)
#         s.t.  ConvexBranchFlow constraints (thesis 3.29–3.45)
#               :Rp[root] + p_import == 0                    (root, hard — no aggregator)
#               :Rp[j] + pag_dso_j[t] == 0                   (load-node coupling var)
#
#   `pag_dso_j := −netflow_j` is an explicit coupling variable so the objective touches a
#   SINGLE variable per (j,t) — the key that makes `set_objective_coefficient` a one-call
#   update (ADMM-03). Solver via `select_optimizer(SOCP())` (INFRA-02); gated on
#   `assert_solved!(...; dual=true)` (INFRA-03). `assert_socp_exact!(dso_ctx)` runs on the
#   CONVERGED solve only (PF-04, RESEARCH Pitfall 3) — never mid-loop (early iterates are
#   legitimately inexact). Never model λ_j as a `Parameter` (Pitfall 1).
#
# No code / no exports yet — Wave 2 owns this seam.
