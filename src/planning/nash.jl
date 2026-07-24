# src/planning/nash.jl
#
# SEAM: run_nash! — the outer Gauss-Seidel diagonalization loop over N distributors'
# already-hardened Benders best-responses (NASH-02/03/04). This file grows across two
# plans in this phase: plan 13-02 owns `NashTrace` (this task) and `run_nash!` (Task 2)
# plus `plot_nash_convergence`'s wiring (Task 3); a future plan may add
# `run_nash_probe` (NASH-04's multi-seed/multi-order gate).
# OWNER: plan 13-02 (Tasks 1-2: NashTrace + run_nash!; Task 3 wires plot_nash_convergence
# in src/diagnostics/plots.jl + ext/TSODSOMakieExt.jl, consuming NashTrace from here).
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
using DrWatson: datadir

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

# --- run_nash! — the outer Gauss-Seidel diagonalization loop (NASH-02, plan 13-02 Task 2) ---
#
# THIS IS THE PHASE'S OWN NOVEL ORCHESTRATION LAYER (see this file's header,
# divergence (1)): the loop body IS a full `solve_stackelberg!` call — this function
# builds NO JuMP model, no oracle, no follower, no master of its own. It only:
#   (a) toggles `SharedTransmission`'s bound-pins via `activate_distributor!`/
#       `write_back!` (coupling.jl, plan 13-01),
#   (b) calls `solve_stackelberg!` fresh, once per distributor per sweep, passing a
#       `DistributorView` as the new `follower` keyword (Task 1's additive extension),
#   (c) records the two-level `NashTrace` ledger.
#
# GAUSS-SEIDEL, NEVER JACOBI (13-RESEARCH.md Pitfall 1 / 13-PATTERNS.md's own explicit
# anti-pattern warning): `write_back!` fires IMMEDIATELY after each distributor's
# best-response converges — BEFORE the next distributor in `sweep_order` is processed
# — so a later distributor in the SAME sweep reads its predecessor's JUST-updated
# `z`/`x_inv`, never a stale previous-sweep snapshot. This is regressed both indirectly
# (forward/reverse agreement, testitem 7) and directly (intra-sweep parameter-state
# inspection, testitem 7b).
#
# NESTED-TOLERANCE GUARD (13-CONTEXT.md locked decision / 13-RESEARCH.md Pitfall 2):
# every distributor's own inner Benders `tol` must be STRICTLY TIGHTER than the outer
# `tol_outer`, enforced here as a code-level `ArgumentError` — never merely documented
# — before any solve call. Without this, the outer residual test could "converge" on
# inner-solve noise rather than a genuine fixed point.
#
# CR-01 PARITY (`test_planning_benders.jl`'s own incumbent-consistency regression,
# reused here one level up): `solve_stackelberg!` returns the INCUMBENT `(y_best,
# z_best)`, which may differ from the actual LAST master trial solved against the
# shared model — so `value(shared.x_inv[i])` immediately after `solve_stackelberg!`
# returns is NOT guaranteed to correspond to the incumbent `result_i.z`. This function
# re-solves `solve_follower!(result_i.follower, result_i.z)` immediately after every
# best-response to make the shared model's own state incumbent-consistent BEFORE
# reading `x_inv[i]` or calling `write_back!` — load-bearing, never skip this re-solve.

"""
    run_nash!(specs::AbstractVector{<:NamedTuple}, shared::SharedTransmission;
              z0::AbstractMatrix{<:Real}, tol_outer::Real = 1e-4,
              max_sweeps::Int = 50, order::Symbol = :forward, ω::Real = 1.0,
              checkpoint_dir::AbstractString = datadir("nash_checkpoints")) -> NamedTuple

Run the outer Gauss-Seidel diagonalization loop (NASH-02) over `shared.N` distributors,
each atomic best-response a FULL `solve_stackelberg!` convergence (never a partial
pass) against a fresh, per-distributor `DistributorView` of `shared` (`coupling.jl`,
plan 13-01). Each element of `specs` supplies, per distributor `i`: `feeder`, `pf`,
`aggregators`, `λ₀`, `master_kwargs` (all required — mirrors `solve_stackelberg!`'s own
split), and OPTIONALLY `tol` (default `1e-6`) and `max_iter` (default `100`) via
`get(spec, :tol, 1e-6)`/`get(spec, :max_iter, 100)`.

# Algorithm

Boundary guards BEFORE any solve call (mirrors `solve_stackelberg!`'s own
guards-before-build discipline, each a distinct `ArgumentError`): `length(specs) ==
shared.N`; `size(z0) == (shared.N, shared.T)`; `order in (:forward, :reverse)`;
`max_sweeps >= 1`; `0 < ω <= 1`; `isfinite(tol_outer) && tol_outer > 0`; and the
NESTED-TOLERANCE guard — for every `spec`, `get(spec, :tol, 1e-6) < tol_outer`, naming
the offending distributor index, its own `tol`, and `tol_outer` (13-CONTEXT.md locked,
13-RESEARCH.md Pitfall 2).

For each sweep `k = 1:max_sweeps`, for each distributor `i` in `sweep_order` (`1:N` if
`order === :forward`, `N:-1:1` if `:reverse`):

 1. `activate_distributor!(shared, i)` — restore `i`'s own investment freedom.
 2. `solve_stackelberg!(...; follower = DistributorView(shared, i), follower_kwargs =
    NamedTuple())` — a FRESH oracle/follower/master triple built from scratch inside
    `solve_stackelberg!` (fresh cut store BY CONSTRUCTION, see this file's header).
 3. CR-01 parity re-solve (`solve_follower!(result_i.follower, result_i.z)`), then read
    `x_inv_i_converged = value(shared.x_inv[i])` — see this file's header for why this
    re-solve is load-bearing.
 4. Compute this distributor's own Nash residual: `max(‖z_i^(k+1) - z_i^(k)‖∞,
    |Δx_inv_i|)`.
 5. Compute the (possibly damped) write-back value `z_i_new` (`ω == 1.0` recovers plain
    undamped Gauss-Seidel, the locked default; `ω < 1` damps toward the PREVIOUS `z_i`,
    documented caveat: the written-back `x_inv[i]` is still the UNDAMPED best-response's
    own optimal investment for the UNDAMPED `result_i.z` — acceptable because this
    phase's own fixtures use the default `ω = 1.0`).
 6. `write_back!(shared, i, z_i_new, x_inv_i_converged)` — fires IMMEDIATELY, Gauss-Seidel
    timing (this file's header).
 7. `push!(trace, k, i; ...)` and a checkpoint under a SEPARATE `"outer"` checkpoint
    subdirectory (never colliding with each distributor's own inner Benders checkpoints,
    already nested under `sweep_k/distributor_i`).

After each sweep completes, if the sweep's own worst-distributor residual (the most
recently pushed `shared.N` trace rows) is `<= tol_outer`, returns `(; z, x_inv, UB,
converged = true, sweeps, outer_residual, trace, shared, order)`.

If `max_sweeps` is exhausted without converging, raises a loud `ErrorException` naming
the exhausted sweep count and the LAST recorded `nash_residual` (read from the trace,
never a stale loop-local) — never silently returns a non-converged result.

# Throws

  - `ArgumentError` on any boundary-guard violation (including the nested-tolerance
    guard), before any solve call.
  - `ErrorException` if `max_sweeps` is exhausted without converging.

# Returns

On convergence, `(; z, x_inv, UB, converged = true, sweeps, outer_residual, trace,
shared, order)` where `z::Matrix{Float64}` is `shared.N × shared.T` (each row `i` the
converged coupling flow `z_i`), `x_inv::Vector{Float64}` and `UB::Vector{Float64}` are
length-`shared.N` (each distributor's own converged investment and best-response
incumbent upper bound), `sweeps` is the converged sweep count, `outer_residual` is that
sweep's own worst-distributor residual, `trace::NashTrace` is the full two-level
ledger, `shared` is the (mutated) `SharedTransmission` this run committed its final
state to, and `order` is the sweep order actually used.
"""
function run_nash!(
    specs::AbstractVector{<:NamedTuple},
    shared::SharedTransmission;
    z0::AbstractMatrix{<:Real},
    tol_outer::Real = 1e-4,
    max_sweeps::Int = 50,
    order::Symbol = :forward,
    ω::Real = 1.0,
    checkpoint_dir::AbstractString = datadir("nash_checkpoints"),
)
    # ---- Boundary guards (mirror solve_stackelberg!'s own guards-before-build
    # discipline): fail here, not deep in the sweep loop. ----------------------------
    length(specs) == shared.N || throw(
        ArgumentError(
            "run_nash!: length(specs)=$(length(specs)) must equal shared.N=$(shared.N)",
        ),
    )
    size(z0) == (shared.N, shared.T) || throw(
        ArgumentError(
            "run_nash!: size(z0)=$(size(z0)) must equal (shared.N, shared.T)=" *
            "($(shared.N), $(shared.T))",
        ),
    )
    order in (:forward, :reverse) ||
        throw(ArgumentError("run_nash!: order must be :forward or :reverse, got $order"))
    max_sweeps >= 1 ||
        throw(ArgumentError("run_nash!: max_sweeps must be >= 1, got $max_sweeps"))
    0 < ω <= 1 || throw(ArgumentError("run_nash!: ω must satisfy 0 < ω <= 1, got $ω"))
    isfinite(tol_outer) && tol_outer > 0 || throw(
        ArgumentError("run_nash!: tol_outer must be finite and > 0, got $tol_outer"),
    )
    # NESTED-TOLERANCE guard (13-CONTEXT.md locked, 13-RESEARCH.md Pitfall 2): every
    # distributor's own inner tol must be STRICTLY TIGHTER than the outer tolerance —
    # otherwise the outer residual test could "converge" on inner-solve noise.
    for (idx, spec) in enumerate(specs)
        inner_tol = get(spec, :tol, 1e-6)
        inner_tol < tol_outer || throw(
            ArgumentError(
                "run_nash!: distributor $idx's inner tol=$inner_tol must be strictly " *
                "tighter than tol_outer=$tol_outer (nested-tolerance guard)",
            ),
        )
    end

    z_prev = Matrix{Float64}(z0)
    x_inv_prev = zeros(shared.N)
    trace = NashTrace()
    ub_prev = fill(NaN, shared.N)
    sweep_order = order === :forward ? (1:(shared.N)) : (shared.N:-1:1)

    for k in 1:max_sweeps
        for i in sweep_order
            spec = specs[i]
            activate_distributor!(shared, i)
            result_i = solve_stackelberg!(
                spec.feeder,
                spec.pf,
                spec.aggregators;
                λ₀ = spec.λ₀,
                T = shared.T,
                follower_kwargs = NamedTuple(),
                master_kwargs = spec.master_kwargs,
                tol = get(spec, :tol, 1e-6),
                max_iter = get(spec, :max_iter, 100),
                checkpoint_dir = joinpath(checkpoint_dir, "sweep_$k", "distributor_$i"),
                follower = DistributorView(shared, i),
            )

            # CR-01 parity (load-bearing, do NOT skip): solve_stackelberg! returns the
            # INCUMBENT (y_best, z_best), which may differ from the last master trial
            # actually solved against the shared model — this re-solve makes
            # value(shared.x_inv[i]) correspond to the incumbent result_i.z.
            f_res = solve_follower!(result_i.follower, result_i.z)
            x_inv_i_converged = value(shared.x_inv[i])

            residual_i = max(
                maximum(abs.(result_i.z .- z_prev[i, :])),
                abs(x_inv_i_converged - x_inv_prev[i]),
            )

            z_i_new =
                ω == 1.0 ? result_i.z : (1 - ω) .* z_prev[i, :] .+ ω .* result_i.z

            write_back!(shared, i, z_i_new, x_inv_i_converged)
            z_prev[i, :] = z_i_new
            x_inv_prev[i] = x_inv_i_converged
            ub_prev[i] = result_i.UB

            push!(
                trace,
                k,
                i;
                nash_residual = residual_i,
                benders_iters = result_i.iters,
                benders_gap = result_i.gap,
                benders_retries = trace_summary(result_i.trace).total_retries,
                cuts_rebuilt = length(result_i.master.cuts),
                order = order,
            )
            checkpoint_iteration!(
                (;
                    k,
                    i,
                    z_i = z_i_new,
                    x_inv_i = x_inv_i_converged,
                    nash_residual = residual_i,
                ),
                (k - 1) * shared.N + findfirst(==(i), sweep_order);
                dir = joinpath(checkpoint_dir, "outer"),
            )
        end

        outer_residual_k = maximum(trace.nash_residual_trace[(end - shared.N + 1):end])
        if outer_residual_k <= tol_outer
            # Final re-solve (load-bearing, do NOT skip): the LAST distributor's own
            # write_back! (bound-pinning x_inv[i]) dirties shared.model's solved status
            # (JuMP's CachingOptimizer marks a model unsolved after ANY bound/Parameter
            # mutation) — without this, a caller querying `dual(shared.model[...])` or
            # `value(...)` immediately after this function returns would hit a spurious
            # `OptimizeNotCalled` even though every Parameter/bound is already pinned at
            # its converged, feasible value. This re-solve is cheap (every degree of
            # freedom is already pinned; HiGHS presolves it away) and leaves `shared`
            # in a genuinely solved state consistent with the returned equilibrium.
            optimize!(shared.model)
            return (;
                z = copy(z_prev),
                x_inv = copy(x_inv_prev),
                UB = copy(ub_prev),
                converged = true,
                sweeps = k,
                outer_residual = outer_residual_k,
                trace,
                shared,
                order,
            )
        end
    end

    last_residual = last(trace.nash_residual_trace)
    error(
        "run_nash!: exhausted $max_sweeps sweep(s) without converging (last recorded " *
        "nash_residual=$last_residual, tol_outer=$tol_outer) — refusing to silently " *
        "return a non-converged result",
    )
end

export run_nash!
