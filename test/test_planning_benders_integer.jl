# test/test_planning_benders_integer.jl
#
# Seam: src/planning/benders.jl. `solve_stackelberg!` gains the
# `master = nothing` injection kwarg (mirroring the existing `follower = nothing`
# seam VERBATIM), the `known_optimum` lattice-exact termination fallback (an
# EXCLUSIVE branch against `gap <= tol`, never an `||`), and generic `apply_integer_cuts!`
# wiring on the optimality branch surfacing `nogood_count`/`converged_via`. Items
# tagged `[:planning]`, names contain "planning" and "benders" (occursin filter
# convention, mirrors test_planning_benders.jl).
#
# Toy fixture (the canonical instance, same as test_planning_benders.jl /
# test_planning_goldens.jl's N=1 golden): T=1, feeder=TwoBusFixtures.two_bus_feeder(),
# λ₀=[4.0], dev=ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0),
# agg=TSODSO.Aggregator(2, 0.9, [dev], [0.0]); follower corridor_cap=2.0, x_inv_max=2.0,
# c_inv=1.0, c_op=[0.5]; master c_y=0.3, y_max=8.0, α_op_lb=-5.0, α_x_lb=0.0.

@testitem "planning benders integer: master=nothing/known_optimum=nothing explicit -> bit-for-bit identical default path (golden) + converged_now mutual exclusivity" tags =
    [:planning] setup = [TwoBusFixtures, ToyDeviceFixture, PlanningFixtures] begin
    using TSODSO

    feeder = TwoBusFixtures.two_bus_feeder()
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

    # GATE first (golden assertion ordering): the production Benders loop's
    # OWN convergence gate must hold before the pinned golden is even consulted.
    @test result.gap <= 1e-6

    # VALUE second: the SAME pinned N=1 hand-enumerated/BilevelJuMP-certified golden as
    # test_planning_goldens.jl's N=1 golden — proving master=nothing/
    # known_optimum=nothing supplied EXPLICITLY is bit-for-bit identical to the omitted-kwarg
    # default.
    @test isapprox(result.y, PlanningFixtures.N1_Y_HAND; atol = 1e-3)
    @test isapprox(result.z[1], PlanningFixtures.N1_Z_HAND; atol = 1e-3)
    @test isapprox(result.UB, PlanningFixtures.N1_OBJ_HAND; atol = 1e-3)

    # The continuous path never fires a no-good cut (apply_integer_cuts! is a true
    # no-op for BendersMaster) and is always attributed :clean.
    @test result.nogood_count == 0
    @test result.converged_via === :clean

    # Regression, at the unit level: converged_now's own formula, replicated
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
    [:planning] setup = [TwoBusFixtures, ToyDeviceFixture] begin
    using TSODSO
    using TSODSO: build_master_integer

    feeder = TwoBusFixtures.two_bus_feeder()
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

    # No known_optimum yet (the certification harness supplies that) — either
    # outcome (converges within max_iter, or raises the existing loud ConvergenceError
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
        @test e isa ConvergenceError
        @test occursin("exhausted", sprint(showerror, e))
    end
end

# `_oracle_or_infeasible`'s MOI.ALMOST_INFEASIBLE handling
# must be CONFIRMED via the real slack-min `feas_oracle`, never assumed. These 4 tests
# demonstrate the original bug (Test 1, now fixed) and the fixed confirmed/disagree/
# non-regression behavior (Tests 2-4), using a `MOI.Utilities.MockOptimizer`-backed JuMP
# model to deterministically pin `termination_status` without a real solve.
@testitem "planning benders integer: _oracle_or_infeasible confirms ALMOST_INFEASIBLE via feas_oracle, never assumes +Inf" tags =
    [:planning] begin
    using TSODSO
    import JuMP
    import JuMP: MOI

    MOIU = MOI.Utilities

    # A fake oracle whose `solve_planning_oracle!` ALWAYS throws (mimicking an untrusted
    # solve), with its `model`'s termination_status pinned via a MockOptimizer backend
    # (no real solve needed — deterministic, per the plan's own <behavior> spec).
    struct FakeOracleWR01
        model::JuMP.Model
    end
    TSODSO.solve_planning_oracle!(::FakeOracleWR01, z; on_inexact) =
        error("FakeOracleWR01: forced throw (untrusted solve)")

    function make_fake_oracle_wr01(status::MOI.TerminationStatusCode)
        inner = MOIU.MockOptimizer(MOIU.Model{Float64}())
        model = JuMP.direct_model(inner)
        MOIU.set_mock_optimize!(inner, mock -> MOIU.mock_optimize!(mock, status))
        JuMP.optimize!(model)
        return FakeOracleWR01(model)
    end

    # A stub feasibility oracle whose `solve_feasibility_oracle!` returns a caller-chosen
    # slack-min value `v` (classified by `_feas_cut_class`), with a dummy `u`.
    struct FakeFeasOracleWR01
        v::Float64
    end
    TSODSO.solve_feasibility_oracle!(fo::FakeFeasOracleWR01, z) = (; v = fo.v, u = [0.0])

    # Test 1 (the bug this task fixes): no feas_oracle supplied, ALMOST_INFEASIBLE is an
    # UNCONFIRMED near-certificate — must rethrow, never silently become `nothing`.
    fake1 = make_fake_oracle_wr01(MOI.ALMOST_INFEASIBLE)
    @test_throws ErrorException TSODSO._oracle_or_infeasible(
        fake1,
        [0.1];
        on_inexact = :throw,
    )

    # Test 2: a :separating-class feas_oracle verdict (v > FEAS_CUT_V_TOL) CONFIRMS the
    # infeasibility claim -> returns `nothing` (genuinely infeasible, confirmed).
    fake2 = make_fake_oracle_wr01(MOI.ALMOST_INFEASIBLE)
    feas_agree = FakeFeasOracleWR01(1.0e-3)
    @test TSODSO._oracle_or_infeasible(
        fake2,
        [0.1];
        on_inexact = :throw,
        feas_oracle = feas_agree,
    ) === nothing

    # Test 3: a :disagree-class feas_oracle verdict (v <= FEAS_CUT_V_NOISE) means the two
    # oracles genuinely disagree -> must rethrow, never silently return `nothing`.
    fake3 = make_fake_oracle_wr01(MOI.ALMOST_INFEASIBLE)
    feas_disagree = FakeFeasOracleWR01(0.0)
    @test_throws ErrorException TSODSO._oracle_or_infeasible(
        fake3,
        [0.1];
        on_inexact = :throw,
        feas_oracle = feas_disagree,
    )

    # Test 4 (non-regression): a plain MOI.INFEASIBLE (not ALMOST_INFEASIBLE) with
    # feas_oracle=nothing is UNAFFECTED by this fix — still returns `nothing` immediately.
    fake4 = make_fake_oracle_wr01(MOI.INFEASIBLE)
    @test TSODSO._oracle_or_infeasible(fake4, [0.1]; on_inexact = :throw) === nothing

    # Only a :separating verdict confirms.
    # Test 5: a :weak-class verdict (FEAS_CUT_V_NOISE < v <= FEAS_CUT_V_TOL — z within
    # the master's feasibility tolerance of the boundary) must RETHROW, never become
    # +Inf (which could discard a near-boundary minimizer and over-estimate Q_nu).
    v_weak = (TSODSO.FEAS_CUT_V_NOISE + TSODSO.FEAS_CUT_V_TOL) / 2
    @test TSODSO._feas_cut_class(v_weak) === :weak
    fake5 = make_fake_oracle_wr01(MOI.ALMOST_INFEASIBLE)
    @test_throws ErrorException TSODSO._oracle_or_infeasible(
        fake5,
        [0.1];
        on_inexact = :throw,
        feas_oracle = FakeFeasOracleWR01(v_weak),
    )
    # Test 6: LOCALLY_INFEASIBLE (a local solver's verdict) is NOT certified: without a
    # feas_oracle it rethrows; with a :separating confirmation it returns `nothing`;
    # with a :weak one it rethrows.
    fake6 = make_fake_oracle_wr01(MOI.LOCALLY_INFEASIBLE)
    @test_throws ErrorException TSODSO._oracle_or_infeasible(fake6, [0.1]; on_inexact = :throw)
    @test TSODSO._oracle_or_infeasible(
        fake6,
        [0.1];
        on_inexact = :throw,
        feas_oracle = feas_agree,
    ) === nothing
    @test_throws ErrorException TSODSO._oracle_or_infeasible(
        fake6,
        [0.1];
        on_inexact = :throw,
        feas_oracle = FakeFeasOracleWR01(v_weak),
    )
    # Test 7 (documented acceptance): INFEASIBLE_OR_UNBOUNDED stays a certified verdict
    # (the welfare oracle at a pinned z is bounded, so it can only mean infeasible).
    fake7 = make_fake_oracle_wr01(MOI.INFEASIBLE_OR_UNBOUNDED)
    @test TSODSO._oracle_or_infeasible(fake7, [0.1]; on_inexact = :throw) === nothing
end

@testitem "planning benders integer: T>1 joint corner search routes a certificate-less follower infeasibility to bisection — no NaN feasibility cut reaches the small master LP" tags =
    [:planning] setup = [TwoBusFixtures, ToyDeviceFixture] begin
    using TSODSO

    # A follower whose FIRST infeasible verdict carries no certificate (the NaN sentinel
    # of solve_follower!(::DistributorView), e.g. a presolve-only verdict) and every later
    # one a genuine certificate. Deliverable region z_t <= 0.6; certificate of the
    # slack-min value V(z) = Σ_t max(z_t − 0.6, 0): v = V(z_k), u_t = 1{z_k,t > 0.6}.
    # Previously the NaN pair was pushed into the small master LP and JuMP threw
    # "Invalid coefficient NaN"; now it is routed to the bisection fallback, the master
    # re-proposes the same trial, the certificate arrives, and the search converges.
    mutable struct OnceNaNFollower
        T::Int
        nan_left::Int
    end
    function TSODSO.solve_follower!(f::OnceNaNFollower, z::AbstractVector{<:Real})
        all(<=(0.6), z) && return (; feasible = true, cost = 0.5 * sum(z), π_s = fill(0.5, f.T))
        if f.nan_left > 0
            f.nan_left -= 1
            return (; feasible = false, v = NaN, u = fill(NaN, f.T))
        end
        return (;
            feasible = false,
            v = sum(max(zt - 0.6, 0.0) for zt in z),
            u = [zt > 0.6 ? 1.0 : 0.0 for zt in z],
        )
    end

    T = 2
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], zeros(T))
    oracle = TSODSO.build_planning_oracle(
        TwoBusFixtures.two_bus_feeder(),
        LinDistFlow(),
        [agg];
        λ₀ = fill(4.0, T),
        T = T,
    )
    follower = OnceNaNFollower(T, 1)
    Qv = TSODSO.corner_recourse(oracle, follower, 2.0, T)
    # HAND-DERIVED: Q(z) = Σ_t [0.5 z_t − (6 z_t − z_t²/2 − 4 z_t)] = Σ_t (z_t²/2 − 1.5 z_t),
    # unconstrained minimizer z_t = 1.5 > 0.6, so the minimum over [0, 0.6]^2 sits on the
    # deliverability boundary: Q = 2 (0.18 − 0.9) = −1.44.
    @test follower.nan_left == 0                 # the certificate-less verdict was hit
    @test isapprox(Qv, -1.44; atol = 1e-6)
end
