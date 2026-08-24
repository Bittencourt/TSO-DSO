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

# D-13/D-14 (Phase 24, plan 24-04): a NEW, dedicated termination threshold for the
# lattice-exact `known_optimum` certification fallback — deliberately DISTINCT from the
# `tol` kwarg's inherited `1e-6` continuous relative-gap tolerance, so it can never be
# mistaken for "reusing" that tolerance (the standing anti-certificate-laundering bar).
#
# EMPIRICALLY MEASURED (2026-08-23) on the D-12 fixture (`Phase6Fixtures.two_bus_feeder()`
# + `ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)`, single aggregator, λ₀=[4.0],
# T=1), solving the oracle (Clarabel SOCP) and follower (HiGHS LP) once each at a
# representative interior trial `z = [1.0]` and reading each solver's OWN certified
# primal/dual objective gap directly (`abs(objective_value(model) - dual_objective_value(model))`
# — no second reference solve needed, `dual_objective_value` IS the solver's own bound at
# the primal solution):
#   gap_oracle   = 3.957388639008741e-9   (Clarabel SOCP interior-point duality gap)
#   gap_follower = 0.0                    (HiGHS LP — exact simplex, zero measured gap)
# `max(gap_oracle, gap_follower) = 3.957388639008741e-9`, which is NOT comfortably below
# `1e-10` (the 10x-margin-under-1e-9 threshold the measurement protocol calls for) — so a
# hardcoded `1e-9` would sit BELOW the solver's own achieved precision on this fixture,
# exactly the failure mode quick task `260823-gea` found in `fit_baseline`. Per the
# measurement formula `max(1e-9, 10 * max(gap_oracle, gap_follower))`, the constant is set
# to the measured value below, not a hopeful guess.
const KNOWN_OPTIMUM_ATOL = 3.957388639008741e-8

# ---------------------------------------------------------------------------------------
# Phase 24 GAP-CLOSURE (plan 24-05.1) — the fix for the LL-cut Q_nu defect plan 24-05's
# certification (D-15) found in already-merged plan 24-03/24-04 code: `apply_integer_cuts!`
# was being handed the recourse EVALUATED AT WHATEVER z THE MASTER'S CURRENT TRIAL
# HAPPENED TO PICK (`follower_res.cost - oracle_res.cost` at `lb_res.z`), not the TRUE,
# EXACTLY-MINIMIZED per-corner recourse `Q(y_inv(b^ν)) = min_{z∈[0,y_inv]}
# [follower_cost(z) - oracle_welfare(z)]` the Laporte-Louveaux theorem (and `add_ll_cut!`'s
# own docstring precondition) requires. See test/test_planning_certification_integer.jl's
# file header for the full, empirically-confirmed diagnosis this fix resolves.
# ---------------------------------------------------------------------------------------

"""
    corner_recourse(oracle, follower, y_inv::Real, T::Int; iters::Int = 100) -> Float64

The TRUE per-corner minimized recourse
`Q(y_inv) = min_{z ∈ [0, y_inv]} [follower_cost(z) − oracle_welfare(z)]`, computed via a
deterministic ternary search over the REAL, already-built `oracle`/`follower` (the SAME
production `solve_planning_oracle!`/`solve_follower!` entrypoints used everywhere else in
the Benders loop — never rebuilt, never a closed-form shortcut).

Mirrors `test/test_planning_certification_integer.jl`'s own `enumerate_lattice` reference
implementation's `Qfun`/`ternary_min` technique EXACTLY — that file's logic, promoted from
test-only certification code into production so `add_ll_cut!`'s caller finally honors its
own documented precondition (`Q_nu = Q(b^ν)`, "never estimated here" — estimating it via
the iterate's own `z` was exactly the caller-side bug). `Q` is convex in `z` whenever the
oracle's welfare is concave and the follower's cost is convex — the SAME convexity
argument `add_optimality_cut!`'s own docstring already establishes for `Q(y_inv)` over the
continuous relaxation — so ternary search on `[0, y_inv]` converges to the true minimum.

Phase 24 is single-distributor Stackelberg-only (T=1 on every canonical fixture to date,
per the roadmap's own explicit scope note); for `T > 1` this pins the SAME scalar trial
value across all `T` periods (`fill(z, T)`) — the natural minimal generalization of the
theory's scalar `z` (each of the master's `T` box constraints shares the identical `y_inv`
upper bound), not a claim of general joint-multivariate optimality across independently
varying per-period trials.

An infeasible trial `z` (the follower's own genuine `feasible = false` branch) is treated
as `+Inf` in the extended-value sense (the SAME Rule-1 device `enumerate_lattice` uses) —
mathematically sound here because `z = 0` (zero flow) is always follower-feasible, so the
feasible sub-interval containing the true minimizer is always nonempty.

`y_inv <= 0` short-circuits to `0.0` without any solve — the feasible interval collapses
to the single point `z = 0`, at which both the follower's zero-cost and the oracle's
zero-welfare baseline apply (matches `enumerate_lattice`'s own `y_inv <= 0` branch).
"""
function corner_recourse(oracle, follower, y_inv::Real, T::Int; iters::Int = 100)
    y_inv <= 0 && return 0.0

    function Qfun(z::Real)
        zvec = fill(Float64(z), T)
        fr = solve_follower!(follower, zvec)
        # Rule 1 auto-fix (mirrors enumerate_lattice's own documented fix): an
        # undeliverable z is a genuine infeasibility, not an error — extend Q to +Inf
        # there so ternary search never dereferences a nonexistent .cost field and
        # still finds the true constrained minimum.
        fr.feasible || return Inf
        orr = solve_planning_oracle!(oracle, zvec)
        return fr.cost - orr.cost
    end

    lo, hi = 0.0, Float64(y_inv)
    for _ in 1:iters
        m1 = lo + (hi - lo) / 3
        m2 = hi - (hi - lo) / 3
        Qfun(m1) < Qfun(m2) ? (hi = m2) : (lo = m1)
    end
    zstar = (lo + hi) / 2
    return Qfun(zstar)
end

"""
    ll_cut_recourse(master, oracle, follower, lb_res, Q_nu_iterate::Real) -> Float64

Dispatched Q_nu resolver for the Laporte-Louveaux cut, mirroring
[`apply_integer_cuts!`](@ref)'s own dispatch shape:

  - `ll_cut_recourse(::BendersMaster, oracle, follower, lb_res, Q_nu_iterate)` — a TRUE
    no-op: returns `Q_nu_iterate` UNCHANGED, touches ZERO fields of `oracle`/`follower`/
    `lb_res` (never re-solves either model). Exists purely to keep the `benders.jl` call
    site uniform across both master types — this value is never actually consumed
    downstream, since `apply_integer_cuts!(::BendersMaster, ...)` is itself a true no-op.
    The continuous path is therefore BYTE-IDENTICAL to its pre-fix behavior.
  - `ll_cut_recourse(master::BendersMasterInteger, oracle, follower, lb_res, Q_nu_iterate)`
    — computes the TRUE per-corner minimized recourse via [`corner_recourse`](@ref) at the
    incumbent trial's OWN `y_inv = lb_res.y`. This is exact by construction: `lb_res.b` is
    binary at a genuine MILP optimum, so `lb_res.y` is the DETERMINISTIC value of the
    `y_inv` expression evaluated at that exact `b` (never a relaxed/fractional value) —
    `y_inv(b^ν)`, not an independent re-derivation.

**THE FIX (Phase 24 gap-closure, plan 24-05.1):** the caller previously passed
`Q_nu_iterate` straight through to `add_ll_cut!` — the recourse evaluated AT WHATEVER `z`
the master's current trial happened to pick, only an UPPER BOUND on `Q(y_inv(b^ν))` in
general (the master's box only guarantees `z <= y_inv`, not `z` = the minimizer). This
method supplies the theorem's actual required value instead.
"""
ll_cut_recourse(::BendersMaster, oracle, follower, lb_res, Q_nu_iterate::Real) = Q_nu_iterate

function ll_cut_recourse(
    master::BendersMasterInteger,
    oracle,
    follower,
    lb_res,
    Q_nu_iterate::Real,
)
    return corner_recourse(oracle, follower, lb_res.y, master.T)
end

"""
    solve_stackelberg!(feeder, pf::AbstractPowerFlow, aggregators::AbstractVector{<:Aggregator};
                       λ₀, T::Int, follower_kwargs::NamedTuple, master_kwargs::NamedTuple,
                       tol::Real = 1e-6, max_iter::Int = 100,
                       checkpoint_dir::AbstractString = datadir("planning_checkpoints"),
                       follower = nothing, master = nothing,
                       known_optimum::Union{Nothing,Real} = nothing)
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
    `master = master === nothing ? build_master(; master_kwargs..., T = T) : master`. No
    `build_*`/`Model(` call appears anywhere inside this function OTHER THAN these two
    conditional builder calls, BOTH of which are skippable via injection and BOTH of which
    still execute strictly BEFORE the `for k in 1:max_iter` loop below — the loop itself
    never constructs a model.

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

    **`master` keyword (Phase 24, plan 24-04, additive/non-breaking — D-08, mirrors the
    `follower` seam immediately above VERBATIM in structure):** defaults to `nothing`, in
    which case behavior is BYTE-IDENTICAL to every prior call site (a fresh `BendersMaster`
    is built from `master_kwargs` exactly as before). When a caller instead supplies a
    pre-built master (e.g. a `BendersMasterInteger` from `build_master_integer`, Phase 24's
    binary-expansion MILP master), that object is used DIRECTLY in place of a
    freshly-built `BendersMaster` — no master is built by this function at all in that case.
    Supplying BOTH a non-`nothing` `master` AND a non-empty `master_kwargs` simultaneously is
    rejected with an `ArgumentError`, mirroring the `follower`/`follower_kwargs` guard.

    **`known_optimum` keyword (Phase 24, plan 24-04, D-13/D-14):** defaults to `nothing`, in
    which case the loop's termination gate is unchanged (`gap <= tol`). When a caller
    supplies a finite value (the enumeration-backed certification harness, plan 24-05), the
    loop instead terminates on an EXCLUSIVE exact-match test against `known_optimum` (see
    `converged_now` in the iteration loop below) — never an `||` with `gap <= tol`.

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
        `feasible = true`; on this branch ALSO call
        `apply_integer_cuts!(master, lb_res, Q_nu)` (Phase 24, plan 24-04 — a TRUE no-op
        for `BendersMaster`, real Laporte-Louveaux/no-good logic for
        `BendersMasterInteger`, `Q_nu = follower_res.cost - oracle_res.cost`); compute
        `converged_now = known_optimum === nothing ? (gap <= tol) : isapprox(UB, known_optimum; atol = KNOWN_OPTIMUM_ATOL)`
        — an EXCLUSIVE branch, NEVER an `||` of the two criteria (D-13/D-14: reusing the
        continuous loop's inherited `tol` on the certified `known_optimum` path would be
        exactly the "certificate laundering" this mechanism exists to forbid); if
        `converged_now`, return the converged result at the INCUMBENT `(y_best, z_best)`.

 4. If `max_iter` is exhausted without `converged_now`, raise a loud `ErrorException` naming
    the exhausted iteration count and the last observed gap (D-10) — never silently return
    a non-converged result.

# Returns

On convergence, `(; y, z, UB, LB, gap, iters, oracle, follower, master, trace, nogood_count, converged_via)`
where `y = y_best` (the INCUMBENT leader investment — the iterate that achieved `UB`, so
the returned point's true cost equals `UB` and the convergence certificate applies to it,
CR-01), `z = z_best` (the incumbent coupling flow), `UB`/`LB` are the converged
upper/lower bounds, `gap` is the converged relative gap (a REPORTING quantity — on the
`known_optimum`-supplied path, convergence is certified by the exact-match test, not by
`gap`), `iters` is the convergence iteration count, `oracle`/`follower`/`master` are the
build-once subproblem handles (for further inspection by the caller/certification gate,
plan 11-03), `trace::BendersTrace` (plan 12-01, additive) is the per-iteration
convergence ledger — one row per iteration on both the feasibility-cut and
optimality-cut branches, including the GENUINE per-iteration retry count and both
retry-gated subproblems' termination statuses (never a log-scrape estimate), and
`nogood_count`/`converged_via` (Phase 24, plan 24-04, D-16, additive) surface the total
number of no-good anti-stall cuts fired (`nogood_count`, always `0` on the continuous
path) and the convergence attribution (`converged_via`, `:clean` if `nogood_count == 0`
else `:nogood_assisted`) — a nonzero `nogood_count` never fails the run, it is reported,
never silently absorbed.

# Throws

  - `ArgumentError` on `T < 1`, `max_iter < 1`, `length(λ₀) != T`, a non-finite/non-positive
    `tol`, `max_iter > 99_999`, a non-`nothing` `follower` supplied together with a
    non-empty `follower_kwargs` (plan 13-02), a non-`nothing` `master` supplied together
    with a non-empty `master_kwargs` (Phase 24, plan 24-04, D-08), or a non-`nothing`
    `known_optimum` that is not finite (Phase 24, plan 24-04, D-13/D-14) — before any build
    call (IN-02/IN-03).
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
    master = nothing,
    known_optimum::Union{Nothing, Real} = nothing,
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
    # Phase 24, plan 24-04 (D-08): the additive `master` keyword and `master_kwargs` are
    # mutually exclusive — mirrors the `follower`/`follower_kwargs` guard immediately above
    # VERBATIM in structure; supplying both would silently pick one and discard the other.
    master === nothing ||
        isempty(master_kwargs) ||
        throw(
            ArgumentError(
                "solve_stackelberg!: supply either master_kwargs or master, not both " *
                "(got master=$master, master_kwargs=$master_kwargs)",
            ),
        )
    # Phase 24, plan 24-04 (D-13/D-14): a non-nothing known_optimum must be finite — a
    # NaN/Inf value would make every isapprox(UB, known_optimum; ...) comparison silently
    # false, guaranteeing max_iter exhaustion with a misleading diagnosis (same rationale
    # as the tol finiteness guard above).
    known_optimum === nothing ||
        isfinite(known_optimum) ||
        throw(
            ArgumentError(
                "solve_stackelberg! needs known_optimum to be finite when supplied, got " *
                "known_optimum=$known_optimum",
            ),
        )

    # ---- BUILD ONCE: the oracle/follower/master subproblems are constructed OUTSIDE the
    # loop. No `build_*`/`Model(` call appears below this point — the loop only re-solves
    # via `solve_planning_oracle!`/`solve_follower!`/`solve_master!` and appends cut rows.
    oracle = build_planning_oracle(feeder, pf, aggregators; λ₀ = λ₀, T = T)
    follower = follower === nothing ? build_follower(; follower_kwargs..., T = T) : follower
    master = master === nothing ? build_master(; master_kwargs..., T = T) : master

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
    # Phase 24, plan 24-04 (D-16): running total of no-good anti-stall cut firings across
    # the whole run — always 0 on the continuous path (apply_integer_cuts! is a true no-op
    # for BendersMaster). Surfaced on the returned NamedTuple, never a silent count.
    nogood_total = 0
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
        # Phase 24 gap-closure (plan 24-05.1): capture oracle.model's GENUINE
        # termination status HERE, immediately after ITS OWN solve at lb_res.z —
        # mirrors master_status_k's own CR-01 capture-before-mutation discipline
        # above. `ll_cut_recourse` below (BendersMasterInteger path only) re-solves
        # oracle/follower at OTHER z trials during its internal ternary search;
        # querying termination_status(oracle.model) AFTER that point would silently
        # report the LAST ternary-search trial's status instead of lb_res.z's own.
        oracle_status_k = Symbol(termination_status(oracle.model))

        # Oracle's :op cut — plan 11-01's <sign_convention> derivation, reused verbatim:
        # cost_k = -oracle_res.cost, grad_k = oracle_res.π (UNNEGATED).
        add_optimality_cut!(master, :op, -oracle_res.cost, oracle_res.π, lb_res.z)
        # Follower's :x cut — used exactly as solve_follower! returns it.
        add_optimality_cut!(master, :x, follower_res.cost, follower_res.π_s, lb_res.z)

        # Phase 24, plan 24-04: apply_integer_cuts! fires generically on the optimality
        # branch — a TRUE no-op for BendersMaster (touches zero fields of lb_res, always
        # returns nogood_fired = false), real Laporte-Louveaux (always) + no-good
        # (on detected stall) logic for BendersMasterInteger (plan 24-03).
        #
        # Q_nu_iterate: the recourse EXCLUDING the leader's own c_y*y term, evaluated AT
        # THE CURRENT ITERATE z = lb_res.z — exactly cost_k below, minus that term. This
        # is NOT what add_ll_cut! requires (see ll_cut_recourse immediately below).
        Q_nu_iterate = follower_res.cost - oracle_res.cost

        # Phase 24 GAP-CLOSURE (plan 24-05.1) — THE FIX for the defect plan 24-05's
        # certification (D-15) found in this already-merged wiring: add_ll_cut!'s own
        # documented precondition is the EXACT, per-corner MINIMIZED recourse
        # Q(y_inv(b^ν)) = min_{z∈[0,y_inv]}[follower_cost(z) − oracle_welfare(z)], never
        # the recourse AT WHATEVER z THE MASTER'S CURRENT TRIAL HAPPENED TO PICK
        # (Q_nu_iterate above — an UPPER-BOUND surrogate, since the master's box only
        # guarantees z <= y_inv, not z = the minimizer). Passing the upper-bound
        # surrogate permanently over-constrains θ at that corner once the cut is
        # appended (cut rows are never retracted) — see
        # test/test_planning_certification_integer.jl's file header for the full
        # diagnosis this fix resolves. `ll_cut_recourse` is a TRUE no-op for
        # BendersMaster (returns Q_nu_iterate UNCHANGED, touches ZERO oracle/follower
        # state — the continuous path is BYTE-IDENTICAL to before this fix); for
        # BendersMasterInteger it performs the real minimization via the SAME
        # deterministic ternary-search technique as
        # test_planning_certification_integer.jl's own `enumerate_lattice` reference
        # implementation, reusing the REAL, already-built `oracle`/`follower` (never
        # rebuilt, never a closed-form shortcut).
        t0_ns = time_ns()
        Q_nu = ll_cut_recourse(master, oracle, follower, lb_res, Q_nu_iterate)
        t_solve += (time_ns() - t0_ns) / 1.0e9

        integer_cut_res = apply_integer_cuts!(master, lb_res, Q_nu)
        integer_cut_res.nogood_fired && (nogood_total += 1)

        # CR-01: track the incumbent, not just the bound — store the (y, z) pair that
        # achieved the running-minimum UB so the converged return is the certified point.
        cost_k = master.c_y * lb_res.y + Q_nu_iterate
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
        # status (never the :not_solved sentinel on this branch). nogood_count (Phase 24,
        # plan 24-04, D-16) records THIS iteration's no-good firing (0 or 1) — always 0 on
        # the continuous path.
        push!(
            trace,
            k;
            LB = lb_res.LB,
            UB = UB,
            gap = gap,
            cut_type = :optimality,
            n_cuts = length(master.cuts),
            # CR-01: the status captured immediately after solve_master!, before the
            # add_optimality_cut! calls dirtied the model. oracle_status_k was captured
            # immediately after the oracle's OWN solve at lb_res.z, BEFORE
            # ll_cut_recourse's (Phase 24 gap-closure, plan 24-05.1) BendersMasterInteger
            # branch potentially re-solves oracle.model at OTHER z trials during its
            # internal ternary search — querying termination_status(oracle.model) HERE
            # instead would silently report the LAST such trial's status.
            master_status = master_status_k,
            oracle_status = oracle_status_k,
            retry_count = (master_attempts[] - 1) + (oracle_attempts[] - 1),
            solve_time = t_solve,
            nogood_count = integer_cut_res.nogood_fired ? 1 : 0,
        )

        # Phase 24, plan 24-04 (D-13/D-14, plan-checker Blocker 2): an EXCLUSIVE branch,
        # NEVER an `||` of the two criteria — reusing `tol` on the `known_optimum`-supplied
        # (certified) path would silently reintroduce the continuous loop's tolerance on
        # exactly the path this mechanism exists to keep tolerance-free. When
        # known_optimum === nothing, this reduces EXACTLY to `gap <= tol`, byte-identical
        # to the pre-Phase-24 behavior.
        converged_now =
            known_optimum === nothing ? (gap <= tol) :
            isapprox(UB, known_optimum; atol = KNOWN_OPTIMUM_ATOL)

        if converged_now
            # CR-01: return the INCUMBENT — c(y_best, z_best) = UB <= LB + tol*max(1,|UB|)
            # (continuous path) or UB matches known_optimum exactly within
            # KNOWN_OPTIMUM_ATOL (certified path); the current iterate (lb_res.y,
            # lb_res.z) carries no such guarantee.
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
                # Phase 24, plan 24-04 (D-16): appended AFTER every existing field so
                # every prior caller destructuring by name is unaffected (NamedTuple
                # field access is name-based, never position-based).
                nogood_count = nogood_total,
                converged_via = nogood_total > 0 ? :nogood_assisted : :clean,
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
