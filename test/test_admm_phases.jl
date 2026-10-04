# test/test_admm_phases.jl
#
# Phase 34 Plan 07 (ARCH-05): unit tests for the named solve_admm phases and the singleton-dispatched
# reactive hooks (src/admm/admm_state.jl, src/admm/admm_phases.jl). Goldens live in test_admm*.jl and
# the knife-edge canary; this file pins only dispatch/propagation behaviour.

@testitem "admm phases: _react_mode maps the enum totally onto the singleton tags (admm_phases)" tags =
    [:admm, :phases] begin
    using TSODSO
    @test TSODSO._react_mode(TSODSO.OFF) isa TSODSO._ReactiveOff
    @test TSODSO._react_mode(TSODSO.CERTIFIED) isa TSODSO._ReactiveCertified
    @test TSODSO._react_mode(TSODSO.LIVE) isa TSODSO._ReactiveLive
    @test all(m -> TSODSO._react_mode(m) isa TSODSO._ReactiveMode, instances(TSODSO.ReactiveMode))
end

@testitem "admm phases: _react_state allocates reactive arrays only under LIVE (admm_phases)" tags =
    [:admm, :phases] begin
    using TSODSO
    nodes = [2, 3]
    @test TSODSO._react_state(TSODSO._ReactiveOff(), nodes, 4, 10.0) === nothing
    @test TSODSO._react_state(TSODSO._ReactiveCertified(), nodes, 4, 10.0) === nothing
    ls = TSODSO._react_state(TSODSO._ReactiveLive(), nodes, 4, 10.0)
    @test ls isa TSODSO._LiveState
    @test ls.ρ_qf == 10.0 && ls.ρ_q_frozen == false
    for dct in (ls.μq, ls.d, ls.b, ls.qag_dso_prev)
        @test sort(collect(keys(dct))) == nodes
        @test all(v -> v == zeros(4), values(dct))
    end
end

@testitem "admm phases: _react_stack OFF is the active-only norms, LIVE the stacked form (admm_phases)" setup =
    [Phase6Fixtures] tags = [:admm, :phases] begin
    using TSODSO
    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators_no_flex(feeder)
    Th = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()
    ρ = Phase6Fixtures.RHO_2BUS

    sq = (2.0, 3.0, 5.0, 7.0, 11.0)   # sq_r, sq_ds, sq_a, sq_pd, sq_λ
    p_p = 6
    ε_abs, ε_rel = 1e-4, 1e-3

    st_off = TSODSO._admm_build(
        feeder, ConvexBranchFlow(), aggs, Th, λ₀, Float64(ρ), Float64(ρ),
        TSODSO.OFF, TSODSO._ReactiveOff(),
    )
    @test st_off.react === nothing
    out = TSODSO._react_stack(TSODSO._ReactiveOff(), st_off, nothing, sq..., p_p, ε_abs, ε_rel)
    ρf = st_off.ρf
    @test out[1] === sqrt(sq[1])
    @test out[2] === ρf * sqrt(sq[2])
    @test out[3] === sqrt(p_p) * ε_abs + ε_rel * max(sqrt(sq[3]), sqrt(sq[4]))
    @test out[4] === sqrt(p_p) * ε_abs + ε_rel * sqrt(sq[5])

    st_live = TSODSO._admm_build(
        feeder, ConvexBranchFlow(), aggs, Th, λ₀, Float64(ρ), Float64(ρ),
        TSODSO.LIVE, TSODSO._ReactiveLive(),
    )
    acc = (; sq_r_q = 0.5, sq_ds_q = 0.25, sq_b = 1.5, sq_qd = 2.5, sq_μq = 3.5)
    ρ_qf = st_live.react.ρ_qf
    o = TSODSO._react_stack(TSODSO._ReactiveLive(), st_live, acc, sq..., p_p, ε_abs, ε_rel)
    @test o[1] === sqrt(sq[1] + acc.sq_r_q)
    @test o[2] === st_live.ρf * sqrt(sq[2]) + ρ_qf * sqrt(acc.sq_ds_q)
    @test o[3] ===
          sqrt(2p_p) * ε_abs +
          ε_rel * max(sqrt(sq[3] + acc.sq_b), sqrt(sq[4] + acc.sq_qd))
    @test o[4] === sqrt(2p_p) * ε_abs + ε_rel * sqrt(sq[5] + acc.sq_μq)
end

@testitem "admm phases: solve_admm propagates each reactive mode and converges (admm_phases)" setup =
    [Phase6Fixtures] tags = [:admm, :phases] begin
    using TSODSO
    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase6Fixtures.build_two_bus_aggregators_no_flex(feeder)
    Th = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()
    ρ = Phase6Fixtures.RHO_2BUS

    function run_mode(m)
        return solve_admm(
            feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀, ρ = ρ, maxiter = 200,
            reactive_consensus = m,
        )
    end
    for (m, tag) in ((TSODSO.OFF, TSODSO.OFF), (TSODSO.CERTIFIED, TSODSO.CERTIFIED), (TSODSO.LIVE, TSODSO.LIVE))
        r = run_mode(m)
        @test r.reactive_consensus_mode == tag
        @test r.status == :converged
        @test (r.mu_q === nothing) == (m != TSODSO.LIVE)
    end
end
