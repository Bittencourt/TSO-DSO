# test/test_planning_benders_ieee13.jl
#
# Seam: BILEV-03 (Phase 30, plan 30-05) — the phase's headline demonstration. A single
# `@testitem` runs the REAL `solve_stackelberg!` Benders loop (`src/planning/benders.jl`)
# with the REAL `ConvexBranchFlow()` SOCP branch-flow formulation on a realistic
# multi-bus, multi-period feeder (`TSODSO.ieee13_modified()`, T=4), consuming the tuned
# population fixture plan 30-03 built (`IEEE13ShortHorizonFixtures`,
# `test/fixtures_planning_ieee13_short.jl`). The convergence result is cross-checked
# against `IEEE13ShortHorizonFixtures.solve_joint_reference` — an INDEPENDENTLY-BUILT
# monolithic single-shot SOCP model representing the SAME integrated problem
# `solve_stackelberg!` Benders-decomposes, built from scratch (NEVER a reuse of
# `PlanningOracle`/`FollowerLP`/`BendersMaster` — 30-CONTEXT.md's explicit instruction).
#
# This is also the FIRST test in the suite to exercise `build_master`'s `:auto`
# `α_op_lb`/`α_x_lb` default END-TO-END on a `ConvexBranchFlow` multi-bus fixture:
# `master_kwargs` below OMITS both keys entirely, so `solve_stackelberg!`'s
# unconditional `bounds_ctx` wiring (BILEV-05, plan 30-04) derives them itself via a
# genuine one-time relaxed solve, never an explicit literal.
#
# Items tagged `[:planning]`, name contains "planning", "benders", and "ieee13"
# (occursin filter convention, mirrors `test_planning_benders.jl`/
# `test_planning_ieee13_short_fixture.jl`).
#
# --- FIXTURE CONFIGURATION (reuses plan 30-03's own smoke-test tuple verbatim, chosen
# because 30-03-SUMMARY.md already confirmed it stays inside the fixture's measured
# feasible-and-exact `z ∈ [-0.05, 0.05]` window end-to-end) ---
#
#   follower_kwargs = (; corridor_cap=1.0, x_inv_max=0.05, c_inv=0.01, c_op=fill(0.01,T))
#   master_kwargs   = (; c_y=0.01, y_max=0.05)   <- NO α_op_lb/α_x_lb: exercises :auto
#
# --- MEASURED CONVERGENCE OUTCOME (this session, JULIA_LOAD_PATH="test:.:@stdlib" julia
# probe_3005_convergence.jl against the UNMODIFIED `ieee13_modified()` + this exact
# population/kwargs — see this comment block for the full transcript) ---
#
#   iters = 6, gap = 3.141107077821004e-7 (<= tol=1e-6)
#   UB = 609.0113505622323, LB = 609.011159265246
#   y = 0.05, z = [0.0010186833736006077, -0.0, -0.0, 0.0499999999999553]
#   ac_report = nothing; trace.socp_maxgap_trace = [NaN, NaN, NaN, NaN, NaN, NaN]
#     (every iteration SOCP-EXACT — a legitimate outcome per 30-03's own sweep map,
#     since this whole box sits inside the documented exact window; see this file's
#     own cone-gap assertions below for the POSITIVE statement this makes, never a
#     silent skip)
#
# --- MEASURED CROSS-CHECK TOLERANCE DERIVATION (mirrors `benders.jl`'s own
# `KNOWN_OPTIMUM_ATOL`/`JOINT_RECOURSE_GAP_TOL` convention: read each model's OWN
# certified solver precision, take 10x the worst observed source of imprecision — never
# a picked/guessed number) ---
#
# Three independent sources of imprecision were measured on the SAME run:
#   1. `oracle_gap = abs(objective_value(result.oracle.model) -
#      dual_objective_value(result.oracle.model))` at the incumbent's LAST oracle solve
#      = 2.7910277822229546e-7 (Clarabel SOCP interior-point duality gap).
#   2. `joint.gap` = the SAME `abs(objective_value - dual_objective_value)` read on
#      `solve_joint_reference`'s own model at ITS optimum = 1.9234505543863634e-7.
#   3. `ub_lb_gap = abs(result.UB - result.LB)` = 0.00019129698637243564 — the Benders
#      loop's OWN converged absolute bound gap. This is the DOMINANT source: `result.UB`
#      is only CERTIFIED to lie within this gap of the true joint optimum (the master's
#      `LB` is a valid lower bound on it whenever every cut is exact, which this run's
#      `ac_report === nothing` confirms) — a tighter cross-check than this would reject
#      a perfectly correct Benders convergence merely because `tol` (a RELATIVE gap,
#      1e-6) was not driven to an arbitrarily small ABSOLUTE value. Omitting this term
#      (10x-ing only the two solver-precision gaps) measurably FAILS the cross-check
#      below (|UB - (-welfare)| = 1.49e-4 > 2.79e-6) — confirmed this session — which is
#      exactly why it is included here, not silently dropped.
#
# `measured_tol = 10 * max(oracle_gap, joint.gap, ub_lb_gap)
#               = 10 * 0.00019129698637243564 = 0.0019129698637243564`
#
# Confirmed this session: `|result.UB - (-joint.welfare_total)| = 1.4885271548337187e-4`,
# comfortably inside `measured_tol` (≈13x margin), while the un-measured 2.79e-6 guess
# would have (incorrectly) failed.
#
# NOTE: TestItemRunner gives each `@testitem` its own anonymous module — a file-level
# `const` here would NOT be visible inside the item body (confirmed this session), so
# the constant itself is defined INSIDE the testitem below; this header comment is its
# sole documented derivation, per every other measured-constant convention in this repo.

@testitem "planning benders ieee13: converges on a realistic multi-bus feeder with :auto bounds, matches an independent monolithic reference within a measured tolerance" tags =
    [:planning] setup = [IEEE13ShortHorizonFixtures] begin
    using TSODSO

    feeder = TSODSO.ieee13_modified()
    aggs = IEEE13ShortHorizonFixtures.population(feeder)
    λ₀ = IEEE13ShortHorizonFixtures.LAMBDA0
    T = IEEE13ShortHorizonFixtures.T

    # 30-03's own smoke-test tuple, reused verbatim (see this file's header comment for
    # why it stays inside the fixture's measured feasible-and-exact window end-to-end).
    follower_kwargs =
        (; corridor_cap = 1.0, x_inv_max = 0.05, c_inv = 0.01, c_op = fill(0.01, T))
    # NO α_op_lb/α_x_lb here — the FIRST ConvexBranchFlow multi-bus fixture in the suite
    # to exercise build_master's NEW `:auto` default end-to-end (BILEV-05, plan 30-04).
    master_kwargs = (; c_y = 0.01, y_max = 0.05)

    mktempdir() do dir
        result = solve_stackelberg!(
            feeder,
            ConvexBranchFlow(),
            aggs;
            λ₀ = λ₀,
            T = T,
            follower_kwargs = follower_kwargs,
            master_kwargs = master_kwargs,
            tol = 1.0e-6,
            max_iter = 100,
            checkpoint_dir = dir,
        )

        # solve_stackelberg!'s own convergence certificate — it would have raised an
        # ErrorException on max_iter exhaustion otherwise.
        @test result.gap <= 1.0e-6
        # Structural floor (NOT a brittle exact count, mirroring
        # test_planning_hardening.jl's own convention): measured 6 this session,
        # generous headroom in case of future, economically-neutral solver-path drift.
        @test result.iters <= 30

        # The INDEPENDENTLY-BUILT monolithic joint-reference cross-check (CONTEXT.md:
        # "must be an independently built model, not a re-use of the Benders
        # subproblems" — IEEE13ShortHorizonFixtures.solve_joint_reference never reuses
        # PlanningOracle/FollowerLP/BendersMaster).
        joint = IEEE13ShortHorizonFixtures.solve_joint_reference(
            feeder,
            aggs;
            λ₀ = λ₀,
            T = T,
            c_y = master_kwargs.c_y,
            y_max = master_kwargs.y_max,
            corridor_cap = follower_kwargs.corridor_cap,
            x_inv_max = follower_kwargs.x_inv_max,
            c_inv = follower_kwargs.c_inv,
            c_op = follower_kwargs.c_op,
        )

        # Sign convention per solve_joint_reference's own docstring: result.UB (a
        # MIN-sense total cost) ≈ -joint.welfare_total (the MAX-sense negative of the
        # same quantity at the joint, non-decomposed optimum). Tolerance is the
        # MEASURED constant derived and documented in this file's own header comment
        # (never picked) — see that comment for the full three-source derivation
        # (oracle's own SOCP duality gap, joint reference's own SOCP duality gap, and
        # the Benders loop's own converged UB-LB absolute gap, 10x the worst of the
        # three).
        measured_crosscheck_atol = 0.0019129698637243564
        @test isapprox(result.UB, -joint.welfare_total; atol = measured_crosscheck_atol)

        # BILEV-03's "do not assume exactness" requirement: a POSITIVE statement about
        # the incumbent's cone-gap status, never a silent skip. This fixture's own
        # kwargs keep the whole Benders trial box inside the measured
        # feasible-and-exact z ∈ [-0.05, 0.05] window (30-03's own sweep table), so
        # EVERY iteration this session came back SOCP-EXACT (confirmed: every entry in
        # socp_maxgap_trace is the :none-sentinel NaN, and the AC-recheck-at-convergence
        # hook found ac_report === nothing) — a legitimate, even likely, outcome per
        # that same sweep table, not a cop-out: the alternative branch
        # (any(isfinite, ...) === true) is exercised instead by
        # test_planning_inexact_policy.jl's own fixture, which deliberately drives a
        # trial just past this window.
        @test result.ac_report === nothing
        @test all(isnan, result.trace.socp_maxgap_trace)
        @test all(a -> a in (:none, :certified_incumbent), result.trace.policy_action_trace)
    end
end
