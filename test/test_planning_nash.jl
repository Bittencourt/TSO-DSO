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
        @test err isa ErrorException
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

    build_shared = () -> build_shared_transmission(;
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

    build_shared = () -> build_shared_transmission(;
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

    build_shared = () -> build_shared_transmission(;
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
    # — must raise ErrorException, propagated from the underlying run_nash!, never
    # caught/swallowed by run_nash_probe.
    @test_throws ErrorException run_nash_probe(
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

    build_shared = () -> build_shared_transmission(;
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
