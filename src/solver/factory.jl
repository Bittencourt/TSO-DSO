# src/solver/factory.jl
#
# SEAM: the single solver factory (INFRA-02).
# OWNER: plan 01-03.
#
# When filled, this is the ONLY core file that names concrete solvers. It will
# provide `select_optimizer(::ProblemClass)` returning a JuMP-ready optimizer
# factory (`optimizer_with_attributes(...)`): HiGHS for LP/MILP, Clarabel for
# QP/SOCP, Ipopt for NLP. Model files never name a solver — they call
# `Model(select_optimizer(LP()))`. Commercial solvers (Gurobi/MosekTools) are
# added ONLY via the weakdep package extensions in ext/. Declares its own exports.
#
# RESEARCH Pitfall 1 correction to the CLAUDE.md perf note:
#   Clarabel is a `copy_to`-only solver (`supports_incremental_interface == false`).
#   `direct_model(Clarabel.Optimizer())` ERRORS. Use a standard `Model(...)`
#   (auto-wrapped in a CachingOptimizer) for anything Clarabel-backed. Reserve
#   `direct_model` for HiGHS-backed hot loops only.
#
# Intentionally empty in plan 01-01: the package must precompile with this stub.
