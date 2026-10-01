# src/planning/benders.jl
#
# SEAM: solve_stackelberg! — the outer Benders orchestration loop wiring the reused
# operational oracle (PlanningOracle, Phase 10), the new transmission-reinforcement
# follower (FollowerLP, plan 11-01), and the new Benders master (BendersMaster, plan
# 11-01) into a single-distributor Stackelberg equilibrium (PLAN-06).
# OWNER: plan 11-02.
#
# HONEST RELABELLING (Phase 29, BILEV-01 API decision, comment/docstring-only diff):
# despite its "Stackelberg" name, `solve_stackelberg!` solves THE INTEGRATED PROBLEM,
# BENDERS-DECOMPOSED, not a genuinely bilevel game — see `solve_stackelberg!`'s own
# docstring below and `src/planning/bilevel_kkt.jl`'s module header for the genuinely
# bilevel variant and why plain Benders is invalid there.
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

# ---------------------------------------------------------------------------------------
# Phase 27 (plan 27-01, FIX-06) — the T>1 generalization of corner_recourse: replaces the
# scalar `fill(z, T)` surrogate with a genuine joint T-dimensional convex minimization
# `Q(y_inv) = min_{z∈[0,y_inv]^T} [follower_cost(z) - oracle_welfare(z)]`, via a Kelley's
# cutting-plane ("bundle") loop reusing the SAME solve_follower!/solve_planning_oracle!
# dual reads already used by the outer Benders loop's own :x/:op cuts (benders.jl:299-301/
# 530-533) as a first-order (value+gradient) oracle for Q. See 27-RESEARCH.md's
# "Architecture Patterns FIX-06" for the full derivation this implements.
# ---------------------------------------------------------------------------------------

# EMPIRICALLY MEASURED (2026-09-29) on a T=2 PVBattery-bearing (genuinely non-separable
# across hours via its soc[t+1] recursion) fixture — two-bus feeder,
# `PVBattery(bus=2, η=0.95, Δt=1, Pmax=5, Emin=0, Emax=10, soc0=2, λ=(1,4,9), Ppv=[3,3])`,
# aggregator net-load `[3.5, 3.5]`, follower `corridor_cap=x_inv_max=2, c_inv=1,
# c_op=[0.5,0.5]`, oracle `λ₀=[4,4]` — solving the follower (HiGHS LP) and oracle
# (Clarabel SOCP) once each at four representative interior trials
# (`z ∈ {[1,1],[0.2,0.2],[1.5,0.5],[0.5,1.5]}`) and reading each solver's OWN certified
# primal/dual objective gap directly (`abs(objective_value(model) -
# dual_objective_value(model))` — no second reference solve needed):
#   gap_follower = 0.0                    (HiGHS LP — exact simplex, zero measured gap)
#   gap_oracle   <= 1.2219521394740696e-8 (Clarabel SOCP, worst of the 4 sampled trials)
# Per the SAME measurement formula `max(1e-9, 10 * max(gap_follower, gap_oracle))`
# `KNOWN_OPTIMUM_ATOL` above uses, the joint cutting-plane loop's own UB-LB convergence
# gate is set to the measured value below.
const JOINT_RECOURSE_GAP_TOL = 1.2219521394740696e-7

# CR-01 fix (27-REVIEW.md, 2026-09-29): bound on how many successive bisection halvings
# the oracle-infeasible-no-certificate stall guard (below) will attempt before giving up
# and raising a diagnostic error, rather than silently making zero progress forever. Not a
# measured tolerance like JOINT_RECOURSE_GAP_TOL above -- it is a hard IEEE-754 double
# bound: halving ANY bounded bracket `[z_lo, z_hi]` this many times drives `z_mid` to be
# bit-identical to one endpoint (a double has 52 mantissa bits; 64 halvings exhausts any
# representable gap even for extreme exponents), so termination is guaranteed independent
# of `iters` and independent of the fixture's scale.
const JOINT_RECOURSE_BISECT_MAX_DEPTH = 64

"""
    corner_recourse(oracle, follower, y_inv::Real, T::Int; iters::Int = 100) -> Float64

The TRUE per-corner minimized recourse
`Q(y_inv) = min_{z ∈ [0, y_inv]^T} [follower_cost(z) − oracle_welfare(z)]`, computed over
the REAL, already-built `oracle`/`follower` (the SAME production
`solve_planning_oracle!`/`solve_follower!` entrypoints used everywhere else in the
Benders loop — never rebuilt, never a closed-form shortcut).

**T==1/T>1 dispatch (Phase 27, plan 27-01, FIX-06):**

  - `T == 1` calls the EXISTING deterministic ternary-search body, UNCHANGED, byte-for-
    byte identical to its pre-Phase-27 output (see [`_corner_recourse_ternary`](@ref)) —
    mirrors `test/test_planning_certification_integer.jl`'s own `enumerate_lattice`
    reference implementation's `Qfun`/`ternary_min` technique EXACTLY (that file's logic,
    promoted from test-only certification code into production so `add_ll_cut!`'s caller
    finally honors its own documented precondition, `Q_nu = Q(b^ν)`, "never estimated
    here" — Phase 24 gap-closure 24-05.1). `Q` is convex in `z` whenever the oracle's
    welfare is concave and the follower's cost is convex — the SAME convexity argument
    `add_optimality_cut!`'s own docstring already establishes for `Q(y_inv)` over the
    continuous relaxation — so ternary search on `[0, y_inv]` converges to the true
    minimum.
  - `T > 1` calls [`_corner_recourse_joint`](@ref), a NEW Kelley's-method cutting-plane
    ("bundle") loop performing the GENUINE joint T-dimensional minimization over the
    shared hypercube `[0, y_inv]^T` (a SINGLE scalar `y_inv` bounds every one of the
    master's `T` box constraints, `master_integer.jl:107-156` — never per-hour-
    independent boxes). Any aggregator with a `PVBattery`/`FourQuadBESS`/`Deferrable`
    member couples hours via `soc[t+1]`, so `oracle_welfare(z)` is in general NOT
    separable across `t` — pinning a single scalar trial across all `T` hours (the
    pre-Phase-27 `fill(z, T)` surrogate, now REMOVED for `T > 1`) silently gives the
    WRONG answer on exactly this common case (27-RESEARCH.md Pitfall FIX-06-1). The two
    dispatch branches are DELIBERATELY not unified into one algebraically-equivalent
    body: different floating-point trajectories would break the `T == 1` byte-identity
    requirement even where mathematically equivalent (27-RESEARCH.md "T=1 byte-identical
    requirement").

Both branches treat a follower-infeasible trial `z` (`solve_follower!`'s genuine
`feasible = false` branch) as `+Inf` in the extended-value sense (the SAME Rule-1 device
`enumerate_lattice` uses) — mathematically sound because `z = zeros(T)` is always
follower-feasible, so the feasible sub-region containing the true minimizer is always
nonempty.

`y_inv <= 0` collapses the feasible region to the single point `z = zeros(T)` — the
recourse there is GENUINELY COMPUTED (one real solve of `follower`/`oracle`), never
assumed to be `0.0` (CR-01, Phase 24 code review) — see `docs/literate/integer_investment.jl`'s
own independently-found fix for the historical rationale.
"""
function corner_recourse(oracle, follower, y_inv::Real, T::Int; iters::Int = 100)
    if T == 1
        return _corner_recourse_ternary(oracle, follower, y_inv, T; iters = iters)
    else
        return _corner_recourse_joint(oracle, follower, y_inv, T; iters = iters)
    end
end

"""
    _corner_recourse_ternary(oracle, follower, y_inv::Real, T::Int; iters::Int = 100) -> Float64

The PRE-PHASE-27 `T == 1` ternary-search body, copied VERBATIM (byte-for-byte identical
floating-point trajectory) into its own named function per [`corner_recourse`](@ref)'s
dispatch — see that function's docstring for the full WR-01/CR-01 rationale. Never called
with `T != 1` (the `fill(z, T)` scalar-pinning here is exactly the surrogate FIX-06 removes
for `T > 1`; it remains correct-by-definition at `T == 1`, where pinning the single scalar
`z` across "all `T` periods" is a no-op).
"""
function _corner_recourse_ternary(oracle, follower, y_inv::Real, T::Int; iters::Int = 100)
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

    # WR-01 (Phase 24 code review): fail LOUDLY rather than silently propagate a
    # divergence. The follower is documented to always be feasible at z=0, so
    # Q(y_inv) can never legitimately be non-finite for y_inv >= 0 -- a non-finite
    # result here is proof of a search bug, not a legitimate value.
    check_finite(Qv::Real, z::Real) =
        isfinite(Qv) || throw(
            ErrorException(
                "corner_recourse: recourse evaluated to a non-finite value at z=$z " *
                "(y_inv=$y_inv) -- the follower is documented to always be feasible " *
                "at z=0, so this should be unreachable; report as a bug (WR-01 " *
                "regression, Phase 24 code review).",
            ),
        )

    # Phase 24 code-review fix (CR-01): compute the zero-corner recourse for real via
    # Qfun(0.0) instead of assuming it is 0.0 -- see the docstring above for the full
    # rationale. This is exact by construction (Qfun is the same function used by the
    # ternary search below), not a special-cased approximation.
    if y_inv <= 0
        Qv = Qfun(0.0)
        check_finite(Qv, 0.0)
        return Qv
    end

    lo, hi = 0.0, Float64(y_inv)
    for _ in 1:iters
        m1 = lo + (hi - lo) / 3
        m2 = hi - (hi - lo) / 3
        f1, f2 = Qfun(m1), Qfun(m2)
        # WR-01 fix (see docstring): a double-infinite tie must shrink from the right
        # (toward the guaranteed-feasible z=0 anchor), never fall through to the
        # ordinary else-branch (lo = m1), which would walk away from feasibility and
        # diverge on a bounded interval.
        if isinf(f1) && isinf(f2)
            hi = m2
        elseif f1 < f2
            hi = m2
        else
            lo = m1
        end
    end
    zstar = (lo + hi) / 2
    Qv = Qfun(zstar)
    check_finite(Qv, zstar)
    return Qv
end

"""
    _corner_recourse_joint(oracle, follower, y_inv::Real, T::Int; iters::Int = 100) -> Float64

The `T > 1` joint T-dimensional minimization `Q(y_inv) = min_{z ∈ [0, y_inv]^T} [follower_cost(z) − oracle_welfare(z)]`, via a Kelley's-method cutting-plane ("bundle")
loop: at each trial `z`, one call each to `solve_follower!`/`solve_planning_oracle!`
yields BOTH `Q(z) = fr.cost − orr.cost` AND its EXACT gradient
`∇Q(z) = fr.π_s .+ orr.π` (elementwise, length T) — the SAME dual reads
`add_optimality_cut!`'s `:x`/`:op` cuts already use for the OUTER Benders loop
(`benders.jl:299-301/530-533`), reused here as a zero-extra-solve first-order oracle for
the convex value function `Q` (convexity: the SAME parametric-value-function/sensitivity
argument `add_optimality_cut!`'s own docstring already establishes for `Q(y_inv)` over the
continuous relaxation of `y_inv`, one level down — over `z` at fixed `y_inv` — since
`master_integer.jl`'s box is the JOINT hypercube `0 <= z[t] <= y_inv ∀t`, not per-hour
independent boxes).

Each outer iteration rebuilds a SMALL cutting-plane master LP FRESH — `Min θ` subject to
`θ >= Q_j + g_j'(z − z_j)` for every accumulated finite (epigraph) cut, `v_k + u_k'(z − z_k) <= 0` for every accumulated FOLLOWER feasibility cut (see below), and
`0 <= z[t] <= y_inv ∀t` — via the SAME `select_optimizer(LP())` factory
`src/planning/follower.jl` uses (never `Model(HiGHS.Optimizer)` directly). This is a
CHEAP, T-variable, at-most-`iters`-row bookkeeping LP, deliberately NOT the expensive
build-once model this project's "build once, re-solve many" convention protects (the
oracle/follower themselves ARE build-once, re-solved via `set_parameter_value.`; only
THIS small inner-loop LP is rebuilt per outer iteration, by design, per plan discretion).

**Infeasible-trial handling (27-RESEARCH.md Pitfall FIX-06-2, generalized):**

  - A FOLLOWER-infeasible trial (`solve_follower!`'s genuine `feasible = false` branch,
    e.g. a `y_inv` large enough that some `z` in the hypercube exceeds the follower's own
    deliverable capacity `corridor_cap * x_inv_max`) contributes NO epigraph cut (an
    `Inf` affine minorant is meaningless) — but its GENUINE Farkas certificate
    (`fr.v`, `fr.u`) IS added as a REAL linear feasibility cut to the small master,
    `v_k + u_k'(z − z_k) <= 0`, the IDENTICAL cut form [`add_feasibility_cut!`](@ref)
    already uses for the OUTER Benders master (`src/planning/master.jl:209-242`). This
    is a deliberate strengthening beyond a bare "skip": without it, the small master's
    deterministic LP would re-propose the IDENTICAL infeasible corner every subsequent
    iteration (no new information ever excludes it), stalling until `iters` exhausts for
    no reason — the SAME certificate already computed for the caller's own feasibility-
    cut branch is reused here at zero extra cost.
  - An ORACLE-infeasible trial (`solve_planning_oracle!` throwing — e.g. a genuine
    network-balance infeasibility unreachable via the follower's own, purely economic,
    capacity model; CONFIRMED to occur on realistic non-separable battery fixtures
    whenever the follower-feasible box extends beyond what the NETWORK can physically
    accept) is caught and ALSO treated as `+Inf`/no epigraph cut — but NO certificate is
    available here (`solve_planning_oracle!` has no structured infeasible return), so it
    contributes NO cut of ANY kind. If the SAME trial is proposed twice in a row this way
    (a genuine stall — the master has zero new information to move away from it), a
    T-dimensional generalization of the ternary search's own WR-01 double-infinite
    tie-break applies: bisect toward the guaranteed-feasible incumbent `z_best` (the SAME
    "shrink toward the known-feasible anchor" principle, one dimension per coordinate
    instead of one). CR-01 fix (27-REVIEW.md): this bisection is genuinely ITERATIVE, not
    single-shot — if a midpoint is *itself* oracle-infeasible with no certificate, the
    bracket shrinks toward `z_best` and a NEW midpoint is tried, up to
    `JOINT_RECOURSE_BISECT_MAX_DEPTH` halvings, before giving up with a diagnostic error
    that clearly distinguishes "stalled, no progress possible" (this branch) from "gap not
    yet met" (the `iters`-exhaustion branch below). A single bisection step is NOT
    sufficient in general: nothing guarantees the first midpoint is feasible, and a
    single-shot version would silently make zero progress and loop until `iters` exhausted
    for no reason whenever it isn't.

`y_inv <= 0` collapses `[0, y_inv]^T` to the single point `z = zeros(T)` — genuinely
computed (never assumed `0.0`), matching [`_corner_recourse_ternary`](@ref)'s own CR-01
treatment. The FIRST trial (before any master solve) is always `z = zeros(T)` (the
guaranteed-feasible WR-01 anchor), so at least one finite epigraph cut always exists
before the loop's first master solve.

Terminates when `UB − LB <= JOINT_RECOURSE_GAP_TOL` (a MEASURED, not guessed, constant —
see the comment immediately above its definition) or after `iters` outer iterations,
whichever comes first; on exhausting `iters` without meeting the tolerance, raises a loud
`ErrorException` naming the achieved gap (never silently returns an unconverged value).
"""
function _corner_recourse_joint(oracle, follower, y_inv::Real, T::Int; iters::Int = 100)
    # Evaluate Q(z) and its gradient at a trial z::Vector{Float64}. See the docstring
    # above ("Infeasible-trial handling") for the full rationale of each branch.
    function evaluate(z::Vector{Float64})
        fr = solve_follower!(follower, z)
        if !fr.feasible
            return (;
                Qz = Inf,
                gradQ = nothing,
                feas_cut = (; v = fr.v, u = fr.u, z_k = copy(z)),
            )
        end
        orr = try
            solve_planning_oracle!(oracle, z)
        catch
            # Pitfall FIX-06-2 generalized (docstring above): an ORACLE-side
            # infeasibility (or any other trust-gate throw) is extended-value +Inf,
            # exactly like a follower infeasibility, but carries no certificate.
            return (; Qz = Inf, gradQ = nothing, feas_cut = nothing)
        end
        Qz = fr.cost - orr.cost
        gradQ = fr.π_s .+ orr.π   # elementwise, length T (docstring's dual-read pattern)
        return (; Qz, gradQ, feas_cut = nothing)
    end

    # WR-01 T-dimensional analogue: fail LOUDLY rather than silently propagate a
    # divergence -- the anchor z=zeros(T) is documented to always be follower- AND
    # oracle-feasible, so a non-finite result there is proof of a search bug.
    check_finite(Qv::Real, z::AbstractVector) =
        isfinite(Qv) || throw(
            ErrorException(
                "_corner_recourse_joint: recourse evaluated to a non-finite value at " *
                "z=$z (y_inv=$y_inv, T=$T) -- the anchor z=zeros(T) is documented to " *
                "always be follower- and oracle-feasible, so this should be " *
                "unreachable; report as a bug (T-dimensional generalization of WR-01, " *
                "Phase 27 FIX-06).",
            ),
        )

    # CR-01 T-dimensional analogue: y_inv <= 0 collapses [0, y_inv]^T to the single
    # point z = zeros(T) -- genuinely COMPUTED via evaluate, never assumed.
    if y_inv <= 0
        r0 = evaluate(zeros(T))
        check_finite(r0.Qz, zeros(T))
        return r0.Qz
    end

    y_inv_f = Float64(y_inv)
    cuts = Tuple{Vector{Float64}, Float64, Vector{Float64}}[]        # (z_k, Q_k, gradQ_k)
    feas_cuts = Tuple{Float64, Vector{Float64}, Vector{Float64}}[]   # (v_k, u_k, z_k)

    # WR-01 T-dimensional anchor: the FIRST trial is zeros(T), the guaranteed-feasible
    # point -- at least one finite epigraph cut always exists before the first master
    # solve.
    z_trial = zeros(T)
    r0 = evaluate(z_trial)
    check_finite(r0.Qz, z_trial)
    push!(cuts, (copy(z_trial), r0.Qz, r0.gradQ))
    UB = r0.Qz
    z_best = copy(z_trial)
    last_skipped = nothing   # anti-stall guard (see docstring's oracle-infeasible case)

    for _ in 1:iters
        # Rebuild the small master LP FRESH each outer iteration (plan discretion,
        # deliberately distinct from the BUILD-ONCE convention this project otherwise
        # protects for the oracle/follower's own expensive models -- this is a cheap,
        # T-variable, at-most-`iters`-row bookkeeping LP, never the expensive
        # build-once model the project's "build once, re-solve many" rule is about).
        mmodel = Model(select_optimizer(LP()))
        @variable(mmodel, 0 <= zz[t = 1:T] <= y_inv_f)
        @variable(mmodel, θ)
        for (z_k, Q_k, g_k) in cuts
            @constraint(mmodel, θ >= Q_k + sum(g_k[t] * (zz[t] - z_k[t]) for t in 1:T))
        end
        for (v_k, u_k, z_k) in feas_cuts
            @constraint(mmodel, v_k + sum(u_k[t] * (zz[t] - z_k[t]) for t in 1:T) <= 0)
        end
        @objective(mmodel, Min, θ)
        optimize!(mmodel)
        is_solved_and_feasible(mmodel) || error(
            "_corner_recourse_joint: the small cutting-plane master LP failed to " *
            "solve (status=$(termination_status(mmodel))) at y_inv=$y_inv, T=$T -- " *
            "report as a bug.",
        )
        LB = objective_value(mmodel)
        z_next = value.(zz)

        r = evaluate(z_next)
        if isfinite(r.Qz)
            push!(cuts, (copy(z_next), r.Qz, r.gradQ))
            if r.Qz < UB
                UB = r.Qz
                z_best = copy(z_next)
            end
            last_skipped = nothing
        elseif r.feas_cut !== nothing
            push!(feas_cuts, (r.feas_cut.v, r.feas_cut.u, r.feas_cut.z_k))
            last_skipped = nothing
        else
            # ORACLE-infeasible, no certificate (docstring's second bullet): if this is
            # the SAME trial skipped last iteration (no new information was added to
            # the master in between, so it deterministically re-proposed the identical
            # point), bisect toward the guaranteed-feasible incumbent z_best instead of
            # spinning until `iters` exhausts for no reason.
            #
            # CR-01 fix (27-REVIEW.md): a SINGLE bisection step is not guaranteed to
            # land on a feasible/certified midpoint -- the midpoint itself can ALSO be
            # oracle-infeasible with no certificate. The old single-shot version added
            # NO cut in that case and reset last_skipped to the SAME z_next, so the
            # (deterministic, unchanged) master LP re-proposed the identical trial every
            # remaining outer iteration -- zero progress until `iters` exhausted. Fix:
            # keep halving the bracket [z_best, z_next] toward the feasible anchor,
            # trying a NEW midpoint each time, until a cut of either kind is produced
            # (guaranteed progress -> break out and continue the outer loop) or
            # JOINT_RECOURSE_BISECT_MAX_DEPTH halvings are exhausted (guaranteed
            # termination -- see that constant's comment -- with a diagnostic error that
            # names this as a genuine stall, distinct from "gap not yet met").
            if last_skipped !== nothing && maximum(abs, z_next .- last_skipped) <= 1e-9
                progressed = false
                z_lo = copy(z_best)   # guaranteed follower- and oracle-feasible anchor
                z_hi = copy(z_next)   # stalled: oracle-infeasible, no certificate
                for _ in 1:JOINT_RECOURSE_BISECT_MAX_DEPTH
                    z_mid = (z_lo .+ z_hi) ./ 2
                    r_mid = evaluate(z_mid)
                    if isfinite(r_mid.Qz)
                        push!(cuts, (copy(z_mid), r_mid.Qz, r_mid.gradQ))
                        if r_mid.Qz < UB
                            UB = r_mid.Qz
                            z_best = copy(z_mid)
                        end
                        progressed = true
                        break
                    elseif r_mid.feas_cut !== nothing
                        push!(
                            feas_cuts,
                            (r_mid.feas_cut.v, r_mid.feas_cut.u, r_mid.feas_cut.z_k),
                        )
                        progressed = true
                        break
                    else
                        # z_mid is ALSO oracle-infeasible with no certificate: shrink
                        # the bracket toward the known-feasible anchor and retry -- this
                        # NEVER re-tests z_hi's own value again, which is what
                        # guarantees eventual termination (see the constant's comment).
                        z_hi = z_mid
                    end
                end
                if !progressed
                    error(
                        "_corner_recourse_joint: stalled at z=$z_next (y_inv=$y_inv, " *
                        "T=$T) -- $JOINT_RECOURSE_BISECT_MAX_DEPTH successive " *
                        "bisections toward the feasible anchor z_best=$z_best all " *
                        "remained oracle-infeasible with no Farkas certificate; no " *
                        "further progress is possible without more information. This " *
                        "is a genuine stall (distinct from 'gap not yet met') -- " *
                        "report as a bug or relax/inspect the fixture.",
                    )
                end
            end
            last_skipped = copy(z_next)
        end

        gap = UB - LB
        if gap <= JOINT_RECOURSE_GAP_TOL
            check_finite(UB, z_best)
            return UB
        end
    end

    error(
        "_corner_recourse_joint: exhausted $iters iteration(s) without meeting the " *
        "measured gap tolerance JOINT_RECOURSE_GAP_TOL=$JOINT_RECOURSE_GAP_TOL at " *
        "y_inv=$y_inv (T=$T) -- refusing to silently return a non-converged result.",
    )
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
ll_cut_recourse(::BendersMaster, oracle, follower, lb_res, Q_nu_iterate::Real) =
    Q_nu_iterate

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
    _assert_epigraph_floor(cost_k::Real, lb::Real, label::Symbol;
                           tol::Real = ALPHA_LB_REJECTION_TOL)

Phase 30 (BILEV-05, plan 30-04): a UNIVERSAL, bound-source-independent runtime sanity
check — `error(...)`s if `cost_k < lb - tol`, naming `label` (`:op`/`:x`), the evaluated
`cost_k`, and the declared `lb`. Reuses `ALPHA_LB_REJECTION_TOL` (`master.jl`, plan
30-02) as its default tolerance — the SAME measured solver-tolerance-scale constant,
never a second, drifting one.

Called UNCONDITIONALLY on `solve_stackelberg!`'s optimality branch (Task 1, this plan),
regardless of whether `master.α_op`/`master.α_x`'s declared lower bound came from
`:auto`, an explicit `Real`, or was build-time-validated via `bounds_ctx` at all — a
genuine lower bound, by definition, can never exceed an actually-achieved cost at a
feasible point. If this ever fires, it is proof of a modeling bug in the derivation or
declaration of that bound (BILEV-05's own core-value risk: "an invalid declared lower
bound silently produces a wrong 'converged' answer"), never a legitimate convergence
edge case to special-case away.
"""
function _assert_epigraph_floor(
    cost_k::Real,
    lb::Real,
    label::Symbol;
    tol::Real = ALPHA_LB_REJECTION_TOL,
)
    cost_k < lb - tol && error(
        "solve_stackelberg!: epigraph $label evaluated to cost_k=$cost_k, below its " *
        "OWN declared lower bound lb=$lb (tol=$tol) — BILEV-05: this is a genuine " *
        "modeling bug (an invalid declared lower bound), not a convergence issue. " *
        "Never silently accepted.",
    )
    return nothing
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

**Honest relabelling (Phase 29, BILEV-01 API decision):** this function solves THE
INTEGRATED PROBLEM, BENDERS-DECOMPOSED — the follower's own true cost is fed directly
into the leader's Benders epigraph, which is only valid because leader and follower
share the same underlying objective here (there is no separate tariff wedge). It is
NOT a genuinely bilevel game, despite the "Stackelberg" name. For a genuinely bilevel
TSO-DSO variant, where the follower minimizes its OWN cost `c(z) - pi_tariff*z` that
differs from the leader's own valuation of `z`, see
[`solve_bilevel!`](@ref)/[`build_bilevel_kkt`](@ref) (`src/planning/bilevel_kkt.jl`,
plan 29-01) — a single-level KKT-MILP, not a Benders loop, because plain Benders is
invalid on that genuinely divergent-objective game (see that file's module header).

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
    inexact_policy::Symbol = :certify_incumbent,
)
    # ---- Boundary guards (mirror solve_admm): fail here, not deep in the loop ----------------
    T >= 1 || throw(ArgumentError("solve_stackelberg! needs T >= 1 (got T=$T)"))
    # Phase 30 (BILEV-04b, plan 30-04): inexact_policy must be one of the three
    # documented dispatches — fail here, alongside the other boundary checks, BEFORE
    # any build call (never deep inside the loop's oracle-throw disambiguation).
    inexact_policy in (:strict, :reject, :certify_incumbent) || throw(
        ArgumentError(
            "solve_stackelberg! needs inexact_policy in (:strict, :reject, " *
            ":certify_incumbent), got $inexact_policy",
        ),
    )
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
        # Phase 30 (BILEV-04a/BILEV-04b, plan 30-04): clear any STALE :socp_maxgap key
        # left over from a PRIOR iteration's success before this iteration's solve, so
        # the disambiguation below (this plan's <interfaces> recipe) can tell "exactness
        # already passed THIS iteration" apart from a stale leftover.
        delete!(oracle.ctx.meta, :socp_maxgap)
        # Per-iteration policy bookkeeping (Phase 30, BILEV-04b): overwritten below only
        # on the branches that actually engage inexact_policy; :none/NaN on every
        # ordinary success path, mirroring every other sentinel default in this loop.
        policy_action_k = :none
        socp_maxgap_k = NaN
        t0_ns = time_ns()
        oracle_res = try
            solve_planning_oracle!(oracle, lb_res.z; attempts_out = oracle_attempts)
        catch e
            e isa ErrorException || rethrow()
            # Disambiguation recipe (this plan's own <interfaces> block): uses ONLY
            # information solve_planning_oracle! ALREADY computes — no string-matching
            # on the error message, no duplicated tolerance logic.
            if !is_solved_and_feasible(oracle.model; dual = true)
                # The trusted-solve gate itself failed -> a genuine MOI.INFEASIBLE (or a
                # non-retryable solver failure), the exactness gate never ran.
                # TODO(plan 30-04 Task 2): route to the NEW oracle-feasibility-cut branch
                # (BILEV-04a) instead of rethrowing — Task 1 of this plan scopes the
                # exactness-policy half only, independently verifiable on its own.
                rethrow()
            elseif haskey(oracle.ctx.meta, :socp_maxgap)
                # Exactness ALREADY passed THIS iteration (the key got set) -> the throw
                # came from assert_battery_complementarity! or something else entirely ->
                # OUT OF SCOPE for inexact_policy; never silently swallowed.
                rethrow()
            else
                # Trusted solve, exactness ITSELF failed (assert_socp_exact! threw) ->
                # genuine exactness-class throw -> dispatch on inexact_policy (BILEV-04b).
                if inexact_policy === :strict
                    rethrow()   # byte-identical to today's throw
                elseif inexact_policy === :reject
                    # Skip the inexact cut entirely this iteration (no add_optimality_cut!
                    # for :op/:x) — checkpoint with feasible=false-equivalent semantics,
                    # reusing the SAME checkpoint_iteration! call shape as the existing
                    # feasibility branch, record the :rejected trace row, and `continue`
                    # (never update UB, mirrors T-11-06's existing feasibility-cut
                    # discipline). `continue` here means the post-try/catch `t_solve`
                    # accumulation below is never reached on THIS path — record it now.
                    t_solve += (time_ns() - t0_ns) / 1.0e9
                    checkpoint_iteration!(
                        (;
                            k,
                            LB = lb_res.LB,
                            UB,
                            gap = NaN,
                            z_k = lb_res.z,
                            feasible = false,
                        ),
                        k;
                        dir = checkpoint_dir,
                    )
                    push!(
                        trace,
                        k;
                        LB = lb_res.LB,
                        UB = UB,
                        gap = NaN,
                        cut_type = :rejected,
                        n_cuts = length(master.cuts),
                        master_status = master_status_k,
                        oracle_status = Symbol(termination_status(oracle.model)),
                        retry_count = master_attempts[] - 1,
                        solve_time = t_solve,
                        policy_action = :rejected,
                        socp_maxgap = socp_relaxation_gap(oracle.ctx),
                    )
                    continue   # T-11-06 analogue: a rejected trial NEVER updates UB
                else   # :certify_incumbent (the default)
                    # The underlying oracle.model IS still solved and trustworthy — only
                    # the Julia-level exception prevented solve_planning_oracle! from
                    # returning it. Reconstruct the NamedTuple it would have returned
                    # (this plan's own <interfaces> recipe) directly off the model.
                    π = dual.(oracle.pin)
                    cost = objective_value(oracle.model)
                    dadp = dual.(oracle.ctx.constraints[:balance_p][oracle.agg_bus, :])
                    socp_maxgap_k = socp_relaxation_gap(oracle.ctx)
                    policy_action_k = :certified_incumbent
                    (; cost, π, π_s = sum(π), dadp, ctx = oracle.ctx)
                end
            end
        end
        t_solve += (time_ns() - t0_ns) / 1.0e9
        # Phase 24 gap-closure (plan 24-05.1): capture oracle.model's GENUINE
        # termination status HERE, immediately after ITS OWN solve at lb_res.z —
        # mirrors master_status_k's own CR-01 capture-before-mutation discipline
        # above. `ll_cut_recourse` below (BendersMasterInteger path only) re-solves
        # oracle/follower at OTHER z trials during its internal ternary search;
        # querying termination_status(oracle.model) AFTER that point would silently
        # report the LAST ternary-search trial's status instead of lb_res.z's own.
        oracle_status_k = Symbol(termination_status(oracle.model))

        # Phase 30 (BILEV-05, plan 30-04): the UNIVERSAL runtime epigraph floor guard —
        # unconditional, independent of whether master.α_op/master.α_x's declared lower
        # bound came from :auto, an explicit Real, or was build-time-validated at all,
        # and independent of inexact_policy. oracle_res/follower_res are known-
        # trustworthy here (either the ordinary success path above, or the
        # :certify_incumbent reconstruction off the already-solved oracle.model).
        _assert_epigraph_floor(-oracle_res.cost, lower_bound(master.α_op), :op)
        _assert_epigraph_floor(follower_res.cost, lower_bound(master.α_x), :x)

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
            # Phase 30 (BILEV-04b, plan 30-04): :none/NaN on the ordinary success path
            # (byte-identical to pre-30-04 behavior); :certified_incumbent/a finite gap
            # when inexact_policy's :certify_incumbent branch fired this iteration.
            policy_action = policy_action_k,
            socp_maxgap = socp_maxgap_k,
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
