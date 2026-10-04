# src/core/errors.jl
#
# SEAM: typed exception hierarchy (ARCH-08 / ARCH-09, phase 34).
#
# `ErrorException` is a concrete struct, so a `SolveFailedError` is NOT an
# `ErrorException`. Catch sites that must keep treating both generations as solver
# failures use `_is_solver_failure`. The "Status & exception policy" docs section is
# the policy home.

using JuMP
const MOI = JuMP.MOI

"""
    TSODSOError <: Exception

Abstract supertype of every typed TSODSO failure (`SolveFailedError`,
`CertificateError`, `ConvergenceError`). Each concrete subtype carries a `msg::String`
and prints exactly that message via `Base.showerror`. Policy home: the
[status & exception policy](@ref status-policy).
"""
abstract type TSODSOError <: Exception end

"""
    SolveFailedError(msg, model) <: TSODSOError

See the [status & exception policy](@ref status-policy).
Policy role: the solver result is untrustworthy (non-optimal termination, missing
primal/dual point). Carries the four solver statuses `termination_status`,
`primal_status`, `dual_status`, `raw_status`. `SolveFailedError(msg)` is a convenience
constructor (test seams) defaulting to `OPTIMIZE_NOT_CALLED`, `NO_SOLUTION`,
`NO_SOLUTION`, `""`.
"""
struct SolveFailedError <: TSODSOError
    msg::String
    termination_status::MOI.TerminationStatusCode
    primal_status::MOI.ResultStatusCode
    dual_status::MOI.ResultStatusCode
    raw_status::String
end

function SolveFailedError(msg::AbstractString, model::Model)
    return SolveFailedError(
        String(msg),
        termination_status(model),
        primal_status(model),
        dual_status(model),
        raw_status(model),
    )
end

function SolveFailedError(msg::AbstractString)
    return SolveFailedError(
        String(msg),
        MOI.OPTIMIZE_NOT_CALLED,
        MOI.NO_SOLUTION,
        MOI.NO_SOLUTION,
        "",
    )
end

"""
    CertificateError(msg; kind = :unspecified) <: TSODSOError

See the [status & exception policy](@ref status-policy).
Policy role: an exactness / no-slack / complementarity certificate was refused.
`kind` is a `Symbol` tagging which certificate failed.
"""
struct CertificateError <: TSODSOError
    msg::String
    kind::Symbol
end
CertificateError(msg::AbstractString; kind::Symbol = :unspecified) =
    CertificateError(String(msg), kind)

"""
    ConvergenceError(msg; iterations = nothing) <: TSODSOError

See the [status & exception policy](@ref status-policy).
Policy role: an iterative method (ADMM, Benders, diagonalization) exhausted its budget
without consensus. `iterations` records the count when known.
"""
struct ConvergenceError <: TSODSOError
    msg::String
    iterations::Union{Nothing,Int}
end
ConvergenceError(msg::AbstractString; iterations::Union{Nothing,Int} = nothing) =
    ConvergenceError(String(msg), iterations)

Base.showerror(io::IO, e::TSODSOError) = print(io, e.msg)

"""
    _is_solver_failure(e) -> Bool

Internal legacy-union predicate: true for a legacy `ErrorException` or any typed
`TSODSOError`. For catch sites that must keep treating both generations as solver failures.
"""
_is_solver_failure(e) = e isa ErrorException || e isa TSODSOError

"""
    STATUS_VOCABULARY

Single source of truth (not exported) for the `status::Symbol` each entry point's result
carries. The status-vs-throw policy page and `test/test_status_policy.jl` both consume it.
`run_mpc`: `:certified` (every step first tier), `:degraded` (a restricted/local-AC step,
none failed), `:cert_failed`. Stackelberg/Nash: `:converged_relaxation_only` iff the UB
certifies only the SOC relaxation.
"""
const STATUS_VOCABULARY = (
    solve_admm = (:converged, :budget_exceeded),
    solve_stackelberg = (:converged, :converged_relaxation_only),
    run_nash = (:converged, :converged_relaxation_only),
    run_mpc = (:certified, :degraded, :cert_failed),
    run_stochastic = (:solved, :oos_infeasible_skipped),
)

export TSODSOError, SolveFailedError, CertificateError, ConvergenceError
