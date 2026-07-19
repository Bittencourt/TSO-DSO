# src/admm/residuals.jl
#
# SEAM: AdmmResiduals — the ADMM primal/dual residual ledger (ADMM-01 diagnostics).
# OWNER: plan 06-01 (this plan, Task 2). Declares its own `export`s per the include-graph
# convention.
#
# A pure data / bookkeeping type — NO JuMP, NO solves — so both Phase 6 (primal-only
# stopping) and Phase 7 (dual-residual stop + adaptive-ρ) reuse it UNCHANGED. It records,
# per ADMM iteration, the worst-MAGNITUDE primal and dual residuals of RESEARCH Pattern 2:
#
#     R_{p,j}[t] = value(pag_j[t]) − value(pag_dso_j[t])   (primal / consensus violation)
#     dual residual ≈ ρ · Δ(coupling) across iterations    (the dual-ascent step size)
#
# so `solve_admm` (plan 06-04) can drive convergence, plot the residual traces (CairoMakie),
# and fail loud at the maxiter cap (RESEARCH Pitfall 2). Phase 6 stops on the PRIMAL residual
# only (`converged`); Phase 7 layers the dual-residual stop + adaptive-ρ on the SAME traces.

"""
    AdmmResiduals

A mutable, JuMP-free ledger of an ADMM run's per-iteration residuals (RESEARCH Pattern 2).

Fields:
- `N::Int`, `T::Int` — the coupling shape (bus count × horizon) the run was sized for; kept
  for diagnostics/plotting context (the per-iteration traces are scalar worst-magnitudes, so
  the shape itself is not needed to record, only to report).
- `primal_trace::Vector{Float64}` — the worst `|R_{p,j}[t]|` per recorded iteration.
- `dual_trace::Vector{Float64}`   — the worst dual-residual magnitude `|ρ·Δ(coupling)|` per
  recorded iteration (tracked as a diagnostic in Phase 6; the hard dual-residual stop is Phase 7).
- `iters::Int` — the number of recorded iterations (`== length(primal_trace)`).

Construct empty via [`AdmmResiduals(N, T)`](@ref) (or [`AdmmResiduals()`](@ref)); append one
iteration with [`record!`](@ref); query primal-residual convergence with [`converged`](@ref).
"""
mutable struct AdmmResiduals
    N::Int
    T::Int
    primal_trace::Vector{Float64}
    dual_trace::Vector{Float64}
    iters::Int
end

"""
    AdmmResiduals(N::Integer, T::Integer) -> AdmmResiduals

Construct an EMPTY residual ledger sized (for reporting) to an `N`-bus, `T`-hour coupling:
empty `primal_trace`/`dual_trace` and `iters == 0`. Records are appended via [`record!`](@ref).
"""
AdmmResiduals(N::Integer, T::Integer) = AdmmResiduals(Int(N), Int(T), Float64[], Float64[], 0)

"""
    AdmmResiduals() -> AdmmResiduals

Construct an empty, unsized (`N == T == 0`) residual ledger — convenience for callers that
do not need the reporting shape.
"""
AdmmResiduals() = AdmmResiduals(0, 0)

"""
    record!(res::AdmmResiduals, k::Integer, primal_maxabs::Real, dual_maxabs::Real) -> AdmmResiduals

Append iteration `k`'s worst primal and dual residual MAGNITUDES to `res` and increment its
iteration count. `k` must be the next sequential iteration (`res.iters + 1`) — a fail-loud
guard (project `throw`-on-misuse convention) against a double-record or a skipped iteration.
Both magnitudes are stored as non-negative values (`abs`), matching the `|R_p|` / `|ρ·Δ|`
worst-case definitions of RESEARCH Pattern 2. Returns `res`.
"""
function record!(res::AdmmResiduals, k::Integer, primal_maxabs::Real, dual_maxabs::Real)
    expected = res.iters + 1
    k == expected ||
        throw(ArgumentError("record!: expected sequential iteration $expected, got k=$k"))
    push!(res.primal_trace, abs(float(primal_maxabs)))
    push!(res.dual_trace, abs(float(dual_maxabs)))
    res.iters += 1
    return res
end

"""
    converged(res::AdmmResiduals, tol::Real) -> Bool

`true` iff the LAST recorded primal residual is `≤ tol` (the Phase-6 primal-residual stopping
rule, RESEARCH Pitfall 2). Returns `false` on an empty ledger (nothing recorded ⇒ not yet
converged). The dual residual is intentionally NOT part of this predicate in Phase 6 — the
hard dual-residual stop is layered on in Phase 7; the centralized cross-validation is Phase 6's
true false-convergence net.
"""
function converged(res::AdmmResiduals, tol::Real)
    res.iters == 0 && return false
    return last(res.primal_trace) <= tol
end

export AdmmResiduals, record!, converged
