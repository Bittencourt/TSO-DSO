# src/solver/ProblemClass.jl
#
# SEAM: problem-class taxonomy for solver dispatch (INFRA-02).
# OWNER: plan 01-03.
#
# When filled, this file will provide the abstract `ProblemClass` and its sealed
# singleton subtypes (`LP`, `MILP`, `QP`, `SOCP`, `NLP`). Singleton types (not an
# `@enum`) let `select_optimizer` dispatch and let weakdep extensions add methods
# for commercial solvers without editing the core. Declares its own exports.
#
# Intentionally empty in plan 01-01: the package must precompile with this stub.
