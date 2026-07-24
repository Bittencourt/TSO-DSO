# test/test_planning_nash.jl
#
# Seam: src/planning/nash.jl (NASH-02/03/04). Task 1 (this section): `NashTrace`'s
# push!/is_converged/trace_summary round-trip contract, plus the regression proving
# `solve_stackelberg!`'s new additive `follower` keyword (src/planning/benders.jl,
# plan 13-02) is byte-identical/non-breaking for every Phase 11/12 call site. Items
# tagged `[:planning]`, names contain "planning" and "nash" (occursin filter
# convention, mirrors test_planning_benders.jl/test_planning_coupling.jl).

@testitem "planning nash: NashTrace push!/is_converged/trace_summary round-trip" tags =
    [:planning] begin
    using TSODSO

    trace = TSODSO.NashTrace()
    @test trace.iters == 0
    @test isempty(trace.sweep_trace)
    @test isempty(trace.distributor_trace)
    @test isempty(trace.nash_residual_trace)
    @test isempty(trace.benders_iters_trace)
    @test isempty(trace.benders_gap_trace)
    @test isempty(trace.benders_retries_trace)
    @test isempty(trace.cuts_rebuilt_trace)
    @test isempty(trace.order_trace)

    empty_summary = TSODSO.trace_summary(trace)
    @test empty_summary.iters == 0
    @test empty_summary.final_sweep == 0
    @test isnan(empty_summary.final_residual)
    @test empty_summary.max_benders_iters == 0
    @test empty_summary.total_benders_retries == 0
    @test empty_summary.total_cuts_rebuilt == 0
    @test TSODSO.is_converged(trace, 1e-4, 2) == false

    push!(
        trace,
        1,
        1;
        nash_residual = 0.05,
        benders_iters = 4,
        benders_gap = 1e-7,
        benders_retries = 0,
        cuts_rebuilt = 3,
        order = :forward,
    )
    push!(
        trace,
        1,
        2;
        nash_residual = 0.02,
        benders_iters = 5,
        benders_gap = 1e-7,
        benders_retries = 1,
        cuts_rebuilt = 4,
        order = :forward,
    )

    @test trace.iters == 2
    # is_converged: the most recent sweep's worst-distributor residual is max(0.05,0.02)=0.05,
    # which is NOT <= 1e-4.
    @test TSODSO.is_converged(trace, 1e-4, 2) == (max(0.05, 0.02) <= 1e-4)
    @test TSODSO.is_converged(trace, 1e-4, 2) == false
    # But it IS <= a looser tolerance that exceeds the worst residual.
    @test TSODSO.is_converged(trace, 0.1, 2) == true

    summary = TSODSO.trace_summary(trace)
    @test summary.iters == 2
    @test summary.final_sweep == 1
    @test summary.final_residual == 0.02
    @test summary.max_benders_iters == 5
    @test summary.total_benders_retries == 1
    @test summary.total_cuts_rebuilt == 7
end

@testitem "planning nash: NashTrace push! guards reject bad order/negative counts" tags =
    [:planning] begin
    using TSODSO

    trace = TSODSO.NashTrace()
    @test_throws ArgumentError push!(
        trace,
        1,
        1;
        nash_residual = 0.1,
        benders_iters = 1,
        benders_gap = 1e-7,
        benders_retries = 0,
        cuts_rebuilt = 0,
        order = :sideways,
    )
    @test_throws ArgumentError push!(
        trace,
        1,
        1;
        nash_residual = 0.1,
        benders_iters = -1,
        benders_gap = 1e-7,
        benders_retries = 0,
        cuts_rebuilt = 0,
        order = :forward,
    )
    @test_throws ArgumentError push!(
        trace,
        1,
        1;
        nash_residual = 0.1,
        benders_iters = 1,
        benders_gap = 1e-7,
        benders_retries = -1,
        cuts_rebuilt = 0,
        order = :forward,
    )
    @test_throws ArgumentError push!(
        trace,
        1,
        1;
        nash_residual = 0.1,
        benders_iters = 1,
        benders_gap = 1e-7,
        benders_retries = 0,
        cuts_rebuilt = -1,
        order = :forward,
    )
    # None of the above should have mutated the trace (guard-before-mutate discipline).
    @test trace.iters == 0
end

@testitem "planning nash: solve_stackelberg! follower keyword is additive — existing Phase 11/12 call sites unchanged" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]
    follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])
    master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)

    mktempdir() do dir
        # No `follower` keyword supplied at all — must be BYTE-IDENTICAL to the
        # pre-plan-13-02 Phase 11/12 regression (test_planning_benders.jl's own
        # first testitem).
        result = solve_stackelberg!(
            feeder,
            LinDistFlow(),
            [agg];
            λ₀ = λ₀,
            T = 1,
            follower_kwargs = follower_kwargs,
            master_kwargs = master_kwargs,
            tol = 1e-6,
            max_iter = 100,
            checkpoint_dir = dir,
        )

        @test result.gap <= 1e-6
        @test isapprox(result.y, 0.7; atol = 1e-3)
        @test isapprox(result.z[1], 0.7; atol = 1e-3)
    end
end

@testitem "planning nash: solve_stackelberg! rejects follower + non-empty follower_kwargs together" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]
    follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])
    master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)

    # A non-`nothing` follower (any object with a `solve_follower!` method) supplied
    # ALONGSIDE a non-empty follower_kwargs must be rejected BEFORE any build call —
    # reuse a genuine FollowerLP (built via build_follower) as the placeholder object,
    # since the guard fires before it is ever used.
    placeholder_follower = build_follower(; follower_kwargs..., T = 1)

    @test_throws ArgumentError solve_stackelberg!(
        feeder,
        LinDistFlow(),
        [agg];
        λ₀ = λ₀,
        T = 1,
        follower_kwargs = follower_kwargs,
        master_kwargs = master_kwargs,
        tol = 1e-6,
        max_iter = 100,
        follower = placeholder_follower,
    )
end
