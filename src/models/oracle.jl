# src/models/oracle.jl
#
# SEAM: operational_oracle + SEAM-01 extension-interface stubs (OPT-03 / SEAM-01).
# OWNER: plan 04-04.
#
# A thin wrapper over `solve_welfare` exposing the centralized operational solve as
# `operational_oracle(feeder, pf, aggregators; λ₀, T, z, role, objective_hook,
# horizon_state) -> (; cost, π, dadp, ctx)` where `cost` is the GLB-CVX optimum and `π`
# is the frontier coupling dual (the dual of the `z`-pin, else the frontier-node DADP).
# From the PSR planning note the coupling variable is the interconnection flow `z` (≈ the
# aggregator net-import profile `p_ag` / frontier import `p₀`) and `π_s` is the dual of
# the coupling constraint `z_x = z_y` — the z↔p_ag, λ_j↔π_s bridge the planning layer will
# consume (Phase 8/9).
#
# SEAM-01 stub inventory (interfaces only, no extension implemented here):
#   • multi-scenario objective hook  — `objective_hook::Function = identity`     → STOCH (v2)
#   • rolling-horizon parameter       — `horizon_state` + a JuMP `Parameter` slot  → MPC (v2)
#   • meshed-formulation slot         — the `AbstractPowerFlow` seam + a doc note   → MESH-01 (v2)
#   • coupling-flow interface         — `z` kwarg + returned `π` + `role::Symbol`   → PLAN (Ph 8/9)
#
# COMMENT-ONLY STUB — no code, no exports. Filled by plan 04-04 (OPT-03 / SEAM-01).
