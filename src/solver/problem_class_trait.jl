# src/solver/problem_class_trait.jl
#
# SEAM: power-flow → problem-class routing trait.
#
# One tiny Holy-trait function mapping an `AbstractPowerFlow` formulation to the
# mathematical `ProblemClass` its assembly becomes, so `solve_welfare` can pick the
# solver factory by `select_optimizer(problem_class(pf))` WITHOUT any model naming a
# concrete solver and WITHOUT an `if formulation ==` ladder. This file is deliberately included AFTER both `solver/ProblemClass.jl`
# (for `QP`) and the `powerflow/` formulations (for `AbstractPowerFlow`), because it
# dispatches on the abstract power-flow supertype and returns a solver problem class.
#
# The GENERIC default lives here and returns `QP()`: DC and LinDistFlow assemble to a
# convex quadratic program, so they stay on the QP() (Clarabel) backend. The
# `problem_class(::ConvexBranchFlow) = SOCP()` method is added by the SOCP formulation's
# own file, so this generic trait is intentionally decoupled from the
# SOCP formulation — it exists on its own.

"""
    problem_class(pf::AbstractPowerFlow) -> ProblemClass

Map a power-flow formulation `pf` to the mathematical [`ProblemClass`](@ref) of the
optimization model its `contribute!` assembles into, so a solve can route to the right
open-source solver via `select_optimizer(problem_class(pf))` — never naming a concrete
solver and never branching on the formulation type.

The GENERIC fallback returns `QP()`: the active-only DC model and the loss-less
LinDistFlow model assemble (with concave-quadratic device utilities) to a convex
quadratic program, whose default backend is Clarabel. Formulations that introduce a
second-order cone (the SOCP Convex Branch Flow) override this with a more
specific method returning `SOCP()`, which routes to the same Clarabel solver but with
the tight duality-gap tolerances (`tol_gap_abs`/`tol_gap_rel = 1e-8`) the DADP accuracy
and the exactness check depend on.
"""
problem_class(::AbstractPowerFlow) = QP()

