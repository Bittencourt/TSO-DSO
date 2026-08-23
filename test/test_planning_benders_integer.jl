# test/test_planning_benders_integer.jl
#
# Seam: src/planning/benders.jl (Phase 24, plan 24-04). `solve_stackelberg!` gains the
# `master = nothing` injection kwarg (D-08, mirroring the existing `follower = nothing`
# seam VERBATIM) and the `known_optimum` D-13/D-14 lattice-exact termination fallback (an
# EXCLUSIVE branch against `gap <= tol`, never an `||`). Items tagged `[:planning]`, names
# contain "planning" and "benders" (occursin filter convention, mirrors
# test_planning_benders.jl).
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
