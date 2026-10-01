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
# `max_iter=10` for `:strict` (throws at iteration 7) and `max_iter=20`/`50` for
# `:certify_incumbent`/`:reject` (both converge at iteration 11 — `:reject` appends the
# inexact trials' cuts since the Phase 30 code review iteration 2, WR-02) keep every item's solve time small (a handful of cheap IEEE-13 T=4 SOCP
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

@testitem "planning inexact policy: :reject appends the inexact trial's cuts but bars it from the incumbent, and converges certified-only (T-30-09, WR-02 iter 2)" tags =
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

    # Phase 30 code review iteration 2 (WR-02). `:reject` used to append NO cut at an
    # inexact trial, so the master re-proposed it and the run could only ever stall.
    # Now the trial's relaxation cuts are appended (valid lower bounds whatever the
    # exactness verdict) and only its access to UB / the incumbent is barred. The master
    # therefore follows EXACTLY the same trajectory as under :certify_incumbent; only
    # UB differs while an inexact trial would have been the running minimum. MEASURED
    # 2026-10-01 (scratchpad fix2/probe_wr02.jl), both policies: iters = 11,
    # UB = 609.0155321155983, LB = 608.9819521916484, the same exact incumbent; rows
    # 7, 8, 10 are the inexact trials (:rejected here); UB_trace[10] = 609.043154704391
    # under :reject vs 609.0392231361435 (a relaxation-only value) under
    # :certify_incumbent.
    solve_with(pol) = mktempdir() do dir
        TSODSO.solve_stackelberg!(
            feeder,
            ConvexBranchFlow(),
            aggs;
            λ₀ = λ₀,
            T = T,
            follower_kwargs = follower_kwargs,
            master_kwargs = master_kwargs,
            tol = 1.0e-4,
            max_iter = 50,
            checkpoint_dir = dir,
            inexact_policy = pol,
        )
    end
    rr = solve_with(:reject)
    rc = solve_with(:certify_incumbent)

    @test rr.gap <= 1.0e-4
    tr = rr.trace
    rejected = findall(==(:rejected), tr.policy_action_trace)
    @test rejected == findall(==(:certified_incumbent), rc.trace.policy_action_trace)
    @test !isempty(rejected)
    # The rejected rows appended their optimality cuts (the master moved on) ...
    @test all(i -> tr.cut_type_trace[i] === :optimality, rejected)
    @test tr.n_cuts_trace == rc.trace.n_cuts_trace
    @test tr.LB_trace ≈ rc.trace.LB_trace
    # ... but never touched UB: it is unchanged across every rejected row.
    @test all(i -> tr.UB_trace[i] == tr.UB_trace[i - 1], rejected)
    @test all(tr.UB_trace .>= rc.trace.UB_trace)
    # UB / the returned point are certified-only under :reject.
    @test rr.incumbent_exactness === :exact
    @test !rr.ub_relaxation_only
    @test rr.UB ≈ rc.UB
    @test rr.z ≈ rc.z
end

@testitem "planning inexact policy: :reject fails fast when the relaxation's optimum is itself inexact (WR-06 backstop, WR-02 iter 2)" tags =
    [:planning] begin
    using TSODSO

    # The CR-02 T=1 fixture below (λ₀ = [-1.0]): every feasible pin above the 0.01 load is
    # SOCP-inexact and the relaxation's optimum is the box corner z = y_max = 0.04. Under
    # :reject the corner's cuts are appended, the master re-proposes the identical corner
    # (the relaxation's optimum), and no certified incumbent can close the gap there.
    # MEASURED 2026-10-01 (scratchpad fix2/probe_wr01.jl, POL=reject): the stall fires at
    # iteration 5 at z = [0.04], best certified UB = 12.240262587779437 (the certified
    # boundary point z ≈ 0.010039) — 4 completed iterations, far short of max_iter = 30.
    T = 1
    feeder = TSODSO.ieee13_modified()
    therm = TSODSO.Thermostatic(2, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, fill(25.0, T))
    agg = TSODSO.Aggregator(2, 0.9, [therm], fill(0.01, T))

    function caught(f)
        try
            f()
            return nothing
        catch e
            return e
        end
    end

    mktempdir() do dir
        e = caught(
            () -> TSODSO.solve_stackelberg!(
                feeder,
                ConvexBranchFlow(),
                [agg];
                λ₀ = [-1.0],
                T = T,
                follower_kwargs = (;
                    corridor_cap = 1.0,
                    x_inv_max = 0.2,
                    c_inv = 0.01,
                    c_op = [0.01],
                ),
                master_kwargs = (; c_y = 0.01, y_max = 0.04),
                tol = 1.0e-6,
                max_iter = 30,
                checkpoint_dir = dir,
                inexact_policy = :reject,
            ),
        )
        @test e isa ErrorException
        @test occursin(":reject stalled", e.msg)
        @test !occursin("exhausted", e.msg)
        @test !occursin("SOCP relaxation INEXACT", e.msg)
        @test length(filter(f -> endswith(f, ".jld2"), readdir(dir))) == 4
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

        # WR-05 (Phase 30 code review): the measured cone gap is recorded on EVERY
        # optimality row (exact and inexact), NaN only on feasibility-cut rows. The
        # inexact (certified) rows' gaps must sit far above the exact rows' gaps
        # (measured 2026-10-01: inexact 1.71e-3–2.40e-3, exact <= 1.41e-8 on this run).
        tr = result.trace
        opt_rows = findall(==(:optimality), tr.cut_type_trace)
        @test all(i -> isfinite(tr.socp_maxgap_trace[i]), opt_rows)
        @test all(i -> isnan(tr.socp_maxgap_trace[i]), findall(==(:feasibility), tr.cut_type_trace))
        inexact_rows = findall(==(:certified_incumbent), tr.policy_action_trace)
        exact_rows = filter(i -> tr.policy_action_trace[i] === :none, opt_rows)
        @test !isempty(inexact_rows) && !isempty(exact_rows)
        @test minimum(tr.socp_maxgap_trace[inexact_rows]) >
              1000 * maximum(tr.socp_maxgap_trace[exact_rows])

        # trace_summary's n_inexact_iterations counts the inexact-VERDICT rows (by policy
        # action), not the finite-gap rows.
        @test TSODSO.trace_summary(tr).n_inexact_iterations == length(inexact_rows)

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
        # WR-01 (iteration 2): the returned point is certified, so the certified
        # incumbent IS the returned point.
        @test result.exact_incumbent !== nothing
        @test result.exact_incumbent.UB == result.UB
        @test result.exact_incumbent.z == result.z
        @test result.exact_incumbent.gap == result.gap

        # BILEV-04a cross-check (Task 2 regression, confirmed NATURALLY on this
        # realistic multi-bus fixture, not just plan 30-01's own purpose-built ones):
        # the SAME run also hits a genuine MOI.INFEASIBLE trial along the way.
        @test :oracle_feasibility_cut in result.trace.policy_action_trace
        # WR-06 (iteration 2): the measured slack-min v is recorded on every oracle
        # feasibility row (NaN elsewhere); on this run every such cut is separating.
        fc = findall(a -> a in (:oracle_feasibility_cut, :oracle_feasibility_cut_weak), tr.policy_action_trace)
        @test all(i -> tr.feas_cut_v_trace[i] > TSODSO.FEAS_CUT_V_TOL, fc)
        @test all(i -> isnan(tr.feas_cut_v_trace[i]), setdiff(1:(tr.iters), fc))
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
        # WR-01 (iteration 2): the run DID visit one certified point — iteration 2 at
        # z ≈ 0.010039, right at the load boundary (measured 2026-10-01, scratchpad
        # fix2/probe_wr01.jl: UB 12.240262587779437, socp_maxgap 6.6e-11). It used to be
        # displaced silently by the cheaper relaxation-only iterates. It is now reported
        # alongside, with its own PHYSICAL gap against the same LB (measured 2.37e-3),
        # and is not returned as the main point because that gap exceeds tol.
        ex = result.exact_incumbent
        @test ex !== nothing
        @test ex.exactness === :exact
        @test ex.UB > result.UB
        @test ex.gap > 1.0e-6
        @test ex.gap ≈ (ex.UB - result.LB) / max(1, abs(ex.UB))
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
        # IN-04 (iteration 2): the old `welfare_gap == socp_welfare − ac_welfare` check only
        # restated the definition. Pin the measured magnitude instead: |welfare_gap| ≈ 3e-10
        # at z = 0.04 (the AC optimum matches the relaxation's welfare there).
        @test abs(rep.welfare_gap) < 1.0e-6
        # WR-03 (iteration 2): the AC re-check succeeded, so no failure is recorded.
        @test rep.error === nothing
    end
end

@testitem "planning inexact policy: the integer-master corner search honours the policy and only maps genuine infeasibility to +Inf (CR-02 iter 2)" tags =
    [:planning] setup = [IEEE13ShortHorizonFixtures] begin
    using TSODSO
    import JuMP: MOI, termination_status

    # Phase 30 code review iteration 2 (CR-02). `corner_recourse` (the Laporte-Louveaux
    # Q_nu evaluator) used to call the oracle in `:throw` mode whatever the outer policy,
    # and its T>1 branch wrapped it in a bare `catch` that turned EVERY throw into +Inf —
    # so an SOCP-inexact trial silently dropped out of the minimization and Q_nu came out
    # too high (an invalid LL cut). MEASURED 2026-10-01 (scratchpad fix2/probe_cr02b.jl),
    # T=4 IEEE13ShortHorizonFixtures population, follower (corridor_cap=1, x_inv_max=0.1,
    # c_inv=c_op=1e-6):
    #   y_inv=0.05: :throw and :report both 609.009650006013 (the box stays exact);
    #   y_inv=0.06: :throw raises "SOCP relaxation INEXACT" (it used to return a value over
    #               the exact points only); :report = 609.0086589949267;
    #   uniform z=0.06 is inexact-but-feasible, uniform z=0.07 is MOI.INFEASIBLE.
    feeder = TSODSO.ieee13_modified()
    aggs = IEEE13ShortHorizonFixtures.population(feeder)
    λ₀ = IEEE13ShortHorizonFixtures.LAMBDA0
    T = IEEE13ShortHorizonFixtures.T
    oracle = TSODSO.build_planning_oracle(feeder, ConvexBranchFlow(), aggs; λ₀ = λ₀, T = T)
    fol = TSODSO.build_follower(;
        corridor_cap = 1.0,
        x_inv_max = 0.1,
        c_inv = 1.0e-6,
        c_op = fill(1.0e-6, T),
        T = T,
    )

    function caught(f)
        try
            f()
            return nothing
        catch e
            return e
        end
    end

    # Classification: an infeasibility verdict is `nothing`; an inexact verdict is a
    # result under :report and the gate's own throw under :throw.
    @test TSODSO._oracle_or_infeasible(oracle, fill(0.07, T); on_inexact = :report) === nothing
    @test termination_status(oracle.model) in TSODSO.ORACLE_INFEASIBLE_STATUSES
    r06 = TSODSO._oracle_or_infeasible(oracle, fill(0.06, T); on_inexact = :report)
    @test r06 !== nothing && r06.exactness === :inexact
    e06 = caught(() -> TSODSO._oracle_or_infeasible(oracle, fill(0.06, T); on_inexact = :throw))
    @test e06 isa ErrorException && occursin("SOCP relaxation INEXACT", e06.msg)

    # T>1 joint corner search: :throw now fails loud instead of silently skipping the
    # inexact region; :report returns the RELAXATION's per-corner minimum.
    e = caught(() -> TSODSO.corner_recourse(oracle, fol, 0.06, T))
    @test e isa ErrorException && occursin("SOCP relaxation INEXACT", e.msg)
    q05 = TSODSO.corner_recourse(oracle, fol, 0.05, T; on_inexact = :report)
    q06 = TSODSO.corner_recourse(oracle, fol, 0.06, T; on_inexact = :report)
    @test isfinite(q05) && isfinite(q06)
    # A larger box can only lower the minimum (the [0, 0.05]^4 box is inside [0, 0.06]^4).
    @test q06 <= q05 + TSODSO.JOINT_RECOURSE_GAP_TOL
    # The exact box is unaffected by the policy.
    @test TSODSO.corner_recourse(oracle, fol, 0.05, T) ≈ q05 atol = TSODSO.JOINT_RECOURSE_GAP_TOL
end

@testitem "planning inexact policy: incumbent ordering never lets a relaxation-only iterate displace a converged certified one (WR-01 iter 2)" tags =
    [:planning] begin
    using TSODSO

    # Phase 30 code review iteration 2 (WR-01): the ordering rule `_select_incumbent`,
    # tested on its own (a pure function of the two incumbents and the convergence test).
    exact = (; y = 0.0, z = [0.0], UB = 10.0, exactness = :exact)
    relax_inexact = (; y = 0.0, z = [0.1], UB = 9.99995, exactness = :inexact)
    relax_exact = (; y = 0.0, z = [0.2], UB = 9.9, exactness = :exact)
    LB = 9.9999
    conv(UBx) = (UBx - LB) / max(1, abs(UBx)) <= 1.0e-4

    # 1. A certified running-minimum incumbent is returned as-is.
    @test TSODSO._select_incumbent(relax_exact, relax_exact, conv) === relax_exact
    # 2. Relaxation-only running minimum, certified incumbent ALSO converged -> certified.
    @test TSODSO._select_incumbent(relax_inexact, exact, conv) === exact
    # 3. Certified incumbent NOT converged against the same LB -> relaxation-only point
    #    (the caller labels it ub_relaxation_only and reports `exact` alongside).
    strict(UBx) = (UBx - LB) / max(1, abs(UBx)) <= 1.0e-6
    @test TSODSO._select_incumbent(relax_inexact, exact, strict) === relax_inexact
    # 4. No certified iterate at all.
    @test TSODSO._select_incumbent(relax_inexact, nothing, conv) === relax_inexact
end

@testitem "planning inexact policy: the oracle-feasibility-cut v rule degrades gracefully near a curved boundary (WR-06 iter 2)" tags =
    [:planning] begin
    using TSODSO

    # Phase 30 code review iteration 2 (WR-06): `_feas_cut_class` is the measured
    # three-way rule (see FEAS_CUT_V_TOL / FEAS_CUT_V_NOISE: noise <= 2.4e-10 at feasible
    # pins, smallest genuine v measured 3.86e-5). A v between the noise floor and the
    # separation tolerance used to abort the run; it is now a valid, appended "weak" cut.
    @test TSODSO.FEAS_CUT_V_NOISE < TSODSO.FEAS_CUT_V_TOL
    @test TSODSO._feas_cut_class(3.86e-5) === :separating        # smallest measured genuine v
    @test TSODSO._feas_cut_class(2 * TSODSO.FEAS_CUT_V_TOL) === :separating
    @test TSODSO._feas_cut_class(TSODSO.FEAS_CUT_V_TOL) === :weak
    @test TSODSO._feas_cut_class(1.0e-8) === :weak
    @test TSODSO._feas_cut_class(TSODSO.FEAS_CUT_V_NOISE) === :disagree
    @test TSODSO._feas_cut_class(2.4e-10) === :disagree          # measured noise floor
    @test TSODSO._feas_cut_class(0.0) === :disagree
end
