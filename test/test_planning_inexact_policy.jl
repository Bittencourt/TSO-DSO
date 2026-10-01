# test/test_planning_inexact_policy.jl
#
# Seam: src/planning/benders.jl's `solve_stackelberg!` `inexact_policy` dispatch
# (BILEV-04b, plan 30-04 Task 3). The 3-policy matrix (`:strict`/`:reject`/
# `:certify_incumbent`) at a MEASURED, naturally-occurring SOCP-inexact pin — never a
# synthetic forced case.
#
# FIXTURE (measured THIS session, JULIA_LOAD_PATH="test:.:@stdlib" julia probe.jl,
# reusing plan 30-03's own `IEEE13ShortHorizonFixtures` population/feeder
# `test/fixtures_planning_ieee13_short.jl`, T=4): `solve_stackelberg!` on the UNMODIFIED
# `ieee13_modified()` with this population, `ConvexBranchFlow()`,
# `follower_kwargs = (; corridor_cap=1.0, x_inv_max=0.1, c_inv=1e-6, c_op=fill(1e-6,T))`,
# `master_kwargs = (; c_y=1e-6, y_max=0.07, α_op_lb=-2000.0, α_x_lb=-10.0)`, `tol=1e-4` —
# chosen so the leader/follower's own economics barely discourage investment, letting the
# Benders iterates converge toward the population's TRUE unconstrained economic optimum
# near `z[4] ≈ 0.050`, a hair above the fixture's own documented feasible-and-exact
# boundary (`z <= 0.05` exact, `z = 0.06` measurably inexact, `z >= 0.0686` infeasible —
# see that fixture module's own header sweep table). Measured iteration trajectory under
# `:certify_incumbent` (the cross-reference every item below is checked against):
#
# | iter | outcome                                                                |
# |------|-------------------------------------------------------------------------|
# | 1    | optimality, EXACT (z=0, the fixture's own documented z=0 anchor)        |
# | 2,3  | GENUINE `MOI.INFEASIBLE` -> `:oracle_feasibility_cut` (BILEV-04a fires NATURALLY on this realistic multi-bus fixture, confirming Task 2's branch works beyond its own purpose-built fixtures) |
# | 4,5  | optimality, EXACT                                                       |
# | 6    | GENUINE `MOI.INFEASIBLE` -> `:oracle_feasibility_cut`                   |
# | 7,8  | SOCP-INEXACT (maxgap ≈ 1.7e-3–1.8e-3) -> policy dispatch fires HERE     |
# | 9    | optimality, EXACT                                                       |
# | 10   | SOCP-INEXACT (maxgap ≈ 2.4e-3) -> policy dispatch fires again           |
# | 11   | optimality, EXACT -> CONVERGES (gap ≈ 5.5e-5 <= tol=1e-4)               |
#
# `:oracle_feasibility_cut` firing is UNCONDITIONAL regardless of `inexact_policy` (it is
# resolved BEFORE the policy dispatch in `solve_stackelberg!`'s own disambiguation — see
# that function's `<interfaces>`), so iterations 2/3/6 behave IDENTICALLY under all three
# policies below; only iterations 7/8/10 (the genuine exactness-class throws) differ.
#
# `max_iter=10` for `:strict`/`:reject` (both resolve — throw or stall — by iteration 7-8,
# well inside the budget) and `max_iter=20` for `:certify_incumbent` (converges at
# iteration 11) keep every item's solve time small (a handful of cheap IEEE-13 T=4 SOCP
# re-solves, ~tens of ms each per 30-RESEARCH.md's own measurement).
#
# Items tagged `[:planning]`, names contain "planning" and "inexact" (occursin filter
# convention, mirrors this phase's other new test files).

@testitem "planning inexact policy: :strict reproduces solve_planning_oracle!'s own exactness throw" tags =
    [:planning] setup = [IEEE13ShortHorizonFixtures] begin
    using TSODSO

    feeder = TSODSO.ieee13_modified()
    aggs = IEEE13ShortHorizonFixtures.population(feeder)
    λ₀ = IEEE13ShortHorizonFixtures.LAMBDA0
    T = IEEE13ShortHorizonFixtures.T

    follower_kwargs =
        (; corridor_cap = 1.0, x_inv_max = 0.1, c_inv = 1.0e-6, c_op = fill(1.0e-6, T))
    master_kwargs =
        (; c_y = 1.0e-6, y_max = 0.07, α_op_lb = -2000.0, α_x_lb = -10.0)

    mktempdir() do dir
        # :strict must reproduce TODAY's byte-identical throw (the exactness-class error
        # `assert_socp_exact!` raises directly) — never silently swallowed, never a
        # DIFFERENT error (e.g. the "exhausted" message `:reject` would raise instead).
        caught = nothing
        try
            TSODSO.solve_stackelberg!(
                feeder,
                ConvexBranchFlow(),
                aggs;
                λ₀ = λ₀,
                T = T,
                follower_kwargs = follower_kwargs,
                master_kwargs = master_kwargs,
                tol = 1.0e-4,
                max_iter = 10,
                checkpoint_dir = dir,
                inexact_policy = :strict,
            )
        catch e
            caught = e
        end
        @test caught !== nothing
        @test caught isa ErrorException
        # Not over-constraining the FULL message (brittle) — just confirming it is
        # genuinely the SOCP-exactness gate's own error (PF-04), not some other failure
        # (e.g. a genuine infeasibility or the :reject-style "exhausted" message).
        @test occursin("SOCP relaxation INEXACT", caught.msg)
    end
end

@testitem "planning inexact policy: :reject skips the inexact trial — no guaranteed progress (T-30-09)" tags =
    [:planning] setup = [IEEE13ShortHorizonFixtures] begin
    using TSODSO

    feeder = TSODSO.ieee13_modified()
    aggs = IEEE13ShortHorizonFixtures.population(feeder)
    λ₀ = IEEE13ShortHorizonFixtures.LAMBDA0
    T = IEEE13ShortHorizonFixtures.T

    follower_kwargs =
        (; corridor_cap = 1.0, x_inv_max = 0.1, c_inv = 1.0e-6, c_op = fill(1.0e-6, T))
    master_kwargs =
        (; c_y = 1.0e-6, y_max = 0.07, α_op_lb = -2000.0, α_x_lb = -10.0)

    # `:reject` never appends ANY cut on the inexact trial (by design — see
    # `solve_stackelberg!`'s own docstring), so the master's LP is UNCHANGED on the next
    # iteration and deterministically re-proposes the IDENTICAL trial forever — a
    # genuine, documented, non-default-policy limitation (T-30-09, accepted in this
    # plan's own threat register), not a bug. This is the EXPECTED outcome at THIS
    # measured pin (confirmed empirically this session): `solve_stackelberg!` exhausts
    # `max_iter` and raises, rather than converging — one of the two outcomes this
    # plan's own PLAN.md Task 3 explicitly accepts as valid for this policy ("EITHER
    # outcome is acceptable ... provided that, if it converges, the trace shows
    # :rejected"). Cross-referenced against the companion `:certify_incumbent` item
    # below, run on the IDENTICAL fixture/configuration: its own trace shows the SAME
    # iteration range is genuinely SOCP-INEXACT-but-feasible (never a genuine
    # MOI.INFEASIBLE) — so this raise is attributable to the designed `:reject` branch
    # repeatedly re-firing on that same inexact trial, not to an unrelated follower/
    # oracle infeasibility or a modeling bug.
    mktempdir() do dir
        caught = nothing
        try
            TSODSO.solve_stackelberg!(
                feeder,
                ConvexBranchFlow(),
                aggs;
                λ₀ = λ₀,
                T = T,
                follower_kwargs = follower_kwargs,
                master_kwargs = master_kwargs,
                tol = 1.0e-4,
                max_iter = 10,
                checkpoint_dir = dir,
                inexact_policy = :reject,
            )
        catch e
            caught = e
        end
        @test caught !== nothing
        @test caught isa ErrorException
        @test occursin("exhausted", caught.msg)
        # NEVER the exactness gate's own message leaking through unhandled — :reject's
        # whole purpose is to intercept that throw and turn it into a skipped iteration.
        @test !occursin("SOCP relaxation INEXACT", caught.msg)
    end
end

@testitem "planning inexact policy: :certify_incumbent (default) converges, certifies the incumbent, logs the measured cone gap" tags =
    [:planning] setup = [IEEE13ShortHorizonFixtures] begin
    using TSODSO

    feeder = TSODSO.ieee13_modified()
    aggs = IEEE13ShortHorizonFixtures.population(feeder)
    λ₀ = IEEE13ShortHorizonFixtures.LAMBDA0
    T = IEEE13ShortHorizonFixtures.T

    follower_kwargs =
        (; corridor_cap = 1.0, x_inv_max = 0.1, c_inv = 1.0e-6, c_op = fill(1.0e-6, T))
    master_kwargs =
        (; c_y = 1.0e-6, y_max = 0.07, α_op_lb = -2000.0, α_x_lb = -10.0)

    mktempdir() do dir
        # :certify_incumbent is the DEFAULT — omitted here deliberately to also confirm
        # the default kwarg value matches the documented policy (never pass
        # inexact_policy explicitly on this item).
        result = TSODSO.solve_stackelberg!(
            feeder,
            ConvexBranchFlow(),
            aggs;
            λ₀ = λ₀,
            T = T,
            follower_kwargs = follower_kwargs,
            master_kwargs = master_kwargs,
            tol = 1.0e-4,
            max_iter = 20,
            checkpoint_dir = dir,
        )

        @test result.gap <= 1.0e-4

        # At least one iteration recorded a finite, nonzero cone gap (the inexact trial
        # was ACCEPTED and certified, not silently discarded).
        finite_gaps = filter(!isnan, result.trace.socp_maxgap_trace)
        @test !isempty(finite_gaps)
        @test all(g -> g > 0, finite_gaps)

        @test :certified_incumbent in result.trace.policy_action_trace

        # trace_summary's n_inexact_iterations (ADDITIVE, this plan) must count EXACTLY
        # the same rows as the finite socp_maxgap_trace entries above.
        @test TSODSO.trace_summary(result.trace).n_inexact_iterations == length(finite_gaps)

        # THIS fixture's measured trajectory (see file header): the FINAL (converged)
        # iteration is itself genuinely SOCP-EXACT — the inexact trials were transient,
        # mid-run excursions the policy survived, not the incumbent's own final state.
        # ac_report is therefore nothing here (documented: the "incumbent itself is
        # exact" case, not the "populated report" case — both are valid per BILEV-04b,
        # this fixture happens to land in the former).
        @test result.ac_report === nothing

        # BILEV-04a cross-check (Task 2 regression, confirmed NATURALLY on this
        # realistic multi-bus fixture, not just plan 30-01's own purpose-built ones):
        # the SAME run also hits a genuine MOI.INFEASIBLE trial along the way.
        @test :oracle_feasibility_cut in result.trace.policy_action_trace
    end
end
