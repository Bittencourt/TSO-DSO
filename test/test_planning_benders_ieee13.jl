# test/test_planning_benders_ieee13.jl
#
# Seam: end-to-end Benders on the IEEE-13 short-horizon fixture — the headline demonstration. A single
# `@testitem` runs the REAL `solve_stackelberg!` Benders loop (`src/planning/benders.jl`)
# with the REAL `ConvexBranchFlow()` SOCP branch-flow formulation on a realistic
# multi-bus, multi-period feeder (`TSODSO.ieee13_modified()`, T=4), consuming the tuned
# population fixture (`IEEE13ShortHorizonFixtures`,
# `test/fixtures_planning_ieee13_short.jl`). The convergence result is cross-checked
# against `IEEE13ShortHorizonFixtures.solve_joint_reference` — an INDEPENDENTLY-BUILT
# monolithic single-shot SOCP model representing the SAME integrated problem
# `solve_stackelberg!` Benders-decomposes, built from scratch (NEVER a reuse of
# `PlanningOracle`/`FollowerLP`/`BendersMaster`; independence is required).
#
# This is also the FIRST test in the suite to exercise `build_master`'s `:auto`
# `α_op_lb`/`α_x_lb` default END-TO-END on a `ConvexBranchFlow` multi-bus fixture:
# `master_kwargs` below OMITS both keys entirely, so `solve_stackelberg!`'s
# unconditional `bounds_ctx` wiring derives them itself via a
# genuine one-time relaxed solve, never an explicit literal.
#
# Items tagged `[:planning]`, name contains "planning", "benders", and "ieee13"
# (occursin filter convention, mirrors `test_planning_benders.jl`/
# `test_planning_ieee13_short_fixture.jl`).
#
# --- FIXTURE CONFIGURATION (the fixture's own smoke-test tuple verbatim, chosen
# because it was already confirmed to stay inside the fixture's measured
# feasible-and-exact `z ∈ [-0.05, 0.05]` window end-to-end) ---
#
#   follower_kwargs = (; corridor_cap=1.0, x_inv_max=0.05, c_inv=0.01, c_op=fill(0.01,T))
#   master_kwargs   = (; c_y=0.01, y_max=0.05)   <- NO α_op_lb/α_x_lb: exercises :auto
#
# --- MEASURED CONVERGENCE OUTCOME (JULIA_LOAD_PATH="test:.:@stdlib" julia,
# convergence probe against the UNMODIFIED `ieee13_modified()` + this exact
# population/kwargs) ---
#
#   RE-MEASURED 2026-10-01 after the scale-aware :auto
#   margin lowered α_op_lb from optimum−1e-6 to optimum−1.5e-5, which moved this
#   trajectory slightly; the earlier values are in parentheses:
#   iters = 6, gap = 3.160109796119891e-7 (3.141e-7) (<= tol=1e-6)
#   UB = 609.01133901254 (609.0113506), LB = 609.0111465582702 (609.0111593)
#   y = 0.05, z = [0.001173086302114036, -0.0, -0.0, 0.050000000000067095]
#     (z[1] was 0.0010187)
#   ac_report = nothing; incumbent_exactness = :exact; trace.socp_maxgap_trace (the
#     MEASURED per-iteration cone residual — it used to be a NaN placeholder on exact
#     rows) = [2.24e-10, 3.13e-9, 4.17e-9, 8.89e-10, 1.69e-10, 2.85e-10]
#     (every iteration SOCP-EXACT — a legitimate outcome per the fixture's sweep map,
#     since this whole box sits inside the documented exact window; see this file's
#     own cone-gap assertions below for the POSITIVE statement this makes, never a
#     silent skip)
#
# --- CROSS-CHECK: A BRACKET, NOT A TOLERANCE BAND ---
#
# Benders' own certificate is `LB <= J* <= UB` for the joint optimum `J*` of the SAME
# relaxation whenever every cut is valid. The cross-check therefore asserts exactly that
# bracket, widened only by the two solvers' OWN runtime-measured duality gaps (read inside
# the test, never frozen):
#
#   ε = 10 * max(oracle_gap, joint.gap)
#   @test result.LB - ε <= -joint.welfare_total <= result.UB + ε
#
# where `oracle_gap = |objective_value − dual_objective_value|` of the oracle re-solved at
# the incumbent and `joint.gap` the same quantity on `solve_joint_reference`'s own model
# (which now solves with `dual = true` and certifies its OWN cone exactness via
# `assert_socp_exact!` — it would throw otherwise, and its `socp_maxgap` is asserted
# below). The previous version froze `10 * (UB − LB)` of one run as a literal (a picked
# number dressed as a measurement, 10x LOOSER than the certificate it checked) and cited a
# `joint.gap` field that did not exist. Measured 2026-10-01: oracle_gap = 2.78e-7,
# joint.gap = 1.92e-7 (joint socp_maxgap = 2.1e-10, exact), so ε = 2.78e-6, and
# J* = 609.0112017 lies inside [LB, UB] = [609.0111466, 609.0113390]
# (J* − LB = 5.5e-5, UB − J* = 1.37e-4) without needing ε at all.
#
# Independence scope: the joint model shares no oracle/follower/master object
# with the decomposition but is built from the same `contribute!` builders, so this
# validates the Benders DECOMPOSITION, not the formulation itself.
#

@testitem "planning benders ieee13: converges on a realistic multi-bus feeder with :auto bounds, brackets an independent monolithic reference within measured solver gaps" tags =
    [:planning] setup = [IEEE13ShortHorizonFixtures] begin
    using TSODSO
    using JuMP: objective_value, dual_objective_value

    feeder = TSODSO.ieee13_modified()
    aggs = IEEE13ShortHorizonFixtures.population(feeder)
    λ₀ = IEEE13ShortHorizonFixtures.LAMBDA0
    T = IEEE13ShortHorizonFixtures.T

    # The fixture's own smoke-test tuple, reused verbatim (see this file's header comment for
    # why it stays inside the fixture's measured feasible-and-exact window end-to-end).
    follower_kwargs =
        (; corridor_cap = 1.0, x_inv_max = 0.05, c_inv = 0.01, c_op = fill(0.01, T))
    # NO α_op_lb/α_x_lb here — the FIRST ConvexBranchFlow multi-bus fixture in the suite
    # to exercise build_master's NEW `:auto` default end-to-end.
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
        # ConvergenceError on max_iter exhaustion otherwise.
        @test result.gap <= 1.0e-6
        # Structural floor (NOT a brittle exact count, mirroring
        # test_planning_hardening.jl's own convention): measured 6 in the recorded run,
        # generous headroom in case of future, economically-neutral solver-path drift.
        @test result.iters <= 30

        # The INDEPENDENTLY-BUILT monolithic joint-reference cross-check (it
        # must be an independently built model, not a re-use of the Benders
        # subproblems — IEEE13ShortHorizonFixtures.solve_joint_reference never reuses
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
        # same quantity at the joint, non-decomposed optimum).
        Jstar = -joint.welfare_total
        # The joint reference certified its OWN cone exactness (it throws otherwise).
        @test isfinite(joint.socp_maxgap)
        # Runtime-measured duality gaps: the oracle's at the incumbent, and the
        # joint model's own.
        TSODSO.solve_planning_oracle!(result.oracle, result.z)
        oracle_gap = abs(
            objective_value(result.oracle.model) - dual_objective_value(result.oracle.model),
        )
        ε = 10 * max(oracle_gap, joint.gap)
        @test isfinite(ε) && ε < 1.0e-4
        # The Benders certificate itself: LB <= J* <= UB, up to measured solver precision.
        # (Only the LOWER side tests the decomposition — it fails if
        # any appended cut over-estimates the value function. The upper side holds for any
        # feasible UB against a global optimum and is kept as a sanity check only.)
        @test result.LB - ε <= Jstar
        @test Jstar <= result.UB + ε

        # The "do not assume exactness" requirement: a POSITIVE statement about
        # the incumbent's cone-gap status, never a silent skip. This fixture's own
        # kwargs keep the whole Benders trial box inside the measured
        # feasible-and-exact z ∈ [-0.05, 0.05] window (the fixture's own sweep table), so
        # EVERY iteration in the recorded run came back SOCP-EXACT (confirmed: every
        # policy_action is :none, every measured socp_maxgap is <= 4.2e-9, and
        # ac_report === nothing) — a legitimate, even likely, outcome per that same
        # sweep table, not a cop-out: the inexact branch is exercised instead by
        # test_planning_inexact_policy.jl's own fixtures, which deliberately drive trials
        # (and, in one item, the incumbent) past this window.
        @test result.ac_report === nothing
        @test result.incumbent_exactness === :exact
        @test !result.ub_relaxation_only
        # The MEASURED cone gap of every optimality row is
        # recorded (it used to be a NaN placeholder on exact rows, making this assertion
        # vacuous). Every row's verdict was exact, and the incumbent's own measured gap
        # is returned.
        tr = result.trace
        opt_rows = findall(==(:optimality), tr.cut_type_trace)
        @test all(i -> isfinite(tr.socp_maxgap_trace[i]), opt_rows)
        @test all(==(:none), tr.policy_action_trace)
        @test TSODSO.trace_summary(tr).n_inexact_iterations == 0
        @test isfinite(result.incumbent_socp_maxgap)
    end
end
