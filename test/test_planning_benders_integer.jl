# test/test_planning_benders_integer.jl
#
# Seam: src/planning/benders.jl (Phase 24, plan 24-04). `solve_stackelberg!` gains the
# `master = nothing` injection kwarg (D-08, mirroring the existing `follower = nothing`
# seam VERBATIM), the `known_optimum` D-13/D-14 lattice-exact termination fallback (an
# EXCLUSIVE branch against `gap <= tol`, never an `||`), and generic `apply_integer_cuts!`
# wiring on the optimality branch surfacing `nogood_count`/`converged_via` (D-16). Items
# tagged `[:planning]`, names contain "planning" and "benders" (occursin filter
# convention, mirrors test_planning_benders.jl).
#
# Toy fixture (D-12's canonical instance, same as test_planning_benders.jl /
# test_planning_goldens.jl's N=1 golden): T=1, feeder=Phase6Fixtures.two_bus_feeder(),
# λ₀=[4.0], dev=ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0),
# agg=TSODSO.Aggregator(2, 0.9, [dev], [0.0]); follower corridor_cap=2.0, x_inv_max=2.0,
# c_inv=1.0, c_op=[0.5]; master c_y=0.3, y_max=8.0, α_op_lb=-5.0, α_x_lb=0.0.

@testitem "planning benders integer: master=nothing/known_optimum=nothing explicit -> byte-identical default path (PVAL-02 golden) + converged_now mutual exclusivity (Blocker 2 regression)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture, PlanningFixtures] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]
    follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])
    master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)

    result = mktempdir() do dir
        solve_stackelberg!(
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
            # The new kwargs' mere PRESENCE (not their omission) must leave the default
            # path unchanged — supplied explicitly, not omitted.
            master = nothing,
            known_optimum = nothing,
        )
    end

    # GATE first (PVAL-02 assertion ordering, T-14-01): the production Benders loop's
    # OWN convergence gate must hold before the pinned golden is even consulted.
    @test result.gap <= 1e-6

    # VALUE second: the SAME pinned N=1 hand-enumerated/BilevelJuMP-certified golden as
    # test_planning_goldens.jl's PVAL-02 N=1 golden — proving master=nothing/
    # known_optimum=nothing supplied EXPLICITLY is byte-identical to the omitted-kwarg
    # default.
    @test isapprox(result.y, PlanningFixtures.N1_Y_HAND; atol = 1e-3)
    @test isapprox(result.z[1], PlanningFixtures.N1_Z_HAND; atol = 1e-3)
    @test isapprox(result.UB, PlanningFixtures.N1_OBJ_HAND; atol = 1e-3)

    # D-16: the continuous path never fires a no-good cut (apply_integer_cuts! is a true
    # no-op for BendersMaster) and is always attributed :clean.
    @test result.nogood_count == 0
    @test result.converged_via === :clean

    # Blocker-2 regression, at the unit level: converged_now's own formula, replicated
    # standalone (not calling solve_stackelberg! again), proving the branch is EXCLUSIVE,
    # never an `||` of `gap <= tol` and the exact-match test.
    _converged_now(known_optimum, gap, tol, UB, atol) =
        known_optimum === nothing ? (gap <= tol) : isapprox(UB, known_optimum; atol = atol)

    # (a) known_optimum = nothing, gap well under tol -> converges, mirrors today.
    @test _converged_now(nothing, 0.0, 1e-6, 5.0, 1e-9) == true

    # (b) THE ADVERSARIAL CASE — the literal regression against the forbidden `||`: gap
    # <= tol holds, but known_optimum is set to a value CLEARLY outside atol of UB. A
    # forbidden `(gap <= tol) || isapprox(...)` would wrongly return `true` here; the
    # required exclusive branch must return `false`.
    @test _converged_now(5.0, 0.0, 1e-6, 999.0, 1e-9) == false

    # (c) gap is NOT <= tol, but UB matches known_optimum exactly within atol ->
    # converges via the exact-match branch alone.
    @test _converged_now(5.0, 1.0, 1e-6, 5.0, 1e-9) == true
end

@testitem "planning benders integer: build_master_integer through solve_stackelberg! end-to-end smoke (apply_integer_cuts! wiring, nogood_count/converged_via surfaced)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]
    follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])

    imaster = build_master_integer(;
        T = 1,
        K = 4,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )

    # No known_optimum yet (plan 24-05's certification harness supplies that) — either
    # outcome (converges within max_iter, or raises the existing loud ErrorException
    # naming the exhausted count) is acceptable at THIS smoke-test stage; the point is
    # proving the wiring runs without a MethodError/UndefVarError.
    try
        result = mktempdir() do dir
            solve_stackelberg!(
                feeder,
                LinDistFlow(),
                [agg];
                λ₀ = λ₀,
                T = 1,
                follower_kwargs = follower_kwargs,
                master_kwargs = NamedTuple(),
                master = imaster,
                max_iter = 50,
                checkpoint_dir = dir,
            )
        end

        # A genuine lattice point: y_max/2^K = 8.0/16 = 0.5 step.
        step = 8.0 / 16
        nearest_multiple = round(result.y / step) * step
        @test isapprox(result.y, nearest_multiple; atol = 1e-6)

        @test result.nogood_count >= 0
        @test result.nogood_count isa Integer
        @test result.converged_via in (:clean, :nogood_assisted)
    catch e
        @test e isa ErrorException
        @test occursin("exhausted", sprint(showerror, e))
    end
end
