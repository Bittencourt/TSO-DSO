# test/test_run_stochastic.jl
#
# Seam: src/experiments/run_stochastic.jl (STOCH-01..03, plan 22-04). `run_stochastic`
# generalizes `run_mpc`'s independent-entry-point SHAPE to the two-stage stochastic
# extensive-form + out-of-sample evaluation: it materializes `s.stoch_S` in-sample scenario
# populations from a DISJOINT `sub_seed` tag family, solves `build_stochastic_welfare`
# (plan 22-02), then materializes `s.stoch_H_oos` held-out populations from a SECOND,
# DISJOINT tag family and drives them through the build-once `StochasticOosHarness`
# (plan 22-03), reporting the realized-vs-in-sample welfare gap. Items tagged
# `[:run_stochastic]`, `setup = [Phase22Fixtures]` (this file's own items construct a
# `Scenario` directly, on `:ieee13`/`:default` — `Phase22Fixtures`' custom 2-bus fixture is
# not addressable via `Scenario`, mirroring `test_mpc_loop.jl`'s own convention).
#
# T=9 (not `Phase22Fixtures.T=6`) is used throughout, per this phase's own checker-mandated
# fix for the Deferrable T<9 pitfall on the `:ieee13`/`:default` population (RESEARCH.md
# Pitfall 3 — `:default` bakes a Deferrable energy-budget window at construction time that
# needs T>=9 to remain constructible).

@testitem "run_stochastic: in-sample and held-out sub_seed families are disjoint (T-22-06)" tags =
    [:run_stochastic] setup = [Phase22Fixtures] begin
    using TSODSO

    s = Scenario(name = "t", feeder = :ieee13, T = 9, stoch_S = 3, stoch_H_oos = 5)

    # Independently re-derive the SAME two seed families run_stochastic itself derives
    # internally, using the SAME sub_seed(s.seed, tag) idiom and DISJOINT tag prefixes.
    insample_seeds =
        [sub_seed(s.seed, Symbol(:stoch_insample_profiles_, k)) for k in 1:s.stoch_S]
    oos_seeds = [sub_seed(s.seed, Symbol(:stoch_oos_profiles_, h)) for h in 1:s.stoch_H_oos]

    @test isempty(intersect(insample_seeds, oos_seeds))
end

@testitem "run_stochastic: same-seed reproducibility (INFRA-04)" tags = [:run_stochastic] setup =
    [Phase22Fixtures] begin
    using TSODSO

    s = Scenario(name = "t", feeder = :ieee13, T = 9, stoch_S = 3, stoch_H_oos = 5)

    r1 = run_stochastic(s)
    r2 = run_stochastic(s)

    @test r1.in_sample.welfare == r2.in_sample.welfare
    @test r1.in_sample.dadp == r2.in_sample.dadp
    @test r1.oos.welfare_gap == r2.oos.welfare_gap
end

@testitem "run_stochastic: WR-05 (phase-22 review) — an infeasible held-out pin is skipped-and-reported, never run-aborting" tags =
    [:run_stochastic] setup = [Phase22Fixtures] begin
    using TSODSO
    using JuMP: set_parameter_value

    # WR-05: a held-out draw whose PV falls below every in-sample draw at some hour makes
    # the pinned p_ch collide with p_ch ≤ pv_used ≤ Ppv_h — a genuine PRIMAL_INFEASIBLE
    # that solve_with_retry! (correctly) refuses to retry. Before this fix that single
    # unlucky draw aborted the whole run_stochastic call after the expensive extensive-
    # form solve. _stoch_solve_held_out! now converts EXACTLY the infeasibility statuses
    # into (NaN, true); everything else still rethrows. This item drives the harness into
    # the documented deterministic infeasibility (constant pinned p_ch = 0.001 overflows
    # soc past Emax within one solve on this fixture — see this file-family's own
    # measured-envelope note in test_stochastic_oos_harness.jl's header) and asserts the
    # skip-and-report contract, then re-solves FEASIBLY on the same never-rebuilt model.
    feeder = Phase22Fixtures.stoch_feeder()
    T = Phase22Fixtures.T
    λ0 = Phase22Fixtures.stoch_lambda0()
    aggs = Phase22Fixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(Phase22Fixtures.SEED_STOCH, :wr05_infeasible),
    )
    h = build_stochastic_oos_harness(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ0)
    pin = only(h.battery_pins)

    # Genuinely infeasible pin: soc0 + 5·η·0.001 = 0.00875 > Emax = 0.008.
    set_parameter_value.(pin.pin_p_ch, fill(0.001, T))
    set_parameter_value.(pin.pin_p_dch, zeros(T))
    w_bad, infeas_bad = TSODSO._stoch_solve_held_out!(h, 1)
    @test infeas_bad
    @test isnan(w_bad)

    # The SAME (build-once, never-rebuilt) harness recovers with a feasible pin — the
    # skip path leaves the model reusable for the remaining held-out scenarios.
    set_parameter_value.(pin.pin_p_ch, zeros(T))
    w_ok, infeas_ok = TSODSO._stoch_solve_held_out!(h, 2)
    @test !infeas_ok
    @test isfinite(w_ok)
end

@testitem "run_stochastic: WR-05 (phase-22 review) — oos result carries the infeasible_h mask (all-feasible fixture: all false)" tags =
    [:run_stochastic] setup = [Phase22Fixtures] begin
    using TSODSO

    s = Scenario(name = "t", feeder = :ieee13, T = 9, stoch_S = 3, stoch_H_oos = 5)
    r = run_stochastic(s)

    @test length(r.oos.infeasible_h) == s.stoch_H_oos
    @test all(.!r.oos.infeasible_h)
    @test all(isfinite, r.oos.welfare_h)
    # With nothing infeasible, realized_welfare keeps its pre-WR-05 definition exactly.
    @test r.oos.realized_welfare == sum(r.oos.welfare_h) / s.stoch_H_oos
end

@testitem "run_stochastic: D-11 measurement-before-golden — repeated-run stability precedes the pinned literal" tags =
    [:run_stochastic] setup = [Phase22Fixtures] begin
    using TSODSO

    s = Scenario(name = "t", feeder = :ieee13, T = 9, stoch_S = 3, stoch_H_oos = 5)

    # THREE fresh calls (never a cached result) with the SAME s — bit-for-bit stability,
    # exploiting this project's own deterministic-seeded-draw guarantee. This assertion MUST
    # be textually BEFORE the pinned golden literal below (D-11's measurement-before-golden
    # ordering) — never the reverse.
    r1 = run_stochastic(s)
    r2 = run_stochastic(s)
    r3 = run_stochastic(s)
    @test r1.oos.welfare_gap == r2.oos.welfare_gap == r3.oos.welfare_gap

    # D-11: the golden literal below was pinned ONLY AFTER the stability assertion above
    # passed in this SAME test run.
    #
    # RE-PINNED for the WR-09 fix (phase-22 review): dropping the (S−1)·T exactly-
    # redundant soc tie rows changes Clarabel's constraint matrix (better-conditioned,
    # same mathematical optimum), shifting the converged iterate within solver tolerance
    # — the previous golden -0.025156091170856598 moved by ~8e-6 RELATIVE to
    # -0.02515629356082627. Re-measured per the D-11 measurement-before-golden
    # discipline: 3 fresh same-process run_stochastic calls, bit-for-bit identical,
    # BEFORE this literal was written.
    @test r1.oos.welfare_gap ≈ -0.02515629356082627
end
