# src/solver/factory.jl
#
# SEAM: the single solver factory (INFRA-02).
# OWNER: plan 01-03.
#
# This is the ONLY core file (besides the ext/* package extensions) that names
# concrete solvers. `select_optimizer(::ProblemClass)` returns a JuMP-ready
# optimizer factory (`optimizer_with_attributes(...)`). Model files never name a
# solver — they call `Model(select_optimizer(LP()))`. Commercial solvers
# (Gurobi/MosekTools) are reachable ONLY via the weakdep package extensions in
# ext/, which add `commercial_optimizer` methods.
#
# RESEARCH Pitfall 1 correction to the CLAUDE.md perf note (VERIFIED 2026-07-18):
#   Clarabel is a `copy_to`-only solver (`supports_incremental_interface == false`).
#   `direct_model(Clarabel.Optimizer())` ERRORS. Use a standard `Model(...)`
#   (auto-wrapped in a CachingOptimizer) for anything Clarabel-backed. Reserve
#   `direct_model` for HiGHS-backed hot loops only. Do NOT call
#   `direct_model` with any Clarabel-backed factory returned here.

using JuMP
import HiGHS
import Clarabel
import Ipopt

# `output_flag => false` (LP/MILP below): silence HiGHS's per-solve console log, matching
# the factory's existing convention for Clarabel (`verbose => false`) and Ipopt
# (`print_level => 0`). Previously the one unsilenced backend — its raw "Objective value
# ... HiGHS run time" blocks leaked into test logs and into the Documenter-executed
# planning literate pages (Phase 14 review WR-03). Nothing in src/ or test/ depends on
# HiGHS console output. (Comment deliberately sits ABOVE the docstring: a comment BETWEEN
# a docstring and its definition detaches the docstring — verified on Julia 1.12.)
"""
    select_optimizer(pc::ProblemClass)

Return a JuMP-ready optimizer factory (from `optimizer_with_attributes`) for the
given problem class `pc`. Dispatched by singleton type — there is no `if class ==`
branching — so weakdep extensions can extend the commercial path independently.

Open-source defaults:

  - `LP`   → HiGHS (presolve on)
  - `MILP` → HiGHS
  - `QP`   → Clarabel (native quadratic objective)
  - `SOCP` → Clarabel (tight duality-gap tolerances for accurate duals / prices)
  - `NLP`  → Ipopt

A model file uses this as `Model(select_optimizer(LP()))` and never names a solver.
"""
select_optimizer(::LP) =
    optimizer_with_attributes(HiGHS.Optimizer, "presolve" => "on", "output_flag" => false)

select_optimizer(::MILP) =
    optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false)

select_optimizer(::QP) = optimizer_with_attributes(Clarabel.Optimizer, "verbose" => false)

# Tight gap tolerances: transactive prices ARE the duals, so accurate conic duals
# matter. Clarabel's `tol_gap_abs`/`tol_gap_rel` default to 1e-8; set explicitly.
select_optimizer(::SOCP) = optimizer_with_attributes(
    Clarabel.Optimizer,
    "verbose" => false,
    "tol_gap_abs" => 1e-8,
    "tol_gap_rel" => 1e-8,
)

select_optimizer(::NLP) = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0)

"""
    commercial_optimizer(choice, pc::ProblemClass)

Return a JuMP-ready optimizer factory for a commercial solver selected by `choice`
(a [`GurobiChoice`](@ref) or [`MosekChoice`](@ref) marker) for problem class `pc`.

This fallback method ERRORS by design: commercial backends are opt-in and are
wired in only by the `TSODSOGurobiExt` / `TSODSOMosekExt` package extensions,
which add methods for the concrete marker types. To enable one, `import Gurobi`
(or `import MosekTools`) in your environment before calling.
"""
function commercial_optimizer(choice, pc::ProblemClass)
    error(
        """
        No commercial optimizer is available for choice $(choice) and problem class $(pc).
        Commercial solvers are opt-in weakdep extensions and are never hard dependencies.
        To enable one, load the solver in your environment, e.g.:
            import Gurobi      # enables commercial_optimizer(GurobiChoice(), pc)
            import MosekTools  # enables commercial_optimizer(MosekChoice(), pc)
        """,
    )
end

export select_optimizer, commercial_optimizer
