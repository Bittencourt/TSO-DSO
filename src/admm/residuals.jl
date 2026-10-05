# src/admm/residuals.jl
#
# SEAM: AdmmResiduals — the ADMM primal/dual residual ledger (solver diagnostics and
# plottable convergence).
# Carries the adaptive-ρ /
# per-unit-tolerance / price-gap traces. Declares its own `export`s per the include-graph
# convention.
#
# A pure data / bookkeeping type — NO JuMP, NO solves — so both the original (primal-only
# stopping) and the extended (two-residual stop + adaptive-ρ + plotting) loops reuse it, and the
# `TSODSOMakieExt` plotting extension + the validation harness consume it WITHOUT
# pulling JuMP or a solver (a HARD reuse contract).
#
# WHAT IT RECORDS:
#
#     R_{p,j}[t]   = value(pag_j[t]) − value(pag_dso_j[t])   (primal / consensus violation)
#     s^{k}        = ρ · (pag_dso^{k} − pag_dso^{k−1})       (Boyd z-block DUAL residual)
#     ε_pri, ε_dual                                          (per-unit stopping thresholds)
#     ρ, price_gap = ‖λ^{k} − λ^{k−1}‖                       (adaptive schedule + price move)
#
# so `solve_admm` can drive TWO-residual convergence (‖r‖ ≤ ε_pri AND ‖s‖ ≤ ε_dual), plot
# the traces (CairoMakie via the weakdep extension), and fail loud at the maxiter cap.
#
# DUAL-RESIDUAL SEMANTICS (the Boyd-correct form): `dual_trace` now
# stores the Boyd-correct z-block dual residual ‖s‖ = ρ·‖Δ(pag_dso)‖ (the change in the
# SECOND-updated consensus block). The earlier diagnostic ρ·Δa (change in the x-block `a`)
# is SUPERSEDED. The value is written by the EXTENDED `record!`; the
# RETAINED 4-arg `record!` overload keeps an
# older primal-only caller writing a well-formed ledger (it NaN-pads the four new traces).

"""
    AdmmResiduals

A mutable, JuMP-free ledger of an ADMM run's per-iteration residuals + adaptive-ρ /
per-unit-tolerance / price-convergence traces.

Fields:

  - `N::Int`, `T::Int` — the coupling shape (bus count × horizon) the run was sized for; kept
    for diagnostics/plotting context.
  - `primal_trace::Vector{Float64}` — the primal residual `‖r‖` per recorded iteration
    (primal-only form: worst `R_{p,j}[t]`; extended form: the Boyd 2-norm ‖a − pag_dso‖₂).
  - `dual_trace::Vector{Float64}` — the DUAL residual per recorded iteration. The extended form stores
    the Boyd z-block value ‖s‖ = ρ·‖Δ(pag_dso)‖₂ (the correction of the
    earlier ρ·Δa diagnostic).
  - `rho_trace::Vector{Float64}` — the penalty ρ in force at each iteration (shows the
    adaptive-ρ schedule).
  - `eps_pri_trace::Vector{Float64}` — the primal stopping threshold ε_pri per iteration (the
    per-unit threshold line for convergence plots).
  - `eps_dual_trace::Vector{Float64}` — the dual stopping threshold ε_dual per iteration.
  - `price_gap_trace::Vector{Float64}` — the price move `‖λ^{k} − λ^{k−1}‖₂` (or the gap to
    the centralized DADP when known), i.e. the price-convergence trajectory.
  - `iters::Int` — the number of recorded iterations (`== length(primal_trace) == …`).

All six traces are kept EQUAL LENGTH (`== iters`): the EXTENDED [`record!`](@ref) pushes a
value to every trace; the RETAINED primal-only 4-arg [`record!`](@ref) NaN-pads the four new
traces so a primal-only run still yields a length-consistent ledger.

Construct empty via [`AdmmResiduals(N, T)`](@ref) (or [`AdmmResiduals()`](@ref)); append one
iteration with [`record!`](@ref); query convergence with [`converged`](@ref).
"""
mutable struct AdmmResiduals
    N::Int
    T::Int
    primal_trace::Vector{Float64}
    dual_trace::Vector{Float64}
    rho_trace::Vector{Float64}
    eps_pri_trace::Vector{Float64}
    eps_dual_trace::Vector{Float64}
    price_gap_trace::Vector{Float64}
    iters::Int
end

"""
    AdmmResiduals(N::Integer, T::Integer) -> AdmmResiduals

Construct an EMPTY residual ledger sized (for reporting) to an `N`-bus, `T`-hour coupling:
every trace empty and `iters == 0`. Records are appended via [`record!`](@ref).
"""
AdmmResiduals(N::Integer, T::Integer) = AdmmResiduals(
    Int(N),
    Int(T),
    Float64[],
    Float64[],
    Float64[],
    Float64[],
    Float64[],
    Float64[],
    0,
)

"""
    AdmmResiduals() -> AdmmResiduals

Construct an empty, unsized (`N == T == 0`) residual ledger — convenience for callers that
do not need the reporting shape.
"""
AdmmResiduals() = AdmmResiduals(0, 0)

# --- internal: the shared sequential-k fail-loud guard (project throw-on-misuse convention) ---
@inline function _assert_sequential(res::AdmmResiduals, k::Integer)
    expected = res.iters + 1
    k == expected ||
        throw(ArgumentError("record!: expected sequential iteration $expected, got k=$k"))
    return nothing
end

"""
    record!(res, k, primal, dual, ρ, ε_pri, ε_dual, price_gap) -> AdmmResiduals

EXTENDED record: append iteration `k`'s primal residual `‖r‖`, DUAL residual
`‖s‖ = ρ·‖Δ(pag_dso)‖`, penalty `ρ`, per-unit thresholds `ε_pri` /
`ε_dual`, and price move `price_gap = ‖Δλ‖`, incrementing the iteration
count. `k` must be the next sequential iteration (`res.iters + 1`) — a fail-loud guard against
a double-record or a skipped iteration. The residual MAGNITUDES `primal`/`dual` are stored
non-negative (`abs`); `ρ`, `ε_pri`, `ε_dual`, `price_gap` are stored as given (non-negative by
construction). All six traces stay equal length (`== iters`). Returns `res`.
"""
function record!(
    res::AdmmResiduals,
    k::Integer,
    primal::Real,
    dual::Real,
    ρ::Real,
    ε_pri::Real,
    ε_dual::Real,
    price_gap::Real,
)
    _assert_sequential(res, k)
    push!(res.primal_trace, abs(float(primal)))
    push!(res.dual_trace, abs(float(dual)))
    push!(res.rho_trace, float(ρ))
    push!(res.eps_pri_trace, float(ε_pri))
    push!(res.eps_dual_trace, float(ε_dual))
    push!(res.price_gap_trace, float(price_gap))
    res.iters += 1
    return res
end

"""
    record!(res, k, primal_maxabs, dual_maxabs) -> AdmmResiduals

RETAINED primal-only 4-arg record. Append iteration `k`'s
worst primal and dual residual MAGNITUDES and increment the iteration count, NaN-padding the
four extended traces (`rho_trace`, `eps_pri_trace`, `eps_dual_trace`, `price_gap_trace`) with a
`NaN` sentinel so ALL six traces stay equal length (`== iters`).

This overload EXISTS so older primal-only callers (which call the 4-arg form)
keep producing a well-formed ledger. The
`solve_admm` call site uses the extended 8-arg form; both overloads coexist. Same
sequential-`k` fail-loud guard and `abs` non-negativity as the extended method. Returns `res`.
"""
function record!(res::AdmmResiduals, k::Integer, primal_maxabs::Real, dual_maxabs::Real)
    _assert_sequential(res, k)
    push!(res.primal_trace, abs(float(primal_maxabs)))
    push!(res.dual_trace, abs(float(dual_maxabs)))
    # NaN-pad the four extended traces: a primal-only run supplies no ρ / ε / price data, and the
    # sentinel keeps every trace length-consistent without fabricating a real value.
    push!(res.rho_trace, NaN)
    push!(res.eps_pri_trace, NaN)
    push!(res.eps_dual_trace, NaN)
    push!(res.price_gap_trace, NaN)
    res.iters += 1
    return res
end

"""
    converged(res::AdmmResiduals, ε_pri::Real, ε_dual::Real) -> Bool

Two-residual  stopping predicate: `true` iff BOTH the last
recorded primal residual `≤ ε_pri` AND the last recorded dual residual `≤ ε_dual`. Returns
`false` on an empty ledger (nothing recorded ⇒ not yet converged). Stopping on the primal
residual alone is the textbook false-convergence bug, so the dual side is
mandatory here.
"""
function converged(res::AdmmResiduals, ε_pri::Real, ε_dual::Real)
    res.iters == 0 && return false
    return last(res.primal_trace) <= ε_pri && last(res.dual_trace) <= ε_dual
end

"""
    converged(res::AdmmResiduals, tol::Real) -> Bool

RETAINED primal-only stopping rule: `true` iff the LAST recorded primal residual is
`≤ tol`. Returns `false` on an empty ledger. KEPT so older primal-only callers still
compile; the loop itself uses the two-residual [`converged`](@ref) predicate above.
"""
function converged(res::AdmmResiduals, tol::Real)
    res.iters == 0 && return false
    return last(res.primal_trace) <= tol
end

export AdmmResiduals
