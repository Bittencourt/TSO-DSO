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
                       checkpoint_dir::AbstractString = datadir("planning_checkpoints"))
        -> NamedTuple

Solve the single-distributor Stackelberg equilibrium (flexibility-investment leader vs.
transmission-reinforcement follower, operational welfare oracle) end-to-end via a
hand-rolled Benders loop (PLAN-06), converging to a documented relative UB/LB gap
tolerance or raising loudly on iteration-cap exhaustion (D-10).

# Algorithm

 1. Boundary guards (mirror `solve_admm`): `T >= 1`, `max_iter >= 1`, `length(λ₀) == T`,
    each `ArgumentError` BEFORE any build call.
 2. BUILD ONCE, outside the loop: `oracle = build_planning_oracle(feeder, pf, aggregators; λ₀ = λ₀, T = T)`, `follower = build_follower(; follower_kwargs..., T = T)`,
    `master = build_master(; master_kwargs..., T = T)`. No `build_*`/`Model(` call appears
    anywhere inside the `for k in 1:max_iter` loop below.
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

On convergence, `(; y, z, UB, LB, gap, iters, oracle, follower, master)` where
`y = y_best` (the INCUMBENT leader investment — the iterate that achieved `UB`, so the
returned point's true cost equals `UB` and the `gap ≤ tol` certificate applies to it,
CR-01), `z = z_best` (the incumbent coupling flow), `UB`/`LB` are the converged
upper/lower bounds, `gap` is the converged relative gap,
`iters` is the convergence iteration count, and `oracle`/`follower`/`master` are the
build-once subproblem handles (for further inspection by the caller/certification gate,
plan 11-03).

# Throws

  - `ArgumentError` on `T < 1`, `max_iter < 1`, or `length(λ₀) != T` — before any build call.
  - `ErrorException` if `max_iter` is exhausted without converging, naming the last observed
    gap and the tolerance (D-10) — refuses to silently return a non-converged result.
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
)
    # ---- Boundary guards (mirror solve_admm): fail here, not deep in the loop ----------------
    T >= 1 || throw(ArgumentError("solve_stackelberg! needs T >= 1 (got T=$T)"))
    max_iter >= 1 || throw(
        ArgumentError("solve_stackelberg! needs max_iter >= 1 (got max_iter=$max_iter)"),
    )
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))

    # ---- BUILD ONCE: the oracle/follower/master subproblems are constructed OUTSIDE the
    # loop. No `build_*`/`Model(` call appears below this point — the loop only re-solves
    # via `solve_planning_oracle!`/`solve_follower!`/`solve_master!` and appends cut rows.
    oracle = build_planning_oracle(feeder, pf, aggregators; λ₀ = λ₀, T = T)
    follower = build_follower(; follower_kwargs..., T = T)
    master = build_master(; master_kwargs..., T = T)

    UB = Inf
    # CR-01: the INCUMBENT — the (y, z) iterate that achieved the running-minimum UB.
    # Convergence (LB rising to meet an OLDER iterate's UB) must return THIS pair, never
    # the current iterate, whose own cuts may not yet bound it: the excess of the last
    # iterate's true cost over UB is NOT bounded by tol.
    y_best = NaN
    z_best = fill(NaN, T)
    gap = NaN
    for k in 1:max_iter
        lb_res = solve_master!(master)
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
        follower_res = solve_follower!(follower, lb_res.z)

        if !follower_res.feasible
            add_feasibility_cut!(master, follower_res.v, follower_res.u, lb_res.z)
            checkpoint_iteration!(
                (; k, LB = lb_res.LB, UB, gap = NaN, z_k = lb_res.z, feasible = false),
                k;
                dir = checkpoint_dir,
            )
            continue   # T-11-06: a feasibility cut NEVER updates UB
        end

        # Only a follower-deliverable z_k ever reaches the oracle (WR-01 ordering above).
        oracle_res = solve_planning_oracle!(oracle, lb_res.z)

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
            )
        end
    end

    error(
        "solve_stackelberg!: exhausted $max_iter iteration(s) without converging " *
        "(last gap=$gap, tol=$tol) — refusing to silently return a non-converged result",
    )
end

export solve_stackelberg!
