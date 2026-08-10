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
    # passed in this SAME test run (measured value: -0.025156091170856598, confirmed stable
    # across 3 fresh calls in this same process before being written here).
    @test r1.oos.welfare_gap ≈ -0.025156091170856598
end
