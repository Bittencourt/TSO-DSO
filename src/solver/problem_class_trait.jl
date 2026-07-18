# src/solver/problem_class_trait.jl
#
# SEAM: power-flow → problem-class routing trait (INFRA-02 / PF-03).
# OWNER: plan 04-01.
#
# One tiny Holy-trait function mapping an `AbstractPowerFlow` formulation to the
# mathematical `ProblemClass` its assembly becomes, so `solve_welfare` can pick the
# solver factory by `select_optimizer(problem_class(pf))` WITHOUT any model naming a
# concrete solver and WITHOUT an `if formulation ==` ladder (INFRA-02, RESEARCH
# Pattern 5). This file is deliberately included AFTER both `solver/ProblemClass.jl`
# (for `QP`) and the `powerflow/` formulations (for `AbstractPowerFlow`), because it
# dispatches on the abstract power-flow supertype and returns a solver problem class.
#
# The GENERIC default lives here and returns `QP()`: DC and LinDistFlow assemble to a
# convex quadratic program, so they stay on the QP() (Clarabel) backend. The
# `problem_class(::ConvexBranchFlow) = SOCP()` method is added LATER by plan 04-02
# (when the SOC cone lands), so this generic trait is intentionally decoupled from the
# SOCP formulation — it exists on its own and keeps Wave-2 plans file-disjoint.

"""
    problem_class(pf::AbstractPowerFlow) -> ProblemClass

Map a power-flow formulation `pf` to the mathematical [`ProblemClass`](@ref) of the
optimization model its `contribute!` assembles into, so a solve can route to the right
open-source solver via `select_optimizer(problem_class(pf))` — never naming a concrete
solver (INFRA-02) and never branching on the formulation type (RESEARCH Pattern 5).

The GENERIC fallback returns `QP()`: the active-only DC model and the loss-less
LinDistFlow model assemble (with concave-quadratic device utilities) to a convex
quadratic program, whose default backend is Clarabel. Formulations that introduce a
second-order cone (the SOCP Convex Branch Flow, plan 04-02) override this with a more
specific method returning `SOCP()`, which routes to the same Clarabel solver but with
the tight duality-gap tolerances (`tol_gap_abs`/`tol_gap_rel = 1e-8`) the DADP accuracy
and the exactness check depend on.
"""
problem_class(::AbstractPowerFlow) = QP()

export problem_class
