# test/test_restricted_branch_flow.jl
#
# Seam: overvoltage-capable relaxation restriction mechanism (OVR-01..04). Every item name
# contains "restricted_branch_flow" so `occursin("restricted_branch_flow", ti.name)` selects
# the whole file.
#
# The FIRST @testitem below is the BLOCKING analytic spot-check RESEARCH.md requires BEFORE any
# `RestrictedBranchFlow` code exists: it numerically confirms (or falsifies) RESEARCH.md
# Assumption A1 — that the EXISTING thesis exactness copy (`v̂`, thesis 3.43/3.45, already coded
# in `ConvexBranchFlow.jl`) is a LOWER-bound shadow on the true voltage (`v ≥ v̂` everywhere),
# the OPPOSITE sign relationship from Gan–Low's UPPER-bound shadow `v ≤ v̂_GL(s)`. If this
# assertion ever fails, STOP: the derivation in 20-RESEARCH.md has an error and every downstream
# plan (20-02..05) needs re-deriving before proceeding.
#
# The SECOND @testitem measures the Gan–Low "modification gap" ε (Definition 3, eq. 18) on a
# genuine AC-feasible operating point via the new `recover_lossfree_shadow_voltage` helper
# (src/models/ac_oracle.jl) — a MEASURED, never-searched default for plan 20-02's
# `RestrictedBranchFlow` shrink kwarg (D-03/D-04).

@testitem "restricted_branch_flow: v ≥ v̂ sign-relationship spot-check on the EXACT-04 fixture (RESEARCH Assumption A1)" tags =
    [:restricted_branch_flow] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = Phase4Fixtures.high_pv_feeder()
    aggs = Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = Phase4Fixtures.mem_price_profile()

    # rtol_exact = 1.0: the SAME diagnostic override test_ac_oracle.jl's EXACT-04 item uses, so
    # the inexact SOCP solution is returned for inspection instead of refused by solve_welfare's
    # own internal PF-04 gate. This is a read of v/v̂, not a claim about exactness.
    ctx, cost, dadp = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
        rtol_exact = 1.0,
    )
    pv = ctx.meta[:pf_vars]
    N = length(feeder.buses)

    mingap = minimum(
        value(pv.v[j, t]) - value(pv.v̂[j, t]) for j in 1:N, t in 1:Phase4Fixtures.T
    )
    @info "v-v̂ min gap" mingap

    # RESEARCH.md Assumption A1: the existing thesis exactness copy is a LOWER-bound shadow
    # (v ≥ v̂), opposite Gan-Low's UPPER-bound shadow — this is the reason Phase 20 needs a
    # genuinely new mechanism, not an adjustment of the existing v̂ bound. If this assertion ever
    # fails, STOP: the derivation in 20-RESEARCH.md has an error and every downstream plan
    # (20-02..05) needs re-deriving before proceeding.
    @test mingap >= -1e-9
end

@testitem "restricted_branch_flow: measured Gan-Low modification gap ε on the EXACT-04 fixture (D-03)" tags =
    [:restricted_branch_flow] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = Phase4Fixtures.high_pv_feeder()
    aggs = Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = Phase4Fixtures.mem_price_profile()

    # A genuine AC-feasible operating point (RESEARCH.md "Measuring ε" recipe step 1).
    ctx_ac, cost_ac, _ = solve_welfare(
        feeder,
        ACPowerFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_local = true,
        allow_export = true,
    )

    v̂_GL = TSODSO.recover_lossfree_shadow_voltage(ctx_ac)
    pv_ac = ctx_ac.meta[:pf_vars]
    N = length(feeder.buses)

    # Lemma 1 sanity check: Gan-Low's v ≤ v̂(s) always holds — the OPPOSITE sign from the first
    # @testitem's v ≥ v̂, confirming the two shadows are genuinely distinct mechanisms.
    @test minimum(
        v̂_GL[j, t] - value(pv_ac.v[j, t]) for j in 1:N, t in 1:Phase4Fixtures.T
    ) >= -1e-9

    ε_measured = maximum(
        v̂_GL[j, t] - value(pv_ac.v[j, t]) for j in 1:N, t in 1:Phase4Fixtures.T
    )
    @info "measured Gan-Low modification gap (before safety multiplier)" ε_measured

    # A nonzero, sensible modification gap. This exact printed value is what plan 20-02's
    # RestrictedBranchFlow default kwarg will hardcode (times a documented safety multiplier per
    # D-03's "measured, not searched" requirement), with a citation back to this test item.
    @test ε_measured > 0.0
end

@testitem "restricted_branch_flow: RestrictedBranchFlow solves EXACT-04 through solve_welfare at PF-04's DEFAULT tolerance (OVR-01, free validation signal)" tags =
    [:restricted_branch_flow] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = Phase4Fixtures.high_pv_feeder()
    aggs = Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = Phase4Fixtures.mem_price_profile()

    # Deliberately WITHOUT any rtol_exact override — the DEFAULT 1e-4 is what
    # assert_socp_exact! uses internally. This call must NOT throw — if it does, the
    # restriction did not close the gap and the plan has failed at the most basic level.
    #
    # ESCALATION NOTE (see 20-02-SUMMARY.md): the SIMPLER OPF-ε special case (shrink v's own
    # bound by a single measured scalar ε) was tried FIRST and empirically found NOT to close
    # this gap at any feasible ε on this fixture (reverse-flow-driven residual, not
    # voltage-pinning-driven). RestrictedBranchFlow now implements the FULLER Gan-Low OPF-m
    # mechanism (direct v̂_GL(s) ≤ v̄ constraint, Theorem 2) by default (ε=0.0), which DOES
    # close the gap here — see the measured socp_maxgap below.
    ctx, cost, dadp = solve_welfare(
        feeder,
        RestrictedBranchFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
    )

    # RESEARCH.md's prediction: the residual should collapse from EXACT-04's documented
    # ≈10.4 to the benign-feeder scale ~1e-7; 1e-5 is a safe order-of-magnitude gate, not a
    # tight pin. Measured (OPF-m): ≈2.08e-8.
    @info "RestrictedBranchFlow socp_maxgap on EXACT-04" ctx.meta[:socp_maxgap]
    @test ctx.meta[:socp_maxgap] < 1e-5

    # D-08 provenance stash from Task 1.
    @test ctx.meta[:formulation] == :RestrictedBranchFlow
    @test ctx.meta[:restriction_ε] >= 0.0
end

@testitem "restricted_branch_flow: plain ConvexBranchFlow on EXACT-04 is UNCHANGED by RestrictedBranchFlow's existence (default-path regression)" tags =
    [:restricted_branch_flow] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP
    import Ipopt

    # Deliberate duplication (not a call into test_ac_oracle.jl) so that a future accidental
    # edit to ConvexBranchFlow.jl's bound-setting loop — the one Task 1's anti-pattern warning
    # protects — is caught by TWO independent test files, not one.
    feeder = Phase4Fixtures.high_pv_feeder()
    aggs = Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = Phase4Fixtures.mem_price_profile()

    ctx_socp, cost_socp, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
        rtol_exact = 1.0,
    )

    ctx_ac, cost_ac, _ = solve_welfare(
        feeder,
        ACPowerFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_local = true,
        allow_export = true,
    )
    ctx_ac2, cost_ac2, _ = solve_welfare(
        feeder,
        ACPowerFlow(),
        aggs;
        T = Phase4Fixtures.T,
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
end

# --- Plan 20-03: assert_restriction_exact! (OVR-02 headline validity gate) ---
#
# ORCHESTRATOR-REVISED SEMANTICS (documented in 20-03-SUMMARY.md's "## Addendum
# (orchestrator revision)" section): the FIRST implementation of `assert_restriction_exact!`
# defined `ac_feasible` as "the restricted dispatch MATCHES the independently-solved
# AC-optimal dispatch," which forces `optimality_loss ≈ 0` whenever `ac_feasible = true` —
# internally incoherent with D-05's "certify AC-feasibility AND report optimality loss in
# ONE call" (the loss clause only has meaning for a feasible-but-suboptimal point).
# `assert_restriction_exact!` NOW certifies PHYSICAL AC-feasibility of the restricted
# solution itself (the SAME per-branch, per-hour cone-tightness residual
# `assert_socp_exact!` gates, with THIS certificate's OWN measured `cone_rtol`/`cone_atol`)
# and DEMOTES the AC-oracle dispatch-match comparison to a separate diagnostic field,
# `matches_ac_optimum`. On the FULL EXACT-04 fixture (`pv_scale = 1.2`): the restricted
# solution's OWN cone is tight (`ac_feasible = true`, reproducing plan 20-02's
# `socp_maxgap = 2.08e-8`), but OPF-m's added `v̂_GL(s) ≤ v̄` constraint (Lemma 1: v ≤
# v̂_GL(s) always, so it is a genuine feasible-set RESTRICTION, D-01) ACTIVELY BINDS during
# EXACT-04's high-PV window (hours 9-12, 14-15 — confirmed below via a large nonzero dual on
# `ctx.constraints[:opfm_shadow_voltage]`), so the restricted optimum genuinely diverges from
# the independently-solved AC optimum there — `matches_ac_optimum = false`, with a
# substantial NEGATIVE `optimality_loss`. This is the EXPECTED, PROVABLE consequence of a
# genuine restriction whose bound actively excludes the true AC optimum — NOT a bug. The
# assertions below test this revised, causally-diagnosed behavior.
@testitem "restricted_branch_flow: assert_restriction_exact! certifies PHYSICAL AC-feasibility while reporting the genuine restriction-induced optimality loss + dispatch-mismatch on the binding EXACT-04 window (D-05, revised semantics)" tags =
    [:restricted_branch_flow] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = Phase4Fixtures.high_pv_feeder()
    aggs = Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = Phase4Fixtures.mem_price_profile()

    ctx_restricted, cost_restricted, _ = solve_welfare(
        feeder,
        RestrictedBranchFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
    )
    ctx_ac, cost_ac, _ = solve_welfare(
        feeder,
        ACPowerFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_local = true,
        allow_export = true,
    )
    # The unrestricted (inexact) SOCP diagnostic bound (D-05's "optimality loss vs the
    # unrestricted SOCP bound"), via the SAME rtol_exact = 1.0 override test_ac_oracle.jl's
    # EXACT-04 item uses.
    ctx_unrestricted, cost_unrestricted, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Phase4Fixtures.T,
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
    # optimum (D-05's coherence fix: a feasible-but-suboptimal point can still certify).
    report = assert_restriction_exact!(
        ctx_restricted,
        ctx_ac;
        unrestricted_cost = cost_unrestricted,
    )
    @info "assert_restriction_exact! on EXACT-04 (revised semantics: physical feasibility + dispatch-mismatch diagnostic)" report.ac_feasible report.matches_ac_optimum report.optimality_loss

    @test report isa NamedTuple
    @test !(report isa Bool)
    # Certification gate: the restricted solution's OWN cone is tight — a genuine AC
    # operating point, independent of whether it is globally optimal.
    @test report.ac_feasible == true
    # Diagnostic: the restricted dispatch does NOT match the true AC optimum during the
    # binding window — the honest finding this certificate now correctly demotes to a
    # separate field rather than using it as the certification gate.
    @test report.matches_ac_optimum == false
    # D-05: optimality_loss is a NAMED field, always populated when unrestricted_cost is
    # supplied, and — since RestrictedBranchFlow's feasible set is a genuine SUBSET of the
    # unrestricted SOCP relaxation's — must be <= 0 (restricted welfare can never exceed the
    # unrestricted bound).
    @test report.optimality_loss !== nothing
    @test report.optimality_loss <= 1e-6
    # T-20-08: the provenance marker reflects the PHYSICAL-feasibility verdict (ac_feasible),
    # never the matches_ac_optimum diagnostic.
    @test ctx_restricted.meta[:price_provenance].status == :certified_convex_dual
    @test ctx_restricted.meta[:price_provenance].formulation == :RestrictedBranchFlow
    @test ctx_restricted.meta[:price_provenance].certificate == :assert_restriction_exact!

    # Synthetic violation of the NEW physical-feasibility gate: an UNRESTRICTED
    # ConvexBranchFlow context on this SAME fixture (rtol_exact = 1.0 neutralizes PF-04 so
    # the genuinely cone-INEXACT solution is returned rather than refused) must FAIL
    # ac_feasible — confirming the certificate now actually gates cone-tightness rather than
    # trivially passing any solved context.
    report_unrestricted = assert_restriction_exact!(ctx_unrestricted, ctx_ac; report = true)
    @test report_unrestricted.ac_feasible == false
    @test ctx_unrestricted.meta[:price_provenance].status == :cert_failed
    # Review WR-01: the provenance formulation is READ from ctx.meta[:formulation] (the
    # D-08 marker RestrictedBranchFlow.contribute! stashes), never fabricated by the
    # certificate — a plain ConvexBranchFlow context (which stashes no marker) reports
    # :unknown, not a false :RestrictedBranchFlow.
    @test ctx_unrestricted.meta[:price_provenance].formulation == :unknown
    @test_throws Exception assert_restriction_exact!(ctx_unrestricted, ctx_ac)
end

@testitem "restricted_branch_flow: assert_restriction_exact! throws by default and neutralizes under report=true on a structural T-mismatch (D-06)" tags =
    [:restricted_branch_flow] setup = [Phase4Fixtures] begin
    using TSODSO
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
        ctx.meta[:feeder] = feeder2
        ctx.meta[:T] = T
        ctx.meta[:pf_vars] = (; v, P, Q, l)
        return ctx
    end
    ctx1 = fixed_ctx(1)
    ctx2 = fixed_ctx(2)

    # Default (report = false): throws, per D-06.
    @test_throws Exception assert_restriction_exact!(ctx1, ctx2)

    # Review WR-02 / T-20-08: a STALE :certified_convex_dual marker from a prior call on a
    # reused ctx must NOT survive the structural-mismatch throw path (assert_ac_exact!
    # raises BEFORE the final stash runs) — the certificate scrubs the marker as its first
    # action, so after the throw the reused ctx carries no marker at all.
    ctx1.meta[:price_provenance] =
        (; formulation = :RestrictedBranchFlow,
            certificate = :assert_restriction_exact!,
            status = :certified_convex_dual)
    @test_throws Exception assert_restriction_exact!(ctx1, ctx2)
    @test !haskey(ctx1.meta, :price_provenance)

    # report = true on the SAME structural mismatch: assert_ac_exact!'s T-mismatch guard is
    # a HARD structural error (never neutralized by ITS OWN report contract — it has none;
    # T-mismatch is unconditional) — read from src/models/ac_oracle.jl: `T == ctx_ac.meta[:T]
    # || error(...)` runs BEFORE any report/throw branching this file's own
    # assert_restriction_exact! adds, so the exception propagates through unconditionally.
    # report=true therefore ALSO throws here — it neutralizes AC-INFEASIBILITY findings
    # (this certificate's own ac_feasible check), never STRUCTURAL mismatches upstream.
    @test_throws Exception assert_restriction_exact!(ctx1, ctx2; report = true)
end

# --- Plan 20-04: ac_dual_fallback_price (OVR-03 nonconvex-AC-dual fallback) ---
#
# ORCHESTRATOR-NOTE ADAPTATION (documented in 20-04-SUMMARY.md's Deviations section): the
# plan's own Task 2 action text checks
# `assert_restriction_exact!(ctx_restricted, ctx_ac; report = true)` BEFORE calling the
# fallback, to "demonstrate the trigger discipline." On the EXACT-04 fixture (pv_scale =
# 1.2), `RestrictedBranchFlow`'s OWN cone certifies `ac_feasible = true` (plan 20-03's
# orchestrator-revised semantics) — so reading `ctx_restricted`'s cert here never actually
# FAILS, and "demonstrating trigger discipline" against an always-passing cert alone would
# be vacuous. This item demonstrates BOTH sides genuinely: (a) the PASSING case on
# `ctx_restricted` (the real reason the fallback is NOT needed for EXACT-04 itself), and (b)
# a GENUINELY FAILING case using an UNRESTRICTED `ConvexBranchFlow` context on the SAME
# fixture (`rtol_exact = 1.0` neutralizes PF-04 so the cone-INEXACT solution is returned
# rather than refused — the SAME synthetic-violation pattern plan 20-03's testitem 5 uses),
# where `cert_failing.ac_feasible == false` / `price_provenance.status == :cert_failed` is
# the genuine D-09 trigger condition a real caller must gate the fallback on.
# `ac_dual_fallback_price` itself is then called UNCONDITIONALLY (per the plan's own action
# text) because THIS item exercises the fallback's OWN mechanics in isolation.
@testitem "restricted_branch_flow: ac_dual_fallback_price triggers only after an observed certificate failure, carries price_status, and 2-seed agreement (D-09/D-10/D-11 CI subset)" tags =
    [:restricted_branch_flow] setup = [Phase4Fixtures] begin
    using TSODSO
    using JuMP

    feeder = Phase4Fixtures.high_pv_feeder()
    aggs = Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)
    λ₀ = Phase4Fixtures.mem_price_profile()

    ctx_restricted, cost_restricted, _ = solve_welfare(
        feeder,
        RestrictedBranchFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
    )
    ctx_ac, cost_ac, _ = solve_welfare(
        feeder,
        ACPowerFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_local = true,
        allow_export = true,
    )

    # (a) The PASSING case (plan 20-03's revised semantics): D-09 does NOT actually require
    # the fallback on EXACT-04's RestrictedBranchFlow solve itself.
    cert = assert_restriction_exact!(ctx_restricted, ctx_ac; report = true)
    @test cert.ac_feasible == true

    # (b) A GENUINELY FAILING case (mirrors plan 20-03's testitem 5's synthetic violation):
    # the unrestricted ConvexBranchFlow context, cone-inexact at rtol_exact = 1.0.
    ctx_unrestricted, cost_unrestricted, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Phase4Fixtures.T,
        λ₀ = λ₀,
        allow_export = true,
        rtol_exact = 1.0,
    )
    cert_failing = assert_restriction_exact!(ctx_unrestricted, ctx_ac; report = true)
    @test cert_failing.ac_feasible == false
    @test ctx_unrestricted.meta[:price_provenance].status == :cert_failed

    # D-09: the fallback below is called REGARDLESS of `cert.ac_feasible` here ONLY because
    # this test exercises the fallback's OWN mechanics in isolation — a real caller must gate
    # this call on `cert.ac_feasible == false`, exactly as (b) above documents.
    result = ac_dual_fallback_price(
        feeder,
        aggs;
        T = Phase4Fixtures.T,
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

# --- Review CR-01: branch-orientation regression (reversed-stored branch is a LEGAL feeder) ---
#
# `assert_radial` (data/topology.jl) validates only tree-ness/connectivity, never orientation:
# a `Branch(from, to, …)` stored child→parent is a fully legal `Feeder` everywhere else in the
# framework (`ConvexBranchFlow`'s DistFlow drop/cone/balances are written in the branch's own
# direction). Review CR-01 found BOTH copies of the Gan-Low shadow recursion — the
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
# r·ℓ at the branch's own `to` end, ConvexBranchFlow Pitfall 6). This algebra also
# discriminates the CORRECT reversed-branch flow (`r·ℓ − P_rev` at the parent side) from the
# tempting bare sign flip `−P_rev`, which would be off by the feeding branch's own loss.
@testitem "restricted_branch_flow: CR-01 regression — reversed-orientation branch agrees exactly with parent→child in BOTH shadow-voltage code paths" tags =
    [:restricted_branch_flow] begin
    using TSODSO
    using JuMP

    r, x = 0.05, 0.04
    buses =
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false), Bus(3, 0.95, 1.05, false)]
    feeder_fwd =
        Feeder(buses, [Branch(1, 2, r, x, 99.0), Branch(2, 3, r, x, 99.0)], 1)
    # Branch 2 stored REVERSED (child 3 → parent 2): legal per assert_radial.
    feeder_rev =
        Feeder(buses, [Branch(1, 2, r, x, 99.0), Branch(3, 2, r, x, 99.0)], 1)

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
        ctx.meta[:feeder] = feeder
        ctx.meta[:T] = T
        ctx.meta[:pf_vars] = (; v = vv, P = PP, Q = QQ, l = ll)
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
        pv = ctx.meta[:pf_vars]
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
            value(xx -> val[xx], constraint_object(c).func) - constraint_object(c).set.upper
            for c in ctx.constraints[:opfm_shadow_voltage]
        ]
    end

    margins_fwd = opfm_margins(feeder_fwd, P_fwd, Q_fwd, l_fwd, v_fixed)
    margins_rev = opfm_margins(feeder_rev, P_rev, Q_rev, l_rev, v_fixed)
    @test length(margins_rev) == 2 * T   # one OPF-m row per non-root bus per hour
    @test maximum(abs.(margins_fwd .- margins_rev)) < 1e-12

    # Cross-path consistency: the model-build margin at the fixed point must equal the
    # post-processing shadow voltage minus the bound — same math, different phase of use.
    idx = 0
    for t in 1:T, i in 2:3
        idx += 1
        @test abs(margins_fwd[idx] - (v̂_fwd[i, t] - buses[i].vmax^2)) < 1e-12
    end
end
