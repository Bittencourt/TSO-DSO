# test/test_planning_nash_integer.jl
#
# Seam: src/planning/nash.jl's `run_nash!` new `integer::Union{Nothing,NamedTuple} =
# nothing` kwarg (Phase 31, BILEV-07, plan 31-04) — threading genuine binary-expansion
# integer investment (`src/planning/master_integer.jl`'s `build_master_integer`, Phase
# 24) through the N-distributor Gauss-Seidel diagonalization. Items tagged `[:planning]`,
# names contain "planning" and "nash" and "integer" (occursin filter convention, mirrors
# `test/test_planning_benders_integer.jl`).
#
# Fixture: the SAME N=2 corner-cap control fixture as
# `test/test_planning_nash.jl`'s own pinned continuous golden (T=1, corridor_cap=2.0,
# x_inv_max=[0.3,0.3], c_inv=[1.0,1.0], c_op=[[0.5],[0.5]], each distributor's own
# feeder=Phase6Fixtures.two_bus_feeder(), pf=LinDistFlow(),
# agg=ToyElasticDevice(2,6.0,1.0,10.0) wrapped in Aggregator(2,0.9,[dev],[0.0]),
# λ₀=[4.0], master_kwargs=(;c_y=0.3,y_max=8.0,α_op_lb=-5.0,α_x_lb=0.0)) — reused here
# with `K=4` (lattice step `y_max/2^K = 0.5`) so the known continuous equilibrium
# (z=[0.6,0.6], x_inv=[0.3,0.3]) is a documented reference point for where the INTEGER
# equilibrium is expected to land (the nearest lattice point at or below the continuous
# optimum). `master_kwargs`'s own `α_op_lb=-5.0`/`α_x_lb=0.0` fields are UNUSED by the
# new `integer` branch (that branch derives `α_op_lb` via `:auto`/`bounds_ctx` and reads
# `α_x_lb` from the `integer` NamedTuple itself, defaulting to `0.0`) — harmless leftover
# fields, kept only so `specs`/`spec` stays the SAME literal shape every other Nash
# testitem in this phase uses.
#
# EMPIRICALLY MEASURED (2026-10-02, scratchpad probe_nash_integer.jl/probe_bruteforce.jl,
# `julia --project=.`, no TestItemRunner): `run_nash!(specs, shared; z0=zeros(2,1),
# tol_outer=1e-4, max_sweeps=10, integer=(;K=4), checkpoint_dir=...)` converges in 2
# sweeps (~67s wall time for 4 best-responses total, each a K=4 MILP best response —
# noticeably slower than the continuous fixture's own sub-second convergence per
# 31-RESEARCH.md's own runtime-impact flag) to `z=[0.5,0.5]`, `x_inv=[0.25,0.25]`,
# `UB=[-0.225,-0.225]` (both distributors, by the fixture's own symmetry) — the nearest
# lattice point AT OR BELOW the continuous optimum `z=0.6` (lattice points are
# `{0,0.5,1.0,...,7.5}`; `0.5` is the largest point `<= 0.6`). The per-player
# brute-force sweep below (Test 2, the load-bearing item) independently confirms this is
# a genuine equilibrium: diff between the reported `UB[i]` and the brute-forced best of
# all 16 lattice points was `2.22e-16` (machine epsilon) for BOTH distributors.
#
# RULE 1 AUTO-FIX (found during this plan's own execution, see 31-04-SUMMARY.md for the
# full account): `solve_follower!(::DistributorView, ...)` (`src/planning/coupling.jl`)
# previously raised an un-named, generic `ErrorException` whenever HiGHS confirmed a
# genuine primal infeasibility (`MOI.INFEASIBLE`) via presolve WITHOUT ever computing a
# Farkas dual ray (`dual_status` stays `NO_SOLUTION`) — a real, previously-unreachable
# code path this plan's `corner_recourse` ternary search (exploring trial `z` values far
# beyond what the shared model's own OTHER-distributor-pinned capacity ever permits)
# triggers routinely. Fixed by adding a third, additive branch: a CONFIRMED
# `MOI.INFEASIBLE` without a certificate now returns `(; feasible = false, v = NaN,
# u = fill(NaN, T))` instead of raising — `corner_recourse`'s own `Qfun` only reads
# `.feasible` (returns `+Inf`, exactly as for a certificate-bearing infeasible trial), so
# this is transparent to every existing caller; a caller that DOES need a cut
# (`solve_stackelberg!`'s own outer feasibility-cut branch, `add_feasibility_cut!`) still
# hits THAT function's pre-existing finiteness guard and fails loudly there instead —
# never silently accepts a vacuous cut. See `src/planning/coupling.jl`'s own updated
# `solve_follower!(::DistributorView, ...)` docstring for the full account.

@testitem "planning nash integer: N=2 run_nash! with integer=(;K=4) converges + per-player brute-force certification (no profitable unilateral deviation, BILEV-07)" tags =
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
    K = 4

    # Test 1 (wiring smoke test, Task 1's own <behavior>): `run_nash!` with the new
    # `integer` kwarg runs end-to-end — no MethodError/UndefVarError. Called WITHOUT a
    # try/catch, mirroring every OTHER Nash testitem in this phase's own "fail loud, no
    # try/catch around run_nash!" convention (T-13-10) — empirically confirmed
    # (scratchpad probes, this file's own header) to converge RELIABLY on this fixture,
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

    # Test 2 (brute-force certification, THE load-bearing item): for EACH distributor i,
    # hold the OTHER distributor's (x_inv_j, z_j) PINNED at the reported equilibrium (via
    # a FRESH SharedTransmission + write_back!/activate_distributor!), enumerate
    # distributor i's own 2^K=16 lattice points via the PRODUCTION `corner_recourse`
    # (never a re-derived enumeration — 31-PATTERNS.md's own "Don't Hand-Roll"
    # guidance), built fresh per distributor (never reused across i), and assert NONE
    # achieves a strictly lower total cost than the reported equilibrium's own UB[i].
    y_max = spec.master_kwargs.y_max
    c_y = spec.master_kwargs.c_y
    step = y_max / 2.0^K
    # Measured tolerance (this file's own header): the brute-force/reported diff was
    # 2.22e-16 (machine epsilon) on this fixture for BOTH distributors — a generous
    # 1e-6 ceiling (this project's own standard tol order of magnitude, e.g.
    # KNOWN_OPTIMUM_ATOL/stall_z_atol in src/planning/benders.jl|master_integer.jl) is
    # used here rather than a hairline machine-epsilon bound, to stay robust to ordinary
    # solver-to-solver noise without masking a genuine profitable deviation (which would
    # be orders of magnitude larger than 1e-6 on this fixture's own cost scale).
    NO_DEVIATION_TOL = 1.0e-6

    for i in 1:2
        j = i == 1 ? 2 : 1
        shared_check = build_shared_transmission(;
            N = 2,
            T = 1,
            corridor_cap = 2.0,
            x_inv_max = [0.3, 0.3],
            c_inv = [1.0, 1.0],
            c_op = [[0.5], [0.5]],
        )
        write_back!(shared_check, j, result.z[j, :], result.x_inv[j])
        activate_distributor!(shared_check, i)
        follower_i = DistributorView(shared_check, i)
        oracle_i = TSODSO.build_planning_oracle(
            spec.feeder,
            spec.pf,
            spec.aggregators;
            λ₀ = spec.λ₀,
            T = 1,
        )

        best_total = Inf
        for idx in 0:(2^K - 1)
            y_inv_idx = step * idx
            Qv = TSODSO.corner_recourse(oracle_i, follower_i, y_inv_idx, 1)
            total_idx = c_y * y_inv_idx + Qv
            best_total = min(best_total, total_idx)
        end

        # The mathematically correct "no profitable unilateral deviation" check for a
        # GNE at this lattice: the reported equilibrium's own cost for i must be WITHIN
        # tolerance of the brute-forced best (never strictly beaten by more than the
        # measured tolerance).
        @test result.UB[i] <= best_total + NO_DEVIATION_TOL
        @test isapprox(result.UB[i], best_total; atol = NO_DEVIATION_TOL)
    end
end

@testitem "planning nash integer: integer kwarg boundary guards (K must be a positive Integer; α_x_lb must be finite) — before any solve call" tags =
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
end

# Cycle detection (Phase 31 code review, CR-01). The original detector keyed a cycle on
# the joint binary state ALONE and raised a false "CYCLED" error on any run that needed
# three or more sweeps with a stable `b` (reproduced: this file's fixture with `ω = 0.5`).
# Two testitems below replace the old standalone `Dict` replication, which never called
# production code:
#   (a) the PRODUCTION predicate `TSODSO._integer_cycle_hit` on synthetic histories — a
#       damped converging history (must NOT fire) and genuine period-1/period-2 cycles
#       (must fire);
#   (b) a LIVE damped `run_nash!(...; integer = (; K = 4), ω = 0.5)` run on this file's
#       fixture that must converge (the old detector threw at sweep 2).
# No LIVE cycling run exists: with objectives separable except through the shared row,
# the summed cost is a potential that exact Gauss-Seidel best responses cannot cycle on
# (see `run_nash!`'s docstring, "Cycle detection") — a stated limitation, not a gap
# papered over.
@testitem "planning nash integer: cycle predicate keys on the full committed state — fires on genuine recurrences, never on a converging damped history (CR-01)" tags =
    [:planning] begin
    using TSODSO

    hit = TSODSO._integer_cycle_hit
    tol_outer = 1e-4
    ω = 0.5
    atol = ω * tol_outer / 2
    b = [1, 0, 0, 0, 1, 0, 0, 0]
    entry(k, jb, st, r) = (; sweep = k, joint_b = jb, state = st, residual = r)

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
    # (6) Same b and state but a strictly smaller residual -> progress, not a cycle.
    @test hit(h1, b, copy(st), 0.3 - 2atol; atol) === nothing
end

@testitem "planning nash integer: damped ω=0.5 integer run converges — no false CYCLED error while b is stable and z/x_inv still move (CR-01, live)" tags =
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
