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

`true` iff the MOST RECENT sweep in the ledger is COMPLETE (exactly `N` rows carry the
last recorded sweep index) AND that sweep's own worst-distributor residual is
`<= tol_outer`. The window is selected BY SWEEP INDEX (`trace.sweep_trace .==
last(trace.sweep_trace)`), never by trailing row count — so a mid-sweep call (e.g.
1.5 sweeps recorded, a legitimate state for an external consumer of this exported
generic) can never mix sweep-`k` and sweep-`k-1` residuals into one window; it simply
returns `false` until the sweep completes. Returns `false` on an empty ledger
(`trace.iters == 0`) — empty-ledger-safe, mirroring `BendersTrace`'s own
`is_converged` empty-ledger-false contract (`trace.jl`). Throws `ArgumentError` on
`N < 1` (an invalid sweep width is a caller bug, never a soft `false`).

This method is THE one convergence definition for the outer Gauss-Seidel loop:
`run_nash!` calls it directly (WR-04) rather than re-implementing the window
arithmetic inline, so the exported method and the loop's actual convergence test can
never drift apart.
"""
function is_converged(trace::NashTrace, tol_outer::Real, N::Int)
    N >= 1 || throw(ArgumentError("is_converged: N must be >= 1, got $N"))
    trace.iters == 0 && return false
    mask = trace.sweep_trace .== last(trace.sweep_trace)
    count(mask) == N || return false
    return maximum(trace.nash_residual_trace[mask]) <= tol_outer
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
              z0::AbstractMatrix{<:Real}, x_inv0 = nothing, tol_outer::Real = 1e-4,
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
shared.N`; `size(z0) == (shared.N, shared.T)`; `z0` entrywise finite and `>= 0`
(`x_op >= 0` plus the coupling equality makes a negative seeded flow structurally
infeasible); `order in (:forward, :reverse)`; `max_sweeps >= 1`; `0 < ω <= 1`;
`isfinite(tol_outer) && tol_outer > 0`; the NESTED-TOLERANCE guard — for every `spec`,
`get(spec, :tol, 1e-6) < tol_outer`, naming the offending distributor index, its own
`tol`, and `tol_outer` (13-CONTEXT.md locked, 13-RESEARCH.md Pitfall 2); and the
SEED-CONSISTENCY guards below.

SEEDING THE GAME STATE (CR-01 — load-bearing for NASH-04's multi-seed probe): BEFORE
the first sweep, the seed is COMMITTED into the shared model's own state via
`write_back!(shared, j, z0[j,:], x_inv0[j])` for every distributor `j` — every `z`
Parameter set to its seeded flow AND every `x_inv[j]` bound-pinned at a consistent
seeded investment — so the FIRST best-response of every run genuinely plays against
the seed, never the build-time all-zeros default. Without this, `z0` would only
initialize the residual baseline `z_prev`, every run's first best-response would face
the identical all-zeros state, and the returned equilibrium would be bitwise identical
across seeds — rendering `run_nash_probe`'s seed dimension (NASH-04's honesty gate)
structurally vacuous. `x_inv0` (optional length-`shared.N` vector) supplies the seeded
investments; when omitted (`nothing`, the default) each entry is derived as the
MINIMAL exactly-supporting investment `maximum(z0[j,:]) / shared.corridor_cap`.
Seed-consistency guards (each a distinct `ArgumentError`, before any solve):
`length(x_inv0) == shared.N`; `x_inv0` entrywise finite; `0 <= x_inv0[j] <=
shared.x_inv_max[j]` (per-distributor ceiling — pass an explicit `x_inv0` to spread a
hot seed's support across other distributors' investment instead); and per-`t`
capacity feasibility of the seeded state, `sum(z0[:,t]) <= corridor_cap *
sum(x_inv0)` — otherwise the first best-response would be globally infeasible at the
seed.

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
    undamped Gauss-Seidel, the locked default; `ω < 1` damps toward the PREVIOUS `z_i`).
    With `ω < 1` the follower is RE-SOLVED at the damped `z_i_new` and the MATCHING
    investment is committed — never the undamped best-response's own `x_inv`, whose
    pairing with a damped (possibly larger) committed flow could exceed the pooled
    pinned capacity and render the shared model globally infeasible for the next
    distributor (one extra cheap LP re-solve, only when damping is active).
 6. `write_back!(shared, i, z_i_new, x_inv_i_committed)` — fires IMMEDIATELY, Gauss-Seidel
    timing (this file's header).
 7. `push!(trace, k, i; ...)` and a checkpoint under a SEPARATE `"outer"` checkpoint
    subdirectory (never colliding with each distributor's own inner Benders checkpoints,
    already nested under `sweep_k/distributor_i`).

After each sweep completes, convergence is decided by `is_converged(trace, tol_outer,
shared.N)` — THE one convergence definition (WR-04), never an inline re-implementation
— i.e. the just-completed sweep's own worst-distributor residual is `<= tol_outer`; on
convergence returns `(; z, x_inv, UB, converged = true, sweeps, outer_residual, trace,
shared, order)`.

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
    x_inv0::Union{Nothing,AbstractVector{<:Real}} = nothing,
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

    # ---- SEED-CONSISTENCY guards (CR-01): the seed is about to be COMMITTED into the
    # shared model's own state (below), so it must be a feasible corridor state —
    # fail here, loudly, never as an opaque solver failure inside sweep 1. ----------
    all(isfinite, z0) || throw(ArgumentError("run_nash!: z0 must be entrywise finite"))
    all(>=(0), z0) || throw(
        ArgumentError(
            "run_nash!: z0 must be entrywise >= 0 — x_op >= 0 plus the coupling " *
            "equality makes a negative seeded flow structurally infeasible",
        ),
    )
    x_inv0_vec = if x_inv0 === nothing
        # Default: the MINIMAL per-distributor investment that exactly supports its
        # own seeded flow (z0[j,t] <= corridor_cap * x_inv0[j] for every t).
        [maximum(z0[j, :]) / shared.corridor_cap for j in 1:shared.N]
    else
        length(x_inv0) == shared.N || throw(
            ArgumentError(
                "run_nash!: length(x_inv0)=$(length(x_inv0)) must equal " *
                "shared.N=$(shared.N)",
            ),
        )
        all(isfinite, x_inv0) ||
            throw(ArgumentError("run_nash!: x_inv0 must be entrywise finite"))
        Float64.(collect(x_inv0))
    end
    for j in 1:shared.N
        0.0 <= x_inv0_vec[j] <= shared.x_inv_max[j] + 1e-9 || throw(
            ArgumentError(
                "run_nash!: seeded investment x_inv0[$j]=$(x_inv0_vec[j]) violates " *
                "0 <= x_inv0[$j] <= x_inv_max[$j]=$(shared.x_inv_max[j]) — the " *
                "seeded state must respect distributor $j's own investment ceiling " *
                "(pass an explicit `x_inv0` to spread a hot seed's support across " *
                "other distributors' investment instead)",
            ),
        )
        x_inv0_vec[j] = min(x_inv0_vec[j], shared.x_inv_max[j])
    end
    for t in 1:shared.T
        sum(z0[j, t] for j in 1:shared.N) <=
        shared.corridor_cap * sum(x_inv0_vec) + 1e-9 || throw(
            ArgumentError(
                "run_nash!: seeded state is capacity-infeasible at t=$t: " *
                "sum(z0[:,$t])=$(sum(z0[:, t])) exceeds corridor_cap * sum(x_inv0)" *
                "=$(shared.corridor_cap * sum(x_inv0_vec)) — the first " *
                "best-response would be globally infeasible at this seed",
            ),
        )
    end

    z_prev = Matrix{Float64}(z0)
    x_inv_prev = copy(x_inv0_vec)
    trace = NashTrace()
    ub_prev = fill(NaN, shared.N)
    sweep_order = order === :forward ? (1:(shared.N)) : (shared.N:-1:1)

    # ---- CR-01 (load-bearing, do NOT skip): commit the seed into the shared model's
    # OWN state — every distributor's z Parameter AND a consistent bound-pinned x_inv
    # — so the first best-response of the sweep genuinely plays against the seed, not
    # the build-time all-zeros default. Without this write, the multi-seed dimension
    # of run_nash_probe (NASH-04) is structurally vacuous: every run's trajectory —
    # and returned equilibrium — would be identical regardless of seed.
    # `activate_distributor!` unpins each distributor in turn inside the sweep,
    # exactly as for any later committed state. ---------------------------------------
    for j in 1:shared.N
        write_back!(shared, j, z0[j, :], x_inv0_vec[j])
    end

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
            # WR-01: solve_follower!(::DistributorView, ...) has a documented
            # three-way contract and can return (; feasible = false, v, u) WITHOUT
            # raising. Left unchecked, the infeasible branch would let the next line
            # read value(...) off a solver state with no primal result (an opaque
            # OptimizeNotCalled/no-result error far from the cause) and write_back!
            # would then pin garbage. Fail loudly at the seam instead.
            f_res.feasible || error(
                "run_nash!: CR-01 parity re-solve at incumbent z for distributor " *
                "$i returned infeasible — the shared model's committed state is " *
                "inconsistent with this distributor's own incumbent best-response",
            )
            x_inv_i_converged = value(shared.x_inv[i])

            residual_i = max(
                maximum(abs.(result_i.z .- z_prev[i, :])),
                abs(x_inv_i_converged - x_inv_prev[i]),
            )

            z_i_new =
                ω == 1.0 ? result_i.z : (1 - ω) .* z_prev[i, :] .+ ω .* result_i.z

            # WR-02: with ω < 1 the damped z_i_new differs from the undamped
            # result_i.z that x_inv_i_converged was solved for — committing the
            # inconsistent pair (z damped, x_inv undamped) can exceed the pooled
            # pinned capacity whenever damping moves z upward, rendering the shared
            # model globally infeasible for the NEXT distributor (whose Benders loop
            # would then grind through feasibility cuts two files away from the
            # cause). Re-solve the follower at the ACTUAL committed flow and pin the
            # MATCHING investment — one extra cheap LP solve, only when damping is
            # active.
            if ω == 1.0
                x_inv_i_committed = x_inv_i_converged
            else
                f_damped = solve_follower!(result_i.follower, z_i_new)
                f_damped.feasible || error(
                    "run_nash!: damped write-back flow z_i_new is undeliverable " *
                    "for distributor $i (ω=$ω) — refusing to commit an infeasible " *
                    "(z, x_inv) pair to the shared model",
                )
                x_inv_i_committed = value(shared.x_inv[i])
            end

            write_back!(shared, i, z_i_new, x_inv_i_committed)
            z_prev[i, :] = z_i_new
            x_inv_prev[i] = x_inv_i_committed
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
                    x_inv_i = x_inv_i_committed,
                    nash_residual = residual_i,
                ),
                (k - 1) * shared.N + findfirst(==(i), sweep_order);
                dir = joinpath(checkpoint_dir, "outer"),
            )
        end

        # WR-04: is_converged(trace, ...) is THE one convergence definition — never
        # re-implement its window arithmetic inline, or the exported method and the
        # loop's actual convergence test drift independently. The sweep just
        # completed, so the trailing shared.N rows below ARE exactly is_converged's
        # own by-sweep-index window (reporting only).
        if is_converged(trace, tol_outer, shared.N)
            outer_residual_k =
                maximum(trace.nash_residual_trace[(end - shared.N + 1):end])
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
            # WR-03: fail-loud solve discipline (project-wide — every other solve in
            # this codebase is gated). A fully-pinned model can still terminate
            # non-OPTIMAL on tolerance-level inconsistency between the pinned z
            # Parameters and the pinned x_inv bounds; returning `converged = true`
            # over an untrusted solver state would poison every subsequent
            # value()/dual() query far from the cause.
            is_solved_and_feasible(shared.model) || error(
                "run_nash!: final consistency re-solve of the fully-pinned shared " *
                "model failed (termination_status=" *
                "$(termination_status(shared.model))) — the converged state is " *
                "not mutually feasible",
            )
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

# --- run_nash_probe — multi-seed/multi-order gate + honest spread reporting (NASH-04,
# plan 13-03 Task 1) ---
#
# THIS IS THE HONESTY GATE THE ENTIRE PHASE EXISTS TO IMPLEMENT (STATE.md's own carried
# blocker — Gauss-Seidel Nash diagonalization has NO general uniqueness/convergence
# guarantee): `run_nash_probe` repeats `run_nash!` across a hand-picked matrix of
# initial-`z` seeds x sweep orders, asserts EVERY combination converges (a phase-gating
# regression — a single non-converging probe run must fail loudly, never a soft
# warning), and reports the observed equilibrium SPREAD across runs — never averaging,
# collapsing, or silently presenting one run as "the" equilibrium.
#
# FRESH `SharedTransmission` PER (seed, order) COMBINATION, BY CONSTRUCTION: per this
# file's own `run_nash!` docstring/header, `activate_distributor!`/`write_back!`
# DESTRUCTIVELY mutate a `SharedTransmission`'s variable bounds/Parameters. Reusing ONE
# `shared` object across multiple probe runs would silently carry state (pinned bounds,
# parameter values) from one run into the next, corrupting the "independent probe run"
# premise this function's own gating contract depends on. `build_shared` is therefore a
# ZERO-ARGUMENT FACTORY, called ONCE per (seed, order) pair — never a pre-built instance
# passed in and reused.
#
# NO try/catch AROUND run_nash!, BY DESIGN (T-13-10): a non-converging probe run's
# `ErrorException` (raised internally by `run_nash!` on `max_sweeps` exhaustion) must
# propagate directly out of `run_nash_probe` to the caller — this is the gating
# regression NASH-04's own success criterion requires, not a defect to be caught and
# summarized away as "mostly converged".

"""
    run_nash_probe(specs::AbstractVector{<:NamedTuple}, build_shared::Function;
                   seeds::NamedTuple, orders::Tuple = (:forward, :reverse),
                   tol_outer::Real = 1e-4, max_sweeps::Int = 50,
                   checkpoint_dir::AbstractString = datadir("nash_probe_checkpoints")) ->
    NamedTuple

Probe `run_nash!`'s Gauss-Seidel diagonalization across every `(seed, order)` combination
in the seed/order matrix (NASH-04), asserting EVERY combination converges (a phase-gating
regression — see this section's header) and reporting the observed equilibrium spread —
structurally as "a converged equilibrium (never "the equilibrium"), since Gauss-Seidel
diagonalization carries no general uniqueness guarantee (STATE.md's own carried blocker).

`build_shared` is a ZERO-ARGUMENT closure/function returning a FRESH `SharedTransmission`
(e.g. `() -> build_shared_transmission(; N=2, T=1, ...)`), called ONCE per `(seed, order)`
combination — NEVER reused across combinations. `activate_distributor!`/`write_back!`
(this file's own `run_nash!`, `coupling.jl` plan 13-01) mutate a `SharedTransmission`
DESTRUCTIVELY; reusing one `shared` instance across probe runs would silently leak state
from one run into the next, corrupting the "independent probe run" premise this
function's own gating contract depends on.

Every seed GENUINELY initializes the shared game state (CR-01): `run_nash!` commits each
seed's `z0` — plus the minimal exactly-supporting per-distributor investment — into the
fresh `SharedTransmission` BEFORE its first sweep, so distinct seeds genuinely produce
distinct sweep-1 states. The seed dimension of this probe matrix is live (a
seed-dependent equilibrium IS detectable in the reported spread), never a mere
residual-baseline relabel.

# Boundary guards (before any `run_nash!` call)

  - `length(seeds) >= 3` — CONTEXT.md's locked "≥3 seeds" minimum.
  - `length(orders) >= 2` — CONTEXT.md's locked "2 sweep orders" minimum.
  - every entry of `orders` `in (:forward, :reverse)`.

# Algorithm

For every `(seed_name, seed_z0)` in `pairs(seeds)` crossed with every `order` in `orders`
(`length(seeds) * length(orders) >= 6` combinations): build a FRESH `shared_run =
build_shared()`, call `run_nash!(specs, shared_run; z0 = seed_z0, tol_outer, max_sweeps,
order, checkpoint_dir = joinpath(checkpoint_dir, "\$(seed_name)_\$(order)"))` — with NO
`try`/`catch` around the call (see this section's header; a non-converging run's
`ErrorException` propagates directly out of this function, by design). Collect `(; seed =
seed_name, order, result)` for every combination.

After every combination converges (by construction — any non-convergence already
propagated and exited this function before this point is reached), compute the pairwise
spread over all `n_runs = length(seeds) * length(orders)` collected runs as the MAXIMUM
pairwise distance across every unordered pair (all `binomial(n_runs, 2)` combinations) —
NEVER a mean/variance or other statistical summary that could understate an outlier run
(13-RESEARCH.md Pattern 4's own explicit rationale):

  - `z_spread`: maximum over all pairs of `maximum(abs.(runs[a].result.z .-
    runs[b].result.z))`.
  - `x_inv_spread`: maximum over all pairs of `maximum(abs.(runs[a].result.x_inv .-
    runs[b].result.x_inv))`.
  - `cost_spread`: maximum over all pairs of `abs(sum(runs[a].result.UB) -
    sum(runs[b].result.UB))` (system-level total cost = the sum of every distributor's
    own converged `UB`, already returned by `run_nash!`).

# Returns

`(; runs, spread, summary, n_runs)` where `runs` is the full `Vector` of every individual
`(; seed, order, result)` combination (NEVER averaged/collapsed — retained so a caller can
inspect any individual run), `spread::NamedTuple` is `(; z_spread, x_inv_spread,
cost_spread)`, `summary::String` contains the literal substring `"a converged
equilibrium"` and NEVER the literal substring `"the equilibrium"` (constructed so this is
true BY CONSTRUCTION — no variable is ever interpolated immediately adjacent to the word
"the" directly before "equilibrium"), and `n_runs` is the total probe-run count.

Callers presenting equilibrium results to a human MUST use `summary` (or construct an
equally honest string reporting spread across every run) — never pick `runs[1]` (or any
other single run) and label it definitive. This is NASH-04's own "never present one run as
canonical" mandate, discharged here in code (T-13-08).

# Throws

  - `ArgumentError` if `length(seeds) < 3`, `length(orders) < 2`, or any `orders` entry is
    not `:forward`/`:reverse` — before any `run_nash!` call.
  - `ErrorException`, propagated UNCAUGHT from the underlying `run_nash!` call, if ANY
    `(seed, order)` combination fails to converge within `max_sweeps` (T-13-10 — never
    swallowed or summarized as "mostly converged").
"""
function run_nash_probe(
    specs::AbstractVector{<:NamedTuple},
    build_shared::Function;
    seeds::NamedTuple,
    orders::Tuple = (:forward, :reverse),
    tol_outer::Real = 1e-4,
    max_sweeps::Int = 50,
    checkpoint_dir::AbstractString = datadir("nash_probe_checkpoints"),
)
    # ---- Boundary guards (mirror run_nash!'s own guards-before-solve discipline):
    # fail here, not deep inside the probe matrix. --------------------------------
    length(seeds) >= 3 || throw(
        ArgumentError(
            "run_nash_probe: seeds must contain >= 3 entries (CONTEXT.md's locked " *
            "minimum), got $(length(seeds))",
        ),
    )
    length(orders) >= 2 || throw(
        ArgumentError(
            "run_nash_probe: orders must contain >= 2 entries (CONTEXT.md's locked " *
            "minimum), got $(length(orders))",
        ),
    )
    for order in orders
        order in (:forward, :reverse) || throw(
            ArgumentError(
                "run_nash_probe: every orders entry must be :forward or :reverse, got $order",
            ),
        )
    end

    # ---- Enumerate every (seed, order) combination — each against a FRESH
    # SharedTransmission (see this section's header: never reuse one across runs). ----
    runs = Vector{NamedTuple}()
    for (seed_name, seed_z0) in pairs(seeds)
        for order in orders
            shared_run = build_shared()
            # Deliberately NOT wrapped in a try/rescue block here, BY DESIGN (T-13-10):
            # a non-converging run's ErrorException propagates directly out of
            # run_nash_probe.
            result = run_nash!(
                specs,
                shared_run;
                z0 = seed_z0,
                tol_outer = tol_outer,
                max_sweeps = max_sweeps,
                order = order,
                checkpoint_dir = joinpath(checkpoint_dir, "$(seed_name)_$(order)"),
            )
            push!(runs, (; seed = seed_name, order, result))
        end
    end

    # ---- Every combination converged (by construction) — compute the max-pairwise-
    # distance spread across ALL runs, never a statistical summary. ------------------
    n_runs = length(runs)
    z_spread = maximum(
        maximum(abs.(runs[a].result.z .- runs[b].result.z)) for a in 1:n_runs,
        b in 1:n_runs if a < b
    )
    x_inv_spread = maximum(
        maximum(abs.(runs[a].result.x_inv .- runs[b].result.x_inv)) for a in 1:n_runs,
        b in 1:n_runs if a < b
    )
    cost_spread = maximum(
        abs(sum(runs[a].result.UB) - sum(runs[b].result.UB)) for a in 1:n_runs,
        b in 1:n_runs if a < b
    )
    spread = (; z_spread, x_inv_spread, cost_spread)

    # ---- Structural summary string: "a converged equilibrium" MUST appear, "the
    # equilibrium" MUST NEVER appear — true BY CONSTRUCTION (no variable interpolated
    # immediately adjacent to "the equilibrium"). -------------------------------------
    summary =
        "a converged equilibrium (spread: z=$(round(spread.z_spread; sigdigits = 3)), " *
        "x_inv=$(round(spread.x_inv_spread; sigdigits = 3)), " *
        "cost=$(round(spread.cost_spread; sigdigits = 3))) across $(n_runs) probe run(s) " *
        "($(length(seeds)) seed(s) x $(length(orders)) order(s))"

    return (; runs, spread, summary, n_runs)
end

export run_nash_probe
