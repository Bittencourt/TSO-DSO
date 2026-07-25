# src/planning/benders.jl
#
# SEAM: solve_stackelberg! — the outer Benders orchestration loop wiring the reused
# operational oracle (PlanningOracle, Phase 10), the new transmission-reinforcement
# follower (FollowerLP, plan 11-01), and the new Benders master (BendersMaster, plan
# 11-01) into a single-distributor Stackelberg equilibrium (PLAN-06).
# OWNER: plan 11-02.
#
# THE OUTER ORCHESTRATOR (mirrors src/admm/solve_admm.jl's own shape: boundary guards ->
# build subproblems ONCE, outside the loop -> iterate -> fail-loud maxiter cap). This file
# builds NO JuMP model of its own — it only calls the three already-validated build_*
# constructors once each, then re-solves them at each Benders trial `z_k` via their own
# solve_*! entry points.
#
# CONVERGENCE CRITERION IS STRUCTURALLY DIFFERENT FROM ADMM's residual test (11-RESEARCH.md
# Pattern 2 / Pitfall 7): the UB/LB relative gap `(UB - LB) / max(1, |UB|) <= tol` (locked
# default 1e-6), never `AdmmResiduals`.
#
# SIGN CONVENTION CONSUMED VERBATIM FROM PLAN 11-01 (`<sign_convention>` note, NOT
# re-derived here): the oracle's `:op` epigraph cut uses `cost_k = -oracle_res.cost`,
# `grad_k = oracle_res.π` (UNNEGATED) — `solve_planning_oracle!` returns a MAX-sense
# welfare value and its already-negated-Max-dual gradient (Phase 10 D-06); the master's
# epigraph is a MIN-sense cost-to-go, hence the negation on `cost_k` only. The follower's
# `:x` epigraph cut uses `cost_k = follower_res.cost` and `grad_k = follower_res.π_s` EXACTLY
# as `solve_follower!` returns them (its own empirically-pinned positive dual sign, plan
# 11-01 Task 1) — no further sign transformation.
#
# EVERY CUT-PRODUCING SOLVE ROUTES THROUGH THE CORRECT GATE (CONTEXT.md's Amendment
# (revision 1)): `solve_planning_oracle!`/`solve_master!` are gated internally by
# `solve_with_retry!`/strict `assert_solved!` (D-08); `solve_follower!` is called DIRECTLY
# here — NEVER wrapped in `solve_with_retry!` — because its infeasible branch must be
# OBSERVED, not retried away, or the Farkas certificate PLAN-04 requires is unreachable.
#
# CHECKPOINTING (D-10): `checkpoint_iteration!` fires EXACTLY ONCE per Benders iteration,
# from both the feasibility-cut branch and the optimality-cut branch (T-11-06: a
# feasibility cut never updates `UB` — the loop `continue`s immediately after checkpointing,
# skipping the `UB = min(...)` line entirely).

using JuMP
using DrWatson: datadir

"""
    solve_stackelberg!(feeder, pf::AbstractPowerFlow, aggregators::AbstractVector{<:Aggregator};
                       λ₀, T::Int, follower_kwargs::NamedTuple, master_kwargs::NamedTuple,
                       tol::Real = 1e-6, max_iter::Int = 100,
                       checkpoint_dir::AbstractString = datadir("planning_checkpoints"),
                       follower = nothing)
        -> NamedTuple

Solve the single-distributor Stackelberg equilibrium (flexibility-investment leader vs.
transmission-reinforcement follower, operational welfare oracle) end-to-end via a
hand-rolled Benders loop (PLAN-06), converging to a documented relative UB/LB gap
tolerance or raising loudly on iteration-cap exhaustion (D-10).

# Algorithm

 1. Boundary guards (mirror `solve_admm`): `T >= 1`, `max_iter >= 1`, `length(λ₀) == T`,
    each `ArgumentError` BEFORE any build call.

 2. BUILD ONCE, outside the loop: `oracle = build_planning_oracle(feeder, pf, aggregators; λ₀ = λ₀, T = T)`,
    `follower = follower === nothing ? build_follower(; follower_kwargs..., T = T) : follower`,
    `master = build_master(; master_kwargs..., T = T)`. No `build_*`/`Model(` call appears
    anywhere inside the `for k in 1:max_iter` loop below.

    **`follower` keyword (plan 13-02, additive/non-breaking — mirrors the
    `attempts_out::Union{Nothing,Ref{Int}}` precedent in `master.jl`/`retry.jl`):**
    defaults to `nothing`, in which case behavior is BYTE-IDENTICAL to every Phase 11/12
    call site (a fresh `FollowerLP` is built from `follower_kwargs` exactly as before). When
    a caller (Phase 13's `run_nash!`) instead supplies a pre-built per-distributor view
    object (e.g. `coupling.jl`'s `DistributorView`, duck-typed via its own
    `solve_follower!(view, z_trial)` method), that object is used DIRECTLY in place of a
    freshly-built `FollowerLP` — no follower is built by this function at all in that case.
    Supplying BOTH a non-`nothing` `follower` AND a non-empty `follower_kwargs`
    simultaneously is rejected with an `ArgumentError` (ambiguous — which one wins is never
    silently decided).

 3. Iterate `k = 1:max_iter`: `lb_res = solve_master!(master)` (the Benders lower bound and
    trial `z_k`); `follower_res = solve_follower!(follower, lb_res.z)` (DIRECT call — never
    `solve_with_retry!`-wrapped, per plan 11-01's follower contract) — the follower's
    feasibility check runs BEFORE any oracle solve (WR-01): an undeliverable trial `z_k`
    (the master's box allows `z` up to `y_max`, beyond `corridor_cap * x_inv_max`) is
    routed to the feasibility-cut branch instead of reaching the oracle, whose
    exactness/complementarity gates can throw at extreme pinned `z`.

      + If `!follower_res.feasible`: append a feasibility cut
        (`add_feasibility_cut!(master, follower_res.v, follower_res.u, lb_res.z)`),
        checkpoint with `gap = NaN` and `feasible = false`, then `continue` — a
        feasibility cut NEVER updates `UB` (T-11-06); the oracle is NEVER solved on
        this branch.
      + Else: `oracle_res = solve_planning_oracle!(oracle, lb_res.z)` — only a
        follower-deliverable `z_k` ever reaches the oracle;
        then append the oracle's `:op` optimality cut (`cost_k = -oracle_res.cost`,
        `grad_k = oracle_res.π`, the plan-11-01-derived sign convention) and the
        follower's `:x` optimality cut (`cost_k = follower_res.cost`,
        `grad_k = follower_res.π_s`, used as-is); compute the iterate's TRUE cost
        `cost_k = master.c_y * lb_res.y + follower_res.cost - oracle_res.cost`; if
        `cost_k < UB`, update the INCUMBENT `UB = cost_k`, `y_best = lb_res.y`,
        `z_best = copy(lb_res.z)` — the `(y, z)` pair that ACHIEVED the running-minimum
        `UB` is stored, never just the bound (CR-01: convergence can trigger at an
        iterate whose own cuts have not yet tightened the master, so the LAST iterate
        is not certified by `UB`; the incumbent is); compute
        `gap = (UB - lb_res.LB) / max(1, abs(UB))`; checkpoint with
        `feasible = true`; if `gap <= tol`, return the converged result at the
        INCUMBENT `(y_best, z_best)`.

 4. If `max_iter` is exhausted without `gap <= tol`, raise a loud `ErrorException` naming
    the exhausted iteration count and the last observed gap (D-10) — never silently return
    a non-converged result.

# Returns

On convergence, `(; y, z, UB, LB, gap, iters, oracle, follower, master, trace)` where
`y = y_best` (the INCUMBENT leader investment — the iterate that achieved `UB`, so the
returned point's true cost equals `UB` and the `gap ≤ tol` certificate applies to it,
CR-01), `z = z_best` (the incumbent coupling flow), `UB`/`LB` are the converged
upper/lower bounds, `gap` is the converged relative gap,
`iters` is the convergence iteration count, `oracle`/`follower`/`master` are the
build-once subproblem handles (for further inspection by the caller/certification gate,
plan 11-03), and `trace::BendersTrace` (plan 12-01, additive) is the per-iteration
convergence ledger — one row per iteration on both the feasibility-cut and
optimality-cut branches, including the GENUINE per-iteration retry count and both
retry-gated subproblems' termination statuses (never a log-scrape estimate).

# Throws

  - `ArgumentError` on `T < 1`, `max_iter < 1`, `length(λ₀) != T`, a non-finite/non-positive
    `tol`, `max_iter > 99_999`, or a non-`nothing` `follower` supplied together with a
    non-empty `follower_kwargs` (plan 13-02) — before any build call (IN-02/IN-03).
  - `ErrorException` if `max_iter` is exhausted without converging, naming the trace's
    last-recorded `LB`/`UB`/`gap` and the tolerance (D-10, IN-01) — refuses to silently
    return a non-converged result.
"""
function solve_stackelberg!(
    feeder,
    pf::AbstractPowerFlow,
    aggregators::AbstractVector{<:Aggregator};
    λ₀,
    T::Int,
    follower_kwargs::NamedTuple,
    master_kwargs::NamedTuple,
    tol::Real = 1e-6,
    max_iter::Int = 100,
    checkpoint_dir::AbstractString = datadir("planning_checkpoints"),
    follower = nothing,
)
    # ---- Boundary guards (mirror solve_admm): fail here, not deep in the loop ----------------
    T >= 1 || throw(ArgumentError("solve_stackelberg! needs T >= 1 (got T=$T)"))
    max_iter >= 1 || throw(
        ArgumentError("solve_stackelberg! needs max_iter >= 1 (got max_iter=$max_iter)"),
    )
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
    # IN-02 (plan 12-01): a NaN/negative tol silently guarantees exhaustion (every
    # gap <= tol comparison is false for NaN) — fail-loud is preserved but the
    # diagnosis is misleading; guard it here alongside the other boundary checks.
    isfinite(tol) && tol > 0 || throw(
        ArgumentError("solve_stackelberg! needs tol to be finite and > 0 (got tol=$tol)"),
    )
    # IN-03 (plan 12-01): checkpoint_iteration! enforces iter ∈ 0:99999 (5-digit
    # zero-padded filename contract, src/planning/checkpoint.jl) — fail HERE, not
    # deep inside checkpoint_iteration! after 99,999 wasted iterations.
    max_iter <= 99_999 || throw(
        ArgumentError(
            "solve_stackelberg! needs max_iter <= 99_999 (checkpoint_iteration!'s " *
            "5-digit zero-padded filename contract, src/planning/checkpoint.jl), got " *
            "max_iter=$max_iter",
        ),
    )
    # plan 13-02: the additive `follower` keyword and `follower_kwargs` are mutually
    # exclusive — supplying both would silently pick one and discard the other; fail
    # loudly instead, before any build call.
    follower === nothing ||
        isempty(follower_kwargs) ||
        throw(
            ArgumentError(
                "solve_stackelberg!: supply either follower_kwargs or follower, not both " *
                "(got follower=$follower, follower_kwargs=$follower_kwargs)",
            ),
        )

    # ---- BUILD ONCE: the oracle/follower/master subproblems are constructed OUTSIDE the
    # loop. No `build_*`/`Model(` call appears below this point — the loop only re-solves
    # via `solve_planning_oracle!`/`solve_follower!`/`solve_master!` and appends cut rows.
    oracle = build_planning_oracle(feeder, pf, aggregators; λ₀ = λ₀, T = T)
    follower = follower === nothing ? build_follower(; follower_kwargs..., T = T) : follower
    master = build_master(; master_kwargs..., T = T)

    UB = Inf
    # CR-01: the INCUMBENT — the (y, z) iterate that achieved the running-minimum UB.
    # Convergence (LB rising to meet an OLDER iterate's UB) must return THIS pair, never
    # the current iterate, whose own cuts may not yet bound it: the excess of the last
    # iterate's true cost over UB is NOT bounded by tol.
    y_best = NaN
    z_best = fill(NaN, T)
    gap = NaN
    # plan 12-01: the purpose-built Benders convergence ledger (roadmap criterion 2) —
    # built alongside the other accumulator state, immediately before the loop.
    trace = BendersTrace()
    for k in 1:max_iter
        # WR-01/IN-04 (phase 12 review): solve_time_trace records ONLY the wall-clock
        # seconds spent inside this iteration's solve calls (master + follower, plus
        # the oracle on the optimality branch) — NEVER checkpoint_iteration!'s JLD2
        # write + git provenance shell-outs, which on the toy fixtures dominate
        # whole-iteration wall time by orders of magnitude. Each solve is bracketed
        # with the MONOTONIC clock (time_ns), immune to the NTP steps that could make
        # a time()-based span negative and trip push!'s solve_time >= 0 guard mid-run.
        t_solve = 0.0
        # The Ref solve_master! overwrites with the actual attempt count via its new
        # attempts_out keyword (plan 12-01); Ref(1) is a safe initial value in case a
        # future call site ever omits the keyword, though this call site always passes it.
        master_attempts = Ref(1)
        t0_ns = time_ns()
        lb_res = solve_master!(master; attempts_out = master_attempts)
        t_solve += (time_ns() - t0_ns) / 1.0e9
        # CR-01 (phase 12 review): capture the master's GENUINE post-solve termination
        # status HERE — before solve_follower! and before any add_*_cut! call. The
        # master is a CACHING-mode model, and JuMP's add_constraint sets
        # is_model_dirty = true, after which termination_status short-circuits to the
        # :OPTIMIZE_NOT_CALLED sentinel; querying at the trace-push sites (after the
        # cut appends) would record that sentinel on every row of every run.
        master_status_k = Symbol(termination_status(master.model))
        # WR-01: the follower's feasibility check runs FIRST — before any oracle solve.
        # The master's box allows z up to y_max, beyond the follower's deliverable
        # capacity (corridor_cap * x_inv_max); at such extreme trial z the oracle's own
        # exactness/complementarity gates can throw (subproblem.jl CR-03), crashing the
        # loop at the exact moment a feasibility cut was the designed recovery. Routing
        # infeasible extremes to the feasibility-cut branch below also avoids a wasted
        # oracle solve per infeasible iteration.
        # DIRECT call — NEVER solve_with_retry!-wrapped (plan 11-01's follower contract):
        # the infeasible branch must be OBSERVED on the un-retried solve, or the Farkas
        # certificate is unreachable.
        t0_ns = time_ns()
        follower_res = solve_follower!(follower, lb_res.z)
        t_solve += (time_ns() - t0_ns) / 1.0e9

        if !follower_res.feasible
            add_feasibility_cut!(master, follower_res.v, follower_res.u, lb_res.z)
            checkpoint_iteration!(
                (; k, LB = lb_res.LB, UB, gap = NaN, z_k = lb_res.z, feasible = false),
                k;
                dir = checkpoint_dir,
            )
            # plan 12-01: feasibility-branch trace row. oracle_status defaults to the
            # :not_solved sentinel because the oracle is never reached on this branch
            # (WR-01 ordering); retry_count is the master's NET retries this iteration
            # (the only retry-gated solve that ran on this branch).
            push!(
                trace,
                k;
                LB = lb_res.LB,
                UB = UB,
                gap = NaN,
                cut_type = :feasibility,
                n_cuts = length(master.cuts),
                # CR-01: the status captured immediately after solve_master!, before
                # add_feasibility_cut! dirtied the model.
                master_status = master_status_k,
                oracle_status = :not_solved,
                retry_count = master_attempts[] - 1,
                solve_time = t_solve,
            )
            continue   # T-11-06: a feasibility cut NEVER updates UB
        end

        # Only a follower-deliverable z_k ever reaches the oracle (WR-01 ordering above).
        oracle_attempts = Ref(1)
        t0_ns = time_ns()
        oracle_res =
            solve_planning_oracle!(oracle, lb_res.z; attempts_out = oracle_attempts)
        t_solve += (time_ns() - t0_ns) / 1.0e9

        # Oracle's :op cut — plan 11-01's <sign_convention> derivation, reused verbatim:
        # cost_k = -oracle_res.cost, grad_k = oracle_res.π (UNNEGATED).
        add_optimality_cut!(master, :op, -oracle_res.cost, oracle_res.π, lb_res.z)
        # Follower's :x cut — used exactly as solve_follower! returns it.
        add_optimality_cut!(master, :x, follower_res.cost, follower_res.π_s, lb_res.z)

        # CR-01: track the incumbent, not just the bound — store the (y, z) pair that
        # achieved the running-minimum UB so the converged return is the certified point.
        cost_k = master.c_y * lb_res.y + follower_res.cost - oracle_res.cost
        if cost_k < UB
            UB = cost_k
            y_best = lb_res.y
            z_best = copy(lb_res.z)
        end
        gap = (UB - lb_res.LB) / max(1, abs(UB))

        checkpoint_iteration!(
            (; k, LB = lb_res.LB, UB, gap, z_k = lb_res.z, feasible = true),
            k;
            dir = checkpoint_dir,
        )
        # plan 12-01: optimality-branch trace row. retry_count sums BOTH retry-gated
        # solves' net retries this iteration (master's and the oracle's), since both
        # actually ran; oracle_status records the oracle's own genuine termination
        # status (never the :not_solved sentinel on this branch).
        push!(
            trace,
            k;
            LB = lb_res.LB,
            UB = UB,
            gap = gap,
            cut_type = :optimality,
            n_cuts = length(master.cuts),
            # CR-01: the status captured immediately after solve_master!, before the
            # add_optimality_cut! calls dirtied the model. oracle.model is NOT dirtied
            # between its solve and this query (only master.model receives cuts), so
            # its status is queried directly here.
            master_status = master_status_k,
            oracle_status = Symbol(termination_status(oracle.model)),
            retry_count = (master_attempts[] - 1) + (oracle_attempts[] - 1),
            solve_time = t_solve,
        )

        if gap <= tol
            # CR-01: return the INCUMBENT — c(y_best, z_best) = UB <= LB + tol*max(1,|UB|)
            # and LB <= optimum, so the returned point is certified within tol; the
            # current iterate (lb_res.y, lb_res.z) carries no such guarantee.
            return (;
                y = y_best,
                z = z_best,
                UB,
                LB = lb_res.LB,
                gap,
                iters = k,
                oracle,
                follower,
                master,
                trace,
            )
        end
    end

    # IN-01 (plan 12-01): read the exhaustion diagnostic from the TRACE's last recorded
    # row, never a loop-local variable that can be stale/NaN if the final iterations
    # were all feasibility branches — every iteration pushes exactly one trace row on
    # either branch, so trace.iters == max_iter and last(...) is always well-defined here.
    last_LB = last(trace.LB_trace)
    last_UB = last(trace.UB_trace)
    last_gap = last(trace.gap_trace)
    error(
        "solve_stackelberg!: exhausted $max_iter iteration(s) without converging " *
        "(last recorded LB=$last_LB, UB=$last_UB, gap=$last_gap [gap may be NaN if the " *
        "final iteration was a feasibility cut], tol=$tol) — refusing to silently " *
        "return a non-converged result",
    )
end

export solve_stackelberg!
