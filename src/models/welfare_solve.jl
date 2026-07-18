# src/models/welfare_solve.jl
#
# SEAM: GLB-CVX centralized social-welfare solve (OPT-01).
# OWNER: plan 03-05.
#
# Generalizes `linear_solve.jl` to a multi-aggregator centralized welfare
# maximization over the Phase-2 LinDistFlow model at horizon T=24 (thesis eq.
# 3.38). Assembles each aggregator's :Rp/:Rq injections and utility, adds a
# non-negative priced frontier import p_import[t] and a FREE-SIGN reactive frontier
# q_import[t] at feeder.root (the WR-03 fix -- without it, pinning :Rq at every bus
# with reactive load present is infeasible), closes the nodal-balance residuals to
# zero, and maximizes welfare = sum(aggregator utility) - sum_t lambda0[t]*p_import[t]
# as a convex QP via `select_optimizer(QP())` (Clarabel; no model names a solver).
# Gated on OPTIMAL via `assert_solved!`, then runs the mandatory post-solve battery
# complementarity check (p_ch*p_dch < tau, App. C). Because every device utility is
# concave and the LinDistFlow constraints are affine, the local optimum is global.
# Declares its own `export`s when plan 03-05 fills it; comment-only stub until then.
