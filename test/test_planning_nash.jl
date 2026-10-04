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

    # WR-04 regressions: an invalid sweep width throws (a caller bug, never a soft
    # false)...
    @test_throws ArgumentError TSODSO.is_converged(trace, 1e-4, 0)
    @test_throws ArgumentError TSODSO.is_converged(trace, 1e-4, -1)
    # ...and a MID-SWEEP ledger (sweep 2 has only 1 of its 2 rows) is never reported
    # converged — the window is selected by sweep index, so the tiny sweep-2 residual
    # below can never be mixed with sweep-1 rows into a fake "last N rows" window
    # (before the fix, the trailing-2-rows window [0.02, 1e-9] reported true at
    # tol = 0.05 mid-sweep).
    push!(
        trace,
        2,
        1;
        nash_residual = 1e-9,
        benders_iters = 3,
        benders_gap = 1e-8,
        benders_retries = 0,
        cuts_rebuilt = 2,
        order = :forward,
    )
    @test TSODSO.is_converged(trace, 0.05, 2) == false
    # Once sweep 2 completes, its own (all-tiny) residuals report converged.
    push!(
        trace,
        2,
        2;
        nash_residual = 2e-9,
        benders_iters = 3,
        benders_gap = 1e-8,
        benders_retries = 0,
        cuts_rebuilt = 2,
        order = :forward,
    )
    @test TSODSO.is_converged(trace, 1e-6, 2) == true
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

# --- Task 2: run_nash! — the outer Gauss-Seidel loop --------------------------------
#
# Shared N=2 SYMMETRIC toy fixture used by testitems 5-9 below (extends the Phase-11
# toy fixture, plan 13-02's own <toy_fixture>): T=1, corridor_cap=2.0,
# x_inv_max=[0.3,0.3], c_inv=[1.0,1.0], c_op=[[0.5],[0.5]]; each distributor's own
# operational side identical to the Phase-11 toy fixture (feeder=
# Phase6Fixtures.two_bus_feeder(), pf=LinDistFlow(), agg=ToyElasticDevice(2,6.0,1.0,10.0)
# wrapped in Aggregator(2,0.9,[dev],[0.0]), λ₀=[4.0],
# master_kwargs=(;c_y=0.3,y_max=8.0,α_op_lb=-5.0,α_x_lb=0.0)). Since TestItemRunner
# executes each `@testitem` in its own isolated module (no shared file-level helper
# functions across items — mirrors this project's own test_planning_benders.jl/
# test_planning_coupling.jl convention of inlining fixture construction per item rather
# than a cross-testmodule dependency), the fixture is constructed inline in each item
# below rather than factored into a shared function.
#
# HAND-DERIVED EQUILIBRIUM (verified, not re-derived at test time): each distributor's
# UNCONSTRAINED Stackelberg optimum (as in test_planning_benders.jl's own re-derivation)
# is z*=0.7 (same marginal follower cost m_f = c_inv[i]/corridor_cap + c_op[i] =
# 1.0/2.0 + 0.5 = 1.0, identical to the single-distributor toy fixture's own m_f). But
# the SHARED pooled capacity, combined with the per-distributor investment ceiling
# x_inv_max=0.3, caps the JOINTLY deliverable flow: at the symmetric fixed point
# x_inv_1=x_inv_2=0.3, the pooled capacity is corridor_cap*(0.3+0.3)=1.2, so
# z_1+z_2<=1.2, i.e. z_i<=0.6 each (below the unconstrained 0.7) — since
# total(z)=c_y*z+φ(z)-W(z) is strictly convex with its unconstrained minimum at 0.7, it
# is DECREASING on [0,0.6], so the tightest feasible z=0.6 is optimal. At z_i=0.6, the
# follower's own required investment is EXACTLY x_inv_max[i]=0.3 (verified:
# x_inv[i]=(z_i+z_j)/corridor_cap - x_inv_j=(0.6+0.6)/2.0-0.3=0.3), a genuine fixed
# point — no re-tuning contingency needed for this symmetric fixture (Revision 1's own
# escape hatch is unused here).

@testitem "planning nash: N=2 Gauss-Seidel converges to the hand-checked congested equilibrium (z=[0.6,0.6], x_inv=[0.3,0.3], capacity binding, PVAL-04 continuous-only companion check)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    using JuMP: value, all_variables, is_binary, is_integer

    shared = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.3],
        c_inv = [1.0, 1.0],
        c_op = [[0.5], [0.5]],
    )
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    specs = [spec, spec]
    z0 = zeros(2, 1)

    result = run_nash!(
        specs,
        shared;
        z0 = z0,
        tol_outer = 1e-4,
        max_sweeps = 50,
        checkpoint_dir = mktempdir(),
    )

    @test result.converged
    @test isapprox(result.z, [0.6, 0.6]; atol = 1e-3)
    @test isapprox(result.x_inv, [0.3, 0.3]; atol = 1e-3)

    # Deviation (Rule 1, discovered during execution): the PLAN's own literal
    # assertion checks `abs(dual(shared.model[:capacity][1])) > 1e-8`, but by the time
    # run_nash! returns, write_back! has bound-pinned BOTH distributors' x_inv[i] to a
    # SINGLE point (lb == ub) and BOTH z[i,:] are pinned Parameters — every variable in
    # shared.model is simultaneously fixed, so the LP has ZERO remaining degrees of
    # freedom anywhere. HiGHS's presolve reduces this fully-determined model to an
    # EMPTY LP ("Reduced to empty") and postsolve recovers SOME valid-but-arbitrary
    # dual assignment among the (degenerate) many that satisfy complementary
    # slackness — verified directly (a standalone probe outside this test file) that
    # this consistently allocates ZERO dual mass to the capacity row regardless of
    # whether x_inv sits at its own ceiling or strictly below it, and regardless of
    # HiGHS's presolve setting. A literal `dual(...)` check is therefore NOT a
    # reliable way to confirm the shared corridor is genuinely congested once both
    # distributors have fully committed. This test instead verifies BINDINGNESS
    # directly and robustly: the pooled capacity constraint holds with EQUALITY (not
    # slack) at the converged equilibrium — the mathematically equivalent, numerically
    # robust way to confirm the corridor is genuinely congested, immune to LP-duality
    # degeneracy in a fully-pinned model.
    total_flow = sum(value(shared.model[:x_op][i, 1]) for i in 1:2)
    total_capacity = 2.0 * sum(value(shared.x_inv[i]) for i in 1:2)
    @test isapprox(total_flow, total_capacity; atol = 1e-6)

    # Revision 1, checker-added: PVAL-04 continuous-only companion check — run_nash!'s
    # own write-back/activate cycle never introduces a binary/integer variable into the
    # shared model it mutates.
    # NOTE: consolidated coverage of all 4 planning-layer builders now also lives in
    # test/test_planning_noninteger.jl; this check additionally covers the
    # POST-run_nash!-mutation state (a genuinely different code path than a fresh
    # build), so it is kept, not removed.
    @test all(v -> !is_binary(v) && !is_integer(v), all_variables(shared.model))
end

@testitem "planning nash: nested-tolerance guard rejects inner tol >= outer tol" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    shared = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.3],
        c_inv = [1.0, 1.0],
        c_op = [[0.5], [0.5]],
    )
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    # Distributor 1's own inner tol equals tol_outer — violates the STRICT nesting
    # requirement.
    specs = [merge(spec, (; tol = 1e-4)), spec]
    z0 = zeros(2, 1)

    @test_throws ArgumentError run_nash!(
        specs,
        shared;
        z0 = z0,
        tol_outer = 1e-4,
        max_sweeps = 50,
        checkpoint_dir = mktempdir(),
    )
end

@testitem "planning nash: forward and reverse sweep orders agree on the symmetric N=2 fixture (Gauss-Seidel-vs-Jacobi timing regression, Pitfall 1)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    build_toy_shared() = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.3],
        c_inv = [1.0, 1.0],
        c_op = [[0.5], [0.5]],
    )
    build_toy_specs() = begin
        dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
        agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
        spec = (;
            feeder = Phase6Fixtures.two_bus_feeder(),
            pf = LinDistFlow(),
            aggregators = [agg],
            λ₀ = [4.0],
            master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
        )
        [spec, spec]
    end

    z0 = zeros(2, 1)

    # Each order runs on its OWN freshly-built shared model, since SharedTransmission
    # is mutated destructively.
    shared_fwd = build_toy_shared()
    result_fwd = run_nash!(
        build_toy_specs(),
        shared_fwd;
        z0 = z0,
        tol_outer = 1e-4,
        max_sweeps = 50,
        order = :forward,
        checkpoint_dir = mktempdir(),
    )

    shared_rev = build_toy_shared()
    result_rev = run_nash!(
        build_toy_specs(),
        shared_rev;
        z0 = z0,
        tol_outer = 1e-4,
        max_sweeps = 50,
        order = :reverse,
        checkpoint_dir = mktempdir(),
    )

    @test result_fwd.converged
    @test result_rev.converged
    @test isapprox(result_fwd.z, result_rev.z; atol = 1e-3)
end

@testitem "planning nash: intra-sweep write-back timing — distributor 2 reads distributor 1's JUST-updated z_1 within the same sweep, not the previous sweep's value (DIRECT regression, Revision 1)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    using JuMP: value, parameter_value

    shared = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.3],
        c_inv = [1.0, 1.0],
        c_op = [[0.5], [0.5]],
    )
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    specs = [spec, spec]

    # Manually replicate ONLY the first half of sweep 1's forward-order body — the
    # EXACT sequence run_nash!'s own loop uses for distributor 1.
    activate_distributor!(shared, 1)
    result_1 = solve_stackelberg!(
        specs[1].feeder,
        specs[1].pf,
        specs[1].aggregators;
        λ₀ = specs[1].λ₀,
        T = shared.T,
        follower_kwargs = NamedTuple(),
        master_kwargs = specs[1].master_kwargs,
        follower = DistributorView(shared, 1),
        checkpoint_dir = mktempdir(),
    )
    f_res = solve_follower!(result_1.follower, result_1.z)
    x_inv_1_converged = value(shared.x_inv[1])
    write_back!(shared, 1, result_1.z, x_inv_1_converged)

    # The shared model's OWN parameter state immediately after distributor 1's
    # write-back — read directly off shared.model, not a separate/cached copy.
    # `parameter_value` (not `value`) is the correct solve-independent accessor for a
    # native JuMP Parameter's own set value — `write_back!`'s bound-pin on x_inv also
    # dirties the model's solved status, so `value()` on a Parameter here would
    # spuriously raise `OptimizeNotCalled` even though the parameter's OWN state is
    # perfectly well-defined without any solve.
    z1_written = copy(parameter_value.(shared.model[:z][1, :]))

    # Mimicking exactly what run_nash!'s loop body does NEXT for distributor 2 within
    # the SAME sweep: distributor 1's row must NOT have reverted or gone stale.
    activate_distributor!(shared, 2)
    @test parameter_value.(shared.model[:z][1, :]) == z1_written
end

@testitem "planning nash: max_sweeps exhaustion raises loudly, never a silent non-converged return" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    shared = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.3],
        c_inv = [1.0, 1.0],
        c_op = [[0.5], [0.5]],
    )
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    specs = [spec, spec]
    z0 = zeros(2, 1)

    # Wrapped in a `let` block (mirrors test_planning_benders.jl's own `mktempdir() do
    # dir ... end` closure idiom): TestItemRunner re-includes each @testitem's body as
    # a SEQUENCE of independent top-level forms, so a bare top-level `err = nothing`
    # followed by a separate `try/catch` form would NOT share scope with the `@test`
    # forms that follow — a single compound expression (this `let` block) keeps
    # `err` in one consistent function-like scope.
    let err = nothing
        try
            run_nash!(
                specs,
                shared;
                z0 = z0,
                tol_outer = 1e-4,
                max_sweeps = 1,
                checkpoint_dir = mktempdir(),
            )
        catch e
            err = e
        end
        @test err isa ConvergenceError
        @test occursin("exhausted", err.msg)
        @test occursin("last recorded nash_residual", err.msg)
    end
end

@testitem "planning nash: damping ω=0.5 still converges (no cycling on this monotone fixture)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    shared = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.3],
        c_inv = [1.0, 1.0],
        c_op = [[0.5], [0.5]],
    )
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    specs = [spec, spec]
    z0 = zeros(2, 1)

    result = run_nash!(
        specs,
        shared;
        z0 = z0,
        tol_outer = 1e-4,
        max_sweeps = 50,
        ω = 0.5,
        checkpoint_dir = mktempdir(),
    )

    @test result.converged
    @test isapprox(result.z, [0.6, 0.6]; atol = 1e-2)
end

# --- Task 3: plot_nash_convergence — core stub + CairoMakie extension method --------
#
# Mirrors test_diagnostics_plot.jl's own separate-process CairoMakie idiom EXACTLY
# (skip-with-message when CairoMakie is not installed — a weakdep, not a hard test
# dependency — so the headless core suite stays green and plot-free).

@testitem "planning nash: plot_nash_convergence core stays plot-free, ext returns a Makie Figure when CairoMakie is loaded (plot, makie, nash)" tags =
    [:planning] begin
    using TSODSO

    # Companion assertion (mirrors test_diagnostics_plot.jl's own headless-branch
    # checks for plot_convergence/plot_price_convergence): the core symbol is ALWAYS
    # exported, but carries NO method and never pulls in CairoMakie/Makie.
    @test isdefined(TSODSO, :plot_nash_convergence)
    @test isempty(methods(TSODSO.plot_nash_convergence))
    loaded = string.(collect(keys(Base.loaded_modules)))
    @test !any(m -> occursin("CairoMakie", m), loaded)
    @test !any(m -> occursin("Makie", m), loaded)

    trace = TSODSO.NashTrace()
    @test_throws MethodError TSODSO.plot_nash_convergence(trace)

    if Base.find_package("CairoMakie") === nothing
        @info "CairoMakie not installed (weakdep) — SKIPPING the with-CairoMakie Figure check; " *
              "the headless core suite stays plot-free."
        @test_skip Base.find_package("CairoMakie") !== nothing
    else
        proj = dirname(Base.active_project())
        code = raw"""
        import CairoMakie
        using TSODSO
        trace = TSODSO.NashTrace()
        push!(trace, 1, 1; nash_residual=0.2, benders_iters=4, benders_gap=1e-7,
              benders_retries=0, cuts_rebuilt=3, order=:forward)
        push!(trace, 1, 2; nash_residual=0.15, benders_iters=5, benders_gap=1e-7,
              benders_retries=0, cuts_rebuilt=3, order=:forward)
        push!(trace, 2, 1; nash_residual=0.05, benders_iters=3, benders_gap=1e-8,
              benders_retries=0, cuts_rebuilt=3, order=:forward)
        push!(trace, 2, 2; nash_residual=0.02, benders_iters=3, benders_gap=1e-8,
              benders_retries=0, cuts_rebuilt=3, order=:forward)
        # WITH CairoMakie loaded the ext activates: the generic now HAS a NashTrace method.
        @assert hasmethod(TSODSO.plot_nash_convergence, Tuple{TSODSO.NashTrace})
        f = TSODSO.plot_nash_convergence(trace)
        @assert f isa CairoMakie.Makie.Figure "plot_nash_convergence must return a Makie Figure"
        println("NASH_MAKIE_EXT_OK")
        """
        out = read(`$(Base.julia_cmd()) --project=$proj -e $code`, String)
        @test occursin("NASH_MAKIE_EXT_OK", out)
    end
end

# --- Task 1 (plan 13-03): run_nash_probe — multi-seed/multi-order gate + honest spread
# reporting (NASH-04). Reuses the same N=2 symmetric toy fixture as testitems 5-9 above
# (build_shared_transmission N=2, T=1, corridor_cap=2.0, x_inv_max=[0.3,0.3],
# c_inv=[1.0,1.0], c_op=[[0.5],[0.5]]; each distributor's own operational side identical
# to the Phase-11 toy fixture) plus a genuinely new N=3 corridor extension for the
# probe-only (no closed-form hand-check required, per CONTEXT.md's own
# N=2-hand-checkable/N=3-probe-only scope split).

@testitem "planning nash: N=2 gating probe — 3 seeds x 2 orders all converge, structural 'a converged equilibrium' language" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    specs = [spec, spec]

    build_shared =
        () -> build_shared_transmission(;
            N = 2,
            T = 1,
            corridor_cap = 2.0,
            x_inv_max = [0.3, 0.3],
            c_inv = [1.0, 1.0],
            c_op = [[0.5], [0.5]],
        )

    # Hand-picked per 13-RESEARCH.md Pattern 4: a cold start, a symmetric-capacity-split
    # guess (the hand-checked equilibrium's own candidate ballpark), and an asymmetric
    # start favoring distributor 1.
    seeds = (;
        zero = zeros(2, 1),
        saturating = fill(2.0 * (0.3 + 0.3) / 2, 2, 1),
        skewed = [0.5; 0.1;;],
    )
    orders = (:forward, :reverse)

    result = run_nash_probe(
        specs,
        build_shared;
        seeds = seeds,
        orders = orders,
        tol_outer = 1e-4,
        max_sweeps = 50,
        checkpoint_dir = mktempdir(),
    )

    @test result.n_runs == 6
    @test all(r -> r.result.converged, result.runs)
    @test occursin("a converged equilibrium", result.summary)
    @test !occursin("the equilibrium", result.summary)
    @test result.spread.z_spread >= 0.0 && isfinite(result.spread.z_spread)
    @test result.spread.x_inv_spread >= 0.0 && isfinite(result.spread.x_inv_spread)
    @test result.spread.cost_spread >= 0.0 && isfinite(result.spread.cost_spread)

    # Phase 31 (BILEV-06a), Task 1's own "Test 2 (control, unique equilibrium unaffected)":
    # this corner-cap fixture is NOT modified by this plan — re-asserted here as a
    # regression that bare-matrix seeds (this testitem's own unchanged call shape) still
    # report an at-or-below-solver-noise spread (unique equilibrium, no split continuum).
    # MEASURED 2026-10-02 (scratchpad probe_interior_gne.jl, this exact fixture/seeds):
    # z_spread ≈ 1.11e-16, x_inv_spread = 0.0, cost_spread = 0.0 — comfortably inside a
    # 1e-6 floor (>> machine epsilon, << the interior-cap fixture's own ~0.7 spread below).
    @test result.spread.x_inv_spread < 1e-6
    @test result.spread.z_spread < 1e-6
end

# --- Task 1 (plan 31-03, BILEV-06a): interior-investment-cap GNE fixture — a genuine 1-D
# continuum of generalized Nash equilibria (GNE), certified via run_nash_probe's own
# Phase-31 seed-dispatch extension (bare matrix OR (;z0,x_inv0) NamedTuple).
#
# HAND-DERIVED GNE INTERVAL (31-RESEARCH.md "Concrete fixture numbers", independently
# re-derivable from the corner-cap control's own "HAND-DERIVED EQUILIBRIUM" comment
# above): each distributor's UNCONSTRAINED Stackelberg optimum is z_i*=0.7 (same
# marginal follower cost m_f = c_inv[i]/corridor_cap + c_op[i] = 1.0/2.0+0.5 = 1.0 as the
# corner-cap fixture). The MINIMAL total investment supporting BOTH distributors at their
# unconstrained optimum is S_min = (0.7+0.7)/corridor_cap = 0.7. With
# x_inv_max=[1.0,1.0] (margin 0.3 above S_min, safely non-binding everywhere on the
# interval — Pitfall 4: a modest margin, not a de facto Inf), the GNE set contains
# {(x_inv_1, 0.7 - x_inv_1) : x_inv_1 ∈ [0, 0.7]}, each paired with (z_1,z_2) ≈ (0.7,0.7)
# (constant across the continuum, since c_inv[i] > 0 strictly makes each player minimize
# its OWN x_inv_i at the SAME marginal cost regardless of the split — see 31-RESEARCH.md
# "Why a continuum exists here specifically" for the full derivation). It is NOT the
# whole GNE set: free-riding GNEs off this segment also exist (x_inv_j = 0,
# z_j = 1.2 − p, p ∈ [0, 0.5], x_inv_i = (1.9 − p)/2 — e.g. x_inv = (0.95, 0),
# z = (0.7, 1.2), multipliers (0.5, ≈0); iteration-2 review, WR-01). The segment is the
# part this testitem exercises (and, with the common multiplier 0.5, the VE set).
#
# WHY z0-ONLY SEEDS CANNOT EXPOSE THIS CONTINUUM (31-RESEARCH.md's own "CRITICAL
# FINDING", restated in run_nash_probe's own docstring): run_nash!'s default x_inv0
# derivation (maximum(z0[j,:])/corridor_cap) always seeds the MINIMAL exactly-supporting
# investment for whatever z0 is chosen — zero slack by construction — so every z0/order
# combination converges to the BIT-IDENTICAL point regardless of seed. Seeds below are
# therefore `(; z0, x_inv0)` NamedTuples spanning x_inv0 ∈ {0.0, 0.2, 0.5, 0.7} (the full
# interval, not just touching it) with the SAME z0 = [0.7,0.7] (the unconstrained
# optimum, constant across the continuum) for every seed.

@testitem "planning nash: interior-cap fixture (x_inv_max=[1.0,1.0]) exposes a genuine GNE continuum — x_inv_spread exceeds a measured floor, z_spread stays near-zero (BILEV-06a)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    # S_min = (0.7+0.7)/corridor_cap = 0.7 — see this testitem's own header comment for
    # the full derivation. A `let`-scoped local (not a file-level `const`): TestItemRunner
    # executes each `@testitem` body in an isolated module, so a bare top-level `const`
    # between testitems in this file is a landmine (never defined inside any testitem's
    # own scope under the real runner) — mirrors this file's own established
    # inline-fixture-construction convention (see this file's Task-2 header comment).
    S_MIN = 0.7

    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    specs = [spec, spec]

    build_shared =
        () -> build_shared_transmission(;
            N = 2,
            T = 1,
            corridor_cap = 2.0,
            x_inv_max = [1.0, 1.0],
            c_inv = [1.0, 1.0],
            c_op = [[0.5], [0.5]],
        )

    z0_optimum = reshape([0.7, 0.7], 2, 1)
    seeds = (;
        low = (; z0 = z0_optimum, x_inv0 = [0.0, 0.7]),
        mid_low = (; z0 = z0_optimum, x_inv0 = [0.2, 0.5]),
        mid_high = (; z0 = z0_optimum, x_inv0 = [0.5, 0.2]),
        high = (; z0 = z0_optimum, x_inv0 = [0.7, 0.0]),
    )
    orders = (:forward, :reverse)

    result = run_nash_probe(
        specs,
        build_shared;
        seeds = seeds,
        orders = orders,
        tol_outer = 1e-4,
        max_sweeps = 50,
        checkpoint_dir = mktempdir(),
    )

    @test result.n_runs == 8
    @test all(r -> r.result.converged, result.runs)
    @test occursin("a converged equilibrium", result.summary)
    @test !occursin("the equilibrium", result.summary)

    # MEASURED 2026-10-02 (scratchpad probe_interior_gne.jl, this exact fixture/seeds):
    # x_inv_spread ≈ 0.6999 (the interval's own full width S_min=0.7, confirming every
    # seed genuinely landed on a DISTINCT point of the continuum); z_spread ≈ 5.8e-4
    # (outer-tol_outer-scale Benders inner-loop noise, ~1000x smaller than x_inv_spread);
    # cost_spread ≈ 9.4e-8 (solver-precision noise). Floor set comfortably below the
    # measured ~0.6999 (margin ~0.2) and far above the noise scale.
    @test result.spread.x_inv_spread > 0.5
    @test result.spread.z_spread < 0.01

    # Every converged run's own (x_inv_1, x_inv_2) sums to S_min — the same atol=1e-3
    # this fixture family already uses (e.g. the corner-cap control's own
    # `isapprox(result.z, [0.6, 0.6]; atol = 1e-3)` above): measured max deviation from
    # S_min across all 8 runs is ≈3.4e-4, well inside this tolerance.
    for r in result.runs
        @test isapprox(sum(r.result.x_inv), S_MIN; atol = 1e-3)
    end
end

@testitem "planning nash: N=3 probe converges (no closed-form hand-check required, per CONTEXT.md's N=2-hand-checkable/N=3-probe-only scope)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    specs = [spec, spec, spec]

    build_shared =
        () -> build_shared_transmission(;
            N = 3,
            T = 1,
            corridor_cap = 2.0,
            x_inv_max = [0.3, 0.3, 0.3],
            c_inv = [1.0, 1.0, 1.0],
            c_op = [[0.5], [0.5], [0.5]],
        )

    seeds = (;
        zero = zeros(3, 1),
        saturating = fill(2.0 * (0.3 + 0.3 + 0.3) / 3, 3, 1),
        skewed = [0.5; 0.1; 0.3;;],
    )
    orders = (:forward, :reverse)

    result = run_nash_probe(
        specs,
        build_shared;
        seeds = seeds,
        orders = orders,
        tol_outer = 1e-4,
        max_sweeps = 50,
        checkpoint_dir = mktempdir(),
    )

    @test result.n_runs == 6
    @test all(r -> r.result.converged, result.runs)
    @test occursin("a converged equilibrium", result.summary)
    @test !occursin("the equilibrium", result.summary)
end

@testitem "planning nash: run_nash_probe propagates a non-converging probe run, never swallows it" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    specs = [spec, spec]

    build_shared =
        () -> build_shared_transmission(;
            N = 2,
            T = 1,
            corridor_cap = 2.0,
            x_inv_max = [0.3, 0.3],
            c_inv = [1.0, 1.0],
            c_op = [[0.5], [0.5]],
        )
    seeds = (;
        zero = zeros(2, 1),
        saturating = fill(2.0 * (0.3 + 0.3) / 2, 2, 1),
        skewed = [0.5; 0.1;;],
    )
    orders = (:forward, :reverse)

    # Deliberately too tight a max_sweeps for ONE probe combination to converge within
    # — must raise ConvergenceError, propagated from the underlying run_nash!, never
    # caught/swallowed by run_nash_probe.
    @test_throws ConvergenceError run_nash_probe(
        specs,
        build_shared;
        seeds = seeds,
        orders = orders,
        tol_outer = 1e-4,
        max_sweeps = 1,
        checkpoint_dir = mktempdir(),
    )
end

@testitem "planning nash: run_nash_probe guards reject fewer than 3 seeds or fewer than 2 orders" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    specs = [spec, spec]

    build_shared =
        () -> build_shared_transmission(;
            N = 2,
            T = 1,
            corridor_cap = 2.0,
            x_inv_max = [0.3, 0.3],
            c_inv = [1.0, 1.0],
            c_op = [[0.5], [0.5]],
        )

    # Only 2 seeds — violates the >= 3 seeds minimum.
    seeds_too_few = (; zero = zeros(2, 1), skewed = [0.5; 0.1;;])
    @test_throws ArgumentError run_nash_probe(
        specs,
        build_shared;
        seeds = seeds_too_few,
        orders = (:forward, :reverse),
        tol_outer = 1e-4,
        max_sweeps = 50,
        checkpoint_dir = mktempdir(),
    )

    # Only 1 order — violates the >= 2 orders minimum.
    seeds_ok = (;
        zero = zeros(2, 1),
        saturating = fill(2.0 * (0.3 + 0.3) / 2, 2, 1),
        skewed = [0.5; 0.1;;],
    )
    @test_throws ArgumentError run_nash_probe(
        specs,
        build_shared;
        seeds = seeds_ok,
        orders = (:forward,),
        tol_outer = 1e-4,
        max_sweeps = 50,
        checkpoint_dir = mktempdir(),
    )
end

@testitem "planning nash: z0/x_inv0 seeds genuinely enter the shared game state — distinct seeds produce distinct sweep-1 trajectories and can reach distinct equilibria (CR-01 regression, NASH-04 seed-liveness)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    build_toy_shared() = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.3],
        c_inv = [1.0, 1.0],
        c_op = [[0.5], [0.5]],
    )
    build_toy_specs() = begin
        dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
        agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
        spec = (;
            feeder = Phase6Fixtures.two_bus_feeder(),
            pf = LinDistFlow(),
            aggregators = [agg],
            λ₀ = [4.0],
            master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
        )
        [spec, spec]
    end

    # Run A: cold seed (z0 = 0, derived x_inv0 = 0) — the hand-checked SYMMETRIC
    # congested equilibrium (testitem 5): z = [0.6, 0.6].
    result_cold = run_nash!(
        build_toy_specs(),
        build_toy_shared();
        z0 = zeros(2, 1),
        tol_outer = 1e-4,
        max_sweeps = 50,
        checkpoint_dir = mktempdir(),
    )

    # Run B: SAME z0 but a hot asymmetric investment seed — distributor 2's seeded
    # x_inv = 0.3 gives distributor 1 free pooled headroom in sweep 1 (z_1 <=
    # 2*(x_inv_1 + 0.3)), so distributor 1's FIRST best-response reaches its
    # unconstrained optimum z_1 = 0.7 (needing only x_inv_1 = 0.05), and the run
    # settles on the genuinely DIFFERENT asymmetric equilibrium z ≈ [0.7, 0.0]
    # (distributor 2 is then forced to hold x_inv_2 = 0.3 just to keep distributor
    # 1's pinned 0.7 deliverable, leaving z_2 <= 0 — the free-riding structure).
    # BEFORE the CR-01 fix the seed never entered the shared model's state, so this
    # run was bitwise identical to run A — this regression pins seed-liveness and
    # can never regress silently.
    result_hot = run_nash!(
        build_toy_specs(),
        build_toy_shared();
        z0 = zeros(2, 1),
        x_inv0 = [0.0, 0.3],
        tol_outer = 1e-4,
        max_sweeps = 50,
        checkpoint_dir = mktempdir(),
    )

    @test result_cold.converged
    @test result_hot.converged

    # Distinct sweep-1 trajectories: the FIRST trace row is distributor 1's own
    # sweep-1 best-response in both runs (forward order), and it must see the seed —
    # cold: residual = max(|0.6 - 0|, 0.3) = 0.6; hot: max(|0.7 - 0|, 0.05) = 0.7.
    @test result_cold.trace.sweep_trace[1] == 1
    @test result_hot.trace.sweep_trace[1] == 1
    @test result_cold.trace.distributor_trace[1] == 1
    @test result_hot.trace.distributor_trace[1] == 1
    @test !isapprox(
        result_cold.trace.nash_residual_trace[1],
        result_hot.trace.nash_residual_trace[1];
        atol = 1e-3,
    )

    # ...and the CONVERGED equilibria themselves differ — the seed dimension of the
    # probe matrix is live (a seed-dependent equilibrium IS detectable), exactly what
    # NASH-04's honesty gate exists to guarantee.
    @test isapprox(result_cold.z, [0.6, 0.6]; atol = 1e-3)
    @test isapprox(result_cold.x_inv, [0.3, 0.3]; atol = 1e-3)
    @test isapprox(result_hot.z, [0.7, 0.0]; atol = 1e-3)
    @test isapprox(result_hot.x_inv, [0.05, 0.3]; atol = 1e-3)
    @test maximum(abs.(result_cold.z .- result_hot.z)) > 0.05

    # Run C (WR-05): differs from run B ONLY in z0 — the SAME explicit x_inv0 — so any
    # trajectory/equilibrium fork between B and C can come ONLY from the z-Parameter
    # half of the seed commit (`set_parameter_value.(shared.z[j,:], z0[j,:])` inside
    # run_nash!'s pre-sweep write_back! loop), the exact dimension run_nash_probe
    # varies. NOTE a hot-z0 run with the DERIVED x_inv0 default cannot pin this: with
    # T = 1 the minimal derived investment x_inv0[j] = z0[j]/corridor_cap makes a
    # pinned neighbor's seeded consumption and seeded headroom cancel EXACTLY in the
    # pooled capacity row (z_1 + z0_2 <= cap*(x_1 + z0_2/cap)  ⇔  z_1 <= cap*x_1), so
    # every derived-default seed yields the cold run's sweep-1 feasible set whether or
    # not the z commit is live, and residuals differ only via the Julia-side z_prev —
    # which never touches the model. An explicit x_inv0 with NON-minimal support is
    # what breaks the cancellation.
    #
    # Here distributor 2's seeded flow 0.6 consumes ALL the pooled headroom its seeded
    # investment provides (corridor_cap * 0.3 = 0.6), so distributor 1's sweep-1
    # best-response collapses back to z_1 <= 2*x_inv_1: BR (z, x_inv) = (0.6, 0.3),
    # residual max(|0.6 - 0|, 0.3) = 0.6 — vs run B's 0.7, where the same pinned 0.3
    # is UNCONSUMED headroom and lets distributor 1 reach its unconstrained optimum
    # 0.7. If a refactor dropped (or reordered around) the z-Parameter commit while
    # keeping the investment pinning, distributor 1 would see z_2 = 0 at pins
    # [_, 0.3] and run C would replay run B EXACTLY — sweep-1 residual 0.7 and
    # free-riding equilibrium [0.7, 0.0] — so BOTH assertion families below fail
    # loudly on precisely that partial-CR-01 recurrence. (Full deletion of the seed
    # loop is already pinned by run B's own assertions above.)
    result_hotz = run_nash!(
        build_toy_specs(),
        build_toy_shared();
        z0 = [0.0; 0.6;;],
        x_inv0 = [0.0, 0.3],
        tol_outer = 1e-4,
        max_sweeps = 50,
        checkpoint_dir = mktempdir(),
    )
    @test result_hotz.converged
    @test result_hotz.trace.sweep_trace[1] == 1
    @test result_hotz.trace.distributor_trace[1] == 1

    # EXACT sweep-1 residual values, not mere pairwise inequality: 0.6 is reachable
    # only when distributor 1's first best-response genuinely sees z_2 = 0.6 inside
    # the shared model (dead z commit ⇒ 0.7 here, identical to run B).
    @test isapprox(result_hot.trace.nash_residual_trace[1], 0.7; atol = 1e-3)
    @test isapprox(result_hotz.trace.nash_residual_trace[1], 0.6; atol = 1e-3)
    @test !isapprox(
        result_hot.trace.nash_residual_trace[1],
        result_hotz.trace.nash_residual_trace[1];
        atol = 1e-3,
    )

    # ...and the reached equilibria fork on z0 ALONE: run B (z0 = 0) free-rides to
    # [0.7, 0.0]; run C (z0 = [0, 0.6], same x_inv0) settles on the symmetric
    # [0.6, 0.6] — the z-Parameter seed dimension is live end-to-end.
    @test isapprox(result_hotz.z, [0.6, 0.6]; atol = 1e-3)
    @test isapprox(result_hotz.x_inv, [0.3, 0.3]; atol = 1e-3)
    @test maximum(abs.(result_hot.z .- result_hotz.z)) > 0.05

    # Seed-consistency guards: an over-ceiling x_inv0 entry and a capacity-infeasible
    # (z0, x_inv0) pair must both fail loudly BEFORE any solve.
    @test_throws ArgumentError run_nash!(
        build_toy_specs(),
        build_toy_shared();
        z0 = zeros(2, 1),
        x_inv0 = [0.0, 0.4],   # > x_inv_max[2] = 0.3
        checkpoint_dir = mktempdir(),
    )
    @test_throws ArgumentError run_nash!(
        build_toy_specs(),
        build_toy_shared();
        z0 = fill(0.7, 2, 1),  # seeded flow sum 1.4 ...
        x_inv0 = [0.1, 0.1],   # ... but pooled seeded capacity only 2*(0.2) = 0.4
        checkpoint_dir = mktempdir(),
    )
end

# Phase 30 code review iteration 2 (CR-01): run_nash! must keep its pre-Phase-30
# fail-loud semantics by default (inexact_policy = :strict, forwarded to every inner
# solve_stackelberg!), and when a caller opts into :certify_incumbent every best
# response's exactness certificate must be surfaced on the result, never dropped.
#
# FIXTURE (measured 2026-10-01, scratchpad fix2/probe_nash.jl): the single-Thermostatic
# T=1 IEEE-13 population at λ₀ = [-1.0] from test_planning_inexact_policy.jl's CR-02
# item, duplicated into an N=2 symmetric Nash game (build_shared_transmission needs
# N >= 2). Every feasible pin above the 0.01 load is SOCP-inexact there, so each best
# response sits at the inexact box corner z = y_max = 0.04. Measured: :strict throws the
# exactness gate's own "SOCP relaxation INEXACT" error inside sweep 1; :certify_incumbent
# converges in 2 sweeps (~13 s) with z = [0.04, 0.04] and all 4 certificates :inexact
# (incumbent maxgap 1.74e-2).
@testitem "planning nash: inexact_policy defaults to :strict and certificates surface relaxation-only best responses (CR-01)" tags =
    [:planning] begin
    using TSODSO

    T = 1
    feeder = TSODSO.ieee13_modified()
    therm =
        TSODSO.Thermostatic(2, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, fill(25.0, T))
    agg = TSODSO.Aggregator(2, 0.9, [therm], fill(0.01, T))
    mk() = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 1.0,
        x_inv_max = [0.2, 0.2],
        c_inv = [0.01, 0.01],
        c_op = [[0.01], [0.01]],
    )
    # α_x_lb must be explicit: a DistributorView follower has no sound α_x_lb derivation.
    spec = (;
        feeder,
        pf = ConvexBranchFlow(),
        aggregators = [agg],
        λ₀ = [-1.0],
        master_kwargs = (; c_y = 0.01, y_max = 0.04, α_x_lb = 0.0),
    )
    specs = [spec, spec]

    function caught(f)
        try
            f()
            return nothing
        catch e
            return e
        end
    end

    # Bogus policy: rejected at run_nash!'s own boundary, before any solve.
    @test_throws ArgumentError run_nash!(
        specs,
        mk();
        z0 = zeros(2, 1),
        checkpoint_dir = mktempdir(),
        inexact_policy = :ignore,
    )

    # Default (:strict): the pre-Phase-30 loud failure, with the gate's own message.
    e = caught(() -> run_nash!(specs, mk(); z0 = zeros(2, 1), checkpoint_dir = mktempdir()))
    @test e isa CertificateError
    @test occursin("SOCP relaxation INEXACT", e.msg)

    # Opt-in :certify_incumbent: converges, and the certificate is carried through.
    r = run_nash!(
        specs,
        mk();
        z0 = zeros(2, 1),
        checkpoint_dir = mktempdir(),
        inexact_policy = :certify_incumbent,
    )
    @test r.converged
    @test length(r.certificates) == r.sweeps * 2
    @test all(
        c -> c.incumbent_exactness === :inexact && c.ub_relaxation_only,
        r.certificates,
    )
    @test all(c -> c.ac_report !== nothing, r.certificates)
    @test r.any_relaxation_only
    @test [(c.sweep, c.distributor) for c in r.certificates] == [(k, i) for k in 1:(r.sweeps) for i in 1:2]
end

# --- Task 2 (plan 31-03, BILEV-06b): solve_variational_equilibrium — monolithic joint
# model for the variational equilibrium (VE), run on the interior-cap fixture's own GNE
# continuum (see the testitem above for the HAND-DERIVED GNE INTERVAL derivation this
# section reuses verbatim: S_min = 0.7, x_inv_1 ∈ [0, 0.7], z_1 ≈ z_2 ≈ 0.7).
#
# CORRECTED by the Phase-31 code review (CR-02; iteration-2 WR-01): on THIS symmetric
# fixture the VE is NOT unique. With c_inv = [1, 1] the joint objective and every
# constraint depend on x_inv only through x_inv_1 + x_inv_2, so the joint optimal face is
# the whole split segment, and every point of the segment carries the SAME shared
# multiplier (interior x_i: c_inv = corridor_cap·μ_i ⇒ μ_i = 0.5; endpoint x_1 = 0:
# z-stationarity gives μ_1 = W'(0.7) − λ₀ − c_y − c_op = 0.5) — the segment is the VE
# set (a face, not a point). The GNE set is STRICTLY larger: it also contains the
# free-riding GNEs x_inv_j = 0, z_j = 1.2 − p, p ∈ [0, 0.5] with unequal multipliers,
# which the VE excludes — so the VE still selects, just not a single point. The point
# returned is solver-dependent (Clarabel's IPM lands on the analytic
# centre (0.35, 0.35)); the testitem below therefore asserts only what holds on the whole
# face. The UNIQUE-VE selection test is the asymmetric-c_inv testitem at the end of this
# file.

@testitem "planning nash: solve_variational_equilibrium on the symmetric interior-cap fixture returns A point of the non-unique VE face (a strict subset of the GNE set) — joint solve, shared multiplier 0.5, no-profitable-deviation (BILEV-06b, CR-02)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    using JuMP: value

    S_MIN = 0.7

    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    specs = [spec, spec]

    # Test 1 (certification core): the joint solve's own (x_inv_1, x_inv_2) sums to
    # S_min within the SAME atol=1e-3 the probe testitem above uses, and z ≈ (0.7, 0.7).
    ve = solve_variational_equilibrium(
        specs;
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [1.0, 1.0],
        c_inv = [1.0, 1.0],
        c_op = [[0.5], [0.5]],
    )
    @test isapprox(sum(ve.x_inv), S_MIN; atol = 1e-3)
    @test isapprox(ve.z, fill(0.7, 2, 1); atol = 1e-3)
    @test all(0.0 .<= ve.x_inv .<= 1.0 + 1e-6)

    # Test 2 (multiplier): exactly ONE shared row exists by construction (the
    # capacity[t] row is written ONCE, never per-distributor). Its multiplier is the
    # hand-derived 0.5 that EVERY GNE of this continuum shares (file comment above —
    # which is why this fixture cannot distinguish a VE from any other GNE). JuMP's
    # sign convention for a <= row in a Max model gives π_capacity = −0.5; measured
    # −0.4999999998.
    @test length(ve.π_capacity) == 1
    @test isapprox(ve.π_capacity, [-0.5]; atol = 1e-6)

    # Test 3 (no-profitable-deviation certification): build a FRESH SharedTransmission
    # with the SAME parameters, write_back! every distributor at the VE's own (x_inv, z),
    # then for EACH distributor run ONE best response via solve_stackelberg! (follower =
    # DistributorView) and confirm its own UB does NOT improve on (is not strictly less
    # than, beyond solver-noise tolerance) that distributor's own cost slice at the VE.
    shared_check = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [1.0, 1.0],
        c_inv = [1.0, 1.0],
        c_op = [[0.5], [0.5]],
    )
    for i in 1:2
        write_back!(shared_check, i, ve.z[i, :], ve.x_inv[i])
    end
    # MEASURED 2026-10-02 (scratchpad probe_ve_deviation.jl, this exact fixture): both
    # distributors' own best response matches the VE's own cost_per_distributor to
    # within ≈4.3e-8 (solver precision) — 1e-4 is a generous margin above that noise
    # floor, consistent with this fixture family's own atol=1e-3/1e-4 conventions.
    NO_DEVIATION_TOL = 1e-4
    for i in 1:2
        activate_distributor!(shared_check, i)
        result_i = solve_stackelberg!(
            specs[i].feeder,
            specs[i].pf,
            specs[i].aggregators;
            λ₀ = specs[i].λ₀,
            T = 1,
            follower_kwargs = NamedTuple(),
            master_kwargs = specs[i].master_kwargs,
            follower = DistributorView(shared_check, i),
            checkpoint_dir = mktempdir(),
        )
        @test result_i.UB >= ve.cost_per_distributor[i] - NO_DEVIATION_TOL
        # Re-pin distributor i back at its own VE point before checking the next
        # distributor (solve_stackelberg! leaves shared_check's own state at ITS best
        # response, not the VE — write_back! is a cheap Parameter/bound set, no re-solve).
        write_back!(shared_check, i, ve.z[i, :], ve.x_inv[i])
    end
end

@testitem "planning nash: solve_variational_equilibrium agrees with the corner-cap control's pinned unique equilibrium — VE and GNE coincide when the equilibrium IS unique (BILEV-06b)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    specs = [spec, spec]

    # Test 4 (control fixture, byte-identical structural sanity): the corner-cap fixture
    # (x_inv_max=[0.3,0.3]) has a UNIQUE equilibrium (testitem "N=2 Gauss-Seidel converges
    # to the hand-checked congested equilibrium" above), so VE and GNE coincide — the
    # SAME atol=1e-3 that pinned testitem uses.
    ve = solve_variational_equilibrium(
        specs;
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.3],
        c_inv = [1.0, 1.0],
        c_op = [[0.5], [0.5]],
    )
    @test isapprox(ve.z, fill(0.6, 2, 1); atol = 1e-3)
    @test isapprox(ve.x_inv, [0.3, 0.3]; atol = 1e-3)
    @test length(ve.π_capacity) == 1
    @test all(isfinite, ve.π_capacity)
end

# --- Phase 31 code review (CR-02): a fixture on which the VE is UNIQUE and genuinely
# SELECTS one point of a GNE continuum. On the symmetric interior-cap fixture above
# (c_inv = [1, 1]) the joint objective depends on x_inv only through x_inv_1 + x_inv_2,
# so every point of the split segment carries the SAME shared multiplier (0.5) — that
# segment is the (non-unique) VE set, strictly smaller than the GNE set, which also
# contains free-riding GNEs with unequal multipliers — and
# solve_variational_equilibrium returns a solver-dependent point of that face. Making investment cost ASYMMETRIC breaks the tie.
#
# HAND DERIVATION (T=1, corridor_cap=2, x_inv_max=[1,1], c_inv=[1.0,1.4],
# c_op=[0.5,0.5], c_y=0.3, λ₀=4, W(z)=6z−z²/2 per distributor, lossless two-bus feeder):
# player i's KKT, with μ_i >= 0 its own multiplier on the shared row
# z_1 + z_2 <= 2(x_1 + x_2) and y_i = z_i at the optimum:
#   z-stationarity:  W'(z_i) − λ₀ − c_y − c_op = μ_i   ⇒  z_i = 1.2 − μ_i
#   x-stationarity:  c_inv_i − 2μ_i >= 0, with equality if x_i > 0.
# GNE set (shared row binding): any μ with μ_i = c_inv_i/2 for an investing player and
# μ_i <= c_inv_i/2 for a non-investing one — e.g. x_2 = 0, μ_1 = 0.5, μ_2 = p ∈ [0, 0.7],
# x_1 = (1.9 − p)/2 ∈ [0.6, 0.95]: a 1-D continuum with player-specific multipliers.
# VE (equal multipliers μ_1 = μ_2 = μ): the joint problem buys capacity only from the
# CHEAPER player 1 (marginal capacity cost c_inv_1/corridor_cap = 0.5 < 0.7), so
# μ = 0.5, z = (0.7, 0.7), x_inv = (0.7, 0.0), y = (0.7, 0.7) — UNIQUE (strictly concave
# W fixes z; c_inv_1 < c_inv_2 fixes the split). cost_per_distributor =
# c_y·y + c_inv·x + c_op·z − (W(z) − λ₀z) = [0.105, −0.595].
# Gauss-Seidel from z0 = 0 (either order) instead lands on the GNE x_inv = (0.35, 0.25),
# z = (0.7, 0.5), μ = (0.5, 0.7): player 2, moving against player 1's committed
# capacity, pays its own 0.7 marginal — a GNE that is NOT the VE.
@testitem "planning nash: solve_variational_equilibrium selects the UNIQUE VE on an asymmetric-c_inv fixture — hand-derived split, equal per-player shared multipliers, distinct from the diagonalization's GNE (CR-02)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    using JuMP: value

    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = Phase6Fixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
    )
    specs = [spec, spec]
    C_INV = [1.0, 1.4]
    C_OP = [[0.5], [0.5]]
    C_Y = 0.3
    fresh_shared() = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [1.0, 1.0],
        c_inv = C_INV,
        c_op = C_OP,
    )

    # Player i's OWN shared-row multiplier at a best response z_i, from z-stationarity
    # (header): μ_i = −π_oracle − c_y − c_op, where π_oracle = dual of the oracle's
    # coupling row = −(W'(z) − λ₀). Read from the ORACLE, not the follower LP: at the
    # VE player 2 sits on the kink x_2 = 0 of its follower value function, where the
    # follower's capacity dual is degenerate (measured 0.0 for player 2 vs −0.5 for
    # player 1 on the SAME row) and so carries no multiplier information.
    function own_multiplier(z_i)
        oracle = TSODSO.build_planning_oracle(
            spec.feeder,
            spec.pf,
            spec.aggregators;
            λ₀ = spec.λ₀,
            T = 1,
        )
        return -solve_planning_oracle!(oracle, z_i).π[1] - C_Y - C_OP[1][1]
    end

    ve = solve_variational_equilibrium(
        specs;
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [1.0, 1.0],
        c_inv = C_INV,
        c_op = C_OP,
    )
    # MEASURED 2026-10-02 (Clarabel IPM): every quantity below within ~1.1e-9 of the
    # hand-derived value; atol = 1e-6 is a ~1000x margin that still rejects any other
    # GNE of the continuum (x_inv_1 ∈ [0.6, 0.95] there).
    VE_ATOL = 1e-6
    @test isapprox(ve.x_inv, [0.7, 0.0]; atol = VE_ATOL)
    @test isapprox(ve.z, fill(0.7, 2, 1); atol = VE_ATOL)
    @test isapprox(ve.y, [0.7, 0.7]; atol = VE_ATOL)
    # JuMP's sign convention for a <= row in a Max model: π_capacity = −μ.
    @test isapprox(ve.π_capacity, [-0.5]; atol = VE_ATOL)
    @test isapprox(ve.cost_per_distributor, [0.105, -0.595]; atol = VE_ATOL)

    # Each player's OWN shared-row multiplier from a run_nash!-style best response
    # (solve_stackelberg! with follower = DistributorView, the other player pinned at
    # the VE) equals −π_capacity: the VE's defining property, checked per player
    # against the joint solve's single multiplier. NOTE (iteration-2 review, IN-01):
    # own_multiplier(z) = 1.2 − z is a fixed function of z on this fixture, so this
    # check is a REPARAMETRIZATION of the `z ≈ 0.7` assertion (same BR_ATOL), not
    # independent evidence — it documents the identification μ_i ↔ z-stationarity and
    # ties it to the joint solve's −π_capacity, nothing more. The same holds for
    # μ_gne ≈ (0.5, 0.7) below, which equals gne.z ≈ (0.7, 0.5). MEASURED: player 1's Benders best
    # response stops at z_1 = 0.69979 (inside its 1e-6 relative UB gap on a flat
    # optimum), giving μ_1 = 0.50021 — BR_ATOL = 1e-3 is ~5x that.
    BR_ATOL = 1e-3
    shared_check = fresh_shared()
    for i in 1:2
        write_back!(shared_check, i, ve.z[i, :], ve.x_inv[i])
    end
    for i in 1:2
        activate_distributor!(shared_check, i)
        result_i = solve_stackelberg!(
            specs[i].feeder,
            specs[i].pf,
            specs[i].aggregators;
            λ₀ = specs[i].λ₀,
            T = 1,
            follower_kwargs = NamedTuple(),
            master_kwargs = specs[i].master_kwargs,
            follower = DistributorView(shared_check, i),
            checkpoint_dir = mktempdir(),
        )
        @test isapprox(result_i.z, ve.z[i, :]; atol = BR_ATOL)
        @test isapprox(result_i.UB, ve.cost_per_distributor[i]; atol = 1e-4)
        @test isapprox(own_multiplier(result_i.z), -ve.π_capacity[1]; atol = BR_ATOL)
        write_back!(shared_check, i, ve.z[i, :], ve.x_inv[i])
    end

    # The diagonalization's GNE is NOT the VE: hand-derived x_inv = (0.35, 0.25),
    # z = (0.7, 0.5), μ = (0.5, 0.7). MEASURED: z = (0.69971, 0.49959), x_inv =
    # (0.34985, 0.24980) — inner-Benders flatness again, so BR_ATOL applies.
    gne = run_nash!(
        specs,
        fresh_shared();
        z0 = zeros(2, 1),
        tol_outer = 1e-4,
        max_sweeps = 20,
        checkpoint_dir = mktempdir(),
    )
    @test gne.converged
    @test isapprox(gne.x_inv, [0.35, 0.25]; atol = BR_ATOL)
    @test isapprox(gne.z, reshape([0.7, 0.5], 2, 1); atol = BR_ATOL)
    μ_gne = [own_multiplier(gne.z[i, :]) for i in 1:2]
    @test isapprox(μ_gne, [0.5, 0.7]; atol = BR_ATOL)
    @test abs(μ_gne[2] - μ_gne[1]) > 0.1   # unequal multipliers: a GNE, not the VE
    @test maximum(abs.(gne.x_inv .- ve.x_inv)) > 0.3
end
