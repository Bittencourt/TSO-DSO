# src/admm/AgrOpt.jl
#
# SEAM: AGR-OPT — the per-node aggregator/device ADMM subproblem (ADMM-01).
# OWNER: plan 06-02 (Wave 2). This file is a COMMENT-ONLY stub here in Wave 1; plan
# 06-02 fills it and declares its own `export`s per the include-graph convention.
#
# WHAT IT WILL BE (RESEARCH Pattern 4 / thesis eq. 3.46):
#   A thin per-aggregator QP that REUSES the existing device/`Aggregator.contribute!`
#   builders verbatim — ADMM is orchestration, not a model re-implementation. Block 1 of
#   the 2-block split derived from the single augmented Lagrangian (RESEARCH Pattern 1):
#
#       max_{device vars}  U_ag,j(devices)
#                          − Σ_t λ_j[t]·pag_j[t]                 (linear price term)
#                          − (ρ/2) Σ_t ( c_j[t] + pag_j[t] )²   (quadratic ρ-penalty)
#         s.t.  pag_j[t] == Σ_d p_inject_d[t] − Pdc[t]          (coupling var, thesis 3.22)
#               qag_j[t] == −Pdc[t]·tan(arccos φ)               (thesis 3.23, constant)
#               device constraints (thesis 3.2–3.9)
#
#   BUILD-ONCE / RE-SOLVE (ADMM-03): the quadratic penalty coefficient (−ρ/2 on pag_j²) is
#   built ONCE; each ADMM iteration mutates ONLY the linear coefficient on pag_j[t] via
#   `set_objective_coefficient(model, pag_j[t], −λ_j[t] − ρ·c_j[t])` (one call per hour).
#   Never model λ_j as a JuMP `Parameter` (indefinite bilinear → Clarabel rejects it,
#   RESEARCH Pitfall 1). Solver via `select_optimizer(QP())` (INFRA-02); gated on
#   `assert_solved!(...; dual=true)` (INFRA-03); App. C battery-complementarity check reused.
#
# No code / no exports yet — Wave 2 owns this seam.
