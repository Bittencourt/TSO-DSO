# src/pricing/welfare.jl
#
# SEAM: welfare accounting — social = prosumer + DSO surplus split (PRICE-03).
# OWNER: plan 05-05.
#
# Empty (comment-only) stub wired onto the include graph in plan 05-01. Plan 05-05 fills
# it and declares its own `export`s. It will export:
#   - `welfare_accounting(ctx; T, ...)` — split the social welfare into prosumer surplus and
#     DSO surplus from a solved ctx. Prosumer surplus = Σ_j U_agⱼ − Σ_j Σ_t λ_j[t]·p_agⱼ[t]
#     (thesis eqs. 3.46/3.47), where Σ_j U_agⱼ = value(ctx.meta[:objective]) and the
#     price-transfer term reads the per-aggregator net injection p_agⱼ[t] stashed under
#     `ctx.meta[:agg_net]` (the additive Phase-4 seam from plan 05-01) priced at the DADP
#     λ_j[t]; the surplus-identity (prosumer + DSO == social) is the correctness net.
#
# Consumes ONLY the additive `ctx.meta[:agg_net]` stash + the registered `:balance_p` dual —
# no change to `solve_welfare`. DISTINCT from the Phase-3 operational solve
# (models/welfare_solve.jl): this is post-solve ACCOUNTING, not the optimization.
