# test/test_planning_nash_integer.jl
#
# Seam: src/planning/nash.jl's `run_nash!` new `integer::Union{Nothing,NamedTuple} =
# nothing` kwarg — threading genuine binary-expansion
# integer investment (`src/planning/master_integer.jl`'s `build_master_integer`)
# through the N-distributor Gauss-Seidel diagonalization. Items tagged `[:planning]`,
# names contain "planning" and "nash" and "integer" (occursin filter convention, mirrors
# `test/test_planning_benders_integer.jl`).
#
# Fixture: the SAME N=2 corner-cap control fixture as
# `test/test_planning_nash.jl`'s own pinned continuous golden (T=1, corridor_cap=2.0,
# x_inv_max=[0.3,0.3], c_inv=[1.0,1.0], c_op=[[0.5],[0.5]], each distributor's own
# feeder=TwoBusFixtures.two_bus_feeder(), pf=LinDistFlow(),
# agg=ToyElasticDevice(2,6.0,1.0,10.0) wrapped in Aggregator(2,0.9,[dev],[0.0]),
# λ₀=[4.0], master_kwargs=(;c_y=0.3,y_max=8.0,α_op_lb=-5.0,α_x_lb=0.0)) — reused here
# with `K=4` (lattice step `y_max/2^K = 0.5`) so the known continuous equilibrium
# (z=[0.6,0.6], x_inv=[0.3,0.3]) is a documented reference point for where the INTEGER
# equilibrium is expected to land (the nearest lattice point at or below the continuous
# optimum). Unlike the continuous fixture, `master_kwargs` here carries ONLY `c_y`/
# `y_max`: the integer path REJECTS any other
# master_kwargs key (an α bound there used to be silently ignored); epigraph bounds go in
# `integer = (; K, α_op_lb, α_x_lb)` (defaults `:auto` and the sign-derived `0.0`).
#
# EMPIRICALLY MEASURED (2026-10-02, probe scripts under
# `julia --project=.`, no TestItemRunner): `run_nash!(specs, shared; z0=zeros(2,1),
# tol_outer=1e-4, max_sweeps=10, integer=(;K=4), checkpoint_dir=...)` converges in 2
# sweeps (~67s wall time for 4 best-responses total, each a K=4 MILP best response —
# noticeably slower than the continuous fixture's own sub-second convergence) to `z=[0.5,0.5]`, `x_inv=[0.25,0.25]`,
# `UB=[-0.225,-0.225]` (both distributors, by the fixture's own symmetry) — the nearest
# lattice point AT OR BELOW the continuous optimum `z=0.6` (lattice points are
# `{0,0.5,1.0,...,7.5}`; `0.5` is the largest point `<= 0.6`). The per-player
# brute-force sweep below (Test 2, the load-bearing item) independently confirms this is
# a genuine equilibrium — with a separately
# hand-written QP per lattice point, never production `corner_recourse`: diff between
# the reported `UB[i]` and the brute-forced best of all 16 lattice points is `2.2e-9`
# for BOTH distributors, and the equilibrium itself is pinned against its hand
# derivation (Test 1b).
#
# INFEASIBILITY FIX (found while developing this path):
# `solve_follower!(::DistributorView, ...)` (`src/planning/coupling.jl`)
# previously raised an un-named, generic `ErrorException` whenever HiGHS confirmed a
# genuine primal infeasibility (`MOI.INFEASIBLE`) via presolve WITHOUT ever computing a
# Farkas dual ray (`dual_status` stays `NO_SOLUTION`) — a real, previously-unreachable
# code path the `corner_recourse` ternary search (exploring trial `z` values far
# beyond what the shared model's own OTHER-distributor-pinned capacity ever permits)
# triggers routinely. Fixed by adding a third, additive branch, later refined (commit 381644a): a `MOI.INFEASIBLE` without a certificate first RE-SOLVES
# the shared model ONCE WITH PRESOLVE OFF (set and restored on the inner optimizer) and
# returns that solve's own trusted outcome — feasible, or a genuine certificate. Only if
# that still yields neither does it return the sentinel `(; feasible = false, v = NaN,
# u = fill(NaN, T))`. Callers never form a cut from the sentinel: `corner_recourse`'s
# ternary `Qfun` reads only `.feasible` (+Inf, as for a certificate-bearing infeasible
# trial); the `T > 1` `_corner_recourse_joint` routes a non-finite certificate to its
# depth-bounded bisection fallback; and `solve_stackelberg!`'s outer feasibility branch
# raises a NAMED error before `add_feasibility_cut!` (no cut can be formed there). See
# `src/planning/coupling.jl`'s `solve_follower!(::DistributorView, ...)` docstring for
# the full account.

@testitem "planning nash integer: N=2 run_nash! with integer=(;K=4) converges + per-player brute-force certification (no profitable unilateral deviation)" tags =
    [:planning] setup = [TwoBusFixtures, ToyDeviceFixture] begin
    using TSODSO
    import JuMP

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
        feeder = TwoBusFixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0),
    )
    specs = [spec, spec]
    z0 = zeros(2, 1)
    K = 4

    # Test 1 (wiring smoke test): `run_nash!` with the new
    # `integer` kwarg runs end-to-end — no MethodError/UndefVarError. Called WITHOUT a
    # try/catch, mirroring every OTHER Nash testitem's own "fail loud, no
    # try/catch around run_nash!" convention — empirically confirmed
    # (probes recorded in this file's header) to converge RELIABLY on this fixture,
    # so asserting convergence directly is the honest claim, not a hedge.
    result = run_nash!(
        specs,
        shared;
        z0 = z0,
        tol_outer = 1e-4,
        max_sweeps = 10,
        integer = (; K = K),
        checkpoint_dir = mktempdir(),
    )
    @test result.converged

    # Test 1b: PIN the hand-derived lattice equilibrium.
    # Player i's cost at master lattice point y (step y_max/2^K = 0.5), the other
    # player j pinned at (z_j, x_inv_j): the pooled row z_i + z_j <= 2(x_i + x_j) with
    # x_i <= 0.3 caps z_i at 0.6 + 2x_j − z_j, and the follower's cheapest support is
    # x_i = (z_i + z_j)/2 − x_j. With the oracle welfare W(z) − λ₀z = 6z − z²/2 − 4z:
    #   cost_i(y) = c_y·y + min_{0 <= z <= min(y, cap)} [c_inv·x_i(z) + c_op·z − (2z − z²/2)]
    # At the symmetric candidate (z_j, x_j) = (0.5, 0.25): x_i(z) = z/2, so the bracket
    # is z²/2 − z, decreasing on [0, 1] — z_i = min(y, 0.6). Lattice: y = 0 → 0;
    # y = 0.5 → 0.15 + (0.125 − 0.5) = −0.225; y = 1.0 → 0.3 + (0.18 − 0.6) = −0.12;
    # every larger y adds 0.15 per step at the same z = 0.6. Unique argmin y = 0.5:
    # z_i = 0.5, x_inv_i = 0.25, UB_i = −0.225 for both players — a Nash equilibrium of
    # the lattice game. MEASURED: UB = −0.2249999999999959, z and x_inv exact.
    @test isapprox(result.z, fill(0.5, 2, 1); atol = 1e-9)
    @test isapprox(result.x_inv, [0.25, 0.25]; atol = 1e-9)
    @test isapprox(result.UB, [-0.225, -0.225]; atol = 1e-9)

    # Test 2 (brute-force certification, THE load-bearing item, made INDEPENDENT):
    # for EACH distributor i, hold the other player's (z_j, x_inv_j) at the
    # reported equilibrium and evaluate player i's FULL cost at every one of its 2^K = 16
    # lattice points with a FRESH, hand-written JuMP model per point (one solve each) —
    # never production `corner_recourse`, `build_planning_oracle`, `DistributorView` or
    # `SharedTransmission`, so a bug in the code under test cannot be reproduced on both
    # sides of the comparison. The model writes the toy economics directly: device
    # p ∈ [0, Pmax] with utility a·p − (b/2)p², lossless two-bus balance p == z (the
    # LinDistFlow two-bus feeder carries no active losses), master box 0 <= z <= y,
    # pooled row z + z_j <= corridor_cap·(x + x_j), 0 <= x <= x_inv_max.
    y_max = spec.master_kwargs.y_max
    c_y = spec.master_kwargs.c_y
    step = y_max / 2.0^K
    # MEASURED 2026-10-02: |UB[i] − brute-force best| = 2.2e-9 and the first three
    # lattice costs within 2.2e-9 of the hand values on this independent conic QP
    # (Clarabel interior-point accuracy; 2.2e-16 when the comparison reused
    # corner_recourse). NO_DEVIATION_TOL = 1e-6 is ~450x that and far below the smallest
    # lattice cost difference (0.105 between y = 0.5 and y = 1.0).
    NO_DEVIATION_TOL = 1.0e-6

    function independent_cost(y, z_j, x_j)
        m = JuMP.Model(TSODSO.select_optimizer(TSODSO.QP()))
        JuMP.@variable(m, 0 <= z <= y)
        JuMP.@variable(m, 0 <= x <= 0.3)
        JuMP.@variable(m, 0 <= p <= dev.Pmax)
        JuMP.@constraint(m, p == z)
        JuMP.@constraint(m, z + z_j <= 2.0 * (x + x_j))
        JuMP.@objective(
            m,
            Min,
            c_y * y + 1.0 * x + 0.5 * z - (dev.a * p - (dev.b / 2) * p^2 - spec.λ₀[1] * z),
        )
        JuMP.optimize!(m)
        @assert JuMP.is_solved_and_feasible(m)
        return JuMP.objective_value(m)
    end
    function brute_force(i)
        j = i == 1 ? 2 : 1
        costs = [independent_cost(step * idx, result.z[j, 1], result.x_inv[j]) for idx in 0:(2^K - 1)]
        return (; best = minimum(costs), argbest = argmin(costs) - 1, costs)
    end

    for i in 1:2
        bf = brute_force(i)
        @test bf.argbest == 1                                    # y = 0.5, hand-derived
        @test isapprox(bf.costs[1:3], [0.0, -0.225, -0.12]; atol = NO_DEVIATION_TOL)
        @test result.UB[i] <= bf.best + NO_DEVIATION_TOL         # no profitable deviation
        @test isapprox(result.UB[i], bf.best; atol = NO_DEVIATION_TOL)
    end
end

@testitem "planning nash integer: integer kwarg boundary guards (K must be a positive Integer; α_op_lb :auto or finite, α_x_lb finite; no silently ignored master_kwargs/integer keys, derived α_x_lb) — before any solve call" tags =
    [:planning] setup = [TwoBusFixtures, ToyDeviceFixture] begin
    using TSODSO

    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    spec = (;
        feeder = TwoBusFixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0),
    )
    specs = [spec, spec]
    z0 = zeros(2, 1)

    build_fresh_shared() = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.3],
        c_inv = [1.0, 1.0],
        c_op = [[0.5], [0.5]],
    )

    # K=0 is not a positive Integer.
    @test_throws ArgumentError run_nash!(
        specs,
        build_fresh_shared();
        z0 = z0,
        integer = (; K = 0),
        checkpoint_dir = mktempdir(),
    )
    # K as a Float64 (not an Integer) must also be rejected.
    @test_throws ArgumentError run_nash!(
        specs,
        build_fresh_shared();
        z0 = z0,
        integer = (; K = 4.0),
        checkpoint_dir = mktempdir(),
    )
    # α_x_lb must be finite.
    @test_throws ArgumentError run_nash!(
        specs,
        build_fresh_shared();
        z0 = z0,
        integer = (; K = 4, α_x_lb = Inf),
        checkpoint_dir = mktempdir(),
    )
    # BOTH epigraph bounds are validated at
    # the boundary with an ArgumentError, before any solve. α_op_lb: :auto or a finite
    # Real only — NaN would otherwise be installed by build_master_integer's explicit
    # branch and -Inf would surface only after a full inner Benders loop. α_x_lb: a
    # finite Real only — `:auto` used to raise `MethodError: isfinite(::Symbol)`.
    for bad in (NaN, -Inf, Inf, :foo, "auto")
        @test_throws ArgumentError run_nash!(
            specs,
            build_fresh_shared();
            z0 = z0,
            integer = (; K = 4, α_op_lb = bad),
            checkpoint_dir = mktempdir(),
        )
    end
    for bad in (NaN, -Inf, :auto, "0.0")
        @test_throws ArgumentError run_nash!(
            specs,
            build_fresh_shared();
            z0 = z0,
            integer = (; K = 4, α_x_lb = bad),
            checkpoint_dir = mktempdir(),
        )
    end

    # Inputs the integer path does not read are rejected,
    # never silently ignored. (a) an α bound in master_kwargs (honoured by the
    # continuous path, ignored by the integer master) names `integer` as the fix:
    spec_alpha = merge(spec, (; master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0)))
    e = try
        run_nash!(
            [spec_alpha, spec_alpha],
            build_fresh_shared();
            z0 = z0,
            integer = (; K = 4),
            checkpoint_dir = mktempdir(),
        )
        nothing
    catch err
        err
    end
    @test e isa ArgumentError
    @test occursin("α_op_lb", e.msg) && occursin("integer", e.msg)
    # (b) an unknown `integer` key:
    @test_throws ArgumentError run_nash!(
        specs,
        build_fresh_shared();
        z0 = z0,
        integer = (; K = 4, α_lb = 0.0),
        checkpoint_dir = mktempdir(),
    )
    # (c) master_kwargs missing y_max:
    spec_noymax = merge(spec, (; master_kwargs = (; c_y = 0.3)))
    @test_throws ArgumentError run_nash!(
        [spec_noymax, spec_noymax],
        build_fresh_shared();
        z0 = z0,
        integer = (; K = 4),
        checkpoint_dir = mktempdir(),
    )

    # The DERIVED default α_x_lb — 0.0 for nonnegative costs (this file's
    # fixture, bit-for-bit identical to the old hard-coded default) and the sign-aware bound
    # min(0,c_inv)·x_inv_max + Σ_t min(0,c_op[t])·y_max otherwise.
    @test TSODSO._integer_alpha_x_lb(build_fresh_shared(), 1, 8.0) == 0.0
    shared_neg = build_shared_transmission(;
        N = 2,
        T = 2,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.5],
        c_inv = [-1.0, 1.0],
        c_op = [[-0.5, 0.25], [0.5, 0.5]],
    )
    @test TSODSO._integer_alpha_x_lb(shared_neg, 1, 8.0) ≈ -1.0 * 0.3 + -0.5 * 8.0
    @test TSODSO._integer_alpha_x_lb(shared_neg, 2, 8.0) == 0.0
end

# Cycle detection. The original detector keyed a cycle on
# the joint binary state ALONE and raised a false "CYCLED" error on any run that needed
# three or more sweeps with a stable `b` (reproduced: this file's fixture with `ω = 0.5`).
# Two testitems below replace the old standalone `Dict` replication, which never called
# production code:
#   (a) the PRODUCTION predicate `TSODSO._integer_cycle_hit` on synthetic histories — a
#       damped converging history and a sign-flipping oscillatory contraction (both must
#       NOT fire; the latter is a known repro) and genuine
#       period-1/period-2 cycles (must fire);
#   (b) a LIVE damped `run_nash!(...; integer = (; K = 4), ω = 0.5)` run on this file's
#       fixture that must converge (the old detector threw at sweep 2).
# No LIVE cycling run exists: with objectives separable except through the shared row,
# the summed cost is a potential that exact Gauss-Seidel best responses cannot cycle on
# ABSENT TIES (see `run_nash!`'s docstring, "Cycle detection"; the interior-cap fixtures
# do have tied best responses) — a stated limitation, not a gap papered over.
@testitem "planning nash integer: cycle predicate keys on the full committed state — fires on genuine recurrences, never on a converging damped history" tags =
    [:planning] begin
    using TSODSO

    hit = TSODSO._integer_cycle_hit
    tol_outer = 1e-4
    ω = 0.5
    atol = ω * tol_outer / 2
    b = [1, 0, 0, 0, 1, 0, 0, 0]
    entry(k, jb, st, r) = (; sweep = k, joint_b = jb, state = st, residual = r)

    # Wrapped in a function (TestItem scoping: the loop must not reassign outer bindings).
    function oscillatory_history_never_flagged(hit)
        tol_o = 1e-4
        atol_o = 1.0 * tol_o / 2
        c, zstar, e = -0.9, 0.7, 0.01
        s(k) = zstar + c^k * e
        bo = [1, 0, 0, 0]
        hist = NamedTuple{
            (:sweep, :joint_b, :state, :residual),
            Tuple{Int, Vector{Int}, Vector{Float64}, Float64},
        }[]
        converged = false
        for k in 1:200
            r = abs(s(k) - s(k - 1))
            if r <= tol_o
                converged = true
                break
            end
            hit(hist, bo, [s(k)], r; atol = atol_o) === nothing || return false
            push!(hist, entry(k, bo, [s(k)], r))
        end
        # Guard against a vacuous pass: the history must reach the regime where the
        # old slack fired (sweep 44) and then genuinely converge.
        return converged && length(hist) >= 44
    end

    # (1) The reviewer's false positive: damped run, b fixed from sweep 1, the committed
    # state moves by ω × residual each sweep and the residual halves. NO prefix of this
    # history may be reported as a cycle.
    damped = [entry(k, b, fill(0.5 - 0.5^(k + 1), 3), 0.5^k) for k in 1:12]
    @test all(hit(damped[1:(k - 1)], b, damped[k].state, damped[k].residual; atol) === nothing for k in 2:12)

    # (2) A genuine period-1 recurrence: same b, same state, same residual -> fires and
    # names the FIRST sweep the state was seen at.
    st = [0.5, 0.5, 0.25, 0.25]
    h1 = [entry(1, b, st, 0.3)]
    @test hit(h1, b, copy(st), 0.3; atol) == 1

    # (3) A genuine period-2 cycle: A, B, A -> fires at the third sweep, naming sweep 1.
    bA, bB = [1, 0, 1, 0], [0, 1, 1, 0]
    stA, stB = [0.5, 0.0, 0.25, 0.0], [0.0, 0.5, 0.0, 0.25]
    h2 = [entry(1, bA, stA, 0.5), entry(2, bB, stB, 0.5)]
    @test hit(h2, bA, copy(stA), 0.5; atol) == 1

    # (4) Exactness of the binary key: one flipped bit is a different state.
    @test hit(h2, [1, 0, 1, 1], copy(stA), 0.5; atol) === nothing
    # (5) Same b, continuous state moved by more than atol -> progress, not a cycle.
    @test hit(h1, b, st .+ 2atol, 0.3; atol) === nothing
    # (6) Same b and state but a strictly smaller residual -> progress, not a cycle —
    # with NO tolerance slack: even a decrease far below
    # atol vetoes the match.
    @test hit(h1, b, copy(st), 0.3 - 2atol; atol) === nothing
    @test hit(h1, b, copy(st), 0.3 - 1e-12; atol) === nothing

    # (7) Regression: an OSCILLATORY contraction (sign-flipping
    # geometric history, step factor c = -0.9, ω = 1, tol_outer = 1e-4, b fixed) returns
    # within atol of its state two sweeps earlier while the residual drops by less than
    # atol; the former `residual >= h.residual - atol` slack reported a FALSE cycle at
    # sweep 44 (matching sweep 42). It converges, so no prefix may be reported.
    @test oscillatory_history_never_flagged(hit)
end

@testitem "planning nash integer: damped ω=0.5 integer run converges — no false CYCLED error while b is stable and z/x_inv still move (live)" tags =
    [:planning] setup = [TwoBusFixtures, ToyDeviceFixture] begin
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
        feeder = TwoBusFixtures.two_bus_feeder(),
        pf = LinDistFlow(),
        aggregators = [agg],
        λ₀ = [4.0],
        master_kwargs = (; c_y = 0.3, y_max = 8.0),
    )
    specs = [spec, spec]

    # HAND-DERIVED trajectory (see the brute-force testitem above for the per-player
    # derivation): every best response on this fixture is y = 0.5 (b = [1,0,0,0]),
    # z = 0.5, x_inv = 0.25, independent of the other player's committed state. Seeded
    # at z0 = 0.46 (x_inv0 = 0.23 by run_nash!'s default derivation) with ω = 0.5, the
    # committed z moves 0.46 -> 0.48 -> 0.49 -> 0.495 and the sweep residual is
    # 0.04, 0.02, 0.01 — so b is IDENTICAL at sweeps 1 and 2 while sweep 2 has not
    # converged (0.02 > tol_outer = 0.015): exactly the state on which the old b-only
    # detector threw "CYCLED ... recurred at sweep 2 (first seen at sweep 1)" (measured
    # 2026-10-02 against the pre-fix code). Sweep 3 converges (0.01 <= 0.015). The
    # seed/tolerance are chosen so the run needs exactly three integer sweeps (~1 min)
    # rather than the reviewer's z0 = 0, tol_outer = 1e-4 repro (~14 sweeps).
    result = run_nash!(
        specs,
        shared;
        z0 = fill(0.46, 2, 1),
        tol_outer = 0.015,
        max_sweeps = 10,
        ω = 0.5,
        integer = (; K = 4),
        checkpoint_dir = mktempdir(),
    )
    @test result.converged
    @test result.sweeps == 3
    # Measured: residuals [0.04, 0.04, 0.02, 0.02, 0.01, 0.01] to ~1e-17.
    @test isapprox(result.trace.nash_residual_trace, [0.04, 0.04, 0.02, 0.02, 0.01, 0.01]; atol = 1e-9)
    @test isapprox(result.z, fill(0.495, 2, 1); atol = 1e-9)
    @test isapprox(result.x_inv, [0.2475, 0.2475]; atol = 1e-9)
    @test isapprox(result.UB, [-0.225, -0.225]; atol = 1e-9)
end
