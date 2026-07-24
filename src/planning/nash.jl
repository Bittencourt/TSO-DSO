# src/planning/nash.jl
#
# SEAM: run_nash! — the outer Gauss-Seidel diagonalization loop over N distributors'
# already-hardened Benders best-responses (NASH-02/03/04). This file grows across two
# plans in this phase: plan 13-02 owns `NashTrace` (this task) and `run_nash!` (Task 2)
# plus `plot_nash_convergence`'s wiring (Task 3); a future plan may add
# `run_nash_probe` (NASH-04's multi-seed/multi-order gate).
# OWNER (this task's scope): plan 13-02, Task 1.
#
# THREE STRUCTURAL DIVERGENCES FROM THIS FILE'S CLOSEST ANALOGS (state explicitly, in
# prose, per 13-PATTERNS.md's own convention that every new ledger/orchestrator restate
# why it is NOT a copy of its nearest sibling):
#
#  (1) UNLIKE `solve_stackelberg!`'s single-level loop (`benders.jl`), `run_nash!` is an
#      OUTER loop whose body IS a full `solve_stackelberg!` call — this file builds NO
#      JuMP model of its own. Every genuinely new JuMP model this phase needs
#      (`SharedTransmission`) already lives in `coupling.jl` (plan 13-01); `nash.jl` is
#      pure orchestration over `solve_stackelberg!` + `coupling.jl`'s lifecycle
#      functions (`activate_distributor!`/`write_back!`), never a solver call of its own.
#
#  (2) UNLIKE `BendersTrace`'s one-row-per-iteration-`k` granularity, `NashTrace` records
#      ONE ROW PER `(sweep, distributor)` PAIR — i.e., N rows per outer sweep, each
#      embedding that distributor's own Benders best-response summary (final gap,
#      iterations, retries, cut count). This lets `plot_nash_convergence` reconstruct
#      BOTH the outer per-sweep max-residual curve (reduce-by-`max` over
#      `distributor_trace` within a `sweep_trace` group) and the inner per-distributor
#      Benders-gap trajectory from the SAME ledger, without a second parallel struct
#      (13-PATTERNS.md Pattern 3).
#
#  (3) `NashTrace.benders_gap_trace` is ALWAYS finite — UNLIKE `BendersTrace.gap_trace`,
#      which carries a legitimate `NaN` sentinel on every feasibility-cut-branch row.
#      A row is only ever pushed here from a CONVERGED `solve_stackelberg!` result
#      (Task 2's `run_nash!`): a best-response that fails to converge within ITS OWN
#      `max_iter` budget raises loudly INSIDE `solve_stackelberg!` itself (D-10) and
#      never reaches `push!` here — there is no partial/failed-best-response row to
#      record a `NaN` gap for.
#
# FRESH CUT STORE PER BEST-RESPONSE, BY CONSTRUCTION (CONTEXT.md's locked
# "correctness-first" decision; the full cut-invalidation math argument is embedded
# verbatim in `coupling.jl`'s own header, plan 13-01): `run_nash!` (Task 2) NEVER
# persists a `BendersMaster`/cut store across best-responses. Every call to
# `solve_stackelberg!` builds its own `oracle`/`follower`/`master` from scratch
# (`benders.jl`'s own "BUILD ONCE, outside the [Benders] loop" discipline still holds —
# it is just that `run_nash!`'s OWN loop calls `solve_stackelberg!` fresh every time, so
# a NEW oracle/follower/master triple is built on every single best-response). Cut
# validity across a changing `z_{-i}` is therefore guaranteed BY CONSTRUCTION, not by a
# runtime check — see `coupling.jl`'s header for why a stale cut computed at old
# `z_{-i}` can be actively WRONG (not merely loose) for the new `V_i(·; z_{-i}^{new})`.

using JuMP

# --- internal: the shared sequential-push!-guard idiom (mirrors `trace.jl`'s own
# `_assert_sequential_trace` for `BendersTrace`) is DELIBERATELY NOT reused here:
# `NashTrace`'s natural incrementing key is the row count itself (`trace.iters`), not a
# caller-supplied `k` — `k` (the outer sweep index) can legitimately repeat across
# different distributors `i` within the SAME sweep, so a sequential-`k` guard would
# reject valid Gauss-Seidel rows. No guard on `k`/`i` themselves beyond their own
# semantic guards (`order`, non-negative counts) below.

"""
    NashTrace

A mutable, JuMP-free two-level convergence ledger (NASH-03) for `run_nash!`'s outer
Gauss-Seidel sweep: ONE ROW PER `(sweep, distributor)` PAIR (see this file's header,
divergence (2), for why this is NOT `BendersTrace`'s one-row-per-iteration shape).

Fields:

  - `sweep_trace::Vector{Int}` — the outer sweep index `k` for this row.
  - `distributor_trace::Vector{Int}` — which distributor `i` this row's best-response
    belongs to.
  - `nash_residual_trace::Vector{Float64}` — this distributor's own Nash residual at
    this sweep (`max(‖z_i^(k+1) - z_i^(k)‖∞, |Δx_inv_i|)`, `run_nash!`'s own formula,
    Task 2). NOT guarded for finiteness (see below).
  - `benders_iters_trace::Vector{Int}` — the embedded inner-loop summary:
    `result.iters` from this distributor's `solve_stackelberg!` best-response.
  - `benders_gap_trace::Vector{Float64}` — the embedded inner-loop summary:
    `result.gap`. ALWAYS finite (see this file's header, divergence (3)) — NOT
    guarded for finiteness, since a `NaN`/`Inf` here would only arise from a
    `solve_stackelberg!` internal bug already covered by Phase 11/12's own regression
    suite (mirrors `BendersTrace.UB_trace`'s own "legitimate-but-not-contractually-
    guaranteed" precedent, `trace.jl`'s header).
  - `benders_retries_trace::Vector{Int}` — the embedded inner-loop summary:
    `trace_summary(result.trace).total_retries`.
  - `cuts_rebuilt_trace::Vector{Int}` — instrumented per CONTEXT.md's own "surface the
    rebuild-cost finding, don't silently retain" decision: `length(result.master.cuts)`,
    the number of cuts this best-response's FRESH master accumulated before converging
    (every best-response starts this count at 0 — see this file's header).
  - `order_trace::Vector{Symbol}` — `:forward`/`:reverse`, which sweep order this row
    belongs to (needed for a future multi-order probe, NASH-04, to slice its own trace
    back out of a shared ledger).
  - `iters::Int` — the number of recorded rows (`== length(sweep_trace) == …`).

Construct empty via [`NashTrace()`](@ref); append one row with [`push!`](@ref) (a
`Base.push!` extension dispatching on `NashTrace`); query convergence with
[`is_converged`](@ref) and summarize with [`trace_summary`](@ref) — both ADD new
methods to the SAME generic functions `trace.jl` already exports for `BendersTrace`
(multiple dispatch), so this file does NOT re-`export` those two names.
"""
mutable struct NashTrace
    sweep_trace::Vector{Int}
    distributor_trace::Vector{Int}
    nash_residual_trace::Vector{Float64}
    benders_iters_trace::Vector{Int}
    benders_gap_trace::Vector{Float64}
    benders_retries_trace::Vector{Int}
    cuts_rebuilt_trace::Vector{Int}
    order_trace::Vector{Symbol}
    iters::Int
end

"""
    NashTrace() -> NashTrace

Construct an EMPTY two-level convergence ledger: every trace field `isempty` and
`iters == 0`. Rows are appended via [`push!`](@ref).
"""
NashTrace() = NashTrace(Int[], Int[], Float64[], Int[], Float64[], Int[], Int[], Symbol[], 0)

"""
    push!(trace::NashTrace, k::Integer, i::Integer; nash_residual, benders_iters,
          benders_gap, benders_retries, cuts_rebuilt, order) -> NashTrace

Append ONE new row to `trace` (one `(sweep, distributor)` pair), incrementing
`trace.iters`. UNLIKE `BendersTrace`'s `push!`, there is NO sequential-`k` guard (see
this file's top-level comment: the natural incrementing key is the row count itself,
and `k` legitimately repeats across distributors within one sweep).

Guards (each a distinct `ArgumentError`, fired BEFORE any field is mutated):

  - `order in (:forward, :reverse)` — any other symbol is rejected.
  - `benders_iters >= 0`.
  - `benders_retries >= 0`.
  - `cuts_rebuilt >= 0`.

`nash_residual`/`benders_gap` are DELIBERATELY NOT guarded for finiteness: both are
always finite in this project's own usage (see the struct docstring), but the ledger
itself makes no contractual promise about it — mirroring `BendersTrace.UB_trace`'s own
unguarded-sentinel precedent (`trace.jl`).

Returns `trace`.
"""
function Base.push!(
    trace::NashTrace,
    k::Integer,
    i::Integer;
    nash_residual::Real,
    benders_iters::Integer,
    benders_gap::Real,
    benders_retries::Integer,
    cuts_rebuilt::Integer,
    order::Symbol,
)
    order in (:forward, :reverse) ||
        throw(ArgumentError("push!: order must be :forward or :reverse, got $order"))
    benders_iters >= 0 ||
        throw(ArgumentError("push!: benders_iters must be >= 0, got $benders_iters"))
    benders_retries >= 0 ||
        throw(ArgumentError("push!: benders_retries must be >= 0, got $benders_retries"))
    cuts_rebuilt >= 0 ||
        throw(ArgumentError("push!: cuts_rebuilt must be >= 0, got $cuts_rebuilt"))

    push!(trace.sweep_trace, Int(k))
    push!(trace.distributor_trace, Int(i))
    push!(trace.nash_residual_trace, float(nash_residual))
    push!(trace.benders_iters_trace, Int(benders_iters))
    push!(trace.benders_gap_trace, float(benders_gap))
    push!(trace.benders_retries_trace, Int(benders_retries))
    push!(trace.cuts_rebuilt_trace, Int(cuts_rebuilt))
    push!(trace.order_trace, order)
    trace.iters += 1
    return trace
end

"""
    is_converged(trace::NashTrace, tol_outer::Real, N::Int) -> Bool

`true` iff at least one full sweep (`N` rows) has been recorded AND the most recently
completed sweep's own worst-distributor residual is `<= tol_outer`:
`maximum(trace.nash_residual_trace[(end - N + 1):end]) <= tol_outer`. Returns `false`
on `trace.iters < N` (not even one full sweep recorded yet) — empty-ledger-safe, never
throws, mirroring `BendersTrace`'s own `is_converged` empty-ledger-false contract
(`trace.jl`).
"""
function is_converged(trace::NashTrace, tol_outer::Real, N::Int)
    trace.iters < N && return false
    return maximum(trace.nash_residual_trace[(end - N + 1):end]) <= tol_outer
end

"""
    trace_summary(trace::NashTrace) -> NamedTuple

Summarize `trace` as `(; iters, final_sweep, final_residual, max_benders_iters,
total_benders_retries, total_cuts_rebuilt)`. On an empty trace (`trace.iters == 0`),
returns `(; iters = 0, final_sweep = 0, final_residual = NaN, max_benders_iters = 0,
total_benders_retries = 0, total_cuts_rebuilt = 0)` — empty-ledger-safe, never throws,
mirroring `BendersTrace.trace_summary`'s own sentinel contract (`trace.jl`).
Otherwise `final_sweep`/`final_residual` are the LAST recorded row's own values,
`max_benders_iters = maximum(trace.benders_iters_trace)`, `total_benders_retries =
sum(trace.benders_retries_trace)`, `total_cuts_rebuilt = sum(trace.cuts_rebuilt_trace)`
— plain, always-computed sums/maxima over the per-row columns, never a log-scrape
estimate (mirrors `BendersTrace.trace_summary`'s own `total_retries` discipline).
"""
function trace_summary(trace::NashTrace)
    trace.iters == 0 && return (;
        iters = 0,
        final_sweep = 0,
        final_residual = NaN,
        max_benders_iters = 0,
        total_benders_retries = 0,
        total_cuts_rebuilt = 0,
    )
    return (;
        iters = trace.iters,
        final_sweep = last(trace.sweep_trace),
        final_residual = last(trace.nash_residual_trace),
        max_benders_iters = maximum(trace.benders_iters_trace),
        total_benders_retries = sum(trace.benders_retries_trace),
        total_cuts_rebuilt = sum(trace.cuts_rebuilt_trace),
    )
end

export NashTrace
