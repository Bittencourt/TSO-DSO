# test/test_planning_certification_bilevel.jl
#
# Seam: BILEV-02 (Phase 29 plan 29-02) — certify the genuinely bilevel production
# solver `TSODSO.solve_bilevel!` (plan 29-01, `src/planning/bilevel_kkt.jl`) against
# TWO independent oracles on the IDENTICAL locked toy fixture
# `PlanningFixtures.bilevel_toy_fixture()`:
#
#   1. BilevelJuMP `StrongDualityMode` (Ipopt) — a hand-derived MPEC built DIRECTLY
#      from the fixture's own lossless 2-bus LinDistFlow algebra (NOT via
#      `contribute!`/`ModelContext` — see (b) below for why).
#   2. Brute-force grid enumeration over the leader's investment decision `y_inv`,
#      re-solving the follower's own tiny LP at each grid point via
#      `select_optimizer(LP())`.
#
# ...and asserts all three (production, BilevelJuMP, brute-force) AGREE with each
# other, while ALL THREE genuinely DIFFER from a fourth "joint" (single-planner,
# no-tariff) reference model by a MEASURED margin well above solver precision.
#
# (a) WHY THIS CLOSES THE 2026-09-28 QUALITY-AUDIT GAP: the existing Phase-11
# `BilevelCertFixture` (test_planning_certification.jl) cannot distinguish
# Stackelberg-via-Benders from joint optimization, because that fixture's
# Upper-level objective LITERALLY REPEATS the Lower level's own cost
# (`0.3*y_inv + 1.0*x_inv + 0.5*x_op - (2*z - 0.5*z^2)` — the follower's own cost
# terms appear verbatim in the leader's objective, so there is no wedge between
# what the follower optimizes and what the leader cares about). THIS fixture has a
# genuine wedge — the follower is paid an exogenous `pi_tariff` strictly BELOW its
# own true cost `c_op`, so its private optimum diverges from the network's own
# valuation `v_d` — this is exactly the BILEV-01/02 "genuinely bilevel" property
# the audit flagged as unclosed.
#
# (b) IMPLEMENTATION NOTE — the BilevelJuMP oracle below does NOT reuse
# `contribute!(LinDistFlow(), ...)`/`ModelContext` (those write plain
# `@variable(ctx.model, ...)` calls, but BilevelJuMP requires every variable be
# declared via `@variable(Upper(model), ...)`/`@variable(Lower(model), ...)`, a
# DIFFERENT container type incompatible with `ModelContext`'s plain `Model`). It
# hand-derives the SAME lossless 2-bus LinDistFlow algebra directly — justified
# because the fixture's single root->load branch, with NO current/loss terms in
# this formulation, makes the branch flow EXACTLY equal to both the root
# injection `z` and the load-bus draw `d`, so `d == z` is the COMPLETE, EXACT
# network-coupling equation for THIS SPECIFIC topology. This is a
# fixture-specific simplification, NOT a general BilevelJuMP/LinDistFlow
# integration pattern — a future contributor must not assume it generalizes to a
# multi-branch or lossy feeder.
#
# INFRA-02 exception (mirrors test_planning_certification.jl's own documented
# exception, Pitfall B3): `BilevelModel`'s own constructor contract requires a
# bare zero-arg solver constructor (`Ipopt.Optimizer`), not an
# `OptimizerWithAttributes` from the project's own solver-factory abstraction.
# This file — like test_planning_certification.jl — imports `HiGHS, Ipopt`
# directly, because BilevelJuMP/Ipopt are validation-oracle-only, test-only
# dependencies (never imported by `src/`).

@testmodule BilevelKKTCertFixture begin
    using BilevelJuMP, HiGHS, Ipopt, JuMP, TSODSO

    """
        build_toy_bilevel_jump(; corridor_cap, x_inv_max, c_inv, c_op, pi_tariff, c_y,
                               y_max, v_d, d_max, r, x, vmin2, vmax2)

    Certification oracle #1 (BILEV-02): a hand-derived MPEC for the IDENTICAL
    2-bus/T=1 toy fixture, built via `BilevelModel(Ipopt.Optimizer, mode =
    BilevelJuMP.StrongDualityMode())` — a DIFFERENT complementarity mode than
    production's SOS1-bridge MILP (29-RESEARCH.md Open Question 2 / T-29-05:
    `SOS1Mode`/`IndicatorMode` empirically fail on HiGHS with
    `BridgeRequiresFiniteDomainError`; `StrongDualityMode` is the proven-working
    mode from the Phase-11 fixture).

    Upper level (the DSO leader): `y_inv` (bounded `<= y_max`), `v2` (the squared
    voltage at bus 2, bounded `vmin2 <= v2 <= vmax2`), `d` (the served elastic
    demand, bounded `<= d_max`). Lower level (the TSO follower): `x_inv` (bounded
    `<= x_inv_max`), `z` (free `>= 0`). Lower objective
    `c_inv*x_inv + (c_op - pi_tariff)*z`. Lower constraints: `invest_op: z <=
    corridor_cap*x_inv`, `coupling_cap: x_inv <= y_inv` (the INVERTED coupling vs.
    the existing Phase-11 `FollowerLP` — leader bounds investment, follower is
    free on `z`). Upper constraints: `v2 == 1.0 - 2*(r*z + x*0)` (Q=0 identically —
    no reactive injection anywhere in this fixture) and `d == z` (the exact
    lossless network-coupling equation, see file header note (b)). Upper
    objective `c_y*y_inv + pi_tariff*z - v_d*d`.
    """
    function build_toy_bilevel_jump(;
        corridor_cap,
        x_inv_max,
        c_inv,
        c_op,
        pi_tariff,
        c_y,
        y_max,
        v_d,
        d_max,
        r,
        x,
        vmin2,
        vmax2,
    )
        model = BilevelModel(Ipopt.Optimizer, mode = BilevelJuMP.StrongDualityMode())
        @variable(Upper(model), 0 <= y_inv <= y_max)
        @variable(Upper(model), vmin2 <= v2 <= vmax2)
        @variable(Upper(model), 0 <= d <= d_max)
        @variable(Lower(model), 0 <= x_inv <= x_inv_max)
        @variable(Lower(model), z >= 0)
        @constraint(Lower(model), invest_op, z <= corridor_cap * x_inv)
        @constraint(Lower(model), coupling_cap, x_inv <= y_inv)
        @objective(Lower(model), Min, c_inv * x_inv + (c_op - pi_tariff) * z)
        @constraint(Upper(model), v2 == 1.0 - 2 * (r * z + x * 0))
        @constraint(Upper(model), d == z)
        @objective(Upper(model), Min, c_y * y_inv + pi_tariff * z - v_d * d)
        optimize!(model)
        return (; model, y_inv, z, x_inv, d, v2)
    end

    """
        brute_force_bilevel(; y_grid, corridor_cap, x_inv_max, c_inv, c_op, pi_tariff,
                            c_y, v_d, d_max)

    Certification oracle #2 (BILEV-02): brute-force enumeration over the leader's
    feasible investment grid `y_grid`. At each grid point `y`, builds a THROWAWAY
    `Model(select_optimizer(TSODSO.LP()))` with the follower's OWN LP (identical
    to production's follower cost/constraints, but with `y` as a FIXED upper
    bound rather than a leader decision variable), solves it, and tracks the
    grid point achieving the minimum LEADER total cost
    `c_y*y + pi_tariff*z_star - v_d*d_star`.

    Leader-level semantics match production (29-REVIEW.md WR-07): the lossless
    network forces `d = z`, so `d_star = z_star`. A follower response with
    `z_star > d_max`, or a bus-2 squared voltage `1 - 2*r*z_star` outside
    `[vmin2, vmax2]`, makes that `y` INFEASIBLE for the leader (`continue`). It is
    not counted as feasible-but-curtailed. Also skips a grid point whose follower LP
    does not solve and feasible (should not happen on this fixture — every `y >= 0`
    is follower-feasible with `x_inv=z=0`).

    Follower ties: this oracle takes whichever follower optimum HiGHS reports, while
    production is OPTIMISTIC (the leader picks among the follower's optimal set).
    The two agree only when the follower's response is unique. It is unique on this
    fixture: `pi_tariff < c_op` and `c_inv > 0` make `x_inv = z = 0` strictly optimal.
    """
    function brute_force_bilevel(;
        y_grid,
        corridor_cap,
        x_inv_max,
        c_inv,
        c_op,
        pi_tariff,
        c_y,
        v_d,
        d_max,
        r = 1e-3,
        vmin2 = 0.95^2,
        vmax2 = 1.05^2,
    )
        best = nothing
        for y in y_grid
            m = Model(TSODSO.select_optimizer(TSODSO.LP()))
            @variable(m, 0 <= x_inv <= x_inv_max)
            @variable(m, z >= 0)
            @constraint(m, z <= corridor_cap * x_inv)
            @constraint(m, x_inv <= y)
            @objective(m, Min, c_inv * x_inv + (c_op - pi_tariff) * z)
            optimize!(m)
            is_solved_and_feasible(m) || continue
            z_star = value(z)
            z_star <= d_max + 1e-7 || continue                  # network: d = z <= d_max
            vmin2 <= 1.0 - 2 * r * z_star <= vmax2 || continue  # leader voltage bounds
            d_star = z_star
            total = c_y * y + pi_tariff * z_star - v_d * d_star
            if best === nothing || total < best.total
                best = (; y, z = z_star, d = d_star, total)
            end
        end
        return best
    end

    """
        build_joint_reference(; feeder, agg_bus, corridor_cap, x_inv_max, c_inv, c_op,
                              c_y, y_max, v_d, d_max, T)

    The TRUE single-planner optimum — no tariff, no follower, no KKT/
    complementarity at all: a single LP (`select_optimizer(LP())`) reusing the
    SAME embedded LinDistFlow network as production (`contribute!(LinDistFlow(),
    ctx, feeder; T)`, since this is a plain `Model`/`ModelContext`, not a
    `BilevelModel`), directly minimizing
    `c_y*y_inv + c_inv*x_inv + sum(c_op[t]*z[t] - v_d[t]*d[t] for t in 1:T)`
    subject to `x_inv <= y_inv`, `z[t] <= corridor_cap*x_inv`, and the network
    balance closed exactly like `solve_bilevel!` (`balance_p`/`balance_q` == 0).
    This is the reference this fixture's bilevel answer must genuinely DIFFER
    from (BILEV-02).
    """
    function build_joint_reference(;
        feeder,
        agg_bus,
        corridor_cap,
        x_inv_max,
        c_inv,
        c_op,
        c_y,
        y_max,
        v_d,
        d_max,
        T,
    )
        model = Model(TSODSO.select_optimizer(TSODSO.LP()))
        ctx = TSODSO.ModelContext(model)
        TSODSO.contribute!(TSODSO.LinDistFlow(), ctx, feeder; T = T)
        Np = length(feeder.buses)

        @variable(model, 0 <= y_inv <= y_max)
        @variable(model, 0 <= x_inv <= x_inv_max)
        @variable(model, z[t = 1:T] >= 0)
        @variable(model, 0 <= d[t = 1:T] <= d_max)
        @constraint(model, x_inv <= y_inv)
        @constraint(model, cap[t = 1:T], z[t] <= corridor_cap * x_inv)

        for t in 1:T
            TSODSO.add_to_residual!(ctx, :Rp, feeder.root, t, z[t])
            TSODSO.add_to_residual!(ctx, :Rp, agg_bus, t, -d[t])
        end

        size(ctx.residuals[:Rp]) == (Np, T) || error(
            "residual :Rp is $(size(ctx.residuals[:Rp])), expected ($Np, $T) — an index escaped the feeder",
        )
        @constraint(model, balance_p[j = 1:Np, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
        if haskey(ctx.residuals, :Rq)
            size(ctx.residuals[:Rq]) == (Np, T) || error(
                "residual :Rq is $(size(ctx.residuals[:Rq])), expected ($Np, $T) — an index escaped the feeder",
            )
            @constraint(model, balance_q[j = 1:Np, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
        end

        @objective(
            model,
            Min,
            c_y * y_inv + c_inv * x_inv + sum(c_op[t] * z[t] - v_d[t] * d[t] for t in 1:T)
        )
        TSODSO.assert_solved!(model; dual = false)

        return (;
            y = value(y_inv),
            x_inv = value(x_inv),
            z = value.(z),
            d = value.(d),
            total = objective_value(model),
        )
    end
end

@testitem "bilevel certification: production == BilevelJuMP StrongDualityMode == brute-force grid enumeration; all three != joint (BILEV-02)" tags =
    [:planning] setup = [PlanningFixtures, BilevelKKTCertFixture] begin
    using TSODSO, BilevelJuMP, JuMP

    f = PlanningFixtures.bilevel_toy_fixture()

    # --- Production (TSODSO.solve_bilevel!, plan 29-01's single-level KKT-MILP) ---
    kkt = build_bilevel_kkt(
        f.feeder,
        LinDistFlow();
        T = f.T,
        agg_bus = f.agg_bus,
        corridor_cap = f.corridor_cap,
        x_inv_max = f.x_inv_max,
        c_inv = f.c_inv,
        c_op = f.c_op,
        pi_tariff = f.pi_tariff,
        q_op = f.q_op,
        c_y = f.c_y,
        y_max = f.y_max,
        v_d = f.v_d,
        d_max = f.d_max,
    )
    prod = solve_bilevel!(kkt)

    # --- Oracle #1: BilevelJuMP StrongDualityMode (Ipopt) ---
    bj = BilevelKKTCertFixture.build_toy_bilevel_jump(;
        corridor_cap = f.corridor_cap,
        x_inv_max = f.x_inv_max,
        c_inv = f.c_inv,
        c_op = f.c_op[1],
        pi_tariff = f.pi_tariff[1],
        c_y = f.c_y,
        y_max = f.y_max,
        v_d = f.v_d[1],
        d_max = f.d_max,
        r = 1e-3,
        x = 1e-3,
        vmin2 = 0.95^2,
        vmax2 = 1.05^2,
    )
    @test termination_status(bj.model) == MOI.LOCALLY_SOLVED

    # --- Oracle #2: brute-force grid enumeration ---
    # 201 points over [0, y_max] is sufficient to resolve the true optimum here:
    # with q_op=0 the follower's response is a STEP function of y_inv (bang-bang,
    # not a smooth curve), and this fixture's true optimum sits exactly AT the
    # grid's own y=0.0 endpoint (measured this session: every y in the grid gives
    # the SAME follower response x_inv=z=0, since pi_tariff < c_op dominates for
    # every y >= 0) — so ANY grid including y=0.0 finds the true minimum, not just
    # a fine one.
    bf = BilevelKKTCertFixture.brute_force_bilevel(;
        y_grid = range(0.0, f.y_max; length = 201),
        corridor_cap = f.corridor_cap,
        x_inv_max = f.x_inv_max,
        c_inv = f.c_inv,
        c_op = f.c_op[1],
        pi_tariff = f.pi_tariff[1],
        c_y = f.c_y,
        v_d = f.v_d[1],
        d_max = f.d_max,
    )

    # --- Reference: joint (single-planner, no-tariff) optimum ---
    jt = BilevelKKTCertFixture.build_joint_reference(;
        feeder = f.feeder,
        agg_bus = f.agg_bus,
        corridor_cap = f.corridor_cap,
        x_inv_max = f.x_inv_max,
        c_inv = f.c_inv,
        c_op = f.c_op,
        c_y = f.c_y,
        y_max = f.y_max,
        v_d = f.v_d,
        d_max = f.d_max,
        T = f.T,
    )

    # --- Production reproduces the named golden corner (PlanningFixtures.BILEV_*_HAND) ---
    @test isapprox(prod.y, PlanningFixtures.BILEV_Y_HAND; atol = 1e-9)
    @test isapprox(prod.z[1], PlanningFixtures.BILEV_Z_HAND; atol = 1e-9)
    @test isapprox(prod.total_cost, PlanningFixtures.BILEV_TOTAL_HAND; atol = 1e-9)

    # --- Joint reference reproduces the named golden optimum (PlanningFixtures.JOINT_*_HAND) ---
    @test isapprox(jt.y, PlanningFixtures.JOINT_Y_HAND; atol = 1e-9)
    @test isapprox(jt.x_inv, PlanningFixtures.JOINT_XINV_HAND; atol = 1e-9)
    @test isapprox(jt.z[1], PlanningFixtures.JOINT_Z_HAND; atol = 1e-9)
    @test isapprox(jt.total, PlanningFixtures.JOINT_TOTAL_HAND; atol = 1e-9)

    # --- Three-way agreement: production == BilevelJuMP == brute-force ---
    # atol=1e-3 MEASURED this session: BilevelJuMP StrongDualityMode (Ipopt, an NLP
    # strong-duality reformulation) converges to this fixture's y*=z*=0.0 corner
    # with a residual of ~1e-7 (Ipopt's own interior-point noise floor approaching
    # a corner solution, not a genuine disagreement) — 1e-3 sits 4 orders of
    # magnitude above that observed residual, matching this project's existing
    # BilevelCertFixture convention (test_planning_certification.jl).
    atol_bilevel = 1e-3
    @test isapprox(prod.y, value(bj.y_inv); atol = atol_bilevel)
    @test isapprox(prod.z[1], value(bj.z); atol = atol_bilevel)
    @test isapprox(prod.total_cost, objective_value(bj.model); atol = atol_bilevel)

    # atol=1e-6: brute-force re-solves the SAME follower LP via the SAME HiGHS
    # backend as production (via `select_optimizer(LP())`) — measured this
    # session as BIT-IDENTICAL agreement (residual exactly 0.0) at this fixture's
    # corner, so 1e-6 is already extremely conservative.
    atol_bruteforce = 1e-6
    @test isapprox(prod.y, bf.y; atol = atol_bruteforce)
    @test isapprox(prod.z[1], bf.z; atol = atol_bruteforce)
    @test isapprox(prod.total_cost, bf.total; atol = atol_bruteforce)

    # --- Genuine bilevel != joint divergence (T-29-04 mitigation) ---
    # PlanningFixtures.BILEV_GAP_FLOOR is derived from a MEASURED solver-precision
    # quantity: 10x the production MILP's own `select_optimizer(MILP())`
    # mip_feasibility_tolerance (1e-9, memory highs-exactness-defaults) — NEVER as
    # a fraction of the observed ~3.9/~2.0 gaps themselves (29-RESEARCH.md Pitfall
    # 6). See fixtures_planning.jl's own derivation comment for the full argument.
    @test abs(prod.total_cost - jt.total) > PlanningFixtures.BILEV_GAP_FLOOR
    @test abs(prod.z[1] - jt.z[1]) > PlanningFixtures.BILEV_GAP_FLOOR
end
