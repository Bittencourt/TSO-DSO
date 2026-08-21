# src/solver/ProblemClass.jl
#
# SEAM: problem-class taxonomy for solver dispatch (INFRA-02).
# OWNER: plan 01-03.
#
# A sealed set of problem classes expressed as SINGLETON TYPES under one abstract
# type, so `select_optimizer` selects a solver by multiple dispatch (never an
# `if class == ...` ladder). Singleton types (not an `@enum`) are the idiomatic
# Julia choice here: they let weakdep package extensions (ext/*) add commercial
# `commercial_optimizer` methods without editing this core file.

"""
    ProblemClass

Abstract supertype for the mathematical class of an optimization model. Concrete
singleton subtypes (`LP`, `MILP`, `QP`, `SOCP`, `NLP`) dispatch
[`select_optimizer`](@ref) to the appropriate open-source solver factory. Models
request a solver by problem class only — they never name a concrete solver
(INFRA-02).
"""
abstract type ProblemClass end

"""
Linear program. Default backend: HiGHS. The toy DC walking skeleton lives here.
"""
struct LP <: ProblemClass end

"""
Mixed-integer linear program. Default backend: HiGHS.
"""
struct MILP <: ProblemClass end

"""
Convex quadratic program. Default backend: Clarabel (native quadratic objective).
"""
struct QP <: ProblemClass end

"""
Second-order cone program. Default backend: Clarabel (tight duality-gap tolerances).
"""
struct SOCP <: ProblemClass end

"""
General smooth nonlinear program. Default backend: Ipopt.
"""
struct NLP <: ProblemClass end

"""
    GurobiChoice

Marker type selecting the commercial Gurobi backend via
[`commercial_optimizer`](@ref). The method that maps a `GurobiChoice` to an actual
optimizer is added ONLY by the `TSODSOGurobiExt` package extension, which loads
solely when the user has `Gurobi` in their environment. Gurobi is never a hard
dependency (INFRA-02).
"""
struct GurobiChoice end

"""
    MosekChoice

Marker type selecting the commercial Mosek backend via
[`commercial_optimizer`](@ref). The mapping method is added ONLY by the
`TSODSOMosekExt` package extension. MosekTools is never a hard dependency.
"""
struct MosekChoice end

"""
    SCSChoice

Marker type selecting the open-source, first-order SCS backend via a NEW, SEPARATE
[`alternative_optimizer`](@ref) function — deliberately NEVER `commercial_optimizer`
(D-20). Routing an open-source solver through a dispatch named/documented as
"commercial" would be a semantic mismatch: SCS is opt-in (a weakdep, never a hard
dependency), but it is not a commercial/licensed backend like Gurobi or Mosek. The
mapping method is added ONLY by the `TSODSOSCSExt` package extension, which loads
solely when the user has `SCS` in their environment.
"""
struct SCSChoice end

export ProblemClass, LP, MILP, QP, SOCP, NLP, GurobiChoice, MosekChoice, SCSChoice
