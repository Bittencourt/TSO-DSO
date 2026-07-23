# src/planning/trace.jl
#
# SEAM: BendersTrace — the Benders convergence ledger (roadmap criterion 2 / PLAN-06
# deepening). A purpose-built per-iteration diagnostics struct for `solve_stackelberg!`,
# explicitly NOT a copy of `src/admm/residuals.jl`'s `AdmmResiduals` dual-ascent
# residual-based stopping criterion (12-PATTERNS.md Pitfall).
# OWNER: plan 12-01.
#
# WHY THIS IS STRUCTURALLY DIFFERENT FROM AdmmResiduals: ADMM's ledger tests TWO
# independent residual norms (a consensus-violation trace and its Boyd z-block
# counterpart) each against its OWN per-unit threshold pair — there is no upper/lower
# bound, only a consensus-violation test. Benders instead bounds a SINGLE primal problem
# from above (an incumbent UB) and below (the relaxed master LB); there is no
# "consensus" to violate. `BendersTrace` therefore records ONE relative-gap scalar per
# iteration (`gap_trace`), never that two-residual pair, and has NO per-unit-threshold
# fields at all — the single tolerance is already `solve_stackelberg!`'s own `tol`
# keyword.
#
# NO JuMP HERE (mirrors `AdmmResiduals` exactly): every field is a primitive
# `Int`/`Float64`/`Symbol` — never a `VariableRef`/`Model` — so this file has zero
# load-time solver dependency and loads as early as `admm/residuals.jl` does.
#
# WHY TWO RETRY-GATED SUBPROBLEM-STATUS COLUMNS BUT NO THIRD (plan-checker warning fix,
# revision 1): `master_status_trace` and `oracle_status_trace` both exist because BOTH
# the master (`solve_master!`) and the oracle (`solve_planning_oracle!`) are gated by
# `solve_with_retry!` (D-08) — a genuine, queryable termination status worth recording
# every time either subproblem actually solves. The follower (`solve_follower!`) has NO
# analogous column: per plan 11-01's contract (CONTEXT.md's Amendment, revision 1), the
# follower is called DIRECTLY, never `solve_with_retry!`-wrapped — its infeasible branch
# must be OBSERVED immediately (the genuine HiGHS Farkas certificate), not retried away.
# `follower_res.feasible`/the Farkas guard already surfaces that outcome synchronously at
# every iteration; there is no retry-gated termination status to parallel `master_status`/
# `oracle_status` with, so no third per-row status column exists here.
#
# WHY `retry_count_trace` IS SOURCED FROM A GENUINE MECHANISM, NEVER A LOG-SCRAPE ESTIMATE
# (plan-checker blocker fix, revision 1): `solve_with_retry!` (`src/planning/retry.jl`)
# gains a non-breaking `attempts_out::Union{Nothing,Ref{Int}}` keyword that the wrapper
# itself sets, on its OWN single successful-return path, to the attempt number (1-indexed)
# the solve succeeded on. `benders.jl` reads that Ref back (`attempts_out[] - 1` = net
# retries beyond the first attempt) and threads it into this ledger's `retry_count_trace`
# — never an assumed constant, never scraped from `@warn` log lines.

"""
    BendersTrace

A mutable, JuMP-free ledger of a Benders run's per-iteration convergence diagnostics
(roadmap criterion 2): one row per `solve_stackelberg!` iteration, on BOTH the
feasibility-cut and optimality-cut branches.

Fields:

  - `iter_trace::Vector{Int}` — the iteration index `k` for each recorded row.
  - `LB_trace::Vector{Float64}` — the Benders master's lower bound at this iteration
    (always a finite LP objective value — no legitimate non-finite state).
  - `UB_trace::Vector{Float64}` — the running incumbent upper bound (`Inf` before any
    optimality iteration has run — a legitimate sentinel, never guarded away).
  - `gap_trace::Vector{Float64}` — the relative UB/LB gap `(UB - LB) / max(1, |UB|)`
    (`NaN` on every feasibility-branch row, and on any row before the first optimality
    iteration — a legitimate sentinel, NOT guarded away; this is the ONE scalar gap
    field, structurally distinct from `AdmmResiduals`'s primal/dual residual pair).
  - `cut_type_trace::Vector{Symbol}` — `:optimality` or `:feasibility`, the branch taken
    at this iteration.
  - `n_cuts_trace::Vector{Int}` — `length(master.cuts)` immediately after this
    iteration's cut was appended (cut-store growth instrumentation, read-only off
    `BendersMaster.cuts`, never a new mutator).
  - `master_status_trace::Vector{Symbol}` — `Symbol(termination_status(master.model))`
    after this iteration's master solve (the master is retry-gated on EVERY iteration).
  - `oracle_status_trace::Vector{Symbol}` — `Symbol(termination_status(oracle.model))`
    on an optimality-branch row (the oracle solved), or the sentinel `:not_solved` on a
    feasibility-branch row (the oracle is never reached, WR-01 ordering) — see the file
    header for why there is no analogous follower column.
  - `retry_count_trace::Vector{Int}` — the NET retries (attempts beyond the first)
    actually consumed at this iteration by whichever retry-gated subproblem(s) ran
    (master-only on the feasibility branch; master + oracle on the optimality branch),
    sourced from `solve_with_retry!`'s own `attempts_out` mechanism (see file header) —
    never an assumed/log-scraped estimate. `0` is the normal, no-retry case.
  - `solve_time_trace::Vector{Float64}` — monotonic-clock (`time_ns`) wall seconds
    spent inside this iteration's solve calls ONLY (master + follower, plus the
    oracle on an optimality-branch row); cut appends, `checkpoint_iteration!`'s
    JLD2/git-provenance I/O, and trace bookkeeping are EXCLUDED (WR-01, phase 12
    review). Non-negative, finite.
  - `iters::Int` — the number of recorded rows (`== length(gap_trace) == …`).

Construct empty via [`BendersTrace()`](@ref); append one row with [`push!`](@ref)
(a `Base.push!` extension, dispatching on `BendersTrace`); query convergence with
[`is_converged`](@ref); summarize with [`trace_summary`](@ref).
"""
mutable struct BendersTrace
    iter_trace::Vector{Int}
    LB_trace::Vector{Float64}
    UB_trace::Vector{Float64}
    gap_trace::Vector{Float64}
    cut_type_trace::Vector{Symbol}
    n_cuts_trace::Vector{Int}
    master_status_trace::Vector{Symbol}
    oracle_status_trace::Vector{Symbol}
    retry_count_trace::Vector{Int}
    solve_time_trace::Vector{Float64}
    iters::Int
end

"""
    BendersTrace() -> BendersTrace

Construct an EMPTY convergence ledger: every trace field `isempty` and `iters == 0`.
Rows are appended via [`push!`](@ref).
"""
BendersTrace() = BendersTrace(
    Int[],
    Float64[],
    Float64[],
    Float64[],
    Symbol[],
    Int[],
    Symbol[],
    Symbol[],
    Int[],
    Float64[],
    0,
)

# --- internal: the shared sequential-k fail-loud guard (mirrors AdmmResiduals's own
# _assert_sequential; a distinct, file-local, non-exported helper — no dispatch
# collision needed) ---
@inline function _assert_sequential_trace(trace::BendersTrace, k::Integer)
    expected = trace.iters + 1
    k == expected ||
        throw(ArgumentError("push!: expected sequential iteration $expected, got k=$k"))
    return nothing
end

"""
    push!(trace::BendersTrace, k::Integer; LB, UB, gap, cut_type, n_cuts,
          master_status, oracle_status = :not_solved, retry_count, solve_time)
        -> BendersTrace

Append ONE new row to `trace`, incrementing `trace.iters`. `k` must be the next
sequential iteration (`trace.iters + 1`) — a fail-loud guard against a double-push or a
skipped iteration, mirroring `AdmmResiduals`'s own `_assert_sequential` idiom.

Guards (each a distinct `ArgumentError`, fired BEFORE any field is mutated):

  - `cut_type in (:optimality, :feasibility)` — any other symbol is rejected.
  - `isfinite(LB)` — `LB` is always a real LP objective value; unlike `UB`/`gap` it has
    no legitimate non-finite state.
  - `isfinite(solve_time) && solve_time >= 0`.
  - `n_cuts >= 0`.
  - `retry_count >= 0` — a count of ACTUAL retries consumed this iteration (see
    `benders.jl`'s instrumentation for exactly how it is computed); `0` is the normal,
    no-retry case, not an edge case to special-case away.

`UB`/`gap` are DELIBERATELY NOT guarded for finiteness: `UB = Inf` (before any
optimality iteration) and `gap = NaN` (every feasibility-branch row) are legitimate
sentinel values, not defects to reject. `oracle_status` needs no additional guard
beyond its `Symbol` type — it is either the sentinel `:not_solved` (feasibility-branch
default) or a genuine termination-status symbol (optimality branch), mirroring
`master_status`'s own unvalidated-`Symbol` treatment.

Returns `trace`.
"""
function Base.push!(
    trace::BendersTrace,
    k::Integer;
    LB::Real,
    UB::Real,
    gap::Real,
    cut_type::Symbol,
    n_cuts::Integer,
    master_status::Symbol,
    oracle_status::Symbol = :not_solved,
    retry_count::Integer,
    solve_time::Real,
)
    _assert_sequential_trace(trace, k)
    cut_type in (:optimality, :feasibility) || throw(
        ArgumentError("push!: cut_type must be :optimality or :feasibility, got $cut_type"),
    )
    # LB is always a real LP objective value — no legitimate non-finite state, unlike
    # UB/gap (see docstring: UB=Inf pre-first-optimality-iteration and gap=NaN on every
    # feasibility-branch row are legitimate sentinels, deliberately NOT guarded here).
    isfinite(LB) || throw(ArgumentError("push!: LB must be finite, got $LB"))
    isfinite(solve_time) && solve_time >= 0 ||
        throw(ArgumentError("push!: solve_time must be finite and >= 0, got $solve_time"))
    n_cuts >= 0 || throw(ArgumentError("push!: n_cuts must be >= 0, got $n_cuts"))
    retry_count >= 0 ||
        throw(ArgumentError("push!: retry_count must be >= 0, got $retry_count"))

    push!(trace.iter_trace, Int(k))
    push!(trace.LB_trace, float(LB))
    push!(trace.UB_trace, float(UB))
    push!(trace.gap_trace, float(gap))
    push!(trace.cut_type_trace, cut_type)
    push!(trace.n_cuts_trace, Int(n_cuts))
    push!(trace.master_status_trace, master_status)
    push!(trace.oracle_status_trace, oracle_status)
    push!(trace.retry_count_trace, Int(retry_count))
    push!(trace.solve_time_trace, float(solve_time))
    trace.iters += 1
    return trace
end

"""
    is_converged(trace::BendersTrace, tol::Real) -> Bool

`true` iff the LAST recorded relative gap is `<= tol`. Returns `false` on an empty
ledger (nothing recorded ⇒ not yet converged) — mirrors `AdmmResiduals.converged`'s
empty-ledger-false + last-row idiom, but reads ONE scalar gap, never a primal/dual
residual pair.
"""
function is_converged(trace::BendersTrace, tol::Real)
    trace.iters == 0 && return false
    return last(trace.gap_trace) <= tol
end

"""
    trace_summary(trace::BendersTrace) -> NamedTuple

Summarize `trace` as `(; iters, final_LB, final_UB, final_gap, max_cuts, total_retries)`. On an empty trace, returns `iters = 0` and all others as `NaN`/`0`
sentinels. Otherwise `final_LB`/`final_UB`/`final_gap` are the LAST recorded row's
values, `max_cuts = maximum(trace.n_cuts_trace)`, and `total_retries = sum(trace.retry_count_trace)` — the EMPIRICAL retry count (plan-checker blocker fix,
revision 1): a plain, always-computed sum over the per-iteration column, never an
aggregate log-scrape estimate.
"""
function trace_summary(trace::BendersTrace)
    trace.iters == 0 && return (;
        iters = 0,
        final_LB = NaN,
        final_UB = NaN,
        final_gap = NaN,
        max_cuts = 0,
        total_retries = 0,
    )
    return (;
        iters = trace.iters,
        final_LB = last(trace.LB_trace),
        final_UB = last(trace.UB_trace),
        final_gap = last(trace.gap_trace),
        max_cuts = maximum(trace.n_cuts_trace),
        total_retries = sum(trace.retry_count_trace),
    )
end

export BendersTrace, is_converged, trace_summary
