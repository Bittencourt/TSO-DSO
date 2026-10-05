# src/planning/benders.jl
#
# SEAM: solve_stackelberg! — the outer Benders orchestration loop wiring the reused
# operational oracle (PlanningOracle), the new transmission-reinforcement
# follower (FollowerLP), and the new Benders master (BendersMaster) into a
# single-distributor Stackelberg equilibrium.
#
# HONEST RELABELLING (API decision):
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
# CONVERGENCE CRITERION IS STRUCTURALLY DIFFERENT FROM ADMM's residual test: the UB/LB relative gap `(UB - LB) / max(1, |UB|) <= tol` (locked
# default 1e-6), never `AdmmResiduals`.
#
# SIGN CONVENTION CONSUMED VERBATIM FROM THE FOLLOWER MODEL (NOT
# re-derived here): the oracle's `:op` epigraph cut uses `cost_k = -oracle_res.cost`,
# `grad_k = oracle_res.π` (UNNEGATED) — `solve_planning_oracle!` returns a MAX-sense
# welfare value and its already-negated-Max-dual gradient; the master's
# epigraph is a MIN-sense cost-to-go, hence the negation on `cost_k` only. The follower's
# `:x` epigraph cut uses `cost_k = follower_res.cost` and `grad_k = follower_res.π_s` EXACTLY
# as `solve_follower!` returns them (its own empirically-pinned positive dual sign) — no further sign transformation.
#
# EVERY CUT-PRODUCING SOLVE ROUTES THROUGH THE CORRECT GATE: `solve_planning_oracle!`/`solve_master!` are gated internally by
# `solve_with_retry!`/strict `assert_solved!`; `solve_follower!` is called DIRECTLY
# here — NEVER wrapped in `solve_with_retry!` — because its infeasible branch must be
# OBSERVED, not retried away, or the Farkas certificate it requires is unreachable.
#
# CHECKPOINTING: `checkpoint_iteration!` fires EXACTLY ONCE per Benders iteration,
# from both the feasibility-cut branch and the optimality-cut branch (a
# feasibility cut never updates `UB` — the loop `continue`s immediately after checkpointing,
# skipping the `UB = min(...)` line entirely).

using JuMP
using DrWatson: datadir

# A NEW, dedicated termination threshold for the
# lattice-exact `known_optimum` certification fallback — deliberately DISTINCT from the
# `tol` kwarg's inherited `1e-6` continuous relative-gap tolerance, so it can never be
# mistaken for "reusing" that tolerance (the standing anti-certificate-laundering bar).
#
# EMPIRICALLY MEASURED (2026-08-23) on the two-bus fixture (`TwoBusFixtures.two_bus_feeder`
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
# exactly the failure mode found earlier in `fit_baseline`. Per the
# measurement formula `max(1e-9, 10 * max(gap_oracle, gap_follower))`, the constant is set
# to the measured value below, not a hopeful guess.
const KNOWN_OPTIMUM_ATOL = 3.957388639008741e-8

# ---------------------------------------------------------------------------------------
# Fix for the LL-cut Q_nu defect found by the enumeration-backed certification in the
# earlier integer-cut code: `apply_integer_cuts!`
# was being handed the recourse EVALUATED AT WHATEVER z THE MASTER'S CURRENT TRIAL
# HAPPENED TO PICK (`follower_res.cost - oracle_res.cost` at `lb_res.z`), not the TRUE,
# EXACTLY-MINIMIZED per-corner recourse `Q(y_inv(b^ν)) = min_{z∈[0,y_inv]}
# [follower_cost(z) - oracle_welfare(z)]` the Laporte-Louveaux theorem (and `add_ll_cut!`'s
# own docstring precondition) requires. See test/test_planning_certification_integer.jl's
# file header for the full, empirically-confirmed diagnosis this fix resolves.
# ---------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------
# The T>1 generalization of corner_recourse: replaces the
# scalar `fill(z, T)` surrogate with a genuine joint T-dimensional convex minimization
# `Q(y_inv) = min_{z∈[0,y_inv]^T} [follower_cost(z) - oracle_welfare(z)]`, via a Kelley's
# cutting-plane ("bundle") loop reusing the SAME solve_follower!/solve_planning_oracle!
# dual reads already used by the outer Benders loop's own :x/:op cuts (benders.jl:299-301/
# 530-533) as a first-order (value+gradient) oracle for Q. The bundle
# loop is Kelley's cutting-plane method applied to the convex function Q.
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

# Bound on how many successive bisection halvings
# the oracle-infeasible-no-certificate stall guard (below) will attempt before giving up
# and raising a diagnostic error, rather than silently making zero progress forever. Not a
# measured tolerance like JOINT_RECOURSE_GAP_TOL above -- it is a hard IEEE-754 double
# bound: halving ANY bounded bracket `[z_lo, z_hi]` this many times drives `z_mid` to be
# bit-identical to one endpoint (a double has 52 mantissa bits; 64 halvings exhausts any
# representable gap even for extreme exponents), so termination is guaranteed independent
# of `iters` and independent of the fixture's scale.
const JOINT_RECOURSE_BISECT_MAX_DEPTH = 64

# The termination statuses that make an oracle throw a
# GENUINE infeasibility of the pinned z_k (routed to the oracle-feasibility-cut branch).
# Anything else untrusted is a solver failure and is rethrown. `ALMOST_INFEASIBLE` is
# included because Clarabel reports a near-certificate that way; the slack-min oracle's
# `v > FEAS_CUT_V_TOL` check below is what actually confirms (or refutes, loudly) that z_k
# is infeasible before any cut is appended.
const ORACLE_INFEASIBLE_STATUSES =
    (MOI.INFEASIBLE, MOI.INFEASIBLE_OR_UNBOUNDED, MOI.LOCALLY_INFEASIBLE, MOI.ALMOST_INFEASIBLE)

# The oracle-infeasibility statuses that are NOT certified verdicts and must be CONFIRMED
# by the slack-min `feas_oracle` before the corner search may treat the trial as +Inf
# (see `_oracle_or_infeasible`). `ALMOST_INFEASIBLE` is a reduced-accuracy
# near-certificate; `LOCALLY_INFEASIBLE` is a local solver's (e.g. Ipopt's) verdict that
# says nothing about global infeasibility. The remaining members of
# ORACLE_INFEASIBLE_STATUSES are accepted as certified: `INFEASIBLE` is a certificate,
# and `INFEASIBLE_OR_UNBOUNDED` (a presolve verdict) can only mean infeasible here,
# because the welfare oracle at a pinned z is bounded (every device dispatch is boxed and
# the network flows are fixed by the balance rows) — an explicit modelling assumption.
const CORNER_UNCONFIRMED_STATUSES = (MOI.ALMOST_INFEASIBLE, MOI.LOCALLY_INFEASIBLE)

# Minimum slack-min value `v` for an oracle feasibility cut
# `v + u'(z - z_k) <= 0` to be appended. At z = z_k the cut reads `v <= 0`, so it separates
# z_k from the master only if `v` exceeds the master's own primal feasibility tolerance.
# MEASURED 2026-10-01 (offline probe), `solve_feasibility_oracle!` on
# ConvexBranchFlow `ieee13_modified()`:
#   - noise floor at relaxation-FEASIBLE pins (T=4 IEEE13ShortHorizonFixtures population at
#     uniform z ∈ {0, 0.02, 0.05, 0.06}; T=1 single-Thermostatic population at
#     z ∈ [0.0105, 0.05]): |v| <= 2.4e-10;
#   - smallest GENUINE v observed at an infeasible pin: 3.86e-5 (T=1, z=0.01) and 5.04e-5
#     (the inexact-policy T=4 run's third natural oracle feasibility cut);
#   - the master LP's HiGHS default primal feasibility tolerance: 1e-7.
# `FEAS_CUT_V_TOL = max(10 * 2.4e-10, 10 * 1e-7) = 1e-6`: 10x above the master's own
# tolerance (so an appended cut really excludes z_k), >= 4000x above the measured noise
# floor, and ~39x below the smallest genuine v measured.
const FEAS_CUT_V_TOL = 1.0e-6

# The NOISE floor below which a slack-min value
# `v` is indistinguishable from zero. Same measurement as FEAS_CUT_V_TOL above: |v| <=
# 2.4e-10 at every relaxation-FEASIBLE pin probed (T=4 and T=1, so no growth with T was
# observed over that range — `v` sums |s| over the T hours, and the per-instance noise
# did not scale with it), and `FEAS_CUT_V_NOISE = 10 * 2.4e-10`. Between this floor and
# FEAS_CUT_V_TOL a cut is "weak": still VALID (see `_feas_cut_class`), but it may not
# separate z_k beyond the master's own 1e-7 feasibility tolerance.
const FEAS_CUT_V_NOISE = 2.4e-9

"""
    _feas_cut_class(v::Real) -> Symbol

Classify the slack-min value `v` at an oracle-infeasible trial `z_k`:

  - `:separating` if `v > FEAS_CUT_V_TOL` — the cut `v + u'(z − z_k) ≤ 0` excludes `z_k`
    with headroom over the master's feasibility tolerance (the iteration-1 rule);
  - `:weak` if `FEAS_CUT_V_NOISE < v ≤ FEAS_CUT_V_TOL` — the normal regime of Kelley
    feasibility cuts converging on a CURVED boundary (voltage-driven or multi-hour
    coupled), where each new trial sits on the last cut's plane and `v` shrinks toward 0.
    The cut is still VALID — `V(z) ≥ v + u'(z − z_k)` by convexity of the slack-min value
    `V`, and `V(z) = 0` at every feasible `z` — so it is appended and the loop continues;
    only a deterministic re-proposal of the same `z_k` right after a weak cut is an error;
  - `:disagree` if `v ≤ FEAS_CUT_V_NOISE` — the slack-min oracle sees `z_k` as feasible
    within its own noise while the oracle reported an infeasibility status: the two
    oracles genuinely disagree and no cut can carry information.
"""
function _feas_cut_class(v::Real)
    v > FEAS_CUT_V_TOL && return :separating
    v > FEAS_CUT_V_NOISE && return :weak
    return :disagree
end

"""
    corner_recourse(oracle, follower, y_inv::Real, T::Int; iters::Int = 100,
                    on_inexact::Symbol = :throw) -> Float64

The TRUE per-corner minimized recourse
`Q(y_inv) = min_{z ∈ [0, y_inv]^T} [follower_cost(z) − oracle_welfare(z)]`, computed over
the REAL, already-built `oracle`/`follower` (the SAME production
`solve_planning_oracle!`/`solve_follower!` entrypoints used everywhere else in the
Benders loop — never rebuilt, never a closed-form shortcut).

**T==1/T>1 dispatch:**

  - `T == 1` calls the EXISTING deterministic ternary-search body, UNCHANGED, byte-for-
    byte identical to its output before the `T > 1` generalization (see [`_corner_recourse_ternary`](@ref)) —
    mirrors `test/test_planning_certification_integer.jl`'s own `enumerate_lattice`
    reference implementation's `Qfun`/`ternary_min` technique EXACTLY (that file's logic,
    promoted from test-only certification code into production so `add_ll_cut!`'s caller
    finally honors its own documented precondition, `Q_nu = Q(b^ν)`, "never estimated
    here"). `Q` is convex in `z` whenever the oracle's
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
    earlier `fill(z, T)` surrogate, now REMOVED for `T > 1`) silently gives the
    WRONG answer on exactly this common case. The two
    dispatch branches are DELIBERATELY not unified into one algebraically-equivalent
    body: different floating-point trajectories would break the `T == 1` byte-identity
    requirement even where mathematically equivalent.

Both branches treat a follower-infeasible trial `z` (`solve_follower!`'s genuine
`feasible = false` branch) as `+Inf` in the extended-value sense (the SAME Rule-1 device
`enumerate_lattice` uses) — mathematically sound because `z = zeros(T)` is always
follower-feasible, so the feasible sub-region containing the true minimizer is always
nonempty.

`y_inv <= 0` collapses the feasible region to the single point `z = zeros(T)` — the
recourse there is GENUINELY COMPUTED (one real solve of `follower`/`oracle`), never
assumed to be `0.0` — see `docs/literate/integer_investment.jl`'s
own independently-found fix for the historical rationale.

**`on_inexact`.** Forwarded UNCHANGED to every
`solve_planning_oracle!` call of both branches. `solve_stackelberg!` passes `:throw`
under `inexact_policy = :strict` and `:report` otherwise, so the corner search honours
the SAME policy as the outer trial. Under `:report` an SOCP-inexact trial contributes its
relaxed value `Q_R(z) ≤ Q_true(z)` (the relaxation's welfare over-estimates the true
welfare), so the returned minimum is the RELAXATION's per-corner minimum — never above
the true one. The Laporte-Louveaux cut built from it under-estimates the true recourse
at that corner, so it stays valid (a weaker cut, never an invalid one). An oracle throw
is classified, never swallowed: only an untrusted solve whose termination status is in
`ORACLE_INFEASIBLE_STATUSES` — and, for `CORNER_UNCONFIRMED_STATUSES`, confirmed by a
`:separating` slack-min verdict (see [`_oracle_or_infeasible`](@ref)) — is
treated as `+Inf` (outside the oracle's feasible set,
which is convex in `z`, so `Q` stays an extended-value convex function). Every other
throw — an exactness verdict under `:throw`, a battery-complementarity violation, an
exhausted retry ladder, a non-`ErrorException` such as `InterruptException` — is
rethrown unchanged.
"""
function corner_recourse(
    oracle,
    follower,
    y_inv::Real,
    T::Int;
    iters::Int = 100,
    on_inexact::Symbol = :throw,
    feas_oracle = nothing,
)
    if T == 1
        return _corner_recourse_ternary(
            oracle,
            follower,
            y_inv,
            T;
            iters = iters,
            on_inexact = on_inexact,
            feas_oracle = feas_oracle,
        )
    else
        return _corner_recourse_joint(
            oracle,
            follower,
            y_inv,
            T;
            iters = iters,
            on_inexact = on_inexact,
            feas_oracle = feas_oracle,
        )
    end
end

"""
    _oracle_or_infeasible(oracle, z; on_inexact, feas_oracle = nothing) -> NamedTuple or nothing

The corner search's ONE oracle entry point:
`solve_planning_oracle!(oracle, z; on_inexact)`, except that a throw from an UNTRUSTED
solve whose termination status is a CERTIFIED infeasibility verdict
(`ORACLE_INFEASIBLE_STATUSES` minus `CORNER_UNCONFIRMED_STATUSES`) returns `nothing`
("z is outside the oracle's feasible set"). Everything else propagates unchanged:
non-`ErrorException`s (e.g. `InterruptException`), throws from a TRUSTED solve (the
exactness gate under `:throw`, battery complementarity), and untrusted solves with any
other status (a solver failure, not a property of `z`).

`MOI.ALMOST_INFEASIBLE` is a
REDUCED-ACCURACY near-certificate, not a confirmed infeasibility — mapping it straight to
`+Inf` (the pre-fix behavior) can over-estimate `Q_nu` and make the caller's
Laporte-Louveaux cut invalid. It is now CONFIRMED via the same slack-min `feas_oracle`
`solve_stackelberg!`'s own outer oracle catch already uses: with no `feas_oracle` supplied,
the status is unconfirmed and the throw is rethrown (fail loud, never silently `+Inf`); with
a `feas_oracle` supplied, `solve_feasibility_oracle!(feas_oracle, z).v` is classified via
[`_feas_cut_class`](@ref).

Only a `:separating` verdict confirms the infeasibility
and returns `nothing`; `:weak` and `:disagree` both rethrow. This is deliberately STRICTER
than `solve_stackelberg!`'s outer catch, where a `:weak` cut is still a VALID cut to
append: here the verdict is turned into `Q(z) = +Inf`, and a `:weak` `z` sits within the
master's feasibility tolerance of the boundary, where `+Inf` could discard the true
near-boundary minimizer and over-estimate `Q_nu`. `MOI.LOCALLY_INFEASIBLE` (a local
solver's verdict) is routed through the SAME confirmation (`CORNER_UNCONFIRMED_STATUSES`)
instead of being accepted as certified.
"""
function _oracle_or_infeasible(oracle, z; on_inexact::Symbol, feas_oracle = nothing)
    return try
        solve_planning_oracle!(oracle, z; on_inexact = on_inexact)
    catch e
        _is_solver_failure(e) || rethrow()
        is_solved_and_feasible(oracle.model; dual = true) && rethrow()
        ts = termination_status(oracle.model)
        ts in ORACLE_INFEASIBLE_STATUSES || rethrow()
        if ts in CORNER_UNCONFIRMED_STATUSES
            feas_oracle === nothing && rethrow()   # unconfirmed verdict: fail loud
            # ONLY a :separating slack-min value confirms.
            # A :weak value (FEAS_CUT_V_NOISE < v <= FEAS_CUT_V_TOL) puts z within the
            # master's own feasibility tolerance of the boundary — mapping it to +Inf
            # could drop a near-boundary minimizer, over-estimate Q_nu and make the LL
            # cut invalid — so it rethrows, like :disagree.
            _feas_cut_class(solve_feasibility_oracle!(feas_oracle, z).v) === :separating ||
                rethrow()
        end
        nothing
    end
end

"""
    _corner_recourse_ternary(oracle, follower, y_inv::Real, T::Int; iters::Int = 100,
                             on_inexact::Symbol = :throw) -> Float64

The `T == 1` ternary-search body, copied VERBATIM (byte-for-byte identical
floating-point trajectory) into its own named function per [`corner_recourse`](@ref)'s
dispatch — see that function's docstring for the full rationale. Never called
with `T != 1` (the `fill(z, T)` scalar-pinning here is exactly the surrogate removed
for `T > 1`; it remains correct-by-definition at `T == 1`, where pinning the single scalar
`z` across "all `T` periods" is a no-op).

`on_inexact` is forwarded to the oracle, and a
genuinely oracle-INFEASIBLE trial (see [`_oracle_or_infeasible`](@ref)) is `+Inf`, like
a follower-infeasible one. Before, every oracle throw aborted the search. That
`+Inf` path only engages where the old code threw, so every trajectory that used to
complete is bit-for-bit identical.
"""
function _corner_recourse_ternary(
    oracle,
    follower,
    y_inv::Real,
    T::Int;
    iters::Int = 100,
    on_inexact::Symbol = :throw,
    feas_oracle = nothing,
)
    function Qfun(z::Real)
        zvec = fill(Float64(z), T)
        fr = solve_follower!(follower, zvec)
        # Rule 1 auto-fix (mirrors enumerate_lattice's own documented fix): an
        # undeliverable z is a genuine infeasibility, not an error — extend Q to +Inf
        # there so ternary search never dereferences a nonexistent .cost field and
        # still finds the true constrained minimum.
        fr.feasible || return Inf
        orr = _oracle_or_infeasible(oracle, zvec; on_inexact = on_inexact, feas_oracle = feas_oracle)
        orr === nothing && return Inf   # genuine oracle infeasibility only
        return fr.cost - orr.cost
    end

    # fail LOUDLY rather than silently propagate a
    # divergence. The follower is documented to always be feasible at z=0, so
    # Q(y_inv) can never legitimately be non-finite for y_inv >= 0 -- a non-finite
    # result here is proof of a search bug, not a legitimate value.
    check_finite(Qv::Real, z::Real) =
        isfinite(Qv) || throw(
            ErrorException(
                "corner_recourse: recourse evaluated to a non-finite value at z=$z " *
                "(y_inv=$y_inv) -- the follower is documented to always be feasible " *
                "at z=0, so this should be unreachable; report as a bug " *
                "(zero-corner feasibility regression).",
            ),
        )

    # Compute the zero-corner recourse for real via
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
        # (see docstring): a double-infinite tie must shrink from the right
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
    _corner_recourse_joint(oracle, follower, y_inv::Real, T::Int; iters::Int = 100,
                           on_inexact::Symbol = :throw) -> Float64

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
THIS small inner-loop LP is rebuilt per outer iteration, by design).

**Infeasible-trial handling:**

  - A FOLLOWER-infeasible trial (`solve_follower!`'s genuine `feasible = false` branch,
    e.g. a `y_inv` large enough that some `z` in the hypercube exceeds the follower's own
    deliverable capacity `corridor_cap * x_inv_max`) contributes NO epigraph cut (an
    `Inf` affine minorant is meaningless) — but its GENUINE Farkas certificate
    (`fr.v`, `fr.u`; only when both are finite — a
    certificate-less infeasibility, `solve_follower!(::DistributorView)`'s NaN sentinel,
    is handled exactly like the ORACLE-infeasible case below, by bisection)
    IS added as a REAL linear feasibility cut to the small master,
    `v_k + u_k'(z − z_k) <= 0`, the IDENTICAL cut form [`add_feasibility_cut!`](@ref)
    already uses for the OUTER Benders master (`src/planning/master.jl:209-242`). This
    is a deliberate strengthening beyond a bare "skip": without it, the small master's
    deterministic LP would re-propose the IDENTICAL infeasible corner every subsequent
    iteration (no new information ever excludes it), stalling until `iters` exhausts for
    no reason — the SAME certificate already computed for the caller's own feasibility-
    cut branch is reused here at zero extra cost.
  - An ORACLE-infeasible trial (`solve_planning_oracle!` throwing from an untrusted
    solve with a status in `ORACLE_INFEASIBLE_STATUSES`;
    every other throw is rethrown, see [`_oracle_or_infeasible`](@ref) — e.g. a
    genuine network-balance infeasibility unreachable via the follower's own, purely economic,
    capacity model; CONFIRMED to occur on realistic non-separable battery fixtures
    whenever the follower-feasible box extends beyond what the NETWORK can physically
    accept) is caught and ALSO treated as `+Inf`/no epigraph cut — but NO certificate is
    available here (`solve_planning_oracle!` has no structured infeasible return), so it
    contributes NO cut of ANY kind. If the SAME trial is proposed twice in a row this way
    (a genuine stall — the master has zero new information to move away from it), a
    T-dimensional generalization of the ternary search's own double-infinite
    tie-break applies: bisect toward the guaranteed-feasible incumbent `z_best` (the SAME
    "shrink toward the known-feasible anchor" principle, one dimension per coordinate
    instead of one). This bisection is genuinely ITERATIVE, not
    single-shot — if a midpoint is *itself* oracle-infeasible with no certificate, the
    bracket shrinks toward `z_best` and a NEW midpoint is tried, up to
    `JOINT_RECOURSE_BISECT_MAX_DEPTH` halvings, before giving up with a diagnostic error
    that clearly distinguishes "stalled, no progress possible" (this branch) from "gap not
    yet met" (the `iters`-exhaustion branch below). A single bisection step is NOT
    sufficient in general: nothing guarantees the first midpoint is feasible, and a
    single-shot version would silently make zero progress and loop until `iters` exhausted
    for no reason whenever it isn't.

`y_inv <= 0` collapses `[0, y_inv]^T` to the single point `z = zeros(T)` — genuinely
computed (never assumed `0.0`), matching [`_corner_recourse_ternary`](@ref)'s own
treatment. The FIRST trial (before any master solve) is always `z = zeros(T)` (the
guaranteed-feasible anchor), so at least one finite epigraph cut always exists
before the loop's first master solve.

Terminates when `UB − LB <= JOINT_RECOURSE_GAP_TOL` (a MEASURED, not guessed, constant —
see the comment immediately above its definition) or after `iters` outer iterations,
whichever comes first; on exhausting `iters` without meeting the tolerance, raises a loud
`ConvergenceError` naming the achieved gap (never silently returns an unconverged value).
"""
function _corner_recourse_joint(
    oracle,
    follower,
    y_inv::Real,
    T::Int;
    iters::Int = 100,
    on_inexact::Symbol = :throw,
    feas_oracle = nothing,
)
    # Evaluate Q(z) and its gradient at a trial z::Vector{Float64}. See the docstring
    # above ("Infeasible-trial handling") for the full rationale of each branch.
    function evaluate(z::Vector{Float64})
        fr = solve_follower!(follower, z)
        if !fr.feasible
            # A follower may confirm infeasibility WITHOUT
            # a certificate (`solve_follower!(::DistributorView)`'s NaN sentinel). A NaN
            # cut must never reach the small master LP (JuMP rejects a NaN coefficient
            # with an opaque error): route it to the no-certificate bisection fallback,
            # exactly like an oracle infeasibility.
            feas_cut =
                isfinite(fr.v) && all(isfinite, fr.u) ? (; v = fr.v, u = fr.u, z_k = copy(z)) :
                nothing
            return (; Qz = Inf, gradQ = nothing, feas_cut)
        end
        # See the infeasible-trial handling in the docstring above: a GENUINE oracle-side
        # infeasibility is extended-value +Inf, exactly like a follower infeasibility,
        # but carries no certificate. This
        # used to be a bare `catch` that turned EVERY throw (an exactness verdict, a
        # complementarity violation, even an InterruptException) into +Inf, so the
        # minimum was taken over the remaining points only — an over-estimated Q_nu
        # and an invalid LL cut. Now only an infeasibility status maps to +Inf.
        orr = _oracle_or_infeasible(oracle, z; on_inexact = on_inexact, feas_oracle = feas_oracle)
        orr === nothing && return (; Qz = Inf, gradQ = nothing, feas_cut = nothing)
        Qz = fr.cost - orr.cost
        gradQ = fr.π_s .+ orr.π   # elementwise, length T (docstring's dual-read pattern)
        return (; Qz, gradQ, feas_cut = nothing)
    end

    # T-dimensional analogue: fail LOUDLY rather than silently propagate a
    # divergence -- the anchor z=zeros(T) is documented to always be follower- AND
    # oracle-feasible, so a non-finite result there is proof of a search bug.
    check_finite(Qv::Real, z::AbstractVector) =
        isfinite(Qv) || throw(
            ErrorException(
                "_corner_recourse_joint: recourse evaluated to a non-finite value at " *
                "z=$z (y_inv=$y_inv, T=$T) -- the anchor z=zeros(T) is documented to " *
                "always be follower- and oracle-feasible, so this should be " *
                "unreachable; report as a bug (T-dimensional zero-corner feasibility " *
                "regression).",
            ),
        )

    # T-dimensional analogue: y_inv <= 0 collapses [0, y_inv]^T to the single
    # point z = zeros(T) -- genuinely COMPUTED via evaluate, never assumed.
    if y_inv <= 0
        r0 = evaluate(zeros(T))
        check_finite(r0.Qz, zeros(T))
        return r0.Qz
    end

    y_inv_f = Float64(y_inv)
    cuts = Tuple{Vector{Float64}, Float64, Vector{Float64}}[]        # (z_k, Q_k, gradQ_k)
    feas_cuts = Tuple{Float64, Vector{Float64}, Vector{Float64}}[]   # (v_k, u_k, z_k)

    # T-dimensional anchor: the FIRST trial is zeros(T), the guaranteed-feasible
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
        is_solved_and_feasible(mmodel) || throw(
            SolveFailedError(
                "_corner_recourse_joint: the small cutting-plane master LP failed to " *
                "solve (status=$(termination_status(mmodel))) at y_inv=$y_inv, T=$T -- " *
                "report as a bug.",
                mmodel,
            ),
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
            # a SINGLE bisection step is not guaranteed to
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

    throw(
        ConvergenceError(
            "_corner_recourse_joint: exhausted $iters iteration(s) without meeting the " *
            "measured gap tolerance JOINT_RECOURSE_GAP_TOL=$JOINT_RECOURSE_GAP_TOL at " *
            "y_inv=$y_inv (T=$T) -- refusing to silently return a non-converged result.";
            iterations = iters,
        ),
    )
end

"""
    ll_cut_recourse(master, oracle, follower, lb_res, Q_nu_iterate::Real;
                    on_inexact::Symbol = :throw) -> Float64

Dispatched Q_nu resolver for the Laporte-Louveaux cut, mirroring
[`apply_integer_cuts!`](@ref)'s own dispatch shape:

  - `ll_cut_recourse(::BendersMaster, oracle, follower, lb_res, Q_nu_iterate)` — a TRUE
    no-op: returns `Q_nu_iterate` UNCHANGED, touches ZERO fields of `oracle`/`follower`/
    `lb_res` (never re-solves either model). Exists purely to keep the `benders.jl` call
    site uniform across both master types — this value is never actually consumed
    downstream, since `apply_integer_cuts!(::BendersMaster, ...)` is itself a true no-op.
    The continuous path is therefore BIT-FOR-BIT IDENTICAL to its pre-fix behavior.
  - `ll_cut_recourse(master::BendersMasterInteger, oracle, follower, lb_res, Q_nu_iterate)`
    — computes the TRUE per-corner minimized recourse via [`corner_recourse`](@ref) at the
    incumbent trial's OWN `y_inv = lb_res.y`. This is exact by construction: `lb_res.b` is
    binary at a genuine MILP optimum, so `lb_res.y` is the DETERMINISTIC value of the
    `y_inv` expression evaluated at that exact `b` (never a relaxed/fractional value) —
    `y_inv(b^ν)`, not an independent re-derivation. `on_inexact` is forwarded to
    [`corner_recourse`](@ref), so the corner
    search honours the caller's `inexact_policy` instead of always throwing.

**THE FIX:** the caller previously passed
`Q_nu_iterate` straight through to `add_ll_cut!` — the recourse evaluated AT WHATEVER `z`
the master's current trial happened to pick, only an UPPER BOUND on `Q(y_inv(b^ν))` in
general (the master's box only guarantees `z <= y_inv`, not `z` = the minimizer). This
method supplies the theorem's actual required value instead.
"""
ll_cut_recourse(
    ::BendersMaster,
    oracle,
    follower,
    lb_res,
    Q_nu_iterate::Real;
    on_inexact::Symbol = :throw,
    feas_oracle = nothing,
) = Q_nu_iterate

function ll_cut_recourse(
    master::BendersMasterInteger,
    oracle,
    follower,
    lb_res,
    Q_nu_iterate::Real;
    on_inexact::Symbol = :throw,
    feas_oracle = nothing,
)
    return corner_recourse(
        oracle,
        follower,
        lb_res.y,
        master.T;
        on_inexact = on_inexact,
        feas_oracle = feas_oracle,
    )
end

"""
    _assert_epigraph_floor(cost_k::Real, lb::Real, label::Symbol; gap::Real = NaN,
                           accepted_slack::Real = 0.0)

A UNIVERSAL, bound-source-independent runtime sanity
check — `error(...)`s if `cost_k < lb - tol`, naming `label` (`:op`/`:x`), the evaluated
`cost_k`, the declared `lb` and the tolerance used.

The tolerance is SCALE-AWARE and measured per evaluation:
`tol = alpha_lb_margin(cost_k, gap; floor = ALPHA_LB_REJECTION_TOL)` =
`max(1e-6, 10·gap, ALPHA_LB_RTOL·|cost_k|)`, where `gap` is the measured duality gap of the
solve that produced `cost_k` (the oracle's own Clarabel gap; `NaN` — no gap term — for the
follower LP, whose HiGHS simplex gap is exactly 0, see `KNOWN_OPTIMUM_ATOL`'s
measurement). The same formula as the α-bound margin itself, so the two can never drift
apart, and at `|W| ≈ 609` (IEEE-13 T=4) or larger the interior-point solver's own relative
precision is covered instead of a T=1-toy absolute `1e-6` (which could fire as a
"modeling bug" on pure solver noise near the box argmax).

`accepted_slack` is the build-time acceptance
slack of the bound in force (`BendersMaster.lb_slack`, read via `_accepted_lb_slack`):
`tol` becomes `alpha_lb_margin(...) + accepted_slack`, so build-time acceptance and this
runtime check apply ONE validity rule and a bound `build_master` accepted can never fire
here (proof in `ALPHA_LB_REJECTION_TOL`'s docstring). `0.0` — the old behavior — for
`:auto` and unvalidated bounds.

Called UNCONDITIONALLY on `solve_stackelberg!`'s optimality branch, regardless of whether
`master.α_op`/`master.α_x`'s declared lower bound came from `:auto`, an explicit `Real`, or
was build-time-validated via `bounds_ctx` at all — a genuine lower bound, by definition,
can never exceed an actually-achieved cost at a feasible point. If this ever fires, it is
proof of a modeling bug in the derivation or declaration of that bound (the
core-value risk of the planning layer), never a legitimate convergence edge case to special-case away.
"""
function _assert_epigraph_floor(
    cost_k::Real,
    lb::Real,
    label::Symbol;
    gap::Real = NaN,
    accepted_slack::Real = 0.0,
)
    tol = alpha_lb_margin(cost_k, gap; floor = ALPHA_LB_REJECTION_TOL) + accepted_slack
    cost_k < lb - tol && error(
        "solve_stackelberg!: epigraph $label evaluated to cost_k=$cost_k, below its " *
        "OWN declared lower bound lb=$lb (tol=$tol, measured gap=$gap) — this " *
        "is a genuine modeling bug (an invalid declared lower bound), not a convergence " *
        "issue. Never silently accepted.",
    )
    return nothing
end

"""
    _accepted_lb_slack(master, label::Symbol) -> Float64

The build-time acceptance slack of `master`'s declared `:op`/`:x` epigraph lower bound:
`master.lb_slack[label]` for a
[`BendersMaster`](@ref), `0.0` for any master type without that record (e.g.
`BendersMasterInteger`, whose explicit bounds are never build-time validated).
"""
_accepted_lb_slack(master::BendersMaster, label::Symbol) = getproperty(master.lb_slack, label)
_accepted_lb_slack(master, label::Symbol) = 0.0

"""
    _incumbent_ac_report(feeder, aggregators, λ₀, T::Int, z, socp_welfare::Real) -> NamedTuple

The `ac_report` of a converged, relaxation-only incumbent. Runs [`ac_recheck_incumbent`](@ref) at `z` and extends its report with
`socp_welfare`, `welfare_gap = socp_welfare − ac_welfare` and `error = nothing`.

The AC re-check is a DIAGNOSTIC of an already-converged result — the slowest and least
robust solve in the pipeline (Ipopt on a nonconvex model). If it fails with an
`SolveFailedError` (Ipopt does not reach `LOCALLY_SOLVED`), the failure is REPORTED here
instead of discarding the converged result: `ok = false`, `violations = nothing`,
`p_import = nothing`, `ac_welfare = NaN`, `raw_status = "AC_RECHECK_FAILED"`,
`welfare_gap = NaN`, and `error` holds the full message. `ok = false` then means "not
certified", never "physically infeasible". Any other exception type (e.g.
`InterruptException`, an `ArgumentError` from a malformed call) propagates.
"""
function _incumbent_ac_report(feeder, aggregators, λ₀, T::Int, z, socp_welfare::Real)
    return try
        ac = ac_recheck_incumbent(feeder, aggregators, λ₀, T, z)
        (; ac..., socp_welfare, welfare_gap = socp_welfare - ac.ac_welfare, error = nothing)
    catch e
        _is_solver_failure(e) || rethrow()
        (;
            ok = false,
            violations = nothing,
            p_import = nothing,
            ac_welfare = NaN,
            raw_status = "AC_RECHECK_FAILED",
            socp_welfare,
            welfare_gap = NaN,
            error = sprint(showerror, e),
        )
    end
end

"""
    _select_incumbent(relax::NamedTuple, exact::Union{Nothing,NamedTuple},
                      converged::Function) -> NamedTuple

The incumbent ORDERING rule. `relax` is the
running-minimum-cost incumbent over ALL accepted iterates (the one whose cost is the
loop's `UB`, which drives convergence); `exact` is the running-minimum-cost incumbent
over the CERTIFIED iterates only (oracle verdict `:exact` or `:not_applicable`), or
`nothing` if none exists. Both carry at least `UB` and `exactness`.

An inexact iterate's cost uses the relaxation's welfare `W_R(z) ≥ W_true(z)`, so it is a
LOWER estimate of that point's physical cost and cannot be compared with a certified
cost on cost alone. The rule is therefore:

 1. If `relax` is itself certified, return it (then `relax === exact`; the case of every
    `:strict`/`:reject` run and of every run on a cone-free formulation).
 2. Otherwise, if a certified incumbent exists AND `converged(exact.UB)` holds against
    the same `LB` (the caller's own convergence test: `gap ≤ tol`, or the
    `known_optimum` exact match), return `exact` — a certified point that is itself
    converged is never displaced by a relaxation-only one.
 3. Otherwise return `relax` (the caller labels it `ub_relaxation_only` and reports
    `exact` alongside, so a certified point is never thrown away).
"""
function _select_incumbent(relax::NamedTuple, exact::Union{Nothing, NamedTuple}, converged::Function)
    relax.exactness === :inexact || return relax
    exact !== nothing && converged(exact.UB) && return exact
    return relax
end

"""
    solve_stackelberg!(feeder, pf::AbstractPowerFlow, aggregators::AbstractVector{<:Aggregator};
                       λ₀, T::Int, follower_kwargs::NamedTuple, master_kwargs::NamedTuple,
                       tol::Real = 1e-6, max_iter::Int = 100,
                       checkpoint_dir::AbstractString = datadir("planning_checkpoints"),
                       follower = nothing, master = nothing,
                       known_optimum::Union{Nothing,Real} = nothing,
                       inexact_policy::Symbol = :certify_incumbent)
        -> NamedTuple

Solve the single-distributor Stackelberg equilibrium (flexibility-investment leader vs.
transmission-reinforcement follower, operational welfare oracle) end-to-end via a
hand-rolled Benders loop, converging to a documented relative UB/LB gap
tolerance or raising loudly on iteration-cap exhaustion.

**Honest relabelling (API decision):** this function solves THE
INTEGRATED PROBLEM, BENDERS-DECOMPOSED — the follower's own true cost is fed directly
into the leader's Benders epigraph, which is only valid because leader and follower
share the same underlying objective here (there is no separate tariff wedge). It is
NOT a genuinely bilevel game, despite the "Stackelberg" name. For a genuinely bilevel
TSO-DSO variant, where the follower minimizes its OWN cost `c(z) - pi_tariff*z` that
differs from the leader's own valuation of `z`, see
[`solve_bilevel!`](@ref)/[`build_bilevel_kkt`](@ref) (`src/planning/bilevel_kkt.jl`)
— a single-level KKT-MILP, not a Benders loop, because plain Benders is
invalid on that genuinely divergent-objective game (see that file's module header). For
the N>1 shared-constraint case (multiple distributors sharing one pooled transmission
corridor), see [`run_nash!`](@ref)/[`solve_variational_equilibrium`](@ref)
(`src/planning/nash.jl`) — a generalized Nash equilibrium (GNE) among `N`
copies of THIS function's own per-distributor best response, not a single integrated
problem. See `docs/writeups/modelo_stackelberg_dso_unico.typ`'s "Taxonomia dos
variantes de planejamento" for the full three-way comparison.

# Algorithm

 1. Boundary guards (mirror `solve_admm`): `T >= 1`, `max_iter >= 1`, `length(λ₀) == T`,
    each `ArgumentError` BEFORE any build call.

 2. BUILD ONCE, outside the loop: `oracle = build_planning_oracle(feeder, pf, aggregators; λ₀ = λ₀, T = T)`,
    `feas_oracle = build_feasibility_oracle(feeder, pf, aggregators; T = T)`
    (unconditional — the second, built-ONCE slack-minimization
    feasibility oracle consumed by the oracle-feasibility-cut branch below),
    `follower = follower === nothing ? build_follower(; follower_kwargs..., T = T) : follower`,
    `master = master === nothing ? build_master(; master_kwargs..., bounds_ctx = _bounds_ctx, T = T) : master`
    (`bounds_ctx` is ALWAYS populated, see below). No
    `build_*`/`Model(` call appears anywhere inside this function OTHER THAN these
    conditional/unconditional builder calls, ALL of which still execute strictly BEFORE
    the `for k in 1:max_iter` loop below — the loop itself never constructs a model.

    **`bounds_ctx` wiring (UNCONDITIONAL):** `solve_stackelberg!`
    is the project's ONE public, validated entry point into the integrated Benders loop,
    and always has `feeder`/`pf`/`aggregators`/`λ₀` in scope — so `α_op_lb` (whether
    `:auto` or an explicit `Real` inside `master_kwargs`) is validated at build time
    on EVERY `master === nothing` call path, not only when `:auto` is explicitly
    requested. `α_x_lb` is likewise validated whenever the follower information supports
    a sound derivation — a `follower_kwargs` `NamedTuple` or a pre-built `FollowerLP` —
    computed from the ORIGINAL `follower`/`follower_kwargs` arguments BEFORE the
    `follower` reassignment immediately below. `solve_stackelberg!` NEVER throws merely
    because a pre-built `follower` is supplied: for a follower type with no sound
    per-object derivation (e.g. `src/planning/coupling.jl`'s `DistributorView`, whose
    pooled-capacity coupling makes a per-distributor relaxed minimum ill-defined —
    `run_nash!`'s own production path), `bounds_ctx.follower_kwargs = nothing` and
    `α_x_lb`'s build-time check is honestly SKIPPED (never silently "passed") — the
    universal runtime floor guard (`_assert_epigraph_floor`, defined above) remains
    active as defense-in-depth for that case.

    **`follower` keyword (additive/non-breaking — mirrors the
    `attempts_out::Union{Nothing,Ref{Int}}` precedent in `master.jl`/`retry.jl`):**
    defaults to `nothing`, in which case behavior is BIT-FOR-BIT IDENTICAL to a call
    without this keyword (a fresh `FollowerLP` is built from `follower_kwargs` exactly as before). When
    a caller (`run_nash!`) instead supplies a pre-built per-distributor view
    object (e.g. `coupling.jl`'s `DistributorView`, duck-typed via its own
    `solve_follower!(view, z_trial)` method), that object is used DIRECTLY in place of a
    freshly-built `FollowerLP` — no follower is built by this function at all in that case.
    Supplying BOTH a non-`nothing` `follower` AND a non-empty `follower_kwargs`
    simultaneously is rejected with an `ArgumentError` (ambiguous — which one wins is never
    silently decided).

    **`master` keyword (additive/non-breaking — mirrors the
    `follower` seam immediately above VERBATIM in structure):** defaults to `nothing`, in
    which case behavior is BIT-FOR-BIT IDENTICAL to a call without this keyword (a fresh `BendersMaster`
    is built from `master_kwargs` exactly as before). When a caller instead supplies a
    pre-built master (e.g. a `BendersMasterInteger` from `build_master_integer`, the
    binary-expansion MILP master), that object is used DIRECTLY in place of a
    freshly-built `BendersMaster` — no master is built by this function at all in that case.
    Supplying BOTH a non-`nothing` `master` AND a non-empty `master_kwargs` simultaneously is
    rejected with an `ArgumentError`, mirroring the `follower`/`follower_kwargs` guard.
    `BendersMasterInteger` now carries its own `bounds_ctx`/`:auto`/`lb_slack` validation
    (ported verbatim from `build_master`'s own machinery) and a
    build-time `lb_clamped` field, so a caller
    supplying a pre-built integer master gets the SAME build-time bound
    validation/clamping discipline as the continuous path, not an unvalidated raw bound.

    **`known_optimum` keyword:** defaults to `nothing`, in
    which case the loop's termination gate is unchanged (`gap <= tol`). When a caller
    supplies a finite value (the enumeration-backed certification harness), the
    loop instead terminates on an EXCLUSIVE exact-match test against `known_optimum` (see
    `converged_now` in the iteration loop below) — never an `||` with `gap <= tol`.

 3. Iterate `k = 1:max_iter`: `lb_res = solve_master!(master)` (the Benders lower bound and
    trial `z_k`); `follower_res = solve_follower!(follower, lb_res.z)` (DIRECT call — never
    `solve_with_retry!`-wrapped, per the follower contract) — the follower's
    feasibility check runs BEFORE any oracle solve: an undeliverable trial `z_k`
    (the master's box allows `z` up to `y_max`, beyond `corridor_cap * x_inv_max`) is
    routed to the feasibility-cut branch instead of reaching the oracle, whose
    exactness/complementarity gates can throw at extreme pinned `z`.

      + If `!follower_res.feasible`: append a feasibility cut
        (`add_feasibility_cut!(master, follower_res.v, follower_res.u, lb_res.z)`),
        checkpoint with `gap = NaN` and `feasible = false`, then `continue` — a
        feasibility cut NEVER updates `UB`; the oracle is NEVER solved on
        this branch.
      + Else: `oracle_res = solve_planning_oracle!(oracle, lb_res.z; on_inexact)` — only
        a follower-deliverable `z_k` ever reaches the oracle. `on_inexact = :throw` under
        `:strict`, `:report` otherwise; the oracle returns its exactness gate's verdict
        as an EXPLICIT field (`oracle_res.exactness`), and its battery-complementarity
        gate runs on EVERY returned result, inexact or not
        — the verdict is never inferred from a stashed side-effect key, and
        no result can bypass the complementarity gate):

          * A throw from an UNTRUSTED solve whose termination status is a genuine
            infeasibility verdict (`ORACLE_INFEASIBLE_STATUSES`) routes to the
            oracle-feasibility-cut branch: `feas_oracle` (built once above) produces a
            `(v, u)` cut pair (`solve_feasibility_oracle!`/`add_feasibility_cut!`), which is appended only if `v > FEAS_CUT_V_TOL` (so it really
            separates `z_k`), the loop `continue`s WITHOUT updating `UB`, and the trace row records the oracle's REAL termination status,
            the measured `v` (`feas_cut_v`) and `policy_action = :oracle_feasibility_cut`.
            A cut with
            `FEAS_CUT_V_NOISE < v ≤ FEAS_CUT_V_TOL` — the normal regime near a curved
            boundary — is still VALID and is appended too (`policy_action =
            :oracle_feasibility_cut_weak`); only a deterministic re-proposal of the same
            `z_k` right after a weak cut, or `v ≤ FEAS_CUT_V_NOISE` (the two oracles
            genuinely disagree), raises a named error. See [`_feas_cut_class`](@ref). Any OTHER untrusted outcome
            (exhausted retry ladder, iteration limit, numerical error) is a solver
            failure and is rethrown unchanged.
          * A throw from a TRUSTED solve can only be a post-solve gate (battery
            complementarity on any formulation, or exactness under `:strict`) — OUT OF
            SCOPE for the feasibility branch, propagated UNCHANGED with its own message.
          * A returned result with `exactness === :inexact` dispatches on
            `inexact_policy`. `:reject` APPENDS the trial's `:op`/`:x` relaxation cuts — they under-estimate
            the relaxed, hence also the true, value function whatever the exactness
            verdict, so `LB` stays valid and the master moves on — but BARS the trial
            from updating `UB` or becoming the incumbent (trace row
            `cut_type = :optimality`, `policy_action = :rejected`). `UB`, `gap` and the
            returned point are therefore certified-only under `:reject`. If the master
            re-proposes the identical rejected trial on the very next iteration, the
            relaxation's optimum sits at that inexact point and no certified incumbent
            can close the gap there; that repeat raises a named "`:reject` stalled"
            `ConvergenceError` at once instead of exhausting `max_iter` (the stall
            backstop). `:certify_incumbent` (the default) accepts the relaxation's cut
            AND lets the trial compete for the incumbent, recording
            `policy_action = :certified_incumbent` and the measured `socp_maxgap` on
            the trace (see "Incumbent ordering" below).

        On a successful (or `:certify_incumbent`-accepted) solve: the universal
        runtime epigraph floor guard (`_assert_epigraph_floor`) checks
        `-oracle_res.cost >= lower_bound(master.α_op) - tol` and
        `follower_res.cost >= lower_bound(master.α_x) - tol`, UNCONDITIONALLY,
        regardless of how either bound was derived; then append the oracle's `:op`
        optimality cut (`cost_k = -oracle_res.cost`,
        `grad_k = oracle_res.π`, the sign convention derived in the follower model) and the
        follower's `:x` optimality cut (`cost_k = follower_res.cost`,
        `grad_k = follower_res.π_s`, used as-is); compute the iterate's TRUE cost
        `cost_k = master.c_y * lb_res.y + follower_res.cost - oracle_res.cost`; if
        `cost_k < UB`, update the INCUMBENT `UB = cost_k`, `y_best = lb_res.y`,
        `z_best = copy(lb_res.z)` — the `(y, z)` pair that ACHIEVED the running-minimum
        `UB` is stored, never just the bound (convergence can trigger at an
        iterate whose own cuts have not yet tightened the master, so the LAST iterate
        is not certified by `UB`; the incumbent is); compute
        `gap = (UB - lb_res.LB) / max(1, abs(UB))`; checkpoint with
        `feasible = true`; on this branch ALSO call
        `apply_integer_cuts!(master, lb_res, Q_nu)` (a TRUE no-op
        for `BendersMaster`, real Laporte-Louveaux/no-good logic for
        `BendersMasterInteger`, `Q_nu = follower_res.cost - oracle_res.cost`); compute
        `converged_now = known_optimum === nothing ? (gap <= tol) : isapprox(UB, known_optimum; atol = KNOWN_OPTIMUM_ATOL)`
        — an EXCLUSIVE branch, NEVER an `||` of the two criteria (reusing the
        continuous loop's inherited `tol` on the certified `known_optimum` path would be
        exactly the "certificate laundering" this mechanism exists to forbid); if
        `converged_now`, return the converged result at the INCUMBENT `(y_best, z_best)`.

 4. If `max_iter` is exhausted without `converged_now`, raise a loud `ConvergenceError` naming
    the exhausted iteration count and the last observed gap — never silently return
    a non-converged result.

# Returns

On convergence, `(; y, z, UB, LB, gap, iters, oracle, follower, master, trace, nogood_count, converged_via, ac_report, incumbent_exactness, incumbent_socp_maxgap, ub_relaxation_only, exact_incumbent, status)`
where `y = y_best` (the INCUMBENT leader investment — the iterate that achieved `UB`, so
the returned point's true cost equals `UB` and the convergence certificate applies to it), `z = z_best` (the incumbent coupling flow), `UB`/`LB` are the converged
upper/lower bounds, `gap` is the converged relative gap (a REPORTING quantity — on the
`known_optimum`-supplied path, convergence is certified by the exact-match test, not by
`gap`), `iters` is the convergence iteration count, `oracle`/`follower`/`master` are the
build-once subproblem handles (for further inspection by the caller/certification gate), `trace::BendersTrace` is the per-iteration
convergence ledger — one row per iteration on both the feasibility-cut and
optimality-cut branches, including the GENUINE per-iteration retry count and both
retry-gated subproblems' termination statuses (never a log-scrape estimate), and
`nogood_count`/`converged_via` surface the total
number of no-good anti-stall cuts fired (`nogood_count`, always `0` on the continuous
path) and the convergence attribution (`converged_via`, `:clean` if `nogood_count == 0`
else `:nogood_assisted`) — a nonzero `nogood_count` never fails the run, it is reported,
never silently absorbed.

**Incumbent exactness certificate (additive trailing
fields).** `incumbent_exactness ∈ (:exact, :inexact, :not_applicable)` is the exactness
verdict of the very oracle solve that produced `UB` (`:not_applicable` for DC/
LinDistFlow, where no cone exists — "not checked", never "certified exact");
`incumbent_socp_maxgap` is that solve's measured cone residual (`NaN` when not
applicable); `ub_relaxation_only = (incumbent_exactness === :inexact)`. **When
`ub_relaxation_only` is `true`, `UB` and `gap` certify the SOC RELAXATION ONLY**: the
incumbent's welfare `W_R(z_best)` comes from a slack cone, `W_R ≥ W_true`, so `UB` is a
LOWER estimate of the incumbent's physical cost, not an upper bound on the physical
problem (the `LB` stays valid either way — relaxation cuts under-estimate the true value
function). This state is reachable only under `inexact_policy = :certify_incumbent`.

**Incumbent ordering.** An inexact iterate's
cost is a LOWER estimate of its physical cost, so it is never compared with a certified
cost on cost alone. The loop keeps two incumbents: the running-minimum over all accepted
iterates (its cost is the `UB` that drives convergence) and the running-minimum over
CERTIFIED iterates only. At convergence [`_select_incumbent`](@ref) returns the certified
one whenever the first is relaxation-only and the certified one ALSO passes the
convergence test against the same `LB`; otherwise the relaxation-only incumbent is
returned (with `ub_relaxation_only = true`). `exact_incumbent` always reports the best
certified iterate as `(; y, z, UB, gap, exactness, socp_maxgap)` — its `gap` is a genuine
PHYSICAL optimality gap, since its `UB` is a true upper bound — or `nothing` if no iterate
was certified. When the returned point is certified, `exact_incumbent` is that same point.

`ac_report` is `nothing` unless `ub_relaxation_only`, in which
case it is [`ac_recheck_incumbent`](@ref)'s report at `z_best` —
`(; ok, violations, p_import, ac_welfare, raw_status)`, where `ok` is `false` whenever the
limits-DROPPED, re-optimized AC dispatch violates a thermal/voltage limit beyond the
measured tolerance (a violation INDICATOR, not proof that no limit-respecting AC dispatch
exists at `z_best` — see that function's docstring) — extended with
`socp_welfare = W_R(z_best)`, `welfare_gap = socp_welfare − ac_welfare` (the AC model
drops the limits, so the gap is a diagnostic of how far the relaxation sits from AC
physics at `z_best`, not a certified error bound) and `error` (`nothing` on success). If
the AC re-check itself fails (Ipopt does not converge), that failure is REPORTED in
`ac_report` (`ok = false`, `raw_status = "AC_RECHECK_FAILED"`, `error` = the message)
and the converged result is still returned (see
[`_incumbent_ac_report`](@ref)). NEVER thrown, never silently passed.

# Throws

  - `ArgumentError` on `T < 1`, `max_iter < 1`, `length(λ₀) != T`, a non-finite/non-positive
    `tol`, `max_iter > 99_999`, a non-`nothing` `follower` supplied together with a
    non-empty `follower_kwargs`, a non-`nothing` `master` supplied together
    with a non-empty `master_kwargs`, a non-`nothing`
    `known_optimum` that is not finite, or an
    `inexact_policy` outside `(:strict, :reject, :certify_incumbent)` — before any build call. ALSO raised
    (unconditionally, on EVERY `master === nothing` build) if an explicit
    `α_op_lb`/`α_x_lb` inside `master_kwargs` exceeds `build_master`'s own derived minimum
    (see that function's docstring) — a found-invalid bound is a genuine bug to fix at its
    call site, never silenced.
  - `ConvergenceError` if `max_iter` is exhausted without converging, naming the trace's
    last-recorded `LB`/`UB`/`gap` and the tolerance — refuses to silently
    return a non-converged result. ALSO raised, immediately, when `inexact_policy =
    :reject` re-encounters the identical SOCP-inexact trial it just rejected even though
    its cuts were appended (a named "`:reject` stalled" error). ALSO raised by the universal runtime epigraph floor
    guard (`_assert_epigraph_floor`) if ANY evaluated epigraph cost ever falls
    below its own declared lower bound — a genuine modeling bug, never a convergence
    issue.

# Status and exceptions
The returned `status` is `:converged` or `:converged_relaxation_only` (the UB certifies
only the SOC relaxation). Throws: `ArgumentError` (invalid inputs), `SolveFailedError`
(untrustworthy solver result), `CertificateError` (refused certificate), `ConvergenceError`
(exhausted `max_iter`). See the [status & exception policy](@ref status-policy).
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
    # `inexact_policy` must be one of the three
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
    # A NaN/negative tol silently guarantees exhaustion (every
    # gap <= tol comparison is false for NaN) — fail-loud is preserved but the
    # diagnosis is misleading; guard it here alongside the other boundary checks.
    isfinite(tol) && tol > 0 || throw(
        ArgumentError("solve_stackelberg! needs tol to be finite and > 0 (got tol=$tol)"),
    )
    # `checkpoint_iteration!` enforces iter ∈ 0:99999 (5-digit
    # zero-padded filename contract, src/planning/checkpoint.jl) — fail HERE, not
    # deep inside checkpoint_iteration! after 99,999 wasted iterations.
    max_iter <= 99_999 || throw(
        ArgumentError(
            "solve_stackelberg! needs max_iter <= 99_999 (checkpoint_iteration!'s " *
            "5-digit zero-padded filename contract, src/planning/checkpoint.jl), got " *
            "max_iter=$max_iter",
        ),
    )
    # The additive `follower` keyword and `follower_kwargs` are mutually
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
    # The additive `master` keyword and `master_kwargs` are
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
    # A non-nothing known_optimum must be finite — a
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
    # The second, built-ONCE slack-minimization
    # feasibility oracle — unconditional, cheap (an LP/SOCP feasible whenever some
    # p_import admits the network), never built inside the loop.
    feas_oracle = build_feasibility_oracle(feeder, pf, aggregators; T = T)

    # ALWAYS construct a
    # populated bounds_ctx — never conditional on α_op_lb/α_x_lb being :auto, and NEVER
    # throwing merely because a pre-built `follower` is supplied (solve_stackelberg! is
    # the project's ONE public, validated entry point into the integrated Benders loop;
    # feeder/pf/aggregators/λ₀ are always in scope here). Computed from the ORIGINAL
    # `follower`/`follower_kwargs` arguments BEFORE the reassignment immediately below —
    # a pre-built follower's TYPE (not the post-reassignment FollowerLP-or-not value)
    # determines which of the three α_x_lb derivability cases applies (DistributorView's
    # pooled-capacity coupling has NO sound per-object derivation).
    _follower_info = if follower === nothing
        follower_kwargs                      # case 1: NamedTuple, unchanged derivation path
    elseif follower isa FollowerLP
        follower                             # case 2: sound FollowerLP dispatch
    else
        nothing                              # case 3: no sound derivation (e.g. DistributorView) —
                                              # documented scope limit, α_x_lb validation skipped
    end
    _bounds_ctx = (; feeder, pf, aggregators, λ₀, follower_kwargs = _follower_info)

    follower = follower === nothing ? build_follower(; follower_kwargs..., T = T) : follower
    master =
        master === nothing ?
        build_master(; master_kwargs..., bounds_ctx = _bounds_ctx, T = T) : master

    UB = Inf
    # The INCUMBENT — the (y, z) iterate that achieved the running-minimum UB.
    # Convergence (LB rising to meet an OLDER iterate's UB) must return THIS pair, never
    # the current iterate, whose own cuts may not yet bound it: the excess of the last
    # iterate's true cost over UB is NOT bounded by tol.
    y_best = NaN
    z_best = fill(NaN, T)
    # The incumbent's own exactness certificate, set
    # together with (y_best, z_best) — see the incumbent update in the loop.
    incumbent_exactness = :not_applicable
    incumbent_socp_maxgap = NaN
    incumbent_welfare = NaN
    # the best CERTIFIED iterate (oracle
    # verdict :exact/:not_applicable), tracked separately from the running-minimum
    # incumbent above, so a relaxation-only iterate can never silently discard it.
    # See `_select_incumbent` for the ordering applied at convergence.
    exact_inc = nothing
    gap = NaN
    # The purpose-built Benders convergence ledger —
    # built alongside the other accumulator state, immediately before the loop.
    trace = BendersTrace()
    # Running total of no-good anti-stall cut firings across
    # the whole run — always 0 on the continuous path (apply_integer_cuts! is a true no-op
    # for BendersMaster). Surfaced on the returned NamedTuple, never a silent count.
    nogood_total = 0
    # The trial rejected on the IMMEDIATELY preceding iteration under `inexact_policy = :reject` (or `nothing`).
    # A rejection appends its relaxation cuts, so a deterministic re-proposal of the SAME
    # trial means the relaxation's optimum sits there — detected below and turned into an
    # immediate, named error instead of silently burning the rest of the iteration budget.
    last_rejected_z = nothing
    # The trial at which the IMMEDIATELY preceding iteration appended
    # a WEAK oracle feasibility cut (see `_feas_cut_class`), or `nothing`.
    last_weak_feas_z = nothing
    for k in 1:max_iter
        # `solve_time_trace` records ONLY the wall-clock
        # seconds spent inside this iteration's solve calls (master + follower, plus
        # the oracle on the optimality branch) — NEVER checkpoint_iteration!'s JLD2
        # write + git provenance shell-outs, which on the toy fixtures dominate
        # whole-iteration wall time by orders of magnitude. Each solve is bracketed
        # with the MONOTONIC clock (time_ns), immune to the NTP steps that could make
        # a time()-based span negative and trip push!'s solve_time >= 0 guard mid-run.
        t_solve = 0.0
        # The Ref solve_master! overwrites with the actual attempt count via its new
        # attempts_out keyword; Ref(1) is a safe initial value in case a
        # future call site ever omits the keyword, though this call site always passes it.
        master_attempts = Ref(1)
        t0_ns = time_ns()
        lb_res = solve_master!(master; attempts_out = master_attempts)
        t_solve += (time_ns() - t0_ns) / 1.0e9
        # Capture the master's GENUINE post-solve termination
        # status HERE — before solve_follower! and before any add_*_cut! call. The
        # master is a CACHING-mode model, and JuMP's add_constraint sets
        # is_model_dirty = true, after which termination_status short-circuits to the
        # :OPTIMIZE_NOT_CALLED sentinel; querying at the trace-push sites (after the
        # cut appends) would record that sentinel on every row of every run.
        master_status_k = Symbol(termination_status(master.model))
        # The follower's feasibility check runs FIRST — before any oracle solve.
        # The master's box allows z up to y_max, beyond the follower's deliverable
        # capacity (corridor_cap * x_inv_max); at such extreme trial z the oracle's own
        # exactness/complementarity gates can throw (subproblem.jl), crashing the
        # loop at the exact moment a feasibility cut was the designed recovery. Routing
        # infeasible extremes to the feasibility-cut branch below also avoids a wasted
        # oracle solve per infeasible iteration.
        # DIRECT call — NEVER solve_with_retry!-wrapped (the follower contract):
        # the infeasible branch must be OBSERVED on the un-retried solve, or the Farkas
        # certificate is unreachable.
        t0_ns = time_ns()
        follower_res = solve_follower!(follower, lb_res.z)
        t_solve += (time_ns() - t0_ns) / 1.0e9

        if !follower_res.feasible
            # A confirmed infeasibility without a Farkas
            # certificate (`solve_follower!(::DistributorView)`'s NaN sentinel, after its
            # own presolve-free re-solve) carries no cut, and this loop has no other way
            # to exclude z_k — fail with a named diagnosis rather than add_feasibility_cut!'s
            # generic non-finite-argument error.
            isfinite(follower_res.v) && all(isfinite, follower_res.u) || error(
                "solve_stackelberg!: the follower is infeasible at the master trial " *
                "z_k=$(lb_res.z) but returned no Farkas certificate (v=$(follower_res.v)) " *
                "even after a presolve-free re-solve — no feasibility cut can exclude " *
                "z_k, so the Benders loop cannot continue",
            )
            last_rejected_z = nothing   # a cut was added — the master moved on
            last_weak_feas_z = nothing
            add_feasibility_cut!(master, follower_res.v, follower_res.u, lb_res.z)
            checkpoint_iteration!(
                (; k, LB = lb_res.LB, UB, gap = NaN, z_k = lb_res.z, feasible = false),
                k;
                dir = checkpoint_dir,
            )
            # Feasibility-branch trace row. oracle_status defaults to the
            # :not_solved sentinel because the oracle is never reached on this branch
            # (ordering); retry_count is the master's NET retries this iteration
            # (the only retry-gated solve that ran on this branch).
            push!(
                trace,
                k;
                LB = lb_res.LB,
                UB = UB,
                gap = NaN,
                cut_type = :feasibility,
                n_cuts = length(master.cuts),
                # The status captured immediately after solve_master!, before
                # add_feasibility_cut! dirtied the model.
                master_status = master_status_k,
                oracle_status = :not_solved,
                retry_count = master_attempts[] - 1,
                solve_time = t_solve,
            )
            continue   # a feasibility cut NEVER updates UB
        end

        # Only a follower-deliverable z_k ever reaches the oracle (ordering above).
        oracle_attempts = Ref(1)
        # Per-iteration policy bookkeeping: overwritten below only
        # on the branches that actually engage inexact_policy; :none on every ordinary
        # success path, mirroring every other sentinel default in this loop.
        policy_action_k = :none
        t0_ns = time_ns()
        # The exactness verdict is an EXPLICIT return
        # field of solve_planning_oracle! (`exactness`), never inferred from which side
        # effects a throw left behind. Under `:strict` the oracle's own `:throw` mode
        # rethrows the gate's error unchanged (bit-for-bit identical to the plain strict path). Under
        # `:reject`/`:certify_incumbent` the `:report` mode returns the inexact result —
        # and the battery-complementarity gate still runs on it inside the oracle, so a
        # complementarity violation ALWAYS throws and can never become a cut, a UB, or an
        # incumbent. The catch below therefore only ever sees a genuine
        # solve failure or an out-of-scope gate throw (complementarity, or exactness under
        # `:strict`); the latter are rethrown UNCHANGED.
        oracle_res = try
            solve_planning_oracle!(
                oracle,
                lb_res.z;
                attempts_out = oracle_attempts,
                on_inexact = inexact_policy === :strict ? :throw : :report,
            )
        catch e
            _is_solver_failure(e) || rethrow()
            # A throw from a TRUSTED solve can only come from a post-solve gate
            # (complementarity, or exactness under :strict) — never an infeasibility.
            # Propagate it with its own diagnosis (no reclassification).
            is_solved_and_feasible(oracle.model; dual = true) && rethrow()
            # ONLY a genuine infeasibility verdict goes to
            # the feasibility-cut branch. Every other untrusted outcome — the retry
            # ladder exhausted on SLOW_PROGRESS/NUMERICAL_ERROR/ITERATION_LIMIT, a
            # foreign-backend attribute rejection, ... — is a solver failure, not a
            # property of z_k, and is rethrown UNCHANGED (a "cut" built there would be
            # meaningless and could stall the master).
            oracle_ts = termination_status(oracle.model)
            oracle_ts in ORACLE_INFEASIBLE_STATUSES || rethrow()
            # The trusted-solve gate failed with an infeasibility verdict -> route to the
            # oracle-feasibility-cut branch: the second, built-ONCE slack-minimization
            # oracle produces a genuine (v, u) Benders feasibility-cut pair
            # for this pinned z_k — the loop recovers instead of crashing, mirroring the
            # EXISTING follower-feasibility-cut branch's own "never update UB" discipline.
            t_solve += (time_ns() - t0_ns) / 1.0e9
            # The slack-min model is feasible only if SOME
            # p_import admits the network, so it can fail too — never let its error mask
            # the original oracle infeasibility. Rethrow with BOTH diagnoses and z_k.
            # This solve is timed and its retries are counted.
            fo_attempts = Ref(1)
            t0_fo_ns = time_ns()
            fo_res = try
                solve_feasibility_oracle!(feas_oracle, lb_res.z; attempts_out = fo_attempts)
            catch fo_err
                _is_solver_failure(fo_err) || rethrow()
                error(
                    "solve_stackelberg!: oracle reported $(oracle_ts) at z_k=$(lb_res.z) " *
                    "(iteration $k), and the slack-minimization feasibility oracle ALSO " *
                    "failed there, so no feasibility cut can be built (no p_import admits " *
                    "the network/device constraints at all, or a numerical failure).\n" *
                    "Original oracle error: $(sprint(showerror, e))\n" *
                    "Feasibility-oracle error: $(sprint(showerror, fo_err))",
                )
            end
            t_solve += (time_ns() - t0_fo_ns) / 1.0e9
            # The cut evaluates to exactly `v` at z_k. It is
            # VALID for any v >= 0 (convexity of the slack-min value), but separates z_k
            # beyond the master's tolerance only for v > FEAS_CUT_V_TOL. See
            # `_feas_cut_class` for the measured three-way rule.
            feas_class = _feas_cut_class(fo_res.v)
            feas_class === :disagree && error(
                "solve_stackelberg!: oracle reported $(oracle_ts) at z_k=$(lb_res.z) " *
                "(iteration $k), but the slack-minimization feasibility oracle measures " *
                "only v=$(fo_res.v) <= FEAS_CUT_V_NOISE=$(FEAS_CUT_V_NOISE) of slack there " *
                "(its own noise floor) — the two oracles disagree about z_k, so no " *
                "feasibility cut carries any information.",
            )
            if feas_class === :weak && last_weak_feas_z !== nothing &&
               maximum(abs, lb_res.z .- last_weak_feas_z) <= 1e-9
                error(
                    "solve_stackelberg!: stalled near a curved feasibility boundary at " *
                    "z_k=$(lb_res.z) (iteration $k): the previous iteration appended a " *
                    "weak oracle feasibility cut there (FEAS_CUT_V_NOISE < v <= " *
                    "FEAS_CUT_V_TOL), the master re-proposed the identical trial, and the " *
                    "slack-min oracle again measures only v=$(fo_res.v).",
                )
            end
            last_weak_feas_z = feas_class === :weak ? copy(lb_res.z) : nothing
            last_rejected_z = nothing   # a cut was added — the master moved on
            add_feasibility_cut!(master, fo_res.v, fo_res.u, lb_res.z)
            checkpoint_iteration!(
                (; k, LB = lb_res.LB, UB, gap = NaN, z_k = lb_res.z, feasible = false),
                k;
                dir = checkpoint_dir,
            )
            push!(
                trace,
                k;
                LB = lb_res.LB,
                UB = UB,
                gap = NaN,
                cut_type = :feasibility,
                n_cuts = length(master.cuts),
                master_status = master_status_k,
                oracle_status = Symbol(oracle_ts),
                # The master's and the feasibility oracle's retries.
                # The FAILED oracle solve's own attempts are not observable here
                # (solve_with_retry! sets attempts_out only on success), so they are not
                # counted: a lower bound on this row's true retry count.
                retry_count = (master_attempts[] - 1) + (fo_attempts[] - 1),
                solve_time = t_solve,
                # A weak (valid, possibly non-separating) cut is
                # labelled distinctly, and the measured v is recorded on every
                # oracle-feasibility row so the regime can be measured.
                policy_action = feas_class === :weak ? :oracle_feasibility_cut_weak :
                                :oracle_feasibility_cut,
                feas_cut_v = fo_res.v,
            )
            continue   # an oracle feasibility cut NEVER updates UB
        end
        t_solve += (time_ns() - t0_ns) / 1.0e9
        # The measured cone residual is recorded on EVERY
        # row whose oracle solve ran the exactness gate (exact or inexact) — NaN only when
        # the gate does not apply (no `:l` stash: DC/LinDistFlow).
        socp_maxgap_k = oracle_res.socp_maxgap

        # policy dispatch on the EXPLICIT verdict. `:strict` never reaches an
        # :inexact result (the oracle threw above). The result has already passed the
        # battery-complementarity gate whatever its exactness verdict.
        # `rejected_k` marks an inexact trial
        # under `:reject`. Its relaxation cuts ARE appended below (they under-estimate
        # the relaxed — hence also the true — value function whatever the exactness
        # verdict, so LB stays valid and the master moves on), but it is barred from
        # updating UB or becoming the incumbent.
        rejected_k = false
        if oracle_res.exactness === :inexact
            if inexact_policy === :reject
                # Stall backstop: the cuts appended at a rejected trial make the master's
                # value there equal the relaxation's own, so if the master re-proposes the
                # IDENTICAL trial next iteration the relaxation's optimum sits at this
                # inexact point and no certified incumbent can close the gap there. Fail
                # with a named diagnosis rather than looping to max_iter. 1e-9 is the
                # same "identical deterministic re-proposal" threshold
                # `_corner_recourse_joint`'s own stall guard uses.
                if last_rejected_z !== nothing &&
                   maximum(abs, lb_res.z .- last_rejected_z) <= 1e-9
                    throw(ConvergenceError(
                        "solve_stackelberg!: inexact_policy=:reject stalled at the " *
                        "SOCP-inexact trial z=$(lb_res.z) (iteration $k, measured cone " *
                        "gap maxgap=$(socp_maxgap_k)): its relaxation cuts were appended " *
                        "and the master re-proposed the identical trial, so the " *
                        "relaxation's optimum sits at this inexact point and no " *
                        "certified incumbent can close the gap (best certified UB=$UB). " *
                        "Use inexact_policy=:certify_incumbent to accept a " *
                        "relaxation-only incumbent, or :strict to fail at the first " *
                        "inexact solve.";
                        iterations = k,
                    ))
                end
                rejected_k = true
                policy_action_k = :rejected
            else   # :certify_incumbent (the default)
                # A cut from the SOC relaxation is a valid under-estimator of the RELAXED
                # value function, so it is accepted; the inexactness is logged here and
                # carried onto the incumbent's certificate if this iterate becomes it.
                policy_action_k = :certified_incumbent
            end
        end
        # Capture oracle.model's GENUINE
        # termination status HERE, immediately after ITS OWN solve at lb_res.z —
        # mirrors master_status_k's own capture-before-mutation discipline
        # above. `ll_cut_recourse` below (BendersMasterInteger path only) re-solves
        # oracle/follower at OTHER z trials during its internal ternary search;
        # querying termination_status(oracle.model) AFTER that point would silently
        # report the LAST ternary-search trial's status instead of lb_res.z's own.
        oracle_status_k = Symbol(termination_status(oracle.model))

        # The UNIVERSAL runtime epigraph floor guard —
        # unconditional, independent of whether master.α_op/master.α_x's declared lower
        # bound came from :auto, an explicit Real, or was build-time-validated at all,
        # and independent of inexact_policy. oracle_res/follower_res have passed every
        # post-solve gate here (an :inexact oracle_res only under :certify_incumbent,
        # and it too has passed battery complementarity).
        # The guard's tolerance adds the
        # build-time acceptance slack of each bound (`_accepted_lb_slack`). Because
        # build time clamps every accepted explicit bound to the certified minimum at build time,
        # that slack is always 0.0 on both master types —
        # the term is kept only as a seam, it widens nothing.
        _assert_epigraph_floor(
            -oracle_res.cost,
            lower_bound(master.α_op),
            :op;
            gap = _measured_duality_gap(oracle.model),
            accepted_slack = _accepted_lb_slack(master, :op),
        )
        _assert_epigraph_floor(
            follower_res.cost,
            lower_bound(master.α_x),
            :x;
            accepted_slack = _accepted_lb_slack(master, :x),
        )

        # Remember a rejected trial for the stall backstop above; any other
        # optimality iteration resets it.
        last_rejected_z = rejected_k ? copy(lb_res.z) : nothing
        last_weak_feas_z = nothing   # optimality cuts are added — the master moves on
        # Oracle's :op cut — sign convention of the follower model, reused verbatim:
        # cost_k = -oracle_res.cost, grad_k = oracle_res.π (UNNEGATED).
        add_optimality_cut!(master, :op, -oracle_res.cost, oracle_res.π, lb_res.z)
        # Follower's :x cut — used exactly as solve_follower! returns it.
        add_optimality_cut!(master, :x, follower_res.cost, follower_res.π_s, lb_res.z)

        # apply_integer_cuts! fires generically on the optimality
        # branch — a TRUE no-op for BendersMaster (touches zero fields of lb_res, always
        # returns nogood_fired = false), real Laporte-Louveaux (always) + no-good
        # (on detected stall) logic for BendersMasterInteger.
        #
        # Q_nu_iterate: the recourse EXCLUDING the leader's own c_y*y term, evaluated AT
        # THE CURRENT ITERATE z = lb_res.z — exactly cost_k below, minus that term. This
        # is NOT what add_ll_cut! requires (see ll_cut_recourse immediately below).
        Q_nu_iterate = follower_res.cost - oracle_res.cost

        # THE FIX for the defect the enumeration-backed certification found in
        # this wiring: add_ll_cut!'s own
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
        # state — the continuous path is BIT-FOR-BIT IDENTICAL to before this fix); for
        # BendersMasterInteger it performs the real minimization via the SAME
        # deterministic ternary-search technique as
        # test_planning_certification_integer.jl's own `enumerate_lattice` reference
        # implementation, reusing the REAL, already-built `oracle`/`follower` (never
        # rebuilt, never a closed-form shortcut).
        t0_ns = time_ns()
        # the corner search runs under the
        # SAME policy as the outer trial — :throw under :strict, :report otherwise.
        Q_nu = ll_cut_recourse(
            master,
            oracle,
            follower,
            lb_res,
            Q_nu_iterate;
            on_inexact = inexact_policy === :strict ? :throw : :report,
            feas_oracle = feas_oracle,
        )
        t_solve += (time_ns() - t0_ns) / 1.0e9

        integer_cut_res = apply_integer_cuts!(master, lb_res, Q_nu)
        integer_cut_res.nogood_fired && (nogood_total += 1)

        # track the incumbent, not just the bound — store the (y, z) pair that
        # achieved the running-minimum UB so the converged return is the certified point.
        cost_k = master.c_y * lb_res.y + Q_nu_iterate
        # a rejected (inexact, :reject) trial never updates UB or the incumbent.
        if !rejected_k && cost_k < UB
            UB = cost_k
            y_best = lb_res.y
            z_best = copy(lb_res.z)
            # the incumbent's exactness certificate is
            # the verdict of the VERY solve that produced UB — recorded here, never
            # re-derived later by a second solve (whose sticky retry attributes could
            # disagree with this one).
            incumbent_exactness = oracle_res.exactness
            incumbent_socp_maxgap = oracle_res.socp_maxgap
            incumbent_welfare = oracle_res.cost
        end
        # the certified incumbent, updated only
        # by a certified iterate, compared only against other certified costs.
        if oracle_res.exactness !== :inexact && (exact_inc === nothing || cost_k < exact_inc.UB)
            exact_inc = (;
                y = lb_res.y,
                z = copy(lb_res.z),
                UB = cost_k,
                exactness = oracle_res.exactness,
                socp_maxgap = oracle_res.socp_maxgap,
                welfare = oracle_res.cost,
            )
        end
        gap = (UB - lb_res.LB) / max(1, abs(UB))

        checkpoint_iteration!(
            (; k, LB = lb_res.LB, UB, gap, z_k = lb_res.z, feasible = true),
            k;
            dir = checkpoint_dir,
        )
        # Optimality-branch trace row. retry_count sums BOTH retry-gated
        # solves' net retries this iteration (master's and the oracle's), since both
        # actually ran; oracle_status records the oracle's own genuine termination
        # status (never the :not_solved sentinel on this branch). nogood_count
        # records THIS iteration's no-good firing (0 or 1) — always 0 on
        # the continuous path.
        push!(
            trace,
            k;
            LB = lb_res.LB,
            UB = UB,
            gap = gap,
            cut_type = :optimality,
            n_cuts = length(master.cuts),
            # the status captured immediately after solve_master!, before the
            # add_optimality_cut! calls dirtied the model. oracle_status_k was captured
            # immediately after the oracle's OWN solve at lb_res.z, BEFORE
            # ll_cut_recourse's BendersMasterInteger
            # branch potentially re-solves oracle.model at OTHER z trials during its
            # internal ternary search — querying termination_status(oracle.model) HERE
            # instead would silently report the LAST such trial's status.
            master_status = master_status_k,
            oracle_status = oracle_status_k,
            retry_count = (master_attempts[] - 1) + (oracle_attempts[] - 1),
            solve_time = t_solve,
            nogood_count = integer_cut_res.nogood_fired ? 1 : 0,
            # :none on the ordinary success path,
            # :certified_incumbent when inexact_policy's :certify_incumbent branch fired.
            # socp_maxgap is the MEASURED cone residual whenever the gate ran.
            policy_action = policy_action_k,
            socp_maxgap = socp_maxgap_k,
        )

        # An EXCLUSIVE branch,
        # NEVER an `||` of the two criteria — reusing `tol` on the `known_optimum`-supplied
        # (certified) path would silently reintroduce the continuous loop's tolerance on
        # exactly the path this mechanism exists to keep tolerance-free. When
        # known_optimum === nothing, this reduces EXACTLY to `gap <= tol`, bit-for-bit identical
        # to the plain continuous criterion.
        # The convergence test as a function of an upper bound, so the SAME test can be
        # applied to the certified incumbent (`_select_incumbent`).
        LB_k = lb_res.LB
        converged_at(UBx) =
            known_optimum === nothing ? ((UBx - LB_k) / max(1, abs(UBx)) <= tol) :
            isapprox(UBx, known_optimum; atol = KNOWN_OPTIMUM_ATOL)
        converged_now = converged_at(UB)

        if converged_now
            # apply the documented incumbent
            # ordering. Only when the running-minimum incumbent is relaxation-only AND
            # the certified incumbent is itself converged does the returned point change.
            chosen = _select_incumbent(
                (;
                    y = y_best,
                    z = z_best,
                    UB,
                    exactness = incumbent_exactness,
                    socp_maxgap = incumbent_socp_maxgap,
                    welfare = incumbent_welfare,
                ),
                exact_inc,
                converged_at,
            )
            y_best = chosen.y
            z_best = chosen.z
            UB = chosen.UB
            gap = (UB - lb_res.LB) / max(1, abs(UB))
            incumbent_exactness = chosen.exactness
            incumbent_socp_maxgap = chosen.socp_maxgap
            incumbent_welfare = chosen.welfare
            # The best certified point and its OWN physical gap (UB_exact is a true upper
            # bound there; LB is a valid lower bound whatever the exactness verdicts).
            exact_incumbent =
                exact_inc === nothing ? nothing :
                (;
                    exact_inc.y,
                    exact_inc.z,
                    exact_inc.UB,
                    gap = (exact_inc.UB - lb_res.LB) / max(1, abs(exact_inc.UB)),
                    exact_inc.exactness,
                    exact_inc.socp_maxgap,
                )
            # + the AC
            # re-check runs ONCE, at the converged incumbent, iff the incumbent's OWN
            # recorded verdict is :inexact — only reachable under :certify_incumbent
            # (:strict throws on any inexact solve; :reject never lets an inexact iterate
            # become the incumbent). No second oracle solve happens here, so sticky retry
            # attributes cannot change the verdict and no policy is bypassed. The report
            # carries the SOCP welfare at the same z so the relaxation error in UB is
            # measured, not just flagged.
            ub_relaxation_only = incumbent_exactness === :inexact
            # a failure of this diagnostic is REPORTED on
            # ac_report, never allowed to discard the converged result.
            ac_report =
                ub_relaxation_only ?
                _incumbent_ac_report(feeder, aggregators, λ₀, T, z_best, incumbent_welfare) :
                nothing

            # return the INCUMBENT — c(y_best, z_best) = UB <= LB + tol*max(1,|UB|)
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
                # Appended AFTER every existing field so
                # every prior caller destructuring by name is unaffected (NamedTuple
                # field access is name-based, never position-based).
                nogood_count = nogood_total,
                converged_via = nogood_total > 0 ? :nogood_assisted : :clean,
                # A TRAILING, additive field — `nothing`
                # unless the incumbent is SOCP-inexact, then the populated AC re-check
                # report (see the docstring's Returns section).
                ac_report,
                # The incumbent's exactness certificate.
                # When ub_relaxation_only is true, UB/gap certify the SOC RELAXATION
                # only — UB is then not an upper bound on the physical problem.
                incumbent_exactness,
                incumbent_socp_maxgap,
                ub_relaxation_only,
                # The best certified incumbent,
                # `nothing` if no iterate was certified (trailing, additive).
                exact_incumbent,
                # Documented status vocabulary (STATUS_VOCABULARY.solve_stackelberg).
                status = ub_relaxation_only ? :converged_relaxation_only : :converged,
            )
        end
    end

    # Read the exhaustion diagnostic from the TRACE's last recorded
    # row, never a loop-local variable that can be stale/NaN if the final iterations
    # were all feasibility branches — every iteration pushes exactly one trace row on
    # either branch, so trace.iters == max_iter and last(...) is always well-defined here.
    last_LB = last(trace.LB_trace)
    last_UB = last(trace.UB_trace)
    last_gap = last(trace.gap_trace)
    throw(ConvergenceError(
        "solve_stackelberg!: exhausted $max_iter iteration(s) without converging " *
        "(last recorded LB=$last_LB, UB=$last_UB, gap=$last_gap [gap may be NaN if the " *
        "final iteration was a feasibility cut], tol=$tol) — refusing to silently " *
        "return a non-converged result";
        iterations = max_iter,
    ))
end

export solve_stackelberg!
