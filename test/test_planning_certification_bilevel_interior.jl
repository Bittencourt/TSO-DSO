# test/test_planning_certification_bilevel_interior.jl
#
# Seam: BILEV-02 BLOCKER-1 remediation (Phase 29 plan 29-04) — the checker's
# fixture-adequacy finding on the initial BILEV-02 plan set.
#
# (a) WHY THIS FILE EXISTS. Plan 29-02's `test_planning_certification_bilevel.jl`
# certifies `TSODSO.solve_bilevel!` on `PlanningFixtures.bilevel_toy_fixture()`
# (`q_op=[0.0]`) — a fixture where `pi_tariff[1]-c_op[1] = -0.3 < 0` for EVERY
# `y_inv >= 0`, so the follower's response is the SAME degenerate corner
# (`x_inv=z=0`) regardless of what the leader does. A wrong single-level
# reformulation, or a trivial stub that always returns `z ≡ 0`, would pass every
# one of that fixture's three oracles: it never exercises genuine leader-follower
# INTERACTION, and its SOS1 coupling pair `[slack_y, rho_y]` is never observed in
# its "inactive" branch. This file adds a SECOND, NON-DEGENERATE fixture
# (`q_op=[1.0] > 0`, via plan 29-01's BLOCKER-1-added `q_op` keyword — `q_op=0`
# recovers the corner fixture exactly, so this is a pure additive extension, never
# a modification of it) where the follower's optimal response `z*(y_inv)` is a
# genuine TWO-BRANCH function of `y_inv`: linear/coupling-bound for small `y_inv`,
# flat/interior once the follower reaches its own unconstrained optimum — real SOS1
# complementarity SWITCHING, not a single always-zero corner.
#
# (b) SELF-CONTAINED BY DESIGN — this file does NOT import or extend
# `test/fixtures_planning.jl` or plan 29-02's `test_planning_certification_bilevel.jl`
# (its own `@testmodule BilevelInteriorCertFixture` defines every fixture constant
# and oracle function locally). This keeps plan 29-04 parallel-wave-safe against
# plan 29-02 (both depend only on plan 29-01).
#
# (c) HAND-DERIVATION (the analytic target the live solve below must reproduce —
# if the live solve disagrees, THIS comment/the golden consts below must be
# corrected, never the model, mirroring `test/fixtures_planning.jl`'s own
# established convention).
#
# Fixture: T=1, same 2-bus (root=1/load=2, r=x=1e-3, smax=99.0) lossless feeder
# shape as plan 29-01's corner fixture, built fresh here for self-containment.
# `corridor_cap=10.0`, `x_inv_max=10.0`, `c_inv=0.2`, `c_op=[0.5]`,
# `pi_tariff=[2.0]`, `q_op=[1.0]`, `c_y=0.05`, `y_max=5.0`, `v_d=[3.0]`,
# `d_max=10.0`, `agg_bus=2`. `x_inv_max`/`d_max` are deliberately LARGE relative to
# every quantity actually reached (never bind on this fixture, verified below).
# The production KKT carries its own `rho_max` multiplier for `x_inv <= x_inv_max`
# (29-REVIEW.md WR-01). That pair is exercised separately in
# test/test_planning_bilevel.jl ("x_inv_max binds").
#
# Follower's own problem (given fixed `y_inv`, T=1, dropping the time index):
#   min_{x_inv,z} c_inv*x_inv + (c_op-pi_tariff)*z + 0.5*q_op*z^2
#   s.t. z <= corridor_cap*x_inv (dual mu_cap), x_inv <= y_inv (dual rho_y),
#        x_inv,z >= 0.
#
# Because `c_inv > 0`, the follower NEVER wastes capacity: at its true optimum the
# cap constraint always binds (`z = corridor_cap*x_inv`, `mu_cap = c_inv/corridor_cap
# = 0.02 > 0`, verified by the stationarity-in-x_inv FOC `c_inv - corridor_cap*mu_cap
# = 0` when `rho_y=rho_lo=0`). Substituting `x_inv = z/corridor_cap`, the follower's
# problem reduces to a single-variable QP in `z`: minimize
# `[c_inv/corridor_cap + c_op - pi_tariff]*z + 0.5*q_op*z^2`, whose UNCONSTRAINED
# (by `y_inv`) optimum is
# `z_F = (pi_tariff - c_op - c_inv/corridor_cap)/q_op = (2.0-0.5-0.02)/1.0 = 1.48`,
# giving `x_inv_F = z_F/corridor_cap = 0.148`.
#
# So the follower's response as a function of `y_inv` is TWO BRANCHES:
#   - `y_inv < 0.148` (coupling BINDS): `x_inv*(y)=y`, `z*(y)=corridor_cap*y=10y`
#     (linear, genuinely varying with `y`); `rho_y(y) = 14.8 - 100y` (strictly
#     POSITIVE, the coupling dual, decreasing continuously toward zero — the
#     "active" SOS1 branch for `[slack_y, rho_y]`).
#   - `y_inv >= 0.148` (coupling SLACK): `x_inv*(y)=x_inv_F=0.148`,
#     `z*(y)=z_F=1.48` (CONSTANT — the follower has reached its own interior
#     optimum, independent of further `y_inv` increases); `rho_y(y)=0` exactly
#     (the "inactive" SOS1 branch).
#
# Leader's objective (network-tied `d=z`, lossless single branch): for `y<0.148`,
# `total(y) = [c_y + corridor_cap*(pi_tariff-v_d)]*y = [0.05+10*(2.0-3.0)]*y
# = -9.95*y` (DECREASING in `y` => leader wants `y` as LARGE as possible in this
# branch, i.e. `y -> 0.148`); for `y>=0.148`,
# `total(y) = c_y*y + (pi_tariff-v_d)*z_F = 0.05*y - 1.48` (INCREASING in `y` =>
# leader wants `y` as SMALL as possible, i.e. `y=0.148`). Both branches agree
# exactly at the kink: `y*=0.148`, `x_inv*=0.148`, `z*=1.48`, `d*=1.48`,
# `total*=-1.4726` — a genuinely INTERIOR leader optimum, structurally forced by
# the sign pattern above (robust, not knife-edge).
#
# JOINT reference (single planner, TRUE costs — `v_d` directly, no tariff —
# INCLUDING the real convex curvature `0.5*q_op*z^2`; at the joint optimum
# `y=x_inv` exactly, same "never waste capacity" argument): reduces to minimizing
# `[(c_y+c_inv)/corridor_cap + c_op - v_d]*z + 0.5*q_op*z^2` over `z`, giving
# `z*_joint = (v_d-c_op-(c_y+c_inv)/corridor_cap)/q_op = (3.0-0.5-0.025)/1.0 = 2.475`,
# `x_inv*_joint = y*_joint = 0.2475`, `d*_joint = 2.475`,
# `total*_joint = -3.0628125`.
#
# MEASURED GAP: `|total*-total*_joint| = 1.5902125`, `|z*-z*_joint| = 0.995` — both
# orders of magnitude above any HiGHS/Clarabel tolerance-class quantity (memory
# `highs-exactness-defaults`), a genuine structural finding.
#
# MUTATION-GUARD TARGET: a stub returning `z ≡ 0` for every `y` would report
# `y=0, x_inv=0, z=0, d=0, total=0.0` (the leader gains nothing from `y>0` if the
# follower never responds, so a naive/broken solver would also collapse to `y=0`)
# — `|total*-0.0| = 1.4726` and `|z*-0.0| = 1.48`, both clearly resolvable.
#
# (d) SAME BilevelJuMP IMPLEMENTATION NOTE AS PLAN 29-02 — the oracle hand-derives
# the lossless 2-bus network algebra directly (`d == z`) rather than reusing
# `contribute!`/`ModelContext` inside a `BilevelModel`, for the same
# fixture-specific reason (single root-to-load branch, no current/loss terms).
#
# INFRA-02 exception (mirrors plan 29-02's own documented exception): this file
# imports `HiGHS, Ipopt, BilevelJuMP, JuMP` directly, because BilevelJuMP/Ipopt are
# validation-oracle-only, test-only dependencies (never imported by `src/`).

@testmodule BilevelInteriorCertFixture begin
    using BilevelJuMP, HiGHS, Ipopt, JuMP, TSODSO

    const corridor_cap = 10.0
    const x_inv_max = 10.0
    const c_inv = 0.2
    const c_op = [0.5]
    const pi_tariff = [2.0]
    const q_op = [1.0]
    const c_y = 0.05
    const y_max = 5.0
    const v_d = [3.0]
    const d_max = 10.0
    const agg_bus = 2

    """
        _interior_feeder()

    The shared lossless 2-bus (root=1/load=2, r=x=1e-3, smax=99.0) feeder,
    rebuilt fresh by every function/testitem in this file (self-containment,
    file header note (b)).
    """
    _interior_feeder() =
        Feeder([Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)], [Branch(1, 2, 1e-3, 1e-3, 99.0)], 1)

    """
        solve_follower_at(y::Real) -> NamedTuple

    The follower's OWN tiny throwaway QP (`q_op[1] != 0` makes this a genuine QP,
    solved via `select_optimizer(TSODSO.QP())`, i.e. Clarabel), parametrized by a
    FIXED leader investment `y`. Both the brute-force oracle's per-grid-point solve
    AND the SOS1 branch-switch probe (file header note (c)) are this SAME function
    evaluated at different `y`.
    """
    function solve_follower_at(y::Real)
        m = Model(TSODSO.select_optimizer(TSODSO.QP()))
        @variable(m, 0 <= x_inv <= x_inv_max)
        @variable(m, z >= 0)
        @constraint(m, cap, corridor_cap * x_inv - z >= 0)
        @constraint(m, inv_bound, x_inv <= y)
        @objective(
            m,
            Min,
            c_inv * x_inv + (c_op[1] - pi_tariff[1]) * z + 0.5 * q_op[1] * z^2
        )
        TSODSO.assert_solved!(m; dual = true)
        return (;
            x_inv = value(x_inv),
            z = value(z),
            rho_y = abs(dual(inv_bound)),
            mu_cap = abs(dual(cap)),
        )
    end

    """
        brute_force_interior(; y_grid) -> NamedTuple

    Certification oracle #2: for each `y in y_grid`, re-solve the follower's own QP
    via [`solve_follower_at`](@ref), compute the leader's own total cost
    `c_y*y + pi_tariff[1]*z - v_d[1]*d`, and return the grid point achieving the
    MINIMUM total.

    Leader-level semantics match production (29-REVIEW.md WR-07): the lossless
    network forces `d = z`. A follower response with `z > dmax`, or a bus-2 squared
    voltage `1 - 2e-3*z` outside `[0.95^2, 1.05^2]`, makes that `y` INFEASIBLE for
    the leader (`continue`), never feasible-but-curtailed. The follower's response
    is unique here (`q_op > 0` makes its QP strictly convex in `z`, and `c_inv > 0`
    pins `x_inv = z/corridor_cap`), so the optimistic-vs-reported tie question
    does not arise. `dmax` defaults to the fixture's `d_max`. The d_max-binding
    testitem below overrides it.
    """
    function brute_force_interior(; y_grid, dmax = d_max)
        best = nothing
        for y in y_grid
            r = solve_follower_at(y)
            r.z <= dmax + 1e-6 || continue                         # network: d = z <= d_max
            0.95^2 <= 1.0 - 2 * (1e-3 * r.z) <= 1.05^2 || continue  # leader voltage bounds
            d = r.z
            total = c_y * y + pi_tariff[1] * r.z - v_d[1] * d
            if best === nothing || total < best.total
                best = (; y, z = r.z, d, total)
            end
        end
        return best
    end

    """
        build_interior_bilevel_jump() -> NamedTuple

    Certification oracle #1: `BilevelModel(Ipopt.Optimizer, mode =
    BilevelJuMP.StrongDualityMode())` — a hand-derived MPEC with a QUADRATIC
    lower-level objective (Ipopt/NLP handles the strong-duality equality of a
    convex QP lower level natively). `dmax` defaults to the fixture's `d_max`.
    """
    function build_interior_bilevel_jump(; dmax = d_max)
        model = BilevelModel(Ipopt.Optimizer, mode = BilevelJuMP.StrongDualityMode())
        @variable(Upper(model), 0 <= y_inv <= y_max)
        @variable(Upper(model), 0.95^2 <= v2 <= 1.05^2)
        @variable(Upper(model), 0 <= d <= dmax)
        @variable(Lower(model), 0 <= x_inv <= x_inv_max)
        @variable(Lower(model), z >= 0)
        @constraint(Lower(model), cap, z <= corridor_cap * x_inv)
        @constraint(Lower(model), coupling, x_inv <= y_inv)
        @objective(
            Lower(model),
            Min,
            c_inv * x_inv + (c_op[1] - pi_tariff[1]) * z + 0.5 * q_op[1] * z^2
        )
        @constraint(Upper(model), v2 == 1.0 - 2 * (1e-3 * z))
        @constraint(Upper(model), d == z)
        @objective(Upper(model), Min, c_y * y_inv + pi_tariff[1] * z - v_d[1] * d)
        optimize!(model)
        return (;
            model,
            y_inv = value(y_inv),
            z = value(z),
            x_inv = value(x_inv),
            d = value(d),
        )
    end

    """
        build_joint_reference_interior() -> NamedTuple

    The TRUE single-planner optimum on this fixture (no tariff, no follower, no
    KKT/complementarity): a plain QP (`select_optimizer(TSODSO.QP())`, since
    `0.5*q_op*z^2` is a genuine quadratic objective term here — this is fine, it's
    a plain JuMP model, not the single-level MILP) reusing the SAME embedded
    LinDistFlow network as production.
    """
    function build_joint_reference_interior()
        feeder = _interior_feeder()
        model = Model(TSODSO.select_optimizer(TSODSO.QP()))
        ctx = TSODSO.ModelContext(model)
        TSODSO.contribute!(TSODSO.LinDistFlow(), ctx, feeder; T = 1)
        Np = length(feeder.buses)

        @variable(model, 0 <= y_inv <= y_max)
        @variable(model, 0 <= x_inv <= x_inv_max)
        @variable(model, z >= 0)
        @variable(model, 0 <= d <= d_max)
        @constraint(model, x_inv <= y_inv)
        @constraint(model, cap, z <= corridor_cap * x_inv)

        TSODSO.add_to_residual!(ctx, :Rp, feeder.root, 1, z)
        TSODSO.add_to_residual!(ctx, :Rp, agg_bus, 1, -d)

        size(ctx.residuals[:Rp]) == (Np, 1) || error(
            "residual :Rp is $(size(ctx.residuals[:Rp])), expected ($Np, 1) — an index escaped the feeder",
        )
        @constraint(model, balance_p[j = 1:Np], ctx.residuals[:Rp][j, 1] == 0)
        if haskey(ctx.residuals, :Rq)
            size(ctx.residuals[:Rq]) == (Np, 1) || error(
                "residual :Rq is $(size(ctx.residuals[:Rq])), expected ($Np, 1) — an index escaped the feeder",
            )
            @constraint(model, balance_q[j = 1:Np], ctx.residuals[:Rq][j, 1] == 0)
        end

        @objective(
            model,
            Min,
            c_y * y_inv + c_inv * x_inv + c_op[1] * z + 0.5 * q_op[1] * z^2 - v_d[1] * d
        )
        TSODSO.assert_solved!(model; dual = false)

        return (;
            y = value(y_inv),
            x_inv = value(x_inv),
            z = value(z),
            d = value(d),
            total = objective_value(model),
        )
    end

    # --- BILEV-02 BLOCKER-1 golden constants (Task 2) ------------------------------
    # Pinned from a LIVE, measured solve this session (see this file's header
    # derivation comment (c) for the full analytic argument — EMPIRICALLY CONFIRMED,
    # not blindly trusted: the direct-script reproduction under a stacked
    # JULIA_LOAD_PATH="test:.:@stdlib" measured production y=0.148, x_inv=0.148,
    # z=1.48, total_cost=-1.4726 to within 1e-7 of these analytic values; joint
    # y=x_inv=0.2475, z=2.475, total=-3.0628125 to within 1e-7; rho_y(0.05)=9.8 to
    # within 3e-8; rho_y(1.0)=0.0 to within 6e-11 -- no derivation correction needed).
    const INTERIOR_Y_HAND = 0.148
    const INTERIOR_XINV_HAND = 0.148
    const INTERIOR_Z_HAND = 1.48
    const INTERIOR_TOTAL_HAND = -1.4726
    const JOINT_Y_HAND_INTERIOR = 0.2475
    const JOINT_XINV_HAND_INTERIOR = 0.2475
    const JOINT_Z_HAND_INTERIOR = 2.475
    const JOINT_TOTAL_HAND_INTERIOR = -3.0628125
    const RHO_Y_BELOW_HAND = 9.8
    const RHO_Y_ABOVE_HAND = 0.0

    # GAP_FLOOR_INTERIOR / Z_GAP_FLOOR_INTERIOR — T-29-07 mitigation: derived from
    # MEASURED solver-precision quantities (10x the production MILP's own
    # `select_optimizer(MILP())` `mip_feasibility_tolerance=1e-9`, memory
    # `highs-exactness-defaults`), NEVER as a fraction of the ~1.59/~0.995
    # hand-derived gaps they validate. Both gaps sit many orders of magnitude above
    # this floor.
    const GAP_FLOOR_INTERIOR = 1e-6
    const Z_GAP_FLOOR_INTERIOR = 1e-6

    export solve_follower_at,
        brute_force_interior,
        build_interior_bilevel_jump,
        build_joint_reference_interior,
        _interior_feeder,
        corridor_cap,
        x_inv_max,
        c_inv,
        c_op,
        pi_tariff,
        q_op,
        c_y,
        y_max,
        v_d,
        d_max,
        agg_bus,
        INTERIOR_Y_HAND,
        INTERIOR_XINV_HAND,
        INTERIOR_Z_HAND,
        INTERIOR_TOTAL_HAND,
        JOINT_Y_HAND_INTERIOR,
        JOINT_XINV_HAND_INTERIOR,
        JOINT_Z_HAND_INTERIOR,
        JOINT_TOTAL_HAND_INTERIOR,
        RHO_Y_BELOW_HAND,
        RHO_Y_ABOVE_HAND,
        GAP_FLOOR_INTERIOR,
        Z_GAP_FLOOR_INTERIOR
end

@testitem "bilevel certification (interior fixture): production == BilevelJuMP StrongDualityMode == brute-force grid; production != joint; production != z≡0 stub (BILEV-02 BLOCKER-1)" tags =
    [:planning] setup = [BilevelInteriorCertFixture] begin
    using TSODSO: build_bilevel_kkt, solve_bilevel!
    using TSODSO, BilevelJuMP, JuMP

    F = BilevelInteriorCertFixture
    feeder = F._interior_feeder()

    # --- Production (TSODSO.solve_bilevel!, plan 29-01's single-level KKT-MILP) ---
    kkt = build_bilevel_kkt(
        feeder,
        LinDistFlow();
        T = 1,
        agg_bus = F.agg_bus,
        corridor_cap = F.corridor_cap,
        x_inv_max = F.x_inv_max,
        c_inv = F.c_inv,
        c_op = F.c_op,
        pi_tariff = F.pi_tariff,
        q_op = F.q_op,
        c_y = F.c_y,
        y_max = F.y_max,
        v_d = F.v_d,
        d_max = F.d_max,
    )
    prod = solve_bilevel!(kkt)

    # --- Oracle #1: BilevelJuMP StrongDualityMode (Ipopt, quadratic lower level) ---
    bj = F.build_interior_bilevel_jump()
    @test termination_status(bj.model) == MOI.LOCALLY_SOLVED

    # --- Oracle #2: brute-force grid enumeration ---
    # A fine background grid (2001 points over [0, y_max]) resolves the true
    # minimum to within its own spacing; the EXPLICIT salted 0.148 point (the
    # hand-derived kink) lets the certification assert a near-EXACT match against
    # production rather than only a grid-spacing-limited one. Including the
    # analytic point does NOT by itself validate anything — the assertion below
    # (bf vs bf_fine_only) confirms 0.148 actually ACHIEVES the minimum over the
    # WHOLE fine grid, not just among salted points.
    fine_grid = range(0.0, F.y_max; length = 2001)
    grid_spacing = step(fine_grid)
    salted_grid = sort(unique(vcat(collect(fine_grid), 0.148)))
    bf = F.brute_force_interior(; y_grid = salted_grid)
    bf_fine_only = F.brute_force_interior(; y_grid = fine_grid)

    # --- Reference: joint (single-planner, true-cost, no-tariff) optimum ---
    jt = F.build_joint_reference_interior()

    # --- Production reproduces the named golden interior optimum ---
    # atol MEASURED this session: HiGHS's own achieved precision on this fixture's
    # embedded SOS1-bridged MILP (see file header derivation comment (c)).
    atol_hand = 1e-4
    @test isapprox(prod.y, F.INTERIOR_Y_HAND; atol = atol_hand)
    @test isapprox(prod.x_inv, F.INTERIOR_XINV_HAND; atol = atol_hand)
    @test isapprox(prod.z[1], F.INTERIOR_Z_HAND; atol = atol_hand)
    @test isapprox(prod.total_cost, F.INTERIOR_TOTAL_HAND; atol = atol_hand)

    # --- Joint reference reproduces the named golden optimum ---
    @test isapprox(jt.y, F.JOINT_Y_HAND_INTERIOR; atol = atol_hand)
    @test isapprox(jt.x_inv, F.JOINT_XINV_HAND_INTERIOR; atol = atol_hand)
    @test isapprox(jt.z, F.JOINT_Z_HAND_INTERIOR; atol = atol_hand)
    @test isapprox(jt.total, F.JOINT_TOTAL_HAND_INTERIOR; atol = atol_hand)

    # --- Three-way agreement: production == BilevelJuMP == brute-force ---
    # atol_bilevel MEASURED this session: BilevelJuMP StrongDualityMode (Ipopt, an
    # NLP strong-duality reformulation of a QP lower level) converges to this
    # fixture's genuinely INTERIOR optimum with its own interior-point residual —
    # see this plan's SUMMARY for the measured value.
    atol_bilevel = 1e-3
    @test isapprox(prod.y, bj.y_inv; atol = atol_bilevel)
    @test isapprox(prod.z[1], bj.z; atol = atol_bilevel)
    @test isapprox(prod.total_cost, objective_value(bj.model); atol = atol_bilevel)

    # atol_bruteforce MEASURED this session: production (HiGHS MILP embedding the
    # follower's OWN KKT conditions) vs brute-force (Clarabel QP re-solving the
    # follower's own problem per grid point) — two structurally DIFFERENT solves
    # of the SAME convex problem, not bit-identical like the LP corner fixture.
    atol_bruteforce = 1e-3
    @test isapprox(prod.y, bf.y; atol = atol_bruteforce)
    @test isapprox(prod.z[1], bf.z; atol = atol_bruteforce)
    @test isapprox(prod.total_cost, bf.total; atol = atol_bruteforce)

    # The FINE-ONLY grid (no salted point) resolves the optimum on its own: its
    # achieving point sits within one grid spacing of the hand-derived kink
    # (29-REVIEW.md WR-04 — the earlier version tested the salted `bf.y`, which
    # contains 0.148 exactly, so it passed by construction).
    @test abs(bf_fine_only.y - F.INTERIOR_Y_HAND) <= grid_spacing

    # The salted 0.148 point is not silently doing all the work: the fine-only
    # total agrees with the salted total to within the analytic spacing error. Some
    # fine-grid point lies in [0.148, 0.148 + grid_spacing], on the right branch
    # total(y) = c_y*y - 1.48 (slope c_y = 0.05), so the fine-only minimum is at most
    # c_y*grid_spacing = 1.25e-4 above the true minimum (analytic gap at y = 0.15:
    # 1.0e-4). The 5e-5 term covers Clarabel's noise at the degenerate kink point:
    # measured z(0.148) = 1.47996 (3.7e-5 short of 1.48), so the measured
    # |bf.total - bf_fine_only.total| is 6.3e-5.
    @test isapprox(bf.total, bf_fine_only.total; atol = F.c_y * grid_spacing + 5e-5)

    # --- Genuine bilevel != joint divergence (well above solver precision) ---
    @test abs(prod.total_cost - jt.total) > F.GAP_FLOOR_INTERIOR
    @test abs(prod.z[1] - jt.z) > F.Z_GAP_FLOOR_INTERIOR

    # --- Mutation guard: production != a z≡0 stub's report ---
    @test abs(prod.total_cost - 0.0) > F.GAP_FLOOR_INTERIOR
    @test abs(prod.z[1] - 0.0) > F.Z_GAP_FLOOR_INTERIOR

    # A z≡0 stub would ALSO disagree with the brute-force oracle's own z at y=1.0
    # (computed independently below) by more than Z_GAP_FLOOR_INTERIOR.
    r_at_one = F.solve_follower_at(1.0)
    @test abs(r_at_one.z - 0.0) > F.Z_GAP_FLOOR_INTERIOR

    # --- SOS1 branch-switch assertion (checker-mandated, explicit) ---
    # r_below/r_above ARE the >= 2 grid points the checker requires, demonstrating
    # the [slack_y, rho_y] SOS1 pair genuinely switching between its two branches
    # (not a single always-inactive or always-active corner).
    r_below = F.solve_follower_at(0.05)   # BELOW the 0.148 threshold: coupling BINDS
    r_above = F.solve_follower_at(1.0)    # ABOVE the 0.148 threshold: coupling SLACK

    @test r_below.rho_y > 1.0
    @test isapprox(r_below.x_inv, 0.05; atol = 1e-4)   # 0.05 is the PROBE input, not a golden
    @test isapprox(r_below.rho_y, F.RHO_Y_BELOW_HAND; atol = 1e-2)

    @test r_above.rho_y < 1e-6
    @test isapprox(r_above.x_inv, F.INTERIOR_XINV_HAND; atol = 1e-4)
    @test isapprox(r_above.rho_y, F.RHO_Y_ABOVE_HAND; atol = 1e-6)

    # --- SOS1 branch-switch + z≡0 guard on the PRODUCTION MILP (29-REVIEW.md WR-05) ---
    # The block above only exercises the oracle QP. The production optimum sits
    # exactly at the kink y = 0.148 (slack_y = 0 AND rho_y = 0, degenerate), so it
    # never shows [slack_y, rho_y] in a strict branch. Fix the leader decision in the
    # production KKT-MILP itself and read ITS complementarity variables:
    #   y = 0.05 (below the kink): slack_y = 0, rho_y = 14.8 - 100*0.05 = 9.8 > 0,
    #            x_inv = 0.05, z = 0.5;
    #   y = 1.0  (above the kink): slack_y = 0.852 > 0, rho_y = 0,
    #            x_inv = 0.148, z = 1.48 (also a production-level z≡0 mutation guard).
    # A production reformulation with a broken rho_y pair (or a z≡0 stub) fails here.
    for (y_fixed, expect_rho, expect_x, expect_z) in (
        (0.05, F.RHO_Y_BELOW_HAND, 0.05, 0.5),
        (1.0, F.RHO_Y_ABOVE_HAND, F.INTERIOR_XINV_HAND, F.INTERIOR_Z_HAND),
    )
        k = build_bilevel_kkt(
            feeder,
            LinDistFlow();
            T = 1,
            agg_bus = F.agg_bus,
            corridor_cap = F.corridor_cap,
            x_inv_max = F.x_inv_max,
            c_inv = F.c_inv,
            c_op = F.c_op,
            pi_tariff = F.pi_tariff,
            q_op = F.q_op,
            c_y = F.c_y,
            y_max = F.y_max,
            v_d = F.v_d,
            d_max = F.d_max,
        )
        fix(k.y_inv, y_fixed; force = true)
        r = solve_bilevel!(k)
        @test isapprox(r.rho_y, expect_rho; atol = 1e-6)
        @test isapprox(r.x_inv, expect_x; atol = 1e-6)
        @test isapprox(r.z[1], expect_z; atol = 1e-6)
        if expect_rho > 0
            @test isapprox(r.y - r.x_inv, 0.0; atol = 1e-6)   # slack_y = 0 branch
        else
            @test r.y - r.x_inv > 0.5                          # slack_y > 0 branch
        end
    end
end

@testitem "bilevel certification (interior fixture, d_max binds): the embedded network coupling restricts the leader (WR-07)" tags =
    [:planning] setup = [BilevelInteriorCertFixture] begin
    using TSODSO: build_bilevel_kkt, solve_bilevel!
    using TSODSO, BilevelJuMP, JuMP

    # 29-REVIEW.md WR-07: on the base fixtures d_max and the voltage limits are
    # slack, so oracle agreement says nothing about the embedded LinDistFlow coupling
    # (CONTEXT "Option B"). Here d_max = 1.0 binds the follower's response.
    #
    # Hand derivation: the follower's response is unchanged (it never sees d_max):
    # z(y) = 10y for y < 0.148, z = 1.48 for y >= 0.148. The network forces
    # d = z <= d_max = 1.0, so the leader's feasible set is y in [0, 0.1]. On that set
    # total(y) = (c_y + corridor_cap*(pi_tariff - v_d))*y = -9.95y, minimized at the
    # coupling boundary: y* = x_inv* = 0.1, z* = d* = 1.0, total* = -0.995, with
    # rho_y = 14.8 - 100*0.1 = 4.8 > 0. (The unrestricted optimum y = 0.148 is now
    # leader-infeasible.) Measured: production matches to ~1e-15; BilevelJuMP to ~1e-8.
    F = BilevelInteriorCertFixture
    feeder = F._interior_feeder()
    dmax = 1.0

    kkt = build_bilevel_kkt(
        feeder,
        LinDistFlow();
        T = 1,
        agg_bus = F.agg_bus,
        corridor_cap = F.corridor_cap,
        x_inv_max = F.x_inv_max,
        c_inv = F.c_inv,
        c_op = F.c_op,
        pi_tariff = F.pi_tariff,
        q_op = F.q_op,
        c_y = F.c_y,
        y_max = F.y_max,
        v_d = F.v_d,
        d_max = dmax,
    )
    prod = solve_bilevel!(kkt)

    atol_hand = 1e-6
    @test isapprox(prod.y, 0.1; atol = atol_hand)
    @test isapprox(prod.x_inv, 0.1; atol = atol_hand)
    @test isapprox(prod.z[1], 1.0; atol = atol_hand)
    @test isapprox(prod.d[1], 1.0; atol = atol_hand)
    @test isapprox(prod.total_cost, -0.995; atol = atol_hand)
    @test isapprox(prod.rho_y, 4.8; atol = atol_hand)

    bj = F.build_interior_bilevel_jump(; dmax = dmax)
    @test termination_status(bj.model) == MOI.LOCALLY_SOLVED
    @test isapprox(prod.y, bj.y_inv; atol = 1e-6)
    @test isapprox(prod.z[1], bj.z; atol = 1e-6)
    @test isapprox(prod.total_cost, objective_value(bj.model); atol = 1e-6)

    # Brute force with production semantics: every grid y > 0.1 is leader-infeasible.
    # The fine grid contains the analytic boundary (0.1 = 40 * 0.0025, up to rounding).
    fine_grid = range(0.0, F.y_max; length = 2001)
    bf = F.brute_force_interior(; y_grid = fine_grid, dmax = dmax)
    @test bf.y <= 0.1 + 1e-9
    @test isapprox(prod.y, bf.y; atol = step(fine_grid))
    @test isapprox(prod.total_cost, bf.total; atol = 9.95 * step(fine_grid))
end

@testitem "bilevel certification (T=2 interior fixture): shared-x_inv stationarity sum over t; production == BilevelJuMP == brute-force (WR-08)" tags =
    [:planning] setup = [BilevelInteriorCertFixture] begin
    using TSODSO: build_bilevel_kkt, solve_bilevel!
    using TSODSO, BilevelJuMP, JuMP, Ipopt

    # 29-REVIEW.md WR-08: every other production call uses T = 1, so the
    # `sum(mu_cap[t] for t in 1:T)` in statio_x and the per-t SOS1 loops were never
    # exercised. T = 2 fixture with DISTINCT tariffs, both periods delivering
    # (pi_tariff[t] - c_op[t] > c_inv/corridor_cap = 0.02 for both t):
    #   corridor_cap = 10, x_inv_max = 10, c_inv = 0.2, c_op = [0.5, 0.5],
    #   pi_tariff = [2.0, 1.5], q_op = [1, 1], c_y = 0.05, y_max = 5,
    #   v_d = [3, 3], d_max = 10. Margins a = pi_tariff - c_op = [1.5, 1.0].
    #
    # Hand derivation. Given x_inv, the follower picks z[t] = min(10*x_inv, a[t]/q_op[t]).
    # Its own x_inv FOC on the branch 1.0 <= 10x <= 1.5 (z[2] = 1.0 interior,
    # mu_cap[2] = 0) is 0.2 + 10*(-1.5 + 10x) = 0, so x_inv_F = 0.148 (the
    # both-capped branch's FOC root, 10x = 1.24, lies outside its own region 10x <= 1).
    # Follower response vs leader y:
    #   y <= 0.1:          x = y, z = [10y, 10y], mu_cap = a .- 10y,
    #                      rho_y = 10*sum(mu_cap) - 0.2 = 24.8 - 200y
    #   0.1 <= y <= 0.148: x = y, z = [10y, 1.0], mu_cap = [1.5 - 10y, 0],
    #                      rho_y = 14.8 - 100y
    #   y >= 0.148:        x = 0.148, z = [1.48, 1.0], rho_y = 0
    # Leader total = 0.05y + sum((pi_tariff - v_d) .* z) = 0.05y - z[1] - 1.5*z[2]:
    #   -24.95y, then -9.95y - 1.5, then 0.05y - 2.98, so the optimum is the kink
    #   y* = x_inv* = 0.148, z* = [1.48, 1.0], total* = -2.9726.
    # At y* statio_x needs 0.2 - 10*(mu_cap[1] + mu_cap[2]) = 0 with
    # mu_cap = [0.02, 0]. A wrong index (e.g. mu_cap[1] repeated: 0.2 - 10*2*0.02 != 0)
    # breaks it. The fixed-y production checks below pin each branch's rho_y.
    # Closed-form m_ub = 10 * max(1.5, 0, 10*2.5 - 0.2, 0.2) = 248.
    F = BilevelInteriorCertFixture
    feeder = F._interior_feeder()
    T = 2
    kw = (;
        T = T,
        agg_bus = 2,
        corridor_cap = 10.0,
        x_inv_max = 10.0,
        c_inv = 0.2,
        c_op = [0.5, 0.5],
        pi_tariff = [2.0, 1.5],
        q_op = [1.0, 1.0],
        c_y = 0.05,
        y_max = 5.0,
        v_d = [3.0, 3.0],
        d_max = 10.0,
    )

    # --- Production ---
    kkt = build_bilevel_kkt(feeder, LinDistFlow(); kw...)
    @test isapprox(kkt.m_ub, 248.0; rtol = 1e-12)
    prod = solve_bilevel!(kkt)
    atol_hand = 1e-6
    @test isapprox(prod.y, 0.148; atol = atol_hand)
    @test isapprox(prod.x_inv, 0.148; atol = atol_hand)
    @test isapprox(prod.z, [1.48, 1.0]; atol = atol_hand)
    @test isapprox(prod.d, [1.48, 1.0]; atol = atol_hand)
    @test isapprox(prod.total_cost, -2.9726; atol = atol_hand)
    @test isapprox(prod.mu_cap, [0.02, 0.0]; atol = atol_hand)

    # --- Production at FIXED leader decisions: one point per follower branch ---
    for (y_fixed, z_hand, rho_hand) in (
        (0.05, [0.5, 0.5], 24.8 - 200 * 0.05),   # both periods cap-bound: 14.8
        (0.12, [1.2, 1.0], 14.8 - 100 * 0.12),   # only period 1 cap-bound: 2.8
        (1.0, [1.48, 1.0], 0.0),                 # coupling slack
    )
        k = build_bilevel_kkt(feeder, LinDistFlow(); kw...)
        fix(k.y_inv, y_fixed; force = true)
        r = solve_bilevel!(k)
        @test isapprox(r.z, z_hand; atol = atol_hand)
        @test isapprox(r.rho_y, rho_hand; atol = atol_hand)
    end

    # --- Oracle #1: BilevelJuMP StrongDualityMode (Ipopt), T = 2 ---
    bjm = BilevelModel(Ipopt.Optimizer, mode = BilevelJuMP.StrongDualityMode())
    set_silent(bjm)
    @variable(Upper(bjm), 0 <= y_inv <= kw.y_max)
    @variable(Upper(bjm), 0.95^2 <= v2[1:T] <= 1.05^2)
    @variable(Upper(bjm), 0 <= d[1:T] <= kw.d_max)
    @variable(Lower(bjm), 0 <= x_inv <= kw.x_inv_max)
    @variable(Lower(bjm), z[1:T] >= 0)
    @constraint(Lower(bjm), cap[t = 1:T], z[t] <= kw.corridor_cap * x_inv)
    @constraint(Lower(bjm), coupling, x_inv <= y_inv)
    @objective(
        Lower(bjm),
        Min,
        kw.c_inv * x_inv + sum(
            (kw.c_op[t] - kw.pi_tariff[t]) * z[t] + 0.5 * kw.q_op[t] * z[t]^2 for t in 1:T
        )
    )
    @constraint(Upper(bjm), [t = 1:T], v2[t] == 1.0 - 2 * (1e-3 * z[t]))
    @constraint(Upper(bjm), [t = 1:T], d[t] == z[t])
    @objective(
        Upper(bjm),
        Min,
        kw.c_y * y_inv + sum(kw.pi_tariff[t] * z[t] - kw.v_d[t] * d[t] for t in 1:T)
    )
    optimize!(bjm)
    @test termination_status(bjm) == MOI.LOCALLY_SOLVED
    atol_bilevel = 1e-5
    @test isapprox(prod.y, value(y_inv); atol = atol_bilevel)
    @test isapprox(prod.z, value.(z); atol = atol_bilevel)
    @test isapprox(prod.total_cost, objective_value(bjm); atol = atol_bilevel)

    # --- Oracle #2: brute-force grid over y, follower QP (Clarabel) per point ---
    function follower_T2(y)
        m = Model(TSODSO.select_optimizer(TSODSO.QP()))
        @variable(m, 0 <= xi <= kw.x_inv_max)
        @variable(m, zz[1:T] >= 0)
        @constraint(m, [t = 1:T], kw.corridor_cap * xi - zz[t] >= 0)
        @constraint(m, xi <= y)
        @objective(
            m,
            Min,
            kw.c_inv * xi + sum(
                (kw.c_op[t] - kw.pi_tariff[t]) * zz[t] + 0.5 * kw.q_op[t] * zz[t]^2 for
                t in 1:T
            )
        )
        TSODSO.assert_solved!(m; dual = false)
        return value.(zz)
    end
    # A function, not a top-level loop: @testitem bodies run as top-level code, where
    # a for-loop assigning to an outer binding creates a new local (soft scope).
    function brute_force_T2(grid)
        best_y, best_total = NaN, Inf
        for y in grid
            zs = follower_T2(y)
            all(zs .<= kw.d_max + 1e-6) || continue   # network: d = z <= d_max
            total = kw.c_y * y + sum((kw.pi_tariff[t] - kw.v_d[t]) * zs[t] for t in 1:T)
            if total < best_total
                best_y, best_total = y, total
            end
        end
        return best_y, best_total
    end
    fine_grid = range(0.0, kw.y_max; length = 2001)
    best_y, best_total = brute_force_T2(fine_grid)
    # Same spacing argument as the T = 1 fixture: a fine-grid point lies in
    # [0.148, 0.148 + spacing] on the slope-c_y right branch, plus 5e-5 for
    # Clarabel's noise near the degenerate kink.
    @test abs(best_y - prod.y) <= step(fine_grid)
    @test isapprox(prod.total_cost, best_total; atol = kw.c_y * step(fine_grid) + 5e-5)
end
