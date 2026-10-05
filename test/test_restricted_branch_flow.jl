# test/test_restricted_branch_flow.jl
#
# Seam: overvoltage-capable relaxation restriction mechanism. Every item name
# contains "restricted_branch_flow" so `occursin("restricted_branch_flow", ti.name)` selects
# the whole file.
#
# The FIRST @testitem below is the analytic spot-check for the CORRECTED
# thesis exactness copy (`v̂`, thesis 3.43/3.45, `ConvexBranchFlow.jl`'s DEFAULT
# `thesis_literal=false`): `v̂ ≥ v` everywhere (the Gan-Low direction), matching Gan-Low's
# UPPER-bound shadow `v ≤ v̂_GL(s)` in kind (though `ConvexBranchFlow`'s `v̂` is a per-branch
# local sign flip, not the tree-wide `v̂_GL(s)` below). Before the exactness copy was corrected, this test
# encoded the OPPOSITE (defective, thesis-literal) relationship `v ≥ v̂`; that
# relationship described the earlier state and is now superseded.
#
# The SECOND @testitem measures the Gan–Low "modification gap" ε (Definition 3, eq. 18) on a
# genuine AC-feasible operating point via the new `recover_lossfree_shadow_voltage` helper
# (src/models/ac_oracle.jl) — a MEASURED, never-searched default for the
# `RestrictedBranchFlow` shrink kwarg.

@testitem "restricted_branch_flow: v̂ ≥ v sign-relationship spot-check on the high-PV fixture" tags =
    [:restricted_branch_flow] setup = [IEEE13Fixtures] begin
    using TSODSO
    using JuMP

    feeder = IEEE13Fixtures.high_pv_feeder()
    aggs = IEEE13Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = IEEE13Fixtures.mem_price_profile()

    # rtol_exact = 1.0: the SAME diagnostic override test_ac_oracle.jl's high-PV fixture item uses, so
    # the inexact SOCP solution is returned for inspection instead of refused by solve_welfare's
    # own internal exactness gate. This is a read of v/v̂, not a claim about exactness.
    ctx, cost, dadp = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = IEEE13Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
        rtol_exact = 1.0,
    )
    pv = ctx.pf_vars
    N = length(feeder.buses)

    mingap =
        minimum(value(pv.v̂[j, t]) - value(pv.v[j, t]) for j in 1:N, t in 1:IEEE13Fixtures.T)
    @info "v̂-v min gap" mingap

    # ConvexBranchFlow's corrected default exactness copy is an
    # UPPER-bound shadow (v̂ ≥ v), the Gan-Low direction — matching the thesis's own stated
    # intent (citing Gan-Low 2015) that v ≤ V²max becomes redundant once v̂ ≤ V²max is
    # imposed. This assertion FLIPPED from the earlier golden (which encoded the opposite,
    # defective `v ≥ v̂` relationship); the corrected direction follows from a
    # telescoping-sum argument. If this assertion ever fails, the
    # cpydrop sign-flip fix (src/powerflow/ConvexBranchFlow.jl) has regressed.
    @test mingap >= -1e-9
end

@testitem "restricted_branch_flow: measured Gan-Low modification gap ε on the high-PV fixture" tags =
    [:restricted_branch_flow] setup = [IEEE13Fixtures] begin
    using TSODSO
    using JuMP

    feeder = IEEE13Fixtures.high_pv_feeder()
    aggs = IEEE13Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = IEEE13Fixtures.mem_price_profile()

    # A genuine AC-feasible operating point (step 1 of the ε-measuring recipe).
    ctx_ac, cost_ac, _ = solve_welfare(
        feeder,
        ACPowerFlow(),
        aggs;
        T = IEEE13Fixtures.T,
        λ₀ = λ₀,
        allow_local = true,
        allow_export = true,
    )

    v̂_GL = TSODSO.recover_lossfree_shadow_voltage(ctx_ac)
    pv_ac = ctx_ac.pf_vars
    N = length(feeder.buses)

    # Lemma 1 sanity check: Gan-Low's v ≤ v̂(s) always holds. With the corrected exactness copy
    # this is the SAME direction as the first @testitem's ConvexBranchFlow v̂ ≥ v (both are
    # upper-bound shadows), but a DIFFERENT, tree-wide (whole-subtree loss-free) magnitude —
    # v̂_GL(s) here is the literal Gan-Low Definition-3 quantity computed post-solve from the
    # AC oracle, strictly tighter than ConvexBranchFlow's per-branch local-sign-flip v̂,
    # confirming the two shadows are genuinely distinct mechanisms despite now sharing a
    # sign.
    @test minimum(
        v̂_GL[j, t] - value(pv_ac.v[j, t]) for j in 1:N, t in 1:IEEE13Fixtures.T
    ) >= -1e-9

    ε_measured =
        maximum(v̂_GL[j, t] - value(pv_ac.v[j, t]) for j in 1:N, t in 1:IEEE13Fixtures.T)
    @info "measured Gan-Low modification gap (before safety multiplier)" ε_measured

    # A nonzero, sensible modification gap. This exact printed value is what the
    # RestrictedBranchFlow default kwarg hardcodes (times a documented safety multiplier, per
    # the "measured, not searched" requirement), with a citation back to this test item.
    @test ε_measured > 0.0
end

@testitem "restricted_branch_flow: RestrictedBranchFlow solves the high-PV fixture through solve_welfare at the exactness gate's DEFAULT tolerance (free validation signal)" tags =
    [:restricted_branch_flow] setup = [IEEE13Fixtures] begin
    using TSODSO
    using JuMP

    feeder = IEEE13Fixtures.high_pv_feeder()
    aggs = IEEE13Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = IEEE13Fixtures.mem_price_profile()

    # Deliberately WITHOUT any rtol_exact override — the DEFAULT 1e-4 is what
    # assert_socp_exact! uses internally. This call must NOT throw — if it does, the
    # restriction did not close the gap and the restriction has failed at the most basic level.
    #
    # ESCALATION NOTE: the SIMPLER OPF-ε special case (shrink v's own
    # bound by a single measured scalar ε) was tried FIRST and empirically found NOT to close
    # this gap at any feasible ε on this fixture (reverse-flow-driven residual, not
    # voltage-pinning-driven). RestrictedBranchFlow now implements the FULLER Gan-Low OPF-m
    # mechanism (direct v̂_GL(s) ≤ v̄ constraint, Theorem 2) by default (ε=0.0), which DOES
    # close the gap here — see the measured socp_maxgap below.
    ctx, cost, dadp = solve_welfare(
        feeder,
        RestrictedBranchFlow(),
        aggs;
        T = IEEE13Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
    )

    # Expected: the residual should collapse from the high-PV fixture's documented
    # ≈10.4 to the benign-feeder scale ~1e-7; 1e-5 is a safe order-of-magnitude gate, not a
    # tight pin. Measured (OPF-m): ≈2.08e-8.
    @info "RestrictedBranchFlow socp_maxgap on the high-PV fixture" ctx.meta[:socp_maxgap]
    @test ctx.meta[:socp_maxgap] < 1e-5

    # Provenance stash.
    @test ctx.meta[:formulation] == :RestrictedBranchFlow
    @test ctx.meta[:restriction_ε] >= 0.0
end

@testitem "restricted_branch_flow: plain ConvexBranchFlow on the high-PV fixture is UNCHANGED by RestrictedBranchFlow's existence (default-path regression)" tags =
    [:restricted_branch_flow] setup = [IEEE13Fixtures] begin
    using TSODSO
    using JuMP
    import Ipopt

    # Deliberate duplication (not a call into test_ac_oracle.jl) so that a future accidental
    # edit to ConvexBranchFlow.jl's bound-setting loop — the one the anti-pattern warning
    # protects — is caught by TWO independent test files, not one.
    feeder = IEEE13Fixtures.high_pv_feeder()
    aggs = IEEE13Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = IEEE13Fixtures.mem_price_profile()

    ctx_socp, cost_socp, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = IEEE13Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
        rtol_exact = 1.0,
    )

    ctx_ac, cost_ac, _ = solve_welfare(
        feeder,
        ACPowerFlow(),
        aggs;
        T = IEEE13Fixtures.T,
        λ₀ = λ₀,
        allow_local = true,
        allow_export = true,
    )
    ctx_ac2, cost_ac2, _ = solve_welfare(
        feeder,
        ACPowerFlow(),
        aggs;
        T = IEEE13Fixtures.T,
        λ₀ = λ₀,
        allow_local = true,
        allow_export = true,
        optimizer = optimizer_with_attributes(
            Ipopt.Optimizer,
            "print_level" => 0,
            "mu_strategy" => "adaptive",
        ),
    )
    @test isapprox(cost_ac, cost_ac2; rtol = 1e-3, atol = 1e-3)

    report = TSODSO.assert_ac_exact!(ctx_socp, ctx_ac; rtol = 1e-4, atol = 1e-6)
    inexact_hours = [row.t for row in report.hours if !row.exact]
    @test !isempty(inexact_hours)

    pv_socp = ctx_socp.pf_vars
    N = length(feeder.buses)
    B = length(feeder.branches)
    diagnosed = any(inexact_hours) do t★
        voltage_bound_hit =
            any(value(pv_socp.v[j, t★]) >= feeder.buses[j].vmax^2 - 1e-3 for j in 1:N)
        reverse_flow = any(value(pv_socp.P[b, t★]) < 0 for b in 1:B)
        voltage_bound_hit || reverse_flow
    end
    @test diagnosed
end

# --- assert_restriction_exact! (headline validity gate) ---
#
# REVISED SEMANTICS: the FIRST implementation of `assert_restriction_exact!`
# defined `ac_feasible` as "the restricted dispatch MATCHES the independently-solved
# AC-optimal dispatch," which forces `optimality_loss ≈ 0` whenever `ac_feasible = true` —
# internally incoherent with the contract "certify AC-feasibility AND report optimality loss in
# ONE call" (the loss clause only has meaning for a feasible-but-suboptimal point).
# `assert_restriction_exact!` NOW certifies PHYSICAL AC-feasibility of the restricted
# solution itself (the SAME per-branch, per-hour cone-tightness residual
# `assert_socp_exact!` gates, with THIS certificate's OWN measured `cone_rtol`/`cone_atol`)
# and DEMOTES the AC-oracle dispatch-match comparison to a separate diagnostic field,
# `matches_ac_optimum`. On the FULL high-PV fixture (`pv_scale = 1.2`): the restricted
# solution's OWN cone is tight (`ac_feasible = true`, reproducing the
# `socp_maxgap = 2.08e-8` measured above), but OPF-m's added `v̂_GL(s) ≤ v̄` constraint (Lemma 1: v ≤
# v̂_GL(s) always, so it is a genuine feasible-set RESTRICTION) ACTIVELY BINDS during
# the fixture's high-PV window (hours 9 through 12 and 14 through 15 — confirmed below via a large nonzero dual on
# `ctx.constraints[:opfm_shadow_voltage]`), so the restricted optimum genuinely diverges from
# the independently-solved AC optimum there — `matches_ac_optimum = false`, with a
# substantial NEGATIVE `optimality_loss`. This is the EXPECTED, PROVABLE consequence of a
# genuine restriction whose bound actively excludes the true AC optimum — NOT a bug. The
# assertions below test this revised, causally-diagnosed behavior.
@testitem "restricted_branch_flow: assert_restriction_exact! certifies PHYSICAL AC-feasibility while reporting the genuine restriction-induced optimality loss + dispatch-mismatch on the binding high-PV window (revised semantics)" tags =
    [:restricted_branch_flow] setup = [IEEE13Fixtures] begin
    using TSODSO
    using JuMP

    feeder = IEEE13Fixtures.high_pv_feeder()
    aggs = IEEE13Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = IEEE13Fixtures.mem_price_profile()

    ctx_restricted, cost_restricted, _ = solve_welfare(
        feeder,
        RestrictedBranchFlow(),
        aggs;
        T = IEEE13Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
    )
    ctx_ac, cost_ac, _ = solve_welfare(
        feeder,
        ACPowerFlow(),
        aggs;
        T = IEEE13Fixtures.T,
        λ₀ = λ₀,
        allow_local = true,
        allow_export = true,
    )
    # The unrestricted (inexact) SOCP diagnostic bound (the "optimality loss vs the
    # unrestricted SOCP bound"), via the SAME rtol_exact = 1.0 override test_ac_oracle.jl's
    # high-PV fixture item uses. UNCHANGED by the synthetic-violation fixture: this leg is the "optimality loss vs
    # the unrestricted SOCP bound" diagnostic, not the synthetic-violation leg below — the
    # DEFAULT ConvexBranchFlow() remains correct here regardless of which voltage band it
    # restricts, since RestrictedBranchFlow's feasible set stays a genuine subset either way.
    ctx_unrestricted, cost_unrestricted, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = IEEE13Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
        rtol_exact = 1.0,
    )

    # Causal diagnosis (mirrors the diagnosed=... pattern above): confirm the restriction
    # GENUINELY binds somewhere on this fixture — a large nonzero dual on
    # :opfm_shadow_voltage, not merely a correlated observation.
    opfm_duals = [abs(dual(c)) for c in ctx_restricted.constraints[:opfm_shadow_voltage]]
    @test maximum(opfm_duals) > 1.0   # genuinely ACTIVE, not numerical noise (~1e-7 off-bind)

    # Default (report = false): must NOT throw — the restricted solution's OWN cone is
    # tight, so it IS certified physically AC-feasible even though it will NOT match the AC
    # optimum (the coherence fix: a feasible-but-suboptimal point can still certify).
    report = assert_restriction_exact!(
        ctx_restricted,
        ctx_ac;
        unrestricted_cost = cost_unrestricted,
    )
    @info "assert_restriction_exact! on the high-PV fixture (revised semantics: physical feasibility + dispatch-mismatch diagnostic)" report.ac_feasible report.matches_ac_optimum report.optimality_loss

    @test report isa NamedTuple
    @test !(report isa Bool)
    # Certification gate: the restricted solution's OWN cone is tight — a genuine AC
    # operating point, independent of whether it is globally optimal.
    @test report.ac_feasible == true
    # Diagnostic: the restricted dispatch does NOT match the true AC optimum during the
    # binding window — the honest finding this certificate now correctly demotes to a
    # separate field rather than using it as the certification gate.
    @test report.matches_ac_optimum == false
    # optimality_loss is a NAMED field, always populated when unrestricted_cost is
    # supplied, and — since RestrictedBranchFlow's feasible set is a genuine SUBSET of the
    # unrestricted SOCP relaxation's — must be <= 0 (restricted welfare can never exceed the
    # unrestricted bound).
    @test report.optimality_loss !== nothing
    @test report.optimality_loss <= 1e-6
    # The provenance marker reflects the PHYSICAL-feasibility verdict (ac_feasible),
    # never the matches_ac_optimum diagnostic.
    @test ctx_restricted.meta[:price_provenance].status == :certified_convex_dual
    @test ctx_restricted.meta[:price_provenance].formulation == :RestrictedBranchFlow
    @test ctx_restricted.meta[:price_provenance].certificate == :assert_restriction_exact!

    # Synthetic violation of the NEW physical-feasibility gate: an UNRESTRICTED
    # ConvexBranchFlow context on this SAME fixture (rtol_exact = 1.0 neutralizes exactness gate so
    # the genuinely cone-INEXACT solution is returned rather than refused) must FAIL
    # ac_feasible — confirming the certificate now actually gates cone-tightness rather than
    # trivially passing any solved context.
    #
    # At the high-PV fixture's own pv_scale = 1.2, BOTH ConvexBranchFlow()'s DEFAULT
    # (Gan-Low direction) AND ConvexBranchFlow(; thesis_literal=true) (the OLD literal copy)
    # are genuinely cone-EXACT on this small 3-bus/2-branch fixture (MEASURED: v's OWN
    # always-imposed V²max bound alone is sufficient to force cone-tightness on a path this
    # short, regardless of which voltage band the exactness-copy v̂ restricts — see
    # ConvexBranchFlow.jl's docstring addendum) — so this fixture's own pv_scale can no longer force the synthetic violation
    # this gate needs. The alternative ("... or a new fixture") is a SEPARATE,
    # higher-pv_scale aggregator set (`aggs_synth`, MEASURED per this project's own discipline
    # to remain solvable while pushing ConvexBranchFlow(; thesis_literal=true) genuinely
    # cone-inexact — ratio ≈ 1982 at pv_scale = 1.4, well past the App. C battery-
    # complementarity throw threshold that fires beyond ≈1.46 on this fixture) feeds ONLY this
    # synthetic-violation leg; `ctx_ac` above (solved at the ORIGINAL pv_scale = 1.2) is reused
    # unchanged as the comparator, since `assert_restriction_exact!`'s `ac_feasible` gate reads
    # ONLY the tested context's own cone residual (never ctx_ac's data), and its ONLY
    # structural requirement against ctx_ac is a matching T (unaffected by pv_scale).
    aggs_synth = IEEE13Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.4)
    ctx_unrestricted_synth, cost_unrestricted_synth, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(; thesis_literal = true),
        aggs_synth;
        T = IEEE13Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
        rtol_exact = 1.0,
    )
    report_unrestricted =
        assert_restriction_exact!(ctx_unrestricted_synth, ctx_ac; report = true)
    @test report_unrestricted.ac_feasible == false
    @test ctx_unrestricted_synth.meta[:price_provenance].status == :cert_failed
    # The provenance formulation is READ from ctx.meta[:formulation] (the
    # marker RestrictedBranchFlow.contribute! stashes), never fabricated by the
    # certificate — a plain ConvexBranchFlow context (which stashes no marker) reports
    # :unknown, not a false :RestrictedBranchFlow.
    @test ctx_unrestricted_synth.meta[:price_provenance].formulation == :unknown
    @test_throws Exception assert_restriction_exact!(ctx_unrestricted_synth, ctx_ac)
end

@testitem "restricted_branch_flow: assert_restriction_exact! throws by default and neutralizes under report=true on a structural T-mismatch" tags =
    [:restricted_branch_flow] setup = [IEEE13Fixtures] begin
    using TSODSO
    using TSODSO: LP
    using JuMP

    feeder2 = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    N2, B2 = 2, 1
    function fixed_ctx(T)
        m = Model(select_optimizer(LP()))
        @variable(m, v[1:N2, 1:T])
        @variable(m, P[1:B2, 1:T])
        @variable(m, Q[1:B2, 1:T])
        @variable(m, l[1:B2, 1:T])
        fix.(v, 1.0; force = true)
        fix.(P, 0.0; force = true)
        fix.(Q, 0.0; force = true)
        fix.(l, 0.0; force = true)
        @objective(m, Max, 0)
        optimize!(m)
        ctx = TSODSO.ModelContext(m)
        ctx.feeder = feeder2
        ctx.T = T
        ctx.pf_vars = (; v, P, Q, l)
        return ctx
    end
    ctx1 = fixed_ctx(1)
    ctx2 = fixed_ctx(2)

    # Default (report = false): throws.
    @test_throws Exception assert_restriction_exact!(ctx1, ctx2)

    # A STALE :certified_convex_dual marker from a prior call on a
    # reused ctx must NOT survive the structural-mismatch throw path (assert_ac_exact!
    # raises BEFORE the final stash runs) — the certificate scrubs the marker as its first
    # action, so after the throw the reused ctx carries no marker at all.
    ctx1.meta[:price_provenance] = (;
        formulation = :RestrictedBranchFlow,
        certificate = :assert_restriction_exact!,
        status = :certified_convex_dual,
    )
    @test_throws Exception assert_restriction_exact!(ctx1, ctx2)
    @test !haskey(ctx1.meta, :price_provenance)

    # report = true on the SAME structural mismatch: assert_ac_exact!'s T-mismatch guard is
    # a HARD structural error (never neutralized by ITS OWN report contract — it has none;
    # T-mismatch is unconditional) — read from src/models/ac_oracle.jl: `T == ctx_ac.T
    # || error(...)` runs BEFORE any report/throw branching this file's own
    # assert_restriction_exact! adds, so the exception propagates through unconditionally.
    # report=true therefore ALSO throws here — it neutralizes AC-INFEASIBILITY findings
    # (this certificate's own ac_feasible check), never STRUCTURAL mismatches upstream.
    @test_throws Exception assert_restriction_exact!(ctx1, ctx2; report = true)
end

# --- ac_dual_fallback_price (nonconvex-AC-dual fallback) ---
#
# NOTE: an obvious design would check
# `assert_restriction_exact!(ctx_restricted, ctx_ac; report = true)` BEFORE calling the
# fallback, to "demonstrate the trigger discipline." On the high-PV fixture (pv_scale =
# 1.2), `RestrictedBranchFlow`'s OWN cone certifies `ac_feasible = true` (the
# revised semantics above) — so reading `ctx_restricted`'s cert here never actually
# FAILS, and "demonstrating trigger discipline" against an always-passing cert alone would
# be vacuous. This item demonstrates BOTH sides genuinely: (a) the PASSING case on
# `ctx_restricted` (the real reason the fallback is NOT needed for the high-PV fixture itself), and (b)
# a GENUINELY FAILING case using an UNRESTRICTED `ConvexBranchFlow` context on the SAME
# fixture (`rtol_exact = 1.0` neutralizes exactness gate so the cone-INEXACT solution is returned
# rather than refused — the SAME synthetic-violation pattern the certificate item above uses),
# where `cert_failing.ac_feasible == false` / `price_provenance.status == :cert_failed` is
# the genuine trigger condition a real caller must gate the fallback on.
# `ac_dual_fallback_price` itself is then called UNCONDITIONALLY because THIS item exercises the fallback's OWN mechanics in isolation.
@testitem "restricted_branch_flow: ac_dual_fallback_price triggers only after an observed certificate failure, carries price_status, and 2-seed agreement (CI subset)" tags =
    [:restricted_branch_flow] setup = [IEEE13Fixtures] begin
    using TSODSO
    using TSODSO: ac_dual_fallback_price
    using JuMP

    feeder = IEEE13Fixtures.high_pv_feeder()
    aggs = IEEE13Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = IEEE13Fixtures.mem_price_profile()

    ctx_restricted, cost_restricted, _ = solve_welfare(
        feeder,
        RestrictedBranchFlow(),
        aggs;
        T = IEEE13Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
    )
    ctx_ac, cost_ac, _ = solve_welfare(
        feeder,
        ACPowerFlow(),
        aggs;
        T = IEEE13Fixtures.T,
        λ₀ = λ₀,
        allow_local = true,
        allow_export = true,
    )

    # (a) The PASSING case (revised semantics): the trigger does NOT actually require
    # the fallback on the high-PV fixture's RestrictedBranchFlow solve itself.
    cert = assert_restriction_exact!(ctx_restricted, ctx_ac; report = true)
    @test cert.ac_feasible == true

    # (b) A GENUINELY FAILING case (mirrors the synthetic violation above):
    # the unrestricted ConvexBranchFlow context, cone-inexact at rtol_exact = 1.0. At this fixture's OWN pv_scale = 1.2, BOTH ConvexBranchFlow() directions
    # (default AND thesis_literal=true) are genuinely cone-EXACT — see the identical,
    # fully-explained rationale comment in the item above. A SEPARATE, higher
    # pv_scale = 1.4 aggregator set (`aggs_synth`, MEASURED to remain solvable while genuinely
    # cone-inexact under thesis_literal=true) feeds ONLY this synthetic-violation leg; `ctx_ac`
    # (solved at the original pv_scale = 1.2) is reused unchanged as the comparator.
    aggs_synth = IEEE13Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.4)
    ctx_unrestricted_synth, cost_unrestricted_synth, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(; thesis_literal = true),
        aggs_synth;
        T = IEEE13Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
        rtol_exact = 1.0,
    )
    cert_failing = assert_restriction_exact!(ctx_unrestricted_synth, ctx_ac; report = true)
    @test cert_failing.ac_feasible == false
    @test ctx_unrestricted_synth.meta[:price_provenance].status == :cert_failed

    # The fallback below is called REGARDLESS of `cert.ac_feasible` here ONLY because
    # this test exercises the fallback's OWN mechanics in isolation — a real caller must gate
    # this call on `cert.ac_feasible == false`, exactly as (b) above documents.
    result = ac_dual_fallback_price(
        feeder,
        aggs;
        T = IEEE13Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
        n_seeds = 2,
    )
    @test result.price_status == :local_ac_dual
    @test result isa NamedTuple
    @test isapprox(
        result.agreement_report.costs[1],
        result.agreement_report.costs[2];
        rtol = 1e-3,
        atol = 1e-3,
    )
    @test all(isfinite, result.dadp)
end

# --- negative ε is rejected loudly (no silent handling) ---
#
# A negative ε applied via set_upper_bound would LOOSEN the voltage bound (a relaxation,
# violating the genuine-restriction contract); the previous `pf.ε > 0` gate in
# contribute! silently treated a sign-typo'd margin as ε = 0. Construction now throws an
# ArgumentError on BOTH the kwarg and positional paths (inner-constructor validation, so
# the non-validating auto-generated constructor no longer exists).
@testitem "restricted_branch_flow: negative ε throws ArgumentError at construction (kwarg AND positional)" tags =
    [:restricted_branch_flow] begin
    using TSODSO

    @test_throws ArgumentError RestrictedBranchFlow(; ε = -0.001)
    @test_throws ArgumentError RestrictedBranchFlow(-0.001)
    @test_throws ArgumentError RestrictedBranchFlow(-1)          # non-Float64 Real too
    # Valid inputs unchanged: default, zero, and a positive measured margin.
    @test RestrictedBranchFlow().ε == 0.0
    @test RestrictedBranchFlow(; ε = 0.0).ε == 0.0
    @test RestrictedBranchFlow(TSODSO._EXACT04_MEASURED_ε).ε == TSODSO._EXACT04_MEASURED_ε
    @test RestrictedBranchFlow(; ε = 1 // 100).ε == 0.01         # Real conversion kept
end

# --- branch-orientation regression (reversed-stored branch is a LEGAL feeder) ---
#
# `assert_radial` (data/topology.jl) validates only tree-ness/connectivity, never orientation:
# a `Branch(from, to, …)` stored child→parent is a fully legal `Feeder` everywhere else in the
# framework (`ConvexBranchFlow`'s DistFlow drop/cone/balances are written in the branch's own
# direction). Both copies of the Gan-Low shadow recursion — the
# post-processing `recover_lossfree_shadow_voltage` (src/models/ac_oracle.jl) and the
# model-build OPF-m constraint loop (`RestrictedBranchFlow.contribute!`) — silently assumed
# `br.from` is the tree parent: reversed orientation read an UNINITIALIZED parent voltage
# (post-processing) or crashed with a cryptic `KeyError` (model build), and used the branch's
# own-direction `P`/`Q` without the reversed-branch correction.
#
# This item re-encodes ONE physical operating point two ways — `fwd` stores both branches
# parent→child; `rev` stores branch 2 REVERSED — and asserts both code paths produce
# IDENTICAL results (float-roundoff scale, NOT solver scale: the comparison is pure algebra
# over fixed numbers, so 1e-12 is the honest gate). The reversed re-encoding of the same
# physical point is: ℓ_rev = ℓ (squared current magnitude is direction-independent),
# P_rev = −(P_fwd − r·ℓ), Q_rev = −(Q_fwd − x·ℓ) — the branch's own sending end at the child
# is the negated RECEIVING end of the parent→child encoding (this project charges the loss
# r·ℓ at the branch's own `to` end, as ConvexBranchFlow does). This algebra also
# discriminates the CORRECT reversed-branch flow (`r·ℓ − P_rev` at the parent side) from the
# tempting bare sign flip `−P_rev`, which would be off by the feeding branch's own loss.
@testitem "restricted_branch_flow: regression — reversed-orientation branch agrees exactly with parent→child in BOTH shadow-voltage code paths" tags =
    [:restricted_branch_flow] begin
    using TSODSO
    using TSODSO: LP
    using JuMP

    r, x = 0.05, 0.04
    buses = [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false), Bus(3, 0.95, 1.05, false)]
    feeder_fwd = Feeder(buses, [Branch(1, 2, r, x, 99.0), Branch(2, 3, r, x, 99.0)], 1)
    # Branch 2 stored REVERSED (child 3 → parent 2): legal per assert_radial.
    feeder_rev = Feeder(buses, [Branch(1, 2, r, x, 99.0), Branch(3, 2, r, x, 99.0)], 1)

    T = 2
    # Branch × hour, parent→child encoding. Hour 2 carries reverse (negative) flow and both
    # hours carry nonzero ℓ, so the reversed-branch r·ℓ correction term is genuinely
    # exercised (a bare −P sign flip would fail the 1e-12 gates below).
    P_fwd = [0.8 -0.5; 0.4 -0.3]
    Q_fwd = [0.2 -0.1; 0.1 -0.05]
    l_fwd = [0.02 0.01; 0.015 0.008]
    v_fixed = [1.0 1.0; 0.99 1.01; 0.98 1.02]

    # The SAME physical point in the reversed encoding (branch 2 only).
    P_rev = copy(P_fwd)
    Q_rev = copy(Q_fwd)
    l_rev = copy(l_fwd)
    P_rev[2, :] .= -(P_fwd[2, :] .- r .* l_fwd[2, :])
    Q_rev[2, :] .= -(Q_fwd[2, :] .- x .* l_fwd[2, :])

    # --- Path 1: recover_lossfree_shadow_voltage (post-processing over a solved point) ---
    function fixed_ctx(feeder, P, Q, l, v)
        m = Model(select_optimizer(LP()))
        @variable(m, vv[1:3, 1:T])
        @variable(m, PP[1:2, 1:T])
        @variable(m, QQ[1:2, 1:T])
        @variable(m, ll[1:2, 1:T])
        fix.(vv, v; force = true)
        fix.(PP, P; force = true)
        fix.(QQ, Q; force = true)
        fix.(ll, l; force = true)
        @objective(m, Max, 0)
        optimize!(m)
        ctx = TSODSO.ModelContext(m)
        ctx.feeder = feeder
        ctx.T = T
        ctx.pf_vars = (; v = vv, P = PP, Q = QQ, l = ll)
        return ctx
    end

    v̂_fwd = TSODSO.recover_lossfree_shadow_voltage(
        fixed_ctx(feeder_fwd, P_fwd, Q_fwd, l_fwd, v_fixed),
    )
    # Pre-fix this read an UNINITIALIZED Matrix{Float64}(undef) entry (silent garbage).
    v̂_rev = TSODSO.recover_lossfree_shadow_voltage(
        fixed_ctx(feeder_rev, P_rev, Q_rev, l_rev, v_fixed),
    )
    @test maximum(abs.(v̂_fwd .- v̂_rev)) < 1e-12

    # --- Path 2: RestrictedBranchFlow.contribute!'s OPF-m constraint builder ---
    # Pre-fix, building on feeder_rev crashed with a KeyError (Dict lookup of the
    # not-yet-computed child voltage). Post-fix it must build, and the OPF-m constraint
    # functions — evaluated at the two encodings of the SAME physical point — must agree
    # exactly.
    function opfm_margins(feeder, P, Q, l, v)
        ctx = TSODSO.ModelContext(Model())
        TSODSO.contribute!(RestrictedBranchFlow(), ctx, feeder; T = T)
        pv = ctx.pf_vars
        val = Dict{VariableRef, Float64}()
        for j in 1:3, t in 1:T
            val[pv.v[j, t]] = v[j, t]
        end
        for b in 1:2, t in 1:T
            val[pv.P[b, t]] = P[b, t]
            val[pv.Q[b, t]] = Q[b, t]
            val[pv.l[b, t]] = l[b, t]
        end
        # Signed constraint margin v̂_GL(s)[i,t] − v̄ᵢ² at the fixed point; both encodings
        # push constraints in the same (t-outer, BFS-inner) order, so elementwise
        # comparison is aligned.
        return [
            value(xx -> val[xx], constraint_object(c).func) -
            constraint_object(c).set.upper for c in ctx.constraints[:opfm_shadow_voltage]
        ]
    end

    margins_fwd = opfm_margins(feeder_fwd, P_fwd, Q_fwd, l_fwd, v_fixed)
    margins_rev = opfm_margins(feeder_rev, P_rev, Q_rev, l_rev, v_fixed)
    @test length(margins_rev) == 2 * T   # one OPF-m row per non-root bus per hour
    @test maximum(abs.(margins_fwd .- margins_rev)) < 1e-12

    # Cross-path consistency: the model-build margin at the fixed point must equal the
    # post-processing shadow voltage minus the bound — same math, different phase of use.
    # (enumerate over the push order, t-outer/BFS-inner, rather than mutating a top-level
    # counter: a `idx += 1` at @testitem top level is a soft-scope global and errors under
    # TestItemRunner's include_string evaluation.)
    for (idx, (t, i)) in enumerate((t, i) for t in 1:T for i in 2:3)
        @test abs(margins_fwd[idx] - (v̂_fwd[i, t] - buses[i].vmax^2)) < 1e-12
    end
end
