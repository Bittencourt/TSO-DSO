# Seam: models/ac_oracle.jl (EXACT-01 angle recovery now; EXACT-02/03 assert_ac_exact! lands
# in plan 15-02 — RED-guarded here). Every item name contains "ac_oracle" so
# `occursin("ac_oracle", ti.name)` selects it.
#
# The 2-bus angle-recovery item is the BLOCKING analytic validation gate flagged in STATE.md:
# `recover_voltage_angles` is the one genuinely-new piece of math this phase adds, so it must
# match a hand-derived closed-form complex phasor on the trivial 2-bus fixture BEFORE any later
# plan trusts it on IEEE-13/123. While RED (plan 15-01 Task 3 not yet landed) the behavioral
# asserts sit behind an `isdefined` guard so they go live automatically; the assert_ac_exact!
# RED-guard is intentionally red until plan 15-02.

@testitem "ac_oracle: recover_voltage_angles matches the hand-derived 2-bus closed-form phasor (EXACT-01, angle-recovery validation gate)" tags = [:ac_oracle] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # RED until plan 15-01 Task 3 defines the phasor recursion.
    @test isdefined(TSODSO, :recover_voltage_angles)

    if isdefined(TSODSO, :recover_voltage_angles)
        # The trivial 2-bus radial fixture (r = 0.01, x = 0.02).
        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        T, N, B = 1, 2, 1

        # A hand-chosen fixed operating point on the equality cone (Baran–Wu, thesis 3.33):
        #   P[1,1] = 0.1, Q[1,1] = 0.05, l[1,1] = (P²+Q²)/v[1,1] = 0.0125, v[1,1] = 1.0 (root).
        #   v[2,1] = v[1,1] − 2(rP+xQ) + (r²+x²)·l
        #          = 1.0 − 0.004 + 0.00000625 = 0.99600625.
        # Closed-form phasor: V₁ = 1.0 + 0.0im; I₁₂ = conj(P+jQ)/conj(V₁) = 0.1 − 0.05im;
        #   V₂ = V₁ − (r+jx)·I₁₂ = 0.998 − 0.0015im. abs2(V₂) = 0.998² + 0.0015² = 0.99600625
        #   (self-consistent with v[2,1]). angle(V₂) ≈ −0.0015003 rad, matching the small-angle
        #   identity θ₂ ≈ −(x·P − r·Q) = −(0.02·0.1 − 0.01·0.05) = −0.0015.
        # An attached optimizer is required for `value(...)` to resolve the fixed variables
        # (mirrors test_exactness.jl's fixed-value construction). Everything is fixed and the
        # objective is 0, so a trivial LP solve suffices — recover_voltage_angles is pure
        # post-processing over the resulting values, no cone involved.
        model = Model(select_optimizer(LP()))
        @variable(model, v[1:N, 1:T])
        @variable(model, P[1:B, 1:T])
        @variable(model, Q[1:B, 1:T])
        @variable(model, l[1:B, 1:T])
        fix(v[1, 1], 1.0; force = true)
        fix(v[2, 1], 0.99600625; force = true)
        fix(P[1, 1], 0.1; force = true)
        fix(Q[1, 1], 0.05; force = true)
        fix(l[1, 1], 0.0125; force = true)
        @objective(model, Max, 0)
        optimize!(model)

        ctx = TSODSO.ModelContext(model)
        ctx.meta[:feeder] = feeder
        ctx.meta[:T] = T
        ctx.meta[:pf_vars] = (; v, P, Q, l)

        Vphasor = TSODSO.recover_voltage_angles(ctx)

        @test Vphasor isa Matrix{ComplexF64}
        @test size(Vphasor) == (N, T)
        @test isapprox(Vphasor[1, 1], 1.0 + 0.0im; atol = 1e-9)            # root reference
        @test isapprox(Vphasor[2, 1], 0.998 - 0.0015im; atol = 1e-6)       # closed-form phasor
        @test isapprox(abs2(Vphasor[2, 1]), 0.99600625; atol = 1e-8)       # magnitude ≡ v[2,1]
        @test isapprox(angle(Vphasor[2, 1]), -0.0015003; atol = 1e-4)      # small-angle identity
    end
end

@testitem "ac_oracle: assert_ac_exact! is defined (RED-guard for plan 15-02)" tags = [:ac_oracle] begin
    using TSODSO

    # GREEN once plan 15-02 defines assert_ac_exact! alongside recover_voltage_angles in this
    # same file.
    @test isdefined(TSODSO, :assert_ac_exact!)
end

@testitem "ac_oracle: assert_ac_exact! reports all-exact on a KNOWN-exact 2-bus solve, never throws, never resolves to a Bool (EXACT-02/EXACT-03)" tags = [:ac_oracle] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    @test isdefined(TSODSO, :assert_ac_exact!)
    @test isdefined(TSODSO, :ACPowerFlow)

    if isdefined(TSODSO, :assert_ac_exact!) && isdefined(TSODSO, :ACPowerFlow)
        # The 2-bus + single-Deferrable-aggregator fixture (docs/literate/convex_branch_flow.jl).
        buses = [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)]
        branches = [Branch(1, 2, 0.01, 0.02, 10.0)]
        feeder = Feeder(buses, branches, 1)
        device = Deferrable(2, 1, 1, 0.5, 1.0, 1.0)
        agg = Aggregator(2, 0.95, [device], [0.2])

        # BOTH contexts from the SAME feeder/agg/λ₀/T/allow_export local variables (Pitfall 3
        # guard: identical problem data, each independently re-optimized).
        ctx_socp, cost_socp, _ =
            solve_welfare(feeder, ConvexBranchFlow(), [agg]; T = 1, λ₀ = [1.0], allow_export = true)
        ctx_ac, cost_ac, _ = solve_welfare(
            feeder, ACPowerFlow(), [agg]; T = 1, λ₀ = [1.0], allow_local = true, allow_export = true,
        )

        report = TSODSO.assert_ac_exact!(ctx_socp, ctx_ac; rtol = 1e-4, atol = 1e-6)

        # The report is a per-hour NamedTuple, NEVER a bare Bool (EXACT-03 — a gap must surface
        # as an inspectable finding, not collapse to pass/fail).
        @test report isa NamedTuple
        @test report.hours isa Vector
        @test !(report isa Bool)
        @test !(report.hours isa Bool)
        @test length(report.hours) == 1
        # A genuinely exact 2-bus case: every hour exact, both solvers on essentially the same
        # optimum. assert_ac_exact! did NOT throw to reach this line.
        @test all(row.exact for row in report.hours)
        @test isapprox(report.obj_gap, 0.0; atol = 1e-3)
    end
end

@testitem "ac_oracle: assert_ac_exact! throws ONLY on a structural T mismatch, never on a numeric gap (EXACT-03 divergence from assert_socp_exact!)" tags = [:ac_oracle] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    @test isdefined(TSODSO, :assert_ac_exact!)

    if isdefined(TSODSO, :assert_ac_exact!)
        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        N, B = 2, 1

        # Two minimal fixed-value contexts on the 2-bus fixture (mirrors test_exactness.jl's
        # fixed-value construction) differing ONLY in horizon T — one T=1, one T=2. This is a
        # STRUCTURAL mismatch: the two solves are not the same operating point, the one case
        # assert_ac_exact! is allowed to refuse.
        function fixed_ctx(T)
            m = Model(select_optimizer(LP()))
            @variable(m, v[1:N, 1:T])
            @variable(m, P[1:B, 1:T])
            @variable(m, Q[1:B, 1:T])
            @variable(m, l[1:B, 1:T])
            fix.(v, 1.0; force = true)
            fix.(P, 0.0; force = true)
            fix.(Q, 0.0; force = true)
            fix.(l, 0.0; force = true)
            @objective(m, Max, 0)
            optimize!(m)
            ctx = TSODSO.ModelContext(m)
            ctx.meta[:feeder] = feeder
            ctx.meta[:T] = T
            ctx.meta[:pf_vars] = (; v, P, Q, l)
            return ctx
        end
        ctx1 = fixed_ctx(1)
        ctx2 = fixed_ctx(2)

        @test_throws Exception TSODSO.assert_ac_exact!(ctx1, ctx2; rtol = 1e-4)
        # Any test asserting a throw on a HIGH-PV/inexact fixture (as opposed to this
        # structural-mismatch fixture) is a signal the design has drifted toward the wrong shape —
        # see plan 15-03's stress test, which is a POSITIVE (non-throwing) assertion.
    end
end

@testitem "ac_oracle: high-PV stress fixture surfaces the genuine SOCP/AC exactness finding at the exactness boundary (EXACT-04)" tags = [:ac_oracle] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP
    import Ipopt

    @test isdefined(TSODSO, :assert_ac_exact!)
    @test isdefined(TSODSO, :ACPowerFlow)

    if isdefined(TSODSO, :assert_ac_exact!) && isdefined(TSODSO, :ACPowerFlow)
        feeder = Phase4Fixtures.high_pv_feeder()
        # pv_scale = 1.2 is the EMPIRICALLY-FOUND value (RESEARCH Open Question 1's 1.0–2.0 range)
        # that pins bus voltage at V²max and drives the SOC relaxation genuinely INEXACT while the
        # true nonconvex AC-OPF stays feasible — see the ## Finding below. It is hard-coded (no
        # search loop) so the committed test is deterministic and reproducible.
        aggs = Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
        λ₀ = Phase4Fixtures.mem_price_profile()

        # SOCP solve with rtol_exact = 1.0: a DELIBERATE, documented diagnostic override of
        # solve_welfare's OWN internal PF-04 gate (assert_socp_exact!), so the loose-relaxation
        # solution is RETURNED for comparison instead of refused. It changes ZERO code in
        # welfare_solve.jl. The milestone's ACTUAL exactness verdict comes from assert_ac_exact!'s
        # own standard rtol = 1e-4 below, NEVER from this loosened internal gate.
        ctx_socp, cost_socp, _ = solve_welfare(
            feeder, ConvexBranchFlow(), aggs;
            T = Phase4Fixtures.T, λ₀ = λ₀, allow_export = true, rtol_exact = 1.0,
        )

        # True nonconvex AC-OPF, default Ipopt attributes (select_optimizer(NLP())).
        ctx_ac, cost_ac, _ = solve_welfare(
            feeder, ACPowerFlow(), aggs;
            T = Phase4Fixtures.T, λ₀ = λ₀, allow_local = true, allow_export = true,
        )
        # SECOND AC start with a different Ipopt interior-point strategy — genuine
        # solver-trajectory diversity WITHOUT touching solve_welfare's signature (the local-optimum
        # guard, Pitfall 2).
        ctx_ac2, cost_ac2, _ = solve_welfare(
            feeder, ACPowerFlow(), aggs;
            T = Phase4Fixtures.T, λ₀ = λ₀, allow_local = true, allow_export = true,
            optimizer = optimizer_with_attributes(
                Ipopt.Optimizer, "print_level" => 0, "mu_strategy" => "adaptive",
            ),
        )
        # Local-optimum guard (Pitfall 2): if this ever fails on a future solver upgrade it flags a
        # LOCAL-OPTIMUM finding distinct from an exactness finding, and must NOT be conflated with
        # the assert_ac_exact! comparison below.
        @test isapprox(cost_ac, cost_ac2; rtol = 1e-3, atol = 1e-3)

        report = TSODSO.assert_ac_exact!(ctx_socp, ctx_ac; rtol = 1e-4, atol = 1e-6)

        # The POSITIVE, EXPECTED finding: at the exactness boundary the SOCP relaxation genuinely
        # disagrees with the true AC-OPF at one or more hours. This is a per-hour REPORT, never a
        # thrown error — a genuine relaxation gap is the milestone's finding, not a defect.
        inexact_hours = [row.t for row in report.hours if !row.exact]
        @test !isempty(inexact_hours)

        # Diagnose the disagreement (Pitfall 4): it must be INVESTIGATED, not merely asserted
        # non-empty. For AT LEAST ONE inexact hour, either a bus voltage is pinned at/near V²max OR
        # a branch carries reverse (PV back-feed) flow — the voltage-binding / reverse-flow regime
        # where SOC exactness is documented to fail (Farivar & Low 2013; Gan, Li, Topcu & Low 2015).
        # The EARLIEST inexact hour can instead be an inter-hour-coupling artifact (the battery /
        # deferrable dispatch shifts in response to the peak-hour inexactness), so the diagnostic
        # scans the whole inexact window rather than only its first hour.
        pv_socp = ctx_socp.meta[:pf_vars]
        N = length(feeder.buses)
        B = length(feeder.branches)
        diagnosed = any(inexact_hours) do t★
            voltage_bound_hit =
                any(value(pv_socp.v[j, t★]) >= feeder.buses[j].vmax^2 - 1e-3 for j in 1:N)
            reverse_flow = any(value(pv_socp.P[b, t★]) < 0 for b in 1:B)
            voltage_bound_hit || reverse_flow
        end
        @test diagnosed
    # DOCUMENTED FINDING (EXACT-04): at pv_scale = 1.2 the SOC relaxation goes genuinely INEXACT
    # over the high-PV afternoon window (hours 6–15), with bus voltage pinned at V²max = 1.1025
    # and reverse (PV back-feed) branch flow — the documented SOC exactness-failure regime. The
    # two independent AC starts agree (no local-optimum artifact), so the gap is a relaxation
    # property, not solver noise. Narrated in docs/literate/ac_oracle.jl.
    end
end
