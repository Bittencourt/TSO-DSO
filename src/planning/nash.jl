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
NashTrace() =
    NashTrace(Int[], Int[], Float64[], Int[], Float64[], Int[], Int[], Symbol[], 0)

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
`<= tol_outer`. The window is selected BY SWEEP INDEX (`trace.sweep_trace .== last(trace.sweep_trace)`), never by trailing row count — so a mid-sweep call (e.g.
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

Summarize `trace` as `(; iters, final_sweep, final_residual, max_benders_iters, total_benders_retries, total_cuts_rebuilt)`. On an empty trace (`trace.iters == 0`),
returns `(; iters = 0, final_sweep = 0, final_residual = NaN, max_benders_iters = 0, total_benders_retries = 0, total_cuts_rebuilt = 0)` — empty-ledger-safe, never throws,
mirroring `BendersTrace.trace_summary`'s own sentinel contract (`trace.jl`).
Otherwise `final_sweep`/`final_residual` are the LAST recorded row's own values,
`max_benders_iters = maximum(trace.benders_iters_trace)`, `total_benders_retries = sum(trace.benders_retries_trace)`, `total_cuts_rebuilt = sum(trace.cuts_rebuilt_trace)`
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
    _integer_alpha_x_lb(shared::SharedTransmission, i::Int, y_max::Real) -> Float64

A valid lower bound on distributor `i`'s follower cost slice
`c_inv[i]·x_inv[i] + Σₜ c_op[i][t]·x_op[i,t]` for `run_nash!`'s integer path (Phase 31
code review, WR-06): `x_inv[i] ∈ [0, x_inv_max[i]]` and `x_op[i,t] = z[i,t] ∈ [0, y_max]`
(the master box `z <= y_inv <= y_max`), so each term is bounded below by
`min(0, coefficient) × its upper bound`. Exactly `0.0` when every cost is nonnegative —
the previous hard-coded default — and still valid when a cost is negative, where `0.0`
would make the integer master's `L = α_op_lb + α_x_lb` an invalid floor.
"""
function _integer_alpha_x_lb(shared::SharedTransmission, i::Int, y_max::Real)
    return min(0.0, shared.c_inv[i]) * shared.x_inv_max[i] +
           sum(min(0.0, shared.c_op[i][t]) * Float64(y_max) for t in 1:(shared.T))
end

"""
    _integer_cycle_hit(history, joint_b, state, residual; atol) -> Union{Nothing, Int}

The integer-diagonalization cycle predicate of [`run_nash!`](@ref) (Phase 31 code
review, CR-01). `history` holds one `(; sweep, joint_b, state, residual)` entry per
earlier completed sweep, where `state = vcat(vec(z), x_inv)` is the FULL committed
continuous state and `residual` is that sweep's worst-distributor Nash residual.
Returns the `sweep` of the first entry that the current sweep REPEATS, or `nothing`.

An entry is repeated only when ALL three hold:

 1. the joint binary state is identical (exact `Vector{Int}` equality — binaries are
    exact);
 2. the committed continuous state recurs, `maximum(abs.(state .- h.state)) <= atol`;
 3. there was no progress at all, `residual >= h.residual` — NO tolerance slack: any
    strict residual decrease between the matched sweeps vetoes the match (iteration-2
    review, CR-01).

Why the binaries alone are NOT a cycle (the bug this predicate fixes): binaries
routinely settle sweeps before `z`/`x_inv` do, so a `b`-only key flagged every
converging run that needed three or more sweeps with a stable `b` — reproduced with
damping `ω = 0.5`, where the residual halves each sweep at a fixed `b`. Condition 2
rejects such runs when consecutive sweeps move the committed state by more than
`atol`, and condition 3 rejects every trajectory whose residual strictly decreased
between the matched sweeps (the residual of a genuine cycle recurs; that of a
converging run decreases). The same lesson as Phase 24's own inner stall guard
(`apply_integer_cuts!`): a revisit with materially different continuous state is
refinement progress, never a stall.

Why condition 3 carries NO `atol` slack (iteration-2 review, CR-01): `history` is
scanned for ANY earlier sweep, not just the previous one, so condition 2 alone does not
separate a converging run from a recurrence. An OSCILLATORY contraction — committed
state `s_k = s* + c^k e` with `c ∈ (-1, 0)`, which a negative-slope Gauss-Seidel sweep
map produces when free-riding on pooled capacity makes one player's best response
decrease in the other's committed state — returns close to its value two sweeps earlier:
`|s_k - s_{k-2}| = (1 - c²)|s_{k-2} - s*|`, and the residual drops by only `(1 - c²)·r_{k-2}`.
Near the end of a run both fall under `atol` for `|c| ≳ 0.82` at `ω = 1`; with the former
`residual >= h.residual - atol` slack the production predicate reported a false cycle on
the synthetic `c = -0.9` history (sweep 44 matching sweep 42) of a run that converges six
sweeps later. Requiring `residual >= h.residual` exactly removes that false positive: on
a contracting trajectory the residual strictly decreases. A genuine cycle whose
recurring residuals differ by inner-solve noise may now go undetected — a missed
detection is safe (it still fails loudly at `max_sweeps`), a false one is not.

`run_nash!` passes `atol = ω * tol_outer / 2`, a recurrence tolerance for the committed
state, not a guaranteed separation: on a non-converged sweep at least one distributor's
residual exceeds `tol_outer`, but only the committed `z` is damped by `ω` — `x_inv` is
RE-SOLVED at the damped `z` (bound-pinned), not interpolated — so when the residual is
`x_inv`-dominated even consecutive sweeps need not differ by `atol`. Condition 3 (not
condition 2) is what keeps such sweeps from being flagged. A genuine cycle whose
recurring states differ by more than `atol` (inner-solve noise, measured ~2–3e-4) is NOT
detected here either; again it fails loudly at `max_sweeps`.

Ties caveat: the potential-game argument in [`run_nash!`](@ref)'s docstring ("Cycle
detection") rules out cycles of exact best responses only ABSENT TIES — a recurrent
state requires every move in the loop to be a tie (ΔΦ = Δcost_i = 0). The interior-cap
fixtures have tied, degenerate best responses, so ties are not hypothetical here; this
predicate is the guard for exactly that case.
"""
function _integer_cycle_hit(
    history::AbstractVector,
    joint_b::AbstractVector{<:Integer},
    state::AbstractVector{<:Real},
    residual::Real;
    atol::Real,
)
    for h in history
        h.joint_b == joint_b || continue
        length(h.state) == length(state) || continue
        maximum(abs.(state .- h.state)) <= atol || continue
        residual >= h.residual || continue  # no slack: any decrease = progress (CR-01, iter 2)
        return h.sweep
    end
    return nothing
end

"""
    run_nash!(specs::AbstractVector{<:NamedTuple}, shared::SharedTransmission;
              z0::AbstractMatrix{<:Real}, x_inv0 = nothing, tol_outer::Real = 1e-4,
              max_sweeps::Int = 50, order::Symbol = :forward, ω::Real = 1.0,
              checkpoint_dir::AbstractString = datadir("nash_checkpoints"),
              inexact_policy::Symbol = :strict) -> NamedTuple

Run the outer Gauss-Seidel diagonalization loop (NASH-02) over `shared.N` distributors,
each atomic best-response a FULL `solve_stackelberg!` convergence (never a partial
pass) against a fresh, per-distributor `DistributorView` of `shared` (`coupling.jl`,
plan 13-01). Each element of `specs` supplies, per distributor `i`: `feeder`, `pf`,
`aggregators`, `λ₀`, `master_kwargs` (all required — mirrors `solve_stackelberg!`'s own
split), and OPTIONALLY `tol` (default `1e-6`) and `max_iter` (default `100`) via
`get(spec, :tol, 1e-6)`/`get(spec, :max_iter, 100)`.

**GNE-multiplicity caveat (Phase 31, BILEV-06).** This loop converges to A generalized
Nash equilibrium (GNE) of the shared-constraint game, not necessarily the UNIQUE one —
on a fixture whose shared capacity row is the only binding coupling (interior individual
investment caps), a whole continuum of GNEs can exist (see [`run_nash_probe`](@ref)'s
own docstring for the full derivation and `test/test_planning_nash.jl`'s interior-cap
fixture). For a GNE whose shared-row multiplier is IDENTICAL across every player (a
variational equilibrium, VE), use [`solve_variational_equilibrium`](@ref) instead — a
single monolithic joint solve, not a diagonalization. The VE is unique only when the
joint problem's optimum is (e.g. asymmetric `c_inv`); on the symmetric interior-cap
fixture the VE set is the whole split segment `x_inv_1 + x_inv_2 = 0.7`, `z = (0.7, 0.7)`
(non-unique, solver-dependent point), and the GNE set is STRICTLY larger — it also
contains free-riding GNEs `x_inv_j = 0`, `z_j = 1.2 − p`, `p ∈ [0, 0.5]`, with unequal
multipliers (see that function's docstring).

**`inexact_policy` (Phase 30 code review iteration 2, CR-01).** Forwarded UNCHANGED to
every inner `solve_stackelberg!` best response. It defaults to `:strict` here, NOT to
`solve_stackelberg!`'s own `:certify_incumbent` default: before Phase 30 every inner
best response threw at the first SOCP-inexact oracle solve, and a Nash sweep must keep
that fail-loud guarantee unless the caller opts out explicitly. With a non-`:strict`
policy an inner best response can certify only the SOC relaxation
(`result_i.ub_relaxation_only`). That is never committed silently: every best
response's exactness certificate is collected on the returned `certificates` vector,
and `any_relaxation_only` flags the run as a whole (see Returns). On a formulation with
no cone (DC/LinDistFlow, every pre-Phase-30 Nash fixture) the policy has no effect.

# Algorithm

Boundary guards BEFORE any solve call (mirrors `solve_stackelberg!`'s own
guards-before-build discipline, each a distinct `ArgumentError`): `length(specs) == shared.N`; `size(z0) == (shared.N, shared.T)`; `z0` entrywise finite and `>= 0`
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
`length(x_inv0) == shared.N`; `x_inv0` entrywise finite; `0 <= x_inv0[j] <= shared.x_inv_max[j]` (per-distributor ceiling — pass an explicit `x_inv0` to spread a
hot seed's support across other distributors' investment instead); and per-`t`
capacity feasibility of the seeded state, `sum(z0[:,t]) <= corridor_cap * sum(x_inv0)` — otherwise the first best-response would be globally infeasible at the
seed.

For each sweep `k = 1:max_sweeps`, for each distributor `i` in `sweep_order` (`1:N` if
`order === :forward`, `N:-1:1` if `:reverse`):

 1. `activate_distributor!(shared, i)` — restore `i`'s own investment freedom.
 2. `solve_stackelberg!(...; follower = DistributorView(shared, i), follower_kwargs = NamedTuple())` — a FRESH oracle/follower/master triple built from scratch inside
    `solve_stackelberg!` (fresh cut store BY CONSTRUCTION, see this file's header).
 3. CR-01 parity re-solve (`solve_follower!(result_i.follower, result_i.z)`), then read
    `x_inv_i_converged = value(shared.x_inv[i])` — see this file's header for why this
    re-solve is load-bearing.
 4. Compute distributor `i`'s Nash residual `residual_i = max(‖z_i^(k+1) − z_i^(k)‖∞,
    |Δx_inv_i|)` against its previously COMMITTED `(z_i, x_inv_i)`.
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

After each sweep completes, convergence is decided by `is_converged(trace, tol_outer, shared.N)` — THE one convergence definition (WR-04), never an inline re-implementation
— i.e. the just-completed sweep's own worst-distributor residual is `<= tol_outer`; on
convergence returns `(; z, x_inv, UB, converged = true, sweeps, outer_residual, trace, shared, order)`.

If `max_sweeps` is exhausted without converging, raises a loud `ErrorException` naming
the exhausted sweep count and the LAST recorded `nash_residual` (read from the trace,
never a stale loop-local) — never silently returns a non-converged result.

# Throws

  - `ArgumentError` on any boundary-guard violation (including the nested-tolerance
    guard, an `inexact_policy` outside `(:strict, :reject, :certify_incumbent)`, or an
    `integer` kwarg whose `K` is not a positive `Integer`, whose `α_op_lb` is not
    `:auto` or a finite `Real`, or whose `α_x_lb` is not a finite `Real`), before any
    solve call.
  - `ErrorException` if `max_sweeps` is exhausted without converging, OR (Phase 31,
    BILEV-07, `integer !== nothing` only) if the integer diagonalization cycles (the
    full committed state — joint binary state, `z` and `x_inv` — recurs across sweeps
    with no residual decrease, without converging) — reports the full cycle shape (see
    "Cycle detection" below).

# Returns

On convergence, `(; z, x_inv, UB, converged = true, sweeps, outer_residual, trace, shared, order)` where `z::Matrix{Float64}` is `shared.N × shared.T` (each row `i` the
converged coupling flow `z_i`), `x_inv::Vector{Float64}` and `UB::Vector{Float64}` are
length-`shared.N` (each distributor's own converged investment and best-response
incumbent upper bound), `sweeps` is the converged sweep count, `outer_residual` is that
sweep's own worst-distributor residual, `trace::NashTrace` is the full two-level
ledger, `shared` is the (mutated) `SharedTransmission` this run committed its final
state to, and `order` is the sweep order actually used.

Two trailing, additive certificate fields (Phase 30 code review iteration 2, CR-01):
`certificates::Vector{NamedTuple}` has one row per best response actually solved, in
solve order, `(; sweep, distributor, incumbent_exactness, incumbent_socp_maxgap, ub_relaxation_only, ac_report)` copied from that `solve_stackelberg!` result; and
`any_relaxation_only::Bool` is `true` iff any best response of ANY sweep (not only the
final one) certified the SOC relaxation only. Under the default `inexact_policy = :strict` it is always `false` (an inexact solve throws instead).

**`integer` (Phase 31, BILEV-07).** `Union{Nothing, NamedTuple} = nothing`. When supplied
(e.g. `integer = (; K = 4)`), every distributor's best response in the
sweep loop uses a FRESH [`build_master_integer`](@ref) (binary-expansion MILP master,
`K` binary blocks, that distributor's own `spec.master_kwargs.c_y`/`y_max` reused)
instead of the continuous `BendersMaster` — built fresh every single best response
(never persisted across best responses or sweeps, mirroring this file's own "fresh cut
store per best-response, by construction" header discipline). `α_op_lb` defaults to
`:auto` (`get(integer, :α_op_lb, :auto)`), derived via the SAME `bounds_ctx` machinery
`build_master`/`solve_stackelberg!` already use (`(; feeder, pf, aggregators, λ₀,
follower_kwargs = nothing)` — `DistributorView`'s pooled-capacity coupling has no sound
per-object relaxed minimum, the SAME accepted, documented skip the continuous path
already uses). `α_x_lb` defaults (WR-06, Phase 31 code review) to the bound DERIVED from
the follower cost's signs, `min(0, c_inv[i])·x_inv_max[i] + Σₜ min(0, c_op[i][t])·y_max`
(`_integer_alpha_x_lb`; `0.0` for nonnegative costs) — a valid lower bound on
distributor `i`'s cost slice whatever the signs, so `L = α_op_lb + α_x_lb` stays a valid
Laporte-Louveaux floor; an explicit `integer.α_x_lb` is the caller's responsibility.
Guards BEFORE any solve call: `integer.K` a positive `Integer`; `integer.α_op_lb` (if
supplied) `:auto` or a finite `Real`; `integer.α_x_lb` (if supplied) a finite `Real` (no
`:auto` on this path — omit it for the derived default); NaN/±Inf/other values raise an
`ArgumentError` (WR-02, Phase 31 code review iteration 2); `integer` keys within `(:K, :α_op_lb, :α_x_lb)`; and every
`spec.master_kwargs` supplying `c_y`/`y_max` and NOTHING else — an `α_op_lb`/`α_x_lb`
placed in `master_kwargs` (which the continuous path honours) is rejected with an
`ArgumentError` pointing at `integer`, never silently ignored. When `integer === nothing` (the default), the
continuous path is BYTE-IDENTICAL to every pre-Phase-31 call (this kwarg's mere
presence/default never touches the existing `master_kwargs = spec.master_kwargs` call).

**Cycle detection (Phase 31, BILEV-07; corrected by the Phase-31 code review, CR-01),
active only when `integer !== nothing`.** Each distributor's own converged binary
investment state `b_i` (recovered EXACTLY from `result_i.y` via the lattice step
`spec.master_kwargs.y_max / 2^K`, `Base.digits`) is accumulated, in FIXED canonical
distributor order `1:shared.N` (independent of `sweep_order`), into a joint state
`joint_b` at the end of every sweep, together with the FULL committed continuous state
`(vec(z), x_inv)` and the sweep's worst-distributor residual. A cycle is reported only
when the whole committed state recurs — identical `joint_b`, continuous state within
`ω·tol_outer/2`, and no strict residual decrease (no slack) — on a sweep that has not converged (the
predicate and its tolerance argument: `_integer_cycle_hit`). The binaries alone are
NOT the game state: they routinely settle before `z`/`x_inv` do, and a `b`-only key
raised false "CYCLED" errors on runs that were still converging (e.g. any damped
`ω < 1` run). On a detected cycle `run_nash!` raises a loud, NAMED `ErrorException`
reporting the sweep first seen, the current sweep and every distributor's own `b`, `z`
and `x_inv` — never silently continuing toward `max_sweeps`.

Limitation, stated honestly: no live cycling instance exists in the test suite. With
objectives separable except through the shared row, each best response lowers the
mover's own cost and leaves every other player's cost unchanged, so the summed cost is
a generalized exact potential (ΔΦ = Δcost_i ≤ 0) that exact Gauss-Seidel best
responses cannot cycle on ABSENT TIES: a recurrent state needs every move in the loop to
be a tie. That caveat is material — the interior-cap fixtures have tied, degenerate best
responses — and inner-solve noise is a second escape. The predicate is therefore
regression-tested directly on synthetic converging (monotone damped AND sign-flipping
oscillatory contraction) and cycling histories, and live on a damped converging run that
the old `b`-only key wrongly rejected (`test/test_planning_nash_integer.jl`).
"""
function run_nash!(
    specs::AbstractVector{<:NamedTuple},
    shared::SharedTransmission;
    z0::AbstractMatrix{<:Real},
    x_inv0::Union{Nothing, AbstractVector{<:Real}} = nothing,
    tol_outer::Real = 1e-4,
    max_sweeps::Int = 50,
    order::Symbol = :forward,
    ω::Real = 1.0,
    checkpoint_dir::AbstractString = datadir("nash_checkpoints"),
    inexact_policy::Symbol = :strict,
    integer::Union{Nothing, NamedTuple} = nothing,
)
    # ---- Boundary guards (mirror solve_stackelberg!'s own guards-before-build
    # discipline): fail here, not deep in the sweep loop. ----------------------------
    # CR-01 (Phase 30 code review iteration 2): validated HERE, before any solve, so a
    # typo never surfaces from inside the first best response.
    inexact_policy in (:strict, :reject, :certify_incumbent) || throw(
        ArgumentError(
            "run_nash!: inexact_policy must be :strict, :reject or :certify_incumbent, " *
            "got $(repr(inexact_policy))",
        ),
    )
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
    isfinite(tol_outer) && tol_outer > 0 ||
        throw(ArgumentError("run_nash!: tol_outer must be finite and > 0, got $tol_outer"))
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

    # BILEV-07 (Phase 31, plan 31-04): the `integer` kwarg's own boundary guard, before
    # any solve call — mirrors this function's own guards-before-build discipline.
    if integer !== nothing
        (haskey(integer, :K) && integer.K isa Integer && integer.K >= 1) || throw(
            ArgumentError(
                "run_nash!: integer.K must be a positive Integer, got " *
                "$(get(integer, :K, nothing))",
            ),
        )
        # WR-02 (Phase 31 code review iteration 2): validate BOTH epigraph bounds here,
        # before any solve. `α_op_lb` is forwarded to `build_master_integer`, whose
        # explicit-bound branch would accept NaN (`NaN > optimum + slack` is false; then
        # `min(NaN, bound) === NaN` is installed) and install -Inf (surfacing only after
        # a full inner Benders loop as `add_ll_cut!`'s "L must be finite"). `α_x_lb`
        # accepts no `:auto` on this path: a `DistributorView` follower has no
        # derivation (`bounds_ctx.follower_kwargs = nothing`); omit the key to get the
        # sign-derived default `_integer_alpha_x_lb`.
        a_op = get(integer, :α_op_lb, :auto)
        (a_op === :auto || (a_op isa Real && isfinite(a_op))) || throw(
            ArgumentError(
                "run_nash!: integer.α_op_lb must be :auto or a finite Real, got " *
                "$(repr(a_op))",
            ),
        )
        if haskey(integer, :α_x_lb)
            a_x = integer.α_x_lb
            (a_x isa Real && isfinite(a_x)) || throw(
                ArgumentError(
                    "run_nash!: integer.α_x_lb must be a finite Real (no :auto — a " *
                    "DistributorView follower has no derivation; omit the key for the " *
                    "sign-derived default), got $(repr(a_x))",
                ),
            )
        end
        # WR-06 (Phase 31 code review): never silently ignore a caller's input. The
        # integer branch reads ONLY c_y/y_max from each spec's master_kwargs and only
        # K/α_op_lb/α_x_lb from `integer`; anything else (notably an α bound placed in
        # master_kwargs, which the continuous path would honour) is rejected here.
        bad_int = setdiff(keys(integer), (:K, :α_op_lb, :α_x_lb))
        isempty(bad_int) || throw(
            ArgumentError(
                "run_nash!: unsupported integer key(s) $(collect(bad_int)) — integer " *
                "accepts only K, α_op_lb, α_x_lb",
            ),
        )
        for (idx, spec) in enumerate(specs)
            mk = spec.master_kwargs
            (haskey(mk, :c_y) && haskey(mk, :y_max)) || throw(
                ArgumentError(
                    "run_nash!: distributor $idx's master_kwargs must supply c_y and " *
                    "y_max on the integer path",
                ),
            )
            bad_mk = setdiff(keys(mk), (:c_y, :y_max))
            isempty(bad_mk) || throw(
                ArgumentError(
                    "run_nash!: distributor $idx's master_kwargs carries " *
                    "$(collect(bad_mk)), which the integer path does not read — the " *
                    "integer master takes only c_y and y_max from master_kwargs; pass " *
                    "epigraph bounds as `integer = (; K, α_op_lb, α_x_lb)` instead",
                ),
            )
        end
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
        sum(z0[j, t] for j in 1:shared.N) <= shared.corridor_cap * sum(x_inv0_vec) + 1e-9 ||
            throw(
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
    # CR-01 (Phase 30 code review iteration 2): one exactness certificate per best
    # response, so a relaxation-only best response is never committed silently.
    certificates = NamedTuple[]
    sweep_order = order === :forward ? (1:(shared.N)) : (shared.N:-1:1)
    # BILEV-07 (Phase 31, plan 31-04; CR-01 of the Phase-31 code review): cycle
    # bookkeeping, active only when integer !== nothing. One entry per completed sweep:
    # the joint binary state (the concatenation, in FIXED canonical distributor order
    # 1:shared.N, of every distributor's own exact b::Vector{Int}), the FULL committed
    # continuous state (vec(z), x_inv) and the sweep's worst-distributor residual. A
    # cycle is flagged only when ALL of the committed state recurs without progress —
    # see `_integer_cycle_hit` and this function's own docstring.
    cycle_history = NamedTuple{
        (:sweep, :joint_b, :state, :residual),
        Tuple{Int, Vector{Int}, Vector{Float64}, Float64},
    }[]
    cycle_atol = ω * tol_outer / 2

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
        # BILEV-07: a fresh per-sweep buffer for this sweep's joint binary state,
        # indexed by distributor i (FIXED canonical order 1:shared.N, independent of
        # sweep_order) — only populated when integer !== nothing.
        integer_buffer =
            integer === nothing ? nothing : Vector{Vector{Int}}(undef, shared.N)
        for i in sweep_order
            spec = specs[i]
            activate_distributor!(shared, i)
            # BILEV-07 (Phase 31, plan 31-04): when integer !== nothing, every
            # distributor's best response builds a FRESH build_master_integer (never
            # persisted across best responses or sweeps, mirroring this file's own
            # "fresh cut store per best-response" discipline) and passes it via
            # solve_stackelberg!'s existing master= keyword; master_kwargs MUST then be
            # empty (D-08's own mutual-exclusivity guard). The continuous
            # (integer === nothing) branch is BYTE-IDENTICAL to before this kwarg
            # existed.
            result_i = if integer === nothing
                solve_stackelberg!(
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
                    # CR-01: :strict by default — the pre-Phase-30 fail-loud semantics.
                    inexact_policy = inexact_policy,
                )
            else
                imaster = build_master_integer(;
                    T = shared.T,
                    K = integer.K,
                    c_y = spec.master_kwargs.c_y,
                    y_max = spec.master_kwargs.y_max,
                    α_op_lb = get(integer, :α_op_lb, :auto),
                    # WR-06: the default is DERIVED from the cost signs, never an
                    # assumed 0.0 (see `_integer_alpha_x_lb`).
                    α_x_lb = get(
                        integer,
                        :α_x_lb,
                        _integer_alpha_x_lb(shared, i, spec.master_kwargs.y_max),
                    ),
                    bounds_ctx = (;
                        feeder = spec.feeder,
                        pf = spec.pf,
                        aggregators = spec.aggregators,
                        λ₀ = spec.λ₀,
                        follower_kwargs = nothing,
                    ),
                )
                solve_stackelberg!(
                    spec.feeder,
                    spec.pf,
                    spec.aggregators;
                    λ₀ = spec.λ₀,
                    T = shared.T,
                    follower_kwargs = NamedTuple(),
                    master_kwargs = NamedTuple(),
                    tol = get(spec, :tol, 1e-6),
                    max_iter = get(spec, :max_iter, 100),
                    checkpoint_dir = joinpath(checkpoint_dir, "sweep_$k", "distributor_$i"),
                    follower = DistributorView(shared, i),
                    master = imaster,
                    # CR-01: :strict by default — the pre-Phase-30 fail-loud semantics.
                    inexact_policy = inexact_policy,
                )
            end
            if integer !== nothing
                # BILEV-07: recover distributor i's own exact binary state from the
                # incumbent y_inv on the lattice (see this function's own docstring —
                # corner_recourse/ll_cut_recourse guarantee the incumbent sits EXACTLY
                # on the lattice for the integer path).
                step_i = spec.master_kwargs.y_max / 2.0^integer.K
                idx_i = round(Int, result_i.y / step_i)
                # IN-05 (Phase 31 code review): never decode an off-lattice or
                # out-of-range y — `digits(...; pad = K)` silently returns MORE than K
                # digits for idx >= 2^K, which would corrupt the joint state key. The
                # tolerance is the MIP integrality tolerance (1e-6) propagated through
                # y = Σ_k step·2^(k-1)·b_k: at most step·(2^K − 1)·1e-6 < 1e-6·y_max.
                (
                    abs(result_i.y - idx_i * step_i) <= 1e-6 * spec.master_kwargs.y_max &&
                    0 <= idx_i < 2^integer.K
                ) || error(
                    "run_nash!: distributor $i's integer best response y=$(result_i.y) " *
                    "is not on the K=$(integer.K) lattice (step=$step_i, idx=$idx_i) — " *
                    "cannot recover its binary state",
                )
                integer_buffer[i] = digits(idx_i; base = 2, pad = integer.K)
            end
            push!(
                certificates,
                (;
                    sweep = k,
                    distributor = i,
                    incumbent_exactness = result_i.incumbent_exactness,
                    incumbent_socp_maxgap = result_i.incumbent_socp_maxgap,
                    ub_relaxation_only = result_i.ub_relaxation_only,
                    ac_report = result_i.ac_report,
                ),
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

            z_i_new = ω == 1.0 ? result_i.z : (1 - ω) .* z_prev[i, :] .+ ω .* result_i.z

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
        sweep_converged = is_converged(trace, tol_outer, shared.N)

        # BILEV-07 (Phase 31, plan 31-04; CR-01 of the Phase-31 code review): cycle
        # detection, active only when integer !== nothing. The key is the FULL
        # committed state, never the binaries alone: binaries routinely settle sweeps
        # before the continuous z/x_inv do (e.g. under damping ω < 1 the residual
        # halves every sweep while b stays fixed), so a b-only key raised false
        # "CYCLED" errors on runs that were still converging. Never reported on the
        # very sweep that converges.
        if integer !== nothing
            joint_b = vcat(integer_buffer...)
            state_k = vcat(vec(z_prev), x_inv_prev)
            residual_k = maximum(trace.nash_residual_trace[(end - shared.N + 1):end])
            if !sweep_converged
                first_seen = _integer_cycle_hit(
                    cycle_history,
                    joint_b,
                    state_k,
                    residual_k;
                    atol = cycle_atol,
                )
                if first_seen !== nothing
                    error(
                        "run_nash!: integer diagonalization CYCLED — the full " *
                        "committed state (joint binary state $joint_b, z, x_inv) " *
                        "recurred at sweep $k (first seen at sweep $first_seen, " *
                        "state atol=$cycle_atol) with no residual decrease " *
                        "(residual=$residual_k, tol_outer=$tol_outer); " *
                        "per-distributor states at the repeat: " *
                        join(
                            [
                                "i=$i: b=$(integer_buffer[i]), z=$(z_prev[i, :]), " *
                                "x_inv=$(x_inv_prev[i])" for i in 1:shared.N
                            ],
                            ", ",
                        ) *
                        " — refusing to silently continue toward max_sweeps",
                    )
                end
            end
            push!(
                cycle_history,
                (; sweep = k, joint_b, state = state_k, residual = residual_k),
            )
        end

        if sweep_converged
            outer_residual_k = maximum(trace.nash_residual_trace[(end - shared.N + 1):end])
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
            is_solved_and_feasible(shared.model) || throw(SolveFailedError(
                "run_nash!: final consistency re-solve of the fully-pinned shared " *
                "model failed (termination_status=" *
                "$(termination_status(shared.model))) — the converged state is " *
                "not mutually feasible",
                shared.model,
            ))
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
                # CR-01 (Phase 30 code review iteration 2): trailing, additive.
                certificates,
                any_relaxation_only = any(c -> c.ub_relaxation_only, certificates),
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
                   checkpoint_dir::AbstractString = datadir("nash_probe_checkpoints"),
                   inexact_policy::Symbol = :strict) ->
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

**Seed shape (Phase 31, BILEV-06a): bare matrix OR `(; z0, x_inv0)` NamedTuple.** Each
entry of `seeds` is EITHER a bare `z0::AbstractMatrix{<:Real}` (the original, unchanged
shape every pre-Phase-31 caller uses) OR a `(; z0, x_inv0)` NamedTuple that ALSO supplies
`run_nash!`'s own `x_inv0` keyword. This is additive and backward-compatible: a bare
matrix forwards `x_inv0 = nothing` to `run_nash!`, which is byte-identical to every
pre-Phase-31 call. **Why this extension is necessary** (31-RESEARCH.md's own "CRITICAL
FINDING", restated here): `run_nash!`'s DEFAULT `x_inv0` derivation
(`maximum(z0[j,:])/corridor_cap`, used whenever `x_inv0` is omitted) always seeds the
MINIMAL exactly-supporting investment for whatever `z0` is chosen — by construction this
default has ZERO slack, so on a shared-constraint game whose continuum of generalized Nash
equilibria (GNE) lives entirely in how the pooled investment is SPLIT (not in the flow
`z` itself, which sits at the same unconstrained optimum everywhere on the continuum), the
first mover in Gauss-Seidel always ends up "alone" at its own exact marginal need,
regardless of which `z0` or sweep order is probed. Varying `z0` alone is therefore
STRUCTURALLY INCAPABLE of exposing this specific kind of GNE multiplicity — not a
fixture-tuning problem, a probe-API gap. Supplying an explicit, non-minimal `x_inv0` per
seed is the ONLY way to land distinct probe runs on distinct points of an investment-split
continuum.

# Boundary guards (before any `run_nash!` call)

  - `length(seeds) >= 3` — CONTEXT.md's locked "≥3 seeds" minimum.
  - `length(orders) >= 2` — CONTEXT.md's locked "2 sweep orders" minimum.
  - every entry of `orders` `in (:forward, :reverse)`.

# Algorithm

For every `(seed_name, seed_z0)` in `pairs(seeds)` crossed with every `order` in `orders`
(`length(seeds) * length(orders) >= 6` combinations): dispatch `seed_z0` on `seed_z0 isa NamedTuple` — a bare matrix forwards `z0 = seed_z0, x_inv0 = nothing` (unchanged
behavior); a `(; z0, x_inv0)` NamedTuple forwards `z0 = seed_z0.z0, x_inv0 = get(seed_z0, :x_inv0, nothing)`. Build a FRESH `shared_run = build_shared()`, call `run_nash!(specs, shared_run; z0 = z0_arg, x_inv0 = x_inv0_arg, tol_outer, max_sweeps, order, checkpoint_dir = joinpath(checkpoint_dir, "\$(seed_name)_\$(order)"))` — with NO
`try`/`catch` around the call (see this section's header; a non-converging run's
`ErrorException` propagates directly out of this function, by design). Collect `(; seed = seed_name, order, result)` for every combination. `inexact_policy` is forwarded
to every `run_nash!` call (default `:strict`, Phase 30 code review iteration 2, CR-01);
each run's own `certificates`/`any_relaxation_only` stay on its `result`.

After every combination converges (by construction — any non-convergence already
propagated and exited this function before this point is reached), compute the pairwise
spread over all `n_runs = length(seeds) * length(orders)` collected runs as the MAXIMUM
pairwise distance across every unordered pair (all `binomial(n_runs, 2)` combinations) —
NEVER a mean/variance or other statistical summary that could understate an outlier run
(13-RESEARCH.md Pattern 4's own explicit rationale):

  - `z_spread`: maximum over all pairs of `maximum(abs.(runs[a].result.z .- runs[b].result.z))`.
  - `x_inv_spread`: maximum over all pairs of `maximum(abs.(runs[a].result.x_inv .- runs[b].result.x_inv))`.
  - `cost_spread`: maximum over all pairs of `abs(sum(runs[a].result.UB) - sum(runs[b].result.UB))` (system-level total cost = the sum of every distributor's
    own converged `UB`, already returned by `run_nash!`).

**On an investment-split GNE continuum (Phase 31, BILEV-06a), `z_spread` near-zero while
`x_inv_spread` is large is a CORRECT, EXPECTED property of that continuum — never a probe
bug.** On such a game every point of the continuum pairs the SAME unconstrained-optimum
flow `z` with a DIFFERENT split of the pooled investment `x_inv`; a caller probing this
kind of fixture with `(; z0, x_inv0)`-shaped seeds spanning the split should expect exactly
this asymmetric spread pattern and must not treat a small `z_spread` there as a sign the
seed dimension failed to vary.

# Returns

`(; runs, spread, summary, n_runs)` where `runs` is the full `Vector` of every individual
`(; seed, order, result)` combination (NEVER averaged/collapsed — retained so a caller can
inspect any individual run), `spread::NamedTuple` is `(; z_spread, x_inv_spread, cost_spread)`, `summary::String` contains the literal substring `"a converged equilibrium"` and NEVER the literal substring `"the equilibrium"` (constructed so this is
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
    inexact_policy::Symbol = :strict,
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
        # Phase 31 (BILEV-06a) seed dispatch: a bare matrix (every pre-Phase-31 caller)
        # forwards x_inv0 = nothing, byte-identical to before this dispatch existed; a
        # `(; z0, x_inv0)` NamedTuple forwards BOTH to run_nash!, whose own `x_inv0`
        # keyword already exists — see this function's own docstring for WHY the
        # z0-only default seed cannot expose an investment-split GNE continuum.
        z0_arg, x_inv0_arg =
            seed_z0 isa NamedTuple ? (seed_z0.z0, get(seed_z0, :x_inv0, nothing)) :
            (seed_z0, nothing)
        for order in orders
            shared_run = build_shared()
            # Deliberately NOT wrapped in a try/rescue block here, BY DESIGN (T-13-10):
            # a non-converging run's ErrorException propagates directly out of
            # run_nash_probe.
            result = run_nash!(
                specs,
                shared_run;
                z0 = z0_arg,
                x_inv0 = x_inv0_arg,
                tol_outer = tol_outer,
                max_sweeps = max_sweeps,
                order = order,
                checkpoint_dir = joinpath(checkpoint_dir, "$(seed_name)_$(order)"),
                inexact_policy = inexact_policy,   # CR-01: forwarded, :strict default
            )
            push!(runs, (; seed = seed_name, order, result))
        end
    end

    # ---- Every combination converged (by construction) — compute the max-pairwise-
    # distance spread across ALL runs, never a statistical summary. ------------------
    n_runs = length(runs)
    z_spread = maximum(
        maximum(abs.(runs[a].result.z .- runs[b].result.z)) for
        a in 1:n_runs, b in 1:n_runs if a < b
    )
    x_inv_spread = maximum(
        maximum(abs.(runs[a].result.x_inv .- runs[b].result.x_inv)) for
        a in 1:n_runs, b in 1:n_runs if a < b
    )
    cost_spread = maximum(
        abs(sum(runs[a].result.UB) - sum(runs[b].result.UB)) for
        a in 1:n_runs, b in 1:n_runs if a < b
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

# --- solve_variational_equilibrium — monolithic joint model selecting the variational
# equilibrium (VE) inside a shared-constraint game's GNE continuum (BILEV-06b, plan 31-03
# Task 2) ---
#
# WHY A MONOLITHIC JOINT SOLVE, NOT A DECOMPOSITION (31-RESEARCH.md's own GNE-structure
# argument, restated here): the shared-transmission game is a textbook Rosen (1965)
# shared-constraint game — every player's own problem is individually convex, objectives
# are STRICTLY additively separable (no cross-player term anywhere — confirmed by direct
# read of `build_shared_transmission`'s own objective and each distributor's own
# oracle/master), and the ONLY place any player's variables appear in another player's
# constraint is the ONE shared pooled `capacity[t]` row. For this class, the variational
# equilibria (the GNEs whose shared-row multiplier is IDENTICAL across every player) are
# EXACTLY the solutions of the single joint optimization problem that writes the shared
# row ONCE instead of `N` times (Rosen's own normalized-equilibrium construction at
# uniform player weights) — no iterative algorithm is needed to CHARACTERIZE the VE, only
# to iterate toward a GNE when a direct joint solve is intractable at scale (out of scope
# here; `run_nash!` remains the iterative path).
#
# UNIQUENESS IS NOT AUTOMATIC (Phase 31 code review, CR-02): Rosen's uniqueness theorem
# needs diagonal strict concavity, which a game LINEAR in `x_inv` lacks. The VE is
# unique iff the joint problem's optimum is. On the symmetric interior-cap fixture
# (`c_inv = [1, 1]`) the joint objective depends on `x_inv` only through `Σᵢ x_inv[i]`,
# the optimal face is the whole split segment `x_inv_1 + x_inv_2 = 0.7`, `z = (0.7, 0.7)`,
# every point of which carries the common multiplier 0.5 — that segment IS the VE set,
# and the solve returns a solver-dependent point of it (Clarabel's IPM: the analytic
# centre). The GNE set there is STRICTLY larger: it also contains free-riding GNEs off
# the segment (`x_inv_j = 0`, `z_j = 1.2 − p`, `p ∈ [0, 0.5]`, `x_inv_i = (1.9 − p)/2`;
# e.g. `x_inv = (0.95, 0)`, `z = (0.7, 1.2)`, multipliers `(0.5, ≈0)`) with UNEQUAL
# multipliers, which the VE excludes — so the VE still selects, just not a single
# point (iteration-2 review, WR-01). With
# asymmetric `c_inv` the joint optimum buys capacity from the cheapest player only, the
# VE is unique, and it genuinely SELECTS one point of a GNE continuum whose other points
# carry player-specific multipliers (`test/test_planning_nash.jl`, CR-02 testitem).
#
# PATTERN REUSE (31-PATTERNS.md): this function generalizes
# `test/fixtures_planning_ieee13_short.jl`'s own `solve_joint_reference` — the
# "independently-built monolithic joint model" cross-check Phase 30 used for its
# single-distributor BILEV-03 certification — from N=1 to N players sharing ONE pooled
# `capacity[t]` row (mirroring `coupling.jl`'s own `build_shared_transmission`, but with
# every `x_inv[i]`/`z[i,:]` kept GENUINELY FREE throughout, never bound-pinned via
# `activate_distributor!`/`write_back!`).
#
# SIMPLIFICATION vs `build_shared_transmission` (documented per the plan's own
# instruction): `build_shared_transmission`'s `x_op[i,t]` is tied to `z[i,t]` by an
# identity coupling row (`coupling[i,t]: x_op[i,t] == z[i,t]`) ONLY because
# `DistributorView`'s per-distributor best-response needs its OWN dualizable coupling row
# to drive Benders cuts. A monolithic joint solve has no such need — it is solved in one
# shot, not iterated per distributor — so this function writes the shared `capacity[t]`
# row DIRECTLY over each distributor's own `z[i,t]`, dropping the redundant `x_op`
# variable entirely. This changes no economics, only drops a variable
# `build_shared_transmission` needs for its own per-distributor-dualizable design.
#
# PVAL-04 scope note: every `@variable` below is continuous (investment, flow, reactive
# channel) — no binary/integer variable is introduced anywhere in this function.

"""
    solve_variational_equilibrium(specs::AbstractVector{<:NamedTuple};
                                  T::Int, corridor_cap::Real,
                                  x_inv_max::AbstractVector{<:Real},
                                  c_inv::AbstractVector{<:Real},
                                  c_op::AbstractVector{<:AbstractVector{<:Real}}) -> NamedTuple

Compute a variational equilibrium (VE) — a generalized Nash equilibrium (GNE) whose
shared-row multiplier is identical across every player — of an `N`-distributor
shared-transmission game via ONE direct, monolithic joint JuMP solve (BILEV-06b). See
this section's header for why a single convex solve suffices to CHARACTERIZE the VE on
this game (Rosen's shared-constraint-game theory), never an iterative decomposition.

**Uniqueness (Phase 31 code review, CR-02).** The returned VE is unique only when the
joint problem's optimum is. On the symmetric interior-cap fixture (`c_inv = [1, 1]`,
`test/test_planning_nash.jl`) it is NOT: the joint problem sees only `Σᵢ x_inv[i]`, so
the VE set is the whole split segment `x_inv_1 + x_inv_2 = 0.7`, `z = (0.7, 0.7)`, every
point carrying the common multiplier 0.5, and the split returned is a solver-dependent
point of that face (measured: the analytic centre `(0.35, 0.35)`). The GNE set is
STRICTLY larger than the VE set even there: it also contains free-riding GNEs
`x_inv_j = 0`, `z_j = 1.2 − p`, `p ∈ [0, 0.5]` (e.g. `x_inv = (0.95, 0)`,
`z = (0.7, 1.2)`, multipliers `(0.5, ≈0)`), whose unequal multipliers the VE excludes
(iteration-2 review, WR-01). With asymmetric `c_inv` (e.g. `[1.0, 1.4]`) the VE is unique —
the cheaper player builds all the capacity, `x_inv = (0.7, 0)` — and differs from the
GNE that `run_nash!` reaches from `z0 = 0`, `x_inv = (0.35, 0.25)`, whose players carry
unequal multipliers `(0.5, 0.7)` (hand-derived and regression-tested in the CR-02
testitem of `test/test_planning_nash.jl`).

`specs` is the SAME shape [`run_nash!`](@ref) already accepts: each entry supplies, per
distributor `i`, `feeder`, `pf::AbstractPowerFlow`, `aggregators`, `λ₀`, and
`master_kwargs` with (at least) `c_y` and `y_max` — so a caller can pass the IDENTICAL
`specs` vector to both `run_nash!` and this function. `N = length(specs)`.

# Boundary guards (before any `@variable`/`@constraint`/solve call)

  - `N >= 2` (a "shared" game with `N=1` has nothing to share, mirrors
    `build_shared_transmission`'s own guard).
  - `length(x_inv_max) == length(c_inv) == length(c_op) == N`; each `c_op[i]` has
    `length(c_op[i]) == T`.
  - `corridor_cap > 0`; `T >= 1`.
  - every `specs[i].pf` maps to the SAME `problem_class(specs[i].pf)` — a
    mixed-formulation joint model is out of scope for this phase's fixture; a mismatch
    throws `ArgumentError` naming the first offending index.

# Algorithm

Build ONE `model = Model(select_optimizer(problem_class(specs[1].pf)))`. For each
distributor `i`: a fresh `ctx_i = ModelContext(model)` (a per-distributor
residual/meta registry over the SAME shared `model` — `ModelContext` is a thin
dict-bearing wrapper, so N independent registries over one model is valid), its own
`0 <= y_inv[i] <= specs[i].master_kwargs.y_max`, `0 <= x_inv[i] <= x_inv_max[i]`, and a
free `z[i,t]` with box constraints `0 <= z[i,t] <= y_inv[i]` (mirrors
`solve_joint_reference`'s own `box_lo`/`box_hi`). `z[i,t]` is reused DIRECTLY as the
frontier import (`add_to_residual!(ctx_i, :Rp, specs[i].feeder.root, t, z[i,t])`,
mirroring `solve_joint_reference`'s own "z reused directly" simplification). Immediately
after `contribute!(specs[i].pf, ctx_i, specs[i].feeder; T)`, `reactive_i = has_reactive(specs[i].pf)` is captured (WR-03 ordering, mirrors
`build_planning_oracle`); when `reactive_i`, a free `zq[i,t]` is added into `:Rq`. Each
distributor's own aggregators then `contribute!` into `ctx_i`, and distributor `i`'s own
`balance_p[i]`/`balance_q[i]` residual-closing constraints are added — per-distributor,
never shared.

The ONE genuinely shared row (SIMPLIFIED per this section's header, directly over
`z[i,t]`, never a separate `x_op`):
`capacity[t]: Σᵢ z[i,t] <= corridor_cap * Σᵢ x_inv[i]`.

Objective: `Max Σᵢ [ctx_i.objective - Σₜ specs[i].λ₀[t]*z[i,t] - specs[i].master_kwargs.c_y*y_inv[i] - c_inv[i]*x_inv[i] - Σₜ c_op[i][t]*z[i,t]]` — the
SAME per-distributor cost/welfare shape `solve_joint_reference`/
`build_shared_transmission` already use, summed over every distributor.

Solved ONCE via [`solve_with_retry!`](@ref)`(model; dual = true)`. If
`problem_class(specs[1].pf) isa SOCP`, [`assert_socp_exact!`](@ref) is called on EVERY
distributor's own `ctx_i` — never silently accepting an inexact joint solve (mirrors
`solve_joint_reference`'s own exactness-or-throw discipline). On a non-SOCP formulation
(the toy `LinDistFlow`/`DC` fixtures) no cone exists, so the gate is skipped entirely —
identical to `problem_class`'s own generic `QP()` fallback routing.

# Returns

`(; y, x_inv, z, π_capacity, cost_per_distributor, model)` where `y::Vector{Float64}`
and `x_inv::Vector{Float64}` are length-`N` (`value.(y_inv)`/`value.(x_inv)`),
`z::Matrix{Float64}` is `N × T` (`value.(z)`), `π_capacity::Vector{Float64}` is the
length-`T` shared multiplier `dual.(capacity)` — a SINGLE, finite vector BY
CONSTRUCTION, since the row is written exactly ONCE (there is nothing to "equalize"
across players; every player's own multiplier IS this one vector) — and
`cost_per_distributor::Vector{Float64}` is each distributor `i`'s OWN MINIMIZATION-sense
total cost (`specs[i].master_kwargs.c_y*y_inv[i] + c_inv[i]*x_inv[i] + Σₜ c_op[i][t]*z[i,t]`) MINUS its own oracle welfare (`ctxs[i].objective - Σₜ specs[i].λ₀[t]*z[i,t]` — the
SAME Max-sense quantity `build_planning_oracle`'s own objective assembles, NOT
`ctxs[i].objective` alone, which carries ONLY the device/aggregator utility and
omits the `-λ₀[t]*z[i,t]` pricing term that lives in THIS function's own joint
`@objective`, not inside any per-distributor `ctx`). This is EXACTLY the quantity
`solve_stackelberg!`'s own `UB` tracks (`benders.jl`'s `cost_k = master.c_y*lb_res.y + follower_res.cost - oracle_res.cost`), so `cost_per_distributor[i]` is directly
comparable to a `solve_stackelberg!` best-response's own reported `UB` at this
distributor's VE-pinned state (the no-profitable-deviation certification this function's
own test suite performs). `model` is the solved `Model`, so a caller can read any other
dual.

# Throws

  - `ArgumentError` on any boundary-guard violation, before any `@variable`/`@constraint`/
    solve call.
  - Whatever `solve_with_retry!`/`assert_socp_exact!` throw on a genuinely infeasible or
    inexact joint solve (never silently swallowed).
"""
function solve_variational_equilibrium(
    specs::AbstractVector{<:NamedTuple};
    T::Int,
    corridor_cap::Real,
    x_inv_max::AbstractVector{<:Real},
    c_inv::AbstractVector{<:Real},
    c_op::AbstractVector{<:AbstractVector{<:Real}},
)
    N = length(specs)
    N >= 2 || throw(
        ArgumentError(
            "solve_variational_equilibrium needs N = length(specs) >= 2 (nothing to " *
            "share), got N=$N",
        ),
    )
    T >= 1 || throw(ArgumentError("solve_variational_equilibrium needs T >= 1, got T=$T"))
    corridor_cap > 0 || throw(
        ArgumentError(
            "solve_variational_equilibrium needs corridor_cap > 0, got $corridor_cap",
        ),
    )
    length(x_inv_max) == N ||
        throw(ArgumentError("x_inv_max has length $(length(x_inv_max)), expected N=$N"))
    length(c_inv) == N ||
        throw(ArgumentError("c_inv has length $(length(c_inv)), expected N=$N"))
    length(c_op) == N ||
        throw(ArgumentError("c_op has length $(length(c_op)), expected N=$N"))
    for i in 1:N
        length(c_op[i]) == T ||
            throw(ArgumentError("c_op[$i] has length $(length(c_op[i])), expected T=$T"))
    end

    # Formulation-genericity guard: a mixed-formulation joint model (e.g. distributor 1
    # on LinDistFlow/QP() and distributor 2 on ConvexBranchFlow/SOCP()) is out of scope
    # for this phase's fixture — fail here, naming the first mismatched index, BEFORE
    # any build call.
    classes = [problem_class(specs[i].pf) for i in 1:N]
    for i in 2:N
        classes[i] == classes[1] || throw(
            ArgumentError(
                "solve_variational_equilibrium: distributor $i's problem_class " *
                "$(classes[i]) differs from distributor 1's $(classes[1]) — a " *
                "mixed-formulation joint model is out of scope for this phase's fixture",
            ),
        )
    end
    is_socp = classes[1] isa SOCP

    model = Model(select_optimizer(classes[1]))

    y_inv = Vector{VariableRef}(undef, N)
    x_inv = Vector{VariableRef}(undef, N)
    z = Matrix{VariableRef}(undef, N, T)
    ctxs = Vector{ModelContext}(undef, N)

    for i in 1:N
        ctx_i = ModelContext(model)
        ctx_i.feeder = specs[i].feeder
        ctx_i.T = T
        ctx_i.meta[:problem_class] = classes[i]
        # Rule 1 (bug, discovered during execution): every `AbstractPowerFlow.contribute!`
        # method (e.g. LinDistFlow/ConvexBranchFlow) registers ITS OWN formulation-level
        # variables/constraints under FIXED, NAMED symbols (`:v`, `:P`, `:Q`, `:vdrop`, ...)
        # directly on `ctx_i.model` — unlike `Aggregator`'s own device loop, which already
        # switched to ANONYMOUS registration for exactly this reason (plan 21-05, this
        # file's sibling fix). A second distributor's `contribute!` call on the SAME
        # shared `model` would collide ("An object of name v is already attached to this
        # model"), since JuMP's object-dictionary registration is MODEL-scoped, not
        # ctx-scoped. Capture the model's object-dictionary keys immediately before/after
        # this ONE call and `unregister` every NEWLY-added name (JuMP's own sanctioned
        # mechanism for exactly this situation — it only removes the `model[:name]`
        # lookup, never the underlying variable/constraint objects, which stay fully
        # live via `ctx_i.residuals`/`ctx_i.pf_vars`). Formulation-generic: no
        # hardcoded name list, so this works for ANY `AbstractPowerFlow` subtype.
        names_before = Set(keys(JuMP.object_dictionary(model)))
        contribute!(specs[i].pf, ctx_i, specs[i].feeder; T = T)
        for name in setdiff(keys(JuMP.object_dictionary(model)), names_before)
            JuMP.unregister(model, name)
        end

        y_inv[i] = @variable(
            model,
            lower_bound = 0.0,
            upper_bound = Float64(specs[i].master_kwargs.y_max),
            base_name = "y_inv[$i]",
        )
        x_inv[i] = @variable(
            model,
            lower_bound = 0.0,
            upper_bound = Float64(x_inv_max[i]),
            base_name = "x_inv[$i]",
        )
        z_i = @variable(model, [t = 1:T], base_name = "z[$i,:]")
        for t in 1:T
            z[i, t] = z_i[t]
            @constraint(model, z_i[t] >= 0)
            @constraint(model, z_i[t] <= y_inv[i])
            add_to_residual!(ctx_i, :Rp, specs[i].feeder.root, t, z_i[t])
        end

        # WR-03 ordering (mirrors build_planning_oracle/solve_joint_reference): capture
        # `reactive_i` IMMEDIATELY after the formulation contributes, BEFORE any
        # aggregator writes.
        reactive_i = has_reactive(specs[i].pf)
        if reactive_i
            zq_i = @variable(model, [t = 1:T], base_name = "zq[$i,:]")
            for t in 1:T
                add_to_residual!(ctx_i, :Rq, specs[i].feeder.root, t, zq_i[t])
            end
        end

        for agg in specs[i].aggregators
            contribute!(agg, ctx_i; T = T)
        end

        Ni = length(specs[i].feeder.buses)
        size(ctx_i.residuals[:Rp]) == (Ni, T) || error(
            "solve_variational_equilibrium: distributor $i's residual :Rp is " *
            "$(size(ctx_i.residuals[:Rp])), expected ($Ni, $T) — an index escaped the " *
            "feeder",
        )
        balance_p_i =
            @constraint(model, [j = 1:Ni, t = 1:T], ctx_i.residuals[:Rp][j, t] == 0)
        register_constraint!(ctx_i, :balance_p, balance_p_i)

        if reactive_i
            size(ctx_i.residuals[:Rq]) == (Ni, T) || error(
                "solve_variational_equilibrium: distributor $i's residual :Rq is " *
                "$(size(ctx_i.residuals[:Rq])), expected ($Ni, $T) — an index escaped " *
                "the feeder",
            )
            balance_q_i =
                @constraint(model, [j = 1:Ni, t = 1:T], ctx_i.residuals[:Rq][j, t] == 0)
            register_constraint!(ctx_i, :balance_q, balance_q_i)
        end

        ctxs[i] = ctx_i
    end

    # The ONE genuinely shared row (SIMPLIFIED, directly over z[i,t] — this section's
    # header).
    @constraint(
        model,
        capacity[t = 1:T],
        sum(z[i, t] for i in 1:N) <= corridor_cap * sum(x_inv[i] for i in 1:N)
    )

    @objective(
        model,
        Max,
        sum(
            ctxs[i].objective - sum(specs[i].λ₀[t] * z[i, t] for t in 1:T) -
            Float64(specs[i].master_kwargs.c_y) * y_inv[i] - c_inv[i] * x_inv[i] -
            sum(c_op[i][t] * z[i, t] for t in 1:T) for i in 1:N
        )
    )

    solve_with_retry!(model; dual = true)

    # Never silently accept an inexact joint solve (mirrors solve_joint_reference's own
    # exactness-or-throw discipline); skipped entirely on a non-SOCP formulation (no cone
    # exists there, identical to problem_class's own generic QP() fallback routing).
    if is_socp
        for i in 1:N
            assert_socp_exact!(ctxs[i])
        end
    end

    # Rule 1 (bug, discovered during execution, Test 3 below): distributor i's OWN
    # oracle welfare — the quantity solve_stackelberg!'s own UB subtracts (`cost_k =
    # master.c_y*lb_res.y + follower_res.cost - oracle_res.cost`, benders.jl) — is
    # `build_planning_oracle`'s FULL objective `ctx.objective - Σ_t λ₀[t]*p_import[t]`,
    # NOT `ctx.objective` alone: the `-λ₀[t]*z[i,t]` pricing term lives in THIS
    # function's own joint `@objective` assembly (summed once over every distributor),
    # never inside `ctxs[i].objective` (which only ever accumulates device/
    # aggregator utility via `add_to_objective!`). Omitting it understated every
    # distributor's own welfare by exactly `Σ_t λ₀[t]*z[i,t]`, silently inflating the
    # reported `cost_per_distributor` — caught by Test 3's own no-profitable-deviation
    # cross-check against `solve_stackelberg!`'s independently-computed `UB` on the toy
    # fixture (measured mismatch: 2.8, exactly `λ₀[1]*z[i,1] = 4.0*0.7`).
    cost_per_distributor = [
        value(
            Float64(specs[i].master_kwargs.c_y) * y_inv[i] +
            c_inv[i] * x_inv[i] +
            sum(c_op[i][t] * z[i, t] for t in 1:T),
        ) - (
            value(ctxs[i].objective) -
            sum(specs[i].λ₀[t] * value(z[i, t]) for t in 1:T)
        ) for i in 1:N
    ]

    return (;
        y = value.(y_inv),
        x_inv = value.(x_inv),
        z = value.(z),
        π_capacity = dual.(capacity),
        cost_per_distributor,
        model,
    )
end

export solve_variational_equilibrium
