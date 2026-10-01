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
        # CR-02: the explicit certificate agrees — the incumbent's own solve was exact,
        # so UB/gap are NOT relaxation-only here.
        @test result.incumbent_exactness === :exact
        @test !result.ub_relaxation_only

        # BILEV-04a cross-check (Task 2 regression, confirmed NATURALLY on this
        # realistic multi-bus fixture, not just plan 30-01's own purpose-built ones):
        # the SAME run also hits a genuine MOI.INFEASIBLE trial along the way.
        @test :oracle_feasibility_cut in result.trace.policy_action_trace
    end
end

@testitem "planning inexact policy: solve_planning_oracle! reports exactness explicitly and never skips the complementarity gate (CR-01/CR-03)" tags =
    [:planning] setup = [IEEE13ShortHorizonFixtures] begin
    using TSODSO

    # Phase 30 code review (CR-01/CR-03). The measured pins come from
    # IEEE13ShortHorizonFixtures' own header sweep map: uniform z = 0.0 is feasible and
    # SOCP-exact, uniform z = 0.06 is feasible but measurably SOCP-INEXACT.
    feeder = TSODSO.ieee13_modified()
    aggs = IEEE13ShortHorizonFixtures.population(feeder)
    λ₀ = IEEE13ShortHorizonFixtures.LAMBDA0
    T = IEEE13ShortHorizonFixtures.T
    oracle = TSODSO.build_planning_oracle(feeder, ConvexBranchFlow(), aggs; λ₀ = λ₀, T = T)

    # Function barrier (TestItem try-scoping trap): return the caught exception or nothing.
    function caught(f)
        try
            f()
            return nothing
        catch e
            return e
        end
    end

    # 1. Exact pin: explicit :exact verdict, measured gap returned AND stashed.
    r0 = TSODSO.solve_planning_oracle!(oracle, zeros(T); on_inexact = :report)
    @test r0.exactness === :exact
    @test isfinite(r0.socp_maxgap)
    @test oracle.ctx.meta[:socp_maxgap] == r0.socp_maxgap

    # 2. Inexact pin, default :throw mode: the gate's own error, byte-identical.
    e1 = caught(() -> TSODSO.solve_planning_oracle!(oracle, fill(0.06, T)))
    @test e1 isa ErrorException
    @test occursin("SOCP relaxation INEXACT", e1.msg)
    # The stale exact-pin certificate from step 1 must NOT survive an inexact solve.
    @test !haskey(oracle.ctx.meta, :socp_maxgap)

    # 3. Inexact pin, :report mode: the verdict is RETURNED, with the measured residual,
    # and no PF-04 certificate is stashed on the inexact ctx.
    r2 = TSODSO.solve_planning_oracle!(oracle, fill(0.06, T); on_inexact = :report)
    @test r2.exactness === :inexact
    @test r2.socp_maxgap > 0
    @test !haskey(oracle.ctx.meta, :socp_maxgap)

    # 4. CR-01: the battery-complementarity gate still runs on an inexact :report result.
    # A negative relative τ makes every product p_ch·p_dch ≥ τ·Pmax² (the gate's own
    # monotone threshold), so the gate MUST throw if it runs at all; before the fix the
    # inexact path skipped it entirely.
    e3 = caught(
        () -> TSODSO.solve_planning_oracle!(
            oracle,
            fill(0.06, T);
            on_inexact = :report,
            τ = -1.0,
        ),
    )
    @test e3 isa ErrorException
    @test occursin("Battery complementarity violated", e3.msg)

    # 5. CR-03: a formulation with no `:l` stash (LinDistFlow) reports :not_applicable —
    # the exactness gate never ran, so no cone residual is read (the old disambiguation
    # called socp_relaxation_gap here and died with a FieldError on `pv.l`), and its
    # complementarity throw propagates with its OWN message.
    oracle_ldf = TSODSO.build_planning_oracle(feeder, LinDistFlow(), aggs; λ₀ = λ₀, T = T)
    r4 = TSODSO.solve_planning_oracle!(oracle_ldf, zeros(T); on_inexact = :report)
    @test r4.exactness === :not_applicable
    @test isnan(r4.socp_maxgap)
    e5 = caught(
        () -> TSODSO.solve_planning_oracle!(
            oracle_ldf,
            zeros(T);
            on_inexact = :report,
            τ = -1.0,
        ),
    )
    @test e5 isa ErrorException
    @test occursin("Battery complementarity violated", e5.msg)

    @test_throws ArgumentError TSODSO.solve_planning_oracle!(
        oracle,
        zeros(T);
        on_inexact = :ignore,
    )
end

@testitem "planning inexact policy: an SOCP-inexact incumbent is labelled relaxation-only and gets a populated AC report end-to-end (CR-02)" tags =
    [:planning] begin
    using TSODSO

    # Phase 30 code review (CR-02): the FIRST test that drives the populated-`ac_report`
    # path through `solve_stackelberg!` itself (every other item's incumbent is exact).
    #
    # FIXTURE (measured 2026-10-01, scratchpad probe_cr02b.jl): the single-Thermostatic
    # T=1 population on the UNMODIFIED `ieee13_modified()` at a NEGATIVE wholesale price
    # λ₀ = [-1.0] (an oversupply hour — the network is PAID to import). The pinned SOC
    # relaxation then prefers to "dissipate" the extra import in a slack cone, so every
    # feasible pin above the load is genuinely SOCP-inexact: measured maxgap 4.3e-4 at
    # z=0.0105, 5.9e-3 at 0.02, 1.1e-2 at 0.03, 1.74e-2 at 0.04. With near-zero
    # investment costs the Benders optimum sits at the box corner z = y_max = 0.04, so the
    # incumbent itself is inexact. Measured run: iters=4, gap≈2.0e-9, z_best=[0.04],
    # incumbent maxgap=1.74e-2; the AC re-check SOLVES with no limit violated
    # (max_overload_ratio≈0.648, |V|≈0.9846), ac_welfare≈socp_welfare (gap≈3e-10).
    T = 1
    feeder = TSODSO.ieee13_modified()
    therm = TSODSO.Thermostatic(2, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, fill(25.0, T))
    agg = TSODSO.Aggregator(2, 0.9, [therm], fill(0.01, T))

    mktempdir() do dir
        result = TSODSO.solve_stackelberg!(
            feeder,
            ConvexBranchFlow(),
            [agg];
            λ₀ = [-1.0],
            T = T,
            follower_kwargs = (; corridor_cap = 1.0, x_inv_max = 0.2, c_inv = 0.01, c_op = [0.01]),
            master_kwargs = (; c_y = 0.01, y_max = 0.04),   # :auto α bounds
            tol = 1.0e-6,
            max_iter = 30,
            checkpoint_dir = dir,
        )

        @test result.gap <= 1.0e-6
        # The incumbent's OWN solve was inexact, and the result says so explicitly.
        @test result.incumbent_exactness === :inexact
        @test result.ub_relaxation_only
        @test result.incumbent_socp_maxgap > 1.0e-3     # measured 1.74e-2
        @test :certified_incumbent in result.trace.policy_action_trace

        # The populated AC re-check report, reached through solve_stackelberg!.
        rep = result.ac_report
        @test rep !== nothing
        @test rep.raw_status == "Solve_Succeeded"
        @test length(rep.p_import) == T
        @test isapprox(rep.p_import, result.z; atol = 1.0e-6)
        # `ok` is DERIVED from the violation counts, never hard-coded.
        @test rep.ok == (
            rep.violations.n_thermal_violations == 0 &&
            rep.violations.n_voltage_violations == 0
        )
        @test rep.ok                                   # measured: no limit violated
        # The relaxation error in UB is MEASURED: SOCP vs AC welfare at the same z.
        @test isfinite(rep.socp_welfare) && isfinite(rep.ac_welfare)
        @test rep.welfare_gap == rep.socp_welfare - rep.ac_welfare
    end
end
