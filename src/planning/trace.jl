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
    at this iteration (`push!` also accepts `:rejected`, the pre-iteration-2 label of a
    `:reject` row; since the Phase 30 code review iteration 2, WR-02, a rejected trial's
    cuts are appended and its row is `:optimality` with `policy_action = :rejected`).
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
  - `nogood_count_trace::Vector{Int}` — Phase 24 (INT-02, D-16, plan 24-03), ADDITIVE:
    the number of D-16 anti-stall no-good cuts fired at this iteration (`0` on every
    continuous-path row and on every integer-path row where `apply_integer_cuts!`
    did NOT detect a stall — see `master_integer.jl`). `push!`'s `nogood_count` keyword
    defaults to `0` so every PRE-EXISTING `benders.jl` call site (which omits this
    keyword entirely) keeps compiling and records `0` here, byte-identical to its
    behavior before this field existed. Never invisible (D-16's "never invisible"
    requirement) — surfaced via `trace_summary`'s `total_nogoods`.
  - `solve_time_trace::Vector{Float64}` — monotonic-clock (`time_ns`) wall seconds
    spent inside this iteration's solve calls ONLY (master + follower, plus the
    oracle on an optimality-branch row); cut appends, `checkpoint_iteration!`'s
    JLD2/git-provenance I/O, and trace bookkeeping are EXCLUDED (WR-01, phase 12
    review). Non-negative, finite.
  - `socp_maxgap_trace::Vector{Float64}` — Phase 30 (BILEV-04b, plan 30-04), ADDITIVE:
    the measured SOC-relaxation cone residual `max |l·v − (P²+Q²)|` at this
    iteration's pinned `z_k`, recorded on EVERY row whose oracle solve ran the
    exactness gate — exact rows AND inexact (`:certified_incumbent`/`:rejected`) rows
    (Phase 30 code review, WR-05; it used to be recorded only on the policy rows). `NaN`
    on rows where the gate does not apply: feasibility-cut rows (no trusted oracle
    solve) and every row of a DC/LinDistFlow run (no `:l` stash) — a legitimate
    sentinel, mirroring `gap_trace`'s own NaN convention, never guarded away. A finite
    entry is therefore NOT by itself a sign of inexactness — read `policy_action_trace`
    for the verdict.
  - `policy_action_trace::Vector{Symbol}` — Phase 30 (BILEV-04b, plan 30-04),
    ADDITIVE: which `inexact_policy` branch (if any) fired at this iteration —
    `:certified_incumbent` (the oracle returned an explicit `:inexact` verdict under
    `inexact_policy = :certify_incumbent`; the relaxation's cuts were appended and the
    trial competed for the incumbent), `:rejected` (an `:inexact` verdict under
    `:reject`; the relaxation's cuts were appended but the trial was barred from UB and
    the incumbent — WR-02, iteration 2), `:oracle_feasibility_cut` (an untrusted oracle
    solve whose status is in `ORACLE_INFEASIBLE_STATUSES` — INFEASIBLE,
    INFEASIBLE_OR_UNBOUNDED, LOCALLY_INFEASIBLE, ALMOST_INFEASIBLE — routed to the
    feasibility-oracle-cut branch, BILEV-04a, with a separating cut),
    `:oracle_feasibility_cut_weak` (the same, with a valid but weak cut — WR-06,
    iteration 2), or the default `:none` (no policy branch fired — the ordinary
    success/follower-feasibility path). No validity-restriction guard beyond its
    `Symbol` type, mirroring `oracle_status_trace`'s own lenient treatment — this is
    a diagnostics column, not a correctness gate.
  - `feas_cut_v_trace::Vector{Float64}` — Phase 30 code review iteration 2 (WR-06),
    ADDITIVE: the slack-minimization value `v` measured at `z_k` on every ORACLE
    feasibility-cut row (`:oracle_feasibility_cut` / `:oracle_feasibility_cut_weak`), so
    the near-boundary regime is measurable; `NaN` on every other row (including follower
    feasibility rows, whose Farkas `v` is not recorded here).
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
    nogood_count_trace::Vector{Int}
    solve_time_trace::Vector{Float64}
    socp_maxgap_trace::Vector{Float64}
    policy_action_trace::Vector{Symbol}
    feas_cut_v_trace::Vector{Float64}
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
    Int[],
    Float64[],
    Float64[],
    Symbol[],
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
          master_status, oracle_status = :not_solved, retry_count,
          nogood_count::Integer = 0, solve_time,
          socp_maxgap::Real = NaN, policy_action::Symbol = :none,
          feas_cut_v::Real = NaN)
        -> BendersTrace

Append ONE new row to `trace`, incrementing `trace.iters`. `k` must be the next
sequential iteration (`trace.iters + 1`) — a fail-loud guard against a double-push or a
skipped iteration, mirroring `AdmmResiduals`'s own `_assert_sequential` idiom.

Guards (each a distinct `ArgumentError`, fired BEFORE any field is mutated):

  - `cut_type in (:optimality, :feasibility, :rejected)` — any other symbol is rejected.
    `:rejected` (Phase 30, BILEV-04b, plan 30-04, ADDITIVE) was the row kind of
    `solve_stackelberg!`'s `inexact_policy = :reject` branch while a rejection appended no
    cut; it stays accepted, but since the Phase 30 code review iteration 2 (WR-02)
    `solve_stackelberg!` records rejected trials as `:optimality` rows with
    `policy_action = :rejected`.
  - `isfinite(LB)` — `LB` is always a real LP objective value; unlike `UB`/`gap` it has
    no legitimate non-finite state.
  - `isfinite(solve_time) && solve_time >= 0`.
  - `n_cuts >= 0`.
  - `retry_count >= 0` — a count of ACTUAL retries consumed this iteration (see
    `benders.jl`'s instrumentation for exactly how it is computed); `0` is the normal,
    no-retry case, not an edge case to special-case away.
  - `nogood_count >= 0` (Phase 24, D-16, mirrors `retry_count`'s own guard) — the number
    of D-16 anti-stall no-good cuts fired at this iteration.

`UB`/`gap` are DELIBERATELY NOT guarded for finiteness: `UB = Inf` (before any
optimality iteration) and `gap = NaN` (every feasibility-branch row) are legitimate
sentinel values, not defects to reject. `oracle_status` needs no additional guard
beyond its `Symbol` type — it is either the sentinel `:not_solved` (feasibility-branch
default) or a genuine termination-status symbol (optimality branch), mirroring
`master_status`'s own unvalidated-`Symbol` treatment. `policy_action` (Phase 30,
BILEV-04b, plan 30-04, ADDITIVE) likewise carries NO validity-restriction guard — it
mirrors `oracle_status`'s own lenient `Symbol` treatment, a diagnostics column, never a
correctness gate.

**`nogood_count` is ADDITIVE (Phase 24, plan 24-03): defaults to `0`.** Every
PRE-EXISTING `benders.jl` call site omits this keyword entirely and keeps compiling,
recording `0` here — byte-identical to its behavior before this keyword existed.

**`feas_cut_v` is ADDITIVE (Phase 30 code review iteration 2, WR-06): defaults to `NaN`.**

**`socp_maxgap`/`policy_action` are ADDITIVE (Phase 30, BILEV-04b, plan 30-04): default
to `NaN`/`:none`.** Every PRE-EXISTING `benders.jl` call site (and every call site in
this file's own pre-30-04 history) omits both keywords entirely and keeps compiling,
recording the sentinel pair here — byte-identical to its behavior before these fields
existed.

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
    nogood_count::Integer = 0,
    solve_time::Real,
    socp_maxgap::Real = NaN,
    policy_action::Symbol = :none,
    feas_cut_v::Real = NaN,
)
    _assert_sequential_trace(trace, k)
    cut_type in (:optimality, :feasibility, :rejected) || throw(
        ArgumentError(
            "push!: cut_type must be :optimality, :feasibility, or :rejected, got $cut_type",
        ),
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
    nogood_count >= 0 ||
        throw(ArgumentError("push!: nogood_count must be >= 0, got $nogood_count"))

    push!(trace.iter_trace, Int(k))
    push!(trace.LB_trace, float(LB))
    push!(trace.UB_trace, float(UB))
    push!(trace.gap_trace, float(gap))
    push!(trace.cut_type_trace, cut_type)
    push!(trace.n_cuts_trace, Int(n_cuts))
    push!(trace.master_status_trace, master_status)
    push!(trace.oracle_status_trace, oracle_status)
    push!(trace.retry_count_trace, Int(retry_count))
    push!(trace.nogood_count_trace, Int(nogood_count))
    push!(trace.solve_time_trace, float(solve_time))
    push!(trace.socp_maxgap_trace, float(socp_maxgap))
    push!(trace.policy_action_trace, policy_action)
    push!(trace.feas_cut_v_trace, float(feas_cut_v))
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

Summarize `trace` as
`(; iters, final_LB, final_UB, final_gap, max_cuts, total_retries, total_nogoods,
n_inexact_iterations)`.
On an empty trace, returns `iters = 0` and all others as `NaN`/`0` sentinels.
Otherwise `final_LB`/`final_UB`/`final_gap` are the LAST recorded row's values,
`max_cuts = maximum(trace.n_cuts_trace)`, `total_retries = sum(trace.retry_count_trace)`
— the EMPIRICAL retry count (plan-checker blocker fix, revision 1): a plain,
always-computed sum over the per-iteration column, never an aggregate log-scrape
estimate — and `total_nogoods = sum(trace.nogood_count_trace)` (Phase 24, D-16,
plan 24-03, ADDITIVE, mirrors `total_retries`'s own `sum(...)` pattern exactly):
D-16's "never invisible" requirement for the count of anti-stall no-good cuts fired
across the whole run. `m > 0` here is informational only — it never fails a run;
`solve_stackelberg!` (plan 24-04) downgrades its own `converged_via` attribution to
`:nogood_assisted` when `total_nogoods > 0`. `n_inexact_iterations` (Phase 30,
BILEV-04b, plan 30-04, ADDITIVE) counts the rows whose `policy_action_trace` entry is
`:certified_incumbent` or `:rejected` — the iterations where the oracle's exactness gate
returned an INEXACT verdict (Phase 30 code review, WR-05: it no longer relies on a NaN
sentinel in `socp_maxgap_trace`, which now carries the measured gap on exact rows too) —
`0` on an empty trace and on every run where those branches never fired.
"""
function trace_summary(trace::BendersTrace)
    trace.iters == 0 && return (;
        iters = 0,
        final_LB = NaN,
        final_UB = NaN,
        final_gap = NaN,
        max_cuts = 0,
        total_retries = 0,
        total_nogoods = 0,
        n_inexact_iterations = 0,
    )
    return (;
        iters = trace.iters,
        final_LB = last(trace.LB_trace),
        final_UB = last(trace.UB_trace),
        final_gap = last(trace.gap_trace),
        max_cuts = maximum(trace.n_cuts_trace),
        total_retries = sum(trace.retry_count_trace),
        total_nogoods = sum(trace.nogood_count_trace),
        n_inexact_iterations = count(
            a -> a === :certified_incumbent || a === :rejected,
            trace.policy_action_trace,
        ),
    )
end

export BendersTrace, is_converged, trace_summary
