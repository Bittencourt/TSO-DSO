# test/test_run_stochastic.jl
#
# Seam: src/experiments/run_stochastic.jl `run_stochastic`
# generalizes `run_mpc`'s independent-entry-point SHAPE to the two-stage stochastic
# extensive-form + out-of-sample evaluation: it materializes `s.strategy.S` in-sample scenario
# populations from a DISJOINT `sub_seed` tag family, solves `build_stochastic_welfare`,
# then materializes `s.strategy.H_oos` held-out populations from a SECOND,
# DISJOINT tag family and drives them through the build-once `StochasticOosHarness`,
# reporting the realized-vs-in-sample welfare gap. Items tagged
# `[:run_stochastic]`, `setup = [StochasticFixtures]` (this file's own items construct a
# `Scenario` directly, on `:ieee13`/`:default` — `StochasticFixtures`' custom 2-bus fixture is
# not addressable via `Scenario`, mirroring `test_mpc_loop.jl`'s own convention).
#
# T=9 (not `StochasticFixtures.T=6`) is used throughout, to avoid the Deferrable T<9 pitfall on
# the `:ieee13`/`:default` population (`:default` bakes a Deferrable energy-budget window at construction time that
# needs T>=9 to remain constructible).

@testitem "run_stochastic: in-sample and held-out sub_seed families are disjoint" tags =
    [:run_stochastic] setup = [StochasticFixtures] begin
    using TSODSO
    using TSODSO: sub_seed

    s = Scenario(
        name = "t",
        feeder = :ieee13,
        T = 9,
        strategy = Stochastic(S = 3, H_oos = 5),
    )

    # Independently re-derive the SAME two seed families run_stochastic itself derives
    # internally, using the SAME sub_seed(s.seed, tag) idiom and DISJOINT tag prefixes.
    insample_seeds =
        [sub_seed(s.seed, Symbol(:stoch_insample_profiles_, k)) for k in 1:s.strategy.S]
    oos_seeds =
        [sub_seed(s.seed, Symbol(:stoch_oos_profiles_, h)) for h in 1:s.strategy.H_oos]

    @test isempty(intersect(insample_seeds, oos_seeds))
end

@testitem "run_stochastic: same-seed reproducibility" tags = [:run_stochastic] setup =
    [StochasticFixtures] begin
    using TSODSO

    s = Scenario(
        name = "t",
        feeder = :ieee13,
        T = 9,
        strategy = Stochastic(S = 3, H_oos = 5),
    )

    r1 = run_stochastic(s)
    r2 = run_stochastic(s)

    @test r1.in_sample.welfare == r2.in_sample.welfare
    @test r1.in_sample.dadp == r2.in_sample.dadp
    @test r1.oos.welfare_gap == r2.oos.welfare_gap
end

@testitem "run_stochastic: an infeasible held-out pin is skipped-and-reported, never run-aborting" tags =
    [:run_stochastic] setup = [StochasticFixtures] begin
    using TSODSO
    using TSODSO: build_stochastic_oos_harness, sub_seed
    using JuMP: set_parameter_value

    # A held-out draw whose PV falls below every in-sample draw at some hour makes
    # the pinned p_ch collide with p_ch ≤ pv_used ≤ Ppv_h — a genuine PRIMAL_INFEASIBLE
    # that solve_with_retry! (correctly) refuses to retry. Before this fix that single
    # unlucky draw aborted the whole run_stochastic call after the expensive extensive-
    # form solve. _stoch_solve_held_out! now converts EXACTLY the infeasibility statuses
    # into (NaN, true); everything else still rethrows. This item drives the harness into
    # the documented deterministic infeasibility (constant pinned p_ch = 0.001 overflows
    # soc past Emax within one solve on this fixture — see this file-family's own
    # measured-envelope note in test_stochastic_oos_harness.jl's header) and asserts the
    # skip-and-report contract, then re-solves FEASIBLY on the same never-rebuilt model.
    #
    # The harness uses the tightened optimizer (tol_gap 5e-10, the in-sample builder's own
    # tolerance): at the default 1e-8 the recovery solve on this near-lossless 2-bus fixture
    # is refused by the held-out exactness gate (measured worst ratio ≈ 7.3); at 5e-10 the
    # first solve is still INFEASIBLE and the recovery measures ≈ 0.08, so this item checks
    # the infeasibility path and an exact recovery.
    oos_opt =
        TSODSO.select_optimizer(TSODSO.SOCP(); tol_gap_abs = 5e-10, tol_gap_rel = 5e-10)
    feeder = StochasticFixtures.stoch_feeder()
    T = StochasticFixtures.T
    λ0 = StochasticFixtures.stoch_lambda0()
    aggs = StochasticFixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(StochasticFixtures.SEED_STOCH, :wr05_infeasible),
    )
    h = build_stochastic_oos_harness(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = T,
        λ₀ = λ0,
        optimizer = oos_opt,
    )
    pin = only(h.battery_pins)

    # Genuinely infeasible pin: soc0 + 5·η·0.001 = 0.00875 > Emax = 0.008.
    set_parameter_value.(pin.pin_p_ch, fill(0.001, T))
    set_parameter_value.(pin.pin_p_dch, zeros(T))
    w_bad, infeas_bad, inexact_bad = TSODSO._stoch_solve_held_out!(h, 1)
    @test infeas_bad
    @test isnan(w_bad)
    @test inexact_bad === false

    # The SAME (build-once, never-rebuilt) harness recovers with a feasible pin — the
    # skip path leaves the model reusable for the remaining held-out scenarios.
    set_parameter_value.(pin.pin_p_ch, zeros(T))
    w_ok, infeas_ok, inexact_ok = TSODSO._stoch_solve_held_out!(h, 2)
    @test !infeas_ok
    @test isfinite(w_ok)
    @test inexact_ok === false
    @test h.ctx.meta[:socp_maxratio] <= 1

    # A non-solver error (programming error) is NOT skipped — it propagates.
    @test_throws MethodError TSODSO._stoch_solve_held_out!(nothing, 3)
end

@testitem "run_stochastic: oos result carries the infeasible_h mask (all-feasible fixture: all false)" tags =
    [:run_stochastic] setup = [StochasticFixtures] begin
    using TSODSO

    s = Scenario(
        name = "t",
        feeder = :ieee13,
        T = 9,
        strategy = Stochastic(S = 3, H_oos = 5),
    )
    r = run_stochastic(s)

    @test length(r.oos.infeasible_h) == s.strategy.H_oos
    @test all(.!r.oos.infeasible_h)
    @test all(isfinite, r.oos.welfare_h)
    # Every held-out re-solve of this fixture passes the exactness gate (measured worst
    # ratio 0.366 on 1.12.5, 0.350 on 1.12.7), so nothing is excluded as inexact either.
    @test length(r.oos.inexact_h) == s.strategy.H_oos
    @test all(.!r.oos.inexact_h)
    @test length(r.oos.socp_maxratio_h) == s.strategy.H_oos
    @test all(<=(1), r.oos.socp_maxratio_h)
    # With nothing skipped, realized_welfare keeps its original definition exactly.
    @test r.oos.realized_welfare == sum(r.oos.welfare_h) / s.strategy.H_oos
end

@testitem "run_stochastic: a refused held-out draw is reported with :oos_inexact_skipped and excluded end to end" tags =
    [:run_stochastic] setup = [StochasticFixtures] begin
    using TSODSO
    using JuMP: @constraint, delete, value

    s = Scenario(
        name = "t",
        feeder = :ieee13,
        T = 9,
        strategy = Stochastic(S = 3, H_oos = 5),
    )
    r0 = run_stochastic(s)   # every draw certified (see the mask item above)

    # A deterministic refusal on chosen draws, through the real exactness gate and the real
    # skip-and-report conversion: certify the draw, then force the squared current of the
    # least-loaded branch at hour 1 at least δ = 5e-6 above its exact value (cone residual
    # about δ, far above the gate's solver floor; measured ratio ≈ 25 on draw 2), re-solve,
    # and delete the constraint again so the next draw sees the unmodified harness.
    function forced_slack(targets; δ = 5e-6)
        return function (h_oos, i)
            i in targets || return TSODSO._stoch_solve_held_out!(h_oos, i)
            TSODSO.solve_stochastic_oos_step!(h_oos)
            l = h_oos.ctx.pf_vars.l
            b = argmin([value(l[k, 1]) for k in 1:length(h_oos.feeder.branches)])
            con = @constraint(h_oos.model, l[b, 1] >= value(l[b, 1]) + δ)
            res = TSODSO._stoch_solve_held_out!(h_oos, i)
            delete(h_oos.model, con)
            return res
        end
    end

    # One refused draw: reported, excluded, and only the usable draws are averaged.
    r = TSODSO._run_stochastic(s, s.strategy; solve_held_out! = forced_slack((2,)))
    usable = [1, 3, 4, 5]
    @test r.status === :oos_inexact_skipped
    @test r.oos.inexact_h == [false, true, false, false, false]
    @test !any(r.oos.infeasible_h)
    @test r.oos.socp_maxratio_h[2] > 1
    @test all(<=(1), r.oos.socp_maxratio_h[usable])
    @test isfinite(r.oos.welfare_h[2])   # kept for reporting, not averaged
    @test r.in_sample.welfare == r0.in_sample.welfare
    @test r.oos.welfare_h[usable] == r0.oos.welfare_h[usable]
    @test r.oos.realized_welfare == sum(r.oos.welfare_h[usable]) / length(usable)
    @test r.oos.realized_welfare != sum(r.oos.welfare_h) / s.strategy.H_oos
    @test r.oos.welfare_gap == r.oos.realized_welfare - r.in_sample.welfare

    # A refused and an infeasible draw together: the inexact status takes precedence and both
    # draws are excluded.
    with_infeasible(inner, bad) =
        (h_oos, i) -> i in bad ? (NaN, true, false) : inner(h_oos, i)
    r2 = TSODSO._run_stochastic(
        s,
        s.strategy;
        solve_held_out! = with_infeasible(forced_slack((2,)), (4,)),
    )
    @test r2.status === :oos_inexact_skipped
    @test r2.oos.inexact_h == [false, true, false, false, false]
    @test r2.oos.infeasible_h == [false, false, false, true, false]
    @test isnan(r2.oos.socp_maxratio_h[4])
    @test r2.oos.realized_welfare == sum(r2.oos.welfare_h[[1, 3, 5]]) / 3

    # Every draw refused: no usable draw, so no fabricated number.
    r3 = TSODSO._run_stochastic(s, s.strategy; solve_held_out! = forced_slack(1:5))
    @test r3.status === :oos_inexact_skipped
    @test all(r3.oos.inexact_h)
    @test isnan(r3.oos.realized_welfare)
    @test isnan(r3.oos.welfare_gap)
end

@testitem "run_stochastic: measurement-before-golden — repeated-run stability precedes the pinned literal" tags =
    [:run_stochastic] setup = [StochasticFixtures] begin
    using TSODSO

    s = Scenario(
        name = "t",
        feeder = :ieee13,
        T = 9,
        strategy = Stochastic(S = 3, H_oos = 5),
    )

    # THREE fresh calls (never a cached result) with the SAME s — bit-for-bit stability,
    # exploiting this project's own deterministic-seeded-draw guarantee. This assertion MUST
    # be textually BEFORE the pinned golden literal below (the measurement-before-golden
    # ordering) — never the reverse.
    r1 = run_stochastic(s)
    r2 = run_stochastic(s)
    r3 = run_stochastic(s)
    @test r1.oos.welfare_gap == r2.oos.welfare_gap == r3.oos.welfare_gap

    # The golden literal below was pinned ONLY AFTER the stability assertion above
    # passed in this SAME test run.
    #
    # RE-PINNED after dropping the (S−1)·T exactly-
    # redundant soc tie rows changes Clarabel's constraint matrix (better-conditioned,
    # same mathematical optimum), shifting the converged iterate within solver tolerance
    # — the previous golden -0.025156091170856598 moved by ~8e-6 RELATIVE to
    # -0.02515629356082627. Re-measured per the measurement-before-golden
    # discipline: 3 fresh same-process run_stochastic calls, bit-for-bit identical,
    # BEFORE this literal was written.
    #
    # Julia-1.12 cross-version finding: this golden was CI-failing
    # on the "Julia 1.12 - ubuntu-latest" job only (1.10 and 1.11 pass). Root cause is a
    # genuine cross-Julia-minor-version Clarabel converged-iterate shift, not a bug or a
    # flaky test — three fresh same-process run_stochastic(s) calls per version, same
    # Scenario(name="t", feeder=:ieee13, T=9, strategy=Stochastic(S=3, H_oos=5)), are bit-for-bit
    # stable WITHIN each version:
    #
    #   Julia   | welfare_gap             | stable across 3 calls
    #   --------|--------------------------|------------------------
    #   1.10.11 | -0.02515629356082627     | yes
    #   1.11.9  | -0.02515629356082627     | yes
    #   1.12.7  | -0.025156313755701376    | yes
    #
    # CI's own 1.12 runners additionally observed two distinct values across two different
    # commits: -0.025156313755701376 (commit 304db38 — matches the local 1.12.7 measurement
    # exactly) and -0.02515643735591766 (commit 3b73633). The golden -0.02515629356082627
    # above was correct and unchanged on Julia 1.10/1.11 UNTIL the device-correctness
    # fixes below landed. Cross-commit variation on the SAME Julia version (304db38 vs 3b73633, both
    # 1.12) is a separately-tracked IEEE-13 numerical-knife-edge finding, noted here as
    # context only — this tolerance is meant to absorb solver-tolerance noise across
    # environments, not to paper over that structural finding.
    #
    # RE-PINNED: OLD -0.02515629356082627 ->
    # NEW -0.018591711034105174. Cause: the Prev/Qrev/smax_rev
    # JuMP name-collision in build_stochastic_welfare's per-scenario unregister list was fixed
    # — this scenario build previously errored before
    # reaching a golden at all; the device-correctness fixes
    # (battery SOC horizon linking, receiving-end thermal limit, flexible-load reactive
    # draw) independently move this welfare gap too, once the collision no longer masks
    # them. Re-measured live (three fresh same-process
    # run_stochastic(s) calls, bit-for-bit stable, BEFORE this literal was written — see
    # the stability assertion above). `rtol = 1e-4` retained to absorb the same
    # cross-Julia-minor-version solver-tolerance noise documented above.
    @test r1.oos.welfare_gap ≈ -0.018591711034105174 rtol = 1e-4
end
